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

custom["x:questie.db"] = function()
    local okLoaded, loaded = Compat.Try("C_AddOns.IsAddOnLoaded", "Questie")
    if not (okLoaded and loaded) then return "INFO", "Questie not loaded" end
    local state = ns.QuestChains.QuestieState()
    local detail = "state=" .. state
    if state == "ready" then
        local okN, n = Compat.Try("C_QuestLog.GetNumQuestLogEntries")
        for i = 1, okN and n or 0 do
            local ok, info = Compat.Try("C_QuestLog.GetInfo", i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then
                local e = ns.QuestChains.Lookup(info.questID)
                detail = detail .. string.format("; quest %d chain %s", info.questID, e and (e.step .. "/" .. e.total .. " via " .. e.source) or "none")
                break
            end
        end
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
