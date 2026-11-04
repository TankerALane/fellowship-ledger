-- UI/MainWindow.lua
-- The one tabbed window: Me, Friends, Graphs, Settings. Movable, resizable, closes
-- with Escape, position and size saved. Phase 1 fills the Me tab; the others say
-- when they arrive.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Main = {}
ns.MainWindow = Main

Main.TABS = { "me", "friends", "graphs", "settings" }
Main.tabs = {}     -- id -> { button, panel, OnShow }
Main.current = nil

local FRAME_NAME = "FellowshipLedgerMainWindow"

local function savePosition(f)
    local s = ns.db.settings
    local point, _, relPoint, x, y = f:GetPoint(1)
    s.window = { point = point, relPoint = relPoint, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

local function build()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    local saved = ns.db.settings.window
    f:SetSize(saved and saved.w or 820, saved and saved.h or 500)
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    f:SetScale(ns.db.settings.scale or 1)

    -- Resizing (SetResizeBounds on retail; older clients use SetMinResize).
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(640, 360, 1400, 900)
    elseif f.SetMinResize then
        f:SetMinResize(640, 360)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    W.Background(grip, W.COLORS.gold, 0.8)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePosition(f)
        if Main.current and Main.tabs[Main.current].OnShow then Main.tabs[Main.current].OnShow() end
    end)

    W.Background(f, W.COLORS.parchment, 0.98)
    W.Border(f, W.COLORS.gold, 2)

    local title = W.Text(f, "GameFontNormalLarge", W.COLORS.ink)
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(L.ADDON_TITLE)

    local close = W.Button(f, "X", 22, 22, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local x = 16
    for _, id in ipairs(Main.TABS) do
        local tab = Main.tabs[id] or {}
        Main.tabs[id] = tab
        tab.button = W.Button(f, L["TAB_" .. id:upper()], 100, 24, function() Main.Select(id) end)
        tab.button:SetPoint("TOPLEFT", x, -40)
        x = x + 106
        tab.panel = CreateFrame("Frame", nil, f)
        tab.panel:SetPoint("TOPLEFT", 12, -72)
        tab.panel:SetPoint("BOTTOMRIGHT", -12, 20)
        tab.panel:Hide()
        if tab.Build then
            tab.Build(tab.panel)
        else
            local msg = W.Text(tab.panel, "GameFontNormal", W.COLORS.darkGold)
            msg:SetPoint("TOPLEFT", 8, -8)
            msg:SetText(L["TAB_" .. id:upper() .. "_SOON"])
        end
    end

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, FRAME_NAME) end
    f:SetScript("OnShow", function()
        if Main.current and Main.tabs[Main.current].OnShow then Main.tabs[Main.current].OnShow() end
    end)
    f:Hide()
    return f
end

-- Tabs register their builder before the window is first built.
function Main.RegisterTab(id, buildFn, onShow)
    Main.tabs[id] = Main.tabs[id] or {}
    Main.tabs[id].Build = buildFn
    Main.tabs[id].OnShow = onShow
end

function Main.Ensure()
    if Main.frame then return true end
    local ok, result = pcall(build)
    if not ok then
        ns.Log.Warn(L.WINDOW_FAILED, tostring(result))
        return false
    end
    Main.frame = result
    Main.Select(Main.current or "me")
    return true
end

function Main.Select(id)
    Main.current = id
    if not Main.frame then return end
    for tabId, tab in pairs(Main.tabs) do
        if tab.panel then tab.panel:SetShown(tabId == id) end
        if tab.button then tab.button:SetSelected(tabId == id) end
    end
    local tab = Main.tabs[id]
    if tab and tab.OnShow then tab.OnShow() end
end

function Main.Toggle(tabId)
    if not Main.Ensure() then return end
    if Main.frame:IsShown() and (not tabId or tabId == Main.current) then
        Main.frame:Hide()
    else
        Main.frame:Show()
        Main.Select(tabId or Main.current or "me")
    end
end
