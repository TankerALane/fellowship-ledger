-- UI/StatsModel.lua
-- PURE: no WoW globals. The views inside an opened character on the Me tab
-- (D-081): a row of tab buttons (Overview, Quests, Gold, Kills, Professions,
-- All completed), and the table lines for each view except Overview (that is
-- UI/DetailModel.lua). Lines are the "grid" lines UI/Table.lua draws.

local _, ns = ...

local StatsModel = {}
ns.StatsModel = StatsModel

StatsModel.TABS = { "overview", "quests", "gold", "kills", "professions", "completed" }
StatsModel.TAB_LABEL = { overview = "DETAIL_TAB_OVERVIEW", quests = "DETAIL_TAB_QUESTS", gold = "DETAIL_TAB_GOLD",
    kills = "DETAIL_TAB_KILLS", professions = "DETAIL_TAB_PROFESSIONS", completed = "DETAIL_TAB_COMPLETED" }
StatsModel.INSET = 18
StatsModel.QUEST_LIMIT = 10
StatsModel.POINT_LIMIT = 10
StatsModel.COMPLETED_PER_LINE = 3
StatsModel.GOLD_SOURCES = { "loot", "vendor", "quest", "mail", "auction", "other" }

local function seg(x, w, text, role, font, align)
    return { x = x, w = w, text = text or "", role = role or "text", font = font or "body", align = align }
end
local function when(dateFn, at) return dateFn("%m-%d, %H:%M", at or 0) end
local function pct(part, whole)
    if not whole or whole <= 0 then return "" end
    return string.format("%d%%", math.floor(part / whole * 100 + 0.5))
end

-- The tab buttons. current: a TABS id; onPick(id).
function StatsModel.TabLine(current, L, onPick)
    local segs, w = {}, 1 / #StatsModel.TABS
    for i, id in ipairs(StatsModel.TABS) do
        segs[i] = { x = (i - 1) * w, w = w, text = "", button = { label = L[StatsModel.TAB_LABEL[id]], fill = true,
            selected = id == current, onClick = function() onPick(id) end } }
    end
    return { kind = "grid", inset = StatsModel.INSET, segments = segs }
end

-- Quests turned in: log = char.questLog ({ id, title, at, xp, money, zone }), oldest first.
-- inRange(at) -> bool. zoneOf(id) -> zone name or nil (for entries saved without one).
function StatsModel.Quests(log, inRange, L, dateFn, showAll, zoneOf, onToggle)
    local Format = ns.Format
    local rows, xp, money = {}, 0, 0
    for i = #(log or {}), 1, -1 do
        local q = log[i]
        if inRange(q.at) then
            rows[#rows + 1] = q
            xp, money = xp + (tonumber(q.xp) or 0), money + (tonumber(q.money) or 0)
        end
    end
    local out = { { segs = { seg(0, 1, string.format(L.STATS_QUESTS_SUM, Format.Number(#rows), Format.Number(xp), Format.Money(money)), "muted") },
        rules = { { 0, 1 } } }, { segs = {} } }
    if #rows == 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_NO_QUESTS, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(0, .12, L.DETAIL_COL_WHEN, "muted", "small"), seg(.13, .40, L.STATS_COL_QUEST, "muted", "small"),
        seg(.54, .08, L.STATS_COL_XP, "muted", "small", "RIGHT"), seg(.63, .14, L.STATS_COL_GOLD, "muted", "small", "RIGHT"),
        seg(.80, .20, L.DETAIL_COL_ZONE, "muted", "small") }, rules = { { 0, 1 } } }
    local shown = showAll and #rows or math.min(#rows, StatsModel.QUEST_LIMIT)
    for i = 1, shown do
        local q = rows[i]
        local zone = q.zone or (zoneOf and q.id and zoneOf(q.id)) or ""
        out[#out + 1] = { segs = { seg(0, .12, when(dateFn, q.at), "muted"), seg(.13, .40, q.title or string.format(L.STATS_QUEST_NUM, q.id or 0)),
            seg(.54, .08, (tonumber(q.xp) or 0) > 0 and Format.Number(q.xp) or "", "text", nil, "RIGHT"),
            seg(.63, .14, (tonumber(q.money) or 0) > 0 and Format.Money(q.money) or "", "text", nil, "RIGHT"),
            seg(.80, .20, zone, "muted") } }
    end
    if #rows > StatsModel.QUEST_LIMIT then
        local label = showAll and L.DETAIL_SHOW_LESS or string.format(L.DETAIL_SHOW_ALL, #rows)
        out[#out + 1] = { segs = { { x = 0, w = 1, text = "", button = { label = label, onClick = onToggle } } } }
    end
    return out
end

-- Gold by source for a range: sum = Days.Sum over the range (money_<source>, moneyIn, moneyOut, moneyNet).
function StatsModel.Gold(sum, L)
    local Format = ns.Format
    local out = { { segs = { seg(0, 1, string.format(L.STATS_GOLD_SUM, Format.Money(sum.moneyIn or 0), Format.Money(sum.moneyOut or 0),
        Format.Money(sum.moneyNet or 0, true)), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    local gains, any = 0, false
    for _, s in ipairs(StatsModel.GOLD_SOURCES) do
        local v = sum["money_" .. s] or 0
        if v > 0 then gains = gains + v end
        if v ~= 0 then any = true end
    end
    if not any then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_NO_GOLD, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(0, .16, L.STATS_COL_SOURCE, "muted", "small"), seg(.17, .16, L.STATS_COL_NET, "muted", "small", "RIGHT"),
        seg(.38, .40, L.STATS_COL_SHARE_IN, "muted", "small") }, rules = { { 0, 1 } } }
    for _, s in ipairs(StatsModel.GOLD_SOURCES) do
        local v = sum["money_" .. s] or 0
        if v ~= 0 then
            local segs = { seg(0, .16, L["GOLD_SOURCE_" .. s:upper()]), seg(.17, .16, Format.Money(v, true), v < 0 and "bad" or "text", nil, "RIGHT") }
            if v > 0 then
                segs[#segs + 1] = { x = .38, w = .40, bar = v / gains }
                segs[#segs + 1] = seg(.80, .08, pct(v, gains), "muted", nil, "RIGHT")
            end
            out[#out + 1] = { segs = segs }
        end
    end
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_GOLD_NOTE, "muted", "small") } }
    return out
end

-- Kills: sum over the range (kills, rareKills, eliteKills, killType:<type>); kills = char.kills (all time).
-- For "all" the creature types come from the all-time table (it includes kills from before D-081).
function StatsModel.Kills(sum, kills, range, L)
    local Format = ns.Format
    kills = kills or {}
    local types = {}
    if range == "all" then
        for t, n in pairs(kills.byType or {}) do types[#types + 1] = { name = t, n = n } end
    else
        for field, n in pairs(sum) do
            local t = type(field) == "string" and field:match("^killType:(.+)$")
            if t and n > 0 then types[#types + 1] = { name = t, n = n } end
        end
    end
    table.sort(types, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    local total = 0
    for _, t in ipairs(types) do total = total + t.n end
    local inRange = range == "all" and (kills.total or sum.kills or 0) or (sum.kills or 0)
    local rare = range == "all" and (kills.rare or 0) or (sum.rareKills or 0)
    local elite = range == "all" and (kills.elite or 0) or (sum.eliteKills or 0)
    local out = { { segs = { seg(0, 1, string.format(L.STATS_KILLS_SUM, Format.Number(inRange), Format.Number(rare), Format.Number(elite),
        Format.Number(kills.total or 0)), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    if #types == 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_NO_KILLS, "muted") } }
    else
        out[#out + 1] = { segs = { seg(0, .22, L.STATS_COL_TYPE, "muted", "small"), seg(.23, .08, L.STATS_COL_KILLS, "muted", "small", "RIGHT"),
            seg(.34, .40, L.STATS_COL_SHARE, "muted", "small") }, rules = { { 0, 1 } } }
        for _, t in ipairs(types) do
            out[#out + 1] = { segs = { seg(0, .22, t.name), seg(.23, .08, Format.Number(t.n), "text", nil, "RIGHT"),
                { x = .34, w = .40, bar = t.n / total }, seg(.76, .08, pct(t.n, total), "muted", nil, "RIGHT") } }
        end
    end
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_KILLS_NOTE, "muted", "small") } }
    return out
end

-- Professions: profs = char.professions ({ name, rank, max, lastAt, history = { { rank, at, active } } }).
-- open[key] = true shows that profession's recent points; onToggle(key).
function StatsModel.Professions(profs, inRange, L, dateFn, open, onToggle, skillUps)
    local Format = ns.Format
    local keys = {}
    for key in pairs(profs or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(profs[a].name) < tostring(profs[b].name) end)
    local out = { { segs = { seg(0, 1, string.format(L.STATS_PROF_SUM, Format.Number(skillUps or 0)), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    if #keys == 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_NO_PROF, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(.03, .20, L.STATS_COL_PROFESSION, "muted", "small"), seg(.24, .10, L.STATS_COL_RANK, "muted", "small", "CENTER"),
        seg(.36, .22, L.STATS_COL_PROGRESS, "muted", "small"), seg(.60, .08, L.STATS_COL_GAINED, "muted", "small", "CENTER"),
        seg(.70, .30, L.STATS_COL_LAST, "muted", "small") }, rules = { { 0, 1 } } }
    for _, key in ipairs(keys) do
        local p = profs[key]
        local gained = 0
        for _, h in ipairs(p.history or {}) do if inRange(h.at) then gained = gained + 1 end end
        local isOpen = open and open[key]
        local max = tonumber(p.max) or 0
        out[#out + 1] = { onClick = function() onToggle(key) end, segs = {
            seg(0, .03, isOpen and "-" or "+", "muted"), seg(.03, .20, p.name or key),
            seg(.24, .10, string.format(L.STATS_RANK, p.rank or 0, max), "text", nil, "CENTER"),
            { x = .36, w = .22, bar = max > 0 and (p.rank or 0) / max or 0 },
            seg(.60, .08, gained > 0 and ("+" .. gained) or "0", "text", nil, "CENTER"),
            seg(.70, .30, p.lastAt and when(dateFn, p.lastAt) or "", "muted") } }
        if isOpen then
            local hist = p.history or {}
            if #hist == 0 then
                out[#out + 1] = { segs = { seg(.05, .95, L.STATS_NO_POINTS, "muted") } }
            else
                out[#out + 1] = { segs = { seg(.05, .08, L.STATS_COL_POINT, "muted", "small", "CENTER"), seg(.15, .15, L.DETAIL_COL_WHEN, "muted", "small"),
                    seg(.31, .17, L.STATS_COL_ACTIVE_FOR, "muted", "small", "RIGHT") }, rules = { { .05, .45 } } }
                local stop = math.max(1, #hist - StatsModel.POINT_LIMIT + 1)
                local slowest
                for i = #hist, stop, -1 do
                    local a = tonumber(hist[i].active) or 0
                    if a > 0 and (not slowest or a > (tonumber(hist[slowest].active) or 0)) then slowest = i end
                end
                for i = #hist, stop, -1 do
                    local h = hist[i]
                    local a = tonumber(h.active) or 0
                    out[#out + 1] = { segs = { seg(.05, .08, tostring(h.rank or ""), "text", nil, "CENTER"), seg(.15, .15, when(dateFn, h.at), "muted"),
                        seg(.31, .17, a > 0 and Format.Duration(a) or "", i == slowest and "bad" or "text", nil, "RIGHT"),
                        seg(.50, .30, i == slowest and L.STATS_SLOWEST or "", "muted") } }
                end
            end
        end
    end
    return out
end

-- Group completed quest IDs by zone. infoOf(id) -> { name, zone } (zone nil = other).
-- Returns { { zone, names = { sorted } } } sorted by zone, the "other" group last.
function StatsModel.GroupCompleted(ids, infoOf, L)
    local byZone, groups = {}, {}
    for _, id in ipairs(ids or {}) do
        local info = infoOf(id) or {}
        local zone = info.zone or L.STATS_ZONE_OTHER
        local g = byZone[zone]
        if not g then
            g = { zone = zone, names = {}, other = info.zone == nil }
            byZone[zone] = g
            groups[#groups + 1] = g
        end
        g.names[#g.names + 1] = info.name or string.format(L.STATS_QUEST_NUM, id)
    end
    for _, g in ipairs(groups) do table.sort(g.names) end
    table.sort(groups, function(a, b)
        if a.other ~= b.other then return not a.other end
        return a.zone < b.zone
    end)
    return groups
end

-- All completed quests: groups from GroupCompleted, or nil when the client has no list.
function StatsModel.Completed(groups, total, questieMissing, L, open, onToggle)
    local Format = ns.Format
    if not groups then return { { segs = { seg(0, 1, L.STATS_COMPLETED_NO_API, "muted") } } } end
    local out = { { segs = { seg(0, 1, string.format(L.STATS_COMPLETED_SUM, Format.Number(total or 0)), "muted") }, rules = { { 0, 1 } } } }
    if questieMissing then out[#out + 1] = { segs = { seg(0, 1, L.STATS_COMPLETED_NO_QUESTIE, "muted", "small") } } end
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(.03, .50, L.DETAIL_COL_ZONE, "muted", "small"), seg(.55, .10, L.STATS_COL_COMPLETED, "muted", "small", "CENTER") },
        rules = { { 0, 1 } } }
    local per = StatsModel.COMPLETED_PER_LINE
    for _, g in ipairs(groups) do
        local isOpen = open and open[g.zone]
        out[#out + 1] = { onClick = function() onToggle(g.zone) end, segs = { seg(0, .03, isOpen and "-" or "+", "muted"),
            seg(.03, .50, g.zone), seg(.55, .10, Format.Number(#g.names), "text", nil, "CENTER") } }
        if isOpen then
            for i = 1, #g.names, per do
                local segs = {}
                for j = 0, per - 1 do
                    local name = g.names[i + j]
                    if name then segs[#segs + 1] = seg(.05 + j * .32, .31, name) end
                end
                out[#out + 1] = { segs = segs }
            end
        end
    end
    return out
end

-- The tab line plus a view's lines, boxed like the card when layout is "card", with a
-- blank line after (as DetailModel.Lines ends).
function StatsModel.Wrap(tabLine, parts, layout)
    local lines = { tabLine }
    for _, p in ipairs(parts) do
        local line = { kind = "grid", inset = StatsModel.INSET, segments = p.segs, rules = p.rules, onClick = p.onClick }
        lines[#lines + 1] = line
    end
    if layout ~= "list" then
        lines[1].box = "top"
        for i = 2, #lines - 1 do lines[i].box = "mid" end
        lines[#lines].box = #lines > 1 and "bottom" or "single"
    end
    lines[#lines + 1] = { kind = "grid", segments = {} }
    return lines
end

-- Put the tab line above the Overview's lines (DetailModel.Lines), joining its box.
function StatsModel.WithTabs(tabLine, overview, layout)
    local lines = { tabLine }
    for _, l in ipairs(overview) do lines[#lines + 1] = l end
    if layout ~= "list" then
        tabLine.box = "top"
        local first = lines[2]
        if first and first.box == "top" then first.box = "mid" elseif first and first.box == "single" then first.box = "bottom" end
    end
    return lines
end
