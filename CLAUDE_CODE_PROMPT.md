# Claude Code prompt: build Fellowship Ledger

Paste everything below this line into Claude Code, started from `D:\Claude Code\fellowship_ledger`.

---

You are building **Fellowship Ledger**, a World of Warcraft addon, for me (Austin, Decoupled Lane Studio). Work out of `D:\Claude Code\fellowship_ledger`, which is your current directory and a git repo you will initialize. Brand assets are already in this folder under `assets/logo/` and `FellowshipLedger/media/`. Read `assets/README.md` first.

## 1. What it is

A personal and social progress tracker. It records what each of my characters does (levels, quests, dungeons, gold, professions and more), shows it in a parchment-and-gold UI with tables and graphs, and shares it with friends who also run the addon, so we can see what each other did today, this week or this month.

It targets two game clients, built in parallel from one codebase so I can test both:

- **WoW Forever** (client folder `_forever_`, version 1.60.1.x). This is the primary target.
- **WoW retail** (client folder `_retail_`, Mainline).

Forever data and retail data are **completely separate**. They never mix, and the two clients never sync with each other.

## 2. Working rules (read these carefully)

1. **Do not guess WoW APIs.** Parts of this client are new and I could not verify many APIs. Every API call, event, and field name you use that you cannot confirm must go on a list in `docs/API-VERIFICATION.md`, each with a one-line in-game test I can run (for example a `/dump` command) and a pass/fail column. Wrap uncertain calls so a missing API disables that one feature and logs a clear message, not a Lua error.
2. **Be honest about what is verified.** Unit tests outside the game prove the logic. Only I can prove in-game behavior. When you report progress, separate "tested by unit tests" from "needs in-game testing by Austin", and give me a short checklist for the second group.
3. **Ask before big assumptions** and before anything destructive or public (see section 13). Otherwise make reasonable decisions and record them in `docs/DECISIONS.md`.
4. **Commit at the end of every working step** with clear messages. Never force-push. Never commit secrets.
5. Create a `CLAUDE.md` in the repo root with the working rules above, the folder layout, and the commands to run tests and the sync script, so future sessions stay consistent.
6. No external libraries. Plain Lua against Blizzard's API. If message chunking or something similar proves too hard, stop and ask me before adding a library.
7. No Blizzard art, logos or trademarks anywhere. The license is MIT. Describe the addon as "for World of Warcraft" in text only.

## 3. Facts I found (treat as leads, verify in the client)

- WoW Forever shares retail's UI architecture and most 12.1.5 APIs. Retail's Midnight "addon disarmament" rules, including **secret values**, are active in Forever. Do not read the combat log (`COMBAT_LOG_EVENT_UNFILTERED`) or depend on combat-state data of other players or enemies.
- TOC format: the Warcraft Wiki says Forever uses interface number **16001** (listed for the beta and test builds; the release build was blank, so verify with `/dump select(4, GetBuildInfo())`). Flavor-specific TOC suffixes are `_Forever` (alias `_Camelot`) and `_Mainline` for retail. A wiki example shows retail as 120105 (12.1.5). Verify both numbers in each client.
- `C_BattleNet.SendGameData(gameAccountID, prefix, data)` exists in Forever 1.60.1 and retail. It returns `Enum.SendAddonMessageResult` values that include `AddOnMessageLockdown` (added in 12.0.0), `TargetOffline`, `AddonMessageThrottle` and `ChannelThrottle`. The docs give no size or rate limits, so discover them and record them. The receive event is `BN_CHAT_MSG_ADDON`.
- Trial accounts cannot send addon messages in Forever.
- Forever beta reports: some classic APIs (`GetItemInfo`, `GetItemStats`, `GetSpellInfo`) were missing or nil in places; reading your own buffs can be blocked by secret values; some chat notices fire no event and some events fire twice (de-duplicate); SavedVariables reportedly failed to persist after relog or `/reload` for some players (a community workaround called ForeverSVFix exists). So code defensively and keep backups (section 6).
- Forever obfuscates server and spawn GUIDs, so do not parse GUIDs for NPC identity. Verify what creature info is available for "kills by creature type".
- Questie's database was built from Classic data and is missing quests that are new in Forever. The game's own quest-line data may fill gaps (see `C_QuestLine`, verify).
- An addon called StoryTracker runs on Forever 1.60.1 and records sessions, level-ups, quest accept and turn-in, zones, money and recipes locally, which is good evidence those events work. Do not depend on it. Friends Progress Tracker exists but covers retail endgame through Raider.IO. Neither does what we are building. Re-check CurseForge for the name "Fellowship Ledger" before publishing.

## 4. Decisions already made

- Name: **Fellowship Ledger**. Addon folder: `FellowshipLedger`. Slash commands: `/fl` and `/fellowshipledger`. Author line: "Decoupled Lane Studio".
- One codebase, one addon folder, two TOC files (`FellowshipLedger_Forever.toc`, `FellowshipLedger_Mainline.toc`), with a small `Compat/` layer for client differences. Verify the suffix naming works before relying on it, and fall back to a generic TOC if needed.
- Look: parchment and gold, from the logo. Also a **plain skin** option that uses the default game look.
- English first, with every user-facing string in a locale file so translation is easy later.
- Light fantasy flavor in UI text, kept readable.
- UI: **one tabbed window**: Me, Friends, Graphs, Settings.
- Minimap button **and** a Game Menu/Options entry **and** slash commands.
- Recommended addons shown in Settings with tags: **Questie = Recommended**. A panel explains "install Questie for full quest-chain info" and links to its CurseForge page (as text to copy). Add it as `## OptionalDeps: Questie`. If you think another addon is needed, ask me.

## 5. What it tracks

Every tracker has two independent switches, **Track** and **Share**, per character. All are **on by default**. Turning Track off stops collecting that data. Turning Share off stops sending it. Local tracking does not depend on sharing. (This is my reading of my own spec, so confirm it with me in your first message.)

1. **Levels.** For each level gained: time per level shown as `1 -> 2: 10m 23s (total 14m 02s)`. The first number is **active time** (idle time removed after 5 minutes without activity), the bracket is total elapsed time. Graphs use active time. Also record XP per hour, kills per level (only if verified), and the zone where each level happened. Show levels gained per session.
2. **Quests.** A log of every turn-in with a timestamp (kept 30 days) plus daily totals (kept 90 days).
3. **Quest chains.** Use game data first (verify `C_QuestLine` or similar), then a Questie lookup if Questie is installed. Show "you are on step X of Y", and, for a friend, show a chain they are on that you have not started and where it begins. If neither source can answer, say so plainly in the UI.
4. **Dungeons.** Count **entered** and **completed** separately. "Completed" means the last boss was killed (verify `ENCOUNTER_END`, `BOSS_KILL` or similar, and how to know which boss is last). Record duration, deaths, and the group make-up: **class and role only** for party members. A party member's **name** is stored and shown only if that player also runs Fellowship Ledger and has switched on "share my name in dungeon records" (an opt-in flag they send you).
5. **Professions.** Skill-ups per session, time to each skill point, current rank.
6. **Gold.** Net change per session is the headline number. Below it, show loot vs vendor vs quest rewards vs mail/auction where the data is available.
7. **Extras (all on by default):** deaths and what killed you; time played per session; zones discovered; reputation gains; rare and elite kills; flight paths unlocked; notable item drops (green or better); party level-ups ("friend dinged 20"); achievements; kill counts by creature type. For each, use only events you can verify. If one is blocked by the secret-value rules, mark it unavailable instead of faking it.

**Sessions.** A session runs from login to logout. A `/reload` does not split it. If a character has been offline more than 30 minutes, the next login starts a new session.

## 6. Data model and safety

- Saved variables: `FellowshipLedgerDB` (account-wide: schema version, settings, `characters["Name-Realm"]`, cached friend data, blocklist) and `FellowshipLedgerBackupDB` (a rolling snapshot).
- Per character: class, race, faction, level, sessions, per-level times, daily buckets (YYYY-MM-DD in the player's local date, kept 90 days), quest log (30 days), dungeon runs, profession progress, and each tracker's Track and Share flags.
- Write the backup at logout and every 10 minutes. On login, compare the main DB to the backup. If the main DB looks reset or empty and the backup does not, show a clear prompt to restore.
- Include a schema version and a migration function from day one.
- Because of the reported SavedVariables bug, also add a `/fl export` that prints a compact text export I can paste into a file.
- Pure logic (time math, aggregation, protocol encode/decode, graph scaling) must live in modules that do not touch WoW globals at load time, so they can be unit tested outside the game.

## 7. Friends and sharing

**Who:** Battle.net friends and in-game character friends. Battle.net friends appear under their Battle.net name with each of their characters beneath. Character-only friends appear on their own.

**Defaults and privacy:** Sharing is on by default for every tracker on every character, and I can turn it off per tracker, per character, or all at once. On first launch, show a short **welcome panel** that explains exactly what is shared and with whom, with a one-click "turn off all sharing" and the per-character toggles. Only friends who run the addon ever receive anything. Never read or store chat. No network access. Add a **block list** (by BattleTag or character) that stops both sending to and showing someone.

**Transport:**
- Battle.net friends: `C_BattleNet.SendGameData` and `BN_CHAT_MSG_ADDON`. Identify friend characters through the friend APIs (verify field names, including how to tell which game client and flavor a friend is on).
- Character friends: addon messages by whisper (verify `C_ChatInfo` calls and any restrictions on Forever).
- Use a different message prefix per flavor (for example `FLDGF` for Forever and `FLDGR` for retail), include the flavor in every payload, and drop messages whose flavor does not match. Forever and retail data must never mix.

**Protocol (write it up in `docs/PROTOCOL.md`):** versioned messages: HELLO (protocol version, flavor, my characters and their share flags), REQUEST (what range I want), DATA (day summaries, sessions, level times, per character, only for trackers the sender shares), and the name-share opt-in flag. Use a compact text format. Chunk messages to a configurable size (default 200 bytes until you learn the real limit), with a send queue and rate limiter.

**When to sync:** at login, when a friend comes online, when I open the window, and on a timer. **Never send during combat or an encounter**, and when a send returns lockdown, throttle or offline results, queue it and retry later with backoff. Show friend data with a "last updated" time, and keep showing the last data received while a friend is offline.

**Compare:** a toggleable overlay on graphs with a selector for which characters to compare, either one of mine and one friend, or two friends.

**Friendly extras:** a weekly summary on the Friends tab, and optional milestone toasts such as "Friend reached level 30". No live rankings or competition.

## 8. UI

- Parchment `#F1E4C3`, ink `#3B2A1A`, gold `#C99A2E`, dark gold text `#7A560F`, night `#2B1E12`. Gold is for graphics, not small body text.
- **Me tab:** my characters; a summary table by character; a sortable table with columns for levels, quests, dungeons, gold net, time and the extras; ranges Today, 7 days, 30 days, All (up to 90 days). Expandable rows for per-level times.
- **Friends tab:** friends grouped as described above, the same table and ranges, a last-updated column, block/unblock.
- **Graphs tab:** levels per session as a bar per session with its date; time per level over the journey; quests per day; gold per session; XP per hour. Tooltips on hover. The compare overlay lives here.
- **Settings tab:** per-character Track and Share toggles for each tracker, a master "pause all sharing", skin choice (own skin or plain), scale slider, font size, colorblind-safe palette option, toast options, block list, recommended addons, and about (version, license, credit, privacy summary).
- Toasts: a level-up toast with the time that level took; a session summary shown on the next login and available with `/fl summary` (the logout moment may not allow chat output, so verify); optional friend milestone toasts.
- The window is movable, resizable, closes with Escape, and scales. Draw graphs yourself with textures and lines. Use a palette that is safe for color blindness and never rely on color alone.
- Minimap button: write your own small one (no libraries) using `FellowshipLedger/media/minimap-icon.tga`. Left click toggles the window, right click opens settings, and the position is saved.
- TOC icon: set `## IconTexture` to the icon in `media/` (verify the correct path format).

## 9. Repo layout to create

```
fellowship_ledger/
  CLAUDE.md  README.md  LICENSE(MIT)  CHANGELOG.md  .gitignore  .pkgmeta
  CLAUDE_CODE_PROMPT.md        (this file, keep it)
  assets/                      (already here: logo source art, not synced to the game)
  docs/                        ARCHITECTURE.md  API-VERIFICATION.md  PROTOCOL.md  DECISIONS.md  ROADMAP.md  TESTING.md
  tools/                       sync.ps1  sync.config.json  run_tests.ps1
  tests/                       pure-Lua unit tests
  FellowshipLedger/            (this exact folder is what gets copied into the game)
    FellowshipLedger_Forever.toc   FellowshipLedger_Mainline.toc
    media/                     (icon.tga and minimap-icon.tga are already here)
    Locale/  Core/  Trackers/  Comms/  UI/  Compat/  Debug/
```

## 10. Sync script

Create `tools/sync.ps1` (PowerShell, since I am on Windows) and `tools/sync.config.json` holding these destinations:

- `E:\Blizzard\World of Warcraft\_forever_\Interface\AddOns`
- `E:\Blizzard\World of Warcraft\_retail_\Interface\AddOns`

Behavior: parameter `-Target Forever|Retail|Both` (default Both) and `-DryRun`. Mirror **only** `FellowshipLedger\` into `<AddOns>\FellowshipLedger` (for example with `robocopy /MIR` on that one folder). Refuse to run unless the destination path ends in `\Interface\AddOns` and exists. Never touch any other addon's folder. Print a clear summary of what changed. Do a dry run first and show me before the first real run. If the Forever `Interface\AddOns` folder does not exist yet, tell me and ask before creating it.

## 11. Debug and testing

- `/fl debug` toggles debug logging and an in-game event log window.
- `/fl fake` fills a **separate** fake data set with 90 days of history and three fake Battle.net friends with several characters each, so I can see every table and graph without playing for hours. `/fl fake off` removes it. Fake data must never mix into real data or be sent to anyone.
- `/fl verify` runs the API checks from `docs/API-VERIFICATION.md` and prints a compact pass/fail report I can paste back to you, and also stores it in a saved variable.
- `/fl test` runs in-game self-tests (schema, protocol round trip, time math, UI smoke).
- Outside the game: unit tests for the pure-Lua modules, run through `tools/run_tests.ps1`. WoW uses Lua 5.1, so test with Lua 5.1 or LuaJIT. Check what is installed; if nothing suitable is, ask me before installing anything.

## 12. Roadmap (four large phases, both clients each time)

**Phase 1: Foundation and local tracking**
- Step 1.0 first, then stop and ask: git init, repo layout, both TOCs, a tiny skeleton that loads on both clients, `/fl verify`, the sync script (dry run first), and `docs/API-VERIFICATION.md`. Then ask me to run `/fl verify` in both clients and paste the results before you build on any unverified API.
- Then: the DB, backup and restore, sessions, active/total time, and the Levels, Quests, Dungeons, Gold and Professions trackers (plus extras you can verify), the Me tab with a basic table, and unit tests.
- Done when: it loads with no Lua errors on both clients, level times are recorded correctly, tests pass, and I have an in-game checklist.

**Phase 2: Views, graphs and quest chains**
- Summary tables with ranges, all graphs, quest-chain lookup and the Questie integration and recommended panel, toasts, settings, the own and plain skins, the welcome panel, minimap button, and `/fl fake`.
- Done when: with fake data every table and graph renders correctly on both clients.

**Phase 3: Friends and sharing**
- The protocol, friend discovery, sync with retries, grouping by Battle.net name, per-character and per-tracker share toggles, block list, compare overlay, weekly summary, milestone toasts, and the dungeon name opt-in.
- Done when: two of my characters, or me and a friend, can see each other's data on the same client, and nothing crosses between Forever and retail.

**Phase 4: Polish and release**
- Accessibility and performance review, the full verification pass, README with screenshots, `.pkgmeta` and a GitHub Actions workflow for CurseForge packaging, the CurseForge name check, and version v0.1.0 on GitHub followed by CurseForge.

At the end of each phase, give me: what works, what is only unit-tested, what I must test in-game, what is still unverified, and any decisions you made.

## 13. Publishing and accounts (ask first)

- **GitHub:** run `gh auth status` and check the repo is logged in. If it is, ask me to confirm the repo name (suggestion: `fellowship-ledger`) and that it is **public** before you create it or push anything. Blizzard requires addons to be free and open source, so public is right.
- **CurseForge:** signs in through my Google account. Do not try to enter credentials or sign in for me. When you reach packaging, stop and ask me to log in myself and create the project page. If you need an API token for CI, ask me to add it as a GitHub secret named `CF_API_KEY`. Never put tokens in the repo or in chat.

## 14. Start now

In your first message, confirm briefly: (1) the Track versus Share switch behavior in section 5, (2) that you will use the author line "Decoupled Lane Studio", and (3) any other questions. Then begin Phase 1, Step 1.0.
