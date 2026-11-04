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

**Runtime** modules talk to the game: `Core/Log.lua`, `Compat/Compat.lua`, `Debug/CopyWindow.lua`, `Debug/Probe.lua`, `Debug/Verify.lua`, `Core/Init.lua`.

Planned pure modules: time math (active and total time, idle cut-off, session splitting), daily buckets and retention, aggregation by range, protocol encode/decode and chunking, and graph scaling.

## The Compat rule

Any API that is not verified on both clients is called through `ns.Compat`:

- `Compat.Call(feature, "Path.To.Api", ...)` returns `ok, ...`. If the API is missing or throws, it disables `feature` once with a clear chat message, and later calls return `false` immediately. The rest of the addon keeps working.
- `Compat.Try(path, ...)` does the same without disabling anything. It is for diagnostics.
- `Compat.Has(path)` reports whether a function exists.
- `Compat.IsSecret(v)` and `Compat.Describe(v)` handle Midnight secret values safely.

## Saved variables

`FellowshipLedgerDB` is account-wide. Its top level (schema v1) is `schemaVersion`, `settings`, `characters["Name-Realm"]`, `friends`, `blocklist`, `dev` (diagnostics: persistence probe and event probe) and `verify` (the last report). The full per-character shape arrives in the next step and is documented here then.

`FellowshipLedgerBackupDB` holds the rolling snapshot. Today it holds only the persistence probe.

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
