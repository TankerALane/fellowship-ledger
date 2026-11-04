-- Trackers/Trackers.lua
-- Registry for trackers. A tracker is a table with an id (matching TrackerList),
-- `events = { EVENT = function(self, ...) end }`, and optional OnLogin(self) and
-- OnTick(self). Handlers only run while the current character has Track on for
-- that tracker and the feature has not been disabled by the Compat guard.

local _, ns = ...

local Trackers = {}
ns.Trackers = Trackers

Trackers.list = {}
Trackers.byId = {}

function Trackers.Define(def)
    assert(ns.TrackerList.byId[def.id], "unknown tracker id " .. tostring(def.id))
    def.events = def.events or {}
    Trackers.list[#Trackers.list + 1] = def
    Trackers.byId[def.id] = def
    return def
end

function Trackers.IsActive(id)
    return ns.Store.char ~= nil and ns.TrackerList.IsTracking(ns.Store.char, id) and not ns.Compat.IsDisabled(id)
end

local registered = false

-- Register every tracker's events once (first login of the UI session).
function Trackers.RegisterAll()
    if registered then return end
    registered = true
    for _, def in ipairs(Trackers.list) do
        for event, fn in pairs(def.events) do
            ns.Events.On(event, def.id, function(_, ...)
                if Trackers.IsActive(def.id) then fn(def, ...) end
            end)
        end
    end
end

local function each(method)
    for _, def in ipairs(Trackers.list) do
        if def[method] and Trackers.IsActive(def.id) then
            local ok, err = pcall(def[method], def)
            if not ok then ns.Log.Warn(ns.L.HANDLER_ERROR, def.id, method, tostring(err)) end
        end
    end
end

function Trackers.LoginAll() each("OnLogin") end
function Trackers.TickAll() each("OnTick") end

-- Short helpers shared by trackers.
function Trackers.Plain(v)
    if ns.Compat.IsSecret(v) then return nil end
    return v
end

-- Drop a repeat of the same key within `window` seconds (some events fire twice).
local lastSeen = {}
function Trackers.Dedupe(key, window)
    local t = ns.Store.Now()
    if lastSeen[key] and t - lastSeen[key] <= (window or 3) then return true end
    lastSeen[key] = t
    return false
end
