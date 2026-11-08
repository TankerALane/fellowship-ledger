-- An opened character on the Me tab (UI/DetailModel.lua, D-075): data, both
-- layouts, Show all / Show less, killer level, and the mock window.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local RETAIL = { interface = 120105, tocFlavor = "Retail" }
local DATE = function(fmt, t) return os.date("!" .. fmt, t) end

local function sampleChar(nLevels, nDeaths, nItems)
    local c = { levels = {}, deathLog = {}, items = {} }
    for to = 2, nLevels + 1 do
        c.levels[to] = { from = to - 1, to = to, active = to * 60, total = to * 90, zone = "Zone" .. to, partial = to == 2 or nil }
    end
    for i = 1, nDeaths do  -- oldest first, as the tracker appends
        c.deathLog[i] = { at = 1000 + i * 100, zone = "DZone" .. i, level = 10 + i, killer = "Killer" .. i, killerStatus = "ok",
            killerLevel = (i % 3 == 0) and 20 + i or nil }
    end
    for i = 1, nItems do
        c.items[i] = { at = 2000 + i * 100, name = "Item" .. i, quality = 2 + (i % 3), zone = "IZone" .. i }
    end
    return c
end

local function texts(lines)
    local out = {}
    for _, line in ipairs(lines) do
        for _, s in ipairs(line.segments or {}) do
            if s.text and s.text ~= "" then out[#out + 1] = s.text end
            if s.button then out[#out + 1] = "[" .. s.button.label .. "]" end
        end
    end
    return table.concat(out, " | ")
end

local function buttons(lines)
    local out = {}
    for _, line in ipairs(lines) do
        for _, s in ipairs(line.segments or {}) do if s.button then out[#out + 1] = s.button end end
    end
    return out
end

H.test("details: newest first, last 10 levels / 5 deaths / 5 loot, Show all lists everything", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local c = sampleChar(21, 9, 8)
    local d = D.Data(c, L, DATE)
    H.eq(#d.levels.rows, 10); H.eq(d.levels.total, 21)
    H.eq(d.levels.rows[1].level, "21 -> 22", "newest level first")
    H.eq(d.levels.rows[10].level, "12 -> 13")
    H.eq(#d.deaths.rows, 5); H.eq(d.deaths.total, 9)
    H.eq(d.deaths.rows[1].killer, "Killer9", "newest death first")
    H.eq(d.deaths.rows[1].yourLevel, "19")
    H.eq(#d.loot.rows, 5); H.eq(d.loot.rows[1].name, "Item8")
    local all = D.Data(c, L, DATE, { levels = true, deaths = true, loot = true })
    H.eq(#all.levels.rows, 21); H.eq(#all.deaths.rows, 9); H.eq(#all.loot.rows, 8)
    H.eq(all.levels.rows[21].level, "1 -> 2")
    H.ok(all.levels.rows[21].zone:find("(partial)", 1, true), "partial levels are marked")
end)

H.test("details: a notable loot name carries its link for the item tooltip, only on that segment (D-103)", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local c = sampleChar(3, 0, 2)
    c.items[2].link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    for _, layout in ipairs({ "card", "list" }) do
        local found, others = nil, 0
        for _, line in ipairs(D.Lines(D.Data(c, L, DATE), layout, L, {})) do
            H.eq(line.item, nil, "the whole line is not an item")
            for _, s in ipairs(line.segments or {}) do
                if s.item then
                    if s.item.link == c.items[2].link then found = s else others = others + 1 end
                end
            end
        end
        H.ok(found and found.text:find("Item2", 1, true), layout .. ": the name segment has the link")
        H.eq(others, 0, layout .. ": an item without a link gets no hover")
    end
end)

H.test("details: levels use our arrow image, tinted to the text color", function()
    local D, L = H.pureNamespace().DetailModel, H.pureNamespace().L
    local code = D.ArrowCode({ 1, 0.5, 0, 1 })
    H.eq(code, "|TInterface\\AddOns\\FellowshipLedger\\media\\level-arrow:0:0:0:0:16:16:0:16:0:16:255:128:0|t")
    local d = D.Data({ levels = { [10] = { from = 9, to = 10, active = 60, total = 60 } } }, L, DATE, nil, code)
    H.eq(d.levels.rows[1].level, "9 " .. code .. " 10")
    H.eq(D.ArrowCode(nil), "->")
end)

H.test("details: their level is a number, ?? for skull level, ? when unknown, blank with no killer", function()
    local D, L = H.pureNamespace().DetailModel, H.pureNamespace().L
    local c = { deathLog = {
        { at = 1, killer = "A", killerLevel = 12, level = 10 },
        { at = 2, killer = "Boss", killerLevel = -1, level = 10 },
        { at = 3, killer = "B", level = 10 },
        { at = 4, killerStatus = "hidden", level = 10 },
        { at = 5, killerStatus = "none" },
    } }
    local rows = D.Data(c, L, DATE).deaths.rows
    H.eq(rows[5].theirLevel, "12"); H.eq(rows[4].theirLevel, "??"); H.eq(rows[3].theirLevel, "?")
    H.eq(rows[2].theirLevel, ""); H.eq(rows[2].killer, "Hidden by the game")
    H.eq(rows[1].killer, "Unknown"); H.eq(rows[1].yourLevel, "")
end)

H.test("details: the summary leaves partial levels out of average, fastest and slowest", function()
    local D, L = H.pureNamespace().DetailModel, H.pureNamespace().L
    local c = { levels = {
        [2] = { from = 1, to = 2, active = 5, total = 5, partial = true },
        [3] = { from = 2, to = 3, active = 100, total = 120 },
        [4] = { from = 3, to = 4, active = 300, total = 400 },
    }, deathLog = { { at = 1 }, { at = 2 } } }
    local s = D.Data(c, L, DATE).summary
    H.eq(s.levels, 3); H.eq(s.average, 200); H.eq(s.fastest.to, 3); H.eq(s.slowest.to, 4); H.eq(s.deaths, 2)
    local text = D.SummaryText(s, L)
    H.ok(text:find("3 levels recorded", 1, true) and text:find("Average 3m 20s a level", 1, true), text)
    H.ok(text:find("Fastest 2 -> 3 (1m 40s)", 1, true) and text:find("Slowest 3 -> 4 (5m 00s)", 1, true), text)
    H.ok(text:find("2 deaths in 90 days", 1, true), text)
end)

H.test("details: card layout is a box with levels left and deaths and loot right", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local toggled
    local lines = D.Lines(D.Data(sampleChar(21, 9, 8), L, DATE), "card", L,
        { skin = "ledger", onToggle = function(k) toggled = k end, onRemove = function() end })
    local last = lines[#lines]
    H.eq(#last.segments, 0, "a blank line after the card"); H.eq(last.box, nil, "outside the box")
    table.remove(lines)
    H.eq(lines[1].box, "top"); H.eq(lines[#lines].box, "bottom")
    for i = 2, #lines - 1 do H.eq(lines[i].box, "mid") end
    H.ok(lines[#lines].action, "Remove button on the last line of the card")
    for _, line in ipairs(lines) do
        H.eq(line.kind, "grid")
        for _, s in ipairs(line.segments) do
            H.ok(s.x >= 0 and s.w > 0 and s.x + s.w <= 1.0001, "segment inside the line")
        end
    end
    -- Heading line: Recent levels (left) and Recent deaths (right), each with Show all.
    local all = texts(lines)
    H.ok(all:find("Recent levels | [Show all (21)] | Recent deaths | [Show all (9)]", 1, true), all)
    H.ok(all:find("Notable loot | [Show all (8)]", 1, true), all)
    H.ok(all:find("Level | Active | Played | Zone", 1, true), "level column headers")
    H.ok(all:find("When | Killed by | Their lvl | Your lvl | Zone", 1, true), "death column headers")
    -- blank + summary + blank + max(2 + 10 levels, 2 + 5 deaths + 1 gap + 2 + 5 loot) + remove
    H.eq(#lines, 3 + 15 + 1)
    H.eq(#lines[1].segments, 0, "space before the summary")
    H.eq(#lines[3].segments, 0, "space before the headings")
    buttons(lines)[1].onClick()
    H.eq(toggled, "levels")
end)

H.test("details: list layout stacks the sections and has no box; Show less after Show all", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local c = sampleChar(21, 9, 8)
    local lines = D.Lines(D.Data(c, L, DATE, { deaths = true }), "list", L, { skin = "ledger" })
    for _, line in ipairs(lines) do H.eq(line.box, nil) end
    local all = texts(lines)
    local a, b, d = all:find("Recent levels", 1, true), all:find("Recent deaths", 1, true), all:find("Notable loot", 1, true)
    H.ok(a and b and d and a < b and b < d, "sections in order, one under another")
    H.ok(all:find("Recent deaths | [Show less]", 1, true), all)
    H.eq(#lines, (2 + 10) + 1 + (2 + 9) + 1 + (2 + 5) + 1, "no Remove line without onRemove; a blank line at the end")
    H.eq(#lines[#lines].segments, 0)
end)

H.test("details: no Show all when everything already fits; empty sections say so", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local lines = D.Lines(D.Data(sampleChar(3, 0, 5), L, DATE), "card", L, { skin = "ledger" })
    H.eq(#buttons(lines), 0)
    local all = texts(lines)
    H.ok(all:find("No deaths in the last 90 days.", 1, true), all)
    lines = D.Lines(D.Data({}, L, DATE), "list", L, {})
    all = texts(lines)
    H.ok(all:find("No levels recorded yet.", 1, true) and all:find("No notable loot", 1, true), all)
end)

H.test("details: loot names are in a readable quality color on every skin", function()
    local ns = H.pureNamespace()
    local P = ns.Palette
    for skin in pairs(P.SKINS) do
        for q in pairs(P.QUALITY) do
            H.ok(P.Contrast(P.QualityColor(q, skin), P.Color(skin, "bg")) >= P.MIN_CONTRAST, q .. " on " .. skin)
        end
    end
    H.eq(P.QualityColor(1, "ledger"), nil, "common items have no color")
    local D, L = ns.DetailModel, ns.L
    local lines = D.Lines(D.Data({ items = { { at = 1, name = "Epic Thing", quality = 4 } } }, L, DATE), "card", L, { skin = "leather" })
    H.ok(texts(lines):find("|cff", 1, true) and texts(lines):find("Epic Thing|r", 1, true))
end)

H.test("details: dates read 'MM-DD, HH:MM'; the space above the summary is half a line", function()
    local ns = H.pureNamespace()
    local D, L = ns.DetailModel, ns.L
    local d = D.Data({ deathLog = { { at = 0, killer = "A" } }, items = { { at = 0, name = "X", quality = 2 } } }, L, DATE)
    H.eq(d.deaths.rows[1].when, "01-01, 00:00")
    H.eq(d.loot.rows[1].when, "01-01, 00:00")
    local lines = D.Lines(d, "card", L, {})
    H.eq(lines[1].height, D.HALF_LINE)
    H.eq(lines[3].height, nil, "the space before the headings is a full line")
end)

-- Runtime (mock game) ------------------------------------------------------------

H.test("the table places lines by height: half-height lines take half the room", function()
    local env = Mock.new(RETAIL)
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    local panel = env.CreateFrame("Frame")
    local tbl = ns.Table.New(panel, { { label = "A", width = 100, field = "a" } }, { top = 0 })
    local function shownCount(lines)
        tbl:SetLines(lines)
        local n = 0
        for _, w in pairs(tbl.widgets) do if w:IsShown() then n = n + 1 end end
        return n
    end
    local full, half = {}, {}
    for i = 1, 60 do
        full[i] = { kind = "grid", segments = {} }
        half[i] = { kind = "grid", segments = {}, height = 10 }
    end
    local a = shownCount(full)
    local b = shownCount(half)
    H.ok(a > 0 and a < 60, "full lines: " .. a)
    H.eq(b, a * 2, "twice as many half-height lines fit")
end)

local function boot(db)
    local env = Mock.new(RETAIL)
    env.FellowshipLedgerDB = db
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    return env, ns
end

local function gridTexts(ns)
    local out = {}
    for _, w in pairs(ns.MeTab.ui.table.widgets) do
        if w:IsShown() and w.line and w.line.kind == "grid" then
            for _, fs in ipairs(w.segs) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
            for _, b in ipairs(w.segButtons) do if b:IsShown() then out[#out + 1] = "[" .. b.text:GetText() .. "]" end end
        end
    end
    return table.concat(out, " | ")
end

H.test("Me tab: open a character as a card or a list, Show all and Show less, switch in Settings", function()
    local alt = sampleChar(21, 9, 8)
    alt.name, alt.level, alt.lastSeen = "Alt", 22, os.time()
    local env, ns = boot({ settings = { askStale = false, welcomeEveryLogin = false }, characters = { ["Alt-TestRealm"] = alt } })
    H.eq(ns.db.settings.detailsLayout, "card", "card is the default")
    ns.MainWindow.Open("me")
    local Me = ns.MeTab
    Me.state.expanded["Alt-TestRealm"] = true
    Me.Refresh()
    local shown = gridTexts(ns)
    H.ok(shown:find("Recent levels", 1, true) and shown:find("[Show all (21)]", 1, true), shown)
    local grid = 0
    for _, line in ipairs(Me.ui.table.lines) do if line.kind == "grid" then grid = grid + 1 end end
    H.eq(grid, 21, "the tab row plus the card")
    -- Show all on levels, then Show less.
    local function levelsButton()
        for _, line in ipairs(Me.ui.table.lines) do
            for _, s in ipairs(line.segments or {}) do if s.button and not s.button.fill then return s.button end end
        end
    end
    levelsButton().onClick()
    H.eq(Me.state.showAll["Alt-TestRealm"].levels, true)
    grid = 0
    for _, line in ipairs(Me.ui.table.lines) do if line.kind == "grid" then grid = grid + 1 end end
    H.eq(grid, 1 + 3 + 2 + 21 + 1 + 1, "all 21 levels listed")
    H.eq(levelsButton().label, "Show less")
    levelsButton().onClick()
    H.eq(Me.state.showAll["Alt-TestRealm"].levels, nil, "back to the last 10")
    -- Switch to the list layout in Settings.
    ns.MainWindow.Open("settings")
    ns.db.settings.detailsLayout = "list"
    ns.MainWindow.Open("me")
    Me.Refresh()
    for _, line in ipairs(Me.ui.table.lines) do H.eq(line.box, nil, "no card box in the list layout") end
    local chat = table.concat(env.__state.chat, "\n")
    H.ok(not chat:find("failed") and not chat:find("problem"), chat)
end)

H.test("dying while targeting the killer keeps its level; another target does not", function()
    local env, ns = boot({ settings = { askStale = false, welcomeEveryLogin = false } })
    env.__state.units.target = { name = "Gnoll Mystic", level = 14 }
    env.__state.recaps = { [1] = { { timestamp = 1, sourceName = "Gnoll Mystic", spellName = "Lightning Bolt" } } }
    Mock.fire(env, "PLAYER_DEAD")
    Mock.runTimers(env)
    local log = ns.Store.char.deathLog
    H.eq(log[1].killerLevel, 14)
    env.__state.units.target = { name = "Kobold Miner", level = 3 }
    env.__state.recaps[2] = { { timestamp = 2, sourceName = "Gnoll Brute", spellName = "Melee" } }
    env.__state.now = (env.__state.now or os.time()) + 60
    Mock.fire(env, "PLAYER_DEAD")
    Mock.runTimers(env)
    H.eq(#log, 2)
    H.eq(log[2].killer, "Gnoll Brute")
    H.eq(log[2].killerLevel, nil, "the target was not the killer")
end)
