-- tests/wowmock.lua
-- A deliberately small fake of the WoW API, just enough to load the whole addon
-- in TOC order, fire events and run slash commands. It proves the runtime code has
-- no typos or nil-index bugs on its main paths. It does NOT prove the real client
-- behaves the same way; that is what /fl verify is for.

local M = {}

-- A frame-like object: any unknown method is a no-op that returns a new mock, so
-- UI building code (CreateTexture():SetPoint(...)) runs without a real renderer.
local function newObject(kind)
    local obj = { _kind = kind, _scripts = {}, _events = {} }
    return setmetatable(obj, {
        __index = function(_, key)
            return function() return newObject(key) end
        end,
    })
end

local function makeFrame(kind, name)
    local f = newObject(kind)
    f._name = name
    function f:SetScript(script, fn) self._scripts[script] = fn end
    function f:GetScript(script) return self._scripts[script] end
    function f:RegisterEvent(event)
        if M.knownEvents and not M.knownEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"")
        end
        self._events[event] = true
    end
    function f:UnregisterEvent(event) self._events[event] = nil end
    function f:UnregisterAllEvents() self._events = {} end
    function f:IsShown() return rawget(self, "_shown") == true end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetShown(v) self._shown = v and true or false end
    function f:SetText(t) self._text = t end
    function f:GetText() return rawget(self, "_text") end
    -- Sizes are numbers so layout math runs (defaults stand in for a real layout pass).
    function f:SetSize(w, h) self._w, self._h = w, h end
    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    function f:GetWidth() return rawget(self, "_w") or 600 end
    function f:GetHeight() return rawget(self, "_h") or 400 end
    function f:GetCenter() return 300, 300 end
    function f:GetEffectiveScale() return 1 end
    function f:GetScale() return 1 end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:GetVerticalScroll() return 0 end
    function f:GetVerticalScrollRange() return 0 end
    function f:SetAlpha(a) self._alpha = a end
    function f:CreateFontString() return makeFrame("FontString") end
    function f:CreateTexture() return makeFrame("Texture") end
    return f
end
M.makeFrame = makeFrame

-- Build a fresh environment. opts: { interface, tocFlavor, missing = { "Name", ... } }
function M.new(opts)
    opts = opts or {}
    local env = {}
    for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber",
        "tostring", "type", "unpack", "rawget", "rawset", "rawequal", "setmetatable", "getmetatable",
        "string", "table", "math", "print" }) do
        env[k] = _G[k]
    end
    env._G = env

    -- Controllable clock: tests move state.now; date()/time() follow it.
    local state = { frames = {}, chat = {}, now = opts.now or os.time({ year = 2026, month = 11, day = 4, hour = 12 }),
        timers = {}, tickers = {}, speed = 0, afk = false, money = 10000, level = 12, xp = 300, xpMax = 2000,
        instance = { "Elwynn Forest", "none", 0, "", 5, 0, false, 0 }, units = {}, guid = {} }
    env.__state = state
    env.time = function(t) if t then return os.time(t) end return state.now end
    env.date = function(fmt, t) return os.date(fmt, t or state.now) end
    env.C_Timer = {
        After = function(delay, fn) state.timers[#state.timers + 1] = { at = state.now + (tonumber(delay) or 0), fn = fn } end,
        NewTicker = function(seconds, fn)
            local t = { seconds = seconds, fn = fn, Cancel = function() end }
            state.tickers[#state.tickers + 1] = t
            return t
        end,
    }
    state.name, state.realm = opts.playerName or "Tester", opts.realm or "TestRealm"
    for k, v in pairs(opts.state or {}) do state[k] = v end -- extra starting state for a test
    env.UnitFullName = function(unit) if unit == "player" then return state.name, state.realm end end
    env.GetNormalizedRealmName = function() return state.realm end
    env.UnitClass = function(unit)
        if unit == "player" then return "Mage", "MAGE" end
        local u = state.units[unit]
        if u then return u.class, u.class end
    end
    env.UnitRace = function() return "Human", "Human" end
    env.UnitFactionGroup = function() return "Alliance" end
    env.UnitExists = function(unit) return unit == "player" or state.units[unit] ~= nil end
    env.UnitGroupRolesAssigned = function(unit) return state.units[unit] and state.units[unit].role or "NONE" end
    env.UnitGUID = function(unit) return state.guid[unit] end
    env.UnitCreatureType = function(unit) return state.units[unit] and state.units[unit].ctype end
    env.UnitClassification = function(unit) return state.units[unit] and state.units[unit].classification end
    env.UnitIsAFK = function() return state.afk end
    env.GetUnitSpeed = function() return state.speed end
    env.GetZoneText = function() return "Elwynn Forest" end
    env.GetAchievementInfo = function(id) return id, "Achievement " .. id end
    -- state.factions: list as the panel shows it; state.hiddenFactions: only reachable by ID
    env.C_Reputation = {
        GetNumFactions = function() return state.factions and #state.factions or 0 end,
        GetFactionDataByIndex = function(i) return state.factions and state.factions[i] end,
        GetFactionDataByID = function(id)
            for _, list in ipairs({ state.factions or {}, state.hiddenFactions or {} }) do
                for _, f in ipairs(list) do if f.factionID == id then return f end end
            end
        end,
    }
    env.GameTooltip = makeFrame("GameTooltip", "GameTooltip")
    env.GetCursorPosition = function() return 0, 0 end
    state.settingsCategories = {}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            local cat = { frame = frame, name = name, ID = #state.settingsCategories + 1 }
            state.settingsCategories[#state.settingsCategories + 1] = cat
            return cat
        end,
        RegisterAddOnCategory = function(cat) cat.registered = true end,
        OpenToCategory = function() end,
    }
    state.compartment = {}
    env.AddonCompartmentFrame = { RegisterAddon = function(_, info) state.compartment[#state.compartment + 1] = info end }
    for _, font in ipairs({ "GameFontHighlightSmall", "GameFontHighlight", "GameFontHighlightLarge", "GameFontNormal",
        "GameFontNormalLarge", "GameFontNormalSmall" }) do env[font] = { name = font } end
    -- Optional fake Questie (set state.questie = { [questID] = { pre = id, next = id, name = "..." } }).
    env.Questie = { API = { isReady = true } }
    env.QuestieLoader = {
        ImportModule = function(_, name)
            if state.questieBroken then error("no such module") end
            if name ~= "QuestieDB" then return nil end
            return { QueryQuestSingle = function(id, field)
                local q = state.questie and state.questie[id]
                if not q then return nil end
                if field == "preQuestSingle" then return q.pre and { q.pre } or nil end
                if field == "nextQuestInChain" then return q.next end
                if field == "name" then return q.name end
                if field == "zoneOrSort" then return q.zone end
                if field == "questLevel" then return q.level end
                if field == "requiredLevel" then return q.req end
                if field == "startedBy" then return q.startedBy end
                if field == "finishedBy" then return q.finishedBy end
                if field == "preQuestGroup" then return q.preGroup end
            end,
            -- state.questieNPCs = { [npcID] = { name, spawns = { [zoneID] = { {x, y} } } } }, same for Items (name only).
            QueryNPCSingle = function(id, field)
                local n = state.questieNPCs and state.questieNPCs[id]
                return n and n[field]
            end,
            QueryItemSingle = function(id, field)
                local n = state.questieItems and state.questieItems[id]
                return n and n[field]
            end }
        end,
    }
    -- Loot window: state.loot = { { name, quantity, quality, link, currency } }
    env.GetNumLootItems = function() return state.loot and #state.loot or 0 end
    env.GetLootSlotInfo = function(i)
        local l = state.loot and state.loot[i]
        if not l then return nil end
        return 136000, l.name, l.quantity or 1, l.currency, l.quality, false, false, nil, false
    end
    env.GetLootSlotLink = function(i) local l = state.loot and state.loot[i] return l and l.link end
    -- Death recap: state.recaps[id] = { events }
    env.C_DeathRecap = {
        HasRecapEvents = function(id) return state.recaps ~= nil and state.recaps[id] ~= nil end,
        GetRecapEvents = function(id) return state.recaps and state.recaps[id] end,
    }
    -- Secret values: anything listed in state.secrets is "secret".
    env.issecretvalue = function(v) return state.secrets ~= nil and state.secrets[v] == true end
    env.UnitIsPlayer = function(unit)
        if unit == "player" then return true end
        local u = state.units[unit]
        return u ~= nil and not u.npc
    end
    env.GetGameMessageInfo = function(t)
        if t == 408 then return "ERR_ZONE_EXPLORED" end
        if t == 300 then return "ERR_NEWTAXIPATH" end
        return "ERR_OTHER"
    end
    env.ERR_NEWTAXIPATH = "New flight path discovered!"
    -- Flight map: state.taxiNodes = { { nodeID, name, state } } (state 0 current, 1 reachable, 2 unreachable).
    env.GetTaxiMapID = function() return 1415 end
    env.C_TaxiMap = { GetAllTaxiNodes = function() return state.taxiNodes or {} end }
    env.ERR_ZONE_EXPLORED = "Discovered: %s"
    env.ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained"

    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) state.chat[#state.chat + 1] = text end }
    env.print = function(...) state.chat[#state.chat + 1] = table.concat({ ... }, " ") end

    env.CreateFrame = function(kind, name)
        local f = makeFrame(kind, name)
        state.frames[#state.frames + 1] = f
        if name then env[name] = f end
        return f
    end
    env.UIParent = makeFrame("Frame", "UIParent")
    env.Minimap = makeFrame("Frame", "Minimap")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.ChatFontNormal = {}

    local interface = opts.interface or 16001
    env.GetBuildInfo = function() return "1.60.1", "70790", "Nov 1 2026", interface end
    local meta = { ["X-Flavor"] = opts.tocFlavor or "Forever", Version = "0.0.1-dev" }
    env.C_AddOns = {
        GetAddOnMetadata = function(addon, field)
            if addon == "FellowshipLedger" then return meta[field] end
            return nil
        end,
        IsAddOnLoaded = function(name) return name == "Questie" and state.questieLoaded == true end,
    }
    env.C_EventUtils = { IsEventValid = function(e) return M.knownEvents == nil or M.knownEvents[e] == true end }

    env.UnitLevel = function(unit)
        if unit == "player" then return state.level end
        return state.units[unit] and state.units[unit].level
    end
    env.UnitXP = function() return state.xp end
    env.UnitXPMax = function() return state.xpMax end
    env.GetMoney = function() return state.money end
    env.UnitName = function(unit)
        if unit == "player" then return state.name end
        return state.units[unit] and state.units[unit].name
    end
    env.GetRealmName = function() return "Test Realm" end
    env.C_Map = {
        GetAreaInfo = function(area) return state.areas and state.areas[area] end,
        GetBestMapForUnit = function() return 1429 end,
        GetMapInfo = function() return { name = "Elwynn Forest", mapID = 1429 } end,
    }
    env.C_QuestLog = {
        GetNumQuestLogEntries = function() return 2 end,
        GetTitleForQuestID = function(id) return "Quest " .. id end,
        IsQuestFlaggedCompleted = function(id) return state.completed ~= nil and state.completed[id] == true end,
        GetAllCompletedQuestIDs = function()
            local ids = {}
            for id, done in pairs(state.completed or {}) do if done then ids[#ids + 1] = id end end
            return ids
        end,
        GetInfo = function(i)
            if i == 1 then return { isHeader = true, title = "Elwynn" } end
            return { isHeader = false, questID = 54, title = "Report to Goldshire" }
        end,
    }
    env.C_QuestLine = {
        GetQuestLineInfo = function() if state.noQuestLines then return nil end return { questLineID = 7, questLineName = "Chain" } end,
        GetQuestLineQuests = function() return { 54, 55, 56 } end,
    }
    env.GetInstanceInfo = function() return unpack(state.instance, 1, 8) end
    env.EJ_GetInstanceForMap = function() return state.ejInstance end
    env.EJ_SelectInstance = function() end
    -- Journal by name: state.ejList = { { id, name } } (one tier).
    env.EJ_GetNumTiers = function() return 1 end
    env.EJ_SelectTier = function() end
    env.EJ_GetInstanceByIndex = function(i)
        local e = state.ejList and state.ejList[i]
        if e then return e.id, e.name end
    end
    env.EJ_GetEncounterInfoByIndex = function(i)
        local b = state.ejBosses and state.ejBosses[i]
        if b then return b.name, "", i, 0, "", state.ejInstance, b.id end
    end
    env.GetProfessions = function() return 1, nil end
    env.GetProfessionInfo = function() return "Mining", 0, 15, 75 end
    -- Real retail values (verify report 2026-11-04).
    env.Enum = { SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
        InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
        NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 },
        FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
    -- Comms: every send is recorded in state.sent; state.sendResult overrides the result.
    state.sent = {}
    state.combat = false
    env.InCombatLockdown = function() return state.combat end
    env.GetTime = function() return state.now end
    env.IsTrialAccount = function() return state.trial == true end
    env.IsVeteranTrialAccount = function() return false end
    env.BNET_CLIENT_WOW = "WoW"
    local registered = {}
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) registered[p] = true return 0 end,
        IsAddonMessagePrefixRegistered = function(p) return registered[p] == true end,
        SendAddonMessage = function(prefix, text, channel, target)
            state.sent[#state.sent + 1] = { kind = "addon", prefix = prefix, text = text, channel = channel, target = target }
            return state.sendResult or 0
        end,
        InChatMessagingLockdown = function() return state.chatLockdown == true end,
    }
    -- Battle.net friends: state.bnFriends = { { battleTag, games = { { gameAccountID, characterName, realmName, wowProjectID, clientProgram } } } }
    state.bnFriends = opts.bnFriends or { { battleTag = "Secret#1234",
        games = { { clientProgram = "WoW", wowProjectID = 99, characterName = "Hidden", gameAccountID = 5 } } } }
    env.BNGetNumFriends = function() return #state.bnFriends, #state.bnFriends end
    env.C_BattleNet = {
        SendGameData = function(gameAccountID, prefix, text)
            state.sent[#state.sent + 1] = { kind = "bn", prefix = prefix, text = text, target = gameAccountID }
            return state.sendResult or 0
        end,
        GetFriendAccountInfo = function(i)
            local f = state.bnFriends[i]
            return f and { battleTag = f.battleTag, isFriend = true } or nil
        end,
        GetFriendNumGameAccounts = function(i) return state.bnFriends[i] and #state.bnFriends[i].games or 0 end,
        GetFriendGameAccountInfo = function(i, j)
            local g = state.bnFriends[i] and state.bnFriends[i].games[j]
            if not g then return nil end
            return { clientProgram = g.clientProgram or "WoW", wowProjectID = g.wowProjectID or 99, characterName = g.characterName,
                realmName = g.realmName, gameAccountID = g.gameAccountID, isOnline = g.isOnline ~= false }
        end,
    }
    state.charFriends = opts.charFriends or { { name = "HiddenFriend", connected = true } }
    env.C_FriendList = {
        GetNumFriends = function() return #state.charFriends end,
        GetFriendInfoByIndex = function(i) return state.charFriends[i] end,
    }
    env.WOW_PROJECT_ID = opts.projectID or 99
    env.WOW_PROJECT_MAINLINE = 1

    for _, name in ipairs(opts.missing or {}) do env[name] = nil end

    return setmetatable(env, {
        __index = function() return nil end, -- unknown globals are simply missing, like a client without them
    })
end

-- Load every file a TOC lists, in order, sharing one namespace.
function M.loadToc(H, env, tocRel)
    local ns = {}
    local toc = H.readFile("FellowshipLedger/" .. tocRel)
    for line in (toc .. "\n"):gmatch("(.-)\r?\n") do
        if line ~= "" and not line:find("^#") then
            local rel = line:gsub("\\", "/")
            local chunk = assert(loadfile(H.ROOT .. "/FellowshipLedger/" .. rel))
            setfenv(chunk, env)
            chunk("FellowshipLedger", ns)
        end
    end
    return ns
end

-- Deliver an event to every frame registered for it.
function M.fire(env, event, ...)
    for _, f in ipairs(env.__state.frames) do
        local handler = f._scripts.OnEvent
        if f._events[event] and handler then handler(f, event, ...) end
    end
end

-- Run queued C_Timer.After callbacks (and any they queue).
function M.runTimers(env)
    local st = env.__state
    for _ = 1, 10 do
        local queue = st.timers
        if #queue == 0 then return end
        st.timers = {}
        for _, t in ipairs(queue) do t.fn() end
    end
end

-- Run only the C_Timer.After callbacks whose delay has passed (for clock-driven tests).
function M.runDueTimers(env)
    local st = env.__state
    for _ = 1, 10 do
        local due, later = {}, {}
        for _, t in ipairs(st.timers) do
            if t.at <= st.now then due[#due + 1] = t else later[#later + 1] = t end
        end
        if #due == 0 then return end
        st.timers = later
        for _, t in ipairs(due) do t.fn() end
    end
end

-- Move the clock forward in ticker-sized steps, firing tickers whose period divides.
function M.advance(env, seconds, step)
    local st = env.__state
    step = step or 30
    local target = st.now + seconds
    while st.now < target do
        st.now = math.min(st.now + step, target)
        for _, t in ipairs(st.tickers) do
            if t.seconds <= step or (st.now % t.seconds) < step then t.fn() end
        end
    end
    M.runTimers(env)
end

function M.slash(env, msg)
    env.SlashCmdList.FELLOWSHIPLEDGER(msg)
end

function M.chatContains(env, needle)
    for _, line in ipairs(env.__state.chat) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

return M
