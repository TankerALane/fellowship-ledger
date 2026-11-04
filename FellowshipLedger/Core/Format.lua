-- Core/Format.lua
-- PURE: no WoW globals. Text formatting for times, levels and money.

local _, ns = ...

local Format = {}
ns.Format = Format

-- 45 -> "45s", 623 -> "10m 23s", 3720 -> "1h 02m", 93600 -> "1d 02h"
function Format.Duration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    end
    if seconds < 86400 then
        return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
    end
    return string.format("%dd %02dh", math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600))
end

-- { from = 1, to = 2, active = 623, total = 842 } -> "1 -> 2: 10m 23s (total 14m 02s)"
function Format.LevelLine(rec)
    return string.format("%d -> %d: %s (total %s)", rec.from, rec.to,
        Format.Duration(rec.active), Format.Duration(rec.total))
end

-- Copper -> "12g 03s 07c" (no icons, so it reads the same in every skin). Signed if asked.
function Format.Money(copper, signed)
    copper = math.floor(tonumber(copper) or 0)
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = -copper
    elseif signed and copper > 0 then
        sign = "+"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor(copper % 10000 / 100)
    local c = copper % 100
    if g > 0 then return string.format("%s%dg %02ds %02dc", sign, g, s, c) end
    if s > 0 then return string.format("%s%ds %02dc", sign, s, c) end
    return string.format("%s%dc", sign, c)
end

-- 1234567 -> "1,234,567"
function Format.Number(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if digits:sub(1, 1) == "," then digits = digits:sub(2) end
    return sign .. digits
end

-- Turn a client format string ("Discovered: %s", "Discovered %s: %d experience gained")
-- into a Lua pattern that captures the first %s. Lets the ledger recognise game
-- messages in any client language using the client's own strings.
function Format.PatternFromFormat(fmt)
    local out, captured = {}, false
    local i = 1
    while i <= #fmt do
        local ch = fmt:sub(i, i)
        if ch == "%" then
            local spec = fmt:match("^%%%d*%$?[%-%d%.]*([sdif%%])", i)
            local whole = fmt:match("^(%%%d*%$?[%-%d%.]*[sdif%%])", i)
            if spec == "%" then
                out[#out + 1] = "%%"
            elseif spec == "s" then
                out[#out + 1] = captured and ".-" or "(.-)"
                captured = true
            elseif spec then
                out[#out + 1] = "[%d%.,]+"
            else
                out[#out + 1] = "%%"
                whole = "%"
            end
            i = i + #(whole or "%")
        else
            out[#out + 1] = ch:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. ch) or ch
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$"
end

-- Short forms for graph axes (tooltips keep the full forms above).
-- 1800 -> "30m", 5400 -> "1h 30m", 7200 -> "2h", 45 -> "45s"
function Format.DurationShort(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then
        if seconds % 60 == 0 then return math.floor(seconds / 60) .. "m" end
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    end
    local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if m == 0 then return h .. "h" end
    return string.format("%dh %02dm", h, m)
end

-- 60000 -> "+6g", 25000 -> "+2.5g", 5000 -> "+50s", -20000 -> "-2g", 0 -> "0"
function Format.MoneyShort(copper, signed)
    copper = math.floor(tonumber(copper) or 0)
    if copper == 0 then return "0" end
    local sign = copper < 0 and "-" or (signed and "+" or "")
    local a = math.abs(copper)
    local text
    if a >= 10000 then
        local g = a / 10000
        text = (g == math.floor(g)) and string.format("%dg", g) or (string.format("%.1f", g):gsub("%.0$", "") .. "g")
    elseif a >= 100 then
        local s = a / 100
        text = (s == math.floor(s)) and string.format("%ds", s) or (string.format("%.1f", s):gsub("%.0$", "") .. "s")
    else
        text = a .. "c"
    end
    return sign .. text
end

-- XP per hour from xp gained over active seconds; nil when there is too little time.
function Format.PerHour(amount, seconds)
    if not seconds or seconds < 60 then return nil end
    return math.floor(amount * 3600 / seconds + 0.5)
end
