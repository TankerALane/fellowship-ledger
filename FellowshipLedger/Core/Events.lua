-- Core/Events.lua
-- One event frame for the whole addon. Each handler runs inside pcall, so an error
-- in one tracker can never stop the others; the first error per owner is reported
-- once in chat. When debug is on, every dispatched event is kept in a ring buffer
-- for the /fl debug event log window (addon-message events: name only, no content).

local _, ns = ...
local L = ns.L

local Events = {}
ns.Events = Events

local frame = CreateFrame("Frame")
local handlers = {}   -- event -> { { owner, fn }, ... }
local reported = {}   -- owner -> true once an error was shown

Events.log = {}       -- ring of { at, event, args }
Events.LOG_MAX = 300
local NO_ARGS = { CHAT_MSG_ADDON = true, BN_CHAT_MSG_ADDON = true }

-- Register `fn(event, ...)` for `event` on behalf of `owner`. Returns false (and
-- disables the owner feature) if the client does not know the event.
function Events.On(event, owner, fn)
    if not handlers[event] then
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns.Compat.Disable(owner, "event " .. event .. " is unknown")
            return false
        end
        handlers[event] = {}
    end
    local list = handlers[event]
    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

local function remember(event, ...)
    local log = Events.log
    local args = NO_ARGS[event] and "(not recorded)" or ns.VerifyReport.Sample(ns.Compat.Describe, 100, ...)
    log[#log + 1] = { at = time(), event = event, args = args }
    if #log > Events.LOG_MAX then table.remove(log, 1) end
end

function Events.Dispatch(event, ...)
    if ns.Log.IsDebug() then remember(event, ...) end
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local h = list[i]
        local ok, err = pcall(h.fn, event, ...)
        if not ok and not reported[h.owner] then
            reported[h.owner] = true
            ns.Log.Warn(L.HANDLER_ERROR, h.owner, event, tostring(err))
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...) Events.Dispatch(event, ...) end)

-- Repeating timer through C_Timer.NewTicker, guarded like any other API.
function Events.Every(seconds, owner, fn)
    local ok, ticker = ns.Compat.Call(owner, "C_Timer.NewTicker", seconds, function()
        local fine, err = pcall(fn)
        if not fine and not reported[owner] then
            reported[owner] = true
            ns.Log.Warn(L.HANDLER_ERROR, owner, "timer", tostring(err))
        end
    end)
    return ok and ticker or nil
end

function Events.After(seconds, fn)
    ns.Compat.Call("timers", "C_Timer.After", seconds, function() pcall(fn) end)
end
