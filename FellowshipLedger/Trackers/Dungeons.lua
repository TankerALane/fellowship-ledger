-- Trackers/Dungeons.lua
-- Dungeon runs: entered and completed are counted separately. A run is completed
-- when the dungeon's last boss (from the encounter journal) dies, or when the
-- dungeon finder reports completion. Party make-up is stored as class and role only.
-- Status "unverified": ENCOUNTER_END and the journal lookup are not yet seen in a probe.

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

-- Journal lookup of the final boss's encounter ID for the current dungeon.
local function findLastBoss()
    local ejFrame = _G.EncounterJournal
    if ejFrame and ejFrame.IsShown and ejFrame:IsShown() then return nil end -- don't disturb an open journal
    local okMap, mapID = ns.Compat.Call("dungeons", "C_Map.GetBestMapForUnit", "player")
    if not okMap or not mapID then return nil end
    local okJ, journalID = ns.Compat.Call("dungeons", "EJ_GetInstanceForMap", mapID)
    if not okJ or not journalID or journalID == 0 then return nil end
    ns.Compat.Call("dungeons", "EJ_SelectInstance", journalID)
    local last, count
    for i = 1, 40 do
        local ok, name, _, _, _, _, _, dungeonEncounterID = ns.Compat.Call("dungeons", "EJ_GetEncounterInfoByIndex", i, journalID)
        if not ok or not name then break end
        last, count = T.Plain(dungeonEncounterID), i
    end
    return last, count
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
        local lastBoss, bossCount = findLastBoss()
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

function Dungeons:OnLogin() check() end

function Dungeons:OnTick()
    local run = Store.char.currentRun
    if run then
        local _, instanceType = GetInstanceInfo()
        if T.Plain(instanceType) == "party" then run.lastSeen = Store.Now() end
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
end

Dungeons.events.ENCOUNTER_END = function(_, encounterID, encounterName, difficultyID, _, success)
    local run = Store.char.currentRun
    noteDifficulty(run, difficultyID)
    if not run or T.Plain(success) ~= 1 then return end
    encounterID = T.Plain(encounterID)
    if T.Dedupe("boss:" .. tostring(encounterID), 10) then return end
    run.bosses[#run.bosses + 1] = { id = encounterID, name = T.Plain(encounterName), at = Store.Now() }
    Store.Count("bossKills")
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
