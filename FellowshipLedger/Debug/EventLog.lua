-- Debug/EventLog.lua
-- The /fl debug event log window: the last events the addon handled, newest first,
-- refreshed every second while open. Addon-message contents are never recorded.

local _, ns = ...
local L = ns.L

local EventLog = {}
ns.EventLog = EventLog

local window = ns.TextWindow.Create("FellowshipLedgerEventLog")
local ticker

local function render()
    local log = ns.Events.log
    local lines = {}
    for i = #log, math.max(1, #log - 199), -1 do
        local e = log[i]
        lines[#lines + 1] = date("%H:%M:%S", e.at) .. "  " .. e.event .. " " .. e.args
    end
    if #lines == 0 then lines[1] = L.EVENT_LOG_EMPTY end
    return table.concat(lines, "\n")
end

function EventLog.Show()
    window:Show(L.EVENT_LOG_TITLE, render(), false)
    if not ticker then
        ticker = ns.Events.Every(1, "eventlog", function()
            if window:IsShown() then window:SetText(render()) end
        end)
    end
end

function EventLog.Hide()
    window:Hide()
end
