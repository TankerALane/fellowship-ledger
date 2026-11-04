-- Debug/VerifyReport.lua
-- PURE: must not touch WoW globals at load time.
-- Turns verify results (and probe counts) into a compact text report that Austin
-- can paste back. Failures first, then details, then a compact list of passes.

local _, ns = ...

local VerifyReport = {}
ns.VerifyReport = VerifyReport

VerifyReport.STATUSES = { "PASS", "FAIL", "ERROR", "INFO", "MANUAL" }
VerifyReport.LINE_WIDTH = 160

function VerifyReport.Count(results)
    local counts = { PASS = 0, FAIL = 0, ERROR = 0, INFO = 0, MANUAL = 0 }
    for _, r in ipairs(results) do
        counts[r.status] = (counts[r.status] or 0) + 1
    end
    return counts
end

-- Join items with ", " into lines no wider than `width`, each line prefixed.
function VerifyReport.Wrap(prefix, items, width)
    width = width or VerifyReport.LINE_WIDTH
    local lines, current = {}, prefix
    local fresh = true
    for _, item in ipairs(items) do
        local piece = fresh and item or (", " .. item)
        if not fresh and #current + #piece > width then
            lines[#lines + 1] = current .. ","
            current = prefix .. item
        else
            current = current .. piece
        end
        fresh = false
    end
    if not fresh then lines[#lines + 1] = current end
    return lines
end

local function line(r)
    if r.detail and r.detail ~= "" then
        return r.status .. " " .. r.id .. ": " .. r.detail
    end
    return r.status .. " " .. r.id
end

-- meta: { version, flavor, tocFlavor, interface, version_string, build, at }
-- results: array of { id, kind, area, status, detail }
-- probe: nil or { enabled, since, events = { NAME = { count, samples = {...} } } }
function VerifyReport.Build(meta, results, probe)
    local out = {}
    local function add(s) out[#out + 1] = s end
    local counts = VerifyReport.Count(results)

    add("Fellowship Ledger verify report")
    add(string.format("addon=%s flavor=%s toc=%s interface=%s client=%s build=%s at=%s",
        tostring(meta.version), tostring(meta.flavor), tostring(meta.tocFlavor),
        tostring(meta.interface), tostring(meta.clientVersion), tostring(meta.build), tostring(meta.at)))
    add(string.format("summary pass=%d fail=%d error=%d info=%d manual=%d",
        counts.PASS, counts.FAIL, counts.ERROR, counts.INFO, counts.MANUAL))

    -- 1. Problems
    local problems = {}
    for _, r in ipairs(results) do
        if r.status == "FAIL" or r.status == "ERROR" then problems[#problems + 1] = r end
    end
    if #problems > 0 then
        add("-- problems")
        for _, r in ipairs(problems) do add(line(r)) end
    end

    -- 2. Custom checks (always shown with their detail) and info lines
    local details = {}
    for _, r in ipairs(results) do
        if r.kind == "custom" and r.status ~= "FAIL" and r.status ~= "ERROR" then
            details[#details + 1] = r
        end
    end
    if #details > 0 then
        add("-- details")
        for _, r in ipairs(details) do add(line(r)) end
    end

    -- 3. Manual checks
    local manual = {}
    for _, r in ipairs(results) do
        if r.status == "MANUAL" then manual[#manual + 1] = r.id end
    end
    if #manual > 0 then
        add("-- manual (check by eye, see docs/API-VERIFICATION.md)")
        for _, l in ipairs(VerifyReport.Wrap("MANUAL ", manual)) do add(l) end
    end

    -- 4. Compact passes
    local apiPass, eventPass = {}, {}
    for _, r in ipairs(results) do
        if r.status == "PASS" and r.kind == "api" then apiPass[#apiPass + 1] = r.id end
        if r.status == "PASS" and r.kind == "event" then eventPass[#eventPass + 1] = (r.id:gsub("^ev:", "")) end
    end
    if #apiPass > 0 then
        add("-- api pass")
        for _, l in ipairs(VerifyReport.Wrap("", apiPass)) do add(l) end
    end
    if #eventPass > 0 then
        add("-- event pass (exists; fired counts are under probe)")
        for _, l in ipairs(VerifyReport.Wrap("", eventPass)) do add(l) end
    end

    -- 5. Probe
    if probe and probe.events then
        local names = {}
        for name in pairs(probe.events) do names[#names + 1] = name end
        table.sort(names)
        add(string.format("-- probe (%s, since %s, %d events seen)",
            probe.enabled and "on" or "off", tostring(probe.since), #names))
        for _, name in ipairs(names) do
            local e = probe.events[name]
            local s = name .. "=" .. tostring(e.count or 0)
            if e.samples and #e.samples > 0 then
                s = s .. " | " .. table.concat(e.samples, " | ")
            end
            add(s)
        end
    end

    return table.concat(out, "\n"), counts
end

-- Turn event arguments into one short sample string. `describe` is a function that
-- makes a value printable without inspecting secrets (Compat.Describe in game).
function VerifyReport.Sample(describe, maxLen, ...)
    maxLen = maxLen or 120
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = describe((select(i, ...)))
    end
    local s = "(" .. table.concat(parts, ", ") .. ")"
    if #s > maxLen then s = s:sub(1, maxLen - 3) .. "..." end
    return s
end
