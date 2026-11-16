-- UI/MeTab.lua
-- Me tab: ranges, tiles, a sortable table with one row per character (its level in a
-- ring, a grey line under its name), and a "Quest chains" view of the quests in your log.
-- 1.14.0 (D-135): clicking a character opens its own page (back link, name, its views
-- as joined tabs, tiles, then the view) instead of opening inside the list.
-- state.expanded holds the one character whose page is open.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local MeModel = ns.MeModel

local Me = {}
ns.MeTab = Me

local state = { range = "today", sort = "level", desc = true, expanded = {}, showAll = {}, mode = "characters",
    chainOpen = {}, chainAll = {}, chainQuest = {}, detailView = {}, openProf = {}, openZone = {},
    chainList = "mine", chainSel = {} } -- 1.14.0: which list, and the chosen chain in each (D-134)
local ui = {}
Me.state, Me.ui = state, ui -- for tests

local RANGE_LABEL = { today = "RANGE_TODAY", week = "RANGE_WEEK", month = "RANGE_MONTH", all = "RANGE_ALL" }

-- Today / 7 days / 30 days / All as one joined group (1.13.0), shared by the Me,
-- Friends and Dungeons tabs. Returns the group; group.buttons[range] are the buttons.
function Me.RangeGroup(parent, onPick, width)
    local items = {}
    for _, range in ipairs(ns.Days.RANGES) do
        items[#items + 1] = { id = range, label = L[RANGE_LABEL[range]], width = width or 72 }
    end
    return W.Segmented(parent, items, onPick)
end

local function cellsFor(row)
    local cells = {}
    for c, col in ipairs(MeModel.ListColumns()) do
        local text = MeModel.FormatCell(col, row)
        if c == 1 and row.key then text = W.ClassName(text, row.class) end
        cells[c] = text
    end
    return cells
end

local function ago(at)
    if type(at) ~= "number" then return nil end
    return ns.FriendsModel.Ago(time(), at)
end
Me.Ago = ago

-- The page that is open (1.14.0): the one key in state.expanded that is still a character.
function Me.PageKey(chars)
    for key in pairs(state.expanded) do
        if chars[key] then return key end
    end
    return nil
end

function Me.OpenPage(key)
    for k in pairs(state.expanded) do state.expanded[k] = nil end
    state.expanded[key] = true
    Me.Refresh()
end

function Me.ClosePage()
    for k in pairs(state.expanded) do state.expanded[k] = nil end
    Me.Refresh()
end

-- The tiles over the table (1.13.0): the range's totals for all your characters.
Me.TILES = { "levels", "quests", "dungeons", "moneyNet", "played", "deaths" }
Me.TILE_H = 40 -- 1.13.1: was 48 (too tall), then 34 (the figure ran into the title)
Me.TILE_WIDTH = 0.75 -- 1.13.1: each tile three quarters of an even share of the row (Austin)
Me.TILE_GAP = 6

function Me.TileValues(rows)
    local total = MeModel.Totals(rows)
    local out = {}
    for _, field in ipairs(Me.TILES) do
        local col
        for _, c in ipairs(MeModel.COLUMNS) do if c.field == field then col = c end end
        local text = MeModel.FormatCell(col, total)
        local full = text
        local role = "text"
        if field == "moneyNet" then
            -- Short in the tile ("+257.9g"), in full on hover.
            text = ns.Format.MoneyShort(total.moneyNet or 0, true)
            if (total.moneyNet or 0) < 0 then role = "bad" end
        end
        out[#out + 1] = { label = L[col.label], text = text, full = full, role = role }
    end
    return out
end

local function buildTiles(panel)
    ui.tiles = CreateFrame("Frame", nil, panel)
    ui.tiles:SetPoint("TOPLEFT", 4, -28)
    ui.tiles:SetPoint("TOPRIGHT", -4, -28)
    ui.tiles:SetHeight(Me.TILE_H)
    ui.tileFrames = {}
    for i = 1, #Me.TILES do
        local t = CreateFrame("Frame", nil, ui.tiles)
        t:SetHeight(Me.TILE_H)
        W.Background(t, "panel")
        W.Border(t, "rule", 1)
        t.label = W.Text(t, "small", "section")
        t.label:SetPoint("TOPLEFT", 8, -5)
        t.value = W.Text(t, "number", "text")
        t.value:SetPoint("BOTTOMLEFT", 8, 4)
        t.value:SetPoint("BOTTOMRIGHT", -6, 4)
        t.value:SetWordWrap(false)
        t:EnableMouse(true)
        t:SetScript("OnEnter", function(self)
            if self.info then W.Tooltip(self, self.info.label, { self.info.full }) end
        end)
        t:SetScript("OnLeave", function() W.HideTooltip() end)
        ui.tileFrames[i] = t
    end
end

local function layoutTiles(values)
    local width = ui.tiles:GetWidth()
    if type(width) ~= "number" or width < 100 then width = 800 end
    local n = #ui.tileFrames
    local w = (width - Me.TILE_GAP * (n - 1)) / n * Me.TILE_WIDTH
    for i, t in ipairs(ui.tileFrames) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", (i - 1) * (w + Me.TILE_GAP), 0)
        t:SetWidth(w)
        local v = values[i]
        t.info = v
        t.label:SetText(ns.Format.Upper(v and v.label or ""))
        t.value:SetText(v and v.text or "")
        W.SetTextStyle(t.value, "number", v and v.role or "text")
    end
end

-- The opened character: a row of view tabs (D-081), then the view. Overview is the
-- summary card or list (Settings, D-075); "Show all" is remembered per character
-- and list until the window is reloaded.
function Me.OverviewLines(key, char, name, noSummary)
    local all = state.showAll[key] or {}
    local skin = ns.db.settings.skin
    local data = ns.DetailModel.Data(char, L, date, all, ns.DetailModel.ArrowCode(ns.Palette.Color(skin, "text")))
    local removable = not ns.Data.IsFake() and key ~= ns.Store.key
    return ns.DetailModel.Lines(data, ns.db.settings.detailsLayout, L, {
        skin = skin,
        noSummary = noSummary,
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

-- Without the tab line (a character's page has its own tabs, 1.14.0): the box joins up.
local function dropTabs(lines)
    table.remove(lines, 1)
    local first = lines[1]
    if first and first.box == "mid" then first.box = "top" elseif first and first.box == "bottom" then first.box = "single" end
    return lines
end

function Me.DetailLines(key, char, name, noTabs)
    local S = ns.StatsModel
    local view = state.detailView[key] or "overview"
    local layout = ns.db.settings.detailsLayout
    local tabs = S.TabLine(view, L, function(id)
        state.detailView[key] = id
        state.completedCache = nil
        Me.Refresh()
    end)
    if view == "overview" then
        if noTabs then return Me.OverviewLines(key, char, name, true) end
        return S.WithTabs(tabs, Me.OverviewLines(key, char, name), layout)
    end

    local today = ns.Store.Today()
    local fromKey = ns.Days.RangeStart(state.range, today, time, date)
    local inRange = function(at) return type(at) == "number" and (not fromKey or date("%Y-%m-%d", at) >= fromKey) end
    local sum = ns.Days.Sum(char.days or {}, fromKey, today)
    local parts
    if view == "quests" then
        local zoneOf = function(id) return ns.QuestChains.QuestInfo(id).zone end
        parts = S.Quests(char.questLog, inRange, L, date, state.showAll[key] and state.showAll[key].quests, zoneOf,
            function() toggleIn(state.showAll, key, "quests") end)
    elseif view == "xp" then
        local playing = key == ns.Store.key and not ns.Data.IsFake()
        local session, title = S.XPSession(char.sessions, playing and ns.Store.session or nil, L, date)
        parts = S.XP(session, L, char.levelXP, playing and char.level or nil,
            state.showAll[key] and state.showAll[key].xpLevels, function() toggleIn(state.showAll, key, "xpLevels") end, title)
    elseif view == "gold" then
        parts = S.Gold(sum, L)
    elseif view == "kills" then
        parts = S.Kills(sum, char.kills, state.range, L)
    elseif view == "professions" then
        parts = S.Professions(char.professions, inRange, L, date, state.openProf[key],
            function(prof) toggleIn(state.openProf, key, prof) end, sum.skillUps)
    elseif view == "bests" then
        local all = ns.Data.IsFake() and (ns.db.fake.bests or ns.Bests.New()) or ns.db.bests
        local rows = ns.Bests.Rows(char.bests, all, L, { Duration = ns.Format.Duration, Number = ns.Format.Number }, date, char.levels)
        parts = S.Bests(rows, L, function(k)
            local c = ns.Data.Characters()[k]
            return c and (c.display or c.name) or k
        end)
    else
        if key ~= ns.Store.key or ns.Data.IsFake() then
            parts = { { segs = { { x = 0, w = 1, text = L.STATS_COMPLETED_OTHER_CHAR, role = "muted", font = "body" } } } }
        else
            local c = Me.CompletedGroups()
            parts = S.Completed(c.groups, c.total, c.questieMissing, L, state.openZone[key],
                function(zone) toggleIn(state.openZone, key, zone) end, c.hidden)
        end
    end
    local lines = S.Wrap(tabs, parts, layout)
    return noTabs and dropTabs(lines) or lines
end

-- A character page's tiles: its levels (average, fastest, slowest) and the range's gold,
-- played time and deaths.
function Me.PageTileValues(row, summary)
    local F = ns.Format
    local s = summary or {}
    local function lv(x)
        if not x then return "-", L.ME_TILE_NONE end
        return F.Duration(x.active), string.format(L.ME_TILE_LEVEL_TIP, x.from or "?", x.to or "?", F.Duration(x.active))
    end
    local fast, fastTip = lv(s.fastest)
    local slow, slowTip = lv(s.slowest)
    local money = row.moneyNet or 0
    return {
        { label = L.ME_TILE_AVERAGE, text = s.average and F.Duration(s.average) or "-", full = s.average and F.Duration(s.average) or L.ME_TILE_NONE },
        { label = L.ME_TILE_FASTEST, text = fast, full = fastTip },
        { label = L.ME_TILE_SLOWEST, text = slow, full = slowTip },
        { label = L.COL_GOLD, text = F.MoneyShort(money, true), full = F.Money(money, true), role = money < 0 and "bad" or "text" },
        { label = L.COL_PLAYED, text = F.Duration(row.played or 0), full = F.Duration(row.played or 0) },
        { label = L.COL_DEATHS, text = tostring(row.deaths or 0), full = tostring(row.deaths or 0) },
    }
end

-- The open page's head, lines and tiles.
function Me.PageLines(key, chars)
    local char = chars[key]
    local rows = MeModel.Build({ [key] = char }, state.range, ns.Store.Today(), time, date)
    local row = rows[1]
    local playing = key == ns.Store.key and not ns.Data.IsFake()
    Me.FillHead(ui.page, row, playing, MeModel.SubText(row, L, ago, playing))
    ui.views:Select(state.detailView[key] or "overview")
    local data = ns.DetailModel.Data(char, L, date, {}, nil)
    return Me.DetailLines(key, char, row.name, true), Me.PageTileValues(row, data.summary)
end

local function characterLines()
    local chars = ns.Data.Characters()
    local rows = MeModel.Build(chars, state.range, ns.Store.Today(), time, date)
    MeModel.Sort(rows, state.sort, state.desc)
    local lines = {}
    -- "This session: ..." (D-099), for the character being played.
    if ns.db.settings.sessionRecap and not ns.Data.IsFake() and ns.Store.session then
        local recap = ns.Summary.Recap(ns.Store.session, L)
        if recap then lines[#lines + 1] = { kind = "detail", text = recap } end
    end
    -- This session's goals (D-116).
    if not ns.Data.IsFake() and ns.SessionGoals then
        local ok, goals = pcall(ns.SessionGoals.Line)
        if ok and goals then lines[#lines + 1] = { kind = "detail", text = goals, onClick = function() ns.SessionGoals.Open(true) end } end
    end
    if #rows > 1 then
        local total = MeModel.Totals(rows)
        total.name = L.TOTAL_ALL
        lines[#lines + 1] = { kind = "total", cells = (function()
            local cells = {}
            for c, col in ipairs(MeModel.ListColumns()) do cells[c] = MeModel.FormatCell(col, total) end
            return cells
        end)() }
    end
    for _, row in ipairs(rows) do
        local key = row.key
        -- The character I am playing (real data only; fake characters are never played).
        local playing = key == ns.Store.key and not ns.Data.IsFake()
        lines[#lines + 1] = { kind = "row", cells = cellsFor(row), tag = playing and L.TAG_PLAYING or nil,
            badge = row.level, badgeRole = playing and "accent" or "muted", sub = MeModel.SubText(row, L, ago, playing),
            height = ns.Table.TALL_H, indent = true, key = key, onClick = function() Me.OpenPage(key) end }
    end
    return lines, #rows, rows
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
    local view = { mine = {}, friends = {}, emptyLog = #entries == 0, questieMissing = source == "missing", logSet = logSet }

    -- One line per quest in the log, named after the quest (Austin looked for "The
    -- Family Crypt" under its chain's first quest, "Speak with Sevren"); the chain's
    -- first quest follows when it is another quest. Two quests of one chain: two
    -- lines, and the chain opens under the first of them only.
    local unknown = {}
    for _, e in ipairs(entries) do
        -- Friends with the same quest in their log (D-106).
        local with = ns.FriendsModel.OnQuest(friends, ns.db.blocklist, e.questID)
        if e.step and e.key then
            local name = e.title
            if e.chainName and e.chainName ~= e.title then name = string.format(L.CHAIN_PART_OF, e.title, e.chainName) end
            view.mine[#view.mine + 1] = { key = e.key, name = name, title = e.title, step = e.step, total = e.total,
                zone = e.startZone, known = true, anchor = e.questID, withFriends = with }
        else
            unknown[#unknown + 1] = { known = false, title = e.title, withFriends = with }
        end
    end
    table.sort(view.mine, function(a, b) return tostring(a.title) < tostring(b.title) end)
    local opened = {}
    for _, c in ipairs(view.mine) do
        if not opened[c.key] then
            opened[c.key] = true
            c.open, c.showAll = state.chainOpen[c.key], state.chainAll[c.key]
            if c.open then
                c.details = ns.QuestChains.Details(c.key, c.anchor, logSet)
                c.friendsOn = ns.QuestChainLogic.FriendsOn(friends, blocked, c.key, ns.QuestChains.FriendChains)
            end
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

local function chainOpts()
    local skin = ns.db.settings.skin
    local Palette = ns.Palette
    return {
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
        -- Quest details (D-100): click a quest for its objective, rewards and your turn-in.
        skin = skin, dateFn = date, openQuest = state.chainQuest,
        -- Shift-click a reward item to link it in chat, as from your bags (D-102).
        onItem = function(item) W.LinkItem(item) end,
        goodCode = Palette.Code(Palette.Color(skin, "good")),
        onLink = function(questID, title)
            local okInfo, info = pcall(ns.QuestChains.QuestInfo, questID)
            return W.LinkQuest(questID, title, okInfo and info and info.level)
        end,
        onQuest = function(key, questID, q)
            -- Shift-click links the quest in chat instead (D-107).
            if W.LinkQuest(questID, q and q.name, q and q.level) then return end
            local k = tostring(key) .. "|" .. tostring(questID)
            state.chainQuest[k] = not state.chainQuest[k] or nil
            Me.Refresh()
        end,
        more = function(q) return Me.QuestMore(q) end,
    }
end

-- The chosen chain of a list (1.14.0, D-134): the saved choice while it is still there,
-- else the first chain with information. Its details are worked out here.
function Me.SelectedChain(view, list)
    local entries = view[list] or {}
    local CM = ns.ChainModel
    local pick, first
    for _, c in ipairs(entries) do
        if c.known ~= false then
            first = first or c
            if CM.EntryId(c) == state.chainSel[list] then pick = c end
        end
    end
    pick = pick or first
    if pick and not pick.details then
        local friends = ns.Data.Friends()
        if list == "friends" then
            pick.details = ns.QuestChains.Details(pick.key, nil, view.logSet)
            pick.next = pick.details and pick.details.next
        else
            local blocked = function(f) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f) end
            pick.details = ns.QuestChains.Details(pick.key, pick.anchor, view.logSet)
            pick.friendsOn = ns.QuestChainLogic.FriendsOn(friends, blocked, pick.key, ns.QuestChains.FriendChains)
        end
    end
    return pick
end

-- The chains as a list and a detail pane.
local function refreshChains()
    local CM = ns.ChainModel
    local view = Me.ChainView()
    local list = state.chainList == "friends" and "friends" or "mine"
    local known = { mine = 0, friends = #view.friends }
    for _, c in ipairs(view.mine) do if c.known then known.mine = known.mine + 1 end end
    ui.chainTabs.buttons.mine.text:SetText(string.format(L.CHAIN_TAB_MINE, known.mine))
    ui.chainTabs.buttons.friends.text:SetText(string.format(L.CHAIN_TAB_FRIENDS, known.friends))
    ui.chainTabs:Select(list)
    local pick = Me.SelectedChain(view, list)
    local opts = chainOpts()
    local lines = CM.ListLines(view[list], pick and CM.EntryId(pick), L, {
        goodCode = opts.goodCode,
        onSelect = function(id)
            state.chainSel[list] = id
            Me.Refresh()
        end,
    })
    if list == "mine" and view.emptyLog then table.insert(lines, 1, { kind = "detail", text = L.CHAIN_EMPTY_LOG }) end
    if list == "friends" and #view.friends == 0 then lines[#lines + 1] = { kind = "detail", text = L.CHAIN_FRIENDS_NONE } end
    if view.questieMissing then lines[#lines + 1] = { kind = "detail", text = L.CHAIN_QUESTIE_HINT } end
    ui.chainList:SetLines(lines)
    if pick then pick.showAll = true end
    ui.chainDetail:SetLines(CM.DetailLines(pick, L, opts))
end

-- The details of one quest: rewards (seen in the game or from Questie) and your
-- latest turn-in of it (30-day log). Fake data has no rewards.
function Me.QuestMore(q)
    if ns.Data.IsFake() or not ns.QuestRewards then return nil end
    local turnedIn
    for _, e in ipairs(ns.Store.char and ns.Store.char.questLog or {}) do
        if e.id == q.id and (not turnedIn or (e.at or 0) > (turnedIn.at or 0)) then turnedIn = e end
    end
    local ok, more = pcall(ns.QuestRewards.More, q.id, q.status == "log", turnedIn)
    if not ok or not more then return nil end
    more.friends = ns.FriendsModel.OnQuest(ns.Data.Friends(), ns.db.blocklist, q.id) -- D-106
    return more
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

-- Open one character's view (a clicked "New personal best" notice).
function Me.OpenView(key, view)
    if not key then return end
    state.mode = "characters"
    for k in pairs(state.expanded) do state.expanded[k] = nil end
    state.expanded[key] = true
    state.detailView[key] = view
    ns.MainWindow.Open("me")
end

function Me.Refresh()
    if not ui.table then return end
    local characters = state.mode == "characters"
    local pageKey = characters and Me.PageKey(ns.Data.Characters()) or nil
    ui.ranges:Select(state.range)
    ui.ranges:SetShown(characters)
    ui.modeButton:SetShown(not pageKey)
    ui.modeButton.text:SetText(characters and L.SHOW_CHAINS or L.SHOW_CHARACTERS)
    ui.chains:SetShown(not characters)
    ui.chainTabs:SetShown(not characters)
    ui.page:SetShown(pageKey ~= nil)
    ui.views:SetShown(pageKey ~= nil)
    local lines, count, rows, tileValues
    if state.mode == "chains" then
        refreshChains()
        lines, count = {}, 1 -- the table stays empty under the list and pane
    elseif pageKey then
        lines, tileValues = Me.PageLines(pageKey, ns.Data.Characters())
        count = 1
    else
        lines, count, rows = characterLines()
        if count > 0 then tileValues = Me.TileValues(rows) end
    end
    -- Tiles over the characters or the page (not over Quest chains, nor with no characters yet).
    local tiles = tileValues ~= nil
    local headH = pageKey and Me.PAGE_HEAD_H or 0
    ui.tiles:ClearAllPoints()
    ui.tiles:SetPoint("TOPLEFT", 4, -28 - headH)
    ui.tiles:SetPoint("TOPRIGHT", -4, -28 - headH)
    ui.tiles:SetShown(tiles)
    if tiles then layoutTiles(tileValues) end
    ui.table:SetTop(30 + headH + (tiles and (Me.TILE_H + 8) or 0) - (pageKey and ns.Table.ROW_H or 0))
    ui.table:SetHeadersShown(characters and not pageKey)
    ui.table:SetLines(lines)
    ui.empty:SetShown(count == 0)
end

-- A character's page head (1.14.0): "< Me", the level ring, the name with PLAYING,
-- the grey line, and the views as joined tabs under it.
Me.PAGE_HEAD_H = 72

-- The head of a character page, shared with the Friends tab: "< Back", the level ring,
-- the name, PLAYING and a grey line. Placed under the range buttons.
function Me.PageHead(panel, onBack)
    local head = CreateFrame("Frame", nil, panel)
    head:SetPoint("TOPLEFT", 4, -28)
    head:SetPoint("TOPRIGHT", -4, -28)
    head:SetHeight(40)
    head:Hide()
    head.back = W.Button(head, L.ME_BACK, 60, 20, onBack)
    head.back:SetPoint("LEFT", 0, 0)
    head.badge = CreateFrame("Frame", nil, head)
    head.badge:SetSize(32, 32)
    head.badge:SetPoint("LEFT", head.back, "RIGHT", 12, 0)
    head.badge.ring = head.badge:CreateTexture(nil, "ARTWORK")
    head.badge.ring:SetTexture("Interface\\AddOns\\FellowshipLedger\\media\\ring")
    head.badge.ring:SetAllPoints()
    head.badge.text = W.Text(head.badge, "body", "heading")
    head.badge.text:SetPoint("CENTER", 0, 0)
    head.name = W.Text(head, "large", "text")
    head.name:SetPoint("TOPLEFT", head.badge, "TOPRIGHT", 10, 0)
    head.sub = W.Text(head, "small", "muted")
    head.sub:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -3)
    head.tag = W.Tag(head)
    return head
end

-- The views of a page as joined tabs, under its head.
function Me.PageViews(panel, tabs, onPick)
    local items = {}
    for _, id in ipairs(tabs) do
        local label = L[ns.StatsModel.TAB_LABEL[id]]
        items[#items + 1] = { id = id, label = label, width = math.max(56, 8 * #label + 18) }
    end
    local g = W.Segmented(panel, items, onPick, 22)
    g:SetPoint("TOPLEFT", 4, -28 - 46)
    g:Hide()
    return g
end

-- row: { name, class, level }; playing: show PLAYING; sub: the grey line.
function Me.FillHead(head, row, playing, sub)
    head.badge.text:SetText(tostring(row.level or "?"))
    local c = W.Color(playing and "accent" or "muted")
    head.badge.ring:SetVertexColor(c[1], c[2], c[3], 1)
    head.name:SetText(W.ClassName(row.name, row.class))
    head.sub:SetText(sub or "")
    if playing then
        head.tag:SetLabel(L.TAG_PLAYING)
        head.tag:ClearAllPoints()
        head.tag:SetPoint("LEFT", head.name, "RIGHT", 8, 0)
        head.tag:Show()
    else
        head.tag:Hide()
    end
end

local function buildPage(panel)
    ui.page = Me.PageHead(panel, function() Me.ClosePage() end)
    ui.views = Me.PageViews(panel, ns.StatsModel.TABS, function(id)
        local key = Me.PageKey(ns.Data.Characters())
        if not key then return end
        state.detailView[key] = id
        state.completedCache = nil
        Me.Refresh()
    end)
end

local function build(panel)
    ui.ranges = Me.RangeGroup(panel, function(range)
        state.range = range
        Me.Refresh()
    end)
    ui.ranges:SetPoint("TOPLEFT", 4, -2)
    ui.rangeButtons = ui.ranges.buttons
    buildTiles(panel)
    ui.modeButton = W.Button(panel, L.SHOW_CHAINS, 130, 20, function()
        state.mode = state.mode == "characters" and "chains" or "characters"
        Me.Refresh()
    end)
    ui.modeButton:SetPoint("TOPRIGHT", -4, -2)
    buildPage(panel)

    local columns = {}
    for _, col in ipairs(MeModel.ListColumns()) do
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

    -- Quest chains (1.14.0, D-134): In your log / Friends are on, a list of chains on
    -- the left and the chosen one on the right.
    ui.chainTabs = W.Segmented(panel, {
        { id = "mine", label = string.format(L.CHAIN_TAB_MINE, 0), width = 120 },
        { id = "friends", label = string.format(L.CHAIN_TAB_FRIENDS, 0), width = 130 },
    }, function(id)
        state.chainList = id
        Me.Refresh()
    end, 20)
    ui.chainTabs:SetPoint("TOPLEFT", 4, -2)
    ui.chainTabs:Hide()
    ui.chains = CreateFrame("Frame", nil, panel)
    ui.chains:SetPoint("TOPLEFT", 0, -30)
    ui.chains:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.chains:Hide()
    local left = CreateFrame("Frame", nil, ui.chains)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(Me.CHAIN_LIST_W)
    W.Background(left, "panel")
    W.Border(left, "rule", 1)
    local right = CreateFrame("Frame", nil, ui.chains)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Background(right, "panel")
    W.Border(right, "rule", 1)
    -- No column titles: the first line starts at the top.
    ui.chainList = ns.Table.New(left, {}, { top = -16 })
    ui.chainList.rule:Hide()
    ui.chainDetail = ns.Table.New(right, {}, { top = -12 })
    ui.chainDetail.rule:Hide()
end

Me.CHAIN_LIST_W = 300

ns.MainWindow.RegisterTab("me", build, function() Me.Refresh() end)
