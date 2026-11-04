-- Debug/SelfTest.lua
-- /fl test: quick in-game self-tests (schema, time math, date math with the real
-- client clock, export, the Me tab model, and a UI smoke test). They complement
-- the unit tests by running inside the real client.

local _, ns = ...
local L = ns.L

local SelfTest = {}
ns.SelfTest = SelfTest

local cases = {
    { "schema migrates a fresh table", function()
        local db = {}
        ns.Migrations.Migrate(db)
        assert(db.schemaVersion == ns.Migrations.CURRENT and type(db.characters) == "table")
    end },
    { "clock: 10m 23s active of 14m 02s", function()
        local c = ns.Clock.New(0)
        for t = 20, 623, 20 do ns.Clock.Touch(c, t) end
        ns.Clock.Touch(c, 623)
        ns.Clock.Idle(c, 623)
        ns.Clock.Advance(c, 842)
        local line = ns.Format.LevelLine({ from = 1, to = 2, active = c.active, total = c.played })
        assert(line == "1 -> 2: 10m 23s (total 14m 02s)", line)
    end },
    { "client date math (time/date tables)", function()
        local today = ns.Days.Key(time(), date)
        assert(today:match("^%d%d%d%d%-%d%d%-%d%d$"), today)
        local back = ns.Days.Shift(today, -6, time, date)
        assert(ns.Days.Shift(back, 6, time, date) == today)
    end },
    { "session split rule", function()
        assert(not ns.Sessions.ShouldStartNew(1000, 1010))
        assert(ns.Sessions.ShouldStartNew(1000, 4000))
    end },
    { "flavor detected", function()
        assert(ns.FlavorLogic.IsSupported(ns.Compat.flavor), tostring(ns.Compat.flavor))
    end },
    { "current character loaded", function()
        assert(ns.Store.char and ns.Store.key and ns.Store.session, "no character")
    end },
    { "export builds", function()
        local text = ns.Export.Build(ns.db, ns.Compat.flavor, date("%Y-%m-%d %H:%M"))
        assert(text:find("^FLX1"))
    end },
    { "Me tab model builds", function()
        local rows = ns.MeModel.Build(ns.db.characters, "all", ns.Store.Today(), time, date)
        assert(#rows >= 1)
    end },
    { "UI: main window opens and closes", function()
        local wasShown = ns.MainWindow.frame and ns.MainWindow.frame:IsShown()
        assert(ns.MainWindow.Ensure(), "window failed to build")
        ns.MainWindow.frame:Show()
        ns.MainWindow.Select("me")
        if not wasShown then ns.MainWindow.frame:Hide() end
    end },
}

function SelfTest.Run()
    local lines, failed = {}, 0
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2])
        if ok then
            lines[#lines + 1] = "PASS " .. case[1]
        else
            failed = failed + 1
            lines[#lines + 1] = "FAIL " .. case[1] .. ": " .. tostring(err)
        end
    end
    local disabled = {}
    for feature, reason in pairs(ns.Compat.disabled) do disabled[#disabled + 1] = feature .. " (" .. reason .. ")" end
    table.sort(disabled)
    table.insert(lines, 1, string.format("Fellowship Ledger self-test %s | %s | %d/%d passed", ns.VERSION,
        tostring(ns.Compat.flavor), #cases - failed, #cases))
    lines[#lines + 1] = "disabled features: " .. (#disabled > 0 and table.concat(disabled, "; ") or "none")
    ns.Log.Info(L.SELFTEST_DONE, #cases - failed, #cases)
    ns.CopyWindow:Show(L.SELFTEST_TITLE, table.concat(lines, "\n"))
    return failed == 0
end
