-- Core/XPSources.lua
-- PURE: no WoW globals. Where XP came from (D-120): quests, kills, exploration or
-- other. The game says how much XP a quest turn-in and a discovery give, but not a
-- kill, and the order of the events is not fixed (the XP bar may move just before or
-- just after the turn-in event). So the tracker reports three things here:
--   Mark(kind, amount, now)  a quest turn-in or discovery (with its XP), or a kill by
--                            you or your group (no amount)
--   Gain(amount, now)        the XP bar moved by this much
-- and each returns the changes to count: { { field, delta, tag } }. tag: what the
-- gain was given (the level it was earned at, for the per-level split); a change that
-- moves XP over later keeps the tag of the gain it moves. A gain takes what a
-- recent mark explains (quest or exploration first, then a kill takes the rest); what
-- is left is "other" for now, and a mark that arrives a moment later moves it over.
-- Counts kept: xp_quest, xp_kill, xp_explore, xp_other (their sum is the XP split
-- so far; the plain xp count still holds all XP, so days before this add up too).

local _, ns = ...

local XPSources = {}
ns.XPSources = XPSources

XPSources.SOURCES = { "quest", "kill", "explore", "other" }
XPSources.WINDOW = 2       -- seconds a mark and a gain can be apart and still belong together
XPSources.KILL_WINDOW = 1.5

function XPSources.New()
    return { marks = {}, recent = {} }
end

local function prune(state, now)
    for i = #state.marks, 1, -1 do
        local m = state.marks[i]
        local w = m.kind == "kill" and XPSources.KILL_WINDOW or XPSources.WINDOW
        if now - m.at > w or (m.amount and m.amount <= 0) then table.remove(state.marks, i) end
    end
    for i = #state.recent, 1, -1 do
        local r = state.recent[i]
        if now - r.at > XPSources.WINDOW or r.amount <= 0 then table.remove(state.recent, i) end
    end
end

local function add(out, field, n, tag)
    if n == 0 then return end
    for _, c in ipairs(out) do
        if c[1] == field and c[3] == tag then c[2] = c[2] + n return end
    end
    out[#out + 1] = { field, n, tag }
end

-- A source event. kind: "quest" or "explore" with the XP the game reported, or "kill".
function XPSources.Mark(state, kind, amount, now)
    prune(state, now)
    local out = {}
    if kind == "kill" then
        -- A gain just before the kill event: it was the kill's.
        for _, r in ipairs(state.recent) do
            if now - r.at <= XPSources.KILL_WINDOW and r.amount > 0 then
                add(out, "xp_other", -r.amount, r.tag)
                add(out, "xp_kill", r.amount, r.tag)
                r.amount = 0
            end
        end
        state.marks[#state.marks + 1] = { kind = "kill", at = now }
        return out
    end
    if type(amount) ~= "number" or amount <= 0 then return out end
    -- XP already counted as other a moment ago: move what this event explains.
    for _, r in ipairs(state.recent) do
        if amount <= 0 then break end
        local take = math.min(amount, r.amount)
        if take > 0 then
            add(out, "xp_other", -take, r.tag)
            add(out, "xp_" .. kind, take, r.tag)
            r.amount, amount = r.amount - take, amount - take
        end
    end
    if amount > 0 then state.marks[#state.marks + 1] = { kind = kind, amount = amount, at = now } end
    return out
end

-- The XP bar moved by amount. A gain across a level-up is reported as two gains, one
-- per level (tag).
function XPSources.Gain(state, amount, now, tag)
    local out = {}
    if type(amount) ~= "number" or amount <= 0 then return out end
    prune(state, now)
    local left = amount
    -- Quest and exploration XP first: their amounts are known.
    for _, m in ipairs(state.marks) do
        if left <= 0 then break end
        if m.amount and m.amount > 0 then
            local take = math.min(left, m.amount)
            add(out, "xp_" .. m.kind, take, tag)
            m.amount, left = m.amount - take, left - take
        end
    end
    if left > 0 then
        for _, m in ipairs(state.marks) do
            if m.kind == "kill" then
                add(out, "xp_kill", left, tag)
                left = 0
                break
            end
        end
    end
    if left > 0 then
        add(out, "xp_other", left, tag)
        state.recent[#state.recent + 1] = { amount = left, at = now, tag = tag }
    end
    return out
end

-- The split for a set of counts (a day sum or a session): { total, before, rows =
-- { { source, xp } } } where before is XP from before sources were kept.
function XPSources.Split(counts)
    counts = counts or {}
    local total = counts.xp or 0
    local rows, known = {}, 0
    for _, s in ipairs(XPSources.SOURCES) do
        local v = math.max(0, counts["xp_" .. s] or 0)
        rows[#rows + 1] = { source = s, xp = v }
        known = known + v
    end
    total = math.max(total, known)
    return { total = total, before = total - known, rows = rows }
end

-- The biggest source of a split, when at least one source is known: source, share (0-1).
function XPSources.Top(split)
    local best
    for _, r in ipairs(split.rows) do
        if r.xp > 0 and (not best or r.xp > best.xp) then best = r end
    end
    if not best or split.total <= 0 then return nil end
    return best.source, best.xp / split.total
end

-- Per level (D-120): byLevel = char.levelXP ({ [level] = { quest, kill, explore, other } },
-- keyed by the level the XP was earned at). Rows newest first: { level, total,
-- quest, kill, explore, other, current }; current: the level being played now.
function XPSources.Levels(byLevel, currentLevel)
    local rows = {}
    for level, t in pairs(byLevel or {}) do
        if type(level) == "number" and type(t) == "table" then
            local row = { level = level, total = 0, current = level == currentLevel or nil }
            for _, src in ipairs(XPSources.SOURCES) do
                row[src] = math.max(0, t[src] or 0)
                row.total = row.total + row[src]
            end
            if row.total > 0 then rows[#rows + 1] = row end
        end
    end
    table.sort(rows, function(a, b) return a.level > b.level end)
    return rows
end
