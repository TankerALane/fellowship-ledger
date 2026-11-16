-- UI/GoalsWindow.lua
-- Session goals (D-116). Off by default (Settings > "Suggest goals when a session
-- starts"). Once a character has 3 sessions of 20+ active minutes, a new session
-- (30+ minutes offline, so never a /reload) opens a window of suggested goals from its
-- own pace; tick the ones you want, change them with - and +, then Start. "Skip today"
-- stops the window until tomorrow. /fl goals opens it any time. Progress shows on the
-- Me tab; the last session's summary at login says how it went.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Goals = ns.Goals

local SessionGoals = {}
ns.SessionGoals = SessionGoals

SessionGoals.PROMPT_DELAY = 12 -- seconds after login, after the welcome panel and summary
SessionGoals.MAX_ROWS = 7

local function fmt() return { Number = ns.Format.Number, Duration = ns.Format.Duration } end
local function plain(v) return ns.Trackers.Plain(v) end

-- The character's state now, for progress.
function SessionGoals.Snapshot()
    local char, s = ns.Store.char, ns.Store.session
    local level = plain(UnitLevel("player")) or char.level or 0
    local xp, xpMax = plain(UnitXP("player")), plain(UnitXPMax("player"))
    local pos = level + ((xp and xpMax and xpMax > 0) and xp / xpMax or 0)
    local ranks = {}
    for key, p in pairs(char.professions or {}) do ranks[key] = p.rank end
    local cleared = {}
    local runs = {}
    for _, r in ipairs(char.dungeons or {}) do runs[#runs + 1] = r end
    if char.currentRun then runs[#runs + 1] = char.currentRun end
    for _, r in ipairs(runs) do
        if r.completed and r.name and r.completedAt then
            -- Under its own name and under the listed name it matches ("Scarlet Monastery").
            cleared[r.name] = math.max(cleared[r.name] or 0, r.completedAt)
            for listed in pairs(ns.DungeonLevels.RANGES) do
                if ns.DungeonLevels.For(r.name) == ns.DungeonLevels.RANGES[listed] then
                    cleared[listed] = math.max(cleared[listed] or 0, r.completedAt)
                end
            end
        end
    end
    return { levelPos = pos, xp = s.counts.xp or 0, quests = s.counts.quests or 0, active = s.active or 0,
        ranks = ranks, cleared = cleared, at = time() }
end

function SessionGoals.Info()
    local char, s = ns.Store.char, ns.Store.session
    local okR, rested = ns.Compat.Try("GetXPExhaustion")
    local cleared = {}
    for name in pairs(SessionGoals.Snapshot().cleared) do cleared[name] = true end
    local level = plain(UnitLevel("player")) or char.level
    return { level = level, maxLevel = ns.Merge.maxLevel, xpMax = plain(UnitXPMax("player")),
        rested = okR and plain(rested) or nil, sessions = char.sessions, currentStart = s.start, levels = char.levels,
        professions = char.professions, cleared = cleared, dungeons = level and ns.DungeonLevels.InRange(level) or {} }
end

-- The goals set for this session, or nil.
function SessionGoals.Current()
    local char, s = ns.Store.char, ns.Store.session
    local set = char and char.goals
    if set and s and set.session == s.start then return set end
    return nil
end

function SessionGoals.Begin(list)
    local snap = SessionGoals.Snapshot()
    local chosen = {}
    for _, g in ipairs(list) do
        if g.on then
            local start = { levelPos = snap.levelPos, xp = snap.xp, quests = snap.quests, active = snap.active, at = snap.at,
                ranks = snap.ranks, rank = g.start and g.start.rank }
            chosen[#chosen + 1] = { kind = g.kind, target = g.target, name = g.name, key = g.key, max = g.max, start = start,
                rate = g.rate }
        end
    end
    if #chosen == 0 then
        ns.Store.char.goals = nil
        if ns.GoalsTracker then ns.GoalsTracker.Refresh() end
        return
    end
    ns.Store.char.goals = { session = ns.Store.session.start, list = chosen }
    SessionGoals.Tick()
    ns.MainWindow.Refresh()
    if ns.GoalsTracker then ns.GoalsTracker.Refresh() end
end

-- Each minute: save progress (for the summary at the next login) and say when a goal is reached.
function SessionGoals.Tick()
    local set = SessionGoals.Current()
    if not set then return end
    local now = SessionGoals.Snapshot()
    set.last = set.last or {}
    for i, g in ipairs(set.list) do
        local value, done = Goals.Progress(g, now)
        local was = set.last[i] and set.last[i].done
        -- took (1.14.0): active seconds from the start to the minute it was reached.
        local took = set.last[i] and set.last[i].took
        if done and not was then took = math.max(0, (now.active or 0) - ((g.start or {}).active or 0)) end
        set.last[i] = { value = value, done = done or nil, took = done and took or nil }
        if done and not was then
            local reached = 0
            for j, other in ipairs(set.list) do
                if j == i then reached = reached + 1
                elseif set.last[j] and set.last[j].done then reached = reached + 1 end
            end
            ns.Toast.Show(L.GOAL_REACHED_TITLE, { Goals.Text(g, value, false, L, fmt()),
                string.format(L.GOAL_REACHED_COUNT, reached, #set.list) }, { kind = "goal", label = L.NOTICE_K_GOAL,
                iconTex = "check", action = L.NOTICE_ACT_GOALS,
                onClick = function() if ns.GoalsTracker then ns.GoalsTracker.Reopen() end end })
        end
    end
    if ns.GoalsTracker then ns.GoalsTracker.Refresh() end
end

-- The Me tab line under "This session".
function SessionGoals.Line()
    local set = SessionGoals.Current()
    if not set then return nil end
    return Goals.Line(set, SessionGoals.Snapshot(), L, fmt())
end

-- The goal lines for the last session's summary at login.
function SessionGoals.ResultsFor(prev)
    local set = ns.Store.char and ns.Store.char.goals
    if not (prev and set and set.session == prev.start) then return {} end
    return Goals.Results(set, L, fmt())
end

-- Window -------------------------------------------------------------------------
-- 1.14.0 (D-137): a head with the level in a ring, one row per goal (a tick box, a
-- small badge for its kind, the label, a bar of your usual session against the
-- target, a grey hint, and - value + on the right), and a foot that counts the goals
-- picked and says about how long they take at your usual pace.

local MEDIA = "Interface\\AddOns\\FellowshipLedger\\media\\"
SessionGoals.WIDTH = 540
SessionGoals.ROW_H = 54
SessionGoals.HEAD_H = 64
SessionGoals.FOOT_H = 52
SessionGoals.BAR_W = 250

local win
local rows = {}
local current = {} -- the suggestions on show
local preview = false -- made-up goals (/fl shots): Start sets nothing

local previewXpMax
local function xpMaxNow()
    if preview then return previewXpMax end
    return plain(UnitXPMax("player"))
end

local function tint(tex, role, alpha)
    local c = W.Color(role)
    tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
end

-- The foot: "3 goals picked" and "About 2h at your usual pace".
function SessionGoals.FootText(list)
    local n = 0
    for _, g in ipairs(list or {}) do if g.on then n = n + 1 end end
    local picked = string.format(n == 1 and L.GOALS_PICKED_ONE or L.GOALS_PICKED, n)
    local secs = Goals.Estimate(list)
    local about = ""
    if secs and secs > 0 then
        about = string.format(L.GOALS_ABOUT, ns.Format.DurationShort(math.max(600, math.floor(secs / 600 + 0.5) * 600)))
    end
    return picked, about
end

local function redraw()
    local xpMax = xpMaxNow()
    for i, row in ipairs(rows) do
        local g = current[i]
        row:SetShown(g ~= nil)
        if g then
            local on = g.on and true or false
            row.check:SetShown(on)
            W.SetTextRole(row.label, on and "text" or "muted")
            row.label:SetText(Goals.KindLabel(g, L))
            row.icon.text:SetText(L["GOAL_ICON_" .. g.kind:upper()] or "")
            W.SetTextRole(row.icon.text, on and "accent" or "muted")
            row.shade:SetShown(on)
            row.box.fill:SetShown(on)
            local usual, target = Goals.Scale(g)
            row.bar:SetShown(usual ~= nil)
            if usual then
                local w = SessionGoals.BAR_W
                row.bar.usual:SetWidth(math.max(1, w * math.min(1, usual)))
                row.bar.target:ClearAllPoints()
                row.bar.target:SetPoint("LEFT", row.bar, "LEFT", math.floor(w * math.min(1, target)) - 1, 0)
                tint(row.bar.target, on and "accent" or "muted")
            end
            row.hint:ClearAllPoints()
            row.hint:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, usual and -16 or -5)
            row.hint:SetText(Goals.Hint(g, L))
            local adjustable = Goals.Step(g, xpMax) > 0
            row.minus:SetShown(adjustable)
            row.plus:SetShown(adjustable)
            row.value:SetShown(adjustable)
            row.value:SetText(Goals.Value(g, fmt()))
            W.SetTextRole(row.value, on and "text" or "muted")
        end
    end
    if win then
        local picked, about = SessionGoals.FootText(current)
        win.picked:SetText(picked)
        win.about:SetText(about)
    end
end

local function makeRow(f, i)
    local row = CreateFrame("Button", nil, f)
    row:SetSize(SessionGoals.WIDTH - 20, SessionGoals.ROW_H - 2)
    row:SetPoint("TOPLEFT", 10, -(SessionGoals.HEAD_H + 6) - (i - 1) * SessionGoals.ROW_H)
    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    W.Fill(row.shade, "accent", 0.06)
    -- The tick box: an outline, filled gold with a check mark when ticked.
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(18, 18)
    row.box:SetPoint("LEFT", 8, 0)
    W.Border(row.box, "buttonBorder", 1)
    row.box.fill = row.box:CreateTexture(nil, "ARTWORK")
    row.box.fill:SetAllPoints()
    W.Fill(row.box.fill, "accent", 0.9)
    row.check = row.box:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture(MEDIA .. "check")
    row.check:SetSize(14, 14)
    row.check:SetPoint("CENTER", 0, 0)
    tint(row.check, "bg")
    -- The kind badge.
    row.icon = CreateFrame("Frame", nil, row)
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row.box, "RIGHT", 10, 0)
    W.Background(row.icon, "panel")
    W.Border(row.icon, "rule", 1)
    row.icon.text = W.Text(row.icon, "small", "accent")
    row.icon.text:SetPoint("CENTER", 0, 0)
    row.icon.text:SetJustifyH("CENTER")
    row.label = W.Text(row, "body", "text")
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 0)
    row.label:SetWidth(SessionGoals.WIDTH - 230)
    row.label:SetWordWrap(false)
    -- Your usual session (grey) and the target (a gold tick) on one scale.
    row.bar = CreateFrame("Frame", nil, row)
    row.bar:SetSize(SessionGoals.BAR_W, 12)
    row.bar:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
    row.bar.track = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.track:SetPoint("LEFT", 0, 0)
    row.bar.track:SetSize(SessionGoals.BAR_W, 4)
    W.Fill(row.bar.track, "rule", 0.35)
    row.bar.usual = row.bar:CreateTexture(nil, "ARTWORK")
    row.bar.usual:SetPoint("LEFT", 0, 0)
    row.bar.usual:SetHeight(4)
    W.Fill(row.bar.usual, "muted", 0.7)
    row.bar.target = row.bar:CreateTexture(nil, "OVERLAY")
    row.bar.target:SetTexture(MEDIA .. "switch-knob")
    row.bar.target:SetSize(3, 12)
    row.hint = W.Text(row, "small", "muted")
    row.hint:SetWidth(SessionGoals.WIDTH - 230)
    row.hint:SetWordWrap(false)
    row.plus = W.Button(row, "+", 24, 22, function()
        local g = current[i]
        if g then Goals.Adjust(g, 1, xpMaxNow()); g.on = true; redraw() end
    end)
    row.plus:SetPoint("RIGHT", -8, 0)
    row.value = W.Text(row, "body", "text")
    row.value:SetWidth(50)
    row.value:SetJustifyH("CENTER")
    row.value:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
    row.minus = W.Button(row, "-", 24, 22, function()
        local g = current[i]
        if g then Goals.Adjust(g, -1, xpMaxNow()); g.on = true; redraw() end
    end)
    row.minus:SetPoint("RIGHT", row.value, "LEFT", -2, 0)
    -- A click anywhere else on the row ticks or unticks the goal.
    row:SetScript("OnClick", function()
        local g = current[i]
        if g then g.on = not g.on; redraw() end
    end)
    row:SetScript("OnEnter", function(self) self.shade:Show() end)
    row:SetScript("OnLeave", function() redraw() end)
    return row
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerGoalsWindow", UIParent)
    f:SetSize(SessionGoals.WIDTH, 200)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Background(f, "bg")
    W.Border(f, "border", 2)
    -- Head: the level in a ring, the title, a grey line, the x.
    f.badge = CreateFrame("Frame", nil, f)
    f.badge:SetSize(36, 36)
    f.badge:SetPoint("TOPLEFT", 16, -14)
    f.badge.ring = f.badge:CreateTexture(nil, "ARTWORK")
    f.badge.ring:SetTexture(MEDIA .. "ring")
    f.badge.ring:SetAllPoints()
    tint(f.badge.ring, "accent")
    f.badge.text = W.Text(f.badge, "body", "heading")
    f.badge.text:SetPoint("CENTER", 0, 0)
    f.title = W.Text(f, "heading", "heading")
    f.title:SetPoint("TOPLEFT", f.badge, "TOPRIGHT", 12, 0)
    f.title:SetText(L.GOALS_HEAD)
    f.sub = W.Text(f, "small", "muted")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.sub:SetWordWrap(false)
    f.close = W.Button(f, "x", 22, 20, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -12, -12)
    f.headRule = W.Rule(f, "rule")
    f.headRule:SetPoint("TOPLEFT", 0, -SessionGoals.HEAD_H)
    f.headRule:SetPoint("TOPRIGHT", 0, -SessionGoals.HEAD_H)
    for i = 1, SessionGoals.MAX_ROWS do rows[i] = makeRow(f, i) end
    -- Foot: the count and the time, then Skip today, Not now and Start.
    f.foot = CreateFrame("Frame", nil, f)
    f.foot:SetPoint("BOTTOMLEFT", 2, 2)
    f.foot:SetPoint("BOTTOMRIGHT", -2, 2)
    f.foot:SetHeight(SessionGoals.FOOT_H)
    W.Background(f.foot, "panel")
    local footRule = W.Rule(f.foot, "rule")
    footRule:SetPoint("TOPLEFT", 0, 0)
    footRule:SetPoint("TOPRIGHT", 0, 0)
    f.picked = W.Text(f.foot, "body", "accent")
    f.picked:SetPoint("TOPLEFT", 14, -10)
    f.about = W.Text(f.foot, "small", "muted")
    f.about:SetPoint("TOPLEFT", f.picked, "BOTTOMLEFT", 0, -3)
    local start = W.Button(f.foot, L.GOALS_START, 96, 26, function()
        if not preview then SessionGoals.Begin(current) end
        f:Hide()
    end)
    start:SetPoint("RIGHT", -12, 0)
    start:SetSelected(true)
    start:SetScript("OnLeave", nil)
    start:SetScript("OnEnter", nil)
    local later = W.Button(f.foot, L.GOALS_NOT_NOW, 84, 26, function() f:Hide() end)
    later:SetPoint("RIGHT", start, "LEFT", -8, 0)
    local skip = W.Button(f.foot, L.GOALS_SKIP_TODAY, 84, 26, function()
        if not preview then ns.Store.char.goalsSkipDay = ns.Store.Today() end
        f:Hide()
    end)
    skip:SetPoint("RIGHT", later, "LEFT", -8, 0)
    f.start, f.later, f.skip = start, later, skip
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerGoalsWindow") end
    f:Hide()
    return f
end
SessionGoals.rows = rows -- for tests

-- Open the window. force: /fl goals (says why when there is nothing to suggest yet).
function SessionGoals.Open(force)
    if not (ns.tracking and ns.Store.char and ns.Store.session) then return false end
    local ready, n = Goals.Ready(ns.Store.char.sessions, ns.Store.session.start)
    if not ready then
        if force then ns.Log.Info(L.GOALS_NOT_READY, Goals.QUALIFY_COUNT, n) end
        return false
    end
    local list = Goals.Suggest(SessionGoals.Info())
    if #list == 0 then
        if force then ns.Log.Info(L.GOALS_NONE) end
        return false
    end
    -- Goals already set this session come back ticked with their targets.
    local set = SessionGoals.Current()
    if set then
        for _, g in ipairs(list) do
            g.on = false
            for _, old in ipairs(set.list) do
                if old.kind == g.kind and old.key == g.key and old.name == g.name then g.on, g.target = true, old.target end
            end
        end
    end
    local char = ns.Store.char
    preview = false
    local info = SessionGoals.Info()
    return SessionGoals.Show(list, { name = char.display or char.name or "?", class = char.class, level = info.level or char.level or 0,
        rested = info.rested, xpMax = info.xpMax, sessions = #Goals.Qualifying(char.sessions, ns.Store.session.start) })
end

-- Show a list of suggestions in the window. who: { name, class, level, rested
-- (XP), xpMax, sessions (how many recent sessions the suggestions come from) }.
function SessionGoals.Show(list, who)
    while #list > SessionGoals.MAX_ROWS do table.remove(list) end
    current = list
    if not win then
        local ok, f = pcall(build)
        if not ok then
            ns.Log.Warn(L.WINDOW_FAILED, tostring(f))
            return false
        end
        win = f
    end
    win.badge.text:SetText(tostring(who.level or "?"))
    win.sub:SetText(SessionGoals.SubText(who))
    win:SetHeight(SessionGoals.HEAD_H + 12 + #list * SessionGoals.ROW_H + SessionGoals.FOOT_H)
    redraw()
    win:Show()
    return true
end

-- "Brannoc  -  level 31  -  1.5 bubbles rested  -  from your last 6 sessions"
function SessionGoals.SubText(who)
    local parts = { W.ClassName(who.name or "?", who.class), string.format(L.GOALS_SUB_LEVEL, who.level or 0) }
    local rested, xpMax = tonumber(who.rested), tonumber(who.xpMax)
    if rested and xpMax and rested > 0 and xpMax > 0 then
        parts[#parts + 1] = string.format(L.GOALS_SUB_RESTED, string.format("%.1f", rested / xpMax * 20))
    end
    if (tonumber(who.sessions) or 0) > 0 then parts[#parts + 1] = string.format(L.GOALS_SUB_FROM, who.sessions) end
    return table.concat(parts, "  -  ")
end

-- /fl shots: the window with goals suggested from a made-up character's history.
-- Nothing is saved: Start and Skip today only close it. xpMax is a stand-in for the
-- game's XP table, which the fake data does not have.
function SessionGoals.Preview(char, now)
    if not char then return false end
    local level = char.level or 1
    previewXpMax = 400 + level * level * 60
    local list = Goals.Suggest({ level = level, maxLevel = ns.Merge.maxLevel or 60, xpMax = previewXpMax,
        sessions = char.sessions, currentStart = now, levels = char.levels, professions = char.professions,
        cleared = {}, dungeons = ns.DungeonLevels.InRange(level) })
    if #list == 0 then return false end
    preview = true
    return SessionGoals.Show(list, { name = char.display or char.name or "?", class = char.class, level = level,
        rested = previewXpMax * 0.075, xpMax = previewXpMax, sessions = #Goals.Qualifying(char.sessions, now) })
end

-- The window, for /fl shots (nil until first opened).
function SessionGoals.Frame() return win end

-- At login: a new session, the switch on, enough sessions, not skipped today.
function SessionGoals.Start()
    ns.Events.Every(60, "goals", function() pcall(SessionGoals.Tick) end)
    local char = ns.Store.char
    if not (ns.db.settings.goals and ns.Store.newSession) then return end
    if char.goalsSkipDay == ns.Store.Today() then return end
    ns.Events.After(SessionGoals.PROMPT_DELAY, function() pcall(SessionGoals.Open, false) end)
end
