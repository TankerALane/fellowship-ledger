-- Friend notices, the session recap and the tooltip line (D-099). Pure logic only;
-- how the notices look and that clicks open the right page is on Austin's checklist.
local H = ...
local ns = H.pureNamespace()
local N, L = ns.Notices, ns.L

local function item(kind, friend, key, extra)
    local e = { kind = kind, character = key and key:match("^[^-]+") or nil, key = key }
    for k, v in pairs(extra or {}) do e[k] = v end
    return { event = e, friendName = friend, friendId = "bn:" .. friend, }
end

local ON = ns.SettingsDefaults.Ensure({})

H.test("notice text for every kind", function()
    H.eq(N.Text({ kind = "level", character = "Cain", level = 30 }, "Hamlet", L), "Cain (Hamlet) reached level 30!")
    H.eq(N.Text({ kind = "levels", character = "Cain", from = 42, to = 45 }, "Hamlet", L), "Cain (Hamlet) went from level 42 to 45")
    H.eq(N.Text({ kind = "joined" }, "Hamlet", L), "Hamlet now runs Fellowship Ledger and shares with you.")
    H.eq(N.Text({ kind = "dungeon", character = "Cain", dungeon = "Deadmines" }, "Hamlet", L), "Cain (Hamlet) cleared Deadmines!")
end)

H.test("select: settings, level gains only while away, sorted by friend", function()
    local items = {
        item("dungeon", "Zed", "Zar-R", { dungeon = "Deadmines" }),
        item("levels", "Hamlet", "Cain-R", { from = 8, to = 11 }),
        item("level", "Hamlet", "Cain-R", { level = 10 }),
        item("profession", "Amy", "Ash-R", { rank = 150, profession = "Mining" }),
    }
    local out = N.Select(items, ON, false)
    H.eq(#out, 3, "no level gain outside the away notice")
    H.eq(out[1].friendName, "Amy"); H.eq(out[2].friendName, "Hamlet"); H.eq(out[3].friendName, "Zed")
    out = N.Select(items, ON, true)
    H.eq(#out, 3, "away: the gain replaces the every-10 line")
    H.eq(out[2].event.kind, "levels")
    local off = ns.SettingsDefaults.Ensure({ friendToastsDungeons = false, awayDigest = false })
    out = N.Select(items, off, true)
    H.eq(#out, 2, "dungeon notice off; away digest off drops the gain")
    H.eq(out[2].event.kind, "level")
end)

H.test("build: one notice, a bundle, more than fit, and where a click goes", function()
    local one = { item("chain", "Hamlet", "Cain-R", { chain = "The Family Crypt" }) }
    local title, lines, target = N.Build(one, L, false)
    H.eq(title, L.FRIEND_MILESTONE_TITLE)
    H.eq(#lines, 1)
    H.eq(target.friendId, "bn:Hamlet"); H.eq(target.key, "Cain-R"); H.eq(target.view, "quests")
    local two = { one[1], item("dungeon", "Hamlet", "Cain-R", { dungeon = "Deadmines" }) }
    title, lines, target = N.Build(two, L, false)
    H.eq(title, "2 friend notices")
    H.eq(target.key, "Cain-R"); H.eq(target.view, "overview", "mixed kinds open the overview")
    local many = {}
    for i = 1, 7 do many[i] = item("level", "F" .. i, "C" .. i .. "-R", { level = 10 }) end
    title, lines, target = N.Build(many, L, true)
    H.eq(title, L.AWAY_TITLE)
    H.eq(#lines, N.MAX_LINES)
    H.eq(lines[#lines], string.format(L.FRIEND_BUNDLE_MORE, 3))
    H.eq(target.friendId, nil, "several friends: just the Friends tab")
    H.eq(N.Build({}, L, false), nil)
    local joined = { item("joined", "Hamlet") }
    H.eq((N.Build(joined, L, false)), L.FRIEND_JOINED_TITLE)
end)

H.test("away window", function()
    H.ok(N.IsAway(ON, 1000, 1000 + N.AWAY_SECONDS))
    H.ok(not N.IsAway(ON, 1000, 1001 + N.AWAY_SECONDS))
    H.ok(not N.IsAway({ awayDigest = false }, 1000, 1001))
    H.ok(not N.IsAway(ON, nil, 1001))
end)

H.test("session recap line", function()
    local S = ns.Summary
    H.eq(S.Recap({ played = 30, counts = {} }, L), nil, "nothing yet")
    H.eq(S.Recap({ played = 4320, counts = { levels = 2, quests = 1, dungeonsEntered = 1, deaths = 3 } }, L),
        "This session: " .. ns.Format.Duration(4320) .. ", 2 levels, 1 quest, 1 dungeon, 3 deaths")
    H.eq(S.Recap(nil, L), nil)
end)

H.test("tooltip line and finding a friend's character", function()
    local M = ns.FriendsModel
    local friends = { ["bn:H"] = { name = "Hamlet", tag = "Hamlet#1", characters = { ["Cain-R"] = { days = {} } } } }
    local id, f = M.FindCharacter(friends, {}, "Cain-R")
    H.eq(id, "bn:H"); H.eq(f.name, "Hamlet")
    H.eq(M.FindCharacter(friends, {}, "Nope-R"), nil)
    H.eq(M.FindCharacter(friends, { ["Hamlet#1"] = true }, "Cain-R"), nil, "blocked friends are skipped")
    H.eq(M.TooltipLine(f, { quests = 12, dungeonsCompleted = 2 }, L), "Ledger: Hamlet's character, 12 quests and 2 dungeons this week")
    H.eq(M.TooltipLine(f, {}, L), "Ledger: Hamlet's character")
end)
