-- XP by source (Core/XPSources.lua, D-120): quests, kills, exploration and other,
-- whatever order the events come in; the XP view, the session line and sharing.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")

local function apply(counts, changes)
    for _, c in ipairs(changes) do counts[c[1]] = (counts[c[1]] or 0) + c[2] end
end

H.test("xp sources: a quest turn-in before or after the XP bar moves", function()
    local X = H.pureNamespace().XPSources
    local s, c = X.New(), {}
    apply(c, X.Mark(s, "quest", 450, 100.0))
    apply(c, X.Gain(s, 450, 100.3))
    H.eq(c.xp_quest, 450); H.eq(c.xp_other, nil)
    -- XP first, then the turn-in event: moved from other to quests.
    s, c = X.New(), {}
    apply(c, X.Gain(s, 450, 200.0))
    H.eq(c.xp_other, 450)
    apply(c, X.Mark(s, "quest", 450, 200.4))
    H.eq(c.xp_quest, 450); H.eq(c.xp_other, 0)
end)

H.test("xp sources: kills take the XP right after them, not later", function()
    local X = H.pureNamespace().XPSources
    local s, c = X.New(), {}
    apply(c, X.Mark(s, "kill", nil, 10.0))
    apply(c, X.Gain(s, 87, 10.2))
    apply(c, X.Gain(s, 40, 30.0)) -- long after: not the kill's
    H.eq(c.xp_kill, 87); H.eq(c.xp_other, 40)
    -- XP just before the kill event.
    s, c = X.New(), {}
    apply(c, X.Gain(s, 60, 50.0))
    apply(c, X.Mark(s, "kill", nil, 50.5))
    H.eq(c.xp_kill, 60); H.eq(c.xp_other, 0)
    -- Too far apart: stays other.
    s, c = X.New(), {}
    apply(c, X.Gain(s, 60, 50.0))
    apply(c, X.Mark(s, "kill", nil, 53.0))
    H.eq(c.xp_kill, nil); H.eq(c.xp_other, 60)
end)

H.test("xp sources: a gain bigger than the quest's XP, exploration, and a split total", function()
    local X = H.pureNamespace().XPSources
    local s, c = X.New(), {}
    apply(c, X.Mark(s, "kill", nil, 5.0))
    apply(c, X.Mark(s, "quest", 300, 5.1))
    apply(c, X.Gain(s, 380, 5.2)) -- one XP update for both
    H.eq(c.xp_quest, 300); H.eq(c.xp_kill, 80)
    apply(c, X.Mark(s, "explore", 1250, 9.0))
    apply(c, X.Gain(s, 1250, 9.1))
    H.eq(c.xp_explore, 1250)
    apply(c, X.Gain(s, 0, 9.2)); apply(c, X.Mark(s, "quest", 0, 9.3)); apply(c, X.Mark(s, "quest", nil, 9.3))
    c.xp = 380 + 1250 + 500 -- 500 from before sources were kept
    local split = X.Split(c)
    H.eq(split.total, 2130); H.eq(split.before, 500)
    local top, share = X.Top(split)
    H.eq(top, "explore"); H.ok(math.abs(share - 1250 / 2130) < 1e-9)
    H.eq(X.Top(X.Split({ xp = 900 })), nil, "nothing split yet")
end)

H.test("xp view: sources with shares, older XP as its own row, nothing in range", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local S, L = ns.StatsModel, ns.L
    local function text(parts)
        local out = {}
        for _, p in ipairs(parts) do for _, sg in ipairs(p.segs or {}) do if sg.text then out[#out + 1] = sg.text end end end
        return table.concat(out, " | ")
    end
    local t = text(S.XP({ counts = { xp = 10000, xp_quest = 5000, xp_kill = 3000, xp_other = 500, levels = 2 }, active = 7200 }, L))
    H.ok(t:find("This session | 10,000 XP", 1, true), t)
    H.ok(t:find("5,000 XP per active hour", 1, true), t)
    H.ok(t:find("Quests | 5,000 | 50%", 1, true), t)
    H.ok(t:find("Kills | 3,000 | 30%", 1, true), t)
    H.ok(t:find("Not split (older data) | 1,500 | 15%", 1, true), t)
    H.ok(not t:find("Exploration", 1, true), "empty sources left out")
    H.ok(text(S.XP(nil, L)):find(L.STATS_NO_XP, 1, true), "no session yet")
    -- The session to show: the live one, else the newest saved one with its date.
    local s, title = S.XPSession({ { start = 100 }, { start = 900 } }, nil, L, function() return "11-09" end)
    H.eq(s.start, 900); H.eq(title, "Last session (11-09)")
    local live = { start = 1 }
    s, title = S.XPSession({ { start = 900 } }, live, L, os.date)
    H.eq(s, live); H.eq(title, "This session")
end)

H.test("session line: XP and its biggest source", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local line = ns.Summary.Recap({ played = 3600, counts = { xp = 8200, xp_quest = 5084, xp_kill = 3116, quests = 4 } }, ns.L)
    H.ok(line:find("8,200 XP (62% from quests), 4 quests", 1, true), line)
    line = ns.Summary.Recap({ played = 3600, counts = { xp = 900 } }, ns.L)
    H.ok(line:find(", 900 XP", 1, true) and not line:find("from", 1, true), line)
end)

H.test("xp sources in the game: kill, quest and discovery XP counted by source and shared", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    local st = env.__state
    local function gain(n)
        st.xp = st.xp + n
        Mock.fire(env, "PLAYER_XP_UPDATE", "player")
    end
    Mock.fire(env, "PARTY_KILL", "Player-2", "Creature-8") -- a group member's kill
    gain(90)
    st.now = st.now + 10
    gain(450) -- the XP bar first, then the turn-in
    Mock.fire(env, "QUEST_TURNED_IN", 54, 450, 75)
    st.now = st.now + 10
    Mock.fire(env, "UI_INFO_MESSAGE", 999, "Discovered Booty Bay: 1,250 experience gained")
    gain(1250)
    st.now = st.now + 10
    gain(30) -- nothing explains it
    local day = env.FellowshipLedgerDB.characters["Tester-TestRealm"].days[os.date("%Y-%m-%d", st.now)]
    H.eq(day.xp, 1820)
    H.eq(day.xp_kill, 90); H.eq(day.xp_quest, 450); H.eq(day.xp_explore, 1250); H.eq(day.xp_other, 30)
    -- Shared with the levels tracker; older clients ignore the new codes.
    local C = ns.Codec
    for _, f in ipairs({ "xp_quest", "xp_kill", "xp_explore", "xp_other" }) do
        H.eq(C.FIELDS[f][2], "levels", f)
        H.eq(C.BY_CODE[C.FIELDS[f][1]], f)
    end
end)

H.test("xp by level: a gain across a level-up is split between the levels, moved XP keeps its level", function()
    local X = H.pureNamespace().XPSources
    local byLevel, changes = {}, {}
    local s = X.New()
    for _, ch in ipairs(X.Gain(s, 300, 1.0, 14)) do changes[#changes + 1] = ch end
    for _, ch in ipairs(X.Mark(s, "quest", 300, 1.2)) do changes[#changes + 1] = ch end
    for _, ch in ipairs(changes) do
        local src = ch[1]:match("^xp_(%a+)$")
        byLevel[ch[3]] = byLevel[ch[3]] or {}
        byLevel[ch[3]][src] = (byLevel[ch[3]][src] or 0) + ch[2]
    end
    H.eq(byLevel[14].quest, 300); H.eq(byLevel[14].other, 0)
    local rows = X.Levels({ [14] = { quest = 300, kill = 100 }, [15] = { kill = 50 }, [13] = {} }, 15)
    H.eq(#rows, 2, "levels with no XP left out")
    H.eq(rows[1].level, 15); H.eq(rows[1].current, true)
    H.eq(rows[2].total, 400)
end)

H.test("xp by level in the game: a level-up splits the gain, and the table shows both levels", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    local st = env.__state -- level 12, 300 / 2000
    Mock.fire(env, "PARTY_KILL", "Player-1", "Creature-1")
    st.xp = 1000
    Mock.fire(env, "PLAYER_XP_UPDATE", "player") -- 700 kill XP at 12
    st.now = st.now + 10
    Mock.fire(env, "QUEST_TURNED_IN", 77, 1500, 0)
    st.level, st.xp, st.xpMax = 13, 500, 2500
    Mock.fire(env, "PLAYER_XP_UPDATE", "player") -- 1000 to finish 12, 500 into 13
    local c = env.FellowshipLedgerDB.characters["Tester-TestRealm"]
    H.eq(c.levelXP[12].kill, 700); H.eq(c.levelXP[12].quest, 1000); H.eq(c.levelXP[13].quest, 500)
    local text = {}
    for _, p in ipairs(ns.StatsModel.XP(ns.Store.session, ns.L, c.levelXP, 13)) do
        for _, sg in ipairs(p.segs or {}) do if sg.text then text[#text + 1] = sg.text end end
    end
    text = table.concat(text, " | ")
    H.ok(text:find("This session | 2,200 XP", 1, true), text)
    H.ok(text:find("By level (all time)", 1, true), text)
    H.ok(text:find("13 (now) | 500 | 100%", 1, true), text)
    H.ok(text:find("12 | 1,700 | 59% | 41%", 1, true), text)
end)

H.test("xp by level is shared: lx records round trip, merge, and leave with the levels tracker", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local C, M = ns.Codec, ns.Merge
    local char = ns.Character.Ensure({ name = "Ann", realm = "R", level = 20, class = "MAGE" }, 1000)
    char.levelXP = { [19] = { quest = 400, kill = 300, explore = 0, other = 25 } }
    local all = {}
    for _, t in ipairs(ns.TrackerList.ORDER) do all[t.id] = true end
    all.time = true
    local body = C.EncodeData("Ann-R", char, all)
    H.ok(body:find("lx,19,400,300,0,25", 1, true), body)
    local data = C.DecodeData(body)
    H.eq(data.levelXP[19].kill, 300)
    local f = { characters = {} }
    M.Data(f, data, "2026-11-04", "2026-08-07", 1000)
    H.eq(f.characters["Ann-R"].levelXP[19].quest, 400)
    -- Without levels shared: not sent, and dropped on the receiving side.
    all.levels = nil
    body = C.EncodeData("Ann-R", char, all)
    H.ok(not body:find("lx,", 1, true), "not sent")
    M.Data(f, C.DecodeData(body), "2026-11-04", "2026-08-07", 2000)
    H.eq(f.characters["Ann-R"].levelXP, nil)
end)

H.test("xp by level: the last 5 levels, then Show all", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    local byLevel = {}
    for level = 1, 8 do byLevel[level] = { kill = level * 100 } end
    local function rows(showAll)
        local n, button = 0, nil
        local seenTable = false
        for _, p in ipairs(ns.StatsModel.XP({ counts = { xp = 50 } }, ns.L, byLevel, 8, showAll, function() end)) do
            for _, sg in ipairs(p.segs or {}) do
                if sg.button then button = sg.button.label end
                if sg.x == 0 and sg.w == .12 and sg.text and (sg.text:match("^%d+$") or sg.text:match("^%d+ %(now%)$")) then n = n + 1 end
            end
        end
        return n, button
    end
    local n, button = rows(false)
    H.eq(n, 5, "five levels"); H.eq(button, "Show all (8)")
    n, button = rows(true)
    H.eq(n, 8); H.eq(button, "Show less")
end)
