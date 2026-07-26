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

local function ClearSlotBorder(panel, slotIdx)
    SetSlotBorder(panel, slotIdx, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3])
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
    panel.dirty    = false

    local ShowNewCompPopup
    local ShowRenameCompPopup
    local ShowDeleteCompPopup
    local ShowDeleteAllCompsPopup

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

        local targetName = PRT.Trim(targetEB:GetText())

        if drag.sourceSlot then
            local sourceEB = self.slots[drag.sourceSlot]
            if sourceEB then sourceEB:SetText(targetName) end
        end
        targetEB:SetText(drag.sourceName)

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
            eb.slotIndex = idx

            eb:SetScript("OnEditFocusLost", function(self)
                panel.dirty = true
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
                end
            end)

            panel.slots[idx] = eb

            -- Overlay Button (sits on top for drag + click-to-edit)
            local ov = W.CreateOverlayButton(panel, eb, { dragButton = "LeftButton" })
            ov.slotIndex = idx

            ov:SetScript("OnClick", function(self, button)
                if button == "LeftButton" and not drag.active then
                    self:Hide()
                    panel.slots[self.slotIndex]:SetFocus()
                end
            end)
            ov:SetScript("OnDragStart", function(self)
                local name = PRT.Trim(panel.slots[self.slotIndex]:GetText())
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

            panel.overlays[idx] = ov
        end
    end

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
    quickScroll:SetPoint("BOTTOMRIGHT", -2, 78)
    panel.quickScroll  = quickScroll
    panel.quickButtons = {}

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
                    if old.compName == panel.selectedComp then
                        old._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
                            PRT.C.SIDEBAR_SEL[3], PRT.C.SIDEBAR_SEL[4])
                    else
                        old._bgTex:SetColorTexture(0, 0, 0, 0)
                    end
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
                if old.compName == panel.selectedComp then
                    old._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
                        PRT.C.SIDEBAR_SEL[3], PRT.C.SIDEBAR_SEL[4])
                else
                    old._bgTex:SetColorTexture(0, 0, 0, 0)
                end
            end
        end
        qlDrag.active = false
        qlDrag.sourceIndex = nil
        qlDrag.hoverIndex = nil
        qlGhost:Hide()
    end

    ---------------------------------------------------------------------------
    -- Shape Import Popup  (select layout → paste → auto-detect → name popup)
    ---------------------------------------------------------------------------
    local shapePopup = W.CreatePopupFrame("PRT_ShapeImportPopup", 520, 340, {
        title = "Import Paste text below",
    })

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

    sipNamePopup.onAccept = function(text)
        local name = PRT.Trim(text)
        if name == "" then return false end
        local roster = sipNamePopup._roster
        if not roster then return false end
        if PRT:GetComp(name) then
            PRT.Print("'" .. name .. "' already exists.")
            return false
        end
        PRT:AddComp(name, roster)
        panel:RefreshQuickLoad()
        panel:LoadComp(name)
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        PRT.Print("Imported: " .. name)
        return true
    end

    ---------------------------------------------------------------------------
    -- Helper: process pasted text, then import directly or show the naming popup
    ---------------------------------------------------------------------------
    local function MakeUniqueImportName(baseName)
        baseName = PRT.Trim(baseName)
        if baseName == "" then baseName = "Imported" end

        local name = baseName
        local suffix = 2
        while PRT:GetComp(name) do
            name = baseName .. " (" .. suffix .. ")"
            suffix = suffix + 1
        end
        return name, name ~= baseName
    end

    local function ProcessShapedPaste(str)
        local shape = shapePopup._selectedShape
        if not shape or PRT.Trim(str) == "" then return end

        if shape == "cooked" then
            local comps = PRT:ParseCookedImport(str)
            shapePopup:Hide()

            if #comps == 0 then
                PRT.Print("No cooked compositions found. Expected [Name] headers followed by roster names.")
                return
            end

            local firstImported
            local renamedDuplicates = false
            for _, comp in ipairs(comps) do
                local name, renamed = MakeUniqueImportName(comp.name)
                renamedDuplicates = renamedDuplicates or renamed
                PRT:AddComp(name, comp.roster)
                firstImported = firstImported or name
            end

            panel:RefreshQuickLoad()
            panel:LoadComp(firstImported)
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end

            local msg = "Imported " .. #comps .. " cooked composition" .. (#comps == 1 and "" or "s") .. "."
            if renamedDuplicates then
                msg = msg .. " Duplicate names were numbered."
            end
            PRT.Print(msg)
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
        { key = "cooked", label = "PRT\nImport" },
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
        width = 450,
        height = 280,
        title = "Export Raid Group",
        instruction = "Select all (Ctrl+A) and copy (Ctrl+C):",
        boxHeight = 200,
        actionText = "Close",
        actionWidth = 110,
    })

    -- Wire the Export button on the quick panel
    qBtnExport:SetScript("OnClick", function()
        if not panel.selectedComp then PRT.Print("No composition selected."); return end
        local text = PRT:ExportCompRoster(panel.selectedComp)
        exportPopup:Open({
            text = text,
            highlight = true,
        })
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
    btnApply:SetScript("OnClick", function()
        if panel.selectedComp then
            local db = PRT:GetDB()
            PRT:RequestReorder(panel.selectedComp, db.settings.forcePositions)
        end
    end)

    local btnSetCurrent = W.CreateButton(panel, "Set Current Roster", 170, 26)
    btnSetCurrent:SetPoint("LEFT", btnApply, "RIGHT", 8, 0)
    btnSetCurrent:SetScript("OnClick", function() panel:SnapshotCurrentRaid() end)

    local btnSave = W.CreateButton(panel, "Save Changes", 130, 26)
    btnSave:SetPoint("LEFT", btnSetCurrent, "RIGHT", 8, 0)
    btnSave:SetScript("OnClick", function() panel:CommitRoster() end)

    -- Keep changes checkbox (auto-save)
    local keepCB = W.CreateCheckbox(panel, "Keep changes", function(checked)
        local db = PRT:GetDB()
        db.settings.keepChanges = checked
        if checked and panel.dirty and panel.selectedComp then
            panel:AutoSave()
        end
    end)
    keepCB:SetPoint("LEFT", btnSave, "RIGHT", 8, 0)
    W.AttachTooltip(keepCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Automatically save any edits to the current composition.", 1, 1, 1, true },
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

    function panel:AutoSave()
        if not self.selectedComp then return end
        if not self.dirty then return end
        local db = PRT:GetDB()
        if not db.settings.keepChanges then return end
        local roster = {}
        for i = 1, 40 do
            roster[i] = PRT.Trim(self.slots[i]:GetText())
        end
        PRT:UpdateCompRoster(self.selectedComp, roster)
        self.dirty = false
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:RefreshQuickLoad()
        local order = PRT:GetCompOrder()
        local content = self.quickScroll.content

        for _, btn in ipairs(self.quickButtons) do btn:Hide() end

        local btnH = 20
        for i, compName in ipairs(order) do
            local btn = self.quickButtons[i]
            if not btn then
                btn = W.CreateRowButton(content, btnH, {
                    bgColor = { 0, 0, 0, 0 },
                    fontSize = PRT.FONT_SIZE,
                    dragButton = "LeftButton",
                })

                btn:SetScript("OnEnter", function(self)
                    if self.compName ~= panel.selectedComp then
                        self._bgTex:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    if self.compName ~= panel.selectedComp then
                        self._bgTex:SetColorTexture(0, 0, 0, 0)
                    end
                end)
                btn:SetScript("OnClick", function(self)
                    panel:LoadComp(self.compName)
                end)

                btn:SetScript("OnDragStart", function(self)
                    if self.orderIndex then
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

            if compName == self.selectedComp then
                btn._bgTex:SetColorTexture(
                    PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
                    PRT.C.SIDEBAR_SEL[3], PRT.C.SIDEBAR_SEL[4])
                btn.label:SetTextColor(PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1)
            else
                btn._bgTex:SetColorTexture(0, 0, 0, 0)
                btn.label:SetTextColor(1, 1, 1, 1)
            end

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
        self:AutoSave()  -- save previous comp if dirty
        self.selectedComp = name
        if self.compNameLabel then
            self.compNameLabel:SetText(name or "")
        end
        local roster = SafeRoster(PRT:GetComp(name))
        for i = 1, 40 do
            self.slots[i]:SetText(roster[i] or "")
        end
        self.dirty = false
        self:RefreshHighlights()
        self:RefreshQuickLoad()
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:CommitRoster()
        if not self.selectedComp then return end
        local roster = {}
        for i = 1, 40 do
            roster[i] = PRT.Trim(self.slots[i]:GetText())
        end
        PRT:UpdateCompRoster(self.selectedComp, roster)
        self.dirty = false
        PRT.Print("Saved: " .. self.selectedComp)
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:SnapshotCurrentRaid()
        if not IsInRaid() then PRT.Print("Not in a raid."); return end
        local groups = {}
        for g = 1, 8 do groups[g] = {} end
        local n = GetNumGroupMembers()
        for i = 1, n do
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name and subgroup and subgroup >= 1 and subgroup <= 8 then
                table.insert(groups[subgroup], name)
            end
        end
        for g = 1, 8 do
            while #groups[g] < 5 do groups[g][#groups[g] + 1] = "" end
            for s = 1, 5 do
                self.slots[(g - 1) * 5 + s]:SetText(groups[g][s] or "")
            end
        end
        self.dirty = true
        self:RefreshHighlights()
        self:AutoSave()
        PRT.Print("Loaded current raid roster.")
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:RefreshHighlights()
        local rosterSet    = {}
        local rosterPretty = {}
        for i = 1, 40 do
            local raw = PRT.Trim(self.slots[i]:GetText())
            local k   = PRT:GetPlayerIdentityKey(raw)
            if k ~= "" then
                rosterSet[k]    = true
                rosterPretty[k] = raw
            end
        end

        local raid = PRT.GetRaidRoster()

        for i = 1, 40 do
            local eb  = self.slots[i]
            local raw = PRT.Trim(eb:GetText())
            local k   = PRT:GetPlayerIdentityKey(raw)
            if k == "" then
                eb:SetTextColor(PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
            elseif raid[k] then
                local r, g, b = PRT.GetClassColor(raid[k].classFile)
                eb:SetTextColor(r, g, b)
            else
                eb:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
            end
        end

        -- Missing: in roster but not in raid
        local missing = {}
        for k, pretty in pairs(rosterPretty) do
            if not raid[k] then missing[#missing + 1] = pretty end
        end
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
                    name      = info.name,
                    display   = info.displayName or info.name,
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
        if PRT.RefreshRosterMatcherPopup then PRT:RefreshRosterMatcherPopup() end
    end

    function panel:OnShow()
        local db = PRT:GetDB()
        keepCB:SetChecked(db.settings.keepChanges or false)
        forceCB:SetChecked(db.settings.forcePositions or false)
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

    ---------------------------------------------------------------------------
    -- Composition popups
    ---------------------------------------------------------------------------
    local compNamePopup = W.CreateNamePopup("PRT_GroupsNamePopup", {
        width = 340,
        height = 118,
        placeholder = "Composition name...",
    })

    local compConfirmPopup = W.CreateConfirmPopup("PRT_GroupsConfirmPopup", {
        width = 340,
        height = 110,
        confirmTextColor = PRT.C.RED,
    })

    local function ClearCompositionEditor()
        panel.selectedComp = nil
        if panel.compNameLabel then panel.compNameLabel:SetText("") end
        for i = 1, 40 do
            if panel.slots[i] then panel.slots[i]:SetText("") end
        end
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
