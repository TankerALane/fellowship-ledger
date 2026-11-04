# Changelog

## Unreleased: 0.0.1-dev

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
