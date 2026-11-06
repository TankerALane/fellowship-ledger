-- Pure Phase 2 models: fake data, graph scaling and series, friends grouping,
-- settings defaults, session summary, quest-chain logic, palettes, totals.
local H = ...

local NOW = os.time({ year = 2026, month = 11, day = 4, hour = 12 })

local function fake(ns) return ns.FakeData.Generate(NOW, os.time, os.date) end

H.test("fake data is deterministic, separate and complete", function()
    local ns = H.pureNamespace()
    local a, b = fake(ns), fake(ns)
    H.eq(ns.Export.Build(a, "x", "t"), ns.Export.Build(b, "x", "t"), "same seed, same world")
    local mine = 0
    for _, c in pairs(a.characters) do
        mine = mine + 1
        H.eq(c.fake, true)
        H.ok(#c.sessions > 10, "plenty of sessions")
        H.ok(next(c.levels), "levels recorded")
    end
    H.eq(mine, 3)
    local bnet, charOnly = 0, 0
    for _, f in pairs(a.friends) do
        H.eq(f.fake, true)
        local n = 0
        for _, c in pairs(f.characters) do n = n + 1; H.eq(c.fake, true) end
        if f.kind == "bnet" then
            bnet = bnet + 1
            H.ok(n >= 2, "several characters per Battle.net friend")
        else
            charOnly = charOnly + 1
        end
    end
    H.eq(bnet, 3)
    H.eq(charOnly, 1)
end)

H.test("fake data covers 90 days and its numbers add up", function()
    local ns = H.pureNamespace()
    local c = fake(ns).characters["Aelwyn-Fakerealm"]
    local oldest, newest = "9999", "0000"
    for key in pairs(c.days) do
        if key < oldest then oldest = key end
        if key > newest then newest = key end
    end
    H.ok(oldest >= ns.Days.Shift("2026-11-04", -89, os.time, os.date), "no older than 90 days: " .. oldest)
    H.ok(newest <= "2026-11-04")
    local dayPlayed, sessPlayed = 0, 0
    for _, d in pairs(c.days) do dayPlayed = dayPlayed + (d.played or 0) end
    for _, s in ipairs(c.sessions) do sessPlayed = sessPlayed + s.played end
    H.eq(dayPlayed, sessPlayed)
    local prev = 0
    for to = 2, c.level do
        H.ok(c.levels[to], "level " .. to .. " recorded")
        H.ok(c.levels[to].at >= prev, "levels in time order")
        prev = c.levels[to].at
    end
end)

H.test("nice axis scales", function()
    local G = H.pureNamespace().GraphModel
    local lo, hi, step = G.NiceScale(0, 7)
    H.eq(lo, 0); H.eq(hi, 8); H.eq(step, 2)
    lo, hi, step = G.NiceScale(-350, 1200)
    H.ok(lo <= -350 and hi >= 1200 and step > 0)
    H.eq((hi - lo) % step, 0)
    lo, hi = G.NiceScale(0, 0)
    H.ok(hi > lo, "empty data still has an axis")
    local layout = G.Layout({ { value = -50 }, { value = 150 } }, 200)
    H.ok(layout.zeroY > 0 and layout.zeroY < 200)
    local y, h = layout.bar(-50)
    H.ok(y < layout.zeroY and math.abs(y + h - layout.zeroY) < 1e-6, "negative bars hang below zero")
end)

H.test("the friends table sorts by any column and keeps characters under their friend", function()
    local ns = H.pureNamespace()
    local friends = {
        ["bn:A"] = { kind = "bnet", name = "Ann", characters = {
            ["Low-R"] = { name = "Low", level = 5, days = {} }, ["High-R"] = { name = "High", level = 50, days = {} } } },
        ["bn:B"] = { kind = "bnet", name = "Bea", characters = { ["Mid-R"] = { name = "Mid", level = 30, days = {} } } },
        ["ch:Solo-R"] = { kind = "char", name = "Solo-R", characters = { ["Solo-R"] = { name = "Solo", level = 40, days = {} } } },
        ["bn:E"] = { kind = "bnet", name = "Empty", characters = {} },
    }
    local function order(field, desc)
        local rows = ns.FriendsModel.Build(friends, {}, "all", "2026-11-04", os.time, os.date, field, desc)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.header and ("[" .. r.friend.name .. "]") or r.name end
        return table.concat(out, " ")
    end
    H.eq(order("level", true), "[Ann] High Low Solo [Bea] Mid [Empty]")
    H.eq(order("level", false), "[Ann] Low High [Bea] Mid Solo [Empty]")
    H.eq(order("name", false), "[Ann] High Low [Bea] Mid [Empty] Solo")
    H.eq(order(nil), "[Ann] High Low [Bea] Mid [Empty] Solo", "default: Battle.net first, by name")
end)

H.test("friend row tooltip: level, race and class, faction, times and their version", function()
    local ns = H.pureNamespace()
    local now = 100000
    local title, lines = ns.FriendsModel.Tooltip({ name = "Mid", level = 30 },
        { level = 30, race = "NightElf", class = "DEATHKNIGHT", lastSeen = now - 7200 },
        { lastUpdated = now - 300, version = "1.0.1" }, now, ns.L, "Alliance")
    H.eq(title, "Mid")
    H.eq(lines[1], "Level 30 Night Elf Death Knight")
    H.eq(lines[2], "Faction: Alliance")
    H.eq(lines[3], "Last played: 2h ago")
    H.eq(lines[4], "Shared with you: 5m ago")
    H.eq(lines[5], "Their Fellowship Ledger: 1.0.1")
    H.eq(ns.FriendsModel.TokenText(ns.L, "RACE_", "Scourge"), "Undead")
    H.eq(ns.FriendsModel.TokenText(ns.L, "CLASS_", "WARRIOR"), "Warrior")
    local _, few = ns.FriendsModel.Tooltip({ name = "X", level = 3 }, nil, nil, now, ns.L, "")
    H.eq(few[1], "Level 3")
    H.eq(#few, 3, "no faction or version lines when unknown")
end)

H.test("graph series for every chart", function()
    local ns = H.pureNamespace()
    local c = fake(ns).characters["Aelwyn-Fakerealm"]
    for _, chart in ipairs(ns.GraphModel.CHARTS) do
        local pts = ns.GraphModel.Build(chart, c, "2026-11-04", os.time, os.date, 30)
        H.ok(#pts > 0 and #pts <= math.max(30, ns.GraphModel.MAX_POINTS), chart)
        for _, p in ipairs(pts) do H.ok(type(p.value) == "number" and p.label, chart .. " point shape") end
        H.ok(ns.GraphModel.FormatValue(chart, pts[1].value))
    end
    H.eq(#ns.GraphModel.QuestsPerDay(c, "2026-11-04", 30, os.time, os.date), 30)
    local tpl = ns.GraphModel.TimePerLevel({ levels = { [3] = { from = 2, to = 3, active = 60, total = 70, partial = true } } })
    H.eq(tpl[1].partial, true)
    H.eq(tpl[1].label, "3")
end)

H.test("friends are grouped, ordered and blockable", function()
    local ns = H.pureNamespace()
    local friends = fake(ns).friends
    local rows, hidden = ns.FriendsModel.Build(friends, {}, "all", "2026-11-04", os.time, os.date)
    H.eq(hidden, 0)
    H.ok(rows[1].header, "Battle.net friends come first, under a header")
    local headers, standalone = 0, 0
    for _, r in ipairs(rows) do
        if r.header then headers = headers + 1 elseif not r.indent then standalone = standalone + 1 end
    end
    H.eq(headers, 3)
    H.eq(standalone, 1, "the character-only friend stands alone")
    local blocked = { ["Fennick#0001"] = true, ["Wren-Fakerealm"] = true }
    local rows2, hidden2 = ns.FriendsModel.Build(friends, blocked, "all", "2026-11-04", os.time, os.date)
    H.eq(hidden2, 2)
    for _, r in ipairs(rows2) do
        H.ok(not (r.header and r.friend.name == "Fennick"), "blocked friend hidden")
        H.ok(r.name ~= "Wren", "blocked character friend hidden")
    end
    H.eq(ns.FriendsModel.Ago(1000, nil), "never")
    H.eq(ns.FriendsModel.Ago(1000, 990), "just now")
    H.eq(ns.FriendsModel.Ago(10000, 10000 - 7200), "2h ago")
end)

H.test("the character a friend is playing is marked and listed first", function()
    local ns = H.pureNamespace()
    local friends = fake(ns).friends
    local rows = ns.FriendsModel.Build(friends, {}, "all", "2026-11-04", os.time, os.date)
    local marked, afterHeader = {}, {}
    local last
    for _, r in ipairs(rows) do
        if r.playing then marked[#marked + 1] = r.name end
        if last and last.header and not r.header then afterHeader[last.friend.name] = r end
        last = r
    end
    H.eq(#marked, 2, "Fennick and Tobin are each on one character")
    H.eq(afterHeader.Fennick.name, "Grimwald", "the character being played comes first")
    H.eq(afterHeader.Tobin.name, "Lune", "even when another character has a higher level")
    H.ok(not afterHeader.Marisol.playing, "an offline friend plays nothing")
    -- Battle.net names may differ from keys in spaces, hyphens and case.
    H.ok(ns.FriendsModel.IsPlaying({ online = true, playing = "first last" }, "First-Last"))
    H.ok(not ns.FriendsModel.IsPlaying({ online = false, playing = "First-Last" }, "First-Last"))
    H.ok(not ns.FriendsModel.IsPlaying({ online = true }, "First-Last"))
    local _, lines = ns.FriendsModel.Tooltip({ name = "Lune", playing = true }, {}, {}, 1000, ns.L)
    H.ok(table.concat(lines, "|"):find(ns.L.TIP_PLAYING_NOW, 1, true), "tooltip says playing now")
end)

H.test("Last played says now only for a fresh update of the character being played", function()
    local ns = H.pureNamespace()
    local LP = ns.FriendsModel.LastPlayed
    H.eq((LP(10000, { playing = true, lastUpdated = 10000 - 30, lastSeen = 9000 })), "now")
    H.eq((LP(10000, { playing = true, lastUpdated = 10000 - 600, lastSeen = 10000 - 600 })), "10m ago", "stale: show the time")
    H.eq((LP(10000, { playing = nil, lastUpdated = 10000, lastSeen = 10000 - 7200 })), "2h ago", "another character: when it was played")
    H.eq((LP(10000, { lastSeen = nil })), "never")
    -- Sorting by the column puts the character being played first.
    local friends = fake(ns).friends
    local rows = ns.FriendsModel.Build(friends, {}, "all", "2026-11-04", os.time, os.date, "lastPlayed", true)
    for i, r in ipairs(rows) do
        if r.header and r.friend.name == "Tobin" then H.eq(rows[i + 1].name, "Lune") end
    end
end)

H.test("settings defaults fill gaps and keep choices", function()
    local D = H.pureNamespace().SettingsDefaults
    local s = D.Ensure({ skin = "plain", colorblind = false })
    H.eq(s.skin, "plain")
    H.eq(s.colorblind, false)
    H.eq(s.levelToast, true)
    H.eq(s.shareNameInDungeons, false, "name sharing is opt-in")
    H.eq(s.sharingPaused, false)
    H.eq(s.minimap.angle, 225)
    H.eq(D.ClampScale(0.2), 0.7)
    H.eq(D.ClampScale(9), 1.5)
    H.eq(D.ClampScale(1.04), 1.0)
end)

H.test("session summary lines", function()
    local ns = H.pureNamespace()
    local s = { start = NOW, played = 3600, active = 3000, levelStart = 10, levelEnd = 12,
        counts = { levels = 2, quests = 5, moneyNet = 12345, dungeonsEntered = 1, dungeonsCompleted = 1 } }
    local title, lines = ns.Summary.Session(s, ns.L, os.date)
    H.ok(title:find("Session of 2026-11-04", 1, true), title)
    local text = table.concat(lines, "\n")
    H.ok(text:find("Played 1h 00m, active 50m 00s", 1, true), text)
    H.ok(text:find("2 level(s): 10 -> 12", 1, true))
    H.ok(text:find("+1g 23s 45c", 1, true))
    H.ok(text:find("1 completed of 1 entered", 1, true))
    H.ok(not text:find("death"), "zero counts are left out")
end)

H.test("quest chain steps and walking", function()
    local Q = H.pureNamespace().QuestChainLogic
    H.eq(select(1, Q.StepOf({ 5, 6, 7 }, 6)), 2)
    H.eq(select(2, Q.StepOf({ 5, 6, 7 }, 6)), 3)
    H.eq(Q.StepOf({ 5 }, 9), nil)
    local links = { [1] = { n = 2 }, [2] = { p = 1, n = 3 }, [3] = { p = 2 } }
    local chain = Q.Walk(2, function(id) return links[id].p end, function(id) return links[id].n end)
    H.eq(table.concat(chain, ","), "1,2,3")
    local loop = Q.Walk(1, function() return 1 end, function(id) return id == 1 and 2 or 1 end)
    H.eq(table.concat(loop, ","), "1,2", "loops stop")
end)

H.test("palettes cover every role; series cycle", function()
    local P = H.pureNamespace().Palette
    for name, set in pairs(P.SKINS) do
        for _, role in ipairs(P.ROLES) do H.ok(set[role], name .. " lacks " .. role) end
    end
    H.ok(P.Series(true, 1) ~= P.Series(true, 2))
    H.eq(P.Series(true, 7), P.Series(true, 1))
    H.eq(P.Color("nonsense", "text"), P.SKINS.ledger.text)
end)

H.test("totals line sums every character", function()
    local ns = H.pureNamespace()
    local rows = { { key = "a", level = 10, quests = 3, moneyNet = 50, dungeons = 1, dungeonsEntered = 2 },
                   { key = "b", level = 20, quests = 4, moneyNet = -20, dungeons = 0, dungeonsEntered = 1 } }
    local t = ns.MeModel.Totals(rows)
    H.eq(t.quests, 7)
    H.eq(t.moneyNet, 30)
    H.eq(ns.MeModel.FormatCell({ field = "dungeons", kind = "pair" }, t), "1/3")
    H.eq(ns.MeModel.FormatCell({ field = "dungeons", kind = "pair" }, { dungeons = 0, dungeonsEntered = 0 }), "-", "none entered")
    H.eq(ns.MeModel.FormatCell({ field = "dungeons", kind = "pair" }, { dungeons = 0, dungeonsEntered = 2 }), "0/2")
end)

H.test("faction column: Horde or Alliance per character, blank on the totals line", function()
    local ns = H.pureNamespace()
    local rows = ns.MeModel.Build({
        h = { name = "Grak", faction = "Horde", days = {} },
        a = { name = "Lia", faction = "Alliance", days = {} },
        old = { name = "Old", days = {} },
    }, "all", "2026-11-05", os.time, os.date)
    local col
    for _, c in ipairs(ns.MeModel.COLUMNS) do if c.field == "faction" then col = c end end
    H.ok(col, "the Me table has a Faction column")
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = ns.MeModel.FormatCell(col, r) end
    H.eq(byKey.h, "Horde")
    H.eq(byKey.a, "Alliance")
    H.eq(byKey.old, "")
    H.eq(ns.MeModel.FormatCell(col, ns.MeModel.Totals(rows)), "")
end)

H.test("class colors are readable on every skin; priest is grey on ledger, white on the dark looks", function()
    local P = H.pureNamespace().Palette
    for class in pairs(P.CLASS) do
        for skin in pairs(P.SKINS) do
            local c = P.ClassColor(class, skin)
            H.ok(P.Contrast(c, P.Color(skin, "bg")) >= P.MIN_CONTRAST, class .. " on " .. skin)
        end
    end
    local priest = P.ClassColor("PRIEST", "ledger")
    H.ok(priest[1] < 0.6 and math.abs(priest[1] - priest[3]) < 0.01, "priest is a grey on ledger")
    H.eq(P.Code(P.ClassColor("PRIEST", "plain")), "|cffffffff")
    H.eq(P.Code(P.ClassColor("PRIEST", "leather")), "|cffffffff", "dark leather: priest stays white")
    H.ok(P.IsLight("ledger") and not P.IsLight("leather") and not P.IsLight("plain"))
    local S = H.pureNamespace().SettingsDefaults
    H.eq(S.Ensure({}).skin, "ledger", "the light look is the default")
    H.eq(S.Ensure({ skin = "parchment" }).skin, "ledger", "dev-build parchment becomes ledger")
    H.eq(S.Ensure({ skin = "leather" }).skin, "leather")
    H.eq(P.Code(P.ClassColor("MAGE", "plain")), "|cff3fc7eb", "already readable: unchanged")
    H.eq(P.ClassColor("NOTACLASS", "ledger"), nil)
    H.eq(P.ClassColor(nil, "ledger"), nil)
end)

H.test("every text color is readable on its skin background (4.5:1)", function()
    local P = H.pureNamespace().Palette
    for skin, set in pairs(P.SKINS) do
        for _, role in ipairs({ "text", "muted", "heading", "good", "bad" }) do
            local c = P.Contrast(set[role], set.bg)
            H.ok(c >= P.MIN_CONTRAST, string.format("%s %s on bg: %.2f", skin, role, c))
        end
    end
end)

H.test("count charts use whole-number steps; labels are spaced to fit", function()
    local G = H.pureNamespace().GraphModel
    local lo, hi, step = G.NiceScale(0, 2, 4, true)
    H.eq(step, 1); H.eq(lo, 0); H.eq(hi, 2)
    H.ok(G.IsInteger("levelsPerSession") and G.IsInteger("questsPerDay"))
    H.ok(not G.IsInteger("goldPerSession"))
    H.eq(G.LabelEvery(40, 2000), 1)
    H.eq(G.LabelEvery(40, 1900), 2)
    H.eq(G.LabelEvery(40, 800), 3)
    H.eq(G.LabelEvery(40, 0), 40)
end)

H.test("columns stretch, shrink, then drop from the right", function()
    local Lay = H.pureNamespace().Layout
    local cols = { { width = 150 }, { width = 50 }, { width = 50 }, { width = 50 } } -- 300 + 3 gaps = 312
    local w, n = Lay.FitColumns(cols, 400, 4)
    H.eq(n, 4)
    H.ok(w[1] > 150, "stretches when there is room")
    w, n = Lay.FitColumns(cols, 260, 4)
    H.eq(n, 4)
    local total = w[1] + w[2] + w[3] + w[4] + 12
    H.ok(total <= 260, "shrinks to fit: " .. total)
    w, n = Lay.FitColumns(cols, 160, 4)
    H.ok(n < 4 and w[4] == nil, "right-most columns dropped")
    local used = 0
    for i = 1, n do used = used + w[i] end
    H.ok(used + 4 * (n - 1) <= 160, "what remains fits")
    w, n = Lay.FitColumns(cols, 10, 4)
    H.eq(n, 1, "the name column is never dropped")
end)

H.test("axis labels are short and steps are round (gold, time)", function()
    local ns = H.pureNamespace()
    local F, G = ns.Format, ns.GraphModel
    H.eq(F.MoneyShort(60000, true), "+6g")
    H.eq(F.MoneyShort(25000, true), "+2.5g")
    H.eq(F.MoneyShort(-20000, true), "-2g")
    H.eq(F.MoneyShort(5000, true), "+50s")
    H.eq(F.MoneyShort(0, true), "0")
    H.eq(F.DurationShort(1800), "30m")
    H.eq(F.DurationShort(5400), "1h 30m")
    H.eq(F.DurationShort(7200), "2h")
    local lo, hi, step = G.NiceDurationScale(0, 7980) -- 2h 13m of data
    H.eq(step, 3600); H.eq(hi, 10800)
    lo, hi, step = G.NiceDurationScale(0, 2500)
    H.eq(step, 900, "15-minute steps")
    for v = lo, hi, step do H.ok(v % 60 == 0, "round minutes") end
    local layout = G.Layout({ { value = 7980 } }, 300, false, "duration")
    H.eq(layout.step, 3600)
    H.eq(G.FormatAxis("goldPerSession", 40000), "+4g")
    H.eq(G.FormatAxis("timePerLevel", 3600), "1h")
end)
