-- Trackers/QuestChains.lua
-- "You are on step X of Y" for the quests in your log.
-- 1. Game data first: C_QuestLine.GetQuestLineInfo(questID) and
--    C_QuestLine.GetQuestLineQuests(questLineID) (retail: 3 of 14 quests had a line).
-- 2. Then Questie, if loaded and ready: its database's previous/next quest links
--    (QueryQuestSingle "preQuestSingle" / "nextQuestInChain", read from Questie 12.5.1's
--    own source). This is Questie's internal API, so it is fully guarded: any error
--    turns the Questie lookup off for the session and the UI says so.
-- 3. Otherwise the UI says plainly that neither source knows.

local _, ns = ...
local T = ns.Trackers
local Logic = ns.QuestChainLogic

local QuestChains = {}
ns.QuestChains = QuestChains

local questieDB
local questieBroken = false

-- "missing" | "loading" | "ready" | "broken"
function QuestChains.QuestieState()
    local okLoaded, loaded = ns.Compat.Try("C_AddOns.IsAddOnLoaded", "Questie")
    if not (okLoaded and loaded) then return "missing" end
    if questieBroken then return "broken" end
    local Questie = _G.Questie
    if not (type(Questie) == "table" and type(Questie.API) == "table" and Questie.API.isReady) then return "loading" end
    if not questieDB then
        local loader = _G.QuestieLoader
        local ok, db = pcall(function() return loader:ImportModule("QuestieDB") end)
        if ok and type(db) == "table" and type(db.QueryQuestSingle) == "function" then
            questieDB = db
        else
            questieBroken = true
            return "broken"
        end
    end
    return "ready"
end

local function questieQuery(id, field)
    local ok, value = pcall(questieDB.QueryQuestSingle, id, field)
    if not ok then
        questieBroken = true
        return nil
    end
    return value
end

local function fromQuestie(questID)
    if QuestChains.QuestieState() ~= "ready" then return nil end
    local chain = Logic.Walk(questID,
        function(id)
            local pre = questieQuery(id, "preQuestSingle")
            return type(pre) == "table" and pre[1] or nil
        end,
        function(id) return questieQuery(id, "nextQuestInChain") end)
    if questieBroken or #chain < 2 then return nil end
    local step, total = Logic.StepOf(chain, questID)
    local firstName = questieQuery(chain[1], "name")
    return { step = step, total = total, chainName = type(firstName) == "string" and firstName or nil, source = "questie" }
end

local function fromGame(questID)
    local ok, line = ns.Compat.Call("questChains", "C_QuestLine.GetQuestLineInfo", questID)
    if not ok or type(line) ~= "table" or not line.questLineID then return nil end
    local okQ, quests = ns.Compat.Call("questChains", "C_QuestLine.GetQuestLineQuests", line.questLineID)
    if not okQ or type(quests) ~= "table" or #quests == 0 then return nil end
    local step, total = Logic.StepOf(quests, questID)
    if not step then return nil end
    return { step = step, total = total, chainName = T.Plain(line.questLineName), source = "game" }
end

function QuestChains.Lookup(questID)
    return fromGame(questID) or fromQuestie(questID)
end

-- Every quest in the log with its chain info. Returns entries, questieState.
function QuestChains.ForLog()
    local out = {}
    local okN, n = ns.Compat.Try("C_QuestLog.GetNumQuestLogEntries")
    for i = 1, okN and n or 0 do
        local ok, info = ns.Compat.Try("C_QuestLog.GetInfo", i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local e = QuestChains.Lookup(info.questID) or {}
            e.title = info.title or ("Quest " .. info.questID)
            e.questID = info.questID
            out[#out + 1] = e
        end
    end
    return out, QuestChains.QuestieState()
end
