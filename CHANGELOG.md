# Changelog

## Unreleased

### Fixed
- **Going out and back in after the last boss stays one run.** A new run now starts only when the dungeon was reset or you are in another leader's dungeon.
- Runs that 1.7.1 joined showed up twice on friends' screens (the joined run and its old second half). The old half is now removed when their data arrives.
- Runs where you went back in after the last boss are joined into that run once at login.
- A run shows **Completed** as soon as the last boss dies, even while you can still go back in, and friends see the clear right away.
- A new run also starts when you go back in under a group leader who was not in the run's group (another leader's copy of the dungeon).
- `/fl verify` shows how the dungeon copy and the group leader are read (for testing). On WoW Forever creature IDs are hidden inside dungeons, so the copy check does not work there; a reset by another player is caught when a boss of the run dies again.

## 1.7.1 - 2026-11-08

### Fixed
- **Dying in a dungeon no longer makes a second run.** Releasing, or going out to repair, and coming back within 30 minutes now continues the same run, with its bosses, deaths and time. Runs already split this way are joined once when you log in. If the dungeon was reset while you were out (a boss you killed dies again), that is still a new run.
- **Resets are caught**, by you or by your group leader: the game's "The Deadmines has been reset." line ends the paused run, so going back in is a new run. The ledger reads only that exact system line; it still never reads player chat.
- Settings no longer says "(not yet confirmed in-game)" next to Dungeons, Reputation, Flight paths and Notable items on WoW Forever, where all four are confirmed. On retail the note stays on Flight paths and Notable items until a retail player confirms them.

## 1.7.0 - 2026-11-07

### Added
- **Quest details**: in Quest chains, click a quest to open it: its objective, where it starts and ends, its levels, and what it gives: XP, money, reputation, the items you choose from and the items you also get (in their quality colors), and when you turned it in and what you got. XP for quests you have not picked up comes from Questie when it is installed. Item rewards show once you have had the quest in your log or seen it at the quest giver (the game only tells addons then); they are remembered for all your characters.
- **While you were away**: friend notices in the first two minutes after login become one notice titled "While you were away", which also lists the levels friends gained ("Cain (Hamlet) went from level 42 to 45").
- Friend notices that arrive together become one ("3 friend notices").
- **Click a friend notice** to open that friend's character on the Friends tab, on the right page (Quests for a finished chain, Dungeons for a clear, and so on). Right click just closes it.
- **A friend joined your ledger**: a notice the first time a friend's ledger says hello.
- **This session** line at the top of the Me tab: time played, levels, quests, dungeons, gold and deaths so far.
- **Tooltip line**: hover a friend's character in the world or in your group and the game's tooltip shows "Ledger: Hamlet's character, 12 quests and 2 dungeons this week".
- **Reward item tooltips**: in an opened quest, each reward item has its own line with its icon; hover it for the game's own tooltip with its stats, as in your bags. Shift-click links it in chat.
- **Boss times**: an opened dungeon run shows when each boss died and how long the fight took, and the clear time. Best is now the fastest clear, and a new **Friends' best** column shows your fastest friend (the faster one in green). Friends on this version share their boss times; hover one of their runs to see them.
- **Friends' deaths and loot**: a friend's Overview now also lists their recent deaths (what killed them, both levels, where) and their blue or better loot, with item tooltips. A new notice says when a friend loots a blue or better item (its own switch). Each follows the friend's Share switches for Deaths and Notable items; greens are never shared.
- Settings > Notices is split into three short groups: how notices show, your notices, and friend notices.
- **You both have this quest**: in Quest chains, a quest a friend also has shows "with Hamlet" (hover for who), and its details list them. A friend's Quests view starts with the quests in both your logs, and their row's tooltip counts them. Uses the quest logs friends already share, so it works with friends on 1.2.1 or later.
- **Shift-click a quest** in Quest chains or in a friend's "In both your quest logs" to link it in chat.
- **Right-click a friend** on the Friends tab to whisper them, or invite the character they are on to your group.
- **Weekly recap**: the first time you log in after the weekly reset (Tuesday morning), a notice shows last week for you and each friend: levels, quests, dungeons and time played. Click it for everyone; the Friends tab's "This week" panel now also has "Last week". It has its own switch under Settings > Notices.
- **Notable loot tooltips**: on an opened character, hover a looted item's name for the game's own tooltip; shift-click links it in chat.
- **Gold total**: the Gold page (yours and friends') now starts with a large "Total gained" (or "Total lost") for the chosen range, and the source table ends with a Net row.
- Settings > Notices: a switch for each of these, plus "Show notices on screen" (turn all on-screen notices off; chat still gets them) and "Also write notices in chat".

## 1.6.0 - 2026-11-06

### Added
- More friend notices, each with its own switch under Settings > Notices: a friend **reached the level cap**, **finished a quest chain**, **cleared a dungeon** (one you have not seen them clear) and a **profession reached 75, 150, 225 or 300**. Like the level notices, none fire the first time a friend's character reaches you. Dungeon clears need the friend on 1.5.0 or later.

### Fixed
- Quest chains: a single quest Questie could not answer (for example one of WoW Forever's own quests) turned the Questie lookup off for the whole session, so no chains showed until a reload. Now that quest just has no chain; only many failures turn it off. `/fl verify` (x:questie.db) lists the chain found for every quest in your log and the last failed query.

### Changed
- Quest chains: one line per quest in your log, named after the quest, with its chain's first quest after it ("The Family Crypt (chain: Speak with Sevren), step 2 of 2"). Before, each chain had one line named after its first quest, so a quest could seem missing, and two quests of one chain shared a line.
- Dungeons tab: your runs now come before your friends' totals, so a long friend list no longer pushes your runs off the screen.

## 1.5.1 - 2026-11-06

### Fixed
- The one-time cleanup of walk-in-and-out dungeon runs (1.5.0) only ran on the character you logged in with, so other characters kept theirs. It now runs on every character at login.
- Dungeons: "With" is now the group at the final boss. Before, it followed the group until you left the dungeon, so people leaving after the last boss dropped out of the run. Someone who joins mid-run still counts, and leaving after the first boss no longer shrinks the group.

## 1.5.0 - 2026-11-06

### Added
- **Dungeons tab**: every run of your characters (when, dungeon, character, time, bosses, deaths, who was with you by role, result), newest first. Click a run to see its bosses in the order they died, with the minutes after entering and the final boss marked. Above it: a summary per dungeon (runs, completed, best and average time, last run) and your friends' dungeon totals (entered, completed, bosses). Today / This week / This month / All and a character drop-down filter it. `/fl shots` takes a picture of it too.
- Friends tab: a **Dungeons** button on a friend's character shows their dungeon totals for the range and which dungeons they ran: when, time inside, bosses killed, deaths and whether they completed it (newest 15). Friends share this from 1.5.0; until then their page says so. Only that is shared: no boss names and nothing about who was in the group.

### Changed
- Much less sharing traffic: Battle.net's frequent "friend changed" events no longer send a hello to every online friend (most of whom do not run the ledger). Only friends who just came online or switched character are greeted then; login, the 15-minute sync, the Friends tab and Sync now still greet everyone.
- Dungeons: a run only counts once you have been inside for 5 minutes or a boss dies. Walking in and straight back out no longer adds an "entered" run, and such runs saved before are removed once (and taken off that day's count).

## 1.4.0 - 2026-11-06

### Changed
- Graphs: the character on show and Compare are now drop-downs. Your characters come first, then each Battle.net friend with their characters under their name, then other friends; Compare has "Compare off" on top. The < and > buttons still step through. Graphs opens on the character you are playing, and the character each friend is playing is marked "(playing)".
- Me tab: the character you are playing shows "(playing)".

### Fixed
- A friend's Professions tab said "Profession ranks arrive once this friend runs Fellowship Ledger 1.2.0 or later" for a friend on 1.2.0 or later whose character has no professions. It now says "This character has no professions." Characters with none now also say so to friends, so a friend who drops their last profession no longer keeps showing it.

## 1.3.0 - 2026-11-06

### Fixed
- The login message now says "/fl" opens the ledger and "/fl help" lists the commands (it said "/fl" for commands).
- "Sync now" (and `/fl sync`) always asks your friends for their latest data. Before, it quietly fetched nothing new if any sync had asked them in the last 5 minutes.

### Changed
- `/fl comms` opens a window you can copy from (Ctrl+A, Ctrl+C), instead of printing to chat. It also shows how many live updates went out since login, and which online friends run the ledger and what they are playing.
- Friends update much faster. The character you are playing sends its changes to friends who run the ledger every minute (only when something changed). The full sync of all your characters stays every 15 minutes. Friends send you these faster updates once they run 1.3.0; older versions still receive yours.
- Friends tab: the "Updated" column is now "Last played": when each character was last played. The character a friend is on shows "now" in green while its data is less than about a minute and a half old, otherwise the time. When their ledger last reached you is still on the friend's header row and in each row's tooltip.

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
