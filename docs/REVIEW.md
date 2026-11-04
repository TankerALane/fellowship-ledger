# Accessibility and performance review (Phase 4, 2026-11-04)

## Accessibility

| Check | Status |
|---|---|
| Never rely on color alone | Done. Toggles read "[x]" or "[ ]". Sort direction shows "v" or "^". Graph bars have exact-value tooltips. Losses sit below the zero line. Partial levels are faded and labelled. Compare uses left and right position plus a text legend. |
| Colorblind-safe palette | Done. Okabe-Ito palette, **on by default**; Settings > Appearance switches to the brand palette. |
| Contrast | Done. Body text is ink `#3B2A1A` on parchment; muted text is dark gold `#7A560F`, which passes 4.5:1 (assets/README.md). Gold is used only for lines and fills. The Plain skin uses light text on near-black. |
| Text size and scale | Done. Small, Normal and Large text, and a window scale of 0.7 to 1.5, both applied without `/reload`. |
| Readability on parchment | Done. The drop shadow is removed in the Ledger skin (D-038). |
| Keyboard | Escape closes every window (main, welcome, copy, event log). Slash commands cover every action. |
| Tooltips | On graph bars and the minimap button. |
| Plain language | Strings live in `Locale/*.lua` with light flavor, and errors say what to do next. |

Open: screen readers are not something WoW addons can address. Every action also has a slash command, so nothing depends on the mouse alone.

## Performance

| Area | Finding |
|---|---|
| Events | One shared frame. Handlers are tiny and do table writes only. Busy events are throttled: `SKILL_LINES_CHANGED` (1 s), `UPDATE_FACTION` (1 s), `QUEST_LOG_UPDATE` (2 s) and `BN_FRIEND_INFO_CHANGED` (10 s; it fired about 300 times an hour on retail). |
| `UNIT_SPELLCAST_SUCCEEDED` | It arrives for every unit and is dropped at once unless it is `player`. Using `RegisterUnitEvent` later could avoid even that. |
| Timers | A 30 s clock tick, a 10 min backup, 0.25 s comms pumping (which returns at once when the queue is empty) and a 15 min sync. |
| Login | The reputation lookup by faction ID makes up to 4,000 cheap calls once per login. |
| UI | Nothing is built until it is first opened. Rows and bars are pooled. Redraws only happen when something changes, at most 10 a second while resizing. |
| Saved data | Daily buckets 90 days, quest log 30 days, sessions and dungeon runs 90 days, friends' data 90 days, 300 points per profession. `/fl fake` adds about 13 characters until `/fl fake off`. |
| Diagnostics | The `/fl probe` and `/fl debug` event recording costs a little on every event. Turn them off when not testing (`/fl probe off`). |
