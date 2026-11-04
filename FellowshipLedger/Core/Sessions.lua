-- Core/Sessions.lua
-- PURE: no WoW globals. A session runs from login to logout. A /reload, or a relog
-- within GAP seconds, continues the same session; a longer break starts a new one.

local _, ns = ...

local Sessions = {}
ns.Sessions = Sessions

Sessions.GAP = 1800                 -- 30 minutes offline starts a new session
Sessions.KEEP_SECONDS = 90 * 86400  -- sessions kept for 90 days

function Sessions.ShouldStartNew(lastSeen, now)
    return lastSeen == nil or now - lastSeen > Sessions.GAP
end

-- snapshot: { level, money }
function Sessions.New(id, now, snapshot)
    snapshot = snapshot or {}
    return {
        id = id,
        start = now,
        stop = now,
        played = 0,
        active = 0,
        levelStart = snapshot.level,
        levelEnd = snapshot.level,
        moneyStart = snapshot.money,
        counts = {}, -- same field names as the daily buckets (levels, quests, xp, moneyNet, ...)
    }
end

function Sessions.Add(session, field, n)
    session.counts[field] = (session.counts[field] or 0) + (n or 1)
end

-- Keep sessions that ended within KEEP_SECONDS; always keep the newest one.
function Sessions.Prune(list, now)
    local newest = list[#list]
    local kept = {}
    for _, s in ipairs(list) do
        if s == newest or (s.stop or s.start or 0) >= now - Sessions.KEEP_SECONDS then kept[#kept + 1] = s end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, s in ipairs(kept) do list[i] = s end
    return list
end
