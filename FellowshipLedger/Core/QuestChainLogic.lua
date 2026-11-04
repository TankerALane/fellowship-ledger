-- Core/QuestChainLogic.lua
-- PURE: no WoW globals. Works out "step X of Y" from a chain's quest list, and
-- walks a chain from Questie-style links (previous quest / next quest) given
-- lookup functions, so the walking logic can be tested without Questie.

local _, ns = ...

local QuestChainLogic = {}
ns.QuestChainLogic = QuestChainLogic

QuestChainLogic.MAX_STEPS = 60

-- Position of questID in an ordered list. Returns step, total (step nil if absent).
function QuestChainLogic.StepOf(list, questID)
    for i, id in ipairs(list or {}) do
        if id == questID then return i, #list end
    end
    return nil, list and #list or 0
end

-- prevOf(id) -> previous quest ID or nil; nextOf(id) -> next quest ID or nil.
-- Returns the ordered chain (first quest first). Stops on loops or MAX_STEPS.
function QuestChainLogic.Walk(questID, prevOf, nextOf)
    local seen = { [questID] = true }
    local before = {}
    local cur = questID
    for _ = 1, QuestChainLogic.MAX_STEPS do
        local p = prevOf(cur)
        if not p or p == 0 or seen[p] then break end
        seen[p] = true
        table.insert(before, 1, p)
        cur = p
    end
    local chain = before
    chain[#chain + 1] = questID
    cur = questID
    for _ = 1, QuestChainLogic.MAX_STEPS do
        local n = nextOf(cur)
        if not n or n == 0 or seen[n] then break end
        seen[n] = true
        chain[#chain + 1] = n
        cur = n
    end
    return chain
end
