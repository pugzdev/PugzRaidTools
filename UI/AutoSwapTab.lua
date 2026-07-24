---------------------------------------------------------------------------
-- PugzRaidTools - Auto Swap Configuration Tab
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local ROW_H = 26

-- Row-relative column x offsets (content frame coords; X delete leftmost)
local CX_DEL   = 0    -- delete button (22px)
local CX_COMP  = 27   -- composition dropdown (155px)
local CX_NPC   = 187  -- npc id editbox (77px)
local CX_COUNT = 269  -- kill count editbox (48px)
local CX_REP   = 322  -- repeat checkbox
local CX_EN    = 376  -- enabled checkbox (extra space so "Repeat" header doesn't clip "On")
local CX_NOTE  = 406  -- note (stretches to right edge)

-- Panel-relative header x (scroll starts at x=12; content inset ~5px total)
local HX = 17
local HX_COMP  = HX + CX_COMP
local HX_NPC   = HX + CX_NPC
local HX_COUNT = HX + CX_COUNT
local HX_REP   = HX + CX_REP
local HX_EN    = HX + CX_EN
local HX_NOTE  = HX + CX_NOTE

function PRT:BuildAutoSwapTab()
    local panel = CreateFrame("Frame", nil, UIParent)

    ---------------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------------
    local hdr = W.CreateHeader(panel, "Group Auto Swap")
    hdr:SetPoint("TOPLEFT", 12, -10)

    ---------------------------------------------------------------------------
    -- Description
    ---------------------------------------------------------------------------
    local desc = W.CreateDescription(panel, nil, {
        width = 576,
        color = { 0.72, 0.72, 0.72, 1 },
    })
    desc:SetPoint("TOPLEFT",  12, -34)
    desc:SetPoint("TOPRIGHT", -12, -34)
    desc:SetText(
        "When enabled, Auto Swap monitors NPC deaths during combat and automatically applies a "..
        "saved composition when its trigger conditions are met. Each trigger links a composition "..
        "to an NPC ID. Use 'Count' to require a number of kills before the swap fires (e.g. Trigger after 8 Necropolis Acolyte deaths). Enable 'Repeat' to reset the trigger after it reaches it's "..
        "threshold; leave it off for a one-time swap. Triggers only fire while the addon is "..
        "active in the selected instance (or everywhere if the testing option is enabled). WARNING - Kill counts will reset on /reload OR Log Out!"
    )

    ---------------------------------------------------------------------------
    -- Enable toggle (global)
    ---------------------------------------------------------------------------
    local enableCB = W.CreateCheckbox(panel, "Enable Auto Swap", function(checked)
        local db = PRT:GetDB()
        db.autoSwap.enabled = checked
        PRT:UpdateAutoSwapListeners()
        if PRT.UpdateMinimapIconTint then PRT:UpdateMinimapIconTint() end
        if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
        if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("autoswap") end
    end)
    enableCB:SetPoint("TOPLEFT", 12, -90)

    ---------------------------------------------------------------------------
    -- Divider helper
    ---------------------------------------------------------------------------
    local function MkDivider(yOff)
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetPoint("TOPLEFT",  12, yOff)
        d:SetPoint("TOPRIGHT", -12, yOff)
        d:SetHeight(1)
        d:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.5)
        return d
    end
    MkDivider(-118)

    ---------------------------------------------------------------------------
    -- Preset management row
    ---------------------------------------------------------------------------
    local presetLabel = W.CreateLabel(panel, "Active Preset:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    presetLabel:SetPoint("TOPLEFT", 12, -126)

    local presetDD = W.CreateDropdown(panel, 150, {}, function(value)
        local db = PRT:GetDB()
        db.autoSwap.activeSwapPreset = value
        if PRT.UpdateActivePRTProfileSelection then
            PRT:UpdateActivePRTProfileSelection("autoSwap", value)
        end
        panel:RefreshTriggers()
        panel:RefreshPresetSettings()
        PRT:UpdateAutoSwapListeners()
    end)
    presetDD:SetPoint("TOPLEFT", 12, -142)

    local btnNewPreset = W.CreateButton(panel, "New", 55, 24)
    btnNewPreset:SetPoint("LEFT", presetDD, "RIGHT", 6, 0)

    local btnRenamePreset = W.CreateButton(panel, "Rename", 75, 24)
    btnRenamePreset:SetPoint("LEFT", btnNewPreset, "RIGHT", 4, 0)

    local btnDeletePreset = W.CreateButton(panel, "Delete", 60, 24)
    btnDeletePreset:SetPoint("LEFT", btnRenamePreset, "RIGHT", 4, 0)

    -- Import / Export Preset anchored to the right of the preset row
    local btnExportPreset = W.CreateButton(panel, "Export Preset", 120, 24)
    btnExportPreset:SetPoint("TOPRIGHT", -12, -142)

    local btnImportPreset = W.CreateButton(panel, "Import Preset", 120, 24)
    btnImportPreset:SetPoint("RIGHT", btnExportPreset, "LEFT", -6, 0)

    ---------------------------------------------------------------------------
    -- Preset Settings subsection
    ---------------------------------------------------------------------------
    local presetSettingsHdr = W.CreateLabel(panel, "Preset Settings",
        PRT.FONT_SIZE_HEADER,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    presetSettingsHdr:SetPoint("TOPLEFT", 12, -178)

    -- Active in instance
    local instLabel = W.CreateLabel(panel, "Active in instance:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    instLabel:SetPoint("TOPLEFT", 12, -202)

    local instItems = {}
    for _, info in ipairs(PRT.RAID_INSTANCES) do
        instItems[#instItems + 1] = { text = info.name, value = info.id }
    end

    local instDD = W.CreateDropdown(panel, 180, instItems, function(value)
        local preset = PRT:GetActiveSwapPreset()
        if preset then
            preset.instanceId = value
            PRT:UpdateAutoSwapListeners()
        end
    end)
    instDD:SetPoint("TOPLEFT", 12, -218)

    -- Allow-anywhere toggle (per-preset; bypasses raid + instance checks)
    local anywhereCB = W.CreateCheckbox(panel,
        "Allow outside of instance/raid  (for testing — fires CLEU everywhere)",
        function(checked)
            local preset = PRT:GetActiveSwapPreset()
            if preset then
                preset.allowAnywhere = checked
                PRT:UpdateAutoSwapListeners()
            end
        end)
    anywhereCB:SetPoint("TOPLEFT", 12, -248)

    -- Reset Kill Counters (manual)
    local btnReset = W.CreateButton(panel, "Reset Kill Counters", 150, 24)
    btnReset:SetPoint("TOPLEFT", 12, -274)
    btnReset:SetScript("OnClick", function()
        PRT:ResetKillCounters()
        panel:RefreshPresetSettings()
    end)

    local counterLabel = W.CreateLabel(panel, "", PRT.FONT_SIZE - 1,
        PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
    counterLabel:SetPoint("LEFT", btnReset, "RIGHT", 8, 0)

    ---------------------------------------------------------------------------
    -- Reset on zone out (per-preset toggle with dynamic tooltip)
    ---------------------------------------------------------------------------
    local resetZoneCB = W.CreateCheckbox(panel, "Reset on zone out", function(checked)
        local preset = PRT:GetActiveSwapPreset()
        if preset then
            preset.resetOnZoneOut = checked
        end
    end)
    resetZoneCB:SetPoint("TOPLEFT", 12, -302)

    -- Dynamic tooltip: shows which instance the reset is currently tied to.
    -- Attached to the CheckButton child (the interactive element) via W.AttachTooltip
    -- with a getLines callback so the instance name always reflects current state.
    W.AttachTooltip(resetZoneCB.check, {
        anchor     = "ANCHOR_RIGHT",
        title      = "Reset on Zone Out",
        titleColor = { 1, 1, 1, 1 },
        lineColor  = { 0.8, 0.8, 0.8, 1 },
        getLines   = function()
            local preset   = PRT:GetActiveSwapPreset()
            local instId   = (preset and preset.instanceId) or 0
            local instName = (instId > 0) and (PRT.RAID_INSTANCE_MAP[instId] or tostring(instId)) or nil
            local ls = {
                "When enabled, all kill counters for this preset",
                "reset automatically when you leave the instance",
                "this preset is set to be active in.",
                "",
                "Has no effect when 'Active in instance' is set",
                "to 'Any Raid'.",
                "",
            }
            if instName then
                ls[#ls + 1] = { "Currently linked to: " .. instName, 1, 0.82, 0, true }
            else
                ls[#ls + 1] = { "Not linked — set 'Active in instance' first.", 1, 0.5, 0.5, true }
            end
            return ls
        end,
    })

    ---------------------------------------------------------------------------
    -- Reset on NPC death (per-preset; resets all counters every N kills of NPC)
    -- Layout: label  [NPC ID]  ×  [count]  [note...]
    ---------------------------------------------------------------------------
    local resetDeathLabel = W.CreateLabel(panel, "Reset on NPC death:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    resetDeathLabel:SetPoint("TOPLEFT", 12, -328)

    -- NPC ID editbox
    local resetDeathNpcEB = W.CreateEditBox(panel, 72, 20, "NPC ID")
    resetDeathNpcEB:SetPoint("TOPLEFT", 152, -326)

    -- × separator (reads as "every N kills")
    local resetDeathXLabel = W.CreateLabel(panel, "×", PRT.FONT_SIZE, 0.5, 0.5, 0.5)
    resetDeathXLabel:SetPoint("TOPLEFT", 228, -328)

    -- kill count editbox
    local resetDeathCountEB = W.CreateEditBox(panel, 42, 20, "N")
    resetDeathCountEB:SetPoint("TOPLEFT", 238, -326)

    -- note editbox (stretches to right edge)
    local resetDeathNoteEB = W.CreateEditBox(panel, 80, 20, "note...")
    resetDeathNoteEB:SetPoint("TOPLEFT",  286, -326)
    resetDeathNoteEB:SetPoint("TOPRIGHT", -12, -326)

    ---------------------------------------------------------------------------
    -- Divider 2
    ---------------------------------------------------------------------------
    MkDivider(-356)

    ---------------------------------------------------------------------------
    -- Column headers
    ---------------------------------------------------------------------------
    local function MkHdr(text, x, y)
        local lbl = W.CreateLabel(panel, text, PRT.FONT_SIZE,
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
        lbl:SetPoint("TOPLEFT", x, y)
        return lbl
    end
    local HDR_Y = -364
    MkHdr("Composition", HX_COMP,  HDR_Y)
    MkHdr("NPC ID",      HX_NPC,   HDR_Y)
    MkHdr("Count",       HX_COUNT, HDR_Y)
    MkHdr("Repeat",      HX_REP,   HDR_Y)
    MkHdr("On",          HX_EN,    HDR_Y)
    MkHdr("Note",        HX_NOTE,  HDR_Y)

    ---------------------------------------------------------------------------
    -- Scrollable trigger rows
    ---------------------------------------------------------------------------
    local scrollContainer = W.CreateScrollFrame(panel, 0, 0)
    scrollContainer:SetPoint("TOPLEFT",     12, -380)
    scrollContainer:SetPoint("BOTTOMRIGHT", -12, 36)
    W.StyleBox(scrollContainer, { 0.04, 0.04, 0.04, 0.6 }, PRT.C.BORDER)
    panel.scrollContainer = scrollContainer
    panel.triggerRows = {}

    ---------------------------------------------------------------------------
    -- Bottom row (y=6): + Add Trigger | Import Triggers | Export Triggers
    ---------------------------------------------------------------------------
    local btnAdd = W.CreateButton(panel, "+ Add Trigger", 120, 24)
    btnAdd:SetPoint("BOTTOMLEFT", 12, 6)
    btnAdd:SetScript("OnClick", function()
        local preset = PRT:GetActiveSwapPreset()
        if not preset then
            PRT.Print("No active preset. Create a preset first.")
            return
        end
        preset.triggers[#preset.triggers + 1] = {
            compName  = "",
            npcId     = 0,
            count     = 1,
            repeating = false,
            enabled   = true,
            note      = "",
        }
        panel:RefreshTriggers()
        PRT:UpdateAutoSwapListeners()
    end)

    local btnTrigImport = W.CreateButton(panel, "Import Triggers", 130, 24)
    btnTrigImport:SetPoint("LEFT", btnAdd, "RIGHT", 8, 0)

    local btnTrigExport = W.CreateButton(panel, "Export All Triggers", 130, 24)
    btnTrigExport:SetPoint("LEFT", btnTrigImport, "RIGHT", 8, 0)

    ---------------------------------------------------------------------------
    -- Import Triggers popup
    ---------------------------------------------------------------------------
    local trigImportPopup = W.CreateTextTransferPopup("PRT_TrigImportPopup", {
        width = 450,
        height = 260,
        title = "Import Triggers",
        instruction = "Paste trigger export string (or legacy  [CompName] = npcId  format):",
        boxHeight = 160,
        actionText = "Import",
        actionWidth = 100,
        cancelText = "Cancel",
        onAction = function(text)
            if PRT.Trim(text) == "" then PRT.Print("Nothing to import."); return end
            local triggers = PRT:ParseAutoSwapString(text)
            if #triggers == 0 then PRT.Print("No triggers found."); return end
            local preset = PRT:GetActiveSwapPreset()
            if not preset then
                PRT.Print("No active preset. Create a preset first.")
                return
            end
            for _, t in ipairs(triggers) do
                preset.triggers[#preset.triggers + 1] = t
            end
            PRT.Print(("Imported %d trigger(s) into '%s'."):format(#triggers, preset.name))
            panel:RefreshTriggers()
            PRT:UpdateAutoSwapListeners()
            return true
        end,
    })

    btnTrigImport:SetScript("OnClick", function() trigImportPopup:Open() end)

    ---------------------------------------------------------------------------
    -- Export Triggers Popup
    ---------------------------------------------------------------------------
    local trigExportPopup = W.CreateTextTransferPopup("PRT_TrigExportPopup", {
        width = 450,
        height = 260,
        title = "Export Triggers",
        instruction = "Copy the text below (Ctrl+A then Ctrl+C):",
        boxHeight = 160,
        actionText = "Close",
    })
    local texBox = trigExportPopup.textBox

    btnTrigExport:SetScript("OnClick", function()
        local preset = PRT:GetActiveSwapPreset()
        if not preset or #preset.triggers == 0 then
            PRT.Print("No triggers to export.")
            return
        end
        trigExportPopup.titleLabel:SetText(
            "Export Triggers — " .. (preset.name or ""))
        texBox:SetText(PRT:ExportSwapTriggers(preset.triggers))
        texBox.editBox:SetFocus()
        texBox.editBox:HighlightText()
        trigExportPopup:Show()
    end)

    ---------------------------------------------------------------------------
    -- Import Preset Popup
    ---------------------------------------------------------------------------
    local presetImportPopup = W.CreateTextTransferPopup("PRT_SwapPresetImportPopup", {
        width = 450,
        height = 260,
        title = "Import Preset",
        instruction = "Paste a preset export string ([AutoSwapPreset: Name] format):",
        boxHeight = 160,
        actionText = "Import",
        actionWidth = 100,
        cancelText = "Cancel",
        onAction = function(text)
            if PRT.Trim(text) == "" then PRT.Print("Nothing to import."); return end

            local preset, looseTriggers = PRT:ParseSwapPresetString(text)

            if preset then
                -- Full preset import; ensure runtime-only and default fields exist
                preset.killCounters = {}
                if not preset.resetOnDeath then
                    preset.resetOnDeath = { npcId = 0, count = 1, note = "" }
                end
                local db = PRT:GetDB()
                -- Auto-rename on collision
                local existing = {}
                for _, p in ipairs(db.autoSwap.swapPresets) do existing[p.name] = true end
                if existing[preset.name] then
                    local base = preset.name
                    local n = 2
                    while existing[base .. " (" .. n .. ")"] do n = n + 1 end
                    preset.name = base .. " (" .. n .. ")"
                end
                db.autoSwap.swapPresets[#db.autoSwap.swapPresets + 1] = preset
                db.autoSwap.activeSwapPreset = preset.name
                if PRT.UpdateActivePRTProfileSelection then
                    PRT:UpdateActivePRTProfileSelection("autoSwap", preset.name)
                end
                PRT.Print(("Imported preset '%s' (%d trigger(s))."):format(
                    preset.name, #preset.triggers))
            elseif looseTriggers and #looseTriggers > 0 then
                -- No preset header — add triggers to active preset
                local activePreset = PRT:GetActiveSwapPreset()
                if not activePreset then
                    PRT.Print("No active preset. Create a preset first.")
                    return
                end
                for _, t in ipairs(looseTriggers) do
                    activePreset.triggers[#activePreset.triggers + 1] = t
                end
                PRT.Print(("Imported %d trigger(s) into '%s'."):format(
                    #looseTriggers, activePreset.name))
            else
                PRT.Print("Nothing importable found.")
                return
            end

            panel:RefreshPresetList()
            panel:RefreshTriggers()
            panel:RefreshPresetSettings()
            PRT:UpdateAutoSwapListeners()
            return true
        end,
    })

    btnImportPreset:SetScript("OnClick", function() presetImportPopup:Open() end)

    ---------------------------------------------------------------------------
    -- Export Preset Popup
    ---------------------------------------------------------------------------
    local presetExportPopup = W.CreateTextTransferPopup("PRT_SwapPresetExportPopup", {
        width = 450,
        height = 260,
        title = "Export Preset",
        instruction = "Copy the text below (Ctrl+A then Ctrl+C):",
        boxHeight = 160,
        actionText = "Close",
    })
    local pexBox = presetExportPopup.textBox

    btnExportPreset:SetScript("OnClick", function()
        local preset = PRT:GetActiveSwapPreset()
        if not preset then PRT.Print("No active preset."); return end
        presetExportPopup.titleLabel:SetText("Export Preset — " .. (preset.name or ""))
        pexBox:SetText(PRT:ExportSwapPreset(preset))
        pexBox.editBox:SetFocus()
        pexBox.editBox:HighlightText()
        presetExportPopup:Show()
    end)

    ---------------------------------------------------------------------------
    -- Custom name-input popup (used for New and Rename)
    ---------------------------------------------------------------------------
    local namePopup = W.CreateNamePopup("PRT_SwapPresetNamePopup", {
        width = 340,
        height = 118,
        placeholder = "Preset name...",
    })

    ---------------------------------------------------------------------------
    -- Custom delete-confirm popup
    ---------------------------------------------------------------------------
    local delPopup = W.CreateConfirmPopup("PRT_SwapPresetDeletePopup", {
        width = 340,
        height = 110,
        title = "Delete Preset",
        confirmText = "Delete",
        confirmTextColor = PRT.C.RED,
    })

    ---------------------------------------------------------------------------
    -- Preset management button scripts
    ---------------------------------------------------------------------------

    -- New Preset
    btnNewPreset:SetScript("OnClick", function()
        namePopup:Open({
            title = "New Preset",
            prompt = "Enter a name for the new preset:",
            text = "",
            onAccept = function(name)
                name = PRT.Trim(name)
                if name == "" then PRT.Print("Name cannot be empty."); return false end
                local db = PRT:GetDB()
                for _, p in ipairs(db.autoSwap.swapPresets) do
                    if p.name == name then
                        PRT.Print("A preset named '" .. name .. "' already exists.")
                        return false
                    end
                end
                db.autoSwap.swapPresets[#db.autoSwap.swapPresets + 1] = {
                    name          = name,
                    triggers      = {},
                    instanceId    = 0,
                    allowAnywhere = false,
                    resetOnZoneOut = false,
                    resetOnDeath  = { npcId = 0, count = 1, note = "" },
                    killCounters  = {},   -- runtime-only; never persisted
                }
                db.autoSwap.activeSwapPreset = name
                if PRT.UpdateActivePRTProfileSelection then
                    PRT:UpdateActivePRTProfileSelection("autoSwap", name)
                end
                panel:RefreshPresetList()
                panel:RefreshTriggers()
                panel:RefreshPresetSettings()
                PRT:UpdateAutoSwapListeners()
            end,
        })
    end)

    -- Rename Preset
    btnRenamePreset:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local currentName = db.autoSwap.activeSwapPreset
        if not currentName or currentName == "" then
            PRT.Print("No active preset to rename."); return
        end
        namePopup:Open({
            title = "Rename Preset",
            prompt = "Enter a new name for '" .. currentName .. "':",
            text = currentName,
            highlight = true,
            onAccept = function(newName)
                newName = PRT.Trim(newName)
                if newName == "" then PRT.Print("Name cannot be empty."); return false end
                if newName == currentName then return true end
                local db2 = PRT:GetDB()
                for _, p in ipairs(db2.autoSwap.swapPresets) do
                    if p.name == newName then
                        PRT.Print("A preset named '" .. newName .. "' already exists.")
                        return false
                    end
                end
                for _, p in ipairs(db2.autoSwap.swapPresets) do
                    if p.name == currentName then p.name = newName; break end
                end
                db2.autoSwap.activeSwapPreset = newName
                if PRT.RenamePRTProfilePresetReference then
                    PRT:RenamePRTProfilePresetReference("autoSwap", currentName, newName)
                end
                panel:RefreshPresetList()
            end,
        })
    end)

    -- Delete Preset
    btnDeletePreset:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local currentName = db.autoSwap.activeSwapPreset
        if not currentName or currentName == "" then
            PRT.Print("No active preset to delete."); return
        end
        delPopup:Open({
            title = "Delete Preset",
            message = "Delete preset '" .. currentName .. "'?\n" ..
                "All triggers in it will be lost.",
            confirmText = "Delete",
            onConfirm = function()
                local db2 = PRT:GetDB()
                for i, p in ipairs(db2.autoSwap.swapPresets) do
                    if p.name == currentName then
                        table.remove(db2.autoSwap.swapPresets, i); break
                    end
                end
                db2.autoSwap.activeSwapPreset =
                    (#db2.autoSwap.swapPresets > 0)
                    and db2.autoSwap.swapPresets[1].name
                    or ""
                if PRT.RemovePRTProfilePresetReference then
                    PRT:RemovePRTProfilePresetReference(
                        "autoSwap", currentName, db2.autoSwap.activeSwapPreset)
                end
                panel:RefreshPresetList()
                panel:RefreshTriggers()
                panel:RefreshPresetSettings()
                PRT:UpdateAutoSwapListeners()
            end,
        })
    end)

    ---------------------------------------------------------------------------
    -- Refresh preset dropdown
    ---------------------------------------------------------------------------
    function panel:RefreshPresetList()
        local db = PRT:GetDB()
        local items = {}
        for _, p in ipairs(db.autoSwap.swapPresets) do
            items[#items + 1] = { text = p.name, value = p.name }
        end
        presetDD:SetItems(items)
        presetDD:SetSelected(db.autoSwap.activeSwapPreset)
    end

    ---------------------------------------------------------------------------
    -- Refresh all per-preset settings UI widgets.
    -- Called on OnShow, preset switch, manual reset, and after import.
    ---------------------------------------------------------------------------
    function panel:RefreshPresetSettings()
        local preset = PRT:GetActiveSwapPreset()

        -- Instance filter + allow-anywhere
        instDD:SetSelected((preset and preset.instanceId) or 0)
        anywhereCB:SetChecked((preset and preset.allowAnywhere) or false)

        -- Zone-out reset
        resetZoneCB:SetChecked((preset and preset.resetOnZoneOut) or false)

        -- NPC death reset
        local rod = preset and preset.resetOnDeath
        resetDeathNpcEB:SetText((rod and rod.npcId and rod.npcId > 0) and tostring(rod.npcId) or "")
        resetDeathCountEB:SetText(tostring((rod and rod.count) or 1))
        resetDeathNoteEB:SetText((rod and rod.note) or "")

        -- Kill counter display
        local parts = {}
        if preset and preset.killCounters then
            for npcId, count in pairs(preset.killCounters) do
                parts[#parts + 1] = ("%d: x%d"):format(npcId, count)
            end
        end
        counterLabel:SetText(#parts > 0 and ("Kills: " .. table.concat(parts, ", ")) or "")
    end

    ---------------------------------------------------------------------------
    -- Wire per-preset settings edit boxes
    ---------------------------------------------------------------------------
    resetDeathNpcEB:SetScript("OnEditFocusLost", function(self)
        local preset = PRT:GetActiveSwapPreset()
        if preset then
            preset.resetOnDeath = preset.resetOnDeath or { npcId = 0, count = 1, note = "" }
            preset.resetOnDeath.npcId = tonumber(self:GetText()) or 0
        end
    end)

    resetDeathCountEB:SetScript("OnEditFocusLost", function(self)
        local preset = PRT:GetActiveSwapPreset()
        if preset then
            preset.resetOnDeath = preset.resetOnDeath or { npcId = 0, count = 1, note = "" }
            local v = math.max(1, tonumber(self:GetText()) or 1)
            preset.resetOnDeath.count = v
            self:SetText(tostring(v))
        end
    end)

    resetDeathNoteEB:SetScript("OnEditFocusLost", function(self)
        local preset = PRT:GetActiveSwapPreset()
        if preset then
            preset.resetOnDeath = preset.resetOnDeath or { npcId = 0, count = 1, note = "" }
            preset.resetOnDeath.note = self:GetText()
        end
    end)

    ---------------------------------------------------------------------------
    -- Refresh trigger list
    -- All scripts are re-set on every refresh so closures always reference
    -- the correct preset and row index regardless of preset switches.
    ---------------------------------------------------------------------------
    function panel:RefreshTriggers()
        local preset   = PRT:GetActiveSwapPreset()
        local triggers = preset and preset.triggers or {}
        local content  = self.scrollContainer.content

        -- Hide stale rows
        for _, row in ipairs(self.triggerRows) do row:Hide() end

        local compOrder = PRT:GetCompOrder()
        local compItems = {}
        for _, name in ipairs(compOrder) do
            compItems[#compItems + 1] = { text = name, value = name }
        end

        for i, trigger in ipairs(triggers) do
            local row = self.triggerRows[i]
            if not row then
                row = W.CreateRowFrame(content, ROW_H)

                -- Delete button
                row.delBtn = W.CreateDeleteButton(row, nil, { point = { "LEFT", CX_DEL, 0 } })

                -- Composition dropdown — calls row._onCompSelect for updatability
                row.compDD = W.CreateDropdown(row, 155, {}, function(val)
                    if row._onCompSelect then row._onCompSelect(val) end
                end)
                row.compDD:SetPoint("LEFT", CX_COMP, 0)

                -- NPC ID
                row.npcEB = W.CreateEditBox(row, 77, 20, "NPC ID")
                row.npcEB:SetPoint("LEFT", CX_NPC, 0)

                -- Count
                row.countEB = W.CreateEditBox(row, 48, 20, "#")
                row.countEB:SetPoint("LEFT", CX_COUNT, 0)

                -- Repeat checkbox
                row.repCB = W.CreateCheckButton(row, 20, nil, { point = { "LEFT", CX_REP, 0 } })

                -- Enabled checkbox
                row.enCB = W.CreateCheckButton(row, 20, nil, { point = { "LEFT", CX_EN, 0 } })

                -- Export button (far right; single-trigger export)
                row.expBtn = W.CreateButton(row, "E", 22, 20, {
                    textColor = { 0.8, 0.8, 0.8, 1 },
                })
                row.expBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                W.AttachTooltip(row.expBtn, {
                    anchor    = "ANCHOR_TOP",
                    title     = "Export Trigger",
                    lineColor = { 0.8, 0.8, 0.8, 1 },
                    lines     = { "Export this individual trigger to a shareable text string." },
                })

                -- Note (stretches to fill space left of the export button)
                row.noteEB = W.CreateEditBox(row, 80, 20, "note...")
                row.noteEB:SetPoint("LEFT",  CX_NOTE, 0)
                row.noteEB:SetPoint("RIGHT", row.expBtn, "LEFT", -4, 0)

                self.triggerRows[i] = row
            end

            -- Re-bind all scripts to the CURRENT preset + index.
            local rowIdx = i

            row.delBtn:SetScript("OnClick", function()
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    table.remove(p.triggers, rowIdx)
                    panel:RefreshTriggers()
                    PRT:UpdateAutoSwapListeners()
                end
            end)

            row._onCompSelect = function(val)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    p.triggers[rowIdx].compName = val
                end
            end

            row.npcEB:SetScript("OnEditFocusLost", function(self)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    p.triggers[rowIdx].npcId = tonumber(self:GetText()) or 0
                    PRT:UpdateAutoSwapListeners()
                end
            end)

            row.countEB:SetScript("OnEditFocusLost", function(self)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    local v = math.max(1, tonumber(self:GetText()) or 1)
                    p.triggers[rowIdx].count = v
                    self:SetText(tostring(v))
                end
            end)

            row.repCB:SetScript("OnClick", function(self)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    p.triggers[rowIdx].repeating = self:GetChecked() and true or false
                end
            end)

            row.enCB:SetScript("OnClick", function(self)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    p.triggers[rowIdx].enabled = self:GetChecked() and true or false
                    PRT:UpdateAutoSwapListeners()
                end
            end)

            row.noteEB:SetScript("OnEditFocusLost", function(self)
                local p = PRT:GetActiveSwapPreset()
                if p and p.triggers[rowIdx] then
                    p.triggers[rowIdx].note = self:GetText()
                end
            end)

            row.expBtn:SetScript("OnClick", function()
                local p = PRT:GetActiveSwapPreset()
                if not (p and p.triggers[rowIdx]) then return end
                trigExportPopup.titleLabel:SetText(
                    "Export Trigger — " .. (p.name or "") .. " #" .. rowIdx)
                texBox:SetText(PRT:ExportSwapTriggers({ p.triggers[rowIdx] }))
                texBox.editBox:SetFocus()
                texBox.editBox:HighlightText()
                trigExportPopup:Show()
            end)

            -- Populate values
            row.compDD:SetItems(compItems)
            row.compDD:SetSelected(trigger.compName)
            row.npcEB:SetText(trigger.npcId > 0 and tostring(trigger.npcId) or "")
            row.countEB:SetText(tostring(trigger.count or 1))
            row.repCB:SetChecked(trigger.repeating)
            row.enCB:SetChecked(trigger.enabled)
            row.noteEB:SetText(trigger.note or "")

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H - 2)
            row:SetPoint("RIGHT",   content, "RIGHT", -4, 0)
            row:Show()
        end

        self.scrollContainer:UpdateContentHeight(#triggers * ROW_H + 4)
    end

    ---------------------------------------------------------------------------
    -- OnShow
    ---------------------------------------------------------------------------
    function panel:RefreshEnabledState()
        local db = PRT:GetDB()
        enableCB:SetChecked(db.autoSwap.enabled)
    end

    function panel:OnShow()
        self:RefreshEnabledState()
        self:RefreshPresetList()
        self:RefreshTriggers()
        self:RefreshPresetSettings()
    end

    PRT:RegisterTab("autoswap", panel)
    PRT.autoSwapPanel = panel
end
