-- UI/GraphsTab.lua
-- Graphs tab: pick a character (yours or a friend's) and a chart: levels per
-- session, time per level, quests per day, gold per session, XP per hour.
-- The compare overlay arrives with sharing in Phase 3.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local GraphModel = ns.GraphModel

local GraphsTab = {}
ns.GraphsTab = GraphsTab

local state = { chart = "timePerLevel", index = 1, days = 30 }
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
    ui.graph:SetData(points, state.chart, series, L.GRAPH_EMPTY)
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

    local area = CreateFrame("Frame", nil, panel)
    area:SetPoint("TOPLEFT", 0, -72)
    area:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.graph = ns.Graph.New(area)
end

ns.MainWindow.RegisterTab("graphs", build, function() GraphsTab.Refresh() end)
