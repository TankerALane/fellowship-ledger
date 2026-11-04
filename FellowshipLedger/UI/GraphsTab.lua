-- UI/GraphsTab.lua
-- Graphs tab: pick a character (yours or a friend's) and a chart: levels per
-- session, time per level, quests per day, gold per session, XP per hour.
-- Compare overlay: a second character as paired bars (Time per level, Quests per day).

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local GraphModel = ns.GraphModel

local GraphsTab = {}
ns.GraphsTab = GraphsTab

local state = { chart = "timePerLevel", index = 1, days = 30, compare = nil }
local ui = {}

local function characters()
    return ns.Data.GraphableCharacters()
end

function GraphsTab.Refresh()
    if not ui.graph then return end
    local list = characters()
    if state.index > #list then state.index = 1 end
    local entry = list[state.index]
    for id, b in pairs(ui.chartButtons) do b:SetSelected(id == state.chart) end
    ui.charLabel:SetText(entry and string.format(L.GRAPH_CHARACTER, entry.label, state.index, #list) or L.GRAPH_NO_CHARACTER)
    ui.title:SetText(L["CHART_" .. state.chart:upper()] .. "  -  " .. L["CHART_" .. state.chart:upper() .. "_HINT"])
    if not entry then
        ui.graph:SetData({}, state.chart, 1, L.GRAPH_EMPTY)
        return
    end
    local points = GraphModel.Build(state.chart, entry.char, ns.Store.Today(), time, date, state.days)
    local series = 1
    for i, id in ipairs(GraphModel.CHARTS) do if id == state.chart then series = i end end
    -- Compare overlay
    local other = state.compare and list[state.compare]
    if other == entry then other = nil end
    local compare
    if other and GraphModel.CanCompare(state.chart) then
        compare = { points = GraphModel.Build(state.chart, other.char, ns.Store.Today(), time, date, state.days),
            nameA = entry.label, nameB = other.label }
        ui.legend:SetText(string.format(L.COMPARE_LEGEND, entry.label, other.label))
    elseif other then
        ui.legend:SetText(L.COMPARE_NOT_THIS_CHART)
    else
        ui.legend:SetText("")
    end
    ui.compareButton.text:SetText(other and string.format(L.COMPARE_WITH, other.label) or L.COMPARE_OFF)
    ui.graph:SetData(points, state.chart, series, L.GRAPH_EMPTY, compare)
end

local function build(panel)
    ui.chartButtons = {}
    local x = 4
    for _, id in ipairs(GraphModel.CHARTS) do
        local b = W.Button(panel, L["CHART_" .. id:upper()], 132, 20, function()
            state.chart = id
            GraphsTab.Refresh()
        end)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + 136
        ui.chartButtons[id] = b
    end
    local prev = W.Button(panel, "<", 24, 20, function()
        local n = #characters()
        state.index = (state.index - 2) % math.max(1, n) + 1
        GraphsTab.Refresh()
    end)
    prev:SetPoint("TOPLEFT", 4, -28)
    local nextB = W.Button(panel, ">", 24, 20, function()
        local n = #characters()
        state.index = state.index % math.max(1, n) + 1
        GraphsTab.Refresh()
    end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    ui.charLabel = W.Text(panel, "body", "text")
    ui.charLabel:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    ui.title = W.Text(panel, "small", "muted")
    ui.title:SetPoint("TOPLEFT", 4, -54)
    -- Compare: cycles Off -> each other character -> Off.
    ui.compareButton = W.Button(panel, L.COMPARE_OFF, 240, 20, function()
        local n = #characters()
        local nextIndex = (state.compare or 0) + 1
        if nextIndex == state.index then nextIndex = nextIndex + 1 end
        if nextIndex > n then state.compare = nil else state.compare = nextIndex end
        GraphsTab.Refresh()
    end)
    ui.compareButton:SetPoint("TOPRIGHT", -4, -28)
    ui.legend = W.Text(panel, "small", "text")
    ui.legend:SetPoint("TOPRIGHT", -4, -54)
    ui.legend:SetJustifyH("RIGHT")

    local area = CreateFrame("Frame", nil, panel)
    area:SetPoint("TOPLEFT", 0, -72)
    area:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.graph = ns.Graph.New(area)
end

ns.MainWindow.RegisterTab("graphs", build, function() GraphsTab.Refresh() end)
