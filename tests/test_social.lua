-- Invite a friend (Core/Invites.lua, D-114), session goals (Core/Goals.lua, D-116),
-- personal bests (Core/Bests.lua) and the Leaderboard (Core/Leaderboard.lua, D-115).
local H = ...

-- Invite a friend ------------------------------------------------------------------

H.test("invites: online friends who never said hello, blocked ones left out, by name", function()
    local I = H.pureNamespace().Invites
    local peers = {
        ["bn:Zed#1"] = { kind = "bnet", name = "Zed", online = true, target = 11, character = "Zz-R" },
        ["bn:Amy#1"] = { kind = "bnet", name = "amy", online = true, target = 12 }, -- no character: D-066
        ["bn:Led#1"] = { kind = "bnet", name = "Ledger", online = true, target = 13 },
        ["bn:Off#1"] = { kind = "bnet", name = "Off", online = false },
        ["ch:Bob-R"] = { kind = "char", name = "Bob-R", online = true, target = "Bob", character = "Bob-R" },
        ["bn:Blk#1"] = { kind = "bnet", name = "Blk", online = true, target = 14 },
    }
    local friends = { ["bn:Led#1"] = { version = "1.7.2" }, ["bn:Zed#1"] = { characters = {} } }
    local list = I.Candidates(peers, friends, function(p) return p.name == "Blk" end)
    H.eq(#list, 3)
    H.eq(list[1].name, "amy"); H.eq(list[1].unknownGame, true, "Battle.net friend without a character")
    H.eq(list[2].name, "Bob-R"); H.eq(list[2].unknownGame, nil)
    H.eq(list[3].name, "Zed", "a stored friend that never said hello is still a candidate")
end)

H.test("invites: a week without the button, then the time still shows", function()
    local ns = H.pureNamespace()
    local I, L = ns.Invites, ns.L
    local now = 1800000000
    H.eq(I.Status(nil, now), nil)
    local s = I.Status(now - 3 * 86400, now)
    H.eq(s.waiting, true)
    H.eq(I.Line({ name = "Hamlet" }, s, L), "Hamlet - invited 3 days ago")
    s = I.Status(now - 15 * 86400, now)
    H.eq(s.waiting, false, "after a week Invite is back")
    H.eq(I.Line({ name = "Hamlet", character = "Cain-R" }, s, L), "Hamlet (Cain-R) - invited 2 weeks ago")
    H.eq(I.Ago(3600, L), "today"); H.eq(I.Ago(86400, L), "1 day ago"); H.eq(I.Ago(90 * 86400, L), "3 months ago")
    H.eq(I.Status(now - I.COOLDOWN, now).waiting, false, "exactly a week")
end)

H.test("invites: the message is one line, no escape codes, at most 255 characters", function()
    local ns = H.pureNamespace()
    local I = ns.Invites
    H.eq(I.Clean("  hi\nthere |cffff0000red  "), "hi there /cffff0000red")
    H.eq(I.Clean("   "), nil)
    H.eq(#I.Clean(string.rep("a", 400)), 255)
    H.ok(#ns.L.INVITE_MESSAGE <= I.MAX_LETTERS, "the default text fits in one whisper")
    H.eq(I.Clean(ns.L.INVITE_MESSAGE), ns.L.INVITE_MESSAGE, "the default text needs no cleaning")
end)
