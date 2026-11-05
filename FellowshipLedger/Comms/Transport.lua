-- Comms/Transport.lua
-- Sending and receiving addon messages.
--  * Send queue with a token-bucket rate limit (Comms/RateLimit.lua).
--  * Nothing is sent in combat, during a boss encounter, while chat messaging is
--    locked down, or from a trial account. Queued messages simply wait.
--  * Results (Enum.SendAddonMessageResult, names confirmed on retail): throttles
--    retry with back-off, lockdown pauses the queue for 30 s, TargetOffline drops
--    everything queued for that friend, other failures drop the message.
--  * Receiving: only our flavor's prefix, only our flavor code, only from friends
--    (plus party NAME notes and our own test messages). Chunks are reassembled.
-- Receive event arguments are not confirmed yet (/fl commtest checks them):
--  BN_CHAT_MSG_ADDON (prefix, text, channel, senderGameAccountID)
--  CHAT_MSG_ADDON    (prefix, text, channel, sender, ...)

local _, ns = ...
local L = ns.L
local Codec, RateLimit = ns.Codec, ns.RateLimit

local Transport = {}
ns.Transport = Transport

Transport.PUMP_EVERY = 0.25
Transport.LOCKDOWN_PAUSE = 30
Transport.queue = {}
Transport.stats = { sent = 0, retried = 0, failed = 0, received = 0, dropped = 0, results = {} }
Transport.encounter = false
Transport.handlers = {} -- type letter -> function(peer, body, info)

local bucket
local reassembler = Codec.NewReassembler()
local pauseUntil = 0
local msgCounter = 0
local started = false

local function now() return GetTime() end

function Transport.Prefix()
    return ns.FlavorLogic.PREFIX[ns.Compat.flavor]
end

function Transport.Code()
    return ns.FlavorLogic.CODE[ns.Compat.flavor]
end

function Transport.ChunkSize()
    local size = tonumber(ns.db.settings.commsChunk) or Codec.DEFAULT_CHUNK
    return math.max(Codec.MIN_CHUNK, math.min(Codec.MAX_CHUNK, size))
end

function Transport.NextId()
    msgCounter = msgCounter + 1
    return string.format("%x%x", time() % 4096, msgCounter % 4096)
end

-- Why sending is held back right now (nil when it may proceed).
function Transport.Blocked()
    if Transport.trial then return "trial account" end
    if ns.Compat.IsDisabled("comms") then return "comms disabled" end
    local okC, combat = ns.Compat.Try("InCombatLockdown")
    if okC and combat then return "combat" end
    if Transport.encounter then return "encounter" end
    if ns.Compat.Has("C_ChatInfo.InChatMessagingLockdown") then
        local okL, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if okL and locked then return "chat lockdown" end
    end
    if now() < pauseUntil then return "paused after lockdown" end
    return nil
end

-- Queue one logical message (it is chunked here).
-- dest: { transport = "bn"|"whisper"|"party", target = gameAccountID | "Name-Realm" | channel, peerId }
function Transport.Send(dest, mtype, body)
    local chunks = Codec.Chunk(Transport.Code(), mtype, Transport.NextId(), body, Transport.ChunkSize())
    for _, text in ipairs(chunks) do
        Transport.queue[#Transport.queue + 1] = { dest = dest, text = text, attempts = 0, notBefore = 0 }
    end
    return #chunks
end

local function resultName(res)
    if res == nil or res == true then return "Success" end
    if res == false then return "Failed" end
    local enum = _G.Enum and _G.Enum.SendAddonMessageResult
    if type(enum) == "table" then
        for name, v in pairs(enum) do if v == res then return name end end
    end
    return tostring(res)
end
Transport.ResultName = resultName

-- A missing send API turns sharing off (nothing could ever be sent). A send that
-- merely errors (say, one friend's game account went away) only fails that
-- message: it must not switch sharing off for everyone for the whole session.
local function guardedSend(path, ...)
    if not ns.Compat.Has(path) then
        ns.Compat.Disable("comms", path .. " is missing")
        return false
    end
    local ok, res = pcall(ns.Compat.Resolve(path), ...)
    if not ok then
        Transport.lastError = path .. ": " .. tostring(res)
        return false
    end
    return true, res
end

local function rawSend(item)
    local prefix = Transport.Prefix()
    local d = item.dest
    if d.transport == "bn" then
        return guardedSend("C_BattleNet.SendGameData", d.target, prefix, item.text)
    elseif d.transport == "whisper" then
        return guardedSend("C_ChatInfo.SendAddonMessage", prefix, item.text, "WHISPER", d.target)
    else
        return guardedSend("C_ChatInfo.SendAddonMessage", prefix, item.text, d.target)
    end
end

local function dropTarget(target)
    local kept = {}
    for _, q in ipairs(Transport.queue) do
        if q.dest.target ~= target then kept[#kept + 1] = q end
    end
    Transport.queue = kept
end

function Transport.Pump()
    if #Transport.queue == 0 then return end
    if Transport.Blocked() then return end
    local t = now()
    local i = 1
    while i <= #Transport.queue do
        local item = Transport.queue[i]
        if item.notBefore <= t then
            if not RateLimit.Take(bucket, t) then return end
            local ok, res = rawSend(item)
            local name = ok and resultName(res) or "Error"
            Transport.stats.results[name] = (Transport.stats.results[name] or 0) + 1
            if name == "Success" then
                Transport.stats.sent = Transport.stats.sent + 1
                table.remove(Transport.queue, i)
            elseif name == "AddonMessageThrottle" or name == "ChannelThrottle" then
                item.attempts = item.attempts + 1
                Transport.stats.retried = Transport.stats.retried + 1
                if item.attempts >= RateLimit.MAX_ATTEMPTS then
                    table.remove(Transport.queue, i)
                    Transport.stats.failed = Transport.stats.failed + 1
                else
                    item.notBefore = t + RateLimit.Backoff(item.attempts)
                    i = i + 1
                end
            elseif name == "AddOnMessageLockdown" then
                pauseUntil = t + Transport.LOCKDOWN_PAUSE
                Transport.stats.retried = Transport.stats.retried + 1
                return
            elseif name == "TargetOffline" then
                dropTarget(item.dest.target)
                Transport.stats.failed = Transport.stats.failed + 1
                i = 1
            else
                table.remove(Transport.queue, i)
                Transport.stats.failed = Transport.stats.failed + 1
                ns.Log.Debug("send failed (%s) to %s", name, tostring(item.dest.target))
            end
        else
            i = i + 1
        end
    end
end

-- Receiving ------------------------------------------------------------------------

-- Argument shapes seen, for /fl commtest (types only, never contents).
Transport.seen = {}
local function noteShape(event, ...)
    if Transport.seen[event] then return end
    local types = {}
    for i = 1, select("#", ...) do types[i] = type((select(i, ...))) end
    Transport.seen[event] = table.concat(types, ",")
end

local function receive(transport, prefix, text, channel, sender)
    if prefix ~= Transport.Prefix() or type(text) ~= "string" then return end
    if ns.Compat.IsSecret(text) or ns.Compat.IsSecret(sender) then return end
    local chunk = Codec.ParseChunk(text)
    if not chunk then return end
    if not ns.FlavorLogic.Matches(ns.Compat.flavor, chunk.flavor) then
        Transport.stats.dropped = Transport.stats.dropped + 1
        return -- another flavor's data never mixes in
    end
    local isSelf = transport == "whisper" and ns.Friends.IsSelf(sender)
    if chunk.type == "T" and not isSelf then
        -- Diagnostics for /fl commtest: what the sender looked like versus my key.
        Transport.selfMismatch = { sender = tostring(sender), key = tostring(ns.Store.key) }
    end
    local peer
    if chunk.type == "N" then
        if channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" and channel ~= "RAID" then return end
    elseif chunk.type == "T" and isSelf then
        peer = { id = "self", tag = ns.Store.key, transport = "whisper", target = ns.Store.key, character = ns.Store.key }
    else
        peer = ns.Friends.PeerFor(transport, sender)
        if not peer then
            Transport.stats.dropped = Transport.stats.dropped + 1
            return -- not a friend: ignored
        end
        if ns.Friends.IsBlocked(peer) then
            Transport.stats.dropped = Transport.stats.dropped + 1
            return
        end
    end
    Transport.stats.received = Transport.stats.received + 1
    local key = (peer and peer.id or tostring(sender)) .. "/" .. chunk.type
    local body = Codec.Feed(reassembler, key, chunk, time())
    if not body then return end
    local handler = Transport.handlers[chunk.type]
    if handler then
        handler(peer, body, { transport = transport, channel = channel, sender = sender, size = #text, proto = chunk.proto })
    end
end

function Transport.Start()
    if started then return end
    started = true
    bucket = RateLimit.New(RateLimit.RATE, RateLimit.BURST, now())
    local prefix = Transport.Prefix()
    if not prefix then
        ns.Compat.Disable("comms", "no prefix for this flavor")
        return
    end
    ns.Compat.Call("comms", "C_ChatInfo.RegisterAddonMessagePrefix", prefix)
    local okT, trial = ns.Compat.Call("comms", "IsTrialAccount")
    local okV, vet = ns.Compat.Call("comms", "IsVeteranTrialAccount")
    Transport.trial = (okT and trial == true) or (okV and vet == true)
    if Transport.trial then ns.Log.Info(L.COMMS_TRIAL) end

    ns.Events.On("BN_CHAT_MSG_ADDON", "comms", function(event, prefix2, text, channel, senderID, ...)
        noteShape(event, prefix2, text, channel, senderID, ...)
        receive("bn", prefix2, text, channel, senderID)
    end)
    ns.Events.On("CHAT_MSG_ADDON", "comms", function(event, prefix2, text, channel, sender, ...)
        noteShape(event, prefix2, text, channel, sender, ...)
        receive(channel == "WHISPER" and "whisper" or "group", prefix2, text, channel, sender)
    end)
    ns.Events.On("ENCOUNTER_START", "comms", function() Transport.encounter = true end)
    ns.Events.On("ENCOUNTER_END", "comms", function() Transport.encounter = false end)
    ns.Events.On("PLAYER_ENTERING_WORLD", "comms", function() Transport.encounter = false end)
    ns.Events.Every(Transport.PUMP_EVERY, "comms", Transport.Pump)
end
