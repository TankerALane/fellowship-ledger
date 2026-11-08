-- UI/ChainModel.lua
-- PURE: no WoW globals. The Quest chains view on the Me tab as table lines
-- (the "grid" lines UI/Table.lua draws, see UI/DetailModel.lua): your chains,
-- each opening to its quests (done, in your log, still to do) with level,
-- required level and where each quest starts, then the chains friends are on
-- that you have not started, each opening to "pick up next". D-078.
--
-- A chain's details (built by Trackers/QuestChains.lua):
--   { quests = { { id, name, level, req, start = place, finish = place, status = "done"|"log"|nil } },
--     current = index of the quest you are on (nil for a friend's chain),
--     also = { { name, done } } (prerequisites outside the chain) }
-- place = { kind = "npc"|"object"|"item", name, zone, x, y (map percent) } or nil.

local _, ns = ...

local ChainModel = {}
ns.ChainModel = ChainModel

ChainModel.INSET = 18
ChainModel.BEFORE, ChainModel.AFTER = 2, 3 -- quests shown around your step until "Show all"

-- Column positions (fractions of the line after the inset).
ChainModel.COLS = {
    mark = { .00, .04 }, num = { .04, .05 }, quest = { .09, .33 }, lvl = { .43, .06 }, req = { .49, .06 }, starts = { .56, .44 },
}
-- The chain's own line: name, step, zone.
ChainModel.HEAD = { sign = { .00, .03 }, name = { .03, .52 }, step = { .56, .20 }, zone = { .77, .23 } }
-- A friend's chain: the name, then who is on it and at which step.
ChainModel.FRIEND_HEAD = { sign = { .00, .03 }, name = { .03, .37 }, step = { .41, .35 }, zone = { .77, .23 } }

local function seg(pos, text, role, font, align)
    return { x = pos[1], w = pos[2], text = text or "", role = role or "text", font = font or "body", align = align }
end

-- Which quests to show: around `focus` (2 before, 3 after) unless showAll.
function ChainModel.Window(n, focus, showAll)
    if showAll or not focus or n == 0 then return 1, n end
    return math.max(1, focus - ChainModel.BEFORE), math.min(n, focus + ChainModel.AFTER)
end

function ChainModel.PlaceText(place, L)
    if type(place) ~= "table" or not place.name then return L.CHAIN_START_UNKNOWN_SHORT end
    if place.kind == "item" then return string.format(L.CHAIN_FROM_ITEM, place.name) end
    local text = place.zone and string.format(L.CHAIN_PLACE, place.name, place.zone) or place.name
    if type(place.x) == "number" and type(place.y) == "number" then text = text .. string.format(L.CHAIN_COORDS, place.x, place.y) end
    return text
end

local function levelText(v)
    if type(v) ~= "number" or v <= 0 then return "" end
    return tostring(v)
end

-- Tooltip for one quest: name, then start, turn-in and levels.
function ChainModel.Tooltip(q, L)
    local lines = { string.format(L.CHAIN_TIP_STARTS, ChainModel.PlaceText(q.start, L)),
        string.format(L.CHAIN_TIP_ENDS, ChainModel.PlaceText(q.finish, L)) }
    if levelText(q.level) ~= "" or levelText(q.req) ~= "" then
        lines[#lines + 1] = string.format(L.CHAIN_TIP_LEVEL, levelText(q.level) ~= "" and levelText(q.level) or "?",
            levelText(q.req) ~= "" and levelText(q.req) or "?")
    end
    return q.name or "?", lines
end

-- Quest details (D-100) -------------------------------------------------------------
ChainModel.WRAP = 100 -- characters per detail line

local function visibleLen(s)
    return #(s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Pack pieces (words, or item names) into lines of at most `max` visible characters.
-- The first line starts with `lead`; pieces are joined with `sep`.
function ChainModel.Wrap(pieces, max, sep, lead)
    local lines, cur = {}, lead or ""
    local started = false
    for _, p in ipairs(pieces) do
        local add = started and (sep .. p) or p
        if started and visibleLen(cur .. add) > max then
            lines[#lines + 1] = cur .. (sep:match("^,") and "," or "")
            cur, add = "   ", p
        end
        cur = cur .. add
        started = true
    end
    if started or cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

local function words(text)
    local out = {}
    for w in tostring(text):gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function itemText(it, L, skin)
    local name = it.name or string.format(L.QUEST_ITEM_UNKNOWN, it.id or 0)
    if it.count then name = string.format(L.QUEST_ITEM_COUNT, name, it.count) end
    local color = skin and ns.Palette and ns.Palette.QualityColor(it.quality, skin)
    local icon = it.icon and ("|T" .. tostring(it.icon) .. ":14:14:0:0|t ") or ""
    return icon .. (color and (ns.Palette.Code(color) .. name .. "|r") or name)
end

-- The text lines of one opened quest. q: the chain's quest (name, level, req, start,
-- finish, status); more: { objectives, xp, xpLevel, money, items = { id, name, quality,
-- count, choice }, seen, rep = { name, value }, done = { at, xp, money } }.
function ChainModel.QuestMore(q, more, L, opts)
    opts = opts or {}
    more = more or {}
    local F = ns.Format
    local out = {}
    local function add(text, role, item)
        out[#out + 1] = { text = text, role = role or "text", item = item }
    end
    if more.objectives then
        for _, l in ipairs(ChainModel.Wrap(words(more.objectives), ChainModel.WRAP, " ", L.QUEST_OBJECTIVE)) do add(l, "muted") end
    end
    add(string.format(L.CHAIN_TIP_STARTS, ChainModel.PlaceText(q.start, L)) .. "    "
        .. string.format(L.CHAIN_TIP_ENDS, ChainModel.PlaceText(q.finish, L)))
    if levelText(q.level) ~= "" or levelText(q.req) ~= "" then
        add(string.format(L.CHAIN_TIP_LEVEL, levelText(q.level) ~= "" and levelText(q.level) or "?",
            levelText(q.req) ~= "" and levelText(q.req) or "?"), "muted")
    end
    local gives = {}
    if more.xp then
        gives[#gives + 1] = string.format(more.xpLevel and L.QUEST_XP_AT or L.QUEST_XP, F.Number(more.xp), more.xpLevel)
    end
    if more.money then gives[#gives + 1] = F.Money(more.money) end
    for _, r in ipairs(more.rep or {}) do
        gives[#gives + 1] = string.format(L.QUEST_REP, r.value >= 0 and "+" or "", r.value, r.name or L.QUEST_REP_UNKNOWN)
    end
    if #gives > 0 then add(L.QUEST_REWARDS .. table.concat(gives, ", ")) end
    -- One line per item (D-102), so hovering it shows the game's own item tooltip.
    local choose, also = {}, {}
    for _, it in ipairs(more.items or {}) do
        local list = it.choice and choose or also
        list[#list + 1] = it
    end
    local function items(list, head)
        add(head)
        for _, it in ipairs(list) do
            add("    " .. itemText(it, L, opts.skin), "text", { id = it.id, link = it.link })
        end
    end
    if #choose > 0 then items(choose, L.QUEST_CHOOSE) end
    if #also > 0 then items(also, #choose > 0 and L.QUEST_ALSO or L.QUEST_ITEMS) end
    if not more.seen then add(L.QUEST_ITEMS_UNSEEN, "muted")
    elseif #choose == 0 and #also == 0 then add(L.QUEST_ITEMS_NONE, "muted") end
    if more.done then
        local got = {}
        if (more.done.xp or 0) > 0 then got[#got + 1] = string.format(L.QUEST_XP, F.Number(more.done.xp)) end
        if (more.done.money or 0) > 0 then got[#got + 1] = F.Money(more.done.money) end
        local when = opts.dateFn and more.done.at and opts.dateFn("%m-%d %H:%M", more.done.at) or "?"
        add(#got > 0 and string.format(L.QUEST_DONE_GOT, when, table.concat(got, ", ")) or string.format(L.QUEST_DONE_AT, when), "muted")
    end
    return out
end

-- The box under an opened chain. c: the chain view entry; returns a list of lines.
local function body(c, L, opts)
    local C = ChainModel.COLS
    local d = c.details
    local lines = {}
    local function add(segs, extra)
        local line = { kind = "grid", inset = ChainModel.INSET, segments = segs }
        for k, v in pairs(extra or {}) do line[k] = v end
        lines[#lines + 1] = line
        return line
    end
    if not d or #(d.quests or {}) == 0 then
        add({ seg({ 0, 1 }, L.CHAIN_NO_DETAILS, "muted") })
    else
        local qs = d.quests
        if c.friendChain then
            local q = c.next and qs[c.next]
            if q then
                local text = string.format(L.CHAIN_PICK_UP, q.name or "?", ChainModel.PlaceText(q.start, L))
                local need = levelText(q.req)
                if need ~= "" then text = text .. string.format(L.CHAIN_PICK_UP_LEVEL, need) end
                add({ seg({ 0, 1 }, text, (type(q.req) == "number" and opts.playerLevel and q.req > opts.playerLevel) and "bad" or "text") })
            else
                add({ seg({ 0, 1 }, L.CHAIN_ALL_DONE, "muted") })
            end
        end
        add({ seg(C.mark, ""), seg(C.num, "#", "muted", "small"), seg(C.quest, L.CHAIN_COL_QUEST, "muted", "small"),
            seg(C.lvl, L.CHAIN_COL_LVL, "muted", "small", "CENTER"), seg(C.req, L.CHAIN_COL_REQ, "muted", "small", "CENTER"),
            seg(C.starts, L.CHAIN_COL_STARTS, "muted", "small") }, { rules = { { 0, 1 } } })
        local focus = d.current or c.next
        local from, to = ChainModel.Window(#qs, focus, c.showAll)
        for i = from, to do
            local q = qs[i]
            local mark = q.status == "done" and (opts.checkCode or "+") or q.status == "log" and (opts.logCode or ">") or ""
            local tooHigh = q.status ~= "done" and q.status ~= "log" and type(q.req) == "number" and opts.playerLevel and q.req > opts.playerLevel
            local starts = q.status == "log" and L.CHAIN_IN_LOG or ChainModel.PlaceText(q.start, L)
            local openKey = tostring(c.key) .. "|" .. tostring(q.id)
            local isOpen = opts.openQuest and opts.openQuest[openKey]
            add({ seg(C.mark, mark), seg(C.num, tostring(i), "muted"),
                seg(C.quest, (isOpen and "- " or "+ ") .. (q.name or ("#" .. tostring(q.id)))),
                seg(C.lvl, levelText(q.level), "text", nil, "CENTER"), seg(C.req, levelText(q.req), tooHigh and "bad" or "text", nil, "CENTER"),
                seg(C.starts, starts, q.status == "log" and "muted" or "text") },
                { shade = (i == focus) or nil, tooltip = function() return ChainModel.Tooltip(q, L) end,
                  onClick = function() opts.onQuest(c.key, q.id) end })
            if isOpen then
                local more = opts.more and opts.more(q) or nil
                for _, l in ipairs(ChainModel.QuestMore(q, more, L, opts)) do
                    local extra = nil
                    if l.item then
                        local item = l.item
                        extra = { item = item, onClick = function() if opts.onItem then opts.onItem(item) end end }
                    end
                    add({ seg({ C.quest[1], 1 - C.quest[1] }, l.text, l.role) }, extra)
                end
            end
        end
        if from > 1 or to < #qs or c.showAll then
            local label = c.showAll and L.DETAIL_SHOW_LESS or string.format(L.DETAIL_SHOW_ALL, #qs)
            add({ { x = 0, w = 1, text = "", button = { label = label, onClick = function() opts.onShowAll(c.key) end } } })
        end
        if #(d.also or {}) > 0 then
            local parts = {}
            for _, a in ipairs(d.also) do
                parts[#parts + 1] = string.format(L.CHAIN_ALSO_ITEM, a.name or "?", a.done and L.CHAIN_ALSO_DONE or L.CHAIN_ALSO_NOT)
            end
            add({ seg({ 0, 1 }, string.format(L.CHAIN_ALSO, table.concat(parts, ", ")), "muted") })
        end
    end
    if #(c.friendsOn or {}) > 0 then
        local parts = {}
        for _, f in ipairs(c.friendsOn) do parts[#parts + 1] = string.format(L.CHAIN_FRIEND_STEP, f.friend, f.character, f.step or 0) end
        add({ seg({ 0, 1 }, string.format(L.CHAIN_FRIENDS_ON, table.concat(parts, ", ")), "muted") })
    end
    if #lines == 1 then lines[1].box = "single" else
        lines[1].box = "top"
        for i = 2, #lines - 1 do lines[i].box = "mid" end
        lines[#lines].box = "bottom"
    end
    lines[#lines + 1] = { kind = "grid", segments = {}, height = 8 }
    return lines
end

local function head(c, L, opts, stepText, H)
    return { kind = "grid", inset = 0, onClick = function() opts.onToggle(c.key) end, segments = {
        seg(H.sign, c.open and "-" or "+", "muted"), seg(H.name, c.name or L.CHAIN_UNNAMED),
        seg(H.step, stepText), seg(H.zone, c.zone or "", "muted") } }
end

-- view: { mine = { entry }, friends = { entry }, emptyLog = bool, questieMissing = bool }
-- mine entry: { key, name, step, total, zone, known, title, open, showAll, details, friendsOn }
-- friend entry: { key, name, friend, character, step, total, zone, open, showAll, details, next }
-- opts: { playerLevel, onToggle(key), onShowAll(key), checkCode, logCode, skin, dateFn,
--         openQuest = { ["<chain key>|<quest id>"] = true }, onQuest(key, questID), more(q) -> details }
function ChainModel.Lines(view, L, opts)
    opts.onToggle = opts.onToggle or function() end
    opts.onShowAll = opts.onShowAll or function() end
    opts.onQuest = opts.onQuest or function() end
    local lines = { { kind = "group", text = L.CHAIN_MINE_TITLE } }
    if view.emptyLog then lines[#lines + 1] = { kind = "detail", text = L.CHAIN_EMPTY_LOG } end
    for _, c in ipairs(view.mine or {}) do
        if c.known then
            lines[#lines + 1] = head(c, L, opts, string.format(L.CHAIN_STEP_OF, c.step or 0, c.total or 0), ChainModel.HEAD)
            if c.open then for _, l in ipairs(body(c, L, opts)) do lines[#lines + 1] = l end end
        else
            local H = ChainModel.HEAD
            lines[#lines + 1] = { kind = "grid", inset = 0, segments = { seg(H.name, c.title or "?", "muted"),
                seg({ H.step[1], 1 - H.step[1] }, L.CHAIN_NO_INFO, "muted") } }
        end
    end
    if view.questieMissing then lines[#lines + 1] = { kind = "detail", text = L.CHAIN_QUESTIE_HINT } end

    lines[#lines + 1] = { kind = "grid", segments = {} }
    lines[#lines + 1] = { kind = "group", text = L.CHAIN_FRIENDS_TITLE }
    for _, c in ipairs(view.friends or {}) do
        c.friendChain = true
        lines[#lines + 1] = head(c, L, opts, string.format(L.CHAIN_WHO, c.friend or "?", c.character or "?", c.step or 0, c.total or 0),
            ChainModel.FRIEND_HEAD)
        if c.open then for _, l in ipairs(body(c, L, opts)) do lines[#lines + 1] = l end end
    end
    if #(view.friends or {}) == 0 then lines[#lines + 1] = { kind = "detail", indent = true, text = L.CHAIN_FRIENDS_NONE } end
    lines[#lines + 1] = { kind = "grid", segments = {} }
    lines[#lines + 1] = { kind = "detail", text = L.CHAIN_LEGEND }
    return lines
end
