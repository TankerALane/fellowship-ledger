-- UI/Palette.lua
-- PURE: no WoW globals. Color roles for the two skins and the graph palettes.
-- Widgets ask for a role ("bg", "text", ...) and the skin decides the color, so
-- switching skins recolors everything in place.

local _, ns = ...

local Palette = {}
ns.Palette = Palette

local function rgb(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end
Palette.rgb = rgb

-- Brand colors (assets/README.md). Gold is for graphics; body text uses ink or dark gold.
Palette.BRAND = {
    parchment = rgb("F1E4C3"), ink = rgb("3B2A1A"), gold = rgb("C99A2E"), lightGold = rgb("E0B34A"),
    darkGold = rgb("7A560F"), night = rgb("2B1E12"), glass = rgb("F6EBD0"),
}

Palette.ROLES = { "bg", "panel", "border", "text", "muted", "heading", "accent", "buttonBg", "buttonBorder",
    "buttonText", "rule", "rowAlt", "good", "bad" }

Palette.SKINS = {
    -- "Ledger" (default since 1.0.1, D-073): dark leather with parchment-colored
    -- text and gold, so class colors show at (nearly) full strength.
    ledger = {
        bg = rgb("2B1E12", 0.97), panel = rgb("3A2918", 1), border = rgb("C99A2E"), text = rgb("F1E4C3"),
        muted = rgb("E0B34A"), heading = rgb("E0B34A"), accent = rgb("C99A2E"), buttonBg = rgb("C99A2E", 0.25),
        buttonBorder = rgb("C99A2E"), buttonText = rgb("F1E4C3"), rule = rgb("C99A2E"), rowAlt = rgb("E0B34A", 0.06),
        good = rgb("7FD08F"), bad = rgb("FF8A70"),
    },
    -- "Parchment": the light look of 1.0.0.
    parchment = {
        bg = rgb("F1E4C3", 0.98), panel = rgb("F6EBD0", 1), border = rgb("C99A2E"), text = rgb("3B2A1A"),
        muted = rgb("7A560F"), heading = rgb("3B2A1A"), accent = rgb("C99A2E"), buttonBg = rgb("C99A2E", 0.25),
        buttonBorder = rgb("7A560F"), buttonText = rgb("3B2A1A"), rule = rgb("C99A2E"), rowAlt = rgb("C99A2E", 0.08),
        good = rgb("1F5F3A"), bad = rgb("8A2A12"),
    },
    plain = {
        bg = { 0.05, 0.05, 0.06, 0.92 }, panel = { 0.1, 0.1, 0.12, 0.9 }, border = { 0.45, 0.45, 0.5, 1 },
        text = { 0.95, 0.95, 0.95, 1 }, muted = { 0.7, 0.7, 0.72, 1 }, heading = { 1, 0.82, 0, 1 },
        accent = { 1, 0.82, 0, 1 }, buttonBg = { 0.25, 0.25, 0.28, 0.9 }, buttonBorder = { 0.5, 0.5, 0.55, 1 },
        buttonText = { 1, 0.82, 0, 1 }, rule = { 0.45, 0.45, 0.5, 1 }, rowAlt = { 1, 1, 1, 0.04 },
        good = { 0.4, 0.85, 0.5, 1 }, bad = { 1, 0.45, 0.4, 1 },
    },
}

-- Graph series colors. "safe" is the Okabe-Ito set, distinguishable with the common
-- forms of color blindness. Graphs never rely on color alone: values are in tooltips,
-- negatives sit below the zero line and partial levels are labelled.
Palette.SERIES = {
    safe = { rgb("0072B2"), rgb("E69F00"), rgb("009E73"), rgb("CC79A7"), rgb("56B4E9"), rgb("D55E00") },
    brand = { rgb("C99A2E"), rgb("7A560F"), rgb("3B2A1A"), rgb("E0B34A"), rgb("8A2A12"), rgb("1F5F3A") },
    brandDark = { rgb("E0B34A"), rgb("F1E4C3"), rgb("C99A2E"), rgb("7FD08F"), rgb("FF8A70"), rgb("8FB8DE") },
}

-- Light skins (parchment) get dark text and no drop shadow; dark ones the reverse.
function Palette.IsLight(skin)
    return Palette.Luminance(Palette.Color(skin, "bg")) > 0.4
end

function Palette.Color(skin, role)
    local set = Palette.SKINS[skin] or Palette.SKINS.ledger
    return set[role] or set.text
end

-- Class colors, keyed by the class token UnitClass returns second (our own copy of
-- the usual values, so no game table is needed; an unknown token gets no color).
Palette.CLASS = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF",
    DEATHKNIGHT = "C41E3A", SHAMAN = "0070DD", MAGE = "3FC7EB", WARLOCK = "8788EE", MONK = "00FF98",
    DRUID = "FF7C0A", DEMONHUNTER = "A330C9", EVOKER = "33937F",
}
Palette.MIN_CONTRAST = 4.5 -- WCAG AA for body text

local function channel(v)
    if v <= 0.03928 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

function Palette.Luminance(c)
    return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

function Palette.Contrast(a, b)
    local x, y = Palette.Luminance(a), Palette.Luminance(b)
    if x < y then x, y = y, x end
    return (x + 0.05) / (y + 0.05)
end

-- A class's color for this skin, moved toward black (light skins) or white (dark
-- skins) just far enough to be readable on the skin's background: priest white
-- becomes grey on parchment, rogue yellow a dark gold. Nil for unknown classes.
function Palette.ClassColor(classToken, skin)
    local hex = type(classToken) == "string" and Palette.CLASS[classToken]
    if not hex then return nil end
    local c = rgb(hex)
    local bg = Palette.Color(skin, "bg")
    local target = Palette.Luminance(bg) > 0.4 and 0 or 1
    for _ = 1, 40 do
        if Palette.Contrast(c, bg) >= Palette.MIN_CONTRAST then break end
        for i = 1, 3 do c[i] = c[i] + (target - c[i]) * 0.08 end
    end
    return c
end

-- "|cffRRGGBB" escape for a color, for colored text inside a string.
function Palette.Code(c)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

function Palette.Series(colorblind, index, skin)
    local set = colorblind and Palette.SERIES.safe
        or (skin and not Palette.IsLight(skin) and Palette.SERIES.brandDark) or Palette.SERIES.brand
    return set[((index or 1) - 1) % #set + 1]
end
