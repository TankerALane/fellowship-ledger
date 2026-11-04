-- Core/Clock.lua
-- PURE: no WoW globals. Played time and active time for one character.
--
-- played: seconds logged in (advances while the addon runs).
-- active: played time with idle stretches removed. Time since the last activity
--         signal is held as "pending". The next activity signal commits it as
--         active. If IDLE seconds pass with no signal first, the whole pending
--         stretch is thrown away, not just the part after 5 minutes (D-014).
--         Going AFK keeps pending time only if there was activity in the last
--         AFK_COMMIT seconds (a typed /afk); the game's own auto-AFK, which comes
--         after 5 idle minutes, never counts.
--
-- All times are whole epoch seconds. Functions that move the clock return the
-- (dPlayed, dActive) they added, so callers can add the same amounts to day
-- buckets and the current session.

local _, ns = ...

local Clock = {}
ns.Clock = Clock

Clock.IDLE = 300       -- 5 minutes without activity = idle, and the whole stretch is removed
Clock.AFK_COMMIT = 60  -- going AFK within this many seconds of activity keeps that time
Clock.MAX_STEP = 900   -- a gap longer than this between ticks (sleep, freeze) counts as nothing

function Clock.New(now)
    return { played = 0, active = 0, pending = 0, last = now, lastActivity = now }
end

local function commit(c)
    local da = c.pending or 0
    c.active = (c.active or 0) + da
    c.pending = 0
    return da
end

-- Move the clock forward to `now`. Never adds active time by itself.
function Clock.Advance(c, now)
    local last = c.last or now
    if now <= last then return 0, 0 end
    local d = now - last
    c.last = now
    if d > Clock.MAX_STEP then
        c.pending = 0
        c.lastActivity = nil
        return 0, 0
    end
    c.played = (c.played or 0) + d
    if c.lastActivity then
        if now - c.lastActivity <= Clock.IDLE then
            c.pending = (c.pending or 0) + d
        else
            c.pending = 0          -- idle: drop the whole quiet stretch
            c.lastActivity = nil
        end
    end
    return d, 0
end

-- An activity signal (movement, combat, quest, loot, ...): commit pending time.
function Clock.Touch(c, now)
    local dp = Clock.Advance(c, now)
    local da = c.lastActivity and commit(c) or 0
    c.pending = 0
    c.lastActivity = now
    return dp, da
end

-- AFK flag turned on.
function Clock.Idle(c, now)
    local dp = Clock.Advance(c, now)
    local da = 0
    if c.lastActivity and now - c.lastActivity <= Clock.AFK_COMMIT then
        da = commit(c)
    end
    c.pending = 0
    c.lastActivity = nil
    return dp, da
end

-- After loading (login or reload): the time the addon was not running is not played.
-- Time pending from before a /reload is committed (reloading is something you did).
function Clock.Resume(c, now)
    local da = commit(c)
    c.last = now
    c.lastActivity = now
    return 0, da
end

-- Active time including the not-yet-committed stretch (for live displays).
function Clock.ActiveNow(c)
    return (c.active or 0) + (c.pending or 0)
end
