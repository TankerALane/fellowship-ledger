-- UI/MinimapButton.lua
-- Our own minimap button (no libraries). Left click toggles the ledger, right click
-- opens Settings, drag moves it around the minimap rim; the angle is saved.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ICON = "Interface\\AddOns\\FellowshipLedger\\media\\minimap-icon"
local button

local function place()
    local angle = math.rad(ns.db.settings.minimap.angle or 225)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    cx, cy = cx / scale, cy / scale
    ns.db.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    place()
end

local function build()
    button = CreateFrame("Button", "FellowshipLedgerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetAllPoints()
    button.icon = icon
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.MainWindow.Open("settings") else ns.MainWindow.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        W.Tooltip(self, L.ADDON_TITLE, { L.MINIMAP_LEFT, L.MINIMAP_RIGHT, L.MINIMAP_DRAG })
    end)
    button:SetScript("OnLeave", function() W.HideTooltip() end)
end

function MinimapButton.Update()
    if not button then
        if ns.db.settings.minimap.hide then return end
        local ok, err = pcall(build)
        if not ok then
            ns.Compat.Disable("minimap", tostring(err))
            return
        end
    end
    if ns.db.settings.minimap.hide then
        button:Hide()
    else
        place()
        button:Show()
    end
end
