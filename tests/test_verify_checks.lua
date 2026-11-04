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
            H.ok(c.id:find("ADDON"), "only addon-message chat events allowed: " .. c.id)
            H.eq(c.noargs, true, c.id .. " must not store arguments")
        end
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
