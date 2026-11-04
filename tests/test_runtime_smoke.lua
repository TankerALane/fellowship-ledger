-- Loads the whole addon against tests/wowmock.lua and drives it like a player would.
-- Proves the runtime code paths run; does not prove real-client behaviour.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local function boot(opts, savedDB, savedBackup)
    local env = Mock.new(opts)
    env.FellowshipLedgerDB = savedDB
    env.FellowshipLedgerBackupDB = savedBackup
    local ns = Mock.loadToc(H, env, (opts and opts.toc) or "FellowshipLedger_Forever.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    return env, ns
end

H.test("Forever: loads, migrates and greets", function()
    local env, ns = boot()
    H.eq(ns.Compat.flavor, "Forever")
    H.eq(ns.Compat.tocFlavor, "Forever")
    H.eq(env.FellowshipLedgerDB.schemaVersion, ns.Migrations.CURRENT)
    H.ok(Mock.chatContains(env, "The ledger is open (v0.0.1-dev, Forever)"))
    H.ok(not Mock.chatContains(env, "Warning: this client"), "no flavor warning expected")
end)

H.test("Forever reminds about /fl verify until a Forever report is saved", function()
    local env = boot()
    H.ok(Mock.chatContains(env, "has not been checked on WoW Forever yet"))
    Mock.slash(env, "verify")
    local env2 = boot(nil, env.FellowshipLedgerDB, env.FellowshipLedgerBackupDB)
    H.ok(not Mock.chatContains(env2, "has not been checked on WoW Forever yet"))
    local env3 = boot({ interface = 120105, tocFlavor = "Retail", toc = "FellowshipLedger_Mainline.toc" })
    H.ok(not Mock.chatContains(env3, "has not been checked on WoW Forever yet"), "never on retail")
end)

H.test("both slash commands are registered", function()
    local env = boot()
    H.eq(env.SLASH_FELLOWSHIPLEDGER1, "/fl")
    H.eq(env.SLASH_FELLOWSHIPLEDGER2, "/fellowshipledger")
end)

H.test("/fl verify runs every check without a crash and saves the report", function()
    local env, ns = boot()
    Mock.slash(env, "verify")
    local v = env.FellowshipLedgerDB.verify
    H.ok(v and v.text, "report saved")
    H.eq(v.counts.ERROR, 0, "no check should crash in the mock\n" .. v.text)
    H.ok(v.text:find("PASS x:build.interface: 16001 -> Forever", 1, true))
    H.ok(v.text:find("PASS x:build.tocflavor", 1, true))
    H.ok(v.text:find("PASS x:comms.prefix: FLDGF", 1, true))
    H.ok(v.text:find("PASS x:secret.ownvalues", 1, true))
    H.ok(v.text:find("1 returned a quest line", 1, true))
    H.ok(v.text:find("FAIL C_BattleNet.GetGameAccountInfoByID", 1, true), "missing APIs show as FAIL")
    local total = v.counts.PASS + v.counts.FAIL + v.counts.ERROR + v.counts.INFO + v.counts.MANUAL
    H.eq(total, #ns.VerifyChecks)
end)

H.test("verify report never contains friend names or BattleTags", function()
    local env = boot()
    Mock.slash(env, "verify")
    local text = env.FellowshipLedgerDB.verify.text
    for _, secret in ipairs({ "Secret#1234", "Hidden", "HiddenFriend" }) do
        H.ok(not text:find(secret, 1, true), "report leaked " .. secret)
    end
    H.ok(text:find("WoW/99 x1", 1, true), "client/project pairs are reported")
end)

H.test("verify still runs when many APIs are missing", function()
    local env = boot({ missing = { "C_QuestLog", "C_QuestLine", "C_Map", "Enum", "C_ChatInfo",
        "BNGetNumFriends", "C_FriendList", "GetProfessions", "C_EventUtils" } })
    Mock.slash(env, "verify")
    local v = env.FellowshipLedgerDB.verify
    H.ok(v and v.text)
    H.eq(v.counts.ERROR, 0, v.text)
    H.ok(v.counts.FAIL > 10)
end)

H.test("events are checked by RegisterEvent when C_EventUtils is missing", function()
    Mock.knownEvents = { ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true, PLAYER_LEVEL_UP = true }
    local ok, err = pcall(function()
        local env = boot({ missing = { "C_EventUtils" } })
        Mock.slash(env, "verify")
        local text = env.FellowshipLedgerDB.verify.text
        H.ok(text:find("FAIL ev:QUEST_TURNED_IN: unknown event (checked with RegisterEvent)", 1, true), text)
        H.ok(not text:find("FAIL ev:PLAYER_LEVEL_UP", 1, true))
    end)
    Mock.knownEvents = nil
    if not ok then error(err, 0) end
end)

H.test("saved variables persistence probe counts reloads", function()
    local env1 = boot()
    Mock.fire(env1, "PLAYER_LOGOUT")
    local db, backup = env1.FellowshipLedgerDB, env1.FellowshipLedgerBackupDB
    H.eq(db.dev.persistProbe.loads, 1)
    H.ok(db.dev.persistProbe.lastLogout)
    local env2 = boot(nil, db, backup)
    Mock.slash(env2, "verify")
    local text = env2.FellowshipLedgerDB.verify.text
    H.ok(text:find("PASS x:sv.persist: loads=2", 1, true), text)
    H.ok(text:find("PASS x:sv.backup: loads=2", 1, true), text)
end)

H.test("probe counts events, survives reload, and skips args for addon messages", function()
    local env = boot()
    Mock.slash(env, "probe on")
    Mock.fire(env, "PLAYER_LEVEL_UP", 13, 0)
    Mock.fire(env, "CHAT_MSG_ADDON", "FLDGF", "private payload", "WHISPER", "Someone")
    local p = env.FellowshipLedgerDB.dev.probe
    H.eq(p.enabled, true)
    H.eq(p.events.PLAYER_LEVEL_UP.count, 1)
    H.eq(p.events.PLAYER_LEVEL_UP.samples[1], "(13, 0)")
    H.eq(p.events.CHAT_MSG_ADDON.count, 1)
    H.eq(#p.events.CHAT_MSG_ADDON.samples, 0)
    -- reload: probe restarts by itself
    local env2 = boot(nil, env.FellowshipLedgerDB, env.FellowshipLedgerBackupDB)
    Mock.fire(env2, "PLAYER_LEVEL_UP", 14, 0)
    H.eq(env2.FellowshipLedgerDB.dev.probe.events.PLAYER_LEVEL_UP.count, 2)
    Mock.slash(env2, "verify")
    H.ok(env2.FellowshipLedgerDB.verify.text:find("PLAYER_LEVEL_UP=2 | (13, 0) | (14, 0)", 1, true))
    Mock.slash(env2, "probe off")
    H.eq(env2.FellowshipLedgerDB.dev.probe.enabled, false)
    Mock.slash(env2, "probe clear")
    H.eq(next(env2.FellowshipLedgerDB.dev.probe.events), nil)
end)

H.test("other commands run and unknown ones print help", function()
    local env = boot()
    Mock.slash(env, "version")
    H.ok(Mock.chatContains(env, "flavor Forever (file Forever) | interface 16001"))
    Mock.slash(env, "debug")
    H.eq(env.FellowshipLedgerDB.settings.debug, true)
    Mock.slash(env, "debug")
    H.eq(env.FellowshipLedgerDB.settings.debug, false)
    Mock.slash(env, "verify show")
    Mock.slash(env, "nonsense")
    H.ok(Mock.chatContains(env, "/fl verify - check"))
    H.ok(not Mock.chatContains(env, "failed:"), "no command should fail")
end)

H.test("Retail TOC on a retail client", function()
    local env, ns = boot({ interface = 120105, tocFlavor = "Retail", toc = "FellowshipLedger_Mainline.toc" })
    H.eq(ns.Compat.flavor, "Retail")
    Mock.slash(env, "verify")
    H.ok(env.FellowshipLedgerDB.verify.text:find("PASS x:comms.prefix: FLDGR", 1, true))
end)

H.test("flavor mismatch is warned about", function()
    local env = boot({ interface = 120105, tocFlavor = "Forever" })
    H.ok(Mock.chatContains(env, "Warning: this client reports flavor Retail, but the Forever file was loaded"))
end)

H.test("unknown client: warns and verify still works", function()
    local env = boot({ interface = 11509 })
    H.ok(Mock.chatContains(env, "not one the ledger recognises (interface 11509)"))
    Mock.slash(env, "verify")
    H.ok(env.FellowshipLedgerDB.verify.text:find("FAIL x:build.interface", 1, true))
end)

H.test("fallback TOC only prints the unsupported message", function()
    local env = Mock.new({ interface = 11509 })
    Mock.loadToc(H, env, "FellowshipLedger.toc")
    Mock.fire(env, "PLAYER_LOGIN")
    H.ok(Mock.chatContains(env, "does not support this game client"))
    H.eq(env.SlashCmdList.FELLOWSHIPLEDGER, nil, "no commands on the fallback")
end)
