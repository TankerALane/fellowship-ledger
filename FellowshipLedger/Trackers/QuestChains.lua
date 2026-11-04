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
    local first = chain[1]
    local firstName = questieQuery(first, "name")
    firstName = type(firstName) == "string" and firstName or nil
    -- Questie's zoneOrSort: a positive value is the zone (area) the quest belongs to.
    local zone
    local area = questieQuery(first, "zoneOrSort")
    if type(area) == "number" and area > 0 and ns.Compat.Has("C_Map.GetAreaInfo") then
        local okA, name = pcall(C_Map.GetAreaInfo, area)
        zone = okA and T.Plain(name) or nil
    end
    return { step = step, total = total, chainName = firstName, source = "questie", key = "q:" .. first,
        firstQuestID = first, firstName = firstName, startZone = zone }
end

local function fromGame(questID)
    local ok, line = ns.Compat.Call("questChains", "C_QuestLine.GetQuestLineInfo", questID)
    if not ok or type(line) ~= "table" or not line.questLineID then return nil end
    local okQ, quests = ns.Compat.Call("questChains", "C_QuestLine.GetQuestLineQuests", line.questLineID)
    if not okQ or type(quests) ~= "table" or #quests == 0 then return nil end
    local step, total = Logic.StepOf(quests, questID)
    if not step then return nil end
    local first = quests[1]
    local okT, firstName = ns.Compat.Try("C_QuestLog.GetTitleForQuestID", first)
    local zone
    local okF, firstLine = ns.Compat.Try("C_QuestLine.GetQuestLineInfo", first)
    if okF and type(firstLine) == "table" then
        firstName = firstName or T.Plain(firstLine.questName)
        local mapID = T.Plain(firstLine.startMapID)
        if mapID then
            local okM, info = ns.Compat.Try("C_Map.GetMapInfo", mapID)
            zone = okM and type(info) == "table" and T.Plain(info.name) or nil
        end
    end
    return { step = step, total = total, chainName = T.Plain(line.questLineName), source = "game",
        key = "g:" .. tostring(T.Plain(line.questLineID)), firstQuestID = first,
        firstName = T.Plain(firstName), startZone = zone }
end

function QuestChains.Lookup(questID)
    return fromGame(questID) or fromQuestie(questID)
end

-- Save the chains this character is on (for sharing and for when it is offline).
function QuestChains.Snapshot()
    local char = ns.Store.char
    if not char then return end
    local chains = {}
    for _, e in ipairs((QuestChains.ForLog())) do
        if e.key and e.step then
            chains[e.key] = { name = e.chainName, step = e.step, total = e.total, firstQuestID = e.firstQuestID,
                firstName = e.firstName, startZone = e.startZone, source = e.source }
        end
    end
    char.chains = chains
    return chains
end

-- Has this character started (or finished) the chain that begins with questID?
function QuestChains.HaveStarted(firstQuestID)
    if not firstQuestID then return false end
    local ok, done = ns.Compat.Try("C_QuestLog.IsQuestFlaggedCompleted", firstQuestID)
    return ok and done == true
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
