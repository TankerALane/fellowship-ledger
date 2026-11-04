# Sync protocol

> **Status: outline only.** The full design is written in Phase 3, after the transports and their limits are verified in-game. Nothing here is implemented yet.

## Fixed decisions

- **Prefix per flavor.** Forever uses `FLDGF` and retail uses `FLDGR`, registered with `C_ChatInfo.RegisterAddonMessagePrefix`. Battle.net messages through `C_BattleNet.SendGameData` use the same prefix strings.
- **Flavor code in every payload.** `F` for Forever, `R` for retail. A receiver drops any message whose code does not match its own flavor.
- **Versioned.** Every message starts with a protocol version, so old and new builds can tell when they cannot understand each other.
- **Compact text**, chunked to a configurable size (default 200 bytes until the real limits are known), with a send queue and a rate limiter.
- **No sending during combat or an encounter.** When a send returns lockdown, throttle or offline, it is queued and retried with backoff.
- **Only shared trackers are sent.** If a tracker's Share flag is off for a character, its data never leaves the client.

## Planned message types

| Type | Purpose |
|---|---|
| HELLO | protocol version, flavor, my characters, their share flags, and the "share my name in dungeon records" opt-in |
| REQUEST | the date range I want |
| DATA | day summaries, sessions and level times per character, for shared trackers only |

## To discover in Phase 3 (and record here)

- Maximum payload size for `C_BattleNet.SendGameData` and for whisper addon messages on each client.
- Rate limits, and how `AddonMessageThrottle` and `ChannelThrottle` behave in practice.
- Whether trial accounts get a specific result code (they cannot send addon messages on Forever).
- How to identify a Battle.net friend's flavor from their game-account info (`x:friends.bnfields` in `/fl verify` collects the field names).
