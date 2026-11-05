-- UI/DetailModel.lua
-- PURE: no WoW globals. What an opened character on the Me tab shows: a summary,
-- recent levels, recent deaths and notable loot (newest first, the last 10 / 5 / 5
-- unless "Show all" is on), and how to lay them out as table lines in either
-- layout: "card" (a shaded box, levels left, deaths and loot right) or "list"
-- (sections one under another). D-075.
--
-- A layout is a list of "grid" lines for UI/Table.lua:
--   { kind = "grid", inset = px, box = "top"|"mid"|"bottom"|"single"|nil,
--     rules = { { x, w }, ... }   (thin lines under parts of the line),
--     segments = { { x, w, text, role, font, align, button = { label, onClick } }, ... },
--     action = { label, onClick } (the table's right-hand button) }
-- x and w are fractions of the line's width after the inset.

local _, ns = ...

local DetailModel = {}
ns.DetailModel = DetailModel

DetailModel.LIMITS = { levels = 10, deaths = 5, loot = 5 }
DetailModel.INSET = 18

local function when(dateFn, at) return dateFn("%m-%d %H:%M", at or 0) end

-- "9 -> 10" with our arrow image (media/level-arrow.tga) tinted to `c`, so it
-- does not depend on the font having an arrow. Without a color: plain "->".
local ARROW_PATH = "Interface\\AddOns\\FellowshipLedger\\media\\level-arrow"
function DetailModel.ArrowCode(c)
    if not c then return "->" end
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|T%s:0:0:0:0:16:16:0:16:0:16:%d:%d:%d|t", ARROW_PATH, byte(c[1]), byte(c[2]), byte(c[3]))
end

function DetailModel.LevelText(L, from, to, arrow)
    return string.format(L.DETAIL_LEVEL, from, arrow or "->", to)
end

-- Killer's level for display: a number, "??" for skull level (-1), "?" unknown.
local function killerLevel(d)
    local v = d.killerLevel
    if type(v) ~= "number" then return d.killer and "?" or "" end
    if v < 0 then return "??" end
    return tostring(v)
end

-- char: a saved character. all: { levels = bool, deaths = bool, loot = bool }.
-- arrow: from DetailModel.ArrowCode (default "->").
function DetailModel.Data(char, L, dateFn, all, arrow)
    all = all or {}
    local Format = ns.Format
    local out = { levels = { rows = {} }, deaths = { rows = {} }, loot = { rows = {} }, summary = {} }

    -- Levels, newest first. Partial levels (the ledger joined partway) are listed
    -- but left out of the average, fastest and slowest.
    local keys = {}
    for to in pairs(char.levels or {}) do keys[#keys + 1] = to end
    table.sort(keys, function(a, b) return a > b end)
    local sum, n, fastest, slowest = 0, 0, nil, nil
    for _, to in ipairs(keys) do
        local r = char.levels[to]
        if not r.partial and type(r.active) == "number" then
            sum, n = sum + r.active, n + 1
            if not fastest or r.active < fastest.active then fastest = r end
            if not slowest or r.active > slowest.active then slowest = r end
        end
    end
    out.levels.total = #keys
    local shown = all.levels and #keys or math.min(#keys, DetailModel.LIMITS.levels)
    for i = 1, shown do
        local r = char.levels[keys[i]]
        out.levels.rows[i] = {
            level = DetailModel.LevelText(L, r.from or (keys[i] - 1), r.to or keys[i], arrow),
            active = Format.Duration(r.active),
            played = Format.Duration(r.total),
            zone = (r.zone or "") .. (r.partial and (" " .. L.DETAIL_PARTIAL) or ""),
        }
    end

    -- Deaths, newest first.
    local deaths = char.deathLog or {}
    out.deaths.total = #deaths
    local stop = all.deaths and 1 or math.max(1, #deaths - DetailModel.LIMITS.deaths + 1)
    for i = #deaths, stop, -1 do
        local d = deaths[i]
        local killer = d.killer
        if not killer then killer = d.killerStatus == "hidden" and L.DETAIL_KILLER_HIDDEN or L.DETAIL_KILLER_UNKNOWN end
        out.deaths.rows[#out.deaths.rows + 1] = {
            when = when(dateFn, d.at), killer = killer, theirLevel = killerLevel(d),
            yourLevel = type(d.level) == "number" and tostring(d.level) or "", zone = d.zone or "",
        }
    end

    -- Notable loot, newest first.
    local items = char.items or {}
    out.loot.total = #items
    stop = all.loot and 1 or math.max(1, #items - DetailModel.LIMITS.loot + 1)
    for i = #items, stop, -1 do
        local it = items[i]
        local q = rawget(L, "QUALITY_" .. tostring(it.quality))
        out.loot.rows[#out.loot.rows + 1] = {
            when = when(dateFn, it.at), name = it.name or it.link or "?", quality = it.quality,
            qualityText = q or tostring(it.quality or ""), zone = it.zone or "",
        }
    end

    out.summary = { levels = #keys, average = n > 0 and math.floor(sum / n) or nil, fastest = fastest, slowest = slowest,
        deaths = #deaths, arrow = arrow }
    return out
end

-- The summary as one string; values in the text color, labels in the line's muted color.
function DetailModel.SummaryText(s, L, valueCode)
    local Format = ns.Format
    local v = function(x) return (valueCode or "") .. x .. (valueCode and "|r" or "") end
    local parts = { string.format(L.DETAIL_SUM_LEVELS, v(tostring(s.levels))) }
    if s.average then parts[#parts + 1] = string.format(L.DETAIL_SUM_AVERAGE, v(Format.Duration(s.average))) end
    if s.fastest and s.slowest and s.fastest ~= s.slowest then
        parts[#parts + 1] = string.format(L.DETAIL_SUM_FASTEST, v(DetailModel.LevelText(L, s.fastest.from, s.fastest.to, s.arrow)),
            Format.Duration(s.fastest.active))
        parts[#parts + 1] = string.format(L.DETAIL_SUM_SLOWEST, v(DetailModel.LevelText(L, s.slowest.from, s.slowest.to, s.arrow)),
            Format.Duration(s.slowest.active))
    end
    parts[#parts + 1] = string.format(L.DETAIL_SUM_DEATHS, v(tostring(s.deaths)))
    return table.concat(parts, "     ")
end

-- Column positions (fractions). Card: levels on the left (0 to .41), deaths and
-- loot on the right (.44 to 1). List: each section uses the full width.
local COLS = {
    card = {
        levels = { { .00, .09 }, { .095, .075 }, { .175, .075 }, { .255, .155 } }, levelsEnd = .41,
        deaths = { { .44, .105 }, { .55, .19 }, { .745, .06 }, { .81, .06 }, { .875, .125 } },
        loot = { { .44, .105 }, { .55, .23 }, { .785, .085 }, { .875, .125 } },
        rightStart = .44,
    },
    list = {
        levels = { { .00, .10 }, { .11, .10 }, { .22, .10 }, { .33, .30 } },
        deaths = { { .00, .12 }, { .13, .30 }, { .44, .08 }, { .53, .08 }, { .62, .30 } },
        loot = { { .00, .12 }, { .13, .30 }, { .44, .12 }, { .62, .30 } },
    },
}
DetailModel.COLS = COLS

local function seg(pos, text, role, font, align)
    return { x = pos[1], w = pos[2], text = text or "", role = role or "text", font = font or "body", align = align }
end

-- One section as a list of "half lines" (segment lists, plus rules for header rows).
-- cols: the column positions; x0/x1: the section's span (for the heading and its button).
local function section(title, sec, cols, x0, x1, kind, L, skin, onToggle, emptyText)
    local Palette = ns.Palette
    local out = {}
    local heading = { segs = { seg({ x0, (x1 - x0) * 0.6 }, title, "heading", "body") } }
    local limit = DetailModel.LIMITS[kind]
    if sec.total > limit then
        local label = (#sec.rows > limit) and L.DETAIL_SHOW_LESS or string.format(L.DETAIL_SHOW_ALL, sec.total)
        heading.segs[#heading.segs + 1] = { x = x0, w = x1 - x0, text = "", button = { label = label, onClick = function() onToggle(kind) end } }
    end
    heading.rules = { { x0, x1 - x0 } }
    out[#out + 1] = heading
    if #sec.rows == 0 then
        out[#out + 1] = { segs = { seg({ x0, x1 - x0 }, emptyText, "muted") } }
        return out
    end
    local header = { segs = {} }
    local labels = kind == "levels" and { L.DETAIL_COL_LEVEL, L.DETAIL_COL_ACTIVE, L.DETAIL_COL_PLAYED, L.DETAIL_COL_ZONE }
        or kind == "deaths" and { L.DETAIL_COL_WHEN, L.DETAIL_COL_KILLER, L.DETAIL_COL_THEIR_LEVEL, L.DETAIL_COL_YOUR_LEVEL, L.DETAIL_COL_ZONE }
        or { L.DETAIL_COL_WHEN, L.DETAIL_COL_ITEM, L.DETAIL_COL_QUALITY, L.DETAIL_COL_ZONE }
    for c, pos in ipairs(cols) do
        local center = kind == "deaths" and (c == 3 or c == 4)
        header.segs[c] = seg(pos, labels[c], "muted", "small", center and "CENTER" or nil)
    end
    out[#out + 1] = header
    for _, r in ipairs(sec.rows) do
        local segs
        if kind == "levels" then
            segs = { seg(cols[1], r.level), seg(cols[2], r.active), seg(cols[3], r.played), seg(cols[4], r.zone, "muted") }
        elseif kind == "deaths" then
            segs = { seg(cols[1], r.when, "muted"), seg(cols[2], r.killer), seg(cols[3], r.theirLevel, "text", nil, "CENTER"),
                seg(cols[4], r.yourLevel, "text", nil, "CENTER"), seg(cols[5], r.zone, "muted") }
        else
            local color = Palette and Palette.QualityColor(r.quality, skin)
            local name = color and (Palette.Code(color) .. r.name .. "|r") or r.name
            segs = { seg(cols[1], r.when, "muted"), seg(cols[2], name), seg(cols[3], r.qualityText, "muted"), seg(cols[4], r.zone, "muted") }
        end
        out[#out + 1] = { segs = segs }
    end
    return out
end

local function sections(data, layout, L, skin, onToggle)
    local C = COLS[layout]
    local x0 = layout == "card" and C.rightStart or 0
    local lv = section(L.DETAIL_LEVELS, data.levels, C.levels, 0, layout == "card" and C.levelsEnd or 1, "levels", L, skin, onToggle, L.NO_LEVELS_YET)
    local de = section(L.DETAIL_DEATHS, data.deaths, C.deaths, x0, 1, "deaths", L, skin, onToggle, L.DETAIL_NO_DEATHS)
    local lo = section(L.DETAIL_LOOT, data.loot, C.loot, x0, 1, "loot", L, skin, onToggle, L.DETAIL_NO_LOOT)
    return lv, de, lo
end

-- opts: { skin, onToggle(kind), onRemove (nil when the character can't be removed), valueCode }
function DetailModel.Lines(data, layout, L, opts)
    opts = opts or {}
    layout = COLS[layout] and layout or "card"
    local lv, de, lo = sections(data, layout, L, opts.skin, opts.onToggle or function() end)
    local inset = DetailModel.INSET
    local lines = {}
    local function add(half, extra)
        local line = { kind = "grid", inset = inset, segments = half.segs, rules = half.rules }
        for k, v in pairs(extra or {}) do line[k] = v end
        lines[#lines + 1] = line
        return line
    end
    if layout == "list" then
        for _, part in ipairs({ lv, de, lo }) do
            if #lines > 0 then add({ segs = {} }) end
            for _, half in ipairs(part) do add(half) end
        end
    else
        -- A blank line before the summary and before the headings, like the one before Notable loot.
        add({ segs = {} })
        add({ segs = { seg({ 0, 1 }, DetailModel.SummaryText(data.summary, L, opts.valueCode), "muted") }, rules = { { 0, 1 } } })
        add({ segs = {} })
        local right = {}
        for _, h in ipairs(de) do right[#right + 1] = h end
        right[#right + 1] = { segs = {} }
        for _, h in ipairs(lo) do right[#right + 1] = h end
        for i = 1, math.max(#lv, #right) do
            local a, b = lv[i] or { segs = {} }, right[i] or { segs = {} }
            local segs, rules = {}, {}
            for _, s in ipairs(a.segs) do segs[#segs + 1] = s end
            for _, s in ipairs(b.segs) do segs[#segs + 1] = s end
            for _, r in ipairs(a.rules or {}) do rules[#rules + 1] = r end
            for _, r in ipairs(b.rules or {}) do rules[#rules + 1] = r end
            add({ segs = segs, rules = #rules > 0 and rules or nil })
        end
    end
    if opts.onRemove then
        add({ segs = { seg({ 0, 1 }, L.REMOVE_LINE, "muted", "body", "RIGHT") } }, { action = { label = L.REMOVE, onClick = opts.onRemove } })
    end
    if layout == "card" then
        if #lines == 1 then lines[1].box = "single" else
            lines[1].box = "top"
            for i = 2, #lines - 1 do lines[i].box = "mid" end
            lines[#lines].box = "bottom"
        end
    end
    return lines
end
