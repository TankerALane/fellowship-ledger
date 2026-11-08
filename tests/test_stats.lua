-- Character detail views (D-081): Quests, Gold, Kills, Professions, All completed
-- (UI/StatsModel.lua), and every tab in the mock window. In-game look is on Austin's checklist.
local H = ...
local ns = H.pureNamespace()
local S, L = ns.StatsModel, ns.L
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
local DATE = function(fmt, t) return os.date("!" .. fmt, t) end
local ALL = function() return true end

local function textOf(parts)
    local out = {}
    for _, p in ipairs(parts) do
        local row = {}
        for _, s in ipairs(p.segs or p.segments or {}) do
            if s.button then row[#row + 1] = "[" .. s.button.label .. "]"
            elseif s.bar then row[#row + 1] = string.format("bar%.2f", s.bar)
            else row[#row + 1] = s.text end
        end
        out[#out + 1] = table.concat(row, " | ")
    end
    return table.concat(out, "\n")
end

H.test("stats: tab row, selected tab, picking", function()
    local picked
    local line = S.TabLine("gold", L, function(id) picked = id end)
    H.eq(#line.segments, 6)
    H.eq(line.segments[1].button.label, "Overview"); H.eq(line.segments[6].button.label, "All completed")
    H.eq(line.segments[3].button.selected, true); H.eq(line.segments[1].button.selected, false)
    line.segments[4].button.onClick(); H.eq(picked, "kills")
end)

H.test("stats: quests newest first, range, totals, Show all after 10", function()
    local log = {}
    for i = 1, 12 do log[i] = { id = i, title = "Q" .. i, at = i * 3600, xp = 100, money = i == 12 and 15000 or 0, zone = i > 6 and "Westfall" or nil } end
    local toggled = false
    local parts = S.Quests(log, ALL, L, DATE, false, function(id) return "Z" .. id end, function() toggled = true end)
    local text = textOf(parts)
    H.ok(text:find("12 quests turned in     1,200 XP     1g 50s 00c from rewards", 1, true), text)
    H.ok(text:find("Q12 | 100 | 1g 50s 00c | Westfall", 1, true), text)
    H.ok(text:find("Q3 | 100 |  | Z3", 1, true), "zone from Questie when not saved: " .. text)
    H.ok(not text:find("| Q2 |", 1, true), "only 10 until Show all")
    H.ok(text:find("[Show all (12)]", 1, true), text)
    parts[#parts].segs[1].button.onClick(); H.ok(toggled)
    text = textOf(S.Quests(log, function(at) return at >= 11 * 3600 end, L, DATE, false))
    H.ok(text:find("2 quests turned in", 1, true), text)
    H.ok(textOf(S.Quests({}, ALL, L, DATE)):find("No quests turned in", 1, true))
end)

H.test("stats: gold by source with shares; losses in red, no bar", function()
    local parts = S.Gold({ moneyIn = 40000, moneyOut = 5000, moneyNet = 35000, money_loot = 30000, money_quest = 10000, money_vendor = -5000 }, L)
    local text = textOf(parts)
    H.ok(text:find("In 4g 00s 00c     Out 50s 00c     Net +3g 50s 00c", 1, true), text)
    H.ok(text:find("Loot | +3g 00s 00c | bar0.75 | 75%", 1, true), text)
    H.ok(text:find("Quest | +1g 00s 00c | bar0.25 | 25%", 1, true), text)
    H.ok(text:find("Vendor | -50s 00c\n", 1, true), text)
    for _, p in ipairs(parts) do
        for _, s in ipairs(p.segs) do if s.text == "-50s 00c" then H.eq(s.role, "bad") end end
    end
    H.ok(textOf(S.Gold({}, L)):find("No gold changes", 1, true))
end)

H.test("stats: gold headline and Net row show the total after everything (D-101)", function()
    local parts = S.Gold({ moneyIn = 40000, moneyOut = 5000, moneyNet = 35000, money_loot = 30000, money_quest = 10000, money_vendor = -5000 }, L)
    H.eq(parts[1].segs[1].text, "Total gained"); H.eq(parts[1].segs[2].text, "+3g 50s 00c"); H.eq(parts[1].segs[2].role, "good")
    H.ok(textOf(parts):find("Net | +3g 50s 00c", 1, true), textOf(parts))
    parts = S.Gold({ moneyIn = 1000, moneyOut = 6000, moneyNet = -5000, money_vendor = -5000, money_loot = 1000 }, L)
    H.eq(parts[1].segs[1].text, "Total lost"); H.eq(parts[1].segs[2].role, "bad")
end)

H.test("stats: kills by type follow the range; All uses the all-time table", function()
    local kills = { total = 400, rare = 3, elite = 11, byType = { Beast = 200, Humanoid = 150, Undead = 50 } }
    local week = { kills = 40, rareKills = 1, eliteKills = 2, ["killType:Beast"] = 30, ["killType:Humanoid"] = 10 }
    local text = textOf(S.Kills(week, kills, "week", L))
    H.ok(text:find("40 kills     1 rare     2 elite     All time: 400", 1, true), text)
    H.ok(text:find("Beast | 30 | bar0.75 | 75%", 1, true), text)
    H.ok(not text:find("Undead", 1, true), "range only")
    text = textOf(S.Kills(week, kills, "all", L))
    H.ok(text:find("400 kills     3 rare     11 elite", 1, true), text)
    H.ok(text:find("Beast | 200 | bar0.50 | 50%", 1, true), text)
    H.ok(textOf(S.Kills({}, {}, "today", L)):find("No kills with a creature type", 1, true))
end)

H.test("stats: professions with gains in range, and the recent points of an opened one", function()
    local profs = { ["186"] = { name = "Mining", rank = 87, max = 150, lastAt = 9000, history = {
        { rank = 85, at = 1000, active = 900 }, { rank = 86, at = 5000, active = 240 }, { rank = 87, at = 9000, active = 370 } } },
        ["129"] = { name = "First Aid", rank = 40, max = 75, history = {} } }
    local toggled
    local parts = S.Professions(profs, function(at) return at >= 5000 end, L, DATE, { ["186"] = true }, function(k) toggled = k end, 2)
    local text = textOf(parts)
    H.ok(text:find("2 skill-ups", 1, true), text)
    H.ok(text:find("+ | First Aid | 40 / 75 | bar0.53 | 0", 1, true), text)
    H.ok(text:find("- | Mining | 87 / 150 | bar0.58 | +2", 1, true), text)
    H.ok(text:find("87 | ", 1, true) and text:find("15m 00s | slowest of these", 1, true), text)
    for _, p in ipairs(parts) do if p.onClick then p.onClick() end end
    H.ok(toggled ~= nil)
    H.ok(textOf(S.Professions({}, ALL, L, DATE, {}, function() end, 0)):find("No professions seen yet", 1, true))
end)

H.test("stats: all completed grouped by zone, other last, opened zone lists names", function()
    local INFO = { [1] = { name = "B Quest", zone = "Westfall" }, [2] = { name = "A Quest", zone = "Westfall" },
        [3] = { name = "Class Quest" }, [4] = { name = "Elwynn One", zone = "Elwynn Forest" } }
    local groups = S.GroupCompleted({ 1, 2, 3, 4, 5 }, function(id) return INFO[id] end, L)
    H.eq(groups[1].zone, "Elwynn Forest"); H.eq(groups[2].zone, "Westfall"); H.eq(groups[3].other, true)
    H.eq(groups[2].names[1], "A Quest")
    H.eq(groups[3].names[2], "Quest 5", "unknown quests by number")
    local text = textOf(S.Completed(groups, 5, false, L, { Westfall = true }, function() end))
    H.ok(text:find("5 quests completed on this character", 1, true), text)
    H.ok(text:find("- | Westfall | 2\nA Quest | B Quest", 1, true), text)
    H.ok(text:find("+ | Elwynn Forest | 1", 1, true), text)
    H.ok(textOf(S.Completed(nil, 0, false, L)):find("does not give addons the list", 1, true))
    -- With Questie loaded, quests it does not know (hidden tracking quests) are left out and counted.
    local named, hidden = S.GroupCompleted({ 1, 2, 3, 4, 5, 99582 }, function(id) return INFO[id] end, L, true)
    H.eq(hidden, 2)
    for _, g in ipairs(named) do for _, n in ipairs(g.names) do H.ok(not n:find("^Quest %d"), n) end end
    text = textOf(S.Completed(named, 6, false, L, {}, function() end, hidden))
    H.ok(text:find("4 quests completed on this character, grouped by zone     (2 hidden game quests not listed)", 1, true), text)
end)

H.test("stats: the box joins the tab row, in both layouts", function()
    local lines = S.Wrap(S.TabLine("gold", L, function() end), S.Gold({}, L), "card")
    H.eq(lines[1].box, "top"); H.eq(lines[#lines - 1].box, "bottom"); H.eq(lines[#lines].box, nil)
    lines = S.Wrap(S.TabLine("gold", L, function() end), S.Gold({}, L), "list")
    for _, l in ipairs(lines) do H.eq(l.box, nil) end
    local over = S.WithTabs(S.TabLine("overview", L, function() end), { { kind = "grid", box = "top" }, { kind = "grid", box = "bottom" } }, "card")
    H.eq(over[1].box, "top"); H.eq(over[2].box, "mid")
end)

H.test("stats: every tab in the window, with tracked kills by type and the completed list", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false } }
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    local st = env.__state
    st.guid.player, st.guid.target = "Player-1", "Creature-7"
    st.units.target = { ctype = "Beast", classification = "normal" }
    Mock.fire(env, "PARTY_KILL", "Player-1", "Creature-7")
    Mock.fire(env, "QUEST_TURNED_IN", 54, 450, 75)
    st.completed = { [54] = true, [55] = true }
    local key = ns2.Store.key
    local today = ns2.Store.char.days[ns2.Store.Today()]
    H.eq(today["killType:Beast"], 1, "kills by type per day")
    H.eq(ns2.Store.char.questLog[1].zone, "Elwynn Forest", "turn-in zone saved")
    ns2.MainWindow.Open("me")
    local Me = ns2.MeTab
    Me.state.expanded[key] = true
    for _, view in ipairs(S.TABS) do
        Me.state.detailView[key] = view
        Me.Refresh()
    end
    local seen = {}
    for _, line in ipairs(Me.ui.table.lines) do
        for _, s in ipairs(line.segments or {}) do if s.text then seen[#seen + 1] = s.text end end
    end
    local text = table.concat(seen, " | ")
    H.ok(text:find("2 quests completed on this character", 1, true), text)
    Me.state.detailView[key] = "kills"; Me.Refresh()
    seen = {}
    for _, line in ipairs(Me.ui.table.lines) do
        for _, s in ipairs(line.segments or {}) do if s.text then seen[#seen + 1] = s.text end end
    end
    H.ok(table.concat(seen, " | "):find("Beast", 1, true))
    local chat = table.concat(st.chat, "\n")
    H.ok(not chat:find("failed") and not chat:find("problem"), chat)
end)
