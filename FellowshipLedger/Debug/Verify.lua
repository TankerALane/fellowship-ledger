-- Debug/Verify.lua
-- /fl verify: runs every check in Debug/VerifyChecks.lua, builds the report with
-- Debug/VerifyReport.lua, stores it in FellowshipLedgerDB.verify and shows it in
-- a copy window. Each check is wrapped so one bad API can never break the rest.
--
-- Privacy: reports are meant to be pasted to a developer, so custom checks print
-- field NAMES and counts only - never friend names, BattleTags or chat text.

local _, ns = ...
local L = ns.L
local Compat = ns.Compat
local describe = function(v) return Compat.Describe(v) end

local Verify = {}
ns.Verify = Verify

local scratchFrame
local eventMethod

-- Does the client know this event? Prefers C_EventUtils.IsEventValid; otherwise
-- tries to register it on a scratch frame (unknown events raise an error there).
function Verify.IsEventValid(name)
    local fn = Compat.Resolve("C_EventUtils.IsEventValid")
    if type(fn) == "function" then
        local ok, valid = pcall(fn, name)
        if ok then
            eventMethod = "C_EventUtils.IsEventValid"
            return valid == true
        end
    end
    eventMethod = "RegisterEvent"
    scratchFrame = scratchFrame or CreateFrame("Frame")
    local ok = pcall(scratchFrame.RegisterEvent, scratchFrame, name)
    if ok then pcall(scratchFrame.UnregisterEvent, scratchFrame, name) end
    return ok
end

local function keysOf(t)
    local keys = {}
    if type(t) ~= "table" then return keys end
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

local function isPlainNumber(v)
    return type(v) == "number" and not Compat.IsSecret(v)
end

-- Custom checks. Each returns status, detail.
local custom = {}

custom["x:build.interface"] = function()
    if ns.FlavorLogic.IsSupported(Compat.flavor) then
        return "PASS", tostring(Compat.interface) .. " -> " .. Compat.flavor
    end
    return "FAIL", tostring(Compat.interface) .. " is not a recognised flavor"
end

custom["x:build.version"] = function()
    return "INFO", tostring(Compat.version) .. " (" .. tostring(Compat.build) .. ")"
end

custom["x:build.tocflavor"] = function()
    if Compat.tocFlavor == Compat.flavor then
        return "PASS", "loaded " .. tostring(Compat.tocFlavor) .. " TOC"
    end
    return "FAIL", "loaded " .. tostring(Compat.tocFlavor) .. " TOC but the interface number says " .. tostring(Compat.flavor)
end

custom["x:build.projectid"] = function()
    local consts = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^WOW_PROJECT_") and type(v) == "number" then
            consts[#consts + 1] = k:gsub("^WOW_PROJECT_", "") .. "=" .. v
        end
    end
    table.sort(consts)
    return "INFO", "WOW_PROJECT_ID=" .. describe(_G.WOW_PROJECT_ID) .. "; constants: " .. table.concat(consts, " ")
end

custom["x:addon.questie"] = function()
    local okLoaded, loaded = Compat.Try("C_AddOns.IsAddOnLoaded", "Questie")
    local okVersion, version = Compat.Try("C_AddOns.GetAddOnMetadata", "Questie", "Version")
    return "INFO", "loaded=" .. describe(okLoaded and loaded) .. " version=" .. describe(okVersion and version)
end

local function persistCheck(probe)
    if type(probe) ~= "table" then return "FAIL", "probe table missing" end
    local detail = string.format("loads=%s lastLogoutSaved=%s firstSeen=%s",
        describe(probe.loads), describe(probe.lastLogout and date("%Y-%m-%d %H:%M", probe.lastLogout)),
        describe(probe.firstSeen and date("%Y-%m-%d %H:%M", probe.firstSeen)))
    if (probe.loads or 0) > 1 then
        return "PASS", detail .. " (count grew, so data survived a reload)"
    end
    return "INFO", detail .. " (first load: /reload, run /fl verify again, loads should be 2)"
end

custom["x:sv.persist"] = function()
    return persistCheck(ns.db.dev.persistProbe)
end

custom["x:sv.backup"] = function()
    return persistCheck(type(FellowshipLedgerBackupDB) == "table" and FellowshipLedgerBackupDB.persistProbe)
end

custom["x:secret.ownvalues"] = function()
    local level = UnitLevel("player")
    local xp, xpMax = UnitXP("player"), UnitXPMax("player")
    local money = GetMoney()
    local parts = {
        "level " .. (isPlainNumber(level) and "ok" or describe(level)),
        "xp " .. (isPlainNumber(xp) and "ok" or describe(xp)),
        "xpMax " .. (isPlainNumber(xpMax) and "ok" or describe(xpMax)),
        "money " .. (isPlainNumber(money) and "ok" or describe(money)),
    }
    local allOk = isPlainNumber(level) and isPlainNumber(xp) and isPlainNumber(xpMax) and isPlainNumber(money)
    return allOk and "PASS" or "FAIL", table.concat(parts, ", ")
end

custom["x:map.current"] = function()
    local ok, mapID = Compat.Try("C_Map.GetBestMapForUnit", "player")
    if not ok or not isPlainNumber(mapID) then return "FAIL", "mapID=" .. describe(mapID) end
    local okInfo, info = Compat.Try("C_Map.GetMapInfo", mapID)
    local name = okInfo and type(info) == "table" and info.name
    return name and "PASS" or "FAIL", "mapID=" .. mapID .. " name " .. (name and "readable" or "missing")
end

custom["x:quest.questline"] = function()
    local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
    if not okN then return "FAIL", "cannot read the quest log" end
    local checked, found, example = 0, 0, nil
    for i = 1, math.min(n or 0, 40) do
        local okInfo, info = Compat.Try("C_QuestLog.GetInfo", i)
        if okInfo and type(info) == "table" and not info.isHeader and info.questID then
            checked = checked + 1
            local okLine, line = Compat.Try("C_QuestLine.GetQuestLineInfo", info.questID)
            if okLine and type(line) == "table" then
                found = found + 1
                if not example then
                    local okQ, quests = Compat.Try("C_QuestLine.GetQuestLineQuests", line.questLineID)
                    example = string.format("e.g. questLineID=%s with %s quests; fields: %s",
                        describe(line.questLineID), okQ and type(quests) == "table" and #quests or "?",
                        table.concat(keysOf(line), ","))
                end
            end
        end
    end
    if checked == 0 then return "INFO", "no quests in your log; pick some up and run again" end
    return "INFO", string.format("checked %d quests, %d returned a quest line. %s", checked, found, example or "")
end

custom["x:dungeon.instance"] = function()
    local r = ns.util.pack(GetInstanceInfo())
    -- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID
    return "INFO", string.format("returned %d values; type=%s difficultyID=%s instanceID=%s",
        r.n, describe(r[2]), describe(r[3]), describe(r[8]))
end

custom["x:prof.list"] = function()
    if Compat.Has("GetProfessions") then
        local p = ns.util.pack(GetProfessions())
        local readable = 0
        for i = 1, p.n do
            if p[i] then
                local okInfo, _, _, rank, maxRank = Compat.Try("GetProfessionInfo", p[i])
                if okInfo and isPlainNumber(rank) and isPlainNumber(maxRank) then readable = readable + 1 end
            end
        end
        return "INFO", string.format("GetProfessions gave %d slots, %d with readable rank", p.n, readable)
    end
    if Compat.Has("GetNumSkillLines") then
        return "INFO", "GetProfessions missing; GetNumSkillLines=" .. describe(GetNumSkillLines())
    end
    return "FAIL", "no profession API found"
end

custom["x:comms.enum"] = function()
    local enum = _G.Enum and _G.Enum.SendAddonMessageResult
    if type(enum) ~= "table" then return "FAIL", "Enum.SendAddonMessageResult missing" end
    local wanted = { "Success", "AddOnMessageLockdown", "TargetOffline", "AddonMessageThrottle", "ChannelThrottle" }
    local missing = {}
    for _, k in ipairs(wanted) do
        if enum[k] == nil then missing[#missing + 1] = k end
    end
    local all = {}
    for _, k in ipairs(keysOf(enum)) do all[#all + 1] = k .. "=" .. describe(enum[k]) end
    local detail = table.concat(all, " ")
    if #missing > 0 then return "FAIL", "missing " .. table.concat(missing, ",") .. "; has " .. detail end
    return "PASS", detail
end

custom["x:comms.prefix"] = function()
    local prefix = ns.FlavorLogic.PREFIX[Compat.flavor]
    if not prefix then return "FAIL", "no prefix for flavor " .. tostring(Compat.flavor) end
    local okReg, result = Compat.Try("C_ChatInfo.RegisterAddonMessagePrefix", prefix)
    local okIs, registered = Compat.Try("C_ChatInfo.IsAddonMessagePrefixRegistered", prefix)
    local detail = string.format("%s register returned %s; registered=%s", prefix,
        describe(okReg and result), describe(okIs and registered))
    return (okIs and registered) and "PASS" or "FAIL", detail
end

custom["x:friends.bnfields"] = function()
    local okN, total, online = Compat.Try("BNGetNumFriends")
    if not okN then return "FAIL", "BNGetNumFriends unavailable" end
    local fields, seen = {}, {}
    local accountFields
    for i = 1, total or 0 do
        local okA, account = Compat.Try("C_BattleNet.GetFriendAccountInfo", i)
        if okA and type(account) == "table" then
            accountFields = accountFields or keysOf(account)
            local okC, count = Compat.Try("C_BattleNet.GetFriendNumGameAccounts", i)
            for j = 1, (okC and count) or 0 do
                local okG, game = Compat.Try("C_BattleNet.GetFriendGameAccountInfo", i, j)
                if okG and type(game) == "table" then
                    for _, k in ipairs(keysOf(game)) do fields[k] = true end
                    local key = describe(game.clientProgram) .. "/" .. describe(game.wowProjectID)
                    seen[key] = (seen[key] or 0) + 1
                end
            end
        end
    end
    local seenList = {}
    for k, v in pairs(seen) do seenList[#seenList + 1] = k .. " x" .. v end
    table.sort(seenList)
    return "INFO", string.format("friends=%s online=%s; account fields: %s; game fields: %s; online client/project: %s",
        describe(total), describe(online), table.concat(accountFields or {}, ","),
        table.concat(ns.util.sortedKeys(fields), ","), #seenList > 0 and table.concat(seenList, ", ") or "none online")
end

custom["x:friends.charfields"] = function()
    local okN, n = Compat.Try("C_FriendList.GetNumFriends")
    if not okN then return "FAIL", "C_FriendList.GetNumFriends unavailable" end
    if (n or 0) == 0 then return "INFO", "no character friends to inspect" end
    local okI, info = Compat.Try("C_FriendList.GetFriendInfoByIndex", 1)
    if not okI or type(info) ~= "table" then return "FAIL", "GetFriendInfoByIndex(1) returned " .. describe(info) end
    return "INFO", string.format("friends=%d; fields: %s", n, table.concat(keysOf(info), ","))
end

custom["x:rep.fields"] = function()
    local okN, n = Compat.Try("C_Reputation.GetNumFactions")
    if not okN then return "FAIL", "C_Reputation.GetNumFactions unavailable" end
    for i = 1, math.min(n or 0, 60) do
        local ok, data = Compat.Try("C_Reputation.GetFactionDataByIndex", i)
        if ok and type(data) == "table" and not data.isHeader then
            local need = { "factionID", "currentStanding", "name", "isHeader" }
            local missing = {}
            for _, k in ipairs(need) do if data[k] == nil then missing[#missing + 1] = k end end
            local detail = "fields: " .. table.concat(keysOf(data), ",")
            if #missing > 0 then return "FAIL", "missing " .. table.concat(missing, ",") .. "; " .. detail end
            return "PASS", detail
        end
    end
    return "INFO", "no non-header faction found (" .. describe(n) .. " entries)"
end

custom["x:ui.frame"] = function()
    local f = CreateFrame("Frame")
    local t = f:CreateTexture()
    local have = {}
    for _, m in ipairs({ "SetResizeBounds", "SetMinResize", "StartSizing", "SetShown", "SetResizable", "SetClampedToScreen" }) do
        have[#have + 1] = m .. "=" .. (type(f[m]) == "function" and "yes" or "no")
    end
    have[#have + 1] = "SetColorTexture=" .. (type(t.SetColorTexture) == "function" and "yes" or "no")
    -- Sort arrows (1.0.1): optional, the arrow is skipped without them.
    local fs = f:CreateFontString()
    have[#have + 1] = "SetTexCoord=" .. (type(t.SetTexCoord) == "function" and "yes" or "no")
    have[#have + 1] = "SetVertexColor=" .. (type(t.SetVertexColor) == "function" and "yes" or "no")
    have[#have + 1] = "GetStringWidth=" .. (type(fs.GetStringWidth) == "function" and "yes" or "no")
    local ok = type(f.StartSizing) == "function" and type(f.SetShown) == "function" and type(t.SetColorTexture) == "function"
        and (type(f.SetResizeBounds) == "function" or type(f.SetMinResize) == "function")
    return ok and "PASS" or "FAIL", table.concat(have, " ")
end

custom["x:ui.compartment"] = function()
    local f = _G.AddonCompartmentFrame
    if type(f) ~= "table" then return "FAIL", "AddonCompartmentFrame missing" end
    return type(f.RegisterAddon) == "function" and "PASS" or "FAIL", "RegisterAddon is " .. type(f.RegisterAddon)
end

-- Quest details (D-100): what the log gives for each quest, and the last quest dialog.
custom["x:quest.rewards"] = function()
    if not ns.QuestRewards then return "FAIL", "QuestRewards module missing" end
    local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
    local parts, any = {}, false
    for i = 1, okN and n or 0 do
        local ok, info = Compat.Try("C_QuestLog.GetInfo", i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            pcall(ns.QuestRewards.FromLog, info.questID)
            local e = (ns.db.questRewards or {})[info.questID]
            local items = {}
            for _, it in ipairs(e and e.items or {}) do items[#items + 1] = (it.choice and "c" or "r") .. it.id end
            if e and (#items > 0 or e.money or e.xp) then any = true end
            parts[#parts + 1] = string.format("%d xp=%s money=%s items=%s from=%s", info.questID, tostring(e and e.xp),
                tostring(e and e.money), #items > 0 and table.concat(items, "/") or "-", tostring(e and e.from))
        end
    end
    local d = ns.QuestRewards.lastDialog
    parts[#parts + 1] = d and string.format("last dialog: quest %d, %d items, money=%s, xp=%s", d.id, d.items, tostring(d.money), tostring(d.xp))
        or "no quest dialog seen since the reload"
    if #parts == 1 and not d then return "INFO", "quest log empty; " .. parts[1] end
    return (any or d) and "PASS" or "FAIL", table.concat(parts, "; ")
end

custom["x:questie.xp"] = function()
    local okLoaded, loaded = Compat.Try("C_AddOns.IsAddOnLoaded", "Questie")
    if not (okLoaded and loaded) then return "INFO", "Questie not loaded" end
    local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
    local parts = {}
    for i = 1, okN and n or 0 do
        local ok, info = Compat.Try("C_QuestLog.GetInfo", i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            parts[#parts + 1] = string.format("%d=%s", info.questID, tostring(ns.QuestRewards.QuestieXP(info.questID)))
            if #parts >= 6 then break end
        end
    end
    if #parts == 0 then return "INFO", "quest log empty" end
    local any = false
    for _, p in ipairs(parts) do if not p:find("=nil$") then any = true end end
    return any and "PASS" or "FAIL", table.concat(parts, " ")
end

custom["x:tooltip.unit"] = function()
    local hook = ns.TooltipInfo and ns.TooltipInfo.hook
    return hook and "PASS" or "FAIL", "hook=" .. tostring(hook)
end

custom["x:questie.db"] = function()
    local okLoaded, loaded = Compat.Try("C_AddOns.IsAddOnLoaded", "Questie")
    if not (okLoaded and loaded) then return "INFO", "Questie not loaded" end
    local state = ns.QuestChains.QuestieState()
    local detail = "state=" .. state
    if state == "ready" then
        -- Every quest in the log and what the chain lookup says for it.
        local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
        local parts = {}
        for i = 1, okN and n or 0 do
            local ok, info = Compat.Try("C_QuestLog.GetInfo", i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then
                local e = ns.QuestChains.Lookup(info.questID)
                parts[#parts + 1] = string.format("%d %s", info.questID, e and (e.step .. "/" .. e.total .. " " .. e.source) or "none")
            end
        end
        detail = detail .. "; log: " .. (#parts > 0 and table.concat(parts, ", ") or "empty")
    end
    local QC = ns.QuestChains
    if (QC.questieErrors or 0) > 0 then
        detail = detail .. string.format("; %d failed queries, last: %s", QC.questieErrors, tostring(QC.questieLastError))
    end
    return state == "ready" and "PASS" or (state == "loading" and "INFO" or "FAIL"), detail
end

-- The quest-chain drop-downs (D-078): a quest from your log with Questie's level,
-- required level, who starts it and where. Quests whose chain is known are preferred.
custom["x:questie.details"] = function()
    if ns.QuestChains.QuestieState() ~= "ready" then return "INFO", "Questie not ready (" .. ns.QuestChains.QuestieState() .. ")" end
    local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
    local pick
    for i = 1, okN and n or 0 do
        local ok, info = Compat.Try("C_QuestLog.GetInfo", i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local e = ns.QuestChains.Lookup(info.questID)
            if not pick or (e and e.step) then pick = info.questID end
            if e and e.step then break end
        end
    end
    if not pick then return "INFO", "quest log is empty; pick up a quest and run /fl verify again" end
    local q = ns.QuestChains.QuestInfo(pick)
    local s = q.start
    local detail = string.format("quest %d \"%s\": level %s, needs %s; starts %s%s%s", pick, tostring(q.name), tostring(q.level),
        tostring(q.req), s and s.kind or "unknown", s and (" " .. tostring(s.name)) or "", s and s.zone and (" in " .. s.zone) or "") .. (s and s.x and string.format(" at %.1f, %.1f", s.x, s.y) or "")
    local good = q.name and type(q.level) == "number" and s and s.name
    return good and "PASS" or "FAIL", detail
end

-- Graphs drop-downs: did the game's menu open and fill this session?
custom["x:graphs.menu"] = function()
    local st = ns.GraphsTab and ns.GraphsTab.menuStatus
    if not st then return "INFO", "not opened this session; open Graphs, click the character name or Compare, then /fl verify" end
    if st.ok then return "PASS", string.format("opened at %s with %d choices", date("%H:%M", st.at), st.items or 0) end
    return "FAIL", "menu failed: " .. tostring(st.err) .. " (the buttons cycle instead)"
end

-- Flight paths (D-080): what this character has saved, and what was seen this session.
custom["x:flight.paths"] = function()
    local char = ns.Store and ns.Store.char
    if not char then return "INFO", "no character" end
    local known, counted, newest = 0, 0, nil
    for _, fp in pairs(char.flightPaths or {}) do
        known = known + 1
        if not fp.baseline then
            counted = counted + 1
            if not newest or (fp.at or 0) > (newest.at or 0) then newest = fp end
        end
    end
    local fpT = ns.Trackers.byId.flightPaths
    local c = fpT and fpT.lastCheck or {}
    local detail = string.format("known=%d counted=%d baseline=%s; message this session=%s; map this session=%s",
        known, counted, tostring(char.flightPathsBaseline == true), c.message and date("%H:%M", c.message) or "no",
        c.open and string.format("%s (%d nodes, %d new)", date("%H:%M", c.open.at), c.open.nodes, c.open.added) or "no")
    if newest then detail = detail .. string.format("; newest counted: %s at %s", tostring(newest.name), date("%m-%d %H:%M", newest.at or 0)) end
    if counted > 0 then return "PASS", detail end
    return "INFO", detail .. "; talk to a flight master you don't know yet, then /fl verify"
end

-- All completed quests (D-081): which list the client gives, how many, and a sample name and zone.
custom["x:quest.completed"] = function()
    local okA = Compat.Has("C_QuestLog.GetAllCompletedQuestIDs")
    local okB = Compat.Has("GetQuestsCompleted")
    local ids = ns.QuestChains.CompletedIDs()
    if not ids then return "FAIL", "no completed-quest list (GetAllCompletedQuestIDs " .. tostring(okA) .. ", GetQuestsCompleted " .. tostring(okB) .. ")" end
    local detail = string.format("%d completed via %s", #ids, okA and "GetAllCompletedQuestIDs" or "GetQuestsCompleted")
    -- A sample with a name (the highest IDs are often hidden tracking quests), and how many have none.
    local unnamed, sample = 0, nil
    for _, qid in ipairs(ids) do
        local info = ns.QuestChains.QuestInfo(qid)
        if info.name then sample = sample or { id = qid, info = info } else unnamed = unnamed + 1 end
    end
    if sample then
        detail = detail .. string.format("; quest %d = %s in %s", sample.id, tostring(sample.info.name), tostring(sample.info.zone))
    end
    detail = detail .. string.format("; %d without a name (hidden)", unnamed)
    return #ids > 0 and "PASS" or "INFO", detail
end

-- Which copy of the dungeon we are in (D-112): from the last creature GUID seen in a run.
custom["x:dungeon.copy"] = function()
    local D = ns.Trackers and ns.Trackers.byId and ns.Trackers.byId.dungeons
    local run = ns.Store and ns.Store.char and ns.Store.char.currentRun
    local seen = D and D.lastCopy
    local detail = string.format("open run: %s (map %s), copy=%s, back in=%s", tostring(run and run.name), tostring(run and run.instanceID),
        tostring(run and run.copy), tostring(run and run.backAt ~= nil))
    -- How far each creature got (target / kill, then the step that stopped it).
    local stats, keys = D and D.copyStats or {}, {}
    for k in pairs(stats) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do keys[i] = k .. "=" .. stats[k] end
    detail = detail .. "; seen: " .. (#keys > 0 and table.concat(keys, " ") or "none")
    if not seen then return "INFO", detail .. "; no creature GUID read yet this session (target one inside a dungeon)" end
    detail = detail .. string.format("; last: %s, copy=%s, GUID map=%s, run map=%s, %ds ago", tostring(seen.kind), tostring(seen.copy),
        tostring(seen.guid), tostring(seen.runMap), (ns.Store.Now() - (seen.at or 0)))
    return seen.copy and "PASS" or "FAIL", detail
end

-- Dungeon completion (D-085): the newest run, and the journal's boss list for it by name.
custom["x:dungeon.journal"] = function()
    local char = ns.Store and ns.Store.char
    local runs = char and char.dungeons or {}
    local run = (char and char.currentRun) or runs[#runs]
    if not run then return "INFO", "no dungeon runs yet; run one, then /fl verify" end
    local detail = string.format("%s: %d bosses killed, completed=%s, lastBossID=%s via %s, lookups=%s", tostring(run.name),
        #(run.bosses or {}), tostring(run.completed == true), tostring(run.lastBossID), tostring(run.lookup), tostring(run.lookups))
    detail = detail .. ", lastBossName=" .. tostring(run.lastBossName)
    local finals = ns.DungeonBosses.For(run.name)
    detail = detail .. "; final-boss list: " .. (finals and table.concat(finals, " / ") or "not listed")
    -- What the journal holds: how many instances, the first few names, and this dungeon's bosses.
    local list = ns.DungeonJournalList and ns.DungeonJournalList() or {}
    local names = {}
    for i = 1, math.min(6, #list) do names[i] = tostring(list[i].name) end
    detail = detail .. string.format("; journal: %d instances (%s)", #list, table.concat(names, ", "))
    local journalID = ns.DungeonJournalByName and ns.DungeonJournalByName(run.name)
    detail = detail .. "; by name: " .. tostring(journalID)
    if journalID then
        local bosses = {}
        for _, b in ipairs(ns.DungeonJournalBosses(journalID)) do
            bosses[#bosses + 1] = string.format("%s[%s/%s]", tostring(b.name), tostring(b.encounterID), tostring(b.journalID))
        end
        detail = detail .. " bosses " .. table.concat(bosses, " ")
    end
    local last, count, how, lastName = nil, nil, nil, nil
    if ns.DungeonFindLastBoss then last, count, how, lastName = ns.DungeonFindLastBoss(run.name) end
    detail = detail .. string.format("; now: last=%s (%s) of %s via %s", tostring(last), tostring(lastName), tostring(count), tostring(how))
    if run.completed then return "PASS", detail end
    return (last ~= nil or finals) and "PASS" or "FAIL", detail
end

custom["x:death.recap"] = function()
    if not (Compat.Has("C_DeathRecap.HasRecapEvents") and Compat.Has("C_DeathRecap.GetRecapEvents")) then
        return "FAIL", "death recap functions missing"
    end
    local newest
    for id = 1, 60 do
        local ok, has = Compat.Try("C_DeathRecap.HasRecapEvents", id)
        if ok and has == true then newest = id end
    end
    if not newest then return "INFO", "no death recap this session; die once (a fall will do) and run /fl verify again" end
    local ok, events = Compat.Try("C_DeathRecap.GetRecapEvents", newest)
    if not ok or type(events) ~= "table" or #events == 0 then return "FAIL", "recap " .. newest .. " has no readable events" end
    local e = events[1]
    local secret = Compat.IsSecret(e.sourceName) or Compat.IsSecret(e.spellName)
    return secret and "FAIL" or "PASS", string.format("recap %d: %d events; fields %s; source/spell %s", newest, #events,
        table.concat(keysOf(e), ","), secret and "SECRET" or "readable")
end

-- The newest death on this character: was the killer's level kept? (D-075)
custom["x:death.killerlevel"] = function()
    if Compat.disabled and Compat.disabled.killerLevel then return "FAIL", "turned off: " .. tostring(Compat.disabled.killerLevel) end
    local log = ns.Store and ns.Store.char and ns.Store.char.deathLog
    local d = log and log[#log]
    if not d then return "INFO", "no deaths on this character yet; target a monster, let it kill you, then run /fl verify" end
    local c = ns.Trackers.byId.deaths
    c = c and c.lastCheck
    local seen = c and string.format("; at death: target %s, recap source %s, matched by %s",
        Compat.Describe(c.target or "none"), Compat.Describe(c.source or "none"), tostring(c.how or "nothing")) or ""
    if type(d.killerLevel) == "number" then
        return "PASS", string.format("newest death: killer %s, level %d", tostring(d.killer), d.killerLevel) .. seen
    end
    if not d.killer then return "INFO", "newest death has no killer (" .. tostring(d.killerStatus) .. "), so no level" .. seen end
    return "INFO", "newest death: killer " .. tostring(d.killer) .. " was not your target, so no level" .. seen
end

local function runCheck(check)
    if check.kind == "api" then
        local value = Compat.Resolve(check.id)
        local expect = check.expect or "function"
        if type(value) == expect then return "PASS" end
        return "FAIL", "is " .. type(value) .. ", expected " .. expect
    elseif check.kind == "event" then
        local name = check.id:gsub("^ev:", "")
        if Verify.IsEventValid(name) then return "PASS" end
        return "FAIL", "unknown event (checked with " .. tostring(eventMethod) .. ")"
    elseif check.kind == "custom" then
        local fn = custom[check.id]
        if not fn then return "ERROR", "no implementation" end
        return fn()
    elseif check.kind == "manual" then
        return "MANUAL"
    end
    return "ERROR", "unknown kind " .. tostring(check.kind)
end

function Verify.Run()
    ns.Log.Info(L.VERIFY_RUNNING)
    local results = {}
    for _, check in ipairs(ns.VerifyChecks) do
        local r = ns.util.pack(pcall(runCheck, check))
        local status, detail
        if r[1] then
            status, detail = r[2], r[3]
        else
            status, detail = "ERROR", tostring(r[2])
        end
        results[#results + 1] = { id = check.id, kind = check.kind, area = check.area, status = status, detail = detail }
    end
    local meta = {
        version = ns.VERSION,
        flavor = Compat.flavor,
        tocFlavor = Compat.tocFlavor,
        interface = Compat.interface,
        clientVersion = Compat.version,
        build = Compat.build,
        at = date("%Y-%m-%d %H:%M"),
    }
    local probe = ns.db.dev.probe
    local text, counts = ns.VerifyReport.Build(meta, results, probe)
    ns.db.verify = { at = time(), flavor = Compat.flavor, counts = counts, text = text }
    ns.Log.Info(L.VERIFY_DONE, counts.PASS, counts.FAIL, counts.ERROR, counts.INFO, counts.MANUAL)
    ns.CopyWindow:Show(L.VERIFY_WINDOW_TITLE, text)
end

function Verify.Show()
    if not (ns.db.verify and ns.db.verify.text) then
        ns.Log.Info(L.VERIFY_NONE)
        return
    end
    ns.CopyWindow:Show(L.VERIFY_WINDOW_TITLE, ns.db.verify.text)
end
