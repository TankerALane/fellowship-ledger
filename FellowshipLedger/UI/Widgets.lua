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
    return ns.db and ns.db.settings and ns.db.settings.skin or "plain"
end

function W.Color(role)
    return Palette.Color(skin(), role)
end

local function fontObject(role)
    local size = ns.db and ns.db.settings and ns.db.settings.fontSize or "normal"
    local name = (FONTS[size] or FONTS.normal)[role] or FONTS.normal.body
    return _G[name]
end

-- The window background's opacity: the setting (1.13.1, D-131), else the look's own.
function W.Opacity()
    local o = ns.db and ns.db.settings and ns.db.settings.opacity
    if type(o) == "number" then return o end
    return W.Color("bg")[4]
end

local function paint(region, role, alpha)
    local c = W.Color(role)
    if role == "bg" and alpha == nil then alpha = W.Opacity() end
    region:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
end

-- Scaled font roles (1.13.0): a base role's font made bigger or smaller (the game has
-- no larger or smaller font objects on every client).
--   number: the figures of the Me tab's tiles (1.13.1: 1.4 -> 1.15, Austin found the tiles too tall)
--   tag:    the boxed PLAYING tag (1.13.1: two thirds of the small font, Austin)
W.NUMBER_SCALE = 1.15
W.TAG_SCALE = 0.8 -- 1.13.1: 0.67 was a little too small once the box was gone (Austin)
W.CLOCK_SCALE = 1.9 -- clock: the dungeon timer's time (1.14.0)
local SCALED = { number = { "large", "NUMBER_SCALE" }, tag = { "small", "TAG_SCALE" }, clock = { "large", "CLOCK_SCALE" } }

local function style(fs, fontRole, colorRole)
    local scaled = SCALED[fontRole]
    local fo = fontObject(scaled and scaled[1] or fontRole)
    if fo then fs:SetFontObject(fo) end
    if scaled and fo then
        pcall(function()
            local path, size, flags = fo:GetFont()
            if type(path) == "string" and type(size) == "number" then
                fs:SetFont(path, math.max(6, math.floor(size * W[scaled[2]] + 0.5)), flags)
            end
        end)
    end
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

-- Joined buttons (1.13.0): one border around the group, thin dividers between, the
-- chosen one filled. items: { { id = ..., label = ..., width = px }, ... }.
-- Returns the group frame; group.buttons[id] are the buttons (each has SetSelected
-- and an OnClick script), group:Select(id) marks one chosen.
function W.Segmented(parent, items, onSelect, height)
    height = height or 20
    local g = CreateFrame("Frame", nil, parent)
    g.buttons = {}
    -- Border and dividers go on a frame above the buttons (a parent's own textures
    -- draw under its children).
    local edges = CreateFrame("Frame", nil, g)
    edges:SetAllPoints()
    local x = 0
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, g)
        local w = item.width or 72
        b:SetSize(w, height)
        b:SetPoint("TOPLEFT", x, 0)
        b.selected = false
        b.bg = W.Background(b, "buttonBg")
        b.text = W.Text(b, "small", "buttonText")
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b.text:SetText(item.label)
        b:SetScript("OnClick", function() if onSelect then onSelect(item.id) end end)
        b:SetScript("OnEnter", function(self) if not self.selected then paint(self.bg, "buttonBg", 0.6) end end)
        b:SetScript("OnLeave", function(self) if not self.selected then paint(self.bg, "buttonBg") end end)
        function b:SetSelected(on)
            self.selected = on
            paint(self.bg, on and "accent" or "buttonBg", on and 0.55 or nil)
        end
        if i > 1 then
            local div = edges:CreateTexture(nil, "BORDER")
            W.Fill(div, "buttonBorder", 0.6)
            div:SetPoint("TOPLEFT", x, 0)
            div:SetSize(1, height)
        end
        g.buttons[item.id] = b
        x = x + w
    end
    g:SetSize(x, height)
    W.Border(edges, "buttonBorder", 1)
    local level = g:GetFrameLevel()
    if type(level) == "number" then edges:SetFrameLevel(level + 5) end
    function g:Select(id)
        for bid, b in pairs(self.buttons) do b:SetSelected(bid == id) end
    end
    return g
end

-- A horizontal slider (1.13.1): a thin track and a thumb in the accent color (no game
-- art). onChange(value) runs only when the player moves it, not on s:SetValueQuiet(v).
function W.Slider(parent, width, minV, maxV, step, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    W.Fill(track, "buttonBorder", 0.8)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    W.Fill(thumb, "accent")
    thumb:SetSize(10, 16)
    s:SetThumbTexture(thumb)
    s:SetScript("OnValueChanged", function(self, value)
        if self.quiet then return end
        if onChange then onChange(value) end
    end)
    function s:SetValueQuiet(v)
        self.quiet = true
        self:SetValue(v)
        self.quiet = false
    end
    return s
end

-- Repaint only the window backgrounds (the opacity slider moves often).
function W.ApplyOpacity()
    for _, f in ipairs(fills) do
        if f[2] == "bg" then paint(f[1], f[2], f[3]) end
    end
end

-- A small boxed tag (1.13.0), such as PLAYING after a character's name: upper-case
-- text in the section color inside a thin border. tag:SetLabel(text) sizes it.
-- 1.13.1: two thirds of its first size (height 14 -> 9, padding 8 -> 5, text TAG_SCALE),
-- and no box, just the text (Austin, 2026-11-15).
W.TAG_H = 9
function W.Tag(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(27, W.TAG_H)
    t.text = W.Text(t, "tag", "section")
    t.text:SetPoint("CENTER", 0, 0)
    t.text:SetJustifyH("CENTER")
    function t:SetLabel(text)
        self.text:SetText(ns.Format.Upper(text or ""))
        local w = self.text:GetStringWidth()
        self:SetWidth((type(w) == "number" and w > 0 and w or 5 * #(text or "")) + 5)
    end
    t:Hide()
    return t
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

-- An on/off switch (1.14.0): a rounded bar with a knob, our own art (media/switch-*.tga,
-- white, tinted here). The knob's side shows the state, not only the color: right and
-- filled with the "good" color when on, left and grey when off. get() returns the value,
-- set(v) stores it; s:Refresh() redraws, s:SetDisabled(off) dims it and ignores clicks.
local MEDIA = "Interface\\AddOns\\FellowshipLedger\\media\\"
W.SWITCH_W, W.SWITCH_H = 30, 15
function W.Switch(parent, get, set)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(W.SWITCH_W, W.SWITCH_H)
    s.disabled = false
    s.track = s:CreateTexture(nil, "ARTWORK")
    s.track:SetTexture(MEDIA .. "switch-track")
    s.track:SetAllPoints()
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetTexture(MEDIA .. "switch-knob")
    s.knob:SetSize(W.SWITCH_H - 4, W.SWITCH_H - 4)
    local function tint(tex, role, alpha)
        local c = W.Color(role)
        tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
    end
    function s:Refresh()
        local on = get() and true or false
        self.on = on
        local dim = self.disabled and 0.35 or 1
        tint(self.track, on and "good" or "buttonBorder", (on and 0.75 or 0.6) * dim)
        tint(self.knob, on and "text" or "muted", dim)
        self.knob:ClearAllPoints()
        if on then self.knob:SetPoint("RIGHT", -2, 0) else self.knob:SetPoint("LEFT", 2, 0) end
    end
    function s:SetDisabled(off)
        self.disabled = off
        self:Refresh()
    end
    s:SetScript("OnClick", function(self)
        if self.disabled then return end
        set(not get())
        self:Refresh()
    end)
    s:Refresh()
    return s
end

-- A settings row (1.14.0): the label (and a short grey hint under it) on the left, a
-- switch on the right; a click anywhere on the row flips it. Same Refresh and
-- SetDisabled as W.Toggle. row.switch is the switch.
function W.SwitchRow(parent, label, hint, get, set, width)
    local r = CreateFrame("Button", nil, parent)
    local tall = hint ~= nil and hint ~= ""
    r:SetSize(width or 260, tall and 32 or 22)
    r.disabled = false
    r.text = W.Text(r, "body", "text")
    r.text:SetText(label)
    r.switch = W.Switch(r, get, set)
    r.switch:SetPoint("RIGHT", -10, 0)
    if tall then
        r.text:SetPoint("TOPLEFT", 10, -4)
        r.hint = W.Text(r, "small", "muted")
        r.hint:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
        r.hint:SetPoint("RIGHT", r.switch, "LEFT", -8, 0)
        r.hint:SetText(hint)
    else
        r.text:SetPoint("LEFT", 10, 0)
    end
    r.text:SetPoint("RIGHT", r.switch, "LEFT", -8, 0)
    r.switch:SetScript("OnClick", function() r:GetScript("OnClick")(r) end)
    function r:Refresh()
        self.switch.disabled = self.disabled
        self.switch:Refresh()
        W.SetTextRole(self.text, self.disabled and "muted" or "text")
    end
    function r:SetDisabled(off)
        self.disabled = off
        self:Refresh()
    end
    r:SetScript("OnClick", function(self)
        if self.disabled then return end
        set(not get())
        self:Refresh()
    end)
    r:Refresh()
    return r
end

-- A titled card (1.14.0): a panel with a thin border and a small upper-case title in
-- the section color, a rule under it, and an optional note on the right of the title
-- (card.count). card:Add(frame, height, shade) stacks a row under the last one;
-- card:Finish() fits the height. card.y is the next row's offset from the top.
function W.Card(parent, title, width)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width or 260, 40)
    W.Background(c, "panel")
    W.Border(c, "rule", 1)
    c.title = W.Text(c, "small", "section")
    c.title:SetPoint("TOPLEFT", 10, -8)
    c.title:SetText(ns.Format.Upper(title or ""))
    c.count = W.Text(c, "small", "muted")
    c.count:SetPoint("TOPRIGHT", -10, -8)
    c.count:SetJustifyH("RIGHT")
    local rule = W.Rule(c, "rule")
    rule:SetPoint("TOPLEFT", 1, -24)
    rule:SetPoint("TOPRIGHT", -1, -24)
    c.y = -26
    c.rows = {}
    function c:Add(frame, height, shade)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self, "TOPLEFT", 1, self.y)
        frame:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, self.y)
        if height then frame:SetHeight(height) end
        if shade then
            local bg = frame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            W.Fill(bg, "rowAlt")
        end
        self.rows[#self.rows + 1] = frame
        local h = height or frame:GetHeight()
        self.y = self.y - (type(h) == "number" and h or 22)
        return frame
    end
    function c:Finish(pad)
        self:SetHeight(-self.y + (pad or 6))
        return self
    end
    return c
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

-- The game's own item tooltip, as in your bags (D-102). item = { id, link }.
-- Tries GameTooltip:SetHyperlink with the link (or "item:<id>"), then SetItemByID.
-- Returns true when the game filled the tooltip.
function W.ItemTooltip(owner, item)
    local tip = _G.GameTooltip
    if not tip or type(item) ~= "table" then return false end
    local id = tonumber(item.id) or (type(item.link) == "string" and tonumber(item.link:match("item:(%d+)")))
    if not id and type(item.link) ~= "string" then return false end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    local link = item.link or ("item:" .. tostring(id))
    local ok = type(tip.SetHyperlink) == "function" and pcall(tip.SetHyperlink, tip, link)
    if not ok and id and type(tip.SetItemByID) == "function" then ok = pcall(tip.SetItemByID, tip, id) end
    if not ok then tip:Hide(); return false end
    tip:Show()
    return true
end

-- Shift-click: put the item's link in the chat box, as from your bags (D-102).
function W.LinkItem(item)
    if type(item) ~= "table" or type(item.link) ~= "string" then return end
    local okShift, shift = ns.Compat.Try("IsShiftKeyDown")
    if okShift and shift then ns.Compat.Try("ChatEdit_InsertLink", item.link) end
end

-- A quest's chat link (D-107). GetQuestLink takes a quest ID on modern clients but a
-- quest log index on older ones, so its link is used only when it names this quest;
-- otherwise the standard quest link is built from the ID, level and name.
function W.QuestLink(id, name, level)
    id = tonumber(id)
    if not id then return nil end
    local ok, link = ns.Compat.Try("GetQuestLink", id)
    if ok and type(link) == "string" and link:find("quest:" .. id .. ":", 1, true) then return link end
    if type(name) ~= "string" or name == "" then return nil end
    return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, tonumber(level) or 0, name)
end

-- Shift-click on a quest: put its link in the chat box. True when shift was down (the
-- click then does nothing else).
function W.LinkQuest(id, name, level)
    local okShift, shift = ns.Compat.Try("IsShiftKeyDown")
    if not (okShift and shift) then return false end
    local link = W.QuestLink(id, name, level)
    if link then ns.Compat.Try("ChatEdit_InsertLink", link) end
    return true
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
