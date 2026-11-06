-- Debug/Screenshots.lua
-- /fl shots (D-088): screenshots for the addon page. Turns on the made-up data set
-- (/fl fake, so only fake names show), then walks through every tab, each with a
-- skin, with a character opened as a card and as a list, and takes one game
-- screenshot per step. Afterwards the skin, layout, tab, window size and fake-data
-- state are put back as they were. The window's place on screen is saved in
-- db.dev.shots so tools/crop_shots.py can cut each picture down to the window.

local _, ns = ...
local L = ns.L

local Shots = {}
ns.Screenshots = Shots

Shots.DELAY = 1.5          -- seconds for the window to redraw before each picture
Shots.WIDTH, Shots.HEIGHT = 1060, 640

-- The steps, in order. me/friends open the first fake character as a card or list.
Shots.PLAN = {
    { tab = "me", skin = "ledger", layout = "card", open = "me" },
    { tab = "me", skin = "leather", layout = "list", open = "me" },
    { tab = "friends", skin = "plain", layout = "card", open = "friend" },
    { tab = "graphs", skin = "ledger" },
    { tab = "settings", skin = "leather" },
    { tab = "me", skin = "plain", mode = "chains" },
}

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- Open one character on the Me or Friends tab (and only that one).
local function openCharacter(step)
    local me, friends = ns.MeTab.state, ns.FriendsTab.state
    for k in pairs(me.expanded) do me.expanded[k] = nil end
    for k in pairs(friends.expanded) do friends.expanded[k] = nil end
    me.mode = step.mode or "characters"
    if step.open == "me" then
        -- The highest-level character: the fullest card.
        local best, bestLevel
        for key, c in pairs(ns.Data.Characters()) do
            if not bestLevel or (c.level or 0) > bestLevel then best, bestLevel = key, c.level or 0 end
        end
        if best then me.expanded[best], me.detailView[best] = true, "overview" end
    elseif step.open == "friend" then
        local all = ns.Data.Friends()
        for _, id in ipairs(sortedKeys(all)) do
            local f = all[id]
            if f.kind == "bnet" then
                local charKey = sortedKeys(f.characters)[1]
                if charKey then
                    local openId = id .. "|" .. charKey
                    friends.expanded[openId], friends.detailView[openId] = true, "overview"
                end
                break
            end
        end
    end
end

-- Where the window is, in screen units (UIParent at scale 1 is 768 high); the crop
-- script scales these to the picture's pixels.
local function windowRect()
    local f = ns.MainWindow.frame
    local ok, left, top, right, bottom, scale, uiH, uiScale = pcall(function()
        return f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom(), f:GetEffectiveScale(),
            UIParent:GetHeight(), UIParent:GetEffectiveScale()
    end)
    if not ok then return nil end
    local n = function(v) return type(v) == "number" end
    if not (n(left) and n(top) and n(right) and n(bottom) and n(scale) and n(uiH) and n(uiScale)) then return nil end
    return { left = left * scale, top = top * scale, right = right * scale, bottom = bottom * scale, screen = uiH * uiScale }
end

local function restore(saved)
    local s = ns.db.settings
    s.skin, s.detailsLayout = saved.skin, saved.layout
    local me = ns.MeTab.state
    me.mode = saved.mode
    for k in pairs(me.expanded) do me.expanded[k] = nil end
    for k in pairs(ns.FriendsTab.state.expanded) do ns.FriendsTab.state.expanded[k] = nil end
    if not saved.fake then ns.Data.DisableFake() end
    Shots.active = false
    local f = ns.MainWindow.frame
    if f and saved.w then f:SetSize(saved.w, saved.h) end
    ns.Widgets.ApplySkin()
    ns.MainWindow.Select(saved.tab or "me")
end

function Shots.Run()
    if Shots.active then return end
    if not ns.Compat.Has("Screenshot") then
        ns.Log.Warn(L.SHOTS_NO_API)
        return
    end
    if not ns.MainWindow.Ensure() then return end
    local f = ns.MainWindow.frame
    local s = ns.db.settings
    local saved = { skin = s.skin, layout = s.detailsLayout, tab = ns.MainWindow.current, fake = ns.Data.IsFake(),
        mode = ns.MeTab.state.mode, w = f:GetWidth(), h = f:GetHeight() }
    if not saved.fake then ns.Data.EnableFake() end
    Shots.active = true
    f:Show()
    f:SetSize(Shots.WIDTH, Shots.HEIGHT)
    ns.db.dev.shots = { at = time(), steps = {} }
    ns.Log.Info(L.SHOTS_START, #Shots.PLAN)

    -- Any error puts the settings back rather than leaving a half state.
    local function safe(fn)
        return function()
            local ok, err = pcall(fn)
            if not ok then
                restore(saved)
                ns.Log.Warn(L.SHOTS_FAILED, tostring(err))
            end
        end
    end
    local i = 0
    local nextStep
    nextStep = safe(function()
        i = i + 1
        local step = Shots.PLAN[i]
        if not step then
            restore(saved)
            ns.Log.Info(L.SHOTS_DONE, #ns.db.dev.shots.steps)
            return
        end
        s.skin, s.detailsLayout = step.skin, step.layout or saved.layout
        openCharacter(step)
        ns.Widgets.ApplySkin()
        ns.MainWindow.Select(step.tab)
        ns.Events.After(Shots.DELAY, safe(function()
            local rect = windowRect()
            local ok = ns.Compat.Call("screenshots", "Screenshot")
            if not ok then
                restore(saved)
                return
            end
            local shots = ns.db.dev.shots.steps
            shots[#shots + 1] = { tab = step.tab, skin = step.skin, layout = step.layout, mode = step.mode, at = time(), rect = rect }
            -- Leave time for the picture to be written before the window changes.
            ns.Events.After(Shots.DELAY, nextStep)
        end))
    end)
    nextStep()
end
