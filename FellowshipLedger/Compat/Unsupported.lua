-- Compat/Unsupported.lua
-- Loaded only by the generic FellowshipLedger.toc, which the client uses when it
-- did not pick the _Forever or _Mainline TOC. Prints one message and does nothing else.

local _, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local interface = select(4, GetBuildInfo())
    print("|cffE0B34AFellowship Ledger|r: " .. ns.L.UNSUPPORTED_CLIENT .. " (interface " .. tostring(interface) .. ")")
end)
