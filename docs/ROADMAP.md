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

## Phase 2: Views, graphs and quest chains (built, waiting on in-game checks)
- [x] `/fl fake` and `/fl fake off`: a separate deterministic fake set (3 own characters, 3 Battle.net friends, 1 character friend, 90 days)
- [x] Me tab: ranges, an all-characters totals line, a sortable table, per-level times, and a quest-chains view
- [x] Friends tab: Battle.net friends grouped with their characters, character friends alone, ranges, last updated, Block
- [x] Graphs tab: levels per session, time per level, quests per day, gold per session and XP per hour, with tooltips
- [x] Quest chains: game data first, then Questie (guarded), else a plain answer; the recommended-addons panel
- [x] Notices: level-up, last-session summary at login, `/fl summary`
- [x] Settings tab: per-character Track/Share, pause all sharing, the dungeon-name opt-in, skin, scale, text size, colorblind palette, minimap toggle, notice options, block list, recommended addons, about
- [x] Ledger and Plain skins (restyle in place), the welcome panel, our own minimap button, the Options > AddOns page and the addon compartment entry
- [ ] Done when: Austin confirms with `/fl fake` that every table and graph renders correctly on both clients

## Phase 3: Friends and sharing (built and tested against two mock clients; waiting on in-game tests)
- [x] Protocol v1: HELLO, REQUEST, DATA, NAME and TEST; compact escaped text; 200-byte pieces; reassembly (`docs/PROTOCOL.md`)
- [x] Friend discovery: Battle.net friends on the same `wowProjectID`, and character friends
- [x] Send queue with a rate limit, back-off and lockdown pause; nothing sent in combat or encounters
- [x] Share filter: per character and per tracker, pause all, never fake data; block list on send and receive
- [x] Friends tab with real data: grouped by Battle.net name, last updated, This week summary, Sync now, status line
- [x] Compare overlay on Graphs; friend milestone notices; dungeon-name opt-in (NAME note to the party)
- [x] `/fl sync`, `/fl comms`, `/fl comms size N`, `/fl commtest`
- [ ] Austin: `/fl commtest` on both clients (sizes and argument shapes)
- [ ] Done when: two characters (or Austin and a friend) see each other's data on the same client, and nothing crosses between Forever and retail

## Phase 5: Finish the brief (built and unit-tested; 1.0.0 waits for Forever)
- [x] Friends' quest chains: chains shared with Quests, and "chains your friends are on that you haven't started", with where each begins
- [x] Notable item drops from your own loot window (green or better), shown in the character's expanded row
- [x] What killed you, from the death recap; stored as hidden if the game makes it secret
- [x] Retail 12.1.7 declared in the TOC and the release versions
- [ ] Austin in-game: loot a green item, die once, then `/fl verify` (new checks: loot functions, `LOOT_SLOT_CLEARED`, `x:death.recap`, `C_Map.GetAreaInfo`)
- [ ] Forever verification pass, two-client test, screenshots, then 1.0.0

## Phase 4: Polish and release (in progress)
- [x] Accessibility and performance review (`docs/REVIEW.md`)
- [x] README; release script, CI and release workflows, `.pkgmeta` note (`docs/RELEASING.md`)
- [x] CurseForge name check: no existing "Fellowship Ledger" found (D-054)
- [x] `/fl commtest` on retail: whispers up to 255 bytes arrive; argument order confirmed
- [ ] Screenshots for the README (Austin)
- [ ] Full verification pass on Forever (launch 2026-11-04 15:00 PST): `/fl verify`, `/fl test`, `/fl commtest`, `/fl fake`, Questie chains
- [ ] Two-client sharing test (Austin and a friend, or two accounts)
- [x] GitHub repository https://github.com/TankerALane/fellowship-ledger (public), CI green, `v0.1.0` published as a pre-release (2026-11-04)
- [x] CurseForge project created by Austin (ID 1784128), ID in both TOCs
- [x] 0.1.0 uploaded to CurseForge by hand; `CF_API_KEY` secret added and checked (token accepted; 12.1.5 and Forever 1.60.1 both listed)
