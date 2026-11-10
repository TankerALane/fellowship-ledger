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
Codec.MAX_RUNS = 20             -- dungeon runs sent per character per DATA (the newest; D-095)
Codec.MAX_DEATHS = 10           -- recent deaths sent per character per DATA (D-105)
Codec.MAX_LOOT = 20             -- notable loot entries sent per character per DATA (D-105)
Codec.LOOT_MIN_QUALITY = 3      -- only blue (rare) or better is shared (Austin, D-105)
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
    -- Quest IDs in the log (1.2.1, D-087): "o,<id>,<id>,...", or just "o" for an empty log.
    if shared.quests and type(char.logQuests) == "table" then
        local parts = { "o" }
        for _, id in ipairs(char.logQuests) do parts[#parts + 1] = string.format("%d", id) end
        recs[#recs + 1] = table.concat(parts, ",")
    end
    -- Profession ranks (1.2.0, D-083): "p,<key>,<name>,<rank>,<max>,<lastAt>". Older
    -- versions skip record types they do not know.
    if shared.professions then
        local keys = {}
        for key in pairs(char.professions or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local pr = char.professions[key]
            recs[#recs + 1] = table.concat({ "p", Codec.Escape(key), Codec.Escape(pr.name), tostring(pr.rank or 0),
                tostring(pr.max or 0), tostring(pr.lastAt or 0) }, ",")
        end
        -- None (1.4.0): a bare "p" says "no professions", so receivers can tell that
        -- from an old sender. 1.2.x receivers skip a "p" with no key.
        if #keys == 0 then recs[#recs + 1] = "p" end
    end
    -- Dungeon runs (1.5.0, D-095): "u,<entered>,<name>,<duration>,<completed>,<bosses>,
    -- <bossCount>,<deaths>". Which dungeons were run, and how it went: finished runs since
    -- `since`, the newest MAX_RUNS. No boss names and nothing about the group.
    if shared.dungeons then
        local runs = {}
        local from = since and ns.Codec.SinceEpoch(since) or nil
        for _, r in ipairs(char.dungeons or {}) do
            if r.entered and (not from or r.entered >= from) then runs[#runs + 1] = r end
        end
        -- A completed run stays open after the final boss (D-112): send it now, so
        -- friends see the clear without waiting for it to close. It has the same entry
        -- time, so the closed run replaces it later.
        local cur = char.currentRun
        if cur and cur.completed and cur.entered and (not from or cur.entered >= from) then
            runs[#runs + 1] = { entered = cur.entered, name = cur.name, completed = true, completedAt = cur.completedAt,
                duration = math.max(0, (cur.lastSeen or cur.entered) - cur.entered), bosses = cur.bosses,
                bossCount = cur.bossCount, deaths = cur.deaths, party = cur.party, levelMax = cur.levelMax }
        end
        table.sort(runs, function(a, b) return a.entered < b.entered end)
        for i = math.max(1, #runs - Codec.MAX_RUNS + 1), #runs do
            local r = runs[i]
            -- 1.7.0 (D-104) adds <clear>,<splits>: seconds from entering to the final boss
            -- (0 = not cleared) and "<killedAt>/<fight>;..." per boss in kill order
            -- (fight empty when unknown). Older versions read only the first 8 fields.
            local clear = (r.completed and r.completedAt and r.entered and r.completedAt >= r.entered) and (r.completedAt - r.entered) or 0
            local splits, names = {}, {}
            for _, b in ipairs(r.bosses or {}) do
                if b.at and r.entered then
                    splits[#splits + 1] = string.format("%d/%s", b.at - r.entered, b.fight and string.format("%d", b.fight) or "")
                    names[#names + 1] = Codec.Escape(b.name or "")
                end
            end
            -- 1.8.0 (D-115, the Leaderboard) adds <bossNames>,<friends>,<levelMax>,<size>:
            -- each split's boss name; the names of group members who are my friends and run
            -- the ledger (nobody else's name is ever sent); the group's highest level at the
            -- final boss (empty if unknown); and how many players were in the group.
            local friends, size = {}, 1
            for _, p in ipairs(r.party or {}) do
                if not p.npc then size = size + 1 end
                if p.friend and p.name then friends[#friends + 1] = Codec.Escape(p.name) end
            end
            recs[#recs + 1] = table.concat({ "u", tostring(r.entered), Codec.Escape(r.name), tostring(r.duration or 0),
                r.completed and "1" or "0", tostring(#(r.bosses or {})), tostring(r.bossCount or 0), tostring(r.deaths or 0),
                string.format("%d", clear), table.concat(splits, ";"), table.concat(names, ";"), table.concat(friends, ";"),
                type(r.levelMax) == "number" and string.format("%d", r.levelMax) or "", string.format("%d", size) }, ",")
        end
    end
    local from = since and Codec.SinceEpoch(since) or nil
    -- Recent deaths (1.7.0, D-105): "r,<at>,<level>,<killerLevel>,<killer>,<zone>", the
    -- newest MAX_DEATHS since `since`. killerLevel: -1 skull, empty unknown.
    if shared.deaths then
        local list = {}
        for _, d in ipairs(char.deathLog or {}) do
            if d.at and (not from or d.at >= from) then list[#list + 1] = d end
        end
        for i = math.max(1, #list - Codec.MAX_DEATHS + 1), #list do
            local d = list[i]
            recs[#recs + 1] = table.concat({ "r", string.format("%d", d.at), tostring(tonumber(d.level) or 0),
                type(d.killerLevel) == "number" and string.format("%d", d.killerLevel) or "", Codec.Escape(d.killer or ""),
                Codec.Escape(d.zone or "") }, ",")
        end
    end
    -- Notable loot, blue (rare) or better only (1.7.0, D-105): "i,<at>,<itemID>,<quality>,
    -- <count>,<zone>", the newest MAX_LOOT since `since`. The item ID only; the receiver
    -- asks its own game for the name and tooltip.
    if shared.items then
        local list = {}
        for _, it in ipairs(char.items or {}) do
            local id = type(it.link) == "string" and tonumber(it.link:match("item:(%d+)"))
            if id and it.at and (tonumber(it.quality) or 0) >= Codec.LOOT_MIN_QUALITY and (not from or it.at >= from) then
                list[#list + 1] = { at = it.at, id = id, quality = it.quality, count = it.quantity, zone = it.zone }
            end
        end
        for i = math.max(1, #list - Codec.MAX_LOOT + 1), #list do
            local it = list[i]
            recs[#recs + 1] = table.concat({ "i", string.format("%d", it.at), string.format("%d", it.id), tostring(it.quality),
                tostring(tonumber(it.count) or 1), Codec.Escape(it.zone or "") }, ",")
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
    local profs
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
        elseif f[1] == "o" then
            out.logQuests = {}
            for i = 2, #f do
                local id = tonumber(f[i])
                if id then out.logQuests[#out.logQuests + 1] = id end
            end
        elseif f[1] == "p" and #f == 1 then
            profs = profs or {} -- "no professions" (1.4.0+ senders)
        elseif f[1] == "p" and f[2] and f[2] ~= "" then
            profs = profs or {}
            local name = Codec.Unescape(f[3] or "")
            profs[Codec.Unescape(f[2])] = { name = name ~= "" and name or nil, rank = tonumber(f[4]) or 0,
                max = tonumber(f[5]) or 0, lastAt = tonumber(f[6]) or 0 }
        elseif f[1] == "u" and tonumber(f[2]) then
            local count = tonumber(f[7]) or 0
            local run = { entered = tonumber(f[2]), name = Codec.Unescape(f[3] or ""), duration = tonumber(f[4]) or 0,
                completed = f[5] == "1" or nil, kills = math.max(0, tonumber(f[6]) or 0), bossCount = count > 0 and count or nil,
                deaths = tonumber(f[8]) or 0 }
            -- Boss times (1.7.0+, D-104).
            local clear = tonumber(f[9])
            if clear and clear > 0 then run.clear = clear end
            if f[10] and f[10] ~= "" then
                run.splits = {}
                for at, fight in f[10]:gmatch("(%d+)/(%d*)") do
                    run.splits[#run.splits + 1] = { at = tonumber(at), fight = tonumber(fight) }
                end
            end
            -- Leaderboard fields (1.8.0+, D-115).
            local function list(field)
                if not field or field == "" then return nil end
                local t = {}
                for piece in (field .. ";"):gmatch("(.-);") do t[#t + 1] = Codec.Unescape(piece) end
                return t
            end
            run.bossNames = list(f[11])
            run.names = list(f[12])
            run.levelMax = tonumber(f[13])
            run.size = tonumber(f[14])
            out.runs = out.runs or {}
            out.runs[#out.runs + 1] = run
        elseif f[1] == "r" and tonumber(f[2]) then
            out.deathLog = out.deathLog or {}
            local killer = Codec.Unescape(f[5] or "")
            local zone = Codec.Unescape(f[6] or "")
            out.deathLog[#out.deathLog + 1] = { at = tonumber(f[2]), level = tonumber(f[3]) ~= 0 and tonumber(f[3]) or nil,
                killerLevel = tonumber(f[4]), killer = killer ~= "" and killer or nil, zone = zone ~= "" and zone or nil }
        elseif f[1] == "i" and tonumber(f[2]) and tonumber(f[3]) then
            out.loot = out.loot or {}
            local zone = Codec.Unescape(f[6] or "")
            out.loot[#out.loot + 1] = { at = tonumber(f[2]), id = tonumber(f[3]), quality = tonumber(f[4]),
                count = tonumber(f[5]), zone = zone ~= "" and zone or nil }
        elseif f[1] == "s" and tonumber(f[2]) then
            out.sessions[#out.sessions + 1] = { start = tonumber(f[2]), played = tonumber(f[3]) or 0, active = tonumber(f[4]) or 0,
                levelStart = tonumber(f[5]), levelEnd = tonumber(f[6]), counts = decodeCounts(f, 7) }
        end
    end
    if not out.key or out.key == "" then return nil end
    out.professions = profs -- nil when the sender sent none (older version, nothing shared, or none before 1.4.0)
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
