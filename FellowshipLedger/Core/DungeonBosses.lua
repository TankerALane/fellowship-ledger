-- Core/DungeonBosses.lua
-- PURE: no WoW globals. Each dungeon's final boss, by name (D-086). WoW Forever's
-- encounter journal is empty (verify report 2026-11-05: "journal: 0 instances"), so
-- the game cannot say which boss ends a dungeon. A run counts as completed when
-- one of its dungeon's final bosses dies.
--
-- Keys are matched loosely against the instance name GetInstanceInfo gives (either
-- contains the other, any case), so "Scarlet Monastery" covers every wing and each
-- wing's own final boss completes that wing's run. Values are boss names as the
-- ENCOUNTER_END event reports them.
-- Sources: the usual Classic final bosses, checked against ForeverDungeonJournal 1.6.7's
-- "Final boss" notes; Ragefire Chasm's is Bazzalan on Forever (the last of Austin's four
-- kills there, 2026-11-05). Forever dungeons that are not open yet are not listed.

local _, ns = ...

local DungeonBosses = {}
ns.DungeonBosses = DungeonBosses

DungeonBosses.FINAL = {
    ["Ragefire Chasm"] = { "Bazzalan" },
    ["The Deadmines"] = { "Edwin VanCleef" },
    ["Wailing Caverns"] = { "Mutanus the Devourer" },
    ["Shadowfang Keep"] = { "Archmage Arugal" },
    ["Blackfathom Deeps"] = { "Aku'mai" },
    ["The Stockade"] = { "Bazil Thredd" },
    ["Gnomeregan"] = { "Mekgineer Thermaplugg" },
    ["Razorfen Kraul"] = { "Charlga Razorflank" },
    ["Scarlet Monastery"] = { "Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane" },
    ["Razorfen Downs"] = { "Amnennar the Coldbringer" },
    ["Uldaman"] = { "Archaedas" },
    ["Zul'Farrak"] = { "Chief Ukorz Sandscalp" },
    ["Maraudon"] = { "Princess Theradras" },
    ["Sunken Temple"] = { "Shade of Eranikus" },
    ["Temple of Atal'Hakkar"] = { "Shade of Eranikus" },
    ["Blackrock Depths"] = { "Emperor Dagran Thaurissan" },
    ["Blackrock Spire"] = { "Overlord Wyrmthalak", "General Drakkisath" },
    ["Dire Maul"] = { "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok" },
    ["Stratholme"] = { "Balnazzar", "Baron Rivendare" },
    ["Scholomance"] = { "Darkmaster Gandling" },
    -- WoW Forever dungeons
    ["Hall of Thanes"] = { "Durgen Dirgehammer" },
    ["Ruins of Lordaeron"] = { "Rath'mael" },
    ["City of Dalaran"] = { "Shade of the Archmage" },
    ["Excavation Site: Wetlands"] = { "Relic Guardian" },
}

local function lower(s) return type(s) == "string" and s:lower() or nil end

-- The final boss names for an instance name, or nil when the dungeon is not listed.
function DungeonBosses.For(instanceName)
    local n = lower(instanceName)
    if not n or n == "" then return nil end
    local best, bestLen
    for key, bosses in pairs(DungeonBosses.FINAL) do
        local k = key:lower()
        if n == k or n:find(k, 1, true) or k:find(n, 1, true) then
            -- The longest matching key wins ("Blackrock Spire" over a shorter one).
            if not bestLen or #k > bestLen then best, bestLen = bosses, #k end
        end
    end
    return best
end

-- Is `bossName` a final boss of the dungeon `instanceName`?
function DungeonBosses.IsFinal(instanceName, bossName)
    local b = lower(bossName)
    if not b then return false end
    for _, name in ipairs(DungeonBosses.For(instanceName) or {}) do
        if name:lower() == b then return true end
    end
    return false
end
