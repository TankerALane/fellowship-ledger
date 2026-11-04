-- Pure files must load with only standard Lua available.
local H = ...

for _, rel in ipairs(H.PURE_FILES) do
    H.test("pure at load time: " .. rel, function()
        -- Load prerequisites in order up to and including this file, all strict.
        local ns = {}
        for _, dep in ipairs(H.PURE_FILES) do
            H.loadAddonFile(dep, ns)
            if dep == rel then break end
        end
    end)
end

H.test("strict environment really rejects WoW globals", function()
    local env = H.strictEnv()
    H.fails(function() return env.CreateFrame end, "non%-standard global")
    H.fails(function() env.Foo = 1 end, "write of global")
end)
