-- Core/TrackerList.lua
-- PURE: no WoW globals. The trackers, in display order, and the per-character
-- Track / Share flags. Track off = nothing collected. Share off = nothing sent.
-- Both default to on. Share is meaningless while Track is off (the UI greys it out).
--
-- status:
--   "ready"       confirmed working in-game
--   "unverified"  built, but depends on something not yet confirmed in-game
--   "unavailable" not built yet: needs an API that is unverified or blocked
-- unverifiedOn = { Retail = true } shows "unverified" only on that client
-- (the names are FlavorLogic.FOREVER / RETAIL). See TrackerList.Status.

local _, ns = ...

local TrackerList = {}
ns.TrackerList = TrackerList

TrackerList.ORDER = {
    { id = "levels", status = "ready" },
    { id = "quests", status = "ready" },
    { id = "dungeons", status = "ready" },       -- completion via our final-boss list, seen on Forever
    { id = "gold", status = "ready" },
    { id = "professions", status = "ready" },
    { id = "deaths", status = "ready" },
    { id = "zones", status = "ready" },
    { id = "reputation", status = "ready" },     -- gains recorded on Forever
    { id = "kills", status = "ready" },
    { id = "flightPaths", status = "ready", unverifiedOn = { Retail = true } }, -- seen on Forever only
    { id = "achievements", status = "ready" },
    { id = "partyLevels", status = "ready" },
    { id = "items", status = "ready", unverifiedOn = { Retail = true } },       -- seen on Forever only
}

-- The status to show on this client.
function TrackerList.Status(t, flavor)
    if t.status == "ready" and t.unverifiedOn and flavor and t.unverifiedOn[flavor] then
        return "unverified"
    end
    return t.status
end

TrackerList.byId = {}
for i, t in ipairs(TrackerList.ORDER) do
    t.index = i
    TrackerList.byId[t.id] = t
end

-- Make sure a character has a flag pair for every tracker (new trackers default on).
function TrackerList.EnsureFlags(char)
    char.flags = char.flags or {}
    for _, t in ipairs(TrackerList.ORDER) do
        local f = char.flags[t.id]
        if type(f) ~= "table" then
            f = {}
            char.flags[t.id] = f
        end
        if f.track == nil then f.track = true end
        if f.share == nil then f.share = true end
    end
end

function TrackerList.IsTracking(char, id)
    local t = TrackerList.byId[id]
    if not t or t.status == "unavailable" then return false end
    local f = char and char.flags and char.flags[id]
    return f == nil or f.track ~= false
end

-- Sharing requires tracking, the per-tracker share flag, and no global pause.
function TrackerList.IsSharing(char, id, sharingPaused)
    if sharingPaused then return false end
    if not TrackerList.IsTracking(char, id) then return false end
    local f = char.flags and char.flags[id]
    return f == nil or f.share ~= false
end
