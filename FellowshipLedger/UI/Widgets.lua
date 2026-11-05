-- UI/Widgets.lua
-- Builders shared by every window. Colors come from color ROLES (UI/Palette.lua) and
-- fonts from font ROLES, and every styled region is remembered, so changing the
-- skin, palette or font size restyles the open windows in place (W.ApplySkin).

local _, ns = ...
local Palette = ns.Palette

local W = {}
ns.Widgets = W

local fills = {}  -- { region, role, alpha }
local texts = {}  -- { fontString, fontRole, colorRole }
local textEntry = {} -- fontString -> its entry in texts

-- Font roles -> Blizzard font objects, per font-size setting.
local FONTS = {
    small = { small = "GameFontHighlightSmall", body = "GameFontHighlightSmall", large = "GameFontHighlight", heading = "GameFontNormal" },
    normal = { small = "GameFontHighlightSmall", body = "GameFontHighlight", large = "GameFontHighlightLarge", heading = "GameFontNormalLarge" },
    large = { small = "GameFontHighlight", body = "GameFontHighlightLarge", large = "GameFontHighlightLarge", heading = "GameFontNormalLarge" },
}

local function skin()
    return ns.db and ns.db.settings and ns.db.settings.skin or "ledger"
end

function W.Color(role)
    return Palette.Color(skin(), role)
end

local function fontObject(role)
    local size = ns.db and ns.db.settings and ns.db.settings.fontSize or "normal"
    local name = (FONTS[size] or FONTS.normal)[role] or FONTS.normal.body
    return _G[name]
end

local function paint(region, role, alpha)
    local c = W.Color(role)
    region:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
end

local function style(fs, fontRole, colorRole)
    local fo = fontObject(fontRole)
    if fo then fs:SetFontObject(fo) end
    local c = W.Color(colorRole)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    -- The game's fonts carry a black drop shadow, which reads as a halo on parchment.
    if not Palette.IsLight(skin()) then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

-- Paint a texture with a color role (remembered for skin changes).
function W.Fill(region, role, alpha)
    fills[#fills + 1] = { region, role, alpha }
    paint(region, role, alpha)
    return region
end

-- Paint with a fixed color table (graph series); not restyled by skins.
function W.FillRGB(region, c, alpha)
    region:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

function W.Background(frame, role, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    return W.Fill(bg, role or "bg", alpha)
end

function W.Border(frame, role, size)
    size = size or 1
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        W.Fill(t, role or "border")
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, size)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    edge("TOPLEFT", "BOTTOMLEFT", size, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
end

function W.Rule(parent, role)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    return W.Fill(t, role or "rule")
end

-- fontRole: "small" | "body" | "large" | "heading"; colorRole: a Palette role.
function W.Text(parent, fontRole, colorRole)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local entry = { fs, fontRole or "body", colorRole or "text" }
    texts[#texts + 1] = entry
    textEntry[fs] = entry
    style(fs, fontRole or "body", colorRole or "text")
    fs:SetJustifyH("LEFT")
    return fs
end

-- Change a text's color role later (for example to show a disabled toggle).
function W.SetTextRole(fs, colorRole)
    local t = textEntry[fs]
    if t then t[3] = colorRole end
    local c = W.Color(colorRole)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Change a font string's font role and color role (kept on skin or size changes).
function W.SetTextStyle(fs, fontRole, colorRole)
    local t = textEntry[fs]
    if t then
        if t[2] == fontRole and t[3] == colorRole then return end
        t[2], t[3] = fontRole, colorRole
    end
    style(fs, fontRole, colorRole)
end

-- A flat text button. b:SetSelected(on) draws a stronger fill.
function W.Button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 90, height or 22)
    b.selected = false
    b.bg = W.Background(b, "buttonBg")
    W.Border(b, "buttonBorder", 1)
    b.text = W.Text(b, "small", "buttonText")
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) if not self.selected then paint(self.bg, "buttonBg", 0.6) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then paint(self.bg, "buttonBg") end end)
    function b:SetSelected(on)
        self.selected = on
        paint(self.bg, on and "accent" or "buttonBg", on and 0.55 or nil)
    end
    return b
end

-- A toggle drawn as "[x] Label" / "[ ] Label" (text, not color, shows the state).
-- get() returns the current value; set(v) stores it. t:Refresh() redraws.
function W.Toggle(parent, label, get, set, width)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(width or 220, 20)
    t.disabled = false
    t.text = W.Text(t, "body", "text")
    t.text:SetPoint("LEFT")
    function t:Refresh()
        local on = get()
        self.text:SetText((on and "[x] " or "[ ] ") .. label)
        W.SetTextRole(self.text, self.disabled and "muted" or "text")
    end
    function t:SetDisabled(off)
        self.disabled = off
        self:Refresh()
    end
    t:SetScript("OnClick", function(self)
        if self.disabled then return end
        set(not get())
        self:Refresh()
    end)
    t:Refresh()
    return t
end

-- A name in its class color, if class colors are on (Settings) and the class is known.
function W.ClassName(text, classToken)
    if not text or text == "" or not (ns.db and ns.db.settings and ns.db.settings.classColors) then return text end
    local c = Palette.ClassColor(classToken, skin())
    if not c then return text end
    return Palette.Code(c) .. text .. "|r"
end

-- Show a tooltip with a title and lines, if GameTooltip exists.
function W.Tooltip(owner, title, lines)
    local tip = _G.GameTooltip
    if not tip then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(title or "", 1, 1, 1)
    for _, l in ipairs(lines or {}) do tip:AddLine(l, 0.9, 0.9, 0.9, true) end
    tip:Show()
end

function W.HideTooltip()
    if _G.GameTooltip then _G.GameTooltip:Hide() end
end

-- Restyle everything after a skin, palette or font change.
function W.ApplySkin()
    for _, f in ipairs(fills) do paint(f[1], f[2], f[3]) end
    for _, t in ipairs(texts) do style(t[1], t[2], t[3]) end
end

-- Simple confirm dialog: text plus two buttons.
local dialog
function W.Confirm(text, yesLabel, noLabel, onYes, onNo)
    if not dialog then
        dialog = CreateFrame("Frame", "FellowshipLedgerDialog", UIParent)
        dialog:SetSize(440, 160)
        dialog:SetPoint("CENTER", 0, 120)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:EnableMouse(true)
        W.Background(dialog, "bg")
        W.Border(dialog, "border", 2)
        dialog.text = W.Text(dialog, "body", "text")
        dialog.text:SetPoint("TOPLEFT", 16, -16)
        dialog.text:SetPoint("TOPRIGHT", -16, -16)
        dialog.yes = W.Button(dialog, "", 170, 24)
        dialog.yes:SetPoint("BOTTOMLEFT", 16, 14)
        dialog.no = W.Button(dialog, "", 170, 24)
        dialog.no:SetPoint("BOTTOMRIGHT", -16, 14)
    end
    dialog.text:SetText(text)
    dialog.yes.text:SetText(yesLabel)
    dialog.no.text:SetText(noLabel)
    dialog.yes:SetScript("OnClick", function() dialog:Hide(); if onYes then onYes() end end)
    dialog.no:SetScript("OnClick", function() dialog:Hide(); if onNo then onNo() end end)
    dialog:Show()
    return dialog
end

-- A vertical scroll area: returns scrollFrame, content (put children on content and
-- set its height). Mouse wheel scrolls.
function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local new = (self:GetVerticalScroll() or 0) - delta * 40
        if new < 0 then new = 0 end
        if new > range then new = range end
        self:SetVerticalScroll(new)
    end)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w or 10) end)
    return scroll, content
end
