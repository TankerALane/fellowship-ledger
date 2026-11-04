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
    ledger = {
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
}

function Palette.Color(skin, role)
    local set = Palette.SKINS[skin] or Palette.SKINS.ledger
    return set[role] or set.text
end

function Palette.Series(colorblind, index)
    local set = colorblind and Palette.SERIES.safe or Palette.SERIES.brand
    return set[((index or 1) - 1) % #set + 1]
end
