-- Core/Days.lua
-- PURE: no WoW globals. Daily buckets keyed "YYYY-MM-DD" in the player's local date,
-- plus date-range helpers. Date functions are passed in (os.date/os.time in tests,
-- date/time in game) so this stays testable.

local _, ns = ...

local Days = {}
ns.Days = Days

Days.KEEP = 90 -- days of daily buckets kept

function Days.Key(epoch, dateFn)
    return dateFn("%Y-%m-%d", epoch)
end

-- Shift a day key by `delta` days. Uses local noon so DST changes cannot skip a day.
function Days.Shift(key, delta, timeFn, dateFn)
    local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
    local t = timeFn({ year = tonumber(y), month = tonumber(m), day = tonumber(d) + delta, hour = 12 })
    return dateFn("%Y-%m-%d", t)
end

function Days.Add(days, key, field, n)
    local day = days[key]
    if not day then
        day = {}
        days[key] = day
    end
    day[field] = (day[field] or 0) + (n or 1)
    return day
end

-- Remove buckets older than `keep` days before todayKey (todayKey counts as day 1).
function Days.Prune(days, todayKey, keep, timeFn, dateFn)
    local cutoff = Days.Shift(todayKey, -((keep or Days.KEEP) - 1), timeFn, dateFn)
    local removed = 0
    for key in pairs(days) do
        if key < cutoff then
            days[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Range names used by the UI.
Days.RANGES = { "today", "week", "month", "all" }
local RANGE_DAYS = { today = 1, week = 7, month = 30 }

-- First day key of a range ending today, or nil for "all".
function Days.RangeStart(range, todayKey, timeFn, dateFn)
    local n = RANGE_DAYS[range]
    if not n then return nil end
    return Days.Shift(todayKey, -(n - 1), timeFn, dateFn)
end

-- Sum every numeric field of the buckets with fromKey <= key <= toKey (nil = open end).
function Days.Sum(days, fromKey, toKey)
    local total = {}
    for key, day in pairs(days) do
        if (not fromKey or key >= fromKey) and (not toKey or key <= toKey) then
            for field, v in pairs(day) do
                if type(v) == "number" then total[field] = (total[field] or 0) + v end
            end
        end
    end
    return total
end

-- Remove list entries whose `field` timestamp is older than now - seconds.
function Days.PruneList(list, field, now, seconds)
    local kept = {}
    for _, item in ipairs(list) do
        if (item[field] or 0) >= now - seconds then kept[#kept + 1] = item end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, item in ipairs(kept) do list[i] = item end
    return list
end
