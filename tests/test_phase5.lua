-- Phase 5: notable loot, what killed you, quest-chain snapshots, chains shared with
-- friends and suggested back, 12.1.7 in the retail TOC.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local RETAIL = { interface = 120105, tocFlavor = "Retail" }

local function boot(opts, db, backup)
    local env = Mock.new(opts or RETAIL)
    env.FellowshipLedgerDB = db
    env.FellowshipLedgerBackupDB = backup
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    env.__ns = ns
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    return env, ns
end

local function char(env) return env.FellowshipLedgerDB.characters["Tester-TestRealm"] end
local function today(env) return char(env).days[os.date("%Y-%m-%d", env.__state.now)] or {} end

H.test("notable loot: green or better, only what is taken, never currency", function()
    local env = boot()
    env.__state.loot = {
        { name = "Linen Cloth", quality = 1, link = "|Hitem:2589|h[Linen Cloth]|h" },
        { name = "Gnoll Hide Belt", quality = 2, link = "|Hitem:100|h[Gnoll Hide Belt]|h" },
        { name = "Ancient Blade", quality = 4, link = "|Hitem:200|h[Ancient Blade]|h" },
        { name = "Valor", quality = 3, link = "|Hcurrency:1|h[Valor]|h", currency = 1191 },
        { name = "Seer's Robe", quality = 2, link = "|Hitem:300|h[Seer's Robe]|h" },
    }
    Mock.fire(env, "LOOT_READY", true)
    Mock.fire(env, "LOOT_OPENED", true, false)
    for slot = 1, 4 do Mock.fire(env, "LOOT_SLOT_CLEARED", slot) end -- slot 5 left behind
    Mock.fire(env, "LOOT_SLOT_CLEARED", 2) -- a repeat does not count twice
    Mock.fire(env, "LOOT_CLOSED")
    local items = char(env).items
    H.eq(#items, 2)
    H.eq(items[1].name, "Gnoll Hide Belt")
    H.eq(items[2].quality, 4)
    H.eq(today(env).itemsNotable, 2)
    H.eq(today(env).itemsEpic, 1)
    H.eq(items[1].zone, "Elwynn Forest")
end)

H.test("notable loot in a group: only what reaches your bags counts (D-125)", function()
    local env = boot()
    local bags = { [400] = 1 } -- one already carried
    env.C_Item = { GetItemCount = function(id) return bags[id] or 0 end }
    env.IsInGroup = function() return true end
    env.__state.loot = {
        { name = "Mine", quality = 3, link = "|Hitem:400|h[Mine]|h" },
        { name = "Theirs", quality = 4, link = "|Hitem:500|h[Theirs]|h" },
    }
    Mock.fire(env, "LOOT_OPENED", true, false)
    Mock.fire(env, "LOOT_SLOT_CLEARED", 1)
    Mock.fire(env, "LOOT_SLOT_CLEARED", 2) -- a group member took it, or won its roll
    bags[400] = 2
    Mock.advance(env, 5)
    local items = char(env).items
    H.eq(#items, 1, "only the item that reached my bags")
    H.eq(items[1].name, "Mine")
    H.eq(today(env).itemsEpic or 0, 0, "their epic is not mine")
    -- No bag count in a group: nothing is claimed.
    env.C_Item = nil
    Mock.fire(env, "LOOT_OPENED", true, false)
    Mock.fire(env, "LOOT_SLOT_CLEARED", 2)
    Mock.advance(env, 5)
    H.eq(#char(env).items, 1)
end)

H.test("what killed you: newest recap, killing blow by latest timestamp", function()
    local env = boot()
    env.__state.recaps = {
        [1] = { { timestamp = 5, sourceName = "Old Wolf", spellName = "Bite" } },
        [2] = { { timestamp = 10, sourceName = "Gnoll Brute", spellName = "Melee", amount = 120 },
                { timestamp = 12, sourceName = "Gnoll Mystic", spellName = "Lightning Bolt", amount = 300 },
                { timestamp = 8, sourceName = "Gnoll Brute", spellName = "Melee", amount = 90 } },
    }
    Mock.fire(env, "PLAYER_DEAD")
    Mock.runTimers(env)
    local d = char(env).deathLog[1]
    H.eq(d.killer, "Gnoll Mystic")
    H.eq(d.killerSpell, "Lightning Bolt")
    H.eq(d.killerStatus, "ok")
    local row = env.__ns.DetailModel.Data(char(env), env.__ns.L, os.date).deaths.rows[1]
    H.eq(row.killer, "Gnoll Mystic")
    H.eq(row.zone, "Elwynn Forest")
end)

H.test("what killed you: secret values are stored as hidden, never guessed", function()
    local env = boot()
    env.__state.recaps = { [1] = { { timestamp = 1, sourceName = "SECRET", spellName = "SECRET" } } }
    env.__state.secrets = { SECRET = true }
    Mock.fire(env, "PLAYER_DEAD")
    Mock.runTimers(env)
    local d = char(env).deathLog[1]
    H.eq(d.killer, nil)
    H.eq(d.killerStatus, "hidden")
    H.eq(env.__ns.DetailModel.Data(char(env), env.__ns.L, os.date).deaths.rows[1].killer, "Hidden by the game")
end)

H.test("no recap at all: the death is still counted", function()
    local env = boot()
    Mock.fire(env, "PLAYER_DEAD")
    Mock.runTimers(env)
    H.eq(today(env).deaths, 1)
    H.eq(char(env).deathLog[1].killerStatus, "none")
end)

H.test("quest-chain snapshot from game data, and from Questie with a start zone", function()
    local env, ns = boot()
    local chains = char(env).chains
    local c = chains["g:7"]
    H.ok(c, "chain recorded at login")
    H.eq(c.step, 1); H.eq(c.total, 3); H.eq(c.firstQuestID, 54); H.eq(c.firstName, "Quest 54"); H.eq(c.source, "game")
    env.__state.noQuestLines = true
    env.__state.questieLoaded = true
    env.__state.questie = { [50] = { next = 54, name = "Start Here", zone = 12 }, [54] = { pre = 50 } }
    env.__state.areas = { [12] = "Elwynn Forest" }
    ns.QuestChains.Snapshot()
    c = char(env).chains["q:50"]
    H.ok(c, "Questie chain recorded")
    H.eq(c.firstName, "Start Here")
    H.eq(c.startZone, "Elwynn Forest")
    H.eq(c.step, 2)
end)

H.test("chains travel only with Quests shared", function()
    local ns = H.pureNamespace()
    local c = ns.Character.Ensure({ class = "MAGE", level = 10 }, 0)
    c.chains["g:7"] = { name = "Chain, with \"quotes\" | and pipes", step = 2, total = 5, firstQuestID = 54, firstName = "Start", startZone = "Elwynn Forest", source = "game" }
    local shared = ns.Codec.SharedTrackers(c, false)
    local d = ns.Codec.DecodeData(ns.Codec.EncodeData("A-R", c, shared, nil))
    H.eq(d.chains["g:7"].name, "Chain, with \"quotes\" | and pipes")
    H.eq(d.chains["g:7"].firstQuestID, 54)
    H.eq(d.chains["g:7"].startZone, "Elwynn Forest")
    local friend = ns.Merge.Friend({}, { id = "bn:X#1", kind = "bnet", name = "X" })
    ns.Merge.Data(friend, d, "2026-11-04", "2026-08-07", 1)
    H.ok(friend.characters["A-R"].chains["g:7"])
    c.flags.quests.share = false
    local shared2 = ns.Codec.SharedTrackers(c, false)
    local d2 = ns.Codec.DecodeData(ns.Codec.EncodeData("A-R", c, shared2, nil))
    H.eq(next(d2.chains), nil, "no chains when Quests is not shared")
    ns.Merge.Data(friend, d2, "2026-11-04", "2026-08-07", 2)
    H.eq(friend.characters["A-R"].chains, nil, "stored chains cleared once Quests sharing stops")
end)

H.test("friend chain suggestions: skip chains I'm on or have started, and blocked friends", function()
    local ns = H.pureNamespace()
    local friends = {
        ["bn:A#1"] = { name = "Ann", tag = "Ann#1", characters = { ["Pip-R"] = { name = "Pip", chains = {
            ["g:1"] = { name = "Wolves", firstQuestID = 10 }, ["g:2"] = { name = "Bears", firstQuestID = 20 },
            ["g:3"] = { name = "Crabs", firstQuestID = 30 } } } } },
        ["bn:B#1"] = { name = "Bob", tag = "Bob#1", characters = { ["Zed-R"] = { name = "Zed", chains = {
            ["g:4"] = { name = "Owls", firstQuestID = 40 } } } } },
    }
    local list = ns.QuestChainLogic.FriendSuggestions(friends, function(f) return f.tag == "Bob#1" end,
        { ["g:1"] = true }, function(id) return id == 20 end)
    H.eq(#list, 1)
    H.eq(list[1].chain.name, "Crabs")
    H.eq(list[1].friend, "Ann")
end)

H.test("fake friends have chains to suggest, and the views render", function()
    local env, ns = boot()
    Mock.slash(env, "fake")
    local list = ns.QuestChainLogic.FriendSuggestions(ns.Data.Friends(), function() return false end, {}, function() return false end)
    H.ok(#list >= 1, "fake suggestions")
    ns.MainWindow.Open("me")
    ns.MeTab.Refresh()
    local chat = table.concat(env.__state.chat, "\n")
    H.ok(not chat:find("failed"), chat)
end)

H.test("/fl verify: death recap check", function()
    local env = boot()
    Mock.slash(env, "verify")
    H.ok(env.FellowshipLedgerDB.verify.text:find("INFO x:death.recap: no death recap this session", 1, true))
    env.__state.recaps = { [3] = { { timestamp = 1, sourceName = "Wolf", spellName = "Bite" } } }
    Mock.slash(env, "verify")
    H.ok(env.FellowshipLedgerDB.verify.text:find("PASS x:death.recap: recap 3: 1 events", 1, true), env.FellowshipLedgerDB.verify.text)
end)

H.test("commtest: self-whispers are recognised when realm spelling differs (Forever)", function()
    local env, ns = boot({ interface = 16001, tocFlavor = "Forever", realm = "Test Realm" })
    env.GetNormalizedRealmName = function() return "TestRealm" end
    H.eq(ns.Store.key, "Tester-Test Realm")
    for _, sender in ipairs({ "Tester-TestRealm", "Tester-Test Realm", "Tester", "tester-testrealm" }) do
        H.ok(ns.Friends.IsSelf(sender), sender)
    end
    H.ok(not ns.Friends.IsSelf("Tester-OtherRealm"), "same name on another realm is not me")
    H.ok(not ns.Friends.IsSelf("Someone-TestRealm"))
    Mock.slash(env, "commtest")
    local sent = env.__state.sent
    env.__state.sent = {}
    for _, m in ipairs(sent) do
        if m.kind == "addon" and m.channel == "WHISPER" then
            Mock.fire(env, "CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", "Tester-TestRealm")
        end
    end
    ns.Sync.CommTestReport()
    local text = ns.CopyWindow.text
    H.ok(text:find("received sizes: 60/WHISPER", 1, true), text)
    H.ok(not text:find("NOT recognised", 1, true), text)
end)

H.test("commtest reports a self mismatch clearly", function()
    local env, ns = boot()
    Mock.slash(env, "commtest")
    local sent = env.__state.sent
    env.__state.sent = {}
    for _, m in ipairs(sent) do
        if m.kind == "addon" and m.channel == "WHISPER" then
            Mock.fire(env, "CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", "Imposter-Elsewhere")
        end
    end
    ns.Sync.CommTestReport()
    H.ok(ns.CopyWindow.text:find("NOT recognised as self: sender 'Imposter-Elsewhere' vs key 'Tester-TestRealm'", 1, true), ns.CopyWindow.text)
end)

H.test("Forever name forms: 'Name Realm' senders and an internal realm ID", function()
    local env, ns = boot({ interface = 16001, tocFlavor = "Forever", playerName = "Tarahallow", realm = "Soldecouple" })
    env.GetNormalizedRealmName = function() return "CAMWOWUS1Realm3PvE" end
    local F = ns.Friends
    H.eq(ns.Store.key, "Tarahallow-Soldecouple")
    H.eq(F.OwnRealm(), "Soldecouple", "own realm comes from the character key, not the internal ID")
    H.eq(F.FullName("Tarahallow Soldecouple"), "Tarahallow-Soldecouple")
    H.eq(F.FullName("Bob"), "Bob-Soldecouple")
    H.eq(F.FullName("Bob", "Argent Dawn"), "Bob-ArgentDawn")
    H.eq(F.FullName("Bob Argent Dawn"), "Bob-ArgentDawn")
    H.eq(F.FullName("Bob-Argent Dawn"), "Bob-ArgentDawn")
    H.ok(F.IsSelf("Tarahallow Soldecouple"))
    H.ok(F.IsSelf("Tarahallow"))
    H.ok(not F.IsSelf("Tarahallow OtherRealm"))
    -- the commtest round trip with Forever's sender format
    Mock.slash(env, "commtest")
    local sent = env.__state.sent
    env.__state.sent = {}
    for _, m in ipairs(sent) do
        if m.kind == "addon" and m.channel == "WHISPER" then
            Mock.fire(env, "CHAT_MSG_ADDON", m.prefix, m.text, "WHISPER", "Tarahallow Soldecouple")
        end
    end
    ns.Sync.CommTestReport()
    H.ok(ns.CopyWindow.text:find("received sizes: 60/WHISPER, 100/WHISPER", 1, true), ns.CopyWindow.text)
end)

H.test("a character friend whispering as 'Name Realm' is recognised", function()
    local env, ns = boot({ interface = 16001, tocFlavor = "Forever", playerName = "Tarahallow", realm = "Soldecouple",
        charFriends = { { name = "Carl", connected = true } } })
    ns.Friends.Refresh()
    local peer = ns.Friends.PeerFor("whisper", "Carl Soldecouple")
    H.ok(peer, "found")
    H.eq(peer.id, "ch:Carl-Soldecouple")
    H.eq(peer.target, "Carl", "whispers go to the name the game gave")
end)
