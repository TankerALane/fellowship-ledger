# Architecture

## One addon, two clients

The repo has one addon folder, `FellowshipLedger/`, with three TOC files:

| TOC | Loaded by | Interface | Loads |
|---|---|---|---|
| `FellowshipLedger_Forever.toc` | WoW Forever | 16001 | the full addon |
| `FellowshipLedger_Mainline.toc` | retail | 120105 | the full addon |
| `FellowshipLedger.toc` | any client that picked neither file | 00000 | a single "unsupported client" message |

Each flavor TOC carries `## X-Flavor: Forever` or `Retail`. At runtime `Compat.Detect()` works out the flavor from the interface number (`Compat/FlavorLogic.lua`) and compares it with the TOC's `X-Flavor`. A mismatch is reported in chat and in `/fl verify`.

### How Forever and retail data stay apart

1. **Saved data.** Each client has its own `WTF` folder (`_forever_\WTF`, `_retail_\WTF`), so the saved variables are separate files.
2. **Network.** Each flavor uses its own addon-message prefix (`FLDGF` for Forever, `FLDGR` for retail). Every payload also carries a one-letter flavor code, and the receiver drops any payload whose code does not match its own flavor (`FlavorLogic.Matches`).

## Namespace and load order

Every file gets `local ADDON_NAME, ns = ...` and hangs its module on `ns` (`ns.Compat`, `ns.Log`, ...). There are no globals except the saved variables (`FellowshipLedgerDB`, `FellowshipLedgerBackupDB`), the slash-command registration and the copy window's frame name, which `UISpecialFrames` needs so Escape closes it.

The load order is in the TOC. `Core/Namespace.lua` loads first and `Core/Init.lua` last.

## Pure and runtime modules

**Pure** modules never touch WoW globals at load time, and their functions take everything they need as arguments. They are unit-tested outside the game. The list lives in `tests/harness.lua` (`PURE_FILES`), and `test_purity.lua` loads each file in a strict environment that errors on any non-standard global.

Current pure modules:

| File | Purpose |
|---|---|
| `Core/Namespace.lua` | `ns`, small utilities (`pack`, `splitCommand`, `sortedKeys`) |
| `Locale/Locale.lua`, `Locale/enUS.lua` | `ns.L` with English fallback |
| `Core/Migrations.lua` | schema version and upgrade steps |
| `Compat/FlavorLogic.lua` | interface number to flavor, prefixes, flavor codes |
| `Debug/VerifyChecks.lua` | the list of things to verify (data only) |
| `Debug/VerifyReport.lua` | builds the verify report text |

Also pure: `Core/Clock.lua` (played and active time), `Core/Days.lua` (date buckets and ranges), `Core/Sessions.lua`, `Core/Format.lua`, `Core/TrackerList.lua` (trackers and Track/Share flags), `Core/Character.lua`, `Core/BackupLogic.lua`, `Core/GoldLogic.lua`, `Core/Export.lua` and `UI/MeModel.lua`.

**Runtime** modules talk to the game:
- `Core/Events.lua`: one event frame, with a pcall around each handler and the debug ring buffer.
- `Core/Store.lua`: the current character, clock, session, day counters, backup and restore.
- `Core/Activity.lua`: activity signals, the 30-second clock ticker and the 10-minute backup ticker.
- `Trackers/*.lua`: one tracker per id in `TrackerList`, each gated by its Track flag.
- `UI/*.lua`: the window and the Me tab.
- `Debug/*.lua`: verify, probe, copy and text windows, the event log and the self-test.
- `Compat/Compat.lua` and `Core/Init.lua`.

Phase 2 adds:
- **Pure:** `Core/SettingsDefaults.lua`, `Core/Summary.lua`, `Core/QuestChainLogic.lua`, `UI/Palette.lua` (skins and graph palettes), `UI/GraphModel.lua` (series and axis scaling), `UI/FriendsModel.lua` and `Debug/FakeData.lua`.
- **Runtime:** `Core/Data.lua` (real or fake data for the windows), `Trackers/QuestChains.lua`, `UI/Widgets.lua` (role-based styling), `UI/Table.lua`, `UI/Graph.lua`, the four tab files, `UI/Toast.lua`, `UI/MinimapButton.lua`, `UI/Welcome.lua` and `UI/OptionsPanel.lua`.

Phase 3 adds `Comms/`:
- **Pure:** `Codec.lua` (wire format, share filter, chunking and reassembly), `Merge.lua` (storing friends' data, milestones, the weekly summary) and `RateLimit.lua`.
- **Runtime:** `Friends.lua` (discovery and peers), `Transport.lua` (queue, send results, receiving) and `Sync.lua` (the HELLO, REQUEST and DATA conversation, the NAME note and `/fl commtest`).

1.8.0 adds (D-114 to D-117):
- **Pure:** `Core/Invites.lua` (who to invite, when last invited), `Core/Bests.lua` (personal records), `Core/DungeonLevels.lua` (level ranges, at-level test), `Core/Goals.lua` (goal suggestions and progress), `Core/Leaderboard.lua` (fastest clears and boss kills, merged across ledgers) and `Locale/enUS_Social.lua`.
- **Runtime:** `UI/InviteDialog.lua`, `Trackers/Records.lua` (keeps bests current), `UI/GoalsWindow.lua` (`ns.SessionGoals`) and `UI/LeaderboardTab.lua`.
- Saved: `db.invites[peerId]` (time of the last invite), `db.bests` and `char.bests`, `char.goals` (this session's goals and progress), `char.goalsSkipDay`.

Friends' data lives in `FellowshipLedgerDB.friends[peerId] = { kind, name, tag, online, lastUpdated, syncedThrough, nameOptIn, characters = { [Name-Realm] = { class, level, days, levels, sessions } } }`, the same character shape the windows already draw. See `docs/PROTOCOL.md`.

Every tracker writes numbers through `Store.Count(field, n)`, which adds them to today's bucket and to the current session at the same time.

Planned pure modules: time math (active and total time, idle cut-off, session splitting), daily buckets and retention, aggregation by range, protocol encode/decode and chunking, and graph scaling.

## The Compat rule

Any API that is not verified on both clients is called through `ns.Compat`:

- `Compat.Call(feature, "Path.To.Api", ...)` returns `ok, ...`. If the API is missing or throws, it disables `feature` once with a clear chat message, and later calls return `false` immediately. The rest of the addon keeps working.
- `Compat.Try(path, ...)` does the same without disabling anything. It is for diagnostics.
- `Compat.Has(path)` reports whether a function exists.
- `Compat.IsSecret(v)` and `Compat.Describe(v)` handle Midnight secret values safely.

## Saved variables

`FellowshipLedgerDB` is account-wide. Its top level (schema v1) is `schemaVersion`, `settings`, `characters["Name-Realm"]`, `friends`, `blocklist`, `dev` (diagnostics: persistence probe and event probe) and `verify` (the last report). The full per-character shape arrives in the next step and is documented here then.

`FellowshipLedgerBackupDB` is **per character** (a different file on disk, see D-016): `{ savedAt, schemaVersion, key, character, settings, persistProbe }`.

Per character (`characters["Name-Realm"]`, shape in `Core/Character.lua`):

| Field | Contents | Kept |
|---|---|---|
| `name, realm, class, race, faction, level` | identity | always |
| `clock` | `{ played, active, last, lastActivity }`, all-time seconds | always |
| `levelStart` | snapshot taken when the current level began | always |
| `levels[to]` | `{ from, to, active, total, at, zone, mapID, xpPerHour, kills, partial }` | always |
| `days["YYYY-MM-DD"]` | counters: `played, active, levels, xp, quests, questsAccepted, moneyNet, moneyIn, moneyOut, money_<source>, dungeonsEntered, dungeonsCompleted, bossKills, deaths, kills, rareKills, eliteKills, skillUps, zonesNew, repGained, flightPaths, achievements, partyLevelUps` | 90 days |
| `sessions[]` | `{ id, start, stop, played, active, levelStart, levelEnd, moneyStart, moneyEnd, counts{...same fields as days} }` | 90 days |
| `questLog[]` | `{ id, title, at, xp, money }` | 30 days |
| `dungeons[]`, `currentRun` | `{ name, instanceID, difficultyID, entered, left, duration, deaths, bosses[], party[{class, role}], completed, completedBy }` | 90 days |
| `professions[skillLine]` | `{ name, rank, max, history[{rank, at, active}] }` | last 300 points |
| `deathLog, zones, reputation, kills, flightPaths, achievements, partyLevels` | extras | 90 days for logs |
| `flags[tracker]` | `{ track, share }`, both default true | always |
| `lastSeen, savedAt` | session split and backup comparison | always |

`Core/Migrations.lua` upgrades older tables step by step. A table from a newer build is left alone, so an older addon never damages newer data.

## Folder map

```
FellowshipLedger/
  Core/      Namespace, Log, Migrations, Init (later: DB, Session, Backup, Time)
  Locale/    Locale.lua + enUS.lua
  Compat/    FlavorLogic (pure), Compat (runtime guard), Unsupported (fallback TOC only)
  Debug/     VerifyChecks, VerifyReport, Verify, Probe, CopyWindow
  Trackers/  (Phase 1) Levels, Quests, Dungeons, Gold, Professions, Extras
  Comms/     (Phase 3) protocol, queue, Battle.net and whisper transports
  UI/        (Phase 1-2) window, tabs, tables, graphs, minimap button, skins
  media/     icon.tga, minimap-icon.tga
```
