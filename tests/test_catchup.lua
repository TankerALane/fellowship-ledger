-- Catching up between computers (D-128): Comms/CatchUp.lua on its own, and mock clients
-- where Alice plays on two computers that are never online together and her friend Bob
-- hands back what each computer missed.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local NOW = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
local TODAY = os.date("%Y-%m-%d", NOW)
local YESTERDAY = os.date("%Y-%m-%d", NOW - 86400)

-- Pure ------------------------------------------------------------------------------

H.test("catch-up records travel in HELLO and REQUEST; relay still reads its own", function()
    local ns = H.pureNamespace()
    local C = ns.Codec
    local h = C.DecodeHello(C.EncodeHello({ version = "1.12.0", characters = {}, relay = true, catchUp = true, noRelay = { "0000abcd" } }))
    H.ok(h.relay and h.catchUp, "both flags in one record")
    H.ok(h.noRelay["0000abcd"])
    local only = C.DecodeHello(C.EncodeHello({ version = "1.12.0", characters = {}, catchUp = true }))
    H.ok(only.catchUp and not only.relay, "catch-up without relaying")
    local r = C.DecodeRequest(C.EncodeRequest("2026-11-03", { { hash = "0000abcd", lastSeen = 5 } }, { { hash = "1234ffff", lastSeen = 99 } }))
    H.eq(r.since, "2026-11-03")
    H.eq(r.known["0000abcd"], 5)
    H.eq(r.mine["1234ffff"], 99)
    H.ok(C.DecodeRequest(C.EncodeRequest(nil, nil, {})).mine, "a bare m asks for everything")
    H.eq(C.DecodeRequest(C.EncodeRequest(nil)).mine, nil, "no m: not asking")
    H.eq(C.TYPES.C, "CATCHUP")
end)

H.test("catch-up: what I list, and what a friend hands back", function()
    local ns = H.pureNamespace()
    local U, R = ns.CatchUp, ns.Relay
    local mine = U.Mine({ ["Alice-Realm"] = { lastSeen = 900 }, ["Alt-Realm"] = { lastSeen = 50 } }, { ["Alice-Realm"] = 300 })
    local by = {}
    for _, m in ipairs(mine) do by[m.hash] = m.lastSeen end
    H.eq(by[R.Hash("Alice-Realm")], 300, "the played character: as it was at login")
    H.eq(by[R.Hash("Alt-Realm")], 0, "new this session on this computer: nothing before")
    local friend = { characters = { ["Alice-Realm"] = { lastSeen = 500 }, ["Alt-Realm"] = { lastSeen = 40 },
        ["Third-Realm"] = { lastSeen = 70 }, ["Old-Realm"] = { lastSeen = 20 } } }
    local theirs = { [R.Hash("Alice-Realm")] = 300, [R.Hash("Alt-Realm")] = 60, [R.Hash("Old-Realm")] = 20 }
    local picks = U.Pick(friend, theirs)
    local keys = {}
    for _, p in ipairs(picks) do keys[p.key] = p.theirs or "none" end
    H.eq(keys["Alice-Realm"], 300, "newer than theirs")
    H.eq(keys["Alt-Realm"], nil, "theirs is newer")
    H.eq(keys["Old-Realm"], nil, "the same")
    H.eq(keys["Third-Realm"], "none", "one they do not have at all")
end)

H.test("catch-up merge: adds what is missing, never replaces or counts twice", function()
    local ns = H.pureNamespace()
    local entered = NOW - 7200
    local mine = { level = 20, lastSeen = NOW - 100,
        days = { [TODAY] = { quests = 4, moneyNet = -300, played = 600 } },
        levels = { [20] = { from = 19, to = 20, active = 900, total = 1000, at = NOW - 5000, zone = "Here" } },
        dungeons = { { entered = entered, name = "The Deadmines", duration = 1800, completed = true } },
        currentRun = { entered = NOW - 600, name = "Wailing Caverns" },
        deathLog = { { at = NOW - 4000, level = 20 } }, items = {}, sessions = { { start = NOW - 9000, stop = NOW - 100 } } }
    local data = { key = "Alice-Realm", class = "MAGE", level = 21, lastSeen = NOW + 50,
        days = { [TODAY] = { quests = 2, moneyNet = 900, kills = 7 }, [YESTERDAY] = { quests = 5 } },
        levels = { [20] = { from = 19, to = 20, active = 1, total = 1, at = 1 }, [21] = { from = 20, to = 21, active = 800, total = 900, at = NOW } },
        runs = {
            { entered = entered, name = "The Deadmines", duration = 1800, completed = true, kills = 2 }, -- the same run
            { entered = entered + 60, name = "The Deadmines", duration = 100, kills = 0 },              -- inside mine
            { entered = NOW - 600, name = "Wailing Caverns", kills = 1 },                              -- the one I am in
            { entered = NOW - 86400, name = "Ragefire Chasm", duration = 1500, completed = true, kills = 4, clear = 1400 } },
        deathLog = { { at = NOW - 4000, level = 20 }, { at = NOW - 86000, level = 19 } },
        loot = { { at = NOW - 80000, id = 2042, quality = 3, count = 1 } },
        sessions = { { start = NOW - 9000, played = 1 }, { start = NOW - 90000, played = 3000, active = 2500 } } }
    local got = ns.CatchUp.Merge(mine, data)
    H.eq(mine.days[TODAY].quests, 4, "mine kept (bigger)")
    H.eq(mine.days[TODAY].kills, 7, "a count I did not have")
    H.eq(mine.days[TODAY].moneyNet, 900, "the bigger amount, even over a loss")
    H.eq(mine.days[YESTERDAY].quests, 5, "a day I did not have")
    H.eq(mine.levels[20].zone, "Here", "my level record untouched")
    H.eq(mine.levels[21].active, 800, "a level I did not have")
    H.eq(mine.level, 21)
    H.eq(#mine.dungeons, 2, "only the run I had no run at that time for")
    H.eq(mine.dungeons[1].name, "Ragefire Chasm", "kept in order")
    H.ok(mine.dungeons[1].recovered and mine.dungeons[1].completed)
    H.eq(mine.dungeons[1].completedAt, NOW - 86400 + 1400)
    H.eq(#mine.deathLog, 2)
    H.eq(#mine.items, 1)
    H.eq(mine.items[1].link, "item:2042")
    H.eq(#mine.sessions, 2)
    H.eq(mine.sessions[2].start, NOW - 9000, "my session still the newest")
    H.eq(mine.lastSeen, NOW + 50)
    H.eq(got.days, 2); H.eq(got.levels, 1); H.eq(got.runs, 1); H.eq(got.deaths, 1); H.eq(got.loot, 1); H.eq(got.sessions, 1)
    -- Again: nothing more (idempotent).
    H.ok(not ns.CatchUp.Any(ns.CatchUp.Merge(mine, data)), "the same copy twice adds nothing")
end)

-- Two computers and a friend ----------------------------------------------------------

local ACCOUNTS = { Alice = 1, Bob = 2 }

local function client(name, opts)
    opts = opts or {}
    local other = name == "Alice" and "Bob" or "Alice"
    local bn = { { battleTag = other .. "#1", games = { { gameAccountID = ACCOUNTS[other], characterName = other,
        realmName = "Realm", wowProjectID = 1 } } } }
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail", now = opts.now or NOW, playerName = name, realm = "Realm",
        projectID = 1, bnFriends = bn, charFriends = {} })
    env.__state.myGameAccount = ACCOUNTS[name]
    env.__state.bnTag = name .. "#1"
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    env.__ns = ns
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    env.FellowshipLedgerDB.settings.welcomeEveryLogin = false
    if opts.setup then opts.setup(env) end
    return env, ns
end

local function network(clients, seconds)
    for _ = 1, seconds or 60 do
        for _, c in ipairs(clients) do
            local st = c.__state
            st.now = st.now + 1
            for _, t in ipairs(st.tickers) do
                if t.seconds <= 1 or (st.now % t.seconds) == 0 then t.fn() end
            end
            Mock.runDueTimers(c)
        end
        for _, from in ipairs(clients) do
            local out = from.__state.sent
            from.__state.sent = {}
            for _, m in ipairs(out) do
                for _, to in ipairs(clients) do
                    if to ~= from and m.kind == "bn" and m.target == to.__state.myGameAccount then
                        Mock.fire(to, "BN_CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", from.__state.myGameAccount)
                    end
                end
            end
        end
    end
end

-- A new session for these clients: they greet and ask again.
-- fresh: these clients just logged in (their login snapshot stays as it is).
local function session(clients, seconds, fresh)
    for _, c in ipairs(clients) do
        local S = c.__ns.Sync
        S.lastHello, S.lastRequest, S.askedMine = {}, {}, {}
        if not (fresh and fresh[c]) then
            local seen = {}
            for key, ch in pairs(c.FellowshipLedgerDB.characters) do seen[key] = ch.lastSeen or 0 end
            c.__ns.Store.seenAtLogin = seen
            -- As Store.Login: the played character is seen now.
            if c.__ns.Store.char then c.__ns.Store.char.lastSeen = c.__state.now end
        end
    end
    for _, c in ipairs(clients) do c.__ns.Sync.SyncAll(true) end
    network(clients, seconds or 60)
end

local function alice(env) return env.FellowshipLedgerDB.characters["Alice-Realm"] end

local function twoComputers(setup)
    local A1 = client("Alice", { setup = setup and setup.A1 })
    local B = client("Bob", { setup = setup and setup.Bob })
    -- Computer 1: Alice quests a little today.
    local c = alice(A1)
    c.days[TODAY] = c.days[TODAY] or {}
    c.days[TODAY].quests = 2
    network({ A1, B }, 60)
    H.eq(B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Alice-Realm"].days[TODAY].quests, 2, "Bob has computer 1's play")
    -- Computer 2, a first login there, later: Bob hands computer 1's play over.
    local A2 = client("Alice", { now = NOW + 5000, setup = setup and setup.A2 })
    B.__state.now = NOW + 5000
    session({ A2, B }, 60, { [A2] = true })
    return A1, A2, B
end

H.test("catch-up: a new computer gets the play from the old one through a friend", function()
    local _, A2 = twoComputers()
    local c = alice(A2)
    H.eq(c.days[TODAY].quests, 2, "computer 1's quests reached computer 2")
    H.ok((A2.__ns.Sync.catchUpReceived or 0) >= 1, "counted")
end)

H.test("catch-up: back on the first computer, what was played on the second comes back", function()
    local A1, A2, B = twoComputers()
    -- Computer 2: a dungeon run and a death yesterday-to-today, and quests on another day.
    local c2 = alice(A2)
    c2.days[YESTERDAY] = { quests = 7 }
    local entered = NOW + 5100
    c2.dungeons[#c2.dungeons + 1] = { entered = entered, name = "Ragefire Chasm", duration = 1500, completed = true,
        completedAt = entered + 1400, bossCount = 4, bosses = { { at = entered + 600, name = "Oggleflint" } }, party = {} }
    c2.deathLog[#c2.deathLog + 1] = { at = NOW + 5200, level = 20, killer = "Taragaman" }
    network({ A2, B }, 120) -- live and timed syncs carry it to Bob
    B.__ns.Sync.SyncAll(true)
    session({ A2, B })
    local atBob = B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Alice-Realm"]
    H.ok(atBob.runs and #atBob.runs == 1, "Bob holds computer 2's run")
    -- Computer 1 again, later.
    A1.__state.now, B.__state.now = NOW + 9000, NOW + 9000
    session({ A1, B })
    local c1 = alice(A1)
    H.eq(c1.days[YESTERDAY] and c1.days[YESTERDAY].quests, 7, "computer 2's day")
    H.eq(c1.days[TODAY].quests, 2, "computer 1's own count kept")
    H.eq(#c1.dungeons, 1, "computer 2's run")
    H.eq(c1.dungeons[1].name, "Ragefire Chasm")
    H.eq(c1.dungeons[1].completedAt, entered + 1400)
    local found = false
    for _, d in ipairs(c1.deathLog) do if d.killer == "Taragaman" then found = true end end
    H.ok(found, "computer 2's death")
    -- Once a session: another round adds nothing and sends nothing more.
    local before = B.__ns.Sync.catchUpSent
    network({ A1, B }, 400)
    H.eq(B.__ns.Sync.catchUpSent, before, "asked once a session")
end)

H.test("catch-up: not when switched off on either side, and a removed character stays removed", function()
    local _, A2 = twoComputers({ A2 = function(env) env.FellowshipLedgerDB.settings.catchUpFromFriends = false end })
    H.eq(alice(A2).days[TODAY] and alice(A2).days[TODAY].quests, nil, "off on the asking computer")
    _, A2 = twoComputers({ Bob = function(env) env.FellowshipLedgerDB.settings.catchUpFromFriends = false end })
    H.eq(alice(A2).days[TODAY] and alice(A2).days[TODAY].quests, nil, "off at the friend")
    -- A character Alice removed on this computer is not brought back.
    local A1, B = client("Alice"), client("Bob")
    network({ A1, B }, 60)
    local mask = B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Alice-Realm"].mask
    B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Gone-Realm"] = { lastSeen = NOW - 50, mask = mask,
        days = { [TODAY] = { quests = 1 } }, levels = {}, sessions = {} }
    A1.FellowshipLedgerDB.removed = { ["Gone-Realm"] = NOW }
    session({ A1, B })
    H.eq(A1.FellowshipLedgerDB.characters["Gone-Realm"], nil, "removed stays removed")
    H.eq(B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Gone-Realm"], nil, "and Bob dropped it, as for any removal")
    -- A character only ever played elsewhere is added.
    A1.FellowshipLedgerDB.removed = {}
    local mask = B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Alice-Realm"].mask
    B.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Gone-Realm"] = { lastSeen = NOW - 50, mask = mask,
        days = { [TODAY] = { quests = 1 } }, levels = {}, sessions = {} }
    session({ A1, B })
    local g = A1.FellowshipLedgerDB.characters["Gone-Realm"]
    H.ok(g and g.days[TODAY].quests == 1, "a character from the other computer is added")
    H.eq(g.name, "Gone")
end)
