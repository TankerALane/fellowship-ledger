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

## D-038 Ledger skin text has no drop shadow
The game's standard fonts draw a 1-pixel black shadow. It reads as a halo on parchment (Austin, 2026-11-04), so the Ledger skin turns the shadow off and the Plain skin keeps it. If the font face itself is still unwelcome, a font choice can be added in Settings.

## D-039 The per-character sharing button is a switch
It reads "Turn off all sharing for this character" while any tracker shares, and "Turn on all sharing for this character" once none do. The master "Pause all sharing" toggle stays separate.

## D-040 Table columns fit the window
Column widths come from `UI/Layout.lua`. Columns stretch up to 1.6 times their natural width on wide windows and shrink down to 0.7 times on narrow ones. Below that, columns are dropped from the right, so Skill-ups goes first, then Kills, then Deaths, and the name column always stays. Tables with row buttons (Friends: Block) keep an 80-pixel column for the button. Austin saw columns past the window edge and Block covering "Updated".

## D-041 Resizing redraws at most every 0.1 seconds
While the corner grip is dragged, size changes only mark a redraw as pending. A redraw then happens at most every 0.1 seconds (10 per second, which Austin preferred over 0.35), plus once when the grip is let go. Redrawing on every size change made resizing laggy.

## D-042 The window opens on Me
Opening the window without naming a tab (`/fl`, a minimap left-click, the addon menu) always shows Me. "Open on the last tab I used" in Settings > Appearance (off by default) changes that. Minimap right-click and the Options page still go straight to Settings.

## D-043 Welcome panel after the loading screen
The welcome panel is queued 3 seconds after the first `PLAYER_ENTERING_WORLD` instead of at `PLAYER_LOGIN`. At login it never appeared for Austin on retail, though `/fl welcome` worked. The likely (unconfirmed) cause is that windows which close with Escape are closed while the world loads. If that event cannot be registered, a 3-second timer from login is used instead.

## D-044 Welcome panel at every load, with an opt-out box (replaces the show-once rule of D-037)
At Austin's request, the welcome panel shows after every loading screen (login and `/reload`) while "Show the welcome panel every time I log in" is ticked. It is ticked by default, and the box is on the panel and in Settings > Notices. Its sharing button is now a switch ("Turn off all sharing" / "Turn sharing back on"), like the per-character one. It probably never appeared before because pressing a button after `/fl welcome` had marked it as seen.

## D-045 Peers are friends only, identified by BattleTag or Name-Realm
Battle.net friends are `bn:<BattleTag>`, shown under the BattleTag's name part (the account's real-ID name is never used). Character friends are `ch:<Name-Realm>`. A character friend who is also a Battle.net friend's current character is handled as the Battle.net friend. Messages from anyone else are ignored, except party NAME notes and your own `/fl commtest` whispers.

## D-046 "Pause all sharing" still says hello
While sharing is paused, HELLO announces no characters and no DATA is sent. The client still greets friends and asks for their data, so their ledgers keep arriving. If you would rather go fully silent, that is a small change.

## D-047 Played and active time travel with any shared tracker
Time has no tracker of its own. Played and active seconds are shared whenever the character shares at least one tracker, and not at all when it shares none.

## D-048 Friends' data is theirs
For each day, level and session a friend sends, their version replaces ours. Data older than 90 days is pruned on arrival. A friend's ledger stays visible while they are offline, with "last updated".

## D-049 Compare overlay on aligned charts only
Compare draws paired bars, one character on the left and the other on the right, with a text legend and a tooltip giving both values. It works on Time per level (aligned by level) and Quests per day (aligned by date). Per-session charts have no shared x axis, so the overlay says it doesn't apply there.

## D-050 Friend milestone notices every 10 levels
A notice appears when a friend's character crosses a multiple of 10 between two syncs ("Bob (Bob) reached level 20!"). There is no notice the first time a character is seen. The "Friend milestones" option in Settings > Notices turns them off.

## D-051 Gentle default rate
The send queue allows 2 messages a second, in bursts of 4, with 200-byte pieces, until in-game tests show what the clients really allow. `/fl comms size N` changes the piece size.

## D-052 Own release script instead of the BigWigs packager
The BigWigs packager names the package from a TOC in the repository root, and its `move-folders` only rearranges folders inside the package. This repo keeps the addon in `FellowshipLedger/` (the layout from the brief), so `tools/build_release.py` builds the zip itself. It holds one `FellowshipLedger/` folder plus `LICENSE.txt`, and fails if the tag and the TOC versions differ. It also uploads to CurseForge's upload API with `CF_API_KEY`. The CurseForge game versions it attaches are set in `tools/release.config.json`. `.github/workflows/release.yml` runs it on `v*` tags and creates the GitHub release. `ci.yml` runs the tests, the verification-doc check and a test build on every push. `.pkgmeta` remains, explaining this.

## D-053 Message size stays at 200 bytes
`/fl commtest` showed whispers up to 255 bytes arrive on retail. The default piece size stays at 200 bytes until Battle.net game data (`SendGameData`), which has no documented limit, is measured with a second client. `/fl comms size 255` raises it.

## D-054 The name "Fellowship Ledger" looks free
A web search on 2026-11-04 found no CurseForge addon called "Fellowship Ledger". The nearest names are "Fellowship" (group auto-invite), "Asgard's Guild Fellowship" and several "... Ledger" addons (Alt Ledger, Warband Ledger, Artisan Ledger, Argent Ledger). CurseForge's own project-creation page is the final check.

## D-055 0.x versions are pre-releases
At Austin's request, v0.1.0 ships before the Forever verification and the two-client test, as a pre-release. Every 0.x version (and any version with a `-suffix`) becomes a GitHub pre-release and a CurseForge "beta". 1.0.0 will be the first full release.

## D-056 Public history uses the GitHub noreply address
Before the first push, the local history was rewritten so author and committer emails are the GitHub noreply address for TankerALane, and this repo's git config uses it from now on.

## D-057 Notable items come from your own loot window
When the loot window opens, `GetNumLootItems`, `GetLootSlotInfo` and `GetLootSlotLink` are read, and green (quality 2) or better items are noted. An item counts only once its slot is taken (`LOOT_SLOT_CLEARED`), so items left behind do not count, and currencies are skipped. Group need/greed rolls are not covered. Retail showed that `ITEM_PUSH` carries only a bag slot and an icon, so it cannot be used. The tracker status is "unverified" until the loot functions pass `/fl verify` (they are on the list).

## D-058 "What killed you" from the death recap, never from chat
One second after `PLAYER_DEAD`, the newest death recap is found by probing `C_DeathRecap.HasRecapEvents(id)` upward from the last one seen (IDs count from 1 each UI session). The killing blow is the recap event with the latest timestamp. If its source or spell is a secret value, the death is stored as "the game hides what killed you", never guessed. `x:death.recap` in `/fl verify` checks this after a death.

## D-059 Friends' quest chains travel with the Quests share switch
Each character keeps a snapshot of the chains it is on (`char.chains`), refreshed at login and after quest-log changes. DATA carries them only when the character shares Quests. The Quest chains view lists chains friends are on that you are not on and whose first quest you have not completed (`C_QuestLog.IsQuestFlaggedCompleted`), with where the chain begins (first quest and zone) when known.

## D-060 Retail TOC also declares 12.1.7
The Mainline TOC lists `## Interface: 120105, 120107`, and the release attaches CurseForge versions 12.1.5 and 12.1.7, so the addon is not flagged out of date when retail patches. Several installed addons already declare 120107.

## D-061 The Questie hint shows only when Questie is missing
A bug made the "install Questie" hint show even with Questie loaded: it compared Questie's state with a value it never takes. It now shows only when Questie is not installed.

## D-062 Names are compared without spaces or case
On Forever, `/fl commtest` whispers to yourself arrived but were dropped as "not a friend", because the sender's name did not exactly match the character key. Realm names can be spelt "Some Realm" or "SomeRealm" depending on the API. `Friends.IsSelf` now ignores spaces and case, and treats a sender with no realm as being on your own realm. If a test whisper is still rejected, the commtest report shows both spellings.

## D-063 Character names in any form (Forever)
On Forever, `CHAT_MSG_ADDON` names the sender "Name Realm", with a space instead of a hyphen, and `GetNormalizedRealmName` returns an internal ID (`CAMWOWUS1Realm3PvE`) rather than the realm's name. Names are now parsed from "Name-Realm", "Name Realm" or "Name", and compared without spaces or case. Your own realm comes from your character key (`UnitFullName`). Battle.net characters use `realmDisplayName` when it is present. Character friends are whispered by the exact name the game lists.

## D-064 Forever characters have a first and a last name
The `/fl friends` report showed Battle.net characters on Forever as "Ned Row" with the realm separately as "CAMWOW US2 Realm 5 PvE", and Austin confirmed that Forever characters have first and last names. So on Forever `UnitFullName` returns the first name and the last name in its name and realm slots, and the "Name Realm" sender in D-063 is really "First Last". Character keys stay "First-Last" (the same shape as retail's "Name-Realm"), so no saved data moves and every path builds the same key: your own key, addon-message senders, Battle.net `characterName` and character friends. Only the display changes: on Forever a character's `display` is "First Last". The real realm (an internal ID) is not part of the key. Two Forever characters with the same first and last name on different realms would share a key; whether Forever allows that is not known.

## D-065 A failed send fails one message, not all of sharing
Sends went through `Compat.Call`, which disables the whole feature when a call errors. One failed `C_BattleNet.SendGameData` (for example to a game account that just went offline) switched sharing off until reload, so messages sat waiting. Sends now disable sharing only when the API is missing; an error fails that message and is shown by `/fl comms`.

## D-066 Project 0 means 'not reported', so those friends are messaged
On Forever, `/fl friends` showed several Battle.net friends in WoW with `wowProjectID` 0 and no character name, including one known to be playing Forever. Friends on retail showed project 1 with a character, so 0 is not another game. Friends with project 0 are now messaged and listened to like friends on our project. Data still never mixes: each flavor has its own prefix and flavor code, and a client on another flavor ignores the message.

## D-067 Death recaps work on Forever (correction)
A first reading of the 20:34 verify report concluded that Forever keeps no death recap, and `/fl verify` was changed to say so. That was wrong: the only death before that report happened before the last reload, and recap IDs start over at each reload. The Me tab then showed "Died 11-04 20:35 to Vile Fin Minor Oracle (Lightning Bolt)", so on Forever the recap exists and its killer and spell are readable. The verify change was reverted.

## Result 2026-11-04: sharing works on Forever
With 0.2.3, Austin and a Battle.net friend on Forever shared ledgers both ways. The friend's game account was one the game reports with project id 0 and no character (D-066). This confirms on Forever: `C_BattleNet.SendGameData` delivery, `BN_CHAT_MSG_ADDON` with the sender's game account ID as the fourth argument, chunk reassembly, HELLO, REQUEST and DATA, and the merge into the Friends tab. Character-friend sharing by whisper is still untested with a second player (whispers to yourself work).

## D-068 Workflows run on ubuntu-24.04
GitHub noted that `ubuntu-latest` moves to Ubuntu 26 from 2026-10-19. The workflows only need LuaJIT, Python 3 and `gh`, so they are pinned to `ubuntu-24.04` to keep releases predictable. Move to a newer image deliberately, with a test run, before 24.04 is retired.


## D-069 Update notice comes from friends' versions
An addon cannot reach CurseForge, so the only signal is the version a friend sends in HELLO. When it is a newer `x.y.z` than ours, one chat line per session says so; the friend's header on the Friends tab says "old version" when theirs is older. A version only changes in the release commit, which is published to CurseForge minutes later, so builds being tested still report the last released number and never cause a notice. The wording says "when it shows there" to cover CurseForge's review delay. Anything that is not plain `x.y.z` (a test build, or nonsense from a peer) is ignored.

## D-070 Class colors: our own table, made readable per skin
Names on the Me and Friends tables use class colors (Settings toggle, on by default). The colors are our own copy of the usual values, keyed by the class token, so no game table (`RAID_CLASS_COLORS`) has to be verified on Forever. On each skin a color is moved toward black (parchment) or white (plain) just until it reaches 4.5:1 contrast with the background: priest white becomes grey (#666666) on parchment, rogue yellow a dark olive gold. A unit test checks every class on both skins.

## D-071 Removing characters you no longer play
The addon cannot detect a deleted character: it does not run at character select, and addons get no list of the account's characters. Austin chose (2026-11-05) a Remove button plus a prompt. The Remove button sits in a character's expanded row on the Me tab and asks for confirmation; it is never offered for the character you are on. The prompt appears on a character the ledger has never seen and lists characters not played for 30 days. "Done" marks the rest as kept (`keep = true`) so they are not asked about again; "Don't ask again" sets `askStale = false` (Settings can turn it back on). It waits up to a minute for the welcome panel to close. Removed keys are kept in `db.removed` for 90 days and sent with HELLO as `x` records, and friends on 1.0.1 or later delete that character. Logging into a removed character again starts a fresh record, clears it from `db.removed`, and the usual restore prompt offers that character's own backup.

## D-072 Aged parchment, and outlined class-colored names
Austin wanted a darker parchment that still contrasts with black text and class colors. Those pull in opposite directions (a darker tan is closer to black, and bright class colors must be darkened more on any tan), so options were shown side by side in a browser preview. He chose "aged parchment": background `C9AF7C`, text `1E140A`, labels `4A3308` (text 8.5:1, labels 5.6:1), with class colors still darkened to 4.5:1 as in D-070. WoW's fonts have no bold, so names get the game's thin OUTLINE font flag instead, only in the name cell of rows that are class-colored. A unit test checks every text role on every skin.

## D-073 Ledger becomes dark leather (replaces D-072)
In a browser mock-up of D-072 (aged parchment with outlined, darkened names) Austin found the names unreadable, and chose option D from the comparison: dark leather. The "Ledger" look (the default, so everyone gets it) is now background `2B1E12`, text `F1E4C3`, labels and headings `E0B34A`, good `7FD08F`, bad `FF8A70`. Class colors need almost no adjustment on it (only Shaman, Death Knight and similar dark colors are lightened slightly, D-070). The name outline is removed. The 1.0.0 light look stays as a third choice, "Parchment". Drop shadows now follow how light the background is, not the skin name, and the non-colorblind graph palette has a light-on-dark set for dark skins. Unit tests check text contrast on every skin.

## D-074 Ledger stays the light default; dark leather becomes "Leather" (revises D-073)
Before release Austin decided the default should stay the parchment look everyone has used since 1.0.0, with dark leather as an option. Settings offers Ledger (light parchment, the default and the internal key `ledger`, so saved 1.0.0 settings are untouched), Leather (the D-073 dark look, key `leather`) and Plain. The short-lived `parchment` key from development builds is mapped back to `ledger` when settings load.

## D-075 Character details: summary card or list
The opened character on the Me tab was a run of sentences (one per level, then deaths and loot). From browser mock-ups Austin chose a summary card (default) with a list layout as a Settings choice ("Character details: Card / List"). Both show, newest first with column headers: the last 10 levels (Level, Active, Played, Zone), the last 5 deaths (When, Killed by, Their lvl, Your lvl, Zone) and the last 5 notable loot (When, Item in its quality color, Quality, Zone). Each list has a Show all (N) button that becomes Show less; the state is per character and per list until reload. The card adds a summary line: levels recorded, average, fastest and slowest (partial levels left out) and deaths in 90 days (deaths and loot are kept 90 days). Both layouts are built in a pure module (UI/DetailModel.lua) as "grid" lines that UI/Table.lua draws, so scrolling stays line-based. The death recap has no level, so at PLAYER_DEAD the target's name and level are noted and kept only if the recap's killer has that name (-1, skull level, shows "??"; otherwise "?"). That uses UnitExists, UnitName and UnitLevel on "target" through Compat under its own feature name, so a failure turns off only the killer level; check `x:death.killerlevel`.

## D-076 Level arrow image, and spacing in the character card
The typed "->" in "9 -> 10" looked poor in the game font, so levels use our own arrow image (`media/level-arrow.tga`, drawn by `tools/make_sort_arrow.py`) inline with the text's `|T...|t` escape, tinted to the skin's text color. The card gets a blank line before the summary and before the Recent levels / Recent deaths headings, matching the one before Notable loot (Austin's in-game check, 2026-11-05). Austin then asked for the space above the summary to be half as tall, so table lines may carry a `height` (UI/Table.lua places lines by accumulated height; scrolling is still by line). Dates in the card and list read `11-04, 20:35`.

## D-077 Killer level from recent targets
Austin's first Forever test (2026-11-05): he was targeting the elite that killed him and its level showed, but none was saved. The likely cause is that the target is already cleared or changed when PLAYER_DEAD fires. Now every PLAYER_TARGET_CHANGED notes the target's name and level in memory (not saved, dropped after 5 minutes), and at death the killer's level comes from the current target, else from a recent target with the recap's killer name. Same Compat feature (`killerLevel`). `/fl verify` now also says what the target was at death, the recap's source name and how the level was matched, so a name mismatch would show.

## D-078 Quest chain drop-downs
Austin asked for drop-downs on the chains he is on: the quests before and after, what they need, and where they start. After a browser mock-up (Ledger and Leather side by side) he approved this layout. It stays in the Me tab's Quest chains view. Each chain is one clickable line (name, step, zone). Opened, it shows a box with these columns: done check (our own `media/check.tga`) or in-log arrow, #, Quest, Lvl, Req (red when above your level) and Starts at (NPC and zone, "item: X", or "in your quest log"). Your step is shaded. The box shows 2 quests before and 3 after your step, with Show all, then "Also requires" (prerequisites outside the chain, from Questie's preQuestGroup and preQuestSingle) and "Friends on this chain" (from friends' shared chain snapshots, D-059). Hovering a quest shows where it starts and where to turn it in. Friends' chains you have not started open the same way, with a "Pick up next" line for the first quest you have neither done nor have in your log. A party-member view was considered and left out: Questie already shares progress in a party, and the ledger only hears from friends.
Data: Questie's internal QueryQuestSingle (name, questLevel, requiredLevel, startedBy, finishedBy, preQuestGroup), plus QueryNPCSingle, QueryObjectSingle and QueryItemSingle (name, spawns). The zone is the spawns zone with the most points, named with C_Map.GetAreaInfo. Everything is guarded like D-033 and cached for the session. Done means C_QuestLog.IsQuestFlaggedCompleted; in your log comes from the quest log already read. On retail, chains from game data list their quests, but without Questie there are no levels or starters. Check `x:questie.details`. The model is pure (UI/ChainModel.lua; details in Core/QuestChainLogic.lua). Table lines gained `shade`, and the table can hide its column headers.

## D-079 NPC coordinates in the quest chain drop-downs
Austin asked for the starting NPC's coordinates. Questie's NPC and object spawns already hold them: `{ [zoneID] = { { x, y }, ... } }` in map percent, -1 inside instances. The ledger shows the first spawn point in the chosen zone (the zone with the most points, D-078) as "Name, Zone (56.3, 47.6)", in the Starts at column and in the tooltip. The column was widened (Quest .33, Starts at .44). Without Questie there is no other source: the game has no API for where an NPC stands, so the only alternative would be shipping our own NPC database, and keeping that up to date is the job Questie does. `x:questie.details` now prints the coordinates.

## D-080 Flight paths: count the discovery message as well
Flight paths were counted only by comparing the known taxi nodes each time the flight map opens. The first time on a character, every node was saved as a baseline and not counted, so a path discovered on that first visit was lost. Austin reported a discovered flight path on Forever, and `/fl verify` had no flight-path line to show what happened. The tracker now also watches UI_INFO_MESSAGE for the discovery text, recognised by its error name `ERR_NEWTAXIPATH` (GetGameMessageInfo) or the client's own `ERR_NEWTAXIPATH` string, as zone discoveries are (D-025). It counts the path once, whether the message arrives before the map opens (the node at `Enum.FlightPathState.Current` is then not counted again, and is not a baseline) or after it (a baseline node is turned into a counted one). Without the message the map comparison still counts new nodes after the first visit. New checks: `ERR_NEWTAXIPATH` and `x:flight.paths` (known, counted, and whether the message and the map were seen this session).

## D-081 Character detail views: Quests, Gold, Kills, Professions, All completed
Austin asked where players can see kill details, skill-ups, gold details and completed quests. The data was recorded but only totals were shown. After a browser mock-up he approved views inside an opened character on the Me tab: a row of tab buttons (Overview, Quests, Gold, Kills, Professions, All completed) at the top of the card. Overview is the D-075 card or list. The range buttons apply to the other views. The tab is remembered per character until reload.
- Quests: the 30-day turn-in log, newest first, 10 with Show all. Turn-ins now save the zone, and older entries take the quest's zone from Questie.
- Gold: per-day `money_<source>` values are net per source (D-011, D-021), so the view shows in, out and net totals and the net per source with a bar for its share of the gains. In and out per source are not recorded.
- Kills: kills by creature type were all-time only. From now on they are also counted per day as local day fields `killType:<type>`, which the share codec ignores (it only sends known fields). "All" uses the all-time table, so older kills still show there.
- Professions: rank and max, a progress bar, points gained in the range (from each profession's history), and when opened the last 10 points with the active time each took, the slowest marked.
- All completed: the game's completed-quest list (`C_QuestLog.GetAllCompletedQuestIDs`, or `GetQuestsCompleted`) for the character you are playing, grouped by Questie's zone for each quest, with class, profession and other non-zone quests last. Without Questie the quests show by number. Unverified on Forever: check `x:quest.completed`.
Lines come from the pure UI/StatsModel.lua. Table grid lines gained bars (`bar = fraction`) and buttons that fill their slot and show as selected.

## D-082 All completed leaves out hidden game quests
Forever's verify report (2026-11-05) showed C_QuestLog.GetAllCompletedQuestIDs works (110 quests; GetQuestsCompleted is missing there, so it stays only a fallback). The sample quest, 99582, had no name or zone in Questie: very high IDs like this are the game's hidden tracking quests, which the server marks completed. With Questie loaded, quests it does not know are left out of All completed, and the summary says how many ("N hidden game quests not listed"). Without Questie nothing can be named, so every quest shows by number. `x:quest.completed` now samples a named quest and reports how many have no name.

## D-083 Friends' characters open like your own; profession ranks are shared
Austin asked whether more friend data could be shown, like the Me tab. Friends already sent much more than the Friends table showed: every day total (played, XP, deaths, kills with rare and elite, skill-ups, zones, reputation, flight paths, achievements, loot counts, party level-ups, gold in, out and by source), level times, sessions and chains. A friend's character row now opens with the Me tab's tabs except All completed (the game lists only your own): Overview (summary, recent levels with Show all, and totals for the range), Quests (counts and the chains they are on; quest titles are not shared), Gold (the same view as yours), Kills (totals; creature types are not shared) and Professions. Each character's share mask decides what is shown; parts it does not share say "not shared" instead of a misleading zero. The table gains Played, Deaths, Kills and Skill-ups columns.
Austin also wanted to see where friends are on their professions. Only the skill-up count was shared, so DATA gains a record `p,<key>,<name>,<rank>,<max>,<lastAt>` under the Professions share switch (no history). Older receivers ignore unknown record types (Codec.DecodeData has no fallback branch), so this is safe to send to friends on 1.0.x and 1.1.0. A receiver keeps the set while the sender shares Professions and clears it when it stops; with none received, the view says the friend's version does not send ranks yet. Fake friends now share everything so `/fl fake` previews every view.

## D-084 Column headers explain themselves; no dungeons shows "-"
Austin found "0/0" under Dungeons unclear but did not want the table more crowded. Instead of a wider label, hovering any column header on the Me and Friends tables shows what it counts (Dungeons: "completed / entered ... in the chosen range"). The text comes from `COL_TIP_<column>` strings, and the table shows it only when one exists. The Dungeons cell shows "-" when no dungeon was entered, so the common empty case is no longer a bare fraction.

## D-085 Dungeon completion: retry the journal, look it up by name, repair old runs
Austin's Ragefire Chasm run on Forever (2026-11-05) showed 0/1: ENCOUNTER_END recorded all four bosses, but the run had no `lastBossID`, because the journal lookup on entry (C_Map.GetBestMapForUnit, then EJ_GetInstanceForMap) returned nothing. Either the map is not known yet while loading in, or Forever's journal does not map dungeons. Now the lookup is retried every tick (30 s) for up to 10 tries, at ENCOUNTER_START and on a boss kill. If the map gives nothing, the dungeon is found by name in the journal's instance lists (EJ_GetNumTiers, EJ_SelectTier, EJ_GetInstanceByIndex), which also works after the run. At login, saved runs without a boss list are looked up once by name, and a run whose last boss is among its kills is marked completed and counted on the day of that kill. The journal calls now use Compat.Try, so a missing journal function no longer turns off the whole dungeon tracker. `x:dungeon.journal` reports the newest run and what the journal gives for it. No boss list is shipped with the addon: if Forever's journal has no data at all, runs stay "entered" and the check says so.
Follow-up (same day): the next Forever report still found nothing ("journal by name: nil"), though EJ_GetNumTiers, EJ_SelectTier and EJ_GetInstanceByIndex all exist. ForeverDungeonJournal (another Forever addon Austin uses) matches journal names loosely and reads the encounter's 3rd value, which suggests names differ slightly and the 7th value (dungeonEncounterID) may be empty there. So names now match loosely (either contains the other, any case), both lists (dungeons and raids) are searched, the last boss's name is kept with its ID, and a kill completes the run when either matches. The repair runs again for runs an earlier version already tried. `x:dungeon.journal` now lists how many instances the journal holds, the first few names, and this dungeon's bosses with both IDs.

## D-086 Our own list of each dungeon's final boss
The third Forever report (2026-11-05) showed "journal: 0 instances": WoW Forever's encounter journal holds no dungeons, so the game cannot say which boss ends a run (D-085's journal lookups stay for clients where it works). Austin chose a list shipped with the addon: Core/DungeonBosses.lua maps each dungeon to its final boss name(s), matched loosely against the instance name, and a run completes when ENCOUNTER_END reports one of them. Dungeons with several wings or ends under one instance name list each wing's final boss (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire). The Classic names were checked against ForeverDungeonJournal 1.6.7's "Final boss" notes (read, not copied); Ragefire Chasm's final boss on Forever is Bazzalan, the last of Austin's four kills. Forever's own dungeons that are open (Hall of Thanes, Ruins of Lordaeron, City of Dalaran, Excavation Site: Wetlands) are listed; those still "coming soon" are not and must be added when they open. The repair (version 3) runs again so earlier runs whose final boss died are completed. `x:dungeon.journal` shows what the list says for the newest run.

## D-087 Share the quest log, and work out friends' chains on the receiving side
Austin's saved data (2026-11-05) showed that all three friends (DrowBear, Romadom, Hamlet; four characters, versions 0.2.2 and 0.2.3) share Quests but send no chains. Their characters refresh the chain list on every quest-log change, so the likely reason is that they have no Questie: on WoW Forever the game has no quest-line data, so without Questie a character cannot tell which chain it is on. Austin wanted his ledger to work fully when friends only run Fellowship Ledger. DATA now also carries the quest IDs in the log (`o,<id>,...`, with the Quests share switch). The receiver works out chains from them with its own lookups (game data, then its own Questie) in QuestChains.FriendChains, and adds them to the chains the friend sent (sent chains win). The result feeds "Chains your friends are on", "Friends on this chain" and a friend's Quests tab, cached per character until its log or the receiver's Questie state changes. Older receivers ignore the record. A friend with Questie still sends their own chains, which also helps receivers without Questie.

## D-088 /fl shots takes the addon-page screenshots
Austin asked for screenshots of every tab, each in a different skin, with at least one character opened, one card and one list, and made-up names. `/fl shots` turns on the fake data set (if it was off), sizes the window to 1060x640, and takes six pictures with the game's Screenshot function, 1.5 s apart: Me with a character opened as a card (Ledger), the same as a list (Leather), Friends with a friend's character opened (Plain), Graphs (Ledger), Settings (Leather) and Quest chains (Plain). While it runs the fake-data banner and the Friends status line are hidden, and Settings shows a made-up character instead of the real one. Quest chains still lists the real character's quest log (game quest names only), since chains are read from the game. Me and Friends use the All range (Today is often empty), the Quest chains picture opens the longest chain you are part-way through, and Settings shows the character's name without the made-up realm. Afterwards skin, layout, ranges, tab, window size and fake-data state are put back. The window's place on screen for each picture is saved in `db.dev.shots`, and `tools/crop_shots.py` cuts the pictures down to the window after a /reload writes the saved variables.


## D-089 Mark the character a friend is playing
Austin wanted to keep seeing all of a Battle.net friend's characters (each still updates) but to see which one they are on. Friends.Refresh already reads the game account's characterName from Battle.net to route messages, so it now also stores it on the friend record (`playing`, cleared when they go offline). The Friends tab marks that character "(playing)" in the "good" color, lists it first under the friend when no column sort is chosen, and its tooltip says "Playing this character now" instead of "Last played". Nothing new is sent, so it works with friends on any version. Names are compared without spaces, hyphens or case, because Battle.net's name and our character key can differ in those (Forever: "First Last" against "First-Last"). Character-only (whisper) friends get the same mark when online, as their peer carries the character too.
