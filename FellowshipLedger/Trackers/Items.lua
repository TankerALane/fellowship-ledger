-- Trackers/Items.lua
-- Notable item drops: green (quality 2) or better, from YOUR loot window only.
-- When the loot window opens, the slots are read (GetNumLootItems, GetLootSlotInfo,
-- GetLootSlotLink); an item counts once its slot is actually taken
-- (LOOT_SLOT_CLEARED). Group need/greed rolls are not covered. ITEM_PUSH was no
-- use here: on retail it carries only a bag slot and an icon (D-020).
-- In a group, a slot also clears when someone ELSE takes the item or wins its roll, so
-- an item counts only once it is really in your bags: its bag count (GetItemCount)
-- went up a moment after the slot cleared (D-125; a friend once got the notice for
-- an item Austin looted). Without a bag count, only solo loot counts.
-- Status "unverified": the loot functions are on the /fl verify list.

local _, ns = ...
local T = ns.Trackers
local Store, Days, Character = ns.Store, ns.Days, ns.Character

local Items = T.Define({ id = "items" })

Items.NOTABLE = 2 -- uncommon (green) and better
Items.EPIC = 4
local pending = {} -- slot -> { link, name, quality, quantity, id, before }
Items.CHECKS = { 1, 3 } -- seconds after the slot cleared to look in the bags

-- How many of this item are in your bags, or nil when the game cannot say.
function Items.BagCount(id)
    if not id then return nil end
    for _, path in ipairs({ "C_Item.GetItemCount", "GetItemCount" }) do
        if ns.Compat.Has(path) then
            local ok, n = ns.Compat.Try(path, id)
            n = ok and T.Plain(n) or nil
            if type(n) == "number" then return n end
        end
    end
    return nil
end

local function inGroup()
    local ok, g = ns.Compat.Try("IsInGroup")
    return ok and T.Plain(g) == true
end

local function scan()
    pending = {}
    local ok, n = ns.Compat.Call("items", "GetNumLootItems")
    for slot = 1, ok and (T.Plain(n) or 0) or 0 do
        -- GetLootSlotInfo: texture, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive
        local okInfo, _, name, quantity, currencyID, quality = ns.Compat.Call("items", "GetLootSlotInfo", slot)
        local okLink, link = ns.Compat.Call("items", "GetLootSlotLink", slot)
        link, quality = okLink and T.Plain(link) or nil, okInfo and T.Plain(quality) or nil
        if link and type(quality) ~= "number" then
            local okQ, q = ns.Compat.Call("items", "C_Item.GetItemQualityByID", link)
            quality = okQ and T.Plain(q) or nil
        end
        if okInfo and link and not T.Plain(currencyID) and type(quality) == "number" and quality >= Items.NOTABLE then
            local id = tonumber(link:match("item:(%d+)"))
            pending[slot] = { link = link, name = T.Plain(name), quality = quality, quantity = T.Plain(quantity),
                id = id, before = Items.BagCount(id) }
        end
    end
end

local function record(item)
    local char = Store.char
    local zone = Store.Zone()
    char.items[#char.items + 1] = { at = Store.Now(), link = item.link, name = item.name, quality = item.quality,
        quantity = item.quantity, zone = zone }
    Days.PruneList(char.items, "at", Store.Now(), Character.LIST_KEEP_SECONDS)
    Store.Count("itemsNotable")
    if item.quality >= Items.EPIC then Store.Count("itemsEpic") end
end

Items.events.LOOT_READY = scan
Items.events.LOOT_OPENED = scan
Items.events.LOOT_SLOT_CLEARED = function(_, slot)
    slot = T.Plain(slot)
    local item = slot and pending[slot]
    if not item then return end
    pending[slot] = nil
    if item.before == nil then
        -- No bag count: only when nobody else could have taken it.
        if not inGroup() then record(item) end
        return
    end
    local done = false
    for _, wait in ipairs(Items.CHECKS) do
        ns.Events.After(wait, function()
            if done then return end
            local now = Items.BagCount(item.id)
            if now and now > item.before then
                done = true
                record(item)
            end
        end)
    end
end
Items.events.LOOT_CLOSED = function() pending = {} end
