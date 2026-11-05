# API verification

> **Forever verified on 2026-11-04** (`docs/verify-reports/forever-2026-11-04.txt`): 191 pass, 0 errors, the same 7 Classic-only fails as retail. The only difference from retail is `x:questie.db` (Questie is on Forever only). Forever is `WOW_PROJECT_ID` 18 (`CAMELOT`). It has no `C_QuestLine` data for its quests, so Questie is the chain source. Still open: profession ranks (0 readable; does the character have professions?), the death recap, and commtest after the self-name fix (D-062).
>
> Earlier note: **FOREVER NOT YET VERIFIED.** Every Forever cell says `pending`. Forever launches 2026-11-04 at 15:00 PST. Until then, the code is built on the **retail** results (2026-11-04, `docs/verify-reports/retail-2026-11-04.txt`), on the assumption that Forever shares retail's client. On Forever, the addon prints a reminder at login until a Forever `/fl verify` report is saved. When it arrives, save it as `docs/verify-reports/forever-<date>.txt` and run `python tools/apply_verify_report.py <file>`. The tool fills the Forever column and lists every check that differs from retail. Fix each difference before marking Forever as verified.

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
  - Fourth check (12:01, in-game `/fl test` 9/9 and `/fl export` after about 16 minutes of play): end-to-end tracking works on retail.
    - `QUEST_TURNED_IN` fires, and titles come from the quest-log cache (3 turn-ins logged once each). `QUEST_ACCEPTED` fires too.
    - Gold: `MERCHANT_SHOW` makes vendor money; `QUEST_TURNED_IN` makes quest money. Loot, quest and vendor add up exactly to money in, with no "other".
    - `PARTY_KILL` was counted 29 times.
    - Profession skill-ups: 6, via the throttled `SKILL_LINES_CHANGED` rescan.
    - `ZONE_CHANGED_NEW_AREA`: 2 new zones.
    - `PLAYER_LEVEL_UP` recorded 14 -> 15, partial because the ledger joined mid-level.
    - Played 958 s and active 870 s.
    - No feature disabled itself.
    - Saved as `docs/verify-reports/retail-2026-11-04-export.txt`, with the character name redacted.
  - Fifth check (12:35, `docs/verify-reports/retail-2026-11-04-1235.txt`, after a follower dungeon and levels 16-18):
    - `ENCOUNTER_START` (id, name, difficulty, size) and `ENCOUNTER_END` (id, name, difficulty, size, success, table) fire, and so do `BOSS_KILL` (id, name), `LFG_COMPLETION_REWARD` and `SCENARIO_COMPLETED`. The dungeon was counted entered once and completed once, with 4 boss kills.
    - `GetInstanceInfo` reported difficulty **0** on entry, so the difficulty is now taken from the encounter events.
    - Follower-dungeon companions are party units that level up with you, which gave 10 false "party level-ups". `UnitIsPlayer` now filters them out.
    - `UPDATE_FACTION` fired 28 times with no gain found. Factions under collapsed headers are hidden from the by-index list, so reputation is now looked up by faction ID.
    - `UI_INFO_MESSAGE` (408, "Discovered: Ruins of Zul'Kunda") is the real "zone discovered" signal, and it is now used.
    - `ACHIEVEMENT_EARNED` (16275, true): the second argument is "already earned on the account", and those are skipped.
    - `TAXIMAP_OPENED` (2) fires. `PLAYER_FLAGS_CHANGED` ("player") fired 10 times, so AFK is seen.
    - `BN_FRIEND_INFO_CHANGED` fired 286 times in an hour, which Phase 3 must throttle.
    - **Battle.net friends in WoW** expose `characterName, realmName, realmDisplayName, realmID, wowProjectID, classFilename, characterLevel, factionName, areaName, playerGuid`. `wowProjectID` was 1 for retail.
    - `x:rep.fields` and `x:ui.frame` pass (`SetResizeBounds` yes, `SetMinResize` no).
    - Manual checks confirmed on retail: `/fl` works, the window works and the report copies.
  - Sixth check (13:03, Phase 2 build, `retail-2026-11-04-1303.txt`):
    - `AddonCompartmentFrame:RegisterAddon`, `GameTooltip`, `UnitIsPlayer`, `GetGameMessageInfo` and both `ERR_ZONE_EXPLORED` strings pass.
    - Questie is not installed on retail, so `x:questie.db` is a Forever check.
    - `m:fakeviews` failed by eye: overlapping date labels, labels outside the window, repeated axis numbers, and a font halo. All are fixed in the next build and need re-checking.
  - `/fl commtest` (13:53, `retail-2026-11-04-commtest.txt`): addon whispers to yourself of 60, 100, 150, 200, 240 and 255 bytes all returned Success and all arrived. **255 bytes is the real whisper limit.** `CHAT_MSG_ADDON` arguments are (string prefix, string text, string channel, string sender, string target, number zoneChannelID, number localID, string name, number instanceID), the order `Comms/Transport.lua` assumes. The 2 HELLOs to online retail friends returned Success; neither runs the ledger. The size limits for `C_BattleNet.SendGameData` and the `BN_CHAT_MSG_ADDON` arguments still need a second client.
  - **Not yet seen firing:** the mail and auction events, `PLAYER_DEAD`, and a real reputation gain or flight path learned. The trackers that use them are built defensively and stay on the in-game checklist.
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
| `x:build.interface` | custom | TOC interface number (expect 16001 Forever, 120105 retail) | `/dump select(4, GetBuildInfo())` | PASS | PASS |
| `x:build.version` | custom | client version and build number | `/dump GetBuildInfo()` | INFO | INFO |
| `x:build.tocflavor` | custom | the client loaded the flavor TOC that matches its interface number | `/dump C_AddOns.GetAddOnMetadata("FellowshipLedger", "X-Flavor")` | PASS | PASS |
| `x:build.projectid` | custom | WOW_PROJECT_ID value, to tell flavors apart in friend info | `/dump WOW_PROJECT_ID, WOW_PROJECT_MAINLINE` | INFO | INFO |
| `GetBuildInfo` | api | read client version and interface number | `/dump type(GetBuildInfo)` -> "function" | PASS | PASS |
| `C_AddOns.GetAddOnMetadata` | api | read our TOC fields (version, flavor) | `/dump type(C_AddOns.GetAddOnMetadata)` -> "function" | PASS | PASS |
| `C_AddOns.IsAddOnLoaded` | api | detect Questie | `/dump type(C_AddOns.IsAddOnLoaded)` -> "function" | PASS | PASS |
| `C_EventUtils.IsEventValid` | api | how /fl verify checks events; if missing it falls back to trying RegisterEvent | `/dump type(C_EventUtils.IsEventValid)` -> "function" | PASS | PASS |
| `x:addon.questie` | custom | is Questie loaded and which version | `/dump C_AddOns.IsAddOnLoaded("Questie")` | INFO | INFO |
| `m:toc.icon` | manual | IconTexture path format works | AddOns list (character select or Esc > AddOns): the compass icon shows next to Fellowship Ledger | pending | ? |
| `m:toc.suffix` | manual | client picks the _Forever / _Mainline TOC, not the fallback | AddOns list title reads 'Fellowship Ledger' with no red '(unsupported client)' | pending | PASS |
| `m:slash` | manual | /fl is not taken by another addon | type /fl - our command list appears | pending | PASS |

### SavedVariables

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `x:sv.persist` | custom | SavedVariables survive /reload and relog (reported Forever bug) | `/dump FellowshipLedgerDB.dev.persistProbe` | PASS | PASS |
| `x:sv.backup` | custom | the second saved variable (backup) persists too | `/dump FellowshipLedgerBackupDB.persistProbe` | PASS | PASS |

### Character

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitName` | api | own character name | `/dump type(UnitName)` -> "function" | PASS | PASS |
| `UnitFullName` | api | own name and realm | `/dump type(UnitFullName)` -> "function" | PASS | PASS |
| `GetRealmName` | api | realm for Name-Realm key | `/dump type(GetRealmName)` -> "function" | PASS | PASS |
| `GetNormalizedRealmName` | api | realm without spaces, for whisper targets | `/dump type(GetNormalizedRealmName)` -> "function" | PASS | PASS |
| `UnitClass` | api | class of self and party members | `/dump type(UnitClass)` -> "function" | PASS | PASS |
| `UnitRace` | api | race | `/dump type(UnitRace)` -> "function" | PASS | PASS |
| `UnitFactionGroup` | api | faction | `/dump type(UnitFactionGroup)` -> "function" | PASS | PASS |
| `UnitLevel` | api | level | `/dump type(UnitLevel)` -> "function" | PASS | PASS |
| `UnitXP` | api | current XP | `/dump type(UnitXP)` -> "function" | PASS | PASS |
| `UnitXPMax` | api | XP to next level | `/dump type(UnitXPMax)` -> "function" | PASS | PASS |
| `GetXPExhaustion` | api | rested XP (context for XP per hour) | `/dump type(GetXPExhaustion)` -> "function" | PASS | PASS |
| `GetMoney` | api | gold tracking | `/dump type(GetMoney)` -> "function" | PASS | PASS |
| `GetLocale` | api | pick locale strings | `/dump type(GetLocale)` -> "function" | PASS | PASS |
| `IsTrialAccount` | api | trial accounts cannot send addon messages | `/dump type(IsTrialAccount)` -> "function" | PASS | PASS |
| `IsVeteranTrialAccount` | api | same, for lapsed accounts | `/dump type(IsVeteranTrialAccount)` -> "function" | PASS | PASS |
| `x:secret.ownvalues` | custom | own level, XP and money are readable plain numbers (not secret) | `/dump UnitLevel("player"), UnitXP("player"), GetMoney()` | PASS | PASS |

### Secret values

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `issecretvalue` | api | test a value before reading it | `/dump type(issecretvalue)` -> "function" | PASS | PASS |
| `canaccessvalue` | api | alternative secret check | `/dump type(canaccessvalue)` -> "function" | PASS | PASS |
| `issecrettable` | api | secret check for tables | `/dump type(issecrettable)` -> "function" | PASS | PASS |
| `canaccesssecrets` | api | whether the current context may read secrets | `/dump type(canaccesssecrets)` -> "function" | PASS | PASS |

### Time

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Timer.After` | api | delayed work, retries | `/dump type(C_Timer.After)` -> "function" | PASS | PASS |
| `C_Timer.NewTicker` | api | 10-minute backup, sync timer, idle check | `/dump type(C_Timer.NewTicker)` -> "function" | PASS | PASS |
| `GetServerTime` | api | server epoch time | `/dump type(GetServerTime)` -> "function" | PASS | PASS |
| `GetTime` | api | precise elapsed time for active-time math | `/dump type(GetTime)` -> "function" | PASS | PASS |
| `RequestTimePlayed` | api | time played per session | `/dump type(RequestTimePlayed)` -> "function" | PASS | PASS |
| `ev:TIME_PLAYED_MSG` | event | answer to RequestTimePlayed | `/dump C_EventUtils.IsEventValid("TIME_PLAYED_MSG")` -> true | PASS | PASS |

### Activity

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitIsAFK` | api | AFK flag ends active time | `/dump type(UnitIsAFK)` -> "function" | PASS | PASS |
| `GetUnitSpeed` | api | is the player moving | `/dump type(GetUnitSpeed)` -> "function" | PASS | PASS |
| `InCombatLockdown` | api | never send during combat | `/dump type(InCombatLockdown)` -> "function" | PASS | PASS |
| `UnitAffectingCombat` | api | own combat state | `/dump type(UnitAffectingCombat)` -> "function" | PASS | PASS |
| `ev:PLAYER_FLAGS_CHANGED` | event | AFK on/off | `/dump C_EventUtils.IsEventValid("PLAYER_FLAGS_CHANGED")` -> true | PASS | PASS |
| `ev:PLAYER_STARTED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STARTED_MOVING")` -> true | PASS | PASS |
| `ev:PLAYER_STOPPED_MOVING` | event | activity signal | `/dump C_EventUtils.IsEventValid("PLAYER_STOPPED_MOVING")` -> true | PASS | PASS |
| `ev:PLAYER_REGEN_DISABLED` | event | entered combat: pause sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_DISABLED")` -> true | PASS | PASS |
| `ev:PLAYER_REGEN_ENABLED` | event | left combat: resume sending | `/dump C_EventUtils.IsEventValid("PLAYER_REGEN_ENABLED")` -> true | PASS | PASS |
| `ev:UNIT_SPELLCAST_SUCCEEDED` | event | activity signal (own casts only) (not probed: too noisy) | `/dump C_EventUtils.IsEventValid("UNIT_SPELLCAST_SUCCEEDED")` -> true | PASS | PASS |

### Session

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_LOADED` | event | saved variables ready | `/dump C_EventUtils.IsEventValid("ADDON_LOADED")` -> true | PASS | PASS |
| `ev:PLAYER_LOGIN` | event | session start | `/dump C_EventUtils.IsEventValid("PLAYER_LOGIN")` -> true | PASS | PASS |
| `ev:PLAYER_ENTERING_WORLD` | event | login vs reload flags, instance changes | `/dump C_EventUtils.IsEventValid("PLAYER_ENTERING_WORLD")` -> true | PASS | PASS |
| `ev:PLAYER_LOGOUT` | event | session end, final backup | `/dump C_EventUtils.IsEventValid("PLAYER_LOGOUT")` -> true | PASS | PASS |
| `ev:PLAYER_LEAVING_WORLD` | event | loading screens | `/dump C_EventUtils.IsEventValid("PLAYER_LEAVING_WORLD")` -> true | PASS | PASS |

### Levels

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_LEVEL_UP` | event | level gained (args: level, ...) | `/dump C_EventUtils.IsEventValid("PLAYER_LEVEL_UP")` -> true | PASS | PASS |
| `ev:PLAYER_XP_UPDATE` | event | XP per hour | `/dump C_EventUtils.IsEventValid("PLAYER_XP_UPDATE")` -> true | PASS | PASS |
| `ev:UNIT_LEVEL` | event | party member level-ups | `/dump C_EventUtils.IsEventValid("UNIT_LEVEL")` -> true | PASS | PASS |

### Zones

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Map.GetBestMapForUnit` | api | zone where a level happened | `/dump type(C_Map.GetBestMapForUnit)` -> "function" | PASS | PASS |
| `C_Map.GetMapInfo` | api | zone name from map ID | `/dump type(C_Map.GetMapInfo)` -> "function" | PASS | PASS |
| `GetZoneText` | api | zone name fallback | `/dump type(GetZoneText)` -> "function" | PASS | PASS |
| `GetRealZoneText` | api | zone name inside instances | `/dump type(GetRealZoneText)` -> "function" | PASS | PASS |
| `GetSubZoneText` | api | subzone name | `/dump type(GetSubZoneText)` -> "function" | PASS | PASS |
| `C_Map.GetAreaInfo` | api | zone name from an area ID (start zone of a Questie chain) | `/dump type(C_Map.GetAreaInfo)` -> "function" | PASS | ? |
| `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` | api | zones discovered | `/dump type(C_MapExplorationInfo.GetExploredAreaIDsAtPosition)` -> "function" | PASS | PASS |
| `GetGameMessageInfo` | api | name of a UI info message type (ERR_ZONE_EXPLORED = discovered an area) | `/dump type(GetGameMessageInfo)` -> "function" | PASS | PASS |
| `ERR_ZONE_EXPLORED` | api | client's own 'Discovered: %s' format, to recognise discoveries in any language | `/dump type(ERR_ZONE_EXPLORED)` -> "string" | PASS | PASS |
| `ERR_ZONE_EXPLORED_XP` | api | same, for discoveries that give experience | `/dump type(ERR_ZONE_EXPLORED_XP)` -> "string" | PASS | PASS |
| `ev:ZONE_CHANGED` | event | subzone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED")` -> true | PASS | PASS |
| `ev:ZONE_CHANGED_NEW_AREA` | event | zone change | `/dump C_EventUtils.IsEventValid("ZONE_CHANGED_NEW_AREA")` -> true | PASS | PASS |
| `ev:UI_INFO_MESSAGE` | event | possible signal for 'discovered' and 'flight path learned' | `/dump C_EventUtils.IsEventValid("UI_INFO_MESSAGE")` -> true | PASS | PASS |
| `x:map.current` | custom | current map ID and name are readable | `/dump C_Map.GetBestMapForUnit("player")` | PASS | PASS |

### Quests

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_QuestLog.GetNumQuestLogEntries` | api | walk the quest log | `/dump type(C_QuestLog.GetNumQuestLogEntries)` -> "function" | PASS | PASS |
| `C_QuestLog.GetInfo` | api | quest log entry (questID, title, isHeader) | `/dump type(C_QuestLog.GetInfo)` -> "function" | PASS | PASS |
| `C_QuestLog.GetTitleForQuestID` | api | quest title for the turn-in log | `/dump type(C_QuestLog.GetTitleForQuestID)` -> "function" | PASS | PASS |
| `C_QuestLog.IsQuestFlaggedCompleted` | api | is a chain step done | `/dump type(C_QuestLog.IsQuestFlaggedCompleted)` -> "function" | PASS | PASS |
| `C_QuestLine.GetQuestLineInfo` | api | quest chain for a quest (game data) | `/dump type(C_QuestLine.GetQuestLineInfo)` -> "function" | PASS | PASS |
| `C_QuestLine.GetQuestLineQuests` | api | all quests in a chain | `/dump type(C_QuestLine.GetQuestLineQuests)` -> "function" | PASS | PASS |
| `C_QuestLine.GetAvailableQuestLines` | api | chains available on a map | `/dump type(C_QuestLine.GetAvailableQuestLines)` -> "function" | PASS | PASS |
| `C_QuestLine.RequestQuestLinesForMap` | api | load chain data for a map | `/dump type(C_QuestLine.RequestQuestLinesForMap)` -> "function" | PASS | PASS |
| `x:quest.questline` | custom | does game data return a chain for quests in your log | `/dump C_QuestLine.GetQuestLineInfo(<questID>)` | INFO | INFO |
| `ev:QUEST_ACCEPTED` | event | quest accepted | `/dump C_EventUtils.IsEventValid("QUEST_ACCEPTED")` -> true | PASS | PASS |
| `ev:QUEST_TURNED_IN` | event | turn-in (args: questID, xp, money) | `/dump C_EventUtils.IsEventValid("QUEST_TURNED_IN")` -> true | PASS | PASS |
| `ev:QUEST_REMOVED` | event | quest left the log | `/dump C_EventUtils.IsEventValid("QUEST_REMOVED")` -> true | PASS | PASS |
| `ev:QUEST_LOG_UPDATE` | event | quest log changed | `/dump C_EventUtils.IsEventValid("QUEST_LOG_UPDATE")` -> true | PASS | PASS |
| `ev:QUEST_COMPLETE` | event | reward frame open (money from quests) | `/dump C_EventUtils.IsEventValid("QUEST_COMPLETE")` -> true | PASS | PASS |

### Dungeons

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `IsInInstance` | api | entered a dungeon | `/dump type(IsInInstance)` -> "function" | PASS | PASS |
| `GetInstanceInfo` | api | dungeon name, type, difficulty, instance ID | `/dump type(GetInstanceInfo)` -> "function" | PASS | PASS |
| `GetDifficultyInfo` | api | difficulty name | `/dump type(GetDifficultyInfo)` -> "function" | PASS | PASS |
| `IsInGroup` | api | group make-up | `/dump type(IsInGroup)` -> "function" | PASS | PASS |
| `UnitIsPlayer` | api | tell real players from follower-dungeon companions | `/dump type(UnitIsPlayer)` -> "function" | PASS | PASS |
| `GetNumGroupMembers` | api | group make-up | `/dump type(GetNumGroupMembers)` -> "function" | PASS | PASS |
| `UnitGroupRolesAssigned` | api | party member role | `/dump type(UnitGroupRolesAssigned)` -> "function" | PASS | PASS |
| `EJ_GetInstanceForMap` | api | find a dungeon's journal entry (to know the last boss) | `/dump type(EJ_GetInstanceForMap)` -> "function" | PASS | PASS |
| `EJ_SelectInstance` | api | select journal instance before listing bosses | `/dump type(EJ_SelectInstance)` -> "function" | PASS | PASS |
| `EJ_GetEncounterInfoByIndex` | api | list bosses in order (last one = completion) | `/dump type(EJ_GetEncounterInfoByIndex)` -> "function" | PASS | PASS |
| `EJ_GetNumTiers` | api | journal tiers, to find a dungeon by name (D-085) | `/dump type(EJ_GetNumTiers)` -> "function" | PASS | ? |
| `EJ_SelectTier` | api | journal tiers, to find a dungeon by name (D-085) | `/dump type(EJ_SelectTier)` -> "function" | PASS | ? |
| `EJ_GetInstanceByIndex` | api | journal instance list, to find a dungeon by name (D-085) | `/dump type(EJ_GetInstanceByIndex)` -> "function" | PASS | ? |
| `x:dungeon.journal` | custom | the newest run's boss list from the journal, by map or by name, so completion can be counted (D-085) | after a dungeon run, /fl verify | PASS | ? |
| `x:dungeon.instance` | custom | GetInstanceInfo returns readable values here | `/dump GetInstanceInfo()` | INFO | INFO |
| `ev:ENCOUNTER_START` | event | boss pull: pause sending | `/dump C_EventUtils.IsEventValid("ENCOUNTER_START")` -> true | PASS | PASS |
| `ev:ENCOUNTER_END` | event | boss kill (args: encounterID, name, difficulty, size, success) | `/dump C_EventUtils.IsEventValid("ENCOUNTER_END")` -> true | PASS | PASS |
| `ev:BOSS_KILL` | event | boss kill alternative | `/dump C_EventUtils.IsEventValid("BOSS_KILL")` -> true | PASS | PASS |
| `ev:LFG_COMPLETION_REWARD` | event | finder dungeon completed | `/dump C_EventUtils.IsEventValid("LFG_COMPLETION_REWARD")` -> true | PASS | PASS |
| `ev:SCENARIO_COMPLETED` | event | scenario-style completion | `/dump C_EventUtils.IsEventValid("SCENARIO_COMPLETED")` -> true | PASS | PASS |
| `ev:UPDATE_INSTANCE_INFO` | event | instance lockout info | `/dump C_EventUtils.IsEventValid("UPDATE_INSTANCE_INFO")` -> true | PASS | PASS |
| `ev:GROUP_ROSTER_UPDATE` | event | party changed | `/dump C_EventUtils.IsEventValid("GROUP_ROSTER_UPDATE")` -> true | PASS | PASS |

### Professions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetProfessions` | api | list professions (retail style) | `/dump type(GetProfessions)` -> "function" | PASS | PASS |
| `GetProfessionInfo` | api | rank and max rank | `/dump type(GetProfessionInfo)` -> "function" | PASS | PASS |
| `GetNumSkillLines` | api | skill list (classic style fallback) | `/dump type(GetNumSkillLines)` -> "function" | FAIL | FAIL |
| `GetSkillLineInfo` | api | skill rank (classic style fallback) | `/dump type(GetSkillLineInfo)` -> "function" | FAIL | FAIL |
| `C_TradeSkillUI.GetBaseProfessionInfo` | api | open profession info | `/dump type(C_TradeSkillUI.GetBaseProfessionInfo)` -> "function" | PASS | PASS |
| `x:prof.list` | custom | professions and ranks are readable | `/dump GetProfessions()` | INFO | INFO |
| `ev:SKILL_LINES_CHANGED` | event | skill-up | `/dump C_EventUtils.IsEventValid("SKILL_LINES_CHANGED")` -> true | PASS | PASS |
| `ev:TRADE_SKILL_SHOW` | event | profession window opened | `/dump C_EventUtils.IsEventValid("TRADE_SKILL_SHOW")` -> true | PASS | PASS |
| `ev:NEW_RECIPE_LEARNED` | event | recipe learned | `/dump C_EventUtils.IsEventValid("NEW_RECIPE_LEARNED")` -> true | PASS | PASS |

### Gold

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_MONEY` | event | money changed | `/dump C_EventUtils.IsEventValid("PLAYER_MONEY")` -> true | PASS | PASS |
| `ev:MERCHANT_SHOW` | event | vendor open: money changes count as vendor | `/dump C_EventUtils.IsEventValid("MERCHANT_SHOW")` -> true | PASS | PASS |
| `ev:MERCHANT_CLOSED` | event | vendor closed | `/dump C_EventUtils.IsEventValid("MERCHANT_CLOSED")` -> true | PASS | PASS |
| `ev:MAIL_SHOW` | event | mailbox open: money changes count as mail | `/dump C_EventUtils.IsEventValid("MAIL_SHOW")` -> true | PASS | PASS |
| `ev:MAIL_CLOSED` | event | mailbox closed | `/dump C_EventUtils.IsEventValid("MAIL_CLOSED")` -> true | PASS | PASS |
| `ev:AUCTION_HOUSE_SHOW` | event | auction house open | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_SHOW")` -> true | PASS | PASS |
| `ev:AUCTION_HOUSE_CLOSED` | event | auction house closed | `/dump C_EventUtils.IsEventValid("AUCTION_HOUSE_CLOSED")` -> true | PASS | PASS |
| `ev:LOOT_READY` | event | loot window: money changes count as loot | `/dump C_EventUtils.IsEventValid("LOOT_READY")` -> true | PASS | PASS |
| `ev:LOOT_OPENED` | event | loot window opened | `/dump C_EventUtils.IsEventValid("LOOT_OPENED")` -> true | PASS | PASS |
| `ev:LOOT_CLOSED` | event | loot window closed | `/dump C_EventUtils.IsEventValid("LOOT_CLOSED")` -> true | PASS | PASS |

### Deaths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:PLAYER_DEAD` | event | you died | `/dump C_EventUtils.IsEventValid("PLAYER_DEAD")` -> true | PASS | PASS |
| `ev:PLAYER_ALIVE` | event | released / resurrected | `/dump C_EventUtils.IsEventValid("PLAYER_ALIVE")` -> true | PASS | PASS |
| `ev:PLAYER_UNGHOST` | event | back from ghost | `/dump C_EventUtils.IsEventValid("PLAYER_UNGHOST")` -> true | PASS | PASS |
| `C_DeathRecap.GetRecapEvents` | api | what killed you (may be secret) | `/dump type(C_DeathRecap.GetRecapEvents)` -> "function" | PASS | PASS |
| `C_DeathRecap.HasRecapEvents` | api | is a death recap available | `/dump type(C_DeathRecap.HasRecapEvents)` -> "function" | PASS | PASS |
| `GetDeathRecapLink` | api | death recap fallback | `/dump type(GetDeathRecapLink)` -> "function" | PASS | PASS |
| `x:death.recap` | custom | the newest death recap can be found and its killing blow (source, spell) is readable, not secret | die once, then /fl verify (or /dump C_DeathRecap.GetRecapEvents(1)) | PASS | ? |
| `x:death.killerlevel` | custom | killer's level (1.0.1): your target's name and level (at death, or targeted in the last 5 minutes) are kept if the recap's killer has that name | target a monster, let it kill you, then /fl verify (the line shows target and recap source at death) | PASS | ? |

### Reputation

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Reputation.GetNumFactions` | api | walk factions | `/dump type(C_Reputation.GetNumFactions)` -> "function" | PASS | PASS |
| `C_Reputation.GetFactionDataByIndex` | api | faction standing (retail style) | `/dump type(C_Reputation.GetFactionDataByIndex)` -> "function" | PASS | PASS |
| `C_Reputation.GetFactionDataByID` | api | faction standing by ID | `/dump type(C_Reputation.GetFactionDataByID)` -> "function" | PASS | PASS |
| `GetNumFactions` | api | classic style fallback | `/dump type(GetNumFactions)` -> "function" | FAIL | FAIL |
| `GetFactionInfo` | api | classic style fallback | `/dump type(GetFactionInfo)` -> "function" | FAIL | FAIL |
| `x:rep.fields` | custom | FactionData field names (factionID, currentStanding, isHeader) used to diff standings | `/dump C_Reputation.GetFactionDataByIndex(2)` | PASS | PASS |
| `ev:UPDATE_FACTION` | event | reputation changed (diff standings) | `/dump C_EventUtils.IsEventValid("UPDATE_FACTION")` -> true | PASS | PASS |

### Achievements

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `GetAchievementInfo` | api | achievement name | `/dump type(GetAchievementInfo)` -> "function" | PASS | PASS |
| `ev:ACHIEVEMENT_EARNED` | event | achievement earned | `/dump C_EventUtils.IsEventValid("ACHIEVEMENT_EARNED")` -> true | PASS | PASS |

### Flight paths

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_TaxiMap.GetAllTaxiNodes` | api | known flight paths | `/dump type(C_TaxiMap.GetAllTaxiNodes)` -> "function" | PASS | PASS |
| `NumTaxiNodes` | api | flight map fallback | `/dump type(NumTaxiNodes)` -> "function" | PASS | PASS |
| `TaxiNodeName` | api | flight map fallback | `/dump type(TaxiNodeName)` -> "function" | PASS | PASS |
| `GetTaxiMapID` | api | map ID of the open flight map | `/dump type(GetTaxiMapID)` -> "function" | PASS | PASS |
| `Enum.FlightPathState` | api | which taxi nodes are known (Unreachable = unknown) | `/dump type(Enum.FlightPathState)` -> "table" | PASS | PASS |
| `ev:TAXIMAP_OPENED` | event | flight map opened (diff known nodes) | `/dump C_EventUtils.IsEventValid("TAXIMAP_OPENED")` -> true | PASS | PASS |
| `ERR_NEWTAXIPATH` | api | the client's "New flight path discovered!" text (D-080) | `/dump type(ERR_NEWTAXIPATH)` -> "string" | PASS | ? |
| `x:flight.paths` | custom | flight paths known and counted; whether the discovery message and the flight map were seen this session (D-080) | talk to a flight master you don't know yet, then /fl verify | PASS | ? |

### Kills

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `UnitGUID` | api | compare PARTY_KILL attacker/target with you and your target (equality only) | `/dump type(UnitGUID)` -> "function" | PASS | PASS |
| `UnitExists` | api | target exists | `/dump type(UnitExists)` -> "function" | PASS | PASS |
| `UnitIsDead` | api | target died (no combat log allowed) | `/dump type(UnitIsDead)` -> "function" | PASS | PASS |
| `UnitClassification` | api | rare / elite kills | `/dump type(UnitClassification)` -> "function" | PASS | PASS |
| `UnitCreatureType` | api | kills by creature type | `/dump type(UnitCreatureType)` -> "function" | PASS | PASS |
| `ev:PLAYER_TARGET_CHANGED` | event | watch the target for kills | `/dump C_EventUtils.IsEventValid("PLAYER_TARGET_CHANGED")` -> true | PASS | PASS |
| `ev:PARTY_KILL` | event | kill credit event, if it still exists | `/dump C_EventUtils.IsEventValid("PARTY_KILL")` -> true | PASS | PASS |

### Items

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_Item.GetItemInfo` | api | item quality for notable drops | `/dump type(C_Item.GetItemInfo)` -> "function" | PASS | PASS |
| `GetItemInfo` | api | fallback (reported missing on Forever) | `/dump type(GetItemInfo)` -> "function" | FAIL | FAIL |
| `C_Item.GetItemQualityByID` | api | item quality | `/dump type(C_Item.GetItemQualityByID)` -> "function" | PASS | PASS |
| `GetItemStats` | api | reported missing on Forever; not planned, listed to confirm | `/dump type(GetItemStats)` -> "function" | FAIL | FAIL |
| `C_Spell.GetSpellInfo` | api | spell names | `/dump type(C_Spell.GetSpellInfo)` -> "function" | PASS | PASS |
| `GetSpellInfo` | api | fallback (reported missing on Forever) | `/dump type(GetSpellInfo)` -> "function" | FAIL | FAIL |
| `GetNumLootItems` | api | how many slots the open loot window has | `/dump type(GetNumLootItems)` -> "function" | PASS | ? |
| `GetLootSlotInfo` | api | loot slot name, quantity, currency, quality | `/dump type(GetLootSlotInfo)` -> "function" | PASS | ? |
| `GetLootSlotLink` | api | item link of a loot slot | `/dump type(GetLootSlotLink)` -> "function" | PASS | ? |
| `ev:LOOT_SLOT_CLEARED` | event | a loot slot was taken: the item counts as looted | `/dump C_EventUtils.IsEventValid("LOOT_SLOT_CLEARED")` -> true | PASS | ? |
| `ev:ITEM_PUSH` | event | item went into your bags | `/dump C_EventUtils.IsEventValid("ITEM_PUSH")` -> true | PASS | PASS |
| `ev:BAG_UPDATE_DELAYED` | event | bags settled (diff for new items) | `/dump C_EventUtils.IsEventValid("BAG_UPDATE_DELAYED")` -> true | PASS | PASS |

### Battle.net friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_BattleNet.SendGameData` | api | send to Battle.net friends | `/dump type(C_BattleNet.SendGameData)` -> "function" | PASS | PASS |
| `ev:BN_CHAT_MSG_ADDON` | event | receive from Battle.net friends (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("BN_CHAT_MSG_ADDON")` -> true | PASS | PASS |
| `x:comms.enum` | custom | Enum.SendAddonMessageResult has the result names we handle | `/dump Enum.SendAddonMessageResult` | PASS | PASS |
| `BNGetInfo` | api | own BattleTag (for the block list and grouping) | `/dump type(BNGetInfo)` -> "function" | PASS | PASS |
| `BNGetNumFriends` | api | count Battle.net friends | `/dump type(BNGetNumFriends)` -> "function" | PASS | PASS |
| `C_BattleNet.GetFriendAccountInfo` | api | friend account (BattleTag, online) | `/dump type(C_BattleNet.GetFriendAccountInfo)` -> "function" | PASS | PASS |
| `C_BattleNet.GetFriendNumGameAccounts` | api | characters a friend is logged in on | `/dump type(C_BattleNet.GetFriendNumGameAccounts)` -> "function" | PASS | PASS |
| `C_BattleNet.GetFriendGameAccountInfo` | api | character, realm, client, gameAccountID | `/dump type(C_BattleNet.GetFriendGameAccountInfo)` -> "function" | PASS | PASS |
| `C_BattleNet.GetGameAccountInfoByID` | api | look up the sender of a message | `/dump type(C_BattleNet.GetGameAccountInfoByID)` -> "function" | PASS | PASS |
| `C_BattleNet.GetAccountInfoByID` | api | look up a friend account | `/dump type(C_BattleNet.GetAccountInfoByID)` -> "function" | PASS | PASS |
| `x:friends.bnfields` | custom | field names on friend game-account info, and which flavor values online friends report | `/dump C_BattleNet.GetFriendAccountInfo(1).gameAccountInfo` | INFO | INFO |
| `ev:BN_FRIEND_ACCOUNT_ONLINE` | event | friend came online: sync | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_ONLINE")` -> true | PASS | PASS |
| `ev:BN_FRIEND_ACCOUNT_OFFLINE` | event | friend went offline | `/dump C_EventUtils.IsEventValid("BN_FRIEND_ACCOUNT_OFFLINE")` -> true | PASS | PASS |
| `ev:BN_FRIEND_INFO_CHANGED` | event | friend switched character or game | `/dump C_EventUtils.IsEventValid("BN_FRIEND_INFO_CHANGED")` -> true | PASS | PASS |

### Character friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `WOW_PROJECT_ID` | api | our project ID, compared with friends' wowProjectID so only same-flavor friends are messaged | `/dump type(WOW_PROJECT_ID)` -> "number" | PASS | ? |
| `BNET_CLIENT_WOW` | api | the clientProgram value of a friend playing WoW | `/dump type(BNET_CLIENT_WOW)` -> "string" | PASS | ? |
| `LE_PARTY_CATEGORY_INSTANCE` | api | tell finder groups (INSTANCE_CHAT) from home parties for the dungeon-name note | `/dump type(LE_PARTY_CATEGORY_INSTANCE)` -> "number" | PASS | ? |
| `m:commtest` | manual | addon whispers to yourself arrive; shows real size limits, result codes and CHAT_MSG_ADDON argument types | `/fl commtest, then paste the report` | PASS | PASS |

### Battle.net friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `m:sync` | manual | a friend who runs the ledger on the same client appears on the Friends tab after Sync now, with their data; nothing crosses Forever/retail | both run /fl sync; check Friends tab and /fl comms on both sides | pending | ? |

### Character friends

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_ChatInfo.RegisterAddonMessagePrefix` | api | register FLDGF / FLDGR | `/dump type(C_ChatInfo.RegisterAddonMessagePrefix)` -> "function" | PASS | PASS |
| `C_ChatInfo.IsAddonMessagePrefixRegistered` | api | confirm registration | `/dump type(C_ChatInfo.IsAddonMessagePrefixRegistered)` -> "function" | PASS | PASS |
| `C_ChatInfo.SendAddonMessage` | api | whisper addon messages to character friends | `/dump type(C_ChatInfo.SendAddonMessage)` -> "function" | PASS | PASS |
| `C_ChatInfo.InChatMessagingLockdown` | api | lockdown check before sending (Midnight) | `/dump type(C_ChatInfo.InChatMessagingLockdown)` -> "function" | PASS | PASS |
| `x:comms.prefix` | custom | registering our prefix succeeds | `/dump C_ChatInfo.RegisterAddonMessagePrefix("FLDGF")` | PASS | PASS |
| `ev:CHAT_MSG_ADDON` | event | receive whispered addon messages (probe counts only, no arguments stored) | `/dump C_EventUtils.IsEventValid("CHAT_MSG_ADDON")` -> true | PASS | PASS |
| `C_FriendList.GetNumFriends` | api | count character friends | `/dump type(C_FriendList.GetNumFriends)` -> "function" | PASS | PASS |
| `C_FriendList.GetFriendInfoByIndex` | api | character friend name, online, class | `/dump type(C_FriendList.GetFriendInfoByIndex)` -> "function" | PASS | PASS |
| `C_FriendList.ShowFriends` | api | refresh the friend list | `/dump type(C_FriendList.ShowFriends)` -> "function" | PASS | PASS |
| `x:friends.charfields` | custom | field names on character friend info | `/dump C_FriendList.GetFriendInfoByIndex(1)` | INFO | INFO |
| `ev:FRIENDLIST_UPDATE` | event | character friend list changed | `/dump C_EventUtils.IsEventValid("FRIENDLIST_UPDATE")` -> true | PASS | PASS |

### Restrictions

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `ev:ADDON_ACTION_FORBIDDEN` | event | tells us if we hit a blocked action | `/dump C_EventUtils.IsEventValid("ADDON_ACTION_FORBIDDEN")` -> true | PASS | PASS |

### UI

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `CreateFrame` | api | all UI | `/dump type(CreateFrame)` -> "function" | PASS | PASS |
| `BackdropTemplateMixin` | api | window borders | `/dump type(BackdropTemplateMixin)` -> "table" | PASS | PASS |
| `UISpecialFrames` | api | Escape closes the window | `/dump type(UISpecialFrames)` -> "table" | PASS | PASS |
| `Minimap` | api | minimap button parent | `/dump type(Minimap)` -> "table" | PASS | PASS |
| `GetCursorPosition` | api | drag the minimap button | `/dump type(GetCursorPosition)` -> "function" | PASS | PASS |
| `Settings.RegisterCanvasLayoutCategory` | api | Options panel entry | `/dump type(Settings.RegisterCanvasLayoutCategory)` -> "function" | PASS | PASS |
| `Settings.RegisterAddOnCategory` | api | Options panel entry | `/dump type(Settings.RegisterAddOnCategory)` -> "function" | PASS | PASS |
| `Settings.OpenToCategory` | api | open our Options page | `/dump type(Settings.OpenToCategory)` -> "function" | PASS | PASS |
| `AddonCompartmentFrame` | api | addon compartment menu entry | `/dump type(AddonCompartmentFrame)` -> "table" | PASS | PASS |
| `MenuUtil.CreateContextMenu` | api | right-click menus | `/dump type(MenuUtil.CreateContextMenu)` -> "function" | PASS | PASS |
| `CreateColor` | api | colors | `/dump type(CreateColor)` -> "function" | PASS | PASS |
| `PlaySound` | api | toast sound | `/dump type(PlaySound)` -> "function" | PASS | PASS |
| `SOUNDKIT` | api | sound IDs | `/dump type(SOUNDKIT)` -> "table" | PASS | PASS |
| `x:ui.frame` | custom | frame and texture methods the window uses (SetResizeBounds or SetMinResize, StartSizing, SetShown, SetColorTexture; for sort arrows SetTexCoord, SetVertexColor, GetStringWidth) | `/dump CreateFrame("Frame").SetResizeBounds` | PASS | PASS |
| `GameTooltip` | api | hover tooltips on graphs and the minimap button | `/dump type(GameTooltip)` -> "table" | PASS | PASS |
| `x:ui.compartment` | custom | AddonCompartmentFrame:RegisterAddon exists (menu entry by the minimap) | `/dump AddonCompartmentFrame.RegisterAddon` | PASS | PASS |
| `x:questie.db` | custom | Questie's internal QuestieDB.QueryQuestSingle is reachable (quest-chain fallback) | `/dump QuestieLoader:ImportModule("QuestieDB").QueryQuestSingle` | PASS | INFO |

### Quests

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `C_QuestLog.GetAllCompletedQuestIDs` | api | every quest this character completed (All completed view, D-081) | `/dump type(C_QuestLog.GetAllCompletedQuestIDs)` -> "function" | PASS | ? |
| `GetQuestsCompleted` | api | older form of the completed-quest list (a set of IDs); only a fallback, missing on Forever (2026-11-05) | `/dump type(GetQuestsCompleted)` -> "function" | FAIL | ? |
| `x:quest.completed` | custom | the completed-quest list is readable, and Questie names and zones for it (D-081) | `/fl verify on a character that has done quests` | PASS | ? |

### UI

| ID | Kind | What it is for | In-game test | Forever | Retail |
|---|---|---|---|---|---|
| `x:questie.details` | custom | quest-chain drop-downs (D-078): Questie's questLevel, requiredLevel, startedBy, and QueryNPCSingle name/spawns with the zone from C_Map.GetAreaInfo and map coordinates (D-079) | have a quest in your log, then /fl verify (the line shows the quest, its levels and who starts it where, with coordinates; compare with Questie's map) | PASS | ? |
| `m:minimap` | manual | minimap button shows the icon, left click toggles, right click opens Settings, drag moves and the spot is remembered | look at the minimap; click, right-click, drag, /reload | pending | ? |
| `m:options` | manual | Options > AddOns lists Fellowship Ledger and its button opens Settings | Esc > Options > AddOns > Fellowship Ledger | pending | ? |
| `m:fakeviews` | manual | with /fl fake every table and all five graphs draw, tooltips show, both skins and all text sizes look right | `/fl fake, visit every tab and chart, switch skin and text size, /fl fake off` | pending | ? |
| `m:copywindow` | manual | the verify report window opens, scrolls, copies and closes with Escape | `/fl verify, then Ctrl+A, Ctrl+C, Escape` | pending | PASS |

<!-- GENERATED:END -->
