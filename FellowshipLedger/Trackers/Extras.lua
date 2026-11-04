-- Trackers/Extras.lua
-- Smaller trackers: deaths, new zones, reputation, kills, flight paths,
-- achievements and party level-ups. Each one is its own tracker id with its own
-- Track/Share flags. "What killed you" and notable item drops are not built yet
-- (their APIs are unverified); see TrackerList statuses.

local _, ns = ...
local T = ns.Trackers
local Store, Days, Character = ns.Store, ns.Days, ns.Character

-- Deaths ---------------------------------------------------------------------
local Deaths = T.Define({ id = "deaths" })
Deaths.events.PLAYER_DEAD = function()
    if T.Dedupe("death", 5) then return end
    local char = Store.char
    local zone = Store.Zone()
    local _, instanceType = GetInstanceInfo()
    char.deathLog[#char.deathLog + 1] = { at = Store.Now(), zone = zone, level = char.level, instanceType = T.Plain(instanceType) }
    Days.PruneList(char.deathLog, "at", Store.Now(), Character.LIST_KEEP_SECONDS)
    Store.Count("deaths")
end

-- New zones visited ("zones discovered" while the ledger is running) -------------
local Zones = T.Define({ id = "zones" })
local function visitZone()
    local name, mapID = Store.Zone()
    if not mapID then return end
    local char = Store.char
    local key = tostring(mapID)
    if not char.zones[key] then
        char.zones[key] = { name = name, first = Store.Now() }
        Store.Count("zonesNew")
    end
end
function Zones:OnLogin() visitZone() end
Zones.events.ZONE_CHANGED_NEW_AREA = function()
    Store.Touch()
    visitZone()
end

-- Reputation (diff of standings on UPDATE_FACTION) --------------------------------
local Reputation = T.Define({ id = "reputation" })
local standings

local function readStandings()
    local ok, n = ns.Compat.Call("reputation", "C_Reputation.GetNumFactions")
    if not ok then return nil end
    local out = {}
    for i = 1, n or 0 do
        local okData, data = ns.Compat.Call("reputation", "C_Reputation.GetFactionDataByIndex", i)
        if okData and type(data) == "table" then
            local id, standing = T.Plain(data.factionID), T.Plain(data.currentStanding)
            if id and type(standing) == "number" and not data.isHeader then
                out[id] = { name = T.Plain(data.name), standing = standing }
            elseif id and data.currentStanding == nil then
                ns.Compat.Disable("reputation", "FactionData has no currentStanding field")
                return nil
            end
        end
    end
    return out
end

function Reputation:OnLogin() standings = readStandings() end

local repPending = false
Reputation.events.UPDATE_FACTION = function()
    if repPending then return end
    repPending = true
    ns.Events.After(1, function()
        repPending = false
        if not T.IsActive("reputation") then return end
        local now = readStandings()
        if not now then return end
        if standings then
            local total = 0
            for id, cur in pairs(now) do
                local before = standings[id]
                if before and cur.standing > before.standing then
                    local gain = cur.standing - before.standing
                    total = total + gain
                    local r = Store.char.reputation[tostring(id)] or { gained = 0 }
                    r.name = cur.name
                    r.gained = r.gained + gain
                    Store.char.reputation[tostring(id)] = r
                end
            end
            if total > 0 then Store.Count("repGained", total) end
        end
        standings = now
    end)
end

-- Kills (PARTY_KILL attacker/target GUIDs: equality checks only, never parsed) ---
local Kills = T.Define({ id = "kills" })
local RARE = { rare = true, rareelite = true }
local ELITE = { elite = true, rareelite = true, worldboss = true }
Kills.events.PARTY_KILL = function(_, attacker, target)
    if ns.Compat.IsSecret(attacker) or ns.Compat.IsSecret(target) then
        ns.Compat.Disable("kills", "kill events carry secret values on this client")
        return
    end
    local ok, me = ns.Compat.Call("kills", "UnitGUID", "player")
    if not ok or attacker ~= me then return end
    Store.Touch()
    local char = Store.char
    char.kills.total = char.kills.total + 1
    Store.Count("kills")
    local okT, targetGUID = ns.Compat.Call("kills", "UnitGUID", "target")
    if okT and targetGUID and targetGUID == target then
        local ctype = T.Plain(UnitCreatureType("target"))
        local class = T.Plain(UnitClassification("target"))
        if ctype then char.kills.byType[ctype] = (char.kills.byType[ctype] or 0) + 1 end
        if class and RARE[class] then
            char.kills.rare = char.kills.rare + 1
            Store.Count("rareKills")
        end
        if class and ELITE[class] then
            char.kills.elite = char.kills.elite + 1
            Store.Count("eliteKills")
        end
    end
end

-- Flight paths (diff of known taxi nodes when the flight map opens) ---------------
local FlightPaths = T.Define({ id = "flightPaths" })
FlightPaths.events.TAXIMAP_OPENED = function()
    local mapID
    if ns.Compat.Has("GetTaxiMapID") then mapID = T.Plain(GetTaxiMapID()) end
    if not mapID then
        local _, m = Store.Zone()
        mapID = m
    end
    if not mapID then return end
    local ok, nodes = ns.Compat.Call("flightPaths", "C_TaxiMap.GetAllTaxiNodes", mapID)
    if not ok or type(nodes) ~= "table" then return end
    local unreachable = _G.Enum and _G.Enum.FlightPathState and _G.Enum.FlightPathState.Unreachable
    local char = Store.char
    local baseline = not char.flightPathsBaseline
    for _, node in ipairs(nodes) do
        local id = T.Plain(node.nodeID)
        if id and node.state ~= unreachable and not char.flightPaths[tostring(id)] then
            char.flightPaths[tostring(id)] = { name = T.Plain(node.name), at = Store.Now(), baseline = baseline or nil }
            if not baseline then Store.Count("flightPaths") end
        end
    end
    char.flightPathsBaseline = true
end

-- Achievements -------------------------------------------------------------------
local Achievements = T.Define({ id = "achievements" })
Achievements.events.ACHIEVEMENT_EARNED = function(_, id, alreadyEarned)
    id = T.Plain(id)
    if not id or T.Plain(alreadyEarned) == true then return end
    if T.Dedupe("ach:" .. id, 10) then return end
    local ok, _, name = ns.Compat.Call("achievements", "GetAchievementInfo", id)
    local list = Store.char.achievements
    list[#list + 1] = { id = id, name = ok and T.Plain(name) or nil, at = Store.Now() }
    Store.Count("achievements")
end

-- Party level-ups (class and level only, no names) -------------------------------
local PartyLevels = T.Define({ id = "partyLevels" })
local partyLevel = {}
local function refreshParty()
    partyLevel = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then partyLevel[unit] = T.Plain(UnitLevel(unit)) end
    end
end
function PartyLevels:OnLogin() refreshParty() end
PartyLevels.events.GROUP_ROSTER_UPDATE = refreshParty
PartyLevels.events.UNIT_LEVEL = function(_, unit)
    if type(unit) ~= "string" or not unit:find("^party%d$") then return end
    local level = T.Plain(UnitLevel(unit))
    local before = partyLevel[unit]
    partyLevel[unit] = level
    if before and level and level > before then
        local list = Store.char.partyLevels
        list[#list + 1] = { at = Store.Now(), class = T.Plain(select(2, UnitClass(unit))), level = level }
        Store.Count("partyLevelUps")
    end
end
