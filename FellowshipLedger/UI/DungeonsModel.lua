-- UI/DungeonsModel.lua
-- PURE: no WoW globals. The Dungeons tab (D-094): a summary per dungeon, my runs
-- (from each character's saved runs), then friends' totals (friends share day
-- counts only, so their runs are counted, not listed). Builds the tab's lines as
-- "grid" lines for UI/Table.lua, like UI/DetailModel.lua.

local _, ns = ...

local DungeonsModel = {}
ns.DungeonsModel = DungeonsModel

-- 2523 -> "42m", 3700 -> "1h 01m", nil -> "-"
function DungeonsModel.Minutes(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "-" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return m .. "m" end
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

-- Runs of my characters (charKey nil = all), entered on or after fromKey (nil = all),
-- newest first. An ongoing run that already counts is included as in progress.
-- Returns { { charKey, char, run, live = bool } }.
function DungeonsModel.Runs(chars, charKey, fromKey, dateFn, now)
    local out = {}
    for key, c in pairs(chars or {}) do
        if not charKey or key == charKey then
            local function add(run, live)
                if run and run.entered and (not fromKey or dateFn("%Y-%m-%d", run.entered) >= fromKey) then
                    out[#out + 1] = { charKey = key, char = c, run = run, live = live or nil }
                end
            end
            for _, run in ipairs(c.dungeons or {}) do add(run) end
            local cur = c.currentRun
            if cur and not cur.pending then add(cur, true) end
        end
    end
    table.sort(out, function(a, b)
        if a.run.entered ~= b.run.entered then return a.run.entered > b.run.entered end
        return tostring(a.charKey) < tostring(b.charKey)
    end)
    return out
end

local function durationOf(e, now)
    if e.live then return (e.run.lastSeen or now or e.run.entered) - e.run.entered end
    return e.run.duration
end

function DungeonsModel.Summary(runs)
    local s = { runs = #runs, completed = 0, bosses = 0, deaths = 0 }
    for _, e in ipairs(runs) do
        if e.run.completed then s.completed = s.completed + 1 end
        s.bosses = s.bosses + #(e.run.bosses or {})
        s.deaths = s.deaths + (e.run.deaths or 0)
    end
    return s
end

-- One row per dungeon name: runs, completed, best (fastest completed), average
-- (finished runs), last entered. Most recently run first.
function DungeonsModel.ByDungeon(runs, now)
    local by, list = {}, {}
    for _, e in ipairs(runs) do
        local name = e.run.name or "?"
        local d = by[name]
        if not d then
            d = { name = name, runs = 0, completed = 0, total = 0, timed = 0, last = 0 }
            by[name] = d
            list[#list + 1] = d
        end
        d.runs = d.runs + 1
        local dur = durationOf(e, now)
        if e.run.completed then
            d.completed = d.completed + 1
            if dur and (not d.best or dur < d.best) then d.best = dur end
        end
        if dur and not e.live then d.total, d.timed = d.total + dur, d.timed + 1 end
        if e.run.entered > d.last then d.last = e.run.entered end
    end
    for _, d in ipairs(list) do d.average = d.timed > 0 and d.total / d.timed or nil end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return list
end

-- "1 tank, 1 healer, 2 damage"; "solo" with nobody else.
function DungeonsModel.Group(party, L)
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0, other = 0 }
    for _, p in ipairs(party or {}) do
        local r = p.role
        if n[r] then n[r] = n[r] + 1 else n.other = n.other + 1 end
    end
    local parts = {}
    if n.TANK > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_TANKS, n.TANK) end
    if n.HEALER > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_HEALERS, n.HEALER) end
    if n.DAMAGER > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_DAMAGE, n.DAMAGER) end
    if n.other > 0 then parts[#parts + 1] = string.format(L.DUNGEONS_OTHERS, n.other) end
    if #parts == 0 then return L.DUNGEONS_SOLO end
    return table.concat(parts, ", ")
end

-- Bosses in kill order with minutes after entering; the one that completed the run
-- is marked final.
function DungeonsModel.Bosses(run)
    local list = {}
    for i, b in ipairs(run.bosses or {}) do
        list[i] = { n = i, name = b.name or "?", offset = b.at and run.entered and (b.at - run.entered) or nil, at = b.at }
    end
    if run.completed and run.completedBy == "lastBoss" and #list > 0 then
        local final = list[#list]
        for _, b in ipairs(list) do
            if run.completedAt and b.at == run.completedAt then final = b end
        end
        final.final = true
    end
    return list
end

-- Friends' totals over the range, from their shared day counts: one row per
-- character that entered a dungeon or killed a boss. Blocked friends are left out.
function DungeonsModel.FriendRows(friends, isBlocked, fromKey, todayKey)
    local out = {}
    for id, f in pairs(friends or {}) do
        if not (isBlocked and isBlocked(f)) then
            for key, c in pairs(f.characters or {}) do
                if not (isBlocked and isBlocked(f, key)) then
                    local e, d, b = 0, 0, 0
                    for day, v in pairs(c.days or {}) do
                        if (not fromKey or day >= fromKey) and (not todayKey or day <= todayKey) then
                            e, d, b = e + (v.dungeonsEntered or 0), d + (v.dungeonsCompleted or 0), b + (v.bossKills or 0)
                        end
                    end
                    if e > 0 or b > 0 then
                        out[#out + 1] = { friend = f.name or id, name = c.display or c.name or key, class = c.class,
                            entered = e, completed = d, bosses = b }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.friend ~= b.friend then return string.lower(a.friend) < string.lower(b.friend) end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return out
end

-- Lines --------------------------------------------------------------------------

local function seg(x, w, text, role, font, align)
    return { x = x, w = w, text = text, role = role, font = font, align = align }
end

-- Column layouts (fractions of the width).
DungeonsModel.RUN_COLS = { { 0, .12 }, { .12, .24 }, { .36, .20 }, { .56, .07, "RIGHT" }, { .63, .07, "RIGHT" },
    { .70, .07, "RIGHT" }, { .78, .12 }, { .90, .10 } }
DungeonsModel.DUNGEON_COLS = { { 0, .34 }, { .34, .10, "RIGHT" }, { .44, .12, "RIGHT" }, { .56, .10, "RIGHT" },
    { .66, .12, "RIGHT" }, { .78, .22, "RIGHT" } }
DungeonsModel.FRIEND_COLS = { { 0, .20 }, { .20, .30 }, { .50, .15, "RIGHT" }, { .65, .15, "RIGHT" }, { .80, .15, "RIGHT" } }

local function row(cols, texts, role, font, roles)
    local segs = {}
    for i, c in ipairs(cols) do
        if texts[i] ~= nil then
            segs[#segs + 1] = seg(c[1], c[2], texts[i], (roles and roles[i]) or role, font, c[3])
        end
    end
    return segs
end

-- opts: { chars, friends, isBlocked, charKey, range, fromKey, todayKey, now, dateFn,
--         L, expanded = { [runKey] = true }, toggle = fn(runKey), nameOf = fn(text, class),
--         goodCode = "|cff..", reset = "|r" }
-- Returns lines, summary.
function DungeonsModel.Lines(o)
    local L = o.L
    local nameOf = o.nameOf or function(t) return t end
    local lines = {}
    local runs = DungeonsModel.Runs(o.chars, o.charKey, o.fromKey, o.dateFn, o.now)
    local sum = DungeonsModel.Summary(runs)
    local when = function(t) return t and o.dateFn("%m-%d %H:%M", t) or "" end

    -- By dungeon
    lines[#lines + 1] = { kind = "group", text = L.DUNGEONS_BY }
    local by = DungeonsModel.ByDungeon(runs, o.now)
    if #by == 0 then
        lines[#lines + 1] = { kind = "detail", text = L.DUNGEONS_NO_RUNS }
    else
        lines[#lines + 1] = { kind = "grid", rules = { { 0, 1 } }, segments = row(DungeonsModel.DUNGEON_COLS,
            { L.DCOL_DUNGEON, L.DCOL_RUNS, L.DCOL_COMPLETED, L.DCOL_BEST, L.DCOL_AVERAGE, L.DCOL_LAST }, "muted", "small") }
        for i, d in ipairs(by) do
            lines[#lines + 1] = { kind = "grid", shade = i % 2 == 0, segments = row(DungeonsModel.DUNGEON_COLS,
                { d.name, tostring(d.runs), tostring(d.completed), DungeonsModel.Minutes(d.best),
                  DungeonsModel.Minutes(d.average), when(d.last) }) }
        end
    end
    lines[#lines + 1] = { kind = "detail", text = "", height = 8 }

    -- Runs
    lines[#lines + 1] = { kind = "group", text = L.DUNGEONS_RUNS }
    if #runs == 0 then
        lines[#lines + 1] = { kind = "detail", text = L.DUNGEONS_NO_RUNS }
    else
        lines[#lines + 1] = { kind = "grid", rules = { { 0, 1 } }, segments = row(DungeonsModel.RUN_COLS,
            { L.DCOL_WHEN, L.DCOL_DUNGEON, L.DCOL_CHARACTER, L.DCOL_TIME, L.DCOL_BOSSES, L.DCOL_DEATHS, L.DCOL_WITH,
              L.DCOL_RESULT }, "muted", "small") }
        for i, e in ipairs(runs) do
            local run = e.run
            local runKey = tostring(e.charKey) .. "|" .. tostring(run.entered)
            local open = o.expanded and o.expanded[runKey]
            local result, resultRole
            if e.live then result, resultRole = L.DUNGEONS_IN_PROGRESS, "muted"
            elseif run.completed then result, resultRole = L.DUNGEONS_COMPLETED, "good"
            else result, resultRole = L.DUNGEONS_NOT_DONE, "muted" end
            local bosses = #(run.bosses or {})
            local bossText = run.bossCount and (bosses .. " / " .. run.bossCount) or tostring(bosses)
            local c = e.char or {}
            lines[#lines + 1] = { kind = "grid", shade = open or i % 2 == 0,
                segments = row(DungeonsModel.RUN_COLS,
                    { (open and "- " or "+ ") .. when(run.entered), run.name or "?", nameOf(c.display or c.name or e.charKey, c.class),
                      DungeonsModel.Minutes(durationOf(e, o.now)), bossText, tostring(run.deaths or 0),
                      DungeonsModel.Group(run.party, L), result },
                    nil, nil, { nil, nil, nil, nil, nil, nil, nil, resultRole }),
                onClick = o.toggle and function() o.toggle(runKey) end or nil,
                tooltip = function() return run.name, { string.format(L.DUNGEONS_TIP_ENTERED, when(run.entered)),
                    string.format(L.DUNGEONS_TIP_CLICK) } end }
            if open then
                local list = DungeonsModel.Bosses(run)
                local dur = durationOf(e, o.now)
                local inset = 24
                if #list == 0 then
                    lines[#lines + 1] = { kind = "grid", inset = inset, box = "single",
                        segments = { seg(0, 1, L.DUNGEONS_NO_BOSSES, "muted") } }
                else
                    lines[#lines + 1] = { kind = "grid", inset = inset, box = "top",
                        segments = { seg(0, .6, L.DUNGEONS_TIMELINE, "muted", "small"),
                            seg(.6, .4, string.format(L.DUNGEONS_INSIDE, DungeonsModel.Minutes(dur)), "muted", "small", "RIGHT") } }
                    for j, b in ipairs(list) do
                        local frac = (b.offset and dur and dur > 0) and math.max(0, math.min(1, b.offset / dur)) or 0
                        lines[#lines + 1] = { kind = "grid", inset = inset, box = j == #list and "bottom" or "middle",
                            segments = { seg(0, .04, tostring(b.n), "muted", nil, "RIGHT"),
                                seg(.06, .30, b.name, b.final and "good" or "text"),
                                seg(.36, .12, b.offset and ("+" .. DungeonsModel.Minutes(b.offset)) or "", "muted", nil, "RIGHT"),
                                { x = .50, w = .36, bar = frac },
                                seg(.87, .13, b.final and L.DUNGEONS_FINAL or "", "good", "small") } }
                    end
                end
            end
        end
    end
    lines[#lines + 1] = { kind = "detail", text = "", height = 8 }
    -- Friends
    lines[#lines + 1] = { kind = "group", text = L.DUNGEONS_FRIENDS }
    local fr = DungeonsModel.FriendRows(o.friends, o.isBlocked, o.fromKey, o.todayKey)
    if #fr == 0 then
        lines[#lines + 1] = { kind = "detail", text = L.DUNGEONS_NO_FRIENDS }
    else
        lines[#lines + 1] = { kind = "grid", rules = { { 0, 1 } }, segments = row(DungeonsModel.FRIEND_COLS,
            { L.DCOL_FRIEND, L.DCOL_CHARACTER, L.DCOL_ENTERED, L.DCOL_COMPLETED, L.DCOL_BOSSES }, "muted", "small") }
        for i, f in ipairs(fr) do
            lines[#lines + 1] = { kind = "grid", shade = i % 2 == 0, segments = row(DungeonsModel.FRIEND_COLS,
                { f.friend, nameOf(f.name, f.class), tostring(f.entered), tostring(f.completed), tostring(f.bosses) }) }
        end
        lines[#lines + 1] = { kind = "detail", text = L.DUNGEONS_FRIENDS_NOTE }
    end
    lines[#lines + 1] = { kind = "detail", text = L.DUNGEONS_FOOTER }
    return lines, sum
end
