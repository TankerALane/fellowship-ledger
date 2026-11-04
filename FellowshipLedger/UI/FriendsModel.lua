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

local function sortedKeys(t, by)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local x, y = by and by(a) or tostring(a), by and by(b) or tostring(b)
        if x == y then return tostring(a) < tostring(b) end
        return x < y
    end)
    return keys
end

-- Returns a flat list of display rows: { header = true, friend, id } and
-- { character row from MeModel, friendId, indent = bool }.
function FriendsModel.Build(friends, blocklist, range, todayKey, timeFn, dateFn)
    local rows = {}
    local ids = sortedKeys(friends, function(id)
        local f = friends[id]
        return (f.kind == "bnet" and "0" or "1") .. string.lower(f.name or id)
    end)
    local hidden = 0
    for _, id in ipairs(ids) do
        local f = friends[id]
        if FriendsModel.IsBlocked(blocklist, f) then
            hidden = hidden + 1
        else
            local chars = {}
            for key, c in pairs(f.characters or {}) do
                if not FriendsModel.IsBlocked(blocklist, f, key) then chars[key] = c end
            end
            local charRows = ns.MeModel.Build(chars, range, todayKey, timeFn, dateFn)
            ns.MeModel.Sort(charRows, "level", true)
            if f.kind == "bnet" then
                rows[#rows + 1] = { header = true, friend = f, id = id, count = #charRows }
                for _, r in ipairs(charRows) do
                    r.friendId, r.indent, r.lastUpdated = id, true, f.lastUpdated
                    rows[#rows + 1] = r
                end
            else
                for _, r in ipairs(charRows) do
                    r.friendId, r.lastUpdated = id, f.lastUpdated
                    rows[#rows + 1] = r
                end
            end
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
