-- UI/Graph.lua
-- A bar chart drawn with plain textures: gridlines with value labels, a zero line,
-- one bar per point, x labels, and a hover tooltip per bar. Colors come from the
-- colorblind-safe or brand series palette; meaning never relies on color alone
-- (tooltips give exact values, negatives sit below the zero line, partial levels
-- are hatched lighter and labelled in the tooltip).

local _, ns = ...
local W = ns.Widgets
local GraphModel = ns.GraphModel

local Graph = {}
ns.Graph = Graph

local Obj = {}
Obj.__index = Obj

local LEFT, BOTTOM, TOP = 64, 22, 8

function Graph.New(parent)
    local self = setmetatable({ parent = parent, bars = {}, grid = {}, xlabels = {} }, Obj)
    self.plot = CreateFrame("Frame", nil, parent)
    self.plot:SetPoint("TOPLEFT", LEFT, -TOP)
    self.plot:SetPoint("BOTTOMRIGHT", -8, BOTTOM)
    W.Background(self.plot, "panel", 0.5)
    self.zero = self.plot:CreateTexture(nil, "ARTWORK")
    W.Fill(self.zero, "text", 0.8)
    self.zero:SetHeight(1)
    self.empty = W.Text(parent, "body", "muted")
    self.empty:SetPoint("CENTER", self.plot, "CENTER")
    -- Redraw at the real size whenever the plot is resized.
    self.plot:SetScript("OnSizeChanged", function()
        if self.points and not ns.MainWindow.sizing then self:Render() end
    end)
    return self
end

local function size(frame, fallbackW, fallbackH)
    local w, h = frame:GetWidth(), frame:GetHeight()
    if type(w) ~= "number" or w < 50 then w = fallbackW end
    if type(h) ~= "number" or h < 50 then h = fallbackH end
    return w, h
end

function Obj:Bar(i)
    local b = self.bars[i]
    if b then return b end
    b = CreateFrame("Button", nil, self.plot)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b:SetScript("OnEnter", function(btn)
        if btn.point then W.Tooltip(btn, btn.point.note or btn.point.label, { btn.valueText }) end
    end)
    b:SetScript("OnLeave", function() W.HideTooltip() end)
    self.bars[i] = b
    return b
end

-- points: from GraphModel; chart: id (for value formatting); seriesIndex: palette slot.
-- compare (optional): { points = second series, nameA, nameB } - drawn as paired bars,
-- A on the left of each pair and B on the right (position, not just color, tells them apart).
function Obj:SetData(points, chart, seriesIndex, emptyText, compare)
    self.points = points or {}
    self.chart = chart
    self.seriesIndex = seriesIndex or 1
    self.emptyText = emptyText
    self.compare = compare
    self:Render()
end

local function rowsFor(self)
    if self.compare then return GraphModel.Align(self.points, self.compare.points) end
    local rows = {}
    for i, p in ipairs(self.points) do
        rows[i] = { label = p.label, note = p.note, a = p.value, partialA = p.partial }
    end
    return rows
end

function Obj:Render()
    local w, h = size(self.plot, 700, 300)
    for _, b in ipairs(self.bars) do b:Hide() end
    for _, g in ipairs(self.grid) do g.line:Hide(); g.label:Hide() end
    for _, x in pairs(self.xlabels) do x:Hide() end
    local rows = rowsFor(self)
    local values, hasData = {}, false
    for _, r in ipairs(rows) do
        for _, v in ipairs({ r.a or 0, r.b or 0 }) do
            values[#values + 1] = { value = v }
            if v ~= 0 then hasData = true end
        end
    end
    self.empty:SetShown(not hasData)
    self.empty:SetText(self.emptyText or "")
    self.zero:SetShown(hasData)
    if not hasData then return end

    local layout = GraphModel.Layout(values, h, GraphModel.IsInteger(self.chart))
    -- Gridlines and value labels.
    local i = 0
    local v = layout.lo
    while v <= layout.hi + layout.step / 2 do
        i = i + 1
        local g = self.grid[i]
        if not g then
            g = { line = self.plot:CreateTexture(nil, "BORDER"), label = W.Text(self.parent, "small", "muted") }
            W.Fill(g.line, "rule", 0.35)
            g.line:SetHeight(1)
            g.label:SetJustifyH("RIGHT")
            g.label:SetWidth(LEFT - 6)
            self.grid[i] = g
        end
        local y = (v - layout.lo) / (layout.hi - layout.lo) * h
        g.line:ClearAllPoints()
        g.line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
        g.line:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)
        g.line:Show()
        g.label:ClearAllPoints()
        g.label:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -4, y)
        g.label:SetText(GraphModel.FormatValue(self.chart, v))
        g.label:Show()
        v = v + layout.step
    end
    self.zero:ClearAllPoints()
    self.zero:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, layout.zeroY)
    self.zero:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, layout.zeroY)

    local n = #rows
    local slot = w / n
    local pair = self.compare ~= nil
    local barW = math.max(2, math.floor(slot * (pair and 0.4 or 0.7)))
    local colorblind = ns.db.settings.colorblind ~= false
    local colorA = ns.Palette.Series(colorblind, pair and 1 or self.seriesIndex)
    local colorB = ns.Palette.Series(colorblind, 2)
    local negColor = ns.Palette.Series(colorblind, (pair and 1 or self.seriesIndex) + 2)
    local labelEvery = GraphModel.LabelEvery(n, w)
    local k = 0
    local function bar(idx, offset, value, partial, color, text, row)
        k = k + 1
        local b = self:Bar(k)
        local y, bh = layout.bar(value)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", (idx - 1) * slot + offset, 0)
        b:SetSize(barW, h)
        b.fill:ClearAllPoints()
        b.fill:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, y)
        b.fill:SetSize(barW, math.max(1, bh))
        W.FillRGB(b.fill, value < 0 and negColor or color, partial and 0.45 or 1)
        b.point = { label = row.label, note = row.note }
        b.valueText = text
        b:Show()
    end
    for idx, row in ipairs(rows) do
        if pair then
            local text = string.format("%s: %s   %s: %s", self.compare.nameA,
                row.a and GraphModel.FormatValue(self.chart, row.a) or "-", self.compare.nameB,
                row.b and GraphModel.FormatValue(self.chart, row.b) or "-")
            local left = (slot - 2 * barW - 2) / 2
            if row.a then bar(idx, left, row.a, row.partialA, colorA, text, row) end
            if row.b then bar(idx, left + barW + 2, row.b, row.partialB, colorB, text, row) end
        else
            local text = GraphModel.FormatValue(self.chart, row.a) .. (row.partialA and (" " .. ns.L.PARTIAL) or "")
            bar(idx, (slot - barW) / 2, row.a, row.partialA, colorA, text, row)
        end
        if (idx - 1) % labelEvery == 0 then
            local x = self.xlabels[idx]
            if not x then
                x = W.Text(self.parent, "small", "muted")
                x:SetJustifyH("CENTER")
                self.xlabels[idx] = x
            end
            x:ClearAllPoints()
            x:SetPoint("TOP", self.plot, "BOTTOMLEFT", (idx - 0.5) * slot, -4)
            x:SetText(row.label)
            x:Show()
        end
    end
end
