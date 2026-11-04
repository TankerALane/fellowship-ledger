-- Core/Export.lua
-- PURE: no WoW globals. /fl export: a compact, line-based text dump of the saved data,
-- for keeping a copy outside the game (SavedVariables reportedly fail on some
-- Forever setups). One record per line, fields separated by " | ".
--
--   FLX1 | <flavor> | <exported at>
--   C | key | class | race | faction | level | played | active
--   L | key | from | to | active | total | at | zone
--   D | key | day | field=value,field=value,...
--   S | key | start | stop | played | active | levelStart | levelEnd
--   Q | key | at | questID | title
--   R | key | entered | name | difficultyID | completed | duration | deaths

local _, ns = ...

local Export = {}
ns.Export = Export

local function clean(v)
    return (tostring(v == nil and "" or v):gsub("[|\n\r]", "/"))
end

local function line(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = clean((select(i, ...))) end
    return table.concat(parts, " | ")
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function Export.Build(db, flavor, exportedAt)
    local out = { line("FLX1", flavor, exportedAt) }
    local chars = db.characters or {}
    for _, key in ipairs(sortedKeys(chars)) do
        local c = chars[key]
        local clock = c.clock or {}
        out[#out + 1] = line("C", key, c.class, c.race, c.faction, c.level, clock.played or 0, clock.active or 0)
        local levels = {}
        for to in pairs(c.levels or {}) do levels[#levels + 1] = to end
        table.sort(levels)
        for _, to in ipairs(levels) do
            local r = c.levels[to]
            out[#out + 1] = line("L", key, r.from, r.to, r.active, r.total, r.at, r.zone)
        end
        for _, day in ipairs(sortedKeys(c.days or {})) do
            local fields = {}
            for _, f in ipairs(sortedKeys(c.days[day])) do fields[#fields + 1] = f .. "=" .. tostring(c.days[day][f]) end
            out[#out + 1] = line("D", key, day, table.concat(fields, ","))
        end
        for _, s in ipairs(c.sessions or {}) do
            out[#out + 1] = line("S", key, s.start, s.stop, s.played, s.active, s.levelStart, s.levelEnd)
        end
        for _, q in ipairs(c.questLog or {}) do
            out[#out + 1] = line("Q", key, q.at, q.id, q.title)
        end
        for _, r in ipairs(c.dungeons or {}) do
            out[#out + 1] = line("R", key, r.entered, r.name, r.difficultyID, r.completed and 1 or 0, r.duration, r.deaths)
        end
    end
    return table.concat(out, "\n")
end
