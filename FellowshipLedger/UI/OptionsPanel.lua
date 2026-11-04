-- UI/OptionsPanel.lua
-- Entries outside our window: a page in the game's Options > AddOns list (Settings
-- API, passed /fl verify on retail) and the addon compartment menu by the minimap.
-- Both are optional: if an API is missing the entry is skipped with one message.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local OptionsPanel = {}
ns.OptionsPanel = OptionsPanel

local registered = false

local function buildCanvas()
    local panel = CreateFrame("Frame")
    panel.name = L.ADDON_TITLE
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.ADDON_TITLE)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -44)
    text:SetPoint("RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    text:SetText(L.OPTIONS_TEXT)
    local open = W.Button(panel, L.OPTIONS_OPEN, 220, 26, function() ns.MainWindow.Open("settings") end)
    open:SetPoint("TOPLEFT", 16, -90)
    return panel
end

function OptionsPanel.Register()
    if registered then return end
    registered = true
    if ns.Compat.Has("Settings.RegisterCanvasLayoutCategory") and ns.Compat.Has("Settings.RegisterAddOnCategory") then
        local ok, err = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(buildCanvas(), L.ADDON_TITLE)
            Settings.RegisterAddOnCategory(category)
            OptionsPanel.category = category
        end)
        if not ok then ns.Compat.Disable("optionsPanel", tostring(err)) end
    else
        ns.Compat.Disable("optionsPanel", "Settings API missing")
    end
    local compartment = _G.AddonCompartmentFrame
    if type(compartment) == "table" and type(compartment.RegisterAddon) == "function" then
        local ok, err = pcall(compartment.RegisterAddon, compartment, {
            text = L.ADDON_TITLE,
            icon = "Interface\\AddOns\\FellowshipLedger\\media\\icon",
            notCheckable = true,
            func = function() ns.MainWindow.Toggle() end,
        })
        if not ok then ns.Compat.Disable("addonCompartment", tostring(err)) end
    end
end
