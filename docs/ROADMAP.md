# Roadmap

Each phase is built and tested on both clients. The full scope is in `CLAUDE_CODE_PROMPT.md`, section 12.

## Phase 1: Foundation and local tracking

### Step 1.0: skeleton and verification (done, waiting on Austin)
- [x] git init, repo layout, license, docs, `CLAUDE.md`
- [x] Forever and Mainline TOCs, plus the fallback TOC
- [x] skeleton: namespace, locale, Compat guard, flavor detection, schema v1 and migration
- [x] `/fl verify` (190 checks, copy window, saved report), `/fl probe`, `/fl debug`, `/fl version`
- [x] `tools/sync.ps1` (dry run shown to Austin), `tools/run_tests.ps1`, `tools/gen_verify_doc.py`
- [x] `docs/API-VERIFICATION.md`
- [x] unit tests and runtime smoke tests: 54 passing under LuaJIT 2.1
- [x] first real sync to both clients
- [x] Austin: retail `/fl verify` report (2026-11-04), applied to `docs/API-VERIFICATION.md`
- [ ] **Austin: Forever `/fl verify` once Forever launches (2026-11-04 15:00 PST). Everything since then rests on retail data.**
- [ ] Austin: retail extras: `/fl probe on` and play a bit, `/reload` then verify again, manual checks, and a verify while a Battle.net friend is in WoW

### Step 1.1: retail results recorded (done)
### Step 1.2: pure core modules (done)
### Step 1.3: tracking (done, built on retail data; waiting on in-game checks)
- [x] DB per character, per-character backup every 10 minutes and at logout, restore prompt, `/fl restore`, `/fl export`
- [x] sessions (a reload does not split a session; offline more than 30 minutes starts a new one), active vs total time with a 5-minute idle cut-off
- [x] trackers: Levels, Quests, Dungeons, Gold, Professions, Deaths, Zones, Reputation, Kills, Flight paths, Achievements, Party level-ups
- [ ] trackers not built yet: notable item drops, "what killed you" (APIs unverified, see D-020)
- [x] Track and Share flags per tracker per character (stored; the toggles UI is Phase 2)
- [x] Me tab with ranges, a sortable table and expandable per-level times
- [x] `/fl debug` event log window, `/fl test` in-game self-tests
- [ ] Phase 1 done when: Austin confirms no Lua errors on both clients and level times recorded correctly (see the checklist in the session report)

## Phase 2: Views, graphs and quest chains
Summary tables with ranges, every graph, quest chains (game data first, then Questie), the recommended-addons panel, toasts, settings, the own and plain skins, the welcome panel, the minimap button, and `/fl fake`.

## Phase 3: Friends and sharing
The protocol, friend discovery, sync with retries, grouping by Battle.net name, share toggles, the block list, the compare overlay, the weekly summary, milestone toasts, and the dungeon name opt-in.

## Phase 4: Polish and release
Accessibility and performance, the full verification pass, a README with screenshots, `.pkgmeta` and a GitHub Actions workflow for CurseForge, the name check, v0.1.0.
