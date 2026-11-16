<!-- The CurseForge project description, kept here so it can be reviewed and updated with each release.
     Paste everything below the line into the description editor on curseforge.com (Markdown mode). -->

---

# Fellowship Ledger

*A ledger of your characters' adventures, shared with your fellowship.*

Fellowship Ledger quietly records what each of your characters does: every level and how long it took, quests, dungeons, gold, professions, deaths and more. Open it with **/fl** or the minimap button and see it all in tables and graphs, for today, this week, this month or all time.

Friends who also run the addon can share their ledgers with you. Open any of their characters to see their levels, totals, gold, kills, quest chains, dungeon runs and profession ranks.

Works on **WoW Forever** and **retail**, and keeps their data completely separate.

## Why Fellowship Ledger

- **A full history for every character.** Not just where everyone is today: the ledger keeps each character's whole story, level by level, with active time (idle stretches removed) next to logged-in time, so you can see how long each level really took.
- **Nothing to set up.** There is no group to create and no one to invite into it. Your Battle.net and character friends who run the addon simply appear, and each of you chooses, per character, what to share.
- **Your history follows you.** The ledger is saved on each computer, so play on a second computer used to be missing from the first. Friends now hand your shared history back, and the ledger fills in what this computer missed without replacing anything. Updates also pass between friends you have in common, so you stay current even when you are rarely online together.
- **Built for dungeons.** A dungeon timer shows a big clock with how far ahead or behind you are, against your best clear or the fastest one among your friends, boss by boss, with the next boss and its time. When you clear, it tells you where the run lands on the Leaderboard, which keeps the fastest clears for every dungeon.
- **Quiet and private.** It never reads chat or the combat log, makes no internet connections, and is open source (MIT).

## What you can see

The window opens with your friends online and when you last synced at the top, beside **Sync** and **Settings**.

**Me**: totals for the range you pick at the top, then all your characters in one sortable list, each with its level, class and when you last played it. Click one to open its own page, with tiles for its fastest and slowest levels, gold, played time and deaths, and its views as tabs:
- **Overview**: average, fastest and slowest level, recent levels, deaths (with your level and the killer's) and notable loot. Show it as a card or a list.
- **XP**: where your XP came from (quests, kills, exploration) this session and for recent levels.
- **Quests**: turn-ins with XP, gold and zone.
- **Gold**: in, out and net, by source (loot, vendor, quests, mail, auction).
- **Kills**: by creature type, plus rares and elites.
- **Professions**: rank, progress and how long each recent point took.
- **All completed**: every quest the character has finished, grouped by zone.
- **Bests**: your personal records.

**Quest chains**: every chain in your quest log in a list, each with its step and a progress bar. Pick one to see what to do next, all its quests, their levels, which ones you've done, and who starts each one and where, with map coordinates. It also lists chains your friends are on that you haven't started, and which friends are on the same chain as you.

**Friends**: friends who run the ledger, grouped under their Battle.net name. Fold a friend down to one line, or **Collapse all** to find someone quickly. Open any of their characters just like your own, with whatever they choose to share. **This week**, in a panel beside them, puts you and your friends side by side, with a crown on the best. Right-click a friend to whisper or invite them.

**Graphs**: levels per session, time per level, quests per day, gold per session and XP per hour. **Compare** puts any two characters side by side, yours or a friend's.

**Dungeons**, in three views:
- **By dungeon**: each dungeon with your best time and your place on the Leaderboard. Pick one for its runs, best, average and deaths, the fastest clears, your best run boss by boss against #1, and your recent runs there.
- **Runs**: every run, cleared ones marked in green. Pick one to see it start to finish, each boss fight, and who was in the group with their roles.
- **Friends**: your friends' dungeon totals.

**Leaderboard**: the five fastest clears of each dungeon by you and your friends, and the fastest kill of each boss.

**Session goals**: pick a few goals when you log in (levels, quests, XP per hour, a dungeon, a profession rank). Each one shows against your usual session, and the window says about how long they will take. A small tracker follows them, shows whether you are ahead of your usual pace, and folds to one line.

**Notices**: level-ups (and how they compare with the level before), friends' milestones, finished goals and new records pop up in their own colour, and a click opens the page behind them. The big moments, like a friend reaching the level cap or a new #1 on the Leaderboard, get a larger notice.

**Settings**, in small tabs: a Track and a Share switch for every tracker on every character, three looks (Plain, Ledger, Leather), background opacity up to fully solid, text size, scale, colorblind-safe colors, notices, and a block list.

## What it tracks

- **Levels**: time per level, both active time (idle stretches removed) and logged-in time, XP per hour and by source, and the zone you levelled in
- **Quests**: turn-ins, daily totals and quest chains
- **Dungeons**: entered and completed, clear time from the first fight, each boss, deaths, and your group's classes and roles
- **Gold**: net per session, split by source
- **Professions**: skill-ups, current rank and time per point
- **Extras**: deaths and what killed you, notable loot, zones discovered, reputation, kills, flight paths, achievements and party level-ups

## Privacy

- Never reads chat or the combat log, and makes no internet connections.
- Shares only with your Battle.net and character friends who also run Fellowship Ledger on the same game, and only what each character allows.
- One click pauses all sharing. Blocked players are never sent anything and never shown.

## Recommended

**Questie** gives fuller quest-chain information, especially on WoW Forever. Fellowship Ledger works without it. Only one of you needs it: with Questie you see your friends' chains even if they don't have it, and a friend with Questie shares their chains with you even if you don't.

## Commands

- **/fl**: open or close the ledger
- **/fl summary**: your last session at a glance
- **/fl sync**: share with online friends now
- **/fl goals**: this session's goals
- **/fl timer**: show the dungeon timer again
- **/fl fake**: try every view with made-up data (never shared)
- **/fl export**: all your data as text you can copy

Found a bug or have an idea? Open an issue on GitHub: https://github.com/TankerALane/fellowship-ledger

*Fellowship Ledger is an addon for World of Warcraft. It is not affiliated with or endorsed by Blizzard Entertainment. MIT license.*
