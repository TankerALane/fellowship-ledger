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
    UNSUPPORTED_CLIENT = "Fellowship Ledger does not support this game client yet, so nothing was loaded. It runs on WoW Forever and retail.",

    -- Feature guard
    FEATURE_DISABLED = "%s is unavailable on this client (%s). The rest of the ledger carries on.",

    -- Slash help
    HELP_HEADER = "Commands:",
    HELP_VERIFY = "/fl verify - check which game functions this client offers and show a report to copy",
    HELP_VERIFY_SHOW = "/fl verify show - show the last report again",
    HELP_PROBE = "/fl probe on|off|clear - quietly count which game events fire, for the verify report",
    HELP_DEBUG = "/fl debug - toggle debug messages",
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

    -- Version
    VERSION_LINE = "Fellowship Ledger v%s | flavor %s (file %s) | interface %s | build %s",
})
