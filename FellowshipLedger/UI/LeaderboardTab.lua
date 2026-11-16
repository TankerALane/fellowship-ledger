-- UI/LeaderboardTab.lua
-- Leaderboard tab (D-115): for each dungeon the five fastest clears by you and your
-- friends (time, group, date, the group's top level), and under it the fastest kill of
-- each boss. At-level runs only by default; "All runs" shows the rest. A run of yours
-- that makes a top 5 gives a notice (Settings > Your notices).

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Leaderboard = ns.Leaderboard

local LeaderboardTab = {}
ns.LeaderboardTab = LeaderboardTab

-- collapsed[dungeon]: its clears and bosses hidden (click its title). Saved in
-- settings.leaderCollapsed so it stays after a /reload (Austin, 2026-11-15).
local state = { all = false, collapsed = {} }
local ui = {}
LeaderboardTab.state, LeaderboardTab.ui = state, ui -- for tests

local function collapsed(fresh)
    local s = ns.db and ns.db.settings
    if s then
        if fresh or type(s.leaderCollapsed) ~= "table" then s.leaderCollapsed = {} end
        state.collapsed = s.leaderCollapsed
    elseif fresh then
        state.collapsed = {}
    end
    return state.collapsed
end

local function seg(x, w, text, role, font, align)
    return { x = x, w = w, text = text or "", role = role or "text", font = font or "body", align = align }
end

local function entries(fake)
    local chars = fake and ns.Data.Characters() or ns.db.characters
    local friends = fake and ns.Data.Friends() or ns.db.friends
    return Leaderboard.Entries(chars, friends, function(f, key) return ns.FriendsModel.IsBlocked(ns.db.blocklist, f, key) end,
        function(_, c) return c.display or c.name end)
end

-- Every run as a Leaderboard entry, real data (for the dungeon timer, D-122).
function LeaderboardTab.Entries() return entries(false) end

function LeaderboardTab.Board()
    return Leaderboard.Build(entries(ns.Data.IsFake()), not state.all)
end

-- One open dungeon: the column labels, its clears (bar, crown on #1) and its bosses.
local function dungeonLines(out, d, crown, good)
    local F = ns.Format
    out[#out + 1] = { kind = "grid", segments = { seg(0, .05, "#", "muted", "small"), seg(.06, .12, L.LEADER_COL_TIME, "muted", "small"),
        seg(.33, .39, L.LEADER_COL_GROUP, "muted", "small"), seg(.73, .12, L.LEADER_COL_DATE, "muted", "small"),
        seg(.86, .14, L.LEADER_COL_LEVELS, "muted", "small") }, rules = { { 0, 1 } } }
    -- The bar (1.13.0): the fastest clear fills it, slower ones fill less (fastest / this).
    local fastest
    for _, e in ipairs(d.clears) do
        if (e.clear or 0) > 0 and (not fastest or e.clear < fastest) then fastest = e.clear end
    end
    for _, e in ipairs(d.clears) do
        local group = Leaderboard.Group(e, L)
        if e.mine then group = good .. group .. "|r" end
        local tip = function()
            local lines = Leaderboard.Members(e, L)
            if e.partial or e.levelGuess or not e.levelMax then
                lines = { unpack(lines) }
                if e.partial then lines[#lines + 1] = ns.DungeonsModel.PartialText(e.partial, L) end
                if e.levelGuess and e.levelMax then
                    lines[#lines + 1] = L.LEADER_LEVEL_GUESS_TIP
                elseif not e.levelMax then
                    lines[#lines + 1] = L.LEADER_LEVEL_UNKNOWN_TIP
                end
            end
            return L.LEADER_GROUP_TIP, lines
        end
        local top = e.rank == 1 and not e.partial
        local rank = e.partial and "" or ((top and (crown .. " ") or "") .. tostring(e.rank))
        local segments = { seg(0, .05, rank, top and "heading" or "text"),
            seg(.06, .12, F.Duration(e.clear) .. (e.partial and "*" or ""), top and "good" or "text"), seg(.33, .39, group),
            seg(.73, .12, date("%m-%d", e.finishedAt), "muted"),
            seg(.86, .14, e.levelMax and string.format(e.levelGuess and L.LEADER_LEVEL_GUESS or L.LEADER_LEVEL, e.levelMax) or "-",
                e.atLevel and "muted" or "bad") }
        if fastest and (e.clear or 0) > 0 then segments[#segments + 1] = { x = .19, w = .13, bar = fastest / e.clear } end
        out[#out + 1] = { kind = "grid", tooltip = tip, segments = segments }
    end
    if #d.bosses > 0 then
        out[#out + 1] = { kind = "grid", segments = { seg(.06, .94, L.LEADER_BOSSES, "muted", "small") } }
        for _, b in ipairs(d.bosses) do
            out[#out + 1] = { kind = "grid", tooltip = function() return b.name, Leaderboard.Members(b.entry, L) end, segments = { seg(.06, .30, b.name), seg(.37, .12, F.Duration(b.fight), "text", nil, "RIGHT"),
                seg(.52, .34, Leaderboard.Group(b.entry, L), "muted"), seg(.86, .14, date("%m-%d", b.entry.finishedAt), "muted") } }
        end
    end
    out[#out + 1] = { kind = "grid", segments = {} }
end

-- The table lines (grid lines, as on the Dungeons tab). Highest-level dungeon first;
-- click a dungeon's title to collapse or open it (Austin, 2026-11-15).
function LeaderboardTab.Lines()
    local board = LeaderboardTab.Board()
    local out = {}
    local good = ns.Palette.Code(W.Color("good"))
    if #board == 0 then
        out[#out + 1] = { kind = "grid", segments = { seg(0, 1, state.all and L.LEADER_EMPTY_ALL or L.LEADER_EMPTY, "muted") } }
        return out
    end
    local crown = ns.DetailModel.IconCode("crown", W.Color("section"))
    for _, d in ipairs(board) do
        local name = d.dungeon
        local closed = collapsed()[name]
        local title = (closed and "+ " or "- ") .. name .. (d.range and string.format(" (%d-%d)", d.range[1], d.range[2]) or "")
        local head = { kind = "grid", shade = true, dungeon = name, segments = { seg(0, .62, title, "heading", "large") },
            onClick = function()
                local c = collapsed()
                c[name] = not c[name] or nil
                LeaderboardTab.Refresh()
            end }
        -- Closed: the #1 clear on the title line, so dungeons can still be compared.
        local first = d.clears[1]
        if closed and first then
            head.segments[#head.segments + 1] = seg(.62, .38, string.format(L.LEADER_COLLAPSED_BEST,
                ns.Format.Duration(first.clear) .. (first.partial and "*" or ""), Leaderboard.Group(first, L)), "muted", nil, "RIGHT")
        end
        out[#out + 1] = head
        if not closed then dungeonLines(out, d, crown, good) end
    end
    return out
end

-- Collapse every dungeon, or open them all when every one is already collapsed.
function LeaderboardTab.ToggleAll()
    local board = LeaderboardTab.Board()
    local allClosed = #board > 0
    for _, d in ipairs(board) do if not collapsed()[d.dungeon] then allClosed = false end end
    local c = collapsed(true)
    if not allClosed then
        for _, d in ipairs(board) do c[d.dungeon] = true end
    end
    LeaderboardTab.Refresh()
end

function LeaderboardTab.Refresh()
    if not ui.table then return end
    ui.which:Select(state.all and "all" or "level")
    local board = LeaderboardTab.Board()
    local allClosed = #board > 0
    for _, d in ipairs(board) do if not collapsed()[d.dungeon] then allClosed = false end end
    ui.allToggle.text:SetText(allClosed and L.LEADER_OPEN_ALL or L.LEADER_COLLAPSE_ALL)
    ui.table:SetLines(LeaderboardTab.Lines())
end

-- A run of mine just completed (Trackers/Dungeons.lua): a notice if it made a top 5.
function LeaderboardTab.CheckRun(run)
    if ns.Data.IsFake() or ns.db.settings.leaderToasts == false or not (run and run.completedAt and run.name) then return nil end
    if run.partial then return nil end -- not timed from the start (D-127)
    local board = Leaderboard.Build(entries(false), true)
    local rank, e = Leaderboard.RankOf(board, run.name, run.completedAt)
    if not rank then return nil end
    ns.Toast.Show(L.LEADER_TOAST_TITLE, { string.format(L.LEADER_TOAST, rank, run.name, ns.Format.Duration(e.clear)) },
        { onClick = function() ns.MainWindow.Open("leaderboard") end })
    return rank
end

local function build(panel)
    ui.which = W.Segmented(panel, { { id = "level", label = L.LEADER_AT_LEVEL, width = 130 },
        { id = "all", label = L.LEADER_ALL_RUNS, width = 90 } }, function(id)
        state.all = id == "all"
        LeaderboardTab.Refresh()
    end)
    ui.which:SetPoint("TOPLEFT", 4, -2)
    ui.levelButton, ui.allButton = ui.which.buttons.level, ui.which.buttons.all
    ui.intro = W.Text(panel, "small", "muted")
    ui.allToggle = W.Button(panel, L.LEADER_COLLAPSE_ALL, 100, 20, function() LeaderboardTab.ToggleAll() end)
    ui.allToggle:SetPoint("TOPRIGHT", -4, -2)
    ui.intro:SetPoint("LEFT", ui.which, "RIGHT", 12, 0)
    ui.intro:SetPoint("RIGHT", ui.allToggle, "LEFT", -8, 0)
    ui.intro:SetJustifyH("LEFT")
    ui.intro:SetText(string.format(L.LEADER_INTRO, ns.DungeonLevels.OVER))
    ui.table = ns.Table.New(panel, { { label = "", width = 100 } }, { top = 30 })
    ui.table:SetHeadersShown(false)
end

ns.MainWindow.RegisterTab("leaderboard", build, function() LeaderboardTab.Refresh() end)
