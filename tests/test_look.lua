-- The 1.13.0 look: section titles in upper case (escape codes kept), the header's
-- friends line, the "This week" comparison with bars and crowns, Leaderboard bars.
local H = ...
local Mock = dofile(H.ROOT .. "/tests/wowmock.lua")
local ns = H.pureNamespace()
local F, FM = ns.Format, ns.FriendsModel
local L = setmetatable({ HEADER_STATUS = "%d of %d friends online, synced %s", HEADER_STATUS_ONE = "%d of %d friend online, synced %s",
    HEADER_NO_FRIENDS = "No ledger friends yet", NEVER = "never", COL_LEVELS = "Levels", COL_QUESTS = "Quests",
    COL_DUNGEONS = "Dungeons", COL_ACTIVE = "Active" }, { __index = function(_, k) return k end })

H.test("Format.Upper: text upper-cased, colors, textures and links left alone", function()
    H.eq(F.Upper("Recent levels"), "RECENT LEVELS")
    H.eq(F.Upper("|cff3b2a1aTotals|r (All)"), "|cff3b2a1aTOTALS|r (ALL)")
    local tex = "|TInterface\\AddOns\\FellowshipLedger\\media\\crown:0|t"
    H.eq(F.Upper(tex .. " best"), tex .. " BEST", "texture path kept")
    H.eq(F.Upper("|Hquest:12:5|h[Bounty]|h done"), "|Hquest:12:5|h[BOUNTY]|h DONE", "link data kept, shown text upper")
    H.eq(F.Upper(""), ""); H.eq(F.Upper(nil), nil)
end)

H.test("header status: friends online of all (blocked not counted), last sync", function()
    local friends = { a = { name = "A", online = true }, b = { name = "B" }, c = { name = "C", tag = "C#3", online = true } }
    H.eq(FM.HeaderStatus(friends, { ["C#3"] = true }, 1000 - 30, 1000, L), "1 of 2 friends online, synced just now")
    H.eq(FM.HeaderStatus({ a = { name = "A" } }, {}, nil, 1000, L), "0 of 1 friend online, synced never")
    H.eq(FM.HeaderStatus({}, {}, nil, 1000, L), "No ledger friends yet")
end)

H.test("comparison: a bar per stat, the best gets the crown, zero gets no bar", function()
    local rows = { { name = "You", isMe = true, levels = 2, quests = 10, dungeons = 0, active = 3600 },
        { name = "Tobin", levels = 4, quests = 5, dungeons = 0, active = 1800 } }
    local lines = FM.CompareLines(rows, L, { crown = "<C>", duration = function(s) return s .. "s" end, inset = 18 })
    H.eq(#lines, 3, "header plus two people")
    H.eq(lines[1].segments[1].text, "Levels"); H.eq(lines[1].segments[4].text, "Active")
    local function texts(line)
        local t = {}
        for _, s in ipairs(line.segments) do if s.text then t[#t + 1] = s.text end end
        return t
    end
    local function bars(line)
        local t = {}
        for _, s in ipairs(line.segments) do if s.bar then t[#t + 1] = s.bar end end
        return t
    end
    H.eq(table.concat(texts(lines[2]), "|"), "You|2|<C> 10|0|<C> 3600s")
    H.eq(table.concat(texts(lines[3]), "|"), "Tobin|<C> 4|5|0|1800s")
    H.eq(lines[2].segments[1].role, "good", "you in the good color")
    local b = bars(lines[2])
    H.eq(#b, 3, "no bar for 0 dungeons"); H.eq(b[1], 0.5); H.eq(b[2], 1)
    -- Alone: no crowns.
    local one = FM.CompareLines({ rows[2] }, L, { crown = "<C>" })
    H.eq(table.concat(texts(one[2]), "|"), "Tobin|4|5|0|1800")
end)

H.test("Leaderboard: the fastest clear has the crown and a full bar, slower ones less", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.runTimers(env)
    local now = env.time()
    local function run(at, clear)
        return { name = "The Deadmines", entered = at, completed = true, completedAt = at + clear, clear = clear,
            bossNames = { "A" }, splits = { { at = clear, fight = 10 } }, group = { levelMax = 20 } }
    end
    ns2.db.friends["bn:F#1"] = { kind = "bnet", name = "F", characters = { ["Zip-R"] = { name = "Zip", level = 20,
        runs = { run(now - 9000, 1200), run(now - 5000, 2400) } } } }
    ns2.LeaderboardTab.state.all = true
    local lines = ns2.LeaderboardTab.Lines()
    local clears = {}
    for _, l in ipairs(lines) do
        for _, s in ipairs(l.segments or {}) do if s.bar then clears[#clears + 1] = { line = l, bar = s.bar } end end
    end
    H.eq(#clears, 2, "a bar on each clear")
    H.eq(clears[1].bar, 1, "the fastest fills it"); H.eq(clears[2].bar, 0.5, "twice as slow, half")
    H.ok(clears[1].line.segments[1].text:find("crown", 1, true), "crown on #1: " .. clears[1].line.segments[1].text)
    H.ok(not clears[2].line.segments[1].text:find("crown", 1, true), "none on #2")
end)

H.test("Friends tab: This week compares you and friends side by side (fake data)", function()
    local env = Mock.new({ interface = 120105, tocFlavor = "Retail" })
    local ns2 = Mock.loadToc(H, env, "FellowshipLedger_Mainline.toc")
    Mock.fire(env, "ADDON_LOADED", "FellowshipLedger")
    Mock.fire(env, "PLAYER_LOGIN")
    Mock.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    Mock.runTimers(env)
    Mock.slash(env, "fake")
    ns2.MainWindow.Open("friends")
    local FT = ns2.FriendsTab
    FT.ui.weeklyButton:GetScript("OnClick")()
    local lines = ns2.FriendsTab.ui.table.lines
    local section, people, crowns = false, 0, 0
    for _, l in ipairs(lines) do
        if l.kind == "group" and l.section and l.text:find("This week", 1, true) then section = true end
        if l.kind == "grid" and l.segments[1] and l.segments[1].role ~= "muted" and #l.segments > 4 then
            people = people + 1
            for _, s in ipairs(l.segments) do if s.text and s.text:find("crown", 1, true) then crowns = crowns + 1 end end
        end
    end
    H.ok(section, "This week as a section title")
    H.ok(people >= 2, "people compared: " .. people)
    H.ok(crowns >= 1, "at least one crown")
    H.eq(ns2.MainWindow.status:GetText(), "", "fake data: the banner speaks, not the header")
end)