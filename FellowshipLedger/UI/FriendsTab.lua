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

local state = { range = "week" }
local ui = {}
local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

local COLUMNS = {
    { field = "name", label = "COL_CHARACTER", width = 170 },
    { field = "level", label = "COL_LEVEL", width = 40 },
    { field = "levels", label = "COL_LEVELS", width = 52 },
    { field = "quests", label = "COL_QUESTS", width = 54 },
    { field = "dungeons", label = "COL_DUNGEONS", width = 70 },
    { field = "moneyNet", label = "COL_GOLD", width = 104 },
    { field = "active", label = "COL_ACTIVE", width = 70 },
    { field = "lastUpdated", label = "COL_UPDATED", width = 90 },
}

local KIND = { level = "number", levels = "number", quests = "number", dungeons = "pair", moneyNet = "money", active = "duration" }

function FriendsTab.Block(tag)
    ns.db.blocklist[tag] = true
    ns.MainWindow.Refresh()
end

local function lines()
    local now = time()
    local rows, hidden = FriendsModel.Build(ns.Data.Friends(), ns.db.blocklist, state.range, ns.Store.Today(), time, date)
    local out = {}
    for _, r in ipairs(rows) do
        if r.header then
            local f = r.friend
            local status = f.online and L.ONLINE or L.OFFLINE
            out[#out + 1] = { kind = "group", text = string.format(L.FRIEND_HEADER, f.name or r.id, status, r.count,
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
    local list, count = lines()
    ui.table:SetLines(list)
    ui.empty:SetShown(count == 0)
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
    local columns = {}
    for _, col in ipairs(COLUMNS) do columns[#columns + 1] = { label = L[col.label], width = col.width } end
    ui.table = ns.Table.New(panel, columns, { top = 30 })
    ui.empty = W.Text(panel, "body", "muted")
    ui.empty:SetPoint("TOPLEFT", 8, -80)
    ui.empty:SetPoint("RIGHT", -8, 0)
    ui.empty:SetWordWrap(true)
end

ns.MainWindow.RegisterTab("friends", build, function() FriendsTab.Refresh() end)
