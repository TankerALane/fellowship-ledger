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
    H.ok(textOf(S.FriendProfessions({}, profs, {}, L, DATE)):find("does not share", 1, true))
end)

H.test("friends: the tab row has no All completed", function()
    local line = S.TabLine("overview", L, function() end, S.FRIEND_TABS)
    H.eq(#line.segments, 5)
    H.eq(line.segments[5].button.label, "Professions")
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
    H.eq(C.DecodeData("c,Vel-Doom,HUNTER,BloodElf,Horde,18,5,1~p~p,,x").professions, nil, "junk ignored")
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
