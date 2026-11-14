-- Trackers/Professions.lua
-- Current rank, skill-ups per day/session, and active time to each skill point.
-- Uses GetProfessions/GetProfessionInfo (pass on retail). SKILL_LINES_CHANGED fired
-- 28 times in a few minutes in the retail probe, so rescans are throttled.

local _, ns = ...
local T = ns.Trackers
local Store = ns.Store

local HISTORY_MAX = 300

-- Returns the professions the game shows, and whether that list is complete (every
-- slot read cleanly). Only a complete list may delete anything.
local function read()
    local out = {}
    if not ns.Compat.Has("GetProfessions") then return out, false end
    local slots = ns.util.pack(GetProfessions())
    local complete, found = true, 0
    for i = 1, slots.n do
        local index = slots[i]
        if index then
            local ok, name, _, rank, maxRank, _, _, skillLine = ns.Compat.Call("professions", "GetProfessionInfo", index)
            rank, maxRank = T.Plain(rank), T.Plain(maxRank)
            if ok and name and type(rank) == "number" then
                out[tostring(T.Plain(skillLine) or name)] = { name = name, rank = rank, max = maxRank }
                found = found + 1
            else
                complete = false
            end
        end
    end
    return out, complete, found
end

local function fresh(char, cur, t)
    return { name = cur.name, rank = cur.rank, max = cur.max, history = {}, lastActive = char.clock.active, lastAt = t }
end

-- countGains: false at login (ranks earned earlier are adopted, not counted).
local function scan(countGains)
    local char = Store.char
    local t = Store.Now()
    local now, complete, found = read()
    -- A profession the game no longer shows was unlearned: delete it (Austin,
    -- 2026-11-13; unlearning is the only way one disappears). Only from a complete
    -- read, and an empty one only after login, so a list the game has not loaded yet
    -- cannot wipe them. Skill-ups already counted in the day totals stay.
    if complete and (found > 0 or countGains) then
        for key in pairs(char.professions) do
            if not now[key] then char.professions[key] = nil end
        end
    end
    for key, cur in pairs(now) do
        local p = char.professions[key]
        if p and cur.rank < p.rank then
            -- Unlearned and learned again between two looks: start over from the new rank.
            p = nil
        end
        if not p then
            p = fresh(char, cur, t)
            char.professions[key] = p
        elseif cur.rank > p.rank then
            local gained = cur.rank - p.rank
            if countGains then
                local activeSince = char.clock.active - (p.lastActive or char.clock.active)
                for r = p.rank + 1, cur.rank do
                    p.history[#p.history + 1] = { rank = r, at = t, active = (r == p.rank + 1) and activeSince or 0 }
                end
                while #p.history > HISTORY_MAX do table.remove(p.history, 1) end
                Store.Count("skillUps", gained)
            end
            p.rank = cur.rank
            p.lastActive = char.clock.active
            p.lastAt = t
        end
        p.name, p.max = cur.name, cur.max
    end
end

local Professions = T.Define({ id = "professions" })

-- At login, adopt the current ranks without counting them (they were earned earlier).
function Professions:OnLogin() scan(false) end

local pending = false
local function queueScan()
    if pending then return end
    pending = true
    ns.Events.After(1, function()
        pending = false
        if T.IsActive("professions") then scan(true) end
    end)
end

Professions.events.SKILL_LINES_CHANGED = queueScan
Professions.events.TRADE_SKILL_SHOW = queueScan
