-- Core/Migrations.lua
-- PURE: must not touch WoW globals at load time.
-- Schema version for FellowshipLedgerDB and the ordered steps that bring an older
-- saved table up to date. Each step upgrades from version (n - 1) to version n and
-- must be safe to run on a table that is partly filled.

local _, ns = ...

local Migrations = {}
ns.Migrations = Migrations

Migrations.CURRENT = 1

local steps = {}

-- v1: the top-level shape. Later steps add per-character fields.
steps[1] = function(db)
    db.settings = db.settings or {}
    db.characters = db.characters or {}
    db.friends = db.friends or {}
    db.blocklist = db.blocklist or {}
    db.dev = db.dev or {}
end

Migrations.steps = steps

-- Upgrades `db` in place. Returns the list of versions applied (may be empty).
-- A db from a newer version than we know is left untouched and reported, so an
-- older addon build never damages newer data.
function Migrations.Migrate(db)
    local applied = {}
    local from = tonumber(db.schemaVersion) or 0
    if from > Migrations.CURRENT then
        return applied, "newer"
    end
    for v = from + 1, Migrations.CURRENT do
        steps[v](db)
        db.schemaVersion = v
        applied[#applied + 1] = v
    end
    return applied
end
