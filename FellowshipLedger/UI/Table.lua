-- UI/Table.lua
-- A scrolling table: sortable column headers and a pool of line widgets.
-- Lines are tables:
--   { cells = { "text", ... }, kind = "row"|"total"|"group"|"detail", indent = bool,
--     text = "..." (group/detail lines), onClick = fn, action = { label, onClick } }

local _, ns = ...
local W = ns.Widgets

local Table = {}
ns.Table = Table

local ROW_H = 20
local Obj = {}
Obj.__index = Obj

-- columns: { { label, width, field }, ... }; opts.onSort(field), opts.sortState() -> field, desc
function Table.New(parent, columns, opts)
    local self = setmetatable({ parent = parent, columns = columns, opts = opts or {}, widgets = {}, offset = 0, lines = {} }, Obj)
    self.headers = {}
    local x = 4
    for c, col in ipairs(columns) do
        local h = CreateFrame("Button", nil, parent)
        h:SetSize(col.width, ROW_H)
        h:SetPoint("TOPLEFT", x, -(self.opts.top or 0))
        h.text = W.Text(h, "small", "muted")
        h.text:SetPoint("LEFT")
        h:SetScript("OnClick", function()
            if self.opts.onSort and col.field then self.opts.onSort(col.field) end
        end)
        self.headers[c] = h
        x = x + col.width + 4
    end
    self.width = x
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

function Obj:Line(i)
    local w = self.widgets[i]
    if w then return w end
    w = CreateFrame("Button", nil, self.parent)
    w:SetHeight(ROW_H)
    w:SetPoint("TOPLEFT", 4, -(self.opts.top or 0) - ROW_H * i - 2)
    w:SetPoint("RIGHT", self.parent, "RIGHT", -4, 0)
    w.alt = W.Background(w, "rowAlt")
    w.cells = {}
    local cx = 0
    for c, col in ipairs(self.columns) do
        local fs = W.Text(w, "body", "text")
        fs:SetPoint("LEFT", cx, 0)
        fs:SetWidth(col.width)
        fs:SetWordWrap(false)
        w.cells[c] = fs
        cx = cx + col.width + 4
    end
    w.full = W.Text(w, "body", "text")
    w.full:SetPoint("LEFT", 0, 0)
    w.full:SetPoint("RIGHT", -90, 0)
    w.full:SetWordWrap(false)
    w.action = W.Button(w, "", 80, ROW_H - 2)
    w.action:SetPoint("RIGHT", 0, 0)
    w:SetScript("OnClick", function(btn)
        if btn.line and btn.line.onClick then btn.line.onClick() end
    end)
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

function Obj:Render()
    local field, desc = nil, nil
    if self.opts.sortState then field, desc = self.opts.sortState() end
    for c, col in ipairs(self.columns) do
        local label = col.label
        if field and col.field == field then label = label .. (desc and " v" or " ^") end
        self.headers[c].text:SetText(label)
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
                    local text = line.cells[c] or ""
                    if c == 1 and line.indent then text = "    " .. text end
                    w.cells[c]:SetText(text)
                    W.SetTextRole(w.cells[c], line.kind == "total" and "heading" or (line.muted and "muted" or "text"))
                    w.cells[c]:Show()
                end
            else
                for c = 1, #self.columns do w.cells[c]:Hide() end
                w.full:SetText((line.indent and "    " or "") .. (line.text or ""))
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
