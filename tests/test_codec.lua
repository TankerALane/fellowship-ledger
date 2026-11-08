-- Pure protocol: escaping, share filter, bodies, chunking, reassembly, merge,
-- milestones, weekly summary, rate limiting, compare alignment.
local H = ...

local function ns_() return H.pureNamespace() end

local function sampleChar(ns)
    local c = ns.Character.Ensure({ class = "HUNTER", race = "BloodElf", faction = "Horde", level = 18, lastSeen = 500 }, 0)
    c.days["2026-11-01"] = { quests = 3, moneyNet = 1200, kills = 9, played = 600, active = 500, levels = 1, skillUps = 2 }
    c.days["2026-11-04"] = { quests = 6, moneyNet = -50, kills = 42, played = 2846, active = 2683, levels = 4 }
    c.levels[15] = { from = 14, to = 15, active = 492, total = 492, at = 100, partial = true }
    c.levels[16] = { from = 15, to = 16, active = 1003, total = 1091, at = 200 }
    c.sessions[1] = { start = 1793821542, stop = 1793824523, played = 2846, active = 2683, levelStart = 14, levelEnd = 18,
        counts = { quests = 6, levels = 4, moneyNet = 743965, kills = 42 } }
    return c
end

H.test("escape round-trips every separator", function()
    local C = ns_().Codec
    local s = "a|b,c;d~e=f%g\nh"
    local e = C.Escape(s)
    H.ok(not e:find("[|,;~=\n]"), e)
    H.eq(C.Unescape(e), s)
end)

H.test("share filter: only shared trackers' fields leave the client", function()
    local ns = ns_()
    local c = sampleChar(ns)
    c.flags.gold.share = false
    c.flags.kills.track = false
    local shared, any = ns.Codec.SharedTrackers(c, false)
    H.ok(any)
    H.ok(shared.quests and shared.levels and shared.time)
    H.ok(not shared.gold, "gold not shared")
    H.ok(not shared.kills, "kills not tracked so not shared")
    local body = ns.Codec.EncodeData("Vel-Testrealm", c, shared, nil)
    H.ok(body:find("qu=6", 1, true))
    H.ok(not body:find("mn=", 1, true), "no gold fields")
    H.ok(not body:find("kl=", 1, true), "no kill fields")
    local _, anyPaused = ns.Codec.SharedTrackers(c, true)
    H.eq(anyPaused, false, "pause shares nothing")
    for _, f in pairs(c.flags) do f.share = false end
    local _, anyOff = ns.Codec.SharedTrackers(c, false)
    H.eq(anyOff, false)
end)

H.test("HELLO, REQUEST and NAME round-trip", function()
    local C = ns_().Codec
    local h = C.DecodeHello(C.EncodeHello({ version = "0.0.1-dev", nameOptIn = true, wantReply = true,
        characters = { { key = "Vel-Testrealm", class = "HUNTER", level = 18, mask = "1101", lastSeen = 77 } } }))
    H.eq(h.version, "0.0.1-dev"); H.eq(h.nameOptIn, true); H.eq(h.wantReply, true)
    H.eq(h.characters[1].key, "Vel-Testrealm"); H.eq(h.characters[1].level, 18); H.eq(h.characters[1].mask, "1101")
    H.eq(C.DecodeRequest(C.EncodeRequest("2026-11-01")).since, "2026-11-01")
    H.eq(C.DecodeRequest(C.EncodeRequest(nil)).since, nil)
    H.eq(C.DecodeName(C.EncodeName("Vel-Testrealm")), "Vel-Testrealm")
end)

H.test("DATA round-trips days, levels and sessions, honouring 'since'", function()
    local ns = ns_()
    local c = sampleChar(ns)
    local shared = ns.Codec.SharedTrackers(c, false)
    local d = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Testrealm", c, shared, nil))
    H.eq(d.key, "Vel-Testrealm"); H.eq(d.class, "HUNTER"); H.eq(d.level, 18)
    H.eq(d.days["2026-11-04"].quests, 6)
    H.eq(d.days["2026-11-04"].moneyNet, -50, "negative numbers survive")
    H.eq(d.levels[16].active, 1003)
    H.eq(d.levels[15].partial, true)
    H.eq(d.sessions[1].counts.moneyNet, 743965)
    local since = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Testrealm", c, shared, "2026-11-02"))
    H.eq(since.days["2026-11-01"], nil, "older days skipped")
    H.ok(since.days["2026-11-04"])
end)

H.test("unknown fields and junk are ignored (forward compatible)", function()
    local C = ns_().Codec
    local d = C.DecodeData("c,Vel-Doom,HUNTER,BloodElf,Horde,18,5,1~d,2026-11-04,qu=2,zz=9,bad~x,whatever~l,notanumber")
    H.eq(d.days["2026-11-04"].quests, 2)
    H.eq(d.days["2026-11-04"].zz, nil)
    H.eq(C.DecodeData("d,2026-11-04,qu=1"), nil, "no character record -> nothing")
end)

H.test("chunks respect the size limit and reassemble in any order", function()
    local C = ns_().Codec
    local body = string.rep("abcdefghij%2C", 120)
    for _, size in ipairs({ 60, 200, 255 }) do
        local chunks = C.Chunk("R", "D", "a1", body, size)
        for _, ch in ipairs(chunks) do H.ok(#ch <= size, "chunk " .. #ch .. " > " .. size) end
        local r = C.NewReassembler()
        local out
        for i = #chunks, 1, -1 do
            local parsed = C.ParseChunk(chunks[i])
            H.eq(parsed.flavor, "R")
            out = C.Feed(r, "bn:X", parsed, 100) or out
            if i == 2 and #chunks > 1 then C.Feed(r, "bn:X", C.ParseChunk(chunks[2]), 100) end -- duplicate
        end
        H.eq(out, body, "size " .. size)
    end
    H.eq(C.ParseChunk("not a chunk"), nil)
end)

H.test("half-received messages time out", function()
    local C = ns_().Codec
    local chunks = C.Chunk("R", "D", "z", string.rep("x", 600), 100)
    local r = C.NewReassembler()
    C.Feed(r, "p", C.ParseChunk(chunks[1]), 0)
    C.Feed(r, "q", C.ParseChunk(chunks[1]), C.REASSEMBLY_TIMEOUT + 10) -- any feed prunes old ones
    local n = 0
    for _ in pairs(r.pending) do n = n + 1 end
    H.eq(n, 1, "the stale one was dropped")
end)

H.test("merge stores friend data and raises level milestones", function()
    local ns = ns_()
    local friends = {}
    local f = ns.Merge.Friend(friends, { id = "bn:Kim#1", kind = "bnet", name = "Kim", tag = "Kim#1", online = true })
    local c = sampleChar(ns)
    local shared = ns.Codec.SharedTrackers(c, false)
    local data = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Testrealm", c, shared, nil))
    local ev = ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 1000)
    H.eq(#ev, 0, "no milestone on first sight")
    H.eq(f.characters["Vel-Testrealm"].days["2026-11-04"].quests, 6)
    H.eq(f.characters["Vel-Testrealm"].name, "Vel")
    H.eq(f.lastUpdated, 1000)
    H.eq(f.syncedThrough, "2026-11-04")
    data.level = 21
    ev = ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 2000)
    H.eq(#ev, 2); H.eq(ev[1].level, 20)
    H.eq(ev[2].kind, "levels"); H.eq(ev[2].from, 18); H.eq(ev[2].to, 21); H.eq(ev[2].key, "Vel-Testrealm")
    data.days["2026-01-01"] = { quests = 1 }
    ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 3000)
    H.eq(f.characters["Vel-Testrealm"].days["2026-01-01"], nil, "days past 90 are not kept")
end)

H.test("friend milestones: level cap, profession ranks, dungeon clears", function()
    local ns = ns_()
    local M = ns.Merge
    local f = M.Friend({}, { id = "bn:Kim#1", kind = "bnet", name = "Kim" })
    local mask = string.rep("1", #ns.TrackerList.ORDER)
    local function data(level, profRank, runs)
        return { key = "Vel-R", class = "MAGE", level = level, mask = mask, days = {}, levels = {}, sessions = {}, chains = {},
            professions = { ["186"] = { name = "Mining", rank = profRank, max = 300 } }, runs = runs }
    end
    local E = 1793988137
    H.eq(#M.Data(f, data(58, 70, nil), "2026-11-06", "2026-08-09", 1), 0, "first sight: nothing")
    M.maxLevel = 60
    local ev = M.Data(f, data(60, 151, { { name = "Ruins of Lordaeron", entered = E, completed = true },
        { name = "Ragefire Chasm", entered = E - 9000 } }), "2026-11-06", "2026-08-09", 2)
    local kinds = {}
    for _, e in ipairs(ev) do
        if e.kind ~= "levels" then kinds[#kinds + 1] = e.kind .. ":" .. tostring(e.level or e.rank or e.dungeon) end
    end
    table.sort(kinds)
    H.eq(table.concat(kinds, ","), "dungeon:Ruins of Lordaeron,maxlevel:60,profession:150",
        "the cap replaces the every-10 notice; 75 and 150 crossed: only 150; an unfinished run is no clear")
    -- The same clear again, or a dungeon cleared before: no notice.
    ev = M.Data(f, data(60, 151, { { name = "Ruins of Lordaeron", entered = E, completed = true },
        { name = "Ruins of Lordaeron", entered = E + 9000, completed = true } }), "2026-11-06", "2026-08-09", 3)
    H.eq(#ev, 0)
    M.maxLevel = nil
    ev = M.Data(f, data(70, 151, nil), "2026-11-06", "2026-08-09", 4)
    H.eq(ev[1].kind, "level"); H.eq(ev[1].level, 70, "no known cap: a plain level notice")
end)

H.test("friends' deaths and blue+ loot: shared, merged, a notice for new loot only (D-105)", function()
    local ns = ns_()
    local C, M = ns.Codec, ns.Merge
    local NOW = 1793988137
    local c = sampleChar(ns)
    c.deathLog = { { at = NOW - 500, level = 17, killer = "Rot Hide Brute", killerLevel = 16, zone = "Silverpine, Forest" },
        { at = NOW - 100, level = 18, killerLevel = -1, killer = "Gesharahan", zone = "The Barrens" } }
    c.items = { { at = NOW - 400, link = "|cff1eff00|Hitem:2589::|h[Green]|h|r", quality = 2, quantity = 1 },
        { at = NOW - 300, link = "|cff0070dd|Hitem:6414::|h[Blue]|h|r", quality = 3, quantity = 1, zone = "Wailing Caverns" },
        { at = NOW - 200, link = "|cffa335ee|Hitem:873::|h[Epic]|h|r", quality = 4, quantity = 2 } }
    local shared = C.SharedTrackers(c, false)
    local body = C.EncodeData("Vel-R", c, shared, nil)
    H.ok(body:find("r," .. (NOW - 100) .. ",18,-1,Gesharahan,The Barrens", 1, true), body)
    H.ok(body:find("Silverpine%2C Forest", 1, true), "commas in a zone are escaped")
    H.ok(not body:find("i,%d+,2589"), "greens are not shared")
    H.ok(body:find("i," .. (NOW - 300) .. ",6414,3,1,Wailing Caverns", 1, true) and body:find(",873,4,2,", 1, true), body)
    local data = C.DecodeData(body)
    H.eq(#data.deathLog, 2); H.eq(data.deathLog[2].killerLevel, -1); H.eq(data.deathLog[1].zone, "Silverpine, Forest")
    H.eq(#data.loot, 2); H.eq(data.loot[1].id, 6414)
    -- Not shared: nothing sent.
    c.flags.deaths.share, c.flags.items.share = false, false
    local quiet = C.EncodeData("Vel-R", c, C.SharedTrackers(c, false), nil)
    H.ok(not quiet:find("~r,") and not quiet:find("~i,"), quiet)
    -- Merge: the first list is the baseline; a new item later is a notice.
    local f = M.Friend({}, { id = "bn:Kim#1", kind = "bnet", name = "Kim" })
    M.Data(f, data, "2026-11-06", "2026-08-09", NOW)
    local ev = M.Data(f, data, "2026-11-06", "2026-08-09", NOW)
    H.eq(#ev, 0, "nothing new")
    H.eq(#f.characters["Vel-R"].deathLog, 2); H.eq(#f.characters["Vel-R"].loot, 2)
    data.loot[#data.loot + 1] = { at = NOW - 10, id = 1234, quality = 3, count = 1 }
    data.loot[#data.loot + 1] = { at = NOW - 3 * 86400, id = 999, quality = 4, count = 1 }
    ev = M.Data(f, data, "2026-11-06", "2026-08-09", NOW)
    H.eq(#ev, 1, "an item looted days ago is stored, not announced"); H.eq(ev[1].kind, "loot"); H.eq(ev[1].itemID, 1234)
    H.eq(#f.characters["Vel-R"].loot, 4)
    local text = ns.Notices.Text(ev[1], "Kim", ns.L)
    H.eq(text, "Vel (Kim) looted item 1234 (loading)!")
    ev[1].itemText = "[Blue]"
    H.eq(ns.Notices.Text(ev[1], "Kim", ns.L), "Vel (Kim) looted [Blue]!")
    H.eq(ns.Notices.Select({ { event = ev[1] } }, { friendToastsLoot = false }, false)[1], nil, "its own switch")
    -- A friend who stops sharing deaths: their list is dropped.
    data.mask = data.mask:sub(1, 5) .. "0" .. data.mask:sub(7)
    M.Data(f, data, "2026-11-06", "2026-08-09", NOW)
    H.eq(f.characters["Vel-R"].deathLog, nil)
end)

H.test("weekly summary per friend, blocked friends left out", function()
    local ns = ns_()
    local fake = ns.FakeData.Generate(os.time({ year = 2026, month = 11, day = 4, hour = 12 }), os.time, os.date)
    local list = ns.Merge.Weekly(fake.friends, {}, "2026-11-04", os.time, os.date)
    H.eq(#list, 4)
    for i = 2, #list do H.ok(list[i - 1].active >= list[i].active, "sorted by active time") end
    local blocked = ns.Merge.Weekly(fake.friends, { ["Tobin#0003"] = true }, "2026-11-04", os.time, os.date)
    H.eq(#blocked, 3)
end)

H.test("rate limiter and back-off", function()
    local R = ns_().RateLimit
    local b = R.New(2, 4, 0)
    local sent = 0
    for _ = 1, 10 do if R.Take(b, 0) then sent = sent + 1 end end
    H.eq(sent, 4, "burst")
    H.ok(not R.Take(b, 0.2))
    H.ok(R.Take(b, 0.6), "refills at the rate")
    H.eq(R.Backoff(1), 2); H.eq(R.Backoff(3), 8); H.eq(R.Backoff(10), 60)
end)

H.test("compare alignment by level and by day", function()
    local G = ns_().GraphModel
    local rows = G.Align({ { label = "2", value = 10 }, { label = "10", value = 30 } }, { { label = "3", value = 5 }, { label = "2", value = 7 } })
    H.eq(#rows, 3)
    H.eq(rows[1].label, "2"); H.eq(rows[1].a, 10); H.eq(rows[1].b, 7)
    H.eq(rows[2].label, "3"); H.eq(rows[2].a, nil); H.eq(rows[2].b, 5)
    H.eq(rows[3].label, "10", "numeric order")
    H.ok(G.CanCompare("timePerLevel") and G.CanCompare("questsPerDay"))
    H.ok(not G.CanCompare("goldPerSession"))
end)
