# Fellowship Ledger

*A ledger of your characters' adventures, shared with your fellowship.*

Fellowship Ledger quietly records what each of your characters does: levels and the time each one took, quests, dungeons, gold, professions and more. It shows them in a parchment-and-gold window with tables and graphs. Friends who also run the addon can share their ledgers with you, so you can see what each of you did today, this week or this month.

An addon for World of Warcraft. It supports **WoW Forever** and **retail**, and keeps their data completely separate.

> Status: **1.0.0**. Verified in-game on retail and WoW Forever, including sharing between two friends on Forever. See [CHANGELOG.md](CHANGELOG.md).

## What it tracks

| Tracker | What you see |
|---|---|
| Levels | Time per level as `1 -> 2: 10m 23s (total 14m 02s)`: active time (idle stretches over 5 minutes removed) and logged-in time; XP per hour; the zone where you levelled |
| Quests | Every turn-in (kept 30 days) and daily totals (kept 90 days); quest chains: "step X of Y" from the game's data, or from Questie; chains your friends are on that you haven't started |
| Dungeons | Entered vs completed (last boss killed), duration, deaths, group make-up (class and role only) |
| Gold | Net per session, split into loot, vendor, quest, mail, auction and other |
| Professions | Skill-ups, time to each point, current rank |
| Extras | Deaths and what killed you, notable loot (green or better), zones discovered, reputation gained, kills (rare, elite, creature type), flight paths, achievements, party level-ups |

Every tracker has its own **Track** and **Share** switch for each character, and all are on by default.

## The window

Type **`/fl`**, or click the minimap button.

- **Me:** your characters for Today, 7 days, 30 days or All, with faction and class-colored names. Click a column to sort, and click a character for a summary card: average, fastest and slowest level, its recent levels, deaths (with your level and the killer's) and notable loot, each with Show all, and a **Remove** button for characters you no longer play. Settings can show it as a list instead. Buttons along the top of the card switch to **Quests** (turn-ins with XP, gold and zone), **Gold** (in, out and net by source), **Kills** (by creature type, rare and elite), **Professions** (rank, progress and the time each recent point took) and **All completed** (every quest the character has completed, by zone). The **Quest chains** view shows where you are in each chain in your quest log; click a chain for its quests, their levels, and who starts each one, where, with map coordinates (from Questie).
- **Friends:** friends who run the ledger, grouped under their Battle.net name, sortable by any column; hover a character for details, or click it to open it like your own: their levels, totals, gold by source, kills, quest chains and profession ranks (whatever they share). **This week** gives a summary, and **Sync now** shares right away. If a friend runs a newer version, you get one reminder to update.
- **Graphs:** levels per session, time per level, quests per day, gold per session and XP per hour, with tooltips. Pick a character, and **Compare** with any other, yours or a friend's, from drop-downs grouped by friend.
- **Dungeons:** every run of your characters (when, how long, bosses, deaths, who was with you by role, completed or not), opening to its bosses with the minutes after entering each died; a summary per dungeon with the best and average time; and your friends' dungeon totals. A run counts once you are inside 5 minutes or a boss dies.
- **Settings:** tracking and sharing switches, the Ledger (parchment), Leather (dark) or Plain look, text size, scale, colorblind-safe colors (on by default), notices (your level-ups and session summary; friends reaching level 10, 20, ... and the level cap, finishing a quest chain, clearing a dungeon, profession milestones), the block list and recommended addons.

### Screenshots

These use the made-up preview data from `/fl fake`.

| | |
|---|---|
| ![Me tab: characters and time per level](docs/screenshots/fl_me.png) | ![Friends tab: friends grouped by Battle.net name](docs/screenshots/fl_friends.png) |
| **Me:** your characters, with time per level | **Friends:** grouped under their Battle.net name |
| ![Time per level, compared with a friend's character](docs/screenshots/fl_graph_tpl_compare.png) | ![Quests per day](docs/screenshots/fl_graph_qpd.png) |
| **Compare:** time per level next to a friend's character | **Quests per day** over the last 30 days |
| ![Gold per session](docs/screenshots/fl_graph_gps.png) | ![XP per hour](docs/screenshots/fl_graph_xph.png) |
| **Gold per session:** losses below the line | **XP per hour** per session |
| ![Settings: track and share per tracker, appearance, notices](docs/screenshots/fl_settings.png) | |
| **Settings:** Track and Share for each tracker, the look, notices and the block list | |

## Commands

| Command | What it does |
|---|---|
| `/fl` | Open or close the ledger |
| `/fl summary` | Your last session's summary (`/fl summary now` for this one) |
| `/fl export` | All your data as text you can copy and keep |
| `/fl sync` | Share with online friends now |
| `/fl fake` / `/fl fake off` | Preview every view with made-up data (never shared) |
| `/fl welcome` | Show the welcome panel |
| `/fl restore` | Restore this character from its backup |
| `/fl verify`, `/fl test`, `/fl commtest`, `/fl comms`, `/fl probe`, `/fl debug` | Diagnostics |

## Privacy

- The ledger **never reads chat or the combat log**, and makes **no network connections**.
- Sharing goes only to your Battle.net and character friends who also run Fellowship Ledger on the same game client, and only for the trackers each character allows. One click pauses all sharing.
- Blocked players are never sent anything and never shown.
- Party members appear by name in your dungeon records only if they run the ledger and opted in.
- A backup of each character is kept in that character's own saved-variables file.

## Recommended

**Questie** adds fuller quest-chain information, especially on WoW Forever. Fellowship Ledger works without it.

## Development

The repo is laid out in [CLAUDE.md](CLAUDE.md), the design in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the sync format in [docs/PROTOCOL.md](docs/PROTOCOL.md). Tests use LuaJIT: `luajit tests/run_all.lua`. Releasing is covered in [docs/RELEASING.md](docs/RELEASING.md).

## License

MIT, © Decoupled Lane Studio. See [LICENSE](LICENSE). Fellowship Ledger is not affiliated with or endorsed by Blizzard Entertainment.
