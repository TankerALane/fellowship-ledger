-- UI/InviteDialog.lua
-- "Invite a friend" (D-114): a preview of the invite whisper that the player can
-- edit, with Send, Cancel and Copy link. Nothing is sent without a click on Send,
-- and only one whisper to the one friend. Replies are never read.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Invites = ns.Invites

local InviteDialog = {}
ns.InviteDialog = InviteDialog

InviteDialog.last = nil -- for /fl verify: { at, kind, ok, how }

-- Send one whisper. Battle.net friends get a Battle.net whisper (BNSendWhisper, by
-- the account ID kept in memory, D-108); character friends a character whisper.
-- Returns true when the game took it.
function InviteDialog.Send(peer, text)
    text = Invites.Clean(text)
    if not (peer and text) then return false end
    local ok, how = false, nil
    if peer.kind == "bnet" and peer.bnetAccountID then
        ok = ns.Compat.Call("invite.bnet", "BNSendWhisper", peer.bnetAccountID, text)
        how = "BNSendWhisper"
    end
    local name = peer.kind == "char" and peer.target or peer.character
    if not ok and name then
        -- Newer clients moved SendChatMessage into C_ChatInfo; older ones have only the global.
        ok = ns.Compat.Try("C_ChatInfo.SendChatMessage", text, "WHISPER", nil, name)
        how = "C_ChatInfo.SendChatMessage"
        if not ok then
            ok = ns.Compat.Call("invite.whisper", "SendChatMessage", text, "WHISPER", nil, name)
            how = "SendChatMessage"
        end
    end
    InviteDialog.last = { at = time(), kind = peer.kind, ok = ok and true or false, how = how }
    if ok then
        ns.db.invites = ns.db.invites or {}
        ns.db.invites[peer.id] = time()
        ns.Log.Info(L.INVITE_SENT, peer.name or "?")
    else
        ns.Log.Warn(L.INVITE_FAILED, peer.name or "?")
    end
    return ok and true or false
end

local dialog
local function build()
    local d = CreateFrame("Frame", "FellowshipLedgerInviteDialog", UIParent)
    d:SetSize(460, 220)
    d:SetPoint("CENTER", 0, 120)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    W.Background(d, "bg")
    W.Border(d, "border", 2)
    d.title = W.Text(d, "heading", "heading")
    d.title:SetPoint("TOPLEFT", 16, -14)
    d.title:SetPoint("RIGHT", -16, 0)
    d.hint = W.Text(d, "small", "muted")
    d.hint:SetPoint("TOPLEFT", 16, -40)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.hint:SetWordWrap(true)
    d.hint:SetText(L.INVITE_HINT)
    local box = CreateFrame("EditBox", nil, d)
    box:SetPoint("TOPLEFT", 16, -74)
    box:SetPoint("RIGHT", -16, 0)
    box:SetHeight(76)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(Invites.MAX_LETTERS)
    box:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    box:SetTextInsets(6, 6, 6, 6)
    W.Background(box, "panel")
    W.Border(box, "border", 1)
    box:SetScript("OnEscapePressed", function() d:Hide() end)
    box:SetScript("OnTextChanged", function(self)
        d.count:SetText(string.format(L.INVITE_COUNT, #(self:GetText() or ""), Invites.MAX_LETTERS))
    end)
    d.box = box
    d.count = W.Text(d, "small", "muted")
    d.count:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    d.send = W.Button(d, L.INVITE_SEND, 120, 24)
    d.send:SetPoint("BOTTOMLEFT", 16, 14)
    d.copy = W.Button(d, L.INVITE_COPY_LINK, 120, 24, function()
        ns.CopyWindow:Show(L.INVITE_LINK_TITLE, Invites.URL)
    end)
    d.copy:SetPoint("BOTTOM", 0, 14)
    d.cancel = W.Button(d, L.CANCEL, 120, 24, function() d:Hide() end)
    d.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FellowshipLedgerInviteDialog") end
    d:Hide()
    return d
end

-- Open the preview for one friend (a Friends.peers entry).
function InviteDialog.Open(peer)
    if not peer then return end
    if not dialog then
        local ok, d = pcall(build)
        if not ok then
            ns.Log.Warn(L.WINDOW_FAILED, tostring(d))
            return
        end
        dialog = d
    end
    dialog.title:SetText(string.format(L.INVITE_TITLE, peer.name or "?"))
    dialog.box:SetText(ns.db.settings.inviteText or L.INVITE_MESSAGE)
    dialog.box:SetCursorPosition(0)
    dialog.send:SetScript("OnClick", function()
        local text = dialog.box:GetText()
        -- An edited message is kept as the starting text for the next invite.
        if Invites.Clean(text) and Invites.Clean(text) ~= Invites.Clean(L.INVITE_MESSAGE) then
            ns.db.settings.inviteText = Invites.Clean(text)
        end
        if InviteDialog.Send(peer, text) then
            dialog:Hide()
            if ns.MainWindow.frame and ns.MainWindow.frame:IsShown() then ns.MainWindow.Refresh() end
        end
    end)
    dialog:Show()
    dialog.box:SetFocus()
end
