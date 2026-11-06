-- Comms/Sync.lua
-- The sync conversation (docs/PROTOCOL.md):
--   A -> B  HELLO (wantReply)      who I am, my sharing characters and flags
--   B -> A  HELLO + REQUEST(since) B introduces itself and asks for A's data
--   A -> B  DATA (one per shared character, only shared trackers, since that day)
--   A <- B  ... and the same the other way round.
-- Triggers: 10 s after login, a friend coming online, opening the Friends tab or
-- "Sync now", and every 15 minutes. Blocked friends get nothing and are ignored.
-- Live update (D-090): every minute, the character I am playing sends today's DATA,
-- unasked, to online friends who run the ledger, but only when it changed.
-- Fake data (/fl fake) is never read here: only db.characters is ever sent.

local _, ns = ...
local L = ns.L
local Codec, Merge, Transport, Friends = ns.Codec, ns.Merge, ns.Transport, ns.Friends

local Sync = {}
ns.Sync = Sync

Sync.INTERVAL = 900      -- seconds between automatic full syncs (every character; D-090)
Sync.HELLO_GAP = 60      -- don't repeat HELLO to the same friend within this
Sync.REQUEST_GAP = 300   -- don't repeat REQUEST to the same friend within this
Sync.NAME_GAP = 60
Sync.LIVE_EVERY = 60     -- seconds between live updates of the character being played
Sync.lastLive = {}       -- peer id -> what the last live update said (lastSeen left out)
Sync.lastHello, Sync.lastRequest = {}, {}
Sync.optedIn = {}        -- party member names who sent a NAME note this session
Sync.test = nil

local function now() return time() end

local function destFor(peer)
    return { transport = peer.transport, target = peer.target, peerId = peer.id }
end

-- My characters that share anything, for HELLO.
function Sync.MyCharacters()
    local list = {}
    local paused = ns.db.settings.sharingPaused
    local keys = {}
    for key in pairs(ns.db.characters) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local c = ns.db.characters[key]
        local shared, any = Codec.SharedTrackers(c, paused)
        if any then
            list[#list + 1] = { key = key, char = c, shared = shared, class = c.class, level = c.level,
                mask = Codec.ShareMask(shared), lastSeen = c.lastSeen }
        end
    end
    return list
end

function Sync.SendHello(peer, wantReply, force)
    if Friends.IsBlocked(peer) or not peer.online or not peer.target then return end
    local t = now()
    if not force and Sync.lastHello[peer.id] and t - Sync.lastHello[peer.id] < Sync.HELLO_GAP then return end
    Sync.lastHello[peer.id] = t
    local removed = {}
    for key in pairs(ns.db.removed or {}) do removed[#removed + 1] = key end
    table.sort(removed)
    local body = Codec.EncodeHello({ version = ns.VERSION, nameOptIn = ns.db.settings.shareNameInDungeons,
        wantReply = wantReply, characters = Sync.MyCharacters(), removed = removed })
    Transport.Send(destFor(peer), "H", body)
end

function Sync.RequestFrom(peer)
    local t = now()
    if Sync.lastRequest[peer.id] and t - Sync.lastRequest[peer.id] < Sync.REQUEST_GAP then return end
    Sync.lastRequest[peer.id] = t
    local f = ns.db.friends[peer.id]
    local since = f and f.syncedThrough and ns.Days.Shift(f.syncedThrough, -1, time, date) or nil
    Transport.Send(destFor(peer), "Q", Codec.EncodeRequest(since))
end

function Sync.SendData(peer, since)
    if Friends.IsBlocked(peer) then return 0 end
    local oldest = ns.Days.Shift(ns.Store.Today(), -(ns.Days.KEEP - 1), time, date)
    if not since or since < oldest then since = oldest end
    local n = 0
    for _, mine in ipairs(Sync.MyCharacters()) do
        local body = Codec.EncodeData(mine.key, mine.char, mine.shared, since)
        n = n + Transport.Send(destFor(peer), "D", body)
    end
    return n
end

-- Live update: today's DATA for the character I am playing, to each online friend
-- who runs the ledger (has sent a HELLO), when it changed since the last one sent
-- to them. lastSeen moves on every tick, so it is left out of that comparison: an
-- idle character sends nothing. Older receivers merge it like any other DATA.
function Sync.SendLive()
    local key = ns.Store.key
    local c = key and ns.db.characters[key]
    if not c then return 0 end
    local shared, any = Codec.SharedTrackers(c, ns.db.settings.sharingPaused)
    if not any then return 0 end
    local today = ns.Store.Today()
    local body = Codec.EncodeData(key, c, shared, today)
    local seen = c.lastSeen
    c.lastSeen = 0
    local same = Codec.EncodeData(key, c, shared, today)
    c.lastSeen = seen
    local n = 0
    -- A friend who went offline gets the next live update in full, even if
    -- nothing changed: the last one may not have reached them.
    for id in pairs(Sync.lastLive) do
        local peer = Friends.peers[id]
        if not (peer and peer.online) then Sync.lastLive[id] = nil end
    end
    for id, peer in pairs(Friends.peers) do
        local f = ns.db.friends[id]
        if peer.online and peer.target and f and f.version and not Friends.IsBlocked(peer) and Sync.lastLive[id] ~= same then
            Sync.lastLive[id] = same
            n = n + Transport.Send(destFor(peer), "D", body)
            Sync.liveSent = (Sync.liveSent or 0) + 1
        end
    end
    Sync.liveMessages = (Sync.liveMessages or 0) + n
    return n
end

-- Message handlers -----------------------------------------------------------------

local function friendRecord(peer)
    return Merge.Friend(ns.db.friends, peer)
end

Transport.handlers.H = function(peer, body)
    local hello = Codec.DecodeHello(body)
    Merge.Hello(friendRecord(peer), hello, now())
    -- A friend runs a newer release: say so once per session. Versions only change
    -- in the release commit, which goes to CurseForge straight away, so a build
    -- being tested still carries the last released number (D-069).
    if not Sync.updateNoticeShown and Merge.CompareVersions(hello.version, ns.VERSION) == 1 then
        Sync.updateNoticeShown = hello.version
        ns.Log.Info(L.UPDATE_AVAILABLE, hello.version, ns.VERSION)
    end
    if hello.wantReply then Sync.SendHello(peer, false, true) end
    Sync.RequestFrom(peer)
end

Transport.handlers.Q = function(peer, body)
    Sync.SendData(peer, Codec.DecodeRequest(body).since)
end

Transport.handlers.D = function(peer, body)
    local data = Codec.DecodeData(body)
    if not data then return end
    local friend = friendRecord(peer)
    local today = ns.Store.Today()
    local cutoff = ns.Days.Shift(today, -(Merge.KEEP_DAYS - 1), time, date)
    local events = Merge.Data(friend, data, today, cutoff, now())
    if ns.db.settings.friendToasts then
        for _, e in ipairs(events) do
            ns.Toast.Show(L.FRIEND_MILESTONE_TITLE, { string.format(L.FRIEND_MILESTONE, e.character, friend.name or peer.id, e.level) })
        end
    end
    if ns.MainWindow.frame and ns.MainWindow.frame:IsShown() then ns.MainWindow.Refresh() end
end

Transport.handlers.N = function(_, body, info)
    local short = type(info.sender) == "string" and info.sender:match("^([^%-]+)") or info.sender
    if short then Sync.optedIn[short] = Codec.DecodeName(body) end
    if ns.DungeonsRefreshParty then ns.DungeonsRefreshParty() end
end

-- True if this party member (unit name) opted in to being named in dungeon records.
function Sync.IsOptedIn(name)
    return name ~= nil and Sync.optedIn[name] ~= nil
end

-- Announce my name to the dungeon group, if I opted in.
local lastName = 0
function Sync.AnnounceName()
    if not ns.db.settings.shareNameInDungeons or not ns.Store.char or not ns.Store.char.currentRun then return end
    if now() - lastName < Sync.NAME_GAP then return end
    lastName = now()
    local channel = "PARTY"
    local ok, inInstanceGroup = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_INSTANCE)
    if ok and inInstanceGroup then channel = "INSTANCE_CHAT" end
    Transport.Send({ transport = "group", target = channel }, "N", Codec.EncodeName(ns.Store.key))
end

-- Sync everyone ------------------------------------------------------------------

function Sync.SyncAll(force)
    Friends.Refresh()
    local count = 0
    for _, peer in pairs(Friends.peers) do
        if peer.online and not Friends.IsBlocked(peer) then
            -- "Sync now" (force) always asks for their data when they answer, even if
            -- a sync asked them less than REQUEST_GAP ago; automatic syncs keep the gap.
            if force then Sync.lastRequest[peer.id] = nil end
            Sync.SendHello(peer, true, force)
            count = count + 1
        end
    end
    Sync.lastSyncAt = now()
    return count
end

-- /fl commtest -----------------------------------------------------------------------
-- Whispers test messages of rising size to yourself and reports what was sent,
-- the result codes, what came back, and the argument shapes of the receive event.

Sync.TEST_SIZES = { 60, 100, 150, 200, 240, 255 }

Transport.handlers.T = function(peer, body, info)
    if not Sync.test then return end
    local id, size = body:match("^t,(%w+),(%d+),")
    if id then Sync.test.received[#Sync.test.received + 1] = { size = tonumber(size), wire = info.size, channel = info.channel } end
end

function Sync.CommTest()
    Sync.test = { started = now(), received = {}, sent = {} }
    local me = ns.Store.key
    for _, size in ipairs(Sync.TEST_SIZES) do
        local id = Transport.NextId()
        local head = Codec.Header(Transport.Code(), "T", id, 1, 1)
        local body = "t," .. id .. "," .. size .. ","
        local pad = math.max(0, size - #head - #body)
        local text = head .. body .. string.rep("x", pad)
        local ok, res = ns.Compat.Try("C_ChatInfo.SendAddonMessage", Transport.Prefix(), text, "WHISPER", me)
        Sync.test.sent[#Sync.test.sent + 1] = { size = #text, result = ok and Transport.ResultName(res) or "error" }
    end
    ns.Log.Info(L.COMMTEST_SENT)
    ns.Events.After(5, Sync.CommTestReport)
end

function Sync.CommTestReport()
    local t = Sync.test
    if not t then return end
    local lines = { "Fellowship Ledger comms test | " .. tostring(ns.Compat.flavor) .. " | " .. date("%Y-%m-%d %H:%M") }
    for _, s in ipairs(t.sent) do lines[#lines + 1] = string.format("sent %d bytes: %s", s.size, s.result) end
    local got = {}
    for _, r in ipairs(t.received) do got[#got + 1] = r.wire .. (r.channel and ("/" .. tostring(r.channel)) or "") end
    lines[#lines + 1] = "received sizes: " .. (#got > 0 and table.concat(got, ", ") or "none")
    for event, shape in pairs(Transport.seen) do lines[#lines + 1] = "args " .. event .. ": " .. shape end
    lines[#lines + 1] = "self key: " .. tostring(ns.Store.key) .. " | own realm: " .. tostring(ns.Friends.OwnRealm())
    if Transport.selfMismatch then
        lines[#lines + 1] = "NOT recognised as self: sender '" .. Transport.selfMismatch.sender .. "' vs key '" .. Transport.selfMismatch.key .. "'"
    end
    local results = {}
    for name, n in pairs(Transport.stats.results) do results[#results + 1] = name .. "=" .. n end
    table.sort(results)
    lines[#lines + 1] = string.format("queue %d, sent %d, retried %d, failed %d, received %d, dropped %d; results %s",
        #Transport.queue, Transport.stats.sent, Transport.stats.retried, Transport.stats.failed, Transport.stats.received,
        Transport.stats.dropped, table.concat(results, " "))
    local peers, online = 0, 0
    for _, p in pairs(ns.Friends.peers) do
        peers = peers + 1
        if p.online then online = online + 1 end
    end
    lines[#lines + 1] = string.format("friends seen %d, online on this flavor %d, with ledger data %d", peers, online,
        (function() local n = 0 for _ in pairs(ns.db.friends) do n = n + 1 end return n end)())
    ns.db.dev.commtest = table.concat(lines, "\n")
    ns.CopyWindow:Show(L.COMMTEST_TITLE, ns.db.dev.commtest)
end

-- Start ----------------------------------------------------------------------------

local started = false
function Sync.Start()
    if started then return end
    started = true
    Sync.startedAt = now()
    Merge.firstLastNames = ns.Compat.flavor == "Forever"
    Transport.Start()
    if ns.Compat.IsDisabled("comms") then return end
    Friends.Refresh()
    ns.Events.On("BN_FRIEND_ACCOUNT_ONLINE", "sync", function()
        ns.Events.After(5, function() Sync.SyncAll(false) end)
    end)
    local friendPending = false
    local function soon()
        if friendPending then return end
        friendPending = true
        ns.Events.After(10, function()
            friendPending = false
            Sync.SyncAll(false)
        end)
    end
    ns.Events.On("FRIENDLIST_UPDATE", "sync", soon)
    ns.Events.On("BN_FRIEND_INFO_CHANGED", "sync", soon) -- fired ~300 times an hour on retail: throttled
    ns.Events.On("GROUP_ROSTER_UPDATE", "sync", function() Sync.AnnounceName() end)
    ns.Events.On("PLAYER_ENTERING_WORLD", "sync", function() ns.Events.After(5, Sync.AnnounceName) end)
    ns.Events.After(10, function() Sync.SyncAll(false) end)
    ns.Events.Every(Sync.INTERVAL, "sync", function() Sync.SyncAll(false) end)
    ns.Events.Every(Sync.LIVE_EVERY, "sync", Sync.SendLive)
end
