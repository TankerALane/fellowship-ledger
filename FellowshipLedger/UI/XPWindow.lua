-- UI/XPWindow.lua
-- The XP window (1.14.6, D-146): a small pop-up opened only with /fl xp. Pick the last
-- 1, 5 or 10 minutes; it shows the XP gained, the pace per hour, how much of the level
-- that is and the time to the next level at that pace, over bars of XP across the time
-- (hover a bar for its XP). Drag it anywhere (settings.xpWindowPos); the choice is kept
-- (settings.xpWindowSpan). It redraws every second while shown. The numbers come from
-- Core/XPRecent.lua.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local XR = ns.XPRecent

local XPWindow = {}
ns.XPWindow = XPWindow

XPWindow.WIDTH = 300
XPWindow.GRAPH_H = 70
XPWindow.REFRESH = 1

local frame

local function settings() return ns.db and ns.db.settings or {} end

local function savePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    if point then settings().xpWindowPos = { point, relativePoint, math.floor(x or 0), math.floor(y or 0) } end
end

local function place(f)
    f:ClearAllPoints()
    local p = settings().xpWindowPos
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
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

function XPWindow.Refresh()
    if not (frame and frame:IsShown()) then return end
    local char = ns.Store.char
    local now = time()
    local list = XR.Prune(char and char.xpRecent, now)
    local xp, xpMax, level = xpNow()
    local spanId = XR.Span(settings().xpWindowSpan).id
    frame.spans:Select(spanId)
    local s = XR.Summary(list, now, spanId, xp, xpMax)
    local minutes = math.floor(s.span / 60)
    frame.total:SetText(string.format(L.XPWIN_TOTAL, ns.Format.Number(s.total)))
    frame.pace:SetText(s.total > 0 and string.format(L.XPWIN_PACE, ns.Format.Number(s.perHour)) or "")
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
    frame.note:SetText(table.concat(lines, "\n"))
    -- The bars.
    local gw = frame.graph:GetWidth()
    if type(gw) ~= "number" or gw < 50 then gw = XPWindow.WIDTH - 24 end
    local n = #s.bars
    local slot = gw / n
    for i, d in ipairs(s.bars) do
        local b = bar(i)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", frame.graph, "BOTTOMLEFT", math.floor((i - 1) * slot + 1), 0)
        b:SetSize(math.max(1, math.floor(slot) - 2), XPWindow.GRAPH_H)
        local h = s.top > 0 and math.floor(XPWindow.GRAPH_H * d.xp / s.top + 0.5) or 0
        b.fill:SetHeight(math.max(1, h))
        b.fill:SetShown(d.xp > 0)
        b.data = { from = d.from, to = d.to, xp = d.xp, now = now }
        b:Show()
    end
    for i = n + 1, #frame.bars do frame.bars[i]:Hide() end
    frame.top:SetText(s.top > 0 and ns.Format.Number(s.top) or "")
    frame.left:SetText(string.format(L.XPWIN_AGO, minutes))
    frame:SetHeight(192 + 14 * math.max(1, #lines))
end

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerXPWindow", UIParent)
    frame = f
    f.bars = {}
    f:SetSize(XPWindow.WIDTH, 190)
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
    W.Background(f, "bg", 1)
    W.Border(f, "border", 1)
    f.title = W.Text(f, "body", "heading")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L.XPWIN_TITLE)
    f.close = W.Button(f, "x", 18, 18, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    local items = {}
    for _, s in ipairs(XR.SPANS) do items[#items + 1] = { id = s.id, label = L["XPWIN_SPAN_" .. s.id:upper()], width = 64 } end
    f.spans = W.Segmented(f, items, function(id)
        settings().xpWindowSpan = id
        XPWindow.Refresh()
    end, 20)
    f.spans:SetPoint("TOPLEFT", 12, -32)
    f.total = W.Text(f, "large", "heading")
    f.total:SetPoint("TOPLEFT", 12, -62)
    f.pace = W.Text(f, "body", "accent")
    f.pace:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -12, -80)
    f.pace:SetJustifyH("RIGHT")
    f.graph = CreateFrame("Frame", nil, f)
    f.graph:SetPoint("TOPLEFT", 12, -90)
    f.graph:SetPoint("TOPRIGHT", -12, -90)
    f.graph:SetHeight(XPWindow.GRAPH_H)
    W.Background(f.graph, "panel", 0.5)
    f.top = W.Text(f, "small", "muted")
    f.top:SetPoint("TOPLEFT", f.graph, "TOPLEFT", 3, -2)
    f.left = W.Text(f, "small", "muted")
    f.left:SetPoint("TOPLEFT", f.graph, "BOTTOMLEFT", 0, -3)
    f.right = W.Text(f, "small", "muted")
    f.right:SetPoint("TOPRIGHT", f.graph, "BOTTOMRIGHT", 0, -3)
    f.right:SetText(L.XPWIN_NOW)
    f.note = W.Text(f, "small", "text")
    f.note:SetPoint("TOPLEFT", f.graph, "BOTTOMLEFT", 0, -20)
    f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.note:SetJustifyH("LEFT")
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + (elapsed or 0)
        if self.elapsed < XPWindow.REFRESH then return end
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
