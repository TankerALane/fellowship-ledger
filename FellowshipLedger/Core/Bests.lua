-- Core/Bests.lua
-- PURE: no WoW globals. Personal bests (D-115): records kept for good, apart from the
-- 90-day history, so an old best is not lost when its days are pruned.
--
-- A store is { filled, level = { [to] = rec }, day = { [field] = rec },
-- session = { [field] = rec }, dungeon = { [name] = rec } } where
-- rec = { value, at, holder, day?, session? }. Two stores are kept: each character's own
-- (char.bests) and one for all your characters (db.bests, with `holder` = character key).
-- A character gains each level once, so fastest levels are only compared across
-- characters; a character's own store has no level records.

local _, ns = ...

local Bests = {}
ns.Bests = Bests

Bests.DAY_FIELDS = { "quests", "kills", "xp" }        -- most in one day
Bests.SESSION_FIELDS = { "active", "levels" }         -- longest session, most levels in one session
Bests.MIN_LEVEL_SECONDS = 60                           -- a level faster than this is not a real time
Bests.MIN_CLEAR_SECONDS = 60

local function lower(a, b) return a < b end
local function higher(a, b) return a > b end

function Bests.New()
    return { level = {}, day = {}, session = {}, dungeon = {} }
end

function Bests.Ensure(store)
    store = type(store) == "table" and store or {}
    store.level, store.day = store.level or {}, store.day or {}
    store.session, store.dungeon = store.session or {}, store.dungeon or {}
    return store
end

-- The clear time of a run (seconds from its first fight, D-126, to the final boss), or nil.
function Bests.Clear(run)
    if not (run and run.completed and run.completedAt and run.entered) then return nil end
    local c = run.completedAt - ns.RunTimer.Start(run)
    if c < Bests.MIN_CLEAR_SECONDS then return nil end
    return c
end

-- Every value a character's data offers for a record: { { group, key, value, at, day?, session? } }.
-- withLevels: include fastest levels (only for the all-characters store).
function Bests.Candidates(char, withLevels)
    local out = {}
    if withLevels then
        for to, r in pairs(char.levels or {}) do
            local a = tonumber(r.active)
            if not r.partial and a and a >= Bests.MIN_LEVEL_SECONDS then
                out[#out + 1] = { group = "level", key = tonumber(to), value = a, at = r.at }
            end
        end
    end
    for day, b in pairs(char.days or {}) do
        for _, f in ipairs(Bests.DAY_FIELDS) do
            local v = tonumber(b[f])
            if v and v > 0 then out[#out + 1] = { group = "day", key = f, value = v, day = day } end
        end
    end
    for _, s in ipairs(char.sessions or {}) do
        local values = { active = tonumber(s.active), levels = tonumber(s.counts and s.counts.levels) }
        for _, f in ipairs(Bests.SESSION_FIELDS) do
            local v = values[f]
            if v and v > 0 then out[#out + 1] = { group = "session", key = f, value = v, at = s.start, session = s.start } end
        end
    end
    local runs = {}
    for _, r in ipairs(char.dungeons or {}) do runs[#runs + 1] = r end
    if char.currentRun then runs[#runs + 1] = char.currentRun end
    for _, r in ipairs(runs) do
        local c = Bests.Clear(r)
        if c and r.name then out[#out + 1] = { group = "dungeon", key = r.name, value = c, at = r.completedAt } end
    end
    return out
end

local function better(group, a, b)
    if group == "level" or group == "dungeon" then return lower(a, b) end
    return higher(a, b)
end

-- The same day or session: a record still growing, not a new one.
local function samePeriod(rec, c)
    if c.day then return rec.day == c.day end
    if c.session then return rec.session == c.session end
    return false
end

-- Fold a character's data into a store. Returns the records beaten:
-- { { group, key, old, new, holder } }. Nothing counts as beaten while the store is
-- being filled for the first time (store.filled not yet set), when there was no
-- record before, or when the record only grew within its own day or session.
function Bests.Update(store, char, holder, withLevels)
    store = Bests.Ensure(store)
    local beaten = {}
    for _, c in ipairs(Bests.Candidates(char, withLevels)) do
        local list = store[c.group]
        local rec = list[c.key]
        if not rec or better(c.group, c.value, rec.value) then
            local new = { value = c.value, at = c.at, day = c.day, session = c.session, holder = holder }
            if rec and store.filled and not (rec.holder == holder and samePeriod(rec, c)) then
                beaten[#beaten + 1] = { group = c.group, key = c.key, old = rec, new = new, holder = holder }
            end
            list[c.key] = new
        end
    end
    return beaten
end

-- The notice line for a beaten record. fmt: { Duration, Number }.
function Bests.Text(b, L, fmt)
    local g, old, new = b.group, b.old.value, b.new.value
    if g == "level" then
        return string.format(L.BEST_LEVEL, b.key, fmt.Duration(new), fmt.Duration(old - new))
    elseif g == "dungeon" then
        return string.format(L.BEST_DUNGEON, b.key, fmt.Duration(new), fmt.Duration(old - new))
    elseif g == "day" then
        return string.format(L["BEST_DAY_" .. b.key:upper()], fmt.Number(new), fmt.Number(old))
    end
    if b.key == "active" then return string.format(L.BEST_SESSION_ACTIVE, fmt.Duration(new), fmt.Duration(old)) end
    return string.format(L.BEST_SESSION_LEVELS, fmt.Number(new), fmt.Number(old))
end

-- Rows for the Bests view: { { section } | { label, mine, all, holder, mineIsAll } }.
-- mine: this character's store (nil fields shown as "-"); all: the all-characters store;
-- ownLevels: this character's char.levels, for its own time at each level.
function Bests.Rows(mine, all, L, fmt, dateFn, ownLevels)
    mine, all = Bests.Ensure(mine), Bests.Ensure(all)
    local rows = {}
    local function when(rec)
        if not rec then return "" end
        if rec.day then return rec.day end
        return rec.at and dateFn("%Y-%m-%d", rec.at) or ""
    end
    local function add(label, group, key, show)
        local m, a = mine[group][key], all[group][key]
        if group == "level" then
            local r = ownLevels and ownLevels[key]
            m = (r and not r.partial and tonumber(r.active)) and { value = tonumber(r.active) } or nil
        end
        if not (m or a) then return end
        rows[#rows + 1] = { label = label, mine = m and show(m.value) or "-", all = a and show(a.value) or "-",
            holder = a and a.holder, when = when(a), mineIsAll = (m and a and m.value == a.value) or nil }
    end
    rows[#rows + 1] = { section = L.BESTS_DAY }
    for _, f in ipairs(Bests.DAY_FIELDS) do add(L["BESTS_DAY_" .. f:upper()], "day", f, fmt.Number) end
    rows[#rows + 1] = { section = L.BESTS_SESSION }
    add(L.BESTS_SESSION_ACTIVE, "session", "active", fmt.Duration)
    add(L.BESTS_SESSION_LEVELS, "session", "levels", fmt.Number)
    local names = {}
    for name in pairs(all.dungeon) do names[#names + 1] = name end
    for name in pairs(mine.dungeon) do if not all.dungeon[name] then names[#names + 1] = name end end
    table.sort(names)
    if #names > 0 then
        rows[#rows + 1] = { section = L.BESTS_DUNGEONS }
        for _, name in ipairs(names) do add(name, "dungeon", name, fmt.Duration) end
    end
    local levels = {}
    for to in pairs(all.level) do levels[#levels + 1] = to end
    table.sort(levels)
    if #levels > 0 then
        rows[#rows + 1] = { section = L.BESTS_LEVELS }
        for _, to in ipairs(levels) do add(string.format(L.BESTS_LEVEL, to - 1, to), "level", to, fmt.Duration) end
    end
    return rows
end
