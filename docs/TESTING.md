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

## In-game checks

See `docs/API-VERIFICATION.md` for the full procedure. In short: sync, log in, optionally `/fl probe on` and play a little, then `/fl verify` and copy the report. After that, `/reload` and run `/fl verify` again to test persistence.

## Syncing to the game

```powershell
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -DryRun          # always look first
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -Target Forever
```

The script mirrors only `FellowshipLedger\` into `<AddOns>\FellowshipLedger`. It refuses any destination that does not end in `\Interface\AddOns` or does not exist.
