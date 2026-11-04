-- Core/Activity.lua
-- Feeds the character clock: activity signals keep active time running, AFK stops
-- it, and a 30-second ticker advances played time, checks movement and lets
-- trackers do periodic work. A 10-minute ticker writes the backup.

local _, ns = ...
local Store = ns.Store

local Activity = {}
ns.Activity = Activity

Activity.TICK = 30
Activity.BACKUP_EVERY = 600

-- Confirmed firing on retail: movement, combat, target, XP, loot, zone changes.
local SIGNALS = {
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "LOOT_READY", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "MERCHANT_SHOW", "MAIL_SHOW", "TAXIMAP_OPENED",
}

local started = false

function Activity.Start()
    if started then return end
    started = true
    for _, event in ipairs(SIGNALS) do
        ns.Events.On(event, "activity", function() Store.Touch() end)
    end
    ns.Events.On("UNIT_SPELLCAST_SUCCEEDED", "activity", function(_, unit)
        if unit == "player" then Store.Touch() end
    end)
    ns.Events.On("PLAYER_FLAGS_CHANGED", "activity", function(_, unit)
        if unit ~= "player" then return end
        local ok, afk = ns.Compat.Call("activity", "UnitIsAFK", "player")
        if ok and afk == true then Store.Idle() else Store.Touch() end
    end)

    ns.Events.Every(Activity.TICK, "clock", function()
        local ok, speed = ns.Compat.Call("activity", "GetUnitSpeed", "player")
        if ok and type(speed) == "number" and not ns.Compat.IsSecret(speed) and speed > 0 then
            Store.Touch()
        else
            Store.Tick()
        end
        ns.Trackers.TickAll()
    end)
    ns.Events.Every(Activity.BACKUP_EVERY, "backup", function() Store.WriteBackup() end)
end
