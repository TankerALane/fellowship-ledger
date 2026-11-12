-- Relaying between mutual friends (D-124): Comms/Relay.lua on its own, and three mock
-- clients where Alice and Bob are never online together and Carol passes Alice's
-- newer progress on to Bob.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local NOW = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
local TODAY = os.date("%Y-%m-%d", NOW)

-- Pure ------------------------------------------------------------------------------

H.test("relay hash: 8 hex digits, stable, different for different keys", function()
    local ns = H.pureNamespace()
    local a = ns.Relay.Hash("Alice-Realm")
    H.ok(a:match("^%x%x%x%x%x%x%x%x$"), a)
    H.eq(ns.Relay.Hash("Alice-Realm"), a)
    H.ok(ns.Relay.Hash("Alicf-Realm") ~= a, "different key, different hash")
end)

H.test("relay records travel in HELLO and REQUEST; older readers still read theirs", function()
    local ns = H.pureNamespace()
    local C = ns.Codec
    local body = C.EncodeHello({ version = "1.11.0", characters = {}, relay = true, noRelay = { "0000abcd", "1234ffff" } })
    local h = C.DecodeHello(body)
    H.eq(h.version, "1.11.0")
    H.ok(h.relay, "relay flag")
    H.ok(h.noRelay["0000abcd"] and h.noRelay["1234ffff"], "blocked hashes")
    H.ok(not C.DecodeHello(C.EncodeHello({ version = "1.11.0", characters = {} })).relay, "no flag when off")
    local q = C.EncodeRequest("2026-11-03", { { hash = "0000abcd", lastSeen = 1234567 } })
    local r = C.DecodeRequest(q)
    H.eq(r.since, "2026-11-03")
    H.eq(r.known["0000abcd"], 1234567)
    H.eq(C.DecodeRequest(C.EncodeRequest(nil)).known, nil, "no list, nothing known")
    H.eq(C.TYPES.R, "RELAY")
end)

local function friends(ns)
    return {
        ["bn:Alice#1"] = { kind = "bnet", tag = "Alice#1", relay = true, characters = {
            ["Alice-Realm"] = { lastSeen = 500, mask = "1" },
            ["Alt-Realm"] = { lastSeen = 100, mask = "1" } } },
        ["bn:Dan#1"] = { kind = "bnet", tag = "Dan#1", characters = { -- an older ledger: no relay flag
            ["Dan-Realm"] = { lastSeen = 900 } } },
        ["bn:Bob#1"] = { kind = "bnet", tag = "Bob#1", relay = true, characters = { ["Bob-Realm"] = { lastSeen = 50 } } },
    }
end

H.test("relay: what I list, and what I pass on", function()
    local ns = H.pureNamespace()
    local R = ns.Relay
    local f = friends(ns)
    local known = R.Known(f, {}, "bn:Bob#1")
    H.eq(#known, 3, "Bob's own character left out")
    H.eq(known[1].lastSeen, 900, "freshest first")
    local bob = { id = "bn:Bob#1", tag = "Bob#1", character = "Bob-Realm" }
    local theirs = { [R.Hash("Alice-Realm")] = 400, [R.Hash("Alt-Realm")] = 100, [R.Hash("Dan-Realm")] = 10 }
    local picks = R.Pick(f, {}, bob, theirs)
    H.eq(#picks, 1, "only newer copies, only owners who allow it")
    H.eq(picks[1].key, "Alice-Realm")
    H.eq(picks[1].theirs, 400)
    -- Alice blocked Bob: her HELLO's hashes stop it.
    f["bn:Alice#1"].noRelay = { [R.Hash("Bob#1")] = true }
    H.eq(#R.Pick(f, {}, bob, theirs), 0, "never to someone the owner blocked")
    f["bn:Alice#1"].noRelay = nil
    -- I blocked Alice: I pass nothing of hers on, and list nothing of hers.
    H.eq(#R.Pick(f, { ["Alice#1"] = true }, bob, theirs), 0)
    H.eq(#R.Known(f, { ["Alice#1"] = true }, "bn:Bob#1"), 1)
    -- Receiving: only a character I already hold, never via its own owner, never blocked.
    local id = R.Owner(f, {}, "Alice-Realm", "bn:Carol#1")
    H.eq(id, "bn:Alice#1")
    H.eq(R.Owner(f, {}, "Stranger-Realm", "bn:Carol#1"), nil)
    H.eq(R.Owner(f, { ["Alice#1"] = true }, "Alice-Realm", "bn:Carol#1"), nil)
end)

H.test("relay: a received character is sent on unchanged (runs, bosses, group, loot)", function()
    local ns = H.pureNamespace()
    local C = ns.Codec
    local entered = NOW - 3600
    local own = { class = "MAGE", race = "Human", faction = "Alliance", level = 20, lastSeen = NOW,
        days = { [TODAY] = { quests = 4, played = 600 } }, levels = {}, sessions = {},
        dungeons = { { entered = entered, name = "The Deadmines", duration = 1900, completed = true, completedAt = entered + 1500,
            bossCount = 2, deaths = 1, levelMax = 21,
            bosses = { { at = entered + 600, fight = 40, name = "Rhahk'Zor" }, { at = entered + 1500, fight = 90, name = "Van" } },
            party = { { name = "Carol", friend = true }, {}, {} } } },
        items = { { link = "|cff0070dd|Hitem:2042:::|h[Staff]|h|r", quality = 3, quantity = 1, at = NOW - 100, zone = "Westfall" } } }
    local shared = C.MaskToSet(C.ShareMask(C.SharedTrackers(own, false)))
    local first = C.DecodeData(C.EncodeData("Alice-Realm", own, shared, nil))
    local stored = { days = {}, levels = {}, sessions = {} }
    local f = { characters = { ["Alice-Realm"] = stored } }
    ns.Merge.Data(f, first, TODAY, "2026-08-01", NOW)
    local again = C.DecodeData(C.EncodeData("Alice-Realm", ns.Relay.AsOwn(f.characters["Alice-Realm"]), shared, nil))
    H.eq(again.days[TODAY].quests, 4)
    local r1, r2 = first.runs[1], again.runs[1]
    H.ok(r2, "the run travels on")
    H.eq(r2.clear, r1.clear)
    H.eq(r2.kills, 2)
    H.eq(r2.splits[2].at, r1.splits[2].at)
    H.eq(r2.splits[2].fight, 90)
    H.eq(r2.bossNames[1], "Rhahk'Zor")
    H.eq(r2.names[1], "Carol")
    H.eq(r2.size, r1.size)
    H.eq(r2.levelMax, 21)
    H.eq(again.loot[1].id, 2042)
    H.eq(again.loot[1].zone, "Westfall")
end)

-- Three clients ------------------------------------------------------------------------

local ACCOUNTS = { Alice = 1, Bob = 2, Carol = 3 }

local function client(name, opts)
    opts = opts or {}
    local bn = {}
    for _, other in ipairs({ "Alice", "Bob", "Carol" }) do
        if other ~= name then
            bn[#bn + 1] = { battleTag = other .. "#1", games = { { gameAccountID = ACCOUNTS[other], characterName = other,
                realmName = "Realm", wowProjectID = 1 } } }
        end
    end
    local o = { interface = 120105, tocFlavor = "Retail", now = NOW, playerName = name, realm = "Realm", projectID = 1,
        bnFriends = bn, charFriends = {} }
    local env = Mock.new(o)
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

-- Only the clients listed are online: whatever is sent to anyone else is lost.
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
                    if m.kind == "bn" and m.target == to.__state.myGameAccount then
                        Mock.fire(to, "BN_CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", from.__state.myGameAccount)
                    end
                end
            end
        end
    end
end

-- A fresh round between these clients: everyone greets and asks again.
local function resync(clients, seconds)
    for _, c in ipairs(clients) do
        local S = c.__ns.Sync
        S.lastHello, S.lastRequest = {}, {}
    end
    for _, c in ipairs(clients) do c.__ns.Sync.SyncAll(true) end
    network(clients, seconds or 60)
end

local function play(env, quests, later)
    local c = env.FellowshipLedgerDB.characters[env.__state.name .. "-Realm"]
    c.days[TODAY] = c.days[TODAY] or {}
    c.days[TODAY].quests = quests
    c.lastSeen = later
    return c
end

local function aliceAtBob(B)
    local f = B.FellowshipLedgerDB.friends["bn:Alice#1"]
    return f and f.characters["Alice-Realm"]
end

local function scenario(setup)
    local A = client("Alice", { setup = setup and setup.Alice })
    local B = client("Bob", { setup = setup and setup.Bob })
    local C = client("Carol", { setup = setup and setup.Carol })
    play(A, 2, NOW + 5)
    network({ A, B, C }, 60)
    H.eq(aliceAtBob(B).days[TODAY].quests, 2, "Bob got Alice's data directly")
    -- Bob logs off; Alice plays on with Carol online.
    play(A, 9, NOW + 5000)
    A.__state.now, C.__state.now = NOW + 5000, NOW + 5000
    resync({ A, C })
    H.eq(C.FellowshipLedgerDB.friends["bn:Alice#1"].characters["Alice-Realm"].days[TODAY].quests, 9, "Carol has Alice's newer data")
    -- Alice logs off; Bob comes back while Carol is on.
    B.__state.now, C.__state.now = NOW + 9000, NOW + 9000
    resync({ B, C })
    return A, B, C
end

H.test("relay: Bob gets Alice's newer progress from Carol, marked via Carol", function()
    local A, B, C = scenario()
    local c = aliceAtBob(B)
    H.eq(c.days[TODAY].quests, 9, "Alice's newer quests reached Bob through Carol")
    H.ok(c.lastSeen >= NOW + 5000, "her newer last-played time")
    H.eq(c.via, "Carol")
    H.ok(C.__ns.Sync.relaySent >= 1, "Carol counted it")
    -- Alice and Bob meet again: Alice's own data replaces it and the mark goes.
    A.__state.now = B.__state.now
    play(A, 10, B.__state.now)
    resync({ A, B })
    c = aliceAtBob(B)
    H.eq(c.days[TODAY].quests, 10)
    H.eq(c.via, nil, "straight from Alice: no longer via Carol")
end)

H.test("relay: not when the owner switched it off, blocked the receiver, or the receiver switched it off", function()
    local _, B = scenario({ Alice = function(env) env.FellowshipLedgerDB.settings.relayFriends = false end })
    H.eq(aliceAtBob(B).days[TODAY].quests, 2, "Alice's own setting off: her data is not passed on")
    _, B = scenario({ Bob = function(env) env.FellowshipLedgerDB.settings.relayFriends = false end })
    H.eq(aliceAtBob(B).days[TODAY].quests, 2, "Bob's setting off: he takes nothing relayed")
    -- Alice blocks Bob after he already holds her data: Carol must not keep him updated.
    local A = client("Alice")
    B = client("Bob")
    local C = client("Carol")
    play(A, 2, NOW + 5)
    network({ A, B, C }, 60)
    A.FellowshipLedgerDB.blocklist["Bob#1"] = true
    play(A, 9, NOW + 5000)
    A.__state.now, C.__state.now = NOW + 5000, NOW + 5000
    resync({ A, C })
    B.__state.now, C.__state.now = NOW + 9000, NOW + 9000
    resync({ B, C })
    H.eq(aliceAtBob(B).days[TODAY].quests, 2, "blocked by Alice: nothing of hers relayed to Bob")
end)

H.test("relay: an older or equal copy is never taken, and strangers' characters are never added", function()
    local _, B, C = scenario()
    local Sync = B.__ns.Sync
    local dropped = Sync.relayDropped or 0
    -- Carol relays the same copy again (her memo cleared): Bob already has it.
    C.__ns.Sync.relayed = {}
    resync({ B, C })
    H.eq(aliceAtBob(B).via, "Carol")
    -- A relay for a character Bob never had from anyone.
    local body = B.__ns.Codec.EncodeData("Stranger-Realm", { class = "ROGUE", level = 5, lastSeen = NOW + 99999, days = {} },
        { levels = true }, nil)
    local peer = B.__ns.Friends.peers["bn:Carol#1"]
    B.__ns.Transport.handlers.R(peer, body)
    for _, f in pairs(B.FellowshipLedgerDB.friends) do H.eq(f.characters["Stranger-Realm"], nil, "not added") end
    H.ok((Sync.relayDropped or 0) > dropped, "counted as not needed")
end)
