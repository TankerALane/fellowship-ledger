-- The 1.13.0 look: section titles in upper case (escape codes kept), the header's
-- friends line, the "This week" comparison with bars and crowns, Leaderboard bars.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
local ns = H.pureNamespace()
local F, FM = ns.Format, ns.FriendsModel
local L = setmetatable({ HEADER_STATUS = "%d of %d friends online, synced %s", HEADER_STATUS_ONE = "%d of %d friend online, synced %s",
    HEADER_NO_FRIENDS = "No ledger friends yet", NEVER = "never", COL_LEVELS = "Levels", COL_QUESTS = "Quests",
    COL_DUNGEONS = "Dungeons", COL_ACTIVE = "Active" }, { __index = function(_, k) return k end })

H.test("Format.Upper: text upper-cased, colors, textures and links left alone", function()
    H.eq(F.Upper("Recent levels"), "RECENT LEVELS")
    H.eq(F.Upper("|cff3b2a1aTotals|r (All)"), "|cff3b2a1aTOTALS|r (ALL)")
    local tex = "|TInterface\\AddOns\\FellowshipLedger\\media\\crown:0|t"
    H.eq(F.Upper(tex .. " best"), tex .. " BEST", "texture path kept")
    H.eq(F.Upper("|Hquest:12:5|h[Bounty]|h done"), "|Hquest:12:5|h[BOUNTY]|h DONE", "link data kept, shown text upper")
    H.eq(F.Upper(""), ""); H.eq(F.Upper(nil), nil)
end)

H.test("a friend's line: online with a green dot and who they play, offline all grey, no version (1.14.2)", function()
    local L2 = { ONLINE = "online", OFFLINE = "offline", FRIEND_PLAYING_ON = "online, playing %s",
        FRIEND_HEADER_REST = "%d characters, updated %s", FRIEND_HEADER_REST_ONE = "%d character, updated %s",
        AGO_JUST_NOW = "just now", AGO_MINUTES = "%dm ago", AGO_HOURS = "%dh ago", AGO_DAYS = "%dd ago", NEVER = "never" }
    setmetatable(L2, { __index = function(_, k) return k end })
    local o = { on = "<ON>", off = "<OFF>", good = "<G>", muted = "<M>" }
    local f = { name = "Fennick", online = true, playing = "Grimwald-Realm", version = "1.0.0", lastUpdated = 1000,
        characters = { ["Grimwald-Realm"] = { name = "Grimwald" }, ["Pip-Realm"] = { name = "Pip" } } }
    local t = FM.HeaderText(f, "x", 2, 1000, L2, o)
    H.ok(t:find("^<ON> Fennick  <G>online, playing Grimwald|r  %-  2 characters, updated "), t)
    H.ok(not t:find("1.0.0", 1, true), "no version")
    f.online = false
    t = FM.HeaderText(f, "x", 1, 1000, L2, o)
    H.ok(t:find("^<OFF> <M>Fennick  offline  %-  1 character, updated .*|r$"), t)
    f.online, f.playing = true, nil
    H.ok(FM.HeaderText(f, "x", 2, 1000, L2, o):find("<G>online|r", 1, true), "online, not on a shared character")
end)

H.test("header status: friends online of all (blocked not counted), last sync", function()
    local friends = { a = { name = "A", online = true }, b = { name = "B" }, c = { name = "C", tag = "C#3", online = true } }
    H.eq(FM.HeaderStatus(friends, { ["C#3"] = true }, 1000 - 30, 1000, L), "1 of 2 friends online, synced just now")
    H.eq(FM.HeaderStatus({ a = { name = "A" } }, {}, nil, 1000, L), "0 of 1 friend online, synced never")
    H.eq(FM.HeaderStatus({}, {}, nil, 1000, L), "No ledger friends yet")
end)

H.test("comparison: a bar per stat, the best gets the crown, zero gets no bar", function()
    local rows = { { name = "You", isMe = true, levels = 2, quests = 10, dungeons = 0, active = 3600 },
        { name = "Tobin", levels = 4, quests = 5, dungeons = 0, active = 1800 } }
    local lines = FM.CompareLines(rows, L, { crown = "<C>", duration = function(s) return s .. "s" end, inset = 18 })
    H.eq(#lines, 3, "header plus two people")
    H.eq(lines[1].segments[1].text, "Levels"); H.eq(lines[1].segments[4].text, "Active")
    local function texts(line)
        local t = {}
        for _, s in ipairs(line.segments) do if s.text then t[#t + 1] = s.text end end
        return t
    end
    local function bars(line)
        local t = {}
        for _, s in ipairs(line.segments) do if s.bar then t[#t + 1] = s.bar end end
        return t
    end
    H.eq(table.concat(texts(lines[2]), "|"), "You|2|<C> 10|0|<C> 3600s")
    H.eq(table.concat(texts(lines[3]), "|"), "Tobin|<C> 4|5|0|1800s")
    H.eq(lines[2].segments[1].role, "good", "you in the good color")
    local b = bars(lines[2])
    H.eq(#b, 3, "no bar for 0 dungeons"); H.eq(b[1], 0.5); H.eq(b[2], 1)
    -- Alone: no crowns.
    local one = FM.CompareLines({ rows[2] }, L, { crown = "<C>" })
    H.eq(table.concat(texts(one[2]), "|"), "Tobin|4|5|0|1800")
end)

H.test("Leaderboard: the fastest clear has the crown and a full bar, slower ones less", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    local now = env.time()
    local function run(at, clear)
        return { name = "The Deadmines", entered = at, completed = true, completedAt = at + clear, clear = clear,
            bossNames = { "A" }, splits = { { at = clear, fight = 10 } }, group = { levelMax = 20 } }
    end
    ns2.db.friends["bn:F#1"] = { kind = "bnet", name = "F", characters = { ["Zip-R"] = { name = "Zip", level = 20,
        runs = { run(now - 9000, 1200), run(now - 5000, 2400) } } } }
    ns2.LeaderboardTab.state.all = true
    local lines = ns2.LeaderboardTab.Lines()
    local clears = {}
    for _, l in ipairs(lines) do
        for _, s in ipairs(l.segments or {}) do if s.bar then clears[#clears + 1] = { line = l, bar = s.bar } end end
    end
    H.eq(#clears, 2, "a bar on each clear")
    H.eq(clears[1].bar, 1, "the fastest fills it"); H.eq(clears[2].bar, 0.5, "twice as slow, half")
    H.ok(clears[1].line.segments[1].text:find("crown", 1, true), "crown on #1: " .. clears[1].line.segments[1].text)
    H.ok(not clears[2].line.segments[1].text:find("crown", 1, true), "none on #2")
end)

H.test("Friends tab: a Battle.net friend folds to its header line; Collapse all and Open all", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    Mock.slash(env, "fake")
    ns2.MainWindow.Open("friends")
    local FT = ns2.FriendsTab
    local function heads()
        local out = {}
        for _, l in ipairs((FT.Lines())) do if l.kind == "group" and l.friendId then out[#out + 1] = l end end
        return out
    end
    local h = heads()
    H.ok(#h >= 2, "fake data has Battle.net friends")
    H.ok(h[1].text:find("^%- "), "open by default: " .. h[1].text)
    H.ok(FT.ui.allToggle:IsShown())
    H.eq(FT.ui.allToggle.text:GetText(), "Collapse all")
    local openCount = #FT.Lines()
    h[1].onClick()
    H.ok(heads()[1].text:find("^%+ "), "folded")
    H.ok(#FT.Lines() < openCount, "its characters are hidden")
    H.eq(ns2.db.settings.friendsCollapsed[h[1].friendId], true, "saved in settings")
    heads()[1].onClick()
    H.eq(#FT.Lines(), openCount, "open again")
    FT.ui.allToggle:GetScript("OnClick")()
    for _, l in ipairs((FT.Lines())) do
        H.ok(not (l.kind == "row" and l.indent), "no Battle.net friend's character shows")
    end
    H.eq(FT.ui.allToggle.text:GetText(), "Open all")
    FT.ui.allToggle:GetScript("OnClick")()
    H.eq(#FT.Lines(), openCount)
    H.eq(FT.ui.allToggle.text:GetText(), "Collapse all")
end)

H.test("Friends tab: This week compares you and friends side by side (fake data)", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    Mock.slash(env, "fake")
    ns2.MainWindow.Open("friends")
    local FT = ns2.FriendsTab
    -- 1.14.0: This week is a panel beside the list, shown by default; per stat a title,
    -- then a line per person with a bar.
    H.ok(FT.ui.week:IsShown(), "the panel is shown")
    local lines = FT.ui.weekTable.lines
    local section, people, crowns = false, 0, 0
    for _, l in ipairs(lines) do
        if l.kind == "group" and l.section and l.text:find("This week", 1, true) then section = true end
        if l.kind == "grid" and #l.segments == 3 and l.segments[2].bar then
            people = people + 1
            if l.segments[1].text:find("crown", 1, true) then crowns = crowns + 1 end
        end
    end
    H.ok(section, "This week as a section title")
    H.ok(people >= 2, "people compared: " .. people)
    H.ok(crowns >= 1, "at least one crown")
    FT.ui.weeklyButton:GetScript("OnClick")()
    H.ok(not FT.ui.week:IsShown(), "the button hides it")
    H.eq(ns2.MainWindow.status:GetText(), "", "fake data: the banner speaks, not the header")
end)
H.test("Leaderboard: highest-level dungeon first; a dungeon collapses to its #1, Collapse all and Open all", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    local now = env.time()
    local function run(name, at, clear)
        return { name = name, entered = at, completed = true, completedAt = at + clear, clear = clear,
            bossNames = { "A" }, splits = { { at = clear, fight = 10 } }, group = { levelMax = 20 } }
    end
    ns2.db.friends["bn:F#1"] = { kind = "bnet", name = "F", characters = { ["Zip-R"] = { name = "Zip", level = 30,
        runs = { run("Ragefire Chasm", now - 9000, 900), run("Blackfathom Deeps", now - 7000, 1800), run("The Deadmines", now - 5000, 1500) } } } }
    ns2.MainWindow.Open("leaderboard")
    local LT = ns2.LeaderboardTab
    LT.state.all = true
    local function heads()
        local t = {}
        for _, l in ipairs(LT.Lines()) do if l.dungeon then t[#t + 1] = l end end
        return t
    end
    local h = heads()
    H.eq(h[1].dungeon, "Blackfathom Deeps"); H.eq(h[2].dungeon, "The Deadmines"); H.eq(h[3].dungeon, "Ragefire Chasm")
    local openCount = #LT.Lines()
    -- Click a title: it closes to one line with its #1.
    h[2].onClick()
    H.ok(LT.state.collapsed["The Deadmines"])
    local closed = heads()[2]
    H.ok(closed.segments[1].text:find("^%+ The Deadmines"), closed.segments[1].text)
    H.ok(closed.segments[2].text:find("25m 00s", 1, true), closed.segments[2].text)
    H.ok(#LT.Lines() < openCount, "fewer lines")
    heads()[2].onClick()
    H.eq(LT.state.collapsed["The Deadmines"], nil, "open again")
    -- Collapse all, then Open all.
    LT.ui.allToggle:GetScript("OnClick")()
    H.eq(#LT.Lines(), 3, "only the three titles")
    H.eq(LT.ui.allToggle.text:GetText(), "Open all")
    LT.ui.allToggle:GetScript("OnClick")()
    H.eq(#LT.Lines(), openCount)
    H.eq(LT.ui.allToggle.text:GetText(), "Collapse all")
    -- Folded dungeons are saved, so they stay folded after a /reload.
    heads()[1].onClick()
    H.eq(ns2.db.settings.leaderCollapsed["Blackfathom Deeps"], true, "saved in settings")
    LT.state.collapsed = {} -- what a reload leaves in memory
    H.ok(heads()[1].segments[1].text:find("^%+ Blackfathom"), "still folded after a reload")
    heads()[1].onClick()
end)
H.test("Dungeons: your own role counts in With; an old run works it out from the group", function()
    local ns3 = H.pureNamespace()
    local DM = ns3.DungeonsModel
    local L = { DUNGEONS_TANKS = "%d tank", DUNGEONS_HEALERS = "%d healer", DUNGEONS_DAMAGE = "%d damage",
        DUNGEONS_OTHERS = "%d other", DUNGEONS_SOLO = "solo" }
    local four = { { role = "DAMAGER" }, { role = "TANK" }, { role = "DAMAGER" }, { role = "DAMAGER" } }
    H.eq(DM.Group(four, L), "1 tank, 3 damage")
    local me, guessed = DM.MyRole({ party = four })
    H.eq(me, "HEALER"); H.eq(guessed, true)
    H.eq(DM.Group(four, L, me), "1 tank, 1 healer, 3 damage")
    H.eq(DM.MyRole({ party = four, role = "DAMAGER" }), "DAMAGER", "the saved role wins")
    H.eq(DM.MyRole({ party = { { role = "TANK" }, { role = "DAMAGER" } } }), nil, "not a full group")
    H.eq(DM.MyRole({ party = { { role = "TANK" }, { role = "TANK" }, { role = "DAMAGER" }, { role = "DAMAGER" } } }), nil, "no clear gap")
    H.eq(DM.Group({}, L, "HEALER"), "solo", "solo stays solo")
end)
H.test("Leaderboard: a run with no recorded group level uses the character's level that day", function()
    local ns3 = H.pureNamespace()
    local LB = ns3.Leaderboard
    local levels = { [15] = { at = 1000 }, [16] = { at = 2000 }, [34] = { at = 9000 } }
    H.eq(LB.LevelAt(levels, 1500), 15); H.eq(LB.LevelAt(levels, 2000), 16); H.eq(LB.LevelAt(levels, 9500), 34)
    H.eq(LB.LevelAt(levels, 500), nil, "before any known level-up"); H.eq(LB.LevelAt(nil, 500), nil)
    local function run(entered, levelMax)
        return { name = "Ragefire Chasm", entered = entered, completed = true, clear = 1200, levelMax = levelMax }
    end
    local friends = { ["bn:H#1"] = { name = "Hamlet", characters = { ["Alastair-Ratt"] = { name = "Alastair", levels = levels,
        runs = { run(2500), run(9500), run(30000, 34) } } } } }
    local board = LB.Build(LB.Entries({}, friends), true)
    H.eq(#board, 1)
    H.eq(#board[1].clears, 1, "only the run at level 16 is at level")
    H.eq(board[1].clears[1].levelMax, 16); H.eq(board[1].clears[1].levelGuess, true)
    local all = LB.Build(LB.Entries({}, friends), false)
    H.eq(#all[1].clears, 3, "all runs keep the level-34 ones")
    local recorded
    for _, e in ipairs(all[1].clears) do if e.finishedAt == 30000 + 1200 then recorded = e end end
    H.eq(recorded.levelGuess, nil, "a recorded level is not a guess")
end)
H.test("Plain look: a Ledger user moves once and is told; the opacity slider sets the background", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { skin = "ledger", welcomeEveryLogin = false, askStale = false } }
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    H.eq(ns2.db.settings.skin, "plain")
    H.ok(Mock.chatContains(env, "now uses the Plain look"), table.concat(env.__state.chat, "\n"))
    H.eq(ns2.db.settings.lookMovedNotice, nil, "told once")
    ns2.MainWindow.Open("settings")
    local ui = ns2.SettingsTab.ui
    H.eq(ui.opacityValue:GetText(), "92% solid", "Plain's own opacity")
    ui.opacity:GetScript("OnValueChanged")(ui.opacity, 1.0)
    H.eq(ns2.db.settings.opacity, 1)
    H.eq(ui.opacityValue:GetText(), "100% solid")
    H.eq(ns2.Widgets.Opacity(), 1)
end)
H.test("Settings in sub-tabs: one page at a time, switch rows, notice counts, tracker switches", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    ns2.MainWindow.Open("settings")
    local ST, ui = ns2.SettingsTab, ns2.SettingsTab.ui
    H.eq(ST.state.page, "general")
    H.ok(ui.pages.general:IsShown()); H.ok(not ui.pages.notices:IsShown())
    -- The sub-tab buttons switch pages.
    ui.tabs.buttons.notices:GetScript("OnClick")()
    H.eq(ST.state.page, "notices")
    H.ok(ui.pages.notices:IsShown()); H.ok(not ui.pages.general:IsShown())
    -- A click on a switch row flips its setting and the card's count follows.
    local row
    for _, r in ipairs(ui.toggles) do if type(r.text) == "table" and r.text:GetText() == "Also in chat" then row = r end end
    H.ok(row, "the chat row")
    local before = ns2.db.settings.toastChat == true
    local countBefore = ui.counts[1].card.count:GetText()
    row:GetScript("OnClick")(row)
    H.eq(ns2.db.settings.toastChat == true, not before)
    H.ok(ui.counts[1].card.count:GetText() ~= countBefore, "count changed")
    H.ok(ui.counts[1].card.count:GetText():find("^%d+ of 7 on$"), ui.counts[1].card.count:GetText())
    -- Clicking the switch itself does the same as the row.
    row.switch:GetScript("OnClick")(row.switch)
    H.eq(ns2.db.settings.toastChat == true, before)
    -- Tracking: the Track switch turns a tracker off for this character; Share dims.
    ST.Show("tracking")
    local levels = ui.trackerRows[1]
    H.eq(levels.id, "levels")
    local c = ns2.db.characters[ns2.Store.key]
    levels.track:GetScript("OnClick")(levels.track)
    H.eq(c.flags.levels.track, false)
    H.ok(levels.share.disabled, "share dimmed without tracking")
    H.eq(levels.what:GetText(), "time per level, XP by source")
    levels.track:GetScript("OnClick")(levels.track)
    H.eq(c.flags.levels.track, true)
    -- Look: the look buttons are joined, Plain first.
    ST.Show("look")
    ui.skin.buttons.leather:GetScript("OnClick")()
    H.eq(ns2.db.settings.skin, "leather")
    H.ok(ui.skin.buttons.leather.selected)
end)

H.test("Friends: two-line rows; a friend's character opens as its own page with Back", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    Mock.slash(env, "fake")
    ns2.MainWindow.Open("friends")
    local FT = ns2.FriendsTab
    local row
    for _, l in ipairs(FT.ui.table.lines) do if l.kind == "row" and l.badge then row = l break end end
    H.ok(row, "a character row with its level ring")
    H.ok(row.sub and row.sub ~= "", "a grey line under the name")
    H.ok(row.indent, "indented under the friend's name")
    H.ok(type(row.badgeProgress) == "number", "fake characters are part-way through their level")
    -- The ring (1.14.5, D-145): 20 pieces, filled clockwise from the top; a dot at the start.
    local W = ns2.Widgets
    local badge = env.CreateFrame("Frame")
    badge.ring = badge:CreateTexture()
    W.LevelRing(badge, 24)
    badge:SetLevelProgress(0.5, { 1, 1, 1, 1 })
    H.eq(badge.filled, 10)
    H.ok(badge.startDot:IsShown() and not badge.ring:IsShown() and badge.segments[20]:IsShown(), "pieces, not the plain circle")
    badge:SetLevelProgress(0, { 1, 1, 1, 1 })
    H.eq(badge.filled, 0); H.ok(badge.startDot:IsShown(), "a fresh level: just the dot lit")
    badge:SetLevelProgress(nil, { 1, 1, 1, 1 })
    H.ok(badge.ring:IsShown() and not badge.startDot:IsShown() and not badge.segments[1]:IsShown(), "unknown: the plain circle")
    H.eq(W.RingFilled(0.999), 19); H.eq(W.RingFilled(0.05), 1); H.eq(W.RingFilled(1), 20)
    row.onClick()
    H.ok(FT.ui.page:IsShown() and FT.ui.views:IsShown(), "the page head and its tabs")
    H.ok(not FT.ui.week:IsShown(), "no This week panel on a page")
    H.ok(FT.ui.page.sub:GetText():find("'s character", 1, true), FT.ui.page.sub:GetText())
    for _, l in ipairs(FT.ui.table.lines) do
        for _, s in ipairs(l.segments or {}) do H.ok(not (s.button and s.button.fill), "no old tab row on the page") end
    end
    FT.ui.views.buttons.gold:GetScript("OnClick")()
    H.eq(FT.state.detailView[FT.PageId()], "gold")
    FT.ui.page.back:GetScript("OnClick")()
    H.ok(not FT.ui.page:IsShown() and FT.ui.week:IsShown(), "back to the list and This week")
end)
