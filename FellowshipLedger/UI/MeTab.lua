-- UI/MeTab.lua
-- Me tab: range buttons and a sortable table with one row per character. Clicking a
-- row expands it to show that character's per-level times.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MeModel = ns.MeModel

local Me = {}
ns.MeTab = Me

local ROW_HEIGHT = 18
local MAX_LINES = 22

local state = { range = "today", sort = "level", desc = true, expanded = {}, offset = 0 }
local ui = {}

local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

-- Flatten rows + expanded level lines into display lines.
local function displayLines()
    local rows = MeModel.Build(ns.db.characters, state.range, ns.Store.Today(), time, date)
    MeModel.Sort(rows, state.sort, state.desc)
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = { row = row }
        if state.expanded[row.key] then
            local levelLines = MeModel.LevelLines(ns.db.characters[row.key], L)
            if #levelLines == 0 then levelLines = { L.NO_LEVELS_YET } end
            for _, text in ipairs(levelLines) do lines[#lines + 1] = { text = text } end
        end
    end
    return lines, #rows
end

function Me.Refresh()
    if not ui.lines then return end
    local lines, count = displayLines()
    if state.offset > math.max(0, #lines - MAX_LINES) then state.offset = math.max(0, #lines - MAX_LINES) end
    for i = 1, MAX_LINES do
        local widget = ui.lines[i]
        local item = lines[i + state.offset]
        widget.item = item
        if not item then
            widget:Hide()
        else
            widget:Show()
            if item.row then
                widget.detail:Hide()
                for c, col in ipairs(MeModel.COLUMNS) do
                    local text = MeModel.FormatCell(col, item.row)
                    if c == 1 then text = (state.expanded[item.row.key] and "- " or "+ ") .. text end
                    widget.cells[c]:SetText(text)
                    widget.cells[c]:Show()
                end
            else
                for c = 1, #MeModel.COLUMNS do widget.cells[c]:Hide() end
                widget.detail:SetText(item.text)
                widget.detail:Show()
            end
        end
    end
    ui.empty:SetShown(count == 0)
    for range, b in pairs(ui.rangeButtons) do b:SetSelected(range == state.range) end
    for c, col in ipairs(MeModel.COLUMNS) do
        local label = L[col.label]
        if state.sort == col.field then label = label .. (state.desc and " v" or " ^") end
        ui.headers[c].text:SetText(label)
    end
end

local function build(panel)
    ui.rangeButtons = {}
    local x = 4
    for _, range in ipairs(ns.Days.RANGES) do
        local b = W.Button(panel, L[RANGE_LABEL[range]], 80, 20, function()
            state.range = range
            Me.Refresh()
        end)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + 86
        ui.rangeButtons[range] = b
    end

    ui.headers = {}
    x = 4
    for c, col in ipairs(MeModel.COLUMNS) do
        local h = CreateFrame("Button", nil, panel)
        h:SetSize(col.width, ROW_HEIGHT)
        h:SetPoint("TOPLEFT", x, -30)
        h.text = W.Text(h, "GameFontNormalSmall", W.COLORS.darkGold)
        h.text:SetPoint("LEFT")
        h:SetScript("OnClick", function()
            if state.sort == col.field then state.desc = not state.desc else state.sort, state.desc = col.field, col.kind ~= "text" end
            Me.Refresh()
        end)
        ui.headers[c] = h
        x = x + col.width + 4
    end
    local rule = panel:CreateTexture(nil, "ARTWORK")
    W.Fill(rule, W.COLORS.gold)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 4, -30 - ROW_HEIGHT)
    rule:SetPoint("TOPRIGHT", -4, -30 - ROW_HEIGHT)

    ui.lines = {}
    for i = 1, MAX_LINES do
        local line = CreateFrame("Button", nil, panel)
        line:SetHeight(ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, -32 - ROW_HEIGHT * i)
        line:SetPoint("RIGHT", -4, 0)
        line.cells = {}
        local cx = 0
        for c, col in ipairs(MeModel.COLUMNS) do
            local fs = W.Text(line, "GameFontHighlightSmall", W.COLORS.ink)
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.width)
            fs:SetJustifyH("LEFT")
            line.cells[c] = fs
            cx = cx + col.width + 4
        end
        line.detail = W.Text(line, "GameFontHighlightSmall", W.COLORS.darkGold)
        line.detail:SetPoint("LEFT", 24, 0)
        line:SetScript("OnClick", function(self)
            if self.item and self.item.row then
                local key = self.item.row.key
                state.expanded[key] = not state.expanded[key] or nil
                Me.Refresh()
            end
        end)
        ui.lines[i] = line
    end

    ui.empty = W.Text(panel, "GameFontNormal", W.COLORS.darkGold)
    ui.empty:SetPoint("TOPLEFT", 8, -60)
    ui.empty:SetText(L.NO_DATA_YET)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        Me.Refresh()
    end)
end

ns.MainWindow.RegisterTab("me", build, function() Me.Refresh() end)
