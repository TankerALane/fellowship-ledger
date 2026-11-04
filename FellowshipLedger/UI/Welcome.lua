-- UI/Welcome.lua
-- First-launch panel: what the ledger records, exactly what is shared and with whom,
-- a one-click "turn off all sharing", and a way to the per-character toggles.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Welcome = {}
ns.Welcome = Welcome

local frame

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerWelcome", UIParent)
    f:SetSize(520, 330)
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
    local keep = W.Button(f, L.WELCOME_KEEP, 150, 24, done)
    keep:SetPoint("BOTTOMLEFT", 16, 14)
    local off = W.Button(f, L.WELCOME_OFF, 170, 24, function()
        ns.db.settings.sharingPaused = true
        ns.Log.Info(L.WELCOME_OFF_DONE)
        done()
    end)
    off:SetPoint("BOTTOM", 0, 14)
    local settings = W.Button(f, L.WELCOME_SETTINGS, 150, 24, function()
        done()
        ns.MainWindow.Open("settings")
    end)
    settings:SetPoint("BOTTOMRIGHT", -16, 14)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerWelcome") end
    return f
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
    frame:Show()
end

function Welcome.MaybeShow()
    if not ns.db.settings.welcomeSeen then Welcome.Show() end
end
