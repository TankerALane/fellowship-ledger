-- Core/Namespace.lua
-- PURE: must not touch WoW globals at load time (unit-tested outside the game).
-- Creates the shared private namespace every other file receives as `ns`.

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME or "FellowshipLedger"
ns.VERSION = "1.11.1" -- overwritten at runtime from the TOC metadata when available

-- Small helpers shared by pure modules.
ns.util = ns.util or {}

-- Pack varargs keeping trailing nils (Lua 5.1 has no table.pack).
function ns.util.pack(...)
    return { n = select("#", ...), ... }
end

-- Shallow copy.
function ns.util.copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- "  Verify   show " -> "verify", "show". Command is lower-cased, rest is trimmed.
function ns.util.splitCommand(msg)
    local cmd, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    return (cmd or ""):lower(), rest or ""
end

-- Sorted list of the keys of a table.
function ns.util.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
