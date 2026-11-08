-- Core/Notices.lua
-- PURE: no WoW globals. Friend notices (D-099): the text of each one, which of them
-- the settings let through, and how several that arrive together become one notice.
--
-- An item is { event = <Merge event>, friendName, friendId }. Events carry `kind`
-- ("level" | "maxlevel" | "levels" | "chain" | "dungeon" | "profession" | "joined" | "loot"),
-- `character` (shown name) and `key` (character key), plus the kind's own fields.
-- "levels" (a friend went from level a to b) is only shown in the "While you were
-- away" notice; on its own it would repeat every level a friend gains.

local _, ns = ...

local Notices = {}
ns.Notices = Notices

Notices.BUNDLE_SECONDS = 4      -- wait this long after the last notice for more to join it
Notices.BUNDLE_MAX_SECONDS = 20 -- but never hold the first one longer than this
Notices.AWAY_SECONDS = 120      -- notices in the first two minutes after login are "while you were away"
Notices.MAX_LINES = 5

-- The setting that turns each kind on or off.
Notices.SETTING = { level = "friendToasts", maxlevel = "friendToastsMaxLevel", chain = "friendToastsChains",
    dungeon = "friendToastsDungeons", profession = "friendToastsProfessions", joined = "friendToastsJoined",
    levels = "awayDigest", loot = "friendToastsLoot" }

-- The view of the friend's character that a click opens.
Notices.VIEW = { level = "overview", maxlevel = "overview", levels = "overview", chain = "quests",
    dungeon = "dungeons", profession = "professions", loot = "overview" }

function Notices.Text(e, friendName, L)
    local who, char = friendName or "?", e.character or "?"
    if e.kind == "maxlevel" then return string.format(L.FRIEND_MILESTONE_MAX, char, who, e.level or 0) end
    if e.kind == "chain" then return string.format(L.FRIEND_MILESTONE_CHAIN, char, who, e.chain or "?") end
    if e.kind == "dungeon" then return string.format(L.FRIEND_MILESTONE_DUNGEON, char, who, e.dungeon or "?") end
    if e.kind == "profession" then return string.format(L.FRIEND_MILESTONE_PROF, char, who, e.rank or 0, e.profession or "?") end
    if e.kind == "levels" then return string.format(L.FRIEND_LEVELS, char, who, e.from or 0, e.to or 0) end
    if e.kind == "joined" then return string.format(L.FRIEND_JOINED, who) end
    -- itemText: the item's link or colored name, filled in when the notice is shown (D-105).
    if e.kind == "loot" then
        local item = e.itemText or string.format(L.QUEST_ITEM_UNKNOWN, e.itemID or 0)
        if (e.count or 1) > 1 then item = string.format(L.QUEST_ITEM_COUNT, item, e.count) end
        return string.format(L.FRIEND_LOOT, char, who, item)
    end
    return string.format(L.FRIEND_MILESTONE, char, who, e.level or 0)
end

-- The items the settings let through, sorted by friend (stable within a friend).
-- away: the "While you were away" notice, which also shows level gains; there a
-- character's every-10 level line is left out, since its "went from" line covers it.
function Notices.Select(items, settings, away)
    settings = settings or {}
    local gained = {}
    away = away and settings.awayDigest ~= false
    if away then
        for _, it in ipairs(items or {}) do
            if it.event and it.event.kind == "levels" then gained[tostring(it.friendId) .. "|" .. tostring(it.event.key)] = true end
        end
    end
    local out = {}
    for i, it in ipairs(items or {}) do
        local e = it.event or {}
        local on = settings[Notices.SETTING[e.kind] or "friendToasts"] ~= false
        if e.kind == "levels" then on = away and on
        elseif e.kind == "level" and gained[tostring(it.friendId) .. "|" .. tostring(e.key)] then on = false end
        if on then out[#out + 1] = { item = it, order = i } end
    end
    table.sort(out, function(a, b)
        local fa, fb = tostring(a.item.friendName or ""):lower(), tostring(b.item.friendName or ""):lower()
        if fa ~= fb then return fa < fb end
        return a.order < b.order
    end)
    for i, o in ipairs(out) do out[i] = o.item end
    return out
end

-- Where a click on the notice goes: one character's view, one friend, or the Friends tab.
function Notices.Target(items)
    local first = items[1]
    if not first then return { tab = "friends" } end
    local sameFriend, sameChar, view = true, true, Notices.VIEW[first.event and first.event.kind]
    for _, it in ipairs(items) do
        if it.friendId ~= first.friendId then sameFriend = false end
        if not it.event or not first.event or it.event.key ~= first.event.key then sameChar = false end
        if Notices.VIEW[it.event and it.event.kind] ~= view then view = "overview" end
    end
    if sameFriend and sameChar and first.event and first.event.key then
        return { tab = "friends", friendId = first.friendId, key = first.event.key, view = view }
    end
    if sameFriend then return { tab = "friends", friendId = first.friendId } end
    return { tab = "friends" }
end

-- One notice for the selected items: title, lines, click target. nil if none.
function Notices.Build(items, L, away)
    local n = #(items or {})
    if n == 0 then return nil end
    local title
    if away then title = L.AWAY_TITLE
    elseif n == 1 then title = items[1].event and items[1].event.kind == "joined" and L.FRIEND_JOINED_TITLE or L.FRIEND_MILESTONE_TITLE
    else title = string.format(L.FRIEND_BUNDLE_TITLE, n) end
    local lines = {}
    local shown = n > Notices.MAX_LINES and Notices.MAX_LINES - 1 or n
    for i = 1, shown do lines[i] = Notices.Text(items[i].event or {}, items[i].friendName, L) end
    if shown < n then lines[#lines + 1] = string.format(L.FRIEND_BUNDLE_MORE, n - shown) end
    return title, lines, Notices.Target(items)
end

-- Is a notice queued at `at` part of the "While you were away" notice?
function Notices.IsAway(settings, startedAt, at)
    if not settings or settings.awayDigest == false or not startedAt or not at then return false end
    return at - startedAt <= Notices.AWAY_SECONDS
end
