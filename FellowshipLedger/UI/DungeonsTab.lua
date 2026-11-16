-- UI/DungeonsTab.lua
-- Dungeons tab (D-094; redrawn in 1.14.0, D-140): three views as joined tabs, By
-- dungeon, Runs and Friends, with the range buttons and a character drop-down. By
-- dungeon and Runs are a list on the left and the chosen one on the right (like Quest
-- chains); Friends is the friends' totals. The lines come from UI/DungeonsModel.lua.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local DM = ns.DungeonsModel

local DungeonsTab = {}
ns.DungeonsTab = DungeonsTab

-- expanded: kept for /fl shots (an opened run there is the chosen run now).
local state = { range = "all", char = nil, view = "dungeons", dungeon = nil, run = nil, expanded = {} }
local ui = {}
DungeonsTab.state, DungeonsTab.ui = state, ui -- for tests
DungeonsTab.LIST_W = 320
DungeonsTab.SUMMARY_MIN_W = 900

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

local function nameOf(text, class) return W.ClassName(text, class) end
local function isBlocked(f, key) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f, key) end

-- My runs in the range (and for the chosen character), newest first.
function DungeonsTab.Runs()
    local today = ns.Store.Today()
    return DM.Runs(ns.Data.Characters(), state.char, ns.Days.RangeStart(state.range, today, time, date), date, time())
end

-- The Leaderboard's boards (at level), by dungeon, and every entry (for #1's splits).
local function boards()
    local fake = ns.Data.IsFake()
    local chars = fake and ns.Data.Characters() or ns.db.characters
    local friends = fake and ns.Data.Friends() or ns.db.friends
    local ok, entries = pcall(ns.Leaderboard.Entries, chars, friends, isBlocked, function(_, c) return c.display or c.name end)
    if not ok then return {}, {} end
    local copy = {}
    for i, e in ipairs(entries) do copy[i] = e end
    local okB, board = pcall(ns.Leaderboard.Build, copy, true)
    local by = {}
    for _, d in ipairs(okB and board or {}) do by[d.dungeon] = d end
    return by, entries
end

-- Open one of my runs on Runs (the dungeon timer's "Open the run", a recent run).
-- key: "charKey|entered", or just the entered time of a run of the character played.
function DungeonsTab.OpenRun(key)
    if type(key) == "number" then key = tostring(ns.Store.key) .. "|" .. tostring(key) end
    state.view, state.run, state.range, state.char = "runs", key, "all", nil
    ns.MainWindow.Open("dungeons")
    DungeonsTab.Refresh()
end

local function selectView(id)
    state.view = id
    DungeonsTab.Refresh()
end

function DungeonsTab.Refresh()
    if not ui.list then return end
    for range, b in pairs(ui.rangeButtons) do b:SetSelected(range == state.range) end
    if state.char and not ns.Data.Characters()[state.char] then state.char = nil end
    ui.charButton.text:SetText(charLabel(state.char))
    local runs = DungeonsTab.Runs()
    local sum = DM.Summary(runs)
    ui.summary:SetText(string.format(L.DUNGEONS_SUMMARY, sum.runs, sum.completed, sum.bosses, sum.deaths))
    -- The summary only when the window is wide enough for it beside the buttons.
    local pw = ui.panel:GetWidth()
    ui.summary:SetShown(type(pw) ~= "number" or pw >= DungeonsTab.SUMMARY_MIN_W)
    local by = DM.ByDungeon(runs, time())
    ui.views.buttons.dungeons.text:SetText(string.format(L.DUNGEONS_VIEW_BY, #by))
    ui.views.buttons.runs.text:SetText(string.format(L.DUNGEONS_VIEW_RUNS, #runs))
    ui.views:Select(state.view)
    local split = state.view ~= "friends"
    ui.split:SetShown(split)
    ui.friends:SetShown(not split)
    if state.view == "friends" then
        local today = ns.Store.Today()
        ui.friendTable:SetLines(DM.FriendLines({ L = L, friends = ns.Data.Friends(), isBlocked = isBlocked,
            fromKey = ns.Days.RangeStart(state.range, today, time, date), todayKey = today, nameOf = nameOf }))
        return
    end
    if state.view == "runs" then
        -- An opened run from before (/fl shots, D-094's expanded) becomes the chosen one.
        for k in pairs(state.expanded) do state.run = k; state.expanded[k] = nil end
        local chosen
        for _, e in ipairs(runs) do if DM.RunKey(e) == state.run then chosen = e end end
        chosen = chosen or runs[1]
        state.run = chosen and DM.RunKey(chosen) or nil
        ui.list:SetLines(DM.RunListLines(runs, state.run, L, { nameOf = nameOf, dateFn = date, now = time(),
            onSelect = function(key) state.run = key; DungeonsTab.Refresh() end }))
        -- Your fastest other clear of the same dungeon, for "vs your best".
        local best
        if chosen then
            for _, e in ipairs(DM.Runs(ns.Data.Characters(), nil, nil, date, time())) do
                local t = e.run.name == chosen.run.name and e ~= chosen and DM.ClearTime(e.run)
                if t and DM.RunKey(e) ~= state.run and (not best or t < best) then best = t end
            end
        end
        ui.detail:SetLines(DM.RunDetailLines(chosen, { L = L, nameOf = nameOf, dateFn = date, now = time(), best = best }))
        return
    end
    local chosen
    for _, d in ipairs(by) do if d.name == state.dungeon then chosen = d end end
    chosen = chosen or by[1]
    state.dungeon = chosen and chosen.name or nil
    local boardOf, entries = boards()
    ui.list:SetLines(DM.DungeonListLines(by, boardOf, state.dungeon, L,
        { onSelect = function(name) state.dungeon = name; DungeonsTab.Refresh() end }))
    local leader
    if chosen then
        local ok, t = pcall(ns.RunTimer.Target, entries, chosen.name, "leader", nil)
        leader = ok and t or nil
    end
    ui.detail:SetLines(DM.DungeonDetailLines(chosen, { L = L, board = chosen and boardOf[chosen.name], leader = leader,
        entries = chosen and chosen.entries, nameOf = nameOf, dateFn = date,
        onRun = function(key) state.view, state.run = "runs", key; DungeonsTab.Refresh() end,
        onAllRuns = function() state.view = "runs"; DungeonsTab.Refresh() end }))
end

local function build(panel)
    ui.views = W.Segmented(panel, {
        { id = "dungeons", label = string.format(L.DUNGEONS_VIEW_BY, 0), width = 104 },
        { id = "runs", label = string.format(L.DUNGEONS_VIEW_RUNS, 0), width = 72 },
        { id = "friends", label = L.DUNGEONS_VIEW_FRIENDS, width = 70 },
    }, selectView, 20)
    ui.views:SetPoint("TOPLEFT", 4, -2)
    ui.ranges = ns.MeTab.RangeGroup(panel, function(range)
        state.range = range
        DungeonsTab.Refresh()
    end, 58)
    ui.ranges:SetPoint("LEFT", ui.views, "RIGHT", 10, 0)
    ui.rangeButtons = ui.ranges.buttons
    ui.charButton = W.Button(panel, L.DUNGEONS_ALL_CHARS, 150, 20, function(self) DungeonsTab.OpenCharMenu(self) end)
    ui.charButton:SetPoint("LEFT", ui.ranges, "RIGHT", 10, 0)
    ui.panel = panel
    ui.summary = W.Text(panel, "small", "muted")
    ui.summary:SetPoint("TOPRIGHT", -4, -6)
    ui.summary:SetJustifyH("RIGHT")
    -- The list and the pane.
    ui.split = CreateFrame("Frame", nil, panel)
    ui.split:SetPoint("TOPLEFT", 0, -30)
    ui.split:SetPoint("BOTTOMRIGHT", 0, 0)
    local left = CreateFrame("Frame", nil, ui.split)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(DungeonsTab.LIST_W)
    W.Background(left, "panel")
    W.Border(left, "rule", 1)
    local right = CreateFrame("Frame", nil, ui.split)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Background(right, "panel")
    W.Border(right, "rule", 1)
    ui.list = ns.Table.New(left, {}, { top = -16 })
    ui.list.rule:Hide()
    ui.detail = ns.Table.New(right, {}, { top = -12 })
    ui.detail.rule:Hide()
    -- Friends: one table.
    ui.friends = CreateFrame("Frame", nil, panel)
    ui.friends:SetPoint("TOPLEFT", 0, 0)
    ui.friends:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.friendTable = ns.Table.New(ui.friends, { { label = "", width = 100 } }, { top = 30 })
    ui.friendTable:SetHeadersShown(false)
    ui.friends:Hide()
end

ns.MainWindow.RegisterTab("dungeons", build, function() DungeonsTab.Refresh() end)
