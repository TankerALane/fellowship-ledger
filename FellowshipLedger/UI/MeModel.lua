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
    { field = "faction", label = "COL_FACTION", kind = "faction", width = 62 },
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
            name = c.display or c.name or key,
            class = c.class,
            faction = c.faction,
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

-- UnitFactionGroup's English token -> locale key. Anything else (an old record
-- without a faction, or a faction we do not know) shows as-is or blank.
local FACTION_KEYS = { Horde = "FACTION_HORDE", Alliance = "FACTION_ALLIANCE", Neutral = "FACTION_NEUTRAL" }

function MeModel.FormatCell(col, row)
    local v = row[col.field]
    if col.kind == "faction" then
        if type(v) ~= "string" then return "" end
        local key = FACTION_KEYS[v]
        return (key and ns.L and ns.L[key]) or v
    end
    if col.kind == "money" then return ns.Format.Money(v, true) end
    if col.kind == "duration" then return ns.Format.Duration(v) end
    if col.kind == "pair" then return tostring(row.dungeons) .. "/" .. tostring(row.dungeonsEntered) end
    return tostring(v)
end

-- Sum of every numeric column over the rows (the "All characters" line).
function MeModel.Totals(rows)
    local total = { name = "", level = 0 }
    for _, r in ipairs(rows) do
        for k, v in pairs(r) do
            if type(v) == "number" and k ~= "level" then total[k] = (total[k] or 0) + v end
        end
    end
    for _, col in ipairs(MeModel.COLUMNS) do
        if col.kind ~= "text" and col.kind ~= "faction" and total[col.field] == nil then total[col.field] = 0 end
    end
    total.dungeonsEntered = total.dungeonsEntered or 0
    return total
end

-- Recent deaths (with what killed you, when known) and notable loot, newest first,
-- for a character's expanded row. At most `limit` (default 5) of each.
function MeModel.RecentLines(char, L, dateFn, limit)
    limit = limit or 5
    local lines = {}
    local deaths = char.deathLog or {}
    for i = #deaths, math.max(1, #deaths - limit + 1), -1 do
        local d = deaths[i]
        local when = dateFn("%m-%d %H:%M", d.at or 0)
        local text
        if d.killer then
            text = string.format(L.RECENT_DEATH_BY, when, d.killer .. (d.killerSpell and (" (" .. d.killerSpell .. ")") or ""), d.zone or "?")
        elseif d.killerStatus == "hidden" then
            text = string.format(L.RECENT_DEATH_HIDDEN, when, d.zone or "?")
        else
            text = string.format(L.RECENT_DEATH, when, d.zone or "?")
        end
        lines[#lines + 1] = text
    end
    local items = char.items or {}
    for i = #items, math.max(1, #items - limit + 1), -1 do
        local it = items[i]
        local quality = L["QUALITY_" .. tostring(it.quality)]
        lines[#lines + 1] = string.format(L.RECENT_ITEM, dateFn("%m-%d %H:%M", it.at or 0), it.name or it.link or "?",
            type(quality) == "string" and quality or tostring(it.quality))
    end
    return lines
end
