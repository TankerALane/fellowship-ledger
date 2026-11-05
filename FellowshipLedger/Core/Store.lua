-- Core/Store.lua
-- The current character's record, its clock and session, day buckets, the backup
-- and the restore prompt. Trackers write through Store.Count so that every number
-- lands in both today's bucket and the current session.

local _, ns = ...
local L = ns.L
local Clock, Days, Sessions, Character = ns.Clock, ns.Days, ns.Sessions, ns.Character
local BackupLogic = ns.BackupLogic

local Store = {}
ns.Store = Store

Store.char = nil     -- current character record
Store.key = nil      -- "Name-Realm"
Store.session = nil  -- current session (last entry of char.sessions)

local function now() return time() end
Store.Now = now

function Store.Today()
    return Days.Key(now(), date)
end

local function plain(v)
    if ns.Compat.IsSecret(v) then return nil end
    return v
end

local function readIdentity()
    local name, realm = UnitFullName("player")
    name = plain(name) or plain(UnitName("player"))
    realm = plain(realm)
    if not realm or realm == "" then
        local ok, r = ns.Compat.Call("identity", "GetNormalizedRealmName")
        realm = ok and r or (GetRealmName() or ""):gsub("%s", "")
    end
    return name, realm
end

local function refreshCharInfo(char)
    char.class = select(2, UnitClass("player"))
    char.race = select(2, UnitRace("player"))
    char.faction = UnitFactionGroup("player")
    char.level = plain(UnitLevel("player")) or char.level
end

local function startOrContinueSession(char, t)
    if #char.sessions == 0 or Sessions.ShouldStartNew(char.lastSeen, t) then
        char.nextSessionId = (char.nextSessionId or 0) + 1
        local s = Sessions.New(char.nextSessionId, t, { level = char.level, money = plain(GetMoney()) })
        char.sessions[#char.sessions + 1] = s
        Sessions.Prune(char.sessions, t)
        Store.newSession = true
        Store.previousSession = char.sessions[#char.sessions - 1]
    else
        Store.newSession = false
    end
    Store.session = char.sessions[#char.sessions]
end

local function prune(char, t)
    Days.Prune(char.days, Days.Key(t, date), Days.KEEP, time, date)
    Days.PruneList(char.questLog, "at", t, Character.QUEST_LOG_SECONDS)
    Days.PruneList(char.dungeons, "entered", t, Character.LIST_KEEP_SECONDS)
    Days.PruneList(char.deathLog, "at", t, Character.LIST_KEEP_SECONDS)
    Days.PruneList(char.partyLevels, "at", t, Character.LIST_KEEP_SECONDS)
end

-- Set up the current character. Called at PLAYER_LOGIN (also after /reload).
function Store.Login()
    local t = now()
    local db = ns.db
    local name, realm = readIdentity()
    Store.key = Character.Key(name, realm)

    -- Compare with the backup before touching anything.
    local backup = FellowshipLedgerBackupDB
    Store.backupState = BackupLogic.Assess(db.characters[Store.key], backup, Store.key)

    -- A character the ledger has never seen (and with no backup to restore): the
    -- new-character prompt may offer to remove characters not played for a while.
    Store.isNewCharacter = db.characters[Store.key] == nil and Store.backupState == "nobackup"
    if db.removed then Character.PruneRemoved(db.removed, t, Store.key) end
    local char = Character.Ensure(db.characters[Store.key] or {}, t)
    db.characters[Store.key] = char
    char.name, char.realm = name, realm
    -- On Forever characters have a first and a last name, and UnitFullName returns
    -- them in its name and realm slots (D-064): show both.
    char.display = ns.Compat.flavor == "Forever" and realm and realm ~= "" and (name .. " " .. realm) or nil
    refreshCharInfo(char)

    char.clock = char.clock or Clock.New(t)
    local _, resumed = Clock.Resume(char.clock, t)
    startOrContinueSession(char, t)
    char.lastSeen = t
    prune(char, t)

    Store.char = char
    Store.AddTime(0, resumed)
    return char
end

-- Add played/active seconds everywhere they are counted.
function Store.AddTime(dp, da)
    if dp <= 0 and da <= 0 then return end
    local char, s = Store.char, Store.session
    local day = Store.Today()
    if dp > 0 then Days.Add(char.days, day, "played", dp) end
    if da > 0 then Days.Add(char.days, day, "active", da) end
    s.played = s.played + dp
    s.active = s.active + da
end

function Store.Tick()
    local char = Store.char
    if not char then return end
    local t = now()
    Store.AddTime(Clock.Advance(char.clock, t))
    Store.session.stop = t
    Store.session.levelEnd = char.level
    char.lastSeen = t
end

function Store.Touch()
    local char = Store.char
    if not char then return end
    local t = now()
    Store.AddTime(Clock.Touch(char.clock, t))
    Store.session.stop = t
    char.lastSeen = t
end

function Store.Idle()
    if not Store.char then return end
    Store.AddTime(Clock.Idle(Store.char.clock, now()))
end

-- Count `n` (default 1) of `field` today and in this session.
function Store.Count(field, n)
    if not Store.char then return end
    n = n or 1
    Days.Add(Store.char.days, Store.Today(), field, n)
    Sessions.Add(Store.session, field, n)
end

-- Backup -------------------------------------------------------------------

function Store.WriteBackup()
    local char = Store.char
    if not char then return end
    local t = now()
    char.savedAt = t
    local probe = type(FellowshipLedgerBackupDB) == "table" and FellowshipLedgerBackupDB.persistProbe or nil
    FellowshipLedgerBackupDB = BackupLogic.Make(Store.key, char, ns.db.settings, t, ns.db.schemaVersion)
    FellowshipLedgerBackupDB.persistProbe = probe
end

function Store.Restore()
    local backup = FellowshipLedgerBackupDB
    if type(backup) ~= "table" or backup.key ~= Store.key or not backup.character then return false end
    ns.db.characters[Store.key] = BackupLogic.DeepCopy(backup.character)
    if not next(ns.db.settings) and type(backup.settings) == "table" then
        ns.db.settings = BackupLogic.DeepCopy(backup.settings)
    end
    Store.Login()
    Store.backupState = "ok"
    ns.Log.Info(L.RESTORE_DONE)
    return true
end

function Store.Logout()
    if not Store.char then return end
    Store.Tick()
    Store.WriteBackup()
end

-- Current zone name and map ID (either may be nil).
function Store.Zone()
    local ok, mapID = ns.Compat.Call("zones", "C_Map.GetBestMapForUnit", "player")
    mapID = ok and plain(mapID) or nil
    local zoneName
    if mapID then
        local okInfo, info = ns.Compat.Call("zones", "C_Map.GetMapInfo", mapID)
        zoneName = okInfo and type(info) == "table" and plain(info.name) or nil
    end
    if not zoneName then
        local okText, text = ns.Compat.Call("zones", "GetZoneText")
        zoneName = okText and plain(text) or nil
    end
    return zoneName, mapID
end
