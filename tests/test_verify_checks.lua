-- Keeps VerifyChecks.lua, Verify.lua and docs/API-VERIFICATION.md in step.
local H = ...

local KINDS = { api = true, event = true, custom = true, manual = true }

H.test("check ids are unique and well formed", function()
    local checks = H.pureNamespace().VerifyChecks
    local seen = {}
    for _, c in ipairs(checks) do
        H.ok(not seen[c.id], "duplicate id " .. c.id)
        seen[c.id] = true
        H.ok(KINDS[c.kind], "bad kind for " .. c.id)
        H.ok(type(c.area) == "string" and c.area ~= "", "area missing for " .. c.id)
        H.ok(type(c.why) == "string" and c.why ~= "", "why missing for " .. c.id)
        if c.kind == "event" then H.ok(c.id:find("^ev:[A-Z_]+$"), "event id format " .. c.id) end
        if c.kind == "custom" then H.ok(c.id:find("^x:"), "custom id format " .. c.id) end
        if c.kind == "manual" then H.ok(c.id:find("^m:"), "manual id format " .. c.id) end
        if c.kind == "api" then H.ok(c.id:find("^[%w_][%w_%.]*$"), "api path format " .. c.id) end
        if c.kind == "custom" or c.kind == "manual" then
            H.ok(type(c.test) == "string" and c.test ~= "", "test text missing for " .. c.id)
        end
    end
end)

H.test("never probes the combat log or player chat", function()
    local checks = H.pureNamespace().VerifyChecks
    for _, c in ipairs(checks) do
        H.ok(c.id ~= "ev:COMBAT_LOG_EVENT_UNFILTERED", "combat log is off limits")
        if c.id:find("^ev:CHAT_MSG_") or c.id:find("^ev:BN_CHAT_MSG_") then
            -- The one exception (D-111): system lines, for "<dungeon> has been reset."
            H.ok(c.id:find("ADDON") or c.id == "ev:CHAT_MSG_SYSTEM", "only addon-message chat events allowed: " .. c.id)
            H.eq(c.noargs, true, c.id .. " must not store arguments")
            if c.id == "ev:CHAT_MSG_SYSTEM" then H.eq(c.probe, false, "the probe never listens to system lines") end
        end
    end
end)

H.test("the addon's code reads no chat but addon messages and the system reset line", function()
    local allowed = { CHAT_MSG_ADDON = true, BN_CHAT_MSG_ADDON = true, CHAT_MSG_ADDON_LOGGED = true }
    local seen, files = {}, 0
    for line in H.readFile("FellowshipLedger/FellowshipLedger_Forever.toc"):gmatch("[^\r\n]+") do
        local rel = line:match("^([%w_/\\]+%.lua)%s*$")
        if rel then
            local f = "FellowshipLedger/" .. rel:gsub("\\", "/")
            files = files + 1
            for ev in H.readFile(f):gmatch("[%w_]*CHAT_MSG_[%u_]+") do
                if not allowed[ev] then seen[#seen + 1] = f .. ": " .. ev end
            end
        end
    end
    H.ok(files > 20, "read the addon's files from the TOC")
    for _, s in ipairs(seen) do
        H.ok(s:find("Trackers/Dungeons.lua: CHAT_MSG_SYSTEM", 1, true) or s:find("Debug/VerifyChecks.lua: CHAT_MSG_SYSTEM", 1, true), "chat event outside the allowed list: " .. s)
    end
end)

H.test("every custom check has an implementation in Verify.lua", function()
    local checks = H.pureNamespace().VerifyChecks
    local src = H.readFile("FellowshipLedger/Debug/Verify.lua")
    for _, c in ipairs(checks) do
        if c.kind == "custom" then
            H.ok(src:find('custom["' .. c.id .. '"]', 1, true), "no implementation for " .. c.id)
        end
    end
end)

H.test("every check appears in docs/API-VERIFICATION.md", function()
    local checks = H.pureNamespace().VerifyChecks
    local doc = H.readFile("docs/API-VERIFICATION.md")
    for _, c in ipairs(checks) do
        H.ok(doc:find("`" .. c.id .. "`", 1, true), c.id .. " missing from API-VERIFICATION.md (run tools/gen_verify_doc.py)")
    end
end)
