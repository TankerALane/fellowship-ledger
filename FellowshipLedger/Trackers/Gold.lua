-- Trackers/Gold.lua
-- Net money per day and session, split by source using what was open at the time
-- (vendor, mailbox, auction house, loot window, quest turn-in). Never reads chat.
-- Confirmed on retail: PLAYER_MONEY (no args), LOOT_READY/OPENED/CLOSED fire.

local _, ns = ...
local T = ns.Trackers
local Store, GoldLogic = ns.Store, ns.GoldLogic

local state = {}
local lastMoney
local recentOther -- { at, amount } of the last "other" gain, so a late QUEST_TURNED_IN can claim it

local Gold = T.Define({ id = "gold" })

function Gold:OnLogin()
    lastMoney = T.Plain(GetMoney())
    if Store.session.moneyStart == nil then Store.session.moneyStart = lastMoney end
end

local function set(key, value)
    return function() state[key] = value end
end

Gold.events.MERCHANT_SHOW = set("merchant", true)
Gold.events.MERCHANT_CLOSED = set("merchant", false)
Gold.events.MAIL_SHOW = set("mail", true)
Gold.events.MAIL_CLOSED = set("mail", false)
Gold.events.AUCTION_HOUSE_SHOW = set("auction", true)
Gold.events.AUCTION_HOUSE_CLOSED = set("auction", false)
Gold.events.LOOT_READY = set("loot", true)
Gold.events.LOOT_OPENED = set("loot", true)
Gold.events.LOOT_CLOSED = function()
    state.loot = false
    state.lootClosedAt = Store.Now()
end

Gold.events.QUEST_TURNED_IN = function(_, _, _, moneyReward)
    local t = Store.Now()
    state.questAt = t
    -- PLAYER_MONEY may already have fired and been counted as "other": move it.
    moneyReward = T.Plain(moneyReward)
    if type(moneyReward) == "number" and moneyReward > 0 and recentOther and t - recentOther.at <= GoldLogic.QUEST_WINDOW then
        local moved = math.min(moneyReward, recentOther.amount)
        Store.Count(GoldLogic.Field("other"), -moved)
        Store.Count(GoldLogic.Field("quest"), moved)
        recentOther = nil
    end
end

Gold.events.PLAYER_MONEY = function()
    local money = T.Plain(GetMoney())
    if type(money) ~= "number" then return end
    if lastMoney == nil then
        lastMoney = money
        return
    end
    local delta = money - lastMoney
    lastMoney = money
    if delta == 0 then return end
    local t = Store.Now()
    local source = GoldLogic.Classify(state, t, delta)
    Store.Count("moneyNet", delta)
    Store.Count(delta > 0 and "moneyIn" or "moneyOut", math.abs(delta))
    Store.Count(GoldLogic.Field(source), delta)
    Store.session.moneyEnd = money
    if source == "other" and delta > 0 then recentOther = { at = t, amount = delta } end
end
