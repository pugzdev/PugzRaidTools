---------------------------------------------------------------------------
-- PugzRaidTools - Groups Tab
-- 8-group x 5-slot composition editor with drag-and-drop reordering.
-- Each slot is a full-width draggable EditBox (MRT-style).
-- Right side: Missing + Not in Roster info panels, Quick Load list.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local COL_W    = 185
local COL_GAP  = 20
local SLOT_H   = 20
local GRP_PAD  = 2
local TOP_BAR  = 24
local QUICK_W  = 240

local ROLE_ICON_SIZE = 14
local ROLE_ICON_GAP = 1
local ROLE_ICON_RIGHT = -3
local DUPLICATE_ICON_SIZE = 15
local ROLE_PENDING_TIMEOUT = 4

PRT._GROUP_ROLE_CONTROL_CONFIG = PRT._GROUP_ROLE_CONTROL_CONFIG or {
    assistantIcon = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
    leaderIcon = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    mainTankIcon = "Interface\\GroupFrame\\UI-Group-MainTankIcon",
    shortcutHint = "Shift+Click: Toggle Assistant  |  Ctrl+Click: Toggle Main Tank",
    useOnKeyDown = false,
    secureVisibility =
        "[combat] hide; [mod:ctrl,mod:shift] hide; [mod:ctrl] show; hide",
    iconLayout = { "duplicate", "mainTank", "rank" },
}
local ROLE_CONTROL = PRT._GROUP_ROLE_CONTROL_CONFIG
local ASSISTANT_ICON = ROLE_CONTROL.assistantIcon
local LEADER_ICON = ROLE_CONTROL.leaderIcon
local MAIN_TANK_ICON = ROLE_CONTROL.mainTankIcon

PRT._groupsRoleDebugEnabled = PRT._groupsRoleDebugEnabled and true or false

function PRT:SetGroupsRoleDebug(enabled)
    self._groupsRoleDebugEnabled = enabled and true or false
    if self.groupsPanel and self.groupsPanel.SetRoleDebugVisuals then
        self.groupsPanel:SetRoleDebugVisuals(self._groupsRoleDebugEnabled)
    end
    PRT.Print("Raid Groups role debugging "
        .. (self._groupsRoleDebugEnabled and "enabled." or "disabled."))
    if self._groupsRoleDebugEnabled then
        PRT.Print("Hold Ctrl over a Raid Groups cell: active tank hit regions are tinted cyan.")
        PRT.Print("After testing, use /prt debug roles to print the captured trace.")
    end
end

function PRT:DumpGroupsRoleDebug()
    if self.groupsPanel and self.groupsPanel.DumpRoleDebug then
        self.groupsPanel:DumpRoleDebug()
    else
        PRT.Print("Raid Groups role debug: open the PRT Raid Groups tab first.")
    end
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function IsShiftDown()
    return IsShiftKeyDown and IsShiftKeyDown() or false
end

local function IsControlDown()
    return IsControlKeyDown and IsControlKeyDown() or false
end

---------------------------------------------------------------------------
-- Cursor-to-slot hit test
---------------------------------------------------------------------------
local function FindSlotAtCursor(panel)
    local x, y  = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = x / scale, y / scale

    for i = 1, 40 do
        local eb = panel.slots[i]
        if eb then
            local left   = eb:GetLeft()
            local right  = eb:GetRight()
            local top    = eb:GetTop()
            local bottom = eb:GetBottom()
            if left and right and top and bottom then
                if cx >= left and cx <= right and cy >= bottom and cy <= top then
                    return i
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Highlight helpers
---------------------------------------------------------------------------
local function SetSlotBorder(panel, slotIdx, r, g, b)
    local eb = panel.slots[slotIdx]
    if eb and eb._borders then
        for _, b_ in ipairs(eb._borders) do
            b_:SetColorTexture(r, g, b, 1)
        end
    end
end

local function RealmWarningColor(kind)
    if kind == "invalid" then return PRT.C.RED end
    if kind == "duplicate" then return PRT.C.GOLD end
    return PRT.C.YELLOW
end

local function ClearSlotBorder(panel, slotIdx)
    local warningState = panel.duplicateSlots and panel.duplicateSlots[slotIdx]
    if warningState then
        local color = RealmWarningColor(warningState.kind)
        SetSlotBorder(panel, slotIdx, color[1], color[2], color[3])
    else
        SetSlotBorder(panel, slotIdx, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3])
    end
end

local function LayoutSlotIcons(panel, slotIdx)
    local eb = panel.slots[slotIdx]
    if not eb then return end

    local x = ROLE_ICON_RIGHT
    local function Place(texture, size)
        if not texture or not texture:IsShown() then return end
        texture:ClearAllPoints()
        texture:SetPoint("RIGHT", x, 0)
        x = x - size - ROLE_ICON_GAP
    end

    -- Place from right to left so duplicate warnings always remain rightmost.
    Place(panel.duplicateWarnings[slotIdx], DUPLICATE_ICON_SIZE)
    Place(panel.mainTankIcons[slotIdx], ROLE_ICON_SIZE)
    Place(panel.rankIcons[slotIdx], ROLE_ICON_SIZE)

    eb:SetTextInsets(6, math.max(6, -x + 2), 0, 0)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function PRT:BuildGroupsTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetAllPoints()

    panel.selectedComp = nil
    panel.slots    = {}   -- [1..40] EditBox
    panel.overlays = {}   -- [1..40] overlay Buttons for drag
    panel.duplicateWarnings = {}
    panel.rankIcons = {}
    panel.mainTankIcons = {}
    panel.mainTankButtons = {}
    panel.pendingRoleStates = {}
    panel._roleDebugTrace = {}
    panel.duplicateSlots = {}
    panel.dirty    = false
    panel.editorRoster = PRT:CopyRealmRoster()
    panel.realmStates = {}
    panel.realmDismissals = {}
    panel.realmWarningButtons = {}
    panel.refreshGuard = W.CreateDeferredRefreshGuard()

    function panel:GetEditorRoster()
        return PRT:CopyRealmRoster(self.editorRoster)
    end

    function panel:FinishEditing()
        for _, slot in ipairs(self.slots) do
            if slot:HasFocus() then slot:ClearFocus() end
        end
    end

    function panel:RenderRealmSlot(index)
        local slot = self.slots[index]
        if slot:HasFocus() then return end
        local state = self.realmStates[index]
        local value = (state and state.display) or self.editorRoster[index] or ""
        if PRT:GetDB().settings.hideServerNames then value = PRT:SplitNameRealm(value, false) end
        slot:SetText(value)
    end

    local ShowNewCompPopup
    local ShowRenameCompPopup
    local ShowDeleteCompPopup
    local ShowDeleteAllCompsPopup

    local function RoleDebug(message, ...)
        if not PRT._groupsRoleDebugEnabled then return end
        if select("#", ...) > 0 then
            message = tostring(message):format(...)
        end
        message = tostring(message)
        panel._roleDebugTrace[#panel._roleDebugTrace + 1] = message
        if #panel._roleDebugTrace > 12 then
            table.remove(panel._roleDebugTrace, 1)
        end
        PRT.Print("[Role debug] " .. message)
    end

    local function GetSlotRaidMember(slotIdx, raid)
        local eb = panel.slots[slotIdx]
        if not eb then return nil, "" end
        local key = PRT:GetRosterSlotIdentityKey(panel.editorRoster, slotIdx)
        return key and key ~= "" and raid[key] or nil, key or ""
    end

    local function CanManageAssistants()
        return IsInRaid and IsInRaid()
            and UnitIsGroupLeader and UnitIsGroupLeader("player")
    end

    local function CanManageMainTanks()
        if not IsInRaid or not IsInRaid() then return false end
        return (UnitIsGroupLeader and UnitIsGroupLeader("player"))
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
            or false
    end

    local function IsPanelVisible()
        if panel.IsVisible then return panel:IsVisible() end
        return panel:IsShown()
    end

    local function RoleStateNow()
        return GetTime and GetTime() or 0
    end

    local function GetPendingRoleState(identityKey)
        local pending = identityKey and panel.pendingRoleStates[identityKey]
        if pending and pending.expires <= RoleStateNow() then
            panel.pendingRoleStates[identityKey] = nil
            return nil
        end
        return pending
    end

    local function GetEffectiveRoleState(identityKey, member)
        local rank = member and (member.rank or 0) or 0
        local isMainTank = member and member.isMainTank or false
        local pending = GetPendingRoleState(identityKey)
        if not pending then return rank, isMainTank end

        -- An authoritative match completes that pending part of the change.
        if pending.rank ~= nil and rank == pending.rank then
            pending.rank = nil
        end
        if pending.isMainTank ~= nil and isMainTank == pending.isMainTank then
            pending.isMainTank = nil
        end

        if pending.rank ~= nil then rank = pending.rank end
        if pending.isMainTank ~= nil then isMainTank = pending.isMainTank end
        if pending.rank == nil and pending.isMainTank == nil then
            panel.pendingRoleStates[identityKey] = nil
        end
        return rank, isMainTank
    end

    local function SetPendingRoleState(identityKey, field, value)
        if not identityKey or identityKey == "" then return end
        local pending = panel.pendingRoleStates[identityKey] or {}
        local expires = RoleStateNow() + ROLE_PENDING_TIMEOUT
        pending[field] = value
        pending.expires = expires
        panel.pendingRoleStates[identityKey] = pending

        if C_Timer and C_Timer.After then
            C_Timer.After(ROLE_PENDING_TIMEOUT + 0.1, function()
                local current = panel.pendingRoleStates[identityKey]
                if current and current.expires == expires then
                    panel.pendingRoleStates[identityKey] = nil
                    if panel.RefreshHighlights then panel:RefreshHighlights() end
                end
            end)
        end
    end

    local function ScheduleMainTankDebugProbes(identityKey, unit, desired)
        if not PRT._groupsRoleDebugEnabled or not C_Timer or not C_Timer.After then return end
        for _, delay in ipairs({ 0.1, 1, 3 }) do
            local probeDelay = delay
            C_Timer.After(probeDelay, function()
                if not PRT._groupsRoleDebugEnabled then return end
                local raid = PRT.GetRaidRoster()
                local member = identityKey and raid[identityKey]
                local exact = GetPartyAssignment
                    and GetPartyAssignment("MAINTANK", unit, true) and true or false
                RoleDebug("probe +%.1fs unit=%s exists=%s desired=%s assignment=%s roster=%s",
                    probeDelay,
                    tostring(unit),
                    tostring(UnitExists and UnitExists(unit) and true or false),
                    tostring(desired),
                    tostring(exact),
                    tostring(member and member.isMainTank or false))
            end)
        end
    end

    local function ToggleAssistantRole(slotIdx)
        if IsInCombat() then
            PRT.Print("Raid role shortcuts are unavailable during combat.")
            return
        end
        if not IsInRaid or not IsInRaid() then
            PRT.Print("You must be in a raid to change raid roles.")
            return
        end
        if not CanManageAssistants() then
            PRT.Print("You must be raid leader to change assistants.")
            return
        end

        local raid = PRT.GetRaidRoster()
        local member, identityKey = GetSlotRaidMember(slotIdx, raid)
        if not member then
            PRT.Print("That player is not in the current raid.")
            return
        end
        if member.rank == 2 then
            PRT.Print("The raid leader cannot be toggled as an assistant.")
            return
        end

        local effectiveRank = GetEffectiveRoleState(identityKey, member)
        local pending = GetPendingRoleState(identityKey)
        if pending and pending.rank ~= nil then
            PRT.Print("That assistant change is still being applied.")
            return
        end

        if effectiveRank == 1 then
            if not DemoteAssistant then
                PRT.Print("Assistant demotion is unavailable on this client.")
                return
            end
            DemoteAssistant(member.name)
            if PRT._inviteToolsManualDemotions then
                PRT._inviteToolsManualDemotions[identityKey] = true
            end
            SetPendingRoleState(identityKey, "rank", 0)
        else
            if not PromoteToAssistant then
                PRT.Print("Assistant promotion is unavailable on this client.")
                return
            end
            if PRT._inviteToolsManualDemotions then
                PRT._inviteToolsManualDemotions[identityKey] = nil
            end
            PromoteToAssistant(member.name)
            SetPendingRoleState(identityKey, "rank", 1)
        end
        panel:RefreshRoleIndicators(raid)
    end

    local function HandleModifierClick(slotIdx, button)
        if button ~= "LeftButton" then return false end

        local shift = IsShiftDown()
        local control = IsControlDown()
        if not shift and not control then return false end

        if shift and control then
            PRT.Print("Use Shift or Ctrl for one raid role at a time.")
            return true
        end
        if shift then
            ToggleAssistantRole(slotIdx)
            return true
        end

        -- A valid Ctrl-click is intercepted by the secure main-tank button.
        -- This path explains why the secure layer was deliberately unavailable.
        RoleDebug("insecure cell layer received Ctrl-click for slot=%d; secure hit region missed",
            slotIdx)
        if IsInCombat() then
            PRT.Print("Raid role shortcuts are unavailable during combat.")
        elseif not IsInRaid or not IsInRaid() then
            PRT.Print("You must be in a raid to change raid roles.")
        else
            local member = GetSlotRaidMember(slotIdx, PRT.GetRaidRoster())
            if not member then
                PRT.Print("That player is not in the current raid.")
            elseif not CanManageMainTanks() then
                PRT.Print("You must be raid leader or assistant to change main tanks.")
            end
        end
        return true
    end

    -- drag state
    local drag = {
        active     = false,
        sourceName = "",
        sourceSlot = nil,
        hoverSlot  = nil,
    }

    ---------------------------------------------------------------------------
    -- Ghost frame (visible dragged label, follows cursor)
    ---------------------------------------------------------------------------
    local ghost = W.CreateGhostLabelFrame(UIParent, {
        width = COL_W,
        height = SLOT_H,
        fontSize = PRT.FONT_SIZE,
    })

    ghost:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)

        local hovered = FindSlotAtCursor(panel)
        if hovered ~= drag.hoverSlot then
            if drag.hoverSlot then ClearSlotBorder(panel, drag.hoverSlot) end
            if hovered       then SetSlotBorder(panel, hovered, 1, 0.82, 0) end
            drag.hoverSlot = hovered
        end
    end)

    ---------------------------------------------------------------------------
    -- Drag functions
    ---------------------------------------------------------------------------
    function panel:StartDrag(name, sourceSlot)
        drag.active     = true
        drag.sourceName = name
        drag.sourceSlot = sourceSlot
        drag.hoverSlot  = nil
        ghost.label:SetText(name)
        ghost:Show()
    end

    function panel:EndDrag()
        if drag.hoverSlot then ClearSlotBorder(panel, drag.hoverSlot) end
        drag.active     = false
        drag.sourceName = ""
        drag.sourceSlot = nil
        drag.hoverSlot  = nil
        ghost:Hide()
    end

    function panel:HandleDrop(targetSlot)
        if not drag.active then return end
        local targetEB = self.slots[targetSlot]
        if not targetEB then self:EndDrag(); return end

        self:FinishEditing()
        local targetName = self.editorRoster[targetSlot]
        local latches = self.editorRoster._prtRealmAmbiguous
        local targetLatch = latches and latches[targetSlot]
        local sourceLatch = drag.sourceSlot and latches and latches[drag.sourceSlot]

        if drag.sourceSlot then
            PRT:SetRealmRosterSlot(self.editorRoster, drag.sourceSlot, targetName)
            if latches then latches[drag.sourceSlot] = targetLatch end
        end
        PRT:SetRealmRosterSlot(self.editorRoster, targetSlot, drag.sourceName)
        if latches then latches[targetSlot] = sourceLatch end

        self.dirty = true
        self:EndDrag()
        self:RefreshHighlights()
        self:AutoSave()
    end

    local function FinishDrag()
        if not drag.active then return end
        local target = FindSlotAtCursor(panel)
        if target and target ~= drag.sourceSlot then
            panel:HandleDrop(target)
        else
            panel:EndDrag()
        end
    end

    ---------------------------------------------------------------------------
    -- Top bar: composition name label
    ---------------------------------------------------------------------------
    local gridTop = -TOP_BAR - 2

    local compNameLabel = W.CreateLabel(panel, "", PRT.FONT_SIZE_HEADER,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    compNameLabel:SetPoint("TOPLEFT", 12, -4)
    panel.compNameLabel = compNameLabel

    local helpBtn = W.CreateButton(panel, "Help", 54, 20)
    helpBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -2)
    helpBtn:SetScript("OnClick", function()
        if PRT.ToggleRaidGroupsHelp then
            PRT:ToggleRaidGroupsHelp("import")
        end
    end)
    W.AttachTooltip(helpBtn, {
        anchor = "ANCHOR_LEFT",
        title = "Raid Groups Help",
        titleColor = PRT.C.TITLE,
        lines = {
            { "Open guides for importing, player names, saving, sorting and automation.", 1, 1, 1, true },
        },
    })
    panel.helpButton = helpBtn

    ---------------------------------------------------------------------------
    -- Group grid (1,3,5,7 = left | 2,4,6,8 = right)
    ---------------------------------------------------------------------------
    for g = 1, 8 do
        local col  = (g % 2 == 1) and 0 or 1
        local row  = math.floor((g - 1) / 2)
        local xOff = 12 + col * (COL_W + COL_GAP)
        local yOff = gridTop - row * (SLOT_H * 5 + GRP_PAD + 14)

        local lbl = W.CreateLabel(panel, "Group " .. g, PRT.FONT_SIZE,
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
        lbl:SetPoint("TOPLEFT", xOff, yOff)

        for s = 1, 5 do
            local idx   = (g - 1) * 5 + s
            local slotY = yOff - 14 - (s - 1) * SLOT_H

            -- EditBox (full slot width, no drag handle)
            local eb = W.CreateEditBox(panel, COL_W, SLOT_H)
            eb:SetPoint("TOPLEFT", xOff, slotY)
            eb:SetTextInsets(6, 22, 0, 0)
            eb.slotIndex = idx

            eb:SetScript("OnEditFocusGained", function(self)
                local ov = panel.overlays[self.slotIndex]
                if ov then ov:Hide() end
                -- Editing always exposes the actual expected full identity,
                -- never a cosmetic short name or an unaccepted preview.
                self:SetText(panel.editorRoster[self.slotIndex] or "")
            end)
            eb:SetScript("OnEditFocusLost", function(self)
                local ov = panel.overlays[self.slotIndex]
                if ov then ov:Show() end
                panel:RefreshHighlights()
                panel:AutoSave()
            end)
            eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            eb:SetScript("OnTabPressed", function(self)
                self:ClearFocus()
                local nxt = panel.slots[self.slotIndex + 1]
                if nxt then nxt:SetFocus() end
            end)
            eb:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and drag.active then
                    FinishDrag()
                elseif not drag.active then
                    HandleModifierClick(self.slotIndex, button)
                end
            end)
            eb:HookScript("OnTextChanged", function(self, isUserInput)
                if isUserInput then
                    PRT:SetRealmRosterSlot(panel.editorRoster, self.slotIndex, self:GetText())
                    panel.dirty = true
                    panel:RefreshDuplicateWarnings()
                    if panel.RefreshSaveControls then
                        panel:RefreshSaveControls()
                    end
                    if panel.RefreshRoleIndicators then
                        panel:RefreshRoleIndicators()
                    end
                end
            end)

            panel.slots[idx] = eb
            panel.refreshGuard:Track(eb)

            local duplicateWarning = eb:CreateTexture(nil, "OVERLAY")
            duplicateWarning:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
            duplicateWarning:SetSize(15, 15)
            duplicateWarning:SetPoint("RIGHT", -3, 0)
            duplicateWarning:Hide()
            panel.duplicateWarnings[idx] = duplicateWarning

            local rankIcon = eb:CreateTexture(nil, "OVERLAY")
            rankIcon:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
            rankIcon:Hide()
            panel.rankIcons[idx] = rankIcon

            local mainTankIcon = eb:CreateTexture(nil, "OVERLAY")
            mainTankIcon:SetTexture(MAIN_TANK_ICON)
            mainTankIcon:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
            mainTankIcon:Hide()
            panel.mainTankIcons[idx] = mainTankIcon

            LayoutSlotIcons(panel, idx)

            -- Overlay Button (sits on top for drag + click-to-edit)
            local ov = W.CreateOverlayButton(panel, eb, {
                dragButton = "LeftButton",
                clicks = "LeftButtonUp",
            })
            ov.slotIndex = idx

            ov:SetScript("OnClick", function(self, button)
                if HandleModifierClick(self.slotIndex, button) then
                    return
                end
                if button == "LeftButton" and not drag.active then
                    self:Hide()
                    panel.slots[self.slotIndex]:SetFocus()
                end
            end)
            ov:SetScript("OnDragStart", function(self)
                if IsShiftDown() or IsControlDown() then return end
                local name = panel.editorRoster[self.slotIndex] or ""
                if name ~= "" then
                    panel:StartDrag(name, self.slotIndex)
                end
            end)
            ov:SetScript("OnDragStop", function()
                FinishDrag()
            end)
            ov:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and drag.active then
                    FinishDrag()
                end
            end)
            ov:SetScript("OnEnter", function(self)
                if not drag.active and eb._bgTex then
                    eb._bgTex:SetColorTexture(0.12, 0.12, 0.12, 0.9)
                end
            end)
            ov:SetScript("OnLeave", function(self)
                if not drag.active and eb._bgTex then
                    local bg = PRT.C.INPUT_BG
                    eb._bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
                end
            end)

            local warningSlotIndex = idx
            local duplicateTooltip = {
                anchor = "ANCHOR_RIGHT",
                title = "Raid Groups: Server Names",
                titleColor = PRT.C.YELLOW,
                shouldShow = function()
                    local state = panel.realmStates[warningSlotIndex]
                    return state and state.kind ~= nil
                end,
                getLines = function()
                    return panel:GetRealmWarningLines(warningSlotIndex)
                end,
            }
            W.AttachTooltip(eb, duplicateTooltip)
            W.AttachTooltip(ov, duplicateTooltip)

            panel.overlays[idx] = ov
            local warningButton = W.CreateOverlayButton(panel, nil)
            warningButton:SetAllPoints(duplicateWarning)
            warningButton:SetFrameLevel(ov:GetFrameLevel() + 1)
            warningButton:SetScript("OnClick", function(_, button)
                if button == "LeftButton" and not IsShiftDown() and not IsControlDown() then
                    panel:ClickRealmWarning(warningSlotIndex)
                end
            end)
            W.AttachTooltip(warningButton, duplicateTooltip)
            warningButton:Hide()
            panel.realmWarningButtons[idx] = warningButton

            -- SetPartyAssignment is protected. This UIParent-owned button is
            -- only visible for an out-of-combat Ctrl-click and uses absolute
            -- coordinates so it never protects the editable cell hierarchy.
            local mainTankSlotIndex = idx
            local mainTankButton = CreateFrame(
                "Button", "PRT_RaidGroupsMainTankButton" .. idx,
                UIParent, "SecureActionButtonTemplate")
            mainTankButton._prtSlotIndex = idx
            mainTankButton:SetSize(COL_W, SLOT_H)
            -- Addon-created secure buttons otherwise inherit the player's
            -- ActionButtonUseKeyDown CVar. This control only registers mouse-up,
            -- so explicitly make mouse-up the protected action phase.
            mainTankButton:SetAttribute("useOnKeyDown", ROLE_CONTROL.useOnKeyDown)
            mainTankButton:RegisterForClicks("LeftButtonUp")
            -- Ctrl prefixes WoW's protected attribute lookup, so use the
            -- modifier wildcard for every part of this left-click action.
            mainTankButton:SetAttribute("*type1", "maintank")
            mainTankButton:SetAttribute("*action1", "toggle")
            mainTankButton:SetAttribute("ctrl-type1", "maintank")
            mainTankButton:SetAttribute("ctrl-action1", "toggle")

            local debugTexture = mainTankButton:CreateTexture(nil, "BACKGROUND")
            debugTexture:SetAllPoints()
            debugTexture:SetColorTexture(0, 0.85, 1, 0.18)
            if PRT._groupsRoleDebugEnabled then debugTexture:Show() else debugTexture:Hide() end
            mainTankButton._prtDebugTexture = debugTexture

            mainTankButton:SetScript("PreClick", function(self, button)
                local raid = PRT.GetRaidRoster()
                local member, identityKey = GetSlotRaidMember(mainTankSlotIndex, raid)
                if member then
                    local _, isMainTank = GetEffectiveRoleState(identityKey, member)
                    self._prtPendingIdentityKey = identityKey
                    self._prtPendingMainTank = not isMainTank
                    local resolvedUnit = SecureButton_GetModifiedUnit
                        and SecureButton_GetModifiedUnit(self, button)
                        or self:GetAttribute("*unit1")
                    local resolvedType = SecureButton_GetModifiedAttribute
                        and SecureButton_GetModifiedAttribute(self, "type", button)
                        or self:GetAttribute("*type1")
                    local resolvedAction = SecureButton_GetModifiedAttribute
                        and SecureButton_GetModifiedAttribute(self, "action", button)
                        or self:GetAttribute("*action1")
                    RoleDebug("secure PreClick slot=%d button=%s player=%s type=%s action=%s unit=%s exists=%s before=%s desired=%s",
                        mainTankSlotIndex,
                        tostring(button),
                        tostring(member.name),
                        tostring(resolvedType),
                        tostring(resolvedAction),
                        tostring(resolvedUnit),
                        tostring(UnitExists and UnitExists(resolvedUnit) and true or false),
                        tostring(isMainTank),
                        tostring(not isMainTank))
                else
                    self._prtPendingIdentityKey = nil
                    self._prtPendingMainTank = nil
                    RoleDebug("secure PreClick slot=%d found no live raid member",
                        mainTankSlotIndex)
                end
            end)
            mainTankButton:SetScript("PostClick", function(self, button)
                if self._prtPendingIdentityKey
                    and self._prtPendingMainTank ~= nil then
                    panel._roleDebugLastClickAt = RoleStateNow()
                    RoleDebug("secure PostClick slot=%d button=%s action dispatched",
                        mainTankSlotIndex, tostring(button))
                    SetPendingRoleState(self._prtPendingIdentityKey,
                        "isMainTank", self._prtPendingMainTank)
                    ScheduleMainTankDebugProbes(self._prtPendingIdentityKey,
                        self:GetAttribute("*unit1"), self._prtPendingMainTank)
                    self:EnableMouse(false)
                    panel:RefreshRoleIndicators()
                end
            end)
            mainTankButton:EnableMouse(false)
            if RegisterStateDriver then
                RegisterStateDriver(mainTankButton, "visibility",
                    ROLE_CONTROL.secureVisibility)
            else
                mainTankButton:Hide()
            end
            panel.mainTankButtons[idx] = mainTankButton
        end
    end

    local roleShortcutHint = W.CreateLabel(panel, ROLE_CONTROL.shortcutHint,
        PRT.FONT_SIZE - 2, PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
    roleShortcutHint:SetPoint("TOPLEFT", panel.slots[35], "BOTTOMLEFT", 0, -2)
    roleShortcutHint:SetWidth(COL_W * 2 + COL_GAP)
    roleShortcutHint:SetJustifyH("LEFT")
    panel.roleShortcutHint = roleShortcutHint

    ---------------------------------------------------------------------------
    -- Quick Load panel (right side)
    ---------------------------------------------------------------------------
    local quickPanel = CreateFrame("Frame", nil, panel)
    quickPanel:SetWidth(QUICK_W)
    quickPanel:SetPoint("TOPRIGHT",    panel, "TOPRIGHT",    -8, gridTop)
    quickPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 34)
    W.StyleBox(quickPanel, { 0.06, 0.06, 0.06, 0.85 }, PRT.C.BORDER)

    local quickHdr = W.CreateLabel(quickPanel, "Quick Load",
        PRT.FONT_SIZE, PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    quickHdr:SetPoint("TOPLEFT", 6, -4)

    local quickScroll = W.CreateScrollFrame(quickPanel, 0, 0)
    quickScroll:SetPoint("TOPLEFT",     2, -20)
    quickScroll:SetPoint("BOTTOMRIGHT", -2, 156)
    panel.quickScroll  = quickScroll
    panel.quickButtons = {}

    local requireCB = W.CreateCheckbox(quickPanel, "Auto-Accept Unspecified Servers", function(checked)
        panel:FinishEditing()
        -- Preserve the legacy setting key while presenting the policy positively:
        -- checked auto-accepts unique matches, which is requireServerNames=false.
        PRT:GetDB().settings.requireServerNames = not checked
        panel:RefreshHighlights()
        PRT:RefreshRealmCompositions()
    end)
    requireCB:SetPoint("BOTTOMLEFT", 4, 104)
    W.AttachTooltip(requireCB.check, { title = "Auto-Accept Unspecified Servers", titleColor = PRT.C.TITLE, lines = {
        { "Controls roster names imported without a server.", 1, 1, 1, true },
        " ",
        { "Checked: accept unique matches automatically", 0.2, 1, 0.6, true },
        { "When exactly one eligible player is in the raid, their full Name-Server identity is accepted.", 1, 1, 1, true },
        { "Multiple possible players still require you to choose the intended identity.", 1, 0.82, 0.3, true },
        " ",
        { "Unchecked: ask before accepting", 1, 0.82, 0.3, true },
        { "Each matching player waits for you to click the cell's warning triangle, including players on your own server.", 1, 1, 1, true },
        " ",
        { "Names imported as Name-Server always remain exact. A matching name is never guessed when more than one player could fit.", 1, 0.82, 0.3, true },
        { "Auto-Save Changes ON: accepted names save automatically. OFF: click Save Changes.", 0.8, 0.8, 0.8, true },
        { "Applies to all compositions. Existing saved rosters retain their previous meaning until edited or reimported.", 0.8, 0.8, 0.8, true },
    } })
    local hideCB = W.CreateCheckbox(quickPanel, "Hide Server Names", function(checked)
        PRT:GetDB().settings.hideServerNames = checked and true or false
        panel:RefreshHighlights()
    end)
    hideCB:SetPoint("BOTTOMLEFT", 4, 82)
    W.AttachTooltip(hideCB.check, { title = "Hide Server Names", titleColor = PRT.C.TITLE, lines = {
        { "Shortens names in Raid Groups cells only.", 1, 1, 1, true },
        " ",
        { "Display only - no player identities change.", 0.2, 1, 0.6, true },
        { "Saved names and exports retain their servers. Sorting and marking still use exact players.", 1, 1, 1, true },
        " ",
        { "Wrong-server and duplicate-name warnings remain visible.", 1, 0.82, 0.3, true },
        { "Click into a cell to edit its full expected name.", 0.8, 0.8, 0.8, true },
    } })
    panel.requireServerNames = requireCB
    panel.autoAcceptUnspecifiedServers = requireCB
    panel.hideServerNames = hideCB
    panel.realmStatus = W.CreateLabel(quickPanel, "", PRT.FONT_SIZE - 1,
        PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3])
    panel.realmStatus:SetPoint("BOTTOMLEFT", 8, 132)
    panel.realmStatus:SetWidth(QUICK_W - 16)
    panel.realmStatus:SetJustifyH("LEFT")

    -- Row 1: New / Rename / Import (equal width, fill row)
    local _q3W = math.floor((QUICK_W - 12) / 3)
    local _q2W = math.floor((QUICK_W - 10) / 2)

    local qBtnNew = W.CreateButton(quickPanel, "New", _q3W, 20)
    qBtnNew:SetPoint("BOTTOMLEFT", 4, 52)
    qBtnNew:SetScript("OnClick", function()
        if ShowNewCompPopup then ShowNewCompPopup() end
    end)

    local qBtnRen = W.CreateButton(quickPanel, "Rename", _q3W, 20)
    qBtnRen:SetPoint("LEFT", qBtnNew, "RIGHT", 2, 0)
    qBtnRen:SetScript("OnClick", function()
        if panel.selectedComp and ShowRenameCompPopup then ShowRenameCompPopup(panel.selectedComp) end
    end)

    local qBtnImport = W.CreateButton(quickPanel, "Import", _q3W, 20)
    qBtnImport:SetPoint("LEFT", qBtnRen, "RIGHT", 2, 0)

    -- Row 2: Delete / Delete All (equal width, fill row)
    local qBtnDel = W.CreateButton(quickPanel, "Delete", _q2W, 20)
    qBtnDel:SetPoint("BOTTOMLEFT", 4, 28)
    qBtnDel.label:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3], 1)
    qBtnDel:SetScript("OnClick", function()
        if panel.selectedComp and ShowDeleteCompPopup then ShowDeleteCompPopup(panel.selectedComp) end
    end)

    local qBtnDelAll = W.CreateButton(quickPanel, "Delete All", _q2W, 20)
    qBtnDelAll:SetPoint("LEFT", qBtnDel, "RIGHT", 2, 0)
    qBtnDelAll.label:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3], 1)
    qBtnDelAll:SetScript("OnClick", function()
        if ShowDeleteAllCompsPopup then ShowDeleteAllCompsPopup() end
    end)

    -- Row 3: Export / Export All (equal width, fill row — handlers set after popups)
    local qBtnExport = W.CreateButton(quickPanel, "Export", _q2W, 22)
    qBtnExport:SetPoint("BOTTOMLEFT", 4, 4)

    local qBtnExportAll = W.CreateButton(quickPanel, "Export All", _q2W, 22)
    qBtnExportAll:SetPoint("LEFT", qBtnExport, "RIGHT", 2, 0)

    ---------------------------------------------------------------------------
    -- Quick Load drag-to-reorder
    ---------------------------------------------------------------------------
    local qlDrag = { active = false, sourceIndex = nil, hoverIndex = nil }

    local qlGhost = W.CreateGhostLabelFrame(UIParent, {
        width = QUICK_W - 4,
        height = 20,
        fontSize = PRT.FONT_SIZE,
    })

    local function FindQuickSlotAtCursor()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = x / scale, y / scale
        for i, btn in ipairs(panel.quickButtons) do
            if btn:IsShown() then
                local left   = btn:GetLeft()
                local right  = btn:GetRight()
                local top    = btn:GetTop()
                local bottom = btn:GetBottom()
                if left and right and top and bottom then
                    if cx >= left and cx <= right and cy >= bottom and cy <= top then
                        return i
                    end
                end
            end
        end
        return nil
    end

    qlGhost:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        qlGhost:ClearAllPoints()
        qlGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)

        local hovered = FindQuickSlotAtCursor()
        if hovered ~= qlDrag.hoverIndex then
            if qlDrag.hoverIndex then
                local old = panel.quickButtons[qlDrag.hoverIndex]
                if old and old:IsShown() then
                    old:SetSelected(old.compName == panel.selectedComp)
                end
            end
            if hovered then
                local hBtn = panel.quickButtons[hovered]
                if hBtn then hBtn._bgTex:SetColorTexture(1, 0.82, 0, 0.3) end
            end
            qlDrag.hoverIndex = hovered
        end
    end)

    local function FinishQuickDrag()
        if not qlDrag.active then return end
        local target = FindQuickSlotAtCursor()
        if target and target ~= qlDrag.sourceIndex then
            PRT:MoveComp(qlDrag.sourceIndex, target)
            panel:RefreshQuickLoad()
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        end
        if qlDrag.hoverIndex then
            local old = panel.quickButtons[qlDrag.hoverIndex]
            if old and old:IsShown() then
                old:SetSelected(old.compName == panel.selectedComp)
            end
        end
        qlDrag.active = false
        qlDrag.sourceIndex = nil
        qlDrag.hoverIndex = nil
        qlGhost:Hide()
        for _, btn in ipairs(panel.quickButtons) do
            btn:SetHoverAnimationSuspended(false)
            btn:SetSelected(btn.compName == panel.selectedComp)
        end
    end

    ---------------------------------------------------------------------------
    -- Shape Import Popup  (select layout → paste → auto-detect → name popup)
    ---------------------------------------------------------------------------
    local shapePopup = W.CreatePopupFrame("PRT_ShapeImportPopup", 520, 368, {
        title = "Import Paste text below",
    })
    local realmImportHint = W.CreateDescription(shapePopup,
        "Name = server unspecified. Name-Server = exact player.\nAuto-Accept Unspecified Servers controls unique matches; cell warnings explain any conflicts.",
        { fontSize = PRT.FONT_SIZE - 1 })
    realmImportHint:SetPoint("BOTTOMLEFT", 14, 8)
    realmImportHint:SetWidth(492)

    -- Shape buttons
    shapePopup._selectedShape = nil
    local SB_BTN_W = 118
    local SB_BTN_H = 80
    local SB_BTN_GAP = 6

    ---------------------------------------------------------------------------
    -- Import Name Popup  (shown after auto-paste to name the new composition)
    ---------------------------------------------------------------------------
    local sipNamePopup = W.CreateNamePopup("PRT_ImportNamePopup", {
        width = 300,
        height = 100,
        title = "Enter preset name",
        prompt = false,
        acceptText = "Accept",
        buttonWidth = 276,
        buttonHeight = 24,
        buttonY = 10,
        acceptFill = true,
        cancelText = false,
    })

    ---------------------------------------------------------------------------
    -- Named import collision popup. All choices are resolved before any saved
    -- composition is changed, so cancelling a multi-import is all-or-nothing.
    ---------------------------------------------------------------------------
    local importConflictPopup
    local ContinueNamedImport

    local function CancelNamedImport(message)
        if not importConflictPopup or not importConflictPopup._state then return end
        importConflictPopup._state = nil
        importConflictPopup._suppressCancel = true
        importConflictPopup:Hide()
        importConflictPopup._suppressCancel = nil
        PRT.Print(message or "Import cancelled. No raid groups were changed.")
    end

    importConflictPopup = W.CreatePopupFrame("PRT_ImportConflictPopup", 410, 178, {
        title = "Raid Group Already Exists",
        onClose = function()
            CancelNamedImport()
        end,
    })

    local conflictMessage = W.CreateLabel(importConflictPopup, "", PRT.FONT_SIZE, 0.9, 0.9, 0.9)
    conflictMessage:SetPoint("TOPLEFT", 12, -34)
    conflictMessage:SetPoint("TOPRIGHT", -12, -34)
    conflictMessage:SetHeight(38)
    conflictMessage:SetJustifyH("LEFT")
    pcall(function() conflictMessage:SetWordWrap(true) end)
    importConflictPopup.messageLabel = conflictMessage

    local renameLabel = W.CreateLabel(importConflictPopup, "Rename this import:",
        PRT.FONT_SIZE - 1, 0.8, 0.8, 0.8)
    renameLabel:SetPoint("TOPLEFT", 12, -78)

    local conflictNameEdit = W.CreateEditBox(importConflictPopup, 386, 22)
    conflictNameEdit:SetPoint("TOPLEFT", 12, -94)
    conflictNameEdit:SetPoint("TOPRIGHT", -12, -94)
    importConflictPopup.nameEdit = conflictNameEdit

    local conflictError = W.CreateLabel(importConflictPopup, "", PRT.FONT_SIZE - 1,
        PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
    conflictError:SetPoint("TOPLEFT", 12, -119)
    conflictError:SetPoint("TOPRIGHT", -12, -119)
    importConflictPopup.errorLabel = conflictError

    local overwriteImportBtn = W.CreateButton(importConflictPopup, "Overwrite", 112, 24, {
        textColor = PRT.C.RED,
    })
    overwriteImportBtn:SetPoint("BOTTOMLEFT", 12, 9)
    importConflictPopup.overwriteButton = overwriteImportBtn

    local renameImportBtn = W.CreateButton(importConflictPopup, "Rename & Import", 132, 24)
    renameImportBtn:SetPoint("LEFT", overwriteImportBtn, "RIGHT", 7, 0)
    importConflictPopup.renameButton = renameImportBtn

    local cancelImportBtn = W.CreateButton(importConflictPopup, "Cancel Import", 120, 24)
    cancelImportBtn:SetPoint("LEFT", renameImportBtn, "RIGHT", 7, 0)
    importConflictPopup.cancelButton = cancelImportBtn

    local function NameUsedByLaterImport(state, name)
        for index = state.index + 1, #state.comps do
            if PRT.Trim(state.comps[index].name) == name then return true end
        end
        return false
    end

    local function RenameUnavailable(state, name)
        return PRT:GetComp(name) ~= nil
            or state.finalByName[name] ~= nil
            or NameUsedByLaterImport(state, name)
    end

    local function SuggestImportName(state, baseName)
        local suffix = 2
        local candidate = baseName .. " (" .. suffix .. ")"
        while RenameUnavailable(state, candidate) do
            suffix = suffix + 1
            candidate = baseName .. " (" .. suffix .. ")"
        end
        return candidate
    end

    local function QueueNamedImport(state, name, roster, overwrite)
        local actionIndex = #state.actions + 1
        state.actions[actionIndex] = {
            name = name,
            roster = roster,
            overwrite = overwrite and true or false,
        }
        state.finalByName[name] = actionIndex
        state.firstImported = state.firstImported or name
    end

    local function CommitNamedImport(state)
        for _, action in ipairs(state.actions) do
            if action.overwrite then
                PRT:UpdateCompRoster(action.name, action.roster)
            else
                PRT:AddComp(action.name, action.roster)
            end
        end

        importConflictPopup._state = nil
        importConflictPopup._suppressCancel = true
        importConflictPopup:Hide()
        importConflictPopup._suppressCancel = nil

        panel:RefreshQuickLoad()
        panel:LoadComp(state.firstImported)
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end

        local count = #state.actions
        local msg = "Imported " .. count .. " PRT composition" .. (count == 1 and "" or "s") .. "."
        local details = {}
        if state.overwritten > 0 then
            details[#details + 1] = state.overwritten .. " overwritten"
        end
        if state.renamed > 0 then
            details[#details + 1] = state.renamed .. " renamed"
        end
        if #details > 0 then msg = msg .. " " .. table.concat(details, ", ") .. "." end
        PRT.Print(msg)
    end

    local function ShowNamedImportConflict(state, existing)
        local comp = state.comps[state.index]
        local name = PRT.Trim(comp.name)
        importConflictPopup._state = state
        importConflictPopup._existingConflict = existing and true or false
        importConflictPopup.titleLabel:SetText("Raid Group Already Exists")
        if existing then
            conflictMessage:SetText("Raid group " .. state.index .. " of " .. #state.comps
                .. " is named '" .. name .. "', which already exists. Overwrite it or enter a new name.")
            overwriteImportBtn:SetLabel("Overwrite")
        else
            conflictMessage:SetText("Raid group " .. state.index .. " of " .. #state.comps
                .. " repeats the name '" .. name .. "' in this import. Replace the earlier copy or enter a new name.")
            overwriteImportBtn:SetLabel("Use This Copy")
        end
        conflictError:SetText("")
        conflictNameEdit:SetText(SuggestImportName(state, name))
        importConflictPopup:Show()
        importConflictPopup:BringToFront()
        conflictNameEdit:SetFocus()
        conflictNameEdit:HighlightText()
    end

    ContinueNamedImport = function(state)
        while state.index <= #state.comps do
            local comp = state.comps[state.index]
            local name = PRT.Trim(comp.name)
            local existing = PRT:GetComp(name) ~= nil
            if existing or state.finalByName[name] then
                ShowNamedImportConflict(state, existing)
                return
            end
            QueueNamedImport(state, name, comp.roster, false)
            state.index = state.index + 1
        end
        CommitNamedImport(state)
    end

    local function ChooseOverwrite()
        local state = importConflictPopup._state
        if not state then return end
        local comp = state.comps[state.index]
        local name = PRT.Trim(comp.name)
        local actionIndex = state.finalByName[name]
        if actionIndex then
            state.actions[actionIndex].roster = comp.roster
        else
            QueueNamedImport(state, name, comp.roster, true)
        end
        state.overwritten = state.overwritten + 1
        state.index = state.index + 1
        ContinueNamedImport(state)
    end

    local function ChooseRename()
        local state = importConflictPopup._state
        if not state then return end
        local name = PRT.Trim(conflictNameEdit:GetText())
        if name == "" then
            conflictError:SetText("Enter a name for this raid group.")
            return
        end
        if RenameUnavailable(state, name) then
            conflictError:SetText("'" .. name .. "' is already in use. Choose another name.")
            return
        end
        local comp = state.comps[state.index]
        QueueNamedImport(state, name, comp.roster, false)
        state.renamed = state.renamed + 1
        state.index = state.index + 1
        ContinueNamedImport(state)
    end

    overwriteImportBtn:SetScript("OnClick", ChooseOverwrite)
    renameImportBtn:SetScript("OnClick", ChooseRename)
    conflictNameEdit:SetScript("OnEnterPressed", ChooseRename)
    cancelImportBtn:SetScript("OnClick", function() CancelNamedImport() end)
    importConflictPopup:HookScript("OnHide", function(self)
        if self._state and not self._suppressCancel then
            self._state = nil
            PRT.Print("Import cancelled. No raid groups were changed.")
        end
    end)

    function panel:BeginNamedCompositionImport(comps)
        if not comps or #comps == 0 then return false end
        local state = {
            comps = comps,
            actions = {},
            finalByName = {},
            index = 1,
            overwritten = 0,
            renamed = 0,
        }
        ContinueNamedImport(state)
        return true
    end

    panel.importConflictPopup = importConflictPopup

    sipNamePopup.onAccept = function(text)
        local name = PRT.Trim(text)
        if name == "" then return false end
        local roster = sipNamePopup._roster
        if not roster then return false end
        panel:BeginNamedCompositionImport({ { name = name, roster = roster } })
        return true
    end

    ---------------------------------------------------------------------------
    -- Helper: process pasted text, then import directly or show the naming popup
    ---------------------------------------------------------------------------

    local function ProcessShapedPaste(str)
        local shape = shapePopup._selectedShape
        if not shape or PRT.Trim(str) == "" then return end

        if shape == "cooked" then
            local comps = PRT:ParseCookedImport(str)
            shapePopup:Hide()

            if #comps == 0 then
                PRT.Print("No PRT compositions found. Expected [Name] headers followed by roster names.")
                return
            end

            panel:BeginNamedCompositionImport(comps)
            return
        end

        local roster = PRT:ParseShapedImport(str, shape)
        shapePopup:Hide()
        sipNamePopup._roster = roster
        sipNamePopup:Open({ text = "" })
    end

    -- Shape layout definitions
    local shapes = {
        { key = "2col",   label = "G1  G2\nG3  G4\nG5  G6\nG7  G8" },
        { key = "8col",   label = "G1 G2 G3 G4 ..." },
        { key = "1col",   label = "G1\nG2\nG3\nG4\n..." },
        { key = "cooked", label = "PRT\nImport", exportLabel = "PRT\nFormat" },
    }

    local sipShapeBtns = {}
    local sipBtnsX = math.floor((520 - 4 * SB_BTN_W - 3 * SB_BTN_GAP) / 2)
    for i, shape in ipairs(shapes) do
        local btn = W.CreateSelectableButton(shapePopup, shape.label, {
            width = SB_BTN_W,
            height = SB_BTN_H,
            bgColor = { 0.08, 0.08, 0.08, 0.9 },
            hoverBgColor = { 0.12, 0.12, 0.12, 0.9 },
            selectedBgColor = { 0.12, 0.15, 0.12, 0.95 },
            borderColor = PRT.C.BORDER,
            selectedBorderColor = PRT.C.TITLE,
            textColor = { 0.8, 0.8, 0.8, 1 },
            selectedTextColor = { PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1 },
            fontSize = PRT.FONT_SIZE - 1,
        })
        btn:SetPoint("TOPLEFT", sipBtnsX + (i - 1) * (SB_BTN_W + SB_BTN_GAP), -28)
        btn.shapeKey = shape.key

        btn:SetScript("OnClick", function(self)
            for _, b in ipairs(sipShapeBtns) do
                b:SetSelected(false)
            end
            self:SetSelected(true)
            shapePopup._selectedShape = self.shapeKey
            PRT:GetDB().settings.lastImportShape = self.shapeKey

            -- If text was already pasted, process it now
            local existing = PRT.Trim(shapePopup._pasteBox:GetText())
            if existing ~= "" then
                ProcessShapedPaste(existing)
            else
                shapePopup._pasteBox.editBox:SetFocus()
            end
        end)

        btn:SetScript("OnEnter", function(self)
            if shapePopup._selectedShape ~= self.shapeKey then self._bgTex:SetColorTexture(0.12, 0.12, 0.12, 0.9) end
        end)
        btn:SetScript("OnLeave", function(self)
            if shapePopup._selectedShape ~= self.shapeKey then self._bgTex:SetColorTexture(0.08, 0.08, 0.08, 0.9) end
        end)

        sipShapeBtns[i] = btn
    end

    -- Paste area
    local sipPasteBox = W.CreateMultiLineEditBox(shapePopup, 496, 200)
    sipPasteBox:SetPoint("TOPLEFT",  12, -114)
    sipPasteBox:SetPoint("TOPRIGHT", -12, -114)
    shapePopup._pasteBox = sipPasteBox

    -- Auto-paste detection: after 150ms of no new input, process the text
    sipPasteBox.editBox:HookScript("OnTextChanged", function(self, isUserInput)
        if not isUserInput then return end
        self._pasteTimer = 0
        self:SetScript("OnUpdate", function(self, elapsed)
            self._pasteTimer = (self._pasteTimer or 0) + elapsed
            if self._pasteTimer >= 0.15 then
                self:SetScript("OnUpdate", nil)
                ProcessShapedPaste(self:GetText())
            end
        end)
    end)

    -- Reset state on show; restore last-used shape if saved
    shapePopup:SetScript("OnShow", function(self)
        sipPasteBox:SetText("")

        -- Deselect all buttons first
        for _, b in ipairs(sipShapeBtns) do
            b:SetSelected(false)
        end

        -- Restore last-used shape
        local lastShape = PRT:GetDB().settings.lastImportShape or ""
        self._selectedShape = nil
        if lastShape ~= "" then
            for _, b in ipairs(sipShapeBtns) do
                if b.shapeKey == lastShape then
                    self._selectedShape = lastShape
                    b:SetSelected(true)
                    break
                end
            end
        end
    end)

    qBtnImport:SetScript("OnClick", function() shapePopup:Show() end)

    ---------------------------------------------------------------------------
    -- Export Popup (single composition)
    ---------------------------------------------------------------------------
    local exportPopup = W.CreateTextTransferPopup("PRT_ExportPopup", {
        width = 520,
        height = 370,
        title = "Export Raid Group",
        instruction = "Choose a layout above, then select all (Ctrl+A) and copy (Ctrl+C):",
        instructionY = -122,
        boxY = -140,
        boxHeight = 190,
        actionText = "Close",
        actionWidth = 110,
    })

    local exportShapeButtons = {}
    local exportBtnsX = math.floor((520 - 4 * SB_BTN_W - 3 * SB_BTN_GAP) / 2)

    local function SelectExportShape(shapeKey)
        if not panel.selectedComp then return end

        exportPopup._selectedShape = shapeKey
        PRT:GetDB().settings.lastExportShape = shapeKey
        for _, button in ipairs(exportShapeButtons) do
            button:SetSelected(button.shapeKey == shapeKey)
        end

        exportPopup.textBox:SetText(PRT:ExportCompRoster(panel.selectedComp, shapeKey))
        exportPopup.textBox.editBox:SetFocus()
        exportPopup.textBox.editBox:HighlightText()
    end

    for i, shape in ipairs(shapes) do
        local btn = W.CreateSelectableButton(exportPopup, shape.exportLabel or shape.label, {
            width = SB_BTN_W,
            height = SB_BTN_H,
            bgColor = { 0.08, 0.08, 0.08, 0.9 },
            hoverBgColor = { 0.12, 0.12, 0.12, 0.9 },
            selectedBgColor = { 0.12, 0.15, 0.12, 0.95 },
            borderColor = PRT.C.BORDER,
            selectedBorderColor = PRT.C.TITLE,
            textColor = { 0.8, 0.8, 0.8, 1 },
            selectedTextColor = { PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1 },
            fontSize = PRT.FONT_SIZE - 1,
        })
        btn:SetPoint("TOPLEFT", exportBtnsX + (i - 1) * (SB_BTN_W + SB_BTN_GAP), -32)
        btn.shapeKey = shape.key
        btn:SetScript("OnClick", function(self)
            SelectExportShape(self.shapeKey)
        end)
        exportShapeButtons[i] = btn
    end

    -- Wire the Export button on the quick panel
    qBtnExport:SetScript("OnClick", function()
        if not panel.selectedComp then PRT.Print("No composition selected."); return end
        exportPopup:Open({
            text = "",
        })
        local shape = PRT:GetDB().settings.lastExportShape or "8col"
        SelectExportShape(shape)
    end)

    ---------------------------------------------------------------------------
    -- Export All Popup
    ---------------------------------------------------------------------------
    local exportAllPopup = W.CreateTextTransferPopup("PRT_ExportAllPopup", {
        width = 450,
        height = 280,
        title = "Export All Compositions",
        instruction = "Select all (Ctrl+A) and copy (Ctrl+C):",
        boxHeight = 200,
        actionText = "Close",
        actionWidth = 110,
    })

    -- Wire the Export All button on the quick panel
    qBtnExportAll:SetScript("OnClick", function()
        local text = PRT:ExportComps()
        exportAllPopup:Open({
            text = text,
            highlight = true,
        })
    end)

    ---------------------------------------------------------------------------
    -- Right info panel (between grid and Quick Load)
    ---------------------------------------------------------------------------
    local infoX = 12 + 2 * (COL_W + COL_GAP) + 10
    local infoPanel = CreateFrame("Frame", nil, panel)
    infoPanel:SetPoint("TOPLEFT",     infoX, gridTop)
    infoPanel:SetPoint("BOTTOMRIGHT", quickPanel, "BOTTOMLEFT", -6, 0)
    W.StyleBox(infoPanel, { 0.06, 0.06, 0.06, 0.85 }, PRT.C.BORDER)
    panel.infoPanel = infoPanel

    -- Midpoint divider
    local midFrame = CreateFrame("Frame", nil, infoPanel)
    midFrame:SetHeight(1)
    midFrame:SetPoint("LEFT",  infoPanel, "LEFT",  0, 0)
    midFrame:SetPoint("RIGHT", infoPanel, "RIGHT", 0, 0)
    midFrame:SetPoint("TOP",   infoPanel, "CENTER", 0, 0)

    -- Missing (top half)
    local missHdr = W.CreateLabel(infoPanel, "Missing",
        PRT.FONT_SIZE, PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
    missHdr:SetPoint("TOPLEFT", 6, -4)

    local missScroll = W.CreateScrollFrame(infoPanel, 0, 0)
    missScroll:SetPoint("TOPLEFT",     2, -18)
    missScroll:SetPoint("BOTTOMRIGHT", midFrame, "BOTTOMRIGHT", -2, 0)
    panel.missScroll  = missScroll
    panel.missButtons = {}

    local divLine = infoPanel:CreateTexture(nil, "ARTWORK")
    divLine:SetPoint("TOPLEFT",  midFrame, "TOPLEFT",  4, 0)
    divLine:SetPoint("TOPRIGHT", midFrame, "TOPRIGHT", -4, 0)
    divLine:SetHeight(1)
    divLine:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.5)

    -- Not in Roster (bottom half)
    local extraHdr = W.CreateLabel(infoPanel, "Not in Roster",
        PRT.FONT_SIZE, PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3])
    extraHdr:SetPoint("TOPLEFT", midFrame, "BOTTOMLEFT", 6, -4)

    local extraScroll = W.CreateScrollFrame(infoPanel, 0, 0)
    extraScroll:SetPoint("TOPLEFT",     midFrame, "BOTTOMLEFT",  2, -18)
    extraScroll:SetPoint("BOTTOMRIGHT", infoPanel, "BOTTOMRIGHT", -2, 34)
    panel.extraScroll  = extraScroll
    panel.extraButtons = {}

    local matcherBtnWrap = CreateFrame("Frame", nil, infoPanel)
    matcherBtnWrap:SetPoint("BOTTOMLEFT", infoPanel, "BOTTOMLEFT", 2, 4)
    matcherBtnWrap:SetPoint("BOTTOMRIGHT", infoPanel, "BOTTOMRIGHT", -2, 4)
    matcherBtnWrap:SetHeight(24)

    local autoMatchBtn = W.CreateButton(matcherBtnWrap, "Auto Match", 120, 24)
    autoMatchBtn:SetPoint("TOPLEFT", 0, 0)
    autoMatchBtn:SetPoint("BOTTOMRIGHT", matcherBtnWrap, "BOTTOM", -2, 0)
    autoMatchBtn:SetScript("OnClick", function()
        if PRT.OpenRosterMatcher then
            PRT:OpenRosterMatcher(panel)
        end
    end)

    local aliasBtn = W.CreateButton(matcherBtnWrap, "Aliases", 120, 24)
    aliasBtn:SetPoint("TOPLEFT", matcherBtnWrap, "TOP", 2, 0)
    aliasBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    aliasBtn:SetScript("OnClick", function()
        if PRT.OpenRosterAliasPopup then
            PRT:OpenRosterAliasPopup(panel)
        end
    end)

    ---------------------------------------------------------------------------
    -- Bottom bar
    ---------------------------------------------------------------------------
    local btnApply = W.CreateButton(panel, "Apply Groups", 150, 26)
    btnApply:SetPoint("BOTTOMLEFT", 12, 6)
    panel.applyGroupsButton = btnApply
    btnApply:SetScript("OnClick", function()
        if panel.selectedComp then
            -- Commit the focused edit to the editor model before Auto-Save Changes
            -- decides whether this Apply should update the saved composition.
            panel:FinishEditing()
            panel:AutoSave()
            local db = PRT:GetDB()
            if panel:IsManualSaveDirty() then
                local changes = panel:GetUnsavedRosterChanges()
                if #changes > 0 then
                    PRT.Print(("Applying saved version - %d unsaved roster %s not included.")
                        :format(#changes, #changes == 1 and "change was" or "changes were"))
                else
                    PRT.Print("Applying saved version - unsaved roster matching changes were not included.")
                end
            end
            PRT:RequestReorder(panel.selectedComp, db.settings.forcePositions)
        end
    end)
    W.AttachTooltip(btnApply, {
        anchor = "ANCHOR_TOP",
        minWidth = 360,
        shouldShow = function() return panel:ShouldShowApplyTooltip() end,
        getLines = function() return panel:GetApplyTooltipLines() end,
    })

    local btnSetCurrent = W.CreateButton(panel, "Set Current Roster", 170, 26)
    btnSetCurrent:SetPoint("LEFT", btnApply, "RIGHT", 8, 0)
    btnSetCurrent:SetScript("OnClick", function() panel:SnapshotCurrentRaid() end)
    W.AttachTooltip(btnSetCurrent, {
        anchor = "ANCHOR_TOP",
        title = "Set Current Roster",
        titleColor = PRT.C.TITLE,
        minWidth = 390,
        getLines = function()
            local lines = {
                { "Replaces this composition's roster with the raid's current group layout.", 1, 1, 1, true },
                " ",
                { "Copies every current raid member into their exact group and within-group position.", 1, 1, 1, true },
                { "Stores each player using their full Name-Server identity.", 1, 1, 1, true },
                " ",
                { "This changes the composition only. It does not move anyone in the raid.", 1, 0.82, 0.3, true },
            }
            if PRT:GetDB().settings.keepChanges then
                lines[#lines + 1] = { "Auto-Save Changes is ON: the captured roster will be saved immediately.", 0.2, 1, 0.6, true }
            else
                lines[#lines + 1] = { "Auto-Save Changes is OFF: review the captured roster, then click Save Changes.", 0.8, 0.8, 0.8, true }
            end
            return lines
        end,
    })

    local btnSave = W.CreateButton(panel, "Save Changes", 130, 26)
    btnSave:SetPoint("LEFT", btnSetCurrent, "RIGHT", 8, 0)
    btnSave:SetScript("OnClick", function() panel:CommitRoster() end)
    panel.saveChangesButton = btnSave
    W.AttachTooltip(btnSave, {
        anchor = "ANCHOR_TOP",
        title = "Save Changes: Pending Edits",
        titleColor = PRT.C.GOLD,
        minWidth = 420,
        shouldShow = function() return panel:ShouldShowSaveTooltip() end,
        getLines = function() return panel:GetSaveChangesTooltipLines() end,
    })

    -- Auto-save checkbox (stored under the legacy keepChanges setting key).
    local keepCB = W.CreateCheckbox(panel, "Auto-Save Changes", function(checked)
        local db = PRT:GetDB()
        db.settings.keepChanges = checked
        if checked and panel.dirty and panel.selectedComp then
            panel:AutoSave()
        end
        if checked then PRT:RefreshRealmCompositions() end
        panel:RefreshSaveControls()
    end)
    keepCB:SetPoint("LEFT", btnSave, "RIGHT", 8, 0)
    W.AttachTooltip(keepCB.check, {
        anchor = "ANCHOR_TOP",
        title = "Auto-Save Changes",
        titleColor = PRT.C.TITLE,
        minWidth = 380,
        lines = {
            { "Automatically saves roster edits when you finish editing a cell, move a player, or accept a server match.", 1, 1, 1, true },
            " ",
            { "When disabled, edits remain pending until you click Save Changes.", 1, 0.82, 0.3, true },
            { "Apply Groups and the Floating List continue using the last saved composition.", 0.8, 0.8, 0.8, true },
        },
    })

    -- Force positions checkbox
    local forceCB = W.CreateCheckbox(panel, "Force positions", function(checked)
        local db = PRT:GetDB()
        db.settings.forcePositions = checked
    end)
    forceCB:SetPoint("LEFT", keepCB, "RIGHT", 8, 0)
    W.AttachTooltip(forceCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Also applies exact within-group positions using the planned and batched position sorter. Shift + Left Click a composition in the floating list to run the same sort.", 1, 1, 1, true },
        },
    })

    ---------------------------------------------------------------------------
    -- Panel methods
    ---------------------------------------------------------------------------
    local function SafeRoster(comp)
        if not comp then return {} end
        local r = comp.roster or {}
        while #r < 40 do r[#r + 1] = "" end
        return r
    end

    local function ChangeValue(value)
        value = value or ""
        return value ~= "" and value or "(empty)"
    end

    local function CurrentRaid()
        return IsInRaid() and PRT.GetRaidRoster() or {}
    end

    local function AddTooltipLine(lines, text, color)
        color = color or PRT.C.WHITE
        lines[#lines + 1] = {
            text, color[1], color[2], color[3], true,
        }
    end

    local function SlotLocation(index)
        return ("G%d S%d"):format(
            math.floor((index - 1) / 5) + 1,
            ((index - 1) % 5) + 1)
    end

    local function AddDuplicateDetails(lines, duplicates, limit)
        limit = math.min(#duplicates, limit or 4)
        for i = 1, limit do
            local duplicate = duplicates[i]
            local locations = {}
            for _, index in ipairs(duplicate.slots or {}) do
                locations[#locations + 1] = SlotLocation(index)
            end
            AddTooltipLine(lines, ("%s: %s"):format(
                duplicate.displayName or duplicate.key or "Player",
                table.concat(locations, ", ")), PRT.C.RED)
        end
        if #duplicates > limit then
            AddTooltipLine(lines, ("...and %d more duplicate assignments.")
                :format(#duplicates - limit), PRT.C.GRAY)
        end
    end

    local function AddPreflightDetails(lines, preflight)
        if preflight.hardError then
            AddTooltipLine(lines, "Sort blocked", PRT.C.RED)
            if #preflight.invalidExact > 0 then
                AddTooltipLine(lines,
                    "The same exact player is assigned to more than one cell.",
                    PRT.C.RED)
                AddDuplicateDetails(lines, preflight.invalidExact, 4)
            elseif preflight.blockReason then
                AddTooltipLine(lines, preflight.blockReason, PRT.C.RED)
            end
        elseif preflight.noActionable then
            AddTooltipLine(lines, "Nothing can be sorted right now.", PRT.C.GOLD)
            if preflight.blockReason then
                AddTooltipLine(lines, preflight.blockReason, PRT.C.WHITE)
            end
        else
            AddTooltipLine(lines, "Best-effort sort", PRT.C.GOLD)
            AddTooltipLine(lines, ("%d resolved present roster %s will be sorted.")
                :format(preflight.presentResolvedCount,
                    preflight.presentResolvedCount == 1 and "player" or "players"))
        end

        if #preflight.unresolved > 0 then
            AddTooltipLine(lines, ("%d unresolved roster %s will be skipped:")
                :format(#preflight.unresolved,
                    #preflight.unresolved == 1 and "cell" or "cells"), PRT.C.GOLD)
            local limit = math.min(#preflight.unresolved, 5)
            for i = 1, limit do
                local entry = preflight.unresolved[i]
                AddTooltipLine(lines, ("%s (G%d S%d)"):format(
                    entry.raw, entry.group, entry.slot))
            end
            if #preflight.unresolved > limit then
                AddTooltipLine(lines, ("...and %d more.")
                    :format(#preflight.unresolved - limit), PRT.C.GRAY)
            end
            AddTooltipLine(lines,
                "Corresponding live players are unconstrained and may move as collateral.",
                PRT.C.GRAY)
        end

        if #preflight.missing > 0 then
            AddTooltipLine(lines, ("%d resolved roster %s missing from the raid:")
                :format(#preflight.missing,
                    #preflight.missing == 1 and "player is" or "players are"), PRT.C.GOLD)
            local limit = math.min(#preflight.missing, 5)
            for i = 1, limit do
                local entry = preflight.missing[i]
                AddTooltipLine(lines, ("%s (G%d S%d)"):format(
                    entry.raw, entry.group, entry.slot))
            end
            if #preflight.missing > limit then
                AddTooltipLine(lines, ("...and %d more.")
                    :format(#preflight.missing - limit), PRT.C.GRAY)
            end
        end

        if #preflight.extra > 0 then
            AddTooltipLine(lines, ("%d raid %s outside this composition:")
                :format(#preflight.extra,
                    #preflight.extra == 1 and "player is" or "players are"), PRT.C.GOLD)
            local limit = math.min(#preflight.extra, 5)
            for i = 1, limit do
                local entry = preflight.extra[i]
                AddTooltipLine(lines, ("%s (G%d)"):format(
                    entry.name, entry.group))
            end
            if #preflight.extra > limit then
                AddTooltipLine(lines, ("...and %d more.")
                    :format(#preflight.extra - limit), PRT.C.GRAY)
            end
            AddTooltipLine(lines,
                "Outside players are unconstrained and may move as collateral.",
                PRT.C.GRAY)
        end
    end

    function panel:GetUnsavedRosterChanges()
        local changes = {}
        local comp = self.selectedComp and PRT:GetComp(self.selectedComp)
        local saved = comp and comp.roster or {}
        for index = 1, 40 do
            local before = saved[index] or ""
            local after = self.editorRoster[index] or ""
            if before ~= after then
                changes[#changes + 1] = {
                    index = index,
                    group = math.floor((index - 1) / 5) + 1,
                    slot = ((index - 1) % 5) + 1,
                    before = before,
                    after = after,
                }
            end
        end
        return changes
    end

    function panel:IsManualSaveDirty()
        return self.selectedComp ~= nil
            and self.dirty == true
            and not PRT:GetDB().settings.keepChanges
    end

    function panel:GetEditorPreflight()
        return PRT:GetRaidGroupsPreflight(self.editorRoster, CurrentRaid())
    end

    function panel:GetSavedPreflight()
        local comp = self.selectedComp and PRT:GetComp(self.selectedComp)
        return PRT:GetRaidGroupsPreflight(comp and comp.roster or {}, CurrentRaid())
    end

    function panel:GetApplyPreflight()
        if PRT:GetDB().settings.keepChanges then
            return self:GetEditorPreflight(), "Visible editor (saved before Apply)"
        end
        return self:GetSavedPreflight(), "Last saved composition"
    end

    function panel:ShouldShowApplyTooltip()
        if not self.selectedComp then return false end
        local preflight = self:GetApplyPreflight()
        return self:IsManualSaveDirty() or preflight.severity ~= "clean"
    end

    function panel:GetApplyTooltipLines()
        local changes = self:GetUnsavedRosterChanges()
        local lines = {}
        if self:IsManualSaveDirty() then
            AddTooltipLine(lines, "Unsaved editor changes", PRT.C.YELLOW)
            AddTooltipLine(lines, #changes > 0
                and ("This editor has %d unsaved roster %s."):format(
                    #changes, #changes == 1 and "change" or "changes")
                or "This editor has unsaved roster matching changes.")
            AddTooltipLine(lines,
                "Apply Groups will continue using the last saved version.",
                PRT.C.GOLD)
            AddTooltipLine(lines,
                "The visible unsaved changes will not be included.")
            AddTooltipLine(lines, "Click Save Changes first to include them.",
                PRT.C.TITLE)
        end

        local preflight, source = self:GetApplyPreflight()
        if preflight.severity ~= "clean" then
            if #lines > 0 then lines[#lines + 1] = " " end
            AddTooltipLine(lines, "Apply source: " .. source, PRT.C.TITLE)
            AddPreflightDetails(lines, preflight)
        end
        return lines
    end

    function panel:ShouldShowSaveTooltip()
        if not self.selectedComp then return false end
        if self:IsManualSaveDirty() then return true end
        if not self.dirty then return false end
        return #self:GetEditorPreflight().invalidExact > 0
    end

    function panel:GetSaveChangesTooltipLines()
        local changes = self:GetUnsavedRosterChanges()
        local editorPreflight = self:GetEditorPreflight()
        local lines = {
            { ("Composition: %s"):format(self.selectedComp or ""), 1, 1, 1, true },
        }
        if #changes == 0 then
            lines[#lines + 1] = {
                "Roster matching state has unsaved changes.",
                PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3], true,
            }
        else
            lines[#lines + 1] = {
                ("Save %d pending roster %s:"):format(
                    #changes, #changes == 1 and "change" or "changes"),
                PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3], true,
            }
            local limit = math.min(#changes, 6)
            for i = 1, limit do
                local change = changes[i]
                lines[#lines + 1] = {
                    ("Group %d, Slot %d: %s -> %s"):format(
                        change.group, change.slot,
                        ChangeValue(change.before), ChangeValue(change.after)),
                    1, 1, 1, true,
                }
            end
            if #changes > limit then
                lines[#lines + 1] = {
                    ("...and %d more."):format(#changes - limit),
                    PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3], true,
                }
            end
        end

        if #editorPreflight.invalidExact > 0 then
            lines[#lines + 1] = " "
            AddTooltipLine(lines,
                "Saving would persist an invalid roster.", PRT.C.RED)
            AddTooltipLine(lines,
                "The same exact player is assigned to more than one cell.",
                PRT.C.RED)
            AddDuplicateDetails(lines, editorPreflight.invalidExact, 4)
            AddTooltipLine(lines,
                "Saving is allowed, but sorting will be blocked until the extra entries are removed.",
                PRT.C.RED)
        elseif #editorPreflight.unresolved > 0 then
            lines[#lines + 1] = " "
            AddTooltipLine(lines, ("After saving, %d unresolved roster %s will remain.")
                :format(#editorPreflight.unresolved,
                    #editorPreflight.unresolved == 1 and "cell" or "cells"),
                PRT.C.GOLD)
            AddTooltipLine(lines,
                "Best-effort sorting will skip those cells until their server names are resolved.",
                PRT.C.GRAY)
        end

        lines[#lines + 1] = " "
        AddTooltipLine(lines, #editorPreflight.invalidExact > 0
            and "Correct the duplicate cells before applying this composition."
            or "Click to save these changes for Apply Groups, Group Auto Swap, and Smart Assign.",
            PRT.C.TITLE)
        return lines
    end

    function panel:RefreshSaveControls()
        local normal = PRT.C.TITLE
        local isManualDirty = self:IsManualSaveDirty()
        local applyPreflight = self:GetApplyPreflight()
        local editorPreflight = self:GetEditorPreflight()
        local pendingInvalidDuplicate = self.dirty
            and #editorPreflight.invalidExact > 0

        local applyColor = normal
        if not self.selectedComp then
            applyColor = normal
        elseif applyPreflight.severity == "error" then
            applyColor = PRT.C.RED
        elseif isManualDirty or applyPreflight.severity == "warning" then
            applyColor = PRT.C.GOLD
        end
        btnApply.label:SetTextColor(
            applyColor[1], applyColor[2], applyColor[3], applyColor[4] or 1)

        local savePulseColor = pendingInvalidDuplicate and PRT.C.RED
            or (isManualDirty and PRT.C.YELLOW or nil)
        if savePulseColor then
            btnSave._prtSavePulseTo = savePulseColor
            if not btnSave._prtSavePulseActive then
                btnSave._prtSavePulseActive = true
                btnSave._prtSavePulseElapsed = 0
                btnSave.label:SetTextColor(PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3], 1)
                btnSave:SetScript("OnUpdate", function(button, elapsed)
                    button._prtSavePulseElapsed = (button._prtSavePulseElapsed + elapsed) % 2.4
                    local phase = button._prtSavePulseElapsed / 2.4
                    local blend = 0.5 - 0.5 * math.cos(phase * math.pi * 2)
                    local from, to = PRT.C.GOLD, button._prtSavePulseTo
                    button.label:SetTextColor(
                        from[1] + (to[1] - from[1]) * blend,
                        from[2] + (to[2] - from[2]) * blend,
                        from[3] + (to[3] - from[3]) * blend,
                        1)
                end)
            end
        else
            btnSave._prtSavePulseActive = false
            btnSave._prtSavePulseElapsed = 0
            btnSave._prtSavePulseTo = nil
            btnSave:SetScript("OnUpdate", nil)
            btnSave.label:SetTextColor(normal[1], normal[2], normal[3], normal[4] or 1)
        end

        local floatingDirtyComp = isManualDirty and self.selectedComp or nil
        if self._prtFloatingDirtyComp ~= floatingDirtyComp then
            self._prtFloatingDirtyComp = floatingDirtyComp
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        end
    end

    function panel:AutoSave()
        if not self.selectedComp then return end
        if not self.dirty then return end
        local db = PRT:GetDB()
        if not db.settings.keepChanges then return end
        local roster = self:GetEditorRoster()
        PRT:UpdateCompRoster(self.selectedComp, roster)
        self.dirty = false
        self:RefreshSaveControls()
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:RefreshQuickLoad()
        local order = PRT:GetCompOrder()
        local content = self.quickScroll.content

        for _, btn in ipairs(self.quickButtons) do
            btn:ResetHoverAnimation()
            btn:Hide()
        end

        local btnH = 20
        for i, compName in ipairs(order) do
            local btn = self.quickButtons[i]
            if not btn then
                btn = W.CreateSelectableButton(content, "", {
                    height = btnH,
                    bgColor = { 0, 0, 0, 0 },
                    selectedBgColor = PRT.C.MENU_SEL,
                    borderColor = { 0, 0, 0, 0 },
                    selectedBorderColor = { 0, 0, 0, 0 },
                    textColor = { 1, 1, 1, 1 },
                    selectedTextColor = { 1, 1, 1, 1 },
                    selectedFontOutline = "OUTLINE",
                    fontSize = PRT.FONT_SIZE,
                    justifyH = "LEFT",
                    labelPoint = { "LEFT", 6, 0 },
                    hoverAnimation = "MRT",
                    hoverAnimationHeight = btnH,
                    dragButton = "LeftButton",
                })
                btn.label:SetPoint("RIGHT", -4, 0)
                btn:SetScript("OnClick", function(self)
                    panel:LoadComp(self.compName)
                end)

                btn:SetScript("OnDragStart", function(self)
                    if self.orderIndex then
                        for _, quickButton in ipairs(panel.quickButtons) do
                            quickButton:SetHoverAnimationSuspended(true)
                        end
                        qlDrag.active = true
                        qlDrag.sourceIndex = self.orderIndex
                        qlDrag.hoverIndex = nil
                        qlGhost.label:SetText(self.compName)
                        qlGhost:Show()
                    end
                end)
                btn:SetScript("OnDragStop", function()
                    FinishQuickDrag()
                end)

                self.quickButtons[i] = btn
            end

            btn.compName = compName
            btn.orderIndex = i
            btn.label:SetText(compName)

            btn:SetSelected(compName == self.selectedComp)

            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * btnH)
            btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * btnH)
            btn:Show()
        end

        self.quickScroll:UpdateContentHeight(#order * btnH + 2)
    end

    -- Backward compat alias used by FloatingList / other callers
    panel.RefreshDropdown = function(self) self:RefreshQuickLoad() end

    function panel:LoadComp(name)
        self:FinishEditing()
        if self.realmChooser then self.realmChooser:Hide() end
        self:AutoSave()  -- save previous comp if dirty
        self.selectedComp = name
        if self.compNameLabel then
            self.compNameLabel:SetText(name or "")
        end
        local roster = SafeRoster(PRT:GetComp(name))
        self.editorRoster = PRT:CopyRealmRoster(roster)
        self.realmDismissals = {}
        self.dirty = false
        self:RefreshHighlights()
        self:RefreshQuickLoad()
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:CommitRoster()
        if not self.selectedComp then return end
        self:FinishEditing()
        local roster = self:GetEditorRoster()
        PRT:UpdateCompRoster(self.selectedComp, roster)
        self.dirty = false
        self:RefreshSaveControls()
        PRT.Print("Saved: " .. self.selectedComp)
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:SnapshotCurrentRaid()
        if not IsInRaid() then PRT.Print("Not in a raid."); return end
        self:FinishEditing()
        local groups = {}
        for g = 1, 8 do groups[g] = {} end
        local n = GetNumGroupMembers()
        for i = 1, n do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name and subgroup and subgroup >= 1 and subgroup <= 8 then
                local base, realm = PRT:GetRaidMemberIdentity(i, name)
                table.insert(groups[subgroup], PRT:MakeCharacterFullName(base, realm, true))
            end
        end
        for g = 1, 8 do
            while #groups[g] < 5 do groups[g][#groups[g] + 1] = "" end
            for s = 1, 5 do
                PRT:SetRealmRosterSlot(self.editorRoster, (g - 1) * 5 + s, groups[g][s] or "")
            end
        end
        self.dirty = true
        self:RefreshHighlights()
        self:AutoSave()
        PRT.Print("Loaded current raid roster.")
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:DisableMainTankControls()
        if IsInCombat() then return end
        for _, button in ipairs(self.mainTankButtons) do
            button:EnableMouse(false)
        end
    end

    function panel:RefreshMainTankControls(raid)
        if IsInCombat() then return end
        raid = raid or PRT.GetRaidRoster()

        local panelShown = IsPanelVisible()
        local canManage = panelShown and CanManageMainTanks()
        for i = 1, 40 do
            local button = self.mainTankButtons[i]
            local eb = self.slots[i]
            local member, identityKey = GetSlotRaidMember(i, raid)
            local pending = GetPendingRoleState(identityKey)
            local mainTankPending = pending and pending.isMainTank ~= nil
            local usable = button and eb and member and canManage
                and not mainTankPending
            if button then
                button:SetAttribute("unit", usable and member.unit or nil)
                button:SetAttribute("*unit1", usable and member.unit or nil)
                button:SetAttribute("ctrl-unit1", usable and member.unit or nil)
                button:EnableMouse(usable and true or false)
                local debugTexture = button._prtDebugTexture
                if debugTexture then
                    if PRT._groupsRoleDebugEnabled and usable then
                        debugTexture:Show()
                    else
                        debugTexture:Hide()
                    end
                end

                if usable then
                    local left = eb:GetLeft()
                    local bottom = eb:GetBottom()
                    if left and bottom then
                        button:ClearAllPoints()
                        button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                        button:SetSize(eb:GetWidth() or COL_W, eb:GetHeight() or SLOT_H)
                        if button.SetFrameStrata then
                            -- These detached buttons must sit above the config
                            -- window's own overlay buttons to receive Ctrl-clicks.
                            button:SetFrameStrata("TOOLTIP")
                        end
                        if eb.GetFrameLevel and button.SetFrameLevel then
                            button:SetFrameLevel(200 + i)
                        end
                    else
                        button:EnableMouse(false)
                    end
                end
            end
        end
    end

    function panel:RefreshRoleIndicators(raid)
        raid = raid or PRT.GetRaidRoster()
        for i = 1, 40 do
            local member, identityKey = GetSlotRaidMember(i, raid)
            local rankIcon = self.rankIcons[i]
            local mainTankIcon = self.mainTankIcons[i]
            local rank, isMainTank = GetEffectiveRoleState(identityKey, member)

            if rankIcon then
                if member and rank == 2 then
                    rankIcon:SetTexture(LEADER_ICON)
                    rankIcon:Show()
                elseif member and rank == 1 then
                    rankIcon:SetTexture(ASSISTANT_ICON)
                    rankIcon:Show()
                else
                    rankIcon:Hide()
                end
            end
            if mainTankIcon then
                if member and isMainTank then
                    mainTankIcon:Show()
                else
                    mainTankIcon:Hide()
                end
            end
            LayoutSlotIcons(self, i)
        end
        self:RefreshMainTankControls(raid)
    end

    function panel:SetRoleDebugVisuals(enabled)
        self._roleDebugTrace = {}
        for _, button in ipairs(self.mainTankButtons) do
            local texture = button._prtDebugTexture
            if texture then
                if enabled then texture:Show() else texture:Hide() end
            end
        end
        if not IsInCombat() and IsPanelVisible() then
            self:RefreshMainTankControls()
        end
    end

    function panel:DumpRoleDebug()
        local shown, mouseEnabled, mouseOver = 0, 0, 0
        local hoverSlots = {}
        for i, button in ipairs(self.mainTankButtons) do
            if button:IsShown() then shown = shown + 1 end
            if button.IsMouseEnabled and button:IsMouseEnabled() then
                mouseEnabled = mouseEnabled + 1
            end
            if button.IsMouseOver and button:IsMouseOver() then
                mouseOver = mouseOver + 1
                hoverSlots[#hoverSlots + 1] = tostring(i)
            end
        end
        PRT.Print(("[Role debug] enabled=%s raid=%s combat=%s leader=%s assistant=%s panel=%s ctrl=%s shown=%d mouse=%d hover=%d slots=%s"):format(
            tostring(PRT._groupsRoleDebugEnabled),
            tostring(IsInRaid and IsInRaid() and true or false),
            tostring(IsInCombat()),
            tostring(UnitIsGroupLeader and UnitIsGroupLeader("player") and true or false),
            tostring(UnitIsGroupAssistant and UnitIsGroupAssistant("player") and true or false),
            tostring(IsPanelVisible()),
            tostring(IsControlDown()),
            shown, mouseEnabled, mouseOver,
            #hoverSlots > 0 and table.concat(hoverSlots, ",") or "none"))
        if #self._roleDebugTrace == 0 then
            PRT.Print("[Role debug] no captured click trace")
        else
            for index, message in ipairs(self._roleDebugTrace) do
                PRT.Print(("[Role debug] trace %02d %s"):format(index, message))
            end
        end
    end

    function panel:GetRealmWarningLines(index)
        local state = self.realmStates[index]
        if not state then return {} end
        local lines = {}
        local function Add(text, color)
            color = color or PRT.C.WHITE
            lines[#lines + 1] = { text, color[1], color[2], color[3], true }
        end
        local amber = { 1, 0.82, 0.3 }
        local muted = { 0.8, 0.8, 0.8 }
        local function AddCandidate(prefix, candidate)
            local r, g, b = PRT.GetClassColor(candidate.info.classFile)
            Add(prefix .. candidate.fullName, { r, g, b })
        end
        local expectedBase = string.lower(PRT:SplitNameRealm(state.raw, false) or "")
        local relatedConfirmed = {}
        local relatedUnconfirmed = {}
        for otherIndex, other in ipairs(self.realmStates) do
            if otherIndex ~= index and other.raw ~= "" then
                local otherBase = string.lower(PRT:SplitNameRealm(other.raw, false) or "")
                if expectedBase ~= "" and otherBase == expectedBase then
                    local related = { index = otherIndex, raw = other.raw }
                    if other.key and (other.kind == nil or other.kind == "duplicate") then
                        relatedConfirmed[#relatedConfirmed + 1] = related
                    elseif not other.key then
                        relatedUnconfirmed[#relatedUnconfirmed + 1] = related
                    end
                end
            end
        end
        local action
        if state.kind == "invalid" then
            Add("This exact player is assigned more than once.", PRT.C.RED)
            action = "Remove the extra entry. This warning cannot be dismissed."
        elseif state.kind == "duplicate" then
            Add("Confirmed exact player - advisory only.", PRT.C.GOLD)
            if #relatedUnconfirmed > 0 then
                action = "This assignment is valid. Resolve the highlighted unconfirmed cell, or click this triangle to dismiss this advisory."
            else
                action = "If intended, click the triangle to dismiss this advisory. The assigned player will not change."
            end
        elseif state.kind == "waiting" then
            Add("Unconfirmed roster name - no matching player found.", amber)
            action = "Waiting for a matching player to join the raid."
        elseif state.kind == "claimed" then
            Add("Unconfirmed roster name - matches are already assigned.", amber)
            action = "Move their existing entries or edit this cell. One player cannot fill two cells."
        elseif state.kind == "mismatch" then
            Add("A matching name has an unexpected server.", amber)
            local candidate = state.available and state.available[1]
            action = candidate
                and ("Click the triangle to use " .. candidate.fullName .. " instead.")
                or "Click the triangle to use the detected player instead."
        elseif state.kind == "choose" then
            Add("Unconfirmed roster name - player choice required.", amber)
            action = "Click the triangle to choose the full player name intended for this cell."
        elseif state.kind == "verify" then
            Add("Unconfirmed roster name - matching player found.", amber)
            local candidate = state.available and state.available[1]
            action = candidate
                and ("Click the triangle to confirm " .. candidate.fullName .. " for this cell.")
                or "Click the triangle to confirm the matching player for this cell."
        end
        Add(" ")
        if state.kind == "duplicate" then
            Add("Confirmed: " .. state.raw .. " (" .. SlotLocation(index) .. ")", PRT.C.GOLD)
            Add("This exact assignment is valid.", muted)
            if #relatedUnconfirmed > 0 then
                Add("Still unconfirmed:", amber)
                for _, related in ipairs(relatedUnconfirmed) do
                    Add("  " .. related.raw .. " (" .. SlotLocation(related.index) .. ")", PRT.C.YELLOW)
                end
            else
                Add("Unassigned players sharing this name:", muted)
                for _, candidate in ipairs(state.available or {}) do
                    if candidate.key ~= state.key then AddCandidate("  ", candidate) end
                end
            end
        elseif state.kind ~= "invalid" then
            Add("Expected: " .. state.raw .. " (" .. SlotLocation(index) .. ")", amber)
            if not state.key and #relatedConfirmed > 0 then
                Add("Confirmed elsewhere:", muted)
                for _, related in ipairs(relatedConfirmed) do
                    Add("  " .. related.raw .. " (" .. SlotLocation(related.index) .. ")", PRT.C.GOLD)
                end
            end
            if state.kind == "choose" then
                Add("Available matches:", muted)
                for _, candidate in ipairs(state.available or {}) do AddCandidate("  ", candidate) end
            elseif state.kind == "verify" and state.available and state.available[1] then
                AddCandidate("Available match: ", state.available[1])
            elseif state.kind == "claimed" and #relatedConfirmed == 0 then
                for _, candidate in ipairs(state.candidates or {}) do AddCandidate("Already assigned: ", candidate) end
            elseif state.kind == "mismatch" then
                for _, candidate in ipairs(state.candidates or {}) do AddCandidate("Found in raid: ", candidate) end
            end
        else
            Add("Expected: " .. state.raw .. " (" .. SlotLocation(index) .. ")", PRT.C.RED)
        end
        if action then
            Add(" ")
            Add(action, PRT.C.TITLE)
        end
        if state.kind == "duplicate" then
            Add("The caution returns if these identities change or the composition is reopened.", muted)
        elseif (state.kind == "verify" or state.kind == "mismatch" or state.kind == "choose")
            and not PRT:GetDB().settings.keepChanges then
            Add("Auto-Save Changes is OFF: click Save Changes after accepting.", muted)
        end
        return lines
    end

    function panel:ClickRealmWarning(index)
        self:FinishEditing()
        self:RefreshHighlights()
        local state = self.realmStates[index]
        if not state then return end
        if state.kind == "duplicate" then
            self.realmDismissals[index] = state.signature
            self:RefreshHighlights()
            if GameTooltip then GameTooltip:Hide() end
            return
        end
        if state.kind == "invalid" or #state.available == 0 then return end
        local expected = self.editorRoster[index]
        local selectedComp = self.selectedComp
        local function Accept(key)
            if panel.selectedComp ~= selectedComp then return end
            local ok, message = PRT:AcceptRealmRosterCandidate(panel.editorRoster,
                index, expected, key, IsInRaid() and PRT.GetRaidRoster() or {})
            if ok then panel.dirty = true else PRT.Print(message) end
            panel:RefreshHighlights()
            if panel.realmChooser then panel.realmChooser:Hide() end
            if GameTooltip then GameTooltip:Hide() end
        end
        if #state.available == 1 then
            Accept(state.available[1].key)
            return
        end
        if not self.realmChooser then
            local chooser = W.CreatePopupFrame("PRT_RealmPlayerChooser", 360, 320,
                { title = "Choose Player and Server" })
            chooser.prompt = W.CreateLabel(chooser, "", PRT.FONT_SIZE)
            chooser.prompt:SetPoint("TOPLEFT", 12, -30)
            chooser.prompt:SetWidth(336)
            chooser.scroll = W.CreateScrollFrame(chooser, 0, 0)
            chooser.scroll:SetPoint("TOPLEFT", 10, -58)
            chooser.scroll:SetPoint("BOTTOMRIGHT", -10, 42)
            chooser.buttons = {}
            local cancel = W.CreateButton(chooser, "Cancel", 100, 24)
            cancel:SetPoint("BOTTOM", 0, 10)
            cancel:SetScript("OnClick", function() chooser:Hide() end)
            self.realmChooser = chooser
        end
        local chooser = self.realmChooser
        chooser.prompt:SetText("Expected: " .. expected .. " - select the intended player:")
        for _, button in ipairs(chooser.buttons) do button:Hide() end
        for n, candidate in ipairs(state.available) do
            local button = chooser.buttons[n]
            if not button then
                button = W.CreateButton(chooser.scroll.content, "", 320, 26)
                chooser.buttons[n] = button
            end
            button:SetPoint("TOPLEFT", 0, -(n - 1) * 28)
            button.label:SetText(candidate.fullName)
            local r, g, b = PRT.GetClassColor(candidate.info.classFile)
            button.label:SetTextColor(r, g, b)
            local key = candidate.key
            button:SetScript("OnClick", function() Accept(key) end)
            button:Show()
        end
        chooser.scroll:UpdateContentHeight(#state.available * 28)
        chooser:Show()
    end

    function panel:RefreshDuplicateWarnings(raid)
        raid = raid or (IsInRaid() and PRT.GetRaidRoster() or {})
        self.realmStates = PRT:GetRealmRosterStates(self.editorRoster, raid, self.realmDismissals)
        self.duplicateSlots = {}
        for i = 1, 40 do
            local kind = self.realmStates[i].kind
            if kind and kind ~= "waiting" then self.duplicateSlots[i] = self.realmStates[i] end
            local warning = self.duplicateWarnings[i]
            local button = self.realmWarningButtons[i]
            if self.duplicateSlots[i] then
                local color = RealmWarningColor(kind)
                SetSlotBorder(self, i, color[1], color[2], color[3])
                if warning then
                    warning:SetVertexColor(color[1], color[2], color[3],
                        kind == "duplicate" and 0.7 or 1)
                    warning:Show()
                end
                if button then button:Show() end
            else
                ClearSlotBorder(self, i)
                if warning then
                    warning:SetVertexColor(1, 1, 1, 1)
                    warning:Hide()
                end
                if button then button:Hide() end
            end
            LayoutSlotIcons(self, i)
        end
    end

    function panel:RefreshHighlights()
        if self.refreshGuard:Defer("realm-roster", function() self:RefreshHighlights() end) then return end
        local raid = IsInRaid() and PRT.GetRaidRoster() or {}
        if self.selectedComp and PRT:ReconcileRealmRoster(self.editorRoster, raid,
                PRT:GetDB().settings.requireServerNames) then
            self.dirty = true
        end
        self:RefreshDuplicateWarnings(raid)
        local rosterSet    = {}
        local missing = {}
        local unresolved = 0
        for i = 1, 40 do
            local state = self.realmStates[i]
            if state.key and state.key ~= "" then rosterSet[state.key] = true end
            if state.previewKey then rosterSet[state.previewKey] = true end
            if state.key == nil then unresolved = unresolved + 1 end
            if state.missing then missing[#missing + 1] = state.raw end
        end

        self:RefreshRoleIndicators(raid)

        for i = 1, 40 do
            local eb  = self.slots[i]
            local state = self.realmStates[i]
            self:RenderRealmSlot(i)
            if state.raw == "" then
                eb:SetTextColor(PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
            elseif state.member then
                local r, g, b = PRT.GetClassColor(state.member.classFile)
                eb:SetTextColor(r, g, b)
            elseif not state.missing then
                eb:SetTextColor(PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3])
            else
                eb:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
            end
        end

        -- Missing: in roster but not in raid
        table.sort(missing)

        for _, lbl in ipairs(self.missButtons) do lbl:Hide() end
        local missContent = self.missScroll.content
        local missRowH    = 18
        for i, name in ipairs(missing) do
            local lbl = self.missButtons[i]
            if not lbl then
                lbl = W.CreateRowFrame(missContent, missRowH)
                lbl.fs = W.CreateLabel(lbl, "", PRT.FONT_SIZE - 1, PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
                lbl.fs:SetPoint("LEFT", 6, 0)
                lbl.fs:SetPoint("RIGHT", -4, 0)
                lbl.fs:SetJustifyH("LEFT")
                self.missButtons[i] = lbl
            end
            lbl.fs:SetText(name)
            lbl:ClearAllPoints()
            lbl:SetPoint("TOPLEFT",  missContent, "TOPLEFT",  0, -(i - 1) * missRowH)
            lbl:SetPoint("TOPRIGHT", missContent, "TOPRIGHT", 0, -(i - 1) * missRowH)
            lbl:Show()
        end
        self.missScroll:UpdateContentHeight(#missing * missRowH + 2)

        -- Extra: in raid but not in roster (draggable buttons)
        local extra = {}
        for k, info in pairs(raid) do
            if not rosterSet[k] then
                extra[#extra + 1] = {
                    name      = PRT:MakeCharacterFullName(info.baseName, info.realm, true),
                    display   = PRT:MakeCharacterFullName(info.baseName, info.realm, true),
                    group     = info.subgroup or 0,
                    classFile = info.classFile,
                }
            end
        end
        table.sort(extra, function(a, b)
            if a.group ~= b.group then return a.group < b.group end
            return a.display < b.display
        end)

        for _, btn in ipairs(self.extraButtons) do btn:Hide() end

        local content = self.extraScroll.content
        local btnH    = 20

        for i, info in ipairs(extra) do
            local btn = self.extraButtons[i]
            if not btn then
                btn = W.CreateRowButton(content, btnH, {
                    bgColor = { 0.1, 0.1, 0.1, 0 },
                    fontSize = PRT.FONT_SIZE - 1,
                })

                btn:SetScript("OnEnter", function(self)
                    if self._bgTex then
                        self._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
                            PRT.C.SIDEBAR_SEL[3], 0.5)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    if self._bgTex then
                        self._bgTex:SetColorTexture(0.1, 0.1, 0.1, 0)
                    end
                end)
                btn:SetScript("OnMouseDown", function(self, button)
                    if button == "LeftButton" and not drag.active then
                        panel:StartDrag(self.playerName, nil)
                    end
                end)
                btn:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" then FinishDrag() end
                end)

                self.extraButtons[i] = btn
            end

            btn.playerName = info.name
            local r, g, b = PRT.GetClassColor(info.classFile)
            btn.label:SetText(("%s (G%d)"):format(info.display, info.group))
            btn.label:SetTextColor(r, g, b)

            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * btnH)
            btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * btnH)
            btn:Show()
        end

        self.extraScroll:UpdateContentHeight(#extra * btnH + 2)
        self:AutoSave()
        self:RefreshSaveControls()
        if self.realmStatus then
            self.realmStatus:SetText(self.dirty and "Unsaved changes - click Save Changes"
                or (unresolved > 0 and (unresolved .. " server names unresolved") or ""))
        end
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:OnShow()
        local db = PRT:GetDB()
        keepCB:SetChecked(db.settings.keepChanges or false)
        forceCB:SetChecked(db.settings.forcePositions or false)
        requireCB:SetChecked(not db.settings.requireServerNames)
        hideCB:SetChecked(db.settings.hideServerNames or false)
        if self.selectedComp then
            self:LoadComp(self.selectedComp)
        else
            local order = PRT:GetCompOrder()
            if #order > 0 then
                self:LoadComp(order[1])
            else
                self:RefreshQuickLoad()
            end
        end
    end

    panel:SetScript("OnHide", function(self)
        self:FinishEditing()
        if self.realmChooser then self.realmChooser:Hide() end
        self:DisableMainTankControls()
    end)

    local roleControlRefreshFrame = CreateFrame("Frame")
    roleControlRefreshFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    roleControlRefreshFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    roleControlRefreshFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
    roleControlRefreshFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    roleControlRefreshFrame:RegisterEvent("UI_ERROR_MESSAGE")
    roleControlRefreshFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    roleControlRefreshFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    roleControlRefreshFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            local addonName, functionName = ...
            RoleDebug("%s addon=%s function=%s", event,
                tostring(addonName), tostring(functionName))
        elseif event == "UI_ERROR_MESSAGE" then
            local _, message = ...
            if panel._roleDebugLastClickAt
                and RoleStateNow() - panel._roleDebugLastClickAt <= 4 then
                RoleDebug("UI error after tank click: %s", tostring(message))
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
            if panel._roleDebugLastClickAt
                and RoleStateNow() - panel._roleDebugLastClickAt <= 4 then
                RoleDebug("received %s after tank click", event)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if IsPanelVisible() then
                panel:RefreshMainTankControls()
            else
                panel:DisableMainTankControls()
            end
        elseif not IsInCombat() and IsPanelVisible() and IsControlDown() then
            -- Recalculate absolute hit regions after window movement/resizing.
            panel:RefreshMainTankControls()
        end
    end)

    ---------------------------------------------------------------------------
    -- Composition popups
    ---------------------------------------------------------------------------
    local compNamePopup = W.CreateNamePopup("PRT_GroupsNamePopup", {
        width = 340,
        height = 118,
        placeholder = "Composition name...",
    })

    local compConfirmPopup = W.CreateConfirmPopup("PRT_GroupsConfirmPopup", {
        width = 280,
        height = 92,
        buttonWidth = 74,
        cancelWidth = 74,
        buttonHeight = 22,
        buttonY = 7,
        confirmTextColor = PRT.C.RED,
    })

    local function ClearCompositionEditor()
        panel:FinishEditing()
        panel.selectedComp = nil
        panel.editorRoster = PRT:CopyRealmRoster()
        panel.realmDismissals = {}
        if panel.compNameLabel then panel.compNameLabel:SetText("") end
        for i = 1, 40 do
            if panel.slots[i] then panel.slots[i]:SetText("") end
        end
        panel:RefreshHighlights()
        panel:RefreshQuickLoad()
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    local function LoadFirstCompositionOrClear()
        local order = PRT:GetCompOrder()
        if #order > 0 then
            panel:LoadComp(order[1])
        else
            ClearCompositionEditor()
        end
    end

    ShowNewCompPopup = function()
        compNamePopup:Open({
            title = "New Composition",
            prompt = "Enter new composition name:",
            acceptText = "Create",
            text = "",
            onAccept = function(text)
                local name = PRT.Trim(text)
                if name == "" then return false end
                if PRT:GetComp(name) then
                    PRT.Print("'" .. name .. "' already exists.")
                    return false
                end
                PRT:AddComp(name)
                panel:RefreshQuickLoad()
                panel:LoadComp(name)
                if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
            end,
        })
    end

    ShowRenameCompPopup = function(target)
        target = target or panel.selectedComp
        if not target then return end

        compNamePopup:Open({
            title = "Rename Composition",
            prompt = "Rename composition to:",
            acceptText = "Rename",
            text = target,
            highlight = true,
            onAccept = function(text)
                local newName = PRT.Trim(text)
                if newName == "" then return false end
                if newName == target then return true end
                if PRT:GetComp(newName) then
                    PRT.Print("Name already in use.")
                    return false
                end
                if not PRT:RenameComp(target, newName) then return false end
                panel.selectedComp = newName
                if panel.compNameLabel then panel.compNameLabel:SetText(newName) end
                panel:RefreshQuickLoad()
                if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
            end,
        })
    end

    ShowDeleteCompPopup = function(target)
        target = target or panel.selectedComp
        if not target then return end

        compConfirmPopup:Open({
            title = "Delete Composition",
            message = "Delete '" .. target .. "'?",
            confirmText = "Delete",
            onConfirm = function()
                if PRT:RemoveComp(target) then
                    panel.selectedComp = nil
                    LoadFirstCompositionOrClear()
                    if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
                end
            end,
        })
    end

    ShowDeleteAllCompsPopup = function()
        compConfirmPopup:Open({
            title = "Delete All Compositions",
            message = "Delete ALL compositions? This cannot be undone.",
            confirmText = "Delete All",
            onConfirm = function()
                local db = PRT:GetDB()
                wipe(db.compositions)
                ClearCompositionEditor()
                if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
                PRT.Print("All compositions deleted.")
            end,
        })
    end

    PRT:RegisterTab("groups", panel)
    PRT.groupsPanel = panel
end
