-- Core/Clock.lua
-- PURE: no WoW globals. Played time and active time for one character.
--
-- played: seconds logged in (advances while the addon runs).
-- active: played time minus idle time. Time counts as active for up to IDLE seconds
--         after the last activity signal; after that it stops until the next signal.
--         Going AFK (Idle) stops it at once.
--
-- All times are whole epoch seconds. Every function that moves the clock returns the
-- (dPlayed, dActive) it added, so callers can add the same amounts to day buckets
-- and the current session.

local _, ns = ...

local Clock = {}
ns.Clock = Clock

Clock.IDLE = 300      -- 5 minutes without activity = idle
Clock.MAX_STEP = 900  -- a gap longer than this between ticks (sleep, freeze) counts as nothing

function Clock.New(now)
    return { played = 0, active = 0, last = now, lastActivity = now }
end

-- Move the clock forward to `now`.
function Clock.Advance(c, now)
    local last = c.last or now
    if now <= last then return 0, 0 end
    local d = now - last
    c.last = now
    if d > Clock.MAX_STEP then return 0, 0 end
    local dActive = 0
    if c.lastActivity then
        local activeEnd = c.lastActivity + Clock.IDLE
        if activeEnd > now then activeEnd = now end
        if activeEnd > last then dActive = activeEnd - last end
    end
    c.played = (c.played or 0) + d
    c.active = (c.active or 0) + dActive
    return d, dActive
end

-- An activity signal (movement, combat, quest, loot, ...).
function Clock.Touch(c, now)
    local dp, da = Clock.Advance(c, now)
    c.lastActivity = now
    return dp, da
end

-- AFK: stop counting active time until the next Touch.
function Clock.Idle(c, now)
    local dp, da = Clock.Advance(c, now)
    c.lastActivity = nil
    return dp, da
end

-- After loading (login or reload): the time the addon was not running is not played.
function Clock.Resume(c, now)
    c.last = now
    c.lastActivity = now
end
