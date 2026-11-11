-- Trackers/Quests.lua
-- Turn-in log (30 days) and daily totals (90 days, via Store.Count).
-- QUEST_TURNED_IN (questID, xpReward, moneyReward) is documented but not yet seen
-- firing in a probe; it is on the in-game checklist.

local _, ns = ...
local T = ns.Trackers
local Store, Days, Character = ns.Store, ns.Days, ns.Character

local titles = {} -- questID -> title, filled from the quest log while quests are in it

local function scanLog()
    local ok, n = ns.Compat.Call("quests", "C_QuestLog.GetNumQuestLogEntries")
    if not ok then return end
    for i = 1, n or 0 do
        local okInfo, info = ns.Compat.Call("quests", "C_QuestLog.GetInfo", i)
        if okInfo and type(info) == "table" and not info.isHeader and info.questID and info.title then
            titles[info.questID] = info.title
            -- Its rewards, for the quest details (D-100).
            if ns.QuestRewards then pcall(ns.QuestRewards.FromLog, info.questID) end
        end
    end
end

local Quests = T.Define({ id = "quests" })

local function snapshot()
    if ns.QuestChains then pcall(ns.QuestChains.Snapshot) end
end

function Quests:OnLogin()
    scanLog()
    snapshot()
end

local scanPending = false
Quests.events.QUEST_LOG_UPDATE = function()
    if scanPending then return end
    scanPending = true
    ns.Events.After(2, function()
        scanPending = false
        scanLog()
        snapshot()
    end)
end

Quests.events.QUEST_ACCEPTED = function()
    Store.Touch()
    Store.Count("questsAccepted")
end

Quests.events.QUEST_TURNED_IN = function(_, questID, xpReward, moneyReward)
    questID = T.Plain(questID)
    if type(questID) ~= "number" then return end
    if T.Dedupe("quest:" .. questID, 5) then return end
    Store.Touch()
    local title = titles[questID]
    if not title then
        local ok, t = ns.Compat.Call("quests", "C_QuestLog.GetTitleForQuestID", questID)
        title = ok and t or nil
    end
    local char = Store.char
    char.questLog[#char.questLog + 1] = {
        id = questID,
        title = title,
        at = Store.Now(),
        xp = T.Plain(xpReward),
        money = T.Plain(moneyReward),
        zone = (Store.Zone()), -- where you turned it in (D-081)
    }
    Days.PruneList(char.questLog, "at", Store.Now(), Character.QUEST_LOG_SECONDS)
    Store.Count("quests")
    T.XPMark("quest", T.Plain(xpReward))
end
