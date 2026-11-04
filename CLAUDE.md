# Fellowship Ledger: notes for Claude Code sessions

A progress-tracking and friend-sharing addon for World of Warcraft, by Decoupled Lane Studio (Austin). It targets **WoW Forever** (primary, `_forever_`, interface 16001) and **retail** (`_retail_`, Mainline, interface 120105) from one codebase. The full original brief is in `CLAUDE_CODE_PROMPT.md`. Read it when you are unsure about scope.

## Working rules

1. **Do not guess WoW APIs.** Every API, event or field name that has not been confirmed in-game goes in `FellowshipLedger/Debug/VerifyChecks.lua`. Run `python tools/gen_verify_doc.py` to regenerate `docs/API-VERIFICATION.md`. Call uncertain APIs through `ns.Compat.Call(feature, "Path.To.Api", ...)`. A missing API then disables only that feature, with one clear message. Never let one raise a Lua error.
2. **Be honest about what is verified.** Unit tests prove logic only. Always report "tested by unit tests" separately from "needs in-game testing by Austin", with a short checklist for the second group.
3. **Ask before big assumptions** and before anything destructive or public (GitHub repo creation or push, CurseForge). Record other decisions in `docs/DECISIONS.md`.
4. **Commit at the end of every working step** with clear messages. Never force-push. Never commit secrets or tokens.
5. **No external libraries** in the addon: plain Lua 5.1 against Blizzard's API. Ask before adding any.
6. **No Blizzard art, logos or trademarks.** The license is MIT. Describe the addon as "for World of Warcraft" in text only.
7. **Forever and retail data never mix.** Each flavor uses its own message prefix (`FLDGF` / `FLDGR`) and a flavor code in every payload. Drop anything that does not match.
8. **Never read the combat log or player chat.** Only the addon-message events (`CHAT_MSG_ADDON`, `BN_CHAT_MSG_ADDON`) are allowed. Respect Midnight secret values: check with `ns.Compat.IsSecret` before using a value.
9. **Pure modules** (time math, aggregation, protocol, graph scaling, report formatting) must not touch WoW globals at load time. List them in `tests/harness.lua` (`PURE_FILES`). The purity test loads them in a strict environment.
10. Every user-facing string goes through `ns.L` (`FellowshipLedger/Locale/enUS.lua`).

## Layout

```
CLAUDE.md  README.md  LICENSE  CHANGELOG.md  .gitignore  .pkgmeta  CLAUDE_CODE_PROMPT.md
assets/            logo source art (not synced to the game)
docs/              ARCHITECTURE, API-VERIFICATION (generated table), PROTOCOL, DECISIONS, ROADMAP, TESTING
tools/             sync.ps1, sync.config.json, run_tests.ps1, gen_verify_doc.py
tests/             pure-Lua unit tests (harness.lua, run_all.lua, test_*.lua)
FellowshipLedger/  the addon folder copied into the game, unchanged
  FellowshipLedger_Forever.toc / _Mainline.toc   keep in step (a test enforces it)
  FellowshipLedger.toc                           fallback: prints "unsupported client" only
  Core/ Locale/ Compat/ Debug/ Trackers/ Comms/ UI/ media/
```

## Commands (PowerShell, from the repo root)

```powershell
# Unit tests (needs LuaJIT or Lua 5.1 on PATH)
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1

# Copy the addon into the game: always dry-run first
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -Target Forever   # or Retail / Both (default)

# Regenerate the API verification table after editing VerifyChecks.lua
python tools/gen_verify_doc.py
```

## In-game commands so far

`/fl verify` (report window to copy), `/fl verify show`, `/fl probe on|off|clear`, `/fl debug`, `/fl version`. `/fellowshipledger` is an alias.

## Status

See `docs/ROADMAP.md` for the current phase and step. As of this writing: Phase 1, Step 1.0 is done and waiting for Austin's `/fl verify` reports from both clients.
