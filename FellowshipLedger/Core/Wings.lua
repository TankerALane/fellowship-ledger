-- Core/Wings.lua
-- PURE: no WoW globals. Dungeons whose wings the game reports as one (D-150). On
-- Forever, Scarlet Monastery's four wings are one instance with one name, and the
-- game gives no map inside, so a run there was just "Scarlet Monastery" and the
-- dungeon timer compared a Library run with a Graveyard one. A run is named by its
-- wing ("Scarlet Monastery: Library") as soon as one of these tells it:
--   the door walked through: the four portals stand close together on the Tirisfal
--     Glades map (1420). The Graveyard and Library doors were measured in game on
--     Forever by ForeverDungeonJournal (Systems/ScarletWing.lua), the Armory's by
--     Austin's /fl verify (2026-11-24; not in a line with the other two, so no door
--     is guessed). The Cathedral's is not known yet: it is learned (Wings.Learn) the
--     first time a boss or room there names the wing;
--   a boss of the wing dying;
--   the room the player stands in (GetSubZoneText), in English.
-- Boss and room names are from ForeverDungeonJournal's data (Data/Dungeons.lua).

local _, ns = ...

local Wings = {}
ns.Wings = Wings

Wings.DOOR_RADIUS = 0.0035 -- half the gap between two portals

local G, L = { x = 0.8480, y = 0.3037 }, { x = 0.8535, y = 0.3239 }
local A = { x = 0.8567, y = 0.3181 } -- Austin's Armory door, 2026-11-24

Wings.DUNGEONS = {
    ["Scarlet Monastery"] = {
        doorMap = 1420,
        wings = {
            { id = "Graveyard", door = G,
                bosses = { "Interrogator Vishas", "Azshir the Sleepless", "Fallen Champion", "Ironspine", "Bloodmage Thalnos" },
                rooms = { "chamber of atonement", "forlorn cloister", "honor's tomb" } },
            { id = "Cathedral", -- door not known: learned
                bosses = { "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" },
                rooms = { "chapel gardens", "crusader's chapel" } },
            { id = "Armory", door = A,
                bosses = { "Herod" },
                rooms = { "training grounds", "footman's armory", "crusader's armory", "hall of champions" } },
            { id = "Library", door = L,
                bosses = { "Houndmaster Loksey", "Arcanist Doan" },
                rooms = { "huntsman's cloister", "gallery of treasures", "athenaeum" } },
        },
    },
}

local function lower(s) return type(s) == "string" and s:lower() or nil end

-- "Scarlet Monastery: Library" -> "Scarlet Monastery", "Library"; a name with no
-- wing -> the name, nil. Only dungeons listed above.
function Wings.Split(name)
    if type(name) ~= "string" then return name, nil end
    local base, wing = name:match("^(.-):%s*(.+)$")
    if base and Wings.DUNGEONS[base] then return base, wing end
    return name, nil
end

function Wings.Base(name) return (Wings.Split(name)) end

-- Does this dungeon have wings? (Its whole name or a wing's name.)
function Wings.Has(name) return Wings.DUNGEONS[Wings.Base(name) or ""] ~= nil end

function Wings.Name(base, wing)
    if not wing or not Wings.DUNGEONS[base or ""] then return base end
    return base .. ": " .. wing
end

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function validDoor(d, door)
    return type(door) == "table" and door.map == d.doorMap and type(door.x) == "number" and type(door.y) == "number"
end

-- The wing whose door { map, x, y } is, or nil. learned: { [wing] = { map, x, y } },
-- doors measured on this account (Wings.Learn), used before the ones above.
function Wings.FromDoor(name, door, learned)
    local d = Wings.DUNGEONS[Wings.Base(name) or ""]
    if not d or not validDoor(d, door) then return nil end
    local best, bestDist
    for _, w in ipairs(d.wings) do
        local at = learned and validDoor(d, learned[w.id]) and learned[w.id] or w.door
        local dd = at and dist(at, door)
        if dd and dd <= Wings.DOOR_RADIUS and (not bestDist or dd < bestDist) then best, bestDist = w.id, dd end
    end
    return best
end

-- A wing a boss or room has confirmed: the door walked through is that wing's door
-- (as ForeverDungeonJournal learns its doors). Kept only near where that wing's door
-- is (within a portal's gap), or for a wing whose door is not known, near the others
-- (NEAR_DOORS), and never on another wing's door: a door read far away teaches
-- nothing. learned: the table to keep it in. Returns true when kept.
Wings.LEARN_RADIUS = 0.007
Wings.NEAR_DOORS = 0.03
function Wings.Learn(name, wing, door, learned)
    local d = Wings.DUNGEONS[Wings.Base(name) or ""]
    if not d or type(learned) ~= "table" or not validDoor(d, door) then return false end
    local mine, near = nil, false
    for _, w in ipairs(d.wings) do
        if w.id == wing then
            mine = w
        elseif w.door and dist(w.door, door) <= Wings.DOOR_RADIUS then
            return false -- another wing's door
        end
        if w.door and dist(w.door, door) <= Wings.NEAR_DOORS then near = true end
    end
    if not mine then return false end
    if mine.door and dist(mine.door, door) > Wings.LEARN_RADIUS then return false end
    if not mine.door and not near then return false end
    learned[wing] = { map = door.map, x = door.x, y = door.y }
    return true
end

-- The wing a boss belongs to, or nil.
function Wings.FromBoss(name, boss)
    local d = Wings.DUNGEONS[Wings.Base(name) or ""]
    local b = lower(boss)
    if not d or not b then return nil end
    for _, w in ipairs(d.wings) do
        for _, n in ipairs(w.bosses) do if n:lower() == b then return w.id end end
    end
    return nil
end

-- The wing a room (subzone) name belongs to, or nil.
function Wings.FromRoom(name, room)
    local d = Wings.DUNGEONS[Wings.Base(name) or ""]
    local r = lower(room)
    if not d or not r or r == "" then return nil end
    for _, w in ipairs(d.wings) do
        for _, n in ipairs(w.rooms) do if n == r then return w.id end end
    end
    return nil
end

-- The wing of a list of boss names (the first that names one), or nil.
function Wings.FromBosses(name, bossNames)
    for _, b in ipairs(bossNames or {}) do
        local w = Wings.FromBoss(name, b)
        if w then return w end
    end
    return nil
end

-- A run's name with its wing, from its bosses when the name has none: for runs saved
-- before wings were known, and friends on older versions. Other names unchanged.
function Wings.Label(name, bossNames)
    local base, wing = Wings.Split(name)
    if wing or not Wings.DUNGEONS[base or ""] then return name end
    return Wings.Name(base, Wings.FromBosses(base, bossNames)) or name
end
