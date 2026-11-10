# Roadmap

Each phase is built and tested on both clients. The full scope is in `CLAUDE_CODE_PROMPT.md`, section 12.

## Phase 1: Foundation and local tracking

### Step 1.0: skeleton and verification (done)
- [x] git init, repo layout, license, docs, `CLAUDE.md`
- [x] Forever and Mainline TOCs, plus the fallback TOC
- [x] skeleton: namespace, locale, Compat guard, flavor detection, schema v1 and migration
- [x] `/fl verify` (190 checks, copy window, saved report), `/fl probe`, `/fl debug`, `/fl version`
- [x] `tools/sync.ps1` (dry run shown to Austin), `tools/run_tests.ps1`, `tools/gen_verify_doc.py`
- [x] `docs/API-VERIFICATION.md`
- [x] unit tests and runtime smoke tests: 54 passing under LuaJIT 2.1
- [x] first real sync to both clients
- [x] Austin: retail `/fl verify` report (2026-11-04), applied to `docs/API-VERIFICATION.md`
- [x] Austin: Forever `/fl verify` (2026-11-04, `docs/verify-reports/forever-2026-11-04*.txt`), applied to the Forever column
- Retail extras (`/fl probe`, a verify with a Battle.net friend in WoW) were not done; Forever is the focus. See "Still open" below.

### Step 1.1: retail results recorded (done)
### Step 1.2: pure core modules (done)
### Step 1.3: tracking (done)
- [x] DB per character, per-character backup every 10 minutes and at logout, restore prompt, `/fl restore`, `/fl export`
- [x] sessions (a reload does not split a session; offline more than 30 minutes starts a new one), active vs total time with a 5-minute idle cut-off
- [x] trackers: Levels, Quests, Dungeons, Gold, Professions, Deaths, Zones, Reputation, Kills, Flight paths, Achievements, Party level-ups
- [x] notable item drops and "what killed you": built in Phase 5
- [x] Track and Share flags per tracker per character (stored; the toggles UI is Phase 2)
- [x] Me tab with ranges, a sortable table and expandable per-level times
- [x] `/fl debug` event log window, `/fl test` in-game self-tests
- [x] Phase 1 done: no Lua errors in the verify passes on both clients, and in daily use on Forever since 2026-11-04

## Phase 2: Views, graphs and quest chains (done)
- [x] `/fl fake` and `/fl fake off`: a separate deterministic fake set (3 own characters, 3 Battle.net friends, 1 character friend, 90 days)
- [x] Me tab: ranges, an all-characters totals line, a sortable table, per-level times, and a quest-chains view
- [x] Friends tab: Battle.net friends grouped with their characters, character friends alone, ranges, last updated, Block
- [x] Graphs tab: levels per session, time per level, quests per day, gold per session and XP per hour, with tooltips
- [x] Quest chains: game data first, then Questie (guarded), else a plain answer; the recommended-addons panel
- [x] Notices: level-up, last-session summary at login, `/fl summary`
- [x] Settings tab: per-character Track/Share, pause all sharing, the dungeon-name opt-in, skin, scale, text size, colorblind palette, minimap toggle, notice options, block list, recommended addons, about
- [x] Ledger and Plain skins (restyle in place), the welcome panel, our own minimap button, the Options > AddOns page and the addon compartment entry
- [x] Tables, graphs and quest chains in use on Forever with real data (2026-11-04). A full `/fl fake` pass on both clients was not done; see "Still open".

## Phase 3: Friends and sharing (done)
- [x] Protocol v1: HELLO, REQUEST, DATA, NAME and TEST; compact escaped text; 200-byte pieces; reassembly (`docs/PROTOCOL.md`)
- [x] Friend discovery: Battle.net friends on the same `wowProjectID`, and character friends
- [x] Send queue with a rate limit, back-off and lockdown pause; nothing sent in combat or encounters
- [x] Share filter: per character and per tracker, pause all, never fake data; block list on send and receive
- [x] Friends tab with real data: grouped by Battle.net name, last updated, This week summary, Sync now, status line
- [x] Compare overlay on Graphs; friend milestone notices; dungeon-name opt-in (NAME note to the party)
- [x] `/fl sync`, `/fl comms`, `/fl comms size N`, `/fl commtest`
- [x] `/fl commtest` on both clients (retail and Forever, 2026-11-04)
- [x] Austin and Battle.net friends see each other's data on Forever (2026-11-04, 0.2.3). Forever/retail separation is covered by unit tests (separate prefixes and flavor codes); it has not been tried with a friend on the other flavor.

## Phase 5: Finish the brief (done; 1.0.0 released 2026-11-04)
- [x] Friends' quest chains: chains shared with Quests, and "chains your friends are on that you haven't started", with where each begins
- [x] Notable item drops from your own loot window (green or better), shown in the character's expanded row
- [x] What killed you, from the death recap; stored as hidden if the game makes it secret
- [x] Retail 12.1.7 declared in the TOC and the release versions
- [x] Forever: notable loot and deaths with the killer and spell from the death recap, confirmed in the Me tab (2026-11-04, D-067)
- [x] Forever verification pass and two-client test (2026-11-04)
- [x] 1.0.0 released 2026-11-04 (GitHub Release and CurseForge Release)

## Phase 4: Polish and release (done)
- [x] Accessibility and performance review (`docs/REVIEW.md`)
- [x] README; release script, CI and release workflows, `.pkgmeta` note (`docs/RELEASING.md`)
- [x] CurseForge name check: no existing "Fellowship Ledger" found (D-054)
- [x] `/fl commtest` on retail: whispers up to 255 bytes arrive; argument order confirmed
- [x] Screenshots for the README (Austin)
- [x] Full verification pass on Forever (2026-11-04): `/fl verify`, `/fl test`, `/fl commtest`, tracking, Questie chains
- [x] Two-client sharing test on Forever (2026-11-04, 0.2.3): Austin and a Battle.net friend shared ledgers over Battle.net, with the friend affected by Forever's friends-list problem (project id 0, D-066)
- [x] GitHub repository https://github.com/TankerALane/fellowship-ledger (public), CI green, `v0.1.0` published as a pre-release (2026-11-04)
- [x] CurseForge project created by Austin (ID 1784128), ID in both TOCs
- [x] 0.1.0 uploaded to CurseForge by hand; `CF_API_KEY` secret added and checked (token accepted; 12.1.5 and Forever 1.60.1 both listed)

## 1.0.1 (released 2026-11-05)
- [x] Faction column on the Me and Friends tables
- [x] Update notice from friends' versions, and an "old version" mark on the Friends tab
- [x] Class-colored names (Settings toggle, on by default; readable on the parchment skin)
- [x] Leather look (dark) as a Settings choice; Ledger parchment stays the default
- [x] Sortable Friends table, characters kept under their friend
- [x] Arrow images for the sort direction
- [x] Tooltip on a friend's character row
- [x] Friends tab empty state that says how many friends are online on this version
- [x] Remove characters you no longer play: a Remove button, a prompt on a new character, and removal on friends' copies
- [x] Roadmap cleanup; release runner pinned to Ubuntu 24.04
- [x] Character details on the Me tab: summary card (default) or list, last 10 levels / 5 deaths / 5 loot with Show all, killer level when targeted

## 1.1.0 (released 2026-11-05)
- [x] Killer level from recent targets (D-077)
- [x] Quest chain drop-downs with levels, starters, zones and coordinates (D-078, D-079)
- [x] Flight paths counted from the discovery message (D-080)
- [x] Character detail views: Quests, Gold, Kills, Professions, All completed (D-081)

## 1.2.0 (released 2026-11-05)
- [x] Friends' characters open like your own, with profession ranks shared (D-083)
- [x] Column header hover text; Dungeons shows "-" when none entered (D-084)
- [x] Dungeon completion on WoW Forever: journal retries, then our own final-boss list (D-085, D-086)

## 1.2.1 (released 2026-11-05)
- [x] Quest logs shared, so friends' chains are worked out with your own Questie (D-087)

## Still open (needs a second player or a retail session)
- [ ] Retail: one death, to see whether the killer is readable or secret
- [ ] Character-friend (whisper) sharing with a second player
- [x] Sharing across factions (Horde and Alliance Battle.net friends), verified on Forever 2026-11-06
- [ ] `/fl fake` pass on both clients; retail `/fl probe`
- [x] 1.6.0 with friends on Forever (2026-11-07): friend notices for chains, dungeon clears and professions, friends' shared dungeon runs, friends' quest chains and profession ranks
- [ ] Friend level-cap notice: fires when a friend reaches 60 (GetMaxLevelForPlayerExpansion returns 60; no friend has reached it yet)

## 1.8.0 (built on `feature/1.8-fun`, not released)
Released once the D-112/D-113 group checks pass. Unit and mock-client tests pass; the in-game checks are below.
- [x] **Invite a friend** (D-114, D-117)
- [x] **Personal bests** (D-115, D-117): a Bests view on each character, records kept for good
- [x] **Session goals** (D-116, D-117): off by default
- [x] **Dungeon Leaderboard** (D-115, D-117): a Leaderboard tab
- [ ] Austin, in game: `/fl verify` on both clients (new: BNSendWhisper, C_ChatInfo.SendChatMessage, SendChatMessage), then m:invite, m:bests, m:goals, m:leaderboard, m:dungeonlevels
- [ ] Austin: confirm the CurseForge address used by Copy link (Core/Invites.lua)

## Possible additions (not scheduled)
- [ ] **Guild sharing** (optional, off by default): share a summary over the guild addon channel. It would help spread the addon, but guildmates are often not Battle.net or character friends, so it is not the best way to grow it; kept for later (Austin, 2026-11-09). Privacy questions to settle before any work starts.
