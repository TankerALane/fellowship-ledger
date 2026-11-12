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

local state = { all = false }
local ui = {}
LeaderboardTab.state, LeaderboardTab.ui = state, ui -- for tests

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

-- The table lines (grid lines, as on the Dungeons tab).
function LeaderboardTab.Lines()
    local board = LeaderboardTab.Board()
    local out = {}
    local F = ns.Format
    local good = ns.Palette.Code(W.Color("good"))
    if #board == 0 then
        out[#out + 1] = { kind = "grid", segments = { seg(0, 1, state.all and L.LEADER_EMPTY_ALL or L.LEADER_EMPTY, "muted") } }
        return out
    end
    for _, d in ipairs(board) do
        local title = d.dungeon .. (d.range and string.format(" (%d-%d)", d.range[1], d.range[2]) or "")
        out[#out + 1] = { kind = "grid", shade = true, segments = { seg(0, 1, title, "heading", "large") } }
        out[#out + 1] = { kind = "grid", segments = { seg(0, .05, "#", "muted", "small"), seg(.06, .12, L.LEADER_COL_TIME, "muted", "small"),
            seg(.19, .53, L.LEADER_COL_GROUP, "muted", "small"), seg(.73, .12, L.LEADER_COL_DATE, "muted", "small"),
            seg(.86, .14, L.LEADER_COL_LEVELS, "muted", "small") }, rules = { { 0, 1 } } }
        for _, e in ipairs(d.clears) do
            local group = Leaderboard.Group(e, L)
            if e.mine then group = good .. group .. "|r" end
            local tip = function()
                local lines = Leaderboard.Members(e, L)
                if e.partial then
                    lines = { unpack(lines) }
                    lines[#lines + 1] = ns.DungeonsModel.PartialText(e.partial, L)
                end
                return L.LEADER_GROUP_TIP, lines
            end
            local top = e.rank == 1 and not e.partial
            out[#out + 1] = { kind = "grid", tooltip = tip, segments = { seg(0, .05, e.partial and "" or tostring(e.rank), top and "heading" or "text"),
                seg(.06, .12, F.Duration(e.clear) .. (e.partial and "*" or ""), top and "good" or "text"), seg(.19, .53, group),
                seg(.73, .12, date("%m-%d", e.finishedAt), "muted"),
                seg(.86, .14, e.levelMax and string.format(L.LEADER_LEVEL, e.levelMax) or "-", e.atLevel and "muted" or "bad") } }
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
    return out
end

function LeaderboardTab.Refresh()
    if not ui.table then return end
    ui.levelButton:SetSelected(not state.all)
    ui.allButton:SetSelected(state.all)
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
    ui.levelButton = W.Button(panel, L.LEADER_AT_LEVEL, 140, 20, function()
        state.all = false
        LeaderboardTab.Refresh()
    end)
    ui.levelButton:SetPoint("TOPLEFT", 4, -2)
    ui.allButton = W.Button(panel, L.LEADER_ALL_RUNS, 100, 20, function()
        state.all = true
        LeaderboardTab.Refresh()
    end)
    ui.allButton:SetPoint("LEFT", ui.levelButton, "RIGHT", 6, 0)
    ui.intro = W.Text(panel, "small", "muted")
    ui.intro:SetPoint("LEFT", ui.allButton, "RIGHT", 12, 0)
    ui.intro:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    ui.intro:SetJustifyH("LEFT")
    ui.intro:SetText(string.format(L.LEADER_INTRO, ns.DungeonLevels.OVER))
    ui.table = ns.Table.New(panel, { { label = "", width = 100 } }, { top = 30 })
    ui.table:SetHeadersShown(false)
end

ns.MainWindow.RegisterTab("leaderboard", build, function() LeaderboardTab.Refresh() end)
