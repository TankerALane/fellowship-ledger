-- Trackers/Items.lua
-- Notable item drops: green (quality 2) or better, from YOUR loot window only.
-- When the loot window opens, the slots are read (GetNumLootItems, GetLootSlotInfo,
-- GetLootSlotLink); an item counts once its slot is actually taken
-- (LOOT_SLOT_CLEARED). Group need/greed rolls are not covered. ITEM_PUSH was no
-- use here: on retail it carries only a bag slot and an icon (D-020).
-- Status "unverified": the loot functions are on the /fl verify list.

local _, ns = ...
local T = ns.Trackers
local Store, Days, Character = ns.Store, ns.Days, ns.Character

local Items = T.Define({ id = "items" })

Items.NOTABLE = 2 -- uncommon (green) and better
Items.EPIC = 4
local pending = {} -- slot -> { link, name, quality, quantity }

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
            pending[slot] = { link = link, name = T.Plain(name), quality = quality, quantity = T.Plain(quantity) }
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
    if item then
        pending[slot] = nil
        record(item)
    end
end
Items.events.LOOT_CLOSED = function() pending = {} end
