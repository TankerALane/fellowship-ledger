-- Comms/Codec.lua
-- PURE: no WoW globals. The sync protocol's text format (docs/PROTOCOL.md):
-- escaping, field codes, the share filter, HELLO / REQUEST / DATA / NAME bodies,
-- chunking into addon-message-sized pieces, and reassembly.

local _, ns = ...

local Codec = {}
ns.Codec = Codec

Codec.PROTO = 1
Codec.DEFAULT_CHUNK = 200       -- bytes per addon message, header included
Codec.MIN_CHUNK, Codec.MAX_CHUNK = 60, 255
Codec.REASSEMBLY_TIMEOUT = 120  -- seconds before a half-received message is dropped
Codec.MAX_SESSIONS = 60         -- sessions sent per character per DATA
Codec.TYPES = { H = "HELLO", Q = "REQUEST", D = "DATA", N = "NAME", T = "TEST" }

-- Escaping: the separators and "%" become %XX.
local SPECIAL = "[%%|,;~=\n\r%z]"
function Codec.Escape(s)
    return (tostring(s == nil and "" or s):gsub(SPECIAL, function(c) return string.format("%%%02X", c:byte()) end))
end
function Codec.Unescape(s)
    return (tostring(s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Day-bucket / session-count fields: short wire code and the tracker that owns them.
-- "time" fields are shared when the character shares anything at all.
Codec.FIELDS = {
    played = { "pl", "time" }, active = { "ac", "time" },
    levels = { "lv", "levels" }, xp = { "xp", "levels" },
    quests = { "qu", "quests" }, questsAccepted = { "qa", "quests" },
    moneyNet = { "mn", "gold" }, moneyIn = { "mi", "gold" }, moneyOut = { "mo", "gold" },
    money_loot = { "ml", "gold" }, money_vendor = { "mv", "gold" }, money_quest = { "mq", "gold" },
    money_mail = { "mm", "gold" }, money_auction = { "ma", "gold" }, money_other = { "mx", "gold" },
    dungeonsEntered = { "de", "dungeons" }, dungeonsCompleted = { "dc", "dungeons" }, bossKills = { "bk", "dungeons" },
    skillUps = { "su", "professions" }, deaths = { "dt", "deaths" },
    zonesNew = { "zn", "zones" }, zonesDiscovered = { "zd", "zones" },
    repGained = { "rg", "reputation" }, kills = { "kl", "kills" }, rareKills = { "kr", "kills" },
    eliteKills = { "ke", "kills" }, flightPaths = { "fp", "flightPaths" }, achievements = { "av", "achievements" },
    partyLevelUps = { "pu", "partyLevels" },
    itemsNotable = { "in", "items" }, itemsEpic = { "ie", "items" },
}
Codec.BY_CODE = {}
for field, def in pairs(Codec.FIELDS) do Codec.BY_CODE[def[1]] = field end

-- Share filter --------------------------------------------------------------------

-- Set of tracker ids this character shares (empty when sharing is paused).
function Codec.SharedTrackers(char, paused)
    local set, any = {}, false
    for _, t in ipairs(ns.TrackerList.ORDER) do
        if ns.TrackerList.IsSharing(char, t.id, paused) then
            set[t.id] = true
            any = true
        end
    end
    if any then set.time = true end
    return set, any
end

-- "1"/"0" per tracker in TrackerList order.
function Codec.ShareMask(set)
    local out = {}
    for i, t in ipairs(ns.TrackerList.ORDER) do out[i] = set[t.id] and "1" or "0" end
    return table.concat(out)
end

function Codec.MaskToSet(mask)
    local set = {}
    for i, t in ipairs(ns.TrackerList.ORDER) do
        if mask:sub(i, i) == "1" then set[t.id] = true end
    end
    return set
end

local function encodeCounts(counts, shared)
    local parts = {}
    local fields = {}
    for field in pairs(counts or {}) do fields[#fields + 1] = field end
    table.sort(fields)
    for _, field in ipairs(fields) do
        local def = Codec.FIELDS[field]
        local v = counts[field]
        if def and shared[def[2]] and type(v) == "number" and v ~= 0 then
            parts[#parts + 1] = def[1] .. "=" .. string.format("%d", v)
        end
    end
    return parts
end

local function decodeCounts(parts, from)
    local counts = {}
    for i = from, #parts do
        local code, v = parts[i]:match("^(%w+)=(%-?%d+)$")
        local field = code and Codec.BY_CODE[code]
        if field then counts[field] = tonumber(v) end
    end
    return counts
end

local function split(s, sep)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = piece end
    return out
end

-- Bodies --------------------------------------------------------------------------

-- chars: list of { key, char } of characters that share anything.
function Codec.EncodeHello(info)
    local recs = { table.concat({ "h", Codec.Escape(info.version), info.nameOptIn and "1" or "0", info.wantReply and "1" or "0" }, ",") }
    for _, c in ipairs(info.characters or {}) do
        recs[#recs + 1] = table.concat({ "c", Codec.Escape(c.key), Codec.Escape(c.class), tostring(c.level or 0),
            c.mask, tostring(c.lastSeen or 0) }, ",")
    end
    -- Characters I removed from my ledger: friends drop them (1.0.1; older
    -- versions ignore record types they do not know).
    for _, key in ipairs(info.removed or {}) do recs[#recs + 1] = "x," .. Codec.Escape(key) end
    return table.concat(recs, "~")
end

function Codec.DecodeHello(body)
    local out = { characters = {}, removed = {} }
    for _, rec in ipairs(split(body, "~")) do
        local f = split(rec, ",")
        if f[1] == "h" then
            out.version, out.nameOptIn, out.wantReply = Codec.Unescape(f[2]), f[3] == "1", f[4] == "1"
        elseif f[1] == "c" and f[2] and f[2] ~= "" then
            out.characters[#out.characters + 1] = { key = Codec.Unescape(f[2]), class = Codec.Unescape(f[3]),
                level = tonumber(f[4]) or 0, mask = f[5] or "", lastSeen = tonumber(f[6]) or 0 }
        elseif f[1] == "x" and f[2] and f[2] ~= "" then
            out.removed[#out.removed + 1] = Codec.Unescape(f[2])
        end
    end
    return out
end

-- since: "YYYY-MM-DD" or nil for everything kept.
function Codec.EncodeRequest(since) return "q," .. (since or "") end
function Codec.DecodeRequest(body)
    local since = body:match("^q,(%d%d%d%d%-%d%d%-%d%d)")
    return { since = since }
end

-- One character's shared data since `since` (nil = all). Returns nil if it shares nothing.
function Codec.EncodeData(key, char, shared, since)
    local recs = { table.concat({ "c", Codec.Escape(key), Codec.Escape(char.class), Codec.Escape(char.race),
        Codec.Escape(char.faction), tostring(char.level or 0), tostring(char.lastSeen or 0), Codec.ShareMask(shared) }, ",") }
    local days = {}
    for day in pairs(char.days or {}) do
        if not since or day >= since then days[#days + 1] = day end
    end
    table.sort(days)
    for _, day in ipairs(days) do
        local parts = encodeCounts(char.days[day], shared)
        if #parts > 0 then recs[#recs + 1] = "d," .. day .. "," .. table.concat(parts, ",") end
    end
    if shared.levels then
        local levels = {}
        for to in pairs(char.levels or {}) do levels[#levels + 1] = to end
        table.sort(levels)
        for _, to in ipairs(levels) do
            local r = char.levels[to]
            recs[#recs + 1] = table.concat({ "l", tostring(to), tostring(r.active or 0), tostring(r.total or 0),
                r.partial and "1" or "0", tostring(r.at or 0) }, ",")
        end
    end
    if shared.quests then
        local keys = {}
        for key in pairs(char.chains or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local ch = char.chains[key]
            recs[#recs + 1] = table.concat({ "k", Codec.Escape(key), Codec.Escape(ch.name), tostring(ch.step or 0),
                tostring(ch.total or 0), tostring(ch.firstQuestID or 0), Codec.Escape(ch.firstName), Codec.Escape(ch.startZone),
                Codec.Escape(ch.source) }, ",")
        end
    end
    local sessions = {}
    for _, s in ipairs(char.sessions or {}) do
        if not since or (s.stop or s.start or 0) >= ns.Codec.SinceEpoch(since) then sessions[#sessions + 1] = s end
    end
    for i = math.max(1, #sessions - Codec.MAX_SESSIONS + 1), #sessions do
        local s = sessions[i]
        local head = { "s", tostring(s.start or 0), tostring(s.played or 0), tostring(s.active or 0),
            tostring(s.levelStart or 0), tostring(s.levelEnd or 0) }
        for _, p in ipairs(encodeCounts(s.counts, shared)) do head[#head + 1] = p end
        recs[#recs + 1] = table.concat(head, ",")
    end
    return table.concat(recs, "~")
end

-- Rough epoch for a day key (noon UTC-ish); only used to choose which sessions to send.
function Codec.SinceEpoch(day)
    local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
    if not y then return 0 end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    -- days since 1970-01-01 (civil from days algorithm, inverted)
    if m <= 2 then y, m = y - 1, m + 12 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m - 3) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 - 86400
end

function Codec.DecodeData(body)
    local out = { days = {}, levels = {}, sessions = {}, chains = {} }
    for _, rec in ipairs(split(body, "~")) do
        local f = split(rec, ",")
        if f[1] == "c" then
            out.key, out.class, out.race, out.faction = Codec.Unescape(f[2]), Codec.Unescape(f[3]), Codec.Unescape(f[4]), Codec.Unescape(f[5])
            out.level, out.lastSeen, out.mask = tonumber(f[6]) or 0, tonumber(f[7]) or 0, f[8] or ""
        elseif f[1] == "d" and f[2] and f[2]:match("^%d%d%d%d%-%d%d%-%d%d$") then
            out.days[f[2]] = decodeCounts(f, 3)
        elseif f[1] == "l" and tonumber(f[2]) then
            local to = tonumber(f[2])
            out.levels[to] = { from = to - 1, to = to, active = tonumber(f[3]) or 0, total = tonumber(f[4]) or 0,
                partial = f[5] == "1" or nil, at = tonumber(f[6]) or 0 }
        elseif f[1] == "k" and f[2] and f[2] ~= "" then
            local function opt(v) v = Codec.Unescape(v) return v ~= "" and v or nil end
            out.chains[Codec.Unescape(f[2])] = { name = opt(f[3]), step = tonumber(f[4]), total = tonumber(f[5]),
                firstQuestID = tonumber(f[6]) ~= 0 and tonumber(f[6]) or nil, firstName = opt(f[7]), startZone = opt(f[8]),
                source = opt(f[9]) }
        elseif f[1] == "s" and tonumber(f[2]) then
            out.sessions[#out.sessions + 1] = { start = tonumber(f[2]), played = tonumber(f[3]) or 0, active = tonumber(f[4]) or 0,
                levelStart = tonumber(f[5]), levelEnd = tonumber(f[6]), counts = decodeCounts(f, 7) }
        end
    end
    if not out.key or out.key == "" then return nil end
    return out
end

function Codec.EncodeName(key) return "n," .. Codec.Escape(key) end
function Codec.DecodeName(body) return Codec.Unescape(body:match("^n,(.*)$") or "") end

-- Chunking ------------------------------------------------------------------------
-- Every piece: "<proto>|<flavorCode>|<type>|<msgId>|<seq>|<total>|<payload piece>"

function Codec.Header(flavorCode, mtype, msgId, seq, total)
    return table.concat({ Codec.PROTO, flavorCode, mtype, msgId, seq, total }, "|") .. "|"
end

function Codec.Chunk(flavorCode, mtype, msgId, body, chunkSize)
    chunkSize = math.max(Codec.MIN_CHUNK, math.min(Codec.MAX_CHUNK, chunkSize or Codec.DEFAULT_CHUNK))
    -- Header length grows with the piece count; size the pieces for the largest header.
    local probe = Codec.Header(flavorCode, mtype, msgId, 999, 999)
    local room = chunkSize - #probe
    local pieces = {}
    local i = 1
    repeat
        local piece = body:sub(i, i + room - 1)
        -- never cut an escape sequence (%XX) in half
        local cut = piece:find("%%%x?$")
        if cut and i + room - 1 < #body then piece = piece:sub(1, cut - 1) end
        pieces[#pieces + 1] = piece
        i = i + #piece
    until i > #body
    local out = {}
    for n, piece in ipairs(pieces) do out[n] = Codec.Header(flavorCode, mtype, msgId, n, #pieces) .. piece end
    return out
end

function Codec.ParseChunk(text)
    local proto, flavor, mtype, msgId, seq, total, piece = text:match("^(%d+)|(%a)|(%a)|(%w+)|(%d+)|(%d+)|(.*)$")
    if not proto then return nil end
    return { proto = tonumber(proto), flavor = flavor, type = mtype, msgId = msgId, seq = tonumber(seq),
        total = tonumber(total), piece = piece }
end

-- Reassembly: feed chunks per sender; returns the full body once all pieces arrived.
function Codec.NewReassembler()
    return { pending = {} }
end

function Codec.Feed(r, sender, chunk, now)
    for key, p in pairs(r.pending) do
        if now - p.at > Codec.REASSEMBLY_TIMEOUT then r.pending[key] = nil end
    end
    if chunk.total < 1 or chunk.seq < 1 or chunk.seq > chunk.total or chunk.total > 2000 then return nil end
    if chunk.total == 1 then return chunk.piece end
    local key = sender .. "/" .. chunk.msgId
    local p = r.pending[key]
    if not p then
        p = { total = chunk.total, pieces = {}, count = 0, at = now }
        r.pending[key] = p
    end
    if p.total ~= chunk.total then return nil end
    if not p.pieces[chunk.seq] then
        p.pieces[chunk.seq] = chunk.piece
        p.count = p.count + 1
    end
    p.at = now
    if p.count < p.total then return nil end
    r.pending[key] = nil
    return table.concat(p.pieces)
end
