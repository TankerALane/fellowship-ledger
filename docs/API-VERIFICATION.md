# API verification

> **FOREVER NOT YET VERIFIED.** Every Forever cell says `pending`. Forever launches 2026-11-04 at 15:00 PST. Until then, the code is built on the **retail** results (2026-11-04, `docs/verify-reports/retail-2026-11-04.txt`), on the assumption that Forever shares retail's client. On Forever, the addon prints a reminder at login until a Forever `/fl verify` report is saved. When it arrives, save it as `docs/verify-reports/forever-<date>.txt` and run `python tools/apply_verify_report.py <file>`. The tool fills the Forever column and lists every check that differs from retail. Fix each difference before marking Forever as verified.

## Retail results (2026-11-04): what they mean for the design

- 169 pass, 7 fail, 0 errors. The failures are all old Classic-style functions (`GetNumSkillLines`, `GetSkillLineInfo`, `GetNumFactions`, `GetFactionInfo`, `GetItemInfo`, `GetItemStats`, `GetSpellInfo`). The code uses the `C_` versions, which passed: `C_Reputation.*`, `C_Item.*`, `C_Spell.*`, `GetProfessions`/`GetProfessionInfo`. If Forever has the Classic ones instead, the Compat layer falls back to them.
- Own level, XP, money and map are plain numbers, not secret values.
- `C_QuestLine.GetQuestLineInfo` returns chains for some quests (3 of 14 checked; one chain had 60 quests). Fields: `questLineID, questLineName, questName, startMapID, x, y, isCampaign, inProgress, ...`.
- `Enum.SendAddonMessageResult` on retail: Success=0, InvalidPrefix=1, InvalidMessage=2, AddonMessageThrottle=3, InvalidChatType=4, NotInGroup=5, TargetRequired=6, InvalidChannel=7, ChannelThrottle=8, GeneralError=9, NotInGuild=10, AddOnMessageLockdown=11, TargetOffline=12. The code always uses the names, never the numbers.
- `WOW_PROJECT_ID` is 1 (MAINLINE) on retail. The constants are CLASSIC=2 and MAINLINE=1. There is no FOREVER constant on retail, so look for one on Forever.
- **Still unconfirmed on retail:**
  - The WoW-specific fields on Battle.net friend game accounts (`characterName`, `realmName`, `wowProjectID`). No friend was in WoW at the time. Re-run `/fl verify` while a friend is in game.
  - Whether events actually fire, and their arguments. The probe was off. Run `/fl probe on`, play a little, then run `/fl verify`.
  - SavedVariables persistence (`loads=1`). Run `/reload`, then `/fl verify`.
  - Character friend fields (no character friends).
  - The four manual checks.
- **Second retail report (11:29, probe on, after a /reload):** saved data **survives /reload** (`x:sv.persist` and `x:sv.backup` both PASS, loads=2). Events confirmed **firing**, with arguments:
  - `PLAYER_LEVEL_UP` (newLevel, ...): the first argument is the new level (14).
  - `PLAYER_XP_UPDATE` ("player").
  - `UNIT_LEVEL` (unit): fires for player, target and pet, so it has to be filtered to party units.
  - `PARTY_KILL` (attackerGUID, targetGUID): plain readable strings on retail, not secret. Kills are counted by comparing the attacker with `UnitGUID("player")` (equality only, never parsing). Forever obfuscates GUIDs, so equality still has to be confirmed there.
  - `ITEM_PUSH` (bagSlot, iconFileID): no item ID or link, so notable drops still need another source (the loot APIs, not yet verified).
  - `LOOT_READY` (autoLoot), `LOOT_OPENED` (autoLoot, isFromItem), `LOOT_CLOSED`, `PLAYER_MONEY` (no arguments), `BAG_UPDATE_DELAYED`.
  - `SKILL_LINES_CHANGED` fired 28 times in a few minutes, so it is throttled.
  - `ZONE_CHANGED`, `PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_*`, `PLAYER_STARTED/STOPPED_MOVING` and `PLAYER_FLAGS_CHANGED` ("player") also fired.
  - Third report (11:30, after another /reload): `PLAYER_ENTERING_WORLD` passes (isInitialLogin=false, isReloadingUi=true) on a reload. `PLAYER_LEAVING_WORLD` and `PLAYER_LOGOUT` **both fire on /reload**, so the logout save also runs then. Persistence still holds (loads=3). `UPDATE_INSTANCE_INFO` fires on load.
  - **Not yet seen firing:** `QUEST_TURNED_IN`, `QUEST_ACCEPTED`, `ZONE_CHANGED_NEW_AREA`, the merchant, mail and auction events, `ENCOUNTER_END`, `PLAYER_DEAD`, `UPDATE_FACTION`, `TAXIMAP_OPENED` and `ACHIEVEMENT_EARNED`. The trackers that use them are built defensively and stay on the in-game checklist.
- **Event arguments** used by the trackers come from retail documentation and memory until the probe confirms them. Every tracker reads state from APIs (for example `UnitLevel`) rather than trusting event arguments wherever it can.

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
| `x:build.interface` | custom | TOC interface number (expect 16001 Forever, 120105 retail) | `/dump select(4, GetBuildInfo())` | pending | PASS |
| `x:build.version` | custom | client version and build number | `/dump GetBuildInfo()` | pending | INFO |
| `x:build.tocflavor` | custom | the client loaded the flavor TOC that matches its interface number | `/dump C_AddOns.GetAddOnMetadata("FellowshipLedger", "X-Flavor")` | pending | PASS |
| `x:build.projectid` | custom | WOW_PROJECT_ID value, to tell flavors apart in friend info | `/dump WOW_PROJECT_ID, WOW_PROJECT_MAINLINE` | pending | INFO |
| `GetBuildInfo` | api | read client version and interface number | `/dump type(GetBuildInfo)` -> "function" | pending | PASS |
| `C_AddOns.GetAddOnMetadata` | api | read our TOC fields (version, flavor) | `/dump type(C_AddOns.GetAddOnMetadata)` -> "function" | pending | PASS |
| `C_AddOns.IsAddOnLoaded` | api | detect Questie | `/dump type(C_AddOns.IsAddOnLoaded)` -> "function" | pending | PASS |
| `C_EventUtils.IsEventValid` | api | how /fl verify checks events; if missing it falls back to trying RegisterEvent | `/dump type(C_EventUtils.IsEventValid)` -> "function" | pending | PASS |
| `x:addon.questie` | custom | is Questie loaded and which version | `/dump C_AddOns.IsAddOnLoaded("Questie")` | pending | INFO |
| `m:toc.icon` | manual | IconTexture path format works | AddOns list (character select or Esc > AddOns): the compass icon shows next to Fellowship Ledger | pending | ? |
| `m:toc.suffix` | manual | client picks the _Forever / _Mainline TOC, not the fallback | AddOns list title reads 'Fellowship Ledger' with no red '(unsupported client)' | pending | ? |
| `m:slash` | manual | /fl is not taken by another addon | type /fl - our command list appears | pending | ? |

### SavedVariables

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `x:sv.persist` | custom | SavedVariables survive /reload and relog (reported Forever bug) | `/dump FellowshipLedgerDB.dev.persistProbe` | pending | PASS |
| `x:sv.backup` | custom | the second saved variable (backup) persists too | `/dump FellowshipLedgerBackupDB.persistProbe` | pending | PASS |

### Character

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitName` | api | own character name | `/dump type(UnitName)` -> "function" | pending | PASS |
| `UnitFullName` | api | own name and realm | `/dump type(UnitFullName)` -> "function" | pending | PASS |
| `GetRealmName` | api | realm for Name-Realm key | `/dump type(GetRealmName)` -> "function" | pending | PASS |
| `GetNormalizedRealmName` | api | realm without spaces, for whisper targets | `/dump type(GetNormalizedRealmName)` -> "function" | pending | PASS |
| `UnitClass` | api | class of self and party members | `/dump type(UnitClass)` -> "function" | pending | PASS |
| `UnitRace` | api | race | `/dump type(UnitRace)` -> "function" | pending | PASS |
| `UnitFactionGroup` | api | faction | `/dump type(UnitFactionGroup)` -> "function" | pending | PASS |
| `UnitLevel` | api | level | `/dump type(UnitLevel)` -> "function" | pending | PASS |
| `UnitXP` | api | current XP | `/dump type(UnitXP)` -> "function" | pending | PASS |
| `UnitXPMax` | api | XP to next level | `/dump type(UnitXPMax)` -> "function" | pending | PASS |
| `GetXPExhaustion` | api | rested XP (context for XP per hour) | `/dump type(GetXPExhaustion)` -> "function" | pending | PASS |
| `GetMoney` | api | gold tracking | `/dump type(GetMoney)` -> "function" | pending | PASS |
| `GetLocale` | api | pick locale strings | `/dump type(GetLocale)` -> "function" | pending | PASS |
| `IsTrialAccount` | api | trial accounts cannot send addon messages | `/dump type(IsTrialAccount)` -> "function" | pending | PASS |
| `IsVeteranTrialAccount` | api | same, for lapsed accounts | `/dump type(IsVeteranTrialAccount)` -> "function" | pending | PASS |
| `x:secret.ownvalues` | custom | own level, XP and money are readable plain numbers (not secret) | `/dump UnitLevel("player"), UnitXP("player"), GetMoney()` | pending | PASS |

### Secret values

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `issecretvalue` | api | test a value before reading it | `/dump type(issecretvalue)` -> "function" | pending | PASS |
| `canaccessvalue` | api | alternative secret check | `/dump type(canaccessvalue)` -> "function" | pending | PASS |
| `issecrettable` | api | secret check for tables | `/dump type(issecrettable)` -> "function" | pending | PASS |
| `canaccesssecrets` | api | whether the current context may read secrets | `/dump type(canaccesssecrets)` -> "function" | pending | PASS |

### Time

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Timer.After` | api | delayed work, retries | `/dump type(C_Timer.After)` -> "function" | pending | PASS |
| `C_Timer.NewTicker` | api | 10-minute backup, sync timer, idle check | `/dump type(C_Timer.NewTicker)` -> "function" | pending | PASS |
| `GetServerTime` | api | server epoch time | `/dump type(GetServerTime)` -> "function" | pending | PASS |
| `GetTime` | api | precise elapsed time for active-time math | `/dump type(GetTime)` -> "function" | pending | PASS |
| `RequestTimePlayed` | api | time played per session | `/dump type(RequestTimePlayed)` -> "function" | pending | PASS |
| `ev:TIME_PLAYED_MSG` | event | answer to RequestTimePlayed | `/dump C_EventUtils.IsEventValid("TIME_PLAYED_MSG")` -> true | pending | PASS |

### Activity

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitIsAFK` | api | AFK flag ends active time | `/dump type(UnitIsAFK)` -> "function" | pending | PASS |
| `GetUnitSpeed` | api | is the player moving | `/dump type(GetUnitSpeed)` -> "function" | pending | PASS |
| `InCombatLockdown` | api | never send during combat | `/dump type(InCombatLockdown)` -> "function" | pending | PASS |
| `UnitAffectingCombat` | api | own combat state | `/dump type(UnitAffectingCombat)` -> "function" | pending | PASS |
| `ev:PLAYER_FLAGS_CHANGED` | event | AFK on/off | `/dump C_EventUtils.IsEventValid("PLAYER_FLAGS_CHANGED")` -> true | pending | PASS |
| `ev:PLAYER_STARTED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STARTED_MOVING")` -> true | pending | PASS |
| `ev:PLAYER_STOPPED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STOPPED_MOVING")` -> true | pending | PASS |
| `ev:PLAYER_REGEN_DISABLED` | event | entered combat: pause sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_DISABLED")` -> true | pending | PASS |
| `ev:PLAYER_REGEN_ENABLED` | event | left combat: resume sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_ENABLED")` -> true | pending | PASS |
| `ev:UNIT_SPELLCAST_SUCCEEDED` | event | activity signal (own casts only) (not probed: too noisy) | `/dump C_EventUtils.IsEventValid("UNIT_SPELLCAST_SUCCEEDED")` -> true | pending | PASS |

### Session

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_LOADED` | event | saved variables ready | `/dump C_EventUtils.IsEventValid("ADDON_LOADED")` -> true | pending | PASS |
| `ev:PLAYER_LOGIN` | event | session start | `/dump C_EventUtils.IsEventValid("PLAYER_LOGIN")` -> true | pending | PASS |
| `ev:PLAYER_ENTERING_WORLD` | event | login vs reload flags, instance changes | `/dump C_EventUtils.IsEventValid("PLAYER_ENTERING_WORLD")` -> true | pending | PASS |
| `ev:PLAYER_LOGOUT` | event | session end, final backup | `/dump C_EventUtils.IsEventValid("PLAYER_LOGOUT")` -> true | pending | PASS |
| `ev:PLAYER_LEAVING_WORLD` | event | loading screens | `/dump C_EventUtils.IsEventValid("PLAYER_LEAVING_WORLD")` -> true | pending | PASS |

### Levels

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_LEVEL_UP` | event | level gained (args: level, ...) | `/dump C_EventUtils.IsEventValid("PLAYER_LEVEL_UP")` -> true | pending | PASS |
| `ev:PLAYER_XP_UPDATE` | event | XP per hour | `/dump C_EventUtils.IsEventValid("PLAYER_XP_UPDATE")` -> true | pending | PASS |
| `ev:UNIT_LEVEL` | event | party member level-ups | `/dump C_EventUtils.IsEventValid("UNIT_LEVEL")` -> true | pending | PASS |

### Zones

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Map.GetBestMapForUnit` | api | zone where a level happened | `/dump type(C_Map.GetBestMapForUnit)` -> "function" | pending | PASS |
| `C_Map.GetMapInfo` | api | zone name from map ID | `/dump type(C_Map.GetMapInfo)` -> "function" | pending | PASS |
| `GetZoneText` | api | zone name fallback | `/dump type(GetZoneText)` -> "function" | pending | PASS |
| `GetRealZoneText` | api | zone name inside instances | `/dump type(GetRealZoneText)` -> "function" | pending | PASS |
| `GetSubZoneText` | api | subzone name | `/dump type(GetSubZoneText)` -> "function" | pending | PASS |
| `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` | api | zones discovered | `/dump type(C_MapExplorationInfo.GetExploredAreaIDsAtPosition)` -> "function" | pending | PASS |
| `ev:ZONE_CHANGED` | event | subzone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED")` -> true | pending | PASS |
| `ev:ZONE_CHANGED_NEW_AREA` | event | zone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED_NEW_AREA")` -> true | pending | PASS |
| `ev:UI_INFO_MESSAGE` | event | possible signal for 'discovered' and 'flight path learned' | `/dump C_EventUtils.IsEventValid("UI_INFO_MESSAGE")` -> true | pending | PASS |
| `x:map.current` | custom | current map ID and name are readable | `/dump C_Map.GetBestMapForUnit("player")` | pending | PASS |

### Quests

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_QuestLog.GetNumQuestLogEntries` | api | walk the quest log | `/dump type(C_QuestLog.GetNumQuestLogEntries)` -> "function" | pending | PASS |
| `C_QuestLog.GetInfo` | api | quest log entry (questID, title, isHeader) | `/dump type(C_QuestLog.GetInfo)` -> "function" | pending | PASS |
| `C_QuestLog.GetTitleForQuestID` | api | quest title for the turn-in log | `/dump type(C_QuestLog.GetTitleForQuestID)` -> "function" | pending | PASS |
| `C_QuestLog.IsQuestFlaggedCompleted` | api | is a chain step done | `/dump type(C_QuestLog.IsQuestFlaggedCompleted)` -> "function" | pending | PASS |
| `C_QuestLine.GetQuestLineInfo` | api | quest chain for a quest (game data) | `/dump type(C_QuestLine.GetQuestLineInfo)` -> "function" | pending | PASS |
| `C_QuestLine.GetQuestLineQuests` | api | all quests in a chain | `/dump type(C_QuestLine.GetQuestLineQuests)` -> "function" | pending | PASS |
| `C_QuestLine.GetAvailableQuestLines` | api | chains available on a map | `/dump type(C_QuestLine.GetAvailableQuestLines)` -> "function" | pending | PASS |
| `C_QuestLine.RequestQuestLinesForMap` | api | load chain data for a map | `/dump type(C_QuestLine.RequestQuestLinesForMap)` -> "function" | pending | PASS |
| `x:quest.questline` | custom | does game data return a chain for quests in your log | `/dump C_QuestLine.GetQuestLineInfo(<questID>)` | pending | INFO |
| `ev:QUEST_ACCEPTED` | event | quest accepted | `/dump C_EventUtils.IsEventValid("QUEST_ACCEPTED")` -> true | pending | PASS |
| `ev:QUEST_TURNED_IN` | event | turn-in (args: questID, xp, money) | `/dump C_EventUtils.IsEventValid("QUEST_TURNED_IN")` -> true | pending | PASS |
| `ev:QUEST_REMOVED` | event | quest left the log | `/dump C_EventUtils.IsEventValid("QUEST_REMOVED")` -> true | pending | PASS |
| `ev:QUEST_LOG_UPDATE` | event | quest log changed | `/dump C_EventUtils.IsEventValid("QUEST_LOG_UPDATE")` -> true | pending | PASS |
| `ev:QUEST_COMPLETE` | event | reward frame open (money from quests) | `/dump C_EventUtils.IsEventValid("QUEST_COMPLETE")` -> true | pending | PASS |

### Dungeons

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `IsInInstance` | api | entered a dungeon | `/dump type(IsInInstance)` -> "function" | pending | PASS |
| `GetInstanceInfo` | api | dungeon name, type, difficulty, instance ID | `/dump type(GetInstanceInfo)` -> "function" | pending | PASS |
| `GetDifficultyInfo` | api | difficulty name | `/dump type(GetDifficultyInfo)` -> "function" | pending | PASS |
| `IsInGroup` | api | group make-up | `/dump type(IsInGroup)` -> "function" | pending | PASS |
| `GetNumGroupMembers` | api | group make-up | `/dump type(GetNumGroupMembers)` -> "function" | pending | PASS |
| `UnitGroupRolesAssigned` | api | party member role | `/dump type(UnitGroupRolesAssigned)` -> "function" | pending | PASS |
| `EJ_GetInstanceForMap` | api | find a dungeon's journal entry (to know the last boss) | `/dump type(EJ_GetInstanceForMap)` -> "function" | pending | PASS |
| `EJ_SelectInstance` | api | select journal instance before listing bosses | `/dump type(EJ_SelectInstance)` -> "function" | pending | PASS |
| `EJ_GetEncounterInfoByIndex` | api | list bosses in order (last one = completion) | `/dump type(EJ_GetEncounterInfoByIndex)` -> "function" | pending | PASS |
| `x:dungeon.instance` | custom | GetInstanceInfo returns readable values here | `/dump GetInstanceInfo()` | pending | INFO |
| `ev:ENCOUNTER_START` | event | boss pull: pause sending | `/dump C_EventUtils.IsEventValid("ENCOUNTER_START")` -> true | pending | PASS |
| `ev:ENCOUNTER_END` | event | boss kill (args: encounterID, name, difficulty, size, success) | `/dump C_EventUtils.IsEventValid("ENCOUNTER_END")` -> true | pending | PASS |
| `ev:BOSS_KILL` | event | boss kill alternative | `/dump C_EventUtils.IsEventValid("BOSS_KILL")` -> true | pending | PASS |
| `ev:LFG_COMPLETION_REWARD` | event | finder dungeon completed | `/dump C_EventUtils.IsEventValid("LFG_COMPLETION_REWARD")` -> true | pending | PASS |
| `ev:SCENARIO_COMPLETED` | event | scenario-style completion | `/dump C_EventUtils.IsEventValid("SCENARIO_COMPLETED")` -> true | pending | PASS |
| `ev:UPDATE_INSTANCE_INFO` | event | instance lockout info | `/dump C_EventUtils.IsEventValid("UPDATE_INSTANCE_INFO")` -> true | pending | PASS |
| `ev:GROUP_ROSTER_UPDATE` | event | party changed | `/dump C_EventUtils.IsEventValid("GROUP_ROSTER_UPDATE")` -> true | pending | PASS |

### Professions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetProfessions` | api | list professions (retail style) | `/dump type(GetProfessions)` -> "function" | pending | PASS |
| `GetProfessionInfo` | api | rank and max rank | `/dump type(GetProfessionInfo)` -> "function" | pending | PASS |
| `GetNumSkillLines` | api | skill list (classic style fallback) | `/dump type(GetNumSkillLines)` -> "function" | pending | FAIL |
| `GetSkillLineInfo` | api | skill rank (classic style fallback) | `/dump type(GetSkillLineInfo)` -> "function" | pending | FAIL |
| `C_TradeSkillUI.GetBaseProfessionInfo` | api | open profession info | `/dump type(C_TradeSkillUI.GetBaseProfessionInfo)` -> "function" | pending | PASS |
| `x:prof.list` | custom | professions and ranks are readable | `/dump GetProfessions()` | pending | INFO |
| `ev:SKILL_LINES_CHANGED` | event | skill-up | `/dump C_EventUtils.IsEventValid("SKILL_LINES_CHANGED")` -> true | pending | PASS |
| `ev:TRADE_SKILL_SHOW` | event | profession window opened | `/dump C_EventUtils.IsEventValid("TRADE_SKILL_SHOW")` -> true | pending | PASS |
| `ev:NEW_RECIPE_LEARNED` | event | recipe learned | `/dump C_EventUtils.IsEventValid("NEW_RECIPE_LEARNED")` -> true | pending | PASS |

### Gold

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_MONEY` | event | money changed | `/dump C_EventUtils.IsEventValid("PLAYER_MONEY")` -> true | pending | PASS |
| `ev:MERCHANT_SHOW` | event | vendor open: money changes count as vendor | `/dump C_EventUtils.IsEventValid("MERCHANT_SHOW")` -> true | pending | PASS |
| `ev:MERCHANT_CLOSED` | event | vendor closed | `/dump C_EventUtils.IsEventValid("MERCHANT_CLOSED")` -> true | pending | PASS |
| `ev:MAIL_SHOW` | event | mailbox open: money changes count as mail | `/dump C_EventUtils.IsEventValid("MAIL_SHOW")` -> true | pending | PASS |
| `ev:MAIL_CLOSED` | event | mailbox closed | `/dump C_EventUtils.IsEventValid("MAIL_CLOSED")` -> true | pending | PASS |
| `ev:AUCTION_HOUSE_SHOW` | event | auction house open | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_SHOW")` -> true | pending | PASS |
| `ev:AUCTION_HOUSE_CLOSED` | event | auction house closed | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_CLOSED")` -> true | pending | PASS |
| `ev:LOOT_READY` | event | loot window: money changes count as loot | `/dump C_EventUtils.IsEventValid("LOOT_READY")` -> true | pending | PASS |
| `ev:LOOT_OPENED` | event | loot window opened | `/dump C_EventUtils.IsEventValid("LOOT_OPENED")` -> true | pending | PASS |
| `ev:LOOT_CLOSED` | event | loot window closed | `/dump C_EventUtils.IsEventValid("LOOT_CLOSED")` -> true | pending | PASS |

### Deaths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_DEAD` | event | you died | `/dump C_EventUtils.IsEventValid("PLAYER_DEAD")` -> true | pending | PASS |
| `ev:PLAYER_ALIVE` | event | released / resurrected | `/dump C_EventUtils.IsEventValid("PLAYER_ALIVE")` -> true | pending | PASS |
| `ev:PLAYER_UNGHOST` | event | back from ghost | `/dump C_EventUtils.IsEventValid("PLAYER_UNGHOST")` -> true | pending | PASS |
| `C_DeathRecap.GetRecapEvents` | api | what killed you (may be secret) | `/dump type(C_DeathRecap.GetRecapEvents)` -> "function" | pending | PASS |
| `C_DeathRecap.HasRecapEvents` | api | is a death recap available | `/dump type(C_DeathRecap.HasRecapEvents)` -> "function" | pending | PASS |
| `GetDeathRecapLink` | api | death recap fallback | `/dump type(GetDeathRecapLink)` -> "function" | pending | PASS |

### Reputation

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Reputation.GetNumFactions` | api | walk factions | `/dump type(C_Reputation.GetNumFactions)` -> "function" | pending | PASS |
| `C_Reputation.GetFactionDataByIndex` | api | faction standing (retail style) | `/dump type(C_Reputation.GetFactionDataByIndex)` -> "function" | pending | PASS |
| `C_Reputation.GetFactionDataByID` | api | faction standing by ID | `/dump type(C_Reputation.GetFactionDataByID)` -> "function" | pending | PASS |
| `GetNumFactions` | api | classic style fallback | `/dump type(GetNumFactions)` -> "function" | pending | FAIL |
| `GetFactionInfo` | api | classic style fallback | `/dump type(GetFactionInfo)` -> "function" | pending | FAIL |
| `x:rep.fields` | custom | FactionData field names (factionID, currentStanding, isHeader) used to diff standings | `/dump C_Reputation.GetFactionDataByIndex(2)` | pending | ? |
| `ev:UPDATE_FACTION` | event | reputation changed (diff standings) | `/dump C_EventUtils.IsEventValid("UPDATE_FACTION")` -> true | pending | PASS |

### Achievements

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetAchievementInfo` | api | achievement name | `/dump type(GetAchievementInfo)` -> "function" | pending | PASS |
| `ev:ACHIEVEMENT_EARNED` | event | achievement earned | `/dump C_EventUtils.IsEventValid("ACHIEVEMENT_EARNED")` -> true | pending | PASS |

### Flight paths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_TaxiMap.GetAllTaxiNodes` | api | known flight paths | `/dump type(C_TaxiMap.GetAllTaxiNodes)` -> "function" | pending | PASS |
| `NumTaxiNodes` | api | flight map fallback | `/dump type(NumTaxiNodes)` -> "function" | pending | PASS |
| `TaxiNodeName` | api | flight map fallback | `/dump type(TaxiNodeName)` -> "function" | pending | PASS |
| `GetTaxiMapID` | api | map ID of the open flight map | `/dump type(GetTaxiMapID)` -> "function" | pending | ? |
| `Enum.FlightPathState` | api | which taxi nodes are known (Unreachable = unknown) | `/dump type(Enum.FlightPathState)` -> "table" | pending | ? |
| `ev:TAXIMAP_OPENED` | event | flight map opened (diff known nodes) | `/dump C_EventUtils.IsEventValid("TAXIMAP_OPENED")` -> true | pending | PASS |

### Kills

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitGUID` | api | compare PARTY_KILL attacker/target with you and your target (equality only) | `/dump type(UnitGUID)` -> "function" | pending | ? |
| `UnitExists` | api | target exists | `/dump type(UnitExists)` -> "function" | pending | PASS |
| `UnitIsDead` | api | target died (no combat log allowed) | `/dump type(UnitIsDead)` -> "function" | pending | PASS |
| `UnitClassification` | api | rare / elite kills | `/dump type(UnitClassification)` -> "function" | pending | PASS |
| `UnitCreatureType` | api | kills by creature type | `/dump type(UnitCreatureType)` -> "function" | pending | PASS |
| `ev:PLAYER_TARGET_CHANGED` | event | watch the target for kills | `/dump C_EventUtils.IsEventValid("PLAYER_TARGET_CHANGED")` -> true | pending | PASS |
| `ev:PARTY_KILL` | event | kill credit event, if it still exists | `/dump C_EventUtils.IsEventValid("PARTY_KILL")` -> true | pending | PASS |

### Items

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Item.GetItemInfo` | api | item quality for notable drops | `/dump type(C_Item.GetItemInfo)` -> "function" | pending | PASS |
| `GetItemInfo` | api | fallback (reported missing on Forever) | `/dump type(GetItemInfo)` -> "function" | pending | FAIL |
| `C_Item.GetItemQualityByID` | api | item quality | `/dump type(C_Item.GetItemQualityByID)` -> "function" | pending | PASS |
| `GetItemStats` | api | reported missing on Forever; not planned, listed to confirm | `/dump type(GetItemStats)` -> "function" | pending | FAIL |
| `C_Spell.GetSpellInfo` | api | spell names | `/dump type(C_Spell.GetSpellInfo)` -> "function" | pending | PASS |
| `GetSpellInfo` | api | fallback (reported missing on Forever) | `/dump type(GetSpellInfo)` -> "function" | pending | FAIL |
| `ev:ITEM_PUSH` | event | item went into your bags | `/dump C_EventUtils.IsEventValid("ITEM_PUSH")` -> true | pending | PASS |
| `ev:BAG_UPDATE_DELAYED` | event | bags settled (diff for new items) | `/dump C_EventUtils.IsEventValid("BAG_UPDATE_DELAYED")` -> true | pending | PASS |

### Battle.net friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_BattleNet.SendGameData` | api | send to Battle.net friends | `/dump type(C_BattleNet.SendGameData)` -> "function" | pending | PASS |
| `ev:BN_CHAT_MSG_ADDON` | event | receive from Battle.net friends (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("BN_CHAT_MSG_ADDON")` -> true | pending | PASS |
| `x:comms.enum` | custom | Enum.SendAddonMessageResult has the result names we handle | `/dump Enum.SendAddonMessageResult` | pending | PASS |
| `BNGetInfo` | api | own BattleTag (for the block list and grouping) | `/dump type(BNGetInfo)` -> "function" | pending | PASS |
| `BNGetNumFriends` | api | count Battle.net friends | `/dump type(BNGetNumFriends)` -> "function" | pending | PASS |
| `C_BattleNet.GetFriendAccountInfo` | api | friend account (BattleTag, online) | `/dump type(C_BattleNet.GetFriendAccountInfo)` -> "function" | pending | PASS |
| `C_BattleNet.GetFriendNumGameAccounts` | api | characters a friend is logged in on | `/dump type(C_BattleNet.GetFriendNumGameAccounts)` -> "function" | pending | PASS |
| `C_BattleNet.GetFriendGameAccountInfo` | api | character, realm, client, gameAccountID | `/dump type(C_BattleNet.GetFriendGameAccountInfo)` -> "function" | pending | PASS |
| `C_BattleNet.GetGameAccountInfoByID` | api | look up the sender of a message | `/dump type(C_BattleNet.GetGameAccountInfoByID)` -> "function" | pending | PASS |
| `C_BattleNet.GetAccountInfoByID` | api | look up a friend account | `/dump type(C_BattleNet.GetAccountInfoByID)` -> "function" | pending | PASS |
| `x:friends.bnfields` | custom | field names on friend game-account info, and which flavor values online friends report | `/dump C_BattleNet.GetFriendAccountInfo(1).gameAccountInfo` | pending | INFO |
| `ev:BN_FRIEND_ACCOUNT_ONLINE` | event | friend came online: sync | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_ONLINE")` -> true | pending | PASS |
| `ev:BN_FRIEND_ACCOUNT_OFFLINE` | event | friend went offline | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_OFFLINE")` -> true | pending | PASS |
| `ev:BN_FRIEND_INFO_CHANGED` | event | friend switched character or game | `/dump C_EventUtils.IsEventValid("BN_FRIEND_INFO_CHANGED")` -> true | pending | PASS |

### Character friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_ChatInfo.RegisterAddonMessagePrefix` | api | register FLDGF / FLDGR | `/dump type(C_ChatInfo.RegisterAddonMessagePrefix)` -> "function" | pending | PASS |
| `C_ChatInfo.IsAddonMessagePrefixRegistered` | api | confirm registration | `/dump type(C_ChatInfo.IsAddonMessagePrefixRegistered)` -> "function" | pending | PASS |
| `C_ChatInfo.SendAddonMessage` | api | whisper addon messages to character friends | `/dump type(C_ChatInfo.SendAddonMessage)` -> "function" | pending | PASS |
| `C_ChatInfo.InChatMessagingLockdown` | api | lockdown check before sending (Midnight) | `/dump type(C_ChatInfo.InChatMessagingLockdown)` -> "function" | pending | PASS |
| `x:comms.prefix` | custom | registering our prefix succeeds | `/dump C_ChatInfo.RegisterAddonMessagePrefix("FLDGF")` | pending | PASS |
| `ev:CHAT_MSG_ADDON` | event | receive whispered addon messages (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("CHAT_MSG_ADDON")` -> true | pending | PASS |
| `C_FriendList.GetNumFriends` | api | count character friends | `/dump type(C_FriendList.GetNumFriends)` -> "function" | pending | PASS |
| `C_FriendList.GetFriendInfoByIndex` | api | character friend name, online, class | `/dump type(C_FriendList.GetFriendInfoByIndex)` -> "function" | pending | PASS |
| `C_FriendList.ShowFriends` | api | refresh the friend list | `/dump type(C_FriendList.ShowFriends)` -> "function" | pending | PASS |
| `x:friends.charfields` | custom | field names on character friend info | `/dump C_FriendList.GetFriendInfoByIndex(1)` | pending | INFO |
| `ev:FRIENDLIST_UPDATE` | event | character friend list changed | `/dump C_EventUtils.IsEventValid("FRIENDLIST_UPDATE")` -> true | pending | PASS |

### Restrictions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_ACTION_FORBIDDEN` | event | tells us if we hit a blocked action | `/dump C_EventUtils.IsEventValid("ADDON_ACTION_FORBIDDEN")` -> true | pending | PASS |

### UI

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `CreateFrame` | api | all UI | `/dump type(CreateFrame)` -> "function" | pending | PASS |
| `BackdropTemplateMixin` | api | window borders | `/dump type(BackdropTemplateMixin)` -> "table" | pending | PASS |
| `UISpecialFrames` | api | Escape closes the window | `/dump type(UISpecialFrames)` -> "table" | pending | PASS |
| `Minimap` | api | minimap button parent | `/dump type(Minimap)` -> "table" | pending | PASS |
| `GetCursorPosition` | api | drag the minimap button | `/dump type(GetCursorPosition)` -> "function" | pending | PASS |
| `Settings.RegisterCanvasLayoutCategory` | api | Options panel entry | `/dump type(Settings.RegisterCanvasLayoutCategory)` -> "function" | pending | PASS |
| `Settings.RegisterAddOnCategory` | api | Options panel entry | `/dump type(Settings.RegisterAddOnCategory)` -> "function" | pending | PASS |
| `Settings.OpenToCategory` | api | open our Options page | `/dump type(Settings.OpenToCategory)` -> "function" | pending | PASS |
| `AddonCompartmentFrame` | api | addon compartment menu entry | `/dump type(AddonCompartmentFrame)` -> "table" | pending | PASS |
| `MenuUtil.CreateContextMenu` | api | right-click menus | `/dump type(MenuUtil.CreateContextMenu)` -> "function" | pending | PASS |
| `CreateColor` | api | colors | `/dump type(CreateColor)` -> "function" | pending | PASS |
| `PlaySound` | api | toast sound | `/dump type(PlaySound)` -> "function" | pending | PASS |
| `SOUNDKIT` | api | sound IDs | `/dump type(SOUNDKIT)` -> "table" | pending | PASS |
| `x:ui.frame` | custom | frame and texture methods the window uses (SetResizeBounds or SetMinResize, StartSizing, SetShown, SetColorTexture) | `/dump CreateFrame("Frame").SetResizeBounds` | pending | ? |
| `m:copywindow` | manual | the verify report window opens, scrolls, copies and closes with Escape | `/fl verify, then Ctrl+A, Ctrl+C, Escape` | pending | ? |

<!-- GENERATED:END -->
