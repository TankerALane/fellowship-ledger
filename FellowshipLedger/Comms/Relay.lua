-- Comms/Relay.lua
-- PURE: no WoW globals. Relaying between mutual friends (D-124): when you and a friend
-- are never online together, a third friend who saw them more recently passes their
-- newer data on to you.
--
--   B -> A  REQUEST with "v" records: a short hash of each friend character B holds
--           and how fresh B's copy is (that character's lastSeen)
--   A -> B  RELAY (type R) for each of those characters A holds a newer copy of,
--           only when the owner allows it (their HELLO says "f,relay") and has not
--           blocked B (their HELLO lists hashes of what they blocked)
--   B       keeps it only for a character it already has from that friend directly,
--           and only when it is newer than what B holds
--
-- Hashes, not names, go out: a friend can only match characters they already know.
-- The owner's own clock stamps lastSeen, so copies of one character always compare.

local _, ns = ...

local Relay = {}
ns.Relay = Relay

Relay.MAX_KNOWN = 40  -- characters listed in one REQUEST (the freshest copies first)
Relay.MAX_SEND = 10   -- characters relayed in answer to one REQUEST

-- A short, stable hash ("FL:" + text, djb2, 32 bits) as 8 hex digits.
function Relay.Hash(text)
    local h = 5381
    local s = "FL:" .. tostring(text)
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function blocked(blocklist, f, key)
    return ns.FriendsModel.IsBlocked(blocklist, f, key)
end

-- What I hold of friends' characters, for a REQUEST to peerId (their own characters
-- left out): { { hash, lastSeen } }, newest first, at most MAX_KNOWN.
function Relay.Known(friends, blocklist, peerId)
    local list = {}
    for id, f in pairs(friends or {}) do
        if id ~= peerId and not blocked(blocklist, f) then
            for key, c in pairs(f.characters or {}) do
                if type(c.lastSeen) == "number" and c.lastSeen > 0 and not blocked(blocklist, f, key) then
                    list[#list + 1] = { hash = Relay.Hash(key), lastSeen = c.lastSeen }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.lastSeen == b.lastSeen then return a.hash < b.hash end
        return a.lastSeen > b.lastSeen
    end)
    while #list > Relay.MAX_KNOWN do table.remove(list) end
    return list
end

-- Is the asking peer one the owner blocked? owner.noRelay: set of hashes from the
-- owner's HELLO; peer: { tag, character }.
function Relay.BlockedByOwner(owner, peer)
    local set = owner.noRelay
    if not set then return false end
    for _, v in ipairs({ peer.tag, peer.character }) do
        if type(v) == "string" and set[Relay.Hash(v)] then return true end
    end
    return false
end

-- Characters to relay to peer: theirs = { [hash] = lastSeen } from their REQUEST.
-- Only owners who allow relaying (owner.relay), not the peer itself, not blocked on
-- either side, and only where my copy is newer. Returns { { key, char, friendId,
-- theirs } }, newest first, at most MAX_SEND.
function Relay.Pick(friends, blocklist, peer, theirs)
    local out = {}
    if not theirs then return out end
    for id, f in pairs(friends or {}) do
        if id ~= peer.id and f.relay and not blocked(blocklist, f) and not Relay.BlockedByOwner(f, peer) then
            for key, c in pairs(f.characters or {}) do
                local seen = theirs[Relay.Hash(key)]
                if seen and type(c.lastSeen) == "number" and c.lastSeen > seen and not blocked(blocklist, f, key) then
                    out[#out + 1] = { key = key, char = c, friendId = id, theirs = seen }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.char.lastSeen == b.char.lastSeen then return a.key < b.key end
        return a.char.lastSeen > b.char.lastSeen
    end)
    while #out > Relay.MAX_SEND do table.remove(out) end
    return out
end

-- The friend record that already holds this character (never the relaying peer's own),
-- if relayed data for it may be kept: returns id, friend, char.
function Relay.Owner(friends, blocklist, key, viaId)
    for id, f in pairs(friends or {}) do
        local c = f.characters and f.characters[key]
        if c and id ~= viaId then
            if blocked(blocklist, f) or blocked(blocklist, f, key) then return nil end
            return id, f, c
        end
    end
    return nil
end

-- A friend's stored character in the shape Codec.EncodeData reads (our own
-- characters' shape), so it can be sent on unchanged.
function Relay.AsOwn(c)
    local out = {}
    for k, v in pairs(c) do out[k] = v end
    out.currentRun = nil
    -- Dungeon runs: back from the received form (kills, clear, splits, bossNames,
    -- names, size) to bosses and a party.
    if c.runs then
        local runs = {}
        for _, r in ipairs(c.runs) do
            local run = { entered = r.entered, name = r.name, duration = r.duration, completed = r.completed,
                bossCount = r.bossCount, deaths = r.deaths, levelMax = r.levelMax, bosses = {}, party = {}, partial = r.partial }
            if r.startOffset and r.entered then run.started = r.entered + r.startOffset end
            if r.completed and r.clear and r.entered then run.completedAt = r.entered + (r.startOffset or 0) + r.clear end
            for i, s in ipairs(r.splits or {}) do
                run.bosses[i] = { at = r.entered and s.at and (r.entered + s.at) or nil, fight = s.fight,
                    name = r.bossNames and r.bossNames[i] or nil }
            end
            -- Kills without times (senders before 1.7.0) still count.
            for i = #run.bosses + 1, r.kills or 0 do run.bosses[i] = {} end
            for _, name in ipairs(r.names or {}) do run.party[#run.party + 1] = { name = name, friend = true } end
            for _ = #run.party + 2, r.size or 1 do run.party[#run.party + 1] = {} end
            runs[#runs + 1] = run
        end
        out.dungeons, out.runs = runs, nil
    end
    -- Notable loot: the received form keeps the item ID; the encoder reads a link.
    if c.loot then
        local items = {}
        for _, e in ipairs(c.loot) do
            items[#items + 1] = { link = "item:" .. tostring(e.id), quality = e.quality, quantity = e.count, at = e.at, zone = e.zone }
        end
        out.items, out.loot = items, nil
    end
    return out
end
