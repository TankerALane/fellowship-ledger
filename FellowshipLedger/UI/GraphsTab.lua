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

-- shown / compare: character keys (Data.GraphableCharacters), so a choice stays on
-- the same character when friends' data arrives. shown nil = the one I am playing.
local state = { chart = "timePerLevel", shown = nil, days = 30, compare = nil }
local ui = {}

local function characters()
    return ns.Data.GraphableCharacters()
end

local function find(list, key)
    if not key then return nil end
    for i, e in ipairs(list) do if e.key == key then return i, e end end
    return nil
end

-- The character on show: the chosen one, else the one being played, else the first.
local function current(list)
    local i, e = find(list, state.shown)
    if i then return i, e end
    for j, x in ipairs(list) do if x.playing and x.mine then return j, x end end
    return (list[1] and 1 or nil), list[1]
end

local function itemText(item)
    return item.playing and (item.label .. " " .. L.FRIEND_PLAYING) or item.label
end

-- A drop-down of characters, grouped (GraphModel.CompareGroups). withOff adds
-- "Compare off" on top. Uses the game's menu (MenuUtil); if that is missing or
-- fails, the feature "graphs.menu" is turned off once and the caller falls back.
GraphsTab.menuStatus = nil -- for /fl verify (x:graphs.menu)
function GraphsTab.OpenMenu(owner, skipKey, withOff, selected, pick)
    if ns.Compat.IsDisabled("graphs.menu") then return false end
    local groups = GraphModel.CompareGroups(characters(), skipKey, L)
    local function fill(root)
        local n = 0
        if type(root.SetScrollMode) == "function" then root:SetScrollMode(480) end
        if withOff then
            root:CreateRadio(L.COMPARE_MENU_OFF, function() return selected() == nil end, function() pick(nil) end)
            n = n + 1
        end
        for gi, g in ipairs(groups) do
            if withOff or gi > 1 then root:CreateDivider() end
            root:CreateTitle(g.title)
            for _, item in ipairs(g.items) do
                local key = item.key
                root:CreateRadio(itemText(item), function() return selected() == key end, function() pick(key) end)
                n = n + 1
            end
        end
        return n
    end
    local ok = ns.Compat.Call("graphs.menu", "MenuUtil.CreateContextMenu", owner, function(_, root)
        local fine, n = pcall(fill, root)
        GraphsTab.menuStatus = { at = time(), ok = fine, items = fine and n or nil, err = not fine and tostring(n) or nil }
        if not fine then ns.Compat.Disable("graphs.menu", "menu could not be filled: " .. tostring(n)) end
    end)
    if not ok and not GraphsTab.menuStatus then
        GraphsTab.menuStatus = { at = time(), ok = false, err = tostring(ns.Compat.disabled["graphs.menu"]) }
    end
    return ok and not ns.Compat.IsDisabled("graphs.menu")
end

function GraphsTab.Refresh()
    if not ui.graph then return end
    local list = characters()
    local index, entry = current(list)
    for id, b in pairs(ui.chartButtons) do b:SetSelected(id == state.chart) end
    ui.charButton.text:SetText(entry and string.format(L.GRAPH_CHARACTER, itemText({ label = entry.label, playing = entry.playing }), index, #list)
        or L.GRAPH_NO_CHARACTER)
    ui.title:SetText(L["CHART_" .. state.chart:upper()] .. "  -  " .. L["CHART_" .. state.chart:upper() .. "_HINT"])
    if not entry then
        ui.graph:SetData({}, state.chart, 1, L.GRAPH_EMPTY)
        return
    end
    local points = GraphModel.Build(state.chart, entry.char, ns.Store.Today(), time, date, state.days)
    local series = 1
    for i, id in ipairs(GraphModel.CHARTS) do if id == state.chart then series = i end end
    -- Compare overlay
    local _, other = find(list, state.compare)
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

-- Step the shown character with < and > (wraps).
local function step(delta)
    local list = characters()
    local n = #list
    if n == 0 then return end
    local i = current(list) or 1
    state.shown = list[(i - 1 + delta) % n + 1].key
    GraphsTab.Refresh()
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
    local prev = W.Button(panel, "<", 24, 20, function() step(-1) end)
    prev:SetPoint("TOPLEFT", 4, -28)
    local nextB = W.Button(panel, ">", 24, 20, function() step(1) end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    -- The shown character: a drop-down of every character, grouped like Compare.
    ui.charButton = W.Button(panel, "", 300, 20, function(self)
        GraphsTab.OpenMenu(self, nil, false, function()
            local _, e = current(characters())
            return e and e.key
        end, function(key)
            state.shown = key
            GraphsTab.Refresh()
        end)
    end)
    ui.charButton:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    ui.charLabel = ui.charButton.text -- older name, kept for tests
    ui.title = W.Text(panel, "small", "muted")
    ui.title:SetPoint("TOPLEFT", 4, -54)
    -- Compare: a drop-down (Compare off, your characters, each Battle.net friend's
    -- characters, other friends). Without the game's menu it cycles as before.
    ui.compareButton = W.Button(panel, L.COMPARE_OFF, 240, 20, function(self)
        local list = characters()
        local _, entry = current(list)
        local shownKey = entry and entry.key
        if GraphsTab.OpenMenu(self, shownKey, true, function() return state.compare end, function(key)
            state.compare = key
            GraphsTab.Refresh()
        end) then return end
        -- Fallback: Off -> each other character -> Off.
        local i = find(list, state.compare) or 0
        repeat i = i + 1 until not list[i] or list[i].key ~= shownKey
        state.compare = list[i] and list[i].key or nil
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

GraphsTab.state, GraphsTab.ui = state, ui -- for tests

ns.MainWindow.RegisterTab("graphs", build, function() GraphsTab.Refresh() end)
