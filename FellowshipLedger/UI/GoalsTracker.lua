-- UI/GoalsTracker.lua
-- The goals tracker (D-121): once session goals are started (D-116), a small window
-- on screen lists each goal with a progress bar. Drag it anywhere (the place is kept
-- in settings.goalsTrackerPos); the x hides it until the next goals are started, or
-- /fl goals tracker brings it back. Settings > "Show the goals tracker on screen"
-- turns it off for good. Under the title, the session's played and active time. It
-- redraws every few seconds while shown.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Goals = ns.Goals

local Tracker = {}
ns.GoalsTracker = Tracker

Tracker.WIDTH = 250
Tracker.ROW_H = 30
Tracker.DONE_H = 18 -- a reached goal: one green line, no bar (Austin, 2026-11-11)
Tracker.TOP = 46 -- the title and the session time line above the goals
Tracker.REFRESH = 5 -- seconds between redraws while shown

local frame
local rows = {}

local function fmt() return { Number = ns.Format.Number, Duration = ns.Format.Duration } end

local function savePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    if point then ns.db.settings.goalsTrackerPos = { point, relativePoint, math.floor(x or 0), math.floor(y or 0) } end
end

local function place(f)
    f:ClearAllPoints()
    local p = ns.db.settings.goalsTrackerPos
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, frame)
    r:SetWidth(Tracker.WIDTH - 20)
    r.text = W.Text(r, "small", "text")
    r.text:SetPoint("TOPLEFT", 0, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.track = r:CreateTexture(nil, "BACKGROUND")
    W.Fill(r.track, "rule", 0.6)
    r.track:SetPoint("BOTTOMLEFT", 0, 2)
    r.track:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.track:SetHeight(5)
    -- Painted once: W.Fill keeps each texture for skin changes.
    r.fill = r:CreateTexture(nil, "ARTWORK")
    W.Fill(r.fill, "accent", 0.9)
    r.fill:SetPoint("BOTTOMLEFT", 0, 2)
    r.fill:SetHeight(5)
    rows[i] = r
    return r
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerGoalsTracker", UIParent)
    f:SetSize(Tracker.WIDTH, 80)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    W.Background(f, "bg", 0.85)
    W.Border(f, "border", 1)
    f.title = W.Text(f, "body", "heading")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    f.title:SetJustifyH("LEFT")
    -- The session's time: played since it started, and active (what XP per hour counts).
    f.time = W.Text(f, "small", "muted")
    f.time:SetPoint("TOPLEFT", 10, -26)
    f.time:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.time:SetJustifyH("LEFT")
    f.close = W.Button(f, "x", 18, 18, function() Tracker.Close() end)
    f.close:SetPoint("TOPRIGHT", -5, -5)
    place(f)
    f:Hide()
    return f
end

-- The goals set for this session, if the tracker should show them.
function Tracker.Wanted()
    if ns.db.settings.goalsTracker == false or ns.Data.IsFake() then return nil end
    local set = ns.SessionGoals.Current()
    if not (set and set.list and #set.list > 0) or set.trackerClosed then return nil end
    return set
end

-- The lines to show: goals under way first (with a bar), then the ones reached (one
-- green line each, no bar), each group in the order they were set. Returns lines, done.
function Tracker.Lines(list, now)
    local open, reached = {}, {}
    for _, g in ipairs(list or {}) do
        local value, ok = Goals.Progress(g, now)
        -- No done mark here: a reached goal is green and at the bottom (Austin, 2026-11-11).
        local line = { text = Goals.Text(g, value, false, L, fmt()), done = ok and true or false,
            fraction = Goals.Fraction(g, value, ok) }
        if ok then reached[#reached + 1] = line else open[#open + 1] = line end
    end
    for _, line in ipairs(reached) do open[#open + 1] = line end
    return open, #reached
end

-- Redraw (or hide) the tracker from the current goals.
function Tracker.Refresh()
    local set = Tracker.Wanted()
    if not set then
        if frame then frame:Hide() end
        return false
    end
    if not frame then
        local ok, f = pcall(build)
        if not ok then
            ns.Log.Warn(L.WINDOW_FAILED, tostring(f))
            return false
        end
        frame = f
    end
    local lines, done = Tracker.Lines(set.list, ns.SessionGoals.Snapshot())
    local y, width = Tracker.TOP, Tracker.WIDTH - 20
    for i, line in ipairs(lines) do
        local r = row(i)
        local h = line.done and Tracker.DONE_H or Tracker.ROW_H
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, -y)
        r:SetHeight(h - 4)
        r.text:SetText(line.text)
        W.SetTextRole(r.text, line.done and "good" or "text")
        r.track:SetShown(not line.done)
        r.fill:SetShown(not line.done)
        r.fill:SetWidth(math.max(1, width * line.fraction))
        r:Show()
        y = y + h
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    frame.title:SetText(done == #lines and string.format(L.GOALS_TRACKER_ALL_DONE, done, #lines)
        or string.format(L.GOALS_TRACKER_TITLE, done, #lines))
    local s = ns.Store.session or {}
    frame.time:SetText(string.format(L.GOALS_TRACKER_TIME, ns.Format.Duration(s.played or 0), ns.Format.Duration(s.active or 0)))
    frame:SetHeight(y + 6)
    frame:Show()
    return true
end

-- The x: hidden until the next goals are started (or /fl goals tracker).
function Tracker.Close()
    local set = ns.SessionGoals.Current()
    if set then set.trackerClosed = true end
    if frame then frame:Hide() end
end

-- /fl goals tracker: show it again for this session's goals.
function Tracker.Reopen()
    local set = ns.SessionGoals.Current()
    if not set then
        ns.Log.Info(L.GOALS_TRACKER_NONE)
        return false
    end
    set.trackerClosed = nil
    if ns.db.settings.goalsTracker == false then
        ns.Log.Info(L.GOALS_TRACKER_OFF)
        return false
    end
    return Tracker.Refresh()
end

function Tracker.Frame() return frame end

-- At login: shown again after a /reload when this session has goals.
function Tracker.Start()
    ns.Events.Every(Tracker.REFRESH, "goalsTracker", function()
        if frame and frame:IsShown() then Tracker.Refresh() end
    end)
    Tracker.Refresh()
end
