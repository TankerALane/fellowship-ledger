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

local state = { range = "week", weekly = false, sort = nil, desc = false, expanded = {}, detailView = {}, showAll = {} }
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
    { field = "played", label = "COL_PLAYED", width = 70 },
    { field = "deaths", label = "COL_DEATHS", width = 50 },
    { field = "kills", label = "COL_KILLS", width = 50 },
    { field = "skillUps", label = "COL_SKILLUPS", width = 54 },
    { field = "lastPlayed", label = "COL_LAST_PLAYED", width = 90 },
}

local KIND = { level = "number", faction = "faction", levels = "number", quests = "number", dungeons = "pair", moneyNet = "money",
    active = "duration", played = "duration", deaths = "number", kills = "number", skillUps = "number" }

function FriendsTab.Block(tag)
    ns.db.blocklist[tag] = true
    ns.MainWindow.Refresh()
end

local function weeklyLines()
    local out = {}
    -- Last week, reset to reset, you included (D-109): what the weekly recap showed.
    if not ns.Data.IsFake() and ns.Sync and ns.Sync.LastReset then
        local last = ns.Sync.LastReset()
        local fromKey, toKey = ns.Weekly.Range(last, date)
        out[#out + 1] = { kind = "group", text = string.format(L.WEEKLY_LAST_TITLE, date("%m-%d", last - ns.Weekly.WEEK), date("%m-%d", last)) }
        local rows = ns.Weekly.Rows(ns.db.characters, ns.db.friends, ns.db.blocklist, fromKey, toKey, L)
        for _, t in ipairs(rows) do out[#out + 1] = { kind = "detail", indent = true, text = ns.Weekly.Line(t, L) } end
        if #rows == 0 then out[#out + 1] = { kind = "detail", indent = true, text = L.WEEKLY_LAST_EMPTY } end
    end
    out[#out + 1] = { kind = "group", text = L.WEEKLY_TITLE }
    local list = ns.Merge.Weekly(ns.Data.Friends(), ns.db.blocklist, ns.Store.Today(), time, date)
    for _, t in ipairs(list) do
        out[#out + 1] = { kind = "detail", indent = true, text = string.format(L.WEEKLY_LINE, t.name, t.levels, t.quests,
            t.dungeons, ns.Format.Duration(t.active)) }
    end
    if #list == 0 then out[#out + 1] = { kind = "detail", indent = true, text = L.WEEKLY_EMPTY } end
    return out
end

-- Whisper / Invite (D-108). Each call is guarded; a missing one falls to the next.
-- Newer clients moved these into ChatFrameUtil; Forever has no ChatFrame_SendBNetTell
-- (verified 2026-11-07), so the ChatFrameUtil names come first.
function FriendsTab.Whisper(peer)
    if peer.kind == "bnet" and peer.accountName then
        if ns.Compat.Try("ChatFrameUtil.SendBNetTell", peer.accountName) then return true end
        if ns.Compat.Try("ChatFrame_SendBNetTell", peer.accountName) then return true end
    end
    local name = peer.kind == "char" and peer.target or peer.character
    if not name then return false end
    return ns.Compat.Try("ChatFrameUtil.SendTell", name) or ns.Compat.Try("ChatFrame_SendTell", name) or false
end

function FriendsTab.Invite(peer)
    if peer.kind == "bnet" and peer.target and ns.Compat.Try("BNInviteFriend", peer.target) then return true end
    local name = peer.kind == "char" and peer.target or peer.character
    if not name then return false end
    return ns.Compat.Try("C_PartyInfo.InviteUnit", name) or ns.Compat.Try("InviteUnit", name) or false
end

FriendsTab.menuStatus = nil -- for /fl verify
function FriendsTab.OpenMenu(owner, friendId, title, playing, characterName)
    local peer = ns.Friends and ns.Friends.peers and ns.Friends.peers[friendId]
    local actions = FriendsModel.Actions(peer, playing)
    if #actions == 0 then
        ns.Log.Info(L.FRIEND_MENU_NOTHING, title or "?")
        return false
    end
    if ns.Compat.IsDisabled("friends.menu") then return false end
    local ok = ns.Compat.Call("friends.menu", "MenuUtil.CreateContextMenu", owner, function(_, root)
        local fine, err = pcall(function()
            root:CreateTitle(title or peer.name or "?")
            for _, a in ipairs(actions) do
                if a == "whisper" then
                    root:CreateButton(string.format(L.FRIEND_MENU_WHISPER, peer.name or "?"), function() FriendsTab.Whisper(peer) end)
                else
                    root:CreateButton(string.format(L.FRIEND_MENU_INVITE, characterName or "?"), function() FriendsTab.Invite(peer) end)
                end
            end
        end)
        FriendsTab.menuStatus = { at = time(), ok = fine, err = not fine and tostring(err) or nil, actions = table.concat(actions, ",") }
    end)
    return ok
end

-- Quests in both your current character's log and this friend character's (D-106),
-- with names and levels from Questie (or the game).
function FriendsTab.Common(char)
    local me = ns.Store.char
    local out = {}
    for _, id in ipairs(FriendsModel.CommonQuests(me and me.logQuests, char and char.logQuests)) do
        local ok, info = pcall(ns.QuestChains.QuestInfo, id)
        info = ok and info or {}
        out[#out + 1] = { id = id, name = info.name, level = info.level, zone = info.zone }
    end
    return out
end

-- An opened friend's character (D-083): the same tabs as the Me tab without All
-- completed, built from what the character shares. id: "<friend id>|<character key>".
function FriendsTab.DetailLines(id, char)
    local S = ns.StatsModel
    local view = state.detailView[id] or "overview"
    local layout = ns.db.settings.detailsLayout
    local tabs = S.TabLine(view, L, function(v)
        state.detailView[id] = v
        FriendsTab.Refresh()
    end, S.FRIEND_TABS)
    local shared = ns.Codec.MaskToSet(char.mask or "")
    local today = ns.Store.Today()
    local fromKey = ns.Days.RangeStart(state.range, today, time, date)
    local sum = ns.Days.Sum(char.days or {}, fromKey, today)
    local allSum = ns.Days.Sum(char.days or {}, nil, today)
    local parts
    if view == "overview" then
        local skin = ns.db.settings.skin
        -- Their shared loot as items for the Notable loot section (D-105): the name, link
        -- and quality come from our own game (loaded on first sight).
        local view_ = setmetatable({ items = {} }, { __index = char })
        for _, it in ipairs(char.loot or {}) do
            local name, quality, link = it.name, nil, nil -- a name only in fake data
            if not name and it.id and ns.QuestRewards and ns.QuestRewards.ItemInfo then
                local ok, n, q, l = pcall(ns.QuestRewards.ItemInfo, it.id)
                if ok then name, quality, link = n, q, l end
            end
            view_.items[#view_.items + 1] = { at = it.at, id = it.id, name = name or string.format(L.QUEST_ITEM_UNKNOWN, it.id or 0),
                link = link, quality = quality or it.quality, quantity = it.count, zone = it.zone }
        end
        local data = ns.DetailModel.Data(view_, L, date, { levels = state.showAll[id], deaths = state.showAll[id .. "|deaths"],
            loot = state.showAll[id .. "|loot"] }, ns.DetailModel.ArrowCode(ns.Palette.Color(skin, "text")))
        data.summary.deaths = allSum.deaths or 0
        parts = S.FriendOverview(data, sum, shared, L, L[RANGE_LABEL[state.range]], function()
            state.showAll[id] = not state.showAll[id] or nil
            FriendsTab.Refresh()
        end, ns.Palette.Code(ns.Palette.Color(skin, "text")))
        local friend = ns.Data.Friends()[id:match("^(.-)|") or ""]
        for _, p in ipairs(S.FriendDeathsLoot(data, shared, L, skin, function(kind)
            state.showAll[id .. "|" .. kind] = not state.showAll[id .. "|" .. kind] or nil
            FriendsTab.Refresh()
        end, friend and friend.version)) do parts[#parts + 1] = p end
    elseif view == "quests" then
        parts = S.FriendQuests(sum, ns.QuestChains.FriendChains(char), shared, L, FriendsTab.Common(char), function(q)
            W.LinkQuest(q.id, q.name, q.level)
        end)
    elseif view == "gold" then
        parts = shared.gold and S.Gold(sum, L) or { { segs = { { x = 0, w = 1, text = L.STATS_NOT_SHARED, role = "muted", font = "body" } } } }
    elseif view == "kills" then
        parts = shared.kills and S.Kills(sum, { total = allSum.kills or 0, rare = allSum.rareKills or 0, elite = allSum.eliteKills or 0 },
            state.range, L, true) or { { segs = { { x = 0, w = 1, text = L.STATS_NOT_SHARED, role = "muted", font = "body" } } } }
    elseif view == "dungeons" then
        local friend = ns.Data.Friends()[id:match("^(.-)|") or ""]
        parts = S.FriendDungeons(sum, char.runs, shared, L, date, friend and friend.version, fromKey)
    else
        local friend = ns.Data.Friends()[id:match("^(.-)|") or ""]
        parts = S.FriendProfessions(sum, char.professions, shared, L, date, friend and friend.version)
    end
    return S.Wrap(tabs, parts, layout)
end

local function lines()
    local now = time()
    local rows, hidden = FriendsModel.Build(ns.Data.Friends(), ns.db.blocklist, state.range, ns.Store.Today(), time, date,
        state.sort, state.desc)
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
                onRightClick = function(owner) FriendsTab.OpenMenu(owner, r.id, f.name or r.id, false) end,
                action = { label = L.BLOCK, onClick = function() FriendsTab.Block(f.tag or r.id) end } }
        else
            local cells = {}
            local openId = tostring(r.friendId) .. "|" .. tostring(r.key)
            for c, col in ipairs(COLUMNS) do
                if col.field == "lastPlayed" then
                    local text, live = FriendsModel.LastPlayed(now, r)
                    cells[c] = live and (ns.Palette.Code(W.Color("good")) .. L.FRIEND_NOW .. "|r") or text
                elseif col.field == "name" then
                    cells[c] = (state.expanded[openId] and "- " or "+ ") .. W.ClassName(r.name, r.class)
                        .. (r.playing and (" " .. ns.Palette.Code(W.Color("good")) .. L.FRIEND_PLAYING .. "|r") or "")
                else
                    cells[c] = MeModel.FormatCell({ field = col.field, kind = KIND[col.field] }, r)
                end
            end
            local friend = ns.Data.Friends()[r.friendId]
            local char = friend and friend.characters and friend.characters[r.key]
            local factionText = MeModel.FormatCell({ field = "faction", kind = "faction" }, r)
            out[#out + 1] = { kind = "row", id = openId, cells = cells, indent = r.indent,
                tooltip = function()
                    local me = ns.Store.char
                    r.common = #FriendsModel.CommonQuests(me and me.logQuests, char and char.logQuests)
                    return FriendsModel.Tooltip(r, char, friend, time(), L, factionText)
                end,
                onClick = function()
                    state.expanded[openId] = not state.expanded[openId] or nil
                    FriendsTab.Refresh()
                end,
                onRightClick = function(owner)
                    FriendsTab.OpenMenu(owner, r.friendId, r.name, r.playing, r.name)
                end,
                action = (not r.indent) and { label = L.BLOCK, onClick = function() FriendsTab.Block(friend.tag or r.key) end } or nil }
            if state.expanded[openId] and char then
                for _, l in ipairs(FriendsTab.DetailLines(openId, char)) do out[#out + 1] = l end
            end
        end
    end
    if hidden > 0 then out[#out + 1] = { kind = "detail", text = string.format(L.BLOCKED_HIDDEN, hidden) } end
    for _, l in ipairs(FriendsTab.InviteLines(now, #rows > 0)) do out[#out + 1] = l end
    return out, #rows
end

-- "Online, not using the ledger" (D-114): friends online on this version who never said
-- hello, each with Invite. While the week after an invite runs there is no button;
-- after it the button is back and the line still says when the last one went out.
-- The section shows from login (Austin, 2026-11-10): for the first minute it says the
-- list is still being checked, since friends' hellos take that long to arrive, and the
-- tab redraws itself when the minute is up. With nobody to invite it says so, unless
-- there are no ledger friends either: then the tab's empty text explains. A blank line
-- keeps it apart from the friends above.
local settleRefresh
function FriendsTab.InviteLines(now, hasLedgerFriends)
    local out = {}
    if ns.Data.IsFake() or not (ns.Friends and ns.Sync) then return out end
    local started = ns.Sync.startedAt
    local left = started and (started + ns.Invites.SETTLE_SECONDS - now) or ns.Invites.SETTLE_SECONDS
    if left > 0 then
        if not hasLedgerFriends then return out end
        if started and not settleRefresh and ns.Events and ns.Events.After then
            settleRefresh = true
            ns.Events.After(left + 1, function()
                settleRefresh = nil
                if ns.MainWindow.frame and ns.MainWindow.frame:IsShown() then FriendsTab.Refresh() end
            end)
        end
        out[#out + 1] = { kind = "grid", segments = {} }
        out[#out + 1] = { kind = "group", text = L.INVITE_GROUP_WAIT }
        out[#out + 1] = { kind = "detail", indent = true, text = L.INVITE_CHECKING }
        return out
    end
    local list = ns.Invites.Candidates(ns.Friends.peers, ns.db.friends, ns.Friends.IsBlocked)
    if #list == 0 and not hasLedgerFriends then return out end
    if hasLedgerFriends then out[#out + 1] = { kind = "grid", segments = {} } end
    out[#out + 1] = { kind = "group", text = string.format(L.INVITE_GROUP, #list) }
    if #list == 0 then
        out[#out + 1] = { kind = "detail", indent = true, text = L.INVITE_NOBODY }
    end
    for _, c in ipairs(list) do
        local status = ns.Invites.Status((ns.db.invites or {})[c.id], now)
        local peer = ns.Friends.peers[c.id]
        out[#out + 1] = { kind = "detail", indent = true, text = ns.Invites.Line(c, status, L),
            action = not (status and status.waiting) and { label = L.INVITE_BUTTON, onClick = function()
                ns.InviteDialog.Open(peer)
            end } or nil }
    end
    return out
end

function FriendsTab.Open(friendId, key, view)
    if friendId and key then
        local id = tostring(friendId) .. "|" .. tostring(key)
        state.expanded[id] = true
        if view then state.detailView[id] = view end
        state.focus = id
    end
    ns.MainWindow.Open("friends")
end

-- The weekly recap's click (D-109): the Friends tab with its weekly panel open.
function FriendsTab.OpenWeekly()
    state.weekly = true
    ns.MainWindow.Open("friends")
end

FriendsTab.Lines = lines -- for tests
FriendsTab.ui = ui
FriendsTab.state = state

function FriendsTab.Refresh()
    if not ui.table then return end
    for range, b in pairs(ui.rangeButtons) do b:SetSelected(range == state.range) end
    ui.weeklyButton:SetSelected(state.weekly)
    if ns.Screenshots and ns.Screenshots.active then
        ui.status:SetText("")
    elseif ns.Data.IsFake() then
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
    -- No ledger friends but an invite list: the explanation goes on top of the list as
    -- a line, since the empty text would cover it.
    local inline = count == 0 and not state.weekly and #list > 0 and not ns.Data.IsFake()
    if inline then
        table.insert(list, 1, { kind = "detail", text = L.INVITE_NONE_YET })
    end
    ui.table:SetLines(list)
    -- A clicked notice: scroll its character's row to the top, once.
    if state.focus then
        for i, l in ipairs(list) do
            if l.id == state.focus then ui.table:ScrollTo(i) break end
        end
        state.focus = nil
    end
    -- "This week" has its own empty line; the long explanation would sit on top of it.
    ui.empty:SetShown(count == 0 and not state.weekly and not inline)
    if ns.Data.IsFake() then
        ui.empty:SetText(L.NO_FRIENDS_FAKE)
    else
        -- Sharing works on its own, so say what it is waiting for.
        local online = 0
        for _, peer in pairs(ns.Friends and ns.Friends.peers or {}) do if peer.online then online = online + 1 end end
        ui.empty:SetText(online > 0 and string.format(L.NO_FRIENDS_ONLINE_SOME, online) or L.NO_FRIENDS_ONLINE_NONE)
    end
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
    for _, col in ipairs(COLUMNS) do
        columns[#columns + 1] = { label = L[col.label], width = col.width, field = col.field,
            tip = rawget(L, (col.label:gsub("^COL_", "COL_TIP_"))) }
    end
    ui.table = ns.Table.New(panel, columns, {
        top = 30,
        actions = true,
        -- Click a header to sort (again to reverse). Text columns start A-Z, numbers high to low.
        onSort = function(field)
            if state.sort == field then
                state.desc = not state.desc
            else
                state.sort, state.desc = field, field ~= "name" and field ~= "faction"
            end
            FriendsTab.Refresh()
        end,
        sortState = function() return state.sort, state.desc end,
    })
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
