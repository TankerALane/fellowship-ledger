-- UI/SettingsTab.lua
-- Settings: per-character Track/Share toggles for every tracker, master "pause all
-- sharing", the dungeon-name opt-in, appearance (skin, scale, font size,
-- colorblind-safe palette, minimap button), toasts, block list, recommended addons
-- and about. Everything here edits ns.db.settings or a character's flags.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local SettingsTab = {}
ns.SettingsTab = SettingsTab

local ui = { toggles = {}, trackerRows = {}, blockRows = {} }
local state = { charIndex = 1 }
local BLOCK_ROWS = 8
local QUESTIE_URL = "https://www.curseforge.com/wow/addons/questie"

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

function SettingsTab.Refresh()
    if not ui.content then return end
    local char, key, count = selectedChar()
    if char then
        ui.shareAll.text:SetText(SettingsTab.AnySharing(char) and L.SHARING_OFF_CHARACTER or L.SHARING_ON_CHARACTER)
    end
    local shown = shooting() and char and char.name or key
    ui.charLabel:SetText(char and string.format(L.SETTINGS_CHARACTER, shown, state.charIndex, count) or L.SETTINGS_NO_CHARACTER)
    for _, row in ipairs(ui.trackerRows) do
        local t = ns.TrackerList.byId[row.id]
        local unavailable = t.status == "unavailable"
        row.track:SetShown(char ~= nil)
        row.share:SetShown(char ~= nil)
        if char then
            row.track:SetDisabled(unavailable)
            row.share:SetDisabled(unavailable or not ns.TrackerList.IsTracking(char, row.id) or S().sharingPaused)
        end
        row.note:SetText(L["STATUS_" .. ns.TrackerList.Status(t, ns.Compat.flavor):upper()])
    end
    for _, t in ipairs(ui.toggles) do t:Refresh() end
    for skin, b in pairs(ui.skinButtons) do b:SetSelected(S().skin == skin) end
    for size, b in pairs(ui.fontButtons) do b:SetSelected(S().fontSize == size) end
    for layout, b in pairs(ui.detailButtons) do b:SetSelected((S().detailsLayout or "card") == layout) end
    ui.scaleLabel:SetText(string.format(L.SETTINGS_SCALE_VALUE, S().scale or 1))
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

local function build(panel)
    local scroll, content = W.ScrollArea(panel)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    content:SetWidth(800)
    ui.content = content
    local y = -4

    local function heading(text)
        y = y - 8
        local h = W.Text(content, "large", "heading")
        h:SetPoint("TOPLEFT", 4, y)
        h:SetText(text)
        y = y - 22
        local r = W.Rule(content, "rule")
        r:SetPoint("TOPLEFT", 4, y + 2)
        r:SetPoint("TOPRIGHT", -4, y + 2)
        y = y - 4
    end
    local function note(text)
        local t = W.Text(content, "small", "muted")
        t:SetPoint("TOPLEFT", 8, y)
        t:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        t:SetWordWrap(true)
        t:SetText(text)
        y = y - 30
        return t
    end
    local function toggle(label, field, onChange, x)
        local tg = W.Toggle(content, label, function() return S()[field] == true end, function(v)
            S()[field] = v
            if onChange then onChange(v) end
            SettingsTab.Refresh()
        end, 360)
        tg:SetPoint("TOPLEFT", x or 8, y)
        ui.toggles[#ui.toggles + 1] = tg
        y = y - 22
        return tg
    end

    -- Tracking and sharing ---------------------------------------------------
    heading(L.SETTINGS_TRACKING)
    note(L.SETTINGS_TRACKING_NOTE)
    local prev = W.Button(content, "<", 24, 20, function() state.charIndex = math.max(1, state.charIndex - 1); SettingsTab.Refresh() end)
    prev:SetPoint("TOPLEFT", 8, y)
    local nextB = W.Button(content, ">", 24, 20, function() state.charIndex = state.charIndex + 1; SettingsTab.Refresh() end)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    ui.charLabel = W.Text(content, "body", "text")
    ui.charLabel:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    y = y - 28
    for _, t in ipairs(ns.TrackerList.ORDER) do
        local id = t.id
        local row = { id = id }
        local label = W.Text(content, "body", "text")
        label:SetPoint("TOPLEFT", 8, y - 2)
        label:SetWidth(170)
        label:SetText(L["TRACKER_" .. id])
        row.track = W.Toggle(content, L.TRACK, function()
            local c = selectedChar()
            return c ~= nil and ns.TrackerList.IsTracking(c, id)
        end, function(v)
            local c = selectedChar()
            if c then ns.TrackerList.EnsureFlags(c); c.flags[id].track = v end
            SettingsTab.Refresh()
        end, 90)
        row.track:SetPoint("TOPLEFT", 184, y)
        row.share = W.Toggle(content, L.SHARE, function()
            local c = selectedChar()
            return c ~= nil and c.flags and c.flags[id] and c.flags[id].share ~= false and true or false
        end, function(v)
            local c = selectedChar()
            if c then ns.TrackerList.EnsureFlags(c); c.flags[id].share = v end
        end, 90)
        row.share:SetPoint("TOPLEFT", 280, y)
        row.note = W.Text(content, "small", "muted")
        row.note:SetPoint("TOPLEFT", 380, y - 4)
        ui.trackerRows[#ui.trackerRows + 1] = row
        ui.toggles[#ui.toggles + 1] = row.track
        ui.toggles[#ui.toggles + 1] = row.share
        y = y - 22
    end
    ui.shareAll = W.Button(content, L.SHARING_OFF_CHARACTER, 280, 22, function()
        local c = selectedChar()
        if c then
            ns.TrackerList.EnsureFlags(c)
            local turnOn = not SettingsTab.AnySharing(c)
            for _, f in pairs(c.flags) do f.share = turnOn end
        end
        SettingsTab.Refresh()
    end)
    ui.shareAll:SetPoint("TOPLEFT", 8, y - 4)
    y = y - 32
    toggle(L.SHARING_PAUSE_ALL, "sharingPaused")
    toggle(L.SHARE_NAME_DUNGEONS, "shareNameInDungeons")
    note(L.SHARING_NOT_LIVE)

    -- Appearance -------------------------------------------------------------
    heading(L.SETTINGS_APPEARANCE)
    ui.skinButtons = {}
    local skinLabel = W.Text(content, "body", "text")
    skinLabel:SetPoint("TOPLEFT", 8, y - 2)
    skinLabel:SetText(L.SETTINGS_SKIN)
    local sx = 140
    for _, skin in ipairs({ "ledger", "leather", "plain" }) do
        local b = W.Button(content, L["SKIN_" .. skin:upper()], 110, 20, function()
            S().skin = skin
            W.ApplySkin()
            SettingsTab.Refresh()
            ns.MainWindow.Refresh()
        end)
        b:SetPoint("TOPLEFT", sx, y)
        sx = sx + 116
        ui.skinButtons[skin] = b
    end
    y = y - 26
    local scaleLabel = W.Text(content, "body", "text")
    scaleLabel:SetPoint("TOPLEFT", 8, y - 2)
    scaleLabel:SetText(L.SETTINGS_SCALE)
    local function step(d)
        S().scale = ns.SettingsDefaults.ClampScale((S().scale or 1) + d)
        ns.MainWindow.ApplyScale()
        SettingsTab.Refresh()
    end
    local minus = W.Button(content, "-", 24, 20, function() step(-ns.SettingsDefaults.SCALE_STEP) end)
    minus:SetPoint("TOPLEFT", 140, y)
    ui.scaleLabel = W.Text(content, "body", "text")
    ui.scaleLabel:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    local plus = W.Button(content, "+", 24, 20, function() step(ns.SettingsDefaults.SCALE_STEP) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 60, 0)
    y = y - 26
    ui.fontButtons = {}
    local fontLabel = W.Text(content, "body", "text")
    fontLabel:SetPoint("TOPLEFT", 8, y - 2)
    fontLabel:SetText(L.SETTINGS_FONT)
    sx = 140
    for _, size in ipairs({ "small", "normal", "large" }) do
        local b = W.Button(content, L["FONT_" .. size:upper()], 80, 20, function()
            S().fontSize = size
            W.ApplySkin()
            SettingsTab.Refresh()
            ns.MainWindow.Refresh()
        end)
        b:SetPoint("TOPLEFT", sx, y)
        sx = sx + 86
        ui.fontButtons[size] = b
    end
    y = y - 26
    ui.detailButtons = {}
    local detailLabel = W.Text(content, "body", "text")
    detailLabel:SetPoint("TOPLEFT", 8, y - 2)
    detailLabel:SetText(L.SETTINGS_DETAILS)
    sx = 140
    for _, layout in ipairs({ "card", "list" }) do
        local b = W.Button(content, L["DETAILS_" .. layout:upper()], 80, 20, function()
            S().detailsLayout = layout
            SettingsTab.Refresh()
            ns.MainWindow.Refresh()
        end)
        b:SetPoint("TOPLEFT", sx, y)
        sx = sx + 86
        ui.detailButtons[layout] = b
    end
    y = y - 28
    toggle(L.SETTINGS_COLORBLIND, "colorblind", function() ns.MainWindow.Refresh() end)
    toggle(L.SETTINGS_CLASS_COLORS, "classColors", function() ns.MainWindow.Refresh() end)
    toggle(L.SETTINGS_REMEMBER_TAB, "rememberTab")
    local mm = W.Toggle(content, L.SETTINGS_MINIMAP, function() return not S().minimap.hide end, function(v)
        S().minimap.hide = not v
        ns.MinimapButton.Update()
    end, 360)
    mm:SetPoint("TOPLEFT", 8, y)
    ui.toggles[#ui.toggles + 1] = mm
    y = y - 22

    -- Toasts -----------------------------------------------------------------
    -- Three short groups (D-105): how notices show, your own, your friends'.
    heading(L.SETTINGS_TOASTS)
    toggle(L.TOAST_SHOWN, "toastsShown")
    toggle(L.TOAST_CHAT, "toastChat")
    toggle(L.TOAST_BUNDLE, "toastBundle")
    toggle(L.TOAST_AWAY, "awayDigest")
    toggle(L.TOAST_TOOLTIP, "tooltipInfo")
    toggle(L.WELCOME_EVERY_LOGIN, "welcomeEveryLogin")
    toggle(L.SETTINGS_ASK_STALE, "askStale")
    heading(L.SETTINGS_TOASTS_YOURS)
    toggle(L.TOAST_LEVEL, "levelToast")
    toggle(L.TOAST_SESSION, "sessionSummary")
    toggle(L.TOAST_RECAP, "sessionRecap", function() ns.MainWindow.Refresh() end)
    toggle(L.TOAST_WEEKLY, "weeklyRecap")
    toggle(L.TOAST_BESTS, "bestToasts")
    toggle(L.TOAST_LEADER, "leaderToasts")
    toggle(L.SETTINGS_GOALS, "goals")
    toggle(L.SETTINGS_GOALS_TRACKER, "goalsTracker", function() ns.GoalsTracker.Refresh() end)
    heading(L.SETTINGS_TOASTS_FRIENDS)
    toggle(L.TOAST_FRIENDS, "friendToasts")
    toggle(L.TOAST_FRIENDS_MAX, "friendToastsMaxLevel")
    toggle(L.TOAST_FRIENDS_CHAINS, "friendToastsChains")
    toggle(L.TOAST_FRIENDS_DUNGEONS, "friendToastsDungeons")
    toggle(L.TOAST_FRIENDS_PROFS, "friendToastsProfessions")
    toggle(L.TOAST_FRIENDS_LOOT, "friendToastsLoot")
    toggle(L.TOAST_FRIENDS_JOINED, "friendToastsJoined")

    -- Block list -------------------------------------------------------------
    heading(L.SETTINGS_BLOCKLIST)
    note(L.BLOCKLIST_NOTE)
    local input = CreateFrame("EditBox", nil, content)
    input:SetSize(220, 20)
    input:SetAutoFocus(false)
    input:SetFontObject(_G.GameFontHighlightSmall or _G.ChatFontNormal)
    W.Background(input, "panel")
    W.Border(input, "border", 1)
    input:SetTextInsets(4, 4, 0, 0)
    input:SetPoint("TOPLEFT", 8, y)
    local function addBlock()
        local tag = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if tag ~= "" then ns.db.blocklist[tag] = true end
        input:SetText("")
        input:ClearFocus()
        ns.MainWindow.Refresh()
    end
    input:SetScript("OnEnterPressed", addBlock)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addB = W.Button(content, L.BLOCK, 80, 20, addBlock)
    addB:SetPoint("LEFT", input, "RIGHT", 8, 0)
    y = y - 26
    ui.blockEmpty = W.Text(content, "small", "muted")
    ui.blockEmpty:SetPoint("TOPLEFT", 8, y)
    ui.blockEmpty:SetText(L.BLOCKLIST_EMPTY)
    for i = 1, BLOCK_ROWS do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(400, 20)
        row:SetPoint("TOPLEFT", 8, y - (i - 1) * 22)
        row.text = W.Text(row, "body", "text")
        row.text:SetPoint("LEFT")
        row.button = W.Button(row, L.UNBLOCK, 80, 18)
        row.button:SetPoint("LEFT", 240, 0)
        ui.blockRows[i] = row
    end
    y = y - BLOCK_ROWS * 22
    ui.blockMore = W.Text(content, "small", "muted")
    ui.blockMore:SetPoint("TOPLEFT", 8, y)
    y = y - 18

    -- Recommended addons -----------------------------------------------------
    heading(L.SETTINGS_RECOMMENDED)
    local q = W.Text(content, "body", "text")
    q:SetPoint("TOPLEFT", 8, y)
    q:SetText(L.QUESTIE_LINE)
    ui.questieStatus = W.Text(content, "small", "muted")
    ui.questieStatus:SetPoint("LEFT", q, "RIGHT", 12, 0)
    y = y - 20
    note(L.QUESTIE_WHY)
    local url = readOnlyBox(content, QUESTIE_URL, 420)
    url:SetPoint("TOPLEFT", 8, y + 6)
    y = y - 26

    -- About ------------------------------------------------------------------
    heading(L.SETTINGS_ABOUT)
    local about = W.Text(content, "body", "text")
    about:SetPoint("TOPLEFT", 8, y)
    about:SetPoint("RIGHT", content, "RIGHT", -8, 0)
    about:SetWordWrap(true)
    about:SetText(string.format(L.ABOUT_TEXT, ns.VERSION))
    y = y - 120

    content:SetHeight(-y + 20)
end

ns.MainWindow.RegisterTab("settings", build, function() SettingsTab.Refresh() end)
