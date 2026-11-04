# Changelog

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
