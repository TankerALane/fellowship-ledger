-- Core/GoldLogic.lua
-- PURE: no WoW globals. Works out where a money change came from by what was open
-- at the time (never by reading chat). See DECISIONS D-011.

local _, ns = ...

local GoldLogic = {}
ns.GoldLogic = GoldLogic

GoldLogic.SOURCES = { "loot", "vendor", "quest", "mail", "auction", "other" }
GoldLogic.QUEST_WINDOW = 3 -- seconds after a quest turn-in that count as quest money
GoldLogic.LOOT_WINDOW = 2  -- seconds after the loot window closes that still count as loot

-- state: { merchant = bool, mail = bool, auction = bool, loot = bool,
--          lootClosedAt = epoch, questAt = epoch }
-- delta: the money change (nil = treat as a gain). Quest rewards and loot only ever
-- add money, so a loss is never put under those sources.
function GoldLogic.Classify(state, now, delta)
    if state.merchant then return "vendor" end
    if state.auction then return "auction" end
    if state.mail then return "mail" end
    if delta ~= nil and delta < 0 then return "other" end
    if state.questAt and now - state.questAt <= GoldLogic.QUEST_WINDOW then return "quest" end
    if state.loot or (state.lootClosedAt and now - state.lootClosedAt <= GoldLogic.LOOT_WINDOW) then
        return "loot"
    end
    return "other"
end

function GoldLogic.Field(source)
    return "money_" .. source
end
