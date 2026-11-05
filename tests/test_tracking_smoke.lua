-- End-to-end tracking against the mock client: login, time, level-ups, quests,
-- gold, dungeons, kills, sessions across reloads, backup and restore, commands.
-- Proves the code paths and the bookkeeping; real-client behaviour is on Austin's checklist.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local function boot(opts, db, backup)
    local env = Mock.new(opts)
    env.FellowshipLedgerDB = db
    env.FellowshipLedgerBackupDB = backup
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    return env, ns
end

local RETAIL = { interface = 120105, tocFlavor = "Retail" }

local function reboot(env, opts, gap)
    Mock.fire(env, "PLAYER_LOGOUT")
    local o = {}
    for k, v in pairs(opts or RETAIL) do o[k] = v end
    o.now = env.__state.now + (gap or 5)
    return boot(o, env.FellowshipLedgerDB, env.FellowshipLedgerBackupDB)
end

local function char(env) return env.FellowshipLedgerDB.characters["Tester-TestRealm"] end
local function today(env) return char(env).days[os.date("%Y-%m-%d", env.__state.now)] or {} end

H.test("login creates the character, a session and starts tracking", function()
    local env, ns = boot(RETAIL)
    H.ok(not Mock.chatContains(env, "could not start"), table.concat(env.__state.chat, "\n"))
    local c = char(env)
    H.ok(c, "character record")
    H.eq(c.class, "MAGE")
    H.eq(c.level, 12)
    H.eq(#c.sessions, 1)
    H.eq(c.flags.levels.track, true)
    H.eq(c.flags.levels.share, true)
    H.eq(ns.Store.key, "Tester-TestRealm")
end)

H.test("moving keeps time active; a quiet stretch over 5 minutes is removed", function()
    local env = boot(RETAIL)
    env.__state.speed = 7
    Mock.advance(env, 600)
    env.__state.speed = 0
    Mock.advance(env, 1200)
    local d = today(env)
    H.eq(d.played, 1800)
    H.eq(d.active, 600, "the 20 quiet minutes are removed entirely")
    local s = char(env).sessions[1]
    H.eq(s.played, 1800)
    H.eq(s.active, 600)
end)

H.test("level up records active and total time with zone and toast", function()
    local env = boot(RETAIL)
    -- The ledger joined mid-level 12 (xp > 0): that level is partial. Play through 13 cleanly.
    Mock.fire(env, "PLAYER_LEVEL_UP", 13, 87)
    env.__state.level = 13
    env.__state.speed = 7
    Mock.advance(env, 623)
    env.__state.speed = 0
    env.__state.afk = true
    Mock.fire(env, "PLAYER_FLAGS_CHANGED", "player")
    Mock.advance(env, 219)
    Mock.fire(env, "PLAYER_LEVEL_UP", 14, 87)
    local c = char(env)
    H.ok(c.levels[13].partial, "first level seen mid-way is partial")
    local r = c.levels[14]
    H.eq(r.from, 13)
    H.eq(r.active, 623, "active stops when AFK starts")
    H.eq(r.total, 842)
    H.eq(r.zone, "Elwynn Forest")
    H.eq(r.partial, nil)
    H.ok(Mock.chatContains(env, "Level 14! - 13 -> 14: 10m 23s (total 14m 02s)"))
    H.eq(today(env).levels, 2)
    H.eq(c.sessions[1].levelEnd, 14)
    Mock.fire(env, "PLAYER_LEVEL_UP", 14, 87) -- duplicate event is ignored
    H.eq(today(env).levels, 2)
end)

H.test("XP gains are counted, including across a level wrap", function()
    local env = boot(RETAIL)
    env.__state.xp = 800
    Mock.fire(env, "PLAYER_XP_UPDATE", "player")
    env.__state.xp, env.__state.xpMax = 100, 2500
    Mock.fire(env, "PLAYER_XP_UPDATE", "player")
    Mock.fire(env, "PLAYER_XP_UPDATE", "target")
    H.eq(today(env).xp, 500 + 1300)
end)

H.test("quest turn-ins are logged once with their title", function()
    local env = boot(RETAIL)
    Mock.fire(env, "QUEST_TURNED_IN", 54, 450, 75)
    Mock.fire(env, "QUEST_TURNED_IN", 54, 450, 75)
    local log = char(env).questLog
    H.eq(#log, 1)
    H.eq(log[1].title, "Report to Goldshire")
    H.eq(log[1].xp, 450)
    H.eq(today(env).quests, 1)
    Mock.fire(env, "QUEST_TURNED_IN", 99, 0, 0)
    H.eq(char(env).questLog[2].title, "Quest 99")
end)

H.test("gold is split by source, and late quest money is moved to quest", function()
    local env = boot(RETAIL)
    local st = env.__state
    Mock.fire(env, "MERCHANT_SHOW")
    st.money = st.money + 300
    Mock.fire(env, "PLAYER_MONEY")
    Mock.fire(env, "MERCHANT_CLOSED")
    Mock.fire(env, "LOOT_READY", true)
    st.money = st.money + 50
    Mock.fire(env, "PLAYER_MONEY")
    Mock.fire(env, "LOOT_CLOSED")
    st.now = st.now + 10
    st.money = st.money + 75 -- money arrives before the turn-in event
    Mock.fire(env, "PLAYER_MONEY")
    Mock.fire(env, "QUEST_TURNED_IN", 54, 0, 75)
    st.money = st.money - 20
    Mock.fire(env, "PLAYER_MONEY")
    local d = today(env)
    H.eq(d.money_vendor, 300)
    H.eq(d.money_loot, 50)
    H.eq(d.money_quest, 75)
    H.eq(d.money_other, -20)
    H.eq(d.moneyNet, 405)
    H.eq(d.moneyIn, 425)
    H.eq(d.moneyOut, 20)
end)

H.test("Track off stops collection for that tracker only", function()
    local env = boot(RETAIL)
    char(env).flags.quests.track = false
    Mock.fire(env, "QUEST_TURNED_IN", 54, 0, 0)
    H.eq(#char(env).questLog, 0)
    H.eq(today(env).quests, nil)
    Mock.fire(env, "PLAYER_LEVEL_UP", 13)
    H.eq(today(env).levels, 1)
end)

H.test("reload continues the session; 30+ minutes offline starts a new one", function()
    local env = boot(RETAIL)
    Mock.advance(env, 120)
    env = reboot(env, RETAIL, 10)
    H.eq(#char(env).sessions, 1)
    env = reboot(env, RETAIL, 1801 + 60)
    H.eq(#char(env).sessions, 2)
    H.eq(char(env).sessions[2].id, 2)
end)

H.test("logout writes a per-character backup; a wiped ledger offers restore", function()
    local env, ns = boot(RETAIL)
    Mock.fire(env, "QUEST_TURNED_IN", 54, 0, 0)
    Mock.fire(env, "PLAYER_LOGOUT")
    local backup = env.FellowshipLedgerBackupDB
    H.eq(backup.key, "Tester-TestRealm")
    H.ok(backup.character.questLog[1], "backup holds the quest log")
    H.ok(backup.persistProbe and backup.persistProbe.loads >= 1, "persistence probe kept")

    local wiped = { schemaVersion = 1, settings = {}, characters = {}, friends = {}, blocklist = {}, dev = {} }
    local env2, ns2 = boot(RETAIL, wiped, backup)
    H.eq(ns2.Store.backupState, "missing")
    H.ok(Mock.chatContains(env2, "looks empty, but a backup from"))
    H.ok(env2.FellowshipLedgerDialog and env2.FellowshipLedgerDialog:IsShown(), "restore dialog shown")
    ns2.Store.Restore()
    H.eq(#char(env2).questLog, 1)
    H.ok(Mock.chatContains(env2, "Backup restored"))
end)

H.test("dungeon: entered, bosses, last boss completes, party class and role only", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.units.party1 = { class = "PRIEST", role = "HEALER", level = 20 }
    st.units.party2 = { class = "WARRIOR", role = "TANK", level = 21 }
    st.ejInstance = 63
    st.ejBosses = { { name = "Rhahk'Zor", id = 1 }, { name = "Captain Cookie", id = 9 } }
    st.instance = { "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    Mock.fire(env, "ZONE_CHANGED_NEW_AREA")
    H.eq(today(env).dungeonsEntered, 1, "re-check in the same instance does not count twice")
    local run = char(env).currentRun
    H.eq(run.lastBossID, 9)
    H.eq(run.party[1].class, "PRIEST")
    H.eq(run.party[1].role, "HEALER")
    H.eq(run.party[1].name, nil)
    Mock.fire(env, "ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
    H.ok(not run.completed)
    Mock.fire(env, "PLAYER_DEAD")
    Mock.advance(env, 600)
    Mock.fire(env, "ENCOUNTER_END", 9, "Captain Cookie", 1, 5, 0) -- wipe: not a kill
    H.ok(not run.completed)
    Mock.fire(env, "ENCOUNTER_END", 9, "Captain Cookie", 1, 5, 1)
    H.ok(run.completed)
    H.eq(run.completedBy, "lastBoss")
    st.instance = { "Westfall", "none", 0, "", 5, 0, false, 0 }
    Mock.fire(env, "ZONE_CHANGED_NEW_AREA")
    local done = char(env).dungeons[1]
    H.eq(done.name, "The Deadmines")
    H.eq(done.deaths, 1)
    H.eq(#done.bosses, 2)
    H.ok(done.duration >= 600)
    H.eq(today(env).dungeonsCompleted, 1)
    H.eq(today(env).deaths, 1)
    H.eq(char(env).currentRun, nil)
end)

H.test("deaths: killer level from the target, or a recent target if it was cleared", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.recaps = { [1] = { { timestamp = 5, sourceName = "Gnoll Brute", spellName = "Melee", amount = 40 } } }
    st.units.target = { name = "Gnoll Brute", level = 14 }
    Mock.fire(env, "PLAYER_DEAD")
    Mock.advance(env, 2)
    local log = char(env).deathLog
    H.eq(log[#log].killer, "Gnoll Brute")
    H.eq(log[#log].killerLevel, 14, "target at death")

    -- Targeted earlier, but the game cleared the target as you died.
    st.units.target = { name = "Elite Ogre", level = 16 }
    Mock.fire(env, "PLAYER_TARGET_CHANGED")
    st.units.target = nil
    st.recaps[2] = { { timestamp = 9, sourceName = "Elite Ogre", spellName = "Smash", amount = 90 } }
    Mock.advance(env, 30)
    Mock.fire(env, "PLAYER_DEAD")
    Mock.advance(env, 2)
    H.eq(log[#log].killer, "Elite Ogre")
    H.eq(log[#log].killerLevel, 16, "recent target")

    -- Someone never targeted: no level.
    st.recaps[3] = { { timestamp = 3, sourceName = "Hidden Rogue", spellName = "Stab", amount = 70 } }
    Mock.advance(env, 30)
    Mock.fire(env, "PLAYER_DEAD")
    Mock.advance(env, 2)
    H.eq(log[#log].killer, "Hidden Rogue")
    H.eq(log[#log].killerLevel, nil)
end)

H.test("flight paths: discovery message counts once, before or after the map, even on a first visit", function()
    local env = boot(RETAIL)
    local st = env.__state
    local function fps() return char(env).flightPaths end
    -- First visit ever, message first: the node you stand at is new, the rest a baseline.
    st.taxiNodes = { { nodeID = 1, name = "Sentinel Hill", state = 0 }, { nodeID = 2, name = "Stormwind", state = 1 },
        { nodeID = 3, name = "Far Away", state = 2 } }
    Mock.fire(env, "UI_INFO_MESSAGE", 300, "New flight path discovered!")
    Mock.fire(env, "TAXIMAP_OPENED")
    H.eq(today(env).flightPaths, 1)
    H.eq(fps()["1"].baseline, nil); H.eq(fps()["2"].baseline, true); H.eq(fps()["3"], nil)

    -- Map first, then the message: still one.
    Mock.advance(env, 60)
    st.taxiNodes = { { nodeID = 4, name = "Lakeshire", state = 0 }, { nodeID = 1, name = "Sentinel Hill", state = 1 } }
    Mock.fire(env, "TAXIMAP_OPENED")
    Mock.fire(env, "UI_INFO_MESSAGE", 300, "New flight path discovered!")
    H.eq(today(env).flightPaths, 2)

    -- No message (missed): the map alone counts it; reopening counts nothing.
    Mock.advance(env, 60)
    st.taxiNodes = { { nodeID = 5, name = "Darkshire", state = 0 } }
    Mock.fire(env, "TAXIMAP_OPENED")
    Mock.fire(env, "TAXIMAP_OPENED")
    H.eq(today(env).flightPaths, 3)
end)

H.test("flight paths: a first map visit without the message is only a baseline", function()
    local env = boot(RETAIL)
    env.__state.taxiNodes = { { nodeID = 1, name = "Sentinel Hill", state = 0 } }
    Mock.fire(env, "TAXIMAP_OPENED")
    H.eq(today(env).flightPaths, nil)
    H.eq(char(env).flightPaths["1"].baseline, true)
end)

H.test("dungeons: no journal by map, found by name; last boss completes the run", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.ejInstance = nil -- the map lookup gives nothing (Forever, 2026-11-05)
    st.ejList = { { id = 226, name = "Ragefire Chasm" } }
    st.ejBosses = { { name = "Oggleflint", id = 2732 }, { name = "Bazzalan", id = 2735 } }
    st.instance = { "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    local run = char(env).currentRun
    H.eq(run.lastBossID, 2735); H.eq(run.lookup, "name")
    Mock.fire(env, "ENCOUNTER_END", 2732, "Oggleflint", 1, 5, 1)
    H.ok(not run.completed)
    Mock.fire(env, "ENCOUNTER_END", 2735, "Bazzalan", 1, 5, 1)
    H.ok(run.completed); H.eq(run.completedBy, "lastBoss")
    H.eq(today(env).dungeonsCompleted, 1)
end)

H.test("dungeons: the boss list is retried during the run when it was not known on entry", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.instance = { "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    local run = char(env).currentRun
    H.eq(run.lastBossID, nil, "nothing known yet")
    st.ejList = { { id = 226, name = "Ragefire Chasm" } }
    st.ejBosses = { { name = "Oggleflint", id = 2732 }, { name = "Bazzalan", id = 2735 } }
    Mock.advance(env, 31)
    H.eq(run.lastBossID, 2735, "found on a later tick")
end)

H.test("dungeons: loose journal name, and a last boss known only by name", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.ejList = { { id = 226, name = "Ragefire Chasm (Orgrimmar)" } }
    st.ejBosses = { { name = "Oggleflint" }, { name = "Bazzalan" } } -- no encounter IDs from the journal
    st.instance = { "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    local run = char(env).currentRun
    H.eq(run.lastBossID, nil); H.eq(run.lastBossName, "Bazzalan")
    Mock.fire(env, "ENCOUNTER_END", 2735, "Bazzalan", 1, 5, 1)
    H.ok(run.completed, "completed by the boss's name")
end)

H.test("dungeons: empty journal (WoW Forever), the final-boss list completes the run", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.instance = { "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    local run = char(env).currentRun
    H.eq(run.lastBossID, nil); H.eq(run.lastBossName, nil)
    Mock.fire(env, "ENCOUNTER_END", 2732, "Oggleflint", 1, 5, 1)
    H.ok(not run.completed)
    Mock.fire(env, "ENCOUNTER_END", 2735, "Bazzalan", 1, 5, 1)
    H.ok(run.completed, "Bazzalan is Ragefire Chasm's final boss")
    H.eq(today(env).dungeonsCompleted, 1)
end)

H.test("dungeons: a run an earlier repair already tried is completed from the list", function()
    local env = boot(RETAIL)
    local st = env.__state
    local c = char(env)
    local killAt = st.now - 600
    c.dungeons[#c.dungeons + 1] = { name = "Ragefire Chasm", instanceID = 389, entered = killAt - 2000, repairTried = 2, party = {},
        bosses = { { id = 2732, name = "Oggleflint", at = killAt - 900 }, { id = 2735, name = "Bazzalan", at = killAt } } }
    env = reboot(env)
    local run = char(env).dungeons[#char(env).dungeons]
    H.ok(run.completed); H.eq(run.repairTried, 3)
    H.eq(char(env).days[os.date("%Y-%m-%d", killAt)].dungeonsCompleted, 1)
end)

H.test("dungeons: a saved run without a boss list is repaired at login", function()
    local env = boot(RETAIL)
    local st = env.__state
    local c = char(env)
    local killAt = st.now - 3600
    c.dungeons[#c.dungeons + 1] = { name = "Ragefire Chasm", instanceID = 389, entered = killAt - 2000, left = killAt + 60,
        deaths = 1, party = {}, bosses = { { id = 2732, name = "Oggleflint", at = killAt - 900 }, { id = 2735, name = "Bazzalan", at = killAt } } }
    c.dungeons[#c.dungeons + 1] = { name = "Unknown Place", entered = killAt, bosses = { { id = 9, at = killAt } }, party = {} }
    env = reboot(env, { interface = 120105, tocFlavor = "Retail", state = {
        ejList = { { id = 226, name = "Ragefire Chasm" } },
        ejBosses = { { name = "Oggleflint", id = 2732 }, { name = "Bazzalan", id = 2735 } } } })
    c = char(env)
    local rfc, other
    for _, r in ipairs(c.dungeons) do if r.name == "Ragefire Chasm" then rfc = r elseif r.name == "Unknown Place" then other = r end end
    H.ok(rfc.completed, "repaired"); H.eq(rfc.completedAt, killAt)
    H.eq(c.days[os.date("%Y-%m-%d", killAt)].dungeonsCompleted, 1, "counted on the day of the kill")
    H.ok(not other.completed, "a dungeon the journal does not know stays as it was")
    H.eq(other.repairTried, 3)
end)

H.test("kills: only your own, with type and rare/elite when targeted", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.guid.player = "Player-1"
    st.guid.target = "Creature-7"
    st.units.target = { ctype = "Beast", classification = "rareelite" }
    Mock.fire(env, "PARTY_KILL", "Player-1", "Creature-7")
    Mock.fire(env, "PARTY_KILL", "Player-2", "Creature-8")
    Mock.fire(env, "PARTY_KILL", "Player-1", "Creature-9")
    local k = char(env).kills
    H.eq(k.total, 2)
    H.eq(k.byType.Beast, 1)
    H.eq(k.rare, 1)
    H.eq(k.elite, 1)
    H.eq(today(env).kills, 2)
end)

H.test("extras: zones, achievements, party level-ups, reputation", function()
    local env = boot(RETAIL)
    local st = env.__state
    H.eq(today(env).zonesNew, 1, "login zone counts once")
    Mock.fire(env, "ZONE_CHANGED_NEW_AREA")
    H.eq(today(env).zonesNew, 1)
    Mock.fire(env, "ACHIEVEMENT_EARNED", 6, false)
    Mock.fire(env, "ACHIEVEMENT_EARNED", 7, true)
    H.eq(char(env).achievements[1].name, "Achievement 6")
    H.eq(today(env).achievements, 1)
    st.units.party1 = { class = "PRIEST", level = 20 }
    Mock.fire(env, "GROUP_ROSTER_UPDATE")
    st.units.party1.level = 21
    Mock.fire(env, "UNIT_LEVEL", "party1")
    Mock.fire(env, "UNIT_LEVEL", "target")
    H.eq(char(env).partyLevels[1].level, 21)
    H.eq(char(env).partyLevels[1].class, "PRIEST")
    H.eq(today(env).partyLevelUps, 1)
    st.factions = { { factionID = 72, name = "Stormwind", currentStanding = 100, isHeader = false } }
    env = reboot(env)
    st = env.__state
    st.factions = { { factionID = 72, name = "Stormwind", currentStanding = 100, isHeader = false } }
    Mock.fire(env, "PLAYER_LOGIN") -- re-read baseline with factions present
    Mock.runTimers(env)
    st.factions[1].currentStanding = 350
    Mock.fire(env, "UPDATE_FACTION")
    Mock.runTimers(env)
    H.eq(today(env).repGained, 250)
    H.eq(char(env).reputation["72"].gained, 250)
end)

H.test("professions: login adopts ranks, later gains count with timing", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.profRank = 15
    env.GetProfessions = function() return 1 end
    env.GetProfessionInfo = function() return "Mining", 0, st.profRank, 75, 0, 0, 186 end
    env = reboot(env)
    st = env.__state
    st.profRank = 15
    env.GetProfessions = function() return 1 end
    env.GetProfessionInfo = function() return "Mining", 0, st.profRank, 75, 0, 0, 186 end
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    local p = char(env).professions["186"]
    H.eq(p.rank, 15)
    st.speed = 7
    Mock.advance(env, 90)
    st.profRank = 17
    for _ = 1, 5 do Mock.fire(env, "SKILL_LINES_CHANGED") end
    Mock.runTimers(env)
    H.eq(p.rank, 17)
    H.eq(#p.history, 2)
    H.eq(p.history[1].active, 90)
    H.eq(today(env).skillUps, 2)
end)

H.test("commands: window, export, self-test, debug log, restore", function()
    local env, ns = boot(RETAIL)
    Mock.fire(env, "QUEST_TURNED_IN", 54, 0, 0)
    Mock.slash(env, "")
    H.ok(env.FellowshipLedgerMainWindow and env.FellowshipLedgerMainWindow:IsShown(), "window opens")
    Mock.slash(env, "")
    H.ok(not env.FellowshipLedgerMainWindow:IsShown(), "and toggles closed")
    Mock.slash(env, "export")
    H.ok(ns.CopyWindow.text:find("\nQ | Tester-TestRealm | ", 1, true), ns.CopyWindow.text)
    Mock.slash(env, "test")
    H.ok(Mock.chatContains(env, "Self-test: 9 of 9 passed."), ns.CopyWindow.text)
    Mock.slash(env, "debug")
    Mock.fire(env, "PLAYER_TARGET_CHANGED")
    H.ok(#ns.Events.log >= 1)
    H.ok(env.FellowshipLedgerEventLog and env.FellowshipLedgerEventLog:IsShown())
    Mock.fire(env, "CHAT_MSG_ADDON", "FLDGR", "secret text", "WHISPER", "X")
    for _, e in ipairs(ns.Events.log) do H.ok(not tostring(e.args):find("secret text", 1, true), "addon messages not logged") end
    Mock.slash(env, "help")
    H.ok(Mock.chatContains(env, "/fl export"))
    H.ok(not Mock.chatContains(env, "failed:"), table.concat(env.__state.chat, "\n"))
end)

H.test("Me tab model sums ranges per character", function()
    local env, ns = boot(RETAIL)
    Mock.fire(env, "QUEST_TURNED_IN", 54, 0, 0)
    local c = char(env)
    c.days["2026-10-01"] = { quests = 5 }
    local rows = ns.MeModel.Build(env.FellowshipLedgerDB.characters, "today", ns.Store.Today(), env.time, env.date)
    H.eq(rows[1].quests, 1)
    rows = ns.MeModel.Build(env.FellowshipLedgerDB.characters, "all", ns.Store.Today(), env.time, env.date)
    H.eq(rows[1].quests, 6)
    local lv = ns.DetailModel.Data({ levels = { [3] = { from = 2, to = 3, active = 60, total = 90, zone = "Elwynn" } } }, ns.L, os.date).levels.rows[1]
    H.eq(lv.level, "2 -> 3"); H.eq(lv.active, "1m 00s"); H.eq(lv.played, "1m 30s"); H.eq(lv.zone, "Elwynn")
end)

H.test("retail findings: follower companions, difficulty 0 on entry, discoveries", function()
    local env = boot(RETAIL)
    local st = env.__state
    st.units.party1 = { class = "PRIEST", role = "HEALER", level = 16, npc = true }
    st.units.party2 = { class = "MAGE", role = "DAMAGER", level = 16 }
    Mock.fire(env, "GROUP_ROSTER_UPDATE")
    st.units.party1.level, st.units.party2.level = 17, 17
    Mock.fire(env, "UNIT_LEVEL", "party1")
    Mock.fire(env, "UNIT_LEVEL", "party2")
    H.eq(today(env).partyLevelUps, 1, "companions are not counted")

    st.instance = { "The Nokhud Offensive", "party", 0, "", 5, 0, false, 2516 }
    Mock.fire(env, "PLAYER_ENTERING_WORLD", false, false)
    local run = char(env).currentRun
    H.eq(run.difficultyID, 0)
    H.eq(run.party[1].npc, true)
    H.eq(run.party[2].npc, nil)
    Mock.fire(env, "ENCOUNTER_START", 2637, "Granyth", 1, 5)
    H.eq(run.difficultyID, 1, "taken from the encounter")

    Mock.fire(env, "UI_INFO_MESSAGE", 408, "Discovered: Ruins of Zul'Kunda")
    Mock.fire(env, "UI_INFO_MESSAGE", 408, "Discovered: Ruins of Zul'Kunda")
    Mock.fire(env, "UI_INFO_MESSAGE", 312, "Bloodscalp Scout slain: 1/7")
    Mock.fire(env, "UI_INFO_MESSAGE", 999, "Discovered Booty Bay: 1,250 experience gained")
    local d = char(env).discoveries
    H.eq(#d, 2)
    H.eq(d[1].name, "Ruins of Zul'Kunda")
    H.eq(d[2].name, "Booty Bay")
    H.eq(today(env).zonesDiscovered, 2)
end)

H.test("reputation under a collapsed header is still counted", function()
    local Mock2 = Mock
    local env = boot(RETAIL)
    local st = env.__state
    st.factions = { { factionID = 67, name = "Horde", isHeader = true, currentStanding = 0 } }
    st.hiddenFactions = { { factionID = 530, name = "Darkspear Trolls", isHeader = false, currentStanding = 3000 } }
    Mock2.fire(env, "PLAYER_LOGIN") -- rescan faction IDs with the factions present
    Mock2.runTimers(env)
    st.hiddenFactions[1].currentStanding = 3250
    Mock2.fire(env, "UPDATE_FACTION")
    Mock2.runTimers(env)
    H.eq(today(env).repGained, 250)
    H.eq(char(env).reputation["530"].name, "Darkspear Trolls")
end)

H.test("export carries professions and dungeon details", function()
    local env, ns = boot(RETAIL)
    local c = char(env)
    c.professions["186"] = { name = "Mining", rank = 40, max = 75, history = { {}, {}, {} }, lastAt = 123 }
    c.dungeons[1] = { entered = 1, name = "Nokhud", difficultyID = 1, completed = true, duration = 986, deaths = 0,
        bosses = { {}, {}, {}, {} }, completedBy = "lastBoss" }
    Mock.slash(env, "export")
    local text = ns.CopyWindow.text
    H.ok(text:find("\nP | Tester-TestRealm | Mining | 40 | 75 | 3 | 123", 1, true), text)
    H.ok(text:find("\nR | Tester-TestRealm | 1 | Nokhud | 1 | 1 | 986 | 0 | 4 | lastBoss", 1, true), text)
end)

H.test("unsupported or newer data: no tracking, no errors", function()
    local env, ns = boot({ interface = 11509 })
    H.eq(ns.tracking, nil)
    H.eq(next(env.FellowshipLedgerDB.characters), nil)
    local env2, ns2 = boot(RETAIL, { schemaVersion = 99, settings = {}, characters = {}, dev = {} })
    H.eq(ns2.tracking, nil)
    H.ok(Mock.chatContains(env2, "newer version"))
end)
