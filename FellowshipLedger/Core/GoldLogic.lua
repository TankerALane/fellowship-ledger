-- Core/GoldLogic.lua
-- PURE: no WoW globals. Works out where a money change came from by what was open
-- at the time (never by reading chat). See DECISIONS D-011 and D-021.
--
-- Quest money is matched by amount: QUEST_TURNED_IN names the reward, and that
-- amount is claimed from money gains within MATCH_WINDOW seconds on either side,
-- whichever event arrives first.

local _, ns = ...

local GoldLogic = {}
ns.GoldLogic = GoldLogic

GoldLogic.SOURCES = { "loot", "vendor", "quest", "mail", "auction", "other" }
GoldLogic.MATCH_WINDOW = 5 -- seconds between a quest turn-in and its money arriving
GoldLogic.LOOT_WINDOW = 2  -- seconds after the loot window closes that still count as loot

-- state: { merchant = bool, mail = bool, auction = bool, loot = bool, lootClosedAt = epoch }
-- delta: the money change (nil = treat as a gain). Loot only ever adds money,
-- so a loss is never put under loot.
function GoldLogic.Classify(state, now, delta)
    if state.merchant then return "vendor" end
    if state.auction then return "auction" end
    if state.mail then return "mail" end
    if delta ~= nil and delta < 0 then return "other" end
    if state.loot or (state.lootClosedAt and now - state.lootClosedAt <= GoldLogic.LOOT_WINDOW) then
        return "loot"
    end
    return "other"
end

function GoldLogic.Field(source)
    return "money_" .. source
end

function GoldLogic.NewMatcher()
    return { others = {}, credit = nil }
end

local function prune(m, now)
    local kept = {}
    for _, o in ipairs(m.others) do
        if now - o.at <= GoldLogic.MATCH_WINDOW and o.amount > 0 then kept[#kept + 1] = o end
    end
    m.others = kept
    if m.credit and (now - m.credit.at > GoldLogic.MATCH_WINDOW or m.credit.amount <= 0) then m.credit = nil end
end

-- A money change. Returns a list of { source, amount } to count.
function GoldLogic.OnMoney(m, state, now, delta)
    prune(m, now)
    local out = {}
    if delta > 0 and m.credit then
        local q = math.min(delta, m.credit.amount)
        m.credit.amount = m.credit.amount - q
        out[#out + 1] = { "quest", q }
        delta = delta - q
    end
    if delta ~= 0 then
        local source = GoldLogic.Classify(state, now, delta)
        out[#out + 1] = { source, delta }
        if source == "other" and delta > 0 then m.others[#m.others + 1] = { at = now, amount = delta } end
    end
    return out
end

-- A quest turn-in naming its money reward. Returns corrections { source, amount }
-- for money that already arrived and was counted as "other".
function GoldLogic.OnQuestReward(m, now, reward)
    prune(m, now)
    local out = {}
    if type(reward) ~= "number" or reward <= 0 then return out end
    for i = #m.others, 1, -1 do
        local o = m.others[i]
        if reward <= 0 then break end
        local moved = math.min(reward, o.amount)
        o.amount = o.amount - moved
        reward = reward - moved
        out[#out + 1] = { "other", -moved }
        out[#out + 1] = { "quest", moved }
    end
    if reward > 0 then
        if m.credit then
            m.credit.amount = m.credit.amount + reward
            m.credit.at = now
        else
            m.credit = { at = now, amount = reward }
        end
    end
    return out
end
