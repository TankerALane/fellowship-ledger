-- UI/MainWindow.lua
-- The one tabbed window: Me, Friends, Graphs, Settings. Movable, resizable, closes
-- with Escape, scales; position and size are saved. Shows a banner while fake
-- data is on.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Main = {}
ns.MainWindow = Main

Main.TABS = { "me", "friends", "graphs", "settings" }
Main.tabs = {}
Main.current = nil
Main.RESIZE_REDRAW = 0.1 -- seconds between redraws while resizing (10 per second)

local FRAME_NAME = "FellowshipLedgerMainWindow"

local function savePosition(f)
    local point, _, relPoint, x, y = f:GetPoint(1)
    ns.db.settings.window = { point = point, relPoint = relPoint, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

local function refreshCurrent()
    local tab = Main.current and Main.tabs[Main.current]
    if tab and tab.OnShow then tab.OnShow() end
end

local function build()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    local saved = ns.db.settings.window
    f:SetSize(saved and saved.w or 860, saved and saved.h or 540)
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

    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(700, 420, 1500, 1000)
    elseif f.SetMinResize then
        f:SetMinResize(700, 420)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    W.Background(grip, "accent", 0.8)
    -- While the corner is dragged, redraw at most every RESIZE_REDRAW seconds;
    -- redraw once more when it is let go. (Redrawing every frame made resizing laggy.)
    grip:SetScript("OnMouseDown", function()
        Main.sizing = true
        Main.sinceRedraw = 0
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        Main.sizing = false
        Main.resizePending = false
        savePosition(f)
        refreshCurrent()
    end)
    grip:SetScript("OnUpdate", function(_, elapsed)
        if not Main.sizing then return end
        Main.sinceRedraw = (Main.sinceRedraw or 0) + (elapsed or 0)
        if Main.resizePending and Main.sinceRedraw >= Main.RESIZE_REDRAW then
            Main.sinceRedraw = 0
            Main.resizePending = false
            refreshCurrent()
        end
    end)

    W.Background(f, "bg")
    W.Border(f, "border", 2)

    local title = W.Text(f, "heading", "heading")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(L.ADDON_TITLE)

    Main.fakeBanner = W.Text(f, "small", "bad")
    Main.fakeBanner:SetPoint("LEFT", title, "RIGHT", 16, 0)
    Main.fakeBanner:SetText(L.FAKE_BANNER)

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
            local ok, err = pcall(tab.Build, tab.panel)
            if not ok then ns.Log.Warn(L.WINDOW_FAILED, id .. ": " .. tostring(err)) end
        else
            local msg = W.Text(tab.panel, "body", "muted")
            msg:SetPoint("TOPLEFT", 8, -8)
            msg:SetText(L["TAB_" .. id:upper() .. "_SOON"])
        end
    end

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, FRAME_NAME) end
    f:SetScript("OnShow", function() Main.Refresh() end)
    f:SetScript("OnSizeChanged", function()
        if Main.sizing then Main.resizePending = true else refreshCurrent() end
    end)
    f:Hide()
    return f
end

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

-- Redraw the visible tab and the fake-data banner.
function Main.Refresh()
    if not Main.frame then return end
    Main.fakeBanner:SetShown(ns.Data.IsFake() and not (ns.Screenshots and ns.Screenshots.active))
    refreshCurrent()
end

function Main.Select(id)
    Main.current = id
    if not Main.frame then return end
    for tabId, tab in pairs(Main.tabs) do
        if tab.panel then tab.panel:SetShown(tabId == id) end
        if tab.button then tab.button:SetSelected(tabId == id) end
    end
    Main.Refresh()
end

-- The tab to show when the window opens without a specific tab: Me, unless the
-- "open on the last tab" setting is on.
function Main.DefaultTab()
    if ns.db.settings.rememberTab and Main.current then return Main.current end
    return "me"
end

function Main.Toggle(tabId)
    if not Main.Ensure() then return end
    if Main.frame:IsShown() and (not tabId or tabId == Main.current) then
        Main.frame:Hide()
    else
        Main.frame:Show()
        Main.Select(tabId or Main.DefaultTab())
    end
end

function Main.Open(tabId)
    if not Main.Ensure() then return end
    Main.frame:Show()
    Main.Select(tabId or Main.DefaultTab())
end

function Main.ApplyScale()
    if Main.frame then Main.frame:SetScale(ns.db.settings.scale or 1) end
end
