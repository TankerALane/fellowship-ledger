-- Core/Data.lua
-- What the windows show: real data, or the separate fake set while /fl fake is on.
-- Trackers never come through here; they always write to the real db.characters.

local _, ns = ...

local Data = {}
ns.Data = Data

function Data.IsFake()
    return ns.db ~= nil and type(ns.db.fake) == "table"
end

function Data.Characters()
    if Data.IsFake() then return ns.db.fake.characters end
    return ns.db.characters
end

-- Friends' cached data (filled by sharing in Phase 3; fake friends while /fl fake is on).
function Data.Friends()
    if Data.IsFake() then return ns.db.fake.friends end
    return ns.db.friends
end

-- Every character that can be graphed: mine first, then friends'. Each entry:
-- { key, label, char, owner } (owner = friend name, nil for mine).
function Data.GraphableCharacters()
    local list = {}
    local mine = {}
    for key in pairs(Data.Characters()) do mine[#mine + 1] = key end
    table.sort(mine)
    for _, key in ipairs(mine) do
        local c = Data.Characters()[key]
        list[#list + 1] = { key = key, label = c.name or key, char = c }
    end
    local friendIds = {}
    for id in pairs(Data.Friends() or {}) do friendIds[#friendIds + 1] = id end
    table.sort(friendIds)
    for _, id in ipairs(friendIds) do
        local f = Data.Friends()[id]
        if not ns.FriendsModel.IsBlocked(ns.db.blocklist, f) then
            local keys = {}
            for key in pairs(f.characters or {}) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local c = f.characters[key]
                list[#list + 1] = { key = id .. "/" .. key, label = (c.name or key) .. " (" .. (f.name or id) .. ")", char = c, owner = f.name }
            end
        end
    end
    return list
end

function Data.EnableFake()
    ns.db.fake = ns.FakeData.Generate(time(), time, date)
end

function Data.DisableFake()
    ns.db.fake = nil
end
