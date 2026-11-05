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
            for _, r in ipairs(charRows) do r.friendId, r.lastUpdated = id, f.lastUpdated end
            if sortField then ns.MeModel.Sort(charRows, sortField, desc) else ns.MeModel.Sort(charRows, "level", true) end
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

-- "5m ago", "3h ago", "2d ago"; "never" when nil.
function FriendsModel.Ago(now, at)
    if not at then return "never" end
    local d = now - at
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end
