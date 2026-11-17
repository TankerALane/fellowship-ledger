-- UI/Toast.lua
-- Small notices near the top of the screen: level-ups, last session's summary, friend
-- milestones, goals, dungeon clears. Up to three stack; each fades out.
-- Every toast is also written to chat (unless that is turned off), so nothing is lost if it is missed.
--
-- 1.14.0 (D-139): each kind has a colour (gold for you, blue for friends, green for
-- goals, orange for dungeons) on a stripe at the left, a small label over the title,
-- an icon in a ring (a number, or the check or crown), a last line that says what a
-- click opens, and a thin line along the bottom that runs down until the notice fades.
-- Rare moments (a friend at the level cap, a new #1) get a bigger notice in the middle
-- with buttons, which stays until it is closed.

local _, ns = ...
local W = ns.Widgets
local L = ns.L

local Toast = {}
ns.Toast = Toast

Toast.SHOW_SECONDS = 7
Toast.FADE_SECONDS = 1.5
Toast.WIDTH = 380
Toast.LINE_H = 14
local MAX = 3
local pool = {}
local MEDIA = "Interface\\AddOns\\FellowshipLedger\\media\\"

-- Kind colours: a palette role, or our own blue and orange (a darker shade on the light skin).
Toast.KINDS = {
    you = { role = "accent" },
    goal = { role = "good" },
    friend = { dark = { 0.37, 0.66, 1 }, light = { 0.16, 0.36, 0.62 } },
    dungeon = { dark = { 1, 0.54, 0.3 }, light = { 0.62, 0.27, 0.08 } },
}

function Toast.KindColor(kind)
    local k = Toast.KINDS[kind] or Toast.KINDS.you
    if k.role then return W.Color(k.role) end
    local light = ns.Palette.Luminance(W.Color("bg")) > 0.4
    local c = light and k.light or k.dark
    return { c[1], c[2], c[3], 1 }
end

local function colorText(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end

-- How tall a wrapped text is (1.14.4): the game's own measure when it gives one, else
-- an estimate from the length of each line at about 6.5 px a letter. A long line wraps,
-- so counting line breaks alone let the click line sit on top of the text.
Toast.CHAR_W = 6.5
function Toast.TextHeight(fs, text, width)
    if text == "" then return 0 end
    local h = type(fs.GetStringHeight) == "function" and fs:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        lines = lines + math.max(1, math.ceil(#plain * Toast.CHAR_W / width))
    end
    return lines * Toast.LINE_H
end

-- The icon in a ring: opts.icon (short text) or opts.iconTex ("check" | "crown").
local function makeIcon(parent, size)
    local i = CreateFrame("Frame", nil, parent)
    i:SetSize(size, size)
    i.ring = i:CreateTexture(nil, "ARTWORK")
    i.ring:SetTexture(MEDIA .. "ring")
    i.ring:SetAllPoints()
    i.text = W.Text(i, size > 36 and "large" or "body", "heading")
    i.text:SetPoint("CENTER", 0, 0)
    i.text:SetJustifyH("CENTER")
    i.tex = i:CreateTexture(nil, "OVERLAY")
    i.tex:SetSize(math.floor(size / 2), math.floor(size / 2))
    i.tex:SetPoint("CENTER", 0, 0)
    function i:Fill(opts, c)
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
        self.text:SetText(opts.icon or "")
        colorText(self.text, c)
        self.tex:SetShown(opts.iconTex ~= nil)
        if opts.iconTex then
            self.tex:SetTexture(MEDIA .. opts.iconTex)
            self.tex:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end
    return i
end

local function make(i)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(Toast.WIDTH, 74)
    f:SetFrameStrata("HIGH")
    W.Background(f, "bg")
    W.Border(f, "border", 1)
    f.stripe = f:CreateTexture(nil, "ARTWORK")
    f.stripe:SetPoint("TOPLEFT", 0, 0)
    f.stripe:SetPoint("BOTTOMLEFT", 0, 0)
    f.stripe:SetWidth(3)
    f.icon = makeIcon(f, 30)
    f.icon:SetPoint("TOPLEFT", 14, -12)
    f.label = W.Text(f, "tag", "section")
    f.title = W.Text(f, "large", "heading")
    f.title:SetPoint("RIGHT", -12, 0)
    f.title:SetWordWrap(false)
    f.body = W.Text(f, "body", "text")
    f.body:SetPoint("RIGHT", -12, 0)
    f.body:SetWordWrap(true)
    f.action = W.Text(f, "small", "muted")
    f.timer = f:CreateTexture(nil, "OVERLAY")
    f.timer:SetPoint("BOTTOMLEFT", 0, 0)
    f.timer:SetHeight(2)
    f:EnableMouse(true)
    -- Left click opens what the notice is about (D-099); any click dismisses it.
    f:SetScript("OnMouseUp", function(self, button)
        local onClick = self.onClick
        self:Hide()
        if onClick and button ~= "RightButton" then
            local ok, err = pcall(onClick)
            if not ok then ns.Log.Debug("toast click failed: %s", tostring(err)) end
        end
    end)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.age = (self.age or 0) + (elapsed or 0)
        local left = Toast.SHOW_SECONDS - self.age
        self.timer:SetWidth(math.max(1, (Toast.WIDTH - 2) * math.max(0, left) / Toast.SHOW_SECONDS))
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

-- Lay a small notice out: where the text starts and how tall it is.
local function fill(f, title, text, opts)
    local c = Toast.KindColor(opts.kind)
    local hasIcon = opts.icon ~= nil or opts.iconTex ~= nil
    local x0 = hasIcon and 54 or 14
    f.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    f.timer:SetColorTexture(c[1], c[2], c[3], 0.8)
    f.icon:SetShown(hasIcon)
    if hasIcon then f.icon:Fill(opts, c) end
    local y = -10
    f.label:ClearAllPoints()
    f.label:SetShown(opts.label ~= nil)
    if opts.label then
        f.label:SetPoint("TOPLEFT", x0, y)
        f.label:SetText(ns.Format.Upper(opts.label))
        colorText(f.label, c)
        y = y - 12
    end
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", x0, y)
    f.title:SetPoint("RIGHT", -12, 0)
    f.title:SetText(title)
    y = y - 18
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", x0, y)
    local bodyW = Toast.WIDTH - x0 - 12
    f.body:SetWidth(bodyW)
    f.body:SetText(text)
    y = y - math.ceil(Toast.TextHeight(f.body, text, bodyW))
    f.action:ClearAllPoints()
    f.action:SetShown(opts.action ~= nil)
    if opts.action then
        f.action:SetPoint("TOPLEFT", x0, y - 6)
        f.action:SetText(opts.action)
        colorText(f.action, c)
        y = y - 20
    end
    return math.max(hasIcon and 54 or 0, -y + 10)
end
Toast.Fill = fill -- for tests

-- The big notice (a friend at the level cap, a new #1): in the middle, until closed.
local big
local function makeBig()
    local f = CreateFrame("Frame", "FellowshipLedgerBigNotice", UIParent)
    f:SetSize(420, 190)
    f:SetFrameStrata("HIGH")
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    W.Background(f, "bg")
    f.band = f:CreateTexture(nil, "ARTWORK")
    f.band:SetPoint("TOPLEFT", 1, -1)
    f.band:SetPoint("TOPRIGHT", -1, -1)
    f.band:SetHeight(70)
    f.edges = CreateFrame("Frame", nil, f)
    f.edges:SetAllPoints()
    f.edge = {}
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = f.edges:CreateTexture(nil, "BORDER")
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetWidth(p[3]) end
        if p[4] then t:SetHeight(p[4]) end
        f.edge[#f.edge + 1] = t
    end
    f.icon = makeIcon(f, 46)
    f.icon:SetPoint("TOP", 0, -14)
    f.label = W.Text(f, "tag", "section")
    f.label:SetPoint("TOP", f.icon, "BOTTOM", 0, -8)
    f.label:SetJustifyH("CENTER")
    f.title = W.Text(f, "heading", "text")
    f.title:SetPoint("TOP", f.label, "BOTTOM", 0, -4)
    f.title:SetWidth(390)
    f.title:SetJustifyH("CENTER")
    f.body = W.Text(f, "small", "muted")
    f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    f.body:SetWidth(390)
    f.body:SetJustifyH("CENTER")
    f.go = W.Button(f, "", 150, 22, function()
        local onClick = f.onClick
        f:Hide()
        if onClick then
            local ok, err = pcall(onClick)
            if not ok then ns.Log.Debug("notice click failed: %s", tostring(err)) end
        end
    end)
    f.go:SetSelected(true)
    f.go:SetScript("OnEnter", nil)
    f.go:SetScript("OnLeave", nil)
    f.dismiss = W.Button(f, L.TOAST_DISMISS, 90, 22, function() f:Hide() end)
    f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 40, 14)
    f.dismiss:SetPoint("LEFT", f.go, "RIGHT", 6, 0)
    f:EnableMouse(true)
    f:Hide()
    return f
end

function Toast.ShowBig(title, text, opts)
    big = big or makeBig()
    local c = Toast.KindColor(opts.kind)
    big.band:SetColorTexture(c[1], c[2], c[3], 0.12)
    for _, t in ipairs(big.edge) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    big.icon:Fill(opts, c)
    big.label:SetText(ns.Format.Upper(opts.label or ""))
    colorText(big.label, c)
    big.title:SetText(title)
    big.body:SetText(text)
    big.onClick = opts.onClick
    big.go:SetShown(opts.onClick ~= nil)
    big.go.text:SetText(opts.button or L.TOAST_OPEN)
    big.dismiss:ClearAllPoints()
    if opts.onClick then
        big.go:ClearAllPoints()
        big.go:SetPoint("BOTTOMRIGHT", big, "BOTTOM", 32, 14)
        big.dismiss:SetPoint("LEFT", big.go, "RIGHT", 6, 0)
    else
        big.dismiss:SetPoint("BOTTOM", 0, 14)
    end
    local lineCount = text == "" and 0 or select(2, text:gsub("\n", "")) + 1
    big:SetHeight(150 + 14 * lineCount)
    big:Show()
    return big
end

function Toast.Big() return big end

-- opts: { onClick = fn (left click), kind = "you" | "friend" | "goal" | "dungeon",
-- label = "Level up", icon = "32" or iconTex = "check" | "crown", action = "Click to
-- open ...", big = true (the notice in the middle), button = its button's label }.
-- Settings (D-099): toastsShown puts it on screen, toastChat also writes it to chat.
function Toast.Show(title, lines, opts)
    opts = opts or {}
    local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
    local settings = ns.db and ns.db.settings or {}
    if settings.toastChat ~= false then ns.Log.Info("%s - %s", title, (text:gsub("\n", "; "))) end
    if settings.toastsShown == false then return end
    local ok, err = pcall(function()
        if opts.big then
            Toast.ShowBig(title, text, opts)
            return
        end
        -- Reuse the oldest slot when all are busy.
        local slot, oldest = nil, -1
        for i = 1, MAX do
            local f = pool[i] or make(i)
            if not f:IsShown() then slot = f break end
            if (f.age or 0) > oldest then oldest, slot = f.age or 0, f end
        end
        slot:SetHeight(fill(slot, title, text, opts))
        slot.onClick = opts.onClick
        slot.age = 0
        slot:SetAlpha(1)
        slot.timer:SetWidth(Toast.WIDTH - 2)
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

-- The small notices, for tests.
function Toast.Pool() return pool end
