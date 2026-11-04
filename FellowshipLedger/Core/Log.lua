-- Core/Log.lua
-- Chat output helpers. Only touches WoW globals when a function is called.

local _, ns = ...

local Log = {}
ns.Log = Log

-- Light gold on the dark chat background (README palette: gold on dark).
local PREFIX = "|cffE0B34AFellowship Ledger|r: "
local DEBUG_PREFIX = "|cffE0B34AFL debug|r: "

-- In-memory ring of recent debug lines; the Phase 1 event log window reads this.
Log.recent = {}
local RECENT_MAX = 200

local function out(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(text)
    else
        print(text)
    end
end

function Log.Info(fmt, ...)
    out(PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

function Log.Warn(fmt, ...)
    out(PREFIX .. "|cffff8040" .. (select("#", ...) > 0 and fmt:format(...) or fmt) .. "|r")
end

function Log.IsDebug()
    return ns.db ~= nil and ns.db.settings ~= nil and ns.db.settings.debug == true
end

function Log.Debug(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    local recent = Log.recent
    recent[#recent + 1] = text
    if #recent > RECENT_MAX then table.remove(recent, 1) end
    if Log.IsDebug() then out(DEBUG_PREFIX .. text) end
end
