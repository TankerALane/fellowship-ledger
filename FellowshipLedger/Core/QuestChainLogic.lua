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

-- Chains friends are on that I have not started.
-- friends: db.friends shape; mine: set of my chain keys; started(firstQuestID) -> bool.
-- Returns { friend, character, chain } sorted by friend then chain name; one entry per chain key.
function QuestChainLogic.FriendSuggestions(friends, blocked, mine, started)
    local out, seen = {}, {}
    for _, f in pairs(friends or {}) do
        if not blocked(f) then
            for charKey, c in pairs(f.characters or {}) do
                for key, chain in pairs(c.chains or {}) do
                    if not mine[key] and not seen[key] and not started(chain.firstQuestID) then
                        seen[key] = true
                        out[#out + 1] = { friend = f.name or "?", character = c.name or charKey, chain = chain, key = key }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.friend ~= b.friend then return a.friend < b.friend end
        return tostring(a.chain.name) < tostring(b.chain.name)
    end)
    return out
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
