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
    for _, skin in ipairs({ "plain", "ledger" }) do
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
