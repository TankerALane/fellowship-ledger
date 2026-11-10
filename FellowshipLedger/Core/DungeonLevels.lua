-- Core/DungeonLevels.lua
-- PURE: no WoW globals. Each dungeon's level range (D-115), for the Leaderboard's
-- at-level filter and the dungeon goal suggestion (D-116). Taken from the DungeonJournal
-- addon for WoW Forever (ForeverDungeonJournal 1.7.4, Data/Dungeons.lua; CurseForge
-- project 1707971), as Austin asked on 2026-11-09. Wings are listed on their own, and
-- each split dungeon also has an entry for its whole name (its widest range), for a
-- client that names only the dungeon. A dungeon with no range never has a run left out.
-- Names are matched like Core/DungeonBosses.lua (either contains the other, any case),
-- but an exact match always wins; case and punctuation are ignored. The numbers are
-- copied here: Fellowship Ledger never loads or reads that addon (Austin: a reference,
-- not a dependency).

local _, ns = ...

local DungeonLevels = {}
ns.DungeonLevels = DungeonLevels

DungeonLevels.OVER = 3 -- at-level: nobody in the group more than 3 above the top of the range (Austin, D-115)

DungeonLevels.RANGES = {
    -- From the DungeonJournal addon
    ["Hall of Thanes"] = { 13, 20 },
    ["Ragefire Chasm"] = { 13, 18 },
    ["Wailing Caverns"] = { 15, 24 },
    ["Ruins of Lordaeron"] = { 15, 22 },
    ["The Deadmines"] = { 17, 26 },
    ["Shadowfang Keep"] = { 20, 30 },
    ["Blackfathom Deeps"] = { 24, 32 },
    ["The Stockade"] = { 24, 32 },
    ["Excavation Site: Wetlands"] = { 26, 33 },
    ["City of Dalaran"] = { 28, 33 },
    ["Gnomeregan"] = { 29, 38 },
    ["Razorfen Kraul"] = { 29, 38 },
    ["Scarlet Monastery: Graveyard"] = { 30, 38 },
    ["Scarlet Monastery: Library"] = { 33, 41 },
    ["Scarlet Monastery: Armory"] = { 34, 42 },
    ["Scarlet Monastery: Cathedral"] = { 36, 45 },
    ["The Drowned City"] = { 35, 40 },
    ["Razorfen Downs"] = { 37, 46 },
    ["Uldaman"] = { 38, 48 },
    ["Krol'dok Stronghold"] = { 40, 45 },
    ["Zul'Farrak"] = { 43, 50 },
    ["Maraudon"] = { 45, 52 },
    ["Alcaz Prison"] = { 48, 53 },
    ["Sunken Temple"] = { 49, 56 },
    ["Blackrock Depths"] = { 52, 60 },
    ["Blackmaw Hold"] = { 55, 60 },
    ["Lower Blackrock Spire"] = { 55, 60 },
    ["Upper Blackrock Spire"] = { 55, 60 },
    ["Dire Maul: East"] = { 55, 60 },
    ["Dire Maul: West"] = { 57, 60 },
    ["Dire Maul: North"] = { 57, 60 },
    ["Shaper's Terrace"] = { 58, 60 },
    ["Scholomance"] = { 58, 60 },
    ["Stratholme: Living"] = { 58, 60 },
    ["Stratholme: Undead"] = { 58, 60 },
    -- Whole names, for a client that does not name the wing
    ["Scarlet Monastery"] = { 30, 45 },
    ["Dire Maul"] = { 55, 60 },
    ["Stratholme"] = { 58, 60 },
    ["Blackrock Spire"] = { 55, 60 },
    ["Temple of Atal'Hakkar"] = { 49, 56 },
}

-- The whole-name entries, left out of goal suggestions (the wings are suggested instead).
DungeonLevels.WHOLE = { ["Scarlet Monastery"] = true, ["Dire Maul"] = true, ["Stratholme"] = true,
    ["Blackrock Spire"] = true, ["Temple of Atal'Hakkar"] = true }

-- Lower case, punctuation dropped: "Scarlet Monastery: Armory" = "scarlet monastery armory".
local function norm(s) return (s:lower():gsub("[^%w%s]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- { min, max } for an instance name, or nil when the dungeon is not listed.
function DungeonLevels.For(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n = norm(name)
    if n == "" then return nil end
    for key, range in pairs(DungeonLevels.RANGES) do
        if norm(key) == n then return range end
    end
    local best, bestLen
    for key, range in pairs(DungeonLevels.RANGES) do
        local k = norm(key)
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
        if level >= r[1] and level <= r[2] and not DungeonLevels.WHOLE[name] then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        local ra, rb = DungeonLevels.RANGES[a], DungeonLevels.RANGES[b]
        if ra[1] ~= rb[1] then return ra[1] < rb[1] end
        return a < b
    end)
    return out
end
