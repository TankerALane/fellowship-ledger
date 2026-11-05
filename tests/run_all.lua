-- tests/run_all.lua
-- Usage (from the repo root): luajit tests/run_all.lua
-- or use tools/run_tests.ps1, which finds the interpreter for you.

local script = arg and arg[0] or "tests/run_all.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."

package.path = root .. "/tests/?.lua;" .. package.path
local H = require("harness")
H.ROOT = root

local FILES = {
    "test_purity",
    "test_namespace",
    "test_locale",
    "test_flavor",
    "test_migrations",
    "test_clock",
    "test_days_sessions",
    "test_format_misc",
    "test_verify_report",
    "test_verify_checks",
    "test_toc",
    "test_runtime_smoke",
    "test_tracking_smoke",
    "test_locale_keys",
    "test_phase2_models",
    "test_phase2_ui",
    "test_codec",
    "test_sync",
    "test_phase5",
    "test_details",
    "test_chains",
    "test_stats",
    "test_friend_details",
    "test_dungeon_bosses",
}

for _, name in ipairs(FILES) do
    H.currentFile = name
    local chunk, err = loadfile(root .. "/tests/" .. name .. ".lua")
    if not chunk then
        H.test("load " .. name, function() error(err) end)
    else
        chunk(H)
    end
end

local ok = H.run()
os.exit(ok and 0 or 1)
