# Changelog

## 1.2.2 - 2026-11-06

### Added
- `/fl shots` takes screenshots of every tab, in each skin, with made-up data, for the addon page.
- Friends tab: the character a friend is playing right now shows "(playing)" in green, sits first under their name, and its tooltip says "Playing this character now". All their characters are still listed and still update.

## 1.2.1 - 2026-11-05

### Changed
- Friends' quest chains no longer need Questie on the friend's side. Each character now also shares the quests in its log (with the Quests share switch), and your ledger works out the chains with your Questie. A friend without Questie shows up in "Chains your friends are on", "Friends on this chain" and their Quests tab, as soon as they run 1.2.1 or later.

## 1.2.0 - 2026-11-05

### Added
- Friends' characters open like yours: click one on the Friends tab for Overview (their levels, with Show all, and totals for the range: played, active, XP, quests, dungeons, deaths, kills, skill-ups, zones, reputation, flight paths, achievements, notable loot, party level-ups), Quests (counts and the chains they are on), Gold (by source), Kills and Professions. Parts a friend does not share say so.
- Professions now share each profession's name and rank, so friends can see where you are (with the Professions share switch). Friends see ranks once both of you run 1.2.0 or later.
- The Friends table has Played, Deaths, Kills and Skill-ups columns, like the Me tab.
- Hover a column header on the Me or Friends table to see what it counts. Dungeons shows "-" instead of 0/0 when none were entered.

### Fixed
- Dungeons on WoW Forever were entered but never completed: the boss list was not found when you zoned in. It is now retried during the run and looked up by the dungeon's name, and earlier runs where you killed the last boss are marked completed at the next login. WoW Forever's journal has no dungeon data, so the ledger now carries its own list of each dungeon's final boss.

## 1.1.0 - 2026-11-05

### Added
- An opened character on the Me tab has views along the top: **Overview** (the card as before), **Quests** (turn-ins with XP, gold and zone, newest first), **Gold** (in, out and net, and net by source: loot, vendor, quest, mail, auction, other), **Kills** (kills, rare and elite, and kills by creature type), **Professions** (rank, progress, points gained, and each profession's recent points with the active time each took) and **All completed** (every quest the character you are playing has completed, grouped by zone, with names from Questie). The Today / Week / Month / All buttons apply to them.
- Kills by creature type are now also counted per day, and quest turn-ins remember the zone.

### Changed
- Quest chains (Me tab > Quest chains) open into drop-downs. Click a chain for its quests with a check for done and an arrow for the one in your log, each quest's level and the level it needs (red if above yours), and who starts it, where and at which map coordinates. Hover a quest for where to turn it in. Long chains show the two quests before your step and three after, with Show all. Under the list: other quests the chain needs, and friends on the same chain and their step. Friends' chains you haven't started open to the quest to pick up next. The details come from Questie.

### Fixed
- A flight path discovered on a character's first visit to a flight master (since installing the ledger) was saved as already known and not counted. The game's "New flight path discovered!" message is now counted too, once, whether it comes before or after the flight map opens.
- The killer's level was missed when the game cleared your target as you died. Targets from the last 5 minutes are now remembered by name, so the level is found as long as you targeted the killer during the fight.

## 1.0.1 - 2026-11-05

### Added
- Faction column (Horde or Alliance) on the Me and Friends tables, next to Lvl.
- Class-colored character names. On the light Ledger look, colors are darkened just enough to read (priest white shows as grey). Turn them off in Settings.
- Update reminder: when a friend runs a newer Fellowship Ledger, one chat line per session says so. Friends on an older version are marked on the Friends tab.
- The Friends table sorts by any column; each friend's characters stay together under them.
- Hover a friend's character for level, race and class, faction, when they last played, when it was shared, and their addon version.
- Remove characters you no longer play: a Remove button in a character's expanded row on the Me tab, and on a new character a prompt listing characters you haven't played for 30 days. Friends drop removed characters at the next sync (friends on 1.0.1 or later).
- Deaths record the killer's level when the killer was your target when you died (otherwise "?").

### Changed
- Clicking a character on the Me tab opens a tidy summary card: levels recorded, average, fastest and slowest level, then the last 10 levels, last 5 deaths (with your level and theirs) and last 5 notable loot, each newest first with column headers and a **Show all** / **Show less** button. Prefer everything in one column? Settings > Character details > **List**.
- A new **Leather** look in Settings: dark leather with parchment-colored text and gold, so class colors show at nearly full strength. Ledger (parchment) stays the default.
- Sort direction is shown with a small arrow instead of "v" and "^".
- With no friends' ledgers yet, the Friends tab says how many friends are online on this version of WoW.
- Release workflows run on Ubuntu 24.04.

## 1.0.0 - 2026-11-04

First full release. Verified in-game on WoW Forever, the main target: tracking, quest chains with Questie, notable loot, deaths with what killed you, and sharing between friends over Battle.net, including friends that Forever's friends list shows with no character. Retail is verified too, except whether it shows or hides what killed you.

### Fixed
- Friends tab: "1 character", not "1 characters".

## 0.2.3 - 2026-11-04 (pre-release)

### Fixed
- WoW Forever: some Battle.net friends who are playing Forever show in the game's friends list with no character and level 0 (a known Forever friends-list problem), and the game reports their game version as unknown. They were skipped as "another game version". They are now included, so sharing can reach them. Forever and retail data still never mix.

## 0.2.2 - 2026-11-04 (pre-release)

Sharing fixes found while testing with friends on WoW Forever. Everyone sharing should update: friends on 0.2.1 or older may not answer.

### Fixed
- One failed send could switch sharing off for the rest of the session, so messages sat "waiting" and Sync now did nothing. A failed send now affects only that message.
- WoW Forever: characters show their first and last name ("Tarahallow Soldecouple"), for you and for friends.
- The Friends tab no longer draws its empty-state text over "This week".

### Added
- `/fl friends`: what the game reports about each friend and whether the ledger will message them, or why not.
- The Friends tab refreshes itself while open and says what is holding messages back. Sync now says how many friends it greeted.
- `/fl comms` lists anything switched off, the last send error, send results and the online friends it would message.

## 0.2.1 - 2026-11-04 (pre-release)

Verified in-game on WoW Forever.

### Fixed
- WoW Forever: messages from friends and from yourself were ignored, because Forever names the sender "Name Realm" (a space, not a hyphen) and reports realms by an internal ID. Names are now read in any form and compared without spaces or capitals, so sharing works on Forever.
- Character friends are whispered by the exact name the game lists.

## 0.2.0 - 2026-11-04 (pre-release)

Phase 5. Tested on retail; WoW Forever testing still to come.

### Added
- Friends' quest chains: chains your friends are on that you haven't started, and where each begins. Chains are shared only when you share Quests.
- Notable loot: green or better items you take from your loot window, with quality and zone.
- What killed you: the killing blow from the game's death recap, or "hidden" where the game keeps it secret.
- Retail 12.1.7 is declared, so the addon stays current when retail patches.

### Fixed
- The "install Questie" hint showed even when Questie was loaded.
- Graph axes: gold labels no longer wrap (+6g, -2g), and time axes use round steps (30m, 1h, 1h 30m).

## 0.1.0 - 2026-11-04 (pre-release)

First public pre-release. Verified on retail (12.1.5); WoW Forever verification and the two-client sharing test are still to come (see docs/ROADMAP.md).

### Added
- Repository layout, MIT license, docs and tooling.
- Addon skeleton that loads on WoW Forever (`FellowshipLedger_Forever.toc`, interface 16001) and retail (`FellowshipLedger_Mainline.toc`, interface 120105), plus a fallback TOC that only reports an unsupported client.
- `/fl verify`: checks 190 APIs, events and values and shows a copyable report, also saved in `FellowshipLedgerDB.verify`.
- `/fl probe`: counts which candidate events fire, with a few argument samples.
- SavedVariables persistence probe in both saved variables.
- Schema version 1 and a migration function.
- `tools/sync.ps1` (robocopy mirror of the addon folder only), `tools/run_tests.ps1`, `tools/gen_verify_doc.py`.
- Pure-Lua unit tests and runtime smoke tests against a mock WoW API.
- Tracking: sessions, played and active time, per-level times (`1 -> 2: 10m 23s (total 14m 02s)`), XP, quests, gold by source, dungeons (entered/completed, bosses, deaths, party class and role), professions, deaths, new zones, reputation, kills (type, rare and elite), flight paths, achievements, party level-ups.
- Per-tracker Track and Share flags per character, all on by default.
- Per-character backup with a restore prompt, plus `/fl restore`, `/fl export`, `/fl test` and the `/fl debug` event log window.
- Active time now drops a whole idle stretch once 5 minutes pass without activity, so AFK time shows (D-024).
- Real zone discoveries ("Discovered: <area>"); reputation read by faction ID, so gains under collapsed headers count; follower companions are no longer counted as party level-ups; dungeon difficulty is taken from the boss events; quest money is matched by amount.
- `/fl export` adds P lines (per profession: rank, max, points logged), boss count and how a dungeon counted as completed, and the partial-level flag.
- Phase 3: sharing with friends who run the ledger:
  - Battle.net and character friends, flavor-separated, with friends-only messaging.
  - Per-tracker and per-character sharing, honoured on send.
  - The block list.
  - The send queue with a rate limit and retries, holding during combat and boss fights.
  - The Friends tab with real data, a This week summary and Sync now.
  - The compare overlay on Graphs.
  - Friend milestone notices.
  - The dungeon-name opt-in.
  - `/fl sync`, `/fl comms` and `/fl commtest`.
- Phase 2:
  - `/fl fake` preview data.
  - The Friends and Graphs tabs.
  - Totals and a quest-chains view on the Me tab.
  - The Settings tab.
  - Ledger and Plain skins, text size, scale and the colorblind palette.
  - Level-up and session-summary notices, plus `/fl summary`.
  - The welcome panel, the minimap button, the Options page and the addon compartment entry.
  - Questie quest-chain lookup.
- The ledger window (`/fl`) with Me, Friends, Graphs and Settings tabs. The Me tab has ranges, a sortable table and per-level times.
