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
local function journalBosses(journalID)
    ns.Compat.Try("EJ_SelectInstance", journalID)
    local last, count
    for i = 1, 40 do
        local ok, name, _, _, _, _, _, dungeonEncounterID = ns.Compat.Try("EJ_GetEncounterInfoByIndex", i, journalID)
        if not ok or not name then break end
        last, count = T.Plain(dungeonEncounterID), i
    end
    return last, count
end

function ns.DungeonJournalByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local okT, tiers = ns.Compat.Try("EJ_GetNumTiers")
    for tier = 1, (okT and type(tiers) == "number") and tiers or 1 do
        if okT then ns.Compat.Try("EJ_SelectTier", tier) end
        for i = 1, 200 do
            local ok, journalID, iname = ns.Compat.Try("EJ_GetInstanceByIndex", i, false)
            if not ok or not journalID then break end
            if T.Plain(iname) == name then return journalID end
        end
    end
    return nil
end

local function findLastBoss(dungeonName)
    local ejFrame = _G.EncounterJournal
    if ejFrame and ejFrame.IsShown and ejFrame:IsShown() then return nil end -- don't disturb an open journal
    local okMap, mapID = ns.Compat.Try("C_Map.GetBestMapForUnit", "player")
    if okMap and mapID then
        local okJ, journalID = ns.Compat.Try("EJ_GetInstanceForMap", mapID)
        if okJ and journalID and journalID ~= 0 then
            local last, count = journalBosses(journalID)
            if last then return last, count, "map" end
        end
    end
    local journalID = ns.DungeonJournalByName(dungeonName)
    if journalID then
        local last, count = journalBosses(journalID)
        if last then return last, count, "name" end
    end
    return nil
end
ns.DungeonFindLastBoss = findLastBoss -- for /fl verify

-- Retry while the run has no boss list (the map can be unknown right at loading).
local RETRIES = 10
local function ensureLastBoss(run)
    if not run or run.lastBossID or (run.lookups or 0) >= RETRIES then return end
    run.lookups = (run.lookups or 0) + 1
    local last, count, how = findLastBoss(run.name)
    if last then run.lastBossID, run.bossCount, run.lookup = last, count, how end
end

local function closeRun(char)
    local run = char.currentRun
    if not run then return end
    run.left = run.lastSeen or Store.Now()
    run.duration = run.left - run.entered
    char.dungeons[#char.dungeons + 1] = run
    char.currentRun = nil
    Days.PruneList(char.dungeons, "entered", Store.Now(), Character.LIST_KEEP_SECONDS)
end

local function check()
    local char = Store.char
    local t = Store.Now()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    instanceType, instanceID = T.Plain(instanceType), T.Plain(instanceID)
    local run = char.currentRun
    if instanceType == "party" then
        if run and run.instanceID == instanceID and t - (run.lastSeen or run.entered) <= RESUME_SECONDS then
            run.lastSeen = t
            return
        end
        closeRun(char)
        local lastBoss, bossCount, how = findLastBoss(T.Plain(name))
        char.currentRun = {
            name = T.Plain(name),
            instanceID = instanceID,
            difficultyID = T.Plain(difficultyID),
            entered = t,
            lastSeen = t,
            deaths = 0,
            bosses = {},
            party = partySnapshot(),
            lastBossID = lastBoss,
            bossCount = bossCount,
            lookup = how,
            lookups = 1,
        }
        Store.Count("dungeonsEntered")
    elseif run then
        closeRun(char)
    end
end

local function complete(run, how)
    if run.completed then return end
    run.completed = true
    run.completedBy = how
    run.completedAt = Store.Now()
    Store.Count("dungeonsCompleted")
end

local Dungeons = T.Define({ id = "dungeons" })

-- Runs saved without a boss list (D-085): look the list up by the dungeon's name now,
-- and if the last boss is among the kills, the run was completed (counted on the day
-- of that kill).
function Dungeons.Repair(char)
    local fixed = 0
    for _, run in ipairs(char.dungeons or {}) do
        if not run.completed and not run.lastBossID and #(run.bosses or {}) > 0 and not run.repairTried then
            run.repairTried = true
            local last, count, how = findLastBoss(run.name)
            if last then
                run.lastBossID, run.bossCount, run.lookup = last, count, how
                for _, b in ipairs(run.bosses) do
                    if b.id == last then
                        run.completed, run.completedBy, run.completedAt = true, "lastBoss", b.at
                        Days.Add(char.days, Days.Key(b.at or Store.Now(), date), "dungeonsCompleted", 1)
                        fixed = fixed + 1
                        break
                    end
                end
            end
        end
    end
    return fixed
end

function Dungeons:OnLogin()
    check()
    Dungeons.Repair(Store.char)
end

function Dungeons:OnTick()
    local run = Store.char.currentRun
    if run then
        local _, instanceType = GetInstanceInfo()
        if T.Plain(instanceType) == "party" then
            run.lastSeen = Store.Now()
            ensureLastBoss(run)
        end
    end
end

Dungeons.events.PLAYER_ENTERING_WORLD = function() check() end
Dungeons.events.ZONE_CHANGED_NEW_AREA = function() check() end

local function refreshParty()
    local run = Store.char and Store.char.currentRun
    if run then
        local party = partySnapshot()
        if #party > 0 then run.party = party end
    end
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

Dungeons.events.ENCOUNTER_START = function(_, _, _, difficultyID)
    noteDifficulty(Store.char.currentRun, difficultyID)
    ensureLastBoss(Store.char.currentRun)
end

Dungeons.events.ENCOUNTER_END = function(_, encounterID, encounterName, difficultyID, _, success)
    local run = Store.char.currentRun
    noteDifficulty(run, difficultyID)
    if not run or T.Plain(success) ~= 1 then return end
    encounterID = T.Plain(encounterID)
    if T.Dedupe("boss:" .. tostring(encounterID), 10) then return end
    run.bosses[#run.bosses + 1] = { id = encounterID, name = T.Plain(encounterName), at = Store.Now() }
    Store.Count("bossKills")
    if not run.lastBossID then run.lookups = 0; ensureLastBoss(run) end
    if run.lastBossID and encounterID == run.lastBossID then complete(run, "lastBoss") end
end

Dungeons.events.LFG_COMPLETION_REWARD = function()
    local run = Store.char.currentRun
    if run then complete(run, "finder") end
end

Dungeons.events.PLAYER_DEAD = function()
    local run = Store.char.currentRun
    if run then run.deaths = run.deaths + 1 end
end
