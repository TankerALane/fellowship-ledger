-- UI/StalePrompt.lua
-- On a character the ledger has never seen, offer to remove my other characters
-- that have not been played for Character.STALE_DAYS days. The addon cannot see
-- the character list (it does not run at character select), so it cannot know a
-- character was deleted: it asks. "Done" keeps the rest and never asks about them
-- again; "Don't ask again" turns the prompt off (Settings can turn it back on).

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local StalePrompt = {}
ns.StalePrompt = StalePrompt

StalePrompt.MAX_ROWS = 8
StalePrompt.WAIT_TRIES = 12 -- 5 s apart: wait up to a minute for the welcome panel to close
local ROW_H = 24
local TOP = 110

local frame

local function build()
    local f = CreateFrame("Frame", "FellowshipLedgerStalePrompt", UIParent)
    f:SetSize(540, 200)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    W.Background(f, "bg")
    W.Border(f, "border", 2)
    f.title = W.Text(f, "large", "heading")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.text = W.Text(f, "body", "text")
    f.text:SetPoint("TOPLEFT", 16, -40)
    f.text:SetPoint("TOPRIGHT", -16, -40)
    f.text:SetWordWrap(true)
    f.rows = {}
    for i = 1, StalePrompt.MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(508, ROW_H - 2)
        row:SetPoint("TOPLEFT", 16, -TOP - (i - 1) * ROW_H)
        row.text = W.Text(row, "body", "text")
        row.text:SetPoint("LEFT")
        row.text:SetPoint("RIGHT", -96, 0)
        row.text:SetWordWrap(false)
        row.button = W.Button(row, L.REMOVE, 88, 20)
        row.button:SetPoint("RIGHT")
        f.rows[i] = row
    end
    f.more = W.Text(f, "small", "muted")
    f.never = W.Button(f, L.STALE_NEVER, 160, 24)
    f.never:SetPoint("BOTTOMLEFT", 16, 14)
    f.done = W.Button(f, L.STALE_DONE, 160, 24)
    f.done:SetPoint("BOTTOMRIGHT", -16, 14)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerStalePrompt") end
    return f
end

-- list: from ns.Character.Stale.
function StalePrompt.Show(list)
    if not frame then
        local ok, result = pcall(build)
        if not ok then
            ns.Log.Warn(L.WINDOW_FAILED, tostring(result))
            return
        end
        frame = result
    end
    frame.title:SetText(L.STALE_TITLE)
    frame.text:SetText(string.format(L.STALE_TEXT, ns.Character.STALE_DAYS))
    local shown = math.min(#list, StalePrompt.MAX_ROWS)
    for i, row in ipairs(frame.rows) do
        local entry = list[i]
        row:SetShown(entry ~= nil)
        if entry then
            row.removed = false
            row.text:SetText(string.format(L.STALE_ROW, W.ClassName(entry.name, entry.class), entry.level or 0, entry.days))
            row.button.text:SetText(L.REMOVE)
            row.button:SetScript("OnClick", function()
                if row.removed then return end
                row.removed = true
                ns.MeTab.Remove(entry.key)
                row.button.text:SetText(L.STALE_REMOVED)
            end)
        end
    end
    local extra = #list - shown
    frame.more:ClearAllPoints()
    frame.more:SetPoint("TOPLEFT", 16, -TOP - shown * ROW_H - 4)
    frame.more:SetText(extra > 0 and string.format(L.STALE_MORE, extra) or "")
    frame:SetHeight(TOP + shown * ROW_H + (extra > 0 and 22 or 0) + 56)
    frame.done:SetScript("OnClick", function()
        -- Kept: do not ask about these again.
        for i = 1, shown do
            local c = not frame.rows[i].removed and ns.db.characters[list[i].key]
            if c then c.keep = true end
        end
        frame:Hide()
    end)
    frame.never:SetScript("OnClick", function()
        ns.db.settings.askStale = false
        frame:Hide()
    end)
    frame:Show()
    return frame
end

function StalePrompt.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Called a few seconds after the loading screen. Shows at most once per login.
function StalePrompt.MaybeShow(tries)
    tries = tries or 0
    if not ns.Store.isNewCharacter or ns.db.settings.askStale == false then return end
    if ns.Welcome.IsShown() and tries < StalePrompt.WAIT_TRIES then
        ns.Events.After(5, function() StalePrompt.MaybeShow(tries + 1) end)
        return
    end
    ns.Store.isNewCharacter = false
    local list = ns.Character.Stale(ns.db.characters, ns.Store.key, time())
    if #list > 0 then StalePrompt.Show(list) end
end
