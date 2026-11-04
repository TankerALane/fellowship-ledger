-- Locale/enUS.lua
-- PURE: must not touch WoW globals at load time.
-- Base English strings. Keep the tone lightly fantasy but readable.

local _, ns = ...

ns.Locale.Set({
    ADDON_TITLE = "Fellowship Ledger",

    -- Loading
    LOADED = "The ledger is open (v%s, %s). Type /fl for commands.",
    FLAVOR_MISMATCH = "Warning: this client reports flavor %s, but the %s file was loaded. Please run /fl verify and send the report.",
    UNKNOWN_FLAVOR = "This client is not one the ledger recognises (interface %s). Tracking is disabled.",
    FOREVER_VERIFY_REMINDER = "This ledger has not been checked on WoW Forever yet. Please type /fl verify and send the report (this reminder stops once a report is saved).",
    UNSUPPORTED_CLIENT = "Fellowship Ledger does not support this game client yet, so nothing was loaded. It runs on WoW Forever and retail.",

    -- Feature guard
    FEATURE_DISABLED = "%s is unavailable on this client (%s). The rest of the ledger carries on.",

    -- Slash help
    HELP_HEADER = "Commands:",
    HELP_OPEN = "/fl - open or close the ledger window",
    HELP_EXPORT = "/fl export - show all saved data as text you can copy and keep",
    HELP_TEST = "/fl test - run quick self-tests inside the game",
    HELP_RESTORE = "/fl restore - restore this character from its backup",
    HELP_VERIFY = "/fl verify - check which game functions this client offers and show a report to copy",
    HELP_VERIFY_SHOW = "/fl verify show - show the last report again",
    HELP_PROBE = "/fl probe on|off|clear - quietly count which game events fire, for the verify report",
    HELP_DEBUG = "/fl debug - toggle debug messages and the event log window",
    HELP_VERSION = "/fl version - show version and client details",

    -- Debug
    DEBUG_ON = "Debug messages on.",
    DEBUG_OFF = "Debug messages off.",

    -- Verify
    VERIFY_RUNNING = "Checking the client's functions...",
    VERIFY_DONE = "Check finished: %d pass, %d fail, %d error, %d info, %d manual. Report saved; press Ctrl+A then Ctrl+C in the window to copy it.",
    VERIFY_NONE = "No report yet. Type /fl verify first.",
    VERIFY_WINDOW_TITLE = "Fellowship Ledger - verify report",
    COPY_HINT = "Click in the box, press Ctrl+A then Ctrl+C to copy. Escape closes.",
    CLOSE = "Close",

    -- Probe
    PROBE_ON = "Event probe on: counting %d events (no chat is read). It keeps running across reloads until /fl probe off.",
    PROBE_OFF = "Event probe off. Counts are kept for the next /fl verify.",
    PROBE_CLEARED = "Event probe counts cleared.",

    -- Tracking and safety
    HANDLER_ERROR = "%s ran into a problem on %s and skipped it: %s",
    TRACKING_FAILED = "Tracking could not start: %s. Please run /fl test and send the result.",
    DB_NEWER = "Your saved ledger comes from a newer version of the addon. Tracking is paused so nothing is damaged; please update the addon.",
    WINDOW_FAILED = "The ledger window could not be built: %s",
    LEVEL_UP_TOAST = "Level up! %s",
    PARTIAL = "(partial: the ledger joined partway through this level)",
    RESTORE_PROMPT_MISSING = "The ledger for this character looks empty, but a backup from %s exists. Restore it?",
    RESTORE_PROMPT_OLDER = "The ledger for this character looks older than its backup from %s (the last save may have been lost). Restore the backup?",
    RESTORE_YES = "Restore backup",
    RESTORE_NO = "Keep current",
    RESTORE_DONE = "Backup restored for this character.",
    RESTORE_SKIPPED = "Kept the current ledger. You can still restore later with /fl restore (until the next backup is written).",
    RESTORE_NONE = "There is no backup for this character yet.",
    EXPORT_TITLE = "Fellowship Ledger - export",
    SELFTEST_TITLE = "Fellowship Ledger - self-test",
    SELFTEST_DONE = "Self-test: %d of %d passed.",
    EVENT_LOG_TITLE = "Fellowship Ledger - event log (newest first)",
    EVENT_LOG_EMPTY = "No events recorded yet. Events are recorded while debug is on.",

    -- Window
    TAB_ME = "Me",
    TAB_FRIENDS = "Friends",
    TAB_GRAPHS = "Graphs",
    TAB_SETTINGS = "Settings",
    TAB_FRIENDS_SOON = "Your fellowship's ledgers arrive in a later chapter (Phase 3).",
    TAB_GRAPHS_SOON = "Charts of your journey arrive in the next chapter (Phase 2).",
    TAB_SETTINGS_SOON = "Settings arrive in the next chapter (Phase 2). Everything is tracked by default; nothing is shared yet.",
    RANGE_TODAY = "Today",
    RANGE_WEEK = "7 days",
    RANGE_MONTH = "30 days",
    RANGE_ALL = "All",
    COL_CHARACTER = "Character",
    COL_LEVEL = "Lvl",
    COL_LEVELS = "Levels",
    COL_QUESTS = "Quests",
    COL_DUNGEONS = "Dungeons",
    COL_GOLD = "Gold",
    COL_PLAYED = "Played",
    COL_ACTIVE = "Active",
    COL_DEATHS = "Deaths",
    COL_KILLS = "Kills",
    COL_SKILLUPS = "Skill-ups",
    NO_DATA_YET = "No entries in the ledger yet. Go forth and adventure!",
    NO_LEVELS_YET = "No levels recorded yet.",

    -- Version
    VERSION_LINE = "Fellowship Ledger v%s | flavor %s (file %s) | interface %s | build %s",
})
