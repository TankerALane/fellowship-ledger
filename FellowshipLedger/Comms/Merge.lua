-- Comms/Merge.lua
-- PURE: no WoW globals. Stores what a friend sent: HELLO peer info and DATA for one
-- character. The friend's own numbers win for every day/level/session they send.
-- Returns milestone events ("reached level 30") for the notices.

local _, ns = ...

local Merge = {}
ns.Merge = Merge

Merge.KEEP_DAYS = 90
Merge.MILESTONE_EVERY = 10
Merge.PROFESSION_CAPS = { 75, 150, 225, 300 } -- profession milestone ranks (D-098)
Merge.maxLevel = nil -- the level cap on this client, set at login (Comms/Sync.lua); nil = unknown
Merge.MAX_RUNS_KEPT = 50
Merge.MAX_DEATHS_KEPT = 20 -- a friend character's recent deaths kept (D-105)
Merge.MAX_LOOT_KEPT = 30   -- a friend character's blue+ loot kept (D-105)

-- One character is never in two runs at once: drop any run (list sorted by entry)
-- that starts inside an earlier run of the same dungeon. Returns how many went.
function Merge.DropInside(list)
    local dropped = 0
    local i = 2
    while i <= #list do
        local r, inside = list[i], false
        for j = 1, i - 1 do
            local o = list[j]
            if o.name == r.name and r.entered > o.entered and r.entered < o.entered + (o.duration or 0) then
                inside = true
                break
            end
        end
        if inside then
            table.remove(list, i)
            dropped = dropped + 1
        else
            i = i + 1
        end
    end
    return dropped
end

-- friends: db.friends; peer: { id, kind, name, tag, online }
function Merge.Friend(friends, peer)
    local f = friends[peer.id]
    if not f then
        f = { kind = peer.kind, characters = {} }
        friends[peer.id] = f
    end
    f.kind, f.name, f.tag = peer.kind, peer.name or f.name, peer.tag or f.tag
    if peer.online ~= nil then f.online = peer.online end
    f.characters = f.characters or {}
    return f
end

-- "1.2.3" -> 1, 2, 3. Anything else (a test build such as "1.2.3-dev", text,
-- nil) gives nil, so it never triggers an update notice.
function Merge.ParseVersion(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

-- 1 if a is newer than b, -1 if older, 0 if the same, nil if either is not x.y.z.
function Merge.CompareVersions(a, b)
    local a1, a2, a3 = Merge.ParseVersion(a)
    local b1, b2, b3 = Merge.ParseVersion(b)
    if not a1 or not b1 then return nil end
    for _, pair in ipairs({ { a1, b1 }, { a2, b2 }, { a3, b3 } }) do
        if pair[1] > pair[2] then return 1 end
        if pair[1] < pair[2] then return -1 end
    end
    return 0
end

function Merge.Hello(friend, hello, now)
    friend.version = hello.version
    friend.nameOptIn = hello.nameOptIn
    friend.helloAt = now
    -- Characters the friend removed from their own ledger.
    for _, key in ipairs(hello.removed or {}) do
        if friend.characters then friend.characters[key] = nil end
    end
    friend.announced = {}
    for _, c in ipairs(hello.characters) do
        friend.announced[c.key] = { class = c.class, level = c.level, mask = c.mask, lastSeen = c.lastSeen }
    end
end

-- Level milestones: every MILESTONE_EVERY levels, and the level cap as its own kind
-- (instead of the every-10 one at the same level).
local function milestones(name, old, new)
    local out = {}
    if not old or not new or new <= old then return out end
    for lvl = old + 1, new do
        if Merge.maxLevel and lvl == Merge.maxLevel then
            out[#out + 1] = { kind = "maxlevel", character = name, level = lvl }
        elseif lvl % Merge.MILESTONE_EVERY == 0 then
            out[#out + 1] = { kind = "level", character = name, level = lvl }
        end
    end
    return out
end

-- Merge one decoded DATA. Returns a list of milestone events.
function Merge.Data(friend, data, todayKey, cutoffKey, now)
    local c = friend.characters[data.key]
    local isNew = c == nil
    if isNew then
        c = { days = {}, levels = {}, sessions = {} }
        friend.characters[data.key] = c
    end
    local oldLevel = c.level
    -- What we knew before, for the milestones (D-098).
    local oldRanks
    if c.professions then
        oldRanks = {}
        for key, p in pairs(c.professions) do oldRanks[key] = p.rank or 0 end
    end
    local cleared = {}
    for _, r in ipairs(c.runs or {}) do if r.completed and r.name then cleared[r.name] = true end end
    c.name = data.key:match("^([^%-]+)") or data.key
    c.realm = data.key:match("%-(.+)$")
    -- Forever: the key is "First-Last" (D-064), so show "First Last".
    c.display = Merge.firstLastNames and c.realm and (c.name .. " " .. c.realm) or nil
    c.class, c.race, c.faction = data.class, data.race, data.faction
    c.level, c.lastSeen, c.mask = data.level, data.lastSeen, data.mask
    c.days = c.days or {}
    for day, counts in pairs(data.days) do
        if day <= todayKey and day >= cutoffKey then c.days[day] = counts end
    end
    for day in pairs(c.days) do
        if day < cutoffKey then c.days[day] = nil end
    end
    c.levels = c.levels or {}
    for to, r in pairs(data.levels) do c.levels[to] = r end
    -- Quest chains are "what they are on now": replace them when quests are shared.
    if ns.Codec.MaskToSet(data.mask or "").quests then
        c.chains = data.chains or {}
        c.logQuests = data.logQuests -- nil from senders before 1.2.1 (D-087)
    else
        c.chains, c.logQuests = nil, nil
    end
    -- Profession ranks (1.2.0+ senders), replaced like chains; nil = not known (D-083).
    if ns.Codec.MaskToSet(data.mask or "").professions then
        c.professions = data.professions or c.professions
    else
        c.professions = nil
    end
    -- Dungeon runs (1.5.0+ senders, D-095): upsert by entry time, keep 90 days and the
    -- newest MAX_RUNS_KEPT; cleared when Dungeons is not shared. A run that starts inside
    -- an earlier run of the same dungeon is a piece the friend's ledger has since joined
    -- into it (D-110, D-112), so it goes (Merge.DropInside).
    if ns.Codec.MaskToSet(data.mask or "").dungeons then
        if data.runs then
            local byEntered = {}
            for _, r in ipairs(c.runs or {}) do byEntered[r.entered] = r end
            for _, r in ipairs(data.runs) do byEntered[r.entered] = r end
            local from = ns.Codec.SinceEpoch(cutoffKey)
            local list = {}
            for _, r in pairs(byEntered) do if r.entered >= from then list[#list + 1] = r end end
            table.sort(list, function(a, b) return a.entered < b.entered end)
            Merge.DropInside(list)
            while #list > Merge.MAX_RUNS_KEPT do table.remove(list, 1) end
            c.runs = list
        end
    else
        c.runs = nil
    end
    -- Recent deaths and blue+ loot (1.7.0+ senders, D-105): upsert by time, keep 90 days
    -- and the newest few, oldest first (as our own lists); cleared when not shared.
    local from = ns.Codec.SinceEpoch(cutoffKey)
    local function upsert(old, new, keyOf, keep)
        local by, list = {}, {}
        for _, e in ipairs(old or {}) do by[keyOf(e)] = e end
        for _, e in ipairs(new or {}) do by[keyOf(e)] = e end
        for _, e in pairs(by) do if (e.at or 0) >= from then list[#list + 1] = e end end
        table.sort(list, function(a, b) return a.at < b.at end)
        while #list > keep do table.remove(list, 1) end
        return list
    end
    local shared = ns.Codec.MaskToSet(data.mask or "")
    if shared.deaths then
        if data.deathLog then c.deathLog = upsert(c.deathLog, data.deathLog, function(e) return e.at end, Merge.MAX_DEATHS_KEPT) end
    else
        c.deathLog = nil
    end
    local newLoot = {}
    if shared.items then
        if data.loot then
            local seen
            if c.loot then
                seen = {}
                for _, e in ipairs(c.loot) do seen[e.at .. ":" .. e.id] = true end
            end
            -- Only loot new since what we already held is a notice; the first list is the baseline.
            -- Nothing older than a day, so a friend back after a week does not replay it.
            for _, e in ipairs(data.loot) do
                if seen and not seen[e.at .. ":" .. e.id] and (not now or e.at >= now - 86400) then newLoot[#newLoot + 1] = e end
            end
            c.loot = upsert(c.loot, data.loot, function(e) return e.at .. ":" .. e.id end, Merge.MAX_LOOT_KEPT)
        end
    else
        c.loot = nil
    end
    -- sessions: upsert by start time, keep sorted
    c.sessions = c.sessions or {}
    local byStart = {}
    for _, s in ipairs(c.sessions) do byStart[s.start] = s end
    for _, s in ipairs(data.sessions) do byStart[s.start] = s end
    local list = {}
    for _, s in pairs(byStart) do list[#list + 1] = s end
    table.sort(list, function(a, b) return a.start < b.start end)
    while #list > ns.Codec.MAX_SESSIONS * 2 do table.remove(list, 1) end
    c.sessions = list
    friend.lastUpdated = now
    local latest = friend.syncedThrough
    for day in pairs(data.days) do
        if not latest or day > latest then latest = day end
    end
    friend.syncedThrough = latest
    if isNew then return {} end
    local name = c.display or c.name
    local events = milestones(name, oldLevel, c.level)
    -- The gain itself, for the "While you were away" notice only (D-099).
    if oldLevel and c.level and c.level > oldLevel then
        events[#events + 1] = { kind = "levels", character = name, from = oldLevel, to = c.level }
    end
    -- Professions: the highest cap crossed since the last DATA.
    if oldRanks and c.professions then
        for key, p in pairs(c.professions) do
            local before, now_ = oldRanks[key], p.rank or 0
            if before then
                local hit
                for _, cap in ipairs(Merge.PROFESSION_CAPS) do
                    if before < cap and now_ >= cap then hit = cap end
                end
                if hit then events[#events + 1] = { kind = "profession", character = name, profession = p.name or key, rank = hit } end
            end
        end
    end
    -- Dungeons: a completed run of a dungeon not seen completed before. A regular sync
    -- carries only the last day or two of runs, so this does not replay old clears.
    for _, r in ipairs(data.runs or {}) do
        if r.completed and r.name and not cleared[r.name] then
            cleared[r.name] = true
            events[#events + 1] = { kind = "dungeon", character = name, dungeon = r.name }
        end
    end
    -- Loot (D-105): a blue or better item looted since the last DATA.
    for _, it in ipairs(newLoot) do
        events[#events + 1] = { kind = "loot", character = name, itemID = it.id, quality = it.quality, count = it.count }
    end
    for _, e in ipairs(events) do e.key = data.key end
    return events
end

-- Weekly summary per friend (last 7 days): { name, levels, quests, dungeons, active }.
function Merge.Weekly(friends, blocklist, todayKey, timeFn, dateFn)
    local from = ns.Days.RangeStart("week", todayKey, timeFn, dateFn)
    local out = {}
    for id, f in pairs(friends or {}) do
        if not ns.FriendsModel.IsBlocked(blocklist, f) then
            local t = { id = id, name = f.name or id, levels = 0, quests = 0, dungeons = 0, active = 0 }
            for _, c in pairs(f.characters or {}) do
                local s = ns.Days.Sum(c.days or {}, from, todayKey)
                t.levels = t.levels + (s.levels or 0)
                t.quests = t.quests + (s.quests or 0)
                t.dungeons = t.dungeons + (s.dungeonsCompleted or 0)
                t.active = t.active + (s.active or 0)
            end
            out[#out + 1] = t
        end
    end
    table.sort(out, function(a, b)
        if a.active == b.active then return a.name < b.name end
        return a.active > b.active
    end)
    return out
end
