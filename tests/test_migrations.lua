local H = ...

H.test("empty db migrates to current with the top-level tables", function()
    local M = H.pureNamespace().Migrations
    local db = {}
    local applied = M.Migrate(db)
    H.eq(db.schemaVersion, M.CURRENT)
    H.eq(#applied, M.CURRENT)
    for _, k in ipairs({ "settings", "characters", "friends", "blocklist", "dev" }) do
        H.eq(type(db[k]), "table", k)
    end
end)

H.test("migrating twice is a no-op", function()
    local M = H.pureNamespace().Migrations
    local db = {}
    M.Migrate(db)
    db.settings.debug = true
    local applied = M.Migrate(db)
    H.eq(#applied, 0)
    H.eq(db.settings.debug, true)
end)

H.test("existing data in a partly filled db is kept", function()
    local M = H.pureNamespace().Migrations
    local db = { characters = { ["A-B"] = { level = 5 } } }
    M.Migrate(db)
    H.eq(db.characters["A-B"].level, 5)
end)

H.test("a db from a newer version is left untouched", function()
    local M = H.pureNamespace().Migrations
    local db = { schemaVersion = M.CURRENT + 5 }
    local applied, status = M.Migrate(db)
    H.eq(#applied, 0)
    H.eq(status, "newer")
    H.eq(db.schemaVersion, M.CURRENT + 5)
    H.eq(db.settings, nil)
end)

H.test("every version up to CURRENT has a step", function()
    local M = H.pureNamespace().Migrations
    for v = 1, M.CURRENT do H.eq(type(M.steps[v]), "function", "step " .. v) end
end)
