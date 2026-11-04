-- UI/MeModel.lua
-- PURE: no WoW globals. Turns saved character records into rows for the Me tab
-- table: one row per character, summed over a date range, sortable.

local _, ns = ...

local MeModel = {}
ns.MeModel = MeModel

-- Columns in display order. `field` is the row key; `kind` picks the formatter.
MeModel.COLUMNS = {
    { field = "name", label = "COL_CHARACTER", kind = "text", width = 150 },
    { field = "level", label = "COL_LEVEL", kind = "number", width = 42 },
    { field = "levels", label = "COL_LEVELS", kind = "number", width = 52 },
    { field = "quests", label = "COL_QUESTS", kind = "number", width = 54 },
    { field = "dungeons", label = "COL_DUNGEONS", kind = "pair", width = 70 },
    { field = "moneyNet", label = "COL_GOLD", kind = "money", width = 104 },
    { field = "played", label = "COL_PLAYED", kind = "duration", width = 70 },
    { field = "active", label = "COL_ACTIVE", kind = "duration", width = 70 },
    { field = "deaths", label = "COL_DEATHS", kind = "number", width = 50 },
    { field = "kills", label = "COL_KILLS", kind = "number", width = 50 },
    { field = "skillUps", label = "COL_SKILLUPS", kind = "number", width = 54 },
}

-- characters: db.characters; range: "today" | "week" | "month" | "all"
function MeModel.Build(characters, range, todayKey, timeFn, dateFn)
    local Days = ns.Days
    local from = Days.RangeStart(range, todayKey, timeFn, dateFn)
    local rows = {}
    for key, c in pairs(characters or {}) do
        local sum = Days.Sum(c.days or {}, from, todayKey)
        rows[#rows + 1] = {
            key = key,
            name = c.name or key,
            class = c.class,
            level = c.level or 0,
            levels = sum.levels or 0,
            quests = sum.quests or 0,
            dungeons = sum.dungeonsCompleted or 0,
            dungeonsEntered = sum.dungeonsEntered or 0,
            moneyNet = sum.moneyNet or 0,
            played = sum.played or 0,
            active = sum.active or 0,
            deaths = sum.deaths or 0,
            kills = sum.kills or 0,
            skillUps = sum.skillUps or 0,
        }
    end
    return rows
end

function MeModel.Sort(rows, field, descending)
    table.sort(rows, function(a, b)
        local x, y = a[field], b[field]
        if x == y then return tostring(a.key) < tostring(b.key) end
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if descending then return x > y end
        return x < y
    end)
    return rows
end

-- Per-level lines for the expanded row, lowest level first.
function MeModel.LevelLines(char, L)
    local levels = {}
    for to in pairs(char.levels or {}) do levels[#levels + 1] = to end
    table.sort(levels)
    local lines = {}
    for _, to in ipairs(levels) do
        local r = char.levels[to]
        local text = ns.Format.LevelLine(r)
        if r.zone then text = text .. "  " .. r.zone end
        if r.partial then text = text .. "  " .. (L and L.PARTIAL or "(partial)") end
        lines[#lines + 1] = text
    end
    return lines
end

function MeModel.FormatCell(col, row)
    local v = row[col.field]
    if col.kind == "money" then return ns.Format.Money(v, true) end
    if col.kind == "duration" then return ns.Format.Duration(v) end
    if col.kind == "pair" then return tostring(row.dungeons) .. "/" .. tostring(row.dungeonsEntered) end
    return tostring(v)
end
