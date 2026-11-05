-- Comms/Friends.lua
-- Finds friends who could run the ledger on THIS client flavor:
--  * Battle.net friends: online WoW game accounts whose wowProjectID matches ours
--    (fields confirmed on retail: clientProgram, wowProjectID, characterName,
--    realmName, gameAccountID, isOnline). Peer id "bn:<BattleTag>".
--  * Character friends: C_FriendList entries (fields not yet seen in a report:
--    name, connected - guarded). Peer id "ch:<Name-Realm>". A character friend who
--    is also a Battle.net friend's current character is left to the Battle.net peer.
-- Only friends are ever messaged or listened to.

local _, ns = ...
local T = ns.Trackers

local Friends = {}
ns.Friends = Friends

Friends.peers = {}         -- id -> peer { id, kind, name, tag, online, target, transport }
Friends.byGameAccount = {} -- gameAccountID -> peer
Friends.byCharacter = {}   -- "Name-Realm" -> peer

local function plain(v) return T.Plain(v) end

-- The second half of my character key. On retail that is my realm. On Forever
-- it is my last name (D-064): Forever characters are "First Last", the game uses
-- "First-Last" where retail uses "Name-Realm", and the real realm is an internal
-- ID such as "CAMWOWUS1Realm3PvE" that never appears in names. Either way it is
-- what a one-word sender name is completed with.
function Friends.OwnRealm()
    local key = ns.Store and ns.Store.key
    local fromKey = key and key:match("^[^%-]+%-(.+)$")
    if fromKey and fromKey ~= "" then return (fromKey:gsub("%s", "")) end
    local ok, realm = ns.Compat.Call("friends", "GetNormalizedRealmName")
    return ok and plain(realm) or ((GetRealmName() or ""):gsub("%s", ""))
end

-- Split "Name-Realm", "Name Realm" or "Name" into two parts. On Forever these are
-- "First-Last" / "First Last" (how addon-message senders and Battle.net
-- characterName look there). Neither part contains a space or hyphen.
function Friends.SplitName(full)
    if type(full) ~= "string" then return nil end
    local name, realm = full:match("^%s*([^%-%s]+)[%-%s]+(.-)%s*$")
    if name then return name, realm ~= "" and realm or nil end
    name = full:match("^%s*([^%-%s]+)%s*$")
    return name, nil
end

-- Any of those forms (or name + separate realm) -> "Name-Realm" with no spaces.
function Friends.FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local n, r = Friends.SplitName(name)
    if not n then return nil end
    r = r or (type(realm) == "string" and realm ~= "" and realm) or Friends.OwnRealm()
    return n .. "-" .. (r:gsub("%s", ""))
end

function Friends.Self()
    return ns.Store.key
end

-- Character names compared without spaces or case: realm names can come back as
-- "Some Realm" from one API and "SomeRealm" from another (seen on Forever, where
-- /fl commtest whispers to yourself were not recognised).
function Friends.Normalize(full)
    return (tostring(full or ""):gsub("%s", ""):lower())
end

-- Do two character names (any of the forms above) mean the same character?
function Friends.SameCharacter(a, b)
    local fa, fb = Friends.FullName(a), Friends.FullName(b)
    return fa ~= nil and fb ~= nil and Friends.Normalize(fa) == Friends.Normalize(fb)
end

-- Is this whisper sender me? A sender without a realm is on my realm.
function Friends.IsSelf(sender)
    local key = ns.Store.key
    if type(sender) ~= "string" or sender == "" or not key then return false end
    return Friends.SameCharacter(sender, key)
end

local function sameFlavor(projectID)
    local ours = _G.WOW_PROJECT_ID
    projectID = plain(projectID)
    return projectID == nil or ours == nil or projectID == ours
end

function Friends.Refresh()
    local peers, byGame, byChar = {}, {}, {}
    local wowClient = _G.BNET_CLIENT_WOW or "WoW"
    -- Battle.net friends
    local okN, total = ns.Compat.Call("friends", "BNGetNumFriends")
    for i = 1, okN and (plain(total) or 0) or 0 do
        local okA, acc = ns.Compat.Call("friends", "C_BattleNet.GetFriendAccountInfo", i)
        local tag = okA and type(acc) == "table" and plain(acc.battleTag)
        if tag then
            local peer = { id = "bn:" .. tag, kind = "bnet", tag = tag, name = tag:match("^([^#]+)") or tag,
                online = false, transport = "bn" }
            local okC, count = ns.Compat.Call("friends", "C_BattleNet.GetFriendNumGameAccounts", i)
            for j = 1, okC and (plain(count) or 0) or 0 do
                local okG, g = ns.Compat.Call("friends", "C_BattleNet.GetFriendGameAccountInfo", i, j)
                if okG and type(g) == "table" and plain(g.clientProgram) == wowClient and g.isOnline ~= false
                    and sameFlavor(g.wowProjectID) and plain(g.gameAccountID) then
                    peer.online = true
                    peer.target = plain(g.gameAccountID)
                    byGame[peer.target] = peer
                    local full = Friends.FullName(plain(g.characterName), plain(g.realmDisplayName) or plain(g.realmName))
                    if full then
                        peer.character = full
                        byChar[Friends.Normalize(full)] = peer
                    end
                end
            end
            peers[peer.id] = peer
        end
    end
    -- Character friends (whispered by the name the game gave us)
    local okF, n = ns.Compat.Call("friends", "C_FriendList.GetNumFriends")
    for i = 1, okF and (plain(n) or 0) or 0 do
        local okI, info = ns.Compat.Call("friends", "C_FriendList.GetFriendInfoByIndex", i)
        local raw = okI and type(info) == "table" and plain(info.name)
        local full = raw and Friends.FullName(raw)
        if full and not byChar[Friends.Normalize(full)] then
            local peer = { id = "ch:" .. full, kind = "char", tag = full, name = full, online = plain(info.connected) == true,
                target = raw, transport = "whisper", character = full }
            peers[peer.id] = peer
            byChar[Friends.Normalize(full)] = peer
        end
    end
    Friends.peers, Friends.byGameAccount, Friends.byCharacter = peers, byGame, byChar
    -- Keep the online flag of stored friends current for the Friends tab.
    for id, f in pairs(ns.db.friends) do
        local p = peers[id]
        f.online = p ~= nil and p.online or false
    end
    return peers
end

-- Which peer sent this? transport "bn": sender is a gameAccountID; "whisper": a name.
function Friends.PeerFor(transport, sender)
    if transport == "bn" then
        local p = Friends.byGameAccount[sender]
        if not p then
            Friends.Refresh()
            p = Friends.byGameAccount[sender]
        end
        return p
    end
    local full = Friends.FullName(sender)
    if not full then return nil end
    local key = Friends.Normalize(full)
    local p = Friends.byCharacter[key]
    if not p then
        Friends.Refresh()
        p = Friends.byCharacter[key]
    end
    return p
end

function Friends.IsBlocked(peer)
    return ns.FriendsModel.IsBlocked(ns.db.blocklist, { tag = peer.tag }, peer.character)
end

-- /fl friends: what the game reports about each friend and whether the ledger
-- would message them. Never sends anything. BattleTag numbers are left out.
function Friends.Report()
    local function show(v)
        v = plain(v)
        if v == nil then return "nil" end
        return ns.Compat.Describe(v)
    end
    local lines = { "Fellowship Ledger friends report | " .. tostring(ns.Compat.flavor) .. " | " .. date("%Y-%m-%d %H:%M"),
        "me: " .. tostring(ns.Store.key) .. " | WOW_PROJECT_ID " .. show(_G.WOW_PROJECT_ID)
            .. " | BNET_CLIENT_WOW " .. show(_G.BNET_CLIENT_WOW) }
    local wowClient = _G.BNET_CLIENT_WOW or "WoW"
    local okN, total = ns.Compat.Try("BNGetNumFriends")
    lines[#lines + 1] = "Battle.net friends: " .. (okN and show(total) or "BNGetNumFriends unavailable")
    for i = 1, okN and (tonumber(plain(total)) or 0) or 0 do
        local okA, acc = ns.Compat.Try("C_BattleNet.GetFriendAccountInfo", i)
        local tag = okA and type(acc) == "table" and plain(acc.battleTag)
        local name = type(tag) == "string" and (tag:match("^([^#]+)") or tag) or ("#" .. i)
        local okC, count = ns.Compat.Try("C_BattleNet.GetFriendNumGameAccounts", i)
        local n = okC and tonumber(plain(count)) or 0
        if okA and type(acc) == "table" then
            local g0 = type(acc.gameAccountInfo) == "table" and acc.gameAccountInfo or nil
            lines[#lines + 1] = string.format("%d. %s | online %s | game accounts %s%s", i, name, show(acc.isOnline),
                okC and show(count) or "?", g0 and (" | current: client " .. show(g0.clientProgram) .. ", project "
                .. show(g0.wowProjectID) .. ", id " .. show(g0.gameAccountID)) or "")
        else
            lines[#lines + 1] = string.format("%d. (no account info)", i)
        end
        for j = 1, n do
            local okG, g = ns.Compat.Try("C_BattleNet.GetFriendGameAccountInfo", i, j)
            if okG and type(g) == "table" then
                local why = {}
                if plain(g.clientProgram) ~= wowClient then why[#why + 1] = "not WoW" end
                if g.isOnline == false then why[#why + 1] = "offline" end
                if not sameFlavor(g.wowProjectID) then why[#why + 1] = "other game version" end
                if not plain(g.gameAccountID) then why[#why + 1] = "no gameAccountID" end
                lines[#lines + 1] = string.format("   game %d: client %s, project %s, online %s, id %s, char %s, realm %s / %s -> %s",
                    j, show(g.clientProgram), show(g.wowProjectID), show(g.isOnline), show(g.gameAccountID),
                    show(g.characterName), show(g.realmName), show(g.realmDisplayName),
                    #why == 0 and "WILL MESSAGE" or ("skipped: " .. table.concat(why, ", ")))
            else
                lines[#lines + 1] = string.format("   game %d: no info", j)
            end
        end
    end
    local okF, nf = ns.Compat.Try("C_FriendList.GetNumFriends")
    lines[#lines + 1] = "Character friends: " .. (okF and show(nf) or "C_FriendList.GetNumFriends unavailable")
    for i = 1, okF and (tonumber(plain(nf)) or 0) or 0 do
        local okI, info = ns.Compat.Try("C_FriendList.GetFriendInfoByIndex", i)
        if okI and type(info) == "table" then
            lines[#lines + 1] = string.format("%d. name %s, connected %s -> %s", i, show(info.name), show(info.connected),
                plain(info.connected) == true and "WILL MESSAGE" or "skipped: offline")
        else
            lines[#lines + 1] = string.format("%d. no info", i)
        end
    end
    Friends.Refresh()
    local stored = 0
    for id, f in pairs(ns.db.friends) do
        stored = stored + 1
        local nchar = 0
        for _ in pairs(f.characters or {}) do nchar = nchar + 1 end
        lines[#lines + 1] = string.format("ledger friend %s: version %s, hello %s, characters %d", tostring(f.name or id),
            tostring(f.version), f.helloAt and date("%H:%M:%S", f.helloAt) or "never", nchar)
    end
    if stored == 0 then lines[#lines + 1] = "no ledger data from any friend yet" end
    lines[#lines + 1] = "disabled: comms " .. tostring(ns.Compat.disabled.comms or "-") .. ", friends "
        .. tostring(ns.Compat.disabled.friends or "-")
    return table.concat(lines, "\n")
end
