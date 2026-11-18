-- Core/XPRecent.lua
-- PURE: no WoW globals. Recent XP for the /fl xp window (1.14.6, D-146): each gain of
-- the XP bar as { t, xp }, kept for the last 10 minutes on the character
-- (char.xpRecent, so a /reload keeps it), and the window's numbers for the last 1, 5
-- or 10 minutes: the total, the pace per hour, how much of the level that is, the time
-- to the next level at that pace, and bars over the time.

local _, ns = ...

local XPRecent = {}
ns.XPRecent = XPRecent

XPRecent.KEEP = 600 -- seconds kept: the longest choice
-- The choices: seconds, and how many bars (each bar the same stretch of time).
XPRecent.SPANS = { { id = "1m", span = 60, bars = 12 }, { id = "5m", span = 300, bars = 20 }, { id = "10m", span = 600, bars = 20 } }

function XPRecent.Span(id)
    for _, s in ipairs(XPRecent.SPANS) do if s.id == id then return s end end
    return XPRecent.SPANS[2]
end

-- Drop gains older than KEEP (and junk). Changes the list in place; returns it.
function XPRecent.Prune(list, now)
    local keep = {}
    for _, g in ipairs(list or {}) do
        if type(g) == "table" and type(g[1]) == "number" and type(g[2]) == "number" and g[1] > now - XPRecent.KEEP and g[1] <= now + 5 then
            keep[#keep + 1] = g
        end
    end
    list = list or {}
    for i = #list, 1, -1 do list[i] = nil end
    for i, g in ipairs(keep) do list[i] = g end
    return list
end

-- One gain of the XP bar. Returns the list.
function XPRecent.Add(list, now, xp)
    list = list or {}
    if type(xp) == "number" and xp > 0 then list[#list + 1] = { now, math.floor(xp) } end
    return XPRecent.Prune(list, now)
end

-- The window's numbers. spanId: "1m" | "5m" | "10m"; xpNow, xpMax: the XP bar now
-- (nil when unknown, or at the level cap: no level share or time to level).
-- Returns { span, total, perHour, levelShare (0-1), toLevel (seconds), bars =
-- { { from, to, xp } }, top (the biggest bar), gains (how many) }.
function XPRecent.Summary(list, now, spanId, xpNow, xpMax)
    local s = XPRecent.Span(spanId)
    local width = s.span / s.bars
    local start = now - s.span
    local out = { span = s.span, id = s.id, total = 0, bars = {}, top = 0, gains = 0 }
    for i = 1, s.bars do out.bars[i] = { from = start + (i - 1) * width, to = start + i * width, xp = 0 } end
    for _, g in ipairs(list or {}) do
        local t, xp = g[1], g[2]
        if type(t) == "number" and type(xp) == "number" and t > start and t <= now then
            local i = math.min(s.bars, math.max(1, math.floor((t - start) / width) + 1))
            out.bars[i].xp = out.bars[i].xp + xp
            out.total = out.total + xp
            out.gains = out.gains + 1
        end
    end
    for _, b in ipairs(out.bars) do if b.xp > out.top then out.top = b.xp end end
    out.perHour = math.floor(out.total * 3600 / s.span + 0.5)
    if type(xpMax) == "number" and xpMax > 0 then
        out.levelShare = out.total / xpMax
        if type(xpNow) == "number" and out.perHour > 0 then
            out.toLevel = math.max(0, xpMax - xpNow) * 3600 / out.perHour
        end
    end
    return out
end

