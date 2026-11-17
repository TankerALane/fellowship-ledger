-- UI/FriendsModel.lua
-- PURE: no WoW globals. Rows for the Friends tab: Battle.net friends as a header
-- row with their characters beneath; character-only friends on their own.
-- Blocked friends are never shown.
--
-- friends: { [id] = { kind = "bnet"|"char", name, tag, online, lastUpdated,
--                     characters = { [charKey] = <character record> } } }
-- blocklist: { [tag or charKey] = true }

local _, ns = ...

local FriendsModel = {}
ns.FriendsModel = FriendsModel

function FriendsModel.IsBlocked(blocklist, friend, charKey)
    if not blocklist then return false end
    if friend.tag and blocklist[friend.tag] then return true end
    if charKey and blocklist[charKey] then return true end
    return false
end

-- Is the friend online on this character right now? friend.playing is the
-- "Name-Realm" (Forever: "First-Last") Battle.net reports; compared without
-- spaces or case, as character keys and Battle.net names can differ in both.
function FriendsModel.IsPlaying(friend, charKey)
    if not (friend and friend.online and type(friend.playing) == "string" and type(charKey) == "string") then
        return false
    end
    local function norm(s) return (s:gsub("[%s%-]", ""):lower()) end
    return norm(friend.playing) == norm(charKey)
end

-- A Battle.net friend's line on the Friends tab (1.14.2, Austin 2026-11-17: easier to
-- tell who is online when the list is folded; no version). o: colour codes and dots,
-- { on = dot, off = dot, good = "|cff..", muted = "|cff.." }. Online: a green dot and
-- "online, playing <character>"; offline: a grey dot and the whole line grey.
function FriendsModel.HeaderText(f, id, count, now, L, o)
    o = o or {}
    local good, muted = o.good or "", o.muted or ""
    local close = function(code) return code ~= "" and "|r" or "" end
    local name = f.name or tostring(id)
    local rest = string.format(count == 1 and L.FRIEND_HEADER_REST_ONE or L.FRIEND_HEADER_REST, count, FriendsModel.Ago(now, f.lastUpdated))
    if f.online then
        local status = L.ONLINE
        for key, c in pairs(f.characters or {}) do
            if FriendsModel.IsPlaying(f, key) then
                status = string.format(L.FRIEND_PLAYING_ON, c.display or c.name or key)
                break
            end
        end
        return (o.on and (o.on .. " ") or "") .. name .. "  " .. good .. status .. close(good) .. "  -  " .. rest
    end
    return (o.off and (o.off .. " ") or "") .. muted .. name .. "  " .. L.OFFLINE .. "  -  " .. rest .. close(muted)
end

-- Returns a flat list of display rows: { header = true, friend, id } and
-- { character row from MeModel, friendId, indent = bool }.
-- sortField/desc (optional): sort characters by that column, and order friends by
-- their best character (a friend's characters always stay together under them).
-- Without a sort: Battle.net friends first, then by name; characters by level.
function FriendsModel.Build(friends, blocklist, range, todayKey, timeFn, dateFn, sortField, desc)
    local groups = {}
    local hidden = 0
    for id, f in pairs(friends or {}) do
        if FriendsModel.IsBlocked(blocklist, f) then
            hidden = hidden + 1
        else
            local chars = {}
            for key, c in pairs(f.characters or {}) do
                if not FriendsModel.IsBlocked(blocklist, f, key) then chars[key] = c end
            end
            local charRows = ns.MeModel.Build(chars, range, todayKey, timeFn, dateFn)
            for _, r in ipairs(charRows) do
                r.friendId, r.lastUpdated = id, f.lastUpdated
                r.playing = FriendsModel.IsPlaying(f, r.key) or nil
                -- Sort value for "Last played": the character being played counts as
                -- played when its data last arrived, so it sorts as the newest.
                local seen = chars[r.key] and chars[r.key].lastSeen
                r.lastSeen = seen
                r.lastPlayed = r.playing and math.max(seen or 0, f.lastUpdated or 0) or seen
            end
            if sortField then
                ns.MeModel.Sort(charRows, sortField, desc)
            else
                -- Default order: the character they are on first, then by level.
                ns.MeModel.Sort(charRows, "level", true)
                for i, r in ipairs(charRows) do
                    if r.playing and i > 1 then table.insert(charRows, 1, table.remove(charRows, i)) break end
                end
            end
            local order
            if sortField == "name" then
                order = string.lower(f.kind == "bnet" and (f.name or id) or (charRows[1] and charRows[1].name or id))
            elseif sortField then
                order = charRows[1] and charRows[1][sortField]
            end
            groups[#groups + 1] = { id = id, friend = f, rows = charRows, order = order,
                default = (f.kind == "bnet" and "0" or "1") .. string.lower(f.name or id) }
        end
    end
    table.sort(groups, function(a, b)
        if sortField then
            local x, y = a.order, b.order
            if x ~= y then
                if x == nil then return false end -- friends with nothing to sort by go last
                if y == nil then return true end
                if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
                if desc then return x > y end
                return x < y
            end
        end
        if a.default ~= b.default then return a.default < b.default end
        return tostring(a.id) < tostring(b.id)
    end)
    local rows = {}
    for _, g in ipairs(groups) do
        if g.friend.kind == "bnet" then
            rows[#rows + 1] = { header = true, friend = g.friend, id = g.id, count = #g.rows }
            for _, r in ipairs(g.rows) do
                r.indent = true
                rows[#rows + 1] = r
            end
        else
            for _, r in ipairs(g.rows) do rows[#rows + 1] = r end
        end
    end
    return rows, hidden
end

-- Readable class and race from the tokens UnitClass/UnitRace return ("DEATHKNIGHT",
-- "NightElf"): a locale string when there is one, else the token split into words.
local function tokenText(L, prefix, token)
    if type(token) ~= "string" or token == "" then return nil end
    local s = L and rawget(L, prefix .. token:upper())
    if s then return s end
    s = token:gsub("(%l)(%u)", "%1 %2")
    if s == s:upper() then s = s:sub(1, 1) .. s:sub(2):lower() end
    return s
end
FriendsModel.TokenText = tokenText

-- Tooltip for a friend's character row: title and lines.
-- row: from Build; char: the stored character; friend: the friend record.
function FriendsModel.Tooltip(row, char, friend, now, L, factionText)
    char, friend = char or {}, friend or {}
    local lines = {}
    local race, class = tokenText(L, "RACE_", char.race), tokenText(L, "CLASS_", char.class)
    local who = (race and class) and (race .. " " .. class) or race or class or ""
    lines[#lines + 1] = (string.format(L.TIP_LEVEL, char.level or row.level or 0, who):gsub("%s+$", ""))
    if factionText and factionText ~= "" then lines[#lines + 1] = string.format(L.TIP_FACTION, factionText) end
    if row.playing then
        lines[#lines + 1] = L.TIP_PLAYING_NOW
    else
        lines[#lines + 1] = string.format(L.TIP_LAST_PLAYED, FriendsModel.Ago(now, char.lastSeen))
    end
    lines[#lines + 1] = string.format(L.TIP_UPDATED, FriendsModel.Ago(now, friend.lastUpdated))
    -- Newer data passed on by a mutual friend (D-124), until the friend's own arrives.
    if char.via then lines[#lines + 1] = string.format(L.TIP_VIA, char.via, FriendsModel.Ago(now, char.viaAt)) end
    if friend.version then lines[#lines + 1] = string.format(L.TIP_VERSION, friend.version) end
    -- row.common: quests in both your logs (D-106).
    if row.common and row.common > 0 then lines[#lines + 1] = string.format(L.TIP_COMMON_QUESTS, row.common) end
    lines[#lines + 1] = L.TIP_RIGHT_CLICK -- D-108
    return row.name, lines
end

-- The "Last played" cell. "now" only while the friend is on this character and
-- their data arrived within LIVE_WINDOW (live updates come every minute, D-090);
-- otherwise when the character was last played, as the friend's ledger reported it.
FriendsModel.LIVE_WINDOW = 90
function FriendsModel.LastPlayed(now, row)
    if row.playing and row.lastUpdated and now - row.lastUpdated <= FriendsModel.LIVE_WINDOW then
        return "now", true
    end
    return FriendsModel.Ago(now, row.lastSeen), false
end

-- "5m ago", "3h ago", "2d ago"; "never" when nil.
function FriendsModel.Ago(now, at)
    if not at then return "never" end
    local d = now - at
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

-- The window's header line (1.13.0): "2 of 3 friends online, synced 1m ago".
-- friends: db.friends (or fake ones); blocked friends are not counted.
function FriendsModel.HeaderStatus(friends, blocklist, lastSyncAt, now, L)
    local total, online = 0, 0
    for _, f in pairs(friends or {}) do
        if not FriendsModel.IsBlocked(blocklist, f) then
            total = total + 1
            if f.online then online = online + 1 end
        end
    end
    if total == 0 then return L.HEADER_NO_FRIENDS end
    local ago = lastSyncAt and FriendsModel.Ago(now, lastSyncAt) or L.NEVER
    return string.format(total == 1 and L.HEADER_STATUS_ONE or L.HEADER_STATUS, online, total, ago)
end

-- Side by side (1.13.0): one grid line per person with a thin bar and the number for
-- each stat, and a crown on the best of each (when more than one person is listed
-- and the best is above 0). rows: { name, isMe, levels, quests, dungeons, active }.
-- opts: { crown = icon code, duration = fn(seconds) -> text, inset = px }.
FriendsModel.COMPARE = {
    { field = "levels", label = "COL_LEVELS" }, { field = "quests", label = "COL_QUESTS" },
    { field = "dungeons", label = "COL_DUNGEONS" }, { field = "active", label = "COL_ACTIVE", duration = true },
}
function FriendsModel.CompareLines(rows, L, opts)
    opts = opts or {}
    local function seg(x, w, text, role, font, align)
        return { x = x, w = w, text = text or "", role = role or "text", font = font or "body", align = align }
    end
    local stats = FriendsModel.COMPARE
    local max = {}
    for _, s in ipairs(stats) do
        max[s.field] = 0
        for _, r in ipairs(rows) do max[s.field] = math.max(max[s.field], tonumber(r[s.field]) or 0) end
    end
    local function base(i) return .22 + (i - 1) * .195 end
    local head = { kind = "grid", inset = opts.inset, segments = {}, rules = { { 0, 1 } } }
    for i, s in ipairs(stats) do
        head.segments[#head.segments + 1] = seg(base(i), .19, L[s.label], "muted", "small", "RIGHT")
    end
    local out = { head }
    for _, r in ipairs(rows) do
        local line = { kind = "grid", inset = opts.inset, segments = { seg(0, .21, r.name, r.isMe and "good" or "text") } }
        for i, s in ipairs(stats) do
            local v = tonumber(r[s.field]) or 0
            local best = #rows > 1 and v > 0 and v == max[s.field]
            if v > 0 and max[s.field] > 0 then
                line.segments[#line.segments + 1] = { x = base(i), w = .10, bar = v / max[s.field] }
            end
            local text = s.duration and (opts.duration and opts.duration(v) or tostring(v)) or tostring(v)
            if best and opts.crown then text = opts.crown .. " " .. text end
            line.segments[#line.segments + 1] = seg(base(i) + .10, .09, text, best and "heading" or "text", nil, "RIGHT")
        end
        out[#out + 1] = line
    end
    return out
end

-- The same comparison stacked for a narrow panel (1.14.0, D-136): per stat a small
-- title, then one line per person (name, a bar, the figure), the best with the crown.
function FriendsModel.CompareStacked(rows, L, opts)
    opts = opts or {}
    local function seg(x, w, text, role, font, align)
        return { x = x, w = w, text = text or "", role = role or "text", font = font or "body", align = align }
    end
    local out = {}
    for _, s in ipairs(FriendsModel.COMPARE) do
        local max = 0
        for _, r in ipairs(rows) do max = math.max(max, tonumber(r[s.field]) or 0) end
        out[#out + 1] = { kind = "grid", segments = { seg(.02, .96, L[s.label], "section") }, stat = s.field }
        for _, r in ipairs(rows) do
            local v = tonumber(r[s.field]) or 0
            local best = #rows > 1 and v > 0 and v == max
            local text = s.duration and (opts.duration and opts.duration(v) or tostring(v)) or tostring(v)
            local name = r.name or "?"
            if best and opts.crown then name = opts.crown .. " " .. name end
            out[#out + 1] = { kind = "grid", segments = {
                seg(.02, .38, name, r.isMe and "good" or (best and "heading" or "text"), "small"),
                { x = .42, w = .34, bar = max > 0 and v / max or 0, track = true, barRole = best and "accent" or "muted", barH = 5 },
                seg(.76, .22, text, best and "heading" or "text", "small", "RIGHT") } }
        end
        out[#out + 1] = { kind = "grid", height = 6, segments = {} }
    end
    return out
end

-- The ledger line in the game's tooltip on a friend's character (D-099):
-- "Ledger: Hamlet's character, 12 quests and 2 dungeons this week".
-- f: the friend record; key: the character key; sum: Days.Sum for this week.
function FriendsModel.TooltipLine(f, sum, L)
    sum = sum or {}
    local quests, dungeons = sum.quests or 0, sum.dungeonsCompleted or 0
    local who = (f and f.name) or "?"
    if quests == 0 and dungeons == 0 then return string.format(L.TOOLTIP_FRIEND_QUIET, who) end
    return string.format(L.TOOLTIP_FRIEND, who, quests, dungeons)
end

-- The right-click menu of a friend's row (D-108): which actions apply. peer: the live
-- Friends peer (nil when the game no longer lists them); playing: the row is the
-- character they are on now. Whisper: Battle.net friends always (their whisper reaches
-- the app too), character friends while online. Invite: only the character they are on.
function FriendsModel.Actions(peer, playing)
    local out = {}
    if not peer then return out end
    if (peer.kind == "bnet" and peer.accountName) or (peer.kind == "char" and peer.online) then out[#out + 1] = "whisper" end
    if peer.online and playing and peer.target then out[#out + 1] = "invite" end
    return out
end

-- Quests in both logs (D-106): the IDs in `mine` (my current character's log) that
-- are also in `theirs` (a friend character's shared log), in my log's order.
function FriendsModel.CommonQuests(mine, theirs)
    local set, out = {}, {}
    for _, id in ipairs(theirs or {}) do set[id] = true end
    for _, id in ipairs(mine or {}) do if set[id] then out[#out + 1] = id end end
    return out
end

-- Friends' characters with quest `id` in their shared log, blocked ones skipped:
-- { { friend, character, friendId, key } }, sorted by friend then character.
function FriendsModel.OnQuest(friends, blocklist, id)
    local out = {}
    for fid, f in pairs(friends or {}) do
        for key, c in pairs(f.characters or {}) do
            if type(c.logQuests) == "table" and not FriendsModel.IsBlocked(blocklist, f, key) then
                for _, q in ipairs(c.logQuests) do
                    if q == id then
                        out[#out + 1] = { friend = f.name or fid, character = c.display or c.name or key, friendId = fid, key = key }
                        break
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.friend:lower() ~= b.friend:lower() then return a.friend:lower() < b.friend:lower() end
        return a.character:lower() < b.character:lower()
    end)
    return out
end

-- Which friend has this character (key), skipping blocked ones. Returns id, friend, character.
function FriendsModel.FindCharacter(friends, blocklist, key)
    if not key then return nil end
    for id, f in pairs(friends or {}) do
        local c = f.characters and f.characters[key]
        if c and not FriendsModel.IsBlocked(blocklist, f, key) then return id, f, c end
    end
    return nil
end
