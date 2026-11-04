local H = ...

H.test("continuous activity counts as active and played", function()
    local C = H.pureNamespace().Clock
    local c = C.New(1000)
    for t = 1030, 1600, 30 do C.Touch(c, t) end
    H.eq(c.played, 600)
    H.eq(c.active, 600)
end)

H.test("a short quiet stretch counts once activity resumes", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    local dp, da = C.Advance(c, 200)
    H.eq(dp, 200); H.eq(da, 0)
    H.eq(C.ActiveNow(c), 200, "shown live while pending")
    dp, da = C.Touch(c, 250)
    H.eq(da, 250)
    H.eq(c.active, 250)
end)

H.test("a quiet stretch longer than 5 minutes is removed entirely", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    for t = 30, 600, 30 do C.Advance(c, t) end
    H.eq(c.played, 600)
    H.eq(c.active, 0)
    H.eq(C.ActiveNow(c), 0)
    C.Touch(c, 660)  -- back at the keyboard
    H.eq(c.active, 0)
    C.Touch(c, 720)
    H.eq(c.active, 60)
end)

H.test("exactly 5 minutes quiet still counts; one tick more does not", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    C.Advance(c, 300)
    C.Touch(c, 300)
    H.eq(c.active, 300)
    local d = C.New(0)
    C.Advance(d, 300)
    C.Advance(d, 301)
    C.Touch(d, 301)
    H.eq(d.active, 0)
end)

H.test("typed /afk right after activity keeps that time", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    for t = 30, 90, 30 do C.Touch(c, t) end
    C.Idle(c, 100)
    H.eq(c.active, 100)
    C.Advance(c, 250)
    H.eq(c.active, 100)
    H.eq(c.played, 250)
    C.Touch(c, 300)
    C.Touch(c, 360)
    H.eq(c.active, 160)
end)

H.test("auto-AFK after a quiet stretch keeps none of it", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    C.Touch(c, 30)
    C.Advance(c, 200)
    C.Idle(c, 290) -- quiet since 30: more than AFK_COMMIT
    H.eq(c.active, 30)
    C.Advance(c, 600)
    H.eq(c.active, 30)
    H.eq(c.played, 600)
end)

H.test("resume after load ignores the offline gap and commits reload-pending time", function()
    local C = H.pureNamespace().Clock
    local c = C.New(0)
    C.Touch(c, 100)
    C.Advance(c, 110)
    local _, da = C.Resume(c, 100000)
    H.eq(da, 10)
    C.Touch(c, 100060)
    H.eq(c.played, 170)
    H.eq(c.active, 170)
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
    for t = 20, 623, 20 do C.Touch(c, t) end
    C.Touch(c, 623)
    C.Idle(c, 623)
    C.Advance(c, 842)
    H.eq(F.LevelLine({ from = 1, to = 2, active = c.active, total = c.played }), "1 -> 2: 10m 23s (total 14m 02s)")
end)

H.test("old saved clocks without a pending field still work", function()
    local C = H.pureNamespace().Clock
    local c = { played = 50, active = 40, last = 0, lastActivity = 0 }
    C.Advance(c, 30)
    C.Touch(c, 40)
    H.eq(c.active, 80)
end)
