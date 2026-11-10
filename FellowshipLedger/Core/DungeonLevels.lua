-- Core/DungeonLevels.lua
-- PURE: no WoW globals. Each dungeon's usual level range (D-115), for the Leaderboard's
-- at-level filter and the dungeon goal suggestion (D-116). The Deadmines' 15-22 is the
-- range Austin sees in WoW Forever; the others are the usual Classic ranges and should be
-- checked against the game (m:dungeonlevels). WoW Forever's own dungeons are not listed
-- until their ranges are known: a dungeon with no range never has a run left out.
-- Names are matched like Core/DungeonBosses.lua (either contains the other, any case).

local _, ns = ...

local DungeonLevels = {}
ns.DungeonLevels = DungeonLevels

DungeonLevels.OVER = 3 -- at-level: nobody in the group more than 3 above the top of the range (Austin, D-115)

DungeonLevels.RANGES = {
    ["Ragefire Chasm"] = { 13, 18 },
    ["Wailing Caverns"] = { 17, 24 },
    ["The Deadmines"] = { 15, 22 },
    ["Shadowfang Keep"] = { 22, 30 },
    ["Blackfathom Deeps"] = { 24, 32 },
    ["The Stockade"] = { 24, 32 },
    ["Gnomeregan"] = { 29, 38 },
    ["Razorfen Kraul"] = { 29, 38 },
    ["Scarlet Monastery"] = { 26, 45 },
    ["Razorfen Downs"] = { 37, 46 },
    ["Uldaman"] = { 41, 51 },
    ["Zul'Farrak"] = { 44, 54 },
    ["Maraudon"] = { 46, 55 },
    ["Sunken Temple"] = { 50, 56 },
    ["Temple of Atal'Hakkar"] = { 50, 56 },
    ["Blackrock Depths"] = { 52, 60 },
    ["Blackrock Spire"] = { 55, 60 },
    ["Dire Maul"] = { 55, 60 },
    ["Stratholme"] = { 58, 60 },
    ["Scholomance"] = { 58, 60 },
}

-- { min, max } for an instance name, or nil when the dungeon is not listed.
function DungeonLevels.For(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n = name:lower()
    local best, bestLen
    for key, range in pairs(DungeonLevels.RANGES) do
        local k = key:lower()
        if n == k or n:find(k, 1, true) or k:find(n, 1, true) then
            if not bestLen or #k > bestLen then best, bestLen = range, #k end
        end
    end
    return best
end

-- Is a run at level? maxLevel: the highest level in the group (nil = unknown).
-- Unknown levels and unlisted dungeons count as at level.
function DungeonLevels.AtLevel(name, maxLevel)
    local r = DungeonLevels.For(name)
    if not r or type(maxLevel) ~= "number" then return true end
    return maxLevel <= r[2] + DungeonLevels.OVER
end

-- Listed dungeons whose range holds this level, sorted by their lowest level.
function DungeonLevels.InRange(level)
    local out = {}
    for name, r in pairs(DungeonLevels.RANGES) do
        if level >= r[1] and level <= r[2] then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        local ra, rb = DungeonLevels.RANGES[a], DungeonLevels.RANGES[b]
        if ra[1] ~= rb[1] then return ra[1] < rb[1] end
        return a < b
    end)
    return out
end
