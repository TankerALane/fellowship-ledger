-- UI/DungeonsModel.lua
-- PURE: no WoW globals. The Dungeons tab (D-094, redrawn in 1.14.0, D-140): a summary
-- per dungeon, my runs (from each character's saved runs), and friends' totals
-- (friends share day counts only, so their runs are counted, not listed). Builds the tab's lines as
-- "grid" lines for UI/Table.lua, like UI/DetailModel.lua.

local _, ns = ...

local DungeonsModel = {}
ns.DungeonsModel = DungeonsModel

-- 2523 -> "42m", 3700 -> "1h 01m", nil -> "-"
function DungeonsModel.Minutes(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "-" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return m .. "m" end
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

-- 45 -> "0:45", 1450 -> "24:10", 3725 -> "1:02:05", nil -> "-" (boss times, D-104)
function DungeonsModel.Clock(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return "-" end
    seconds = math.floor(seconds + 0.5)
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- Clear time (D-104): the first fight (D-126; entering, for older runs) to the kill that completed the run. Friends send it
-- as run.clear (1.7.0+). nil when the run was not completed by its final boss.
function DungeonsModel.ClearTime(run)
    if not run or not run.completed then return nil end
    if run.clear then return run.clear end
    local start = ns.RunTimer.Start(run)
    if run.completedAt and start and run.completedAt >= start then return run.completedAt - start end
    return nil
end

-- Runs of my characters (charKey nil = all), entered on or after fromKey (nil = all),
-- newest first. An ongoing run that already counts is included as in progress.
-- Returns { { charKey, char, run, live = bool } }.
function DungeonsModel.Runs(chars, charKey, fromKey, dateFn, now)
    local out = {}
    for key, c in pairs(chars or {}) do
        if not charKey or key == charKey then
            local function add(run, live)
                if run and run.entered and (not fromKey or dateFn("%Y-%m-%d", run.entered) >= fromKey) then
                    out[#out + 1] = { charKey = key, char = c, run = run, live = live or nil }
                end
            end
            for _, run in ipairs(c.dungeons or {}) do add(run) end
            local cur = c.currentRun
            if cur and not cur.pending then add(cur, true) end
        end
    end
    table.sort(out, function(a, b)
        if a.run.entered ~= b.run.entered then return a.run.entered > b.run.entered end
        return tostring(a.charKey) < tostring(b.charKey)
    end)
    return out
end

local function durationOf(e, now)
    if e.live then return (e.run.lastSeen or now or e.run.entered) - e.run.entered end
    return e.run.duration
end

-- The Time column (Austin, 2026-11-11): the clear time (entering to the final boss)
-- once the final boss is dead, so it stops there; before that, and for a run not
-- completed, the time inside.
-- Why a run is not timed from the start (D-127): "* Not timed from the start: <reason>".
function DungeonsModel.PartialText(code, L)
    local why = L["PARTIAL_" .. tostring(code):upper()] or L.PARTIAL_UNKNOWN
    return string.format(L.PARTIAL_TIP, why)
end

function DungeonsModel.TimeText(run, inside)
    local clear = DungeonsModel.ClearTime(run)
    if clear then return DungeonsModel.Clock(clear) .. (run.partial and "*" or "") end
    return DungeonsModel.Minutes(inside)
end

function DungeonsModel.Summary(runs)
    local s = { runs = #runs, completed = 0, bosses = 0, deaths = 0 }
    for _, e in ipairs(runs) do
        if e.run.completed then s.completed = s.completed + 1 end
        s.bosses = s.bosses + #(e.run.bosses or {})
        s.deaths = s.deaths + (e.run.deaths or 0)
    end
    return s
end

-- One row per dungeon name: runs, completed, best (fastest completed), average
-- (finished runs), last entered. Most recently run first.
function DungeonsModel.ByDungeon(runs, now)
    local by, list = {}, {}
    for _, e in ipairs(runs) do
        local name = e.run.name or "?"
        local d = by[name]
        if not d then
            d = { name = name, runs = 0, completed = 0, total = 0, timed = 0, last = 0, deaths = 0, entries = {} }
            by[name] = d
            list[#list + 1] = d
        end
        d.runs = d.runs + 1
        -- 1.14.0: deaths, the boss count and the runs themselves (newest first, as given).
        d.deaths = d.deaths + (tonumber(e.run.deaths) or 0)
        if e.run.bossCount and (not d.bossCount or e.run.bossCount > d.bossCount) then d.bossCount = e.run.bossCount end
        d.entries[#d.entries + 1] = e
        local dur = durationOf(e, now)
        if e.run.completed then
            d.completed = d.completed + 1
            -- Best = fastest clear (entering to the final boss), else time inside (D-104).
            local t = DungeonsModel.ClearTime(e.run) or dur
            if t and (not d.best or t < d.best) then d.best = t end
            -- Average: of the clear times too, like the Time column (Austin, 2026-11-11).
            if t then d.total, d.timed = d.total + t, d.timed + 1 end
        end
        if e.run.entered > d.last then d.last = e.run.entered end
    end
    for _, d in ipairs(list) do d.average = d.timed > 0 and d.total / d.timed or nil end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return list
end

-- Your own role in a run: the saved one (1.13.2+), else, in a full group of five whose
-- other four are one short of 1 tank, 1 healer and 3 damage, the missing one
-- (guessed = true). nil when it cannot be told.
function DungeonsModel.MyRole(run)
    if not run then return nil end
    if run.role then return run.role, false end
    local party = run.party or {}
    if #party ~= 4 then return nil end
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, p in ipairs(party) do
        if not n[p.role or ""] then return nil end
        n[p.role] = n[p.role] + 1
    end
    if n.TANK == 0 and n.HEALER == 1 and n.DAMAGER == 3 then return "TANK", true end
    if n.TANK == 1 and n.HEALER == 0 and n.DAMAGER == 3 then return "HEALER", true end
    if n.TANK == 1 and n.HEALER == 1 and n.DAMAGER == 2 then return "DAMAGER", true end
    return nil
end

-- "1 tank, 1 healer, 2 damage"; "solo" with nobody else. With `me` (your role), you
-- are counted too (Austin, 2026-11-15).
function DungeonsModel.Group(party, L, me)
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0, other = 0 }
    if n[me or ""] and #(party or {}) > 0 then n[me] = n[me] + 1 end
    for _, p in ipairs(party or {}) do
        local r = p.role
        if n[r] then n[r] = n[r] + 1 else n.other = n.other + 1 end
    end
    local parts = {}
    if n.TANK > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_TANKS, n.TANK) end
    if n.HEALER > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_HEALERS, n.HEALER) end
    if n.DAMAGER > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_DAMAGE, n.DAMAGER) end
    if n.other > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_OTHERS, n.other) end
    if #parts == 0 then return L.DUNGEONS_SOLO end
    return table.concat(parts, ", ")
end

-- Bosses in kill order with the time into the run (from its first fight, D-126); the one that completed the run
-- is marked final.
function DungeonsModel.Bosses(run)
    local list = {}
    local start = ns.RunTimer.Start(run) or run.entered
    for i, b in ipairs(run.bosses or {}) do
        list[i] = { n = i, name = b.name or "?", offset = b.at and start and math.max(0, b.at - start) or nil, at = b.at,
            fight = b.fight }
    end
    if run.completed and run.completedBy == "lastBoss" and #list > 0 then
        local final = list[#list]
        for _, b in ipairs(list) do
            if run.completedAt and b.at == run.completedAt then final = b end
        end
        final.final = true
    end
    return list
end

-- Friends' totals over the range, from their shared day counts: one row per
-- character that entered a dungeon or killed a boss. Blocked friends are left out.
function DungeonsModel.FriendRows(friends, isBlocked, fromKey, todayKey)
    local out = {}
    for id, f in pairs(friends or {}) do
        if not (isBlocked and isBlocked(f)) then
            for key, c in pairs(f.characters or {}) do
                if not (isBlocked and isBlocked(f, key)) then
                    local e, d, b = 0, 0, 0
                    for day, v in pairs(c.days or {}) do
                        if (not fromKey or day >= fromKey) and (not todayKey or day <= todayKey) then
                            e, d, b = e + (v.dungeonsEntered or 0), d + (v.dungeonsCompleted or 0), b + (v.bossKills or 0)
                        end
                    end
                    if e > 0 or b > 0 then
                        out[#out + 1] = { friend = f.name or id, name = c.display or c.name or key, class = c.class,
                            entered = e, completed = d, bosses = b }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.friend ~= b.friend then return string.lower(a.friend) < string.lower(b.friend) end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return out
end

-- Friends' fastest clear per dungeon over the range (D-104), from their shared runs
-- (clear time from 1.7.0+, else time inside): { [dungeon] = { time, friend, name } }.
function DungeonsModel.FriendBest(friends, isBlocked, fromKey, dateFn)
    local best = {}
    for id, f in pairs(friends or {}) do
        if not (isBlocked and isBlocked(f)) then
            for key, c in pairs(f.characters or {}) do
                if not (isBlocked and isBlocked(f, key)) then
                    for _, r in ipairs(c.runs or {}) do
                        if r.completed and r.name and r.entered and (not fromKey or dateFn("%Y-%m-%d", r.entered) >= fromKey) then
                            local t = DungeonsModel.ClearTime(r) or r.duration
                            local b = best[r.name]
                            if t and t > 0 and (not b or t < b.time) then
                                best[r.name] = { time = t, friend = f.name or id, name = c.display or c.name or key }
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Lines (1.14.0, D-140) ----------------------------------------------------------
-- The tab has three views: By dungeon and Runs are a list on the left and the chosen
-- one on the right (like Quest chains); Friends is the friends' totals.

local function seg(x, w, text, role, font, align)
    return { x = x, w = w, text = text, role = role, font = font, align = align }
end

DungeonsModel.VIEWS = { "dungeons", "runs", "friends" }
DungeonsModel.RECENT = 4 -- runs listed under a dungeon

function DungeonsModel.RunKey(e) return tostring(e.charKey) .. "|" .. tostring(e.run.entered) end

-- "1st", "2nd", ... (a place on the Leaderboard's top 5).
function DungeonsModel.Ordinal(n, L)
    return rawget(L, "DUNGEONS_ORD_" .. tostring(n)) or ("#" .. tostring(n))
end

-- Your place on a dungeon's board (Leaderboard.Build): the rank of your fastest clear, or nil.
function DungeonsModel.MyRank(board)
    for _, e in ipairs(board and board.clears or {}) do
        if e.mine then return e.rank end
    end
    return nil
end

local function resultOf(e, L)
    if e.run.completed then return L.DUNGEONS_COMPLETED, "good" end
    if e.live then return L.DUNGEONS_IN_PROGRESS, "muted" end
    return L.DUNGEONS_NOT_DONE, "muted"
end

local function bossText(run)
    local n = #(run.bosses or {})
    return run.bossCount and (n .. " / " .. run.bossCount) or tostring(n)
end

-- Tiles as two lines: small titles, then the figures. tiles: { { label, value, role } }.
local function tileLines(out, tiles)
    local w = 1 / #tiles
    local labels, values = {}, {}
    for i, t in ipairs(tiles) do
        labels[#labels + 1] = seg((i - 1) * w, w - .02, t[1], "section", "small")
        values[#values + 1] = seg((i - 1) * w, w - .02, t[2], t[3] or "text", "number")
    end
    out[#out + 1] = { kind = "grid", height = 16, segments = labels }
    out[#out + 1] = { kind = "grid", height = 26, segments = values }
end

local function section(out, text)
    out[#out + 1] = { kind = "grid", height = 8, segments = {} }
    out[#out + 1] = { kind = "grid", height = 18, segments = { seg(0, 1, text, "section", "small") } }
end

-- The list of dungeons. by: ByDungeon; boards: { [dungeon] = Leaderboard board entry };
-- opts: { onSelect = fn(name) }.
function DungeonsModel.DungeonListLines(by, boards, selected, L, opts)
    local out = {}
    for _, d in ipairs(by or {}) do
        local chosen = d.name == selected
        local click = function() if opts.onSelect then opts.onSelect(d.name) end end
        local rank = DungeonsModel.MyRank(boards and boards[d.name])
        local range = ns.DungeonLevels.For(d.name)
        local sub = string.format(d.runs == 1 and L.DUNGEONS_LIST_RUN or L.DUNGEONS_LIST_RUNS, d.runs, d.completed)
        if range then sub = string.format(L.DUNGEONS_LEVELS, range[1], range[2]) .. "  -  " .. sub end
        local rankText = rank and (rank == 1 and L.DUNGEONS_RANK_TOP or string.format(L.DUNGEONS_RANK, DungeonsModel.Ordinal(rank, L))) or ""
        out[#out + 1] = { kind = "grid", shade = chosen or nil, onClick = click, dungeon = d.name,
            segments = { seg(.03, .64, d.name, chosen and "heading" or "text"),
                seg(.67, .31, d.best and DungeonsModel.Clock(d.best) or "-", "text", nil, "RIGHT") } }
        out[#out + 1] = { kind = "grid", shade = chosen or nil, onClick = click, height = 16, dungeon = d.name,
            segments = { seg(.03, .55, sub, "muted", "small"),
                { x = .60, w = .12, bar = d.runs > 0 and d.completed / d.runs or 0, track = true, barRole = "good", barH = 4 },
                seg(.74, .24, rankText, rank == 1 and "heading" or "muted", "small", "RIGHT") } }
        out[#out + 1] = { kind = "grid", height = 6, segments = {} }
    end
    if #out == 0 then out[1] = { kind = "grid", segments = { seg(.03, .94, L.DUNGEONS_NO_RUNS, "muted") } } end
    return out
end

-- The fastest of my runs of a dungeon (completed, by clear time).
local function bestRun(entries)
    local best, bestT
    for _, e in ipairs(entries or {}) do
        local t = DungeonsModel.ClearTime(e.run)
        if t and (not bestT or t < bestT) then best, bestT = e, t end
    end
    return best, bestT
end

-- The right pane for one dungeon. d: a ByDungeon row; o: { L, board, leader (a
-- RunTimer.Target for #1), entries (my runs of it, newest first), nameOf, dateFn,
-- onRun = fn(runKey), onAllRuns = fn() }.
function DungeonsModel.DungeonDetailLines(d, o)
    local L = o.L
    local nameOf = o.nameOf or function(t) return t end
    local when = function(t) return t and o.dateFn("%m-%d %H:%M", t) or "" end
    local out = {}
    if not d then
        out[1] = { kind = "grid", segments = { seg(0, 1, L.DUNGEONS_PICK, "muted") } }
        return out
    end
    out[#out + 1] = { kind = "grid", height = 24, segments = { seg(0, .65, d.name, "heading", "large"),
        seg(.65, .35, string.format(L.DUNGEONS_LAST_RUN, when(d.last)), "muted", "small", "RIGHT") } }
    local range = ns.DungeonLevels.For(d.name)
    local sub = {}
    if range then sub[#sub + 1] = string.format(L.DUNGEONS_LEVELS, range[1], range[2]) end
    if d.bossCount then sub[#sub + 1] = string.format(L.DUNGEONS_BOSS_COUNT, d.bossCount) end
    out[#out + 1] = { kind = "grid", height = 16, segments = { seg(0, 1, table.concat(sub, "  -  "), "muted", "small") } }
    out[#out + 1] = { kind = "grid", height = 8, segments = {} }
    tileLines(out, { { L.DUNGEONS_T_RUNS, tostring(d.runs) }, { L.DUNGEONS_T_CLEARED, tostring(d.completed), "good" },
        { L.DUNGEONS_T_BEST, d.best and DungeonsModel.Clock(d.best) or "-", "heading" },
        { L.DUNGEONS_T_AVERAGE, d.average and DungeonsModel.Clock(d.average) or "-" },
        { L.DUNGEONS_T_DEATHS, tostring(d.deaths or 0), (d.deaths or 0) > 0 and "bad" or "text" } })

    -- The Leaderboard's fastest clears here (at level), you among them.
    section(out, L.DUNGEONS_FASTEST)
    local clears = o.board and o.board.clears or {}
    if #clears == 0 then
        out[#out + 1] = { kind = "grid", segments = { seg(0, 1, L.DUNGEONS_NO_CLEARS, "muted") } }
    else
        local slowest = 0
        for _, e in ipairs(clears) do if e.clear > slowest then slowest = e.clear end end
        for _, e in ipairs(clears) do
            out[#out + 1] = { kind = "grid", segments = {
                seg(0, .06, "#" .. tostring(e.rank), e.rank == 1 and "heading" or "muted", nil, "RIGHT"),
                seg(.09, .32, ns.Leaderboard.Group(e, L), e.mine and "good" or "text"),
                { x = .43, w = .40, bar = slowest > 0 and e.clear / slowest or 0, track = true,
                    barRole = e.rank == 1 and "accent" or (e.mine and "good" or "muted"), barH = 6 },
                seg(.85, .15, DungeonsModel.Clock(e.clear) .. (e.partial and "*" or ""), "text", nil, "RIGHT") } }
        end
    end
    -- 1.14.1: your best clear beats a place on the list but is not on it: it was over
    -- level (someone more than DungeonLevels.OVER above the dungeon).
    local mineListed, slowest = false, 0
    for _, e in ipairs(clears) do
        if e.mine then mineListed = true end
        if e.clear > slowest then slowest = e.clear end
    end
    if d.best and not mineListed and (#clears < 5 or d.best < slowest) then
        out[#out + 1] = { kind = "grid", height = 16, segments = { seg(.09, .91,
            string.format(L.DUNGEONS_BEST_OVER, DungeonsModel.Clock(d.best), ns.DungeonLevels.OVER), "muted", "small") } }
    end

    -- Your best run boss by boss, against #1.
    local best = bestRun(o.entries)
    if best and #(best.run.bosses or {}) > 0 then
        section(out, L.DUNGEONS_BEST_SPLITS)
        local leader = o.leader
        local same = leader and leader.mine and leader.clear == DungeonsModel.ClearTime(best.run)
        for _, b in ipairs(DungeonsModel.Bosses(best.run)) do
            -- 1.14.1: by kill number (routes differ); an extra after the final boss by name.
            local doneAt = best.run.completedAt
            local extra = doneAt and b.at and b.at > doneAt + 1 or false
            local ref = (leader and not same and b.offset) and ns.RunTimer.RefFor(leader, b.n, b.name, b.final, extra)
            local delta = ref and (b.offset - ref) or nil
            out[#out + 1] = { kind = "grid", segments = {
                seg(0, .06, tostring(b.n), "muted", nil, "RIGHT"),
                seg(.09, .55, b.name, b.final and "good" or "text"),
                seg(.64, .16, b.offset and DungeonsModel.Clock(b.offset) or "-", "muted", nil, "RIGHT"),
                seg(.82, .18, delta and ns.RunTimer.Delta(delta) or "", delta and (delta < 0 and "good" or delta > 0 and "bad" or "muted") or "muted",
                    nil, "RIGHT") } }
        end
        local note
        if same then note = L.DUNGEONS_SPLITS_TOP
        elseif leader then note = string.format(L.DUNGEONS_SPLITS_VS, leader.lead or "?", DungeonsModel.Clock(leader.clear)) end
        if note then out[#out + 1] = { kind = "grid", height = 16, segments = { seg(.09, .91, note, "muted", "small") } } end
    end

    -- Your recent runs here; a click opens one in Runs.
    local entries = o.entries or {}
    if #entries > 0 then
        section(out, L.DUNGEONS_RECENT)
        for i = 1, math.min(#entries, DungeonsModel.RECENT) do
            local e = entries[i]
            local c = e.char or {}
            local result, role = resultOf(e, L)
            local key = DungeonsModel.RunKey(e)
            out[#out + 1] = { kind = "grid", shade = i % 2 == 0 or nil,
                onClick = o.onRun and function() o.onRun(key) end or nil, segments = {
                seg(0, .20, when(e.run.entered), "muted"),
                seg(.21, .27, nameOf(c.display or c.name or e.charKey, c.class)),
                seg(.49, .14, bossText(e.run), "muted", nil, "RIGHT"),
                seg(.64, .14, DungeonsModel.TimeText(e.run, e.run.duration), "text", nil, "RIGHT"),
                seg(.80, .20, result, role, nil, "RIGHT") } }
        end
        if #entries > DungeonsModel.RECENT and o.onAllRuns then
            out[#out + 1] = { kind = "grid", height = 18, onClick = o.onAllRuns,
                segments = { seg(0, 1, string.format(L.DUNGEONS_ALL_RUNS, #entries), "heading", "small", "RIGHT") } }
        end
    end
    return out
end

-- The list of runs (Runs, newest first): two lines each with a stripe, green when cleared.
function DungeonsModel.RunListLines(runs, selected, L, opts)
    local out = {}
    local nameOf = opts.nameOf or function(t) return t end
    local when = function(t) return t and opts.dateFn("%m-%d %H:%M", t) or "" end
    for _, e in ipairs(runs or {}) do
        local key = DungeonsModel.RunKey(e)
        local chosen = key == selected
        local click = function() if opts.onSelect then opts.onSelect(key) end end
        local c = e.char or {}
        local stripe = e.run.completed and "good" or "muted"
        local deaths = tonumber(e.run.deaths) or 0
        out[#out + 1] = { kind = "grid", shade = chosen or nil, onClick = click, runKey = key, segments = {
            { x = 0, w = .012, bar = 1, barRole = stripe, barH = 20 },
            seg(.04, .64, e.run.name or "?", chosen and "heading" or "text"),
            seg(.68, .30, DungeonsModel.TimeText(e.run, durationOf(e, opts.now)), "text", nil, "RIGHT") } }
        out[#out + 1] = { kind = "grid", shade = chosen or nil, onClick = click, runKey = key, height = 16, segments = {
            { x = 0, w = .012, bar = 1, barRole = stripe, barH = 16 },
            seg(.04, .28, nameOf(c.display or c.name or e.charKey, c.class), "text", "small"),
            seg(.32, .24, when(e.run.entered), "muted", "small"),
            seg(.56, .26, string.format(L.DUNGEONS_BOSSES_SHORT, bossText(e.run)), "muted", "small", "RIGHT"),
            seg(.83, .15, deaths > 0 and string.format(L.DUNGEONS_DEATHS_SHORT, deaths) or "", "bad", "small", "RIGHT") } }
        out[#out + 1] = { kind = "grid", height = 4, segments = {} }
    end
    if #out == 0 then out[1] = { kind = "grid", segments = { seg(.04, .94, L.DUNGEONS_NO_RUNS, "muted") } } end
    return out
end

-- The right pane for one run. e: a Runs entry; o: { L, nameOf, dateFn, now, best (your
-- fastest other clear of this dungeon, seconds, or nil) }.
function DungeonsModel.RunDetailLines(e, o)
    local L = o.L
    local nameOf = o.nameOf or function(t) return t end
    local out = {}
    if not e then
        out[1] = { kind = "grid", segments = { seg(0, 1, L.DUNGEONS_PICK_RUN, "muted") } }
        return out
    end
    local run, c = e.run, e.char or {}
    local result, role = resultOf(e, L)
    out[#out + 1] = { kind = "grid", height = 24, segments = { seg(0, .70, run.name or "?", "heading", "large"),
        seg(.70, .30, ns.Format.Upper(result), role, "small", "RIGHT") } }
    local dur = durationOf(e, o.now)
    local sub = { nameOf(c.display or c.name or e.charKey, c.class), run.entered and o.dateFn("%Y-%m-%d %H:%M", run.entered) or "",
        string.format(L.DUNGEONS_INSIDE, DungeonsModel.Minutes(dur)) }
    out[#out + 1] = { kind = "grid", height = 16, segments = { seg(0, 1, table.concat(sub, "  -  "), "muted", "small") } }
    if run.partial then
        out[#out + 1] = { kind = "grid", height = 16, segments = { seg(0, 1, DungeonsModel.PartialText(run.partial, L), "muted", "small") } }
    end
    out[#out + 1] = { kind = "grid", height = 8, segments = {} }
    local clear = DungeonsModel.ClearTime(run)
    local vs, vsRole = "-", "muted"
    if clear and o.best then
        local d = clear - o.best
        vs, vsRole = ns.RunTimer.Delta(d), d < 0 and "good" or d > 0 and "bad" or "text"
    end
    local deaths = tonumber(run.deaths) or 0
    tileLines(out, { { clear and L.DUNGEONS_T_CLEARED_IN or L.DUNGEONS_T_INSIDE, clear and DungeonsModel.Clock(clear) or DungeonsModel.Minutes(dur),
            clear and "good" or "text" },
        { L.DUNGEONS_T_VS_BEST, vs, vsRole }, { L.DUNGEONS_T_BOSSES, bossText(run) },
        { L.DUNGEONS_T_DEATHS, tostring(deaths), deaths > 0 and "bad" or "text" } })

    local list = DungeonsModel.Bosses(run)
    if #list == 0 then
        section(out, L.DUNGEONS_BOSS_HEAD)
        out[#out + 1] = { kind = "grid", segments = { seg(0, 1, L.DUNGEONS_NO_BOSSES, "muted") } }
    else
        -- The run from its start to the final boss: a stretch per boss, the times under it.
        local total = clear or dur or 0
        for _, b in ipairs(list) do if b.offset and b.offset > total then total = b.offset end end
        if total > 0 then
            section(out, L.DUNGEONS_TIMELINE_HEAD)
            local bars, labels, prev = {}, {}, 0
            labels[1] = seg(0, .12, "0:00", "muted", "small")
            for i, b in ipairs(list) do
                if b.offset then
                    local x = math.min(1, b.offset / total)
                    if x - prev > .006 then
                        bars[#bars + 1] = { x = prev, w = x - prev - .004, bar = 1, barRole = i % 2 == 1 and "accent" or "muted", barH = 8 }
                    end
                    labels[#labels + 1] = seg(math.max(.12, x - .12), .12, DungeonsModel.Clock(b.offset), b.final and "good" or "text",
                        "small", "RIGHT")
                    prev = x
                end
            end
            if 1 - prev > .006 then bars[#bars + 1] = { x = prev, w = 1 - prev, bar = 1, track = true, barRole = "muted", barH = 8 } end
            out[#out + 1] = { kind = "grid", height = 14, segments = bars }
            out[#out + 1] = { kind = "grid", height = 16, segments = labels }
            out[#out + 1] = { kind = "grid", height = 16, segments = { seg(0, 1, L.DUNGEONS_TIMELINE_NOTE, "muted", "small") } }
        end
        section(out, L.DUNGEONS_BOSS_HEAD)
        out[#out + 1] = { kind = "grid", height = 16, rules = { { 0, 1 } }, segments = {
            seg(.09, .40, L.DUNGEONS_BOSS, "muted", "small"), seg(.50, .14, L.DUNGEONS_KILLED_AT, "muted", "small", "RIGHT"),
            seg(.65, .12, L.DUNGEONS_FIGHT, "muted", "small", "RIGHT") } }
        local longest = 0
        for _, b in ipairs(list) do if (b.fight or 0) > longest then longest = b.fight end end
        for _, b in ipairs(list) do
            out[#out + 1] = { kind = "grid", segments = {
                seg(0, .06, tostring(b.n), "muted", nil, "RIGHT"),
                seg(.09, .40, b.final and (b.name .. "  -  " .. L.DUNGEONS_FINAL) or b.name, b.final and "good" or "text"),
                seg(.50, .14, b.offset and DungeonsModel.Clock(b.offset) or "", "muted", nil, "RIGHT"),
                seg(.65, .12, b.fight and DungeonsModel.Clock(b.fight) or "-", b.fight and "text" or "muted", nil, "RIGHT"),
                { x = .80, w = .20, bar = (b.fight and longest > 0) and b.fight / longest or 0, track = true,
                    barRole = b.final and "good" or "accent", barH = 6 } } }
        end
    end

    -- The group: you and the others, with their roles.
    local members = {}
    local me = DungeonsModel.MyRole(run)
    members[#members + 1] = { name = L.DUNGEONS_YOU, class = c.class, role = me }
    for _, p in ipairs(run.party or {}) do
        if not p.npc then
            members[#members + 1] = { name = p.name or (p.class and rawget(L, "CLASS_" .. p.class)) or L.DUNGEONS_SOMEONE, class = p.class, role = p.role }
        end
    end
    if #members > 1 then
        section(out, L.DUNGEONS_GROUP)
        local segs, w = {}, 1 / 5
        for i = 1, math.min(#members, 5) do
            local m = members[i]
            local short = m.role and rawget(L, "DUNGEONS_ROLE_SHORT_" .. m.role)
            segs[#segs + 1] = seg((i - 1) * w, w - .01, (short and (short .. "  ") or "") .. nameOf(m.name, m.class), "text")
        end
        local roleName = me and rawget(L, "DUNGEONS_ROLE_" .. me)
        local _, guessed = DungeonsModel.MyRole(run)
        out[#out + 1] = { kind = "grid", segments = segs, tooltip = roleName and function()
            return L.DUNGEONS_GROUP, { string.format(guessed and L.DUNGEONS_TIP_ROLE_GUESS or L.DUNGEONS_TIP_ROLE, roleName) }
        end or nil }
    end
    return out
end

-- The Friends view: each friend's dungeons over the range, from their shared day counts.
DungeonsModel.FRIEND_COLS = { { 0, .20 }, { .20, .30 }, { .50, .15, "RIGHT" }, { .65, .15, "RIGHT" }, { .80, .15, "RIGHT" } }
function DungeonsModel.FriendLines(o)
    local L = o.L
    local nameOf = o.nameOf or function(t) return t end
    local out = {}
    local function row(texts, role, font)
        local segs = {}
        for i, c in ipairs(DungeonsModel.FRIEND_COLS) do segs[#segs + 1] = seg(c[1], c[2], texts[i], role, font, c[3]) end
        return segs
    end
    local fr = DungeonsModel.FriendRows(o.friends, o.isBlocked, o.fromKey, o.todayKey)
    if #fr == 0 then
        out[#out + 1] = { kind = "detail", text = L.DUNGEONS_NO_FRIENDS }
    else
        out[#out + 1] = { kind = "grid", rules = { { 0, 1 } },
            segments = row({ L.DCOL_FRIEND, L.DCOL_CHARACTER, L.DCOL_ENTERED, L.DCOL_COMPLETED, L.DCOL_BOSSES }, "muted", "small") }
        for i, f in ipairs(fr) do
            out[#out + 1] = { kind = "grid", shade = i % 2 == 0,
                segments = row({ f.friend, nameOf(f.name, f.class), tostring(f.entered), tostring(f.completed), tostring(f.bosses) }) }
        end
        out[#out + 1] = { kind = "detail", text = L.DUNGEONS_FRIENDS_NOTE }
    end
    out[#out + 1] = { kind = "detail", text = L.DUNGEONS_FOOTER }
    return out
end
