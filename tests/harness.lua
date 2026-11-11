-- tests/harness.lua
-- Tiny test runner for Lua 5.1 / LuaJIT. No dependencies.

local H = {}

H.ROOT = "."
H.tests = {}

function H.test(name, fn)
    H.tests[#H.tests + 1] = { name = name, fn = fn, file = H.currentFile }
end

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function H.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function H.ok(cond, msg)
    if not cond then error(msg or "expected a true value", 2) end
end

function H.fails(fn, pattern, msg)
    local ok, err = pcall(fn)
    if ok then error((msg or "expected an error") .. " (no error raised)", 2) end
    if pattern and not tostring(err):find(pattern) then
        error((msg or "wrong error") .. ": " .. tostring(err), 2)
    end
end

function H.readFile(rel)
    local f = assert(io.open(H.ROOT .. "/" .. rel, "rb"), "cannot open " .. rel)
    local s = f:read("*a")
    f:close()
    return s
end

function H.fileExists(rel)
    local f = io.open(H.ROOT .. "/" .. rel, "rb")
    if f then f:close() return true end
    return false
end

-- Standard Lua globals a PURE addon file may use. Anything else (any WoW API)
-- raises an error, which is how the purity rule is enforced.
local ALLOWED = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber",
    "tostring", "type", "unpack", "rawget", "rawset", "rawequal", "setmetatable",
    "getmetatable", "string", "table", "math",
}

function H.strictEnv()
    local env = {}
    for _, k in ipairs(ALLOWED) do env[k] = _G[k] end
    env._G = env
    return setmetatable(env, {
        __index = function(_, k) error("read of non-standard global '" .. tostring(k) .. "'", 2) end,
        __newindex = function(_, k) error("write of global '" .. tostring(k) .. "'", 2) end,
    })
end

-- Load one addon file (path relative to FellowshipLedger/) the way the game does:
-- the chunk receives (addonName, ns). Pure files run in the strict environment.
function H.loadAddonFile(rel, ns, env)
    local path = H.ROOT .. "/FellowshipLedger/" .. rel
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. rel .. ": " .. tostring(err), 2) end
    setfenv(chunk, env or H.strictEnv())
    chunk("FellowshipLedger", ns)
    return ns
end

-- Files that must be pure, in TOC load order.
H.PURE_FILES = {
    "Core/Namespace.lua",
    "Locale/Locale.lua",
    "Locale/enUS.lua",
    "Locale/enUS_Phase2.lua",
    "Locale/enUS_Phase3.lua",
    "Locale/enUS_Social.lua",
    "Core/Migrations.lua",
    "Compat/FlavorLogic.lua",
    "Core/Clock.lua",
    "Core/Days.lua",
    "Core/Sessions.lua",
    "Core/Format.lua",
    "Core/TrackerList.lua",
    "Core/Character.lua",
    "Core/BackupLogic.lua",
    "Core/GoldLogic.lua",
    "Core/Export.lua",
    "Core/SettingsDefaults.lua",
    "Core/Summary.lua",
    "Core/Notices.lua",
    "Core/Weekly.lua",
    "Core/Invites.lua",
    "Core/Bests.lua",
    "Core/DungeonLevels.lua",
    "Core/Goals.lua",
    "Core/XPSources.lua",
    "Core/RunTimer.lua",
    "Core/Leaderboard.lua",
    "Core/QuestChainLogic.lua",
    "Core/DungeonBosses.lua",
    "UI/Palette.lua",
    "UI/Layout.lua",
    "UI/MeModel.lua",
    "UI/DetailModel.lua",
    "UI/ChainModel.lua",
    "UI/StatsModel.lua",
    "UI/GraphModel.lua",
    "UI/FriendsModel.lua",
    "UI/DungeonsModel.lua",
    "Debug/FakeData.lua",
    "Comms/Codec.lua",
    "Comms/Merge.lua",
    "Comms/RateLimit.lua",
    "Debug/VerifyChecks.lua",
    "Debug/VerifyReport.lua",
}

-- A fresh namespace with every pure module loaded.
function H.pureNamespace()
    local ns = {}
    for _, rel in ipairs(H.PURE_FILES) do H.loadAddonFile(rel, ns) end
    return ns
end

function H.run()
    local passed, failed = 0, 0
    for _, t in ipairs(H.tests) do
        local ok, err = pcall(t.fn)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAIL  " .. t.file .. " :: " .. t.name .. "\n      " .. tostring(err))
        end
    end
    print(string.format("\n%d passed, %d failed, %d total", passed, failed, passed + failed))
    return failed == 0
end

return H
