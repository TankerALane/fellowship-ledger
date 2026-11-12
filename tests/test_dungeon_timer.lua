-- The dungeon timer (Core/RunTimer.lua, UI/DungeonTimer.lua, D-122): time into the
-- run, boss times, ahead/behind the Leaderboard's #1 or your own best.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

H.test("run timer: the compared run's extra kills are compared, but not part of its run", function()
    local ns = H.pureNamespace()
    local entries = { { dungeon = "The Deadmines", clear = 1200, finishedAt = 2200, names = { "Zip" }, lead = "Zip", size = 5,
        bosses = { { name = "Sneed", at = 1500 }, { name = "VanCleef", at = 2200 }, { name = "Cookie", at = 2300 } } } }
    local t = ns.RunTimer.Target(entries, "The Deadmines", "leader")
    H.eq(t.splits.Sneed, 500); H.eq(t.splits.VanCleef, 1200); H.eq(t.splits.Cookie, 1300, "kept for comparing")
    H.eq(#t.refs, 2, "the running +/- uses only the run's own kills")
    -- Past the run's last kill and its clear: behind by the clear, not by Cookie.
    local v = ns.RunTimer.View({ entered = 0, bosses = { { name = "Sneed", at = 500 } } }, 1250, t)
    H.eq(v.pace, 50)
end)

H.test("run timer: clock and delta text", function()
    local RT = H.pureNamespace().RunTimer
    H.eq(RT.Clock(872), "14:32")
    H.eq(RT.Clock(3725), "1:02:05")
    H.eq(RT.Clock(-5), "0:00")
    H.eq(RT.Delta(22), "+0:22")
    H.eq(RT.Delta(-4), "-0:04")
    H.eq(RT.Delta(-75.4), "-1:15")
end)

H.test("run timer: boss times into the run, ahead or behind the target, final time frozen", function()
    local RT = H.pureNamespace().RunTimer
    local run = { name = "The Deadmines", entered = 1000, bossCount = 3,
        bosses = { { name = "Sneed", at = 1700 }, { name = "Rhahk'Zor", at = 1130 } } }
    local target = { clear = 1500, splits = { ["Rhahk'Zor"] = 150, Sneed = 680 } }
    local v = RT.View(run, 1900, target)
    H.eq(v.elapsed, 900); H.eq(v.killed, 2); H.eq(v.total, 3); H.eq(v.done, false)
    H.eq(v.bosses[1].name, "Rhahk'Zor", "in kill order")
    H.eq(v.bosses[1].into, 130); H.eq(v.bosses[1].delta, -20, "20 seconds ahead")
    H.eq(v.bosses[2].delta, 20, "20 seconds behind")
    H.eq(v.pace, 20, "the +/- beside the time: as of the latest kill")
    H.eq(RT.View({ entered = 0, bosses = {} }, 50, target).pace, nil, "nothing before a boss, while still in time")
    -- Running: past the compared run's next kill without it, behind and growing.
    local slow = { entered = 0, bosses = {} }
    local v1 = RT.View(slow, 170, target)
    H.eq(v1.pace, 20, "20 seconds past #1's first kill"); H.eq(v1.live, true)
    H.eq(RT.View(slow, 200, target).pace, 50, "grows each second")
    slow.bosses[1] = { name = "Rhahk'Zor", at = 140 } -- killed: 10 behind at the kill
    H.eq(RT.View(slow, 300, target).pace, -10, "10 seconds ahead at that kill (140 vs 150)")
    H.eq(RT.View(slow, 300, target).live, nil)
    H.eq(RT.View(slow, 700, target).pace, 20, "past #1's second kill at 680: 20 behind")
    -- After the compared run's last boss, its clear time is the mark.
    local all = { entered = 0, bosses = { { name = "Rhahk'Zor", at = 140 }, { name = "Sneed", at = 600 } } }
    H.eq(RT.View(all, 1520, target).pace, 20, "20 seconds past #1's clear without the final boss")
    run.bosses[3] = { name = "Captain Cookie", at = 2400 }
    run.completed, run.completedAt = true, 2400
    v = RT.View(run, 9999, target)
    H.eq(v.elapsed, 1400, "stops at the final boss"); H.eq(v.done, true); H.eq(v.delta, -100)
    H.eq(v.pace, -100, "the whole clear once done")
    H.eq(v.bosses[3].delta, nil, "no target time for that boss")
    -- An extra boss after the final one: listed, muted, no +/-, not counted.
    run.bosses[4] = { name = "Cookie", at = 2500 }
    target.splits.Cookie = 1600
    v = RT.View(run, 9999, target)
    H.eq(v.bosses[4].name, "Cookie"); H.eq(v.bosses[4].extra, true)
    H.eq(v.bosses[4].delta, -100, "an extra is still compared with the same kill (1500 into the run vs 1600)")
    H.eq(v.killed, 3, "the extra is not counted"); H.eq(v.pace, -100)
    run.bosses[4] = nil
    v = RT.View(run, 9999, nil)
    H.eq(v.bosses[1].delta, nil); H.eq(v.delta, nil)
end)

-- Mock client helpers (as in test_tracking_smoke) ----------------------------------
local RETAIL = { interface = 120105, tocFlavor = "Retail" }
local DEADMINES = { "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
local WESTFALL = { "Westfall", "none", 0, "", 5, 0, false, 0 }
local function boot()
    local env = Mock.new(RETAIL)
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    return env, ns
end
local function go(env, where, secs)
    if secs then Mock.advance(env, secs) end
    env.__state.instance = where
    Mock.fire(env, "ZONE_CHANGED_NEW_AREA")
end
local function enter(env)
    local st = env.__state
    st.ejInstance = 63
    st.ejBosses = { { name = "Rhahk'Zor", id = 1 }, { name = "Sneed", id = 5 }, { name = "Captain Cookie", id = 9 } }
    go(env, DEADMINES)
end
local function enterAndPull(env)
    enter(env)
    Mock.fire(env, "PLAYER_REGEN_DISABLED") -- the first fight: the clock starts (D-126)
end
local function boss(env, secs, id, name)
    Mock.advance(env, secs)
    Mock.fire(env, "ENCOUNTER_END", id, name, 1, 5, 1)
end

H.test("dungeon timer in the game: shows in a run, compares with #1 or your best, closes, hides outside runs", function()
    local env, ns = boot()
    local T = ns.DungeonTimer
    H.ok(not T.Frame() or not T.Frame():IsShown(), "nothing outside a dungeon")
    -- A first run of mine: 25 minutes.
    enterAndPull(env)
    boss(env, 300, 1, "Rhahk'Zor"); boss(env, 600, 5, "Sneed"); boss(env, 600, 9, "Captain Cookie")
    go(env, WESTFALL, 30)
    Mock.advance(env, 1801)
    ns.Trackers.byId.dungeons:OnTick()
    H.ok(not T.Frame():IsShown(), "gone once the run is closed")
    -- A friend's faster run (20 minutes) is the Leaderboard's #1.
    local now = env.time()
    ns.db.friends["bn:Fast#1"] = { kind = "bnet", name = "Fast", tag = "Fast#1", characters = { ["Zip-R"] = { name = "Zip",
        runs = { { name = "The Deadmines", entered = now - 86400, completed = true, clear = 1200,
            splits = { { at = 200, fight = 30 }, { at = 700, fight = 40 }, { at = 1200, fight = 50 } },
            bossNames = { "Rhahk'Zor", "Sneed", "Captain Cookie" } } } } } }
    -- Second run: the timer shows, compared with #1.
    enterAndPull(env)
    Mock.advance(env, 2)
    local f = T.Frame()
    H.ok(f:IsShown(), "shown on entering")
    H.eq(f.title:GetText(), "The Deadmines")
    boss(env, 250, 1, "Rhahk'Zor")
    T.Refresh()
    H.ok(f.compare.text:GetText():find("vs #1 Zip, 20:00", 1, true), f.compare.text:GetText())
    H.eq(f.pace:GetText(), "+0:52", "the +/- beside the time")
    H.eq(ns.RunTimer.View(ns.Store.char.currentRun, env.time(), T.Target(ns.Store.char.currentRun, env.time())).bosses[1].delta, 52,
        "Rhahk'Zor 52 seconds behind #1")
    -- Switch to your own best: the first run (Rhahk'Zor at 5:00).
    f.compare:GetScript("OnClick")()
    H.eq(ns.db.settings.dungeonTimerMine, true)
    H.ok(f.compare.text:GetText():find("vs your best: 25:00", 1, true), f.compare.text:GetText())
    local v = ns.RunTimer.View(ns.Store.char.currentRun, env.time(), T.Target(ns.Store.char.currentRun, env.time()))
    H.eq(v.bosses[1].delta, -48, "48 seconds ahead of your best")
    -- Closed: stays closed for this run, back with /fl timer.
    T.Close(); Mock.advance(env, 5)
    H.ok(not f:IsShown(), "closed for this run")
    Mock.slash(env, "timer")
    H.ok(f:IsShown(), "back with /fl timer")
    -- Off in Settings.
    ns.db.settings.dungeonTimer = false
    Mock.advance(env, 2)
    H.ok(not f:IsShown(), "off in Settings")
    ns.db.settings.dungeonTimer = true
    -- Finish: the clock stops at the final boss.
    boss(env, 400, 5, "Sneed"); boss(env, 400, 9, "Captain Cookie")
    T.Refresh()
    local stopped = f.clock:GetText()
    Mock.advance(env, 120)
    H.eq(f.clock:GetText(), stopped, "frozen after the final boss")
    H.ok(f.status:GetText():find("Cleared in", 1, true), f.status:GetText())
    -- 2 + 250 + 5 + 2 + 400 + 400 seconds = 17:39, against your best 25:00.
    H.eq(f.pace:GetText(), "-7:21", "the whole clear against your best (17:39 vs 25:00)")
    H.ok(f.compare.text:GetText():find("vs your best: 25:00", 1, true), "still the earlier run, not this one")
    -- Against #1 (the friend's 20:00, not this run, which is now on the Leaderboard).
    f.compare:GetScript("OnClick")()
    H.eq(f.pace:GetText(), "-2:21", "against #1 (17:39 vs 20:00), not against itself")
end)

H.test("dungeon timer waits at 0:00 until the first fight, and the clear counts from it (D-126)", function()
    local env, ns = boot()
    local T = ns.DungeonTimer
    enter(env)
    Mock.advance(env, 90) -- buffing and waiting for the group
    local f = T.Frame()
    H.ok(f:IsShown(), "shown on entering")
    H.eq(f.clock:GetText(), "0:00", "not running before anyone fights")
    H.eq(f.status:GetText(), "Starts at the first fight")
    local run = ns.Store.char.currentRun
    H.eq(run.started, nil)
    -- The group kills something: the clock starts.
    Mock.fire(env, "PARTY_KILL", "Player-1", "Creature-1")
    H.eq(run.started, env.time())
    Mock.advance(env, 65)
    H.eq(f.clock:GetText(), "1:05")
    -- Later fights do not move the start.
    Mock.fire(env, "PLAYER_REGEN_DISABLED")
    H.eq(run.started, env.time() - 65)
    boss(env, 600, 1, "Rhahk'Zor"); boss(env, 600, 5, "Sneed"); boss(env, 600, 9, "Captain Cookie")
    local clear = ns.DungeonsModel.ClearTime(run)
    H.eq(clear, 65 + 1800, "the clear counts from the first fight, not from entering")
    H.eq(ns.Bests.Clear(run), clear)
    -- Friends get it too, and older readers keep reading the time from entering.
    local C = ns.Codec
    local body = C.EncodeData("Me-R", { class = "MAGE", level = 20, days = {}, dungeons = {}, currentRun = run }, { dungeons = true }, nil)
    local u = C.DecodeData(body).runs[1]
    H.eq(u.startOffset, 90)
    H.eq(u.clear, clear, "a newer friend sees the same clear")
    H.eq(u.splits[1].at, 90 + 65 + 600, "boss times still count from entering on the wire")
    local e = ns.Leaderboard.Entries({}, { f = { characters = { ["Me-R"] = { runs = { u } } } } })[1]
    H.eq(e.finishedAt, run.completedAt, "the friend's copy finishes at the same moment")
    H.eq(e.clear, clear)
end)

H.test("a boss pulled first starts the clock at the pull", function()
    local env, ns = boot()
    enter(env)
    Mock.advance(env, 30)
    Mock.fire(env, "ENCOUNTER_START", 1, "Rhahk'Zor", 1, 5)
    local run = ns.Store.char.currentRun
    H.eq(run.started, env.time())
end)
