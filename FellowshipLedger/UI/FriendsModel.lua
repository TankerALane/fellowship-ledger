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
    if friend.version then lines[#lines + 1] = string.format(L.TIP_VERSION, friend.version) end
    -- row.common: quests in both your logs (D-106).
    if row.common and row.common > 0 then lines[#lines + 1] = string.format(L.TIP_COMMON_QUESTS, row.common) end
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
