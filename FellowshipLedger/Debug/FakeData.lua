-- Debug/FakeData.lua
-- PURE: no WoW globals. /fl fake builds a SEPARATE data set (FellowshipLedgerDB.fake)
-- with 90 days of history for three of "your" characters, three Battle.net friends
-- with several characters each and one character-only friend. It is deterministic
-- (same seed, same world) so screenshots are repeatable. Every record carries
-- fake = true, the window shows a "fake data" banner, and nothing in it is ever
-- tracked into or sent from: trackers write only to db.characters, and the
-- sharing code (Phase 3) reads only real data.

local _, ns = ...

local FakeData = {}
ns.FakeData = FakeData

FakeData.SEED = 20261104
FakeData.DAYS = 90
FakeData.REALM = "Fakerealm"

local ZONES = { "Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood", "Stranglethorn Vale", "Arathi Highlands",
    "The Hinterlands", "Tanaris", "Feralas", "Un'Goro Crater" }
local DUNGEONS = { "The Deadmines", "Wailing Caverns", "Shadowfang Keep", "Blackfathom Deeps", "Gnomeregan", "Scarlet Monastery" }
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "DRUID", "PALADIN", "WARLOCK", "SHAMAN" }
local ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

local function newRng(seed)
    local state = seed % 2147483647
    if state <= 0 then state = state + 2147483646 end
    local rng = {}
    function rng.float()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
    function rng.int(lo, hi) return lo + math.floor(rng.float() * (hi - lo + 1)) end
    function rng.pick(list) return list[rng.int(1, #list)] end
    return rng
end

local function makeCharacter(rng, spec, now, timeFn, dateFn)
    local Days, Character = ns.Days, ns.Character
    local c = Character.Ensure({}, now - FakeData.DAYS * 86400)
    c.fake = true
    c.name, c.realm, c.class, c.race, c.faction = spec.name, FakeData.REALM, spec.class, "Human", "Alliance"
    local level = spec.startLevel
    local played, active = 0, 0
    local sessionId = 0
    local todayKey = Days.Key(now, dateFn)
    for d = FakeData.DAYS - 1, 0, -1 do
        local dayKey = Days.Shift(todayKey, -d, timeFn, dateFn)
        if rng.float() < spec.playChance then
            local y, m, dd = dayKey:match("^(%d+)-(%d+)-(%d+)$")
            local start = timeFn({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = rng.int(9, 20), min = rng.int(0, 59) })
            for _ = 1, rng.int(1, 2) do
                if start > now then break end
                sessionId = sessionId + 1
                local sPlayed = rng.int(20, 180) * 60
                local sActive = math.floor(sPlayed * (0.72 + rng.float() * 0.24))
                local s = ns.Sessions.New(sessionId, start, { level = level, money = 0 })
                s.stop, s.played, s.active = start + sPlayed, sPlayed, sActive
                local function add(field, n)
                    if n and n ~= 0 then
                        ns.Sessions.Add(s, field, n)
                        Days.Add(c.days, dayKey, field, n)
                    end
                end
                add("played", sPlayed)
                add("active", sActive)
                -- Levels: slower as level rises.
                local perLevel = (6 + level * 1.6) * 60
                local gained = math.min(math.floor(sActive / perLevel), 70 - level)
                for i = 1, gained do
                    local lvlActive = math.floor(perLevel * (0.75 + rng.float() * 0.5))
                    c.levels[level + 1] = { from = level, to = level + 1, active = lvlActive,
                        total = math.floor(lvlActive * (1.05 + rng.float() * 0.3)), at = start + i * math.floor(sPlayed / (gained + 1)),
                        zone = ZONES[math.min(#ZONES, math.floor(level / 7) + 1)], xpPerHour = rng.int(8, 30) * 1000 }
                    level = level + 1
                end
                add("levels", gained)
                local quests = rng.int(1, 14)
                add("quests", quests)
                add("questsAccepted", quests + rng.int(0, 3))
                add("xp", math.floor(sActive / 3600 * rng.int(8, 30) * 1000))
                add("kills", rng.int(5, 90))
                if rng.float() < 0.15 then add("rareKills", 1) end
                add("eliteKills", rng.int(0, 4))
                add("deaths", rng.float() < 0.3 and rng.int(1, 2) or 0)
                add("skillUps", rng.int(0, 8))
                add("zonesNew", rng.float() < 0.2 and 1 or 0)
                add("repGained", rng.int(0, 1200))
                local loot, vendor, quest = rng.int(0, 400) * level, rng.int(0, 300) * level, quests * rng.int(20, 90) * level
                local spent = -rng.int(0, 700) * level
                add("money_loot", loot); add("money_vendor", vendor + spent); add("money_quest", quest)
                add("moneyIn", loot + vendor + quest); add("moneyOut", -spent); add("moneyNet", loot + vendor + quest + spent)
                if rng.float() < 0.15 then
                    local done = rng.float() < 0.8
                    add("dungeonsEntered", 1)
                    if done then add("dungeonsCompleted", 1) end
                    local party = {}
                    for p = 1, 4 do party[p] = { class = rng.pick(CLASSES), role = ROLES[p + 1] or "DAMAGER" } end
                    c.dungeons[#c.dungeons + 1] = { name = rng.pick(DUNGEONS), entered = start + 600, left = start + 600 + rng.int(18, 55) * 60,
                        duration = rng.int(18, 55) * 60, deaths = rng.int(0, 3), completed = done or nil,
                        completedBy = done and "lastBoss" or nil, difficultyID = 1, party = party, bosses = {}, fake = true }
                end
                if d < 30 then
                    for q = 1, math.min(quests, 4) do
                        c.questLog[#c.questLog + 1] = { id = 90000 + sessionId * 10 + q, title = "A Task in " .. ZONES[rng.int(1, #ZONES)],
                            at = start + q * 300, xp = rng.int(200, 4000), money = rng.int(0, 5000) }
                    end
                end
                s.levelEnd = level
                c.sessions[#c.sessions + 1] = s
                played, active = played + sPlayed, active + sActive
                start = start + sPlayed + rng.int(60, 240) * 60
            end
        end
    end
    c.level = level
    c.clock = { played = played, active = active, pending = 0, last = now, lastActivity = now }
    c.professions["fake1"] = { name = "Mining", rank = math.min(300, level * 5), max = 300, history = {}, lastAt = now - 86400 }
    c.professions["fake2"] = { name = "Cooking", rank = math.min(300, level * 3), max = 300, history = {}, lastAt = now - 3 * 86400 }
    c.lastSeen = now - rng.int(0, 3) * 86400
    -- A few quest chains in progress, deaths and notable loot, for previews.
    local chainNames = { "The Venture Co. Menace", "Defias Brotherhood", "Nesingwary's Expedition", "The Missing Diplomat", "Stalvan's Legacy" }
    for i = 1, rng.int(1, 3) do
        local name = chainNames[rng.int(1, #chainNames)]
        local total = rng.int(4, 12)
        c.chains["fake:" .. name] = { name = name, step = rng.int(1, total), total = total, firstQuestID = 990000 + i,
            firstName = "Into " .. ZONES[rng.int(1, #ZONES)], startZone = ZONES[rng.int(1, #ZONES)], source = "game" }
    end
    -- Oldest first, as the trackers append them. Enough of each that "Show all" appears.
    local deaths = rng.int(2, 9)
    for i = 1, deaths do
        local killed = rng.float() < 0.7
        local dLevel = math.max(1, level - (deaths - i))
        c.deathLog[#c.deathLog + 1] = { at = now - (deaths - i + 1) * 86400 - rng.int(0, 80000), zone = ZONES[rng.int(1, #ZONES)],
            level = dLevel, killer = killed and ("Gnoll " .. ({ "Brute", "Mystic", "Poacher" })[rng.int(1, 3)]) or nil,
            killerSpell = killed and "Melee" or nil, killerStatus = killed and "ok" or "none",
            killerLevel = killed and rng.float() < 0.6 and (dLevel + rng.int(0, 3)) or nil }
    end
    local loot = rng.int(3, 8)
    for i = 1, loot do
        c.items[#c.items + 1] = { at = now - (loot - i + 1) * 86400 - rng.int(0, 80000), name = ({ "Gnoll Hide Belt", "Cutthroat's Mantle",
            "Seer's Robe", "Ironforge Breastplate" })[rng.int(1, 4)], quality = rng.int(2, 4), zone = ZONES[rng.int(1, #ZONES)] }
    end
    return c
end

-- Returns { characters = { [key] = char }, friends = { [id] = friend } }.
function FakeData.Generate(now, timeFn, dateFn, seed)
    local rng = newRng(seed or FakeData.SEED)
    local out = { characters = {}, friends = {}, createdAt = now, fake = true }
    local mine = {
        { name = "Aelwyn", class = "MAGE", startLevel = 1, playChance = 0.6 },
        { name = "Brannoc", class = "WARRIOR", startLevel = 12, playChance = 0.35 },
        { name = "Cyndra", class = "PRIEST", startLevel = 30, playChance = 0.25 },
    }
    for _, spec in ipairs(mine) do
        out.characters[ns.Character.Key(spec.name, FakeData.REALM)] = makeCharacter(rng, spec, now, timeFn, dateFn)
    end
    local friends = {
        { id = "fake-bn-1", kind = "bnet", name = "Fennick", tag = "Fennick#0001", online = true,
          chars = { { "Thistle", "DRUID", 5 }, { "Grimwald", "PALADIN", 20 }, { "Pip", "ROGUE", 1 } } },
        { id = "fake-bn-2", kind = "bnet", name = "Marisol", tag = "Marisol#0002", online = false,
          chars = { { "Seraphel", "SHAMAN", 15 }, { "Vexa", "WARLOCK", 34 } } },
        { id = "fake-bn-3", kind = "bnet", name = "Tobin", tag = "Tobin#0003", online = true,
          chars = { { "Hollin", "HUNTER", 1 }, { "Brask", "WARRIOR", 25 }, { "Lune", "PRIEST", 10 }, { "Okka", "MAGE", 40 } } },
        { id = "fake-char-1", kind = "char", name = "Wren-" .. FakeData.REALM, tag = "Wren-" .. FakeData.REALM, online = false,
          chars = { { "Wren", "ROGUE", 8 } } },
    }
    for _, f in ipairs(friends) do
        local friend = { kind = f.kind, name = f.name, tag = f.tag, online = f.online, fake = true,
            lastUpdated = now - rng.int(5, 3 * 24 * 60) * 60, characters = {} }
        for _, cs in ipairs(f.chars) do
            local spec = { name = cs[1], class = cs[2], startLevel = cs[3], playChance = 0.2 + rng.float() * 0.4 }
            friend.characters[ns.Character.Key(cs[1], FakeData.REALM)] = makeCharacter(rng, spec, now, timeFn, dateFn)
        end
        out.friends[f.id] = friend
    end
    return out
end
