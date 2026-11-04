local H = ...

H.test("interface numbers map to flavors", function()
    local F = H.pureNamespace().FlavorLogic
    H.eq(F.FromInterface(16001), "Forever")
    H.eq(F.FromInterface("16001"), "Forever")
    H.eq(F.FromInterface(16999), "Forever")
    H.eq(F.FromInterface(120105), "Retail")
    H.eq(F.FromInterface(120107), "Retail")
    H.eq(F.FromInterface(130000), "Retail")
end)

H.test("classic flavors and junk are unknown", function()
    local F = H.pureNamespace().FlavorLogic
    for _, n in ipairs({ 11509, 20506, 38000, 50504, 15999, 17000, 0 }) do
        H.eq(F.FromInterface(n), "Unknown", "interface " .. n)
    end
    H.eq(F.FromInterface(nil), "Unknown")
    H.eq(F.FromInterface("abc"), "Unknown")
end)

H.test("each flavor has its own prefix and code", function()
    local F = H.pureNamespace().FlavorLogic
    H.ok(F.PREFIX.Forever ~= F.PREFIX.Retail)
    H.ok(F.CODE.Forever ~= F.CODE.Retail)
    H.ok(#F.PREFIX.Forever <= 16, "addon prefixes are limited to 16 characters")
end)

H.test("payload flavor codes never cross", function()
    local F = H.pureNamespace().FlavorLogic
    H.ok(F.Matches("Forever", "F"))
    H.ok(F.Matches("Retail", "R"))
    H.ok(not F.Matches("Forever", "R"))
    H.ok(not F.Matches("Retail", "F"))
    H.ok(not F.Matches("Unknown", "F"))
    H.ok(not F.Matches("Forever", nil))
end)
