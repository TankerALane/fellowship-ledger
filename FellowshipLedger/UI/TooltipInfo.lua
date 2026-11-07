-- UI/TooltipInfo.lua
-- One ledger line in the game's tooltip when you hover a friend's character (D-099):
-- "Ledger: Hamlet, 12 quests and 2 dungeons this week". Only units that are players,
-- only characters a friend shares, and never a secret value (Midnight). The hook is
-- TooltipDataProcessor.AddTooltipPostCall for unit tooltips, or GameTooltip's
-- OnTooltipSetUnit on clients without it; both are on the /fl verify list
-- (x:tooltip.unit). Turned off in Settings with "tooltipInfo".

local _, ns = ...
local L = ns.L

local TooltipInfo = {}
ns.TooltipInfo = TooltipInfo
TooltipInfo.hook = nil -- "processor" | "script" | nil, for /fl verify

local function plain(v)
    if v == nil or ns.Compat.IsSecret(v) then return nil end
    return v
end

-- The character key of a unit, like Store's own key ("Name-Realm", on Forever "First-Last").
function TooltipInfo.KeyOf(unit)
    local ok, name, realm = ns.Compat.Try("UnitFullName", unit)
    name, realm = ok and plain(name) or nil, ok and plain(realm) or nil
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then
        local okR, r = ns.Compat.Try("GetNormalizedRealmName")
        realm = okR and plain(r) or nil
    end
    if type(realm) ~= "string" or realm == "" then return nil end
    return ns.Character.Key(name, realm)
end

function TooltipInfo.LineFor(unit)
    if not ns.db or not ns.db.settings.tooltipInfo or not unit or ns.Compat.IsSecret(unit) then return nil end
    local okP, isPlayer = ns.Compat.Try("UnitIsPlayer", unit)
    if not okP or plain(isPlayer) ~= true then return nil end
    local key = TooltipInfo.KeyOf(unit)
    if not key or key == ns.Store.key then return nil end
    local _, f, c = ns.FriendsModel.FindCharacter(ns.Data.Friends(), ns.db.blocklist, key)
    if not c then return nil end
    local today = ns.Store.Today()
    local sum = ns.Days.Sum(c.days or {}, ns.Days.RangeStart("week", today, time, date), today)
    return ns.FriendsModel.TooltipLine(f, sum, L)
end

local function onUnit(tooltip)
    local ok, err = pcall(function()
        if type(tooltip) ~= "table" or type(tooltip.GetUnit) ~= "function" then return end
        local _, unit = tooltip:GetUnit()
        local line = TooltipInfo.LineFor(unit)
        if line then
            tooltip:AddLine(line, 0.88, 0.70, 0.29) -- the light gold of the chat prefix
        end
    end)
    if not ok then ns.Log.Debug("tooltip line failed: %s", tostring(err)) end
end

function TooltipInfo.Start()
    if TooltipInfo.hook then return end
    local processor = _G.TooltipDataProcessor
    local unitType = type(_G.Enum) == "table" and type(_G.Enum.TooltipDataType) == "table" and _G.Enum.TooltipDataType.Unit
    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and unitType then
        local ok = pcall(processor.AddTooltipPostCall, unitType, onUnit)
        if ok then TooltipInfo.hook = "processor" return end
    end
    local tip = _G.GameTooltip
    if type(tip) == "table" and type(tip.HookScript) == "function" and type(tip.HasScript) == "function" then
        local okHas, has = pcall(tip.HasScript, tip, "OnTooltipSetUnit")
        if okHas and has and pcall(tip.HookScript, tip, "OnTooltipSetUnit", onUnit) then TooltipInfo.hook = "script" end
    end
end
