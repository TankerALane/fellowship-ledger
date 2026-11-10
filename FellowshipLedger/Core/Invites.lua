-- Core/Invites.lua
-- PURE: no WoW globals. "Invite a friend" (D-114): which online friends do not run
-- the ledger yet, when each was last invited, and the invite text. Nothing here
-- sends anything; UI/InviteDialog.lua sends one whisper when the player clicks Send.

local _, ns = ...

local Invites = {}
ns.Invites = Invites

Invites.COOLDOWN = 7 * 86400 -- one invite per friend per week (Austin, D-114)
Invites.MAX_LETTERS = 255    -- the longest whisper the game sends
Invites.SETTLE_SECONDS = 60  -- after login, wait this long for friends' hellos before listing anyone
-- The addon's CurseForge page, for Copy link. Austin: check the address once the page is public.
Invites.URL = "https://www.curseforge.com/wow/addons/fellowship-ledger"

-- Online friends on this flavor who have never said hello (so do not run the ledger,
-- as far as we know). peers: Friends.peers; friends: db.friends; isBlocked(peer).
-- Returns { { id, name, kind, character, unknownGame } } sorted by name.
-- unknownGame: a Battle.net friend the game reports in WoW without a character or
-- project (Forever, D-066), who may be playing another version.
function Invites.Candidates(peers, friends, isBlocked)
    local out = {}
    for id, p in pairs(peers or {}) do
        local f = friends and friends[id]
        local known = f and f.version ~= nil
        if p.online and p.target and not known and not (isBlocked and isBlocked(p)) then
            out[#out + 1] = { id = id, name = p.name or id, kind = p.kind, character = p.character,
                unknownGame = (p.kind == "bnet" and not p.character) or nil }
        end
    end
    table.sort(out, function(a, b)
        local x, y = tostring(a.name):lower(), tostring(b.name):lower()
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return out
end

-- When this friend was last invited: nil if never, else { ago = seconds, waiting = true
-- while the week has not passed }. After the week the time is still shown (Austin:
-- "Invited 2 weeks ago", so you know an invite was sent).
function Invites.Status(lastAt, now)
    if type(lastAt) ~= "number" then return nil end
    local ago = math.max(0, now - lastAt)
    return { ago = ago, waiting = ago < Invites.COOLDOWN }
end

-- "today", "1 day ago", "3 days ago", "2 weeks ago", "4 months ago".
function Invites.Ago(seconds, L)
    local days = math.floor((seconds or 0) / 86400)
    if days < 1 then return L.INVITE_AGO_TODAY end
    if days < 14 then return string.format(days == 1 and L.INVITE_AGO_DAY or L.INVITE_AGO_DAYS, days) end
    if days < 60 then return string.format(L.INVITE_AGO_WEEKS, math.floor(days / 7)) end
    return string.format(L.INVITE_AGO_MONTHS, math.floor(days / 30))
end

-- The text of a candidate's line on the Friends tab.
function Invites.Line(c, status, L)
    local text = c.name
    if c.character then text = text .. " (" .. c.character .. ")" end
    if c.unknownGame then text = text .. " " .. L.INVITE_UNKNOWN_GAME end
    if status then text = text .. " - " .. string.format(L.INVITE_LAST, Invites.Ago(status.ago, L)) end
    return text
end

-- The message as the player left it: one line, trimmed, at most MAX_LETTERS
-- characters. nil when nothing is left to send.
function Invites.Clean(text)
    if type(text) ~= "string" then return nil end
    -- "|" starts the game's escape codes, which a chat message may not carry.
    text = text:gsub("[\r\n]+", " "):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if #text > Invites.MAX_LETTERS then text = text:sub(1, Invites.MAX_LETTERS) end
    return text
end
