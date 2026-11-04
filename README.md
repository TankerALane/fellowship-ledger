# Fellowship Ledger

A ledger of your characters' progress (levels, quests, dungeons, gold, professions and more), kept in a parchment-and-gold window with tables and graphs. You can share it with friends who also run the addon, so you can see what each of you did today, this week or this month.

An addon for World of Warcraft. It supports **WoW Forever** and **retail**, and keeps their data completely separate.

> **Status: early development (0.0.1-dev).** Only the diagnostic skeleton exists so far. Nothing is tracked yet.

## Install (development)

Copy the `FellowshipLedger` folder into `World of Warcraft\<client>\Interface\AddOns\`, or use `tools/sync.ps1`.

## Commands

| Command | What it does |
|---|---|
| `/fl` | List commands |
| `/fl verify` | Check which game functions this client offers and show a report you can copy |
| `/fl probe on` / `off` / `clear` | Count which game events fire, for the verify report (no chat is read) |
| `/fl debug` | Toggle debug messages |
| `/fl version` | Version and client details |

## Privacy

Fellowship Ledger never reads chat or the combat log, and it makes no network connections. Sharing (coming later) only goes to friends who also run the addon, and you can switch it off per tracker, per character or all at once.

## License

MIT, © Decoupled Lane Studio. See [LICENSE](LICENSE). Not affiliated with or endorsed by Blizzard Entertainment.
