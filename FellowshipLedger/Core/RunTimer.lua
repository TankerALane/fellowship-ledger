-- Core/RunTimer.lua
-- PURE: no WoW globals. The dungeon timer's numbers (D-122): the time into the run,
-- each boss killed with its time into the run, and how that compares with a target
-- run: the Leaderboard's #1 for this dungeon (default) or your own fastest clear.
-- The run's time is counted like its clear time (Trackers/Dungeons.lua): from first
-- entering to the final boss, time spent outside included (D-110).

local _, ns = ...

local RunTimer = {}
ns.RunTimer = RunTimer

RunTimer.MODES = { leader = true, mine = true }

-- The target run for a dungeon from Leaderboard entries (Leaderboard.Entries), joined
-- across ledgers and at level like the Leaderboard tab. mode: "leader" (#1, anyone)
-- or "mine" (your fastest). current: the open run, left out once it is completed (it
-- is on the Leaderboard then, and would be compared with itself; friends' reports of
-- it are joined into it). Returns { clear, splits = { [boss] = seconds into the run },
-- lead, mine } or nil when there is no completed run to compare with.
function RunTimer.Target(entries, dungeon, mode, current)
    if not dungeon then return nil end
    local doneAt = current and current.completed and current.completedAt
    local best
    for _, e in ipairs(ns.Leaderboard.Merge(entries or {})) do
        local itself = doneAt and e.mine and math.abs(e.finishedAt - doneAt) <= ns.Leaderboard.MATCH_SECONDS
        if e.dungeon == dungeon and not itself and ns.DungeonLevels.AtLevel(e.dungeon, e.levelMax)
            and (mode ~= "mine" or e.mine) then
            if not best or e.clear < best.clear then best = e end
        end
    end
    if not best then return nil end
    local start = best.finishedAt - best.clear
    local splits = {}
    for _, b in ipairs(best.bosses or {}) do
        if b.name and b.at then
            local into = b.at - start
            if not splits[b.name] or into < splits[b.name] then splits[b.name] = into end
        end
    end
    return { clear = best.clear, splits = splits, lead = best.lead, mine = best.mine }
end

-- What the timer shows for an open run at `now`: { elapsed, done, killed, total,
-- bosses = { { name, into, delta } } }. delta: seconds against the target's kill of the
-- same boss (negative = ahead), nil when the target has no time for it.
function RunTimer.View(run, now, target)
    local out = { bosses = {}, killed = 0, total = run.bossCount }
    local entered = run.entered or now
    out.done = run.completed and run.completedAt and true or false
    out.elapsed = math.max(0, (out.done and run.completedAt or now) - entered)
    local list = {}
    for _, b in ipairs(run.bosses or {}) do list[#list + 1] = b end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    for _, b in ipairs(list) do
        local into = math.max(0, (b.at or entered) - entered)
        local ref = target and target.splits[b.name]
        out.bosses[#out.bosses + 1] = { name = b.name or "?", into = into, delta = ref and (into - ref) or nil }
    end
    out.killed = #out.bosses
    if out.done and target then out.delta = out.elapsed - target.clear end
    -- The +/- next to the run's time, running (Austin, 2026-11-11: "so that I can push
    -- harder"). Done: the whole clear against the compared clear. Before that: where the
    -- run stood at its latest boss kill the compared run also has, and, once the clock
    -- passes the moment the compared run got its next kill (or its clear, after its
    -- last boss) without that kill here, how far behind it is now, growing each second
    -- (out.live = true). nil until there is something to compare.
    if out.delta then
        out.pace = out.delta
    elseif target then
        for i = #out.bosses, 1, -1 do
            if out.bosses[i].delta then out.pace = out.bosses[i].delta break end
        end
        local refs = {}
        for _, t in pairs(target.splits or {}) do refs[#refs + 1] = t end
        table.sort(refs)
        local nextAt = refs[out.killed + 1] or target.clear
        if nextAt and out.elapsed > nextAt then
            local behind = out.elapsed - nextAt
            if not out.pace or behind > out.pace then out.pace, out.live = behind, true end
        end
    end
    return out
end

-- "+0:22" / "-0:04" for a delta in seconds.
function RunTimer.Delta(seconds)
    local sign = seconds < 0 and "-" or "+"
    seconds = math.floor(math.abs(seconds) + 0.5)
    return string.format("%s%d:%02d", sign, math.floor(seconds / 60), seconds % 60)
end

-- "14:32" or "1:02:05" for the timer.
function RunTimer.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end
