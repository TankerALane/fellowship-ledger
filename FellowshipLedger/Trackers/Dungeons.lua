-- Trackers/Dungeons.lua
-- Dungeon runs: entered and completed are counted separately. A run is completed
-- when the dungeon's last boss (from the encounter journal) dies, or when the
-- dungeon finder reports completion. Party make-up is stored as class and role only.
-- ENCOUNTER_END works on Forever (2026-11-05); the journal lookup by map did not on the
-- first run there, so it is retried and falls back to the dungeon's name (D-085).

local _, ns = ...
local T = ns.Trackers
local Store, Days, Character = ns.Store, ns.Days, ns.Character

local RESUME_SECONDS = 1800 -- re-entering the same instance within this continues the run

local function partySnapshot()
    local party = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local class = T.Plain(select(2, UnitClass(unit)))
            local okRole, role = ns.Compat.Call("dungeons", "UnitGroupRolesAssigned", unit)
            local okPlayer, isPlayer = ns.Compat.Call("dungeons", "UnitIsPlayer", unit)
            -- A name is stored ONLY if that player runs the ledger and sent us their
            -- "share my name in dungeon records" opt-in (Comms/Sync.lua NAME note).
            local name = T.Plain(UnitName(unit))
            party[#party + 1] = {
                class = class,
                role = okRole and T.Plain(role) or nil,
                npc = (okPlayer and T.Plain(isPlayer) == false) or nil, -- follower-dungeon companion
                name = (ns.Sync and ns.Sync.IsOptedIn(name)) and name or nil,
            }
        end
    end
    return party
end

-- Journal lookup of the final boss's encounter ID (D-085). First by the map you are
-- on; if that gives nothing (Forever's first Ragefire Chasm run, 2026-11-05), by the
-- dungeon's name in the journal's instance lists, which also works after the run.
-- Returns lastEncounterID, bossCount, how ("map" | "name") or nil.
-- The journal's bosses for an instance: { { name, journalID, encounterID } } in order.
-- The encounter ID (7th value) is what ENCOUNTER_END reports; some clients leave it
-- empty, so the boss's name is kept too and either can match (D-085).
function ns.DungeonJournalBosses(journalID)
    ns.Compat.Try("EJ_SelectInstance", journalID)
    local list = {}
    for i = 1, 40 do
        local ok, name, _, journalEncounterID, _, _, _, dungeonEncounterID = ns.Compat.Try("EJ_GetEncounterInfoByIndex", i, journalID)
        if not (ok and name) then ok, name, _, journalEncounterID, _, _, _, dungeonEncounterID = ns.Compat.Try("EJ_GetEncounterInfoByIndex", i) end
        if not (ok and T.Plain(name)) then break end
        list[#list + 1] = { name = T.Plain(name), journalID = T.Plain(journalEncounterID), encounterID = T.Plain(dungeonEncounterID) }
    end
    return list
end

local function journalBosses(journalID)
    local list = ns.DungeonJournalBosses(journalID)
    local last = list[#list]
    if not last then return nil end
    return last.encounterID or false, #list, last.name
end

-- Loose match: the journal's name and the instance name may differ in case or by a
-- prefix or suffix, so either containing the other counts.
local function sameDungeon(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then return false end
    a, b = a:lower(), b:lower()
    return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

-- Every instance in the journal: { { journalID, name } } (for matching and /fl verify).
function ns.DungeonJournalList()
    local out = {}
    local okT, tiers = ns.Compat.Try("EJ_GetNumTiers")
    for tier = 1, (okT and type(tiers) == "number" and tiers > 0) and tiers or 1 do
        if okT then ns.Compat.Try("EJ_SelectTier", tier) end
        for _, raid in ipairs({ false, true }) do
            for i = 1, 200 do
                local ok, journalID, iname = ns.Compat.Try("EJ_GetInstanceByIndex", i, raid)
                if not ok or not journalID then break end
                out[#out + 1] = { journalID = T.Plain(journalID), name = T.Plain(iname) }
            end
        end
    end
    return out
end

function ns.DungeonJournalByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    for _, e in ipairs(ns.DungeonJournalList()) do
        if sameDungeon(e.name, name) then return e.journalID end
    end
    return nil
end

-- Returns lastEncounterID (false when the journal has no ID for it), bossCount, how,
-- lastBossName; or nil when the journal does not know the dungeon.
local function findLastBoss(dungeonName)
    local ejFrame = _G.EncounterJournal
    if ejFrame and ejFrame.IsShown and ejFrame:IsShown() then return nil end -- don't disturb an open journal
    local okMap, mapID = ns.Compat.Try("C_Map.GetBestMapForUnit", "player")
    if okMap and mapID then
        local okJ, journalID = ns.Compat.Try("EJ_GetInstanceForMap", mapID)
        if okJ and journalID and journalID ~= 0 then
            local last, count, lastName = journalBosses(journalID)
            if last ~= nil then return last, count, "map", lastName end
        end
    end
    local journalID = ns.DungeonJournalByName(dungeonName)
    if journalID then
        local last, count, lastName = journalBosses(journalID)
        if last ~= nil then return last, count, "name", lastName end
    end
    return nil
end

-- Is this kill the run's last boss? By encounter ID, or by name when the journal had no ID.
-- Is this kill the run's last boss? From the journal (by encounter ID, or by name when
-- it had no ID), or from our own final-boss list (Core/DungeonBosses.lua, D-086), which
-- is what WoW Forever needs: its journal is empty.
local function isLastBoss(run, encounterID, encounterName)
    if run.lastBossID and encounterID == run.lastBossID then return true end
    if run.lastBossName ~= nil and type(encounterName) == "string" and encounterName:lower() == run.lastBossName:lower() then
        return true
    end
    return ns.DungeonBosses.IsFinal(run.name, encounterName)
end
ns.DungeonFindLastBoss = findLastBoss -- for /fl verify

-- Retry while the run has no boss list (the map can be unknown right at loading).
local RETRIES = 10
local function ensureLastBoss(run)
    if not run or run.lastBossID or run.lastBossName or (run.lookups or 0) >= RETRIES then return end
    run.lookups = (run.lookups or 0) + 1
    local last, count, how, lastName = findLastBoss(run.name)
    if last ~= nil then run.lastBossID, run.bossCount, run.lookup, run.lastBossName = last or nil, count, how, lastName end
end

-- A run counts once it lasts 5 minutes or a boss dies (Austin, 2026-11-06): walking in
-- and straight back out is not a run. Until then it is "pending": not counted, and
-- dropped if it ends that way. Runs saved before this have no pending flag.
local MIN_RUN_SECONDS = 300
local function qualifies(run, t)
    return #(run.bosses or {}) > 0 or (t - (run.entered or t)) >= MIN_RUN_SECONDS
end
local function countIfReady(run, t)
    if run and run.pending and qualifies(run, t) then
        run.pending = nil
        Store.Count("dungeonsEntered")
    end
end

local function closeRun(char)
    local run = char.currentRun
    if not run then return end
    run.left = run.lastSeen or Store.Now()
    run.duration = run.left - run.entered
    run.pull, run.outside, run.backAt, run.seenBefore = nil, nil, nil, nil
    countIfReady(run, run.left)
    if run.pending then -- in and out: not a run
        char.currentRun = nil
        return
    end
    char.dungeons[#char.dungeons + 1] = run
    char.currentRun = nil
    Days.PruneList(char.dungeons, "entered", Store.Now(), Character.LIST_KEEP_SECONDS)
end

local function startRun(char, t, name, instanceID, difficultyID)
    local lastBoss, bossCount, how, lastName = findLastBoss(name)
    char.currentRun = {
        name = name,
        instanceID = instanceID,
        difficultyID = difficultyID,
        entered = t,
        lastSeen = t,
        deaths = 0,
        bosses = {},
        party = partySnapshot(),
        lastBossID = lastBoss or nil,
        lastBossName = lastName,
        bossCount = bossCount,
        lookup = how,
        lookups = 1,
        pending = true, -- counted as entered after 5 minutes or a boss kill
    }
    return char.currentRun
end

-- Leaving the dungeon only pauses the run (D-110): dying and running back, or going
-- out to repair, is still one run. Coming back into the same dungeon within
-- RESUME_SECONDS of last being inside continues it. It closes when that time passes
-- (checked here, each minute and at login), when another dungeon is entered, or on
-- leaving after the run was completed.
local function check()
    local char = Store.char
    local t = Store.Now()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    instanceType, instanceID = T.Plain(instanceType), T.Plain(instanceID)
    local run = char.currentRun
    if instanceType == "party" then
        if run and run.instanceID == instanceID and t - (run.lastSeen or run.entered) <= RESUME_SECONDS then
            if run.outside then
                -- Back in: remember when, in case a reset shows this is a new run.
                run.outside = nil
                run.backAt, run.seenBefore = t, run.lastSeen
            end
            run.lastSeen = t
            countIfReady(run, t)
            return
        end
        closeRun(char)
        startRun(char, t, T.Plain(name), instanceID, T.Plain(difficultyID))
    elseif run then
        if run.completed or t - (run.lastSeen or run.entered) > RESUME_SECONDS then
            closeRun(char)
        elseif not run.outside then
            run.outside = t
        end
    end
end

local function complete(run, how)
    if run.completed then return end
    countIfReady(run, Store.Now())
    if run.pending then -- completed without a kill (a reward) still makes it a run
        run.pending = nil
        Store.Count("dungeonsEntered")
    end
    run.completed = true
    run.completedBy = how
    run.completedAt = Store.Now()
    -- The group at the final boss is the run's group: groups often break up before
    -- anyone leaves the dungeon (Austin, 2026-11-06). Frozen from here on.
    local party = partySnapshot()
    if #party > 0 then run.party = party end
    run.partyFrozen = true
    Store.Count("dungeonsCompleted")
end

local Dungeons = T.Define({ id = "dungeons" })
Dungeons.MIN_RUN_SECONDS = MIN_RUN_SECONDS

-- Runs saved without a boss list (D-085): look the list up by the dungeon's name now,
-- and if the last boss is among the kills, the run was completed (counted on the day
-- of that kill).
local REPAIR_VERSION = 3
function Dungeons.Repair(char)
    local fixed = 0
    for _, run in ipairs(char.dungeons or {}) do
        -- repairTried: the version of this repair that last looked (3 = final-boss list, D-086).
        if not run.completed and #(run.bosses or {}) > 0 and (run.repairTried or 0) ~= REPAIR_VERSION then
            run.repairTried = REPAIR_VERSION
            local last, count, how, lastName = findLastBoss(run.name)
            if last ~= nil then
                run.lastBossID, run.bossCount, run.lookup, run.lastBossName = last or nil, count, how, lastName
            end
            for _, b in ipairs(run.bosses) do
                if isLastBoss(run, b.id, b.name) then
                    run.completed, run.completedBy, run.completedAt = true, "lastBoss", b.at
                    Days.Add(char.days, Days.Key(b.at or Store.Now(), date), "dungeonsCompleted", 1)
                    fixed = fixed + 1
                    break
                end
            end
        end
    end
    return fixed
end

-- Take one off a run's day and session "entered" count.
local function uncount(char, at)
    local day = char.days and char.days[Days.Key(at or 0, date)]
    if day and (day.dungeonsEntered or 0) > 0 then day.dungeonsEntered = day.dungeonsEntered - 1 end
    for _, s in ipairs(char.sessions or {}) do
        local e = at or 0
        if s.counts and e >= (s.start or 0) and e <= (s.stop or e) then
            if (s.counts.dungeonsEntered or 0) > 0 then s.counts.dungeonsEntered = s.counts.dungeonsEntered - 1 end
            break
        end
    end
end

-- Once per character: drop saved runs from before the 5-minute rule that were only
-- a walk in and out (under 5 minutes, no boss, not completed), and take them back
-- off that day's and that session's "entered" count.
function Dungeons.DropBlips(char)
    if char.dungeonBlipsDropped then return 0 end
    char.dungeonBlipsDropped = true
    local dropped = 0
    local list = char.dungeons or {}
    for i = #list, 1, -1 do
        local run = list[i]
        if not run.completed and #(run.bosses or {}) == 0 and (run.duration or 0) < MIN_RUN_SECONDS then
            table.remove(list, i)
            dropped = dropped + 1
            uncount(char, run.entered)
        end
    end
    return dropped
end

-- Once per character (D-110): before 1.7.1, leaving the dungeon (a death and a
-- release, or going out to repair) closed the run, so coming back made a second one.
-- Join two saved runs of the same dungeon when the second began within
-- RESUME_SECONDS of the first ending, the first was not completed, and no boss died
-- in both (that would be a reset, so two real runs).
function Dungeons.MergeSplits(char)
    if char.dungeonSplitsMerged then return 0 end
    char.dungeonSplitsMerged = true
    local list = char.dungeons or {}
    local merged = 0
    for i = #list, 2, -1 do
        local a, b = list[i - 1], list[i]
        local aEnd = a.left or ((a.entered or 0) + (a.duration or 0))
        local gap = (b.entered or 0) - aEnd
        local same = a.name ~= nil and a.name == b.name and (a.instanceID == nil or b.instanceID == nil or a.instanceID == b.instanceID)
        local repeated = false
        for _, x in ipairs(a.bosses or {}) do
            for _, y in ipairs(b.bosses or {}) do
                if (x.id ~= nil and x.id == y.id) or (x.id == nil and x.name ~= nil and x.name == y.name) then repeated = true end
            end
        end
        if same and not a.completed and gap >= 0 and gap <= RESUME_SECONDS and not repeated then
            for _, y in ipairs(b.bosses or {}) do a.bosses[#a.bosses + 1] = y end
            a.deaths = (a.deaths or 0) + (b.deaths or 0)
            a.left = b.left or ((b.entered or 0) + (b.duration or 0))
            a.duration = a.left - a.entered
            if #(b.party or {}) > 0 then a.party = b.party end
            for _, k in ipairs({ "completed", "completedBy", "completedAt", "partyFrozen", "lastBossID", "lastBossName", "bossCount", "lookup" }) do
                if b[k] ~= nil then a[k] = b[k] end
            end
            if (a.difficultyID or 0) == 0 then a.difficultyID = b.difficultyID end
            table.remove(list, i)
            uncount(char, b.entered)
            merged = merged + 1
        end
    end
    return merged
end

function Dungeons:OnLogin()
    -- Every character on this account, not only the one logging in: a character
    -- not played since the update would otherwise keep its old walk-in runs.
    for _, c in pairs(ns.db.characters or {}) do Dungeons.DropBlips(c); Dungeons.MergeSplits(c) end
    check()
    Dungeons.Repair(Store.char)
end

function Dungeons:OnTick()
    local run = Store.char.currentRun
    if run then
        local _, instanceType = GetInstanceInfo()
        if T.Plain(instanceType) == "party" and not run.outside then
            run.lastSeen = Store.Now()
            countIfReady(run, run.lastSeen)
            ensureLastBoss(run)
        else
            check() -- outside: close the run once the time to come back has passed
        end
    end
end

Dungeons.events.PLAYER_ENTERING_WORLD = function() check() end
Dungeons.events.ZONE_CHANGED_NEW_AREA = function() check() end

-- Group changes during a run. Joins always count (a late arrival was in the run);
-- after the first boss, someone leaving no longer shrinks the group; once the
-- run is completed the group is frozen, and only a name opt-in that arrives late
-- is filled in (matched by class and role).
local function refreshParty()
    local run = Store.char and Store.char.currentRun
    if not run then return end
    local party = partySnapshot()
    if run.partyFrozen then
        for _, p in ipairs(party) do
            if p.name then
                for _, q in ipairs(run.party or {}) do
                    if not q.name and q.class == p.class and q.role == p.role then q.name = p.name break end
                end
            end
        end
        return
    end
    if #(run.bosses or {}) > 0 and #party < #(run.party or {}) then return end
    if #party > 0 then run.party = party end
end
Dungeons.events.GROUP_ROSTER_UPDATE = refreshParty
ns.DungeonsRefreshParty = refreshParty -- called when a party member's name opt-in arrives

-- GetInstanceInfo reported difficulty 0 on entry in the retail run; the encounter
-- events carry the real difficulty, so fill it in from them.
local function noteDifficulty(run, difficultyID)
    difficultyID = T.Plain(difficultyID)
    if run and type(difficultyID) == "number" and difficultyID > 0 and (run.difficultyID or 0) == 0 then
        run.difficultyID = difficultyID
    end
end

Dungeons.events.ENCOUNTER_START = function(_, encounterID, _, difficultyID)
    local run = Store.char.currentRun
    noteDifficulty(run, difficultyID)
    ensureLastBoss(run)
    -- The pull, for the fight length (D-104). A wipe and a new pull start it again.
    if run then run.pull = { id = T.Plain(encounterID), at = Store.Now() } end
end

Dungeons.events.ENCOUNTER_END = function(_, encounterID, encounterName, difficultyID, _, success)
    local run = Store.char.currentRun
    noteDifficulty(run, difficultyID)
    if not run then return end
    local pull = run.pull
    run.pull = nil
    if T.Plain(success) ~= 1 then return end
    encounterID = T.Plain(encounterID)
    if T.Dedupe("boss:" .. tostring(encounterID), 10) then return end
    local t = Store.Now()
    -- A boss this run already killed died again: the dungeon was reset while we were
    -- out, so the old run ended when we left and a new one began when we came back.
    if run.backAt then
        for _, b in ipairs(run.bosses) do
            if b.id == encounterID and (b.at or 0) < run.backAt then
                local backAt = run.backAt
                run.lastSeen = run.seenBefore or run.lastSeen
                run.pull = nil
                local char = Store.char
                closeRun(char)
                local _, _, diff = GetInstanceInfo()
                run = startRun(char, backAt, run.name, run.instanceID, T.Plain(diff) or run.difficultyID)
                run.lastSeen = t
                break
            end
        end
    end
    -- Fight length: from this encounter's pull to the kill (D-104); nil without a pull.
    local fight = pull and pull.at and (pull.id == nil or pull.id == encounterID) and t - pull.at or nil
    if fight and (fight < 0 or fight > 3600) then fight = nil end
    run.bosses[#run.bosses + 1] = { id = encounterID, name = T.Plain(encounterName), at = t, fight = fight }
    if not run.partyFrozen then
        local party = partySnapshot() -- the group that killed this boss
        if #party > 0 then run.party = party end
    end
    countIfReady(run, Store.Now())
    Store.Count("bossKills")
    if not run.lastBossID and not run.lastBossName then run.lookups = 0; ensureLastBoss(run) end
    if isLastBoss(run, encounterID, T.Plain(encounterName)) then complete(run, "lastBoss") end
end

Dungeons.events.LFG_COMPLETION_REWARD = function()
    local run = Store.char.currentRun
    if run then complete(run, "finder") end
end

Dungeons.events.PLAYER_DEAD = function()
    local run = Store.char.currentRun
    if run and not run.outside then run.deaths = run.deaths + 1 end -- not a death out in the world
end
