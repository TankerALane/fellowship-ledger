-- Trackers/Gold.lua
-- Net money per day and session, split by source using what was open at the time
-- (vendor, mailbox, auction house, loot window) and by matching quest rewards by
-- amount. Never reads chat. Confirmed on retail: PLAYER_MONEY (no args),
-- LOOT_READY/OPENED/CLOSED, MERCHANT_SHOW/CLOSED and QUEST_TURNED_IN (questID, xp, money).

local _, ns = ...
local T = ns.Trackers
local Store, GoldLogic = ns.Store, ns.GoldLogic

local state = {}
local matcher = GoldLogic.NewMatcher()
local lastMoney

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

local function count(entries)
    for _, e in ipairs(entries) do Store.Count(GoldLogic.Field(e[1]), e[2]) end
end

Gold.events.QUEST_TURNED_IN = function(_, _, _, moneyReward)
    count(GoldLogic.OnQuestReward(matcher, Store.Now(), T.Plain(moneyReward)))
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
    Store.Count("moneyNet", delta)
    Store.Count(delta > 0 and "moneyIn" or "moneyOut", math.abs(delta))
    count(GoldLogic.OnMoney(matcher, state, Store.Now(), delta))
    Store.session.moneyEnd = money
end
