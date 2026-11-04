# Decisions

Decisions made during development that the brief left open. Newest at the bottom. "Pending" means it is waiting for Austin to confirm.

## D-001 Track vs Share (pending confirmation)
Each tracker has two independent per-character flags, Track and Share, both on by default. Track off stops collection. Share off stops sending. Local tracking never depends on sharing. When Track is off, Share has nothing to send, so the Share toggle is shown greyed out.

## D-002 Fallback TOC prints a message only
`FellowshipLedger.toc` (interface 00000) loads only the locale and `Compat/Unsupported.lua`, which prints "unsupported client". The full addon never runs on a client that did not pick a flavor TOC. Questie uses the same pattern. If the suffix TOCs ever fail to load, the message makes it obvious.

## D-003 Flavor detection by interface number
Forever is 16000-16999 (the same range Questie uses) and retail is 120000 and up. Everything else is unsupported. The TOC also states its flavor (`## X-Flavor`), and the two are cross-checked.

## D-004 One interface number per TOC
Forever is `16001` and retail is `120105`, the values installed addons use. When the client patches, these get bumped. Listing several numbers, like some retail addons do with `120100, 120105, 120107`, is possible, but it was left out until a patch makes it necessary.

## D-005 Development version string
TOCs and `Core/Namespace.lua` say `0.0.1-dev`. Phase 4 switches the TOCs to the packager's `@project-version@` token. A unit test keeps the TOCs and the namespace in step.

## D-006 Single source for the verification list
`Debug/VerifyChecks.lua` is the source of truth. `docs/API-VERIFICATION.md` is generated from it by `tools/gen_verify_doc.py`. Python is only developer tooling and never ships in the addon. A unit test fails if the doc misses a check, and regenerating keeps Austin's PASS/FAIL marks.

## D-007 Verify report goes to a copy window
WoW chat text cannot be copied, so `/fl verify` opens a read-only text box (Ctrl+A, Ctrl+C) and also stores the report in `FellowshipLedgerDB.verify`. If the window cannot be built, the report is printed to chat instead.

## D-008 Event probe
`/fl probe on` counts the candidate events and keeps their first three argument samples. It survives reloads until turned off. Addon-message events are counted without storing arguments, and no player chat event is ever registered. A unit test enforces this.

## D-009 Verify output is privacy-safe
Custom checks report field names, counts and types. They never report friend names, BattleTags, realm names or chat text, because Austin pastes the report to a developer.

## D-010 Persistence probe in both saved variables
Every load bumps a counter in `FellowshipLedgerDB.dev.persistProbe` and in `FellowshipLedgerBackupDB.persistProbe`, and logout stamps a time. This directly tests the reported Forever SavedVariables bug before real data depends on it.

## D-011 Gold sources by context, not chat (planned)
"Loot vs vendor vs quest vs mail/auction" will be inferred from which window is open when `PLAYER_MONEY` fires: merchant, mailbox, auction house, loot window, or quest reward. The `QUEST_TURNED_IN` money argument is also used. Loot and money chat messages are not read, to honour "never read chat". Amounts that cannot be attributed show as "other".

## D-012 Empty module folders
`Trackers/`, `Comms/` and `UI/` hold a `.gitkeep` until code lands. The file is harmless when synced into the game.
