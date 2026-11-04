# API verification

Every WoW API, event and value Fellowship Ledger plans to use, with a way to test it in each client. Nothing here counts as verified until Austin runs it in-game and marks it.

## How to run it

1. Sync the addon (`tools/sync.ps1`) and log in on a character, in Forever and in retail.
2. Optional but useful: type `/fl probe on`, then play for a few minutes. Level up if you can, turn in a quest, open a vendor or mailbox, enter a dungeon. The probe counts which events actually fire and keeps a few argument samples. It never reads chat, and for addon-message events it keeps counts only.
3. Type `/fl verify`. A window opens with the report. Click in it, press Ctrl+A, then Ctrl+C, and paste it to Claude. The report is also saved in `WTF\Account\<ACCOUNT>\SavedVariables\FellowshipLedger.lua` under `verify`.
4. Type `/reload`, then `/fl verify` again. `x:sv.persist` should now show `loads=2`. That is the SavedVariables persistence test.
5. Do the **manual** rows (kind `manual`) by eye and tell Claude the result.

## What "pass" means

- **api**: the global exists and has the expected type. It does not prove the function returns useful data. Custom checks (`x:`) test real values where it matters.
- **event**: the client knows the event name (via `C_EventUtils.IsEventValid`, or by trying `RegisterEvent` if that is missing). It does **not** prove the event fires, or which arguments it carries. The probe section of the report shows that.
- **custom** (`x:`): inspects a real value. These lines show detail in the report. They print field names and counts only, never friend names, BattleTags or chat.
- **manual** (`m:`): only a person can check these.

The Forever and Retail columns below are for Austin's marks: `PASS`, `FAIL`, or a short note. `?` means not yet checked. The table is generated from `FellowshipLedger/Debug/VerifyChecks.lua` by `python tools/gen_verify_doc.py`. Existing marks are kept when it is regenerated. A unit test fails if a check is missing here.

## Evidence gathered without the client (2026-11-04)

These come from addons already installed in Austin's game folders. They are good leads, but not proof:

- Forever build is `1.60.1.70790`, retail is `12.1.5.70783` (from `.build.info`).
- Many installed Forever addons declare `## Interface: 16001`. Several retail addons declare `120105` (some also `120107`).
- AtlasLootClassic and Questie ship `_Forever.toc` files, and Questie also ships `_Camelot.toc`. So the `_Forever` suffix is in real use.
- Questie detects Forever with `interface >= 16000 and interface < 17000`. Fellowship Ledger uses the same range.
- Questie ships a generic `Questie.toc` with `## Interface: 00000` that only prints "unsupported client". Fellowship Ledger copies that pattern for its fallback TOC.

## Open questions (no check can answer these yet)

- **Size and rate limits** of `C_BattleNet.SendGameData` and whisper addon messages. These need a two-client test in Phase 3 (see `docs/PROTOCOL.md`).
- **Kill counting** without the combat log. The candidates are `PARTY_KILL` (may no longer exist) and watching the target with `UnitIsDead`. Creature type and classification of other units may be secret. This is decided after the probe results.
- **Last boss of a dungeon.** The journal (`EJ_*`) order is the candidate. Its availability on Forever is unknown.
- **Chat output at logout.** Whether anything printed during `PLAYER_LOGOUT` is visible. The session summary will be shown at next login instead.

<!-- GENERATED:BEGIN (tools/gen_verify_doc.py) -->


### Build

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `x:build.interface` | custom | TOC interface number (expect 16001 Forever, 120105 retail) | `/dump select(4, GetBuildInfo())` | ? | ? |
| `x:build.version` | custom | client version and build number | `/dump GetBuildInfo()` | ? | ? |
| `x:build.tocflavor` | custom | the client loaded the flavor TOC that matches its interface number | `/dump C_AddOns.GetAddOnMetadata("FellowshipLedger", "X-Flavor")` | ? | ? |
| `x:build.projectid` | custom | WOW_PROJECT_ID value, to tell flavors apart in friend info | `/dump WOW_PROJECT_ID, WOW_PROJECT_MAINLINE` | ? | ? |
| `GetBuildInfo` | api | read client version and interface number | `/dump type(GetBuildInfo)` -> "function" | ? | ? |
| `C_AddOns.GetAddOnMetadata` | api | read our TOC fields (version, flavor) | `/dump type(C_AddOns.GetAddOnMetadata)` -> "function" | ? | ? |
| `C_AddOns.IsAddOnLoaded` | api | detect Questie | `/dump type(C_AddOns.IsAddOnLoaded)` -> "function" | ? | ? |
| `C_EventUtils.IsEventValid` | api | how /fl verify checks events; if missing it falls back to trying RegisterEvent | `/dump type(C_EventUtils.IsEventValid)` -> "function" | ? | ? |
| `x:addon.questie` | custom | is Questie loaded and which version | `/dump C_AddOns.IsAddOnLoaded("Questie")` | ? | ? |
| `m:toc.icon` | manual | IconTexture path format works | AddOns list (character select or Esc > AddOns): the compass icon shows next to Fellowship Ledger | ? | ? |
| `m:toc.suffix` | manual | client picks the _Forever / _Mainline TOC, not the fallback | AddOns list title reads 'Fellowship Ledger' with no red '(unsupported client)' | ? | ? |
| `m:slash` | manual | /fl is not taken by another addon | type /fl - our command list appears | ? | ? |

### SavedVariables

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `x:sv.persist` | custom | SavedVariables survive /reload and relog (reported Forever bug) | `/dump FellowshipLedgerDB.dev.persistProbe` | ? | ? |
| `x:sv.backup` | custom | the second saved variable (backup) persists too | `/dump FellowshipLedgerBackupDB.persistProbe` | ? | ? |

### Character

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitName` | api | own character name | `/dump type(UnitName)` -> "function" | ? | ? |
| `UnitFullName` | api | own name and realm | `/dump type(UnitFullName)` -> "function" | ? | ? |
| `GetRealmName` | api | realm for Name-Realm key | `/dump type(GetRealmName)` -> "function" | ? | ? |
| `GetNormalizedRealmName` | api | realm without spaces, for whisper targets | `/dump type(GetNormalizedRealmName)` -> "function" | ? | ? |
| `UnitClass` | api | class of self and party members | `/dump type(UnitClass)` -> "function" | ? | ? |
| `UnitRace` | api | race | `/dump type(UnitRace)` -> "function" | ? | ? |
| `UnitFactionGroup` | api | faction | `/dump type(UnitFactionGroup)` -> "function" | ? | ? |
| `UnitLevel` | api | level | `/dump type(UnitLevel)` -> "function" | ? | ? |
| `UnitXP` | api | current XP | `/dump type(UnitXP)` -> "function" | ? | ? |
| `UnitXPMax` | api | XP to next level | `/dump type(UnitXPMax)` -> "function" | ? | ? |
| `GetXPExhaustion` | api | rested XP (context for XP per hour) | `/dump type(GetXPExhaustion)` -> "function" | ? | ? |
| `GetMoney` | api | gold tracking | `/dump type(GetMoney)` -> "function" | ? | ? |
| `GetLocale` | api | pick locale strings | `/dump type(GetLocale)` -> "function" | ? | ? |
| `IsTrialAccount` | api | trial accounts cannot send addon messages | `/dump type(IsTrialAccount)` -> "function" | ? | ? |
| `IsVeteranTrialAccount` | api | same, for lapsed accounts | `/dump type(IsVeteranTrialAccount)` -> "function" | ? | ? |
| `x:secret.ownvalues` | custom | own level, XP and money are readable plain numbers (not secret) | `/dump UnitLevel("player"), UnitXP("player"), GetMoney()` | ? | ? |

### Secret values

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `issecretvalue` | api | test a value before reading it | `/dump type(issecretvalue)` -> "function" | ? | ? |
| `canaccessvalue` | api | alternative secret check | `/dump type(canaccessvalue)` -> "function" | ? | ? |
| `issecrettable` | api | secret check for tables | `/dump type(issecrettable)` -> "function" | ? | ? |
| `canaccesssecrets` | api | whether the current context may read secrets | `/dump type(canaccesssecrets)` -> "function" | ? | ? |

### Time

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Timer.After` | api | delayed work, retries | `/dump type(C_Timer.After)` -> "function" | ? | ? |
| `C_Timer.NewTicker` | api | 10-minute backup, sync timer, idle check | `/dump type(C_Timer.NewTicker)` -> "function" | ? | ? |
| `GetServerTime` | api | server epoch time | `/dump type(GetServerTime)` -> "function" | ? | ? |
| `GetTime` | api | precise elapsed time for active-time math | `/dump type(GetTime)` -> "function" | ? | ? |
| `RequestTimePlayed` | api | time played per session | `/dump type(RequestTimePlayed)` -> "function" | ? | ? |
| `ev:TIME_PLAYED_MSG` | event | answer to RequestTimePlayed | `/dump C_EventUtils.IsEventValid("TIME_PLAYED_MSG")` -> true | ? | ? |

### Activity

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitIsAFK` | api | AFK flag ends active time | `/dump type(UnitIsAFK)` -> "function" | ? | ? |
| `GetUnitSpeed` | api | is the player moving | `/dump type(GetUnitSpeed)` -> "function" | ? | ? |
| `InCombatLockdown` | api | never send during combat | `/dump type(InCombatLockdown)` -> "function" | ? | ? |
| `UnitAffectingCombat` | api | own combat state | `/dump type(UnitAffectingCombat)` -> "function" | ? | ? |
| `ev:PLAYER_FLAGS_CHANGED` | event | AFK on/off | `/dump C_EventUtils.IsEventValid("PLAYER_FLAGS_CHANGED")` -> true | ? | ? |
| `ev:PLAYER_STARTED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STARTED_MOVING")` -> true | ? | ? |
| `ev:PLAYER_STOPPED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STOPPED_MOVING")` -> true | ? | ? |
| `ev:PLAYER_REGEN_DISABLED` | event | entered combat: pause sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_DISABLED")` -> true | ? | ? |
| `ev:PLAYER_REGEN_ENABLED` | event | left combat: resume sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_ENABLED")` -> true | ? | ? |
| `ev:UNIT_SPELLCAST_SUCCEEDED` | event | activity signal (own casts only) (not probed: too noisy) | `/dump C_EventUtils.IsEventValid("UNIT_SPELLCAST_SUCCEEDED")` -> true | ? | ? |

### Session

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_LOADED` | event | saved variables ready | `/dump C_EventUtils.IsEventValid("ADDON_LOADED")` -> true | ? | ? |
| `ev:PLAYER_LOGIN` | event | session start | `/dump C_EventUtils.IsEventValid("PLAYER_LOGIN")` -> true | ? | ? |
| `ev:PLAYER_ENTERING_WORLD` | event | login vs reload flags, instance changes | `/dump C_EventUtils.IsEventValid("PLAYER_ENTERING_WORLD")` -> true | ? | ? |
| `ev:PLAYER_LOGOUT` | event | session end, final backup | `/dump C_EventUtils.IsEventValid("PLAYER_LOGOUT")` -> true | ? | ? |
| `ev:PLAYER_LEAVING_WORLD` | event | loading screens | `/dump C_EventUtils.IsEventValid("PLAYER_LEAVING_WORLD")` -> true | ? | ? |

### Levels

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_LEVEL_UP` | event | level gained (args: level, ...) | `/dump C_EventUtils.IsEventValid("PLAYER_LEVEL_UP")` -> true | ? | ? |
| `ev:PLAYER_XP_UPDATE` | event | XP per hour | `/dump C_EventUtils.IsEventValid("PLAYER_XP_UPDATE")` -> true | ? | ? |
| `ev:UNIT_LEVEL` | event | party member level-ups | `/dump C_EventUtils.IsEventValid("UNIT_LEVEL")` -> true | ? | ? |

### Zones

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Map.GetBestMapForUnit` | api | zone where a level happened | `/dump type(C_Map.GetBestMapForUnit)` -> "function" | ? | ? |
| `C_Map.GetMapInfo` | api | zone name from map ID | `/dump type(C_Map.GetMapInfo)` -> "function" | ? | ? |
| `GetZoneText` | api | zone name fallback | `/dump type(GetZoneText)` -> "function" | ? | ? |
| `GetRealZoneText` | api | zone name inside instances | `/dump type(GetRealZoneText)` -> "function" | ? | ? |
| `GetSubZoneText` | api | subzone name | `/dump type(GetSubZoneText)` -> "function" | ? | ? |
| `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` | api | zones discovered | `/dump type(C_MapExplorationInfo.GetExploredAreaIDsAtPosition)` -> "function" | ? | ? |
| `ev:ZONE_CHANGED` | event | subzone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED")` -> true | ? | ? |
| `ev:ZONE_CHANGED_NEW_AREA` | event | zone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED_NEW_AREA")` -> true | ? | ? |
| `ev:UI_INFO_MESSAGE` | event | possible signal for 'discovered' and 'flight path learned' | `/dump C_EventUtils.IsEventValid("UI_INFO_MESSAGE")` -> true | ? | ? |
| `x:map.current` | custom | current map ID and name are readable | `/dump C_Map.GetBestMapForUnit("player")` | ? | ? |

### Quests

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_QuestLog.GetNumQuestLogEntries` | api | walk the quest log | `/dump type(C_QuestLog.GetNumQuestLogEntries)` -> "function" | ? | ? |
| `C_QuestLog.GetInfo` | api | quest log entry (questID, title, isHeader) | `/dump type(C_QuestLog.GetInfo)` -> "function" | ? | ? |
| `C_QuestLog.GetTitleForQuestID` | api | quest title for the turn-in log | `/dump type(C_QuestLog.GetTitleForQuestID)` -> "function" | ? | ? |
| `C_QuestLog.IsQuestFlaggedCompleted` | api | is a chain step done | `/dump type(C_QuestLog.IsQuestFlaggedCompleted)` -> "function" | ? | ? |
| `C_QuestLine.GetQuestLineInfo` | api | quest chain for a quest (game data) | `/dump type(C_QuestLine.GetQuestLineInfo)` -> "function" | ? | ? |
| `C_QuestLine.GetQuestLineQuests` | api | all quests in a chain | `/dump type(C_QuestLine.GetQuestLineQuests)` -> "function" | ? | ? |
| `C_QuestLine.GetAvailableQuestLines` | api | chains available on a map | `/dump type(C_QuestLine.GetAvailableQuestLines)` -> "function" | ? | ? |
| `C_QuestLine.RequestQuestLinesForMap` | api | load chain data for a map | `/dump type(C_QuestLine.RequestQuestLinesForMap)` -> "function" | ? | ? |
| `x:quest.questline` | custom | does game data return a chain for quests in your log | `/dump C_QuestLine.GetQuestLineInfo(<questID>)` | ? | ? |
| `ev:QUEST_ACCEPTED` | event | quest accepted | `/dump C_EventUtils.IsEventValid("QUEST_ACCEPTED")` -> true | ? | ? |
| `ev:QUEST_TURNED_IN` | event | turn-in (args: questID, xp, money) | `/dump C_EventUtils.IsEventValid("QUEST_TURNED_IN")` -> true | ? | ? |
| `ev:QUEST_REMOVED` | event | quest left the log | `/dump C_EventUtils.IsEventValid("QUEST_REMOVED")` -> true | ? | ? |
| `ev:QUEST_LOG_UPDATE` | event | quest log changed | `/dump C_EventUtils.IsEventValid("QUEST_LOG_UPDATE")` -> true | ? | ? |
| `ev:QUEST_COMPLETE` | event | reward frame open (money from quests) | `/dump C_EventUtils.IsEventValid("QUEST_COMPLETE")` -> true | ? | ? |

### Dungeons

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `IsInInstance` | api | entered a dungeon | `/dump type(IsInInstance)` -> "function" | ? | ? |
| `GetInstanceInfo` | api | dungeon name, type, difficulty, instance ID | `/dump type(GetInstanceInfo)` -> "function" | ? | ? |
| `GetDifficultyInfo` | api | difficulty name | `/dump type(GetDifficultyInfo)` -> "function" | ? | ? |
| `IsInGroup` | api | group make-up | `/dump type(IsInGroup)` -> "function" | ? | ? |
| `GetNumGroupMembers` | api | group make-up | `/dump type(GetNumGroupMembers)` -> "function" | ? | ? |
| `UnitGroupRolesAssigned` | api | party member role | `/dump type(UnitGroupRolesAssigned)` -> "function" | ? | ? |
| `EJ_GetInstanceForMap` | api | find a dungeon's journal entry (to know the last boss) | `/dump type(EJ_GetInstanceForMap)` -> "function" | ? | ? |
| `EJ_SelectInstance` | api | select journal instance before listing bosses | `/dump type(EJ_SelectInstance)` -> "function" | ? | ? |
| `EJ_GetEncounterInfoByIndex` | api | list bosses in order (last one = completion) | `/dump type(EJ_GetEncounterInfoByIndex)` -> "function" | ? | ? |
| `x:dungeon.instance` | custom | GetInstanceInfo returns readable values here | `/dump GetInstanceInfo()` | ? | ? |
| `ev:ENCOUNTER_START` | event | boss pull: pause sending | `/dump C_EventUtils.IsEventValid("ENCOUNTER_START")` -> true | ? | ? |
| `ev:ENCOUNTER_END` | event | boss kill (args: encounterID, name, difficulty, size, success) | `/dump C_EventUtils.IsEventValid("ENCOUNTER_END")` -> true | ? | ? |
| `ev:BOSS_KILL` | event | boss kill alternative | `/dump C_EventUtils.IsEventValid("BOSS_KILL")` -> true | ? | ? |
| `ev:LFG_COMPLETION_REWARD` | event | finder dungeon completed | `/dump C_EventUtils.IsEventValid("LFG_COMPLETION_REWARD")` -> true | ? | ? |
| `ev:SCENARIO_COMPLETED` | event | scenario-style completion | `/dump C_EventUtils.IsEventValid("SCENARIO_COMPLETED")` -> true | ? | ? |
| `ev:UPDATE_INSTANCE_INFO` | event | instance lockout info | `/dump C_EventUtils.IsEventValid("UPDATE_INSTANCE_INFO")` -> true | ? | ? |
| `ev:GROUP_ROSTER_UPDATE` | event | party changed | `/dump C_EventUtils.IsEventValid("GROUP_ROSTER_UPDATE")` -> true | ? | ? |

### Professions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetProfessions` | api | list professions (retail style) | `/dump type(GetProfessions)` -> "function" | ? | ? |
| `GetProfessionInfo` | api | rank and max rank | `/dump type(GetProfessionInfo)` -> "function" | ? | ? |
| `GetNumSkillLines` | api | skill list (classic style fallback) | `/dump type(GetNumSkillLines)` -> "function" | ? | ? |
| `GetSkillLineInfo` | api | skill rank (classic style fallback) | `/dump type(GetSkillLineInfo)` -> "function" | ? | ? |
| `C_TradeSkillUI.GetBaseProfessionInfo` | api | open profession info | `/dump type(C_TradeSkillUI.GetBaseProfessionInfo)` -> "function" | ? | ? |
| `x:prof.list` | custom | professions and ranks are readable | `/dump GetProfessions()` | ? | ? |
| `ev:SKILL_LINES_CHANGED` | event | skill-up | `/dump C_EventUtils.IsEventValid("SKILL_LINES_CHANGED")` -> true | ? | ? |
| `ev:TRADE_SKILL_SHOW` | event | profession window opened | `/dump C_EventUtils.IsEventValid("TRADE_SKILL_SHOW")` -> true | ? | ? |
| `ev:NEW_RECIPE_LEARNED` | event | recipe learned | `/dump C_EventUtils.IsEventValid("NEW_RECIPE_LEARNED")` -> true | ? | ? |

### Gold

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_MONEY` | event | money changed | `/dump C_EventUtils.IsEventValid("PLAYER_MONEY")` -> true | ? | ? |
| `ev:MERCHANT_SHOW` | event | vendor open: money changes count as vendor | `/dump C_EventUtils.IsEventValid("MERCHANT_SHOW")` -> true | ? | ? |
| `ev:MERCHANT_CLOSED` | event | vendor closed | `/dump C_EventUtils.IsEventValid("MERCHANT_CLOSED")` -> true | ? | ? |
| `ev:MAIL_SHOW` | event | mailbox open: money changes count as mail | `/dump C_EventUtils.IsEventValid("MAIL_SHOW")` -> true | ? | ? |
| `ev:MAIL_CLOSED` | event | mailbox closed | `/dump C_EventUtils.IsEventValid("MAIL_CLOSED")` -> true | ? | ? |
| `ev:AUCTION_HOUSE_SHOW` | event | auction house open | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_SHOW")` -> true | ? | ? |
| `ev:AUCTION_HOUSE_CLOSED` | event | auction house closed | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_CLOSED")` -> true | ? | ? |
| `ev:LOOT_READY` | event | loot window: money changes count as loot | `/dump C_EventUtils.IsEventValid("LOOT_READY")` -> true | ? | ? |
| `ev:LOOT_OPENED` | event | loot window opened | `/dump C_EventUtils.IsEventValid("LOOT_OPENED")` -> true | ? | ? |
| `ev:LOOT_CLOSED` | event | loot window closed | `/dump C_EventUtils.IsEventValid("LOOT_CLOSED")` -> true | ? | ? |

### Deaths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_DEAD` | event | you died | `/dump C_EventUtils.IsEventValid("PLAYER_DEAD")` -> true | ? | ? |
| `ev:PLAYER_ALIVE` | event | released / resurrected | `/dump C_EventUtils.IsEventValid("PLAYER_ALIVE")` -> true | ? | ? |
| `ev:PLAYER_UNGHOST` | event | back from ghost | `/dump C_EventUtils.IsEventValid("PLAYER_UNGHOST")` -> true | ? | ? |
| `C_DeathRecap.GetRecapEvents` | api | what killed you (may be secret) | `/dump type(C_DeathRecap.GetRecapEvents)` -> "function" | ? | ? |
| `C_DeathRecap.HasRecapEvents` | api | is a death recap available | `/dump type(C_DeathRecap.HasRecapEvents)` -> "function" | ? | ? |
| `GetDeathRecapLink` | api | death recap fallback | `/dump type(GetDeathRecapLink)` -> "function" | ? | ? |

### Reputation

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Reputation.GetNumFactions` | api | walk factions | `/dump type(C_Reputation.GetNumFactions)` -> "function" | ? | ? |
| `C_Reputation.GetFactionDataByIndex` | api | faction standing (retail style) | `/dump type(C_Reputation.GetFactionDataByIndex)` -> "function" | ? | ? |
| `C_Reputation.GetFactionDataByID` | api | faction standing by ID | `/dump type(C_Reputation.GetFactionDataByID)` -> "function" | ? | ? |
| `GetNumFactions` | api | classic style fallback | `/dump type(GetNumFactions)` -> "function" | ? | ? |
| `GetFactionInfo` | api | classic style fallback | `/dump type(GetFactionInfo)` -> "function" | ? | ? |
| `ev:UPDATE_FACTION` | event | reputation changed (diff standings) | `/dump C_EventUtils.IsEventValid("UPDATE_FACTION")` -> true | ? | ? |

### Achievements

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetAchievementInfo` | api | achievement name | `/dump type(GetAchievementInfo)` -> "function" | ? | ? |
| `ev:ACHIEVEMENT_EARNED` | event | achievement earned | `/dump C_EventUtils.IsEventValid("ACHIEVEMENT_EARNED")` -> true | ? | ? |

### Flight paths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_TaxiMap.GetAllTaxiNodes` | api | known flight paths | `/dump type(C_TaxiMap.GetAllTaxiNodes)` -> "function" | ? | ? |
| `NumTaxiNodes` | api | flight map fallback | `/dump type(NumTaxiNodes)` -> "function" | ? | ? |
| `TaxiNodeName` | api | flight map fallback | `/dump type(TaxiNodeName)` -> "function" | ? | ? |
| `ev:TAXIMAP_OPENED` | event | flight map opened (diff known nodes) | `/dump C_EventUtils.IsEventValid("TAXIMAP_OPENED")` -> true | ? | ? |

### Kills

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitExists` | api | target exists | `/dump type(UnitExists)` -> "function" | ? | ? |
| `UnitIsDead` | api | target died (no combat log allowed) | `/dump type(UnitIsDead)` -> "function" | ? | ? |
| `UnitClassification` | api | rare / elite kills | `/dump type(UnitClassification)` -> "function" | ? | ? |
| `UnitCreatureType` | api | kills by creature type | `/dump type(UnitCreatureType)` -> "function" | ? | ? |
| `ev:PLAYER_TARGET_CHANGED` | event | watch the target for kills | `/dump C_EventUtils.IsEventValid("PLAYER_TARGET_CHANGED")` -> true | ? | ? |
| `ev:PARTY_KILL` | event | kill credit event, if it still exists | `/dump C_EventUtils.IsEventValid("PARTY_KILL")` -> true | ? | ? |

### Items

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Item.GetItemInfo` | api | item quality for notable drops | `/dump type(C_Item.GetItemInfo)` -> "function" | ? | ? |
| `GetItemInfo` | api | fallback (reported missing on Forever) | `/dump type(GetItemInfo)` -> "function" | ? | ? |
| `C_Item.GetItemQualityByID` | api | item quality | `/dump type(C_Item.GetItemQualityByID)` -> "function" | ? | ? |
| `GetItemStats` | api | reported missing on Forever; not planned, listed to confirm | `/dump type(GetItemStats)` -> "function" | ? | ? |
| `C_Spell.GetSpellInfo` | api | spell names | `/dump type(C_Spell.GetSpellInfo)` -> "function" | ? | ? |
| `GetSpellInfo` | api | fallback (reported missing on Forever) | `/dump type(GetSpellInfo)` -> "function" | ? | ? |
| `ev:ITEM_PUSH` | event | item went into your bags | `/dump C_EventUtils.IsEventValid("ITEM_PUSH")` -> true | ? | ? |
| `ev:BAG_UPDATE_DELAYED` | event | bags settled (diff for new items) | `/dump C_EventUtils.IsEventValid("BAG_UPDATE_DELAYED")` -> true | ? | ? |

### Battle.net friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_BattleNet.SendGameData` | api | send to Battle.net friends | `/dump type(C_BattleNet.SendGameData)` -> "function" | ? | ? |
| `ev:BN_CHAT_MSG_ADDON` | event | receive from Battle.net friends (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("BN_CHAT_MSG_ADDON")` -> true | ? | ? |
| `x:comms.enum` | custom | Enum.SendAddonMessageResult has the result names we handle | `/dump Enum.SendAddonMessageResult` | ? | ? |
| `BNGetInfo` | api | own BattleTag (for the block list and grouping) | `/dump type(BNGetInfo)` -> "function" | ? | ? |
| `BNGetNumFriends` | api | count Battle.net friends | `/dump type(BNGetNumFriends)` -> "function" | ? | ? |
| `C_BattleNet.GetFriendAccountInfo` | api | friend account (BattleTag, online) | `/dump type(C_BattleNet.GetFriendAccountInfo)` -> "function" | ? | ? |
| `C_BattleNet.GetFriendNumGameAccounts` | api | characters a friend is logged in on | `/dump type(C_BattleNet.GetFriendNumGameAccounts)` -> "function" | ? | ? |
| `C_BattleNet.GetFriendGameAccountInfo` | api | character, realm, client, gameAccountID | `/dump type(C_BattleNet.GetFriendGameAccountInfo)` -> "function" | ? | ? |
| `C_BattleNet.GetGameAccountInfoByID` | api | look up the sender of a message | `/dump type(C_BattleNet.GetGameAccountInfoByID)` -> "function" | ? | ? |
| `C_BattleNet.GetAccountInfoByID` | api | look up a friend account | `/dump type(C_BattleNet.GetAccountInfoByID)` -> "function" | ? | ? |
| `x:friends.bnfields` | custom | field names on friend game-account info, and which flavor values online friends report | `/dump C_BattleNet.GetFriendAccountInfo(1).gameAccountInfo` | ? | ? |
| `ev:BN_FRIEND_ACCOUNT_ONLINE` | event | friend came online: sync | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_ONLINE")` -> true | ? | ? |
| `ev:BN_FRIEND_ACCOUNT_OFFLINE` | event | friend went offline | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_OFFLINE")` -> true | ? | ? |
| `ev:BN_FRIEND_INFO_CHANGED` | event | friend switched character or game | `/dump C_EventUtils.IsEventValid("BN_FRIEND_INFO_CHANGED")` -> true | ? | ? |

### Character friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_ChatInfo.RegisterAddonMessagePrefix` | api | register FLDGF / FLDGR | `/dump type(C_ChatInfo.RegisterAddonMessagePrefix)` -> "function" | ? | ? |
| `C_ChatInfo.IsAddonMessagePrefixRegistered` | api | confirm registration | `/dump type(C_ChatInfo.IsAddonMessagePrefixRegistered)` -> "function" | ? | ? |
| `C_ChatInfo.SendAddonMessage` | api | whisper addon messages to character friends | `/dump type(C_ChatInfo.SendAddonMessage)` -> "function" | ? | ? |
| `C_ChatInfo.InChatMessagingLockdown` | api | lockdown check before sending (Midnight) | `/dump type(C_ChatInfo.InChatMessagingLockdown)` -> "function" | ? | ? |
| `x:comms.prefix` | custom | registering our prefix succeeds | `/dump C_ChatInfo.RegisterAddonMessagePrefix("FLDGF")` | ? | ? |
| `ev:CHAT_MSG_ADDON` | event | receive whispered addon messages (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("CHAT_MSG_ADDON")` -> true | ? | ? |
| `C_FriendList.GetNumFriends` | api | count character friends | `/dump type(C_FriendList.GetNumFriends)` -> "function" | ? | ? |
| `C_FriendList.GetFriendInfoByIndex` | api | character friend name, online, class | `/dump type(C_FriendList.GetFriendInfoByIndex)` -> "function" | ? | ? |
| `C_FriendList.ShowFriends` | api | refresh the friend list | `/dump type(C_FriendList.ShowFriends)` -> "function" | ? | ? |
| `x:friends.charfields` | custom | field names on character friend info | `/dump C_FriendList.GetFriendInfoByIndex(1)` | ? | ? |
| `ev:FRIENDLIST_UPDATE` | event | character friend list changed | `/dump C_EventUtils.IsEventValid("FRIENDLIST_UPDATE")` -> true | ? | ? |

### Restrictions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_ACTION_FORBIDDEN` | event | tells us if we hit a blocked action | `/dump C_EventUtils.IsEventValid("ADDON_ACTION_FORBIDDEN")` -> true | ? | ? |

### UI

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `CreateFrame` | api | all UI | `/dump type(CreateFrame)` -> "function" | ? | ? |
| `BackdropTemplateMixin` | api | window borders | `/dump type(BackdropTemplateMixin)` -> "table" | ? | ? |
| `UISpecialFrames` | api | Escape closes the window | `/dump type(UISpecialFrames)` -> "table" | ? | ? |
| `Minimap` | api | minimap button parent | `/dump type(Minimap)` -> "table" | ? | ? |
| `GetCursorPosition` | api | drag the minimap button | `/dump type(GetCursorPosition)` -> "function" | ? | ? |
| `Settings.RegisterCanvasLayoutCategory` | api | Options panel entry | `/dump type(Settings.RegisterCanvasLayoutCategory)` -> "function" | ? | ? |
| `Settings.RegisterAddOnCategory` | api | Options panel entry | `/dump type(Settings.RegisterAddOnCategory)` -> "function" | ? | ? |
| `Settings.OpenToCategory` | api | open our Options page | `/dump type(Settings.OpenToCategory)` -> "function" | ? | ? |
| `AddonCompartmentFrame` | api | addon compartment menu entry | `/dump type(AddonCompartmentFrame)` -> "table" | ? | ? |
| `MenuUtil.CreateContextMenu` | api | right-click menus | `/dump type(MenuUtil.CreateContextMenu)` -> "function" | ? | ? |
| `CreateColor` | api | colors | `/dump type(CreateColor)` -> "function" | ? | ? |
| `PlaySound` | api | toast sound | `/dump type(PlaySound)` -> "function" | ? | ? |
| `SOUNDKIT` | api | sound IDs | `/dump type(SOUNDKIT)` -> "table" | ? | ? |
| `m:copywindow` | manual | the verify report window opens, scrolls, copies and closes with Escape | `/fl verify, then Ctrl+A, Ctrl+C, Escape` | ? | ? |

<!-- GENERATED:END -->
