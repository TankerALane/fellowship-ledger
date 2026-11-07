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
-- Failed Questie queries this session. One quest Questie cannot answer (say, a WoW
-- Forever quest its data lacks) gets no chain; only this many failures turn the
-- Questie lookup off for the session.
QuestChains.MAX_QUESTIE_ERRORS = 25
QuestChains.questieErrors = 0
QuestChains.questieLastError = nil -- for /fl verify

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
        QuestChains.questieErrors = QuestChains.questieErrors + 1
        QuestChains.questieLastError = string.format("quest %s %s: %s", tostring(id), tostring(field), tostring(value))
        if QuestChains.questieErrors >= QuestChains.MAX_QUESTIE_ERRORS then questieBroken = true end
        return nil
    end
    return value
end

-- Quest IDs of each chain, by chain key (static game data, so kept for the session).
local chainIds = {}

local function questieWalk(questID)
    return Logic.Walk(questID,
        function(id)
            local pre = questieQuery(id, "preQuestSingle")
            return type(pre) == "table" and pre[1] or nil
        end,
        function(id) return questieQuery(id, "nextQuestInChain") end)
end

local function fromQuestie(questID)
    if QuestChains.QuestieState() ~= "ready" then return nil end
    local chain = questieWalk(questID)
    if questieBroken or #chain < 2 then return nil end
    chainIds["q:" .. chain[1]] = chain
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
    chainIds["g:" .. tostring(T.Plain(line.questLineID))] = quests
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
    local chains, ids = {}, {}
    for _, e in ipairs((QuestChains.ForLog())) do
        if e.questID then ids[#ids + 1] = e.questID end
        if e.key and e.step then
            chains[e.key] = { name = e.chainName, step = e.step, total = e.total, firstQuestID = e.firstQuestID,
                firstName = e.firstName, startZone = e.startZone, source = e.source }
        end
    end
    table.sort(ids)
    char.chains = chains
    -- The quests in the log, shared with Quests so friends can work out the chains with
    -- their own Questie when this character has none (D-087).
    char.logQuests = ids
    return chains
end

-- A friend's character's chains (D-087): the chains it sent, plus chains worked out
-- here from the quest IDs in its log (sent from 1.2.1), so a friend without Questie
-- still shows up when you have it. Sent chains win for the same key. Cached per
-- character until its log or our Questie state changes.
local friendCache = setmetatable({}, { __mode = "k" })
function QuestChains.FriendChains(c)
    if type(c) ~= "table" then return {} end
    if type(c.logQuests) ~= "table" then return c.chains or {} end
    local sig = table.concat(c.logQuests, ",") .. "|" .. QuestChains.QuestieState()
    local cached = friendCache[c]
    if cached and cached.sig == sig and cached.sent == c.chains then return cached.chains end
    local out = {}
    for _, id in ipairs(c.logQuests) do
        local e = QuestChains.Lookup(id)
        if e and e.key and e.step then
            local have = out[e.key]
            if not have or e.step > (have.step or 0) then
                out[e.key] = { name = e.chainName, step = e.step, total = e.total, firstQuestID = e.firstQuestID,
                    firstName = e.firstName, startZone = e.startZone, source = e.source, derived = true }
            end
        end
    end
    for key, ch in pairs(c.chains or {}) do out[key] = ch end
    friendCache[c] = { sig = sig, sent = c.chains, chains = out }
    return out
end

-- Has this character started (or finished) the chain that begins with questID?
function QuestChains.HaveStarted(firstQuestID)
    if not firstQuestID then return false end
    local ok, done = ns.Compat.Try("C_QuestLog.IsQuestFlaggedCompleted", firstQuestID)
    return ok and done == true
end

-- Details for the drop-downs (D-078) ------------------------------------------
-- Questie's other tables, looked up the same guarded way as quests.
local function questieOther(kind, id, field)
    local fn = questieDB and questieDB["Query" .. kind .. "Single"]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, id, field)
    if ok then return value end
    return nil
end

-- Where an NPC or object stands: Questie's spawns are { [zoneID] = { { x, y }, ... } }
-- with x and y in map percent (-1 inside instances). The zone with the most spawn
-- points wins; its first point gives the coordinates. Returns zone name, x, y.
local function zoneOf(spawns)
    if type(spawns) ~= "table" then return nil end
    local best, most = nil, 0
    for zoneID, coords in pairs(spawns) do
        local n = type(coords) == "table" and #coords or 0
        if type(zoneID) == "number" and (n > most or (n == most and best and zoneID < best) or not best) then best, most = zoneID, n end
    end
    if not best then return nil end
    local ok, name = ns.Compat.Try("C_Map.GetAreaInfo", best)
    name = ok and type(T.Plain(name)) == "string" and name or nil
    local pt = type(spawns[best]) == "table" and spawns[best][1]
    local x, y = type(pt) == "table" and pt[1], type(pt) == "table" and pt[2]
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or y < 0 then x, y = nil, nil end
    return name, x, y
end

local function spot(kind, name, spawns)
    local zone, x, y = zoneOf(spawns)
    return { kind = kind, name = name, zone = zone, x = x, y = y }
end

-- startedBy / finishedBy: { npcIDs, objectIDs, itemIDs }. Returns { kind, name, zone } or nil.
local function placeOf(by)
    if type(by) ~= "table" then return nil end
    local npc = type(by[1]) == "table" and by[1][1]
    if npc then
        local name = questieOther("NPC", npc, "name")
        if type(name) == "string" then return spot("npc", name, questieOther("NPC", npc, "spawns")) end
    end
    local obj = type(by[2]) == "table" and by[2][1]
    if obj then
        local name = questieOther("Object", obj, "name")
        if type(name) == "string" then return spot("object", name, questieOther("Object", obj, "spawns")) end
    end
    local item = type(by[3]) == "table" and by[3][1]
    if item then
        local name = questieOther("Item", item, "name")
        if type(name) == "string" then return { kind = "item", name = name } end
    end
    return nil
end

local infoCache = {}
-- One quest: { name, level, req, start, finish, pre }. From Questie when it is
-- ready (kept for the session), else just the game's title.
function QuestChains.QuestInfo(id)
    if infoCache[id] then return infoCache[id] end
    local info = {}
    if QuestChains.QuestieState() == "ready" then
        local name = questieQuery(id, "name")
        info.name = type(name) == "string" and name or nil
        local level, req = questieQuery(id, "questLevel"), questieQuery(id, "requiredLevel")
        info.level = type(level) == "number" and level or nil
        info.req = type(req) == "number" and req or nil
        info.start = placeOf(questieQuery(id, "startedBy"))
        info.finish = placeOf(questieQuery(id, "finishedBy"))
        local pre = {}
        for _, field in ipairs({ "preQuestGroup", "preQuestSingle" }) do
            local list = questieQuery(id, field)
            if type(list) == "table" then for _, p in ipairs(list) do if type(p) == "number" then pre[#pre + 1] = p end end end
        end
        info.pre = pre
        -- Questie's zoneOrSort: a positive value is the zone (area) the quest belongs to.
        local area = questieQuery(id, "zoneOrSort")
        if type(area) == "number" and area > 0 then
            local okA, zname = ns.Compat.Try("C_Map.GetAreaInfo", area)
            info.zone = okA and type(T.Plain(zname)) == "string" and zname or nil
        end
        if not questieBroken and info.name then infoCache[id] = info end
    end
    if not info.name then
        local ok, title = ns.Compat.Try("C_QuestLog.GetTitleForQuestID", id)
        info.name = ok and type(T.Plain(title)) == "string" and title or nil
    end
    return info
end

-- The quest IDs of the chain `key` ("q:<first quest>" from Questie, "g:<quest line>"
-- from the game). Friends' chains you have not looked up yet are worked out here.
function QuestChains.ChainIDs(key)
    if chainIds[key] then return chainIds[key] end
    local kind, id = tostring(key):match("^(%a):(%d+)$")
    id = tonumber(id)
    if not id then return nil end
    local ids
    if kind == "q" and QuestChains.QuestieState() == "ready" then
        ids = questieWalk(id)
        if questieBroken or #ids < 2 then ids = nil end
    elseif kind == "g" then
        local ok, quests = ns.Compat.Try("C_QuestLine.GetQuestLineQuests", id)
        if ok and type(quests) == "table" and #quests > 0 then ids = quests end
    end
    chainIds[key] = ids
    return ids
end

-- Details of the chain `key` for the view. logSet: { [questID] = true } for your log.
function QuestChains.Details(key, anchor, logSet)
    local ids = QuestChains.ChainIDs(key)
    if not ids then return nil end
    return Logic.Details(ids, QuestChains.QuestInfo, function(id)
        if logSet and logSet[id] then return "log" end
        if QuestChains.HaveStarted(id) then return "done" end
        return nil
    end, anchor)
end

-- Every quest this character has ever completed (D-081): the game's list, from
-- C_QuestLog.GetAllCompletedQuestIDs (a list) or GetQuestsCompleted (a set).
-- Returns a sorted list of IDs, or nil when neither exists.
function QuestChains.CompletedIDs()
    local ok, list = ns.Compat.Try("C_QuestLog.GetAllCompletedQuestIDs")
    local ids = {}
    if ok and type(list) == "table" then
        for _, id in ipairs(list) do if type(T.Plain(id)) == "number" then ids[#ids + 1] = id end end
    else
        local okS, set = ns.Compat.Try("GetQuestsCompleted")
        if not (okS and type(set) == "table") then return nil end
        for id, done in pairs(set) do if type(id) == "number" and done then ids[#ids + 1] = id end end
    end
    table.sort(ids)
    return ids
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
