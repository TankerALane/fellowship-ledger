# Decisions

Decisions made during development that the brief left open. Newest at the bottom. "Pending" means it is waiting for Austin to confirm.

## D-001 Track vs Share (pending confirmation)
Each tracker has two independent per-character flags, Track and Share, both on by default. Track off stops collection. Share off stops sending. Local tracking never depends on sharing. When Track is off, Share has nothing to send, so the Share toggle is shown greyed out.

## D-002 Fallback TOC prints a message only
`FellowshipLedger.toc` (interface 00000) loads only the locale and `Compat/Unsupported.lua`, which prints "unsupported client". The full addon never runs on a client that did not pick a flavor TOC. Questie uses the same pattern. If the suffix TOCs ever fail to load, the message makes it obvious.

## D-003 Flavor detection by interface number
Forever is 16000-16999 (the same range Questie uses) and retail is 120000 and up. Everything else is unsupported. The TOC also states its flavor (`## X-Flavor`), and the two are cross-checked.

## D-004 One interface number per TOC
Forever is `16001` and retail is `120105`, the values installed addons use. When the client patches, these get bumped. Listing several numbers, like some retail addons do with `120100, 120105, 120107`, is possible, but it was left out until a patch makes it necessary.

## D-005 Development version string
TOCs and `Core/Namespace.lua` say `0.0.1-dev`. Phase 4 switches the TOCs to the packager's `@project-version@` token. A unit test keeps the TOCs and the namespace in step.

## D-006 Single source for the verification list
`Debug/VerifyChecks.lua` is the source of truth. `docs/API-VERIFICATION.md` is generated from it by `tools/gen_verify_doc.py`. Python is only developer tooling and never ships in the addon. A unit test fails if the doc misses a check, and regenerating keeps Austin's PASS/FAIL marks.

## D-007 Verify report goes to a copy window
WoW chat text cannot be copied, so `/fl verify` opens a read-only text box (Ctrl+A, Ctrl+C) and also stores the report in `FellowshipLedgerDB.verify`. If the window cannot be built, the report is printed to chat instead.

## D-008 Event probe
`/fl probe on` counts the candidate events and keeps their first three argument samples. It survives reloads until turned off. Addon-message events are counted without storing arguments, and no player chat event is ever registered. A unit test enforces this.

## D-009 Verify output is privacy-safe
Custom checks report field names, counts and types. They never report friend names, BattleTags, realm names or chat text, because Austin pastes the report to a developer.

## D-010 Persistence probe in both saved variables
Every load bumps a counter in `FellowshipLedgerDB.dev.persistProbe` and in `FellowshipLedgerBackupDB.persistProbe`, and logout stamps a time. This directly tests the reported Forever SavedVariables bug before real data depends on it.

## D-011 Gold sources by context, not chat (planned)
"Loot vs vendor vs quest vs mail/auction" will be inferred from which window is open when `PLAYER_MONEY` fires: merchant, mailbox, auction house, loot window, or quest reward. The `QUEST_TURNED_IN` money argument is also used. Loot and money chat messages are not read, to honour "never read chat". Amounts that cannot be attributed show as "other".

## D-012 Empty module folders
`Trackers/`, `Comms/` and `UI/` hold a `.gitkeep` until code lands. The file is harmless when synced into the game.

## D-013 Building on retail verify data until Forever launches
On 2026-11-04 Austin chose to keep building for both clients on the retail `/fl verify` results, because Forever launched later that day. Forever cells in `API-VERIFICATION.md` say `pending`, the addon reminds on Forever until a Forever report is saved, and `tools/apply_verify_report.py` lists every difference once that report exists.

## D-014 What "active time" means (superseded by D-024)
Time counts as active for up to 5 minutes after the last activity signal: movement (and a 30-second movement check), combat, casting, targeting, XP, loot, quests, vendors, mail, zone changes or the flight map. After that it stops until the next signal. Going AFK stops it immediately. So quiet moments such as reading quest text still count, but walking away does not. There is no API for raw keyboard or mouse input, so a player who only reads for more than 5 minutes is treated as idle.

## D-015 What the "(total ...)" level time means
The total is **logged-in time** during that level, not wall-clock time. A night offline in the middle of a level does not inflate it.

## D-016 Backup is a per-character saved variable
`FellowshipLedgerBackupDB` is declared `SavedVariablesPerCharacter`, so it lives in a **different file** (`WTF\Account\<acct>\<realm>\<char>\SavedVariables\FellowshipLedger.lua`) from the main database. Both account-wide variables would share one file, so an account-wide backup could not protect against that file being lost or reset (the reported Forever bug). Each character's backup holds that character's record and a copy of the settings, written every 10 minutes and at logout (which also runs on `/reload`, as confirmed on retail). At login, if this character's main record is missing or empty, or was saved clearly before its backup, a dialog offers to restore it. `/fl restore` does the same by hand. The trade-off: after a full reset, each character is restored when you log into it.

## D-017 Partial levels
If the ledger starts partway through a level (first install, or the addon was off), that level's time is incomplete. It is recorded with `partial = true`, shown as "(partial)", and left out of XP-per-hour.

## D-018 Zones "discovered" means new zones visited while tracking
There is no confirmed event for "zone discovered". The ledger records the first visit to each map while it is running, and shows it as new zones visited.

## D-019 Kills come from PARTY_KILL by equality only
`PARTY_KILL(attackerGUID, targetGUID)` arguments were readable on retail. The ledger compares them with `UnitGUID("player")` and `UnitGUID("target")` and never parses them, which is safe with Forever's obfuscated GUIDs. Creature type and rare or elite status are recorded only when the killed unit was your target. If the arguments are secret on a client, the kills tracker turns itself off with a message.

## D-020 Not built yet: "what killed you" and notable item drops
`ITEM_PUSH` carries only a bag slot and an icon (seen on retail), and the death recap needs a recap ID whose source is unverified. Both are marked unavailable in `TrackerList` rather than faked, and are revisited in Phase 2 with new verify checks.

## D-021 Gold losses are never "quest" or "loot"
Quest rewards and loot only add money. A loss while a vendor, mailbox or auction house is open goes to that source, and any other loss goes to "other". Quest money that arrives a moment before `QUEST_TURNED_IN` is moved from "other" to "quest" when the event names the reward.

## D-022 `/fl` opens the window
`/fl` on its own toggles the ledger window, and `/fl help` lists the commands. An unknown subcommand also lists them.

## D-023 Party level-ups store class and level only
No names are stored, in keeping with the privacy rule for party members. Names arrive only through the Phase 3 opt-in.

## D-024 Idle stretches are removed whole (replaces D-014)
Austin's retail test showed the D-014 rule hid AFK time. That rule counted up to 5 quiet minutes as active, and the game's own auto-AFK also starts at 5 minutes, so a 5-minute AFK barely showed. The new rule:
- Time since the last activity signal is held as *pending*. The next activity signal commits it as active.
- If 5 minutes pass with no signal, the **whole** quiet stretch is dropped.
- Going AFK keeps the pending time only if there was activity in the last 60 seconds (a typed `/afk`). The game's auto-AFK keeps none of it.
- A level-up counts as activity, so pending time is committed before the level's time is recorded.
- Activity signals are unchanged: movement (and a 30-second movement check), combat, casting, targeting, XP, loot, quests, vendors, mail, zone changes and the flight map.

## D-025 Real zone discoveries come from the UI info message
Retail fires `UI_INFO_MESSAGE` (408, "Discovered: <area>"). That is the on-screen info line, not chat. The ledger recognises it by the message's error name (`GetGameMessageInfo` returns `ERR_ZONE_EXPLORED` or `ERR_ZONE_EXPLORED_XP`), or by matching the client's own localized format strings, so it works in any language. Results are counted as `zonesDiscovered` and listed in `discoveries`. "New zones visited" (D-018) is kept alongside.

## D-026 Reputation is read by faction ID
Factions under collapsed headers are missing from the by-index reputation list. At login the ledger asks `C_Reputation.GetFactionDataByID` for IDs 1 to 4000 once, keeps the ones that exist, and diffs their standings on `UPDATE_FACTION`. The diff is throttled to one per second and also includes anything newly visible in the panel. It never expands or collapses headers in your reputation panel.

## D-027 Follower companions are not party members for level-ups
In follower dungeons the AI companions are party units that level up with you. Party level-ups count real players only (`UnitIsPlayer`). Dungeon party make-up keeps companions but marks them `npc`.

## D-028 Quest money is matched by amount (refines D-021)
`QUEST_TURNED_IN` names the money reward. That amount is claimed from money gains within 5 seconds on either side, whichever event arrives first. Several quick turn-ins each claim their own reward. A loss never matches. Other money with no matching turn-in stays under "other". The 13g 16s left in "other" after Austin's follower dungeon was most likely the dungeon-finder reward.

## D-029 Dungeon difficulty from the encounter events
`GetInstanceInfo` reported difficulty 0 on entering a follower dungeon on retail. When the run's difficulty is 0, it is filled from `ENCOUNTER_START` and `ENCOUNTER_END`, which carried difficulty 1.

## D-030 Fake data is a separate, deterministic saved set
`/fl fake` writes `FellowshipLedgerDB.fake` (`{ characters, friends }`) from a fixed seed, so every run shows the same world. The set holds 3 of "your" characters, 3 Battle.net friends with 2 to 4 characters each, and 1 character-only friend, with 90 days of history. The windows read through `Core/Data.lua`, which returns the fake set while it exists. Trackers always write to `db.characters`, export and backup read only real data, and Phase 3 sharing will read only real data. A red "FAKE DATA" banner shows in the window. `/fl fake off` deletes the set.

## D-031 Skins are color and font roles
Every texture and text asks for a role ("bg", "text", "accent", ... and "small", "body", "large", "heading"). The two skins map the roles to colors: "Ledger" is parchment, ink and gold, and "Plain" is the default dark game look. Changing the skin, the text size or the palette restyles open windows in place, with no `/reload`. Scale applies with `SetScale`.

## D-032 Graph colors and accessibility
The colorblind-safe palette (Okabe-Ito) is **on by default**; the brand palette is optional. No graph relies on color alone:
- Every bar has a tooltip with its exact value.
- Losses hang below the zero line.
- Partial levels are faded and labelled "(partial)".
- Toggles read "[x]" or "[ ]".
- Table sort direction shows as "v" or "^".

## D-033 Questie is used through its internal database, fully guarded
Questie has no public quest-chain API, so the ledger reads Questie 12.5.1's own source: `QuestieLoader:ImportModule("QuestieDB").QueryQuestSingle(id, "preQuestSingle" | "nextQuestInChain" | "name")`, and only after `Questie.API.isReady`. Any error marks Questie as "broken" for the session. The chain view then falls back to "no chain information", Settings says Questie's data could not be read, and `/fl verify` has `x:questie.db`. Game data (`C_QuestLine`) is always tried first.

## D-034 Friends tab before sharing exists
Real friend data arrives with Phase 3. Until then the Friends tab explains that and offers `/fl fake`. Block and Unblock already work: blocked BattleTags or `Name-Realm` keys are hidden from the Friends tab and the Graphs character list, and Phase 3 will never send to them.

## D-035 Graphs per character; compare overlay in Phase 3
The Graphs tab cycles through your characters and your friends' characters, one chart at a time. "XP per hour" is per session (XP over active hours). "Quests per day" covers the last 30 days. The compare overlay waits for Phase 3 (where the brief lists it), because it needs friend data.

## D-036 Session summary
At login, if a new session started, a notice summarises the previous session: played and active time, levels, quests, dungeons, gold, skill-ups and deaths. `/fl summary` shows it again, and `/fl summary now` shows the current session so far. Every notice is also written to chat. Whether chat output works during logout is unverified, which is why the summary is shown at the next login instead.

## D-037 Welcome panel shows once, including for existing installs
`settings.welcomeSeen` starts false, so Austin's existing characters see the panel once after this update. "Turn off all sharing" sets the master pause, and the per-character toggles live in Settings.
