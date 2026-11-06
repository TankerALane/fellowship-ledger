-- Phase 2 UI against the mock: fake data in every view, skins, toasts, minimap,
-- welcome, options entry, quest chains (game data, Questie, neither).
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local RETAIL = { interface = 120105, tocFlavor = "Retail" }

local function boot(opts, db, backup)
    local env = Mock.new(opts or RETAIL)
    env.FellowshipLedgerDB = db
    env.FellowshipLedgerBackupDB = backup
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    return env, ns
end

local function noErrors(env)
    local chat = table.concat(env.__state.chat, "\n")
    H.ok(not chat:find("failed") and not chat:find("problem") and not chat:find("could not"), chat)
end

H.test("fake data: every tab, range, chart and mode renders; real data untouched", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    noErrors(env)
    H.ok(env.FellowshipLedgerDB.fake, "fake set created")
    H.ok(env.FellowshipLedgerMainWindow:IsShown())
    H.ok(ns.MainWindow.fakeBanner:IsShown(), "fake banner shown")
    local real = 0
    for _ in pairs(env.FellowshipLedgerDB.characters) do real = real + 1 end
    H.eq(real, 1, "only the real character in real data")
    for _, tab in ipairs(ns.MainWindow.TABS) do ns.MainWindow.Select(tab) end
    for _, chart in ipairs(ns.GraphModel.CHARTS) do
        ns.MainWindow.Select("graphs")
        ns.GraphsTab.Refresh()
    end
    noErrors(env)
    -- export never contains fake characters
    Mock.slash(env, "export")
    H.ok(not ns.CopyWindow.text:find("Fakerealm", 1, true), "fake data is not exported")
    Mock.slash(env, "fake off")
    H.eq(env.FellowshipLedgerDB.fake, nil)
    H.ok(not ns.MainWindow.fakeBanner:IsShown())
end)

H.test("graphs draw one bar per point for each chart", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    ns.MainWindow.Select("graphs")
    local list = ns.Data.GraphableCharacters()
    H.ok(#list >= 3 + 10, "own and friends' characters are graphable")
    for _, chart in ipairs(ns.GraphModel.CHARTS) do
        local pts = ns.GraphModel.Build(chart, list[1].char, ns.Store.Today(), env.time, env.date, 30)
        local area = ns.MainWindow.frame
        local g = ns.Graph.New(area)
        g:SetData(pts, chart, 1, "empty")
        local shown = 0
        for _, b in ipairs(g.bars) do if b:IsShown() then shown = shown + 1 end end
        local nonZero = false
        for _, p in ipairs(pts) do if p.value ~= 0 then nonZero = true end end
        H.eq(shown, nonZero and #pts or 0, chart)
    end
    noErrors(env)
end)

H.test("skins, text sizes and scale apply without errors", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    for _, skin in ipairs({ "plain", "ledger", "leather" }) do
        for _, size in ipairs({ "small", "normal", "large" }) do
            env.FellowshipLedgerDB.settings.skin = skin
            env.FellowshipLedgerDB.settings.fontSize = size
            ns.Widgets.ApplySkin()
            for _, tab in ipairs(ns.MainWindow.TABS) do ns.MainWindow.Select(tab) end
        end
    end
    env.FellowshipLedgerDB.settings.scale = 1.3
    ns.MainWindow.ApplyScale()
    noErrors(env)
end)

H.test("welcome panel shows every load until its box is unticked; sharing switch", function()
    local env, ns = boot()
    local w = env.FellowshipLedgerWelcome
    H.ok(w and w:IsShown(), "welcome shown")
    -- sharing switch: off, then back on
    w.share:GetScript("OnClick")(w.share)
    H.eq(env.FellowshipLedgerDB.settings.sharingPaused, true)
    H.eq(w.share.text:GetText(), "Turn sharing back on")
    w.share:GetScript("OnClick")(w.share)
    H.eq(env.FellowshipLedgerDB.settings.sharingPaused, false)
    -- seen before: still shows on the next load
    env.FellowshipLedgerDB.settings.welcomeSeen = true
    Mock.fire(env, "PLAYER_LOGOUT")
    local env2 = boot(RETAIL, env.FellowshipLedgerDB, env.FellowshipLedgerBackupDB)
    H.ok(env2.FellowshipLedgerWelcome:IsShown(), "shown again on the next load")
    -- untick the box: not shown on the next load
    local box = env2.FellowshipLedgerWelcome.every
    box:GetScript("OnClick")(box)
    H.eq(env2.FellowshipLedgerDB.settings.welcomeEveryLogin, false)
    Mock.fire(env2, "PLAYER_LOGOUT")
    local env3 = boot(RETAIL, env2.FellowshipLedgerDB, env2.FellowshipLedgerBackupDB)
    H.ok(not (env3.FellowshipLedgerWelcome and env3.FellowshipLedgerWelcome:IsShown()), "not shown once unticked")
end)

H.test("minimap button, options page and compartment entry", function()
    local env, ns = boot()
    local b = env.FellowshipLedgerMinimapButton
    H.ok(b and b:IsShown(), "minimap button shown")
    b:GetScript("OnClick")(b, "LeftButton")
    H.ok(env.FellowshipLedgerMainWindow:IsShown(), "left click opens")
    b:GetScript("OnClick")(b, "RightButton")
    H.eq(ns.MainWindow.current, "settings", "right click opens settings")
    env.FellowshipLedgerDB.settings.minimap.hide = true
    ns.MinimapButton.Update()
    H.ok(not b:IsShown(), "can be hidden")
    H.eq(#env.__state.settingsCategories, 1)
    H.ok(env.__state.settingsCategories[1].registered)
    H.eq(#env.__state.compartment, 1)
end)

H.test("level-up toast and session summary at the next login", function()
    local env = boot()
    Mock.fire(env, "PLAYER_LEVEL_UP", 13)
    H.ok(Mock.chatContains(env, "Level 13!"), "toast echoed to chat")
    env.__state.speed = 7
    Mock.advance(env, 600)
    Mock.fire(env, "PLAYER_LOGOUT")
    local opts = { interface = 120105, tocFlavor = "Retail", now = env.__state.now + 3600 }
    local env2 = boot(opts, env.FellowshipLedgerDB, env.FellowshipLedgerBackupDB)
    H.ok(Mock.chatContains(env2, "Session of"), "previous session summarised")
    H.ok(Mock.chatContains(env2, "1 level(s)"))
    Mock.slash(env2, "summary")
    noErrors(env2)
end)

H.test("quest chains: game data, then Questie, then a plain answer", function()
    local env, ns = boot()
    local e = ns.QuestChains.ForLog()
    H.eq(e[1].step, 1); H.eq(e[1].total, 3); H.eq(e[1].source, "game")
    env.__state.noQuestLines = true
    e = ns.QuestChains.ForLog()
    H.eq(e[1].step, nil, "neither source")
    env.__state.questieLoaded = true
    env.__state.questie = { [53] = { next = 54, name = "Start Here" }, [54] = { pre = 53, next = 60 }, [60] = { pre = 54 } }
    local entries, state = ns.QuestChains.ForLog()
    H.eq(state, "ready")
    H.eq(entries[1].source, "questie")
    H.eq(entries[1].step, 2); H.eq(entries[1].total, 3)
    H.eq(entries[1].chainName, "Start Here")
    ns.MainWindow.Open("me")
    ns.MeTab.Refresh()
    noErrors(env)
end)

H.test("quest chain drop-down: Questie levels, starters and zones in the Me tab", function()
    local env, ns = boot()
    local st = env.__state
    st.noQuestLines = true
    st.questieLoaded = true
    st.level = 12
    st.areas = { [40] = "Westfall" }
    st.questieNPCs = { [234] = { name = "Gryan Stoutmantle", spawns = { [40] = { { 56, 47 } } } } }
    st.questieItems = { [1307] = { name = "Gold Pickup Schedule" } }
    st.questie = {
        [53] = { next = 54, name = "Start Here", level = 10, req = 8, startedBy = { { 234 } } },
        [54] = { pre = 53, next = 60, name = "Middle", level = 12, req = 10, finishedBy = { { 234 } } },
        [60] = { pre = 54, name = "The End", level = 15, req = 13, startedBy = { nil, nil, { 1307 } }, preGroup = { 88 } },
        [88] = { name = "Side Quest" },
    }
    st.completed = { [53] = true }
    ns.MainWindow.Open("me")
    ns.MeTab.state.mode = "chains"
    ns.MeTab.Refresh()
    local view = ns.MeTab.ChainView()
    H.eq(#view.mine, 1)
    H.eq(view.mine[1].key, "q:53")
    ns.MeTab.state.chainOpen["q:53"] = true
    view = ns.MeTab.ChainView()
    local q = view.mine[1].details.quests
    H.eq(q[1].status, "done"); H.eq(q[2].status, "log"); H.eq(q[3].status, nil)
    H.eq(q[1].start.name, "Gryan Stoutmantle"); H.eq(q[1].start.zone, "Westfall")
    H.eq(q[1].start.x, 56); H.eq(q[1].start.y, 47)
    H.eq(q[3].start.kind, "item"); H.eq(q[3].req, 13)
    H.eq(view.mine[1].details.also[1].name, "Side Quest")
    ns.MeTab.Refresh()
    noErrors(env)
end)

H.test("a broken Questie never breaks the ledger", function()
    local env, ns = boot()
    env.__state.noQuestLines = true
    env.__state.questieLoaded = true
    env.__state.questieBroken = true
    local entries, state = ns.QuestChains.ForLog()
    H.eq(state, "broken")
    H.eq(entries[1].step, nil)
    Mock.slash(env, "verify")
    H.ok(env.FellowshipLedgerDB.verify.text:find("FAIL x:questie.db: state=broken", 1, true))
    noErrors(env)
end)

H.test("blocking from the Friends tab hides the friend", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    ns.FriendsTab.Block("Tobin#0003")
    H.eq(env.FellowshipLedgerDB.blocklist["Tobin#0003"], true)
    for _, entry in ipairs(ns.Data.GraphableCharacters()) do H.ok(entry.owner ~= "Tobin", "blocked friend not graphable") end
    noErrors(env)
end)

H.test("self-test still passes with Phase 2 loaded", function()
    local env = boot()
    Mock.slash(env, "test")
    H.ok(Mock.chatContains(env, "Self-test: 9 of 9 passed."))
end)

H.test("graph labels: old labels never linger after a redraw", function()
    local env, ns = boot()
    local area = ns.MainWindow.Ensure() and ns.MainWindow.frame
    local g = ns.Graph.New(area)
    local many, few = {}, {}
    for i = 1, 40 do many[i] = { label = "L" .. i, value = i % 3 } end
    for i = 1, 10 do few[i] = { label = "S" .. i, value = 1 } end
    g.plot:SetWidth(1900)
    g:SetData(many, "levelsPerSession", 1, "")
    g.plot:SetWidth(500)
    g:SetData(few, "levelsPerSession", 1, "")
    local shown = 0
    for idx, x in pairs(g.xlabels) do
        if x:IsShown() then
            shown = shown + 1
            H.ok(idx <= 10, "label from the old chart still shown at " .. idx)
            H.ok(x:GetText():find("^S"), "stale text " .. tostring(x:GetText()))
        end
    end
    H.ok(shown >= 1 and shown <= math.floor(500 / ns.GraphModel.LABEL_PX), "labels fit the width: " .. shown)
    local values = {}
    for _, grid in ipairs(g.grid) do
        if grid.label:IsShown() then
            local t = grid.label:GetText()
            H.ok(not values[t], "repeated axis label " .. t)
            values[t] = true
        end
    end
end)

H.test("per-character sharing button switches all off, then all on", function()
    local env, ns = boot()
    ns.MainWindow.Open("settings")
    local c = env.FellowshipLedgerDB.characters["Tester-TestRealm"]
    H.ok(ns.SettingsTab.AnySharing(c))
    for _, f in pairs(c.flags) do f.share = false end
    H.ok(not ns.SettingsTab.AnySharing(c))
    c.flags.levels.share = true
    H.ok(ns.SettingsTab.AnySharing(c))
end)

H.test("/fl welcome reopens the panel; startup failures are reported", function()
    local env, ns = boot()
    env.FellowshipLedgerWelcome:Hide()
    Mock.slash(env, "welcome")
    H.ok(env.FellowshipLedgerWelcome:IsShown())
    -- a failing startup step says so in chat instead of failing silently
    local env2 = Mock.new(RETAIL)
    local ns2 = Mock.loadToc(H, env2, "FellowshipLedger_Mainline.toc")
    ns2.Welcome.MaybeShow = function() error("boom") end
    Mock.fire(env2, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env2, "PLAYER_LOGIN")
    Mock.fire(env2, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env2)
    H.ok(Mock.chatContains(env2, "The welcome panel could not start: "), table.concat(env2.__state.chat, "\n"))
end)

H.test("tables fit the window; the Block button has its own space", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    ns.MainWindow.Select("me")
    local panel = ns.MainWindow.tabs.me.panel
    local columns = {}
    for _, col in ipairs(ns.MeModel.COLUMNS) do columns[#columns + 1] = { label = col.label, width = col.width } end
    local tbl = ns.Table.New(panel, columns, { top = 30 })
    panel:SetWidth(450)
    tbl:SetLines({ { kind = "row", cells = { "a", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" } } })
    local right = 4
    for c, h in ipairs(tbl.headers) do
        if h:IsShown() then right = right + tbl.widths[c] + 4 end
    end
    H.ok(right <= 450, "columns end inside the panel: " .. right)
    H.ok(not tbl.headers[#tbl.headers]:IsShown(), "the last column is hidden when narrow")
    local withButtons = ns.Table.New(panel, columns, { top = 30, actions = true })
    withButtons:SetLines({})
    local used = 4
    for c in ipairs(columns) do if withButtons.widths[c] then used = used + withButtons.widths[c] + 4 end end
    H.ok(used <= 450 - 80, "space kept for the Block button: " .. used)
end)

H.test("the sorted column shows an arrow image, not a letter", function()
    local env, ns = boot()
    ns.MainWindow.Open("me")
    local panel = ns.MainWindow.tabs.me.panel
    local sort = { field = "level", desc = true }
    local tbl = ns.Table.New(panel, { { label = "Name", width = 100, field = "name" }, { label = "Lvl", width = 40, field = "level" } },
        { top = 30, sortState = function() return sort.field, sort.desc end })
    tbl:SetLines({})
    H.eq(tbl.headers[2].text:GetText(), "Lvl")
    H.ok(tbl.headers[2].arrow:IsShown(), "arrow on the sorted column")
    H.ok(not tbl.headers[1].arrow:IsShown(), "no arrow elsewhere")
    sort.field = "name"
    tbl:SetLines({})
    H.ok(tbl.headers[1].arrow:IsShown() and not tbl.headers[2].arrow:IsShown(), "arrow follows the sort")
end)

H.test("the window opens on Me unless 'open on the last tab' is on", function()
    local env, ns = boot()
    ns.MainWindow.Open("graphs")
    ns.MainWindow.frame:Hide()
    ns.MainWindow.Toggle()
    H.eq(ns.MainWindow.current, "me")
    env.FellowshipLedgerDB.settings.rememberTab = true
    ns.MainWindow.Open("friends")
    ns.MainWindow.frame:Hide()
    ns.MainWindow.Toggle()
    H.eq(ns.MainWindow.current, "friends")
end)

H.test("resizing defers redraws until the corner is let go", function()
    local env, ns = boot()
    ns.MainWindow.Open("me")
    local f = ns.MainWindow.frame
    local calls = 0
    local original = ns.MeTab.Refresh
    ns.MeTab.Refresh = function() calls = calls + 1; original() end
    ns.MainWindow.tabs.me.OnShow = function() ns.MeTab.Refresh() end
    ns.MainWindow.sizing = true
    for _ = 1, 20 do f:GetScript("OnSizeChanged")(f) end
    H.eq(calls, 0, "no redraw per resize step")
    H.ok(ns.MainWindow.resizePending)
    ns.MainWindow.sizing = false
    f:GetScript("OnSizeChanged")(f)
    H.eq(calls, 1)
    ns.MeTab.Refresh = original
end)

H.test("a new character offers to remove characters not played for 30 days; Done keeps the rest", function()
    local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
    local day = 86400
    -- The welcome panel is off here; with it on, the prompt waits for it to close.
    local db = { settings = { welcomeEveryLogin = false }, characters = {
        ["Gone-TestRealm"] = { name = "Gone", level = 20, class = "PRIEST", lastSeen = now - 90 * day },
        ["Old-TestRealm"] = { name = "Old", level = 10, class = "ROGUE", lastSeen = now - 40 * day },
        ["Recent-TestRealm"] = { name = "Recent", level = 30, lastSeen = now - 5 * day },
        ["Kept-TestRealm"] = { name = "Kept", level = 5, lastSeen = now - 60 * day, keep = true },
    } }
    local env, ns = boot(RETAIL, db)
    local f
    for _, frame in pairs(env.__state.frames) do if frame._name == "FellowshipLedgerStalePrompt" then f = frame end end
    H.ok(f and f:IsShown(), "prompt shown on the new character")
    H.ok(f.rows[1]:IsShown() and f.rows[2]:IsShown() and not f.rows[3]:IsShown(), "two stale characters listed")
    H.ok(f.rows[1].text:GetText():find("Gone", 1, true), "longest first: " .. f.rows[1].text:GetText())
    f.rows[1].button:GetScript("OnClick")()
    H.eq(ns.db.characters["Gone-TestRealm"], nil, "removed")
    H.ok(ns.db.removed["Gone-TestRealm"], "remembered for friends")
    f.done:GetScript("OnClick")()
    H.ok(not f:IsShown())
    H.eq(ns.db.characters["Old-TestRealm"].keep, true, "the rest are kept and not asked about again")
    H.eq(#ns.Character.Stale(ns.db.characters, ns.Store.key, now), 0)
end)

H.test("no prompt on a character the ledger already knows, or with the setting off", function()
    local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
    local db = { characters = {
        ["Tester-TestRealm"] = { name = "Tester", level = 12, lastSeen = now - 100 },
        ["Old-TestRealm"] = { name = "Old", level = 10, lastSeen = now - 40 * 86400 },
    } }
    local env = boot(RETAIL, db)
    for _, frame in pairs(env.__state.frames) do
        H.ok(not (frame._name == "FellowshipLedgerStalePrompt" and frame:IsShown()), "not shown for a known character")
    end
    local env2 = boot(RETAIL, { settings = { askStale = false }, characters = {
        ["Old-TestRealm"] = { name = "Old", level = 10, lastSeen = now - 40 * 86400 } } })
    for _, frame in pairs(env2.__state.frames) do
        H.ok(not (frame._name == "FellowshipLedgerStalePrompt" and frame:IsShown()), "not shown when turned off")
    end
end)

H.test("Remove on the Me tab: confirm first, never the current character", function()
    local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
    local env, ns = boot(RETAIL, { settings = { askStale = false }, characters = {
        ["Alt-TestRealm"] = { name = "Alt", level = 3, lastSeen = now - 86400 } } })
    ns.MeTab.Remove(ns.Store.key)
    H.ok(ns.db.characters[ns.Store.key], "the character you are on is never removed")
    ns.MeTab.ConfirmRemove("Alt-TestRealm", "Alt")
    H.ok(ns.db.characters["Alt-TestRealm"], "nothing removed before the confirm")
    local dialog = env.FellowshipLedgerDialog
    for _, frame in pairs(env.__state.frames) do if frame._name == "FellowshipLedgerDialog" then dialog = frame end end
    dialog.yes:GetScript("OnClick")()
    H.eq(ns.db.characters["Alt-TestRealm"], nil)
    H.ok(Mock.chatContains(env, "Removed Alt-TestRealm"))
end)

H.test("the new-character prompt waits for the welcome panel to close", function()
    local now = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
    local env, ns = boot(RETAIL, { characters = { ["Old-TestRealm"] = { name = "Old", level = 10, lastSeen = now - 40 * 86400 } } })
    H.ok(ns.Welcome.IsShown(), "welcome panel up")
    H.ok(not ns.StalePrompt.IsShown(), "prompt waits")
    for _, frame in pairs(env.__state.frames) do if frame._name == "FellowshipLedgerWelcome" then frame:Hide() end end
    Mock.runTimers(env)
    H.ok(ns.StalePrompt.IsShown(), "prompt after the welcome panel closes")
end)

H.test("/fl shots: every planned picture with fake data, then settings put back", function()
    local env, ns = boot()
    local taken, seen = 0, {}
    env.Screenshot = function()
        taken = taken + 1
        seen[#seen + 1] = { tab = ns.MainWindow.current, skin = ns.db.settings.skin, layout = ns.db.settings.detailsLayout,
            range = ns.MeTab.state.range,
            fake = ns.Data.IsFake(), banner = ns.MainWindow.fakeBanner:IsShown() }
    end
    ns.db.settings.skin, ns.db.settings.detailsLayout = "leather", "list"
    ns.MeTab.state.range = "today"
    ns.db.blocklist["Someone#1234"] = true
    Mock.slash(env, "shots")
    for _ = 1, 3 do Mock.runTimers(env) end
    noErrors(env)
    H.eq(taken, #ns.Screenshots.PLAN, "one picture per step: " .. table.concat(env.__state.chat, " | "))
    H.eq(#ns.db.dev.shots.steps, taken, "a record per picture")
    local cards, lists, opened = 0, 0, false
    for i, s in ipairs(seen) do
        H.eq(s.tab, ns.Screenshots.PLAN[i].tab)
        H.eq(s.skin, ns.Screenshots.PLAN[i].skin)
        H.ok(s.fake and not s.banner, "fake data without the banner")
        H.eq(s.range, "all", "the All range")
        if ns.Screenshots.PLAN[i].open then
            opened = true
            if s.layout == "card" then cards = cards + 1 else lists = lists + 1 end
        end
    end
    H.ok(opened and cards > 0 and lists > 0, "a card and a list")
    local skins = {}
    for _, s in ipairs(seen) do skins[s.skin] = true end
    H.ok(skins.ledger and skins.leather and skins.plain, "every skin")
    H.eq(ns.db.settings.skin, "leather", "skin back")
    H.eq(ns.db.settings.detailsLayout, "list", "layout back")
    H.eq(ns.MeTab.state.range, "today", "range back")
    H.ok(not ns.Data.IsFake(), "fake data off again")
    H.ok(not ns.Screenshots.active)
    H.ok(Mock.chatContains(env, "Screenshots done"))
end)

H.test("/fl shots: no Screenshot function, one message and nothing changed", function()
    local env, ns = boot()
    env.Screenshot = nil
    Mock.slash(env, "shots")
    H.ok(Mock.chatContains(env, "no Screenshot function"))
    H.ok(not ns.Data.IsFake() and not ns.Screenshots.active)
end)
