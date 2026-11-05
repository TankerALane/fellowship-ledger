-- Core/Character.lua
-- PURE: no WoW globals. Shape of one character record in FellowshipLedgerDB.characters.

local _, ns = ...

local Character = {}
ns.Character = Character

Character.QUEST_LOG_SECONDS = 30 * 86400
Character.LIST_KEEP_SECONDS = 90 * 86400

Character.STALE_DAYS = 30                   -- "not played for a while" in the new-character prompt
Character.REMOVED_KEEP_SECONDS = 90 * 86400 -- how long removals are passed on to friends

-- My other characters not played for STALE_DAYS or more, longest first. Characters
-- I chose to keep (c.keep) and the one I am on are left out. The addon cannot see
-- the character list, so "not played for a while" is all it can go on.
function Character.Stale(characters, currentKey, now)
    local out = {}
    for key, c in pairs(characters or {}) do
        if key ~= currentKey and not c.keep then
            local days = math.floor((now - (c.lastSeen or c.created or 0)) / 86400)
            if days >= Character.STALE_DAYS then
                out[#out + 1] = { key = key, name = c.display or c.name or key, class = c.class, level = c.level, days = days }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.days ~= b.days then return a.days > b.days end
        return a.key < b.key
    end)
    return out
end

-- Remove a character from the ledger and remember it for a while, so friends are
-- told to drop it too (sent with HELLO). Returns true if it was there.
function Character.Remove(db, key, now)
    if not db.characters or not db.characters[key] then return false end
    db.characters[key] = nil
    db.removed = db.removed or {}
    db.removed[key] = now
    return true
end

-- Forget removals older than REMOVED_KEEP_SECONDS; a character logged into again
-- is no longer removed.
function Character.PruneRemoved(removed, now, currentKey)
    for key, at in pairs(removed or {}) do
        if key == currentKey or now - (tonumber(at) or 0) > Character.REMOVED_KEEP_SECONDS then removed[key] = nil end
    end
end

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
    char.items = char.items or {}          -- notable loot { at, link, name, quality, quantity, zone }, 90 days
    char.chains = char.chains or {}        -- quest chains in progress [key] = { name, step, total, firstQuestID, firstName, startZone, source }
    char.reputation = char.reputation or {}
    char.flightPaths = char.flightPaths or {}
    char.achievements = char.achievements or {}
    char.partyLevels = char.partyLevels or {}
    char.kills = char.kills or { total = 0, byType = {}, rare = 0, elite = 0 }
    ns.TrackerList.EnsureFlags(char)
    return char
end
