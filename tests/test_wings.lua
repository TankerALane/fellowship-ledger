-- Dungeon wings (Core/Wings.lua, D-150): Scarlet Monastery's wings by door, boss and room.
local H = ...
local ns = H.pureNamespace()
local W = ns.Wings
local SM = "Scarlet Monastery"

H.test("wings: names", function()
    H.eq(W.Name(SM, "Library"), "Scarlet Monastery: Library")
    H.eq(W.Name("The Deadmines", "Library"), "The Deadmines", "only dungeons with wings")
    H.eq(W.Name(SM, nil), SM)
    H.eq(W.Base("Scarlet Monastery: Armory"), SM)
    H.eq(select(2, W.Split("Scarlet Monastery: Armory")), "Armory")
    H.eq(W.Base("Excavation Site: Wetlands"), "Excavation Site: Wetlands", "a colon in another dungeon's name")
    H.ok(W.Has(SM) and W.Has("Scarlet Monastery: Library"))
    H.ok(not W.Has("Razorfen Kraul"))
end)

H.test("wings: by door, boss and room", function()
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8482, y = 0.3035 }), "Graveyard", "Austin's door, 2026-11-24")
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8535, y = 0.3239 }), "Library")
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8567, y = 0.3181 }), "Armory", "Austin's Armory door, 2026-11-24")
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8568, y = 0.3179 }), "Armory", "the last spot outside, same report")
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8510, y = 0.3110 }), nil, "the Cathedral's door is not known until learned")
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.80, y = 0.30 }), nil, "far from every door")
    H.eq(W.FromDoor(SM, { map = 1414, x = 0.8482, y = 0.3035 }), nil, "another map")
    H.eq(W.FromDoor("Razorfen Kraul", { map = 1420, x = 0.8482, y = 0.3035 }), nil)
    H.eq(W.FromBoss(SM, "arcanist doan"), "Library", "any case")
    H.eq(W.FromBoss("Scarlet Monastery: Graveyard", "Herod"), "Armory", "a wing name works too")
    H.eq(W.FromBoss(SM, "Edwin VanCleef"), nil)
    H.eq(W.FromRoom(SM, "Athenaeum"), "Library")
    H.eq(W.FromRoom(SM, ""), nil)
    H.eq(W.Label(SM, { "Interrogator Vishas", "Bloodmage Thalnos" }), "Scarlet Monastery: Graveyard")
    H.eq(W.Label(SM, {}), SM, "no boss: unchanged")
    H.eq(W.Label("Scarlet Monastery: Library", { "Herod" }), "Scarlet Monastery: Library", "a named wing stays")
    H.eq(W.Label("The Deadmines", { "Herod" }), "The Deadmines")
end)

H.test("wings: each wing's final boss, the whole name keeps all four", function()
    local B = ns.DungeonBosses
    H.ok(B.IsFinal("Scarlet Monastery: Library", "Arcanist Doan"))
    H.ok(not B.IsFinal("Scarlet Monastery: Library", "Bloodmage Thalnos"), "another wing's final boss")
    H.eq(#B.For(SM), 4)
    H.ok(B.IsFinal("Deadmines", "Edwin VanCleef"), "a name inside a key still works")
end)

H.test("wings: the Leaderboard and the timer's compared run keep wings apart", function()
    local now = 1795400000
    local function run(at, bosses)
        local list = {}
        for i, b in ipairs(bosses) do list[i] = { name = b, at = at + 100 * i, fight = 20 } end
        return { name = SM, entered = at, started = at, completed = true, completedAt = at + 100 * #bosses, bosses = list, levelMax = 38 }
    end
    local chars = { ["Me-Realm"] = { dungeons = {
        run(now - 9000, { "Interrogator Vishas", "Bloodmage Thalnos" }),  -- a fast Graveyard
        run(now - 5000, { "Houndmaster Loksey", "Unknown Elite", "Arcanist Doan" }),
    } } }
    local entries = ns.Leaderboard.Entries(chars, {})
    local seen = {}
    for _, e in ipairs(entries) do seen[e.dungeon] = true end
    H.ok(seen["Scarlet Monastery: Graveyard"] and seen["Scarlet Monastery: Library"], "each under its wing")
    H.ok(not seen[SM])
    local t = ns.RunTimer.Target(entries, "Scarlet Monastery: Library", "mine", { name = "Scarlet Monastery: Library", entered = now, bosses = {} })
    H.ok(t, "a Library run to compare with")
    H.eq(t.order[1].name, "Houndmaster Loksey", "the Library's bosses, not the Graveyard's")
    H.eq(t.splits["Bloodmage Thalnos"], nil)
end)

H.test("wings: doors learned from a boss or room are used first (D-151)", function()
    local learned = {}
    local armory = { map = 1420, x = 0.8562, y = 0.3184 } -- a little off the known door
    H.eq(W.Learn(SM, "Armory", armory, learned), true)
    H.eq(learned.Armory.x, 0.8562)
    H.eq(W.Learn(SM, "Armory", { map = 1420, x = 0.80, y = 0.30 }, learned), false, "far from that wing's door: not kept")
    H.eq(W.Learn(SM, "Armory", { map = 1414, x = 0.8562, y = 0.3184 }, learned), false, "another map")
    H.eq(W.Learn("Razorfen Kraul", "Armory", armory, learned), false)
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8561, y = 0.3185 }, learned), "Armory", "by the learned door")
    -- The Cathedral: no door known, learned near the others, never on another wing's door.
    local cath = { map = 1420, x = 0.8510, y = 0.3110 }
    H.eq(W.FromDoor(SM, cath, learned), nil)
    H.eq(W.Learn(SM, "Cathedral", { map = 1420, x = 0.8536, y = 0.3238 }, learned), false, "the Library's door")
    H.eq(W.Learn(SM, "Cathedral", { map = 1420, x = 0.70, y = 0.30 }, learned), false, "far from the monastery")
    H.eq(W.Learn(SM, "Cathedral", cath, learned), true)
    H.eq(W.FromDoor(SM, { map = 1420, x = 0.8511, y = 0.3111 }, learned), "Cathedral", "known from then on")
end)
