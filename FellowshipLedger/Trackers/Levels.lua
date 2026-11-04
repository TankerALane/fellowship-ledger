-- Trackers/Levels.lua
-- Time per level (active and total), XP per hour, zone, kills per level, XP gained.
-- Confirmed on retail: PLAYER_LEVEL_UP's first argument is the new level;
-- PLAYER_XP_UPDATE fires with "player".

local _, ns = ...
local L = ns.L
local T = ns.Trackers
local Store, Format = ns.Store, ns.Format

local lastXP, lastXPMax

local function newStart(char, level, partial)
    local clock = char.clock
    char.levelStart = {
        level = level,
        played = clock.played,
        active = clock.active,
        at = Store.Now(),
        kills = char.kills.total,
        xpMax = T.Plain(UnitXPMax("player")),
        -- partial: we did not see the start of this level, so its time is incomplete
        partial = partial or nil,
    }
end

local Levels = T.Define({ id = "levels" })

function Levels:OnLogin()
    local char = Store.char
    local level = T.Plain(UnitLevel("player")) or char.level
    local ls = char.levelStart
    if not ls or ls.level ~= level then
        newStart(char, level, (T.Plain(UnitXP("player")) or 0) > 0 or level > 1)
    end
    lastXP, lastXPMax = T.Plain(UnitXP("player")), T.Plain(UnitXPMax("player"))
end

Levels.events.PLAYER_LEVEL_UP = function(_, newLevel)
    local char = Store.char
    newLevel = T.Plain(newLevel)
    if type(newLevel) ~= "number" then newLevel = (char.level or 0) + 1 end
    if T.Dedupe("levelup:" .. newLevel, 10) then return end
    Store.Tick()

    local ls = char.levelStart or {}
    local clock = char.clock
    local zone, mapID = Store.Zone()
    local rec = {
        from = newLevel - 1,
        to = newLevel,
        active = clock.active - (ls.active or clock.active),
        total = clock.played - (ls.played or clock.played),
        at = Store.Now(),
        zone = zone,
        mapID = mapID,
        partial = (ls.partial or ls.level ~= newLevel - 1) or nil,
    }
    if T.IsActive("kills") and ls.kills then rec.kills = char.kills.total - ls.kills end
    if not rec.partial and ls.xpMax then rec.xpPerHour = Format.PerHour(ls.xpMax, rec.active) end
    char.levels[newLevel] = rec
    char.level = newLevel
    Store.session.levelEnd = newLevel
    Store.Count("levels")
    newStart(char, newLevel, false)
    -- UnitXPMax may still report the old level during the event; read it again shortly.
    ns.Events.After(2, function()
        if char.levelStart and char.levelStart.level == newLevel then
            char.levelStart.xpMax = T.Plain(UnitXPMax("player"))
        end
    end)

    if ns.db.settings.levelToast ~= false then
        ns.Log.Info(L.LEVEL_UP_TOAST, Format.LevelLine(rec) .. (rec.partial and (" " .. L.PARTIAL) or ""))
    end
end

Levels.events.PLAYER_XP_UPDATE = function(_, unit)
    if unit ~= "player" then return end
    Store.Touch()
    local xp, xpMax = T.Plain(UnitXP("player")), T.Plain(UnitXPMax("player"))
    if not xp or not xpMax then return end
    if lastXP and lastXPMax then
        local gained
        if xp >= lastXP then
            gained = xp - lastXP
        else
            gained = (lastXPMax - lastXP) + xp -- wrapped past a level
        end
        if gained > 0 then Store.Count("xp", gained) end
    end
    lastXP, lastXPMax = xp, xpMax
end
