-- Core/Leaderboard.lua
-- PURE: no WoW globals. The Dungeon Leaderboard (D-115): for each dungeon the fastest
-- clears (top 5) by you and your friends, and under it the fastest kill of each boss.
--
-- A clear is the time from entering to the final boss. One run seen by several ledgers
-- (you and a friend, or two friends, in the same group) is shown once: same dungeon,
-- final boss within MATCH_SECONDS. Its time is the longest of the reports (the first
-- one in), so joining late never makes a run faster.
-- Names: your own runs show your character and the names stored with the group (friends
-- who run the ledger, and players who opted in to being named); a friend's run shows
-- their character and the names they shared (their ledger friends only, D-115 option a).
-- Everyone else is a count ("+2").
-- At level (default): nobody in the group more than DungeonLevels.OVER above the
-- dungeon's top level; unknown levels count (Core/DungeonLevels.lua).

local _, ns = ...

local Leaderboard = {}
ns.Leaderboard = Leaderboard

Leaderboard.TOP = 5
Leaderboard.MATCH_SECONDS = 120   -- the same final-boss kill seen by two ledgers
-- Each computer has its own clock, so two reports of one run can be minutes apart. They
-- are still one run when they share someone in the group, their clear times are within
-- CLEAR_MATCH_SECONDS, and they finished less than one clear apart (two runs one after
-- the other always finish at least a clear apart), up to WIDE_MATCH_SECONDS.
Leaderboard.WIDE_MATCH_SECONDS = 1800
Leaderboard.CLEAR_MATCH_SECONDS = 120
Leaderboard.BOSS_MATCH_SECONDS = 60
Leaderboard.MIN_CLEAR = 60

local function addName(entry, name)
    if type(name) ~= "string" or name == "" then return end
    for _, n in ipairs(entry.names) do if n == name then return end end
    entry.names[#entry.names + 1] = name
end

-- Every completed run as an entry: { dungeon, clear, finishedAt, names, lead, size,
-- levelMax, mine, bosses = { { name, fight, at } } }. lead: the name shown for the
-- group (your character in your own runs, else the friend's character who reported it);
-- the rest of `names` show on hover.
-- chars: my characters (key -> character); friends: db.friends (or fake data);
-- isBlocked(friend, key); nameOf(key, char) for my characters.
function Leaderboard.Entries(chars, friends, isBlocked, nameOf)
    local out = {}
    for key, c in pairs(chars or {}) do
        local runs = {}
        for _, r in ipairs(c.dungeons or {}) do runs[#runs + 1] = r end
        if c.currentRun then runs[#runs + 1] = c.currentRun end
        for _, r in ipairs(runs) do
            local clear = (r.completed and r.completedAt and r.entered) and (r.completedAt - ns.RunTimer.Start(r)) or nil
            if clear and clear >= Leaderboard.MIN_CLEAR and r.name then
                local e = { dungeon = r.name, clear = clear, finishedAt = r.completedAt, names = {}, size = 1,
                    levelMax = r.levelMax, mine = true, bosses = {} }
                addName(e, nameOf and nameOf(key, c) or c.display or c.name or key)
                e.lead = e.names[1]
                for _, p in ipairs(r.party or {}) do
                    if not p.npc then e.size = e.size + 1 end
                    addName(e, p.name)
                end
                -- A kill without its fight length still says when the boss died (the dungeon
                -- timer's splits, D-122); the fastest-kill list uses only those with one.
                for _, b in ipairs(r.bosses or {}) do
                    if b.name and (b.fight or b.at) then e.bosses[#e.bosses + 1] = { name = b.name, fight = b.fight, at = b.at } end
                end
                out[#out + 1] = e
            end
        end
    end
    for fid, f in pairs(friends or {}) do
        for key, c in pairs(f.characters or {}) do
            if not (isBlocked and isBlocked(f, key)) then
                for _, r in ipairs(c.runs or {}) do
                    if r.completed and r.clear and r.clear >= Leaderboard.MIN_CLEAR and r.entered and r.name then
                        -- r.clear counts from the first fight, startOffset seconds after entering (D-126).
                        local e = { dungeon = r.name, clear = r.clear, finishedAt = r.entered + (r.startOffset or 0) + r.clear, names = {},
                            size = r.size or (1 + #(r.names or {})), levelMax = r.levelMax, friendId = fid, bosses = {} }
                        addName(e, c.display or c.name or key)
                        e.lead = e.names[1]
                        for _, n in ipairs(r.names or {}) do addName(e, n) end
                        for i, sp in ipairs(r.splits or {}) do
                            local bossName = r.bossNames and r.bossNames[i]
                            if bossName and bossName ~= "" and (sp.fight or sp.at) then
                                e.bosses[#e.bosses + 1] = { name = bossName, fight = sp.fight, at = r.entered + (sp.at or 0) }
                            end
                        end
                        out[#out + 1] = e
                    end
                end
            end
        end
    end
    return out
end

-- Join entries that are one run seen by several ledgers.
function Leaderboard.Merge(entries)
    table.sort(entries, function(a, b)
        if a.dungeon ~= b.dungeon then return a.dungeon < b.dungeon end
        return a.finishedAt < b.finishedAt
    end)
    local function shareName(a, b)
        for _, x in ipairs(a.names) do
            for _, y in ipairs(b.names) do if x == y then return true end end
        end
        return false
    end
    local function same(a, b)
        if a.dungeon ~= b.dungeon then return false end
        local gap = math.abs(a.finishedAt - b.finishedAt)
        if gap <= Leaderboard.MATCH_SECONDS then return true end
        return gap <= Leaderboard.WIDE_MATCH_SECONDS and gap < math.min(a.clear, b.clear)
            and math.abs(a.clear - b.clear) <= Leaderboard.CLEAR_MATCH_SECONDS and shareName(a, b)
    end
    local out = {}
    for _, e in ipairs(entries) do
        local last
        for i = #out, 1, -1 do
            if out[i].dungeon ~= e.dungeon then break end
            if same(out[i], e) then last = out[i] break end
        end
        if last then
            -- Your own report names the group after your character.
            if e.mine and not last.mine then last.lead = e.lead end
            last.clear = math.max(last.clear, e.clear)
            for _, n in ipairs(e.names) do addName(last, n) end
            last.size = math.max(last.size, e.size, #last.names)
            if e.levelMax and (not last.levelMax or e.levelMax > last.levelMax) then last.levelMax = e.levelMax end
            last.mine = last.mine or e.mine
            for _, b in ipairs(e.bosses) do last.bosses[#last.bosses + 1] = b end
        else
            e.size = math.max(e.size, #e.names)
            out[#out + 1] = e
        end
    end
    return out
end

-- The board: { { dungeon, range, clears = { top entries }, bosses = { { name, fight, entry } } } },
-- dungeons ordered by level range, then name. atLevelOnly: leave out over-level runs.
-- Each clear has `rank`. Bosses: the fastest kill of each boss, in the order bosses
-- usually die (their average time into the run).
function Leaderboard.Build(entries, atLevelOnly)
    local Ranges = ns.DungeonLevels
    local by = {}
    for _, e in ipairs(Leaderboard.Merge(entries)) do
        e.atLevel = Ranges.AtLevel(e.dungeon, e.levelMax)
        if e.atLevel or not atLevelOnly then
            by[e.dungeon] = by[e.dungeon] or {}
            table.insert(by[e.dungeon], e)
        end
    end
    local board = {}
    for name, list in pairs(by) do
        table.sort(list, function(a, b)
            if a.clear ~= b.clear then return a.clear < b.clear end
            return a.finishedAt < b.finishedAt
        end)
        local clears = {}
        for i = 1, math.min(#list, Leaderboard.TOP) do
            list[i].rank = i
            clears[i] = list[i]
        end
        -- Fastest kill per boss over every run (not only the top 5); one kill seen twice counts once.
        local best, order = {}, {}
        for _, e in ipairs(list) do
            for _, b in ipairs(e.bosses) do
                if b.fight then
                    local cur = best[b.name]
                    if not cur or b.fight < cur.fight then best[b.name] = { name = b.name, fight = b.fight, entry = e } end
                    local into = (b.at or 0) - (e.finishedAt - e.clear)
                    order[b.name] = order[b.name] or { sum = 0, n = 0 }
                    order[b.name].sum, order[b.name].n = order[b.name].sum + into, order[b.name].n + 1
                end
            end
        end
        local bosses = {}
        for _, b in pairs(best) do bosses[#bosses + 1] = b end
        table.sort(bosses, function(a, b)
            local x, y = order[a.name].sum / order[a.name].n, order[b.name].sum / order[b.name].n
            if x ~= y then return x < y end
            return a.name < b.name
        end)
        board[#board + 1] = { dungeon = name, range = Ranges.For(name), clears = clears, bosses = bosses }
    end
    table.sort(board, function(a, b)
        local x, y = a.range and a.range[1] or 999, b.range and b.range[1] or 999
        if x ~= y then return x < y end
        return a.dungeon < b.dungeon
    end)
    return board
end

-- "Austin +3": the lead name and how many others were in the group.
function Leaderboard.Group(e, L)
    local others = math.max(#e.names, e.size or 0) - 1
    local lead = e.lead or e.names[1] or "?"
    if others > 0 then return lead .. " " .. string.format(L.LEADER_MORE, others) end
    return lead
end

-- Everyone in the group, for the hover: the lead first, then the other names, then
-- "and 2 others" for players nobody named.
function Leaderboard.Members(e, L)
    local lines = { e.lead or e.names[1] or "?" }
    for _, n in ipairs(e.names) do if n ~= lines[1] then lines[#lines + 1] = n end end
    local unnamed = (e.size or #e.names) - #e.names
    if unnamed > 0 then lines[#lines + 1] = string.format(unnamed == 1 and L.LEADER_UNNAMED_ONE or L.LEADER_UNNAMED, unnamed) end
    return lines
end

-- Where a new run of mine landed: its rank on its dungeon's board (at level), or nil
-- when outside the top TOP. finishedAt: the run's final-boss time.
function Leaderboard.RankOf(board, dungeon, finishedAt)
    for _, d in ipairs(board) do
        if d.dungeon == dungeon then
            for _, e in ipairs(d.clears) do
                if math.abs(e.finishedAt - finishedAt) <= Leaderboard.MATCH_SECONDS then return e.rank, e end
            end
        end
    end
    return nil
end
