local H = ...

H.test("continuous activity counts as active and played", function()
    local C = H.pureNamespace().Clock
    local c = C.New(1000)
    for t = 1030, 1600, 30 do C.Touch(c, t) end
    H.eq(c.played, 600)
    H.eq(c.active, 600)
end)

H.test("quiet time counts for 5 minutes, then stops", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    local dp, da = C.Advance(c, 600) -- 10 minutes with no activity after the start
    H.eq(dp, 600)
    H.eq(da, 300)
    H.eq(c.active, 300)
    C.Touch(c, 660) -- activity again: the 60 s since 600 were idle
    H.eq(c.active, 300)
    C.Advance(c, 720)
    H.eq(c.active, 360)
    H.eq(c.played, 720)
end)

H.test("idle stretch split over many ticks gives the same answer", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    for t = 30, 600, 30 do C.Advance(c, t) end
    H.eq(c.active, 300)
    H.eq(c.played, 600)
end)

H.test("AFK stops active time at once", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    C.Idle(c, 100)
    C.Advance(c, 250)
    H.eq(c.active, 100)
    H.eq(c.played, 250)
    C.Touch(c, 300)
    C.Advance(c, 360)
    H.eq(c.active, 160)
end)

H.test("resume after load ignores the offline gap", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    C.Touch(c, 100)
    C.Resume(c, 100000)
    C.Touch(c, 100060)
    H.eq(c.played, 160)
    H.eq(c.active, 160)
end)

H.test("a huge jump between ticks counts nothing; time never runs backwards", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    local dp, da = C.Advance(c, 5000)
    H.eq(dp, 0); H.eq(da, 0)
    dp = C.Advance(c, 4000)
    H.eq(dp, 0)
    H.eq(c.played, 0)
end)

H.test("level example: 10m 23s active inside 14m 02s total", function()
    local ns = H.pureNamespace()
    local C, F = ns.Clock, ns.Format
    local c = C.New(0)
    for t = 20, 623, 20 do C.Touch(c, t) end -- active until 620
    C.Touch(c, 623)
    C.Idle(c, 623)                           -- AFK for the rest
    C.Advance(c, 842)
    H.eq(F.LevelLine({ from = 1, to = 2, active = c.active, total = c.played }), "1 -> 2: 10m 23s (total 14m 02s)")
end)
