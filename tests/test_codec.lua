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
    local body = ns.Codec.EncodeData("Vel-Doomhammer", c, shared, nil)
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
        characters = { { key = "Vel-Doomhammer", class = "HUNTER", level = 18, mask = "1101", lastSeen = 77 } } }))
    H.eq(h.version, "0.0.1-dev"); H.eq(h.nameOptIn, true); H.eq(h.wantReply, true)
    H.eq(h.characters[1].key, "Vel-Doomhammer"); H.eq(h.characters[1].level, 18); H.eq(h.characters[1].mask, "1101")
    H.eq(C.DecodeRequest(C.EncodeRequest("2026-11-01")).since, "2026-11-01")
    H.eq(C.DecodeRequest(C.EncodeRequest(nil)).since, nil)
    H.eq(C.DecodeName(C.EncodeName("Vel-Doomhammer")), "Vel-Doomhammer")
end)

H.test("DATA round-trips days, levels and sessions, honouring 'since'", function()
    local ns = ns_()
    local c = sampleChar(ns)
    local shared = ns.Codec.SharedTrackers(c, false)
    local d = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Doomhammer", c, shared, nil))
    H.eq(d.key, "Vel-Doomhammer"); H.eq(d.class, "HUNTER"); H.eq(d.level, 18)
    H.eq(d.days["2026-11-04"].quests, 6)
    H.eq(d.days["2026-11-04"].moneyNet, -50, "negative numbers survive")
    H.eq(d.levels[16].active, 1003)
    H.eq(d.levels[15].partial, true)
    H.eq(d.sessions[1].counts.moneyNet, 743965)
    local since = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Doomhammer", c, shared, "2026-11-02"))
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
    local data = ns.Codec.DecodeData(ns.Codec.EncodeData("Vel-Doomhammer", c, shared, nil))
    local ev = ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 1000)
    H.eq(#ev, 0, "no milestone on first sight")
    H.eq(f.characters["Vel-Doomhammer"].days["2026-11-04"].quests, 6)
    H.eq(f.characters["Vel-Doomhammer"].name, "Vel")
    H.eq(f.lastUpdated, 1000)
    H.eq(f.syncedThrough, "2026-11-04")
    data.level = 21
    ev = ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 2000)
    H.eq(#ev, 1); H.eq(ev[1].level, 20)
    data.days["2026-01-01"] = { quests = 1 }
    ns.Merge.Data(f, data, "2026-11-04", "2026-08-07", 3000)
    H.eq(f.characters["Vel-Doomhammer"].days["2026-01-01"], nil, "days past 90 are not kept")
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
