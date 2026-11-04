-- Every L.KEY used in the addon must exist in the English strings, and dynamic
-- keys built from ids (charts, trackers, statuses, ...) must exist too.
local H = ...

local FILES = {}
for line in (H.readFile("FellowshipLedger/FellowshipLedger_Forever.toc") .. "\n"):gmatch("(.-)\r?\n") do
    if line ~= "" and not line:find("^#") then FILES[#FILES + 1] = (line:gsub("\\", "/")) end
end

H.test("every L.KEY used in the code has an English string", function()
    local ns = H.pureNamespace()
    local missing = {}
    for _, rel in ipairs(FILES) do
        local src = H.readFile("FellowshipLedger/" .. rel)
        for key in src:gmatch("L%.([%u_][%w_]*)") do
            if rawget(ns.L, key) == nil then missing[#missing + 1] = rel .. ": " .. key end
        end
    end
    H.eq(#missing, 0, "missing strings:\n" .. table.concat(missing, "\n"))
end)

H.test("dynamic keys exist", function()
    local ns = H.pureNamespace()
    local need = {}
    for _, t in ipairs(ns.TrackerList.ORDER) do
        need[#need + 1] = "TRACKER_" .. t.id
        need[#need + 1] = "STATUS_" .. t.status:upper()
    end
    for _, id in ipairs(ns.GraphModel.CHARTS) do
        need[#need + 1] = "CHART_" .. id:upper()
        need[#need + 1] = "CHART_" .. id:upper() .. "_HINT"
    end
    for _, k in ipairs({ "QUESTIE_MISSING", "QUESTIE_LOADING", "QUESTIE_READY", "QUESTIE_BROKEN", "SKIN_LEDGER", "SKIN_PLAIN",
        "FONT_SMALL", "FONT_NORMAL", "FONT_LARGE", "CHAIN_SOURCE_GAME", "CHAIN_SOURCE_QUESTIE", "TAB_ME", "TAB_FRIENDS",
        "TAB_GRAPHS", "TAB_SETTINGS", "RANGE_TODAY", "RANGE_WEEK", "RANGE_MONTH", "RANGE_ALL" }) do
        need[#need + 1] = k
    end
    for _, col in ipairs(ns.MeModel.COLUMNS) do need[#need + 1] = col.label end
    local missing = {}
    for _, k in ipairs(need) do if rawget(ns.L, k) == nil then missing[#missing + 1] = k end end
    H.eq(#missing, 0, "missing: " .. table.concat(missing, ", "))
end)
