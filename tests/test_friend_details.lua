-- Friends' characters opened like your own (D-083): the views built from what a
-- character shares, profession ranks on the wire, and the Friends tab in the mock window.
local H = ...
local ns = H.pureNamespace()
local S, L = ns.StatsModel, ns.L
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
local DATE = function(fmt, t) return os.date("!" .. fmt, t) end

local function textOf(parts)
    local out = {}
    for _, p in ipairs(parts) do
        local row = {}
        for _, s in ipairs(p.segs or p.segments or {}) do
            if s.button then row[#row + 1] = "[" .. s.button.label .. "]"
            elseif s.bar then row[#row + 1] = string.format("bar%.2f", s.bar)
            elseif s.text ~= "" then row[#row + 1] = s.text end
        end
        out[#out + 1] = table.concat(row, " | ")
    end
    return table.concat(out, "\n")
end

local ALL = { time = true, levels = true, quests = true, gold = true, kills = true, deaths = true, professions = true,
    dungeons = true, zones = true, reputation = true, flightPaths = true, achievements = true, items = true, partyLevels = true }

H.test("friends: overview has their levels and totals for the range; unshared parts say so", function()
    local char = { levels = {} }
    for to = 2, 13 do char.levels[to] = { from = to - 1, to = to, active = to * 60, total = to * 90 } end
    local data = ns.DetailModel.Data(char, L, DATE, {}, "->")
    data.summary.deaths = 3
    local sum = { played = 7200, active = 5400, quests = 9, deaths = 1, kills = 40, rareKills = 1, eliteKills = 2,
        dungeonsCompleted = 1, dungeonsEntered = 2, itemsNotable = 3, itemsEpic = 1 }
    local toggled
    local text = textOf(S.FriendOverview(data, sum, ALL, L, "Week", function() toggled = true end))
    H.ok(text:find("12 levels recorded", 1, true), text)
    H.ok(text:find("Recent levels | [Show all (12)] | Totals (Week)", 1, true), text)
    H.ok(text:find("12 -> 13 | 13m 00s | 19m 30s | Active | 1h 30m", 1, true), text)
    H.ok(text:find("Kills | 40 (1 rare, 2 elite)", 1, true), text)
    H.ok(text:find("Dungeons completed | 1 of 2", 1, true), text)
    H.ok(text:find("Notable loot | 3 (1 epic)", 1, true), text)
    H.ok(text:find("3 deaths in 90 days", 1, true), text)
    local some = { time = true, quests = true }
    text = textOf(S.FriendOverview(data, sum, some, L, "Week"))
    H.ok(text:find("This character does not share this.", 1, true), "levels not shared: " .. text)
    H.ok(text:find("Kills | not shared", 1, true), text)
    H.ok(text:find("Played | 2h 00m", 1, true), "time is always shared")
end)

H.test("friends: quests are counts plus their chains; kills without types; professions with ranks", function()
    local text = textOf(S.FriendQuests({ quests = 5, questsAccepted = 7, xp = 4200 },
        { ["q:1"] = { name = "Defias", step = 3, total = 7, firstName = "The Defias Brotherhood", startZone = "Westfall" } }, ALL, L))
    H.ok(text:find("5 quests turned in     7 accepted     4,200 XP", 1, true), text)
    H.ok(text:find("Defias | step 3 of 7 | The Defias Brotherhood, Westfall", 1, true), text)
    H.ok(textOf(S.FriendQuests({}, nil, {}, L)):find("does not share", 1, true))

    text = textOf(S.Kills({ kills = 12 }, { total = 300, rare = 2, elite = 5 }, "week", L, true))
    H.ok(text:find("12 kills", 1, true) and text:find("All time: 300", 1, true), text)
    H.ok(text:find("Kills by creature type are not shared", 1, true), text)

    local profs = { m = { name = "Mining", rank = 90, max = 150, lastAt = 3600 }, c = { name = "Cooking", rank = 30, max = 75 } }
    text = textOf(S.FriendProfessions({ skillUps = 6 }, profs, ALL, L, DATE))
    H.ok(text:find("6 skill-ups", 1, true), text)
    H.ok(text:find("Cooking | 30 / 75 | bar0.40", 1, true), text)
    H.ok(text:find("Mining | 90 / 150 | bar0.60 | 01-01, 01:00", 1, true), text)
    H.ok(textOf(S.FriendProfessions({ skillUps = 1 }, nil, ALL, L, DATE)):find("1.2.0 or later", 1, true), "older friend")
    H.ok(textOf(S.FriendProfessions({ skillUps = 1 }, nil, ALL, L, DATE, "1.1.0")):find("1.2.0 or later", 1, true), "1.1.0 is older")
    H.ok(textOf(S.FriendProfessions({}, nil, ALL, L, DATE, "1.2.1")):find("has no professions", 1, true),
        "a 1.2.x friend who sent none has none")
    H.ok(textOf(S.FriendProfessions({}, {}, ALL, L, DATE, "1.4.0")):find("has no professions", 1, true), "said outright")

    -- The codec: a character with no professions sends a bare "p"; it decodes to an empty set.
    local none = { class = "MAGE", level = 5, days = {}, levels = {}, sessions = {}, professions = {} }
    local body = ns.Codec.EncodeData("Vel-Testrealm", none, ALL, nil)
    local d = ns.Codec.DecodeData(body)
    H.ok(d.professions and next(d.professions) == nil, "no professions decodes to an empty set: " .. body)
    H.eq(ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Testrealm", none, {}, nil)).professions, nil, "not shared: nothing sent")
    -- A 1.2.x decoder (key required) skips the bare "p" record.
    H.ok(not body:find("~p,", 1, true), "the marker has no key field for old decoders to read")
    H.ok(textOf(S.FriendProfessions({}, profs, {}, L, DATE)):find("does not share", 1, true))
end)

H.test("friends: the tab row has no All completed, and has Dungeons", function()
    local line = S.TabLine("overview", L, function() end, S.FRIEND_TABS)
    H.eq(#line.segments, 6)
    H.eq(line.segments[5].button.label, "Professions")
    H.eq(line.segments[6].button.label, "Dungeons")
end)

H.test("profession ranks travel with Professions; older data and junk are fine", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local C = ns2.Codec
    local char = { class = "MAGE", level = 20, days = {}, levels = {}, sessions = {}, chains = {},
        professions = { ["186"] = { name = "Mining", rank = 87, max = 150, lastAt = 500, history = { { rank = 87, at = 500 } } } } }
    local d = C.DecodeData(C.EncodeData("Vel-Realm", char, { time = true, professions = true }, nil))
    H.eq(d.professions["186"].name, "Mining"); H.eq(d.professions["186"].rank, 87); H.eq(d.professions["186"].max, 150)
    H.eq(d.professions["186"].history, nil, "history stays home")
    H.eq(C.DecodeData(C.EncodeData("Vel-Realm", char, { time = true }, nil)).professions, nil, "not shared, not sent")
    H.eq(C.DecodeData("c,Vel-Doom,HUNTER,BloodElf,Horde,18,5,1~p,,x~p,").professions, nil, "junk ignored")
    local bare = C.DecodeData("c,Vel-Doom,HUNTER,BloodElf,Horde,18,5,1~p").professions
    H.ok(bare and next(bare) == nil, "a bare p means no professions (1.4.0+)")
    -- Merge keeps them only while Professions is shared.
    local mask = string.rep("1", #ns2.TrackerList.ORDER)
    local friend = { characters = {} }
    ns2.Merge.Data(friend, { key = "Vel-Realm", level = 20, mask = mask, days = {}, levels = {}, sessions = {}, chains = {},
        professions = d.professions }, "2026-11-05", "2026-08-01", 1000)
    H.eq(friend.characters["Vel-Realm"].professions["186"].rank, 87)
    ns2.Merge.Data(friend, { key = "Vel-Realm", level = 20, mask = string.rep("0", #ns2.TrackerList.ORDER), days = {}, levels = {},
        sessions = {}, chains = {} }, "2026-11-05", "2026-08-01", 1001)
    H.eq(friend.characters["Vel-Realm"].professions, nil, "stopped sharing")
end)

H.test("Friends tab: open a fake friend's character and go through every view", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false } }
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    Mock.slash(env, "fake")
    ns2.MainWindow.Open("friends")
    local F = ns2.FriendsTab
    local row
    for _, line in ipairs(F.ui.table.lines) do if line.kind == "row" and line.onClick then row = line break end end
    H.ok(row, "a clickable friend character row")
    row.onClick()
    local opened
    for id in pairs(F.state.expanded) do opened = id end
    H.ok(opened, "expanded")
    for _, v in ipairs(S.FRIEND_TABS) do
        F.state.detailView[opened] = v
        F.Refresh()
        local seen = {}
        for _, line in ipairs(F.ui.table.lines) do
            for _, s in ipairs(line.segments or {}) do if s.text and s.text ~= "" then seen[#seen + 1] = s.text end end
        end
        local text = table.concat(seen, " | ")
        H.ok(not text:find("does not share", 1, true), v .. ": fake friends share everything: " .. text)
        if v == "professions" then H.ok(text:find("Mining", 1, true), text) end
        if v == "overview" then H.ok(text:find("Totals (", 1, true), text) end
    end
    local chat = table.concat(env.__state.chat, "\n")
    H.ok(not chat:find("failed") and not chat:find("problem"), chat)
end)

H.test("column headers explain themselves on hover (Me and Friends)", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false } }
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    for _, tab in ipairs({ "me", "friends" }) do
        ns2.MainWindow.Open(tab)
        local t = (tab == "me" and ns2.MeTab or ns2.FriendsTab).ui.table
        local dungeons
        for c, col in ipairs(t.columns) do if col.field == "dungeons" then dungeons = t.headers[c] end end
        H.ok(dungeons and dungeons:GetScript("OnEnter"), tab .. ": Dungeons header has hover text")
        local col
        for _, cdef in ipairs(t.columns) do if cdef.field == "dungeons" then col = cdef end end
        H.ok(col.tip:find("Completed / entered", 1, true), col.tip)
        dungeons:GetScript("OnEnter")(dungeons)
        local name
        for _, c2 in ipairs(t.columns) do if c2.field == "name" then name = c2 end end
        H.eq(name.tip, nil, "no hover text where nothing needs explaining")
    end
end)

H.test("quest log IDs travel with Quests; empty logs and older senders are told apart", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local C = ns2.Codec
    local char = { class = "MAGE", level = 9, days = {}, levels = {}, sessions = {}, chains = {}, logQuests = { 53, 54, 900 } }
    local d = C.DecodeData(C.EncodeData("Zeryssa-Drowbear", char, { time = true, quests = true }, nil))
    H.eq(table.concat(d.logQuests, ","), "53,54,900")
    char.logQuests = {}
    H.eq(#C.DecodeData(C.EncodeData("Zeryssa-Drowbear", char, { time = true, quests = true }, nil)).logQuests, 0, "empty log")
    H.eq(C.DecodeData(C.EncodeData("Zeryssa-Drowbear", char, { time = true }, nil)).logQuests, nil, "not shared")
    H.eq(C.DecodeData("c,Old-Realm,MAGE,Human,Alliance,9,5,1").logQuests, nil, "an older sender sends none")
    local friend = { characters = {} }
    local all, none = string.rep("1", #ns2.TrackerList.ORDER), string.rep("0", #ns2.TrackerList.ORDER)
    ns2.Merge.Data(friend, { key = "Z-R", level = 9, mask = all, days = {}, levels = {}, sessions = {}, chains = {}, logQuests = { 54 } },
        "2026-11-05", "2026-08-01", 1)
    H.eq(friend.characters["Z-R"].logQuests[1], 54)
    ns2.Merge.Data(friend, { key = "Z-R", level = 9, mask = none, days = {}, levels = {}, sessions = {}, chains = {} }, "2026-11-05", "2026-08-01", 2)
    H.eq(friend.characters["Z-R"].logQuests, nil, "cleared when Quests is no longer shared")
end)

H.test("a friend without Questie: their chains are worked out here from their quest log", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false } }
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    local st = env.__state
    st.noQuestLines = true
    st.questieLoaded = true
    st.questie = { [70] = { next = 71, name = "Gnolls" }, [71] = { pre = 70, next = 72, name = "More Gnolls" }, [72] = { pre = 71, name = "Hogger" },
        [53] = { next = 54, name = "Start Here" }, [54] = { pre = 53, next = 60 }, [60] = { pre = 54 } }
    -- My own character saves its quest log for sharing.
    ns2.QuestChains.Snapshot()
    H.eq(table.concat(ns2.Store.char.logQuests, ","), "54")
    -- Like DrowBear on 1.2.1 without Questie: no chains sent, but the quest log is.
    local zer = { name = "Zeryssa", level = 12, mask = string.rep("1", #ns2.TrackerList.ORDER), chains = {}, logQuests = { 71, 54 }, days = {} }
    ns2.db.friends["bn:DrowBear#1411"] = { kind = "bnet", name = "DrowBear", characters = { ["Zeryssa-Drowbear"] = zer } }
    local chains = ns2.QuestChains.FriendChains(zer)
    H.eq(chains["q:70"].step, 2); H.eq(chains["q:70"].total, 3); H.eq(chains["q:70"].name, "Gnolls")
    H.ok(chains["q:53"], "the chain we are both on")
    -- Chains the friend sent win.
    zer.chains = { ["q:70"] = { name = "Gnolls (sent)", step = 2, total = 3, firstQuestID = 70 } }
    H.eq(ns2.QuestChains.FriendChains(zer)["q:70"].name, "Gnolls (sent)")
    zer.chains = {}
    -- In the Quest chains view: a suggestion for the chain I am not on, and "Friends on this chain" for mine.
    ns2.MainWindow.Open("me")
    local Me = ns2.MeTab
    Me.state.mode = "chains"
    local view = Me.ChainView()
    local suggested
    for _, f in ipairs(view.friends) do if f.key == "q:70" then suggested = f end end
    H.ok(suggested, "Gnolls suggested from DrowBear's quest log")
    H.eq(suggested.friend, "DrowBear")
    Me.state.chainOpen["q:53"] = true
    view = Me.ChainView()
    local mine
    for _, c in ipairs(view.mine) do if c.key == "q:53" then mine = c end end
    H.eq(mine.friendsOn[1].friend, "DrowBear", "friends on this chain")
    Me.Refresh()
    -- Their Quests tab lists it too.
    ns2.MainWindow.Open("friends")
    local F = ns2.FriendsTab
    local id = "bn:DrowBear#1411|Zeryssa-Drowbear"
    F.state.expanded[id], F.state.detailView[id] = true, "quests"
    F.Refresh()
    local seen = {}
    for _, line in ipairs(F.ui.table.lines) do
        for _, s in ipairs(line.segments or {}) do if s.text and s.text ~= "" then seen[#seen + 1] = s.text end end
    end
    H.ok(table.concat(seen, " | "):find("Gnolls", 1, true), table.concat(seen, " | "))
    local chat = table.concat(st.chat, "\n")
    H.ok(not chat:find("failed") and not chat:find("problem"), chat)
end)

H.test("dungeon runs travel with Dungeons: which dungeon, when, time, result, bosses, deaths only", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local C, M = ns2.Codec, ns2.Merge
    local E = os.time({ year = 2026, month = 11, day = 6, hour = 10, min = 2 })
    local char = { class = "PRIEST", level = 20, days = {}, levels = {}, sessions = {}, dungeons = {
        { name = "Ruins of Lordaeron", entered = E, duration = 2675, completed = true, bossCount = 6, deaths = 0,
          party = { { class = "MAGE", role = "DAMAGER", name = "Someone" } },
          bosses = { { name = "Witherfang", at = E + 300 }, { name = "Rath'mael", at = E + 1860 } } },
        { name = "Ragefire Chasm, Orgrimmar", entered = E - 3 * 86400, duration = 2278, deaths = 1, bosses = {} },
    } }
    local body = C.EncodeData("Tara-R", char, { time = true, dungeons = true }, nil)
    H.ok(not body:find("Witherfang", 1, true) and not body:find("Someone", 1, true) and not body:find("MAGE,", 1, true),
        "no boss names, nothing about the group: " .. body)
    local d = C.DecodeData(body)
    H.eq(#d.runs, 2)
    H.eq(d.runs[2].name, "Ruins of Lordaeron"); H.eq(d.runs[2].kills, 2); H.eq(d.runs[2].bossCount, 6)
    H.ok(d.runs[2].completed); H.eq(d.runs[2].duration, 2675)
    H.eq(d.runs[1].name, "Ragefire Chasm, Orgrimmar", "a comma in a name survives"); H.eq(d.runs[1].completed, nil); H.eq(d.runs[1].deaths, 1)
    H.eq(C.DecodeData(C.EncodeData("Tara-R", char, { time = true }, nil)).runs, nil, "not shared, not sent")
    H.eq(#C.DecodeData(C.EncodeData("Tara-R", char, { time = true, dungeons = true }, "2026-11-06")).runs, 1, "only runs since")
    -- Merge: upsert by entry time, cleared when Dungeons stops being shared.
    local mask = string.rep("1", #ns2.TrackerList.ORDER)
    local friend = { characters = {} }
    d.mask = mask
    M.Data(friend, d, "2026-11-06", "2026-08-09", E + 5000)
    local c = friend.characters["Tara-R"]
    H.eq(#c.runs, 2)
    local again = C.DecodeData(C.EncodeData("Tara-R", char, { time = true, dungeons = true }, "2026-11-06"))
    again.mask = mask
    M.Data(friend, again, "2026-11-06", "2026-08-09", E + 6000)
    H.eq(#c.runs, 2, "a later DATA with fewer runs keeps the others")
    local off = C.DecodeData(C.EncodeData("Tara-R", char, { time = true }, nil))
    off.mask = string.rep("0", #ns2.TrackerList.ORDER)
    M.Data(friend, off, "2026-11-06", "2026-08-09", E + 7000)
    H.eq(c.runs, nil, "cleared when not shared")
end)

H.test("a friend's Dungeons view: totals, runs, and older versions told apart", function()
    local DATE = os.date
    local E = os.time({ year = 2026, month = 11, day = 6, hour = 10, min = 2 })
    local runs = { { name = "Ruins of Lordaeron", entered = E, duration = 2675, completed = true, kills = 6, bossCount = 6, deaths = 0 },
        { name = "Ragefire Chasm", entered = E - 40000, duration = 2278, kills = 2, deaths = 1 } }
    local sum = { dungeonsEntered = 2, dungeonsCompleted = 1, bossKills = 8 }
    local text = textOf(S.FriendDungeons(sum, runs, ALL, L, DATE, "1.5.0"))
    H.ok(text:find("2 dungeons entered, 1 completed, 8 bosses killed", 1, true), text)
    H.ok(text:find("Ruins of Lordaeron | 45m | 6 / 6 | 0 | Completed", 1, true), text)
    H.ok(text:find("Ragefire Chasm | 38m | 2 | 1 | Not finished", 1, true), text)
    H.ok(text:find("Ruins", 1, true) < text:find("Ragefire", 1, true), "newest first")
    H.ok(textOf(S.FriendDungeons(sum, nil, ALL, L, DATE, "1.4.0")):find("1.5.0 or later", 1, true), "older friend")
    H.ok(textOf(S.FriendDungeons(sum, nil, ALL, L, DATE, "1.5.0")):find("No dungeon runs", 1, true), "new friend, no runs")
    H.ok(textOf(S.FriendDungeons(sum, runs, {}, L, DATE, "1.5.0")):find("does not share", 1, true))
    H.eq(S.FRIEND_TABS[#S.FRIEND_TABS], "dungeons")
end)
