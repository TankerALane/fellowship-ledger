-- UI/Table.lua
-- A scrolling table: sortable column headers and a pool of line widgets.
-- Columns are fitted to the panel width (UI/Layout.lua): they stretch, shrink and,
-- when the window is very narrow, the right-most ones are hidden. Tables with row
-- buttons (opts.actions) keep a column of space for them on the right.
-- Lines are tables:
--   { cells = { "text", ... }, kind = "row"|"total"|"group"|"detail", indent = bool,
--     text = "..." (group/detail lines), onClick = fn, action = { label, onClick },
--     tooltip = fn() -> title, lines (shown on hover),
--     align = "right" (group/detail text next to its action button) }

local _, ns = ...
local W = ns.Widgets

local Table = {}
ns.Table = Table

local ROW_H = 20
local GAP = 4
local ACTION_W = 80
local ARROW = "Interface\\AddOns\\FellowshipLedger\\media\\sort-arrow"
local ARROW_SIZE = 10
local Obj = {}
Obj.__index = Obj

-- columns: { { label, width, field }, ... }
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
    w.action = W.Button(w, "", ACTION_W, ROW_H - 2)
    w.action:SetPoint("RIGHT", 0, 0)
    w:SetScript("OnClick", function(btn)
        if btn.line and btn.line.onClick then btn.line.onClick() end
    end)
    w:SetScript("OnEnter", function(btn)
        local tip = btn.line and btn.line.tooltip
        if not tip then return end
        local ok, title, lines = pcall(tip)
        if ok and title then W.Tooltip(btn, title, lines) end
    end)
    w:SetScript("OnLeave", function() W.HideTooltip() end)
    self.widgets[i] = w
    return w
end

function Obj:SetLines(lines)
    self.lines = lines or {}
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

function Obj:Render()
    self:Fit()
    local field, desc = nil, nil
    if self.opts.sortState then field, desc = self.opts.sortState() end
    for c, col in ipairs(self.columns) do
        self:ShowSort(self.headers[c], col.label, field ~= nil and col.field == field, desc, self.widths[c])
    end
    local visible = self:Visible()
    local maxOffset = math.max(0, #self.lines - visible)
    if self.offset > maxOffset then self.offset = maxOffset end
    for i = 1, math.max(visible, #self.widgets) do
        local line = (i <= visible) and self.lines[i + self.offset] or nil
        if not line then
            if self.widgets[i] then self.widgets[i]:Hide() end
        else
            local w = self:Line(i)
            w.line = line
            w:Show()
            w.alt:SetShown(line.kind == "total" or line.kind == "group" or (i + self.offset) % 2 == 0)
            if line.cells then
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
