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

-- Personal bests --------------------------------------------------------------------

local function fmt(ns) return { Duration = ns.Format.Duration, Number = ns.Format.Number } end

H.test("bests: the first fill is quiet, a beaten record of another day is reported", function()
    local ns = H.pureNamespace()
    local B, L = ns.Bests, ns.L
    local store = B.New()
    local a = { days = { ["2026-11-01"] = { quests = 20, kills = 50 } },
        levels = { [10] = { active = 1800, at = 1 }, [11] = { active = 30, at = 2 }, [12] = { active = 900, partial = true } },
        sessions = { { start = 100, active = 3600, counts = { levels = 2 } } },
        dungeons = { { name = "The Deadmines", entered = 1000, completed = true, completedAt = 2500 } } }
    H.eq(#B.Update(store, a, "A-R", true), 0, "first fill")
    store.filled = true
    H.eq(store.level[10].value, 1800); H.eq(store.level[11], nil, "too fast to be real"); H.eq(store.level[12], nil, "partial")
    H.eq(store.dungeon["The Deadmines"].value, 1500)
    -- Another character, another day: quests and level 10 beaten, kills not.
    local b = { days = { ["2026-11-05"] = { quests = 25, kills = 10 } }, levels = { [10] = { active = 1500, at = 3 } },
        dungeons = { { name = "The Deadmines", entered = 0, completed = true, completedAt = 1400 } } }
    local beaten = B.Update(store, b, "B-R", true)
    H.eq(#beaten, 3)
    local text = {}
    for _, x in ipairs(beaten) do text[#text + 1] = B.Text(x, L, fmt(ns)) end
    table.sort(text)
    H.eq(text[1], "25 quests in one day (best was 20)")
    H.eq(text[2], "Level 10 in 25m 00s, 5m 00s faster than your best")
    H.eq(text[3], "The Deadmines cleared in 23m 20s, 1m 40s faster than your best")
    H.eq(store.day.quests.holder, "B-R")
end)

H.test("bests: a record growing within its own day or session is not a new one", function()
    local B = H.pureNamespace().Bests
    local store = B.New()
    local c = { days = { ["2026-11-05"] = { quests = 5 } }, sessions = { { start = 100, active = 600, counts = {} } } }
    B.Update(store, c, "A-R")
    store.filled = true
    c.days["2026-11-05"].quests = 9
    c.sessions[1].active = 900
    H.eq(#B.Update(store, c, "A-R"), 0, "same day, same session")
    H.eq(store.day.quests.value, 9, "but the record moves up")
    c.days["2026-11-06"] = { quests = 10 }
    H.eq(#B.Update(store, c, "A-R"), 1, "a new day beats it")
end)

H.test("bests: rows show this character, all characters and the holder", function()
    local ns = H.pureNamespace()
    local B, L = ns.Bests, ns.L
    local all, mine = B.New(), B.New()
    local me = { days = { d = { quests = 4 } }, levels = { [5] = { active = 600 } } }
    me.days = { ["2026-11-02"] = { quests = 4 } }
    B.Update(mine, me, "Me-R", false)
    B.Update(all, me, "Me-R", true)
    B.Update(all, { days = { ["2026-11-03"] = { quests = 9 } } }, "Alt-R", true)
    local rows = B.Rows(mine, all, L, fmt(ns), function() return "x" end, me.levels)
    local quests, level
    for _, r in ipairs(rows) do
        if r.label == "Quests" then quests = r end
        if r.label == "Level 4 -> 5" then level = r end
    end
    H.eq(quests.mine, "4"); H.eq(quests.all, "9"); H.eq(quests.holder, "Alt-R"); H.eq(quests.when, "2026-11-03")
    H.eq(quests.mineIsAll, nil)
    H.eq(level.mine, "10m 00s"); H.eq(level.mineIsAll, true)
    H.eq(mine.level[5], nil, "a character's own store has no level records")
    for _, f in ipairs(B.DAY_FIELDS) do
        H.ok(ns.L["BEST_DAY_" .. f:upper()] and ns.L["BESTS_DAY_" .. f:upper()], "strings for " .. f)
    end
end)

H.test("bests in the mock client: filled at login, a beaten record gives one notice", function()
    local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false, sessionSummary = false } }
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    H.ok(ns.db.bests and ns.db.bests.filled, "filled at login")
    -- An old day with 2 quests, then 3 today: a new record.
    ns.Store.char.days["2026-10-01"] = { quests = 2 }
    H.eq(#ns.Records.Check(), 0, "an old day that nobody saw before is not a beaten record")
    ns.Store.Count("quests", 3)
    local beaten = ns.Records.Check()
    H.eq(#beaten, 1)
    H.eq(beaten[1].key, "quests")
    H.eq(#ns.Records.Check(), 0, "not again for the same day")
    H.eq(ns.Store.char.bests.day.quests.value, 3, "the character's own store too")
end)

-- Session goals ---------------------------------------------------------------------

local function sessions(n, active, counts)
    local list = {}
    for i = 1, n do list[i] = { start = i * 10000, active = active, counts = counts or { quests = 10, levels = 1, skillUps = 6 } } end
    return list
end

H.test("goals: ready after 3 sessions of 20+ active minutes, the current one not counted", function()
    local G = H.pureNamespace().Goals
    local list = sessions(2, 1500)
    list[#list + 1] = { start = 99, active = 600, counts = {} } -- too short
    H.eq(G.Ready(list, nil), false)
    list[#list + 1] = { start = 500, active = 5000, counts = {} }
    H.eq(G.Ready(list, 500), false, "the session being played")
    H.eq(G.Ready(list, nil), true)
    local _, n = G.Ready(list, 500)
    H.eq(n, 2)
end)

H.test("goals: XP per hour follows the part of a level per hour, so it grows with the level", function()
    local G = H.pureNamespace().Goals
    -- Levels near 10 took 30 minutes each: 2 levels per hour.
    local levels = { [9] = { active = 1800 }, [10] = { active = 1800 }, [30] = { active = 7200 }, [8] = { active = 900, partial = true } }
    H.eq(G.Pace(levels, 10), 2)
    H.eq(G.Pace(levels, 30), 0.5, "only levels within 5")
    H.eq(G.Pace({ [50] = { active = 3600 } }, 10), 1, "falls back to any full level")
    local low = G.Suggest({ level = 10, xpMax = 7000, sessions = sessions(3, 3600), levels = levels })
    local high = G.Suggest({ level = 10, xpMax = 70000, sessions = sessions(3, 3600), levels = levels })
    H.eq(low[1].kind, "xphour"); H.eq(low[1].target, 14000)
    H.eq(high[1].target, 140000, "ten times the XP per level, ten times the goal")
    H.eq(low[2].kind, "levels"); H.eq(low[2].target, 2, "2 levels an hour in a typical 1-hour session")
    H.eq(low[3].kind, "quests"); H.eq(low[3].target, 11, "usual 10, a little more")
    H.eq(#G.Suggest({ level = 60, maxLevel = 60, xpMax = 0, sessions = sessions(3, 3600), levels = levels }), 1,
        "at the level cap: only quests")
end)

H.test("goals: a dungeon in range not yet cleared, professions not maxed", function()
    local ns = H.pureNamespace()
    local G, DL = ns.Goals, ns.DungeonLevels
    H.eq(DL.InRange(20)[1], "The Deadmines")
    local list = G.Suggest({ level = 20, sessions = sessions(3, 3600), dungeons = DL.InRange(20),
        cleared = { ["The Deadmines"] = true },
        professions = { [164] = { name = "Blacksmithing", rank = 100, max = 150 }, [186] = { name = "Mining", rank = 150, max = 150 } } })
    local kinds = {}
    for _, g in ipairs(list) do kinds[g.kind] = g end
    H.eq(kinds.dungeon.name, "Wailing Caverns", "the Deadmines was cleared")
    H.eq(kinds.dungeon.on, false, "not ticked by default")
    H.eq(kinds.profession.name, "Blacksmithing"); H.eq(kinds.profession.target, 106)
    H.eq(G.Adjust(kinds.profession, -1), 105)
    for _ = 1, 10 do G.Adjust(kinds.profession, -1) end
    H.eq(kinds.profession.target, 101, "never below one point up")
    for _ = 1, 100 do G.Adjust(kinds.profession, 1) end
    H.eq(kinds.profession.target, 150, "never above the cap")
end)

H.test("goals: progress, the Me tab line and the results at the next login", function()
    local ns = H.pureNamespace()
    local G, L = ns.Goals, ns.L
    local f = { Number = ns.Format.Number }
    local start = { levelPos = 10.5, xp = 1000, quests = 2, active = 100, at = 50, ranks = { [164] = 100 } }
    local set = { list = {
        { kind = "xphour", target = 10000, start = start },
        { kind = "levels", target = 1, start = start },
        { kind = "quests", target = 5, start = start },
        { kind = "dungeon", name = "The Deadmines", target = 1, start = start },
        { kind = "profession", key = 164, name = "Blacksmithing", target = 105, start = start } } }
    local now = { levelPos = 11.6, xp = 7000, quests = 6, active = 1900, cleared = { ["The Deadmines"] = 40 }, ranks = { [164] = 105 } }
    local v, d = G.Progress(set.list[1], now)
    H.eq(v, 12000); H.eq(d, true)
    v, d = G.Progress(set.list[4], now)
    H.eq(d, false, "a clear before the goals started does not count")
    now.cleared["The Deadmines"] = 60
    H.eq(select(2, G.Progress(set.list[4], now)), true)
    H.eq(G.Line(set, now, L, f), "Goals (4 of 5 done): (done) XP per hour 12,000 / 10,000; (done) Levels 1.1 / 1.0; "
        .. "Quests 4 / 5; (done) Clear The Deadmines; (done) Blacksmithing 105 / 105")
    local early = { levelPos = 10.5, xp = 1500, quests = 2, active = 400, ranks = {} }
    H.eq(select(2, G.Progress(set.list[1], early)), false, "XP per hour waits for 10 active minutes")
    set.last = { { value = 12000, done = true }, { value = 0.4 } }
    local res = G.Results({ list = { set.list[1], set.list[2] }, last = set.last }, L, f)
    H.eq(res[1], "Goals: 1 of 2 done"); H.eq(res[3], "  Levels 0.4 / 1.0")
    for _, k in ipairs({ "GOAL_HINT_XPHOUR", "GOAL_HINT_XPHOUR_RESTED", "GOAL_HINT_LEVELS", "GOAL_HINT_QUESTS",
        "GOAL_HINT_DUNGEON", "GOAL_HINT_PROFESSION" }) do H.ok(rawget(L, k), k) end
end)

H.test("goals in the mock client: off by default, /fl goals waits for 3 sessions, then Start", function()
    local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false, sessionSummary = false } }
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    H.eq(ns.db.settings.goals, false, "off by default")
    Mock.slash(env, "goals")
    H.ok(Mock.chatContains(env, "3 sessions of 20 minutes or more (0 so far)"), "says why")
    local char = ns.Store.char
    for i = 1, 3 do table.insert(char.sessions, 1, { start = i, stop = i, active = 3600, played = 3600, counts = { quests = 8 } }) end
    char.levels[2] = { active = 600 }
    H.eq(ns.SessionGoals.Open(true), true, "the window opens")
    ns.SessionGoals.Begin(ns.Goals.Suggest(ns.SessionGoals.Info()))
    local set = ns.SessionGoals.Current()
    H.ok(set and #set.list >= 2, "goals set for this session")
    ns.Store.Count("quests", 20)
    ns.SessionGoals.Tick()
    H.ok(ns.SessionGoals.Line():find("Quests 20 / 9", 1, true), ns.SessionGoals.Line())
    H.eq(#ns.SessionGoals.ResultsFor(ns.Store.session) > 0, true, "results for the summary")
end)

-- Leaderboard -----------------------------------------------------------------------

local T0 = 1800000000

-- One of my runs: entered at T0 + off, clear seconds, party and bosses.
local function myRun(name, off, clear, extra)
    local r = { name = name, entered = T0 + off, completed = true, completedAt = T0 + off + clear, bosses = {}, party = {} }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

H.test("leaderboard: one run seen by me and a friend is shown once, with both names", function()
    local ns = H.pureNamespace()
    local LB, L = ns.Leaderboard, ns.L
    local chars = { ["Me-R"] = { name = "Austin", dungeons = {
        myRun("The Deadmines", 0, 1500, { levelMax = 21, party = { { class = "ROGUE", name = "Cain", friend = true, level = 21 },
            { class = "MAGE" }, { class = "PRIEST" }, { class = "WARRIOR", npc = true } },
            bosses = { { name = "Rhahk'Zor", fight = 40, at = T0 + 300 }, { name = "Edwin VanCleef", fight = 130, at = T0 + 1500 } } }),
    } } }
    -- Hamlet's Cain was in that run: he entered 2 minutes later, and shares the same final boss.
    local friends = { ["bn:Ham#1"] = { name = "Hamlet", characters = { ["Cain-R"] = { name = "Cain", runs = {
        { name = "The Deadmines", entered = T0 + 120, completed = true, clear = 1380, size = 4, levelMax = 21, names = { "Austin" },
          splits = { { at = 170, fight = 35 }, { at = 1380, fight = 130 } }, bossNames = { "Rhahk'Zor", "Edwin VanCleef" } },
    } } } } }
    local board = LB.Build(LB.Entries(chars, friends), true)
    H.eq(#board, 1)
    local d = board[1]
    H.eq(#d.clears, 1, "one run, not two")
    local e = d.clears[1]
    H.eq(e.clear, 1500, "the longest report: joining late does not make a run faster")
    H.eq(LB.Group(e, L), "Austin, Cain, +2", "names from both, strangers counted, the companion left out")
    H.eq(e.mine, true)
    H.eq(d.bosses[1].name, "Rhahk'Zor"); H.eq(d.bosses[1].fight, 35, "the fastest kill of each boss")
    H.eq(d.bosses[2].name, "Edwin VanCleef", "bosses in the order they die")
    H.eq(d.range[1], 15)
end)

H.test("leaderboard: top 5 by clear time, over-level runs only under All runs", function()
    local ns = H.pureNamespace()
    local LB = ns.Leaderboard
    local runs = {}
    for i = 1, 7 do runs[i] = myRun("The Deadmines", i * 86400, 1000 + i * 100, { levelMax = 22 }) end
    runs[8] = myRun("The Deadmines", 9 * 86400, 600, { levelMax = 26 }) -- 4 over 22: a carry
    runs[9] = myRun("The Deadmines", 10 * 86400, 700, { levelMax = 25 }) -- 3 over: still at level
    runs[10] = myRun("The Deadmines", 11 * 86400, 30) -- too short to be a real clear
    runs[11] = myRun("Hall of Thanes", 12 * 86400, 900, { levelMax = 60 }) -- no range known: always counts
    local chars = { ["Me-R"] = { name = "Austin", dungeons = runs } }
    local board = LB.Build(LB.Entries(chars, {}), true)
    H.eq(board[1].dungeon, "The Deadmines"); H.eq(board[2].dungeon, "Hall of Thanes", "unlisted dungeons last")
    local c = board[1].clears
    H.eq(#c, 5); H.eq(c[1].clear, 700); H.eq(c[1].rank, 1); H.eq(c[2].clear, 1100); H.eq(c[5].clear, 1400)
    local all = LB.Build(LB.Entries(chars, {}), false)
    H.eq(all[1].clears[1].clear, 600); H.eq(all[1].clears[1].atLevel, false)
    H.eq(LB.RankOf(board, "The Deadmines", T0 + 10 * 86400 + 700), 1)
    H.eq(LB.RankOf(board, "The Deadmines", T0 + 7 * 86400 + 1700), nil, "6th is off the board")
    H.eq(ns.DungeonLevels.AtLevel("The Deadmines", nil), true, "unknown level counts")
    H.eq(ns.DungeonLevels.AtLevel("Scarlet Monastery Armory", 48), true)
    H.eq(ns.DungeonLevels.AtLevel("Scarlet Monastery Armory", 49), false)
end)

H.test("leaderboard: blocked friends and friends without the new fields", function()
    local ns = H.pureNamespace()
    local LB, L = ns.Leaderboard, ns.L
    local old = { name = "Wailing Caverns", entered = T0, completed = true, clear = 1800 } -- a 1.7.x friend
    local friends = {
        ["bn:Ham#1"] = { name = "Hamlet", tag = "Ham#1", characters = { ["Cain-R"] = { name = "Cain", runs = { old } } } },
        ["bn:Blk#1"] = { name = "Blk", tag = "Blk#1", characters = { ["X-R"] = { name = "X", runs = {
            { name = "Wailing Caverns", entered = T0 + 9999, completed = true, clear = 900 } } } } },
    }
    local board = LB.Build(LB.Entries({}, friends, function(f) return f.tag == "Blk#1" end), true)
    H.eq(#board[1].clears, 1)
    H.eq(LB.Group(board[1].clears[1], L), "Cain"); H.eq(#board[1].bosses, 0, "no boss names from older versions")
end)

H.test("leaderboard in the mock client: the tab draws, a top-5 clear gives a notice", function()
    local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    env.FellowshipLedgerDB = { settings = { askStale = false, welcomeEveryLogin = false, sessionSummary = false } }
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    local now = env.__state.now
    local run = { name = "The Deadmines", entered = now - 1500, completed = true, completedAt = now, bosses = {}, party = {}, levelMax = 20 }
    table.insert(ns.Store.char.dungeons, run)
    H.eq(ns.LeaderboardTab.CheckRun(run), 1)
    H.ok(Mock.chatContains(env, "#1 on The Deadmines, cleared in 25m 00s"), "the notice")
    ns.MainWindow.Open("leaderboard")
    local seen = {}
    for _, line in ipairs(ns.LeaderboardTab.ui.table.lines) do
        for _, s in ipairs(line.segments or {}) do if s.text then seen[#seen + 1] = s.text end end
    end
    local text = table.concat(seen, " | ")
    H.ok(text:find("The Deadmines (15-22)", 1, true) and text:find("25m 00s", 1, true), text)
    ns.db.settings.leaderToasts = false
    H.eq(ns.LeaderboardTab.CheckRun(run), nil, "the switch turns it off")
end)
