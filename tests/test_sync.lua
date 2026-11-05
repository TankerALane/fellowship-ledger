-- Two (or three) mock clients wired together through a fake network: HELLO,
-- REQUEST and DATA flow both ways; blocks, combat, flavors, throttles, the
-- dungeon-name opt-in and /fl commtest behave.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local NOW = os.time({ year = 2026, month = 11, day = 4, hour = 12 })

-- Client A (Alice, gameAccountID 1) and client B (Bob, gameAccountID 2) are Battle.net friends.
local function client(name, myId, friendTag, friendId, friendName, opts)
    opts = opts or {}
    local o = { interface = opts.interface or 120105, tocFlavor = opts.tocFlavor or "Retail", now = NOW,
        playerName = name, realm = "Realm", projectID = opts.projectID or 1,
        bnFriends = { { battleTag = friendTag, games = { { gameAccountID = friendId, characterName = friendName,
            realmName = "Realm", wowProjectID = opts.friendProjectID or 1 } } } },
        charFriends = opts.charFriends or {} }
    local env = Mock.new(o)
    env.__state.myGameAccount = myId
    env.__state.bnTag = name .. "#1"
    local ns = Mock.loadToc(H, env, o.tocFlavor == "Forever" and "FellowshipLedger_Forever.toc" or "FellowshipLedger_Mainline.toc")
    env.__ns = ns
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    env.FellowshipLedgerDB.settings.welcomeEveryLogin = false
    return env, ns
end

-- Move every client's clock 1 s at a time, pump queues, deliver what was sent.
local function network(clients, seconds)
    for _ = 1, seconds or 120 do
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
                    local st = to.__state
                    if m.kind == "bn" and m.target == st.myGameAccount then
                        Mock.fire(to, "BN_CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", from.__state.myGameAccount)
                    elseif m.kind == "addon" and m.channel == "WHISPER" and (m.target == st.name or m.target == (st.name .. "-" .. st.realm)) then
                        Mock.fire(to, "CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", from.__state.name .. "-" .. from.__state.realm)
                    elseif m.kind == "addon" and (m.channel == "PARTY" or m.channel == "INSTANCE_CHAT") and to ~= from then
                        Mock.fire(to, "CHAT_MSG_ADDON", m.prefix, m.text, m.channel, from.__state.name .. "-" .. from.__state.realm)
                    end
                end
            end
        end
    end
end

local function giveData(env, quests)
    local c = env.FellowshipLedgerDB.characters[env.__state.name .. "-Realm"]
    c.days[os.date("%Y-%m-%d", NOW)] = { quests = quests, moneyNet = 5000, played = 3600, active = 3000, levels = 2 }
    c.levels[12] = { from = 11, to = 12, active = 900, total = 1000, at = NOW - 100 }
    return c
end

H.test("two friends exchange their ledgers both ways", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(A, 7)
    giveData(B, 3)
    network({ A, B }, 60)
    local fromBob = A.FellowshipLedgerDB.friends["bn:Bob#1"]
    H.ok(fromBob, "A stored Bob")
    H.eq(fromBob.name, "Bob")
    H.eq(fromBob.characters["Bob-Realm"].days[os.date("%Y-%m-%d", NOW)].quests, 3)
    H.eq(fromBob.characters["Bob-Realm"].levels[12].active, 900)
    local fromAlice = B.FellowshipLedgerDB.friends["bn:Alice#1"]
    H.eq(fromAlice.characters["Alice-Realm"].days[os.date("%Y-%m-%d", NOW)].quests, 7)
    H.ok(fromAlice.lastUpdated, "last updated time kept")
end)

H.test("unshared trackers, paused sharing and fake data never leave", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    local c = giveData(A, 7)
    c.flags.gold.share = false
    Mock.slash(A, "fake") -- fake set exists on A
    network({ A, B }, 60)
    local got = B.FellowshipLedgerDB.friends["bn:Alice#1"].characters
    H.ok(got["Alice-Realm"], "real character arrived")
    H.eq(got["Alice-Realm"].days[os.date("%Y-%m-%d", NOW)].moneyNet, nil, "gold not shared")
    for key in pairs(got) do H.ok(not key:find("Fakerealm"), "fake character leaked: " .. key) end
    -- now pause everything on a fresh pair
    local A2 = client("Alice", 1, "Bob#1", 2, "Bob")
    local B2 = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(A2, 7)
    A2.FellowshipLedgerDB.settings.sharingPaused = true
    network({ A2, B2 }, 60)
    local f = B2.FellowshipLedgerDB.friends["bn:Alice#1"]
    H.ok(not f or next(f.characters) == nil, "paused: no characters sent")
end)

H.test("blocked friends get nothing and are not stored", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(A, 7)
    A.FellowshipLedgerDB.blocklist["Bob#1"] = true
    network({ A, B }, 60)
    H.eq(A.FellowshipLedgerDB.friends["bn:Bob#1"], nil, "nothing stored from a blocked friend")
    local f = B.FellowshipLedgerDB.friends["bn:Alice#1"]
    H.ok(not f or not f.characters["Alice-Realm"], "nothing sent to a blocked friend")
end)

H.test("Forever and retail never mix", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice", { interface = 16001, tocFlavor = "Forever", projectID = 1 })
    giveData(A, 7)
    giveData(B, 3)
    network({ A, B }, 60)
    H.eq(A.FellowshipLedgerDB.friends["bn:Bob#1"], nil)
    H.eq(B.FellowshipLedgerDB.friends["bn:Alice#1"], nil)
    -- a retail-prefix message carrying the Forever flavor code is dropped too
    local A2 = client("Alice", 1, "Bob#1", 2, "Bob")
    local before = A2.__ns.Transport.stats.dropped
    Mock.fire(A2, "BN_CHAT_MSG_ADDON", "FLDGR", "1|F|H|ab|1|1|h,0.0.1,0,1~c,Bob-Realm,MAGE,10,1111,0", "WHISPER", 2)
    H.eq(A2.__ns.Transport.stats.dropped, before + 1)
    H.eq(A2.FellowshipLedgerDB.friends["bn:Bob#1"], nil)
    -- the same message with the right code is accepted
    Mock.fire(A2, "BN_CHAT_MSG_ADDON", "FLDGR", "1|R|H|ac|1|1|h,0.0.1,0,0~c,Bob-Realm,MAGE,10,1111,0", "WHISPER", 2)
    H.ok(A2.FellowshipLedgerDB.friends["bn:Bob#1"], "matching flavor accepted")
end)

H.test("friends on another project are not even messaged", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob", { friendProjectID = 5 })
    network({ A }, 20)
    for _, m in ipairs(A.__state.sent) do H.ok(m.kind ~= "bn", "messaged a friend on another flavor") end
end)

H.test("Forever: a friend whose game version is not reported (project 0) still shares, both ways", function()
    local fo = { interface = 16001, tocFlavor = "Forever", projectID = 18, friendProjectID = 0 }
    local a, nsA = client("Ned", 1, "Tara#2", 2, "Tara Hallow", fo)
    local b, nsB = client("Tara", 2, "Ned#1", 1, "Ned Row", fo)
    giveData(a, 3)
    giveData(b, 3)
    nsA.Sync.SyncAll(true)
    network({ a, b }, 120)
    H.ok(nsB.db.friends["bn:Ned#1"], "Ned's ledger reached Tara")
    H.ok(nsA.db.friends["bn:Tara#2"], "Tara's ledger reached Ned")
end)

H.test("nothing is sent in combat; it goes out afterwards", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(A, 7)
    A.__state.combat = true
    local sentInCombat = 0
    for _ = 1, 30 do
        network({ A, B }, 1)
        sentInCombat = sentInCombat + #A.__state.sent
    end
    H.ok(not B.FellowshipLedgerDB.friends["bn:Alice#1"], "nothing arrived during combat")
    A.__state.combat = false
    network({ A, B }, 60)
    H.ok(B.FellowshipLedgerDB.friends["bn:Alice#1"], "sent after combat")
end)

H.test("throttle results are retried, offline drops the queue", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    A.__state.sendResult = 3 -- AddonMessageThrottle
    network({ A }, 15)
    local T = A.__ns.Transport
    H.ok(T.stats.retried > 0, "retried")
    H.ok(#T.queue > 0, "still queued")
    A.__state.sendResult = 12 -- TargetOffline
    network({ A }, 120)
    H.eq(#T.queue, 0, "dropped for an offline friend")
end)

H.test("character friends sync by whisper; strangers are ignored", function()
    local A = client("Alice", 1, "Nobody#1", 9, "Nobody", { charFriends = { { name = "Carl", connected = true } } })
    local C = client("Carl", 3, "Nobody#2", 8, "Nobody", { charFriends = { { name = "Alice", connected = true } } })
    giveData(A, 4)
    giveData(C, 6)
    network({ A, C }, 60)
    H.eq(A.FellowshipLedgerDB.friends["ch:Carl-Realm"].characters["Carl-Realm"].days[os.date("%Y-%m-%d", NOW)].quests, 6)
    local S = client("Stranger", 7, "Nobody#3", 6, "Nobody", { charFriends = { { name = "Alice", connected = true } } })
    giveData(S, 9)
    network({ A, S }, 60)
    H.eq(A.FellowshipLedgerDB.friends["ch:Stranger-Realm"], nil, "not a friend of Alice: ignored")
end)

H.test("level milestone notice when a friend crosses a multiple of 10", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(B, 3)
    network({ A, B }, 60)
    B.FellowshipLedgerDB.characters["Bob-Realm"].level = 20
    A.__ns.Sync.lastRequest = {}
    A.__ns.Sync.SyncAll(true)
    network({ A, B }, 60)
    H.ok(Mock.chatContains(A, "Bob (Bob) reached level 20!"), table.concat(A.__state.chat, "\n"))
end)

H.test("dungeon names appear only for party members who opted in", function()
    local A = client("Alice", 1, "Nobody#1", 9, "Nobody")
    local B = client("Bob", 2, "Nobody#2", 8, "Nobody")
    A.__state.units.party1 = { name = "Bob", class = "PRIEST", role = "HEALER", level = 20 }
    A.__state.units.party2 = { name = "Dana", class = "MAGE", role = "DAMAGER", level = 20 }
    A.__state.instance = { "Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
    B.__state.instance = { "Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
    B.FellowshipLedgerDB.settings.shareNameInDungeons = true
    Mock.fire(A, "PLAYER_ENTERING_WORLD", false, false)
    Mock.fire(B, "PLAYER_ENTERING_WORLD", false, false)
    network({ A, B }, 20)
    local run = A.FellowshipLedgerDB.characters["Alice-Realm"].currentRun
    H.eq(run.party[1].name, "Bob", "opted-in member named")
    H.eq(run.party[2].name, nil, "everyone else stays nameless")
end)

H.test("/fl commtest reports sizes, results and argument shapes", function()
    local A = client("Alice", 1, "Nobody#1", 9, "Nobody")
    Mock.slash(A, "commtest")
    network({ A }, 8)
    local text = A.__ns.CopyWindow.text
    H.ok(text:find("sent 255 bytes: Success", 1, true), text)
    H.ok(text:find("received sizes: 60/WHISPER", 1, true), text)
    H.ok(text:find("args CHAT_MSG_ADDON: string,string,string,string", 1, true), text)
    H.ok(A.FellowshipLedgerDB.dev.commtest)
end)

H.test("/fl comms status and size setting", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    Mock.slash(A, "comms size 120")
    H.eq(A.FellowshipLedgerDB.settings.commsChunk, 120)
    Mock.slash(A, "comms size 9999")
    H.eq(A.FellowshipLedgerDB.settings.commsChunk, 255)
    Mock.slash(A, "comms")
    H.ok(Mock.chatContains(A, "Sharing: prefix FLDGR, size 255"))
end)

H.test("graphs compare a friend's character with mine", function()
    local A = client("Alice", 1, "Bob#1", 2, "Bob")
    local B = client("Bob", 2, "Alice#1", 1, "Alice")
    giveData(A, 7)
    giveData(B, 3)
    network({ A, B }, 60)
    local ns = A.__ns
    ns.MainWindow.Open("graphs")
    local list = ns.Data.GraphableCharacters()
    H.eq(#list, 2, "mine and Bob's")
    ns.GraphsTab.Refresh()
    local chat = table.concat(A.__state.chat, "\n")
    H.ok(not chat:find("failed"), chat)
end)

H.test("a send that errors fails that message only; sharing stays on", function()
    local a, nsA = client("Alice", 1, "Bob#2", 2, "Bob")
    local b, nsB = client("Bob", 2, "Alice#1", 1, "Alice")
    local real = a.C_BattleNet.SendGameData
    local calls = 0
    a.C_BattleNet.SendGameData = function(...)
        calls = calls + 1
        if calls == 1 then error("game account went away") end
        return real(...)
    end
    nsA.Sync.SyncAll(true)
    network({ a, b }, 60)
    H.ok(not nsA.Compat.IsDisabled("comms"), "comms still on: " .. tostring(nsA.Compat.disabled.comms))
    H.ok(nsA.Transport.lastError and nsA.Transport.lastError:find("went away", 1, true), "error kept for /fl comms")
    H.eq(#nsA.Transport.queue, 0, "queue drained")
    nsA.Sync.lastHello, nsA.Sync.lastRequest = {}, {}
    nsA.Sync.SyncAll(true)
    network({ a, b }, 120)
    H.ok(nsA.db.friends["bn:Bob#2"], "Bob's ledger arrived after the failed send")
end)

H.test("/fl friends reports each friend and whether they will be messaged", function()
    local a, nsA = client("Alice", 1, "Bob#2", 2, "Bob", { friendProjectID = 2 })
    Mock.slash(a, "friends")
    local text = nsA.CopyWindow.text
    H.ok(text:find("game 1: client", 1, true), text)
    H.ok(text:find("skipped: other game version", 1, true), text)
    H.ok(not text:find("#2", 1, true), "BattleTag number left out")
end)

H.test("Forever shows first and last names for me and for friends", function()
    local fo = { interface = 16001, tocFlavor = "Forever", projectID = 18, friendProjectID = 18 }
    local a, nsA = client("Ned", 1, "Tara#2", 2, "Tara Hallow", fo)
    local b, nsB = client("Tara", 2, "Ned#1", 1, "Ned Row", fo)
    nsA.Sync.SyncAll(true)
    network({ a, b }, 120)
    local f = nsB.db.friends["bn:Ned#1"]
    H.ok(f, "Ned's ledger arrived on Forever")
    local key = next(f.characters)
    H.eq(f.characters[key].display, f.characters[key].name .. " " .. f.characters[key].realm)
    H.eq(nsA.Store.char.display, "Ned " .. nsA.Store.char.realm, "own display name is First Last")
end)
