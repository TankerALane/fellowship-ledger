-- Debug/VerifyChecks.lua
-- PURE: data only, must not touch WoW globals at load time.
--
-- The list of every WoW API, event and value the ledger plans to use but has not
-- confirmed on both clients. /fl verify runs these; docs/API-VERIFICATION.md is
-- generated from this file (tools/gen_verify_doc.py), and a unit test fails if the
-- two drift apart.
--
-- Keep ONE entry per line in this exact shape so the doc generator can read it:
--   { id = "...", kind = "...", area = "...", why = "..." [, expect = "..."] [, probe = false] [, noargs = true] [, test = "..."] },
--
-- kind:
--   api     id is a dotted global path; passes if it resolves to `expect` (default "function").
--   event   id is "ev:EVENT_NAME"; passes if the client knows the event. That proves the
--           event EXISTS, not that it fires with the arguments we expect - the probe
--           (/fl probe on) records that. probe = false skips noisy events; noargs = true
--           counts the event without storing its arguments (used for comms and anything
--           that could contain other people's text).
--   custom  id is "x:name"; a function in Debug/Verify.lua inspects a value. `test` is the
--           matching one-line command for running it by hand.
--   manual  id is "m:name"; only Austin can check it by looking. `test` says how.

local _, ns = ...

ns.VerifyChecks = {
    -- Build and TOC
    { id = "x:build.interface", kind = "custom", area = "Build", why = "TOC interface number (expect 16001 Forever, 120105 retail)", test = "/dump select(4, GetBuildInfo())" },
    { id = "x:build.version", kind = "custom", area = "Build", why = "client version and build number", test = "/dump GetBuildInfo()" },
    { id = "x:build.tocflavor", kind = "custom", area = "Build", why = "the client loaded the flavor TOC that matches its interface number", test = "/dump C_AddOns.GetAddOnMetadata(\"FellowshipLedger\", \"X-Flavor\")" },
    { id = "x:build.projectid", kind = "custom", area = "Build", why = "WOW_PROJECT_ID value, to tell flavors apart in friend info", test = "/dump WOW_PROJECT_ID, WOW_PROJECT_MAINLINE" },
    { id = "GetBuildInfo", kind = "api", area = "Build", why = "read client version and interface number" },
    { id = "C_AddOns.GetAddOnMetadata", kind = "api", area = "Build", why = "read our TOC fields (version, flavor)" },
    { id = "C_AddOns.IsAddOnLoaded", kind = "api", area = "Build", why = "detect Questie" },
    { id = "C_EventUtils.IsEventValid", kind = "api", area = "Build", why = "how /fl verify checks events; if missing it falls back to trying RegisterEvent" },
    { id = "x:addon.questie", kind = "custom", area = "Build", why = "is Questie loaded and which version", test = "/dump C_AddOns.IsAddOnLoaded(\"Questie\")" },
    { id = "m:toc.icon", kind = "manual", area = "Build", why = "IconTexture path format works", test = "AddOns list (character select or Esc > AddOns): the compass icon shows next to Fellowship Ledger" },
    { id = "m:toc.suffix", kind = "manual", area = "Build", why = "client picks the _Forever / _Mainline TOC, not the fallback", test = "AddOns list title reads 'Fellowship Ledger' with no red '(unsupported client)'" },
    { id = "m:slash", kind = "manual", area = "Build", why = "/fl is not taken by another addon", test = "type /fl - our command list appears" },

    -- Saved variables
    { id = "x:sv.persist", kind = "custom", area = "SavedVariables", why = "SavedVariables survive /reload and relog (reported Forever bug)", test = "/dump FellowshipLedgerDB.dev.persistProbe" },
    { id = "x:sv.backup", kind = "custom", area = "SavedVariables", why = "the second saved variable (backup) persists too", test = "/dump FellowshipLedgerBackupDB.persistProbe" },

    -- Core character info
    { id = "UnitName", kind = "api", area = "Character", why = "own character name" },
    { id = "UnitFullName", kind = "api", area = "Character", why = "own name and realm" },
    { id = "GetRealmName", kind = "api", area = "Character", why = "realm for Name-Realm key" },
    { id = "GetNormalizedRealmName", kind = "api", area = "Character", why = "realm without spaces, for whisper targets" },
    { id = "UnitClass", kind = "api", area = "Character", why = "class of self and party members" },
    { id = "UnitRace", kind = "api", area = "Character", why = "race" },
    { id = "UnitFactionGroup", kind = "api", area = "Character", why = "faction" },
    { id = "UnitLevel", kind = "api", area = "Character", why = "level" },
    { id = "UnitXP", kind = "api", area = "Character", why = "current XP" },
    { id = "UnitXPMax", kind = "api", area = "Character", why = "XP to next level" },
    { id = "GetXPExhaustion", kind = "api", area = "Character", why = "rested XP (context for XP per hour)" },
    { id = "GetMoney", kind = "api", area = "Character", why = "gold tracking" },
    { id = "GetLocale", kind = "api", area = "Character", why = "pick locale strings" },
    { id = "IsTrialAccount", kind = "api", area = "Character", why = "trial accounts cannot send addon messages" },
    { id = "IsVeteranTrialAccount", kind = "api", area = "Character", why = "same, for lapsed accounts" },
    { id = "x:secret.ownvalues", kind = "custom", area = "Character", why = "own level, XP and money are readable plain numbers (not secret)", test = "/dump UnitLevel(\"player\"), UnitXP(\"player\"), GetMoney()" },

    -- Secret values (Midnight rules)
    { id = "issecretvalue", kind = "api", area = "Secret values", why = "test a value before reading it" },
    { id = "canaccessvalue", kind = "api", area = "Secret values", why = "alternative secret check" },
    { id = "issecrettable", kind = "api", area = "Secret values", why = "secret check for tables" },
    { id = "canaccesssecrets", kind = "api", area = "Secret values", why = "whether the current context may read secrets" },

    -- Time and timers
    { id = "C_Timer.After", kind = "api", area = "Time", why = "delayed work, retries" },
    { id = "C_Timer.NewTicker", kind = "api", area = "Time", why = "10-minute backup, sync timer, idle check" },
    { id = "GetServerTime", kind = "api", area = "Time", why = "server epoch time" },
    { id = "GetTime", kind = "api", area = "Time", why = "precise elapsed time for active-time math" },
    { id = "RequestTimePlayed", kind = "api", area = "Time", why = "time played per session" },
    { id = "ev:TIME_PLAYED_MSG", kind = "event", area = "Time", why = "answer to RequestTimePlayed" },

    -- Activity (idle detection for active time)
    { id = "UnitIsAFK", kind = "api", area = "Activity", why = "AFK flag ends active time" },
    { id = "GetUnitSpeed", kind = "api", area = "Activity", why = "is the player moving" },
    { id = "InCombatLockdown", kind = "api", area = "Activity", why = "never send during combat" },
    { id = "UnitAffectingCombat", kind = "api", area = "Activity", why = "own combat state" },
    { id = "ev:PLAYER_FLAGS_CHANGED", kind = "event", area = "Activity", why = "AFK on/off" },
    { id = "ev:PLAYER_STARTED_MOVING", kind = "event", area = "Activity", why = "activity signal" },
    { id = "ev:PLAYER_STOPPED_MOVING", kind = "event", area = "Activity", why = "activity signal" },
    { id = "ev:PLAYER_REGEN_DISABLED", kind = "event", area = "Activity", why = "entered combat: pause sending" },
    { id = "ev:PLAYER_REGEN_ENABLED", kind = "event", area = "Activity", why = "left combat: resume sending" },
    { id = "ev:UNIT_SPELLCAST_SUCCEEDED", kind = "event", area = "Activity", why = "activity signal (own casts only)", probe = false },

    -- Session lifecycle
    { id = "ev:ADDON_LOADED", kind = "event", area = "Session", why = "saved variables ready" },
    { id = "ev:PLAYER_LOGIN", kind = "event", area = "Session", why = "session start" },
    { id = "ev:PLAYER_ENTERING_WORLD", kind = "event", area = "Session", why = "login vs reload flags, instance changes" },
    { id = "ev:PLAYER_LOGOUT", kind = "event", area = "Session", why = "session end, final backup" },
    { id = "ev:PLAYER_LEAVING_WORLD", kind = "event", area = "Session", why = "loading screens" },

    -- Levels
    { id = "ev:PLAYER_LEVEL_UP", kind = "event", area = "Levels", why = "level gained (args: level, ...)" },
    { id = "ev:PLAYER_XP_UPDATE", kind = "event", area = "Levels", why = "XP per hour" },
    { id = "ev:UNIT_LEVEL", kind = "event", area = "Levels", why = "party member level-ups" },

    -- Zones
    { id = "C_Map.GetBestMapForUnit", kind = "api", area = "Zones", why = "zone where a level happened" },
    { id = "C_Map.GetMapInfo", kind = "api", area = "Zones", why = "zone name from map ID" },
    { id = "GetZoneText", kind = "api", area = "Zones", why = "zone name fallback" },
    { id = "GetRealZoneText", kind = "api", area = "Zones", why = "zone name inside instances" },
    { id = "GetSubZoneText", kind = "api", area = "Zones", why = "subzone name" },
    { id = "C_MapExplorationInfo.GetExploredAreaIDsAtPosition", kind = "api", area = "Zones", why = "zones discovered" },
    { id = "GetGameMessageInfo", kind = "api", area = "Zones", why = "name of a UI info message type (ERR_ZONE_EXPLORED = discovered an area)" },
    { id = "ERR_ZONE_EXPLORED", kind = "api", area = "Zones", why = "client's own 'Discovered: %s' format, to recognise discoveries in any language", expect = "string" },
    { id = "ERR_ZONE_EXPLORED_XP", kind = "api", area = "Zones", why = "same, for discoveries that give experience", expect = "string" },
    { id = "ev:ZONE_CHANGED", kind = "event", area = "Zones", why = "subzone change" },
    { id = "ev:ZONE_CHANGED_NEW_AREA", kind = "event", area = "Zones", why = "zone change" },
    { id = "ev:UI_INFO_MESSAGE", kind = "event", area = "Zones", why = "possible signal for 'discovered' and 'flight path learned'" },
    { id = "x:map.current", kind = "custom", area = "Zones", why = "current map ID and name are readable", test = "/dump C_Map.GetBestMapForUnit(\"player\")" },

    -- Quests
    { id = "C_QuestLog.GetNumQuestLogEntries", kind = "api", area = "Quests", why = "walk the quest log" },
    { id = "C_QuestLog.GetInfo", kind = "api", area = "Quests", why = "quest log entry (questID, title, isHeader)" },
    { id = "C_QuestLog.GetTitleForQuestID", kind = "api", area = "Quests", why = "quest title for the turn-in log" },
    { id = "C_QuestLog.IsQuestFlaggedCompleted", kind = "api", area = "Quests", why = "is a chain step done" },
    { id = "C_QuestLine.GetQuestLineInfo", kind = "api", area = "Quests", why = "quest chain for a quest (game data)" },
    { id = "C_QuestLine.GetQuestLineQuests", kind = "api", area = "Quests", why = "all quests in a chain" },
    { id = "C_QuestLine.GetAvailableQuestLines", kind = "api", area = "Quests", why = "chains available on a map" },
    { id = "C_QuestLine.RequestQuestLinesForMap", kind = "api", area = "Quests", why = "load chain data for a map" },
    { id = "x:quest.questline", kind = "custom", area = "Quests", why = "does game data return a chain for quests in your log", test = "/dump C_QuestLine.GetQuestLineInfo(<questID>)" },
    { id = "ev:QUEST_ACCEPTED", kind = "event", area = "Quests", why = "quest accepted" },
    { id = "ev:QUEST_TURNED_IN", kind = "event", area = "Quests", why = "turn-in (args: questID, xp, money)" },
    { id = "ev:QUEST_REMOVED", kind = "event", area = "Quests", why = "quest left the log" },
    { id = "ev:QUEST_LOG_UPDATE", kind = "event", area = "Quests", why = "quest log changed" },
    { id = "ev:QUEST_COMPLETE", kind = "event", area = "Quests", why = "reward frame open (money from quests)" },

    -- Dungeons
    { id = "IsInInstance", kind = "api", area = "Dungeons", why = "entered a dungeon" },
    { id = "GetInstanceInfo", kind = "api", area = "Dungeons", why = "dungeon name, type, difficulty, instance ID" },
    { id = "GetDifficultyInfo", kind = "api", area = "Dungeons", why = "difficulty name" },
    { id = "IsInGroup", kind = "api", area = "Dungeons", why = "group make-up" },
    { id = "UnitIsPlayer", kind = "api", area = "Dungeons", why = "tell real players from follower-dungeon companions" },
    { id = "GetNumGroupMembers", kind = "api", area = "Dungeons", why = "group make-up" },
    { id = "UnitGroupRolesAssigned", kind = "api", area = "Dungeons", why = "party member role" },
    { id = "EJ_GetInstanceForMap", kind = "api", area = "Dungeons", why = "find a dungeon's journal entry (to know the last boss)" },
    { id = "EJ_SelectInstance", kind = "api", area = "Dungeons", why = "select journal instance before listing bosses" },
    { id = "EJ_GetEncounterInfoByIndex", kind = "api", area = "Dungeons", why = "list bosses in order (last one = completion)" },
    { id = "x:dungeon.instance", kind = "custom", area = "Dungeons", why = "GetInstanceInfo returns readable values here", test = "/dump GetInstanceInfo()" },
    { id = "ev:ENCOUNTER_START", kind = "event", area = "Dungeons", why = "boss pull: pause sending" },
    { id = "ev:ENCOUNTER_END", kind = "event", area = "Dungeons", why = "boss kill (args: encounterID, name, difficulty, size, success)" },
    { id = "ev:BOSS_KILL", kind = "event", area = "Dungeons", why = "boss kill alternative" },
    { id = "ev:LFG_COMPLETION_REWARD", kind = "event", area = "Dungeons", why = "finder dungeon completed" },
    { id = "ev:SCENARIO_COMPLETED", kind = "event", area = "Dungeons", why = "scenario-style completion" },
    { id = "ev:UPDATE_INSTANCE_INFO", kind = "event", area = "Dungeons", why = "instance lockout info" },
    { id = "ev:GROUP_ROSTER_UPDATE", kind = "event", area = "Dungeons", why = "party changed" },

    -- Professions
    { id = "GetProfessions", kind = "api", area = "Professions", why = "list professions (retail style)" },
    { id = "GetProfessionInfo", kind = "api", area = "Professions", why = "rank and max rank" },
    { id = "GetNumSkillLines", kind = "api", area = "Professions", why = "skill list (classic style fallback)" },
    { id = "GetSkillLineInfo", kind = "api", area = "Professions", why = "skill rank (classic style fallback)" },
    { id = "C_TradeSkillUI.GetBaseProfessionInfo", kind = "api", area = "Professions", why = "open profession info" },
    { id = "x:prof.list", kind = "custom", area = "Professions", why = "professions and ranks are readable", test = "/dump GetProfessions()" },
    { id = "ev:SKILL_LINES_CHANGED", kind = "event", area = "Professions", why = "skill-up" },
    { id = "ev:TRADE_SKILL_SHOW", kind = "event", area = "Professions", why = "profession window opened" },
    { id = "ev:NEW_RECIPE_LEARNED", kind = "event", area = "Professions", why = "recipe learned" },

    -- Gold sources (by context, never by reading chat)
    { id = "ev:PLAYER_MONEY", kind = "event", area = "Gold", why = "money changed" },
    { id = "ev:MERCHANT_SHOW", kind = "event", area = "Gold", why = "vendor open: money changes count as vendor" },
    { id = "ev:MERCHANT_CLOSED", kind = "event", area = "Gold", why = "vendor closed" },
    { id = "ev:MAIL_SHOW", kind = "event", area = "Gold", why = "mailbox open: money changes count as mail" },
    { id = "ev:MAIL_CLOSED", kind = "event", area = "Gold", why = "mailbox closed" },
    { id = "ev:AUCTION_HOUSE_SHOW", kind = "event", area = "Gold", why = "auction house open" },
    { id = "ev:AUCTION_HOUSE_CLOSED", kind = "event", area = "Gold", why = "auction house closed" },
    { id = "ev:LOOT_READY", kind = "event", area = "Gold", why = "loot window: money changes count as loot" },
    { id = "ev:LOOT_OPENED", kind = "event", area = "Gold", why = "loot window opened" },
    { id = "ev:LOOT_CLOSED", kind = "event", area = "Gold", why = "loot window closed" },

    -- Extras: deaths
    { id = "ev:PLAYER_DEAD", kind = "event", area = "Deaths", why = "you died" },
    { id = "ev:PLAYER_ALIVE", kind = "event", area = "Deaths", why = "released / resurrected" },
    { id = "ev:PLAYER_UNGHOST", kind = "event", area = "Deaths", why = "back from ghost" },
    { id = "C_DeathRecap.GetRecapEvents", kind = "api", area = "Deaths", why = "what killed you (may be secret)" },
    { id = "C_DeathRecap.HasRecapEvents", kind = "api", area = "Deaths", why = "is a death recap available" },
    { id = "GetDeathRecapLink", kind = "api", area = "Deaths", why = "death recap fallback" },

    -- Extras: reputation
    { id = "C_Reputation.GetNumFactions", kind = "api", area = "Reputation", why = "walk factions" },
    { id = "C_Reputation.GetFactionDataByIndex", kind = "api", area = "Reputation", why = "faction standing (retail style)" },
    { id = "C_Reputation.GetFactionDataByID", kind = "api", area = "Reputation", why = "faction standing by ID" },
    { id = "GetNumFactions", kind = "api", area = "Reputation", why = "classic style fallback" },
    { id = "GetFactionInfo", kind = "api", area = "Reputation", why = "classic style fallback" },
    { id = "x:rep.fields", kind = "custom", area = "Reputation", why = "FactionData field names (factionID, currentStanding, isHeader) used to diff standings", test = "/dump C_Reputation.GetFactionDataByIndex(2)" },
    { id = "ev:UPDATE_FACTION", kind = "event", area = "Reputation", why = "reputation changed (diff standings)" },

    -- Extras: achievements, flight paths, kills, items
    { id = "GetAchievementInfo", kind = "api", area = "Achievements", why = "achievement name" },
    { id = "ev:ACHIEVEMENT_EARNED", kind = "event", area = "Achievements", why = "achievement earned" },
    { id = "C_TaxiMap.GetAllTaxiNodes", kind = "api", area = "Flight paths", why = "known flight paths" },
    { id = "NumTaxiNodes", kind = "api", area = "Flight paths", why = "flight map fallback" },
    { id = "TaxiNodeName", kind = "api", area = "Flight paths", why = "flight map fallback" },
    { id = "GetTaxiMapID", kind = "api", area = "Flight paths", why = "map ID of the open flight map" },
    { id = "Enum.FlightPathState", kind = "api", area = "Flight paths", why = "which taxi nodes are known (Unreachable = unknown)", expect = "table" },
    { id = "ev:TAXIMAP_OPENED", kind = "event", area = "Flight paths", why = "flight map opened (diff known nodes)" },
    { id = "UnitGUID", kind = "api", area = "Kills", why = "compare PARTY_KILL attacker/target with you and your target (equality only)" },
    { id = "UnitExists", kind = "api", area = "Kills", why = "target exists" },
    { id = "UnitIsDead", kind = "api", area = "Kills", why = "target died (no combat log allowed)" },
    { id = "UnitClassification", kind = "api", area = "Kills", why = "rare / elite kills" },
    { id = "UnitCreatureType", kind = "api", area = "Kills", why = "kills by creature type" },
    { id = "ev:PLAYER_TARGET_CHANGED", kind = "event", area = "Kills", why = "watch the target for kills" },
    { id = "ev:PARTY_KILL", kind = "event", area = "Kills", why = "kill credit event, if it still exists" },
    { id = "C_Item.GetItemInfo", kind = "api", area = "Items", why = "item quality for notable drops" },
    { id = "GetItemInfo", kind = "api", area = "Items", why = "fallback (reported missing on Forever)" },
    { id = "C_Item.GetItemQualityByID", kind = "api", area = "Items", why = "item quality" },
    { id = "GetItemStats", kind = "api", area = "Items", why = "reported missing on Forever; not planned, listed to confirm" },
    { id = "C_Spell.GetSpellInfo", kind = "api", area = "Items", why = "spell names" },
    { id = "GetSpellInfo", kind = "api", area = "Items", why = "fallback (reported missing on Forever)" },
    { id = "ev:ITEM_PUSH", kind = "event", area = "Items", why = "item went into your bags" },
    { id = "ev:BAG_UPDATE_DELAYED", kind = "event", area = "Items", why = "bags settled (diff for new items)" },

    -- Comms: Battle.net
    { id = "C_BattleNet.SendGameData", kind = "api", area = "Battle.net friends", why = "send to Battle.net friends" },
    { id = "ev:BN_CHAT_MSG_ADDON", kind = "event", area = "Battle.net friends", why = "receive from Battle.net friends", noargs = true },
    { id = "x:comms.enum", kind = "custom", area = "Battle.net friends", why = "Enum.SendAddonMessageResult has the result names we handle", test = "/dump Enum.SendAddonMessageResult" },
    { id = "BNGetInfo", kind = "api", area = "Battle.net friends", why = "own BattleTag (for the block list and grouping)" },
    { id = "BNGetNumFriends", kind = "api", area = "Battle.net friends", why = "count Battle.net friends" },
    { id = "C_BattleNet.GetFriendAccountInfo", kind = "api", area = "Battle.net friends", why = "friend account (BattleTag, online)" },
    { id = "C_BattleNet.GetFriendNumGameAccounts", kind = "api", area = "Battle.net friends", why = "characters a friend is logged in on" },
    { id = "C_BattleNet.GetFriendGameAccountInfo", kind = "api", area = "Battle.net friends", why = "character, realm, client, gameAccountID" },
    { id = "C_BattleNet.GetGameAccountInfoByID", kind = "api", area = "Battle.net friends", why = "look up the sender of a message" },
    { id = "C_BattleNet.GetAccountInfoByID", kind = "api", area = "Battle.net friends", why = "look up a friend account" },
    { id = "x:friends.bnfields", kind = "custom", area = "Battle.net friends", why = "field names on friend game-account info, and which flavor values online friends report", test = "/dump C_BattleNet.GetFriendAccountInfo(1).gameAccountInfo" },
    { id = "ev:BN_FRIEND_ACCOUNT_ONLINE", kind = "event", area = "Battle.net friends", why = "friend came online: sync" },
    { id = "ev:BN_FRIEND_ACCOUNT_OFFLINE", kind = "event", area = "Battle.net friends", why = "friend went offline" },
    { id = "ev:BN_FRIEND_INFO_CHANGED", kind = "event", area = "Battle.net friends", why = "friend switched character or game" },

    -- Comms: character friends
    { id = "WOW_PROJECT_ID", kind = "api", area = "Character friends", why = "our project ID, compared with friends' wowProjectID so only same-flavor friends are messaged", expect = "number" },
    { id = "BNET_CLIENT_WOW", kind = "api", area = "Character friends", why = "the clientProgram value of a friend playing WoW", expect = "string" },
    { id = "LE_PARTY_CATEGORY_INSTANCE", kind = "api", area = "Character friends", why = "tell finder groups (INSTANCE_CHAT) from home parties for the dungeon-name note", expect = "number" },
    { id = "m:commtest", kind = "manual", area = "Character friends", why = "addon whispers to yourself arrive; shows real size limits, result codes and CHAT_MSG_ADDON argument types", test = "/fl commtest, then paste the report" },
    { id = "m:sync", kind = "manual", area = "Battle.net friends", why = "a friend who runs the ledger on the same client appears on the Friends tab after Sync now, with their data; nothing crosses Forever/retail", test = "both run /fl sync; check Friends tab and /fl comms on both sides" },
    { id = "C_ChatInfo.RegisterAddonMessagePrefix", kind = "api", area = "Character friends", why = "register FLDGF / FLDGR" },
    { id = "C_ChatInfo.IsAddonMessagePrefixRegistered", kind = "api", area = "Character friends", why = "confirm registration" },
    { id = "C_ChatInfo.SendAddonMessage", kind = "api", area = "Character friends", why = "whisper addon messages to character friends" },
    { id = "C_ChatInfo.InChatMessagingLockdown", kind = "api", area = "Character friends", why = "lockdown check before sending (Midnight)" },
    { id = "x:comms.prefix", kind = "custom", area = "Character friends", why = "registering our prefix succeeds", test = "/dump C_ChatInfo.RegisterAddonMessagePrefix(\"FLDGF\")" },
    { id = "ev:CHAT_MSG_ADDON", kind = "event", area = "Character friends", why = "receive whispered addon messages", noargs = true },
    { id = "C_FriendList.GetNumFriends", kind = "api", area = "Character friends", why = "count character friends" },
    { id = "C_FriendList.GetFriendInfoByIndex", kind = "api", area = "Character friends", why = "character friend name, online, class" },
    { id = "C_FriendList.ShowFriends", kind = "api", area = "Character friends", why = "refresh the friend list" },
    { id = "x:friends.charfields", kind = "custom", area = "Character friends", why = "field names on character friend info", test = "/dump C_FriendList.GetFriendInfoByIndex(1)" },
    { id = "ev:FRIENDLIST_UPDATE", kind = "event", area = "Character friends", why = "character friend list changed" },

    -- Restrictions
    { id = "ev:ADDON_ACTION_FORBIDDEN", kind = "event", area = "Restrictions", why = "tells us if we hit a blocked action" },

    -- UI
    { id = "CreateFrame", kind = "api", area = "UI", why = "all UI" },
    { id = "BackdropTemplateMixin", kind = "api", area = "UI", why = "window borders", expect = "table" },
    { id = "UISpecialFrames", kind = "api", area = "UI", why = "Escape closes the window", expect = "table" },
    { id = "Minimap", kind = "api", area = "UI", why = "minimap button parent", expect = "table" },
    { id = "GetCursorPosition", kind = "api", area = "UI", why = "drag the minimap button" },
    { id = "Settings.RegisterCanvasLayoutCategory", kind = "api", area = "UI", why = "Options panel entry" },
    { id = "Settings.RegisterAddOnCategory", kind = "api", area = "UI", why = "Options panel entry" },
    { id = "Settings.OpenToCategory", kind = "api", area = "UI", why = "open our Options page" },
    { id = "AddonCompartmentFrame", kind = "api", area = "UI", why = "addon compartment menu entry", expect = "table" },
    { id = "MenuUtil.CreateContextMenu", kind = "api", area = "UI", why = "right-click menus" },
    { id = "CreateColor", kind = "api", area = "UI", why = "colors" },
    { id = "PlaySound", kind = "api", area = "UI", why = "toast sound" },
    { id = "SOUNDKIT", kind = "api", area = "UI", why = "sound IDs", expect = "table" },
    { id = "x:ui.frame", kind = "custom", area = "UI", why = "frame and texture methods the window uses (SetResizeBounds or SetMinResize, StartSizing, SetShown, SetColorTexture)", test = "/dump CreateFrame(\"Frame\").SetResizeBounds" },
    { id = "GameTooltip", kind = "api", area = "UI", why = "hover tooltips on graphs and the minimap button", expect = "table" },
    { id = "x:ui.compartment", kind = "custom", area = "UI", why = "AddonCompartmentFrame:RegisterAddon exists (menu entry by the minimap)", test = "/dump AddonCompartmentFrame.RegisterAddon" },
    { id = "x:questie.db", kind = "custom", area = "UI", why = "Questie's internal QuestieDB.QueryQuestSingle is reachable (quest-chain fallback)", test = "/dump QuestieLoader:ImportModule(\"QuestieDB\").QueryQuestSingle" },
    { id = "m:minimap", kind = "manual", area = "UI", why = "minimap button shows the icon, left click toggles, right click opens Settings, drag moves and the spot is remembered", test = "look at the minimap; click, right-click, drag, /reload" },
    { id = "m:options", kind = "manual", area = "UI", why = "Options > AddOns lists Fellowship Ledger and its button opens Settings", test = "Esc > Options > AddOns > Fellowship Ledger" },
    { id = "m:fakeviews", kind = "manual", area = "UI", why = "with /fl fake every table and all five graphs draw, tooltips show, both skins and all text sizes look right", test = "/fl fake, visit every tab and chart, switch skin and text size, /fl fake off" },
    { id = "m:copywindow", kind = "manual", area = "UI", why = "the verify report window opens, scrolls, copies and closes with Escape", test = "/fl verify, then Ctrl+A, Ctrl+C, Escape" },
}
