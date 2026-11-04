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
