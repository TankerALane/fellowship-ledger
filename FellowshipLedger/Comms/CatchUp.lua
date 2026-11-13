-- Comms/CatchUp.lua
-- PURE: no WoW globals. Catching up between computers (D-128): addon data lives in a
-- file on each computer, so play on a second computer never reaches the first. Friends
-- hold a copy of what each of your characters shares, so they hand it back.
--
--   A -> B  REQUEST with "m" records: a hash of each of my own characters and how fresh
--           my copy is (lastSeen as it was at login), sent once per session per friend
--   B -> A  CATCHUP (type C) for each character B holds of mine that is newer than mine,
--           or that I do not have at all
--   A       merges it into my own ledger: what is missing is added, nothing is replaced,
--           so my own data on this computer always wins and nothing counts twice
--
-- Only the friend's copy of the asker's own characters goes back, and only to the
-- asker (B keys its copy by the peer the data came from), so nobody else's data moves.

local _, ns = ...

local CatchUp = {}
ns.CatchUp = CatchUp

CatchUp.MAX_MINE = 50 -- my characters listed in one REQUEST
CatchUp.MAX_SEND = 20 -- characters sent back in answer to one REQUEST

-- My characters for a REQUEST: { { hash, lastSeen } }. seenAtLogin: key -> lastSeen
-- before this session began (the played character's moves on every minute, and its
-- live updates reach friends, so its time now would hide the other computer's play).
function CatchUp.Mine(characters, seenAtLogin)
    local list = {}
    for key, c in pairs(characters or {}) do
        -- A character new this session (first login on this computer) had nothing before.
        local seen
        if seenAtLogin then seen = seenAtLogin[key] or 0 else seen = c.lastSeen end
        list[#list + 1] = { hash = ns.Relay.Hash(key), lastSeen = math.floor(tonumber(seen) or 0) }
    end
    table.sort(list, function(a, b)
        if a.lastSeen == b.lastSeen then return a.hash < b.hash end
        return a.lastSeen > b.lastSeen
    end)
    while #list > CatchUp.MAX_MINE do table.remove(list) end
    return list
end

-- What to send back to a friend who asked: friend = my record of them (their own
-- characters as I hold them); mine = { [hash] = lastSeen } from their REQUEST. A
-- character they listed goes back when my copy is newer; one they did not list (a
-- character only ever played on another computer) goes back too. Returns
-- { { key, char, theirs } } (theirs nil when they did not list it), newest first.
function CatchUp.Pick(friend, mine)
    local out = {}
    if not (friend and mine) then return out end
    for key, c in pairs(friend.characters or {}) do
        local seen = mine[ns.Relay.Hash(key)]
        if type(c.lastSeen) == "number" and c.lastSeen > 0 and (seen == nil or c.lastSeen > seen) then
            out[#out + 1] = { key = key, char = c, theirs = seen }
        end
    end
    table.sort(out, function(a, b)
        if a.char.lastSeen == b.char.lastSeen then return a.key < b.key end
        return a.char.lastSeen > b.char.lastSeen
    end)
    while #out > CatchUp.MAX_SEND do table.remove(out) end
    return out
end

-- One day's counts: a field I do not have is taken; one both have keeps the larger
-- (by size, so a day's net gold can be a loss). Both computers' copies of a day hold
-- only what that computer saw, so this never counts anything twice; a day played on
-- both computers keeps the bigger half of each count.
local function mergeCounts(own, theirs)
    local added = false
    for field, v in pairs(theirs or {}) do
        local o = own[field]
        if type(v) == "number" and (type(o) ~= "number" or math.abs(v) > math.abs(o)) then
            own[field] = v
            added = true
        end
    end
    return added
end

local function sortBy(list, field)
    table.sort(list, function(a, b) return (a[field] or 0) < (b[field] or 0) end)
end

-- Merge a friend's copy of my character (Codec.DecodeData) into my own char table.
-- Returns what was added: { days, levels, runs, deaths, loot, sessions } (counts).
function CatchUp.Merge(char, data)
    local got = { days = 0, levels = 0, runs = 0, deaths = 0, loot = 0, sessions = 0 }
    local copy = ns.Relay.AsOwn(data) -- runs and loot in our own shape

    char.class = char.class or data.class
    char.race = char.race or data.race
    char.faction = char.faction or data.faction
    if type(data.level) == "number" and data.level > (char.level or 0) then char.level = data.level end

    char.days = char.days or {}
    for day, counts in pairs(data.days or {}) do
        if not char.days[day] then char.days[day] = {} end
        if mergeCounts(char.days[day], counts) then got.days = got.days + 1 end
    end

    char.levels = char.levels or {}
    for to, r in pairs(data.levels or {}) do
        if not char.levels[to] then
            char.levels[to] = { from = r.from, to = r.to, active = r.active, total = r.total, partial = r.partial, at = r.at }
            got.levels = got.levels + 1
        end
    end
    if data.levelXP then
        char.levelXP = char.levelXP or {}
        for level, t in pairs(data.levelXP) do
            if not char.levelXP[level] then char.levelXP[level] = t end
        end
    end
    if data.professions and next(char.professions or {}) == nil then char.professions = data.professions end

    -- Dungeon runs: one I have no run at that time for (none overlapping, and not the
    -- run I am in now).
    char.dungeons = char.dungeons or {}
    local mineRuns = {}
    for _, r in ipairs(char.dungeons) do mineRuns[#mineRuns + 1] = r end
    if char.currentRun then mineRuns[#mineRuns + 1] = char.currentRun end
    local function overlaps(e)
        for _, r in ipairs(mineRuns) do
            if r.entered and (r.entered == e or (e >= r.entered and e <= r.entered + (r.duration or 0))) then return true end
        end
        return false
    end
    for _, run in ipairs(copy.dungeons or {}) do
        if run.entered and not overlaps(run.entered) then
            run.recovered = true
            char.dungeons[#char.dungeons + 1] = run
            mineRuns[#mineRuns + 1] = run
            got.runs = got.runs + 1
        end
    end
    sortBy(char.dungeons, "entered")

    local function addMissing(list, new, keyOf, counter)
        local have = {}
        for _, e in ipairs(list) do have[keyOf(e)] = true end
        for _, e in ipairs(new or {}) do
            local k = keyOf(e)
            if e.at and not have[k] then
                have[k] = true
                list[#list + 1] = e
                got[counter] = got[counter] + 1
            end
        end
        sortBy(list, "at")
    end
    char.deathLog = char.deathLog or {}
    addMissing(char.deathLog, data.deathLog, function(e) return tostring(e.at) end, "deaths")
    char.items = char.items or {}
    local function itemKey(e)
        local id = type(e.link) == "string" and e.link:match("item:(%d+)") or "?"
        return tostring(e.at) .. ":" .. id
    end
    addMissing(char.items, copy.items, itemKey, "loot")

    char.sessions = char.sessions or {}
    local starts = {}
    for _, s in ipairs(char.sessions) do if s.start then starts[s.start] = true end end
    for _, s in ipairs(data.sessions or {}) do
        if s.start and s.start > 0 and not starts[s.start] then
            starts[s.start] = true
            char.sessions[#char.sessions + 1] = { start = s.start, stop = s.stop or (s.start + (s.played or 0)), played = s.played, active = s.active,
                levelStart = s.levelStart, levelEnd = s.levelEnd, counts = s.counts or {}, recovered = true }
            got.sessions = got.sessions + 1
        end
    end
    sortBy(char.sessions, "start")

    if type(data.lastSeen) == "number" and data.lastSeen > (char.lastSeen or 0) then char.lastSeen = data.lastSeen end
    return got
end

-- Anything at all added?
function CatchUp.Any(got)
    for _, n in pairs(got or {}) do if n > 0 then return true end end
    return false
end

