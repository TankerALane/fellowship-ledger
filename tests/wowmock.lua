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
    function f:IsShown() return self._shown == true end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetText(t) self._text = t end
    function f:GetText() return self._text end
    return f
end

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
    env.date = os.date
    env.time = os.time

    local state = { frames = {}, chat = {} }
    env.__state = state

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
        IsAddOnLoaded = function() return false end,
    }
    env.C_EventUtils = { IsEventValid = function(e) return M.knownEvents == nil or M.knownEvents[e] == true end }

    env.UnitLevel = function() return 12 end
    env.UnitXP = function() return 300 end
    env.UnitXPMax = function() return 2000 end
    env.GetMoney = function() return 12345 end
    env.UnitName = function() return "Tester" end
    env.GetRealmName = function() return "Test Realm" end
    env.C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetMapInfo = function() return { name = "Elwynn Forest", mapID = 1429 } end,
    }
    env.C_QuestLog = {
        GetNumQuestLogEntries = function() return 2 end,
        GetInfo = function(i)
            if i == 1 then return { isHeader = true, title = "Elwynn" } end
            return { isHeader = false, questID = 54, title = "Report to Goldshire" }
        end,
    }
    env.C_QuestLine = {
        GetQuestLineInfo = function() return { questLineID = 7, questLineName = "Chain" } end,
        GetQuestLineQuests = function() return { 54, 55, 56 } end,
    }
    env.GetInstanceInfo = function() return "Elwynn", "none", 0, "", 5, 0, false, 0 end
    env.GetProfessions = function() return 1, nil end
    env.GetProfessionInfo = function() return "Mining", 0, 15, 75 end
    env.Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 9, TargetOffline = 3,
        AddonMessageThrottle = 4, ChannelThrottle = 8 } }
    local registered = {}
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) registered[p] = true return 0 end,
        IsAddonMessagePrefixRegistered = function(p) return registered[p] == true end,
        SendAddonMessage = function() return 0 end,
    }
    env.BNGetNumFriends = function() return 1, 1 end
    env.C_BattleNet = {
        SendGameData = function() return 0 end,
        GetFriendAccountInfo = function() return { battleTag = "Secret#1234", isFriend = true } end,
        GetFriendNumGameAccounts = function() return 1 end,
        GetFriendGameAccountInfo = function()
            return { clientProgram = "WoW", wowProjectID = 99, characterName = "Hidden", gameAccountID = 5 }
        end,
    }
    env.C_FriendList = {
        GetNumFriends = function() return 1 end,
        GetFriendInfoByIndex = function() return { name = "HiddenFriend", connected = true } end,
    }
    env.WOW_PROJECT_ID = 99
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
