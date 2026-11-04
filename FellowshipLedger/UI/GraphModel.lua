-- UI/GraphModel.lua
-- PURE: no WoW globals. Data series for the Graphs tab and axis scaling.
-- A series is a list of points { label, value, note } in display order.

local _, ns = ...

local GraphModel = {}
ns.GraphModel = GraphModel

GraphModel.CHARTS = { "levelsPerSession", "timePerLevel", "questsPerDay", "goldPerSession", "xpPerHour" }
GraphModel.KIND = {
    levelsPerSession = "number", timePerLevel = "duration", questsPerDay = "number",
    goldPerSession = "money", xpPerHour = "number",
}
GraphModel.MAX_POINTS = 40

-- "Nice" axis: a round maximum (1, 2, 2.5, 5 x 10^k) and tick step covering [lo, hi].
-- integer = true keeps the step a whole number (for counts), so labels never repeat.
function GraphModel.NiceScale(lo, hi, ticks, integer)
    ticks = ticks or 4
    lo, hi = math.min(lo or 0, 0), math.max(hi or 0, 0)
    if hi == lo then hi = lo + 1 end
    local raw = (hi - lo) / ticks
    local mag = 10 ^ math.floor(math.log10(raw))
    local step
    for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
        step = m * mag
        if step >= raw then break end
    end
    if integer then step = math.max(1, math.ceil(step)) end
    local niceLo = math.floor(lo / step) * step
    local niceHi = math.ceil(hi / step) * step
    if niceHi == niceLo then niceHi = niceLo + step end
    return niceLo, niceHi, step
end

local function tail(points)
    local n = #points
    if n <= GraphModel.MAX_POINTS then return points end
    local out = {}
    for i = n - GraphModel.MAX_POINTS + 1, n do out[#out + 1] = points[i] end
    return out
end

local function shortDate(epoch, dateFn)
    return dateFn("%m-%d", epoch)
end

function GraphModel.LevelsPerSession(char, dateFn)
    local pts = {}
    for _, s in ipairs(char.sessions or {}) do
        pts[#pts + 1] = { label = shortDate(s.start, dateFn), value = (s.counts and s.counts.levels) or 0,
            note = dateFn("%Y-%m-%d %H:%M", s.start) }
    end
    return tail(pts)
end

function GraphModel.TimePerLevel(char)
    local levels = {}
    for to in pairs(char.levels or {}) do levels[#levels + 1] = to end
    table.sort(levels)
    local pts = {}
    for _, to in ipairs(levels) do
        local r = char.levels[to]
        pts[#pts + 1] = { label = tostring(to), value = r.active or 0, partial = r.partial,
            note = ns.Format.LevelLine(r) .. (r.partial and " (partial)" or "") }
    end
    return tail(pts)
end

-- Quests per day over the range ending todayKey (days with no quests are zero).
function GraphModel.QuestsPerDay(char, todayKey, days, timeFn, dateFn)
    local pts = {}
    for i = (days or 30) - 1, 0, -1 do
        local key = ns.Days.Shift(todayKey, -i, timeFn, dateFn)
        local day = char.days and char.days[key]
        pts[#pts + 1] = { label = key:sub(6), value = day and day.quests or 0, note = key }
    end
    return pts
end

function GraphModel.GoldPerSession(char, dateFn)
    local pts = {}
    for _, s in ipairs(char.sessions or {}) do
        pts[#pts + 1] = { label = shortDate(s.start, dateFn), value = (s.counts and s.counts.moneyNet) or 0,
            note = dateFn("%Y-%m-%d %H:%M", s.start) }
    end
    return tail(pts)
end

function GraphModel.XpPerHour(char, dateFn)
    local pts = {}
    for _, s in ipairs(char.sessions or {}) do
        local xp = s.counts and s.counts.xp or 0
        local rate = ns.Format.PerHour(xp, s.active) or 0
        pts[#pts + 1] = { label = shortDate(s.start, dateFn), value = rate, note = dateFn("%Y-%m-%d %H:%M", s.start) }
    end
    return tail(pts)
end

function GraphModel.Build(chart, char, todayKey, timeFn, dateFn, days)
    if chart == "levelsPerSession" then return GraphModel.LevelsPerSession(char, dateFn) end
    if chart == "timePerLevel" then return GraphModel.TimePerLevel(char) end
    if chart == "questsPerDay" then return GraphModel.QuestsPerDay(char, todayKey, days, timeFn, dateFn) end
    if chart == "goldPerSession" then return GraphModel.GoldPerSession(char, dateFn) end
    if chart == "xpPerHour" then return GraphModel.XpPerHour(char, dateFn) end
    return {}
end

-- Count charts (whole numbers) get whole-number axis steps.
function GraphModel.IsInteger(chart)
    return chart == "levelsPerSession" or chart == "questsPerDay"
end

-- How many x labels fit: at least LABEL_PX pixels per label.
GraphModel.LABEL_PX = 48
function GraphModel.LabelEvery(n, width)
    local fit = math.max(1, math.floor((width or 0) / GraphModel.LABEL_PX))
    return math.max(1, math.ceil(n / fit))
end

function GraphModel.FormatValue(chart, v)
    local kind = GraphModel.KIND[chart]
    if kind == "duration" then return ns.Format.Duration(v) end
    if kind == "money" then return ns.Format.Money(v, true) end
    return ns.Format.Number(v)
end

-- Bar geometry for a plot `height` pixels tall: returns zeroY and a function value -> (y, h).
function GraphModel.Layout(points, height, integer)
    local lo, hi = 0, 0
    for _, p in ipairs(points) do
        if p.value < lo then lo = p.value end
        if p.value > hi then hi = p.value end
    end
    local niceLo, niceHi, step = GraphModel.NiceScale(lo, hi, 4, integer)
    local span = niceHi - niceLo
    local zeroY = (0 - niceLo) / span * height
    local function bar(v)
        local h = math.abs(v) / span * height
        if v >= 0 then return zeroY, h end
        return zeroY - h, h
    end
    return { lo = niceLo, hi = niceHi, step = step, zeroY = zeroY, bar = bar }
end

-- Compare overlay: only charts whose x axis means the same thing for both
-- characters (level number, calendar day) can be compared.
GraphModel.COMPARABLE = { timePerLevel = true, questsPerDay = true }

function GraphModel.CanCompare(chart)
    return GraphModel.COMPARABLE[chart] == true
end

-- Line two series up by label. Returns rows { label, note, a, b, partialA, partialB }
-- (a or b nil where that character has no point). Level labels sort numerically.
function GraphModel.Align(a, b)
    local byLabel, order = {}, {}
    local function add(points, side)
        for _, p in ipairs(points or {}) do
            local row = byLabel[p.label]
            if not row then
                row = { label = p.label, note = p.note }
                byLabel[p.label] = row
                order[#order + 1] = row
            end
            row[side] = p.value
            row["partial" .. side:upper()] = p.partial
        end
    end
    add(a, "a")
    add(b, "b")
    local numeric = true
    for _, row in ipairs(order) do if not tonumber(row.label) then numeric = false end end
    if numeric then
        table.sort(order, function(x, y) return tonumber(x.label) < tonumber(y.label) end)
    else
        table.sort(order, function(x, y) return tostring(x.note or x.label) < tostring(y.note or y.label) end)
    end
    while #order > GraphModel.MAX_POINTS do table.remove(order, 1) end
    return order
end
