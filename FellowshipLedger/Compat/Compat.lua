-- Compat/Compat.lua
-- The only place that decides "does this client have API X?".
-- Rule: every uncertain call goes through Compat.Call (or is checked with Compat.Has
-- first), so a missing or failing API disables that one feature with a clear
-- message instead of raising a Lua error.

local _, ns = ...
local L = ns.L
local unpack = unpack or table.unpack

local Compat = {}
ns.Compat = Compat

Compat.flavor = nil     -- "Forever" | "Retail" | "Unknown", set by Detect()
Compat.tocFlavor = nil  -- the X-Flavor line of the TOC the client actually loaded
Compat.interface = nil
Compat.build = nil
Compat.version = nil

-- feature name -> reason it was disabled
Compat.disabled = {}

-- Resolve a dotted path such as "C_BattleNet.SendGameData" against _G.
-- Never errors; returns nil if any part is missing.
function Compat.Resolve(path)
    local ok, value = pcall(function()
        local obj = _G
        for part in string.gmatch(path, "[^%.]+") do
            if type(obj) ~= "table" then return nil end
            obj = obj[part]
        end
        return obj
    end)
    if ok then return value end
    return nil
end

function Compat.Has(path)
    return type(Compat.Resolve(path)) == "function"
end

function Compat.IsDisabled(feature)
    return Compat.disabled[feature] ~= nil
end

-- Turn a feature off once, with one message.
function Compat.Disable(feature, reason)
    if Compat.disabled[feature] then return end
    Compat.disabled[feature] = reason or "unknown reason"
    ns.Log.Warn(L.FEATURE_DISABLED, feature, tostring(reason))
end

-- Call the API at `path` on behalf of `feature`.
-- Returns ok (boolean) followed by the API's return values.
-- If the API is missing or errors, the feature is disabled and ok is false.
function Compat.Call(feature, path, ...)
    if Compat.disabled[feature] then return false end
    local fn = Compat.Resolve(path)
    if type(fn) ~= "function" then
        Compat.Disable(feature, path .. " is missing")
        return false
    end
    local result = ns.util.pack(pcall(fn, ...))
    if not result[1] then
        Compat.Disable(feature, path .. " failed: " .. tostring(result[2]))
        return false
    end
    return true, unpack(result, 2, result.n)
end

-- Like Call, but never disables anything or logs. For diagnostics (/fl verify)
-- where a missing API is the expected answer, not a fault.
function Compat.Try(path, ...)
    local fn = Compat.Resolve(path)
    if type(fn) ~= "function" then return false end
    local result = ns.util.pack(pcall(fn, ...))
    if not result[1] then return false end
    return true, unpack(result, 2, result.n)
end

-- True if `value` is a Midnight-style secret value we must not inspect.
-- On clients without issecretvalue nothing is secret.
function Compat.IsSecret(value)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then return false end
    local ok, secret = pcall(fn, value)
    return ok and secret == true
end

-- Safe tostring that never inspects a secret value.
function Compat.Describe(value)
    if Compat.IsSecret(value) then return "<secret>" end
    local ok, text = pcall(tostring, value)
    if ok then return text end
    return "<unprintable>"
end

function Compat.GetAddOnMetadata(field)
    local fn = Compat.Resolve("C_AddOns.GetAddOnMetadata") or _G.GetAddOnMetadata
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ns.ADDON_NAME, field)
    if ok then return value end
    return nil
end

-- Work out which client we are on. Called once from Init at ADDON_LOADED.
function Compat.Detect()
    local ok, version, build, _, interface = pcall(_G.GetBuildInfo)
    if ok then
        Compat.version = version
        Compat.build = build
        Compat.interface = interface
    end
    Compat.flavor = ns.FlavorLogic.FromInterface(Compat.interface)
    Compat.tocFlavor = Compat.GetAddOnMetadata("X-Flavor")
    local tocVersion = Compat.GetAddOnMetadata("Version")
    if tocVersion and tocVersion ~= "" then ns.VERSION = tocVersion end
    return Compat.flavor
end
