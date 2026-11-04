-- Locale/Locale.lua
-- PURE: must not touch WoW globals at load time.
-- Every user-facing string goes through ns.L. A missing key falls back to the key
-- itself, so a forgotten translation shows readable English rather than erroring.

local _, ns = ...

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})

ns.L = L
ns.Locale = {}

-- Copy a table of strings into L. Later calls override earlier ones, so enUS
-- loads first as the base and other locales (added later) override it.
function ns.Locale.Set(strings)
    for k, v in pairs(strings) do
        rawset(L, k, v)
    end
end
