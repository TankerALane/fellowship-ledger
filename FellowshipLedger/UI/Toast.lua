-- UI/Toast.lua
-- Small parchment notices near the top of the screen: level-ups, last session's
-- summary, and (Phase 3) friend milestones. Up to three stack; each fades out.
-- Every toast is also written to chat, so nothing is lost if it is missed.

local _, ns = ...
local W = ns.Widgets

local Toast = {}
ns.Toast = Toast

Toast.SHOW_SECONDS = 7
Toast.FADE_SECONDS = 1.5
local MAX = 3
local pool = {}

local function make(i)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(380, 74)
    f:SetFrameStrata("HIGH")
    W.Background(f, "bg")
    W.Border(f, "border", 2)
    f.title = W.Text(f, "large", "heading")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetPoint("RIGHT", -12, 0)
    f.body = W.Text(f, "body", "text")
    f.body:SetPoint("TOPLEFT", 12, -32)
    f.body:SetPoint("RIGHT", -12, 0)
    f.body:SetWordWrap(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(self) self:Hide() end) -- click to dismiss
    f:SetScript("OnUpdate", function(self, elapsed)
        self.age = (self.age or 0) + (elapsed or 0)
        local left = Toast.SHOW_SECONDS - self.age
        if left <= 0 then
            self:Hide()
        elseif left < Toast.FADE_SECONDS then
            self:SetAlpha(left / Toast.FADE_SECONDS)
        end
    end)
    f:Hide()
    pool[i] = f
    return f
end

function Toast.Show(title, lines)
    local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
    ns.Log.Info("%s - %s", title, (text:gsub("\n", "; ")))
    local ok, err = pcall(function()
        -- Reuse the oldest slot when all are busy.
        local slot, oldest = nil, -1
        for i = 1, MAX do
            local f = pool[i] or make(i)
            if not f:IsShown() then slot = f break end
            if (f.age or 0) > oldest then oldest, slot = f.age or 0, f end
        end
        slot.title:SetText(title)
        slot.body:SetText(text)
        local lineCount = select(2, text:gsub("\n", "")) + 1
        slot:SetHeight(44 + 14 * lineCount)
        slot.age = 0
        slot:SetAlpha(1)
        slot:Show()
        -- Restack shown toasts top-down.
        local y = -120
        for i = 1, MAX do
            local f = pool[i]
            if f and f:IsShown() then
                f:ClearAllPoints()
                f:SetPoint("TOP", UIParent, "TOP", 0, y)
                y = y - (f:GetHeight() or 80) - 6
            end
        end
    end)
    if not ok then ns.Log.Debug("toast failed: %s", tostring(err)) end
end
