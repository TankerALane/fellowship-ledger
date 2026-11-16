-- UI/GoalsTracker.lua
-- The goals tracker (D-121): once session goals are started (D-116), a small window
-- on screen lists each goal with a progress bar. Drag it anywhere (the place is kept
-- in settings.goalsTrackerPos); the x hides it until the next goals are started, or
-- /fl goals tracker brings it back. Settings > "Show the goals tracker on screen"
-- turns it off for good. Under the title, the session's played and active time. It
-- redraws every few seconds while shown.
-- 1.14.0 (D-137): the done count in a ring by the title, a fold button (one line:
-- the count and the first open goal; settings.goalsTrackerFolded), a white tick on each
-- bar where your usual pace would have you by now with "Ahead of your usual pace" or
-- what is left under it, the time each reached goal took, and when all are done a
-- green frame with "Pick more goals".

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Goals = ns.Goals

local Tracker = {}
ns.GoalsTracker = Tracker

Tracker.WIDTH = 250
Tracker.ROW_H = 30
Tracker.NOTE_H = 13 -- the grey line under a bar
Tracker.FOLDED_H = 30
local MEDIA = "Interface\\AddOns\\FellowshipLedger\\media\\"
Tracker.DONE_H = 18 -- a reached goal: one green line, no bar (Austin, 2026-11-11)
Tracker.TOP = 50 -- the title and the session time line above the goals
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
    -- Where your usual pace would have you by now (1.14.0).
    r.pace = r:CreateTexture(nil, "OVERLAY")
    W.Fill(r.pace, "text", 0.9)
    r.pace:SetSize(2, 11)
    r.note = W.Text(r, "small", "muted")
    r.note:SetPoint("BOTTOMLEFT", 0, -Tracker.NOTE_H + 1)
    r.note:SetWordWrap(false)
    r.took = W.Text(r, "small", "good")
    r.took:SetPoint("TOPRIGHT", 0, 0)
    r.took:SetJustifyH("RIGHT")
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
    -- The green frame once every goal is done (over the usual border).
    f.doneFrame = CreateFrame("Frame", nil, f)
    f.doneFrame:SetAllPoints()
    W.Border(f.doneFrame, "good", 1)
    f.doneFrame:Hide()
    -- The done count in a ring.
    f.ring = CreateFrame("Frame", nil, f)
    f.ring:SetSize(22, 22)
    f.ring:SetPoint("TOPLEFT", 8, -5)
    f.ring.tex = f.ring:CreateTexture(nil, "ARTWORK")
    f.ring.tex:SetTexture(MEDIA .. "ring")
    f.ring.tex:SetAllPoints()
    f.ring.text = W.Text(f.ring, "small", "heading")
    f.ring.text:SetPoint("CENTER", 0, 0)
    f.ring.text:SetJustifyH("CENTER")
    f.title = W.Text(f, "body", "heading")
    f.title:SetPoint("LEFT", f.ring, "RIGHT", 6, 0)
    f.title:SetPoint("RIGHT", f, "RIGHT", -50, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    -- The session's time: played since it started, and active (what XP per hour counts).
    f.time = W.Text(f, "small", "muted")
    f.time:SetPoint("TOPLEFT", 10, -32)
    f.time:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.time:SetJustifyH("LEFT")
    f.close = W.Button(f, "x", 18, 18, function() Tracker.Close() end)
    f.close:SetPoint("TOPRIGHT", -5, -7)
    f.fold = W.Button(f, "-", 18, 18, function()
        ns.db.settings.goalsTrackerFolded = not ns.db.settings.goalsTrackerFolded or nil
        Tracker.Refresh()
    end)
    f.fold:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    f.more = W.Button(f, L.GOALS_PICK_MORE, 120, 20, function()
        if ns.SessionGoals.Open(true) then f.more:Hide() end
    end)
    f.more:Hide()
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
-- last: set.last (how long each reached goal took, 1.14.0). A line: { text, done,
-- fraction, expected (the pace tick, or nil), note, noteRole, took (seconds or nil) }.
function Tracker.Lines(list, now, last)
    local open, reached = {}, {}
    for i, g in ipairs(list or {}) do
        local value, ok = Goals.Progress(g, now)
        -- No done mark here: a reached goal is green and at the bottom (Austin, 2026-11-11).
        local note, noteRole = Goals.PaceNote(g, value, ok, now, L)
        local line = { text = Goals.Text(g, value, false, L, fmt()), done = ok and true or false,
            fraction = Goals.Fraction(g, value, ok), expected = not ok and Goals.Expected(g, now) or nil,
            note = note, noteRole = noteRole, took = ok and last and last[i] and last[i].took or nil }
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
    local lines, done = Tracker.Lines(set.list, ns.SessionGoals.Snapshot(), set.last)
    local all = done == #lines
    local folded = ns.db.settings.goalsTrackerFolded and true or false
    -- The ring: the done count, gold, or green when all are done.
    frame.ring.text:SetText(done .. "/" .. #lines)
    local c = W.Color(all and "good" or "accent")
    frame.ring.tex:SetVertexColor(c[1], c[2], c[3], 1)
    W.SetTextRole(frame.ring.text, all and "good" or "heading")
    frame.doneFrame:SetShown(all)
    frame.fold.text:SetText(folded and "+" or "-")
    if folded then
        -- One line: the count and the first goal under way.
        local first = lines[1] and not lines[1].done and lines[1].text
        frame.title:SetText(first and string.format(L.GOALS_TRACKER_FOLDED, done, #lines, first)
            or string.format(L.GOALS_TRACKER_ALL_DONE, done, #lines))
        W.SetTextRole(frame.title, all and "good" or "heading")
        frame.time:Hide()
        frame.more:Hide()
        for i = 1, #rows do rows[i]:Hide() end
        frame:SetHeight(Tracker.FOLDED_H + 2)
        frame:Show()
        return true
    end
    frame.time:Show()
    local y, width = Tracker.TOP, Tracker.WIDTH - 20
    for i, line in ipairs(lines) do
        local r = row(i)
        local h = line.done and Tracker.DONE_H or (Tracker.ROW_H + (line.note and Tracker.NOTE_H or 0))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, -y)
        r:SetHeight((line.done and Tracker.DONE_H or Tracker.ROW_H) - 4)
        r.text:SetText(line.text)
        W.SetTextRole(r.text, line.done and "good" or "text")
        r.track:SetShown(not line.done)
        r.fill:SetShown(not line.done)
        r.fill:SetWidth(math.max(1, width * line.fraction))
        r.pace:SetShown(line.expected ~= nil)
        if line.expected then
            r.pace:ClearAllPoints()
            r.pace:SetPoint("BOTTOMLEFT", math.max(0, math.floor(width * line.expected) - 1), -1)
        end
        r.note:SetShown(line.note ~= nil)
        if line.note then
            r.note:SetText(line.note)
            W.SetTextRole(r.note, line.noteRole or "muted")
        end
        r.took:SetShown(line.took ~= nil)
        if line.took then r.took:SetText(ns.Format.DurationShort(line.took)) end
        r:Show()
        y = y + h
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    frame.title:SetText(all and string.format(L.GOALS_TRACKER_ALL_DONE, done, #lines)
        or string.format(L.GOALS_TRACKER_TITLE, done, #lines))
    W.SetTextRole(frame.title, all and "good" or "heading")
    local s = ns.Store.session or {}
    frame.time:SetText(string.format(L.GOALS_TRACKER_TIME, ns.Format.Duration(s.played or 0), ns.Format.Duration(s.active or 0)))
    -- All done: offer a fresh set.
    frame.more:SetShown(all)
    if all then
        frame.more:ClearAllPoints()
        frame.more:SetPoint("TOPLEFT", 10, -(y + 2))
        y = y + 26
    end
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
