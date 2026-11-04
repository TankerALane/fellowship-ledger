-- Core/Character.lua
-- PURE: no WoW globals. Shape of one character record in FellowshipLedgerDB.characters.

local _, ns = ...

local Character = {}
ns.Character = Character

Character.QUEST_LOG_SECONDS = 30 * 86400
Character.LIST_KEEP_SECONDS = 90 * 86400

function Character.Key(name, realm)
    return tostring(name) .. "-" .. tostring(realm)
end

-- Fill in any missing fields. Safe to run on every login (idempotent).
function Character.Ensure(char, now)
    char.created = char.created or now
    char.days = char.days or {}            -- ["YYYY-MM-DD"] = { levels, quests, xp, moneyNet, ... }
    char.sessions = char.sessions or {}    -- list, newest last
    char.levels = char.levels or {}        -- [toLevel] = { from, to, active, total, at, zone, xpPerHour, kills }
    char.questLog = char.questLog or {}    -- { id, title, at, xp, money }, 30 days
    char.dungeons = char.dungeons or {}    -- runs, newest last, 90 days
    char.professions = char.professions or {}
    char.deathLog = char.deathLog or {}
    char.zones = char.zones or {}          -- [mapID] = { name, first }
    char.discoveries = char.discoveries or {} -- { name, at }, from "Discovered: <area>", 90 days
    char.reputation = char.reputation or {}
    char.flightPaths = char.flightPaths or {}
    char.achievements = char.achievements or {}
    char.partyLevels = char.partyLevels or {}
    char.kills = char.kills or { total = 0, byType = {}, rare = 0, elite = 0 }
    ns.TrackerList.EnsureFlags(char)
    return char
end
