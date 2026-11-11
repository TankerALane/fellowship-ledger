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
    local t = text(S.XP({ xp = 10000, xp_quest = 5000, xp_kill = 3000, xp_other = 500, active = 7200, levels = 2 }, L))
    H.ok(t:find("Total XP | 10,000", 1, true), t)
    H.ok(t:find("5,000 XP per active hour", 1, true), t)
    H.ok(t:find("Quests | 5,000 | 50%", 1, true), t)
    H.ok(t:find("Kills | 3,000 | 30%", 1, true), t)
    H.ok(t:find("Not split (older data) | 1,500 | 15%", 1, true), t)
    H.ok(not t:find("Exploration", 1, true), "empty sources left out")
    H.ok(text(S.XP({}, L)):find(L.STATS_NO_XP, 1, true))
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
