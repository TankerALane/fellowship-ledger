-- Core/Init.lua
-- Startup: saved variables, migrations, flavor detection, the current character,
-- trackers, timers and slash commands. Loaded last, so every module exists on `ns`.

local ADDON_NAME, ns = ...
local L, Log, Compat = ns.L, ns.Log, ns.Compat

local frame = CreateFrame("Frame")
ns.eventFrame = frame

local handlers = {}

-- Count loads and logouts in BOTH saved variables, so /fl verify can tell whether
-- the client really persists them across /reload and relog.
local function touchPersistProbe(tbl, field)
    local p = tbl[field]
    if type(p) ~= "table" then p = { loads = 0 } end
    p.loads = (p.loads or 0) + 1
    p.firstSeen = p.firstSeen or time()
    p.lastLoad = time()
    tbl[field] = p
end

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    frame:UnregisterEvent("ADDON_LOADED")

    Compat.Detect()

    if type(FellowshipLedgerDB) ~= "table" then FellowshipLedgerDB = {} end
    if type(FellowshipLedgerBackupDB) ~= "table" then FellowshipLedgerBackupDB = {} end

    local _, migrateStatus = ns.Migrations.Migrate(FellowshipLedgerDB)
    ns.db = FellowshipLedgerDB
    ns.dbIsNewer = migrateStatus == "newer"
    ns.db.settings = ns.SettingsDefaults.Ensure(ns.db.settings or {})
    ns.db.characters = ns.db.characters or {}
    ns.db.friends = ns.db.friends or {}
    ns.db.blocklist = ns.db.blocklist or {}
    ns.db.dev = ns.db.dev or {}

    touchPersistProbe(ns.db.dev, "persistProbe")
    touchPersistProbe(FellowshipLedgerBackupDB, "persistProbe")

    ns.supported = ns.FlavorLogic.IsSupported(Compat.flavor)
end

local function offerRestore()
    local state = ns.Store.backupState
    if state ~= "missing" and state ~= "older" then return end
    local backup = FellowshipLedgerBackupDB
    local when = date("%Y-%m-%d %H:%M", backup.savedAt or 0)
    local text = (state == "missing" and L.RESTORE_PROMPT_MISSING or L.RESTORE_PROMPT_OLDER):format(when)
    Log.Warn(text)
    ns.Widgets.Confirm(text, L.RESTORE_YES, L.RESTORE_NO,
        function() ns.Store.Restore() end,
        function() Log.Info(L.RESTORE_SKIPPED) end)
end

function handlers.PLAYER_LOGIN()
    if not ns.db then return end
    if not ns.supported then
        Log.Warn(L.UNKNOWN_FLAVOR, tostring(Compat.interface))
    elseif Compat.tocFlavor ~= Compat.flavor then
        Log.Warn(L.FLAVOR_MISMATCH, tostring(Compat.flavor), tostring(Compat.tocFlavor))
    end
    Log.Info(L.LOADED, ns.VERSION, tostring(Compat.flavor))

    -- The code was built on retail verify results; nag on Forever until a Forever report exists.
    if Compat.flavor == ns.FlavorLogic.FOREVER and not (ns.db.verify and ns.db.verify.flavor == ns.FlavorLogic.FOREVER) then
        Log.Warn(L.FOREVER_VERIFY_REMINDER)
    end

    local probe = ns.db.dev.probe
    if probe and probe.enabled then ns.Probe.Start(true) end

    if not ns.supported or ns.dbIsNewer then
        if ns.dbIsNewer then Log.Warn(L.DB_NEWER) end
        return -- diagnostics only: no tracking
    end

    local ok, err = pcall(function()
        ns.Store.Login()
        ns.Trackers.RegisterAll()
        ns.Trackers.LoginAll()
        ns.Activity.Start()
    end)
    if not ok then
        Log.Warn(L.TRACKING_FAILED, tostring(err))
        return
    end
    ns.tracking = true
    offerRestore()

    -- Window extras: each is optional and guarded, and says so in chat if it fails.
    local function step(name, fn)
        local ok, err = pcall(fn)
        if not ok then Log.Warn(L.STARTUP_STEP_FAILED, name, tostring(err)) end
    end
    step("sharing", ns.Sync.Start)
    step("minimap button", ns.MinimapButton.Update)
    step("options page", ns.OptionsPanel.Register)
    ns.welcomeStep = function()
        step("welcome panel", ns.Welcome.MaybeShow)
        ns.Events.After(4, function() step("new character check", ns.StalePrompt.MaybeShow) end)
    end
    if not ns.pewRegistered then ns.Events.After(3, ns.welcomeStep) end
    if ns.Store.newSession and ns.Store.previousSession and ns.db.settings.sessionSummary then
        local title, lines = ns.Summary.Session(ns.Store.previousSession, L, date)
        ns.Toast.Show(title, lines)
    end
end

function handlers.PLAYER_LOGOUT()
    if not ns.db then return end
    if ns.tracking then pcall(ns.Store.Logout) end
    local t = time()
    if ns.db.dev.persistProbe then ns.db.dev.persistProbe.lastLogout = t end
    if type(FellowshipLedgerBackupDB) == "table" and FellowshipLedgerBackupDB.persistProbe then
        FellowshipLedgerBackupDB.persistProbe.lastLogout = t
    end
end

-- The welcome panel waits until the loading screen is over: windows that close
-- with Escape appear to be closed while the world loads, so showing it at
-- PLAYER_LOGIN was not reliable (Austin never saw it on retail).
local welcomeQueued = false
function handlers.PLAYER_ENTERING_WORLD()
    if welcomeQueued or not ns.welcomeStep then return end
    welcomeQueued = true
    ns.Events.After(3, ns.welcomeStep)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
ns.pewRegistered = pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD") -- only used to delay the welcome panel

-- Slash commands ------------------------------------------------------------

local HELP = { "HELP_OPEN", "HELP_SUMMARY", "HELP_FAKE", "HELP_EXPORT", "HELP_VERIFY", "HELP_VERIFY_SHOW", "HELP_PROBE", "HELP_DEBUG",
    "HELP_SYNC", "HELP_FRIENDS", "HELP_COMMS", "HELP_COMMTEST", "HELP_TEST", "HELP_WELCOME", "HELP_RESTORE", "HELP_SHOTS", "HELP_VERSION" }

local function printHelp()
    Log.Info(L.HELP_HEADER)
    for _, key in ipairs(HELP) do Log.Info(L[key]) end
end

local commands = {}

commands[""] = function()
    if not ns.tracking then printHelp() return end
    ns.MainWindow.Toggle()
end

commands.help = printHelp

function commands.verify(rest)
    if rest == "show" then ns.Verify.Show() else ns.Verify.Run() end
end

function commands.probe(rest)
    if rest == "on" then ns.Probe.Start(false)
    elseif rest == "off" then ns.Probe.Stop()
    elseif rest == "clear" then ns.Probe.Clear()
    else Log.Info(L.HELP_PROBE) end
end

function commands.debug()
    ns.db.settings.debug = not ns.db.settings.debug
    Log.Info(ns.db.settings.debug and L.DEBUG_ON or L.DEBUG_OFF)
    if ns.db.settings.debug then ns.EventLog.Show() else ns.EventLog.Hide() end
end

function commands.export()
    if ns.tracking then ns.Store.Tick() end
    local text = ns.Export.Build(ns.db, tostring(Compat.flavor), date("%Y-%m-%d %H:%M"))
    ns.CopyWindow:Show(L.EXPORT_TITLE, text)
end

function commands.summary(rest)
    if not ns.tracking then return end
    ns.Store.Tick()
    local s = ns.Store.previousSession or ns.Store.session
    if rest == "now" then s = ns.Store.session end
    local title, lines = ns.Summary.Session(s, L, date)
    ns.Toast.Show(title, lines)
end

function commands.fake(rest)
    if rest == "off" then
        ns.Data.DisableFake()
        Log.Info(L.FAKE_OFF)
    else
        ns.Data.EnableFake()
        Log.Info(L.FAKE_ON)
        ns.MainWindow.Open("me")
    end
    ns.MainWindow.Refresh()
end

function commands.sync()
    if not ns.tracking then return end
    local n = ns.Sync.SyncAll(true)
    Log.Info(L.SYNC_STARTED, n)
end

function commands.comms(rest)
    local size = rest and tonumber(rest:match("^size%s+(%d+)$"))
    if size then
        ns.db.settings.commsChunk = math.max(ns.Codec.MIN_CHUNK, math.min(ns.Codec.MAX_CHUNK, size))
        Log.Info(L.COMMS_SIZE_SET, ns.db.settings.commsChunk)
        return
    end
    local T = ns.Transport
    local online = 0
    for _, p in pairs(ns.Friends.peers) do if p.online then online = online + 1 end end
    Log.Info(L.COMMS_STATUS, tostring(T.Prefix()), T.ChunkSize(), #T.queue, T.stats.sent, T.stats.retried, T.stats.failed,
        T.stats.received, T.stats.dropped, online, tostring(T.Blocked() or "-"))
    if ns.Compat.disabled.comms then Log.Info(L.COMMS_OFF_WHY, "comms", tostring(ns.Compat.disabled.comms)) end
    if ns.Compat.disabled.friends then Log.Info(L.COMMS_OFF_WHY, "friends", tostring(ns.Compat.disabled.friends)) end
    if T.lastError then Log.Info(L.COMMS_LAST_ERROR, T.lastError) end
    local results = {}
    for name, n in pairs(T.stats.results) do results[#results + 1] = name .. "=" .. n end
    table.sort(results)
    if #results > 0 then Log.Info(L.COMMS_RESULTS, table.concat(results, " ")) end
    for id, p in pairs(ns.Friends.peers) do
        if p.online then Log.Info(L.COMMS_PEER_LINE, id, tostring(p.transport), tostring(p.target)) end
    end
end

function commands.friends()
    if not ns.tracking then return end
    ns.db.dev.friends = ns.Friends.Report()
    ns.CopyWindow:Show(L.FRIENDS_REPORT_TITLE, ns.db.dev.friends)
end

function commands.commtest()
    if not ns.tracking then return end
    ns.Sync.CommTest()
end

function commands.welcome()
    ns.Welcome.Show()
end

function commands.test()
    ns.SelfTest.Run()
end

function commands.restore()
    if not ns.tracking then return end
    if not ns.Store.Restore() then Log.Info(L.RESTORE_NONE) end
end

function commands.shots()
    ns.Screenshots.Run()
end

function commands.version()
    Log.Info(L.VERSION_LINE, ns.VERSION, tostring(Compat.flavor), tostring(Compat.tocFlavor),
        tostring(Compat.interface), tostring(Compat.version) .. " (" .. tostring(Compat.build) .. ")")
end

local function onSlash(msg)
    if not ns.db then return end
    local cmd, rest = ns.util.splitCommand(msg)
    local fn = commands[cmd]
    if fn then
        local ok, err = pcall(fn, rest)
        if not ok then Log.Warn("/fl %s failed: %s", cmd, tostring(err)) end
    else
        printHelp()
    end
end

SLASH_FELLOWSHIPLEDGER1 = "/fl"
SLASH_FELLOWSHIPLEDGER2 = "/fellowshipledger"
SlashCmdList["FELLOWSHIPLEDGER"] = onSlash
