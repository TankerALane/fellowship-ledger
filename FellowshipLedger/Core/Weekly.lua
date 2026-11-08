-- Core/Weekly.lua
-- PURE: no WoW globals. The weekly recap (D-109): after the weekly reset, the first
-- login shows last week (reset to reset) for you and each friend, once per reset.
--
-- The reset time comes from the game when it says (C_DateAndTime.
-- GetSecondsUntilWeeklyReset, so other regions get their own reset); else Tuesday
-- 8:00 PST (16:00 UTC), as Austin asked. Days are counted by the ledger's day keys:
-- last week is the reset's day up to the day before this reset's day.

local _, ns = ...

local Weekly = {}
ns.Weekly = Weekly

Weekly.WEEK = 7 * 86400
Weekly.FALLBACK_ANCHOR = 5 * 86400 + 16 * 3600 -- Tuesday 1970-01-06 16:00 UTC (8:00 PST)
Weekly.MAX_LINES = 5

-- The most recent reset at or before `now`. untilNext: seconds until the next reset
-- (the game's number), or nil to use the fallback.
function Weekly.LastReset(now, untilNext)
    untilNext = tonumber(untilNext)
    if untilNext and untilNext > 0 and untilNext <= Weekly.WEEK then
        return now + math.floor(untilNext) - Weekly.WEEK
    end
    local a = Weekly.FALLBACK_ANCHOR
    return a + math.floor((now - a) / Weekly.WEEK) * Weekly.WEEK
end

-- Last week's day keys: from the previous reset's day to the day before this reset's.
function Weekly.Range(lastReset, dateFn)
    return dateFn("%Y-%m-%d", lastReset - Weekly.WEEK), dateFn("%Y-%m-%d", lastReset - 1)
end

local function total(chars, fromKey, toKey)
    local t = { levels = 0, quests = 0, dungeons = 0, active = 0, deaths = 0 }
    for _, c in pairs(chars or {}) do
        local s = ns.Days.Sum(c.days or {}, fromKey, toKey)
        t.levels = t.levels + (s.levels or 0)
        t.quests = t.quests + (s.quests or 0)
        t.dungeons = t.dungeons + (s.dungeonsCompleted or 0)
        t.active = t.active + (s.active or 0)
        t.deaths = t.deaths + (s.deaths or 0)
    end
    return t
end

-- Rows for last week: you first (your characters), then friends who played, most
-- active first. Blocked friends are left out. Nobody who did nothing is listed.
function Weekly.Rows(myChars, friends, blocklist, fromKey, toKey, L)
    local out = {}
    local me = total(myChars, fromKey, toKey)
    if me.active > 0 or me.quests > 0 or me.levels > 0 then
        me.name, me.isMe = L.WEEKLY_YOU, true
        out[1] = me
    end
    local list = {}
    for id, f in pairs(friends or {}) do
        if not ns.FriendsModel.IsBlocked(blocklist, f) then
            local t = total(f.characters, fromKey, toKey)
            if t.active > 0 or t.quests > 0 or t.levels > 0 then
                t.name, t.id = f.name or id, id
                list[#list + 1] = t
            end
        end
    end
    table.sort(list, function(a, b)
        if a.active ~= b.active then return a.active > b.active end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    for _, t in ipairs(list) do out[#out + 1] = t end
    return out
end

function Weekly.Line(t, L)
    return string.format(L.WEEKLY_LINE, t.name, t.levels, t.quests, t.dungeons, ns.Format.Duration(t.active))
end

-- The notice: title and up to MAX_LINES lines ("...and 3 more"). nil when empty.
function Weekly.Notice(rows, L)
    if #(rows or {}) == 0 then return nil end
    local lines = {}
    local shown = #rows > Weekly.MAX_LINES and Weekly.MAX_LINES - 1 or #rows
    for i = 1, shown do lines[i] = Weekly.Line(rows[i], L) end
    if shown < #rows then lines[#lines + 1] = string.format(L.WEEKLY_MORE, #rows - shown) end
    return L.WEEKLY_RECAP_TITLE, lines
end

-- Is a recap due? seen: the reset already shown (db.weeklyRecapSeen).
function Weekly.Due(settings, seen, lastReset)
    if settings and settings.weeklyRecap == false then return false end
    return not seen or seen < lastReset
end
