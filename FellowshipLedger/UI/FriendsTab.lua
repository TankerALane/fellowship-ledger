-- UI/FriendsTab.lua
-- Friends tab: Battle.net friends under their name with their characters beneath,
-- character-only friends on their own, the same ranges as the Me tab, a "last
-- updated" column and Block buttons. Real friend data arrives with sharing in
-- Phase 3; until then this shows fake friends (/fl fake) or an explanation.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MeModel, FriendsModel = ns.MeModel, ns.FriendsModel

local FriendsTab = {}
ns.FriendsTab = FriendsTab

local state = { range = "week", weekly = false }
local ui = {}
local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

local COLUMNS = {
    { field = "name", label = "COL_CHARACTER", width = 170 },
    { field = "level", label = "COL_LEVEL", width = 40 },
    { field = "faction", label = "COL_FACTION", width = 62 },
    { field = "levels", label = "COL_LEVELS", width = 52 },
    { field = "quests", label = "COL_QUESTS", width = 54 },
    { field = "dungeons", label = "COL_DUNGEONS", width = 70 },
    { field = "moneyNet", label = "COL_GOLD", width = 104 },
    { field = "active", label = "COL_ACTIVE", width = 70 },
    { field = "lastUpdated", label = "COL_UPDATED", width = 90 },
}

local KIND = { level = "number", faction = "faction", levels = "number", quests = "number", dungeons = "pair", moneyNet = "money", active = "duration" }

function FriendsTab.Block(tag)
    ns.db.blocklist[tag] = true
    ns.MainWindow.Refresh()
end

local function weeklyLines()
    local out = { { kind = "group", text = L.WEEKLY_TITLE } }
    local list = ns.Merge.Weekly(ns.Data.Friends(), ns.db.blocklist, ns.Store.Today(), time, date)
    for _, t in ipairs(list) do
        out[#out + 1] = { kind = "detail", indent = true, text = string.format(L.WEEKLY_LINE, t.name, t.levels, t.quests,
            t.dungeons, ns.Format.Duration(t.active)) }
    end
    if #list == 0 then out[#out + 1] = { kind = "detail", indent = true, text = L.WEEKLY_EMPTY } end
    return out
end

local function lines()
    local now = time()
    local rows, hidden = FriendsModel.Build(ns.Data.Friends(), ns.db.blocklist, state.range, ns.Store.Today(), time, date)
    local out = {}
    if state.weekly then
        for _, l in ipairs(weeklyLines()) do out[#out + 1] = l end
    end
    for _, r in ipairs(rows) do
        if r.header then
            local f = r.friend
            local status = f.online and L.ONLINE or L.OFFLINE
            if ns.Merge.CompareVersions(f.version, ns.VERSION) == -1 then
                status = status .. ", " .. string.format(L.FRIEND_OLD_VERSION, f.version)
            end
            out[#out + 1] = { kind = "group", text = string.format(r.count == 1 and L.FRIEND_HEADER_ONE or L.FRIEND_HEADER, f.name or r.id, status, r.count,
                FriendsModel.Ago(now, f.lastUpdated)),
                action = { label = L.BLOCK, onClick = function() FriendsTab.Block(f.tag or r.id) end } }
        else
            local cells = {}
            for c, col in ipairs(COLUMNS) do
                if col.field == "lastUpdated" then
                    cells[c] = FriendsModel.Ago(now, r.lastUpdated)
                elseif col.field == "name" then
                    cells[c] = r.name
                else
                    cells[c] = MeModel.FormatCell({ field = col.field, kind = KIND[col.field] }, r)
                end
            end
            local friend = ns.Data.Friends()[r.friendId]
            out[#out + 1] = { kind = "row", cells = cells, indent = r.indent,
                action = (not r.indent) and { label = L.BLOCK, onClick = function() FriendsTab.Block(friend.tag or r.key) end } or nil }
        end
    end
    if hidden > 0 then out[#out + 1] = { kind = "detail", text = string.format(L.BLOCKED_HIDDEN, hidden) } end
    return out, #rows
end

function FriendsTab.Refresh()
    if not ui.table then return end
    for range, b in pairs(ui.rangeButtons) do b:SetSelected(range == state.range) end
    ui.weeklyButton:SetSelected(state.weekly)
    if ns.Data.IsFake() then
        ui.status:SetText(L.SYNC_STATUS_FAKE)
    else
        local online = 0
        for _, peer in pairs(ns.Friends and ns.Friends.peers or {}) do if peer.online then online = online + 1 end end
        local last = ns.Sync and ns.Sync.lastSyncAt and FriendsModel.Ago(time(), ns.Sync.lastSyncAt) or L.NEVER
        local waiting = ns.Transport and #ns.Transport.queue or 0
        local held = waiting > 0 and ns.Transport.Blocked()
        if held then
            ui.status:SetText(string.format(L.SYNC_STATUS_HELD, online, last, waiting, held))
        else
            ui.status:SetText(string.format(L.SYNC_STATUS, online, last, waiting))
        end
    end
    local list, count = lines()
    ui.table:SetLines(list)
    -- "This week" has its own empty line; the long explanation would sit on top of it.
    ui.empty:SetShown(count == 0 and not state.weekly)
    ui.empty:SetText(ns.Data.IsFake() and L.NO_FRIENDS_FAKE or L.NO_FRIENDS_YET)
end

local function build(panel)
    ui.rangeButtons = {}
    local x = 4
    for _, range in ipairs(ns.Days.RANGES) do
        local b = W.Button(panel, L[RANGE_LABEL[range]], 80, 20, function()
            state.range = range
            FriendsTab.Refresh()
        end)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + 86
        ui.rangeButtons[range] = b
    end
    ui.weeklyButton = W.Button(panel, L.WEEKLY_BUTTON, 100, 20, function()
        state.weekly = not state.weekly
        FriendsTab.Refresh()
    end)
    ui.weeklyButton:SetPoint("TOPLEFT", x + 12, -2)
    local syncNow = W.Button(panel, L.SYNC_NOW, 100, 20, function()
        if ns.Sync and ns.tracking and not ns.Data.IsFake() then
            local n = ns.Sync.SyncAll(true)
            ns.Log.Info(n > 0 and L.SYNC_WAITING_REPLY or L.SYNC_NONE_ONLINE, n)
            -- Show the queue draining and any replies that arrive.
            for _, delay in ipairs({ 1, 4, 10 }) do
                ns.Events.After(delay, function()
                    if ns.MainWindow.frame and ns.MainWindow.frame:IsShown() then FriendsTab.Refresh() end
                end)
            end
        end
        FriendsTab.Refresh()
    end)
    syncNow:SetPoint("TOPRIGHT", -4, -2)
    ui.status = W.Text(panel, "small", "muted")
    ui.status:SetPoint("RIGHT", syncNow, "LEFT", -8, 0)
    ui.status:SetJustifyH("RIGHT")
    local columns = {}
    for _, col in ipairs(COLUMNS) do columns[#columns + 1] = { label = L[col.label], width = col.width } end
    ui.table = ns.Table.New(panel, columns, { top = 30, actions = true })
    ui.empty = W.Text(panel, "body", "muted")
    ui.empty:SetPoint("TOPLEFT", 8, -80)
    ui.empty:SetPoint("RIGHT", -8, 0)
    ui.empty:SetWordWrap(true)
end

-- While the Friends tab is on screen, keep its status and rows current.
local ticking = false
local function startTicker()
    if ticking then return end
    ticking = true
    ns.Events.Every(2, "ui", function()
        local f = ns.MainWindow.frame
        if f and f:IsShown() and ns.MainWindow.current == "friends" then FriendsTab.Refresh() end
    end)
end

-- Opening the Friends tab also starts a sync (rate-limited inside Sync).
ns.MainWindow.RegisterTab("friends", build, function()
    if ns.Sync and ns.tracking and not ns.Data.IsFake() then pcall(ns.Sync.SyncAll, false) end
    startTicker()
    FriendsTab.Refresh()
end)
