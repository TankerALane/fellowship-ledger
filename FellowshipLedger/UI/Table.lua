-- UI/Table.lua
-- A scrolling table: sortable column headers and a pool of line widgets.
-- Columns are fitted to the panel width (UI/Layout.lua): they stretch, shrink and,
-- when the window is very narrow, the right-most ones are hidden. Tables with row
-- buttons (opts.actions) keep a column of space for them on the right.
-- Lines are tables:
--   { cells = { "text", ... }, kind = "row"|"total"|"group"|"detail", indent = bool,
--     text = "..." (group/detail lines), onClick = fn, action = { label, onClick },
--     tooltip = fn() -> title, lines (shown on hover), shade = true (grid lines: shaded background),
--     item = { id, link } (hover shows the game's item tooltip instead, D-102),
--     align = "right" (group/detail text next to its action button) }
-- or a "grid" line (UI/DetailModel.lua): text placed at fractions of the width,
-- with optional small buttons, rules and a shaded box spanning several lines.

local _, ns = ...
local W = ns.Widgets

local Table = {}
ns.Table = Table

local ROW_H = 20
local GAP = 4
local ACTION_W = 80
local ARROW = "Interface\\AddOns\\FellowshipLedger\\media\\sort-arrow"
local ARROW_SIZE = 10
local SEG_BTN_W = 96
local Obj = {}
Obj.__index = Obj

-- columns: { { label, width, field, tip }, ... } (tip: hover text for the header)
-- opts: top, bottom, actions (bool), onSort(field), sortState() -> field, desc
function Table.New(parent, columns, opts)
    local self = setmetatable({ parent = parent, columns = columns, opts = opts or {}, widgets = {}, offset = 0, lines = {} }, Obj)
    self.headers = {}
    for c, col in ipairs(columns) do
        local h = CreateFrame("Button", nil, parent)
        h:SetHeight(ROW_H)
        h.text = W.Text(h, "small", "muted")
        h.text:SetPoint("LEFT")
        h.text:SetWordWrap(false)
        -- Sort direction: our arrow image (points down; flipped for up), tinted like the label.
        h.arrow = h:CreateTexture(nil, "OVERLAY")
        h.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
        h.arrow:SetTexture(ARROW)
        h.arrow:Hide()
        h:SetScript("OnClick", function()
            if self.opts.onSort and col.field then self.opts.onSort(col.field) end
        end)
        -- col.tip: what the column means, shown when hovering the header (D-084).
        if col.tip then
            h:SetScript("OnEnter", function(btn) W.Tooltip(btn, col.label, { col.tip }) end)
            h:SetScript("OnLeave", function() W.HideTooltip() end)
        end
        self.headers[c] = h
    end
    local rule = W.Rule(parent, "rule")
    rule:SetPoint("TOPLEFT", 4, -(self.opts.top or 0) - ROW_H)
    rule:SetPoint("TOPRIGHT", -4, -(self.opts.top or 0) - ROW_H)
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta)
        self.offset = math.max(0, self.offset - delta * 3)
        self:Render()
    end)
    return self
end

-- Work out column widths for the current panel width (only when it changed).
function Obj:Fit()
    local width = self.parent:GetWidth() or 0
    if width < 100 then width = 800 end
    if self.fittedFor == width then return end
    self.fittedFor = width
    local available = width - 8 - (self.opts.actions and (ACTION_W + GAP) or 0)
    self.widths, self.visibleCols = ns.Layout.FitColumns(self.columns, available, GAP)
    local x = 4
    for c, h in ipairs(self.headers) do
        local w = self.widths[c]
        if w then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", x, -(self.opts.top or 0))
            h:SetWidth(w)
            h.text:SetWidth(w)
            h:Show()
            x = x + w + GAP
        else
            h:Hide()
        end
    end
    for _, line in pairs(self.widgets) do self:PlaceCells(line) end
end

function Obj:PlaceCells(w)
    local cx = 0
    for c, fs in ipairs(w.cells) do
        local width = self.widths and self.widths[c]
        if width then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(width)
            cx = cx + width + GAP
        end
    end
end

function Obj:Line(i)
    local w = self.widgets[i]
    if w then return w end
    w = CreateFrame("Button", nil, self.parent)
    w:SetHeight(ROW_H)
    w:SetPoint("TOPLEFT", 4, -(self.opts.top or 0) - ROW_H * i - 2)
    w:SetPoint("RIGHT", self.parent, "RIGHT", -4, 0)
    w.alt = W.Background(w, "rowAlt")
    w.cells = {}
    for c = 1, #self.columns do
        local fs = W.Text(w, "body", "text")
        fs:SetWordWrap(false)
        w.cells[c] = fs
    end
    self:PlaceCells(w)
    w.full = W.Text(w, "body", "text")
    w.full:SetPoint("LEFT", 0, 0)
    w.full:SetPoint("RIGHT", -(ACTION_W + GAP), 0)
    w.full:SetWordWrap(false)
    w.segs, w.segButtons, w.rules, w.bars = {}, {}, {}, {}
    -- The shaded box of a "card" (UI/DetailModel.lua): fill plus edges.
    w.box = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    W.Fill(w.box, "panel")
    w.boxEdges = {}
    for _, name in ipairs({ "top", "bottom", "left", "right" }) do
        local t = w:CreateTexture(nil, "BORDER")
        W.Fill(t, "rule", 0.6)
        w.boxEdges[name] = t
    end
    w.action = W.Button(w, "", ACTION_W, ROW_H - 2)
    w.action:SetPoint("RIGHT", 0, 0)
    w:SetScript("OnClick", function(btn)
        if btn.line and btn.line.onClick then btn.line.onClick() end
    end)
    w:SetScript("OnEnter", function(btn)
        if btn.line and btn.line.item and W.ItemTooltip(btn, btn.line.item) then return end
        local tip = btn.line and btn.line.tooltip
        if not tip then return end
        local ok, title, lines = pcall(tip)
        if ok and title then W.Tooltip(btn, title, lines) end
    end)
    w:SetScript("OnLeave", function() W.HideTooltip() end)
    self.widgets[i] = w
    return w
end

-- Column headers off (e.g. the Quest chains view, which has its own headings).
function Obj:SetHeadersShown(shown)
    self.headersHidden = not shown
end

function Obj:SetLines(lines)
    self.lines = lines or {}
    self:Render()
end

-- Scroll so line i is at the top (Render keeps it within range).
function Obj:ScrollTo(i)
    self.offset = math.max(0, (tonumber(i) or 1) - 1)
    self:Render()
end

function Obj:Visible()
    local h = self.parent:GetHeight() or 0
    if h < ROW_H * 3 then h = 400 end
    return math.max(1, math.floor((h - (self.opts.top or 0) - ROW_H - (self.opts.bottom or 0)) / ROW_H) - 1)
end

-- Header label plus the sort arrow beside it. Falls back to " v" / " ^" text if
-- this client's textures cannot be flipped or tinted.
function Obj:ShowSort(h, label, sorted, desc, width)
    local arrow = h.arrow
    local canDraw = type(arrow.SetTexCoord) == "function" and type(arrow.SetVertexColor) == "function"
    if not sorted then
        h.text:SetText(label)
        arrow:Hide()
        return
    end
    if not canDraw then
        h.text:SetText(label .. (desc and " v" or " ^"))
        arrow:Hide()
        return
    end
    h.text:SetText(label)
    local textW = type(h.text.GetStringWidth) == "function" and h.text:GetStringWidth() or nil
    if type(textW) ~= "number" then textW = 0 end
    local x = math.max(0, math.min(textW + 2, (width or textW + 12) - ARROW_SIZE))
    arrow:ClearAllPoints()
    arrow:SetPoint("LEFT", h, "LEFT", x, 0)
    if desc then arrow:SetTexCoord(0, 1, 0, 1) else arrow:SetTexCoord(0, 1, 1, 0) end
    local m = W.Color("muted")
    arrow:SetVertexColor(m[1], m[2], m[3], 1)
    arrow:Show()
end

-- Width a line has to lay out in (falls back when the client has no size yet).
function Obj:LineWidth()
    local width = self.fittedFor or 800
    return math.max(100, width - 8)
end

local function hideGrid(w)
    for _, fs in ipairs(w.segs) do fs:Hide() end
    for _, b in ipairs(w.segButtons) do b:Hide() end
    for _, r in ipairs(w.rules) do r:Hide() end
    for _, b in ipairs(w.bars) do b:Hide() end
    w.box:Hide()
    for _, t in pairs(w.boxEdges) do t:Hide() end
end

function Obj:RenderGrid(w, line)
    local inset = line.inset or 0
    local span = self:LineWidth() - inset - (line.action and (ACTION_W + GAP) or 0)
    local nText, nBtn, nBar = 0, 0, 0
    for _, sg in ipairs(line.segments or {}) do
        local x, width = inset + span * sg.x, span * sg.w
        if sg.button then
            nBtn = nBtn + 1
            local b = w.segButtons[nBtn]
            if not b then
                b = W.Button(w, "", SEG_BTN_W, ROW_H - 4)
                w.segButtons[nBtn] = b
            end
            b.text:SetText(sg.button.label)
            b:SetScript("OnClick", sg.button.onClick)
            -- fill: as wide as the segment (tab buttons); selected: drawn pressed.
            b:SetWidth(sg.button.fill and math.max(20, width - 4) or SEG_BTN_W)
            if b.SetSelected then b:SetSelected(sg.button.selected == true) end
            b:ClearAllPoints()
            b:SetPoint("RIGHT", w, "LEFT", x + width, 0)
            b:Show()
        elseif sg.bar then
            -- A bar: sg.bar is the filled fraction (0 to 1) of the segment's width.
            nBar = nBar + 1
            local tex = w.bars[nBar]
            if not tex then
                tex = w:CreateTexture(nil, "ARTWORK")
                W.Fill(tex, "accent", 0.8)
                w.bars[nBar] = tex
            end
            tex:ClearAllPoints()
            tex:SetPoint("LEFT", x, 0)
            tex:SetSize(math.max(1, (width - 4) * math.max(0, math.min(1, sg.bar))), 8)
            tex:Show()
        else
            nText = nText + 1
            local fs = w.segs[nText]
            if not fs then
                fs = W.Text(w, "body", "text")
                fs:SetWordWrap(false)
                w.segs[nText] = fs
            end
            W.SetTextStyle(fs, sg.font or "body", sg.role or "text")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(math.max(1, width - 2))
            fs:SetJustifyH(sg.align or "LEFT")
            fs:SetText(sg.text or "")
            fs:Show()
        end
    end
    for i = nText + 1, #w.segs do w.segs[i]:Hide() end
    for i = nBtn + 1, #w.segButtons do w.segButtons[i]:Hide() end
    for i = nBar + 1, #w.bars do w.bars[i]:Hide() end
    local nRule = 0
    for _, r in ipairs(line.rules or {}) do
        nRule = nRule + 1
        local t = w.rules[nRule]
        if not t then
            t = w:CreateTexture(nil, "ARTWORK")
            t:SetHeight(1)
            W.Fill(t, "rule", 0.5)
            w.rules[nRule] = t
        end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", inset + span * r[1], 1)
        t:SetWidth(math.max(1, span * r[2] - 4))
        t:Show()
    end
    for i = nRule + 1, #w.rules do w.rules[i]:Hide() end
    -- The card box: a fill from (inset - 6) to the right edge, with edges by position.
    local box = line.box
    w.box:SetShown(box ~= nil)
    for _, t in pairs(w.boxEdges) do t:Hide() end
    if box then
        local left = inset - 6
        w.box:ClearAllPoints()
        w.box:SetPoint("TOPLEFT", left, 0)
        w.box:SetPoint("BOTTOMRIGHT", 0, 0)
        local e = w.boxEdges
        e.left:ClearAllPoints(); e.left:SetPoint("TOPLEFT", left, 0); e.left:SetPoint("BOTTOMLEFT", left, 0); e.left:SetWidth(1); e.left:Show()
        e.right:ClearAllPoints(); e.right:SetPoint("TOPRIGHT", 0, 0); e.right:SetPoint("BOTTOMRIGHT", 0, 0); e.right:SetWidth(1); e.right:Show()
        if box == "top" or box == "single" then
            e.top:ClearAllPoints(); e.top:SetPoint("TOPLEFT", left, 0); e.top:SetPoint("TOPRIGHT", 0, 0); e.top:SetHeight(1); e.top:Show()
        end
        if box == "bottom" or box == "single" then
            e.bottom:ClearAllPoints(); e.bottom:SetPoint("BOTTOMLEFT", left, 0); e.bottom:SetPoint("BOTTOMRIGHT", 0, 0); e.bottom:SetHeight(1); e.bottom:Show()
        end
    end
end

function Obj:Render()
    self:Fit()
    local field, desc = nil, nil
    if self.opts.sortState then field, desc = self.opts.sortState() end
    for c, col in ipairs(self.columns) do
        self:ShowSort(self.headers[c], col.label, field ~= nil and col.field == field, desc, self.widths[c])
        self.headers[c]:SetShown(not self.headersHidden and self.widths[c] ~= nil)
    end
    -- Lines are ROW_H tall unless they say otherwise (line.height, e.g. a half-height
    -- spacer), so place them by accumulated height.
    local avail = self:Visible() * ROW_H
    local function heightOf(line) return line.height or ROW_H end
    local maxOffset, used = #self.lines, 0
    for n = #self.lines, 1, -1 do
        used = used + heightOf(self.lines[n])
        if used > avail then break end
        maxOffset = n - 1
    end
    if self.offset > maxOffset then self.offset = maxOffset end
    local y = 0
    for i = 1, math.max(#self.lines, #self.widgets) do
        local line = self.lines[i + self.offset]
        if line and y + heightOf(line) > avail then line = nil end
        if not line then
            if self.widgets[i] then self.widgets[i]:Hide() end
        else
            local w = self:Line(i)
            local h = heightOf(line)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", 4, -(self.opts.top or 0) - ROW_H - 2 - y)
            w:SetPoint("RIGHT", self.parent, "RIGHT", -4, 0)
            w:SetHeight(h)
            y = y + h
            w.line = line
            w:Show()
            -- Grid lines are shaded only when they ask (line.shade: e.g. the quest you are on).
            w.alt:SetShown(line.shade == true or (line.kind ~= "grid" and (line.kind == "total" or line.kind == "group" or (i + self.offset) % 2 == 0)))
            if line.kind == "grid" then
                for c = 1, #self.columns do w.cells[c]:Hide() end
                w.full:Hide()
                self:RenderGrid(w, line)
            elseif line.cells then
                hideGrid(w)
                w.full:Hide()
                for c = 1, #self.columns do
                    local shown = self.widths[c] ~= nil
                    local text = line.cells[c] or ""
                    if c == 1 and line.indent then text = "    " .. text end
                    w.cells[c]:SetText(text)
                    W.SetTextRole(w.cells[c], line.kind == "total" and "heading" or (line.muted and "muted" or "text"))
                    w.cells[c]:SetShown(shown)
                end
            else
                hideGrid(w)
                for c = 1, #self.columns do w.cells[c]:Hide() end
                w.full:SetText((line.indent and "    " or "") .. (line.text or ""))
                w.full:SetJustifyH(line.align == "right" and "RIGHT" or "LEFT")
                W.SetTextRole(w.full, line.kind == "group" and "heading" or "muted")
                w.full:Show()
            end
            if line.action then
                w.action.text:SetText(line.action.label)
                w.action:SetScript("OnClick", line.action.onClick)
                w.action:Show()
            else
                w.action:Hide()
            end
        end
    end
end
