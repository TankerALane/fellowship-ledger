-- Core/SettingsDefaults.lua
-- PURE: no WoW globals. Default settings, filled in without overwriting choices.

local _, ns = ...

local SettingsDefaults = {}
ns.SettingsDefaults = SettingsDefaults

SettingsDefaults.VALUES = {
    skin = "ledger",          -- "ledger" (parchment and gold) or "plain" (default game look)
    scale = 1.0,              -- window scale, 0.7 to 1.5
    fontSize = "normal",      -- "small" | "normal" | "large"
    classColors = true,       -- names in class colors (made readable on the parchment skin)
    colorblind = true,        -- colorblind-safe graph palette (on by default: it costs nothing)
    levelToast = true,
    sessionSummary = true,    -- show last session's summary at login
    friendToasts = true,      -- friend milestone toasts (Phase 3)
    sharingPaused = false,    -- master "pause all sharing"
    shareNameInDungeons = false, -- opt-in: party members who also run the ledger may see your name
    welcomeSeen = false,
    welcomeEveryLogin = true, -- show the welcome panel after every loading screen
    rememberTab = false,
    askStale = true,          -- on a new character, offer to remove characters not played for 30 days      -- open the window on the last tab used (default: always Me)
    debug = false,
}

SettingsDefaults.SCALE_MIN = 0.7
SettingsDefaults.SCALE_MAX = 1.5
SettingsDefaults.SCALE_STEP = 0.1

function SettingsDefaults.Ensure(settings)
    for k, v in pairs(SettingsDefaults.VALUES) do
        if settings[k] == nil then settings[k] = v end
    end
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
