-- UI/XPWindow.lua
-- The XP window (1.14.6, D-146): a small pop-up opened only with /fl xp. Pick the last
-- 1, 5 or 10 minutes; it shows the XP gained, the pace per hour, how much of the level
-- that is and the time to the next level at that pace, over bars of XP across the time
-- (hover a bar for its XP). Drag it anywhere (settings.xpWindowPos); the choice is kept
-- (settings.xpWindowSpan). It redraws every second while shown. The numbers come from
-- Core/XPRecent.lua.
-- Resizable from the corner (settings.xpWindowSize) down to about a quarter of its
-- full size: narrow, the title goes and the buttons say 1m / 5m / 10m with a short
-- pace; short, the level lines and then the time labels go; the bars take the rest.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local XR = ns.XPRecent

local XPWindow = {}
ns.XPWindow = XPWindow

XPWindow.WIDTH, XPWindow.HEIGHT = 300, 220   -- the size at first
XPWindow.MIN_W, XPWindow.MIN_H = 150, 90     -- about a quarter of it
XPWindow.MAX_W, XPWindow.MAX_H = 700, 500
XPWindow.COMPACT_W = 240                      -- narrower than this: the compact top line
XPWindow.REFRESH = 1

local frame

local function settings() return ns.db and ns.db.settings or {} end

local function savePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    if point then settings().xpWindowPos = { point, relativePoint, math.floor(x or 0), math.floor(y or 0) } end
end

local function saveSize(f)
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) == "number" and type(h) == "number" then settings().xpWindowSize = { math.floor(w + 0.5), math.floor(h + 0.5) } end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function place(f)
    f:ClearAllPoints()
    local p = settings().xpWindowPos
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    local s = settings().xpWindowSize
    local w = type(s) == "table" and tonumber(s[1]) or XPWindow.WIDTH
    local h = type(s) == "table" and tonumber(s[2]) or XPWindow.HEIGHT
    f:SetSize(clamp(w, XPWindow.MIN_W, XPWindow.MAX_W), clamp(h, XPWindow.MIN_H, XPWindow.MAX_H))
end

-- Where things go at a size (pure; for tests). noteLines: the level lines to show.
-- Returns { compact, totalY, graphY, graphH, axis (show the time labels), note
-- (show the level lines), noteY }: y as offsets down from the top.
function XPWindow.Layout(w, h, noteLines)
    local compact = w < XPWindow.COMPACT_W
    local out = { compact = compact }
    local top = compact and 30 or 56          -- under the buttons
    out.totalY = top
    local totalH = compact and 18 or 28
    out.graphY = top + totalH
    local bottom = 8
    local axisH, noteH = 16, 14 * math.max(1, noteLines or 1) + 4
    local room = h - out.graphY - bottom
    out.axis = room - axisH >= 40
    out.note = room - axisH - noteH >= 40
    out.graphH = room - (out.axis and axisH or 0) - (out.note and noteH or 0)
    out.graphH = math.max(12, out.graphH)
    out.noteY = out.graphY + out.graphH + (out.axis and axisH or 0) + 2
    return out
end

-- "2:30" for seconds ago.
local function ago(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function bar(i)
    local b = frame.bars[i]
    if b then return b end
    b = CreateFrame("Frame", nil, frame.graph)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("BOTTOMLEFT", 0, 0)
    b.fill:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Fill(b.fill, "accent")
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        W.Tooltip(self, string.format(L.XPWIN_BAR_TITLE, ago(d.now - d.from), ago(d.now - d.to)),
            { string.format(L.XPWIN_BAR_XP, ns.Format.Number(d.xp)) })
    end)
    b:SetScript("OnLeave", function() W.HideTooltip() end)
    frame.bars[i] = b
    return b
end

-- The XP bar now: xp, xpMax (nil at the level cap or when unreadable).
local function xpNow()
    local T = ns.Trackers
    local function read(fn) return type(fn) == "function" and T.Plain(fn("player")) or nil end
    local xp, xpMax, level = read(UnitXP), read(UnitXPMax), read(UnitLevel)
    local maxLevel = ns.Merge and ns.Merge.maxLevel
    if maxLevel and type(level) == "number" and level >= maxLevel then return nil, nil, level end
    return xp, xpMax, level
end

local function size(f)
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) ~= "number" or w < 10 then w = XPWindow.WIDTH end
    if type(h) ~= "number" or h < 10 then h = XPWindow.HEIGHT end
    return w, h
end

function XPWindow.Refresh()
    if not (frame and frame:IsShown()) then return end
    local char = ns.Store.char
    local now = time()
    local list = XR.Prune(char and char.xpRecent, now)
    local xp, xpMax, level = xpNow()
    local spanId = XR.Span(settings().xpWindowSpan).id
    local s = XR.Summary(list, now, spanId, xp, xpMax)
    local minutes = math.floor(s.span / 60)
    local lines = {}
    if s.total == 0 then
        lines[1] = string.format(minutes == 1 and L.XPWIN_NONE_ONE or L.XPWIN_NONE, minutes)
    else
        if s.levelShare and level then
            lines[#lines + 1] = string.format(L.XPWIN_SHARE, math.floor(s.levelShare * 1000 + 0.5) / 10, level)
        end
        if s.toLevel and level then
            lines[#lines + 1] = string.format(L.XPWIN_TO_LEVEL, level + 1, ns.Format.Duration(s.toLevel))
        end
    end
    -- Lay it out for the window's size.
    local w, h = size(frame)
    local lay = XPWindow.Layout(w, h, #lines)
    frame.layout = lay -- for tests
    frame.title:SetShown(not lay.compact)
    frame.spans:SetShown(not lay.compact)
    frame.spansShort:SetShown(lay.compact)
    frame.spans:Select(spanId)
    frame.spansShort:Select(spanId)
    W.SetTextStyle(frame.total, lay.compact and "body" or "large", "heading")
    W.SetTextStyle(frame.pace, lay.compact and "small" or "body", "accent")
    frame.total:ClearAllPoints()
    frame.total:SetPoint("TOPLEFT", 10, -lay.totalY)
    frame.pace:ClearAllPoints()
    frame.pace:SetPoint("TOPRIGHT", -10, -(lay.totalY + (lay.compact and 2 or 6)))
    frame.graph:ClearAllPoints()
    frame.graph:SetPoint("TOPLEFT", 10, -lay.graphY)
    frame.graph:SetPoint("TOPRIGHT", -10, -lay.graphY)
    frame.graph:SetHeight(lay.graphH)
    frame.left:SetShown(lay.axis)
    frame.right:SetShown(lay.axis)
    frame.note:SetShown(lay.note)
    frame.note:ClearAllPoints()
    frame.note:SetPoint("TOPLEFT", 10, -lay.noteY)
    frame.note:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.top:SetShown(lay.graphH >= 24)
    -- The words.
    frame.total:SetText(string.format(L.XPWIN_TOTAL, ns.Format.Number(s.total)))
    local pace = lay.compact and L.XPWIN_PACE_SHORT or L.XPWIN_PACE
    frame.pace:SetText(s.total > 0 and string.format(pace, ns.Format.Number(s.perHour)) or "")
    frame.note:SetText(table.concat(lines, "\n"))
    frame.top:SetText(s.top > 0 and ns.Format.Number(s.top) or "")
    frame.left:SetText(string.format(L.XPWIN_AGO, minutes))
    -- The bars.
    local gw = w - 20
    local n = #s.bars
    local slot = gw / n
    local gap = slot >= 6 and 2 or 1
    for i, d in ipairs(s.bars) do
        local b = bar(i)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", frame.graph, "BOTTOMLEFT", math.floor((i - 1) * slot + 1), 0)
        b:SetSize(math.max(1, math.floor(slot) - gap), lay.graphH)
        local bh = s.top > 0 and math.floor(lay.graphH * d.xp / s.top + 0.5) or 0
        b.fill:SetHeight(math.max(1, bh))
        b.fill:SetShown(d.xp > 0)
        b.data = { from = d.from, to = d.to, xp = d.xp, now = now }
        b:Show()
    end
    for i = n + 1, #frame.bars do frame.bars[i]:Hide() end
end

local function spanButtons(f, short)
    local items = {}
    for _, s in ipairs(XR.SPANS) do
        local key = (short and "XPWIN_SPAN_SHORT_" or "XPWIN_SPAN_") .. s.id:upper()
        items[#items + 1] = { id = s.id, label = L[key], width = short and 34 or 64 }
    end
    return W.Segmented(f, items, function(id)
        settings().xpWindowSpan = id
        XPWindow.Refresh()
    end, short and 18 or 20)
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerXPWindow", UIParent)
    frame = f
    f.bars = {}
    f:SetSize(XPWindow.WIDTH, XPWindow.HEIGHT)
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
    -- Resizing from the corner, like the main window (x:ui.frame).
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(XPWindow.MIN_W, XPWindow.MIN_H, XPWindow.MAX_W, XPWindow.MAX_H)
    elseif f.SetMinResize then
        f:SetMinResize(XPWindow.MIN_W, XPWindow.MIN_H)
    end
    W.Background(f, "bg", 1)
    W.Border(f, "border", 1)
    f.title = W.Text(f, "body", "heading")
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.title:SetText(L.XPWIN_TITLE)
    f.close = W.Button(f, "x", 18, 18, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -5, -5)
    f.spans = spanButtons(f, false)
    f.spans:SetPoint("TOPLEFT", 10, -30)
    f.spansShort = spanButtons(f, true)
    f.spansShort:SetPoint("TOPLEFT", 6, -6)
    f.total = W.Text(f, "large", "heading")
    f.pace = W.Text(f, "body", "accent")
    f.pace:SetJustifyH("RIGHT")
    f.graph = CreateFrame("Frame", nil, f)
    W.Background(f.graph, "panel", 0.5)
    f.top = W.Text(f, "small", "muted")
    f.top:SetPoint("TOPLEFT", f.graph, "TOPLEFT", 3, -2)
    f.left = W.Text(f, "small", "muted")
    f.left:SetPoint("TOPLEFT", f.graph, "BOTTOMLEFT", 0, -3)
    f.right = W.Text(f, "small", "muted")
    f.right:SetPoint("TOPRIGHT", f.graph, "BOTTOMRIGHT", 0, -3)
    f.right:SetText(L.XPWIN_NOW)
    f.note = W.Text(f, "small", "text")
    f.note:SetJustifyH("LEFT")
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(10, 10)
    f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
    W.Background(f.grip, "accent", 0.6)
    f.grip:SetScript("OnMouseDown", function()
        f.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.sizing = false
        savePosition(f)
        saveSize(f)
        XPWindow.Refresh()
    end)
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + (elapsed or 0)
        -- While the corner is dragged, redraw ten times a second so the bars follow.
        if self.elapsed < (self.sizing and 0.1 or XPWindow.REFRESH) then return end
        self.elapsed = 0
        local ok, err = pcall(XPWindow.Refresh)
        if not ok then ns.Log.Debug("xp window failed: %s", tostring(err)) end
    end)
    f:Hide()
    return f
end

-- /fl xp: open (or close when open).
function XPWindow.Toggle()
    frame = frame or build()
    if frame:IsShown() then frame:Hide() return end
    place(frame)
    frame:Show()
    XPWindow.Refresh()
end

function XPWindow.Frame() return frame end -- for tests
