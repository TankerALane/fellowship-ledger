-- Core/Init.lua
-- Startup: saved variables, migrations, flavor detection, slash commands.
-- Loaded last, so every other module already exists on `ns`.

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
    -- A db from a newer build may lack nothing we need, but make sure our dev area exists.
    ns.db.settings = ns.db.settings or {}
    ns.db.dev = ns.db.dev or {}

    touchPersistProbe(ns.db.dev, "persistProbe")
    touchPersistProbe(FellowshipLedgerBackupDB, "persistProbe")

    ns.supported = ns.FlavorLogic.IsSupported(Compat.flavor)
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
end

function handlers.PLAYER_LOGOUT()
    if not ns.db then return end
    local now = time()
    if ns.db.dev.persistProbe then ns.db.dev.persistProbe.lastLogout = now end
    if FellowshipLedgerBackupDB.persistProbe then FellowshipLedgerBackupDB.persistProbe.lastLogout = now end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

-- Slash commands ------------------------------------------------------------

local function printHelp()
    Log.Info(L.HELP_HEADER)
    Log.Info(L.HELP_VERIFY)
    Log.Info(L.HELP_VERIFY_SHOW)
    Log.Info(L.HELP_PROBE)
    Log.Info(L.HELP_DEBUG)
    Log.Info(L.HELP_VERSION)
end

local commands = {}

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
