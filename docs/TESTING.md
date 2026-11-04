# Testing

There are two kinds of tests, and they prove different things.

| Kind | Proves | Who runs it |
|---|---|---|
| Unit tests (`tests/`) | the logic of pure modules is right | anyone, outside the game |
| In-game checks (`/fl verify`, the probe, manual checks) | the client really behaves as assumed | Austin, in each client |

A feature counts as done only when both kinds agree.

## Unit tests

They need Lua 5.1 semantics, because WoW runs Lua 5.1. LuaJIT or Lua 5.1 both work. Lua 5.2 and later do not, because the tests use `setfenv`.

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
```

The script finds `luajit`, `lua5.1`, `lua51` or `lua` on PATH and checks the version. It returns exit code 0 when all tests pass, 1 on a failure, and 2 when no interpreter is found.

What is covered today:

- **Purity.** Every file in `PURE_FILES` loads with standard Lua only.
- **Flavor logic.** Interface ranges, prefixes, and that flavor codes never cross.
- **Migrations.** Fresh, repeated, partial and newer-than-known databases.
- **Locale fallback and format strings.**
- **Verify report formatting.** Problems come first, wrapping works, the probe section renders.
- **Verify check list.** Ids are unique and well formed, the combat log and player chat are never probed, every custom check is implemented, and every check is in `docs/API-VERIFICATION.md`.
- **TOCs.** The two flavor TOCs stay in step, every listed file exists, the icon file exists, and versions agree.
- **Runtime smoke** (`test_runtime_smoke.lua` + `wowmock.lua`). Loads the whole addon in TOC order against a small fake WoW API, fires login and logout events, and runs every slash command. Covered: Forever, retail, flavor mismatch, unknown client, the fallback TOC, missing APIs, the persistence probe across a simulated reload, the probe, and that the report never leaks friend names. This proves the code paths run. It does **not** prove the real client behaves like the mock.

- **Tracking smoke** (`test_tracking_smoke.lua`). An end-to-end run against the mock with a controllable clock. It covers:
  - login
  - active and idle time
  - level-ups, including the exact `10m 23s (total 14m 02s)` case and duplicate events
  - XP across a level wrap
  - quest turn-ins with titles and de-duplication
  - gold by source, including late quest money and losses
  - Track off
  - reload vs a new session
  - backup and the restore dialog
  - a full dungeon run with the last boss
  - kills
  - zones, achievements, party level-ups and reputation
  - profession skill-ups with timing
  - every slash command, the Me tab model, and an unsupported client or newer database

Installed interpreter: LuaJIT 2.1 (`winget install --id DEVCOM.LuaJIT`).

## In-game checks

See `docs/API-VERIFICATION.md` for the full procedure. In short: sync, log in, optionally `/fl probe on` and play a little, then `/fl verify` and copy the report. After that, `/reload` and run `/fl verify` again to test persistence.

## Syncing to the game

```powershell
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -DryRun          # always look first
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -Target Forever
```

The script mirrors only `FellowshipLedger\` into `<AddOns>\FellowshipLedger`. It refuses any destination that does not end in `\Interface\AddOns` or does not exist.
