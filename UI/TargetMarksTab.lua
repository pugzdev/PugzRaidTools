---------------------------------------------------------------------------
-- PugzRaidTools - Target Marks Configuration Tab
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local SLOT_ROW_H = 24
local SLOT_BTN_H = 18
local ENTRY_GAP = 8
local SLOT_BTN_GAP = 4

local PAD_X = 8
local NPC_W = 78
local NAME_W = 170
local SLOT_W = 106
local SLOT_GAP = 8
local DELETE_W = 24
local SLOT_ADD_W = 64
local SLOT_REMOVE_W = SLOT_W - SLOT_ADD_W - SLOT_BTN_GAP

local COL_NPC = PAD_X
local COL_NAME = COL_NPC + NPC_W + 8
local COL_MAIN = COL_NAME + NAME_W + 8
local COL_ALT1 = COL_MAIN + SLOT_W + SLOT_GAP
local COL_ALT2 = COL_ALT1 + SLOT_W + SLOT_GAP
local COL_DELETE = COL_ALT2 + SLOT_W + SLOT_GAP

local SLOT_COLUMNS = {
    { key = "main", label = "Main Mark", x = COL_MAIN },
    { key = "alt1", label = "Alternative 1", x = COL_ALT1 },
    { key = "alt2", label = "Alternative 2", x = COL_ALT2 },
}

local ENTRY_TOP_PAD = 6
local ENTRY_BOTTOM_PAD = 6
local EDITOR_HEADER_OFFSET = 90
local EDITOR_BOTTOM_PAD = 34

local MARK_ITEMS = {
    { text = "-", value = 0 },
}

for _, mi in ipairs(PRT.MARK_ICONS) do
    if mi.id > 0 then
        MARK_ITEMS[#MARK_ITEMS + 1] = {
            text = string.format(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s",
                mi.id, mi.name),
            value = mi.id,
        }
    end
end

local function GetActivePreset()
    return PRT:GetActiveTargetMarksPreset()
end

local function NewBlankEntry()
    return PRT:CreateTargetMarksEntry(0, "")
end

function PRT:BuildTargetMarksTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel._entryUiState = {}
    panel._refreshGuard = W.CreateDeferredRefreshGuard()

    -----------------------------------------------------------------------
    -- Popups
    -----------------------------------------------------------------------
    local namePopup = W.CreateNamePopup("PRT_TargetMarksNamePopup", {
        width = 320,
        height = 110,
        prompt = false,
        placeholder = "Enter name...",
        buttonHeight = 22,
        buttonY = 10,
    })

    local importPopup = W.CreateTextTransferPopup("PRT_TargetMarksImportPopup", {
        width = 450,
        height = 280,
        boxHeight = 180,
        actionText = "Import",
        actionWidth = 100,
        cancelText = "Cancel",
    })

    local exportPopup = W.CreateTextTransferPopup("PRT_TargetMarksExportPopup", {
        width = 450,
        height = 280,
        instruction = "Select all: Ctrl+A  then copy: Ctrl+C",
        boxHeight = 204,
        actionText = "Close",
    })

    local overwriteConfirmPopup = W.CreateConfirmPopup("PRT_TargetMarksOverwriteConfirmPopup", {
        width = 360,
        height = 120,
        confirmText = "Overwrite",
        confirmTextColor = PRT.C.RED,
    })

    local deleteConfirmPopup = W.CreateConfirmPopup("PRT_TargetMarksDeleteConfirmPopup", {
        width = 360,
        height = 120,
        confirmText = "Delete",
        confirmTextColor = PRT.C.RED,
    })

    local conflictPopup = W.CreatePopupFrame("PRT_TargetMarksImportConflictPopup", 380, 124, {
        title = "Name Already Exists",
    })

    local conflictMessage = W.CreateDescription(conflictPopup, "", {
        width = 356,
        color = { 0.9, 0.9, 0.9, 1 },
    })
    conflictMessage:SetPoint("TOPLEFT", 12, -32)
    conflictMessage:SetPoint("TOPRIGHT", -12, -32)

    local conflictRenameBtn = W.CreateButton(conflictPopup, "Rename", 100, 22)
    conflictRenameBtn:SetPoint("BOTTOMLEFT", 12, 10)

    local conflictOverwriteBtn = W.CreateButton(conflictPopup, "Overwrite", 100, 22)
    conflictOverwriteBtn:SetPoint("LEFT", conflictRenameBtn, "RIGHT", 8, 0)
    conflictOverwriteBtn.label:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3], PRT.C.RED[4] or 1)

    local conflictCancelBtn = W.CreateButton(conflictPopup, "Cancel", 80, 22)
    conflictCancelBtn:SetPoint("LEFT", conflictOverwriteBtn, "RIGHT", 8, 0)
    conflictCancelBtn:SetScript("OnClick", function() conflictPopup:Hide() end)

    local function ShowNamePopup(title, defaultText, onOK)
        namePopup:Open({
            title = title,
            text = defaultText or "",
            onAccept = function(text)
                text = PRT.Trim(text)
                if text == "" then return false end
                return onOK(text)
            end,
        })
    end

    local function ShowImportPopup(title, instruction, onImport)
        importPopup:Open({
            title = title,
            instruction = instruction,
            text = "",
            actionText = "Import",
            onAction = onImport,
        })
    end

    local function ShowExportPopup(title, text)
        exportPopup:Open({
            title = title,
            text = text,
            highlight = true,
        })
    end

    local function FindPresetIndexByName(name)
        local db = PRT:GetDB()
        for idx, preset in ipairs(db.targetMarks.presets or {}) do
            if preset.name == name then
                return idx, preset
            end
        end
    end

    local function FindGroupIndexByName(preset, name)
        if not preset then return end
        for idx, group in ipairs(preset.groups or {}) do
            if group.name == name then
                return idx, group
            end
        end
    end

    local function ShowOverwriteConfirm(kindLabel, name, onConfirm)
        overwriteConfirmPopup:Open({
            title = "Confirm Overwrite",
            message = ("Overwrite the existing %s '%s'? This cannot be undone."):format(kindLabel, name),
            confirmText = "Overwrite",
            onConfirm = onConfirm,
        })
    end

    local function ShowImportConflictPopup(kindLabel, name, onRename, onOverwrite)
        conflictMessage:SetText(
            ("A %s named '%s' already exists. Rename the imported %s, overwrite the existing one, or cancel."):format(
                kindLabel, name, kindLabel))
        conflictRenameBtn:SetScript("OnClick", function()
            conflictPopup:Hide()
            onRename()
        end)
        conflictOverwriteBtn:SetScript("OnClick", function()
            conflictPopup:Hide()
            ShowOverwriteConfirm(kindLabel, name, onOverwrite)
        end)
        conflictPopup:Show()
    end

    local function RefreshAfterImport()
        panel:RefreshTargetMarksView(true)
        C_Timer.After(0, function()
            if panel and panel:IsShown() then
                panel:RefreshTargetMarksView(true)
            end
        end)
    end

    -----------------------------------------------------------------------
    -- Shared selectors/state
    -----------------------------------------------------------------------
    function panel:GetSelectedGroup()
        local preset = GetActivePreset()
        if not preset then
            self.selectedGroupName = nil
            return nil, nil
        end

        PRT:EnsureTargetMarksPresetDefaults(preset)

        if self.selectedGroupName then
            for idx, group in ipairs(preset.groups) do
                if group.name == self.selectedGroupName then
                    return group, idx
                end
            end
        end

        if preset.groups[1] then
            self.selectedGroupName = preset.groups[1].name
            return preset.groups[1], 1
        end

        self.selectedGroupName = nil
        return nil, nil
    end

    local function GetEntryUiState(entry)
        local state = panel._entryUiState[entry]
        if not state then
            state = { main = 0, alt1 = 0, alt2 = 0 }
            panel._entryUiState[entry] = state
        end
        return state
    end

    local function ClearEntryUiState(entry)
        panel._entryUiState[entry] = nil
    end

    local function GetVisibleSlotCount(entry, slot)
        local list = PRT:GetTargetMarksSlotList(entry, slot)
        local state = GetEntryUiState(entry)
        local extraBlanks = state[slot] or 0
        local placeholder = (#list == 0) and 1 or 0
        return math.max(1, #list + extraBlanks + placeholder)
    end

    local function GetEntryVisibleCount(entry)
        local maxVisibleCount = 1
        for _, slotInfo in ipairs(SLOT_COLUMNS) do
            local visibleCount = GetVisibleSlotCount(entry, slotInfo.key)
            if visibleCount > maxVisibleCount then
                maxVisibleCount = visibleCount
            end
        end
        return maxVisibleCount
    end

    local function GetEntryHeight(entry)
        return ENTRY_TOP_PAD + (GetEntryVisibleCount(entry) * SLOT_ROW_H) + SLOT_BTN_H + ENTRY_BOTTOM_PAD
    end

    -----------------------------------------------------------------------
    -- Header
    -----------------------------------------------------------------------
    local hdr = W.CreateHeader(panel, "Target Marks")
    hdr:SetPoint("TOPLEFT", 12, -10)

    local desc = W.CreateDescription(panel, nil, {
        width = 600,
        color = { 0.72, 0.72, 0.72, 1 },
    })
    desc:SetPoint("TOPLEFT", 12, -34)
    desc:SetPoint("TOPRIGHT", -12, -34)
    desc:SetText(
        "Automatically apply raid markers to NPCs while mousing over them with a configured modifier held. " ..
        "Each NPC row can hold multiple mark priorities per modifier, so you can use multiple modifiers to " ..
        "apply an alternative set of marks to the same targets. Marks apply while modifier is held."
    )

    local enableCB = W.CreateCheckbox(panel, "Enable Target Marking", function(checked)
        local db = PRT:GetDB()
        db.targetMarks.enabled = checked
        PRT:HandleTargetMarksModifierChange()
    end)
    enableCB:SetPoint("TOPLEFT", 12, -66)

    -----------------------------------------------------------------------
    -- Preset row
    -----------------------------------------------------------------------
    local presetLabel = W.CreateLabel(panel, "Active Preset:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    presetLabel:SetPoint("TOPLEFT", 12, -94)

    local presetDD = W.CreateDropdown(panel, 190, {}, function(value)
        local db = PRT:GetDB()
        db.targetMarks.activePreset = value
        if PRT.UpdateActivePRTProfileSelection then
            PRT:UpdateActivePRTProfileSelection("targetMarks", value)
        end
        panel.selectedGroupName = nil
        PRT:InvalidateTargetMarksCache()
        panel:RefreshTargetMarksView(true)
    end)
    presetDD:SetPoint("TOPLEFT", 12, -110)

    local btnNewPreset = W.CreateButton(panel, "+ New", 58, 22)
    btnNewPreset:SetPoint("LEFT", presetDD, "RIGHT", 6, 0)

    local btnRenamePreset = W.CreateButton(panel, "Rename", 64, 22)
    btnRenamePreset:SetPoint("LEFT", btnNewPreset, "RIGHT", 4, 0)

    local btnDeletePreset = W.CreateButton(panel, "Delete", 58, 22)
    btnDeletePreset:SetPoint("LEFT", btnRenamePreset, "RIGHT", 4, 0)

    local btnExportPreset = W.CreateButton(panel, "Export", 58, 22)
    btnExportPreset:SetPoint("TOPRIGHT", -12, -110)

    local btnImportPreset = W.CreateButton(panel, "Import", 58, 22)
    btnImportPreset:SetPoint("RIGHT", btnExportPreset, "LEFT", -4, 0)

    -----------------------------------------------------------------------
    -- Global modifiers
    -----------------------------------------------------------------------
    local modLabel = W.CreateLabel(panel, "Main Mouse-over Modifier:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    modLabel:SetPoint("TOPLEFT", 12, -140)

    local modMainDD = W.CreateDropdown(panel, 140, PRT.TARGET_MARK_MODIFIER_ITEMS, function(value)
        local db = PRT:GetDB()
        db.targetMarks.modifiers.main = value
        PRT:HandleTargetMarksModifierChange()
    end)
    modMainDD:SetPoint("TOPLEFT", 170, -136)

    local modAlt1Label = W.CreateLabel(panel, "Alternative Modifier 1:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    modAlt1Label:SetPoint("TOPLEFT", 12, -166)

    local modAlt1DD = W.CreateDropdown(panel, 140, PRT.TARGET_MARK_MODIFIER_ITEMS, function(value)
        local db = PRT:GetDB()
        db.targetMarks.modifiers.alt1 = value
        PRT:HandleTargetMarksModifierChange()
    end)
    modAlt1DD:SetPoint("TOPLEFT", 170, -162)

    local modAlt2Label = W.CreateLabel(panel, "Alternative Modifier 2:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    modAlt2Label:SetPoint("TOPLEFT", 12, -192)

    local modAlt2DD = W.CreateDropdown(panel, 140, PRT.TARGET_MARK_MODIFIER_ITEMS, function(value)
        local db = PRT:GetDB()
        db.targetMarks.modifiers.alt2 = value
        PRT:HandleTargetMarksModifierChange()
    end)
    modAlt2DD:SetPoint("TOPLEFT", 170, -188)

    local note = W.CreateDescription(panel, nil, {
        width = 560,
        color = { 0.62, 0.62, 0.62, 1 },
        fontSize = PRT.FONT_SIZE - 1,
    })
    note:SetPoint("TOPLEFT", 330, -140)
    note:SetPoint("TOPRIGHT", -12, -140)
    note:SetText(
        "Application of marks resets after you stop holding the modifier."
    )

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 12, -222)
    divider:SetPoint("TOPRIGHT", -12, -222)
    divider:SetHeight(1)
    divider:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.5)

    -----------------------------------------------------------------------
    -- Group controls
    -----------------------------------------------------------------------
    local groupsHdr = W.CreateHeader(panel, "Preset Grouping")
    groupsHdr:SetPoint("TOPLEFT", 12, -232)

    local groupDD = W.CreateDropdown(panel, 220, {}, function(value)
        panel.selectedGroupName = value
        panel:RefreshTargetMarksView(true)
    end)
    groupDD:SetPoint("TOPLEFT", 12, -260)

    local btnAddGroup = W.CreateButton(panel, "+ New Group", 96, 22)
    btnAddGroup:SetPoint("LEFT", groupDD, "RIGHT", 6, 0)

    local btnRenameGroup = W.CreateButton(panel, "Rename", 64, 22)
    btnRenameGroup:SetPoint("LEFT", btnAddGroup, "RIGHT", 4, 0)

    local btnDeleteGroup = W.CreateButton(panel, "Delete", 58, 22)
    btnDeleteGroup:SetPoint("LEFT", btnRenameGroup, "RIGHT", 4, 0)

    local btnExportGroup = W.CreateButton(panel, "Export", 58, 22)
    btnExportGroup:SetPoint("RIGHT", btnImportPreset, "RIGHT", 0, 0)
    btnExportGroup:SetPoint("TOP", groupDD, "TOP", 0, 0)

    local btnImportGroup = W.CreateButton(panel, "Import", 58, 22)
    btnImportGroup:SetPoint("RIGHT", btnExportGroup, "LEFT", -4, 0)

    local groupingTransferTooltip = {
        anchor = "ANCHOR_TOP",
        title = "Preset Grouping Import / Export",
        titleColor = PRT.C.TITLE,
        lines = {
            {
                "Transfers only this grouping, typically marks for one raid, battleground, or dungeon.",
                1, 1, 1, true,
            },
            {
                "For the entire Target Marks preset and all its groupings, use the Preset Import / Export buttons above.",
                0.72, 0.72, 0.72, true,
            },
        },
    }
    W.AttachTooltip(btnImportGroup, groupingTransferTooltip)
    W.AttachTooltip(btnExportGroup, groupingTransferTooltip)

    local scroll = W.CreateScrollFrame(panel, 0, 0)
    scroll:SetPoint("TOPLEFT", 12, -292)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    W.StyleBox(scroll, { 0.04, 0.04, 0.04, 0.4 }, PRT.C.BORDER)

    local emptyState = W.CreateDescription(scroll.content, nil, {
        width = 520,
        color = { 0.7, 0.7, 0.7, 1 },
    })
    emptyState:SetPoint("TOPLEFT", 12, -12)
    emptyState:SetText("Create a grouping to start building target mark rules for the active preset.")

    -----------------------------------------------------------------------
    -- Group editor frame
    -----------------------------------------------------------------------
    local editor = CreateFrame("Frame", nil, scroll.content)
    W.StyleBox(editor, { 0.04, 0.04, 0.04, 0.55 }, PRT.C.BORDER)
    editor:SetPoint("TOPLEFT", 2, -2)
    editor:SetPoint("TOPRIGHT", -2, -2)
    editor.rows = {}
    editor.entryMeta = {}
    editor.totalContentHeight = 0
    editor.visibleStartIndex = 1
    editor.visibleEndIndex = 0

    editor.title = W.CreateHeader(editor, "")
    editor.title:SetPoint("TOPLEFT", 8, -8)

    editor.help = W.CreateDescription(editor, nil, {
        width = 560,
        color = { 0.65, 0.65, 0.65, 1 },
        fontSize = PRT.FONT_SIZE - 1,
    })
    editor.help:SetPoint("TOPLEFT", 8, -32)
    editor.help:SetPoint("TOPRIGHT", -8, -32)
    editor.help:SetText(
        "Use one row per NPC. Each modifier column can hold its own priority list of marks for that NPC."
    )

    editor.header = CreateFrame("Frame", nil, editor)
    W.StyleBox(editor.header, { 0.07, 0.07, 0.07, 0.8 }, PRT.C.BORDER)
    editor.header:SetPoint("TOPLEFT", 8, -58)
    editor.header:SetPoint("TOPRIGHT", -8, -58)
    editor.header:SetHeight(24)

    local colNpc = W.CreateLabel(editor.header, "NPC ID", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    colNpc:SetPoint("LEFT", COL_NPC, 0)

    local colName = W.CreateLabel(editor.header, "Target Name", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    colName:SetPoint("LEFT", COL_NAME, 0)

    for _, slotInfo in ipairs(SLOT_COLUMNS) do
        local label = W.CreateLabel(editor.header, slotInfo.label, PRT.FONT_SIZE,
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
        label:SetPoint("LEFT", slotInfo.x, 0)
    end

    local colDelete = W.CreateLabel(editor.header, "Delete", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    colDelete:SetPoint("LEFT", COL_DELETE, 0)

    editor.btnAddEntry = W.CreateButton(editor, "+ Add NPC", 90, 20)

    local markPicker = CreateFrame("Frame", nil, UIParent)
    markPicker:SetFrameStrata("TOOLTIP")
    markPicker:SetClampedToScreen(true)
    markPicker:Hide()
    W.StyleBox(markPicker, { 0.05, 0.05, 0.05, 0.98 }, PRT.C.BORDER)
    markPicker.rows = {}

    local function HideMarkPicker()
        markPicker:Hide()
        markPicker.owner = nil
    end

    local function CreateMarkPickerRow(idx)
        local row = CreateFrame("Button", nil, markPicker)
        row:SetHeight(20)
        W.AddBackground(row, 0, 0, 0, 0)
        row.text = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function(self)
            self._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2], PRT.C.SIDEBAR_SEL[3], PRT.C.SIDEBAR_SEL[4])
        end)
        row:SetScript("OnLeave", function(self)
            self._bgTex:SetColorTexture(0, 0, 0, 0)
        end)
        row:SetPoint("TOPLEFT", 0, -((idx - 1) * 20))
        row:SetPoint("TOPRIGHT", 0, -((idx - 1) * 20))
        markPicker.rows[idx] = row
        return row
    end

    for itemIdx, item in ipairs(MARK_ITEMS) do
        local row = CreateMarkPickerRow(itemIdx)
        row.value = item.value
        row.text:SetText(item.text)
        row:SetScript("OnClick", function(self)
            local owner = markPicker.owner
            HideMarkPicker()
            if owner and owner.OnValuePicked then
                owner:OnValuePicked(self.value)
            end
        end)
    end

    markPicker:SetWidth(SLOT_W)
    markPicker:SetHeight(#MARK_ITEMS * 20)

    local function ToggleMarkPicker(owner)
        if markPicker:IsShown() and markPicker.owner == owner then
            HideMarkPicker()
            return
        end

        markPicker.owner = owner
        markPicker:ClearAllPoints()
        markPicker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
        markPicker:SetWidth(owner:GetWidth())
        markPicker:Show()
    end

    local function GetMarkItemText(value)
        local markId = tonumber(value) or 0
        for _, item in ipairs(MARK_ITEMS) do
            if item.value == markId then
                return item.text
            end
        end
        return tostring(markId)
    end

    local function CreateMarkButton(parent, width, onPick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(width or SLOT_W, SLOT_ROW_H)
        W.StyleBox(btn, PRT.C.INPUT_BG, PRT.C.BORDER)
        btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
        btn:RegisterForClicks("LeftButtonUp")
        btn.selectedValue = 0
        btn.onPick = onPick

        btn.label = W.CreateLabel(btn, "-", PRT.FONT_SIZE, 1, 1, 1)
        btn.label:SetPoint("LEFT", 8, 0)
        btn.label:SetPoint("RIGHT", -20, 0)
        btn.label:SetJustifyH("LEFT")

        btn.arrow = W.CreateLabel(btn, "v", PRT.FONT_SIZE, PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
        btn.arrow:SetPoint("RIGHT", -6, 0)

        function btn:SetSelected(value)
            self.selectedValue = tonumber(value) or 0
            self.label:SetText(GetMarkItemText(self.selectedValue))
        end

        function btn:OnValuePicked(value)
            self:SetSelected(value)
            if self.onPick then
                self.onPick(value)
            end
        end

        btn:SetScript("OnClick", function(self)
            ToggleMarkPicker(self)
        end)
        btn:SetScript("OnHide", function(self)
            if markPicker.owner == self then
                HideMarkPicker()
            end
        end)

        return btn
    end

    local function GetCurrentGroup()
        return panel:GetSelectedGroup()
    end

    local function GetCurrentEntry(rowFrame)
        local group = GetCurrentGroup()
        if not group then return nil end
        return group.entries[rowFrame._idx]
    end

    local function UpdateSlotValue(entry, slot, markIdx, value)
        local list = PRT:GetTargetMarksSlotList(entry, slot)
        local uiState = GetEntryUiState(entry)
        local markId = tonumber(value) or 0

        if markIdx <= #list then
            if markId > 0 then
                list[markIdx] = markId
            else
                table.remove(list, markIdx)
            end
            return
        end

        if markId > 0 then
            table.insert(list, markId)
            if (uiState[slot] or 0) > 0 then
                uiState[slot] = uiState[slot] - 1
            end
        elseif (uiState[slot] or 0) > 0 then
            uiState[slot] = uiState[slot] - 1
        end
    end

    local function RemoveLastSlotValue(entry, slot)
        local list = PRT:GetTargetMarksSlotList(entry, slot)
        local uiState = GetEntryUiState(entry)

        if (uiState[slot] or 0) > 0 then
            uiState[slot] = uiState[slot] - 1
            return true
        end

        if #list > 0 then
            table.remove(list, #list)
            return true
        end

        return false
    end

    local function BuildEntryMeta(group)
        wipe(editor.entryMeta)
        local y = -EDITOR_HEADER_OFFSET

        for idx, entry in ipairs(group.entries) do
            local height = GetEntryHeight(entry)
            editor.entryMeta[idx] = {
                y = y,
                height = height,
            }
            y = y - height - ENTRY_GAP
        end

        editor.addButtonY = y
        editor.totalContentHeight = math.abs(y) + EDITOR_BOTTOM_PAD
    end

    local function GetVisibleEntryRange(group)
        local entryCount = #(group.entries or {})
        if entryCount == 0 then
            return 1, 0
        end

        local scrollTop = scroll.scroll:GetVerticalScroll()
        local viewHeight = scroll.scroll:GetHeight()
        local visibleTop = -scrollTop
        local visibleBottom = visibleTop - viewHeight
        local startIdx, endIdx

        for idx = 1, entryCount do
            local meta = editor.entryMeta[idx]
            local rowTop = meta.y
            local rowBottom = meta.y - meta.height
            if not startIdx and rowBottom <= visibleTop then
                startIdx = idx
            end
            if startIdx and rowTop >= visibleBottom then
                endIdx = idx
            elseif startIdx and rowTop < visibleBottom then
                break
            end
        end

        startIdx = startIdx or 1
        endIdx = endIdx or entryCount

        startIdx = math.max(1, startIdx - 1)
        endIdx = math.min(entryCount, endIdx + 1)

        return startIdx, endIdx
    end

    local function GetOrCreateEntryRow(poolIdx)
        if editor.rows[poolIdx] then return editor.rows[poolIdx] end

        local row = CreateFrame("Frame", nil, editor)
        W.StyleBox(row, { 0.05, 0.05, 0.05, 0.48 }, PRT.C.BORDER)
        row.markBtns = {}
        row.addBtns = {}
        row.removeBtns = {}

        row.npcEB = W.CreateEditBox(row, NPC_W, 20, "NPC")
        row.npcEB:SetPoint("TOPLEFT", COL_NPC, -6)
        row.npcEB:SetScript("OnEditFocusLost", function(self)
            local entry = GetCurrentEntry(row)
            if not entry then return end
            entry.npcId = tonumber(self:GetText()) or 0
            self:SetText(entry.npcId > 0 and tostring(entry.npcId) or "")
            PRT:InvalidateTargetMarksCache()
        end)
        panel._refreshGuard:Track(row.npcEB)

        row.nameEB = W.CreateEditBox(row, NAME_W, 20, "Target note")
        row.nameEB:SetPoint("TOPLEFT", COL_NAME, -6)
        row.nameEB:SetScript("OnEditFocusLost", function(self)
            local entry = GetCurrentEntry(row)
            if not entry then return end
            entry.targetName = self:GetText() or ""
        end)
        panel._refreshGuard:Track(row.nameEB)

        row.delBtn = W.CreateDeleteButton(row, function()
            local group = GetCurrentGroup()
            if not group or not group.entries[row._idx] then return end
            ClearEntryUiState(group.entries[row._idx])
            table.remove(group.entries, row._idx)
            PRT:InvalidateTargetMarksCache()
            panel:RefreshGroupEditor()
        end, {
            width = DELETE_W,
            point = { "TOPLEFT", COL_DELETE, -6 },
        })

        local function GetOrCreateMarkButton(slot, markIdx)
            row.markBtns[slot] = row.markBtns[slot] or {}
            if row.markBtns[slot][markIdx] then
                return row.markBtns[slot][markIdx]
            end

            local btn
            btn = CreateMarkButton(row, SLOT_W, function(value)
                local entry = GetCurrentEntry(row)
                if not entry then return end
                UpdateSlotValue(entry, btn._slot, btn._markIdx, value)
                PRT:InvalidateTargetMarksCache()
                panel:RefreshGroupEditor()
            end)

            row.markBtns[slot][markIdx] = btn
            return btn
        end

        for _, slotInfo in ipairs(SLOT_COLUMNS) do
            local slot = slotInfo.key
            local btn = W.CreateButton(row, "+", SLOT_ADD_W, SLOT_BTN_H, {
                fontSize = PRT.FONT_SIZE,
                clicks = "LeftButtonDown",
            })
            btn:SetFrameLevel(row:GetFrameLevel() + 2)
            btn:SetScript("OnClick", function()
                local entry = GetCurrentEntry(row)
                if not entry then return end
                local uiState = GetEntryUiState(entry)
                uiState[slot] = (uiState[slot] or 0) + 1
                panel:RefreshGroupEditor()
            end)
            row.addBtns[slot] = btn

            local removeBtn = W.CreateButton(row, "-", SLOT_REMOVE_W, SLOT_BTN_H, {
                fontSize = PRT.FONT_SIZE,
                textColor = PRT.C.RED,
                clicks = "LeftButtonDown",
            })
            removeBtn:SetFrameLevel(row:GetFrameLevel() + 2)
            removeBtn:SetScript("OnClick", function()
                local entry = GetCurrentEntry(row)
                if not entry then return end
                if RemoveLastSlotValue(entry, slot) then
                    PRT:InvalidateTargetMarksCache()
                    panel:RefreshGroupEditor()
                end
            end)
            row.removeBtns[slot] = removeBtn
        end

        function row:Refresh(entry)
            PRT:EnsureTargetMarksEntryDefaults(entry)

            self.npcEB:SetText(entry.npcId > 0 and tostring(entry.npcId) or "")
            self.nameEB:SetText(entry.targetName or "")

            local maxVisibleCount = GetEntryVisibleCount(entry)

            for _, slotInfo in ipairs(SLOT_COLUMNS) do
                local slot = slotInfo.key
                local list = PRT:GetTargetMarksSlotList(entry, slot)
                local visibleCount = GetVisibleSlotCount(entry, slot)
                self.markBtns[slot] = self.markBtns[slot] or {}

                for markIdx = 1, math.max(visibleCount, #self.markBtns[slot]) do
                    local btn = GetOrCreateMarkButton(slot, markIdx)
                    if markIdx <= visibleCount then
                        btn._slot = slot
                        btn._markIdx = markIdx
                        btn:SetSelected(list[markIdx] or 0)
                        btn:ClearAllPoints()
                        btn:SetPoint("TOPLEFT", slotInfo.x, -ENTRY_TOP_PAD - ((markIdx - 1) * SLOT_ROW_H))
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end

                local addBtn = self.addBtns[slot]
                addBtn:ClearAllPoints()
                addBtn:SetPoint("TOPLEFT", slotInfo.x, -(ENTRY_TOP_PAD + 2) - (maxVisibleCount * SLOT_ROW_H))
                addBtn:Show()

                local removeBtn = self.removeBtns[slot]
                removeBtn:ClearAllPoints()
                removeBtn:SetPoint("LEFT", addBtn, "RIGHT", SLOT_BTN_GAP, 0)
                removeBtn:Show()
            end

            self:SetHeight(GetEntryHeight(entry))
        end

        editor.rows[poolIdx] = row
        return row
    end

    editor.btnAddEntry:SetScript("OnClick", function()
        local group = GetCurrentGroup()
        if not group then
            PRT.Print("Create a grouping first.")
            return
        end
        group.entries[#group.entries + 1] = NewBlankEntry()
        PRT:InvalidateTargetMarksCache()
        panel:RefreshGroupEditor()
    end)

    -----------------------------------------------------------------------
    -- Preset controls
    -----------------------------------------------------------------------
    btnNewPreset:SetScript("OnClick", function()
        ShowNamePopup("New Preset", "", function(name)
            local db = PRT:GetDB()
            for _, preset in ipairs(db.targetMarks.presets) do
                if preset.name == name then
                    PRT.Print("Preset '" .. name .. "' already exists.")
                    return
                end
            end
            db.targetMarks.presets[#db.targetMarks.presets + 1] = {
                name = name,
                groups = {},
            }
            db.targetMarks.activePreset = name
            if PRT.UpdateActivePRTProfileSelection then
                PRT:UpdateActivePRTProfileSelection("targetMarks", name)
            end
            panel.selectedGroupName = nil
            PRT:InvalidateTargetMarksCache()
            panel:RefreshTargetMarksView(true)
        end)
    end)

    btnRenamePreset:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then
            PRT.Print("No preset selected.")
            return
        end
        ShowNamePopup("Rename Preset", preset.name, function(newName)
            local db = PRT:GetDB()
            for _, other in ipairs(db.targetMarks.presets) do
                if other ~= preset and other.name == newName then
                    PRT.Print("Preset '" .. newName .. "' already exists.")
                    return
                end
            end
            local oldName = preset.name
            preset.name = newName
            db.targetMarks.activePreset = newName
            if PRT.RenamePRTProfilePresetReference then
                PRT:RenamePRTProfilePresetReference("targetMarks", oldName, newName)
            end
            PRT:InvalidateTargetMarksCache()
            panel:RefreshTargetMarksView(true)
        end)
    end)

    btnDeletePreset:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local active = db.targetMarks.activePreset
        if active == "" then return end
        deleteConfirmPopup:Open({
            title = "Delete Preset",
            message = "Delete preset '" .. active .. "'?",
            confirmText = "Delete",
            onConfirm = function()
                for i, preset in ipairs(db.targetMarks.presets) do
                    if preset.name == active then
                        table.remove(db.targetMarks.presets, i)
                        break
                    end
                end

                db.targetMarks.activePreset = db.targetMarks.presets[1] and db.targetMarks.presets[1].name or ""
                if PRT.RemovePRTProfilePresetReference then
                    PRT:RemovePRTProfilePresetReference(
                        "targetMarks", active, db.targetMarks.activePreset)
                end
                panel.selectedGroupName = nil
                PRT:InvalidateTargetMarksCache()
                panel:RefreshTargetMarksView(true)
            end,
        })
    end)

    btnImportPreset:SetScript("OnClick", function()
        ShowImportPopup(
            "Import Preset",
            "Paste a Target Marks Preset export string below.",
            function(text)
                if PRT.Trim(text) == "" then
                    PRT.Print("Nothing to import.")
                    return
                end

                local preset = PRT:ParseTargetMarksPresetString(text)
                if not preset then
                    local groups = PRT:ParseTargetMarksGroupBlocks(text)
                    if #groups == 0 then
                        PRT.Print("No preset or groupings found in import string.")
                        return
                    end
                    preset = {
                        name = "Imported",
                        groups = groups,
                    }
                    PRT:EnsureTargetMarksPresetDefaults(preset)
                end

                local db = PRT:GetDB()
                local existingIdx = FindPresetIndexByName(preset.name)

                local function finishImport(importedPreset)
                    db.targetMarks.presets[#db.targetMarks.presets + 1] = importedPreset
                    db.targetMarks.activePreset = importedPreset.name
                    if PRT.UpdateActivePRTProfileSelection then
                        PRT:UpdateActivePRTProfileSelection("targetMarks", importedPreset.name)
                    end
                    panel.selectedGroupName = nil
                    PRT:InvalidateTargetMarksCache()
                    RefreshAfterImport()
                    PRT.Print(("Imported preset '%s' with %d grouping(s)."):format(
                        importedPreset.name, #importedPreset.groups))
                end

                if existingIdx then
                    ShowImportConflictPopup("preset", preset.name, function()
                        ShowNamePopup("Rename Imported Preset", preset.name, function(newName)
                            if FindPresetIndexByName(newName) then
                                PRT.Print("Preset '" .. newName .. "' already exists.")
                                return false
                            end
                            preset.name = newName
                            finishImport(preset)
                        end)
                    end, function()
                        db.targetMarks.presets[existingIdx] = preset
                        db.targetMarks.activePreset = preset.name
                        if PRT.UpdateActivePRTProfileSelection then
                            PRT:UpdateActivePRTProfileSelection("targetMarks", preset.name)
                        end
                        panel.selectedGroupName = nil
                        PRT:InvalidateTargetMarksCache()
                        RefreshAfterImport()
                        PRT.Print(("Overwrote preset '%s' with imported data."):format(preset.name))
                    end)
                    return true
                end

                finishImport(preset)
                return true
            end)
    end)

    btnExportPreset:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then
            PRT.Print("Select a preset to export.")
            return
        end
        ShowExportPopup("Export Preset", PRT:ExportTargetMarksPreset(preset))
    end)

    -----------------------------------------------------------------------
    -- Group controls
    -----------------------------------------------------------------------
    btnAddGroup:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then
            PRT.Print("Select a preset first.")
            return
        end
        ShowNamePopup("New Grouping", "", function(name)
            preset.groups[#preset.groups + 1] = {
                name = name,
                entries = {},
            }
            panel.selectedGroupName = name
            PRT:InvalidateTargetMarksCache()
            panel:RefreshTargetMarksView(true)
        end)
    end)

    btnRenameGroup:SetScript("OnClick", function()
        local group = GetCurrentGroup()
        if not group then
            PRT.Print("No grouping selected.")
            return
        end
        ShowNamePopup("Rename Grouping", group.name, function(name)
            group.name = name
            panel.selectedGroupName = name
            panel:RefreshTargetMarksView(true)
        end)
    end)

    btnDeleteGroup:SetScript("OnClick", function()
        local preset = GetActivePreset()
        local _, groupIdx = GetCurrentGroup()
        if not preset or not groupIdx then
            PRT.Print("No grouping selected.")
            return
        end
        local group = preset.groups[groupIdx]
        deleteConfirmPopup:Open({
            title = "Delete Grouping",
            message = "Delete grouping '" .. ((group and group.name) or "") .. "'?",
            confirmText = "Delete",
            onConfirm = function()
                local removed = preset.groups[groupIdx]
                if removed then
                    for _, entry in ipairs(removed.entries or {}) do
                        ClearEntryUiState(entry)
                    end
                end

                table.remove(preset.groups, groupIdx)
                panel.selectedGroupName = nil
                PRT:InvalidateTargetMarksCache()
                panel:RefreshTargetMarksView(true)
            end,
        })
    end)

    btnImportGroup:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then
            PRT.Print("Select a preset first.")
            return
        end

        ShowImportPopup(
            "Import Grouping",
            "Paste a Target Marks Group export string below. If the paste contains multiple groupings, only the first one will be used here.",
            function(text)
                if PRT.Trim(text) == "" then
                    PRT.Print("Nothing to import.")
                    return
                end

                local groups = PRT:ParseTargetMarksGroupBlocks(text)
                if #groups == 0 then
                    PRT.Print("No grouping found in import string.")
                    return
                end

                local importedGroup = groups[1]
                local existingIdx = FindGroupIndexByName(preset, importedGroup.name)

                local function finishImport(groupToStore)
                    preset.groups[#preset.groups + 1] = groupToStore
                    panel.selectedGroupName = groupToStore.name
                    PRT:InvalidateTargetMarksCache()
                    RefreshAfterImport()

                    if #groups > 1 then
                        PRT.Print("Imported the first grouping from the pasted string.")
                    end
                end

                if existingIdx then
                    ShowImportConflictPopup("grouping", importedGroup.name, function()
                        ShowNamePopup("Rename Imported Grouping", importedGroup.name, function(newName)
                            if FindGroupIndexByName(preset, newName) then
                                PRT.Print("Grouping '" .. newName .. "' already exists in this preset.")
                                return false
                            end
                            importedGroup.name = newName
                            finishImport(importedGroup)
                        end)
                    end, function()
                        local replacedGroup = preset.groups[existingIdx]
                        if replacedGroup and replacedGroup.entries then
                            for _, entry in ipairs(replacedGroup.entries) do
                                ClearEntryUiState(entry)
                            end
                        end
                        preset.groups[existingIdx] = importedGroup
                        panel.selectedGroupName = importedGroup.name
                        PRT:InvalidateTargetMarksCache()
                        RefreshAfterImport()
                        PRT.Print(("Overwrote grouping '%s' with imported data."):format(importedGroup.name))
                    end)
                    return true
                end

                finishImport(importedGroup)
                return true
            end)
    end)

    btnExportGroup:SetScript("OnClick", function()
        local group = GetCurrentGroup()
        if not group then
            PRT.Print("Select a grouping to export.")
            return
        end
        ShowExportPopup("Export Grouping", PRT:ExportTargetMarksGroup(group))
    end)

    -----------------------------------------------------------------------
    -- Panel refresh
    -----------------------------------------------------------------------
    function panel:RefreshEnabledState()
        local db = PRT:GetDB()
        enableCB:SetChecked(db.targetMarks.enabled and true or false)
    end

    function panel:RefreshPresetDD()
        local db = PRT:GetDB()
        local items = {}
        for _, preset in ipairs(db.targetMarks.presets or {}) do
            items[#items + 1] = { text = preset.name, value = preset.name }
        end
        presetDD:SetItems(items)
        presetDD:SetSelected(db.targetMarks.activePreset)
    end

    function panel:RefreshModifierControls()
        local db = PRT:GetDB()
        local mods = db.targetMarks.modifiers or {}
        modMainDD:SetSelected(mods.main or "CTRL")
        modAlt1DD:SetSelected(mods.alt1 or "ALT")
        modAlt2DD:SetSelected(mods.alt2 or "SHIFT")
    end

    function panel:RefreshGroupDD()
        local preset = GetActivePreset()
        local items = {}
        if preset then
            PRT:EnsureTargetMarksPresetDefaults(preset)
            for _, group in ipairs(preset.groups) do
                items[#items + 1] = { text = group.name, value = group.name }
            end
        end
        groupDD:SetItems(items)
        local group = self:GetSelectedGroup()
        groupDD:SetSelected(group and group.name or "")
    end

    function panel:RefreshGroupEditor()
        local group = self:GetSelectedGroup()

        editor:Hide()
        emptyState:Hide()
        HideMarkPicker()
        for _, row in ipairs(editor.rows) do
            row:Hide()
        end

        if not group then
            emptyState:SetText("Create a grouping to start building target mark rules for the active preset.")
            emptyState:Show()
            scroll:UpdateContentHeight(48)
            editor.visibleStartIndex = 1
            editor.visibleEndIndex = 0
            return
        end

        PRT:EnsureTargetMarksGroupDefaults(group)
        editor.title:SetText(group.name)
        BuildEntryMeta(group)

        editor.btnAddEntry:ClearAllPoints()
        editor.btnAddEntry:SetPoint("TOPLEFT", 8, editor.addButtonY)

        editor:SetHeight(editor.totalContentHeight)
        editor:Show()
        scroll:UpdateContentHeight(editor:GetHeight() + 6)
        self:RefreshVisibleTargetMarkRows()
    end

    function panel:RefreshVisibleTargetMarkRows()
        local group = self:GetSelectedGroup()
        if not group then return end

        local startIdx, endIdx = GetVisibleEntryRange(group)
        editor.visibleStartIndex = startIdx
        editor.visibleEndIndex = endIdx

        local poolIdx = 1
        for entryIdx = startIdx, endIdx do
            local entry = group.entries[entryIdx]
            local meta = editor.entryMeta[entryIdx]
            local row = GetOrCreateEntryRow(poolIdx)
            row._idx = entryIdx
            row:Refresh(entry)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, meta.y)
            row:SetPoint("TOPRIGHT", -8, meta.y)
            row:Show()
            poolIdx = poolIdx + 1
        end

        for idx = poolIdx, #editor.rows do
            editor.rows[idx]:Hide()
        end
    end

    function panel:RequestVisibleTargetMarkRowsRefresh()
        local function RefreshAfterEdit()
            if panel and panel:IsShown() then
                panel:RefreshVisibleTargetMarkRows()
            end
        end

        if self._refreshGuard:Defer("visibleRows", RefreshAfterEdit) then return end
        self:RefreshVisibleTargetMarkRows()
    end

    function panel:RefreshTargetMarksView(deferred)
        self:RefreshPresetDD()
        self:RefreshModifierControls()
        self:RefreshGroupDD()
        self:RefreshGroupEditor()

        if deferred then
            C_Timer.After(0, function()
                if panel and panel:IsShown() then
                    panel:RefreshGroupDD()
                    panel:RefreshGroupEditor()
                end
            end)
        end
    end

    function panel:OnShow()
        PRT:EnsureTargetMarksDBDefaults()
        self:RefreshEnabledState()
        self:RefreshTargetMarksView()
    end

    scroll.scroll:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        if panel and panel:IsShown() then
            panel:RequestVisibleTargetMarkRowsRefresh()
        end
    end)

    PRT:RegisterTab("targetmarks", panel)
    PRT.targetMarksPanel = panel
end
