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
- Pure-Lua unit tests.
