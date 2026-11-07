-- Core/Summary.lua
-- PURE: no WoW globals. One-paragraph summary of a session, for the login toast
-- and /fl summary.

local _, ns = ...

local Summary = {}
ns.Summary = Summary

-- Returns a title and a list of short lines.
function Summary.Session(s, L, dateFn)
    local F = ns.Format
    local c = s.counts or {}
    local title = string.format(L.SUMMARY_TITLE, dateFn("%Y-%m-%d %H:%M", s.start))
    local lines = {
        string.format(L.SUMMARY_TIME, F.Duration(s.played or 0), F.Duration(s.active or 0)),
    }
    if (c.levels or 0) > 0 then
        lines[#lines + 1] = string.format(L.SUMMARY_LEVELS, c.levels, tostring(s.levelStart), tostring(s.levelEnd))
    end
    if (c.quests or 0) > 0 then lines[#lines + 1] = string.format(L.SUMMARY_QUESTS, c.quests) end
    if (c.dungeonsEntered or 0) > 0 then
        lines[#lines + 1] = string.format(L.SUMMARY_DUNGEONS, c.dungeonsCompleted or 0, c.dungeonsEntered)
    end
    if c.moneyNet and c.moneyNet ~= 0 then lines[#lines + 1] = string.format(L.SUMMARY_GOLD, F.Money(c.moneyNet, true)) end
    if (c.skillUps or 0) > 0 then lines[#lines + 1] = string.format(L.SUMMARY_SKILLUPS, c.skillUps) end
    if (c.deaths or 0) > 0 then lines[#lines + 1] = string.format(L.SUMMARY_DEATHS, c.deaths) end
    return title, lines
end

-- One line for the top of the Me tab (D-099): "This session: 1h 12m, 2 levels, ...".
-- nil before anything happened (under a minute played and nothing counted).
function Summary.Recap(s, L)
    if type(s) ~= "table" then return nil end
    local F = ns.Format
    local c = s.counts or {}
    local parts = {}
    local function add(n, one, many)
        if (n or 0) > 0 then parts[#parts + 1] = string.format(n == 1 and one or many, n) end
    end
    add(c.levels, L.RECAP_LEVEL, L.RECAP_LEVELS)
    add(c.quests, L.RECAP_QUEST, L.RECAP_QUESTS)
    add(c.dungeonsEntered, L.RECAP_DUNGEON, L.RECAP_DUNGEONS)
    if c.moneyNet and c.moneyNet ~= 0 then parts[#parts + 1] = F.Money(c.moneyNet, true) end
    add(c.deaths, L.RECAP_DEATH, L.RECAP_DEATHS)
    if (s.played or 0) < 60 and #parts == 0 then return nil end
    table.insert(parts, 1, F.Duration(s.played or 0))
    return string.format(L.RECAP, table.concat(parts, ", "))
end
