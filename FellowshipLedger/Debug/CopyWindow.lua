-- Debug/CopyWindow.lua
-- Movable windows with a read-only, selectable text box, so text can be copied out
-- of the game with Ctrl+A, Ctrl+C. Used by /fl verify, /fl export, /fl test and the
-- /fl debug event log. If building a window fails, the text goes to chat instead.

local _, ns = ...
local L = ns.L

local TextWindow = {}
ns.TextWindow = TextWindow

-- Night #2B1E12, gold #C99A2E (see assets/README.md).
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

local function build(self)
    local f = CreateFrame("Frame", self.frameName, UIParent)
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

    self.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.title:SetPoint("TOPLEFT", 14, -12)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 16)
    hint:SetText(L.COPY_HINT)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -14, 44)
    self.scroll = scroll

    local inner = scroll:CreateTexture(nil, "BACKGROUND")
    inner:SetAllPoints()
    inner:SetColorTexture(0, 0, 0, 0.35)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(640)
    edit:SetHeight(360)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnTextChanged", function(box, userInput)
        if userInput then box:SetText(self.text) end -- read-only
    end)
    scroll:SetScrollChild(edit)
    self.edit = edit

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local range = sf:GetVerticalScrollRange()
        local new = sf:GetVerticalScroll() - delta * 40
        if new < 0 then new = 0 end
        if new > range then new = range end
        sf:SetVerticalScroll(new)
    end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)

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

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, self.frameName) end
    f:Hide()
    return f
end

local Window = {}
Window.__index = Window

function TextWindow.Create(frameName)
    return setmetatable({ frameName = frameName, text = "" }, Window)
end

function Window:Ensure()
    if self.frame then return true end
    local ok, result = pcall(build, self)
    if not ok then
        ns.Log.Warn("Could not build a text window (%s). Printing to chat instead.", tostring(result))
        return false
    end
    self.frame = result
    return true
end

function Window:SetText(text)
    self.text = text or ""
    if self.edit then self.edit:SetText(self.text) end
end

function Window:Show(title, text, focus)
    self.text = text or ""
    if not self:Ensure() then
        for l in self.text:gmatch("[^\n]+") do ns.Log.Info(l) end
        return
    end
    self.title:SetText(title or "")
    self.edit:SetText(self.text)
    self.edit:SetCursorPosition(0)
    self.frame:Show()
    if focus ~= false then
        self.edit:SetFocus()
        self.edit:HighlightText()
    end
end

function Window:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

function Window:Hide()
    if self.frame then self.frame:Hide() end
end

-- The shared report window used by verify, export and self-test.
ns.CopyWindow = TextWindow.Create("FellowshipLedgerCopyWindow")
