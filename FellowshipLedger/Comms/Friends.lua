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

-- My realm as players see it. Taken from my own character key (UnitFullName),
-- because on Forever GetNormalizedRealmName returns an internal ID such as
-- "CAMWOWUS1Realm3PvE" instead of the realm's name.
function Friends.OwnRealm()
    local key = ns.Store and ns.Store.key
    local fromKey = key and key:match("^[^%-]+%-(.+)$")
    if fromKey and fromKey ~= "" then return (fromKey:gsub("%s", "")) end
    local ok, realm = ns.Compat.Call("friends", "GetNormalizedRealmName")
    return ok and plain(realm) or ((GetRealmName() or ""):gsub("%s", ""))
end

-- Split "Name-Realm", "Name Realm" (how Forever names addon-message senders) or
-- "Name" into name, realm. Character names never contain spaces or hyphens.
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
