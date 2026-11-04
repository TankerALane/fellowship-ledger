-- Locale/enUS_Phase3.lua
-- PURE: no WoW globals. English strings for friends and sharing (Phase 3).

local _, ns = ...

ns.Locale.Set({
    HELP_SYNC = "/fl sync - share with online friends now",
    HELP_COMMS = "/fl comms - sharing status (/fl comms size 200 sets the message size, 60-255)",
    HELP_COMMTEST = "/fl commtest - send test messages to yourself and report what arrived",
    SYNC_STARTED = "Saying hello to %d online friend(s) who might run the ledger.",
    COMMS_STATUS = "Sharing: prefix %s, size %d, queued %d, sent %d, retried %d, failed %d, received %d, ignored %d, friends online %d, held back: %s",
    COMMS_SIZE_SET = "Message size set to %d bytes.",
    COMMS_TRIAL = "Trial accounts cannot send addon messages, so sharing is off. Friends' data you receive is still shown.",
    COMMTEST_SENT = "Comms test sent; the report opens in a few seconds.",
    COMMTEST_TITLE = "Fellowship Ledger - comms test",
    FRIEND_MILESTONE_TITLE = "A friend's milestone",
    FRIEND_MILESTONE = "%s (%s) reached level %d!",
    COMPARE_OFF = "Compare: off",
    COMPARE_WITH = "Compare with: %s",
    COMPARE_LEGEND = "Left bars: %s   |   Right bars: %s",
    COMPARE_NOT_THIS_CHART = "Compare works on Time per level and Quests per day.",
    WEEKLY_BUTTON = "This week",
    WEEKLY_TITLE = "This week in the fellowship (last 7 days)",
    WEEKLY_LINE = "%s: %d level(s), %d quest(s), %d dungeon(s), %s active",
    WEEKLY_EMPTY = "No friends' ledgers yet.",
    SYNC_NOW = "Sync now",
    SYNC_STATUS = "%d friend(s) online here, last sync %s, %d message(s) waiting",
    SYNC_STATUS_FAKE = "Fake data: nothing is sent or received.",
    NEVER = "never",
})
