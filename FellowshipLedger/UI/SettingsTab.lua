-- UI/SettingsTab.lua
-- Settings (1.14.0, D-133): small sub-tabs instead of one long page (Austin: "large
-- pages of words"): General, Look, Tracking & sharing, Notices, Block list, About.
-- Each page is a few titled cards of switch rows (a short label, a grey hint under it,
-- a switch on the right); the long explanations moved into hover tooltips.
-- Everything here edits ns.db.settings or a character's flags.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local SettingsTab = {}
ns.SettingsTab = SettingsTab

local ui = { toggles = {}, trackerRows = {}, blockRows = {}, pages = {}, counts = {} }
SettingsTab.ui = ui -- for tests
local state = { charIndex = 1, page = "general" }
SettingsTab.state = state
local BLOCK_ROWS = 8
local QUESTIE_URL = "https://www.curseforge.com/wow/addons/questie"
local WIDTH = 800 -- the pages' content width (they scroll when the window is smaller)
local GAP = 10

SettingsTab.PAGES = { "general", "look", "tracking", "notices", "block", "about" }

local function S() return ns.db.settings end

local function shooting() return ns.Screenshots and ns.Screenshots.active end
local function characters() return shooting() and ns.Data.Characters() or ns.db.characters end

local function realCharacterKeys()
    local keys = {}
    for k in pairs(characters()) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if a == ns.Store.key then return true end
        if b == ns.Store.key then return false end
        return a < b
    end)
    return keys
end

local function selectedChar()
    local keys = realCharacterKeys()
    if state.charIndex > #keys then state.charIndex = 1 end
    local key = keys[state.charIndex]
    return key and characters()[key], key, #keys
end

local function readOnlyBox(parent, text, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(_G.GameFontHighlightSmall or _G.ChatFontNormal)
    W.Background(box, "panel")
    W.Border(box, "border", 1)
    box:SetTextInsets(4, 4, 0, 0)
    box:SetText(text)
    box:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(text) end end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- True if any tracker of this character has Share on.
function SettingsTab.AnySharing(char)
    for _, f in pairs(char.flags or {}) do
        if f.share ~= false then return true end
    end
    return false
end

local function tooltip(frame, title, text)
    if not text or text == "" then return end
    frame:SetScript("OnEnter", function(self) W.Tooltip(self, title, { text }) end)
    frame:SetScript("OnLeave", function() W.HideTooltip() end)
end

-- Show one page (sub-tab).
function SettingsTab.Show(page)
    if not ui.pages[page] then page = "general" end
    state.page = page
    for id, p in pairs(ui.pages) do p:SetShown(id == page) end
    if ui.tabs then ui.tabs:Select(page) end
    SettingsTab.Refresh()
end

function SettingsTab.Refresh()
    if not ui.content then return end
    local char, key, count = selectedChar()
    if char then
        ui.shareAll.text:SetText(SettingsTab.AnySharing(char) and L.SHARING_OFF_CHARACTER or L.SHARING_ON_CHARACTER)
    end
    local shown = shooting() and char and char.name or (char and (char.display or char.name)) or key
    ui.charLabel:SetText(char and W.ClassName(shown or "", char.class) or L.SETTINGS_NO_CHARACTER)
    ui.charSub:SetText(char and string.format(L.SET_CHAR_LINE, tostring(char.level or "?"), state.charIndex, count) or "")
    for _, row in ipairs(ui.trackerRows) do
        local t = ns.TrackerList.byId[row.id]
        local unavailable = t.status == "unavailable"
        row.track:SetShown(char ~= nil)
        row.share:SetShown(char ~= nil)
        if char then
            row.track:SetDisabled(unavailable)
            row.share:SetDisabled(unavailable or not ns.TrackerList.IsTracking(char, row.id) or S().sharingPaused)
        end
        local status = L["STATUS_" .. ns.TrackerList.Status(t, ns.Compat.flavor):upper()]
        row.what:SetText(status ~= "" and status or (L["SET_WHAT_" .. row.id] or ""))
        W.SetTextRole(row.what, status ~= "" and "bad" or "muted")
    end
    for _, t in ipairs(ui.toggles) do t:Refresh() end
    -- "6 of 7 on" on each notices card.
    for _, c in ipairs(ui.counts) do
        local on = 0
        for _, f in ipairs(c.fields) do if S()[f] == true then on = on + 1 end end
        c.card.count:SetText(string.format(L.SET_COUNT_ON, on, #c.fields))
    end
    ui.skin:Select(S().skin)
    ui.font:Select(S().fontSize)
    ui.details:Select(S().detailsLayout or "card")
    ui.scaleLabel:SetText(string.format(L.SETTINGS_SCALE_VALUE, S().scale or 1))
    ui.opacity:SetValueQuiet(W.Opacity())
    ui.opacityValue:SetText(string.format(L.SETTINGS_OPACITY_VALUE, math.floor(W.Opacity() * 100 + 0.5)))
    -- Block list
    local tags = {}
    for tag in pairs(shooting() and {} or ns.db.blocklist) do tags[#tags + 1] = tag end -- no real names in screenshots
    table.sort(tags)
    for i, row in ipairs(ui.blockRows) do
        local tag = tags[i]
        row:SetShown(tag ~= nil)
        if tag then
            row.text:SetText(tag)
            row.button:SetScript("OnClick", function()
                ns.db.blocklist[tag] = nil
                ns.MainWindow.Refresh()
            end)
        end
    end
    ui.blockEmpty:SetShown(#tags == 0)
    ui.blockMore:SetShown(#tags > BLOCK_ROWS)
    ui.blockMore:SetText(string.format(L.BLOCK_MORE, #tags - BLOCK_ROWS))
    local questie = ns.QuestChains.QuestieState()
    ui.questieStatus:SetText(L["QUESTIE_" .. questie:upper()])
end

-- A switch row for a settings field, added to a card. tip: the longer explanation on hover.
local function switchRow(card, label, hint, field, onChange, tip, shade, get, set)
    local r = W.SwitchRow(card, label, hint, get or function() return S()[field] == true end, set or function(v)
        S()[field] = v
        if onChange then onChange(v) end
        SettingsTab.Refresh()
    end)
    card:Add(r, nil, shade)
    tooltip(r, label, tip)
    ui.toggles[#ui.toggles + 1] = r
    return r
end

-- A card whose rows are { label, hint, field, onChange, tip }; with `counted`, its title
-- line says how many are on ("6 of 7 on").
local function switchCard(parent, title, width, rows, counted)
    local card = W.Card(parent, title, width)
    local fields = {}
    for i, r in ipairs(rows) do
        switchRow(card, r[1], r[2], r[3], r[4], r[5], i % 2 == 0)
        fields[#fields + 1] = r[3]
    end
    if counted then ui.counts[#ui.counts + 1] = { card = card, fields = fields } end
    return card:Finish()
end

-- A labelled line in a card (Look): the label on the left, the control placed by the caller.
local function labelLine(card, label, shade)
    local f = CreateFrame("Frame", nil, card)
    card:Add(f, 30, shade)
    local t = W.Text(f, "body", "text")
    t:SetPoint("LEFT", 10, 0)
    t:SetText(label)
    return f
end

local function newPage(panel, id)
    local scroll, content = W.ScrollArea(panel)
    scroll:SetPoint("TOPLEFT", 0, -32)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    content:SetWidth(WIDTH)
    scroll:Hide()
    ui.pages[id] = scroll
    return content
end

local function fit(content, ...)
    local h = 0
    for _, f in ipairs({ ... }) do
        local _, _, _, _, y = f:GetPoint(1)
        local fh = f:GetHeight()
        if type(y) == "number" and type(fh) == "number" then h = math.max(h, -y + fh) end
    end
    content:SetHeight(h + 16)
end

-- General ---------------------------------------------------------------------
local function buildGeneral(panel)
    local content = newPage(panel, "general")
    local half = (WIDTH - GAP) / 2
    local window = switchCard(content, L.SET_CARD_WINDOW, half, {
        { L.SET_REMEMBER_TAB, L.SET_REMEMBER_TAB_HINT, "rememberTab" },
    })
    local mm = switchRow(window, L.SET_MINIMAP, L.SET_MINIMAP_HINT, nil, nil, nil, true,
        function() return not S().minimap.hide end,
        function(v) S().minimap.hide = not v; ns.MinimapButton.Update() end)
    window:Finish()
    window:SetPoint("TOPLEFT", 0, -4)
    local goals = switchCard(content, L.SET_CARD_GOALS, half, {
        { L.SET_GOALS, L.SET_GOALS_HINT, "goals" },
        { L.SET_GOALS_TRACKER, L.SET_GOALS_TRACKER_HINT, "goalsTracker", function() ns.GoalsTracker.Refresh() end },
        { L.SET_TIMER, L.SET_TIMER_HINT, "dungeonTimer", function() ns.DungeonTimer.Refresh() end },
        { L.SET_TIMER_MINE, L.SET_TIMER_MINE_HINT, "dungeonTimerMine", function() ns.DungeonTimer.Refresh() end },
    })
    goals:SetPoint("TOPLEFT", half + GAP, -4)
    local rec = W.Card(content, L.SETTINGS_RECOMMENDED, WIDTH)
    local line = CreateFrame("Frame", nil, rec)
    rec:Add(line, 70)
    local q = W.Text(line, "body", "text")
    q:SetPoint("TOPLEFT", 10, -6)
    q:SetText(L.QUESTIE_LINE)
    ui.questieStatus = W.Text(line, "small", "muted")
    ui.questieStatus:SetPoint("LEFT", q, "RIGHT", 12, 0)
    local why = W.Text(line, "small", "muted")
    why:SetPoint("TOPLEFT", 10, -26)
    why:SetPoint("RIGHT", line, "RIGHT", -10, 0)
    why:SetWordWrap(true)
    why:SetText(L.QUESTIE_WHY)
    local url = readOnlyBox(line, QUESTIE_URL, 420)
    url:SetPoint("TOPLEFT", 10, -44)
    rec:Finish()
    local top = math.max(window:GetHeight() or 0, goals:GetHeight() or 0)
    rec:SetPoint("TOPLEFT", 0, -4 - (type(top) == "number" and top or 0) - GAP)
    fit(content, window, goals, rec)
    return mm
end

-- Look ------------------------------------------------------------------------
local function buildLook(panel)
    local content = newPage(panel, "look")
    local card = W.Card(content, L.SETTINGS_APPEARANCE, WIDTH)
    local X = 180
    local f = labelLine(card, L.SETTINGS_SKIN)
    ui.skin = W.Segmented(f, {
        { id = "plain", label = L.SKIN_PLAIN, width = 100 },
        { id = "ledger", label = L.SKIN_LEDGER, width = 100 },
        { id = "leather", label = L.SKIN_LEATHER, width = 100 },
    }, function(skin)
        S().skin = skin
        W.ApplySkin()
        SettingsTab.Refresh()
        ns.MainWindow.Refresh()
    end, 20)
    ui.skin:SetPoint("LEFT", X, 0)
    -- Background opacity (1.13.1, D-131): up to fully solid.
    f = labelLine(card, L.SETTINGS_OPACITY, true)
    local D = ns.SettingsDefaults
    ui.opacity = W.Slider(f, 220, D.OPACITY_MIN, D.OPACITY_MAX, D.OPACITY_STEP, function(v)
        S().opacity = D.ClampOpacity(v)
        W.ApplyOpacity()
        ui.opacityValue:SetText(string.format(L.SETTINGS_OPACITY_VALUE, math.floor(S().opacity * 100 + 0.5)))
    end)
    ui.opacity:SetPoint("LEFT", X, 0)
    ui.opacityValue = W.Text(f, "body", "text")
    ui.opacityValue:SetPoint("LEFT", ui.opacity, "RIGHT", 10, 0)
    f = labelLine(card, L.SETTINGS_SCALE)
    local function step(d)
        S().scale = ns.SettingsDefaults.ClampScale((S().scale or 1) + d)
        ns.MainWindow.ApplyScale()
        SettingsTab.Refresh()
    end
    local minus = W.Button(f, "-", 24, 20, function() step(-ns.SettingsDefaults.SCALE_STEP) end)
    minus:SetPoint("LEFT", X, 0)
    ui.scaleLabel = W.Text(f, "body", "text")
    ui.scaleLabel:SetPoint("LEFT", minus, "RIGHT", 12, 0)
    local plus = W.Button(f, "+", 24, 20, function() step(ns.SettingsDefaults.SCALE_STEP) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 52, 0)
    f = labelLine(card, L.SETTINGS_FONT, true)
    ui.font = W.Segmented(f, {
        { id = "small", label = L.FONT_SMALL, width = 80 },
        { id = "normal", label = L.FONT_NORMAL, width = 80 },
        { id = "large", label = L.FONT_LARGE, width = 80 },
    }, function(size)
        S().fontSize = size
        W.ApplySkin()
        SettingsTab.Refresh()
        ns.MainWindow.Refresh()
    end, 20)
    ui.font:SetPoint("LEFT", X, 0)
    f = labelLine(card, L.SETTINGS_DETAILS)
    ui.details = W.Segmented(f, {
        { id = "card", label = L.DETAILS_CARD, width = 80 },
        { id = "list", label = L.DETAILS_LIST, width = 80 },
    }, function(layout)
        S().detailsLayout = layout
        SettingsTab.Refresh()
        ns.MainWindow.Refresh()
    end, 20)
    ui.details:SetPoint("LEFT", X, 0)
    switchRow(card, L.SET_CLASS_COLORS, L.SET_CLASS_COLORS_HINT, "classColors", function() ns.MainWindow.Refresh() end, nil, true)
    switchRow(card, L.SET_COLORBLIND, L.SET_COLORBLIND_HINT, "colorblind", function() ns.MainWindow.Refresh() end)
    card:Finish()
    card:SetPoint("TOPLEFT", 0, -4)
    fit(content, card)
end

-- Tracking & sharing ------------------------------------------------------------
local COL_TRACK, COL_SHARE, COL_WHAT = 180, 240, 296
local function buildTracking(panel)
    local content = newPage(panel, "tracking")
    local leftW = 500
    local card = W.Card(content, L.SET_CARD_TRACKERS, leftW)
    -- The character: < name > with its level and "1 of 6".
    local pick = CreateFrame("Frame", nil, card)
    card:Add(pick, 42)
    local prev = W.Button(pick, "<", 22, 22, function() state.charIndex = math.max(1, state.charIndex - 1); SettingsTab.Refresh() end)
    prev:SetPoint("LEFT", 10, 0)
    ui.charLabel = W.Text(pick, "body", "text")
    ui.charLabel:SetPoint("TOPLEFT", prev, "TOPRIGHT", 10, 3)
    ui.charSub = W.Text(pick, "small", "muted")
    ui.charSub:SetPoint("TOPLEFT", ui.charLabel, "BOTTOMLEFT", 0, -2)
    local nextB = W.Button(pick, ">", 22, 22, function() state.charIndex = state.charIndex + 1; SettingsTab.Refresh() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 200, 0)
    ui.shareAll = W.Button(pick, L.SHARING_OFF_CHARACTER, 220, 22, function()
        local c = selectedChar()
        if c then
            ns.TrackerList.EnsureFlags(c)
            local turnOn = not SettingsTab.AnySharing(c)
            for _, fl in pairs(c.flags) do fl.share = turnOn end
        end
        SettingsTab.Refresh()
    end)
    ui.shareAll:SetPoint("RIGHT", -10, 0)
    -- Column titles.
    local head = CreateFrame("Frame", nil, card)
    card:Add(head, 18)
    local function colTitle(text, x, w, justify)
        local t = W.Text(head, "small", "section")
        t:SetPoint("LEFT", x, 0)
        if w then t:SetWidth(w) end
        t:SetJustifyH(justify or "LEFT")
        t:SetText(ns.Format.Upper(text))
        return t
    end
    colTitle(L.SET_COL_TRACKER, 10)
    colTitle(L.TRACK, COL_TRACK - 10, W.SWITCH_W + 20, "CENTER")
    colTitle(L.SHARE, COL_SHARE - 10, W.SWITCH_W + 20, "CENTER")
    colTitle(L.SET_COL_WHAT, COL_WHAT)
    for i, t in ipairs(ns.TrackerList.ORDER) do
        local id = t.id
        local row = { id = id }
        local f = CreateFrame("Frame", nil, card)
        card:Add(f, 24, i % 2 == 0)
        local label = W.Text(f, "body", "text")
        label:SetPoint("LEFT", 10, 0)
        label:SetWidth(COL_TRACK - 16)
        label:SetText(L["TRACKER_" .. id])
        row.track = W.Switch(f, function()
            local c = selectedChar()
            return c ~= nil and ns.TrackerList.IsTracking(c, id)
        end, function(v)
            local c = selectedChar()
            if c then ns.TrackerList.EnsureFlags(c); c.flags[id].track = v end
            SettingsTab.Refresh()
        end)
        row.track:SetPoint("LEFT", COL_TRACK, 0)
        row.share = W.Switch(f, function()
            local c = selectedChar()
            return c ~= nil and c.flags and c.flags[id] and c.flags[id].share ~= false and true or false
        end, function(v)
            local c = selectedChar()
            if c then ns.TrackerList.EnsureFlags(c); c.flags[id].share = v end
        end)
        row.share:SetPoint("LEFT", COL_SHARE, 0)
        row.what = W.Text(f, "small", "muted")
        row.what:SetPoint("LEFT", COL_WHAT, 0)
        row.what:SetPoint("RIGHT", f, "RIGHT", -10, 0)
        row.what:SetWordWrap(false)
        row.note = row.what -- older name (tests)
        ui.trackerRows[#ui.trackerRows + 1] = row
        ui.toggles[#ui.toggles + 1] = row.track
        ui.toggles[#ui.toggles + 1] = row.share
    end
    card:Finish()
    card:SetPoint("TOPLEFT", 0, -4)

    local rightW = WIDTH - leftW - GAP
    local share = W.Card(content, L.SET_CARD_SHARING, rightW)
    switchRow(share, L.SET_PAUSE_ALL, L.SET_PAUSE_ALL_HINT, "sharingPaused")
    switchRow(share, L.SET_SHARE_NAME, L.SET_SHARE_NAME_HINT, "shareNameInDungeons", nil, nil, true)
    switchRow(share, L.SET_RELAY, L.SET_RELAY_HINT, "relayFriends", nil, L.RELAY_FRIENDS_NOTE)
    switchRow(share, L.SET_CATCHUP, L.SET_CATCHUP_HINT, "catchUpFromFriends", nil, L.CATCHUP_FRIENDS_NOTE, true)
    share:Finish()
    share:SetPoint("TOPLEFT", leftW + GAP, -4)
    local how = W.Card(content, L.SET_CARD_HOW, rightW)
    local body = CreateFrame("Frame", nil, how)
    how:Add(body, 130)
    local t = W.Text(body, "small", "muted")
    t:SetPoint("TOPLEFT", 10, -6)
    t:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    t:SetWordWrap(true)
    t:SetSpacing(2)
    t:SetText(L.SETTINGS_TRACKING_NOTE .. "\n\n" .. L.SHARING_NOT_LIVE)
    how:Finish()
    local sh = share:GetHeight()
    how:SetPoint("TOPLEFT", leftW + GAP, -4 - (type(sh) == "number" and sh or 0) - GAP)
    fit(content, card, share, how)
end

-- Notices ---------------------------------------------------------------------
local function buildNotices(panel)
    local content = newPage(panel, "notices")
    local w = (WIDTH - 2 * GAP) / 3
    local show = switchCard(content, L.SET_CARD_SHOW, w, {
        { L.SET_ON_SCREEN, L.SET_ON_SCREEN_HINT, "toastsShown" },
        { L.SET_IN_CHAT, L.SET_IN_CHAT_HINT, "toastChat" },
        { L.SET_BUNDLE, L.SET_BUNDLE_HINT, "toastBundle" },
        { L.SET_AWAY, L.SET_AWAY_HINT, "awayDigest" },
        { L.SET_TOOLTIP, L.SET_TOOLTIP_HINT, "tooltipInfo" },
        { L.SET_WELCOME, L.SET_WELCOME_HINT, "welcomeEveryLogin" },
        { L.SET_STALE, L.SET_STALE_HINT, "askStale" },
    }, true)
    show:SetPoint("TOPLEFT", 0, -4)
    local yours = switchCard(content, L.SETTINGS_TOASTS_YOURS, w, {
        { L.SET_LEVEL, L.SET_LEVEL_HINT, "levelToast" },
        { L.SET_SESSION, L.SET_SESSION_HINT, "sessionSummary" },
        { L.SET_RECAP, L.SET_RECAP_HINT, "sessionRecap", function() ns.MainWindow.Refresh() end },
        { L.SET_WEEKLY, L.SET_WEEKLY_HINT, "weeklyRecap" },
        { L.SET_BESTS, L.SET_BESTS_HINT, "bestToasts" },
        { L.SET_LEADER, L.SET_LEADER_HINT, "leaderToasts" },
    }, true)
    yours:SetPoint("TOPLEFT", w + GAP, -4)
    local friends = switchCard(content, L.SETTINGS_TOASTS_FRIENDS, w, {
        { L.SET_F_MILESTONES, L.SET_F_MILESTONES_HINT, "friendToasts" },
        { L.SET_F_MAX, L.SET_F_MAX_HINT, "friendToastsMaxLevel" },
        { L.SET_F_CHAINS, L.SET_F_CHAINS_HINT, "friendToastsChains" },
        { L.SET_F_DUNGEONS, L.SET_F_DUNGEONS_HINT, "friendToastsDungeons" },
        { L.SET_F_PROFS, L.SET_F_PROFS_HINT, "friendToastsProfessions" },
        { L.SET_F_LOOT, L.SET_F_LOOT_HINT, "friendToastsLoot" },
        { L.SET_F_JOINED, L.SET_F_JOINED_HINT, "friendToastsJoined" },
    }, true)
    friends:SetPoint("TOPLEFT", 2 * (w + GAP), -4)
    fit(content, show, yours, friends)
end

-- Block list ------------------------------------------------------------------
local function buildBlock(panel)
    local content = newPage(panel, "block")
    local card = W.Card(content, L.SETTINGS_BLOCKLIST, WIDTH)
    local top = CreateFrame("Frame", nil, card)
    card:Add(top, 56)
    local note = W.Text(top, "small", "muted")
    note:SetPoint("TOPLEFT", 10, -6)
    note:SetPoint("RIGHT", top, "RIGHT", -10, 0)
    note:SetWordWrap(true)
    note:SetText(L.BLOCKLIST_NOTE)
    local input = CreateFrame("EditBox", nil, top)
    input:SetSize(220, 20)
    input:SetAutoFocus(false)
    input:SetFontObject(_G.GameFontHighlightSmall or _G.ChatFontNormal)
    W.Background(input, "bg")
    W.Border(input, "border", 1)
    input:SetTextInsets(4, 4, 0, 0)
    input:SetPoint("TOPLEFT", 10, -28)
    local function addBlock()
        local tag = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if tag ~= "" then ns.db.blocklist[tag] = true end
        input:SetText("")
        input:ClearFocus()
        ns.MainWindow.Refresh()
    end
    input:SetScript("OnEnterPressed", addBlock)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addB = W.Button(top, L.BLOCK, 80, 20, addBlock)
    addB:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local empty = CreateFrame("Frame", nil, card)
    card:Add(empty, 22)
    ui.blockEmpty = W.Text(empty, "small", "muted")
    ui.blockEmpty:SetPoint("LEFT", 10, 0)
    ui.blockEmpty:SetText(L.BLOCKLIST_EMPTY)
    for i = 1, BLOCK_ROWS do
        local row = CreateFrame("Frame", nil, card)
        card:Add(row, 24, i % 2 == 0)
        row.text = W.Text(row, "body", "text")
        row.text:SetPoint("LEFT", 10, 0)
        row.button = W.Button(row, L.UNBLOCK, 80, 18)
        row.button:SetPoint("RIGHT", -10, 0)
        ui.blockRows[i] = row
    end
    local more = CreateFrame("Frame", nil, card)
    card:Add(more, 20)
    ui.blockMore = W.Text(more, "small", "muted")
    ui.blockMore:SetPoint("LEFT", 10, 0)
    card:Finish()
    card:SetPoint("TOPLEFT", 0, -4)
    fit(content, card)
end

-- About -----------------------------------------------------------------------
local function buildAbout(panel)
    local content = newPage(panel, "about")
    local card = W.Card(content, L.SETTINGS_ABOUT, WIDTH)
    local body = CreateFrame("Frame", nil, card)
    card:Add(body, 150)
    local about = W.Text(body, "body", "text")
    about:SetPoint("TOPLEFT", 10, -8)
    about:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    about:SetWordWrap(true)
    about:SetText(string.format(L.ABOUT_TEXT, ns.VERSION))
    card:Finish()
    card:SetPoint("TOPLEFT", 0, -4)
    fit(content, card)
end

local function build(panel)
    ui.content = panel
    local items = {}
    for _, id in ipairs(SettingsTab.PAGES) do
        items[#items + 1] = { id = id, label = L["SET_PAGE_" .. id:upper()], width = id == "tracking" and 130 or 90 }
    end
    ui.tabs = W.Segmented(panel, items, function(id) SettingsTab.Show(id) end, 22)
    ui.tabs:SetPoint("TOPLEFT", 0, -2)
    ui.minimap = buildGeneral(panel)
    buildLook(panel)
    buildTracking(panel)
    buildNotices(panel)
    buildBlock(panel)
    buildAbout(panel)
    SettingsTab.Show(state.page)
end

ns.MainWindow.RegisterTab("settings", build, function() SettingsTab.Show(state.page) end)
