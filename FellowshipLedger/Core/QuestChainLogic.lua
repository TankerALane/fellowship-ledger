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
                        out[#out + 1] = { friend = f.name or "?", character = c.display or c.name or charKey, chain = chain, key = key }
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

-- Friends' characters on the chain `key`: { friend, character, step }, by friend then character.
function QuestChainLogic.FriendsOn(friends, blocked, key)
    local out = {}
    for _, f in pairs(friends or {}) do
        if not blocked(f) then
            for charKey, c in pairs(f.characters or {}) do
                local chain = c.chains and c.chains[key]
                if chain then
                    out[#out + 1] = { friend = f.name or "?", character = c.display or c.name or charKey, step = chain.step }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.friend ~= b.friend then return a.friend < b.friend end
        return a.character < b.character
    end)
    return out
end

-- A chain's details for the view (UI/ChainModel.lua).
-- ids: the chain's quest IDs in order. infoOf(id) -> { name, level, req, start, finish, pre = { ids } }.
-- statusOf(id) -> "done" | "log" | nil. anchor: the quest you are on (or nil).
-- Returns { quests, current, next, also }: current = index of the anchor (or of the
-- last quest in your log); next = the first quest not done and not in your log;
-- also = prerequisites outside the chain for quests not yet done.
function QuestChainLogic.Details(ids, infoOf, statusOf, anchor)
    local inChain, quests = {}, {}
    for _, id in ipairs(ids) do inChain[id] = true end
    local current, nextIdx
    for i, id in ipairs(ids) do
        local info = infoOf(id) or {}
        local q = { id = id, name = info.name, level = info.level, req = info.req, start = info.start,
            finish = info.finish, pre = info.pre, status = statusOf(id) }
        quests[i] = q
        if id == anchor then current = i end
        if q.status == "log" and not anchor then current = i end
        if not nextIdx and q.status == nil then nextIdx = i end
    end
    local also, seen = {}, {}
    for i, q in ipairs(quests) do
        if q.status ~= "done" and (not current or i >= current) then
            for _, p in ipairs(q.pre or {}) do
                if not inChain[p] and not seen[p] then
                    seen[p] = true
                    local info = infoOf(p) or {}
                    also[#also + 1] = { id = p, name = info.name, done = statusOf(p) == "done" }
                end
            end
        end
    end
    return { quests = quests, current = current, next = nextIdx, also = also }
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
