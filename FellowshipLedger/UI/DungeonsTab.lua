-- UI/DungeonsTab.lua
-- Dungeons tab (D-094): range buttons, a character drop-down (all my characters or
-- one), a summary line, and one scrolling list: runs per dungeon, friends' totals,
-- and my runs, each opening to its bosses. The lines come from UI/DungeonsModel.lua.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local DungeonsTab = {}
ns.DungeonsTab = DungeonsTab

local state = { range = "all", char = nil, expanded = {} }
local ui = {}
DungeonsTab.state, DungeonsTab.ui = state, ui -- for tests

local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

local function charLabel(key)
    local c = key and ns.Data.Characters()[key]
    if not c then return L.DUNGEONS_ALL_CHARS end
    local text = c.display or c.name or key
    if key == ns.Store.key and not ns.Data.IsFake() then text = text .. " " .. L.FRIEND_PLAYING end
    return text
end

-- My characters that have runs, A-Z.
local function charsWithRuns()
    local keys = {}
    for key, c in pairs(ns.Data.Characters()) do
        if #(c.dungeons or {}) > 0 or (c.currentRun and not c.currentRun.pending) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return charLabel(a):lower() < charLabel(b):lower() end)
    return keys
end

local function pick(key)
    state.char = key
    DungeonsTab.Refresh()
end

-- The game's menu (verified on Forever and retail via x:graphs.menu); without it
-- the button cycles All -> each character -> All.
function DungeonsTab.OpenCharMenu(owner)
    local keys = charsWithRuns()
    if not ns.Compat.IsDisabled("graphs.menu") then
        local ok = ns.Compat.Call("graphs.menu", "MenuUtil.CreateContextMenu", owner, function(_, root)
            local fine, err = pcall(function()
                root:CreateRadio(L.DUNGEONS_ALL_CHARS, function() return state.char == nil end, function() pick(nil) end)
                root:CreateDivider()
                for _, key in ipairs(keys) do
                    root:CreateRadio(charLabel(key), function() return state.char == key end, function() pick(key) end)
                end
            end)
            if not fine then ns.Compat.Disable("graphs.menu", "menu could not be filled: " .. tostring(err)) end
        end)
        if ok and not ns.Compat.IsDisabled("graphs.menu") then return end
    end
    local i = 0
    for j, key in ipairs(keys) do if key == state.char then i = j end end
    pick(keys[i + 1])
end

function DungeonsTab.Lines()
    local today = ns.Store.Today()
    local good = ns.Palette.Code(W.Color("good"))
    return ns.DungeonsModel.Lines({
        chars = ns.Data.Characters(), friends = ns.Data.Friends(),
        isBlocked = function(f, key) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f, key) end,
        charKey = state.char, fromKey = ns.Days.RangeStart(state.range, today, time, date), todayKey = today,
        now = time(), dateFn = date, L = L, expanded = state.expanded,
        toggle = function(runKey)
            state.expanded[runKey] = not state.expanded[runKey] or nil
            DungeonsTab.Refresh()
        end,
        nameOf = function(text, class) return W.ClassName(text, class) end,
        goodCode = good,
    })
end

function DungeonsTab.Refresh()
    if not ui.table then return end
    for range, b in pairs(ui.rangeButtons) do b:SetSelected(range == state.range) end
    if state.char and not ns.Data.Characters()[state.char] then state.char = nil end
    ui.charButton.text:SetText(charLabel(state.char))
    local lines, sum = DungeonsTab.Lines()
    ui.summary:SetText(string.format(L.DUNGEONS_SUMMARY, sum.runs, sum.completed, sum.bosses, sum.deaths))
    ui.table:SetLines(lines)
end

local function build(panel)
    ui.rangeButtons = {}
    local x = 4
    for _, range in ipairs(ns.Days.RANGES) do
        local b = W.Button(panel, L[RANGE_LABEL[range]], 80, 20, function()
            state.range = range
            DungeonsTab.Refresh()
        end)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + 86
        ui.rangeButtons[range] = b
    end
    ui.charButton = W.Button(panel, L.DUNGEONS_ALL_CHARS, 220, 20, function(self) DungeonsTab.OpenCharMenu(self) end)
    ui.charButton:SetPoint("TOPLEFT", x + 12, -2)
    ui.summary = W.Text(panel, "small", "muted")
    ui.summary:SetPoint("TOPRIGHT", -4, -6)
    ui.summary:SetJustifyH("RIGHT")
    ui.table = ns.Table.New(panel, { { label = "", width = 100 } }, { top = 30 })
    ui.table:SetHeadersShown(false)
end

ns.MainWindow.RegisterTab("dungeons", build, function() DungeonsTab.Refresh() end)
