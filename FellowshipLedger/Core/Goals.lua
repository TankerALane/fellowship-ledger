-- Core/Goals.lua
-- PURE: no WoW globals. Session goals (D-116): suggestions built from a character's
-- own past sessions and level times, and how far each goal has come.
--
-- XP is measured as part of a level per active hour (from the time each recent level
-- took), not raw XP, so a goal means the same at level 5 and level 40 (Austin's point);
-- it is turned into XP for the level you are at now.
--
-- Goal: { kind, target, name?, key?, on, start = { ... } }. kinds:
--   xphour      XP per active hour this session         target: XP per hour
--   levels      levels gained this session               target: levels (halves allowed)
--   quests      quests turned in this session            target: count
--   dungeon     clear this dungeon this session          name: the dungeon
--   profession  reach this rank in a profession          key: skill line, name, target: rank
-- now / start snapshots: { levelPos, xp, quests, active, ranks = { [key] = rank }, at }.

local _, ns = ...

local Goals = {}
ns.Goals = Goals

Goals.QUALIFY_SECONDS = 1200 -- a session counts toward the first suggestions after 20 active minutes
Goals.QUALIFY_COUNT = 3      -- and the first suggestions come after 3 such sessions (D-116)
Goals.NEARBY = 5             -- pace from the levels within 5 of yours
Goals.RECENT = 10            -- the last 10 qualifying sessions
Goals.MIN_XPHOUR_SECONDS = 600 -- XP per hour is judged after 10 active minutes
Goals.MAX_PROFESSIONS = 2
Goals.KINDS = { "xphour", "levels", "quests", "dungeon", "profession" }

-- Sessions that count: finished (not the current one) and 20+ active minutes.
function Goals.Qualifying(sessions, currentStart)
    local out = {}
    for _, s in ipairs(sessions or {}) do
        if s.start ~= currentStart and (tonumber(s.active) or 0) >= Goals.QUALIFY_SECONDS then out[#out + 1] = s end
    end
    while #out > Goals.RECENT do table.remove(out, 1) end
    return out
end

function Goals.Ready(sessions, currentStart)
    local n = #Goals.Qualifying(sessions, currentStart)
    return n >= Goals.QUALIFY_COUNT, n
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    local m = math.floor((#list + 1) / 2)
    if #list % 2 == 1 then return list[m] end
    return (list[m] + list[m + 1]) / 2
end

-- Levels per active hour from the levels near `level` (within NEARBY, full times only).
-- Falls back to every full level time. nil without any.
function Goals.Pace(levels, level)
    local near, all = {}, {}
    for to, r in pairs(levels or {}) do
        local a = tonumber(r.active)
        if not r.partial and a and a >= 60 then
            local rate = 3600 / a
            all[#all + 1] = rate
            if math.abs((tonumber(to) or 0) - (level or 0)) <= Goals.NEARBY then near[#near + 1] = rate end
        end
    end
    return median(#near > 0 and near or all)
end

local function roundTo(v, step) return math.floor(v / step + 0.5) * step end

-- Suggestions for this session. info: { level, maxLevel, xpMax, rested, sessions,
-- currentStart, levels, professions, cleared = { [dungeon] = true } }.
-- Returns a list of goals with `hint` = { key, args... } for the window.
function Goals.Suggest(info)
    local out = {}
    local recent = Goals.Qualifying(info.sessions, info.currentStart)
    local pace = Goals.Pace(info.levels, info.level)
    local leveling = info.level and (not info.maxLevel or info.level < info.maxLevel)
    if leveling and pace and (tonumber(info.xpMax) or 0) > 0 then
        local perHour = math.max(100, roundTo(pace * info.xpMax, 100))
        out[#out + 1] = { kind = "xphour", target = perHour, on = true,
            hint = { (tonumber(info.rested) or 0) > 0 and "GOAL_HINT_XPHOUR_RESTED" or "GOAL_HINT_XPHOUR", math.floor(pace * 100 + 0.5) } }
        local actives = {}
        for _, s in ipairs(recent) do actives[#actives + 1] = s.active end
        local typical = median(actives) or 3600
        local usual = {}
        for _, s in ipairs(recent) do usual[#usual + 1] = tonumber(s.counts and s.counts.levels) or 0 end
        out[#out + 1] = { kind = "levels", target = math.max(0.5, roundTo(pace * typical / 3600, 0.5)), on = true,
            hint = { "GOAL_HINT_LEVELS", string.format("%.1f", median(usual) or 0) } }
    end
    local quests, best = {}, 0
    for _, s in ipairs(recent) do
        local q = tonumber(s.counts and s.counts.quests) or 0
        quests[#quests + 1] = q
        if q > best then best = q end
    end
    local usualQuests = median(quests) or 0
    if usualQuests > 0 then
        out[#out + 1] = { kind = "quests", target = math.max(3, math.ceil(usualQuests * 1.1)), on = true,
            hint = { "GOAL_HINT_QUESTS", best } }
    end
    for _, name in ipairs(info.dungeons or {}) do
        if not (info.cleared or {})[name] then
            out[#out + 1] = { kind = "dungeon", name = name, target = 1, on = false, hint = { "GOAL_HINT_DUNGEON" } }
            break
        end
    end
    local keys = {}
    for key, p in pairs(info.professions or {}) do
        if (tonumber(p.rank) or 0) > 0 and (tonumber(p.max) or 0) > (tonumber(p.rank) or 0) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local ups = {}
    for _, s in ipairs(recent) do ups[#ups + 1] = tonumber(s.counts and s.counts.skillUps) or 0 end
    local step = math.max(5, math.floor((median(ups) or 0) / math.max(1, #keys) + 0.5))
    for i = 1, math.min(#keys, Goals.MAX_PROFESSIONS) do
        local p = info.professions[keys[i]]
        out[#out + 1] = { kind = "profession", key = keys[i], name = p.name or tostring(keys[i]), max = p.max,
            target = math.min(p.max, p.rank + step), on = false, hint = { "GOAL_HINT_PROFESSION", p.rank },
            start = { rank = p.rank } }
    end
    return out
end

-- How much a -/+ click moves a goal. xpMax: XP for the current level.
function Goals.Step(goal, xpMax)
    if goal.kind == "xphour" then return math.max(100, roundTo((tonumber(xpMax) or 0) * 0.05, 100)) end
    if goal.kind == "levels" then return 0.5 end
    if goal.kind == "dungeon" then return 0 end
    return 1
end

function Goals.Adjust(goal, dir, xpMax)
    local step = Goals.Step(goal, xpMax)
    if step == 0 then return goal.target end
    local minimum = goal.kind == "profession" and (goal.start and goal.start.rank or 0) + 1 or step
    local v = goal.target + dir * step
    if v < minimum then v = minimum end
    if goal.kind == "profession" and goal.max and v > goal.max then v = goal.max end
    goal.target = v
    return v
end

-- Where a goal stands. now: the current snapshot. Returns value, done.
function Goals.Progress(goal, now)
    local s = goal.start or {}
    if goal.kind == "xphour" then
        local active = (now.active or 0) - (s.active or 0)
        local value = active > 0 and math.floor(((now.xp or 0) - (s.xp or 0)) * 3600 / active) or 0
        return value, active >= Goals.MIN_XPHOUR_SECONDS and value >= goal.target
    elseif goal.kind == "levels" then
        local value = math.max(0, (now.levelPos or 0) - (s.levelPos or 0))
        return value, value >= goal.target
    elseif goal.kind == "quests" then
        local value = math.max(0, (now.quests or 0) - (s.quests or 0))
        return value, value >= goal.target
    elseif goal.kind == "dungeon" then
        local done = (now.cleared or {})[goal.name] and now.cleared[goal.name] >= (s.at or 0) or false
        return done and 1 or 0, done
    end
    local rank = (now.ranks or {})[goal.key] or (s.ranks or {})[goal.key] or 0
    return rank, rank >= goal.target
end

-- One goal as text: "Quests: 5 / 12", "Clear The Deadmines", with a check when done.
-- fmt: { Number }.
function Goals.Text(goal, value, done, L, fmt)
    local text
    if goal.kind == "xphour" then
        text = string.format(L.GOAL_XPHOUR, fmt.Number(value or 0), fmt.Number(goal.target))
    elseif goal.kind == "levels" then
        text = string.format(L.GOAL_LEVELS, string.format("%.1f", value or 0), string.format("%.1f", goal.target))
    elseif goal.kind == "quests" then
        text = string.format(L.GOAL_QUESTS, value or 0, goal.target)
    elseif goal.kind == "dungeon" then
        text = string.format(L.GOAL_DUNGEON, goal.name or "?")
    else
        text = string.format(L.GOAL_PROFESSION, goal.name or "?", value or 0, goal.target)
    end
    return (done and L.GOAL_DONE_MARK or "") .. text
end

-- The label in the suggestion window (the target, before the session starts).
function Goals.Label(goal, L, fmt)
    if goal.kind == "xphour" then return string.format(L.GOAL_SET_XPHOUR, fmt.Number(goal.target)) end
    if goal.kind == "levels" then return string.format(L.GOAL_SET_LEVELS, string.format("%.1f", goal.target)) end
    if goal.kind == "quests" then return string.format(L.GOAL_SET_QUESTS, goal.target) end
    if goal.kind == "dungeon" then return string.format(L.GOAL_DUNGEON, goal.name or "?") end
    return string.format(L.GOAL_SET_PROFESSION, goal.name or "?", goal.target)
end

function Goals.Hint(goal, L)
    local h = goal.hint
    if not h then return "" end
    return string.format(L[h[1]], unpack(h, 2))
end

-- The Me tab line: "Goals: Quests 5 / 12, ..." (nil when no goal was set).
function Goals.Line(set, now, L, fmt)
    if not (set and set.list and #set.list > 0) then return nil end
    local parts, done = {}, 0
    for _, g in ipairs(set.list) do
        local v, d = Goals.Progress(g, now)
        if d then done = done + 1 end
        parts[#parts + 1] = Goals.Text(g, v, d, L, fmt)
    end
    return string.format(L.GOAL_LINE, done, #set.list, table.concat(parts, "; "))
end

-- The lines added to the last session's summary at login: one per goal, from the
-- progress saved while playing.
function Goals.Results(set, L, fmt)
    if not (set and set.list and set.last) then return {} end
    local out, done = {}, 0
    for i, g in ipairs(set.list) do
        local r = set.last[i] or {}
        if r.done then done = done + 1 end
        out[#out + 1] = "  " .. Goals.Text(g, r.value, r.done, L, fmt)
    end
    table.insert(out, 1, string.format(L.GOAL_RESULTS, done, #set.list))
    return out
end
