-- Locale/enUS_Social.lua
-- PURE: no WoW globals. English strings for inviting friends, session goals,
-- personal bests and the Leaderboard (1.8.0: D-114, D-115, D-116).

local _, ns = ...

ns.Locale.Set({
    CANCEL = "Cancel",

    -- Invite a friend (D-114)
    INVITE_GROUP = "Online, not using the ledger (%d)",
    INVITE_NONE_YET = "None of your online friends has shared a ledger yet. You can invite them below.",
    INVITE_BUTTON = "Invite",
    INVITE_UNKNOWN_GAME = "(game version unknown)",
    INVITE_LAST = "invited %s",
    INVITE_AGO_TODAY = "today",
    INVITE_AGO_DAY = "%d day ago",
    INVITE_AGO_DAYS = "%d days ago",
    INVITE_AGO_WEEKS = "%d weeks ago",
    INVITE_AGO_MONTHS = "%d months ago",
    INVITE_TITLE = "Invite %s to Fellowship Ledger",
    INVITE_HINT = "This goes to them as an ordinary whisper from you. Change the text if you like. Chat cannot carry clickable web links, so it names the addon to search for.",
    INVITE_MESSAGE = "I'm using Fellowship Ledger to share leveling progress with friends. If you install it (search \"Fellowship Ledger\" on CurseForge), we can see each other's levels, quests and dungeons.",
    INVITE_COUNT = "%d / %d",
    INVITE_SEND = "Send",
    INVITE_COPY_LINK = "Copy link",
    INVITE_LINK_TITLE = "Fellowship Ledger on CurseForge (Ctrl+C to copy)",
    INVITE_SENT = "Invite sent to %s.",
    INVITE_FAILED = "The invite to %s could not be sent. Try whispering them yourself.",
})
