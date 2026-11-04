local H = ...

local T = function(y, m, d, h) return os.time({ year = y, month = m, day = d, hour = h or 12 }) end

H.test("day key and shifting across month and year ends", function()
    local D = H.pureNamespace().Days
    H.eq(D.Key(T(2026, 11, 4, 23), os.date), "2026-11-04")
    H.eq(D.Shift("2026-11-04", -6, os.time, os.date), "2026-10-29")
    H.eq(D.Shift("2026-01-01", -1, os.time, os.date), "2025-12-31")
    H.eq(D.Shift("2024-02-28", 1, os.time, os.date), "2024-02-29")
end)

H.test("Add, Sum and ranges", function()
    local D = H.pureNamespace().Days
    local days = {}
    D.Add(days, "2026-11-04", "quests", 3)
    D.Add(days, "2026-11-04", "quests")
    D.Add(days, "2026-11-01", "quests", 2)
    D.Add(days, "2026-10-01", "quests", 10)
    D.Add(days, "2026-10-01", "moneyNet", -50)
    H.eq(days["2026-11-04"].quests, 4)
    local today = "2026-11-04"
    H.eq(D.Sum(days, D.RangeStart("today", today, os.time, os.date), today).quests, 4)
    H.eq(D.Sum(days, D.RangeStart("week", today, os.time, os.date), today).quests, 6)
    H.eq(D.Sum(days, D.RangeStart("month", today, os.time, os.date), today).quests, 6)
    local all = D.Sum(days, D.RangeStart("all", today, os.time, os.date), today)
    H.eq(all.quests, 16)
    H.eq(all.moneyNet, -50)
end)

H.test("Prune keeps exactly 90 days", function()
    local D = H.pureNamespace().Days
    local days = {}
    local today = "2026-11-04"
    for i = 0, 99 do days[D.Shift(today, -i, os.time, os.date)] = { quests = 1 } end
    local removed = D.Prune(days, today, 90, os.time, os.date)
    H.eq(removed, 10)
    H.ok(days[D.Shift(today, -89, os.time, os.date)])
    H.eq(days[D.Shift(today, -90, os.time, os.date)], nil)
end)

H.test("PruneList drops old entries in place", function()
    local D = H.pureNamespace().Days
    local list = { { at = 10 }, { at = 500 }, { at = 1000 } }
    D.PruneList(list, "at", 1000, 600)
    H.eq(#list, 2)
    H.eq(list[1].at, 500)
end)

H.test("session split rule: reload and short relog continue, 30+ minutes starts new", function()
    local S = H.pureNamespace().Sessions
    H.ok(S.ShouldStartNew(nil, 1000))
    H.ok(not S.ShouldStartNew(1000, 1010))
    H.ok(not S.ShouldStartNew(1000, 1000 + 1800))
    H.ok(S.ShouldStartNew(1000, 1000 + 1801))
end)

H.test("session counters and pruning", function()
    local S = H.pureNamespace().Sessions
    local s = S.New(1, 100, { level = 5, money = 10 })
    S.Add(s, "quests")
    S.Add(s, "quests", 2)
    H.eq(s.counts.quests, 3)
    H.eq(s.levelStart, 5)
    local now = 200 * 86400
    local list = { { start = 0, stop = 0 }, { start = now - 100, stop = now - 50 } }
    S.Prune(list, now)
    H.eq(#list, 1)
    local only = { { start = 0, stop = 0 } }
    S.Prune(only, now)
    H.eq(#only, 1, "newest is always kept")
end)
