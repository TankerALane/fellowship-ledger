-- Trackers/QuestRewards.lua
-- What a quest gives (D-100), for the quest details in Quest chains. Item rewards
-- are only known once the game has shown them, so they are remembered account-wide
-- in db.questRewards[questID] = { money, xp, xpLevel, items = { { id, n, q, choice } }, at, from }:
--   * at a quest giver (QUEST_DETAIL) and at turn-in (QUEST_COMPLETE), from the quest
--     dialog: GetQuestID, GetNumQuestRewards / GetNumQuestChoices, GetQuestItemInfo,
--     GetQuestItemLink, GetRewardMoney, GetRewardXP;
--   * for quests in your log, on every log scan: GetNumQuestLogRewards(questID),
--     GetQuestLogRewardInfo(i, questID), GetNumQuestLogChoices(questID),
--     GetQuestLogChoiceInfo(i, questID), GetQuestLogRewardMoney(questID), GetQuestLogRewardXP(questID).
-- These signatures come from QuestieTrace's notes on WoW Forever and Questie's own
-- calls; none is confirmed by /fl verify yet (x:quest.rewards), so every call is
-- guarded and a missing one only leaves the rewards blank.
-- XP for quests not in your log comes from Questie's QuestXP module when it is loaded
-- (QuestXP:GetQuestLogRewardXP(questID), XP at your level); Questie has no item rewards.

local _, ns = ...
local T = ns.Trackers

local QuestRewards = {}
ns.QuestRewards = QuestRewards
QuestRewards.MAX_KEPT = 3000
QuestRewards.lastDialog = nil -- for /fl verify: what the last quest dialog gave

local function plain(v) return T.Plain(v) end

local function db()
    if not ns.db then return nil end
    ns.db.questRewards = ns.db.questRewards or {}
    return ns.db.questRewards
end

local function itemIdOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- One reward item from a GetQuestItemInfo / GetQuestLogRewardInfo style result.
local function item(itemID, count, quality, choice, link)
    local id = plain(itemID)
    if type(id) ~= "number" then id = itemIdOf(plain(link)) end
    if type(id) ~= "number" then return nil end
    count, quality = plain(count), plain(quality)
    return { id = id, n = type(count) == "number" and count > 1 and count or nil,
        q = type(quality) == "number" and quality or nil, choice = choice or nil }
end

local function store(questID, entry)
    local list = db()
    if not list or type(questID) ~= "number" or questID <= 0 then return end
    local old = list[questID]
    -- An empty read (the game had not loaded the quest yet) never wipes what we know.
    if old and #entry.items == 0 and not entry.money and #(old.items or {}) > 0 then
        entry.items, entry.money = old.items, entry.money or old.money
    end
    list[questID] = entry
end

-- The quest dialog (giver or turn-in).
function QuestRewards.FromDialog()
    local okID, questID = ns.Compat.Try("GetQuestID")
    questID = okID and plain(questID) or nil
    if type(questID) ~= "number" or questID <= 0 then return end
    local items = {}
    for _, kind in ipairs({ "reward", "choice" }) do
        local okN, n = ns.Compat.Try(kind == "reward" and "GetNumQuestRewards" or "GetNumQuestChoices")
        n = okN and plain(n) or 0
        for i = 1, type(n) == "number" and math.min(n, 10) or 0 do
            local ok, _, _, count, quality, _, itemID = ns.Compat.Try("GetQuestItemInfo", kind, i)
            local okL, link = ns.Compat.Try("GetQuestItemLink", kind, i)
            local it = ok and item(itemID, count, quality, kind == "choice", okL and link or nil)
            if it then items[#items + 1] = it end
        end
    end
    local okM, money = ns.Compat.Try("GetRewardMoney")
    local okX, xp = ns.Compat.Try("GetRewardXP")
    money, xp = okM and plain(money) or nil, okX and plain(xp) or nil
    local entry = { items = items, money = type(money) == "number" and money > 0 and money or nil,
        xp = type(xp) == "number" and xp > 0 and xp or nil, xpLevel = ns.Store.char and ns.Store.char.level,
        at = time(), from = "dialog" }
    QuestRewards.lastDialog = { id = questID, items = #items, money = entry.money, xp = entry.xp }
    store(questID, entry)
end

-- A quest in the log, by quest ID.
function QuestRewards.FromLog(questID)
    if type(questID) ~= "number" then return end
    local items = {}
    local okN, n = ns.Compat.Try("GetNumQuestLogRewards", questID)
    n = okN and plain(n) or 0
    for i = 1, type(n) == "number" and math.min(n, 10) or 0 do
        local ok, _, _, count, quality, _, itemID = ns.Compat.Try("GetQuestLogRewardInfo", i, questID)
        local it = ok and item(itemID, count, quality, false)
        if it then items[#items + 1] = it end
    end
    local okC, c = ns.Compat.Try("GetNumQuestLogChoices", questID)
    c = okC and plain(c) or 0
    for i = 1, type(c) == "number" and math.min(c, 10) or 0 do
        local ok, _, _, count, quality, _, itemID = ns.Compat.Try("GetQuestLogChoiceInfo", i, questID)
        local it = ok and item(itemID, count, quality, true)
        if it then items[#items + 1] = it end
    end
    local okM, money = ns.Compat.Try("GetQuestLogRewardMoney", questID)
    local okX, xp = ns.Compat.Try("GetQuestLogRewardXP", questID)
    money, xp = okM and plain(money) or nil, okX and plain(xp) or nil
    local old = (db() or {})[questID]
    -- The dialog saw the full reward; the log only adds what is missing.
    if old and old.from == "dialog" and #(old.items or {}) > 0 then
        if type(xp) == "number" and xp > 0 then old.xp, old.xpLevel = xp, ns.Store.char and ns.Store.char.level end
        return
    end
    store(questID, { items = items, money = type(money) == "number" and money > 0 and money or nil,
        xp = type(xp) == "number" and xp > 0 and xp or nil, xpLevel = ns.Store.char and ns.Store.char.level,
        at = time(), from = "log" })
end

-- Keep the list bounded: drop the oldest when it grows past MAX_KEPT.
function QuestRewards.Prune()
    local list = db()
    if not list then return end
    local ids = {}
    for id, e in pairs(list) do ids[#ids + 1] = { id = id, at = type(e) == "table" and e.at or 0 } end
    if #ids <= QuestRewards.MAX_KEPT then return end
    table.sort(ids, function(a, b) return a.at < b.at end)
    for i = 1, #ids - QuestRewards.MAX_KEPT do list[ids[i].id] = nil end
end

-- XP at your level from Questie's QuestXP module (guarded like the rest of Questie).
local questXP
function QuestRewards.QuestieXP(questID)
    if not ns.QuestChains or ns.QuestChains.QuestieState() ~= "ready" then return nil end
    if questXP == nil then
        local ok, mod = pcall(function() return _G.QuestieLoader:ImportModule("QuestXP") end)
        questXP = ok and type(mod) == "table" and type(mod.GetQuestLogRewardXP) == "function" and mod or false
    end
    if not questXP then return nil end
    local ok, xp = pcall(questXP.GetQuestLogRewardXP, questXP, questID, false)
    return ok and type(xp) == "number" and xp > 0 and xp or nil
end

-- Item name and quality for display; nil name until the game has the item cached.
function QuestRewards.ItemInfo(id)
    -- C_Item.GetItemInfo: name, link, quality, ..., the icon is the 10th value.
    local ok, name, link, quality, _, _, _, _, _, _, icon = ns.Compat.Try("C_Item.GetItemInfo", id)
    name, quality = ok and plain(name) or nil, ok and plain(quality) or nil
    if type(name) ~= "string" then
        ns.Compat.Try("C_Item.RequestLoadItemDataByID", id)
        return nil
    end
    link, icon = plain(link), plain(icon)
    return name, quality, type(link) == "string" and link or nil, (type(icon) == "number" or type(icon) == "string") and icon or nil
end

-- Everything the quest details show about one quest (see ChainModel.QuestMore).
-- inLog: the quest is in your log; turnedIn: your turn-in log entry, if any.
function QuestRewards.More(questID, inLog, turnedIn)
    if inLog then pcall(QuestRewards.FromLog, questID) end
    local seen = (db() or {})[questID]
    local more = { items = {}, objectives = nil, rep = {} }
    local info = ns.QuestChains and ns.QuestChains.QuestInfo(questID) or {}
    more.objectives = info.objectives
    for _, r in ipairs(info.rep or {}) do more.rep[#more.rep + 1] = r end
    -- XP: the game's number for a quest in the log, else Questie's estimate at your
    -- level, else what the game said when you last saw it (at that level).
    if inLog and seen and seen.xp then more.xp = seen.xp
    else
        more.xp = QuestRewards.QuestieXP(questID)
        if not more.xp and seen and seen.xp then more.xp, more.xpLevel = seen.xp, seen.xpLevel end
    end
    if seen then
        more.money = seen.money
        more.seen = true
        for _, it in ipairs(seen.items or {}) do
            local name, quality, link, icon = QuestRewards.ItemInfo(it.id)
            more.items[#more.items + 1] = { id = it.id, name = name, quality = quality or it.q, count = it.n, choice = it.choice,
                link = link, icon = icon }
        end
    end
    if turnedIn then more.done = { at = turnedIn.at, xp = turnedIn.xp, money = turnedIn.money } end
    return more
end

function QuestRewards.Start()
    ns.Events.On("QUEST_DETAIL", "questRewards", function() pcall(QuestRewards.FromDialog) end)
    ns.Events.On("QUEST_COMPLETE", "questRewards", function() pcall(QuestRewards.FromDialog) end)
    pcall(QuestRewards.Prune)
end
