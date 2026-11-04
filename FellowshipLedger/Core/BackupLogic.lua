-- Core/BackupLogic.lua
-- PURE: no WoW globals. Decides whether the main saved data looks lost, compared
-- with the per-character backup (a different file on disk, see DECISIONS D-015).
--
-- Backup shape (FellowshipLedgerBackupDB, saved per character):
--   { savedAt, schemaVersion, key, character = <copy>, settings = <copy> }

local _, ns = ...

local BackupLogic = {}
ns.BackupLogic = BackupLogic

BackupLogic.SLACK = 120 -- seconds of difference tolerated between the two saves

function BackupLogic.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[BackupLogic.DeepCopy(k, seen)] = BackupLogic.DeepCopy(v, seen) end
    return out
end

local function hasData(char)
    return type(char) == "table" and (next(char.days or {}) ~= nil or next(char.levels or {}) ~= nil
        or #(char.sessions or {}) > 0)
end

-- Returns one of:
--   "ok"       nothing to do
--   "nobackup" no usable backup yet
--   "missing"  the main data has no (or an empty) record for this character, the backup has data
--   "older"    the main record was saved clearly before the backup (its last save was lost)
function BackupLogic.Assess(mainChar, backup, key)
    if type(backup) ~= "table" or backup.key ~= key or not hasData(backup.character) then
        return "nobackup"
    end
    if not hasData(mainChar) then return "missing" end
    local mainSaved = mainChar.savedAt or 0
    if (backup.savedAt or 0) > mainSaved + BackupLogic.SLACK then return "older" end
    return "ok"
end

function BackupLogic.Make(key, char, settings, now, schemaVersion)
    return {
        savedAt = now,
        schemaVersion = schemaVersion,
        key = key,
        character = BackupLogic.DeepCopy(char),
        settings = BackupLogic.DeepCopy(settings),
    }
end
