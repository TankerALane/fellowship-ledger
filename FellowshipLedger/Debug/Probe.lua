-- Debug/Probe.lua
-- Quietly counts which of the candidate events (from VerifyChecks) actually fire,
-- and keeps the first few argument samples, so the verify report can show real
-- event arguments. Never registers chat events other than the two addon-message
-- events, and for those (and any check marked noargs) it stores counts only.

local _, ns = ...
local L = ns.L

local Probe = {}
ns.Probe = Probe

local MAX_SAMPLES = 3
local frame

local function state()
    local dev = ns.db.dev
    dev.probe = dev.probe or { enabled = false, events = {} }
    dev.probe.events = dev.probe.events or {}
    return dev.probe
end

-- Event checks that the probe should listen to: name -> { noargs = bool }
function Probe.Candidates()
    local list = {}
    for _, check in ipairs(ns.VerifyChecks) do
        if check.kind == "event" and check.probe ~= false then
            list[(check.id:gsub("^ev:", ""))] = { noargs = check.noargs == true }
        end
    end
    return list
end

local function onEvent(_, event, ...)
    local p = state()
    local e = p.events[event]
    if not e then
        e = { count = 0, samples = {} }
        p.events[event] = e
    end
    e.count = e.count + 1
    local candidate = Probe.candidates and Probe.candidates[event]
    if candidate and not candidate.noargs and #e.samples < MAX_SAMPLES then
        e.samples[#e.samples + 1] = ns.VerifyReport.Sample(ns.Compat.Describe, 120, ...)
    end
end

function Probe.Start(silent)
    local p = state()
    frame = frame or CreateFrame("Frame")
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", onEvent)
    Probe.candidates = Probe.Candidates()
    local n = 0
    for name in pairs(Probe.candidates) do
        if pcall(frame.RegisterEvent, frame, name) then n = n + 1 end
    end
    p.enabled = true
    p.since = p.since or date("%Y-%m-%d %H:%M")
    if not silent then ns.Log.Info(L.PROBE_ON, n) end
end

function Probe.Stop()
    if frame then frame:UnregisterAllEvents() end
    state().enabled = false
    ns.Log.Info(L.PROBE_OFF)
end

function Probe.Clear()
    local p = state()
    p.events = {}
    p.since = date("%Y-%m-%d %H:%M")
    ns.Log.Info(L.PROBE_CLEARED)
end

function Probe.Get()
    return state()
end
