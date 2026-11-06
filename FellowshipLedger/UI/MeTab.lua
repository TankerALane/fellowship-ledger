-- UI/MeTab.lua
-- Me tab: ranges, a totals line, a sortable table with one row per character
-- (click a row for its levels, deaths and loot: UI/DetailModel.lua), and a "Quest chains" view of the quests
-- in your log.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MeModel = ns.MeModel

local Me = {}
ns.MeTab = Me

local state = { range = "today", sort = "level", desc = true, expanded = {}, showAll = {}, mode = "characters",
    chainOpen = {}, chainAll = {}, detailView = {}, openProf = {}, openZone = {} }
local ui = {}
Me.state, Me.ui = state, ui -- for tests

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

-- The opened character: a row of view tabs (D-081), then the view. Overview is the
-- summary card or list (Settings, D-075); "Show all" is remembered per character
-- and list until the window is reloaded.
function Me.OverviewLines(key, char, name)
    local all = state.showAll[key] or {}
    local skin = ns.db.settings.skin
    local data = ns.DetailModel.Data(char, L, date, all, ns.DetailModel.ArrowCode(ns.Palette.Color(skin, "text")))
    local removable = not ns.Data.IsFake() and key ~= ns.Store.key
    return ns.DetailModel.Lines(data, ns.db.settings.detailsLayout, L, {
        skin = skin,
        valueCode = ns.Palette.Code(ns.Palette.Color(skin, "text")),
        onToggle = function(kind)
            state.showAll[key] = state.showAll[key] or {}
            state.showAll[key][kind] = not state.showAll[key][kind] or nil
            Me.Refresh()
        end,
        onRemove = removable and function() Me.ConfirmRemove(key, name) end or nil,
    })
end

-- All completed quests of the character you are on, grouped by zone (cached until
-- the tab is picked again; the game only knows the current character's list).
function Me.CompletedGroups()
    if state.completedCache then return state.completedCache end
    local ids = ns.QuestChains.CompletedIDs()
    local c = { total = ids and #ids or 0 }
    c.questieMissing = ns.QuestChains.QuestieState() ~= "ready"
    if ids then
        c.groups, c.hidden = ns.StatsModel.GroupCompleted(ids, ns.QuestChains.QuestInfo, L, not c.questieMissing)
    end
    state.completedCache = c
    return c
end

local function toggleIn(tbl, key, sub)
    tbl[key] = tbl[key] or {}
    tbl[key][sub] = not tbl[key][sub] or nil
    Me.Refresh()
end

function Me.DetailLines(key, char, name)
    local S = ns.StatsModel
    local view = state.detailView[key] or "overview"
    local layout = ns.db.settings.detailsLayout
    local tabs = S.TabLine(view, L, function(id)
        state.detailView[key] = id
        state.completedCache = nil
        Me.Refresh()
    end)
    if view == "overview" then return S.WithTabs(tabs, Me.OverviewLines(key, char, name), layout) end

    local today = ns.Store.Today()
    local fromKey = ns.Days.RangeStart(state.range, today, time, date)
    local inRange = function(at) return type(at) == "number" and (not fromKey or date("%Y-%m-%d", at) >= fromKey) end
    local sum = ns.Days.Sum(char.days or {}, fromKey, today)
    local parts
    if view == "quests" then
        local zoneOf = function(id) return ns.QuestChains.QuestInfo(id).zone end
        parts = S.Quests(char.questLog, inRange, L, date, state.showAll[key] and state.showAll[key].quests, zoneOf,
            function() toggleIn(state.showAll, key, "quests") end)
    elseif view == "gold" then
        parts = S.Gold(sum, L)
    elseif view == "kills" then
        parts = S.Kills(sum, char.kills, state.range, L)
    elseif view == "professions" then
        parts = S.Professions(char.professions, inRange, L, date, state.openProf[key],
            function(prof) toggleIn(state.openProf, key, prof) end, sum.skillUps)
    else
        if key ~= ns.Store.key or ns.Data.IsFake() then
            parts = { { segs = { { x = 0, w = 1, text = L.STATS_COMPLETED_OTHER_CHAR, role = "muted", font = "body" } } } }
        else
            local c = Me.CompletedGroups()
            parts = S.Completed(c.groups, c.total, c.questieMissing, L, state.openZone[key],
                function(zone) toggleIn(state.openZone, key, zone) end, c.hidden)
        end
    end
    return S.Wrap(tabs, parts, layout)
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
            for _, line in ipairs(Me.DetailLines(key, chars[key], row.name)) do lines[#lines + 1] = line end
        end
    end
    return lines, #rows
end

-- Quest chains (D-078): your chains, each opening to its quests, then chains
-- friends are on that you have not started. Open and "Show all" are kept by
-- chain key until reload.
function Me.ChainView()
    local entries, source = ns.QuestChains.ForLog()
    local friends = ns.Data.Friends()
    local blocked = function(f) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f) end
    local logSet = {}
    for _, e in ipairs(entries) do logSet[e.questID] = true end
    local view = { mine = {}, friends = {}, emptyLog = #entries == 0, questieMissing = source == "missing" }

    -- One line per chain (two quests of one chain in the log: the later step counts).
    local byKey, unknown = {}, {}
    for _, e in ipairs(entries) do
        if e.step and e.key then
            local c = byKey[e.key]
            if not c then
                c = { key = e.key, name = e.chainName, total = e.total, zone = e.startZone, known = true }
                byKey[e.key] = c
                view.mine[#view.mine + 1] = c
            end
            if not c.step or e.step > c.step then c.step, c.anchor = e.step, e.questID end
        else
            unknown[#unknown + 1] = { known = false, title = e.title }
        end
    end
    table.sort(view.mine, function(a, b) return tostring(a.name) < tostring(b.name) end)
    for _, c in ipairs(view.mine) do
        c.open, c.showAll = state.chainOpen[c.key], state.chainAll[c.key]
        if c.open then
            c.details = ns.QuestChains.Details(c.key, c.anchor, logSet)
            c.friendsOn = ns.QuestChainLogic.FriendsOn(friends, blocked, c.key, ns.QuestChains.FriendChains)
        end
    end
    for _, u in ipairs(unknown) do view.mine[#view.mine + 1] = u end

    local mine = {}
    local me = ns.Store.char
    for key in pairs(me and me.chains or {}) do mine[key] = true end
    local started = ns.Data.IsFake() and function() return false end or ns.QuestChains.HaveStarted
    for _, s in ipairs(ns.QuestChainLogic.FriendSuggestions(friends, blocked, mine, started, ns.QuestChains.FriendChains)) do
        local c = { key = s.key, name = s.chain.name, friend = s.friend, character = s.character, step = s.chain.step,
            total = s.chain.total, zone = s.chain.startZone, open = state.chainOpen[s.key], showAll = state.chainAll[s.key] }
        if c.open then
            c.details = ns.QuestChains.Details(s.key, nil, logSet)
            c.next = c.details and c.details.next
        end
        view.friends[#view.friends + 1] = c
    end
    return view
end

local function chainLines()
    local skin = ns.db.settings.skin
    local Palette = ns.Palette
    return ns.ChainModel.Lines(Me.ChainView(), L, {
        playerLevel = ns.Store.char and ns.Store.char.level,
        checkCode = ns.DetailModel.IconCode("check", Palette.Color(skin, "good")),
        logCode = ns.DetailModel.IconCode("level-arrow", Palette.Color(skin, "muted")),
        onToggle = function(key)
            state.chainOpen[key] = not state.chainOpen[key] or nil
            Me.Refresh()
        end,
        onShowAll = function(key)
            state.chainAll[key] = not state.chainAll[key] or nil
            Me.Refresh()
        end,
    })
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
    ui.table:SetHeadersShown(state.mode == "characters")
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
    for _, col in ipairs(MeModel.COLUMNS) do
        columns[#columns + 1] = { label = L[col.label], width = col.width, field = col.field,
            tip = rawget(L, (col.label:gsub("^COL_", "COL_TIP_"))) }
    end
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
