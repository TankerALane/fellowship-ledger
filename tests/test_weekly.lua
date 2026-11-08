-- The weekly recap (Core/Weekly.lua, D-109): reset times, last week's rows, the notice.
local H = ...

H.test("weekly: the last reset from the game, else Tuesday 16:00 UTC (8:00 PST)", function()
    local W = H.pureNamespace().Weekly
    local now = 1794200000
    H.eq(W.LastReset(now, 3600), now + 3600 - W.WEEK, "the game's seconds until the next reset")
    local last = W.LastReset(now, nil)
    H.ok(last <= now and now - last < W.WEEK, "within the last week")
    H.eq(os.date("!%A %H:%M", last), "Tuesday 16:00")
    H.eq(W.LastReset(last, nil), last, "exactly at the reset")
    H.eq(W.LastReset(last - 1, nil), last - W.WEEK, "a second before")
    H.eq(W.LastReset(now, 0), last, "a zero from the game falls back")
end)

H.test("weekly: rows for last week, you first, quiet friends and blocked ones left out", function()
    local ns = H.pureNamespace()
    local W, L = ns.Weekly, ns.L
    local mine = { ["Me-R"] = { days = { ["2026-11-03"] = { quests = 5, active = 3600, levels = 1 },
        ["2026-11-10"] = { quests = 99, active = 99 } } } }
    local friends = {
        ["bn:Ham#1"] = { name = "Hamlet", characters = { ["Ca-R"] = { days = { ["2026-11-05"] = { quests = 9, active = 7200, dungeonsCompleted = 2 } } } } },
        ["bn:Rom#1"] = { name = "Romadom", characters = { ["Ro-R"] = { days = { ["2026-11-09"] = { quests = 1, active = 600 } } } } },
        ["bn:Qui#1"] = { name = "Quiet", characters = { ["Q-R"] = { days = {} } } },
        ["bn:Blk#1"] = { name = "Blocked", tag = "Blk#1", characters = { ["X-R"] = { days = { ["2026-11-05"] = { quests = 3, active = 60 } } } } },
    }
    local rows = W.Rows(mine, friends, { ["Blk#1"] = true }, "2026-11-03", "2026-11-09", L)
    H.eq(#rows, 3)
    H.eq(rows[1].name, "You"); H.eq(rows[1].quests, 5, "this week's day is not last week")
    H.eq(rows[2].name, "Hamlet"); H.eq(rows[3].name, "Romadom", "most active first")
    H.eq(W.Line(rows[2], L), "Hamlet: 0 level(s), 9 quest(s), 2 dungeon(s), 2h 00m active")
    local title, lines = W.Notice(rows, L)
    H.eq(title, "Last week in your ledger"); H.eq(#lines, 3)
    H.eq(W.Notice({}, L), nil, "nothing played: no notice")
    local many = {}
    for i = 1, 8 do many[i] = { name = "F" .. i, levels = 0, quests = 1, dungeons = 0, active = 60 } end
    _, lines = W.Notice(many, L)
    H.eq(#lines, 5); H.eq(lines[5], "...and 4 more. Click for everyone.")
end)

H.test("weekly: due once per reset, and off by its switch", function()
    local W = H.pureNamespace().Weekly
    H.ok(W.Due({}, nil, 100), "never shown")
    H.ok(not W.Due({}, 100, 100), "shown for this reset")
    H.ok(W.Due({}, 100, 100 + W.WEEK), "a new reset")
    H.ok(not W.Due({ weeklyRecap = false }, nil, 100))
    H.eq(select(1, W.Range(1794326400, function(f, t) return os.date("!" .. f, t) end)), os.date("!%Y-%m-%d", 1794326400 - W.WEEK))
end)
