-- UI/StatsModel.lua
-- PURE: no WoW globals. The views inside an opened character on the Me tab
-- (D-081): a row of tab buttons (Overview, Quests, Gold, Kills, Professions,
-- All completed), and the table lines for each view except Overview (that is
-- UI/DetailModel.lua). Lines are the "grid" lines UI/Table.lua draws.

local _, ns = ...

local StatsModel = {}
ns.StatsModel = StatsModel

StatsModel.TABS = { "overview", "xp", "quests", "gold", "kills", "professions", "completed", "bests" }
StatsModel.TAB_LABEL = { overview = "DETAIL_TAB_OVERVIEW", xp = "DETAIL_TAB_XP", quests = "DETAIL_TAB_QUESTS", gold = "DETAIL_TAB_GOLD",
    kills = "DETAIL_TAB_KILLS", professions = "DETAIL_TAB_PROFESSIONS", completed = "DETAIL_TAB_COMPLETED",
    dungeons = "DETAIL_TAB_DUNGEONS", bests = "DETAIL_TAB_BESTS" }
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

-- XP by source (D-120), laid out like Gold. The top is one session (Austin: this
-- session; for a character not being played, its last one): its XP, then each source
-- with its share. Under it the By level table, all time. Neither follows the range
-- buttons. session: { counts, active, start } (nil = none yet); title: the heading.
-- byLevel: char.levelXP; currentLevel marks the level being played; showAll/onToggle:
-- more than LEVEL_LIMIT levels.
StatsModel.LEVEL_LIMIT = 5
local function levelTable(out, byLevel, currentLevel, L, showAll, onToggle)
    local Format = ns.Format
    local rows = ns.XPSources.Levels(byLevel, currentLevel)
    if #rows == 0 then return end
    out[#out + 1] = { segs = {} }
    local heading = { segs = { seg(0, .30, L.STATS_XP_BY_LEVEL, "heading") } }
    if #rows > StatsModel.LEVEL_LIMIT then
        heading.segs[#heading.segs + 1] = { x = .70, w = .30, text = "", button = { label = showAll and L.DETAIL_SHOW_LESS
            or string.format(L.DETAIL_SHOW_ALL, #rows), onClick = onToggle } }
    end
    out[#out + 1] = heading
    local cols = { { "quest", .32 }, { "kill", .46 }, { "explore", .60 }, { "other", .76 } }
    local head = { seg(0, .12, L.STATS_COL_LEVEL, "muted", "small"), seg(.13, .16, L.STATS_COL_XP, "muted", "small", "RIGHT") }
    for _, c in ipairs(cols) do head[#head + 1] = seg(c[2], .13, L["XP_SOURCE_" .. c[1]:upper()], "muted", "small", "RIGHT") end
    out[#out + 1] = { segs = head, rules = { { 0, .90 } } }
    for i, r in ipairs(rows) do
        if i > StatsModel.LEVEL_LIMIT and not showAll then break end
        local label = r.current and string.format(L.STATS_XP_LEVEL_NOW, r.level) or tostring(r.level)
        local segs = { seg(0, .12, label, r.current and "good" or "text"), seg(.13, .16, Format.Number(r.total), "text", nil, "RIGHT") }
        for _, c in ipairs(cols) do
            local v = r[c[1]]
            segs[#segs + 1] = seg(c[2], .13, v > 0 and pct(v, r.total) or "-", v > 0 and "text" or "muted", nil, "RIGHT")
        end
        out[#out + 1] = { segs = segs }
    end
end

-- The session for the XP view: the live one for the character being played, else the
-- newest saved one. Returns session, title.
function StatsModel.XPSession(sessions, live, L, dateFn)
    if live then return live, L.STATS_XP_SESSION end
    local newest
    for _, s in ipairs(sessions or {}) do
        if not newest or (s.start or 0) > (newest.start or 0) then newest = s end
    end
    if not newest then return nil, L.STATS_XP_SESSION end
    return newest, string.format(L.STATS_XP_LAST_SESSION, dateFn("%m-%d", newest.start or 0))
end

function StatsModel.XP(session, L, byLevel, currentLevel, showAll, onToggle, title)
    local Format = ns.Format
    local sum = {}
    for k, v in pairs(session and session.counts or {}) do sum[k] = v end
    sum.active = session and session.active or 0
    local split = ns.XPSources.Split(sum)
    local out = { { height = 26, segs = { seg(0, .40, title or L.STATS_XP_SESSION, "heading", "large"),
        seg(.40, .30, string.format(L.STATS_XP_AMOUNT, Format.Number(split.total)), split.total > 0 and "good" or "text", "large") } } }
    local active = sum.active or 0
    local perHour = active >= 60 and math.floor(split.total * 3600 / active) or nil
    out[#out + 1] = { segs = { seg(0, 1, string.format(L.STATS_XP_SUM, perHour and Format.Number(perHour) or "-",
        sum.levels or 0, Format.Duration(active)), "muted") }, rules = { { 0, 1 } } }
    out[#out + 1] = { segs = {} }
    if split.total <= 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_NO_XP, "muted") } }
        levelTable(out, byLevel, currentLevel, L, showAll, onToggle)
        return out
    end
    out[#out + 1] = { segs = { seg(0, .20, L.STATS_COL_SOURCE, "muted", "small"), seg(.21, .14, L.STATS_COL_XP, "muted", "small", "RIGHT"),
        seg(.38, .40, L.STATS_COL_SHARE, "muted", "small") }, rules = { { 0, 1 } } }
    local rows = {}
    for _, r in ipairs(split.rows) do rows[#rows + 1] = { label = L["XP_SOURCE_" .. r.source:upper()], xp = r.xp } end
    if split.before > 0 then rows[#rows + 1] = { label = L.XP_SOURCE_BEFORE, xp = split.before, muted = true } end
    for _, r in ipairs(rows) do
        if r.xp > 0 then
            out[#out + 1] = { segs = { seg(0, .20, r.label, r.muted and "muted" or "text"),
                seg(.21, .14, Format.Number(r.xp), r.muted and "muted" or "text", nil, "RIGHT"),
                { x = .38, w = .40, bar = r.xp / split.total }, seg(.80, .08, pct(r.xp, split.total), "muted", nil, "RIGHT") } }
        end
    end
    out[#out + 1] = { segs = { seg(0, .20, L.STATS_XP_TOTAL_ROW, "heading"), seg(.21, .14, Format.Number(split.total), "heading", nil, "RIGHT") },
        rules = { { 0, .36 } } }
    levelTable(out, byLevel, currentLevel, L, showAll, onToggle)
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_XP_NOTE, "muted", "small") } }
    return out
end

-- A friend's character has no All completed (the game only lists your own).
StatsModel.FRIEND_TABS = { "overview", "xp", "quests", "gold", "kills", "professions", "dungeons" }

-- The tab buttons. current: a tab id; onPick(id); tabs: TABS (default) or FRIEND_TABS.
function StatsModel.TabLine(current, L, onPick, tabs)
    tabs = tabs or StatsModel.TABS
    local segs, w = {}, 1 / #StatsModel.TABS -- same button width either way
    for i, id in ipairs(tabs) do
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
    -- The headline (D-101): the net after everything, green when up, red when down.
    local net = sum.moneyNet or ((sum.moneyIn or 0) - (sum.moneyOut or 0))
    local netRole = net > 0 and "good" or net < 0 and "bad" or "text"
    local out = { { height = 26, segs = { seg(0, .30, net < 0 and L.STATS_GOLD_TOTAL_LOST or L.STATS_GOLD_TOTAL, "heading", "large"),
            seg(.30, .40, Format.Money(net, true), netRole, "large") } },
        { segs = { seg(0, 1, string.format(L.STATS_GOLD_SUM, Format.Money(sum.moneyIn or 0), Format.Money(sum.moneyOut or 0),
            Format.Money(net, true)), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
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
    out[#out + 1] = { segs = { seg(0, .16, L.STATS_GOLD_TOTAL_ROW, "heading"), seg(.17, .16, Format.Money(net, true), netRole, nil, "RIGHT") },
        rules = { { 0, .34 } } }
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_GOLD_NOTE, "muted", "small") } }
    return out
end

-- Kills: sum over the range (kills, rareKills, eliteKills, killType:<type>); kills = char.kills (all time).
-- For "all" the creature types come from the all-time table (it includes kills from before D-081).
function StatsModel.Kills(sum, kills, range, L, noTypes)
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
    if noTypes then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_KILLS_TYPES_NOT_SHARED, "muted") } }
        return out
    elseif #types == 0 then
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
-- skipUnnamed: leave out quests with no name (with Questie loaded these are the
-- game's hidden tracking quests, e.g. 99582 on Forever). Returns the groups
-- ({ { zone, names = { sorted } } } sorted by zone, the "other" group last) and
-- how many quests were left out.
function StatsModel.GroupCompleted(ids, infoOf, L, skipUnnamed)
    local byZone, groups, hidden = {}, {}, 0
    for _, id in ipairs(ids or {}) do
        local info = infoOf(id) or {}
        if skipUnnamed and not info.name then
            hidden = hidden + 1
        else
            local zone = info.zone or L.STATS_ZONE_OTHER
            local g = byZone[zone]
            if not g then
                g = { zone = zone, names = {}, other = info.zone == nil }
                byZone[zone] = g
                groups[#groups + 1] = g
            end
            g.names[#g.names + 1] = info.name or string.format(L.STATS_QUEST_NUM, id)
        end
    end
    for _, g in ipairs(groups) do table.sort(g.names) end
    table.sort(groups, function(a, b)
        if a.other ~= b.other then return not a.other end
        return a.zone < b.zone
    end)
    return groups, hidden
end

-- All completed quests: groups from GroupCompleted, or nil when the client has no list.
function StatsModel.Completed(groups, total, questieMissing, L, open, onToggle, hidden)
    local Format = ns.Format
    if not groups then return { { segs = { seg(0, 1, L.STATS_COMPLETED_NO_API, "muted") } } } end
    local sum = string.format(L.STATS_COMPLETED_SUM, Format.Number((total or 0) - (hidden or 0)))
    if (hidden or 0) > 0 then sum = sum .. string.format(L.STATS_COMPLETED_HIDDEN, Format.Number(hidden)) end
    local out = { { segs = { seg(0, 1, sum, "muted") }, rules = { { 0, 1 } } } }
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

-- Friends (D-083) ------------------------------------------------------------------
-- What a friend's character shares: day totals, level times, sessions, chains and
-- (from 1.2.0) profession ranks. shared: set of tracker ids from its share mask.

-- Totals listed in a friend's Overview: field, label, kind, owning tracker.
StatsModel.FRIEND_TOTALS = {
    { "played", "COL_PLAYED", "duration", "time" }, { "active", "COL_ACTIVE", "duration", "time" },
    { "xp", "STATS_T_XP", "number", "levels" }, { "quests", "COL_QUESTS", "number", "quests" },
    { "dungeonsCompleted", "STATS_T_DUNGEONS", "dungeons", "dungeons" }, { "deaths", "COL_DEATHS", "number", "deaths" },
    { "kills", "COL_KILLS", "kills", "kills" }, { "skillUps", "COL_SKILLUPS", "number", "professions" },
    { "zonesDiscovered", "STATS_T_ZONES", "number", "zones" }, { "repGained", "STATS_T_REP", "number", "reputation" },
    { "flightPaths", "STATS_T_FLIGHT", "number", "flightPaths" }, { "achievements", "STATS_T_ACH", "number", "achievements" },
    { "itemsNotable", "STATS_T_LOOT", "loot", "items" }, { "partyLevelUps", "STATS_T_PARTY", "number", "partyLevels" },
}

local function totalText(def, sum, L)
    local Format, field, kind = ns.Format, def[1], def[3]
    local v = sum[field] or 0
    if kind == "duration" then return Format.Duration(v) end
    if kind == "dungeons" then return string.format(L.STATS_T_OF, Format.Number(v), Format.Number(sum.dungeonsEntered or 0)) end
    if kind == "kills" then return string.format(L.STATS_T_KILLS, Format.Number(v), Format.Number(sum.rareKills or 0), Format.Number(sum.eliteKills or 0)) end
    if kind == "loot" then return string.format(L.STATS_T_LOOT_VALUE, Format.Number(v), Format.Number(sum.itemsEpic or 0)) end
    return Format.Number(v)
end

-- A friend's Overview: summary, recent levels (left) and totals for the range (right).
-- data: DetailModel.Data(char, ...) (levels and summary are used). rangeLabel: "Today", ...
function StatsModel.FriendOverview(data, sum, shared, L, rangeLabel, onToggle, valueCode)
    local out = { { segs = { seg(0, 1, ns.DetailModel.SummaryText(data.summary, L, valueCode), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    local left = {}
    local heading = { segs = { seg(0, .22, L.DETAIL_LEVELS, "heading") }, rules = { { 0, .36 } } }
    local limit = ns.DetailModel.LIMITS.levels
    if data.levels.total > limit then
        local label = (#data.levels.rows > limit) and L.DETAIL_SHOW_LESS or string.format(L.DETAIL_SHOW_ALL, data.levels.total)
        heading.segs[#heading.segs + 1] = { x = 0, w = .36, text = "", button = { label = label, onClick = onToggle } }
    end
    left[1] = heading
    if not shared.levels then
        left[2] = { segs = { seg(0, .36, L.STATS_NOT_SHARED, "muted") } }
    elseif #data.levels.rows == 0 then
        left[2] = { segs = { seg(0, .36, L.NO_LEVELS_YET, "muted") } }
    else
        left[2] = { segs = { seg(0, .12, L.DETAIL_COL_LEVEL, "muted", "small"), seg(.13, .10, L.DETAIL_COL_ACTIVE, "muted", "small"),
            seg(.24, .10, L.DETAIL_COL_PLAYED, "muted", "small") } }
        for _, r in ipairs(data.levels.rows) do
            left[#left + 1] = { segs = { seg(0, .12, r.level), seg(.13, .10, r.active), seg(.24, .10, r.played) } }
        end
    end
    local right = { { segs = { seg(.42, .58, string.format(L.STATS_TOTALS, rangeLabel), "heading") }, rules = { { .42, .58 } } } }
    for _, def in ipairs(StatsModel.FRIEND_TOTALS) do
        local on = def[4] == "time" or shared[def[4]]
        right[#right + 1] = { segs = { seg(.42, .30, L[def[2]], "muted"),
            seg(.73, .27, on and totalText(def, sum, L) or L.STATS_NOT_SHARED_SHORT, on and "text" or "muted") } }
    end
    for i = 1, math.max(#left, #right) do
        local a, b = left[i] or { segs = {} }, right[i] or { segs = {} }
        local segs, rules = {}, {}
        for _, s in ipairs(a.segs) do segs[#segs + 1] = s end
        for _, s in ipairs(b.segs) do segs[#segs + 1] = s end
        for _, r in ipairs(a.rules or {}) do rules[#rules + 1] = r end
        for _, r in ipairs(b.rules or {}) do rules[#rules + 1] = r end
        out[#out + 1] = { segs = segs, rules = #rules > 0 and rules or nil }
    end
    return out
end

-- Under a friend's Overview (D-105): their recent deaths and their blue or better loot,
-- laid out like our own (full width, one under the other). data: DetailModel.Data of
-- the friend's character (its items built from the shared loot); version: their ledger.
function StatsModel.FriendDeathsLoot(data, shared, L, skin, onToggle, version)
    local DM = ns.DetailModel
    local cols = DM.COLS.list
    local old = version == nil or ns.Merge.CompareVersions(version, "1.7.0") == -1
    local out = { { segs = {} } }
    local function part(title, kind, sec, sharedOn, empty)
        if not sharedOn or old then
            out[#out + 1] = { segs = { seg(0, .6, title, "heading") }, rules = { { 0, 1 } } }
            out[#out + 1] = { segs = { seg(0, 1, not sharedOn and L.STATS_NOT_SHARED or L.STATS_FRIEND_NEEDS_170, "muted") } }
        else
            for _, half in ipairs(DM.Section(title, sec, cols[kind], 0, 1, kind, L, skin, onToggle, empty)) do out[#out + 1] = half end
        end
    end
    part(L.DETAIL_DEATHS, "deaths", data.deaths, shared.deaths, L.DETAIL_NO_DEATHS)
    out[#out + 1] = { segs = {} }
    part(L.DETAIL_LOOT_FRIEND, "loot", data.loot, shared.items, L.DETAIL_NO_LOOT_FRIEND)
    return out
end

-- A friend's Quests: counts for the range and the chains they are on (titles are not shared).
-- common (D-106): quests in both your logs, { { id, name, level, zone } }, shown first
-- when there are any; onLink(q) for shift-click.
function StatsModel.FriendQuests(sum, chains, shared, L, common, onLink)
    local Format = ns.Format
    if not shared.quests then return { { segs = { seg(0, 1, L.STATS_NOT_SHARED, "muted") } } } end
    local out = { { segs = { seg(0, 1, string.format(L.STATS_FRIEND_QUESTS_SUM, Format.Number(sum.quests or 0),
        Format.Number(sum.questsAccepted or 0), Format.Number(sum.xp or 0)), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    if common and #common > 0 then
        out[#out + 1] = { segs = { seg(0, 1, string.format(L.STATS_FRIEND_COMMON, #common), "heading") }, rules = { { 0, 1 } } }
        for _, q in ipairs(common) do
            out[#out + 1] = { segs = { seg(0, .56, q.name or string.format(L.STATS_QUEST_NUM, q.id), "good"),
                seg(.56, .10, q.level and tostring(q.level) or "", "muted", nil, "CENTER"), seg(.68, .32, q.zone or "", "muted") },
                onClick = onLink and function() onLink(q) end or nil }
        end
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_FRIEND_COMMON_NOTE, "muted", "small") } }
        out[#out + 1] = { segs = {} }
    end
    local list = {}
    for key, c in pairs(chains or {}) do list[#list + 1] = { key = key, c = c } end
    table.sort(list, function(a, b) return tostring(a.c.name) < tostring(b.c.name) end)
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_FRIEND_CHAINS, "heading") }, rules = { { 0, 1 } } }
    if #list == 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_FRIEND_NO_CHAINS, "muted") } }
    else
        out[#out + 1] = { segs = { seg(0, .40, L.STATS_COL_CHAIN, "muted", "small"), seg(.41, .14, L.STATS_COL_STEP, "muted", "small"),
            seg(.56, .44, L.STATS_COL_STARTS_WITH, "muted", "small") } }
        for _, e in ipairs(list) do
            local c = e.c
            local starts = c.firstName and (c.startZone and string.format(L.CHAIN_PLACE, c.firstName, c.startZone) or c.firstName) or ""
            out[#out + 1] = { segs = { seg(0, .40, c.name or L.CHAIN_UNNAMED), seg(.41, .14, string.format(L.CHAIN_STEP_OF, c.step or 0, c.total or 0)),
                seg(.56, .44, starts, "muted") } }
        end
    end
    out[#out + 1] = { segs = {} }
    out[#out + 1] = { segs = { seg(0, 1, L.STATS_FRIEND_QUESTS_NOTE, "muted", "small") } }
    return out
end

-- A friend's Professions: skill-ups in the range, and each profession's rank when the
-- friend's version shares it (char.professions = { [key] = { name, rank, max, lastAt } }).
-- version: the friend's ledger version. No ranks from 1.2.0+ means the character
-- has no professions (1.3.0+ also says so outright); before 1.2.0 they were not sent.
function StatsModel.FriendProfessions(sum, profs, shared, L, dateFn, version)
    local Format = ns.Format
    if not shared.professions then return { { segs = { seg(0, 1, L.STATS_NOT_SHARED, "muted") } } } end
    local out = { { segs = { seg(0, 1, string.format(L.STATS_PROF_FRIEND_SUM, Format.Number(sum.skillUps or 0)), "muted") }, rules = { { 0, 1 } } },
        { segs = {} } }
    if not profs then
        local old = version == nil or ns.Merge.CompareVersions(version, "1.2.0") == -1
        out[#out + 1] = { segs = { seg(0, 1, old and L.STATS_PROF_FRIEND_OLD or L.STATS_PROF_FRIEND_NONE, "muted") } }
        return out
    end
    local keys = {}
    for key in pairs(profs) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(profs[a].name) < tostring(profs[b].name) end)
    if #keys == 0 then
        out[#out + 1] = { segs = { seg(0, 1, L.STATS_PROF_FRIEND_NONE, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(0, .22, L.STATS_COL_PROFESSION, "muted", "small"), seg(.23, .10, L.STATS_COL_RANK, "muted", "small", "CENTER"),
        seg(.35, .25, L.STATS_COL_PROGRESS, "muted", "small"), seg(.62, .38, L.STATS_COL_LAST, "muted", "small") }, rules = { { 0, 1 } } }
    for _, key in ipairs(keys) do
        local p = profs[key]
        local max = tonumber(p.max) or 0
        out[#out + 1] = { segs = { seg(0, .22, p.name or key), seg(.23, .10, string.format(L.STATS_RANK, p.rank or 0, max), "text", nil, "CENTER"),
            { x = .35, w = .25, bar = max > 0 and (p.rank or 0) / max or 0 },
            seg(.62, .38, (p.lastAt or 0) > 0 and dateFn("%m-%d, %H:%M", p.lastAt) or "", "muted") } }
    end
    return out
end

-- A friend's Dungeons view (D-095): their totals for the range (from day counts), then
-- which dungeons they ran, newest first. runs: the friend character's c.runs (1.5.0+
-- senders); fromKey: the range start day (nil = all); version: the friend's ledger.
StatsModel.FRIEND_RUNS_SHOWN = 15
function StatsModel.FriendDungeons(sum, runs, shared, L, dateFn, version, fromKey)
    if not shared.dungeons then return { { segs = { seg(0, 1, L.STATS_NOT_SHARED, "muted") } } } end
    local out = { { segs = { seg(0, 1, string.format(L.STATS_DUNGEONS_FRIEND_SUM, sum.dungeonsEntered or 0,
        sum.dungeonsCompleted or 0, sum.bossKills or 0), "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    local list = {}
    for _, r in ipairs(runs or {}) do
        if r.entered and (not fromKey or dateFn("%Y-%m-%d", r.entered) >= fromKey) then list[#list + 1] = r end
    end
    table.sort(list, function(a, b) return a.entered > b.entered end)
    if #list == 0 then
        local old = runs == nil and (version == nil or ns.Merge.CompareVersions(version, "1.5.0") == -1)
        out[#out + 1] = { segs = { seg(0, 1, old and L.STATS_DUNGEONS_FRIEND_OLD or L.STATS_DUNGEONS_FRIEND_NONE, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(0, .16, L.DCOL_WHEN, "muted", "small"), seg(.17, .37, L.DCOL_DUNGEON, "muted", "small"),
        seg(.55, .10, L.DCOL_TIME, "muted", "small", "RIGHT"), seg(.66, .10, L.DCOL_BOSSES, "muted", "small", "RIGHT"),
        seg(.77, .09, L.DCOL_DEATHS, "muted", "small", "RIGHT"), seg(.88, .12, L.DCOL_RESULT, "muted", "small") }, rules = { { 0, 1 } } }
    for i = 1, math.min(#list, StatsModel.FRIEND_RUNS_SHOWN) do
        local r = list[i]
        local kills = r.kills or 0
        -- Time: the clear time when shared (1.7.0+, D-104), else the time inside.
        -- Hover for the boss times.
        local DM = ns.DungeonsModel
        local clear = DM.ClearTime(r)
        local splits = r.splits
        out[#out + 1] = { tooltip = function()
                local tip = {}
                if clear then tip[#tip + 1] = string.format(L.DUNGEONS_CLEARED_IN, DM.Clock(clear)) end
                tip[#tip + 1] = string.format(L.DUNGEONS_INSIDE, DM.Minutes(r.duration))
                for n, s in ipairs(splits or {}) do
                    tip[#tip + 1] = string.format(L.DUNGEONS_FRIEND_SPLIT, n, DM.Clock(s.at), s.fight and DM.Clock(s.fight) or "-")
                end
                if not splits and kills > 0 then tip[#tip + 1] = L.DUNGEONS_FRIEND_SPLITS_NONE end
                return r.name or "?", tip
            end,
            segs = { seg(0, .16, when(dateFn, r.entered)), seg(.17, .37, r.name or "?"),
            seg(.55, .10, clear and DM.Clock(clear) or DM.Minutes(r.duration), "text", nil, "RIGHT"),
            seg(.66, .10, r.bossCount and (kills .. " / " .. r.bossCount) or tostring(kills), "text", nil, "RIGHT"),
            seg(.77, .09, tostring(r.deaths or 0), "text", nil, "RIGHT"),
            seg(.88, .12, r.completed and L.DUNGEONS_COMPLETED or L.DUNGEONS_NOT_DONE, r.completed and "good" or "muted") } }
    end
    if #list > StatsModel.FRIEND_RUNS_SHOWN then
        out[#out + 1] = { segs = { seg(0, 1, string.format(L.STATS_DUNGEONS_MORE, #list - StatsModel.FRIEND_RUNS_SHOWN), "muted", "small") } }
    end
    return out
end

-- The tab line plus a view's lines, boxed like the card when layout is "card", with a
-- blank line after (as DetailModel.Lines ends).
-- Personal bests (D-115): rows from Bests.Rows. holderName(key) -> the character's shown name.
function StatsModel.Bests(rows, L, holderName)
    local out = { { segs = { seg(0, 1, L.BESTS_INTRO, "muted") }, rules = { { 0, 1 } } }, { segs = {} } }
    local any = false
    for _, r in ipairs(rows) do if not r.section then any = true end end
    if not any then
        out[#out + 1] = { segs = { seg(0, 1, L.BESTS_NONE, "muted") } }
        return out
    end
    out[#out + 1] = { segs = { seg(0, .34, L.BESTS_COL_RECORD, "muted", "small"), seg(.35, .15, L.BESTS_COL_MINE, "muted", "small", "RIGHT"),
        seg(.52, .15, L.BESTS_COL_ALL, "muted", "small", "RIGHT"), seg(.70, .30, L.BESTS_COL_HOLDER, "muted", "small") }, rules = { { 0, 1 } } }
    for i, r in ipairs(rows) do
        local nextRow = rows[i + 1]
        if r.section then
            -- A section with no rows under it is left out.
            if nextRow and not nextRow.section then out[#out + 1] = { segs = { seg(0, 1, r.section, "heading") } } end
        else
            local holder = r.holder and ((holderName and holderName(r.holder)) or r.holder) or ""
            out[#out + 1] = { segs = { seg(0, .34, r.label), seg(.35, .15, r.mine, r.mineIsAll and "good" or "text", nil, "RIGHT"),
                seg(.52, .15, r.all, "text", nil, "RIGHT"), seg(.70, .30, holder ~= "" and (holder .. ", " .. (r.when or "")) or "", "muted") } }
        end
    end
    return out
end

function StatsModel.Wrap(tabLine, parts, layout)
    local lines = { tabLine }
    for _, p in ipairs(parts) do
        local line = { kind = "grid", inset = StatsModel.INSET, segments = p.segs, rules = p.rules, onClick = p.onClick,
            tooltip = p.tooltip }
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
