-- UI/Welcome.lua
-- Welcome panel: what the ledger records, exactly what is shared and with whom, a
-- sharing on/off switch, and a way to the per-character toggles. Shown after every
-- loading screen (login and /reload) while "Show this every time I log in" is ticked.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Welcome = {}
ns.Welcome = Welcome

local frame

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerWelcome", UIParent)
    f:SetSize(540, 360)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Background(f, "bg")
    W.Border(f, "border", 2)
    local title = W.Text(f, "heading", "heading")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L.WELCOME_TITLE)
    local body = W.Text(f, "body", "text")
    body:SetPoint("TOPLEFT", 16, -42)
    body:SetPoint("RIGHT", -16, 0)
    body:SetWordWrap(true)
    body:SetText(L.WELCOME_BODY)
    local function done()
        ns.db.settings.welcomeSeen = true
        f:Hide()
    end
    local every = W.Toggle(f, L.WELCOME_EVERY_LOGIN,
        function() return ns.db.settings.welcomeEveryLogin ~= false end,
        function(v) ns.db.settings.welcomeEveryLogin = v end, 400)
    every:SetPoint("BOTTOMLEFT", 16, 48)
    f.every = every
    local keep = W.Button(f, L.WELCOME_KEEP, 150, 24, done)
    keep:SetPoint("BOTTOMLEFT", 16, 14)
    -- Sharing switch: pauses all sharing, or turns it back on.
    local share = W.Button(f, L.WELCOME_OFF, 190, 24, function(self)
        local s = ns.db.settings
        s.sharingPaused = not s.sharingPaused
        ns.Log.Info(s.sharingPaused and L.WELCOME_OFF_DONE or L.WELCOME_ON_DONE)
        Welcome.RefreshButtons()
    end)
    share:SetPoint("BOTTOM", 0, 14)
    f.share = share
    local settings = W.Button(f, L.WELCOME_SETTINGS, 150, 24, function()
        done()
        ns.MainWindow.Open("settings")
    end)
    settings:SetPoint("BOTTOMRIGHT", -16, 14)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerWelcome") end
    return f
end

function Welcome.RefreshButtons()
    if not frame then return end
    frame.share.text:SetText(ns.db.settings.sharingPaused and L.WELCOME_ON or L.WELCOME_OFF)
    frame.every:Refresh()
end

function Welcome.Show()
    if not frame then
        local ok, result = pcall(build)
        if not ok then
            ns.Log.Warn(L.WINDOW_FAILED, tostring(result))
            return
        end
        frame = result
    end
    Welcome.RefreshButtons()
    frame:Show()
    ns.Log.Debug("welcome panel shown")
end

function Welcome.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Welcome.MaybeShow()
    if ns.db.settings.welcomeEveryLogin ~= false then Welcome.Show() end
end
