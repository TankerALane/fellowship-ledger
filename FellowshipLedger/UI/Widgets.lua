-- UI/Widgets.lua
-- Small builders shared by the windows: colors, bordered panels, text buttons and a
-- yes/no dialog. Parchment-and-gold palette from assets/README.md. Gold is used for
-- lines and fills only; body text is ink or dark gold, which pass contrast on parchment.

local _, ns = ...

local W = {}
ns.Widgets = W

local function rgb(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end

W.COLORS = {
    parchment = rgb("F1E4C3"),
    ink = rgb("3B2A1A"),
    gold = rgb("C99A2E"),
    darkGold = rgb("7A560F"),
    night = rgb("2B1E12"),
    glass = rgb("F6EBD0"),
}

function W.Fill(region, color, alpha)
    region:SetColorTexture(color[1], color[2], color[3], alpha or color[4])
end

function W.Border(frame, color, size)
    size = size or 1
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        W.Fill(t, color)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, size)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    edge("TOPLEFT", "BOTTOMLEFT", size, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
end

function W.Background(frame, color, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    W.Fill(bg, color, alpha)
    return bg
end

function W.Text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4]) end
    return fs
end

-- A flat text button. `selected` state draws a stronger fill.
function W.Button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 90, height or 22)
    b.bg = W.Background(b, W.COLORS.gold, 0.25)
    W.Border(b, W.COLORS.darkGold, 1)
    b.text = W.Text(b, "GameFontNormalSmall", W.COLORS.ink)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) if not self.selected then W.Fill(self.bg, W.COLORS.gold, 0.45) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then W.Fill(self.bg, W.COLORS.gold, 0.25) end end)
    function b:SetSelected(on)
        self.selected = on
        W.Fill(self.bg, W.COLORS.gold, on and 0.75 or 0.25)
    end
    return b
end

-- Simple modal-style dialog: text plus two buttons.
local dialog
function W.Confirm(text, yesLabel, noLabel, onYes, onNo)
    if not dialog then
        dialog = CreateFrame("Frame", "FellowshipLedgerDialog", UIParent)
        dialog:SetSize(420, 150)
        dialog:SetPoint("CENTER", 0, 120)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:EnableMouse(true)
        W.Background(dialog, W.COLORS.parchment, 0.98)
        W.Border(dialog, W.COLORS.gold, 2)
        dialog.text = W.Text(dialog, "GameFontNormal", W.COLORS.ink)
        dialog.text:SetPoint("TOPLEFT", 16, -16)
        dialog.text:SetPoint("TOPRIGHT", -16, -16)
        dialog.text:SetJustifyH("LEFT")
        dialog.yes = W.Button(dialog, "", 150, 24)
        dialog.yes:SetPoint("BOTTOMLEFT", 16, 14)
        dialog.no = W.Button(dialog, "", 150, 24)
        dialog.no:SetPoint("BOTTOMRIGHT", -16, 14)
    end
    dialog.text:SetText(text)
    dialog.yes.text:SetText(yesLabel)
    dialog.no.text:SetText(noLabel)
    dialog.yes:SetScript("OnClick", function() dialog:Hide(); if onYes then onYes() end end)
    dialog.no:SetScript("OnClick", function() dialog:Hide(); if onNo then onNo() end end)
    dialog:Show()
    return dialog
end
