-- Compat/FlavorLogic.lua
-- PURE: must not touch WoW globals at load time.
-- Decides which client flavor we are on from the interface number, and holds the
-- per-flavor constants that keep Forever and retail data apart.

local _, ns = ...

local FlavorLogic = {}
ns.FlavorLogic = FlavorLogic

FlavorLogic.FOREVER = "Forever"
FlavorLogic.RETAIL = "Retail"
FlavorLogic.UNKNOWN = "Unknown"

-- Addon-message prefix per flavor. Different prefixes mean a Forever client never
-- even receives retail traffic for us, and the other way round.
FlavorLogic.PREFIX = {
    Forever = "FLDGF",
    Retail = "FLDGR",
}

-- One-letter code written into every payload, so a message can be dropped if it
-- ever arrives on the wrong flavor.
FlavorLogic.CODE = {
    Forever = "F",
    Retail = "R",
}

-- Interface number -> flavor.
-- Forever uses 16xxx (16001 seen in installed addons; Questie uses the same 16000-16999 range).
-- Retail (Mainline) is 120000 and up. Everything else (Classic Era, Anniversary,
-- Mists Classic, ...) is not supported.
function FlavorLogic.FromInterface(interface)
    local n = tonumber(interface)
    if not n then return FlavorLogic.UNKNOWN end
    if n >= 16000 and n < 17000 then return FlavorLogic.FOREVER end
    if n >= 120000 then return FlavorLogic.RETAIL end
    return FlavorLogic.UNKNOWN
end

function FlavorLogic.IsSupported(flavor)
    return flavor == FlavorLogic.FOREVER or flavor == FlavorLogic.RETAIL
end

-- True when a payload's flavor code belongs to our flavor.
function FlavorLogic.Matches(ourFlavor, code)
    return FlavorLogic.CODE[ourFlavor] ~= nil and FlavorLogic.CODE[ourFlavor] == code
end
