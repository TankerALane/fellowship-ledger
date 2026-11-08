-- Quest chain drop-downs (D-078): chain details, the shown window, and the lines
-- the Quest chains view draws. Pure logic; the in-game look is on Austin's checklist.
local H = ...
local ns = H.pureNamespace()
local Logic, M, L = ns.QuestChainLogic, ns.ChainModel, ns.L

-- A 7-quest chain: 1-2 done, 3 in the log; quest 5 also needs quest 99 (outside the chain).
local INFO = {
    [1] = { name = "One", level = 14, req = 9, start = { kind = "npc", name = "Gryan", zone = "Westfall" } },
    [2] = { name = "Two", level = 14, req = 9 },
    [3] = { name = "Three", level = 15, req = 10 },
    [4] = { name = "Four", level = 16, req = 12, start = { kind = "item", name = "Torn Scroll" } },
    [5] = { name = "Five", level = 18, req = 14, pre = { 4, 99 } },
    [6] = { name = "Six", level = 20, req = 18, start = { kind = "npc", name = "Traitor" } },
    [7] = { name = "Seven", level = 22, req = 18 },
    [99] = { name = "Red Silk Bandanas" },
}
local STATUS = { [1] = "done", [2] = "done", [3] = "log" }
local function details(anchor)
    return Logic.Details({ 1, 2, 3, 4, 5, 6, 7 }, function(id) return INFO[id] end, function(id) return STATUS[id] end, anchor)
end

local function textOf(lines)
    local out = {}
    for _, l in ipairs(lines) do
        local parts = {}
        for _, s in ipairs(l.segments or {}) do parts[#parts + 1] = s.button and ("[" .. s.button.label .. "]") or s.text end
        out[#out + 1] = l.text or table.concat(parts, " | ")
    end
    return table.concat(out, "\n")
end

H.test("chains: details mark done, in log, next, and outside prerequisites", function()
    local d = details(3)
    H.eq(d.current, 3); H.eq(d.next, 4)
    H.eq(d.quests[1].status, "done"); H.eq(d.quests[3].status, "log"); H.eq(d.quests[4].status, nil)
    H.eq(#d.also, 1); H.eq(d.also[1].name, "Red Silk Bandanas"); H.eq(d.also[1].done, false)
    -- Without an anchor (a friend's chain), the quest in your log is "current".
    H.eq(details(nil).current, 3)
end)

H.test("chains: two before and three after your step until Show all", function()
    H.eq(select(1, M.Window(7, 3, false)), 1); H.eq(select(2, M.Window(7, 3, false)), 6)
    H.eq(select(1, M.Window(12, 8, false)), 6); H.eq(select(2, M.Window(12, 8, false)), 11)
    H.eq(select(2, M.Window(7, 3, true)), 7)
    H.eq(select(2, M.Window(3, 1, false)), 3)
end)

H.test("chains: where a quest starts", function()
    H.eq(M.PlaceText(INFO[1].start, L), "Gryan, Westfall")
    H.eq(M.PlaceText(INFO[4].start, L), "item: Torn Scroll")
    H.eq(M.PlaceText(INFO[6].start, L), "Traitor")
    H.eq(M.PlaceText(nil, L), "?")
    H.eq(M.PlaceText({ kind = "npc", name = "Gryan", zone = "Westfall", x = 56.33, y = 47.6 }, L), "Gryan, Westfall (56.3, 47.6)")
    local title, tip = M.Tooltip(INFO[1], L)
    H.eq(title, "One"); H.eq(tip[1], "Starts: Gryan, Westfall"); H.eq(tip[2], "Turn in: ?")
    H.eq(tip[3], "Quest level 14, needs level 9")
end)

H.test("chains: an opened chain is a box with the quests, Show all, prerequisites and friends", function()
    local toggled, all
    local view = {
        mine = {
            { key = "q:1", name = "The Defias Brotherhood", step = 3, total = 7, zone = "Westfall", known = true, open = true,
                details = details(3), friendsOn = { { friend = "Bob", character = "Bob Ironbeard", step = 5 } } },
            { key = "q:50", name = "Closed", step = 1, total = 2, known = true },
            { known = false, title = "Kill On Sight" },
        },
        friends = {},
    }
    local lines = M.Lines(view, L, { playerLevel = 16, checkCode = "OK", logCode = "NOW",
        onToggle = function(k) toggled = k end, onShowAll = function(k) all = k end })
    local text = textOf(lines)
    H.ok(text:find("- | The Defias Brotherhood | step 3 of 7 | Westfall", 1, true), text)
    H.ok(text:find("+ | Closed | step 1 of 2", 1, true), text)
    H.ok(text:find("Kill On Sight | no chain information", 1, true), text)
    H.ok(text:find("OK | 1 | + One | 14 | 9 | Gryan, Westfall", 1, true), text)
    H.ok(text:find("NOW | 3 | + Three | 15 | 10 | in your quest log", 1, true), text)
    H.ok(text:find(" | 4 | + Four | 16 | 12 | item: Torn Scroll", 1, true), text)
    H.ok(not text:find("Seven", 1, true), "step 7 is past the window")
    H.ok(text:find("[Show all (7)]", 1, true), text)
    H.ok(text:find("Also requires: \"Red Silk Bandanas\" (not done)", 1, true), text)
    H.ok(text:find("Friends on this chain: Bob (Bob Ironbeard), step 5", 1, true), text)
    H.ok(text:find("None right now", 1, true), "no friend chains")

    -- Your step is shaded, too-high Req is red, the box is closed off, and clicks reach the callbacks.
    local shaded, red, box, showAllBtn = 0, false, {}, nil
    for _, l in ipairs(lines) do
        if l.shade then shaded = shaded + 1 end
        for _, s in ipairs(l.segments or {}) do
            if s.role == "bad" and s.text == "18" then red = true end
            if s.button then showAllBtn = s.button end
        end
        if l.box then box[#box + 1] = l.box end
    end
    H.eq(shaded, 1); H.ok(red, "Req 18 above level 16 is red")
    H.eq(box[1], "top"); H.eq(box[#box], "bottom")
    lines[2].onClick(); H.eq(toggled, "q:1")
    showAllBtn.onClick(); H.eq(all, "q:1")
    H.ok(lines[2].onClick ~= nil and lines[#lines].onClick == nil)
end)

H.test("chains: a friend's chain opens to the quest to pick up next", function()
    local d = Logic.Details({ 1, 2, 3, 4 }, function(id) return INFO[id] end, function(id) return id == 1 and "done" or nil end)
    local view = { mine = {}, emptyLog = true, friends = {
        { key = "q:1", name = "Defias", friend = "Bob", character = "Bob Ironbeard", step = 2, total = 4, zone = "Westfall",
            open = true, details = d, next = d.next } } }
    local text = textOf(M.Lines(view, L, { playerLevel = 16 }))
    H.ok(text:find("Your quest log is empty.", 1, true), text)
    H.ok(text:find("Defias | Bob (Bob Ironbeard), step 2 of 4 | Westfall", 1, true), text)
    H.ok(text:find("Pick up next: \"Two\" from ?, needs level 9", 1, true), text)
    -- Nothing known about the chain: say so instead of an empty box.
    view.friends[1].details = nil
    text = textOf(M.Lines(view, L, {}))
    H.ok(text:find("No details for this chain", 1, true), text)
end)

H.test("chains: friends on a chain, blocked friends left out", function()
    local friends = {
        a = { name = "Bob", characters = { x = { display = "Bob Ironbeard", chains = { ["q:1"] = { step = 5 } } } } },
        b = { name = "Ann", blocked = true, characters = { y = { display = "Ann", chains = { ["q:1"] = { step = 2 } } } } },
        c = { name = "Cy", characters = { z = { display = "Cy", chains = { ["q:9"] = { step = 1 } } } } },
    }
    local on = Logic.FriendsOn(friends, function(f) return f.blocked end, "q:1")
    H.eq(#on, 1); H.eq(on[1].friend, "Bob"); H.eq(on[1].step, 5)
end)

H.test("quest details: objective, rewards, items to choose, your turn-in", function()
    local q = { id = 3, name = "Three", level = 15, req = 10, status = "log",
        start = { kind = "npc", name = "Gryan", zone = "Westfall" } }
    local more = { objectives = string.rep("Kill the Defias ", 10), xp = 1250, money = 12345,
        rep = { { name = "Stormwind", value = 250 } }, seen = true,
        items = { { id = 1, name = "Sword", quality = 2, choice = true }, { id = 2, name = "Mace", choice = true },
            { id = 3, name = "Potion", count = 5 } },
        done = { at = 0, xp = 1250, money = 12345 } }
    local out = M.QuestMore(q, more, L, { skin = "ledger", dateFn = function() return "11-05 14:20" end })
    local text = {}
    for _, l in ipairs(out) do text[#text + 1] = l.text end
    text = table.concat(text, "\n")
    H.ok(text:find("Objective: Kill the Defias", 1, true), text)
    H.ok(#out[1].text <= M.WRAP and out[2].text:find("^   "), "long objectives wrap onto indented lines")
    H.ok(text:find("Starts: Gryan, Westfall    Turn in: ?", 1, true), text)
    H.ok(text:find("Rewards: 1,250 XP, 1g 23s 45c, +250 Stormwind", 1, true), text)
    H.ok(text:find("Choose one: \n    |c", 1, true) and text:find("Sword|r\n    Mace", 1, true), "green item colored, one per line: " .. text)
    H.ok(text:find("You also get: \n    Potion x5", 1, true), text)
    -- Each item line carries its id for the game's item tooltip (D-102).
    local ids = {}
    for _, l in ipairs(out) do if l.item then ids[#ids + 1] = l.item.id end end
    H.eq(table.concat(ids, ","), "1,2,3")
    local withIcon = M.QuestMore(q, { seen = true, items = { { id = 9, name = "Ring", icon = 1234, link = "|Hitem:9|h" } } }, L, {})
    local ring
    for _, l in ipairs(withIcon) do if l.item then ring = l end end
    H.ok(ring.text:find("|T1234:14:14:0:0|t Ring", 1, true), ring.text); H.eq(ring.item.link, "|Hitem:9|h")
    H.ok(text:find("You turned it in 11-05 14:20 and got 1,250 XP, 1g 23s 45c.", 1, true), text)
    -- Not seen yet; seen with no items; an old XP number from when you saw it.
    text = M.QuestMore(q, { xp = 300, xpLevel = 9 }, L, {})
    local last = text[#text].text
    H.eq(last, L.QUEST_ITEMS_UNSEEN)
    H.ok(text[#text - 1].text:find("300 XP (at level 9, when you saw it)", 1, true), text[#text - 1].text)
    text = M.QuestMore(q, { seen = true }, L, {})
    H.eq(text[#text].text, L.QUEST_ITEMS_NONE)
end)

H.test("quests in both logs: common IDs, friends on a quest, the chain line and details (D-106)", function()
    local FM = H.pureNamespace().FriendsModel
    H.eq(table.concat(FM.CommonQuests({ 5, 7, 9 }, { 9, 1, 5 }), ","), "5,9", "in my log's order")
    H.eq(#FM.CommonQuests(nil, { 1 }), 0)
    local friends = {
        ["bn:Ham#1"] = { name = "Hamlet", characters = { ["Ca-R"] = { display = "Cain", logQuests = { 3, 4 } },
            ["Al-R"] = { display = "Alastair", logQuests = { 3 } } } },
        ["bn:Blk#1"] = { name = "Blocked", tag = "Blk#1", characters = { ["X-R"] = { logQuests = { 3 } } } },
        ["bn:Old#1"] = { name = "Old", characters = { ["O-R"] = {} } },
    }
    local on = FM.OnQuest(friends, { ["Blk#1"] = true }, 3)
    H.eq(#on, 2); H.eq(on[1].character, "Alastair"); H.eq(on[2].friend, "Hamlet")
    H.eq(M.WithText(on, L), "with Hamlet +1"); H.eq(M.WithText({ on[1] }, L), "with Hamlet"); H.eq(M.WithText({}, L), nil)
    local view = { mine = { { key = "q:1", name = "Defias", step = 3, total = 7, known = true, anchor = 3, withFriends = on } }, friends = {} }
    local lines = M.Lines(view, L, {})
    H.ok(textOf(lines):find("3 of 7   with Hamlet +1", 1, true), textOf(lines))
    local title, tip = lines[2].tooltip()
    H.eq(title, L.CHAIN_WITH_TITLE); H.eq(tip[1], "Alastair (Hamlet)")
    -- Shift-click on the line links the quest instead of opening the chain.
    local linked, toggled
    lines = M.Lines(view, L, { onLink = function(id) linked = id return true end, onToggle = function() toggled = true end })
    lines[2].onClick()
    H.eq(linked, 3); H.eq(toggled, nil)
    local out = M.QuestMore({ id = 3, name = "Three" }, { seen = true, friends = on }, L, {})
    local found
    for _, l in ipairs(out) do if l.text:find("Also in the log of: Alastair (Hamlet), Cain (Hamlet)", 1, true) then found = l end end
    H.ok(found and found.role == "good")
end)

H.test("quest details: a click opens a quest inside its chain", function()
    local view = { mine = { { key = "q:1", name = "Defias", step = 3, total = 7, known = true, open = true, details = details(3) } },
        friends = {} }
    local clicked
    local opts = { playerLevel = 16, openQuest = { ["q:1|3"] = true },
        onQuest = function(k, id) clicked = k .. "|" .. id end,
        more = function(q2) return { seen = true, xp = q2.id * 100, items = { { id = 77, name = "Cloak", link = "L77" } } } end }
    local picked
    opts.onItem = function(item) picked = item.link end
    local lines = M.Lines(view, L, opts)
    local text = textOf(lines)
    H.ok(text:find("- Three", 1, true), text)
    H.ok(text:find("Rewards: 300 XP", 1, true), text)
    for _, l in ipairs(lines) do if l.item then H.eq(l.item.id, 77); l.onClick() end end
    H.eq(picked, "L77")
    for _, l in ipairs(lines) do
        for _, s in ipairs(l.segments or {}) do if s.text == "+ Four" then l.onClick() end end
    end
    H.eq(clicked, "q:1|4")
end)
