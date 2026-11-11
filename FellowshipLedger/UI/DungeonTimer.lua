-- UI/DungeonTimer.lua
-- The dungeon timer (D-122): while a run is open, a small window shows the dungeon,
-- the time into the run, each boss killed with its time into the run and how far
-- ahead or behind that is, and the run it is compared with: the Leaderboard's #1
-- for this dungeon (default) or your own fastest clear (Austin, 2026-11-11). Click
-- the bottom line, or use Settings, to switch. On by default (Settings > Your
-- notices). Movable (settings.dungeonTimerPos); the x hides it for this run, and
-- /fl timer brings it back. The time is counted like the clear time: from first
-- entering to the final boss, time outside included.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local RT = ns.RunTimer

local Timer = {}
ns.DungeonTimer = Timer

Timer.WIDTH = 270
Timer.ROW_H = 16
Timer.MAX_ROWS = 14
Timer.TOP = 46
Timer.TARGET_EVERY = 30 -- seconds before the compared run is looked up again

local frame
local rows = {}
local closedFor -- entered time of the run whose timer was closed
local cache = { key = nil, at = 0, target = nil }

local function settings() return ns.db.settings end

local function savePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    if point then settings().dungeonTimerPos = { point, relativePoint, math.floor(x or 0), math.floor(y or 0) } end
end

local function place(f)
    f:ClearAllPoints()
    local p = settings().dungeonTimerPos
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -60, -120)
    end
end

local function mode() return settings().dungeonTimerMine and "mine" or "leader" end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(Timer.WIDTH - 20, Timer.ROW_H)
    r:SetPoint("TOPLEFT", 10, -Timer.TOP - (i - 1) * Timer.ROW_H)
    r.name = W.Text(r, "small", "text")
    r.name:SetPoint("LEFT", 0, 0)
    r.name:SetWidth(Timer.WIDTH - 130)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.into = W.Text(r, "small", "text")
    r.into:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.into:SetJustifyH("RIGHT")
    r.delta = W.Text(r, "small", "muted")
    r.delta:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.delta:SetJustifyH("RIGHT")
    rows[i] = r
    return r
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerDungeonTimer", UIParent)
    f:SetSize(Timer.WIDTH, 100)
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
    f.title:SetPoint("RIGHT", f, "RIGHT", -140, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.clock = W.Text(f, "large", "heading")
    f.clock:SetPoint("TOPRIGHT", -30, -6)
    f.clock:SetJustifyH("RIGHT")
    -- The run's +/- against the compared run, beside the time (RunTimer.View pace).
    f.pace = W.Text(f, "body", "muted")
    f.pace:SetPoint("RIGHT", f.clock, "LEFT", -6, 0)
    f.pace:SetJustifyH("RIGHT")
    f.status = W.Text(f, "small", "muted")
    f.status:SetPoint("TOPLEFT", 10, -26)
    f.status:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.status:SetJustifyH("LEFT")
    f.close = W.Button(f, "x", 18, 18, function() Timer.Close() end)
    f.close:SetPoint("TOPRIGHT", -5, -5)
    -- The bottom line names the run compared with; a click switches #1 / your best.
    f.compare = W.Button(f, "", Timer.WIDTH - 20, 18, function()
        settings().dungeonTimerMine = not settings().dungeonTimerMine or nil
        cache.key = nil
        Timer.Refresh()
        if ns.SettingsTab and ns.SettingsTab.Refresh then pcall(ns.SettingsTab.Refresh) end
    end)
    f.compare:SetPoint("BOTTOMLEFT", 10, 6)
    place(f)
    f:Hide()
    return f
end

-- The open run, if the timer should show it.
function Timer.Run()
    if settings().dungeonTimer == false or ns.Data.IsFake() then return nil end
    local run = ns.Store.char and ns.Store.char.currentRun
    if not (run and run.name and run.entered) or closedFor == run.entered then return nil end
    return run
end

-- The run compared with, looked up again every TARGET_EVERY seconds or when the run
-- or the mode changes.
function Timer.Target(run, now)
    local key = tostring(run.entered) .. "|" .. mode() .. "|" .. tostring(run.completed and true or false)
    if cache.key ~= key or now - cache.at >= Timer.TARGET_EVERY then
        local ok, t = pcall(RT.Target, ns.LeaderboardTab.Entries(), run.name, mode(), run)
        cache.key, cache.at, cache.target = key, now, ok and t or nil
    end
    return cache.target
end

local function deltaRole(d) return d < 0 and "good" or d > 0 and "bad" or "muted" end

function Timer.Refresh()
    local run = Timer.Run()
    if not run then
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
    local now = time()
    local target = Timer.Target(run, now)
    local v = RT.View(run, now, target)
    frame.title:SetText(run.name)
    frame.clock:SetText(RT.Clock(v.elapsed))
    W.SetTextRole(frame.clock, v.done and "good" or "heading")
    frame.pace:SetText(v.pace and RT.Delta(v.pace) or "")
    if v.pace then W.SetTextRole(frame.pace, deltaRole(v.pace)) end
    local status = v.total and string.format(L.TIMER_BOSSES_OF, v.killed, v.total) or string.format(L.TIMER_BOSSES, v.killed)
    if v.done then
        status = string.format(L.TIMER_CLEARED, RT.Clock(v.elapsed))
        if v.delta then status = status .. "  " .. string.format(L.TIMER_VS, RT.Delta(v.delta)) end
    elseif run.outside then
        status = status .. "  " .. L.TIMER_OUTSIDE
    end
    frame.status:SetText(status)
    local shown = math.min(#v.bosses, Timer.MAX_ROWS)
    -- The latest kills when there are more than fit.
    local first = #v.bosses - shown
    for i = 1, shown do
        local b = v.bosses[first + i]
        local r = row(i)
        r.name:SetText(L.GOAL_DONE_MARK .. b.name)
        r.into:SetText(RT.Clock(b.into))
        r.delta:SetText(b.delta and RT.Delta(b.delta) or "")
        if b.delta then W.SetTextRole(r.delta, deltaRole(b.delta)) end
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    local label
    if not target then
        label = mode() == "mine" and L.TIMER_NO_MINE or L.TIMER_NO_LEADER
    elseif mode() == "mine" then
        label = string.format(L.TIMER_VS_MINE, RT.Clock(target.clear))
    else
        label = string.format(L.TIMER_VS_LEADER, RT.Clock(target.clear), target.lead or "?")
    end
    frame.compare.text:SetText(label)
    frame:SetHeight(Timer.TOP + shown * Timer.ROW_H + 32)
    frame:Show()
    return true
end

-- The x: hidden for the rest of this run (a new run shows it again).
function Timer.Close()
    local run = ns.Store.char and ns.Store.char.currentRun
    closedFor = run and run.entered or closedFor
    if frame then frame:Hide() end
end

-- /fl timer: show it again for the open run.
function Timer.Reopen()
    closedFor = nil
    if settings().dungeonTimer == false then
        ns.Log.Info(L.TIMER_OFF)
        return false
    end
    if not Timer.Run() then
        ns.Log.Info(L.TIMER_NO_RUN)
        return false
    end
    return Timer.Refresh()
end

function Timer.Frame() return frame end

function Timer.Start()
    ns.Events.Every(1, "dungeonTimer", function()
        local run = ns.Store.char and ns.Store.char.currentRun
        if run or (frame and frame:IsShown()) then Timer.Refresh() end
    end)
    Timer.Refresh()
end
