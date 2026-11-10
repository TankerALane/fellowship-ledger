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
            chosen[#chosen + 1] = { kind = g.kind, target = g.target, name = g.name, key = g.key, max = g.max, start = start }
        end
    end
    if #chosen == 0 then
        ns.Store.char.goals = nil
        return
    end
    ns.Store.char.goals = { session = ns.Store.session.start, list = chosen }
    SessionGoals.Tick()
    ns.MainWindow.Refresh()
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
        set.last[i] = { value = value, done = done or nil }
        if done and not was then
            ns.Toast.Show(L.GOAL_REACHED_TITLE, { Goals.Text(g, value, done, L, fmt()) })
        end
    end
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

local win
local rows = {}
local current = {} -- the suggestions on show

local function redraw()
    local xpMax = plain(UnitXPMax("player"))
    for i, row in ipairs(rows) do
        local g = current[i]
        row:SetShown(g ~= nil)
        if g then
            row.label.text:SetText((g.on and "[x] " or "[ ] ") .. Goals.Label(g, L, fmt()))
            row.hint:SetText(Goals.Hint(g, L))
            local adjustable = Goals.Step(g, xpMax) > 0
            row.minus:SetShown(adjustable)
            row.plus:SetShown(adjustable)
        end
    end
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerGoalsWindow", UIParent)
    f:SetSize(520, 120 + SessionGoals.MAX_ROWS * 40)
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
    f.title = W.Text(f, "heading", "heading")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.intro = W.Text(f, "small", "muted")
    f.intro:SetPoint("TOPLEFT", 16, -38)
    f.intro:SetPoint("RIGHT", -16, 0)
    f.intro:SetWordWrap(true)
    f.intro:SetText(L.GOALS_INTRO)
    local xpMaxNow = function() return plain(UnitXPMax("player")) end
    for i = 1, SessionGoals.MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(488, 36)
        row:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 40)
        row.label = W.Button(row, "", 380, 20, function()
            local g = current[i]
            if g then g.on = not g.on; redraw() end
        end)
        row.label:SetPoint("TOPLEFT", 0, 0)
        row.label.text:ClearAllPoints()
        row.label.text:SetPoint("LEFT", 6, 0)
        row.label.text:SetJustifyH("LEFT")
        row.hint = W.Text(row, "small", "muted")
        row.hint:SetPoint("TOPLEFT", 6, -22)
        row.minus = W.Button(row, "-", 24, 20, function()
            local g = current[i]
            if g then Goals.Adjust(g, -1, xpMaxNow()); g.on = true; redraw() end
        end)
        row.minus:SetPoint("TOPRIGHT", -30, 0)
        row.plus = W.Button(row, "+", 24, 20, function()
            local g = current[i]
            if g then Goals.Adjust(g, 1, xpMaxNow()); g.on = true; redraw() end
        end)
        row.plus:SetPoint("TOPRIGHT", 0, 0)
        rows[i] = row
    end
    local start = W.Button(f, L.GOALS_START, 140, 24, function()
        SessionGoals.Begin(current)
        f:Hide()
    end)
    start:SetPoint("BOTTOMLEFT", 16, 14)
    local later = W.Button(f, L.GOALS_NOT_NOW, 140, 24, function() f:Hide() end)
    later:SetPoint("BOTTOM", 0, 14)
    local skip = W.Button(f, L.GOALS_SKIP_TODAY, 140, 24, function()
        ns.Store.char.goalsSkipDay = ns.Store.Today()
        f:Hide()
    end)
    skip:SetPoint("BOTTOMRIGHT", -16, 14)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerGoalsWindow") end
    f:Hide()
    return f
end

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
    local char = ns.Store.char
    win.title:SetText(string.format(L.GOALS_TITLE, char.display or char.name or "?", char.level or 0))
    win:SetHeight(120 + #list * 40)
    redraw()
    win:Show()
    return true
end

-- At login: a new session, the switch on, enough sessions, not skipped today.
function SessionGoals.Start()
    ns.Events.Every(60, "goals", function() pcall(SessionGoals.Tick) end)
    local char = ns.Store.char
    if not (ns.db.settings.goals and ns.Store.newSession) then return end
    if char.goalsSkipDay == ns.Store.Today() then return end
    ns.Events.After(SessionGoals.PROMPT_DELAY, function() pcall(SessionGoals.Open, false) end)
end
