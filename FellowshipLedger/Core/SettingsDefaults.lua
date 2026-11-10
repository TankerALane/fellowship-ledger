-- Core/SettingsDefaults.lua
-- PURE: no WoW globals. Default settings, filled in without overwriting choices.

local _, ns = ...

local SettingsDefaults = {}
ns.SettingsDefaults = SettingsDefaults

SettingsDefaults.VALUES = {
    skin = "ledger",          -- "ledger" (parchment and gold), "leather" (dark leather and gold) or "plain"
    scale = 1.0,              -- window scale, 0.7 to 1.5
    fontSize = "normal",      -- "small" | "normal" | "large"
    classColors = true,       -- names in class colors (made readable on every skin)
    detailsLayout = "card",   -- an opened character on the Me tab: "card" (summary card) or "list" (sections)
    colorblind = true,        -- colorblind-safe graph palette (on by default: it costs nothing)
    toastsShown = true,       -- notices on screen at all (D-099)
    toastChat = true,         -- also write every notice to chat
    toastBundle = true,       -- friend notices that arrive together become one
    awayDigest = true,        -- "While you were away" at login, with friends' level gains
    sessionRecap = true,      -- "This session: ..." line on the Me tab
    tooltipInfo = true,       -- a ledger line in the game's tooltip on a friend's character
    levelToast = true,
    sessionSummary = true,    -- show last session's summary at login
    friendToasts = true,      -- friend milestone toasts: every 10 levels (Phase 3)
    friendToastsMaxLevel = true,     -- a friend reached the level cap (D-098)
    friendToastsChains = true,       -- a friend finished a quest chain
    friendToastsDungeons = true,     -- a friend cleared a dungeon not cleared before
    friendToastsProfessions = true,  -- a friend's profession reached 75 / 150 / 225 / 300
    friendToastsJoined = true,       -- a friend's first hello: they now run the ledger (D-099)
    friendToastsLoot = true,         -- a friend looted a blue or better item (D-105)
    weeklyRecap = true,              -- last week's recap after the weekly reset (D-109)
    goals = false,                   -- suggest goals when a session starts (D-116; off unless asked for)
    bestToasts = true,
    leaderToasts = true,             -- a run of yours made a top 5 on the Leaderboard (D-115)               -- a record of all your characters was beaten (D-115)
    sharingPaused = false,    -- master "pause all sharing"
    shareNameInDungeons = false, -- opt-in: party members who also run the ledger may see your name
    welcomeSeen = false,
    welcomeEveryLogin = true, -- show the welcome panel after every loading screen
    rememberTab = false,      -- open the window on the last tab used (default: always Me)
    askStale = true,          -- on a new character, offer to remove characters not played for 30 days
    debug = false,
}

SettingsDefaults.SCALE_MIN = 0.7
SettingsDefaults.SCALE_MAX = 1.5
SettingsDefaults.SCALE_STEP = 0.1

function SettingsDefaults.Ensure(settings)
    for k, v in pairs(SettingsDefaults.VALUES) do
        if settings[k] == nil then settings[k] = v end
    end
    -- 1.0.1 development builds briefly had a "parchment" skin; it is "ledger" again.
    if settings.skin == "parchment" then settings.skin = "ledger" end
    settings.minimap = settings.minimap or {}
    if settings.minimap.angle == nil then settings.minimap.angle = 225 end
    if settings.minimap.hide == nil then settings.minimap.hide = false end
    return settings
end

function SettingsDefaults.ClampScale(v)
    v = math.floor((tonumber(v) or 1) * 10 + 0.5) / 10
    if v < SettingsDefaults.SCALE_MIN then v = SettingsDefaults.SCALE_MIN end
    if v > SettingsDefaults.SCALE_MAX then v = SettingsDefaults.SCALE_MAX end
    return v
end
