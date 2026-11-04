local H = ...

local function sample()
    return {
        { id = "GetBuildInfo", kind = "api", status = "PASS" },
        { id = "GetItemStats", kind = "api", status = "FAIL", detail = "is nil, expected function" },
        { id = "ev:PLAYER_LEVEL_UP", kind = "event", status = "PASS" },
        { id = "x:build.version", kind = "custom", status = "INFO", detail = "1.60.1 (70790)" },
        { id = "x:sv.persist", kind = "custom", status = "ERROR", detail = "boom" },
        { id = "m:toc.icon", kind = "manual", status = "MANUAL" },
    }
end

local META = { version = "0.0.1-dev", flavor = "Forever", tocFlavor = "Forever", interface = 16001,
    clientVersion = "1.60.1", build = "70790", at = "2026-11-04 10:00" }

H.test("Count tallies each status", function()
    local R = H.pureNamespace().VerifyReport
    local c = R.Count(sample())
    H.eq(c.PASS, 2); H.eq(c.FAIL, 1); H.eq(c.ERROR, 1); H.eq(c.INFO, 1); H.eq(c.MANUAL, 1)
end)

H.test("report lists problems before passes", function()
    local R = H.pureNamespace().VerifyReport
    local text = R.Build(META, sample())
    local problems = text:find("FAIL GetItemStats: is nil", 1, true)
    local passes = text:find("-- api pass", 1, true)
    H.ok(problems, "failure line present")
    H.ok(text:find("ERROR x:sv.persist: boom", 1, true), "error line present")
    H.ok(passes and problems < passes, "problems come first")
    H.ok(text:find("summary pass=2 fail=1 error=1 info=1 manual=1", 1, true))
    H.ok(text:find("interface=16001", 1, true))
end)

H.test("event passes drop the ev: prefix and custom details are shown", function()
    local R = H.pureNamespace().VerifyReport
    local text = R.Build(META, sample())
    H.ok(text:find("\nPLAYER_LEVEL_UP", 1, true))
    H.ok(text:find("INFO x:build.version: 1.60.1 (70790)", 1, true))
    H.ok(text:find("MANUAL m:toc.icon", 1, true))
end)

H.test("probe section lists events sorted with samples", function()
    local R = H.pureNamespace().VerifyReport
    local probe = { enabled = true, since = "2026-11-04 09:00", events = {
        ZONE_CHANGED = { count = 4, samples = {} },
        PLAYER_LEVEL_UP = { count = 1, samples = { "(5, 0)" } },
    } }
    local text = R.Build(META, sample(), probe)
    local a = text:find("PLAYER_LEVEL_UP=1 | (5, 0)", 1, true)
    local b = text:find("ZONE_CHANGED=4", 1, true)
    H.ok(a and b and a < b, "sorted, with samples")
    H.ok(text:find("-- probe (on, since 2026-11-04 09:00, 2 events seen)", 1, true))
end)

H.test("Wrap keeps lines within the width", function()
    local R = H.pureNamespace().VerifyReport
    local items = {}
    for i = 1, 50 do items[i] = "C_Something.Function" .. i end
    local lines = R.Wrap("", items, 80)
    H.ok(#lines > 1)
    for _, l in ipairs(lines) do H.ok(#l <= 81, "line too long: " .. #l) end
    H.eq(#R.Wrap("", {}, 80), 0)
end)

H.test("Sample describes args and truncates", function()
    local R = H.pureNamespace().VerifyReport
    H.eq(R.Sample(tostring, 120, 5, nil, "x"), "(5, nil, x)")
    local long = R.Sample(tostring, 20, string.rep("a", 50))
    H.eq(#long, 20)
    H.ok(long:sub(-3) == "...")
end)
