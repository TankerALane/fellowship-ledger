-- Our own final-boss list (Core/DungeonBosses.lua, D-086): loose instance names,
-- several wings under one name, case, and dungeons that are not listed.
local H = ...
local ns = H.pureNamespace()
local B = ns.DungeonBosses

H.test("final bosses: listed dungeons, loose names, wings, case", function()
    H.ok(B.IsFinal("Ragefire Chasm", "Bazzalan"))
    H.ok(not B.IsFinal("Ragefire Chasm", "Oggleflint"))
    H.ok(B.IsFinal("ragefire chasm", "BAZZALAN"), "any case")
    H.ok(B.IsFinal("Deadmines", "Edwin VanCleef"), "instance name without 'The'")
    H.ok(B.IsFinal("Scarlet Monastery", "Herod") and B.IsFinal("Scarlet Monastery", "High Inquisitor Whitemane"), "each wing")
    H.ok(B.IsFinal("Dire Maul", "King Gordok"))
    H.ok(B.IsFinal("Stratholme", "Baron Rivendare") and B.IsFinal("Stratholme", "Balnazzar"))
    H.ok(B.IsFinal("The Temple of Atal'Hakkar", "Shade of Eranikus"), "Sunken Temple's instance name")
    H.ok(B.IsFinal("Hall of Thanes", "Durgen Dirgehammer"), "a Forever dungeon")
    H.eq(B.For("Shaper's Terrace"), nil, "not open yet, not listed")
    H.ok(not B.IsFinal(nil, "Bazzalan")); H.ok(not B.IsFinal("Ragefire Chasm", nil))
end)

H.test("final bosses: every entry has at least one name", function()
    for dungeon, bosses in pairs(B.FINAL) do
        H.ok(type(bosses) == "table" and #bosses > 0, dungeon)
        for _, name in ipairs(bosses) do H.ok(type(name) == "string" and name ~= "", dungeon) end
    end
end)
