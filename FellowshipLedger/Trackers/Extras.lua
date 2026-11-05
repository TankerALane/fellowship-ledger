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

-- "What killed you": the game's death recap. Recap IDs count up from 1 each UI
-- session; after a death the newest ID with events is found by probing upward
-- (no chat is read). The killing blow is the event with the latest timestamp.
-- On clients where these values are secret, the killer is stored as hidden.
local lastRecap = 0
function Deaths.FindKiller()
    if not (ns.Compat.Has("C_DeathRecap.HasRecapEvents") and ns.Compat.Has("C_DeathRecap.GetRecapEvents")) then
        return nil, "unavailable"
    end
    local newest
    for id = lastRecap + 1, lastRecap + 25 do
        local ok, has = pcall(C_DeathRecap.HasRecapEvents, id)
        if ok and T.Plain(has) == true then newest = id end
    end
    if not newest then return nil, "none" end
    lastRecap = newest
    local ok, events = pcall(C_DeathRecap.GetRecapEvents, newest)
    if not ok or type(events) ~= "table" or #events == 0 then return nil, "none" end
    local blow, best = nil, -math.huge
    for _, e in ipairs(events) do
        local ts = type(e) == "table" and T.Plain(e.timestamp)
        if type(ts) == "number" and ts > best then blow, best = e, ts end
    end
    blow = blow or events[1]
    if type(blow) ~= "table" then return nil, "none" end
    local source, spell = T.Plain(blow.sourceName), T.Plain(blow.spellName)
    if ns.Compat.IsSecret(blow.sourceName) or ns.Compat.IsSecret(blow.spellName) then return nil, "hidden" end
    return { source = source, spell = spell, amount = T.Plain(blow.amount) }, "ok"
end

-- Name and level of your target, or nil (no target, or the values are secret).
function Deaths.TargetNow()
    local okE, exists = ns.Compat.Call("killerLevel", "UnitExists", "target")
    if not okE or not T.Plain(exists) then return nil end
    local okN, name = ns.Compat.Call("killerLevel", "UnitName", "target")
    local okL, level = ns.Compat.Call("killerLevel", "UnitLevel", "target")
    name, level = okN and T.Plain(name) or nil, okL and T.Plain(level) or nil
    if type(name) ~= "string" or type(level) ~= "number" then return nil end
    return name, level
end

-- Recently targeted units by name, so the level is still known when the game
-- clears your target as you die. Kept in memory only, for 5 minutes.
Deaths.SEEN_KEEP = 300
Deaths.seen = {}
function Deaths.Remember(name, level, now)
    if not name then return end
    Deaths.seen[name] = { level = level, at = now }
    for n, s in pairs(Deaths.seen) do
        if now - s.at > Deaths.SEEN_KEEP then Deaths.seen[n] = nil end
    end
end

-- The killer's level: from the target at the moment of death, else from a
-- recent target with the same name. Returns level, how ("target"/"recent") or nil.
function Deaths.LevelFor(source, targetName, targetLevel, now)
    if not source then return nil end
    if targetName == source then return targetLevel, "target" end
    local s = Deaths.seen[source]
    if s and now - s.at <= Deaths.SEEN_KEEP then return s.level, "recent" end
    return nil
end

Deaths.events.PLAYER_TARGET_CHANGED = function()
    local name, level = Deaths.TargetNow()
    if name then Deaths.Remember(name, level, Store.Now()) end
end

Deaths.events.PLAYER_DEAD = function()
    if T.Dedupe("death", 5) then return end
    local char = Store.char
    local zone = Store.Zone()
    local _, instanceType = GetInstanceInfo()
    local entry = { at = Store.Now(), zone = zone, level = char.level, instanceType = T.Plain(instanceType) }
    char.deathLog[#char.deathLog + 1] = entry
    Days.PruneList(char.deathLog, "at", Store.Now(), Character.LIST_KEEP_SECONDS)
    Store.Count("deaths")
    -- The recap has no level, so note your target now (and recent targets); if
    -- one turns out to be the killer, keep its level (D-075, D-077). -1 = skull.
    local targetName, targetLevel = Deaths.TargetNow()
    if targetName then Deaths.Remember(targetName, targetLevel, Store.Now()) end
    -- The recap is built a moment after the death.
    ns.Events.After(1, function()
        local killer, status = Deaths.FindKiller()
        entry.killerStatus = status
        local how
        if killer then
            entry.killer, entry.killerSpell = killer.source, killer.spell
            entry.killerLevel, how = Deaths.LevelFor(killer.source, targetName, targetLevel, Store.Now())
        end
        -- For /fl verify only (this session, not saved).
        Deaths.lastCheck = { target = targetName or false, source = killer and killer.source, how = how or false }
    end)
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

-- True discoveries: the game's on-screen info message "Discovered: <area>" (seen on
-- retail as UI_INFO_MESSAGE type 408). This is the UI info line, not chat. It is
-- recognised by the message's error name (GetGameMessageInfo) or, failing that, by
-- the client's own localized format strings ERR_ZONE_EXPLORED / ERR_ZONE_EXPLORED_XP.
local DISCOVERY_NAMES = { ERR_ZONE_EXPLORED = true, ERR_ZONE_EXPLORED_XP = true }
local discoveryPatterns
local function patterns()
    if not discoveryPatterns then
        discoveryPatterns = {}
        for _, key in ipairs({ "ERR_ZONE_EXPLORED", "ERR_ZONE_EXPLORED_XP" }) do
            local fmt = _G[key]
            if type(fmt) == "string" then discoveryPatterns[#discoveryPatterns + 1] = ns.Format.PatternFromFormat(fmt) end
        end
    end
    return discoveryPatterns
end

Zones.events.UI_INFO_MESSAGE = function(_, messageType, message)
    messageType, message = T.Plain(messageType), T.Plain(message)
    local discovered, area = false, nil
    if messageType and ns.Compat.Has("GetGameMessageInfo") then
        local ok, errorName = ns.Compat.Call("zones", "GetGameMessageInfo", messageType)
        discovered = ok and DISCOVERY_NAMES[T.Plain(errorName)] == true
    end
    if type(message) == "string" then
        for _, p in ipairs(patterns()) do
            local found = message:match(p)
            if found then
                discovered, area = true, found
                break
            end
        end
    end
    if not discovered then return end
    area = area or message
    if T.Dedupe("discover:" .. tostring(area), 10) then return end
    local list = Store.char.discoveries
    list[#list + 1] = { name = area, at = Store.Now() }
    Days.PruneList(list, "at", Store.Now(), Character.LIST_KEEP_SECONDS)
    Store.Count("zonesDiscovered")
end

-- Reputation (diff of standings on UPDATE_FACTION) --------------------------------
local Reputation = T.Define({ id = "reputation" })
local standings

-- The reputation list by index hides factions under collapsed headers (seen on
-- retail: 28 UPDATE_FACTION, no gain found). So at login the ledger looks factions
-- up by ID once and then watches every ID that exists, whatever the panel shows.
local MAX_FACTION_ID = 4000
local factionIDs

local function addFaction(out, data)
    if type(data) ~= "table" or data.isHeader and not data.isHeaderWithRep then return end
    local id, standing = T.Plain(data.factionID), T.Plain(data.currentStanding)
    if id and type(standing) == "number" then
        out[id] = { name = T.Plain(data.name), standing = standing }
    end
end

local function discoverFactionIDs()
    local ids, seen = {}, {}
    if ns.Compat.Has("C_Reputation.GetFactionDataByID") then
        for id = 1, MAX_FACTION_ID do
            local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
            if ok and type(data) == "table" and T.Plain(data.factionID) then
                ids[#ids + 1] = id
                seen[id] = true
            end
        end
    end
    -- Also anything visible in the panel (covers clients where lookup by ID is missing).
    local okN, n = ns.Compat.Call("reputation", "C_Reputation.GetNumFactions")
    for i = 1, okN and n or 0 do
        local okData, data = ns.Compat.Call("reputation", "C_Reputation.GetFactionDataByIndex", i)
        local id = okData and type(data) == "table" and T.Plain(data.factionID)
        if id and not seen[id] then
            ids[#ids + 1] = id
            seen[id] = true
        end
    end
    return ids
end

local function readStandings()
    factionIDs = factionIDs or discoverFactionIDs()
    local out = {}
    if ns.Compat.Has("C_Reputation.GetFactionDataByID") then
        for _, id in ipairs(factionIDs) do
            local ok, data = ns.Compat.Call("reputation", "C_Reputation.GetFactionDataByID", id)
            if ok then addFaction(out, data) end
        end
    end
    -- Plus anything visible in the panel that the ID scan did not have (newly met factions).
    local okN, n = ns.Compat.Call("reputation", "C_Reputation.GetNumFactions")
    for i = 1, okN and n or 0 do
        local ok, data = ns.Compat.Call("reputation", "C_Reputation.GetFactionDataByIndex", i)
        local id = ok and type(data) == "table" and T.Plain(data.factionID)
        if id and not out[id] then addFaction(out, data) end
    end
    return out
end

function Reputation:OnLogin()
    factionIDs = nil -- rescan IDs once per login
    standings = readStandings()
end

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
        if ctype then
            char.kills.byType[ctype] = (char.kills.byType[ctype] or 0) + 1
            -- Per day too, so the Kills view can follow the range (D-081). Local only:
            -- these day fields are not in the share codec.
            ns.Days.Add(char.days, Store.Today(), "killType:" .. ctype, 1)
        end
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

-- Flight paths --------------------------------------------------------------------
-- Two signals (D-080):
-- 1. The game's on-screen "New flight path discovered!" (UI_INFO_MESSAGE, recognised by
--    its error name ERR_NEWTAXIPATH or the client's own string). It is counted at once.
-- 2. When the flight map opens, known taxi nodes are compared with the saved list. The
--    first time on a character everything is a baseline (not counted), except the node
--    you stand at if the discovery message just came; later new nodes are counted unless
--    the message already counted them.
local FlightPaths = T.Define({ id = "flightPaths" })
FlightPaths.DISCOVERY_WINDOW = 120 -- seconds from the message to the flight map
FlightPaths.lastCheck = {} -- for /fl verify (this session only)

function FlightPaths.IsDiscovery(messageType, message)
    if messageType and ns.Compat.Has("GetGameMessageInfo") then
        local ok, errorName = ns.Compat.Try("GetGameMessageInfo", messageType)
        if ok and T.Plain(errorName) == "ERR_NEWTAXIPATH" then return true end
    end
    local text = _G.ERR_NEWTAXIPATH
    return type(text) == "string" and message == text
end

-- The message may come just before or just after the flight map opens; either
-- way the new path is counted once.
FlightPaths.events.UI_INFO_MESSAGE = function(_, messageType, message)
    if not FlightPaths.IsDiscovery(T.Plain(messageType), T.Plain(message)) then return end
    if T.Dedupe("flightPathMsg", 5) then return end
    local now = Store.Now()
    FlightPaths.lastCheck.message = now
    local open = FlightPaths.recentOpen
    if open and now - open.at <= 10 and open.currentNew then
        local entry = Store.char.flightPaths[tostring(open.currentNew)]
        if entry and entry.baseline then
            entry.baseline = nil
            Store.Count("flightPaths")
        end
        return -- the map already counted it
    end
    FlightPaths.pending = now
    Store.Count("flightPaths")
end

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
    local states = _G.Enum and _G.Enum.FlightPathState
    local unreachable, current = states and states.Unreachable, states and states.Current
    local char = Store.char
    local baseline = not char.flightPathsBaseline
    local pending = FlightPaths.pending and Store.Now() - FlightPaths.pending <= FlightPaths.DISCOVERY_WINDOW
    local added, currentNew = 0, nil
    for _, node in ipairs(nodes) do
        local id = T.Plain(node.nodeID)
        local state = T.Plain(node.state)
        if id and state ~= unreachable and not char.flightPaths[tostring(id)] then
            local here = current ~= nil and state == current
            -- The message already counted the node you stand at.
            local claimed = pending and (here or current == nil)
            local entry = { name = T.Plain(node.name), at = Store.Now() }
            if claimed then
                pending = false
            elseif baseline then
                entry.baseline = true
            else
                Store.Count("flightPaths")
            end
            char.flightPaths[tostring(id)] = entry
            added = added + 1
            if here then currentNew = id end
        end
    end
    FlightPaths.pending = nil
    char.flightPathsBaseline = true
    FlightPaths.recentOpen = { at = Store.Now(), currentNew = currentNew }
    FlightPaths.lastCheck.open = { at = Store.Now(), nodes = #nodes, added = added, baseline = baseline }
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
-- Real players only: follower-dungeon companions are party units that level with you.
local function isPlayer(unit)
    local ok, yes = ns.Compat.Call("partyLevels", "UnitIsPlayer", unit)
    return ok and T.Plain(yes) == true
end

local function refreshParty()
    partyLevel = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and isPlayer(unit) then partyLevel[unit] = T.Plain(UnitLevel(unit)) end
    end
end
function PartyLevels:OnLogin() refreshParty() end
PartyLevels.events.GROUP_ROSTER_UPDATE = refreshParty
PartyLevels.events.UNIT_LEVEL = function(_, unit)
    if type(unit) ~= "string" or not unit:find("^party%d$") or not isPlayer(unit) then return end
    local level = T.Plain(UnitLevel(unit))
    local before = partyLevel[unit]
    partyLevel[unit] = level
    if before and level and level > before then
        local list = Store.char.partyLevels
        list[#list + 1] = { at = Store.Now(), class = T.Plain(select(2, UnitClass(unit))), level = level }
        Store.Count("partyLevelUps")
    end
end
