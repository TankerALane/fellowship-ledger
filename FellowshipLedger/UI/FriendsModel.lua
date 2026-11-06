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
    return row.name, lines
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
