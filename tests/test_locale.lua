local H = ...

H.test("known key returns English text", function()
    local ns = H.pureNamespace()
    H.eq(ns.L.ADDON_TITLE, "Fellowship Ledger")
end)

H.test("missing key falls back to the key itself", function()
    local ns = H.pureNamespace()
    H.eq(ns.L.SOME_MISSING_KEY, "SOME_MISSING_KEY")
end)

H.test("format strings accept their arguments", function()
    local ns = H.pureNamespace()
    H.eq(ns.L.LOADED:format("1.0", "Forever"), "The ledger is open (v1.0, Forever). Type /fl to open it, or /fl help for commands.")
    H.ok(ns.L.VERIFY_DONE:format(1, 2, 3, 4, 5))
    H.ok(ns.L.FEATURE_DISABLED:format("Quests", "missing"))
end)

H.test("later Set calls override earlier ones", function()
    local ns = H.pureNamespace()
    ns.Locale.Set({ ADDON_TITLE = "Grand Livre" })
    H.eq(ns.L.ADDON_TITLE, "Grand Livre")
end)
