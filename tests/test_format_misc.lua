local H = ...

H.test("durations", function()
    local F = H.pureNamespace().Format
    H.eq(F.Duration(0), "0s")
    H.eq(F.Duration(45), "45s")
    H.eq(F.Duration(623), "10m 23s")
    H.eq(F.Duration(842), "14m 02s")
    H.eq(F.Duration(3720), "1h 02m")
    H.eq(F.Duration(93600), "1d 02h")
    H.eq(F.Duration(-5), "0s")
    H.eq(F.Duration(nil), "0s")
end)

H.test("money", function()
    local F = H.pureNamespace().Format
    H.eq(F.Money(120307), "12g 03s 07c")
    H.eq(F.Money(507), "5s 07c")
    H.eq(F.Money(7), "7c")
    H.eq(F.Money(-120307), "-12g 03s 07c")
    H.eq(F.Money(507, true), "+5s 07c")
    H.eq(F.Money(0, true), "0c")
end)

H.test("client format strings become match patterns", function()
    local F = H.pureNamespace().Format
    local p = F.PatternFromFormat("Discovered: %s")
    H.eq(("Discovered: Ruins of Zul'Kunda"):match(p), "Ruins of Zul'Kunda")
    H.eq(("Bloodscalp Scout slain: 1/7"):match(p), nil)
    local xp = F.PatternFromFormat("Discovered %s: %d experience gained")
    H.eq(("Discovered Booty Bay: 1,250 experience gained"):match(xp), "Booty Bay")
    local pos = F.PatternFromFormat("%1$s entdeckt (100%%)")
    H.eq(("Beutebucht entdeckt (100%)"):match(pos), "Beutebucht")
    H.eq(("a.b (x)"):match(F.PatternFromFormat("a.b (%s)")), "x")
end)

H.test("numbers and per hour", function()
    local F = H.pureNamespace().Format
    H.eq(F.Number(1234567), "1,234,567")
    H.eq(F.Number(123), "123")
    H.eq(F.Number(-1234), "-1,234")
    H.eq(F.PerHour(1000, 1800), 2000)
    H.eq(F.PerHour(1000, 30), nil)
end)

H.test("tracker flags default on; share needs track and no pause", function()
    local ns = H.pureNamespace()
    local TL = ns.TrackerList
    local char = {}
    TL.EnsureFlags(char)
    H.ok(TL.IsTracking(char, "levels"))
    H.ok(TL.IsSharing(char, "levels", false))
    H.ok(not TL.IsSharing(char, "levels", true), "global pause")
    char.flags.levels.share = false
    H.ok(TL.IsTracking(char, "levels"))
    H.ok(not TL.IsSharing(char, "levels"))
    char.flags.quests.track = false
    H.ok(not TL.IsTracking(char, "quests"))
    H.ok(not TL.IsSharing(char, "quests"), "no share without track")
    TL.byId.items.status = "unavailable" -- a tracker whose APIs are missing
    H.ok(not TL.IsTracking(char, "items"), "unavailable trackers never track")
    TL.byId.items.status = "unverified"
    H.ok(not TL.IsTracking(char, "nonsense"))
    char.flags.levels.track = false
    TL.EnsureFlags(char)
    H.eq(char.flags.levels.track, false, "EnsureFlags keeps existing choices")
end)

H.test("character records are filled idempotently", function()
    local ns = H.pureNamespace()
    local c = ns.Character.Ensure({}, 100)
    c.days["2026-11-04"] = { quests = 1 }
    ns.Character.Ensure(c, 200)
    H.eq(c.created, 100)
    H.eq(c.days["2026-11-04"].quests, 1)
    H.eq(ns.Character.Key("Tess", "Argent Dawn"), "Tess-Argent Dawn")
end)

H.test("gold source classification", function()
    local G = H.pureNamespace().GoldLogic
    H.eq(G.Classify({ merchant = true, loot = true }, 100), "vendor")
    H.eq(G.Classify({ mail = true }, 100), "mail")
    H.eq(G.Classify({ auction = true }, 100), "auction")
    H.eq(G.Classify({ loot = true }, 100), "loot")
    H.eq(G.Classify({ lootClosedAt = 99 }, 100), "loot")
    H.eq(G.Classify({}, 100), "other")
    H.eq(G.Classify({ loot = true }, 100, -5), "other", "a loss is never loot")
    H.eq(G.Classify({ merchant = true }, 100, -5), "vendor")
    H.eq(G.Field("loot"), "money_loot")
end)

local function total(entries)
    local t = {}
    for _, e in ipairs(entries) do t[e[1]] = (t[e[1]] or 0) + e[2] end
    return t
end

H.test("quest money is matched whichever event comes first", function()
    local G = H.pureNamespace().GoldLogic
    -- money first, then the turn-in names it
    local m = G.NewMatcher()
    H.eq(total(G.OnMoney(m, {}, 100, 500)).other, 500)
    local fix = total(G.OnQuestReward(m, 101, 500))
    H.eq(fix.other, -500); H.eq(fix.quest, 500)
    -- turn-in first, then the money
    m = G.NewMatcher()
    H.eq(#G.OnQuestReward(m, 200, 300), 0)
    H.eq(total(G.OnMoney(m, {}, 201, 300)).quest, 300)
end)

H.test("several quick turn-ins each claim their own reward", function()
    local G = H.pureNamespace().GoldLogic
    local m = G.NewMatcher()
    local sums = {}
    local function add(entries) for k, v in pairs(total(entries)) do sums[k] = (sums[k] or 0) + v end end
    add(G.OnMoney(m, {}, 10, 452))
    add(G.OnMoney(m, {}, 11, 555))
    add(G.OnQuestReward(m, 12, 452))
    add(G.OnQuestReward(m, 12, 555))
    add(G.OnQuestReward(m, 14, 100))      -- arrives before its money
    add(G.OnMoney(m, { loot = true }, 15, 130)) -- 100 quest + 30 loot in one change
    H.eq(sums.quest, 1107)
    H.eq(sums.loot, 30)
    H.eq(sums.other or 0, 0)
end)

H.test("quest credit expires and spending never matches it", function()
    local G = H.pureNamespace().GoldLogic
    local m = G.NewMatcher()
    G.OnQuestReward(m, 0, 200)
    H.eq(total(G.OnMoney(m, {}, 2, -50)).other, -50, "a loss is not quest money")
    H.eq(total(G.OnMoney(m, {}, 20, 200)).other, 200, "credit expired after the window")
    m = G.NewMatcher()
    G.OnMoney(m, {}, 0, 100)
    H.eq(#G.OnQuestReward(m, 30, 100), 0, "old 'other' money is not reclaimed")
    H.eq(#G.OnQuestReward(m, 30, 0), 0)
end)

H.test("backup assessment", function()
    local ns = H.pureNamespace()
    local B = ns.BackupLogic
    local full = ns.Character.Ensure({}, 0)
    full.days["2026-11-04"] = { quests = 1 }
    full.savedAt = 1000
    local backup = B.Make("A-B", full, { debug = true }, 1000, 1)
    H.eq(backup.character.days["2026-11-04"].quests, 1)
    H.ok(backup.character ~= full, "deep copy")
    H.eq(B.Assess(full, backup, "A-B"), "ok")
    H.eq(B.Assess(nil, backup, "A-B"), "missing")
    H.eq(B.Assess(ns.Character.Ensure({}, 0), backup, "A-B"), "missing")
    H.eq(B.Assess(full, nil, "A-B"), "nobackup")
    H.eq(B.Assess(full, backup, "Other-Key"), "nobackup")
    local stale = B.DeepCopy(full)
    stale.savedAt = 500
    H.eq(B.Assess(stale, backup, "A-B"), "older")
end)

H.test("export lists every record type", function()
    local ns = H.pureNamespace()
    local c = ns.Character.Ensure({ class = "MAGE", race = "Human", faction = "Alliance", level = 3 }, 0)
    c.clock = { played = 100, active = 80 }
    c.levels[2] = { from = 1, to = 2, active = 60, total = 70, at = 50, zone = "Elwynn | Forest" }
    c.levels[3] = { from = 2, to = 3, active = 5, total = 9, at = 60, partial = true }
    c.days["2026-11-04"] = { quests = 2, levels = 1 }
    c.sessions[1] = { start = 1, stop = 100, played = 99, active = 80, levelStart = 1, levelEnd = 3 }
    c.questLog[1] = { at = 40, id = 7, title = "A Threat Within" }
    c.dungeons[1] = { entered = 60, name = "Deadmines", difficultyID = 1, completed = true, duration = 900, deaths = 2 }
    local text = ns.Export.Build({ characters = { ["Tess-Realm"] = c } }, "Retail", "2026-11-04 12:00")
    H.ok(text:find("^FLX1 | Retail | 2026%-11%-04 12:00"))
    H.ok(text:find("\nC | Tess-Realm | MAGE | Human | Alliance | 3 | 100 | 80", 1, true))
    H.ok(text:find("\nL | Tess-Realm | 1 | 2 | 60 | 70 | 50 | Elwynn / Forest | 0", 1, true), "pipes are escaped")
    H.ok(text:find("\nL | Tess-Realm | 2 | 3 | 5 | 9 | 60 |  | 1", 1, true), "partial flag exported")
    H.ok(text:find("\nD | Tess-Realm | 2026-11-04 | levels=1,quests=2", 1, true))
    H.ok(text:find("\nS | Tess-Realm | 1 | 100 | 99 | 80 | 1 | 3", 1, true))
    H.ok(text:find("\nQ | Tess-Realm | 40 | 7 | A Threat Within", 1, true))
    H.ok(text:find("\nR | Tess-Realm | 60 | Deadmines | 1 | 1 | 900 | 2", 1, true))
end)
