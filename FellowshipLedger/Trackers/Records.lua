-- Trackers/Records.lua
-- Personal bests (D-115), kept up to date. At login every character's data is folded
-- into its own store (char.bests) and the all-characters store (db.bests) without any
-- notice; after that the character being played is checked every minute, and a record
-- of all your characters that is beaten gives a "New personal best" notice.

local _, ns = ...
local L = ns.L
local Bests = ns.Bests

local Records = {}
ns.Records = Records

Records.EVERY = 60

local function fmt() return { Duration = ns.Format.Duration, Number = ns.Format.Number } end

-- Fold one character in. Returns the all-characters records it beat.
function Records.Fold(key, char)
    char.bests = Bests.Ensure(char.bests)
    Bests.Update(char.bests, char, key, false)
    char.bests.filled = true
    return Bests.Update(ns.db.bests, char, key, true)
end

function Records.Check()
    local key, char = ns.Store.key, ns.Store.char
    if not (key and char) then return {} end
    local beaten = Records.Fold(key, char)
    if #beaten > 0 and ns.db.settings.bestToasts ~= false then
        local lines = {}
        for _, b in ipairs(beaten) do lines[#lines + 1] = Bests.Text(b, L, fmt()) end
        ns.Toast.Show(L.BEST_TITLE, lines, { onClick = function() Records.Open() end })
    end
    return beaten
end

-- Open the Bests view of the character being played.
function Records.Open()
    if ns.MeTab and ns.MeTab.OpenView then ns.MeTab.OpenView(ns.Store.key, "bests") end
end

function Records.Start()
    ns.db.bests = Bests.Ensure(ns.db.bests)
    for key, char in pairs(ns.db.characters) do Records.Fold(key, char) end
    ns.db.bests.filled = true
    ns.Events.Every(Records.EVERY, "bests", function() pcall(Records.Check) end)
end
