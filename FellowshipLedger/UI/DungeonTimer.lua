-- UI/DungeonTimer.lua
-- The dungeon timer (D-122): while a run is open, a small window shows the dungeon,
-- the time into the run, each boss killed with its time into the run and how far
-- ahead or behind that is, and the run it is compared with: the Leaderboard's #1
-- for this dungeon (default) or your own fastest clear (Austin, 2026-11-11). Click
-- the bottom line, or use Settings, to switch. On by default (Settings > Your
-- notices). Movable (settings.dungeonTimerPos); the x hides it for this run, even
-- across /reload (char.timerClosedFor), and /fl timer brings it back. The time is counted like the clear time: from the first
-- fight inside (D-126; it waits at 0:00 until then) to the final boss, time outside
-- included.
-- 1.14.0 (D-138): a big clock with the +/- in a filled box, a bar with a tick for each
-- kill (yours green, the compared run's grey), a dot per kill and the next boss with
-- the compared run's time for it, a two-way switch (#1 / my best) instead of a line
-- to click, and once cleared a gold frame with the run's place on the Leaderboard,
-- how it compares with your best, and buttons to open the run or the Leaderboard.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local RT = ns.RunTimer

local Timer = {}
ns.DungeonTimer = Timer

Timer.WIDTH = 270
Timer.ROW_H = 16
Timer.MAX_ROWS = 14
Timer.TOP = 96
Timer.TARGET_EVERY = 30 -- seconds before the compared run is looked up again

local frame
local rows = {}
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

local MEDIA = "Interface\\AddOns\\FellowshipLedger\\media\\"
Timer.BAR_TOP = 74 -- the bar under the clock (1.14.0)
Timer.RESULT_H = 66 -- the lines and buttons under a cleared run

local function tint(tex, role, alpha)
    local c = W.Color(role)
    tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(Timer.WIDTH - 20, Timer.ROW_H)
    r:SetPoint("TOPLEFT", 10, -Timer.TOP - (i - 1) * Timer.ROW_H)
    -- A filled dot for a kill, a ring for the next boss (1.14.0).
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", 0, 0)
    r.name = W.Text(r, "small", "text")
    r.name:SetPoint("LEFT", 14, 0)
    r.name:SetWidth(Timer.WIDTH - 144)
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

-- A tick on the bar: i-th of a kind ("mine" or "theirs").
local function tick(kind, i)
    frame.ticks[kind] = frame.ticks[kind] or {}
    local t = frame.ticks[kind][i]
    if not t then
        t = frame.bar:CreateTexture(nil, "OVERLAY")
        frame.ticks[kind][i] = t
    end
    return t
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
    -- A gold frame once the run is cleared.
    f.doneFrame = CreateFrame("Frame", nil, f)
    f.doneFrame:SetAllPoints()
    W.Border(f.doneFrame, "accent", 1)
    f.doneFrame:Hide()
    f.title = W.Text(f, "body", "heading")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.status = W.Text(f, "small", "muted")
    f.status:SetPoint("TOPLEFT", 10, -24)
    f.status:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    -- The big clock, and the +/- in a filled box beside it (RunTimer.View pace).
    f.clock = W.Text(f, "clock", "heading")
    f.clock:SetPoint("TOPLEFT", 10, -40)
    f.clock:SetJustifyH("LEFT")
    f.paceBox = CreateFrame("Frame", nil, f)
    f.paceBox:SetSize(52, 18)
    f.paceBox:SetPoint("LEFT", f.clock, "RIGHT", 10, 0)
    f.paceBox.bg = f.paceBox:CreateTexture(nil, "BACKGROUND")
    f.paceBox.bg:SetAllPoints()
    f.pace = W.Text(f.paceBox, "body", "bg")
    f.pace:SetPoint("CENTER", 0, 0)
    f.pace:SetJustifyH("CENTER")
    -- Over the clock: hovering a run marked * (not timed from the start, D-127) says
    -- why. Dragging here still moves the window.
    f.clockHover = CreateFrame("Frame", nil, f)
    f.clockHover:SetAllPoints(f.clock)
    f.clockHover:EnableMouse(true)
    f.clockHover:RegisterForDrag("LeftButton")
    f.clockHover:SetScript("OnDragStart", function() f:StartMoving() end)
    f.clockHover:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition(f)
    end)
    f.clockHover:SetScript("OnEnter", function(self) Timer.ShowWhy(self) end)
    f.clockHover:SetScript("OnLeave", function() W.HideTooltip() end)
    -- The bar: the time so far, a green tick for each of your kills, a grey one for each
    -- kill of the compared run, and its clear at the far end.
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetPoint("TOPLEFT", 10, -Timer.BAR_TOP)
    f.bar:SetSize(Timer.WIDTH - 20, 14)
    f.bar.track = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bar.track:SetPoint("LEFT", 0, 0)
    f.bar.track:SetSize(Timer.WIDTH - 20, 4)
    W.Fill(f.bar.track, "rule", 0.35)
    f.bar.fill = f.bar:CreateTexture(nil, "ARTWORK")
    f.bar.fill:SetPoint("LEFT", 0, 0)
    f.bar.fill:SetHeight(4)
    W.Fill(f.bar.fill, "accent", 0.9)
    f.ticks = {}
    f.close = W.Button(f, "x", 18, 18, function() Timer.Close() end)
    f.close:SetPoint("TOPRIGHT", -5, -5)
    -- Under a cleared run: its place on the Leaderboard, against your best, two buttons.
    f.result = CreateFrame("Frame", nil, f)
    f.result:SetSize(Timer.WIDTH - 20, Timer.RESULT_H)
    f.result.crown = f.result:CreateTexture(nil, "ARTWORK")
    f.result.crown:SetTexture(MEDIA .. "crown")
    f.result.crown:SetSize(12, 12)
    f.result.crown:SetPoint("TOPLEFT", 0, -4)
    f.result.rank = W.Text(f.result, "small", "heading")
    f.result.rank:SetPoint("TOPLEFT", 16, -4)
    f.result.best = W.Text(f.result, "small", "muted")
    f.result.best:SetPoint("TOPLEFT", 0, -20)
    f.result.best:SetWidth(Timer.WIDTH - 20)
    f.result.best:SetWordWrap(false)
    f.result.open = W.Button(f.result, L.TIMER_OPEN_RUN, 100, 20, function()
        if ns.DungeonsTab and ns.DungeonsTab.OpenRun then ns.DungeonsTab.OpenRun(f.result.runKey) else ns.MainWindow.Open("dungeons") end
    end)
    f.result.open:SetPoint("TOPLEFT", 0, -40)
    f.result.board = W.Button(f.result, L.TAB_LEADERBOARD, 100, 20, function() ns.MainWindow.Open("leaderboard") end)
    f.result.board:SetPoint("LEFT", f.result.open, "RIGHT", 6, 0)
    f.result:Hide()
    -- The run compared with: a two-way switch, #1 or your best (1.14.0).
    local half = math.floor((Timer.WIDTH - 20) / 2)
    f.switch = W.Segmented(f, { { id = "leader", label = "", width = half }, { id = "mine", label = "", width = Timer.WIDTH - 20 - half } },
        function(id)
            settings().dungeonTimerMine = id == "mine" or nil
            cache.key = nil
            Timer.Refresh()
            if ns.SettingsTab and ns.SettingsTab.Refresh then pcall(ns.SettingsTab.Refresh) end
        end, 18)
    f.switch:SetPoint("BOTTOMLEFT", 10, 8)
    for id, b in pairs(f.switch.buttons) do
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 4, 0)
        b.text:SetPoint("RIGHT", -4, 0)
        b.text:SetWordWrap(false)
        b:HookScript("OnEnter", function(self)
            W.Tooltip(self, L.TIMER_SWITCH_TITLE, { id == "mine" and L.TIMER_SWITCH_TO_MINE or L.TIMER_SWITCH_TO_LEADER })
        end)
        b:HookScript("OnLeave", function() W.HideTooltip() end)
    end
    place(f)
    f:Hide()
    return f
end

-- The open run, if the timer should show it.
function Timer.Run()
    if settings().dungeonTimer == false or ns.Data.IsFake() then return nil end
    local run = ns.Store.char and ns.Store.char.currentRun
    if not (run and run.name and run.entered) or ns.Store.char.timerClosedFor == run.entered then return nil end
    return run
end

-- The run compared with, looked up again every TARGET_EVERY seconds or when the run
-- or the mode changes. which: "leader" | "mine" (default: the chosen mode). Both are
-- kept, for the switch's two labels.
function Timer.Target(run, now, which)
    which = which or mode()
    local key = tostring(run.entered) .. "|" .. tostring(run.completed and true or false)
    if cache.key ~= key or now - cache.at >= Timer.TARGET_EVERY then
        cache.key, cache.at, cache.targets, cache.rank = key, now, {}, nil
        local okE, entries = pcall(ns.LeaderboardTab.Entries)
        for m in pairs(RT.MODES) do
            local ok, t = pcall(RT.Target, okE and entries or {}, run.name, m, run)
            cache.targets[m] = ok and t or false
        end
        -- A cleared run's place on the Leaderboard (at level, like the tab's default).
        if run.completed and run.completedAt and okE then
            local okB, board = pcall(ns.Leaderboard.Build, entries, true)
            if okB then cache.rank = ns.Leaderboard.RankOf(board, run.name, run.completedAt) end
        end
    end
    return cache.targets[which] or nil
end

local function deltaRole(d) return d < 0 and "good" or d > 0 and "bad" or "muted" end

-- The boss the compared run killed next, that this run has not: { name, at } or nil.
function Timer.NextBoss(view, target)
    if not (target and target.splits) or view.done then return nil end
    local killed = {}
    for _, b in ipairs(view.bosses) do killed[b.name] = true end
    local best
    for name, at in pairs(target.splits) do
        if not killed[name] and (not best or at < best.at) then best = { name = name, at = at } end
    end
    return best
end

-- The switch's two labels: "#1 Zip 20:00" / "My best 25:00" (or "none yet").
function Timer.SwitchLabels(leader, mine)
    local a = leader and string.format(L.TIMER_SEG_LEADER, leader.lead or "?", RT.Clock(leader.clear)) or L.TIMER_SEG_LEADER_NONE
    local b = mine and string.format(L.TIMER_SEG_MINE, RT.Clock(mine.clear)) or L.TIMER_SEG_MINE_NONE
    return a, b
end

local function drawBar(v, target)
    local width = Timer.WIDTH - 20
    local scale = math.max(v.elapsed or 0, target and target.clear or 0)
    for _, list in pairs(frame.ticks) do for _, t in ipairs(list) do t:Hide() end end
    frame.bar:SetShown(not v.waiting and scale > 0)
    if v.waiting or scale <= 0 then return end
    frame.bar.fill:SetWidth(math.max(1, width * math.min(1, v.elapsed / scale)))
    W.Fill(frame.bar.fill, v.done and "good" or "accent", 0.9)
    local function place(t, at, h, role, alpha, dy)
        t:ClearAllPoints()
        t:SetSize(2, h)
        t:SetPoint("LEFT", frame.bar, "LEFT", math.max(0, math.min(width - 2, math.floor(width * at / scale) - 1)), dy or 0)
        W.Fill(t, role, alpha)
        t:Show()
    end
    local n = 0
    if target then
        for _, at in ipairs(target.refs or {}) do
            n = n + 1
            place(tick("theirs", n), at, 6, "muted", 0.8, -5)
        end
        n = n + 1
        place(tick("theirs", n), target.clear, 14, "muted", 0.8)
    end
    for i, b in ipairs(v.bosses) do
        if not b.extra then place(tick("mine", i), b.into, 14, "good", 1) end
    end
end

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
    frame.clock:SetText(RT.Clock(v.elapsed) .. (v.partial and "*" or ""))
    W.SetTextRole(frame.clock, v.done and "good" or (v.waiting and "muted" or "text"))
    frame.pace:SetText(v.pace and RT.Delta(v.pace) or "")
    frame.paceBox:SetShown(v.pace ~= nil)
    if v.pace then W.Fill(frame.paceBox.bg, deltaRole(v.pace), 0.9) end
    local status = v.total and string.format(L.TIMER_BOSSES_OF, v.killed, v.total) or string.format(L.TIMER_BOSSES, v.killed)
    if v.waiting then
        status = L.TIMER_WAITING
    elseif v.done then
        status = string.format(L.TIMER_CLEARED, RT.Clock(v.elapsed))
        if v.delta then status = status .. "  " .. string.format(L.TIMER_VS, RT.Delta(v.delta)) end
    elseif run.outside then
        status = status .. "  " .. L.TIMER_OUTSIDE
    end
    frame.status:SetText(status)
    frame.doneFrame:SetShown(v.done)
    drawBar(v, target)
    -- The kills (the latest when there are more than fit), then the next boss.
    local nextBoss = Timer.NextBoss(v, target)
    local room = Timer.MAX_ROWS - (nextBoss and 1 or 0)
    local shown = math.min(#v.bosses, room)
    local first = #v.bosses - shown
    for i = 1, shown do
        local b = v.bosses[first + i]
        local r = row(i)
        r.dot:SetTexture(MEDIA .. "switch-knob")
        tint(r.dot, b.extra and "muted" or "good")
        r.name:SetText(b.extra and string.format(L.TIMER_EXTRA, b.name) or b.name) -- all dead: no done mark
        W.SetTextRole(r.name, b.extra and "muted" or "text")
        W.SetTextRole(r.into, b.extra and "muted" or "text")
        r.into:SetText(RT.Clock(b.into))
        r.delta:SetText(b.delta and RT.Delta(b.delta) or "")
        if b.delta then W.SetTextRole(r.delta, deltaRole(b.delta)) end
        r:Show()
    end
    if nextBoss then
        shown = shown + 1
        local r = row(shown)
        r.dot:SetTexture(MEDIA .. "ring")
        tint(r.dot, "muted")
        r.name:SetText(nextBoss.name)
        W.SetTextRole(r.name, "muted")
        r.into:SetText(RT.Clock(nextBoss.at))
        W.SetTextRole(r.into, "muted")
        r.delta:SetText(L.TIMER_NEXT)
        W.SetTextRole(r.delta, "muted")
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    -- A cleared run: its place and how it compares with your best.
    local y = Timer.TOP + shown * Timer.ROW_H
    frame.result:SetShown(v.done)
    if v.done then
        frame.result:ClearAllPoints()
        frame.result:SetPoint("TOPLEFT", 10, -(y + 2))
        local rank = cache.rank
        frame.result.crown:SetShown(rank == 1)
        tint(frame.result.crown, "accent")
        frame.result.rank:ClearAllPoints()
        frame.result.rank:SetPoint("TOPLEFT", rank == 1 and 16 or 0, -4)
        frame.result.rank:SetText(rank == 1 and L.TIMER_NEW_TOP or (rank and string.format(L.TIMER_RANK, rank) or L.TIMER_NO_RANK))
        local mine = Timer.Target(run, now, "mine")
        local deaths = tonumber(run.deaths) or 0
        local text = mine and string.format(L.TIMER_BEST_WAS, RT.Clock(mine.clear), RT.Delta(v.elapsed - mine.clear)) or L.TIMER_FIRST_CLEAR
        if deaths > 0 then text = text .. "  -  " .. string.format(deaths == 1 and L.TIMER_DEATH or L.TIMER_DEATHS, deaths) end
        frame.result.best:SetText(text)
        frame.result.runKey = run.entered
        y = y + Timer.RESULT_H
    end
    local leader, mine = Timer.Target(run, now, "leader"), Timer.Target(run, now, "mine")
    local a, b = Timer.SwitchLabels(leader, mine)
    frame.switch.buttons.leader.text:SetText(a)
    frame.switch.buttons.mine.text:SetText(b)
    frame.switch:Select(mode())
    frame:SetHeight(y + 34)
    frame:Show()
    return true
end

-- Hover on the clock: why the run is marked * (nothing for a run timed from the start).
function Timer.ShowWhy(owner)
    local run = Timer.Run()
    if not (run and run.partial) then return false end
    W.Tooltip(owner, run.name, { ns.DungeonsModel.PartialText(run.partial, L) })
    return true
end

-- The x: hidden for the rest of this run, kept in the saved data so /reload does not
-- bring it back (a new run shows it again).
function Timer.Close()
    local char = ns.Store.char
    local run = char and char.currentRun
    if run and run.entered then char.timerClosedFor = run.entered end
    if frame then frame:Hide() end
end

-- /fl timer: show it again for the open run.
function Timer.Reopen()
    if ns.Store.char then ns.Store.char.timerClosedFor = nil end
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
