# Sync protocol (version 1)

How Fellowship Ledger clients share data with friends. Code: `Comms/Codec.lua` (format), `Comms/Transport.lua` (send queue and receiving), `Comms/Sync.lua` (the conversation), `Comms/Friends.lua` (who counts as a friend) and `Comms/Merge.lua` (storing what arrives).

## Rules that never bend

- **Flavor separation.** Forever uses the prefix `FLDGF` and retail uses `FLDGR`. Every piece also carries a flavor code (`F` or `R`), and a piece whose code is not ours is dropped (`stats.dropped`). Battle.net friends are only messaged when their game account's `wowProjectID` equals our `WOW_PROJECT_ID`.
- **Friends only.** We only message, and only accept messages from, Battle.net friends whose WoW game account is online on our flavor, and character friends (`C_FriendList`). The exceptions are the party NAME note (accepted from the party or instance channel) and `/fl commtest` whispers to yourself. Everything else is ignored.
- **Block list.** Blocked BattleTags or `Name-Realm` keys get nothing, and anything they send is dropped.
- **Only shared data.** A character is announced only if it shares at least one tracker. DATA carries only the fields of shared trackers. Played and active time go along whenever the character shares anything. "Pause all sharing" announces no characters and sends no DATA, but still says hello and asks friends for theirs.
- **Never in combat.** The queue holds while `InCombatLockdown()` is true, during a boss encounter (`ENCOUNTER_START` to `ENCOUNTER_END`), while `C_ChatInfo.InChatMessagingLockdown()` is true, and for 30 s after an `AddOnMessageLockdown` result.
- **Never fake.** Only `db.characters` is read. The `/fl fake` set is never sent.
- **Never chat.** Only addon-message events are read: `BN_CHAT_MSG_ADDON` and `CHAT_MSG_ADDON` with our prefix.

## Wire format

Every addon message is one piece:

```
<proto>|<flavor>|<type>|<msgId>|<seq>|<total>|<payload piece>
1|R|D|3a17|2|9|...
```

- `type`: `H` HELLO, `Q` REQUEST, `D` DATA, `N` NAME, `T` TEST.
- `msgId`: hex, unique per sender session.
- `seq` and `total`: piece number and count. Pieces reassemble in any order, and duplicates are ignored. A half-received message is dropped after 120 s.
- **Piece size:** 200 bytes by default, header included. Change it with `/fl comms size N` (60 to 255) until `/fl commtest` and two-client tests show the real limits.

Payloads are records separated by `~`, fields by `,`. Any `% | , ; ~ = newline` inside a value is written as `%XX`. Unknown record types and field codes are ignored, so newer clients can add fields.

### HELLO (`H`)

```
h,<addonVersion>,<nameOptIn 0|1>,<wantReply 0|1>
c,<Name-Realm>,<CLASS>,<level>,<shareMask>,<lastSeen>      (one per sharing character)
x,<Name-Realm>                                             (1.0.1: one per character I removed)
```

`shareMask` has one `0` or `1` per tracker, in `Core/TrackerList.lua` order.

`x` lists characters removed from the sender's ledger in the last 90 days; the receiver deletes them from that friend's record (D-071). Receivers older than 1.0.1 skip record types they do not know, so this needs no protocol version change. The sender's version in `h` also drives the update notice (D-069).

### REQUEST (`Q`)

```
q,<YYYY-MM-DD or empty>
```

"Send me everything from this day on." The requester asks from the day before the latest day it already holds for that friend, so today's partial numbers refresh; the first request is empty, meaning everything kept. The sender caps it at 90 days.

### DATA (`D`), one per shared character

```
c,<Name-Realm>,<CLASS>,<race>,<faction>,<level>,<lastSeen>,<shareMask>
d,<YYYY-MM-DD>,<code>=<int>,...                                        day buckets
l,<toLevel>,<active>,<total>,<partial 0|1>,<at>                        level times (levels tracker)
k,<chainKey>,<name>,<step>,<total>,<firstQuestID>,<firstName>,<startZone>,<source>   quest chains in progress (quests tracker)
p,<professionKey>,<name>,<rank>,<max>,<lastAt>   profession ranks (professions tracker; 1.2.0)
s,<start>,<played>,<active>,<levelStart>,<levelEnd>,<code>=<int>,...   last 60 sessions
```

Field codes:

| Code | Field | Tracker |
|---|---|---|
| `pl`, `ac` | played, active | time (shared if anything is) |
| `lv`, `xp` | levels, xp | levels |
| `qu`, `qa` | quests, questsAccepted | quests |
| `mn`, `mi`, `mo` | moneyNet, moneyIn, moneyOut | gold |
| `ml`, `mv`, `mq`, `mm`, `ma`, `mx` | money from loot, vendor, quest, mail, auction, other | gold |
| `de`, `dc`, `bk` | dungeonsEntered, dungeonsCompleted, bossKills | dungeons |
| `su` | skillUps | professions |
| `dt` | deaths | deaths |
| `zn`, `zd` | zonesNew, zonesDiscovered | zones |
| `rg` | repGained | reputation |
| `kl`, `kr`, `ke` | kills, rareKills, eliteKills | kills |
| `fp` | flightPaths | flightPaths |
| `av` | achievements | achievements |
| `pu` | partyLevelUps | partyLevels |
| `in`, `ie` | itemsNotable, itemsEpic | items |

The receiver replaces each day, level and session it receives with the sender's version (the sender is authoritative), and keeps 90 days. Quest chains (`k`) describe what the character is on now, so the received set replaces the stored one. When the sender stops sharing Quests, the stored chains are cleared. Chain keys are `g:<questLineID>` (game data) or `q:<firstQuestID>` (Questie). Profession ranks (`p`, from 1.2.0) are replaced the same way and cleared when the sender stops sharing Professions; a 1.2.0 receiver that has none from a friend says the friend's version does not send them. Version 1 receivers that predate these records ignore them.

### NAME (`N`)

```
n,<Name-Realm>
```

Sent to `PARTY` or `INSTANCE_CHAT` while in a dungeon run, only if the sender ticked "Share my name in friends' dungeon records". At most one a minute. A receiver stores a party member's name in its dungeon record only for members who sent this. Everyone else stays class and role only.

### TEST (`T`)

```
t,<id>,<size>,<padding>
```

Sent only by `/fl commtest`, as whispers to yourself.

## The conversation

```
A -> B   HELLO(wantReply=1)
B -> A   HELLO(wantReply=0) + REQUEST(since)
A -> B   DATA x (A's sharing characters)
A -> B   REQUEST(since)          (A got B's HELLO)
B -> A   DATA x (B's sharing characters)
```

**Repeats:**
- A HELLO goes to the same friend at most once a minute (unless "Sync now" forces it).
- A REQUEST goes at most once every 5 minutes.

**Triggers:**
- 10 s after login
- 5 s after a Battle.net friend comes online
- 10 s after friend-list changes (throttled; `BN_FRIEND_INFO_CHANGED` fired about 300 times an hour on retail)
- opening the Friends tab
- "Sync now" or `/fl sync`
- every 15 minutes

## Send queue

- **Token bucket:** 2 messages a second, bursts of 4 (`Comms/RateLimit.lua`), pumped every 0.25 s.
- **Throttled** (`AddonMessageThrottle` or `ChannelThrottle`): retried after 2, 4, 8 … up to 60 s, and dropped after 6 tries.
- **`AddOnMessageLockdown`:** the whole queue pauses for 30 s.
- **`TargetOffline`:** everything queued for that friend is dropped.
- **Any other failure:** that message is dropped.

`/fl comms` prints the counters.

## Still to discover (in-game)

- **Real size limits.** `C_ChatInfo.SendAddonMessage` is widely known to allow 255 bytes; `/fl commtest` measures it. The limit for `C_BattleNet.SendGameData` needs two clients.
- **Real rate limits.** The defaults are deliberately gentle.
- **Receive event arguments.** `BN_CHAT_MSG_ADDON` is coded as (prefix, text, channel, senderGameAccountID) and `CHAT_MSG_ADDON` as (prefix, text, channel, sender, ...). `/fl commtest` reports the argument types it sees.
- **Trial accounts** cannot send on Forever. The ledger detects `IsTrialAccount()` / `IsVeteranTrialAccount()` and stays receive-only.
