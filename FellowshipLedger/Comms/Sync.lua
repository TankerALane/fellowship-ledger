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
Sync.relayed = {}        -- "peer id|character key" -> lastSeen of the copy relayed to them (D-124)
Sync.optedIn = {}        -- party member names who sent a NAME note this session
Sync.test = nil

local function now() return time() end

-- Relaying between mutual friends (D-124): on unless switched off or sharing is paused.
function Sync.RelayOn()
    local s = ns.db.settings
    return s.relayFriends ~= false and not s.sharingPaused
end

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
    local noRelay = {}
    for key in pairs(ns.db.blocklist or {}) do noRelay[#noRelay + 1] = ns.Relay.Hash(key) end
    table.sort(noRelay)
    local body = Codec.EncodeHello({ version = ns.VERSION, nameOptIn = ns.db.settings.shareNameInDungeons,
        wantReply = wantReply, characters = Sync.MyCharacters(), removed = removed,
        relay = Sync.RelayOn(), noRelay = noRelay })
    Transport.Send(destFor(peer), "H", body)
end

function Sync.RequestFrom(peer)
    local t = now()
    if Sync.lastRequest[peer.id] and t - Sync.lastRequest[peer.id] < Sync.REQUEST_GAP then return end
    Sync.lastRequest[peer.id] = t
    local f = ns.db.friends[peer.id]
    local since = f and f.syncedThrough and ns.Days.Shift(f.syncedThrough, -1, time, date) or nil
    -- What I hold of other friends, so this friend can relay newer copies (only to a
    -- friend whose ledger relays: older versions would not use it).
    local known = (Sync.RelayOn() and f and f.relay) and ns.Relay.Known(ns.db.friends, ns.db.blocklist, peer.id) or nil
    Transport.Send(destFor(peer), "Q", Codec.EncodeRequest(since, known))
end

-- Relay (D-124): send peer my newer copies of friends' characters they listed.
function Sync.SendRelays(peer, theirs)
    if not (theirs and Sync.RelayOn()) or Friends.IsBlocked(peer) then return 0 end
    local f = ns.db.friends[peer.id]
    if not (f and f.relay) then return 0 end
    local n = 0
    for _, pick in ipairs(ns.Relay.Pick(ns.db.friends, ns.db.blocklist, peer, theirs)) do
        local memo = peer.id .. "|" .. pick.key
        if Sync.relayed[memo] ~= pick.char.lastSeen then
            Sync.relayed[memo] = pick.char.lastSeen
            local shared = Codec.MaskToSet(pick.char.mask or "")
            -- From the day before their copy's last play: what they miss, and a little more.
            local since = date("%Y-%m-%d", pick.theirs - 86400)
            local body = Codec.EncodeData(pick.key, ns.Relay.AsOwn(pick.char), shared, since)
            n = n + Transport.Send(destFor(peer), "R", body)
            Sync.relaySent = (Sync.relaySent or 0) + 1
        end
    end
    return n
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

-- "Hamlet joined your ledger" (D-099): the first hello from a friend. Not during the
-- first 15 minutes after the ledger is installed, when every friend is new.
Sync.JOIN_GRACE = 900
Transport.handlers.H = function(peer, body)
    local hello = Codec.DecodeHello(body)
    local friend = friendRecord(peer)
    local fresh = friend.version == nil
    Merge.Hello(friend, hello, now())
    if fresh and ns.db.joinNoticesFrom and now() >= ns.db.joinNoticesFrom then
        Sync.Notify({ event = { kind = "joined" }, friendName = friend.name or peer.id, friendId = peer.id })
    end
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
    local req = Codec.DecodeRequest(body)
    Sync.SendData(peer, req.since)
    Sync.SendRelays(peer, req.known)
end

-- A friend's chains as { key = { step, total, name } } (theirs plus the ones worked out
-- here from their quest log), for the "finished a chain" notice.
local function chainState(c)
    if not c or not ns.QuestChains then return nil end
    local ok, chains = pcall(ns.QuestChains.FriendChains, c)
    if not ok or type(chains) ~= "table" then return nil end
    local out = {}
    for key, ch in pairs(chains) do out[key] = { step = ch.step, total = ch.total, name = ch.name or ch.firstName } end
    return out
end

-- Chains that were on their last step and are gone from the log now. (Abandoning the
-- last quest looks the same; the game does not tell us which.)
function Sync.FinishedChains(before, after)
    local out = {}
    for key, ch in pairs(before or {}) do
        if ch.step and ch.total and ch.step >= ch.total and not (after or {})[key] then out[#out + 1] = ch.name or key end
    end
    table.sort(out)
    return out
end

function Sync.MilestoneText(e, friendName)
    return ns.Notices.Text(e, friendName, L)
end

-- Friend notices (D-099) ------------------------------------------------------------
-- Notices that arrive close together become one; the ones in the first two minutes
-- after login are "While you were away". Each notice opens the friend's page on click.
Sync.queue = {}
local queueGen, queueFirst = 0, nil

function Sync.OpenTarget(target)
    if not target then return end
    if ns.FriendsTab and ns.FriendsTab.Open then ns.FriendsTab.Open(target.friendId, target.key, target.view) end
end

local function showNotice(items, away)
    local title, lines, target = ns.Notices.Build(items, L, away)
    if title then ns.Toast.Show(title, lines, { onClick = function() Sync.OpenTarget(target) end }) end
end

-- A friend's looted item for its notice (D-105): the game's link (colored, clickable
-- in chat), else the name. The name loaded while the notice waited to be shown.
local function itemText(id)
    if not (ns.QuestRewards and ns.QuestRewards.ItemInfo) then return nil end
    local ok, name, _, link = pcall(ns.QuestRewards.ItemInfo, id)
    if not ok or not name then return nil end
    return link or name
end

function Sync.FlushNotices()
    local items, first = Sync.queue, queueFirst
    Sync.queue, queueFirst = {}, nil
    queueGen = queueGen + 1
    for _, it in ipairs(items) do
        local e = it.event
        if e and e.kind == "loot" and not e.itemText then e.itemText = itemText(e.itemID) end
    end
    local settings = ns.db.settings
    local away = ns.Notices.IsAway(settings, Sync.startedAt, first)
    local shown = ns.Notices.Select(items, settings, away)
    if #shown == 0 then return end
    if away or settings.toastBundle ~= false then
        showNotice(shown, away)
    else
        for _, it in ipairs(shown) do showNotice({ it }, false) end
    end
end

-- Queue one notice. items: { event, friendName, friendId }.
function Sync.Notify(item)
    local t = now()
    Sync.queue[#Sync.queue + 1] = item
    queueFirst = queueFirst or t
    local settings = ns.db.settings
    local away = ns.Notices.IsAway(settings, Sync.startedAt, queueFirst)
    if not away and settings.toastBundle == false then return Sync.FlushNotices() end
    if t - queueFirst >= ns.Notices.BUNDLE_MAX_SECONDS then return Sync.FlushNotices() end
    queueGen = queueGen + 1
    local gen = queueGen
    ns.Events.After(ns.Notices.BUNDLE_SECONDS, function()
        if gen == queueGen then Sync.FlushNotices() end
    end)
end

Transport.handlers.D = function(peer, body)
    local data = Codec.DecodeData(body)
    if not data then return end
    local friend = friendRecord(peer)
    local today = ns.Store.Today()
    local cutoff = ns.Days.Shift(today, -(Merge.KEEP_DAYS - 1), time, date)
    local known = friend.characters[data.key]
    local chainsBefore = known and chainState(known)
    local events = Merge.Data(friend, data, today, cutoff, now())
    -- Straight from the friend: no longer "via" anyone (D-124).
    friend.characters[data.key].via, friend.characters[data.key].viaAt = nil, nil
    -- Finished chains (D-098): only while Quests is shared, and only for a character we knew.
    if chainsBefore and Codec.MaskToSet(data.mask or "").quests then
        local c = friend.characters[data.key]
        for _, name in ipairs(Sync.FinishedChains(chainsBefore, chainState(c))) do
            events[#events + 1] = { kind = "chain", character = c.display or c.name or data.key, chain = name, key = data.key }
        end
    end
    for _, e in ipairs(events) do
        if e.kind == "loot" then itemText(e.itemID) end -- start loading the item's name
        Sync.Notify({ event = e, friendName = friend.name or peer.id, friendId = peer.id })
    end
    if ns.MainWindow.frame and ns.MainWindow.frame:IsShown() then ns.MainWindow.Refresh() end
end

-- RELAY (D-124): a friend's character's newer data, passed on by peer. Kept only for a
-- character I already have from that friend directly, only when newer than my copy,
-- and only while relaying is on. It is merged like their own DATA, marked "via".
Transport.handlers.R = function(peer, body)
    if not Sync.RelayOn() then return end
    local data = Codec.DecodeData(body)
    if not data then return end
    local id, friend, c = ns.Relay.Owner(ns.db.friends, ns.db.blocklist, data.key, peer.id)
    if not friend or (c.lastSeen or 0) >= (data.lastSeen or 0) then
        Sync.relayDropped = (Sync.relayDropped or 0) + 1
        return
    end
    local today = ns.Store.Today()
    local cutoff = ns.Days.Shift(today, -(Merge.KEEP_DAYS - 1), time, date)
    -- A relay carries one character: the friend's next direct REQUEST still asks from
    -- where their own DATA left off, so their other characters miss nothing.
    local synced = friend.syncedThrough
    local events = Merge.Data(friend, data, today, cutoff, now())
    friend.syncedThrough = synced
    local merged = friend.characters[data.key]
    merged.via, merged.viaAt = peer.name or peer.id, now()
    Sync.relayReceived = (Sync.relayReceived or 0) + 1
    for _, e in ipairs(events) do
        if e.kind == "loot" then itemText(e.itemID) end
        Sync.Notify({ event = e, friendName = friend.name or id, friendId = id })
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

local function groupChannel()
    local channel = "PARTY"
    local ok, inInstanceGroup = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_INSTANCE)
    if ok and inInstanceGroup then channel = "INSTANCE_CHAT" end
    return channel
end

local function inGroup()
    local ok, g = pcall(IsInGroup)
    return ok and g == true
end

-- Announce my name to the dungeon group, if I opted in.
local lastName = 0
function Sync.AnnounceName()
    if not ns.db.settings.shareNameInDungeons or not ns.Store.char or not ns.Store.char.currentRun then return end
    if now() - lastName < Sync.NAME_GAP then return end
    lastName = now()
    Transport.Send({ transport = "group", target = groupChannel() }, "N", Codec.EncodeName(ns.Store.key))
end

-- One start for the whole group (D-127) ------------------------------------------------
-- Group members who run the ledger tell each other when their run's clock started, and
-- each keeps the earliest. Sent to the party or instance channel, so it is taken from
-- any group member, friend or not: it can only start your clock earlier (a slower
-- time), never give you a faster one. The time is "seconds ago", worked out when it
-- is queued; the queue holds in combat, so a start found in combat waits for it to end.
Sync.START_REPLY_GAP = 10
local startWanted, lastStartReply = false, 0

local function sendStart(run, ask)
    if not inGroup() then return end
    local ago = run.started and math.max(0, now() - run.started) or nil
    Transport.Send({ transport = "group", target = groupChannel() }, "S", Codec.EncodeStart(run.name, ago, run.partial, ask))
end

local function inCombat()
    local ok, c = pcall(InCombatLockdown)
    return ok and c == true
end

-- My run's clock just started: tell the group (after combat).
function Sync.ShareStart(run)
    if inCombat() then startWanted = true return end
    sendStart(run, false)
end

-- I just came in: ask the group when their run started.
function Sync.AskStart(run)
    sendStart(run, true)
end

function Sync.StartAfterCombat()
    if not startWanted then return end
    startWanted = false
    local run = ns.Store.char and ns.Store.char.currentRun
    if run and run.started then sendStart(run, false) end
end

Transport.handlers.S = function(_, body, info)
    if ns.Friends.IsSelf(info.sender) then return end
    local s = Codec.DecodeStart(body)
    local run = ns.Store.char and ns.Store.char.currentRun
    if not (s and run and run.name == s.dungeon) then return end
    if s.ago then
        local who = type(info.sender) == "string" and info.sender:match("^([^%-]+)") or "?"
        local D = ns.Trackers.byId and ns.Trackers.byId.dungeons
        if D and D.AdoptStart(s.dungeon, now() - s.ago, s.partial, who) then
            Sync.startsAdopted = (Sync.startsAdopted or 0) + 1
        end
    end
    if s.ask and run.started and now() - lastStartReply >= Sync.START_REPLY_GAP then
        lastStartReply = now()
        if inCombat() then startWanted = true else sendStart(run, false) end
    end
end

-- Sync everyone ------------------------------------------------------------------

-- changedOnly (friend-list events, which fire very often): only friends who came
-- online on this game version or switched character since the last look. Login,
-- the 15-minute timer, the Friends tab and Sync now still greet everyone online.
Sync.seen = {} -- peer id -> "online|character" at the last look
function Sync.SyncAll(force, changedOnly)
    Friends.Refresh()
    local count = 0
    for id, peer in pairs(Friends.peers) do
        local state = tostring(peer.online) .. "|" .. tostring(peer.character)
        local changed = Sync.seen[id] ~= state
        Sync.seen[id] = state
        if peer.online and not Friends.IsBlocked(peer) and (changed or not changedOnly) then
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

-- Weekly recap (D-109) ---------------------------------------------------------------
-- Once per weekly reset, on the first login after it (or when a reset passes while
-- playing): last week for you and each friend. A click opens the Friends tab's weekly
-- panel, which lists it too.
Sync.WEEKLY_DELAY = 25 -- seconds after login, after the "While you were away" notice starts
function Sync.LastReset()
    local okR, secs = ns.Compat.Try("C_DateAndTime.GetSecondsUntilWeeklyReset")
    return ns.Weekly.LastReset(now(), okR and ns.Trackers.Plain(secs) or nil)
end

function Sync.CheckWeekly()
    if ns.Data.IsFake() then return end
    local settings = ns.db.settings
    local last = Sync.LastReset()
    if not ns.Weekly.Due(settings, ns.db.weeklyRecapSeen, last) then return end
    ns.db.weeklyRecapSeen = last
    local fromKey, toKey = ns.Weekly.Range(last, date)
    local rows = ns.Weekly.Rows(ns.db.characters, ns.db.friends, ns.db.blocklist, fromKey, toKey, L)
    local title, lines = ns.Weekly.Notice(rows, L)
    if title then
        ns.Toast.Show(title, lines, { onClick = function()
            if ns.FriendsTab and ns.FriendsTab.OpenWeekly then ns.FriendsTab.OpenWeekly() end
        end })
    end
end

-- Start ----------------------------------------------------------------------------

local started = false
function Sync.Start()
    if started then return end
    started = true
    Sync.startedAt = now()
    ns.db.joinNoticesFrom = ns.db.joinNoticesFrom or (now() + Sync.JOIN_GRACE)
    Merge.firstLastNames = ns.Compat.flavor == "Forever"
    -- The level cap, for the "reached the level cap" notice (D-098). Unverified on both
    -- clients (VerifyChecks): without either, that notice is simply never shown.
    local okMax, maxLevel = ns.Compat.Try("GetMaxLevelForPlayerExpansion")
    if not (okMax and type(maxLevel) == "number" and maxLevel > 0) then maxLevel = ns.Compat.Resolve("MAX_PLAYER_LEVEL") end
    Merge.maxLevel = type(maxLevel) == "number" and maxLevel > 0 and maxLevel or nil
    -- The weekly recap works without sharing too (your own week).
    ns.Events.After(Sync.WEEKLY_DELAY, function() pcall(Sync.CheckWeekly) end)
    ns.Events.Every(600, "weekly", function() pcall(Sync.CheckWeekly) end)
    Transport.Start()
    if ns.Compat.IsDisabled("comms") then return end
    Friends.Refresh()
    ns.Events.On("BN_FRIEND_ACCOUNT_ONLINE", "sync", function()
        ns.Events.After(5, function() Sync.SyncAll(false, true) end)
    end)
    local friendPending = false
    local function soon()
        if friendPending then return end
        friendPending = true
        ns.Events.After(10, function()
            friendPending = false
            Sync.SyncAll(false, true)
        end)
    end
    ns.Events.On("FRIENDLIST_UPDATE", "sync", soon)
    ns.Events.On("BN_FRIEND_INFO_CHANGED", "sync", soon) -- fired ~300 times an hour on retail: throttled
    ns.Events.On("GROUP_ROSTER_UPDATE", "sync", function() Sync.AnnounceName() end)
    ns.Events.On("PLAYER_REGEN_ENABLED", "sync", function() Sync.StartAfterCombat() end)
    ns.Events.On("PLAYER_ENTERING_WORLD", "sync", function() ns.Events.After(5, Sync.AnnounceName) end)
    ns.Events.After(10, function() Sync.SyncAll(false) end)
    ns.Events.Every(Sync.INTERVAL, "sync", function() Sync.SyncAll(false) end)
    ns.Events.Every(Sync.LIVE_EVERY, "sync", Sync.SendLive)
end
