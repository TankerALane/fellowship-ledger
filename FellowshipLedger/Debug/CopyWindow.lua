-- Debug/CopyWindow.lua
-- A small movable window with a read-only, selectable text box, so reports can be
-- copied out of the game with Ctrl+A, Ctrl+C. Plain look on purpose (debug tool).
-- If building the window fails on some client, the text is printed to chat instead.

local _, ns = ...
local L = ns.L

local CopyWindow = {}
ns.CopyWindow = CopyWindow

local FRAME_NAME = "FellowshipLedgerCopyWindow"
local frame, editBox, titleText
local currentText = ""

-- Night #2B1E12, gold #C99A2E, parchment #F1E4C3 (see assets/README.md).
local NIGHT = { 0.169, 0.118, 0.071, 0.96 }
local GOLD = { 0.788, 0.604, 0.180, 1 }

local function addBorder(f, size)
    local function edge(p1, p2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, size)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    edge("TOPLEFT", "BOTTOMLEFT", size, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
end

local function build()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(680, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(NIGHT[1], NIGHT[2], NIGHT[3], NIGHT[4])
    addBorder(f, 2)

    titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 14, -12)
    titleText:SetText(L.VERIFY_WINDOW_TITLE)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 16)
    hint:SetText(L.COPY_HINT)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -14, 44)

    local inner = scroll:CreateTexture(nil, "BACKGROUND")
    inner:SetAllPoints()
    inner:SetColorTexture(0, 0, 0, 0.35)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(640)
    editBox:SetHeight(360)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: undo any typing by restoring the report text.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(currentText) end
    end)
    scroll:SetScrollChild(editBox)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local new = self:GetVerticalScroll() - delta * 40
        if new < 0 then new = 0 end
        if new > range then new = range end
        self:SetVerticalScroll(new)
    end)
    -- Clicking anywhere in the box focuses the edit box.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeText:SetPoint("CENTER")
    closeText:SetText(L.CLOSE)
    close:SetScript("OnClick", function() f:Hide() end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME)
    end

    f:Hide()
    return f
end

function CopyWindow.Show(title, text)
    currentText = text or ""
    if not frame then
        local ok, result = pcall(build)
        if not ok then
            ns.Log.Warn("Could not build the copy window (%s). Printing to chat instead.", tostring(result))
            for l in currentText:gmatch("[^\n]+") do ns.Log.Info(l) end
            return
        end
        frame = result
    end
    titleText:SetText(title or L.VERIFY_WINDOW_TITLE)
    editBox:SetText(currentText)
    editBox:SetCursorPosition(0)
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
