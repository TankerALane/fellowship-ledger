-- UI/MeTab.lua
-- Me tab: ranges, a totals line, a sortable table with one row per character
-- (click a row for its per-level times), and a "Quest chains" view of the quests
-- in your log.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MeModel = ns.MeModel

local Me = {}
ns.MeTab = Me

local state = { range = "today", sort = "level", desc = true, expanded = {}, mode = "characters" }
local ui = {}

local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

local function cellsFor(row)
    local cells = {}
    for c, col in ipairs(MeModel.COLUMNS) do
        local text = MeModel.FormatCell(col, row)
        if c == 1 and row.key then text = (state.expanded[row.key] and "- " or "+ ") .. W.ClassName(text, row.class) end
        cells[c] = text
    end
    return cells
end

local function characterLines()
    local chars = ns.Data.Characters()
    local rows = MeModel.Build(chars, state.range, ns.Store.Today(), time, date)
    MeModel.Sort(rows, state.sort, state.desc)
    local lines = {}
    if #rows > 1 then
        local total = MeModel.Totals(rows)
        total.name = L.TOTAL_ALL
        lines[#lines + 1] = { kind = "total", cells = (function()
            local cells = {}
            for c, col in ipairs(MeModel.COLUMNS) do cells[c] = MeModel.FormatCell(col, total) end
            cells[2] = ""
            return cells
        end)() }
    end
    for _, row in ipairs(rows) do
        local key = row.key
        lines[#lines + 1] = { kind = "row", cells = cellsFor(row), onClick = function()
            state.expanded[key] = not state.expanded[key] or nil
            Me.Refresh()
        end }
        if state.expanded[key] then
            local levelLines = MeModel.LevelLines(chars[key], L)
            if #levelLines == 0 then levelLines = { L.NO_LEVELS_YET } end
            for _, text in ipairs(levelLines) do lines[#lines + 1] = { kind = "detail", text = text, indent = true } end
            for _, text in ipairs(MeModel.RecentLines(chars[key], L, date)) do
                lines[#lines + 1] = { kind = "detail", text = text, indent = true }
            end
            if not ns.Data.IsFake() and key ~= ns.Store.key then
                lines[#lines + 1] = { kind = "detail", align = "right", text = L.REMOVE_LINE,
                    action = { label = L.REMOVE, onClick = function() Me.ConfirmRemove(key, row.name) end } }
            end
        end
    end
    return lines, #rows
end

local function chainLines()
    local lines = {}
    local entries, source = ns.QuestChains.ForLog()
    for _, e in ipairs(entries) do
        local text
        if e.step then
            text = string.format(L.CHAIN_STEP, e.title, e.chainName or L.CHAIN_UNNAMED, e.step, e.total, L["CHAIN_SOURCE_" .. e.source:upper()])
        else
            text = string.format(L.CHAIN_NONE, e.title)
        end
        lines[#lines + 1] = { kind = "detail", text = text }
    end
    if #entries == 0 then lines[1] = { kind = "detail", text = L.CHAIN_EMPTY_LOG } end
    if source == "missing" then lines[#lines + 1] = { kind = "group", text = L.CHAIN_QUESTIE_HINT } end

    -- Chains friends are on that this character has not started.
    lines[#lines + 1] = { kind = "group", text = L.CHAIN_FRIENDS_TITLE }
    local mine = {}
    local me = ns.Store.char
    for key in pairs(me and me.chains or {}) do mine[key] = true end
    local started = ns.Data.IsFake() and function() return false end or ns.QuestChains.HaveStarted
    local suggestions = ns.QuestChainLogic.FriendSuggestions(ns.Data.Friends(),
        function(f) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f) end, mine, started)
    for _, s in ipairs(suggestions) do
        local c = s.chain
        local where = c.firstName and c.startZone and string.format(L.CHAIN_STARTS_AT, c.firstName, c.startZone)
            or c.firstName and string.format(L.CHAIN_STARTS_WITH, c.firstName)
            or L.CHAIN_START_UNKNOWN
        lines[#lines + 1] = { kind = "detail", indent = true, text = string.format(L.CHAIN_FRIEND_LINE, s.friend, s.character,
            c.name or L.CHAIN_UNNAMED, c.step or 0, c.total or 0, where) }
    end
    if #suggestions == 0 then lines[#lines + 1] = { kind = "detail", indent = true, text = L.CHAIN_FRIENDS_NONE } end
    return lines
end

-- Remove one of my characters (never the one I am on), after a confirm. Friends
-- are told at the next hello, which is sent now.
function Me.ConfirmRemove(key, name)
    W.Confirm(string.format(L.REMOVE_CONFIRM, name or key), L.REMOVE_YES, L.REMOVE_NO, function()
        Me.Remove(key)
    end)
end

function Me.Remove(key)
    if key == ns.Store.key then return end
    if ns.Character.Remove(ns.db, key, time()) then
        state.expanded[key] = nil
        ns.Log.Info(L.REMOVED_CHARACTER, key)
        if ns.Sync and ns.tracking then pcall(ns.Sync.SyncAll, true) end
    end
    ns.MainWindow.Refresh()
end

function Me.Refresh()
    if not ui.table then return end
    for range, b in pairs(ui.rangeButtons) do
        b:SetSelected(range == state.range)
        b:SetShown(state.mode == "characters")
    end
    ui.modeButton.text:SetText(state.mode == "characters" and L.SHOW_CHAINS or L.SHOW_CHARACTERS)
    local lines, count
    if state.mode == "chains" then
        lines = chainLines()
        count = #lines
    else
        lines, count = characterLines()
    end
    ui.table:SetLines(lines)
    ui.empty:SetShown(count == 0)
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
    ui.modeButton = W.Button(panel, L.SHOW_CHAINS, 130, 20, function()
        state.mode = state.mode == "characters" and "chains" or "characters"
        Me.Refresh()
    end)
    ui.modeButton:SetPoint("TOPRIGHT", -4, -2)

    local columns = {}
    for _, col in ipairs(MeModel.COLUMNS) do columns[#columns + 1] = { label = L[col.label], width = col.width, field = col.field } end
    ui.table = ns.Table.New(panel, columns, {
        top = 30,
        onSort = function(field)
            if state.mode ~= "characters" then return end
            if state.sort == field then state.desc = not state.desc else state.sort, state.desc = field, field ~= "name" end
            Me.Refresh()
        end,
        sortState = function() return state.sort, state.desc end,
    })

    ui.empty = W.Text(panel, "body", "muted")
    ui.empty:SetPoint("TOPLEFT", 8, -80)
    ui.empty:SetText(L.NO_DATA_YET)
end

ns.MainWindow.RegisterTab("me", build, function() Me.Refresh() end)
