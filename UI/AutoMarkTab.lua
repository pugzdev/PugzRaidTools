---------------------------------------------------------------------------
-- PugzRaidTools - Player Auto Marking Configuration Tab
-- Two-panel layout: left panel lists Marking Rules within the active
-- preset; right panel shows the selected rule's full configuration
-- (marks, NPC death triggers, group swap triggers, trigger requirements).
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local RULE_LIST_W = 170
local ROW_H       = 24
local SEC_GAP     = 8
local SEC_PAD     = 6    -- top padding inside each section box before its header
local INSET       = 6    -- content padding inside detail scroll
local BTN_Y       = 56   -- y-offset where both scrolls end (room for rule buttons below)

---------------------------------------------------------------------------
-- Column x-offsets within detail scroll content (X delete leftmost)
---------------------------------------------------------------------------
-- Marks table
local MRK_DEL   = INSET + 2       --  8  delete button (22px)
local MRK_ICON  = MRK_DEL  + 26   -- 34  icon dropdown (88px)
local MRK_FIELD = MRK_ICON + 92   -- 126  name / pos field (160px or dropdown)
local MRK_NOTE  = MRK_FIELD + 164 -- 290  note (stretches to right edge)

-- NPC Death Triggers
local NPC_DEL   = INSET + 2       --  8  delete button (22px)
local NPC_NAME  = NPC_DEL  + 26   -- 34  trigger name (114px)
local NPC_ID    = NPC_NAME + 118  -- 152  npc id (76px)
local NPC_COUNT = NPC_ID   + 80   -- 232  kill count (46px)
local NPC_NOTE  = NPC_COUNT + 52  -- 284  note (stretches to right edge)

-- Group Swap Triggers
local SWP_DEL   = INSET + 2       --  8  delete button (22px)
local SWP_NAME  = SWP_DEL  + 26   -- 34  trigger name (114px)
local SWP_COMP  = SWP_NAME + 118  -- 152  comp dropdown (150px)
local SWP_NOTE  = SWP_COMP + 156  -- 308  note (stretches to right edge)

-- Conditionals
local CND_DEL   = INSET + 2       --  8  delete button (22px)
local CND_TRIG  = CND_DEL  + 26   -- 34  trigger-name dropdown (155px)
local CND_MUST  = CND_TRIG + 159  -- 193  must-be-true column header
local CND_FALSE = CND_MUST + 90   -- 283  must-be-false column header

---------------------------------------------------------------------------
-- Shared helper
---------------------------------------------------------------------------
local function GetActivePreset()
    local db = PRT:GetDB()
    return PRT:GetAutoMarkPreset(db.autoMark.activePreset)
end

---------------------------------------------------------------------------
-- Mark icon dropdown items — in-game raid target textures
---------------------------------------------------------------------------
local ICON_ITEMS = {}
for _, mi in ipairs(PRT.MARK_ICONS) do
    if mi.id == 0 then
        ICON_ITEMS[#ICON_ITEMS + 1] = { text = "Clear mark", value = 0 }
    else
        ICON_ITEMS[#ICON_ITEMS + 1] = {
            text = string.format(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s",
                mi.id, mi.name),
            value = mi.id,
        }
    end
end

local RETRY_DURATION_ITEMS = {
    { text = "1 second",  value = 1  },
    { text = "2 seconds", value = 2  },
    { text = "3 seconds", value = 3  },
    { text = "5 seconds", value = 5  },
    { text = "10 seconds", value = 10 },
}

---------------------------------------------------------------------------
-- Section box helpers — textures on the dc frame itself (BACKGROUND/BORDER
-- draw layers always render behind ARTWORK/OVERLAY child content on the
-- same frame, fixing the text-tinting bug caused by child Frame approach).
---------------------------------------------------------------------------
local function CreateSectionBoxTextures(parent)
    local bc, a = PRT.C.BORDER, 0.65
    local s = {}
    s.bg = parent:CreateTexture(nil, "BACKGROUND")
    s.bg:SetColorTexture(0.05, 0.05, 0.05, 0.45)
    s.t = parent:CreateTexture(nil, "BORDER")
    s.t:SetHeight(1); s.t:SetColorTexture(bc[1], bc[2], bc[3], a)
    s.b = parent:CreateTexture(nil, "BORDER")
    s.b:SetHeight(1); s.b:SetColorTexture(bc[1], bc[2], bc[3], a)
    s.l = parent:CreateTexture(nil, "BORDER")
    s.l:SetWidth(1); s.l:SetColorTexture(bc[1], bc[2], bc[3], a)
    s.r = parent:CreateTexture(nil, "BORDER")
    s.r:SetWidth(1); s.r:SetColorTexture(bc[1], bc[2], bc[3], a)
    s.bg:Hide(); s.t:Hide(); s.b:Hide(); s.l:Hide(); s.r:Hide()
    return s
end

local function PlaceSectionBox(s, parent, topY, bottomY)
    local h = math.abs(topY - bottomY)
    if h < 4 then h = 4 end
    s.bg:ClearAllPoints()
    s.bg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  2, topY)
    s.bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, topY)
    s.bg:SetHeight(h); s.bg:Show()
    s.t:ClearAllPoints()
    s.t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  2, topY)
    s.t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, topY); s.t:Show()
    s.b:ClearAllPoints()
    s.b:SetPoint("TOPLEFT",  parent, "TOPLEFT",  2, topY - h)
    s.b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, topY - h); s.b:Show()
    s.l:ClearAllPoints()
    s.l:SetPoint("TOPLEFT",  parent, "TOPLEFT",  2, topY)
    s.l:SetHeight(h); s.l:Show()
    s.r:ClearAllPoints()
    s.r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, topY)
    s.r:SetHeight(h); s.r:Show()
end

local function HideSectionBox(s)
    s.bg:Hide(); s.t:Hide(); s.b:Hide(); s.l:Hide(); s.r:Hide()
end

---------------------------------------------------------------------------
-- Build the tab
---------------------------------------------------------------------------
function PRT:BuildAutoMarkTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel._refreshGuard = W.CreateDeferredRefreshGuard()

    ---------------------------------------------------------------------------
    -- Name-input popup (for presets)
    ---------------------------------------------------------------------------
    local namePopup = W.CreateNamePopup("PRT_NameInputPopup", {
        width = 320,
        height = 110,
        prompt = false,
        placeholder = "Enter name...",
        buttonHeight = 22,
        buttonY = 10,
    })

    local function ShowNamePopup(title, defaultText, onOK)
        namePopup:Open({
            title = title,
            text = defaultText or "",
            onAccept = function(text)
                text = PRT.Trim(text)
                if text == "" then return false end
                onOK(text)
            end,
        })
    end

    ---------------------------------------------------------------------------
    -- Import popup (shared for rule and preset import)
    ---------------------------------------------------------------------------
    local importPopup = W.CreateTextTransferPopup("PRT_MarkImportPopup", {
        width = 450,
        height = 280,
        boxHeight = 180,
        actionText = "Import",
        actionWidth = 100,
        cancelText = "Cancel",
    })

    local function ShowImportPopup(title, instrText, onImport)
        importPopup:Open({
            title = title,
            instruction = instrText,
            text = "",
            actionText = "Import",
            onAction = onImport,
        })
    end

    ---------------------------------------------------------------------------
    -- Export popup (shared for rule and preset export)
    ---------------------------------------------------------------------------
    local exportPopup = W.CreateTextTransferPopup("PRT_MarkExportPopup", {
        width = 450,
        height = 280,
        instruction = "Select all: Ctrl+A  then copy: Ctrl+C",
        boxHeight = 204,
        actionText = "Close",
    })

    local deletePresetPopup = W.CreateConfirmPopup("PRT_AutoMarkDeletePresetPopup", {
        width = 340,
        height = 110,
        title = "Delete Preset",
        confirmText = "Delete",
        confirmTextColor = PRT.C.RED,
    })

    local function ShowExportPopup(title, text)
        exportPopup:Open({
            title = title,
            text = text,
            highlight = true,
        })
    end

    ---------------------------------------------------------------------------
    -- Header / description / enable toggle / preset management
    ---------------------------------------------------------------------------
    local hdr = W.CreateHeader(panel, "Player Auto Marking")
    hdr:SetPoint("TOPLEFT", 12, -10)

    local desc = W.CreateDescription(panel, nil, {
        width = 576,
        color = { 0.72, 0.72, 0.72, 1 },
    })
    desc:SetPoint("TOPLEFT",  12, -34)
    desc:SetPoint("TOPRIGHT", -12, -34)
    desc:SetText(
        "Automatically apply raid marks to players based on NPC death events or group swap triggers. "..
        "Create presets containing Marking Rules — each rule defines what marks to apply and what triggers them."
    )

    local apiWarning = W.CreateDescription(panel, nil, {
        width = 576,
        fontSize = PRT.FONT_SIZE - 1,
        color = { 1, 0.72, 0.35, 1 },
    })
    apiWarning:SetPoint("TOPLEFT", 12, -66)
    apiWarning:SetPoint("TOPRIGHT", -12, -66)
    apiWarning:SetText(
        "|cFFFF5555Warning:|r Classic Era 1.15.9 may not expose remote raid members outside the raid leader's "..
        "subgroup to automatic marking. Enable \"Retry unavailable players\" per rule; persistently unavailable "..
        "players cannot be marked."
    )

    local enableCB = W.CreateCheckbox(panel, "Enable Auto Marking", function(checked)
        local db = PRT:GetDB()
        db.autoMark.enabled = checked
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
        if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("automark") end
    end)
    enableCB:SetPoint("TOPLEFT", 12, -106)

    local presetLabel = W.CreateLabel(panel, "Active Preset:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    presetLabel:SetPoint("TOPLEFT", 12, -132)

    local presetDD = W.CreateDropdown(panel, 180, {}, function(value)
        local db = PRT:GetDB()
        db.autoMark.activePreset = value
        if PRT.UpdateActivePRTProfileSelection then
            PRT:UpdateActivePRTProfileSelection("autoMark", value)
        end
        panel.selectedRule = nil
        panel:RefreshPresetSettings()
        panel:RefreshRules()
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
    end)
    presetDD:SetPoint("TOPLEFT", 12, -148)

    local btnNewPreset = W.CreateButton(panel, "+ New", 55, 22)
    btnNewPreset:SetPoint("LEFT", presetDD, "RIGHT", 6, 0)
    btnNewPreset:SetScript("OnClick", function()
        ShowNamePopup("New Preset", "", function(name)
            local db = PRT:GetDB()
            for _, p in ipairs(db.autoMark.presets) do
                if p.name == name then
                    PRT.Print("Preset '" .. name .. "' already exists."); return
                end
            end
            db.autoMark.presets[#db.autoMark.presets + 1] = {
                name = name,
                instanceId = 0,
                allowAnywhere = false,
                markGroups = {},
            }
            db.autoMark.activePreset = name
            if PRT.UpdateActivePRTProfileSelection then
                PRT:UpdateActivePRTProfileSelection("autoMark", name)
            end
            panel:RefreshPresetDD()
            panel:RefreshPresetSettings()
            panel:RefreshRules()
            if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        end)
    end)

    local btnRenPreset = W.CreateButton(panel, "Rename", 60, 22)
    btnRenPreset:SetPoint("LEFT", btnNewPreset, "RIGHT", 4, 0)
    btnRenPreset:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then PRT.Print("No preset selected."); return end
        ShowNamePopup("Rename Preset", preset.name, function(newName)
            local db = PRT:GetDB()
            for _, p in ipairs(db.autoMark.presets) do
                if p.name == newName and p ~= preset then
                    PRT.Print("Preset '" .. newName .. "' already exists."); return
                end
            end
            local oldName = preset.name
            preset.name = newName
            db.autoMark.activePreset = newName
            if PRT.RenamePRTProfilePresetReference then
                PRT:RenamePRTProfilePresetReference("autoMark", oldName, newName)
            end
            panel:RefreshPresetDD()
            panel:RefreshPresetSettings()
        end)
    end)

    local btnDelPreset = W.CreateButton(panel, "Delete", 55, 22)
    btnDelPreset:SetPoint("LEFT", btnRenPreset, "RIGHT", 4, 0)
    btnDelPreset:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local name = db.autoMark.activePreset
        if name == "" then return end
        deletePresetPopup:Open({
            title = "Delete Preset",
            message = "Delete preset '" .. name .. "'?",
            confirmText = "Delete",
            onConfirm = function()
                for i, p in ipairs(db.autoMark.presets) do
                    if p.name == name then table.remove(db.autoMark.presets, i); break end
                end
                db.autoMark.activePreset = ""
                if db.autoMark.presets[1] then
                    db.autoMark.activePreset = db.autoMark.presets[1].name
                end
                if PRT.RemovePRTProfilePresetReference then
                    PRT:RemovePRTProfilePresetReference(
                        "autoMark", name, db.autoMark.activePreset)
                end
                panel.selectedRule = nil
                panel:RefreshPresetDD()
                panel:RefreshPresetSettings()
                panel:RefreshRules()
                if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
            end,
        })
    end)

    local btnResetCounters = W.CreateButton(panel, "Reset Counters", 110, 22)
    btnResetCounters:SetPoint("LEFT", btnDelPreset, "RIGHT", 12, 0)
    btnResetCounters:SetScript("OnClick", function()
        if PRT.ResetAutoMarkCounters then PRT:ResetAutoMarkCounters() end
    end)

    local btnImportPreset = W.CreateButton(panel, "Import", 50, 22)
    btnImportPreset:SetPoint("LEFT", btnResetCounters, "RIGHT", 4, 0)
    btnImportPreset:SetScript("OnClick", function()
        ShowImportPopup("Import Preset",
            "Paste a Preset export string below.",
            function(text)
                if PRT.Trim(text) == "" then PRT.Print("Nothing to import."); return end
                local preset = PRT:ParseMarkPresetString(text)
                if not preset then
                    -- Try parsing as bare rules without a preset wrapper
                    local rules = PRT:ParseMarkRuleString(text)
                    if #rules == 0 then
                        PRT.Print("No preset or rules found in import string."); return
                    end
                    preset = {
                        name = "Imported",
                        instanceId = 0,
                        allowAnywhere = false,
                        markGroups = rules,
                    }
                end
                if PRT.EnsureAutoMarkPresetDefaults then
                    PRT:EnsureAutoMarkPresetDefaults(preset)
                end
                local db = PRT:GetDB()
                -- Avoid name collision
                local baseName = preset.name
                local suffix = 0
                local nameExists = true
                while nameExists do
                    nameExists = false
                    for _, p in ipairs(db.autoMark.presets) do
                        if p.name == preset.name then
                            nameExists = true
                            suffix = suffix + 1
                            preset.name = baseName .. " (" .. suffix .. ")"
                            break
                        end
                    end
                end
                db.autoMark.presets[#db.autoMark.presets + 1] = preset
                db.autoMark.activePreset = preset.name
                if PRT.UpdateActivePRTProfileSelection then
                    PRT:UpdateActivePRTProfileSelection("autoMark", preset.name)
                end
                PRT.Print(("Imported preset '%s' with %d rule(s)."):format(
                    preset.name, #preset.markGroups))
                panel.selectedRule = nil
                panel:RefreshPresetDD()
                panel:RefreshPresetSettings()
                panel:RefreshRules()
                if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
                return true
            end)
    end)

    local btnExportPreset = W.CreateButton(panel, "Export", 50, 22)
    btnExportPreset:SetPoint("LEFT", btnImportPreset, "RIGHT", 4, 0)
    btnExportPreset:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then PRT.Print("Select a preset to export."); return end
        ShowExportPopup("Export Preset", PRT:ExportMarkPreset(preset))
    end)

    local loadCondLabel = W.CreateLabel(panel, "Preset Load Conditions:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    loadCondLabel:SetPoint("TOPLEFT", 12, -178)

    local instLabel = W.CreateLabel(panel, "Active in instance:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    instLabel:SetPoint("TOPLEFT", 12, -202)

    local instItems = {}
    for _, info in ipairs(PRT.RAID_INSTANCES) do
        instItems[#instItems + 1] = { text = info.name, value = info.id }
    end

    local instDD = W.CreateDropdown(panel, 180, instItems, function(value)
        local preset = GetActivePreset()
        if preset then
            preset.instanceId = value
            if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        end
    end)
    instDD:SetPoint("TOPLEFT", 126, -198)

    local anywhereCB = W.CreateCheckbox(panel,
        "Allow outside of instance/raid (for testing — fires CLEU everywhere)",
        function(checked)
            local preset = GetActivePreset()
            if preset then
                preset.allowAnywhere = checked
                if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
            end
        end)
    anywhereCB:SetPoint("TOPLEFT", 318, -198)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT",  12, -230)
    divider:SetPoint("TOPRIGHT", -12, -230)
    divider:SetHeight(1)
    divider:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.5)

    ---------------------------------------------------------------------------
    -- Left panel: Marking Rules list
    ---------------------------------------------------------------------------
    local LEFT_TOP = -238
    local RIGHT_X  = 12 + RULE_LIST_W + 8   -- 190

    local ruleListHdr = W.CreateHeader(panel, "Marking Rules")
    ruleListHdr:SetPoint("TOPLEFT", 12, LEFT_TOP)

    local ruleListScroll = W.CreateScrollFrame(panel, RULE_LIST_W, 0)
    ruleListScroll:SetPoint("TOPLEFT",    12, LEFT_TOP - 20)
    ruleListScroll:SetPoint("BOTTOMLEFT", 12, BTN_Y)
    W.StyleBox(ruleListScroll, { 0.04, 0.04, 0.04, 0.6 }, PRT.C.BORDER)

    panel.ruleButtons = {}
    panel.selectedRule = nil

    -- Add Rule / Delete Rule buttons (Rename removed — user can rename in config)
    local btnAddRule = W.CreateButton(panel, "+ Add Rule", 90, 22)
    btnAddRule:SetPoint("BOTTOMLEFT", 12, 30)
    btnAddRule:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then PRT.Print("Select a preset first."); return end
        local idx = #preset.markGroups + 1
        preset.markGroups[idx] = {
            name         = "Rule " .. idx,
            note         = "",
            applyOn      = "position",
            smartAssign  = true,
            smartComp    = "",
            unmarkAll    = false,
            repeatable   = false,
            retryUnavailable = false,
            retryDuration = 3,
            triggerMode  = "any",
            marks        = {},
            npcTriggers  = {},
            swapTriggers = {},
            conditionals = {},
        }
        panel.selectedRule = idx
        panel:RefreshRules()
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
    end)

    local btnDelRule = W.CreateButton(panel, "Delete", 55, 22)
    btnDelRule:SetPoint("LEFT", btnAddRule, "RIGHT", 4, 0)
    btnDelRule:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then return end
        table.remove(preset.markGroups, panel.selectedRule)
        if panel.selectedRule > #preset.markGroups then
            panel.selectedRule = #preset.markGroups > 0 and #preset.markGroups or nil
        end
        panel:RefreshRules()
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
    end)

    -- Import / Export Rule buttons (second row)
    local btnImportRule = W.CreateButton(panel, "Import", 55, 22)
    btnImportRule:SetPoint("BOTTOMLEFT", 12, 6)
    btnImportRule:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset then PRT.Print("Select a preset first."); return end
        ShowImportPopup("Import Marking Rule",
            "Paste a Marking Rule export string below.",
            function(text)
                if PRT.Trim(text) == "" then PRT.Print("Nothing to import."); return end
                local rules = PRT:ParseMarkRuleString(text)
                if #rules == 0 then PRT.Print("No rules found in import string."); return end
                for _, rule in ipairs(rules) do
                    preset.markGroups[#preset.markGroups + 1] = rule
                end
                PRT.Print(("Imported %d rule(s)."):format(#rules))
                panel.selectedRule = #preset.markGroups
                panel:RefreshRules()
                if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
                return true
            end)
    end)

    local btnExportRule = W.CreateButton(panel, "Export", 55, 22)
    btnExportRule:SetPoint("LEFT", btnImportRule, "RIGHT", 4, 0)
    btnExportRule:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then
            PRT.Print("Select a rule to export."); return
        end
        local mg = preset.markGroups[panel.selectedRule]
        if not mg then return end
        ShowExportPopup("Export Marking Rule", PRT:ExportMarkRule(mg))
    end)

    ---------------------------------------------------------------------------
    -- Right panel: "Marking Rule Configuration" header + scrollable detail
    ---------------------------------------------------------------------------
    local configHdr = W.CreateHeader(panel, "Marking Rule Configuration")
    configHdr:SetPoint("TOPLEFT", RIGHT_X, LEFT_TOP)

    local detailScroll = W.CreateScrollFrame(panel, 0, 0)
    detailScroll:SetPoint("TOPLEFT",     RIGHT_X, LEFT_TOP - 20)
    detailScroll:SetPoint("BOTTOMRIGHT", -12, BTN_Y)
    W.StyleBox(detailScroll, { 0.04, 0.04, 0.04, 0.4 }, PRT.C.BORDER)

    panel.detailScroll = detailScroll
    local dc = detailScroll.content

    ---------------------------------------------------------------------------
    -- Section box textures on dc — BACKGROUND/BORDER draw layers render
    -- behind ARTWORK/OVERLAY FontStrings on the same frame. No child Frames
    -- needed, so no frame-level override of text.
    ---------------------------------------------------------------------------
    local secMark    = CreateSectionBoxTextures(dc)
    local secNpc     = CreateSectionBoxTextures(dc)
    local secSwap    = CreateSectionBoxTextures(dc)
    local secTrigReq = CreateSectionBoxTextures(dc)

    ---------------------------------------------------------------------------
    -- Smart Assign tooltip helper
    ---------------------------------------------------------------------------
    local function ShowSmartTip(anchor)
        GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Smart Assign", 1, 0.82, 0, 1)
        GameTooltip:AddLine(
            "|cFFFFFF00Strongly recommended.|r Your marking rules are tied to " ..
            "the composition NAME (e.g. \"Main\"), not a specific roster. Before " ..
            "each raid, import a new roster under the same name and all your " ..
            "rules automatically apply to the new players — no reconfiguration " ..
            "needed. As long as you keep the same group shape, position 5 will " ..
            "always resolve to whoever is at position 5 in the current roster.\n\n" ..
            "Marks are assigned by raid position number, and the actual player " ..
            "name is looked up from the selected composition at the moment of " ..
            "triggering. This also means marks stay correct even if the raid has " ..
            "been reordered since the composition was last applied.\n\n" ..
            "|cFFFF6060Without Smart Assign:|r you must enter exact character " ..
            "names (case-sensitive) or know exact raid slot numbers. Marks will " ..
            "break any time the roster changes or the raid is reordered.",
            1, 1, 1, 1, true)
        GameTooltip:Show()
    end

    ---------------------------------------------------------------------------
    -- Static detail widgets
    ---------------------------------------------------------------------------
    local d = {}
    panel.d = d

    -- Name row + Note TextArea (below name, full width)
    d.nameLabel = W.CreateLabel(dc, "Name:",  PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    d.nameEB    = W.CreateEditBox(dc, 180, 20, "Rule name")
    d.noteTA    = W.CreateTextArea(dc, 60, "Optional rule note...")
    panel._refreshGuard:Track(d.nameEB)
    panel._refreshGuard:Track(d.noteTA.editBox)

    -- Apply By row
    d.modeLabel = W.CreateLabel(dc, "Apply By:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    d.modeDD    = W.CreateDropdown(dc, 150, {
        { text = "Raid Position", value = "position" },
        { text = "Player Name",   value = "name"     },
    }, function(val)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].applyOn = val
            panel:RefreshRuleDetails()
        end
    end)

    -- Smart Assign warning (shown when Smart Assign is enabled but Apply By is not Position)
    d.smartAssignWarning = W.CreateDescription(dc, "|cFFFF0000Warning!|r Smart Assign requires Apply By: Raid Position", {
        fontSize = PRT.FONT_SIZE - 1,
        color = { 1, 1, 1, 1 },
    })

    -- Smart Assign row (only shown when applyOn == "position")
    d.smartCB = W.CreateCheckbox(dc, "Smart Assign", function(checked)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].smartAssign = checked
            panel:RefreshRuleDetails()
        end
    end)
    -- Tooltip: outer frame (covers label area) + inner CheckButton
    d.smartCB:EnableMouse(true)
    d.smartCB:SetScript("OnEnter", function(self) ShowSmartTip(self) end)
    d.smartCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.smartCB.check:HookScript("OnEnter", function(self) ShowSmartTip(self) end)
    d.smartCB.check:HookScript("OnLeave", function() GameTooltip:Hide() end)

    d.smartCompLabel = W.CreateLabel(dc, "Select Raid Group:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    d.smartCompDD    = W.CreateDropdown(dc, 160, {}, function(val)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].smartComp = val
            panel:RefreshRuleDetails()
        end
    end)

    d.unmarkCB = W.CreateCheckbox(dc, "Unmark All First", function(checked)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].unmarkAll = checked
        end
    end)

    d.repeatCB = W.CreateCheckbox(dc, "Repeatable", function(checked)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].repeatable = checked
        end
    end)

    d.retryCB = W.CreateCheckbox(dc, "Retry unavailable players", function(checked)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].retryUnavailable = checked
            panel:RefreshRuleDetails()
        end
    end)
    d.retryDurationLabel = W.CreateLabel(dc, "Retry for:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    d.retryDurationDD = W.CreateDropdown(dc, 100, RETRY_DURATION_ITEMS, function(val)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].retryDuration = tonumber(val) or 3
        end
    end)

    local retryTooltip = {
        anchor = "ANCHOR_RIGHT",
        title = "Retry unavailable players",
        titleColor = { 1, 0.82, 0, 1 },
        lines = {
            {
                "Since the WoW Classic Era 1.15.9 update in July 2026, raid marker API calls can silently fail when a raid member is not currently addressable to the raid leader's client. This is most often seen when a player is distant, in another zone, or temporarily unavailable while raid groups are changing.",
                1, 1, 1, true,
            },
            {
                "When enabled, PRT applies this rule immediately to available players, then keeps failed assignments in a short pending queue and retries until the selected duration expires.",
                1, 1, 1, true,
            },
            {
                "This cannot mark a player who remains unavailable for the full retry duration.",
                1, 0.55, 0.35, true,
            },
        },
    }
    d.retryCB:EnableMouse(true)
    W.AttachTooltip(d.retryCB, retryTooltip)
    W.AttachTooltip(d.retryCB.check, retryTooltip)

    -- Marks section
    d.marksHdr  = W.CreateHeader(dc, "Marks")
    d.marksDesc = W.CreateDescription(dc, nil, {
        fontSize = PRT.FONT_SIZE - 1,
        color = { 0.65, 0.65, 0.65, 1 },
    })
    d.marksDesc:SetText(
        "Each entry assigns a raid icon to a specific player or position. "..
        "Icons are applied when the rule fires."
    )
    d.markColIcon  = W.CreateLabel(dc, "Icon", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.markColField = W.CreateLabel(dc, "Raid Position #", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.markColNote  = W.CreateLabel(dc, "Note", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.btnAddMark   = W.CreateButton(dc, "+ Add Mark", 90, 20)

    -- NPC Death Triggers section
    d.npcHdr  = W.CreateHeader(dc, "NPC Death Triggers")
    d.npcDesc = W.CreateDescription(dc, nil, {
        fontSize = PRT.FONT_SIZE - 1,
        color = { 0.65, 0.65, 0.65, 1 },
    })
    d.npcDesc:SetText(
        "Fire this rule when a specific NPC dies during combat. "..
        "Enter the NPC ID and how many kills are required before triggering."
    )
    d.npcColName  = W.CreateLabel(dc, "Name",   PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.npcColId    = W.CreateLabel(dc, "NPC ID", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.npcColCount = W.CreateLabel(dc, "Count",  PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.npcColNote  = W.CreateLabel(dc, "Note",   PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.btnAddNpc   = W.CreateButton(dc, "+ Add Trigger", 100, 20)

    -- Group Swap Triggers section
    d.swapHdr  = W.CreateHeader(dc, "Group Swap Triggers")
    d.swapDesc = W.CreateDescription(dc, nil, {
        fontSize = PRT.FONT_SIZE - 1,
        color = { 0.65, 0.65, 0.65, 1 },
    })
    d.swapDesc:SetText(
        "Fire this rule when Group Auto Swap applies a specific saved composition. "..
        "Select the composition that should trigger this rule."
    )
    d.swapColName = W.CreateLabel(dc, "Name",        PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.swapColComp = W.CreateLabel(dc, "Composition", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.swapColNote = W.CreateLabel(dc, "Note",        PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.btnAddSwap  = W.CreateButton(dc, "+ Add Trigger", 100, 20)

    -- Trigger Requirements section
    d.trigReqHdr    = W.CreateHeader(dc, "Trigger Requirements")
    d.trigModeLabel = W.CreateLabel(dc, "Fire when:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    d.trigModeDD    = W.CreateDropdown(dc, 170, {
        { text = "Any trigger condition is met",   value = "any"         },
        { text = "All trigger conditions are met", value = "all"         },
        { text = "Custom conditional logic",        value = "conditional" },
    }, function(val)
        local preset = GetActivePreset()
        if preset and panel.selectedRule then
            preset.markGroups[panel.selectedRule].triggerMode = val
            panel:RefreshRuleDetails()
        end
    end)
    d.condColTrig = W.CreateLabel(dc, "Trigger Name", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.condColMust  = W.CreateLabel(dc, "Must Be True", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.condColFalse = W.CreateLabel(dc, "Must Be False", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    d.btnAddCond   = W.CreateButton(dc, "+ Add Condition", 110, 20)

    -- Dynamic row pools
    panel.markRows     = {}
    panel.npcTrigRows  = {}
    panel.swapTrigRows = {}
    panel.condRows     = {}

    -- Add-button handlers
    d.btnAddMark:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then return end
        local mg = preset.markGroups[panel.selectedRule]
        mg.marks[#mg.marks + 1] = { icon = 0, playerName = "", position = 0, note = "" }
        panel:RefreshRuleDetails()
    end)

    d.btnAddNpc:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then return end
        local mg = preset.markGroups[panel.selectedRule]
        local n = #mg.npcTriggers + 1
        mg.npcTriggers[n] = { name = "Trigger " .. n, npcId = 0, count = 1 }
        panel:RefreshRuleDetails()
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
    end)

    d.btnAddSwap:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then return end
        local mg = preset.markGroups[panel.selectedRule]
        local n = #mg.swapTriggers + 1
        mg.swapTriggers[n] = { name = "Trigger " .. n, compName = "" }
        panel:RefreshRuleDetails()
    end)

    d.btnAddCond:SetScript("OnClick", function()
        local preset = GetActivePreset()
        if not preset or not panel.selectedRule then return end
        local mg = preset.markGroups[panel.selectedRule]
        mg.conditionals[#mg.conditionals + 1] = { triggerName = "", mustBeTrue = true, mustBeFalse = false }
        panel:RefreshRuleDetails()
    end)

    ---------------------------------------------------------------------------
    -- Row factory: Marks (X delete leftmost)
    ---------------------------------------------------------------------------
    local function GetOrCreateMarkRow(pool, idx)
        if pool[idx] then return pool[idx] end
        local row = W.CreateRowFrame(dc, ROW_H)

        row.delBtn = W.CreateDeleteButton(row, function()
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                table.remove(preset.markGroups[panel.selectedRule].marks, row._idx)
                panel:RefreshRuleDetails()
            end
        end, { point = { "LEFT", MRK_DEL, 0 } })

        row.iconDD = W.CreateDropdown(row, 88, ICON_ITEMS, function(val)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.marks[row._idx] then mg.marks[row._idx].icon = val end
            end
        end)
        row.iconDD:SetPoint("LEFT", MRK_ICON, 0)

        -- Player name — free text (applyOn=="name", no smart dropdown)
        row.nameEB = W.CreateEditBox(row, 160, 20, "Player name")
        row.nameEB:SetPoint("LEFT", MRK_FIELD, 0)
        row.nameEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if not preset or not panel.selectedRule then return end
            local mg = preset.markGroups[panel.selectedRule]
            if mg.marks[row._idx] then mg.marks[row._idx].playerName = self:GetText() end
        end)
        panel._refreshGuard:Track(row.nameEB)

        -- Player name — dropdown from comp (applyOn=="name" + smartAssign + comp)
        row.nameDD = W.CreateDropdown(row, 160, {}, function(val)
            local preset = GetActivePreset()
            if not preset or not panel.selectedRule then return end
            local mg = preset.markGroups[panel.selectedRule]
            if not mg.marks[row._idx] then return end
            mg.marks[row._idx].playerName = val
            if mg.smartComp ~= "" then
                local comp = PRT:GetComp(mg.smartComp)
                if comp then
                    local identityKey = PRT:GetPlayerIdentityKey(val)
                    for pos = 1, 40 do
                        if PRT:GetPlayerIdentityKey(comp.roster[pos] or "") == identityKey then
                            mg.marks[row._idx].position = pos; break
                        end
                    end
                end
            end
        end)
        row.nameDD:SetPoint("LEFT", MRK_FIELD, 0)

        -- Raid position — free text (applyOn=="position", no smart dropdown)
        row.posEB = W.CreateEditBox(row, 50, 20, "#")
        row.posEB:SetPoint("LEFT", MRK_FIELD, 0)
        row.posEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if not preset or not panel.selectedRule then return end
            local mg = preset.markGroups[panel.selectedRule]
            if not mg.marks[row._idx] then return end
            local pos = math.max(0, math.min(40, tonumber(self:GetText()) or 0))
            mg.marks[row._idx].position = pos
            self:SetText(pos > 0 and tostring(pos) or "")
        end)
        panel._refreshGuard:Track(row.posEB)

        -- Raid position — dropdown from comp (applyOn=="position" + smartAssign + comp)
        row.posDD = W.CreateDropdown(row, 160, {}, function(val)
            local preset = GetActivePreset()
            if not preset or not panel.selectedRule then return end
            local mg = preset.markGroups[panel.selectedRule]
            if not mg.marks[row._idx] then return end
            mg.marks[row._idx].position = val
            if mg.smartComp ~= "" then
                local comp = PRT:GetComp(mg.smartComp)
                if comp and comp.roster[val] then
                    mg.marks[row._idx].playerName = comp.roster[val]
                end
            end
        end)
        row.posDD:SetPoint("LEFT", MRK_FIELD, 0)

        -- Note (stretches to right edge)
        row.noteEB = W.CreateEditBox(row, 100, 20, "note")
        row.noteEB:SetPoint("LEFT",  MRK_NOTE, 0)
        row.noteEB:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.noteEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.marks[row._idx] then mg.marks[row._idx].note = self:GetText() end
            end
        end)
        panel._refreshGuard:Track(row.noteEB)

        pool[idx] = row
        return row
    end

    ---------------------------------------------------------------------------
    -- Row factory: NPC Death Triggers (X delete leftmost)
    ---------------------------------------------------------------------------
    local function GetOrCreateNpcTrigRow(pool, idx)
        if pool[idx] then return pool[idx] end
        local row = W.CreateRowFrame(dc, ROW_H)

        row.delBtn = W.CreateDeleteButton(row, function()
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                table.remove(preset.markGroups[panel.selectedRule].npcTriggers, row._idx)
                panel:RefreshRuleDetails()
                if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
            end
        end, { point = { "LEFT", NPC_DEL, 0 } })

        row.nameEB = W.CreateEditBox(row, 114, 20, "Trigger name")
        row.nameEB:SetPoint("LEFT", NPC_NAME, 0)
        row.nameEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.npcTriggers[row._idx] then
                    mg.npcTriggers[row._idx].name = self:GetText()
                    -- Rebuild conditional dropdowns when trigger name changes
                    if mg.triggerMode == "conditional" then
                        panel:RefreshRuleDetails()
                    end
                end
            end
        end)
        panel._refreshGuard:Track(row.nameEB)

        row.npcIdEB = W.CreateEditBox(row, 76, 20, "NPC ID")
        row.npcIdEB:SetPoint("LEFT", NPC_ID, 0)
        row.npcIdEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.npcTriggers[row._idx] then
                    mg.npcTriggers[row._idx].npcId = tonumber(self:GetText()) or 0
                end
            end
            if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        end)
        panel._refreshGuard:Track(row.npcIdEB)

        row.countEB = W.CreateEditBox(row, 46, 20, "#")
        row.countEB:SetPoint("LEFT", NPC_COUNT, 0)
        row.countEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.npcTriggers[row._idx] then
                    mg.npcTriggers[row._idx].count = math.max(1, tonumber(self:GetText()) or 1)
                    self:SetText(tostring(mg.npcTriggers[row._idx].count))
                end
            end
        end)
        panel._refreshGuard:Track(row.countEB)

        row.noteEB = W.CreateEditBox(row, 100, 20, "note")
        row.noteEB:SetPoint("LEFT",  NPC_NOTE, 0)
        row.noteEB:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.noteEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.npcTriggers[row._idx] then
                    mg.npcTriggers[row._idx].note = self:GetText()
                end
            end
        end)
        panel._refreshGuard:Track(row.noteEB)

        pool[idx] = row
        return row
    end

    ---------------------------------------------------------------------------
    -- Row factory: Group Swap Triggers (X delete leftmost)
    ---------------------------------------------------------------------------
    local function GetOrCreateSwapTrigRow(pool, idx)
        if pool[idx] then return pool[idx] end
        local row = W.CreateRowFrame(dc, ROW_H)

        row.delBtn = W.CreateDeleteButton(row, function()
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                table.remove(preset.markGroups[panel.selectedRule].swapTriggers, row._idx)
                panel:RefreshRuleDetails()
            end
        end, { point = { "LEFT", SWP_DEL, 0 } })

        row.nameEB = W.CreateEditBox(row, 114, 20, "Trigger name")
        row.nameEB:SetPoint("LEFT", SWP_NAME, 0)
        row.nameEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.swapTriggers[row._idx] then
                    mg.swapTriggers[row._idx].name = self:GetText()
                end
            end
        end)
        panel._refreshGuard:Track(row.nameEB)

        row.compDD = W.CreateDropdown(row, 150, {}, function(val)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.swapTriggers[row._idx] then
                    mg.swapTriggers[row._idx].compName = val
                end
            end
        end)
        row.compDD:SetPoint("LEFT", SWP_COMP, 0)

        row.noteEB = W.CreateEditBox(row, 100, 20, "note")
        row.noteEB:SetPoint("LEFT",  SWP_NOTE, 0)
        row.noteEB:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.noteEB:SetScript("OnEditFocusLost", function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.swapTriggers[row._idx] then
                    mg.swapTriggers[row._idx].note = self:GetText()
                end
            end
        end)
        panel._refreshGuard:Track(row.noteEB)

        pool[idx] = row
        return row
    end

    ---------------------------------------------------------------------------
    -- Row factory: Conditionals (X delete leftmost)
    ---------------------------------------------------------------------------
    local function GetOrCreateCondRow(pool, idx)
        if pool[idx] then return pool[idx] end
        local row = W.CreateRowFrame(dc, ROW_H)

        row.delBtn = W.CreateDeleteButton(row, function()
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                table.remove(preset.markGroups[panel.selectedRule].conditionals, row._idx)
                panel:RefreshRuleDetails()
            end
        end, { point = { "LEFT", CND_DEL, 0 } })

        row.trigDD = W.CreateDropdown(row, 155, {}, function(val)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.conditionals[row._idx] then
                    mg.conditionals[row._idx].triggerName = val
                end
            end
        end)
        row.trigDD:SetPoint("LEFT", CND_TRIG, 0)

        row.mustCB = W.CreateCheckButton(row, 20, function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.conditionals[row._idx] then
                    mg.conditionals[row._idx].mustBeTrue = self:GetChecked() and true or false
                    if self:GetChecked() then
                        mg.conditionals[row._idx].mustBeFalse = false
                        row.falseCB:SetChecked(false)
                    end
                end
            end
        end, { point = { "LEFT", CND_MUST + 28, 0 } })  -- repositioned in refresh

        row.falseCB = W.CreateCheckButton(row, 20, function(self)
            local preset = GetActivePreset()
            if preset and panel.selectedRule then
                local mg = preset.markGroups[panel.selectedRule]
                if mg.conditionals[row._idx] then
                    mg.conditionals[row._idx].mustBeFalse = self:GetChecked() and true or false
                    if self:GetChecked() then
                        mg.conditionals[row._idx].mustBeTrue = false
                        row.mustCB:SetChecked(false)
                    end
                end
            end
        end, { point = { "LEFT", CND_FALSE + 30, 0 } })  -- repositioned in refresh

        pool[idx] = row
        return row
    end

    ---------------------------------------------------------------------------
    -- Refresh: Preset dropdown
    ---------------------------------------------------------------------------
    function panel:RefreshPresetDD()
        local db = PRT:GetDB()
        local items = {}
        for _, p in ipairs(db.autoMark.presets) do
            items[#items + 1] = { text = p.name, value = p.name }
        end
        presetDD:SetItems(items)
        presetDD:SetSelected(db.autoMark.activePreset)
        self:RefreshPresetSettings()
    end

    function panel:RefreshPresetSettings()
        local preset = GetActivePreset()
        if preset and PRT.EnsureAutoMarkPresetDefaults then
            PRT:EnsureAutoMarkPresetDefaults(preset)
        end

        instDD:SetSelected((preset and preset.instanceId) or 0)
        anywhereCB:SetChecked(preset and preset.allowAnywhere or false)
    end

    ---------------------------------------------------------------------------
    -- Refresh: Rule list (left panel)
    ---------------------------------------------------------------------------
    function panel:RefreshRules()
        local preset = GetActivePreset()

        for _, btn in ipairs(self.ruleButtons) do
            if btn.ResetHoverAnimation then btn:ResetHoverAnimation() end
            btn:Hide()
        end

        if not preset then
            self.selectedRule = nil
            self:RefreshRuleDetails()
            return
        end

        local content = ruleListScroll.content
        for i, mg in ipairs(preset.markGroups) do
            local btn = self.ruleButtons[i]
            if not btn then
                btn = W.CreateSelectableButton(content, "", {
                    width = RULE_LIST_W - 4,
                    height = 22,
                    bgColor = { 0, 0, 0, 0 },
                    selectedBgColor = PRT.C.SIDEBAR_SEL,
                    borderColor = { 0, 0, 0, 0 },
                    selectedBorderColor = { 0, 0, 0, 0 },
                    textColor = { 1, 1, 1, 1 },
                    selectedTextColor = PRT.C.TITLE,
                    fontSize = PRT.FONT_SIZE,
                    justifyH = "LEFT",
                    labelPoint = { "LEFT", 6, 0 },
                    hoverAnimation = "MRT",
                    hoverAnimationHeight = 22,
                })
                btn.label:SetPoint("RIGHT", -4, 0)
                btn:SetScript("OnClick", function(self)
                    panel.selectedRule = self._ruleIdx
                    panel:HighlightRuleButton()
                    panel:RefreshRuleDetails()
                end)
                self.ruleButtons[i] = btn
            end
            btn._ruleIdx = i
            btn.label:SetText(mg.name)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 2, -(i - 1) * 22 - 2)
            btn:SetPoint("RIGHT", content, "RIGHT", -2, 0)
            btn:Show()
        end

        ruleListScroll:UpdateContentHeight(#preset.markGroups * 22 + 4)

        if self.selectedRule and self.selectedRule > #preset.markGroups then
            self.selectedRule = #preset.markGroups > 0 and #preset.markGroups or nil
        end
        if not self.selectedRule and #preset.markGroups > 0 then
            self.selectedRule = 1
        end

        self:HighlightRuleButton()
        self:RefreshRuleDetails()
    end

    function panel:HighlightRuleButton()
        for i, btn in ipairs(self.ruleButtons) do
            if btn:IsShown() then
                btn:SetSelected(i == self.selectedRule)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Refresh: Rule detail (right panel)
    ---------------------------------------------------------------------------
    function panel:RefreshRuleDetails()
        local preset = GetActivePreset()
        local mg = nil
        if preset and self.selectedRule then
            mg = preset.markGroups[self.selectedRule]
            if mg and PRT.EnsureAutoMarkRuleDefaults then
                PRT:EnsureAutoMarkRuleDefaults(mg)
            end
        end

        for _, r in ipairs(self.markRows)     do r:Hide() end
        for _, r in ipairs(self.npcTrigRows)  do r:Hide() end
        for _, r in ipairs(self.swapTrigRows) do r:Hide() end
        for _, r in ipairs(self.condRows)     do r:Hide() end

        HideSectionBox(secMark); HideSectionBox(secNpc)
        HideSectionBox(secSwap); HideSectionBox(secTrigReq)

        if not mg then
            for _, w in pairs(d) do
                if w and w.Hide then pcall(w.Hide, w) end
            end
            self.detailScroll:UpdateContentHeight(1)
            return
        end

        local y = -INSET

        -----------------------------------------------------------------
        -- Name row
        -----------------------------------------------------------------
        d.nameLabel:ClearAllPoints()
        d.nameLabel:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 2, y - 4)
        d.nameLabel:Show()

        d.nameEB:ClearAllPoints()
        d.nameEB:SetPoint("LEFT", d.nameLabel, "RIGHT", 4, 0)
        d.nameEB:SetText(mg.name)
        d.nameEB:SetScript("OnEditFocusLost", function(self)
            local p = GetActivePreset()
            if p and panel.selectedRule then
                p.markGroups[panel.selectedRule].name = PRT.Trim(self:GetText())
                for idx, btn in ipairs(panel.ruleButtons) do
                    if btn:IsShown() and idx == panel.selectedRule then
                        btn.label:SetText(p.markGroups[idx].name)
                    end
                end
            end
        end)
        d.nameEB:Show()

        y = y - 28

        -----------------------------------------------------------------
        -- Note TextArea (full-width, below name row)
        -----------------------------------------------------------------
        d.noteTA:ClearAllPoints()
        d.noteTA:SetPoint("TOPLEFT",  dc, "TOPLEFT",  INSET + 2, y)
        d.noteTA:SetPoint("TOPRIGHT", dc, "TOPRIGHT", -(INSET + 2), y)
        d.noteTA:SetText(mg.note or "")
        d.noteTA.editBox:SetScript("OnEditFocusLost", function(self)
            local p = GetActivePreset()
            if p and panel.selectedRule then
                p.markGroups[panel.selectedRule].note = self:GetText()
            end
        end)
        d.noteTA:Show()

        y = y - 68   -- 60px TextArea + 8px gap

        -----------------------------------------------------------------
        -- Apply By row
        -----------------------------------------------------------------
        d.modeLabel:ClearAllPoints()
        d.modeLabel:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 2, y - 4)
        d.modeLabel:Show()

        d.modeDD:ClearAllPoints()
        d.modeDD:SetPoint("LEFT", d.modeLabel, "RIGHT", 4, 0)
        d.modeDD:SetSelected(mg.applyOn or "position")
        d.modeDD:Show()

        -- Show warning if Smart Assign is enabled but Apply By is not Position
        if mg.smartAssign and (mg.applyOn or "position") ~= "position" then
            d.smartAssignWarning:ClearAllPoints()
            d.smartAssignWarning:SetPoint("LEFT", d.modeDD, "RIGHT", 12, 0)
            d.smartAssignWarning:Show()
        else
            d.smartAssignWarning:Hide()
        end

        y = y - 28

        -----------------------------------------------------------------
        -- Smart Assign row (only when applyOn == "position")
        -----------------------------------------------------------------
        local showSmart = (mg.applyOn == "position")
        if showSmart then
            d.smartCB:ClearAllPoints()
            d.smartCB:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET, y)
            d.smartCB:SetChecked(mg.smartAssign or false)
            d.smartCB:Show()

            if mg.smartAssign then
                d.smartCompLabel:ClearAllPoints()
                d.smartCompLabel:SetPoint("LEFT", d.smartCB, "RIGHT", 4, 0)
                d.smartCompLabel:Show()

                d.smartCompDD:ClearAllPoints()
                d.smartCompDD:SetPoint("LEFT", d.smartCompLabel, "RIGHT", 4, 0)
                local compItems = {}
                for _, name in ipairs(PRT:GetCompOrder()) do
                    compItems[#compItems + 1] = { text = name, value = name }
                end
                d.smartCompDD:SetItems(compItems)
                d.smartCompDD:SetSelected(mg.smartComp or "")
                d.smartCompDD:Show()
            else
                d.smartCompLabel:Hide()
                d.smartCompDD:Hide()
            end

            y = y - 26
        else
            d.smartCB:Hide()
            d.smartCompLabel:Hide()
            d.smartCompDD:Hide()
        end

        -----------------------------------------------------------------
        -- Unmark All + Repeatable + unavailable-player retry rows
        -----------------------------------------------------------------
        d.unmarkCB:ClearAllPoints()
        d.unmarkCB:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET, y)
        d.unmarkCB:SetChecked(mg.unmarkAll or false)
        d.unmarkCB:Show()
        y = y - 26

        d.repeatCB:ClearAllPoints()
        d.repeatCB:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET, y)
        d.repeatCB:SetChecked(mg.repeatable or false)
        d.repeatCB:Show()
        y = y - 26

        d.retryCB:ClearAllPoints()
        d.retryCB:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET, y)
        d.retryCB:SetChecked(mg.retryUnavailable or false)
        d.retryCB:Show()

        if mg.retryUnavailable then
            d.retryDurationLabel:ClearAllPoints()
            d.retryDurationLabel:SetPoint("LEFT", d.retryCB, "RIGHT", 8, 0)
            d.retryDurationLabel:Show()

            d.retryDurationDD:ClearAllPoints()
            d.retryDurationDD:SetPoint("LEFT", d.retryDurationLabel, "RIGHT", 6, 0)
            d.retryDurationDD:SetSelected(tonumber(mg.retryDuration) or 3)
            d.retryDurationDD:Show()
        else
            d.retryDurationLabel:Hide()
            d.retryDurationDD:Hide()
        end
        y = y - 26

        y = y - SEC_GAP

        -----------------------------------------------------------------
        -- MARKS section
        -----------------------------------------------------------------
        local secMarkTop = y
        y = y - SEC_PAD   -- top padding inside section box

        d.marksHdr:ClearAllPoints()
        d.marksHdr:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y)
        d.marksHdr:Show()
        y = y - 20

        d.marksDesc:ClearAllPoints()
        d.marksDesc:SetPoint("TOPLEFT",  dc, "TOPLEFT",  INSET + 6, y)
        d.marksDesc:SetPoint("TOPRIGHT", dc, "TOPRIGHT", -(INSET + 6), y)
        d.marksDesc:Show()
        y = y - 26

        local applyOn    = mg.applyOn or "position"
        local hasSmartDD = (applyOn == "position") and mg.smartAssign and mg.smartComp ~= ""
        local fieldLabel = (applyOn == "name") and "Player Name" or "Raid Position #"
        d.markColField:SetText(fieldLabel)

        d.markColIcon:ClearAllPoints()
        d.markColIcon:SetPoint("TOPLEFT", dc, "TOPLEFT", MRK_ICON + 4, y)
        d.markColIcon:Show()

        d.markColField:ClearAllPoints()
        d.markColField:SetPoint("TOPLEFT", dc, "TOPLEFT", MRK_FIELD + 4, y)
        d.markColField:Show()

        d.markColNote:ClearAllPoints()
        d.markColNote:SetPoint("TOPLEFT", dc, "TOPLEFT", MRK_NOTE + 4, y)
        d.markColNote:Show()

        y = y - 18

        local useNameEB = (applyOn == "name") and not (mg.smartAssign and mg.smartComp ~= "")
        local useNameDD = (applyOn == "name") and mg.smartAssign and mg.smartComp ~= ""
        local usePosEB  = (applyOn == "position") and not hasSmartDD
        local usePosDD  = hasSmartDD

        local posItems  = {}
        local nameItems = {}
        if usePosDD then
            local comp = PRT:GetComp(mg.smartComp)
            if comp then
                for pos = 1, 40 do
                    local n = comp.roster[pos]
                    if n and n ~= "" then
                        posItems[#posItems + 1] = { text = pos .. " — " .. n, value = pos }
                    end
                end
            end
        elseif useNameDD then
            local comp = PRT:GetComp(mg.smartComp)
            if comp then
                for pos = 1, 40 do
                    local n = comp.roster[pos]
                    if n and n ~= "" then
                        nameItems[#nameItems + 1] = { text = n, value = n }
                    end
                end
            end
        end

        for i, mark in ipairs(mg.marks) do
            local row = GetOrCreateMarkRow(self.markRows, i)
            row._idx = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dc, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT",   dc, "RIGHT",   0, 0)

            row.iconDD:SetSelected(mark.icon or 0)
            row.noteEB:SetText(mark.note or "")

            row.nameEB:SetShown(useNameEB)
            row.nameDD:SetShown(useNameDD)
            row.posEB:SetShown(usePosEB)
            row.posDD:SetShown(usePosDD)

            if useNameEB then row.nameEB:SetText(mark.playerName or "") end
            if useNameDD then
                row.nameDD:SetItems(nameItems)
                row.nameDD:SetSelected(mark.playerName or "")
            end
            if usePosEB then
                row.posEB:SetText(mark.position and mark.position > 0
                                  and tostring(mark.position) or "")
            end
            if usePosDD then
                row.posDD:SetItems(posItems)
                row.posDD:SetSelected(mark.position or 0)
            end

            row:Show()
            y = y - ROW_H
        end

        d.btnAddMark:ClearAllPoints()
        d.btnAddMark:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y - 2)
        d.btnAddMark:Show()
        y = y - 28

        local secMarkBot = y - SEC_GAP
        PlaceSectionBox(secMark, dc, secMarkTop, secMarkBot)
        y = secMarkBot - SEC_GAP

        -----------------------------------------------------------------
        -- NPC DEATH TRIGGERS section
        -----------------------------------------------------------------
        local secNpcTop = y
        y = y - SEC_PAD   -- top padding inside section box

        d.npcHdr:ClearAllPoints()
        d.npcHdr:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y)
        d.npcHdr:Show()
        y = y - 20

        d.npcDesc:ClearAllPoints()
        d.npcDesc:SetPoint("TOPLEFT",  dc, "TOPLEFT",  INSET + 6, y)
        d.npcDesc:SetPoint("TOPRIGHT", dc, "TOPRIGHT", -(INSET + 6), y)
        d.npcDesc:Show()
        y = y - 26

        d.npcColName:ClearAllPoints()
        d.npcColName:SetPoint("TOPLEFT", dc, "TOPLEFT", NPC_NAME + 4, y)
        d.npcColName:Show()

        d.npcColId:ClearAllPoints()
        d.npcColId:SetPoint("TOPLEFT", dc, "TOPLEFT", NPC_ID + 4, y)
        d.npcColId:Show()

        d.npcColCount:ClearAllPoints()
        d.npcColCount:SetPoint("TOPLEFT", dc, "TOPLEFT", NPC_COUNT + 4, y)
        d.npcColCount:Show()

        d.npcColNote:ClearAllPoints()
        d.npcColNote:SetPoint("TOPLEFT", dc, "TOPLEFT", NPC_NOTE + 4, y)
        d.npcColNote:Show()

        y = y - 18

        for i, trigger in ipairs(mg.npcTriggers) do
            local row = GetOrCreateNpcTrigRow(self.npcTrigRows, i)
            row._idx = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dc, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT",   dc, "RIGHT",   0, 0)
            row.nameEB:SetText(trigger.name or "")
            row.npcIdEB:SetText(trigger.npcId > 0 and tostring(trigger.npcId) or "")
            row.countEB:SetText(tostring(trigger.count or 1))
            row.noteEB:SetText(trigger.note or "")
            row:Show()
            y = y - ROW_H
        end

        d.btnAddNpc:ClearAllPoints()
        d.btnAddNpc:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y - 2)
        d.btnAddNpc:Show()
        y = y - 28

        local secNpcBot = y - SEC_GAP
        PlaceSectionBox(secNpc, dc, secNpcTop, secNpcBot)
        y = secNpcBot - SEC_GAP

        -----------------------------------------------------------------
        -- GROUP SWAP TRIGGERS section
        -----------------------------------------------------------------
        local secSwapTop = y
        y = y - SEC_PAD   -- top padding inside section box

        d.swapHdr:ClearAllPoints()
        d.swapHdr:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y)
        d.swapHdr:Show()
        y = y - 20

        d.swapDesc:ClearAllPoints()
        d.swapDesc:SetPoint("TOPLEFT",  dc, "TOPLEFT",  INSET + 6, y)
        d.swapDesc:SetPoint("TOPRIGHT", dc, "TOPRIGHT", -(INSET + 6), y)
        d.swapDesc:Show()
        y = y - 26

        d.swapColName:ClearAllPoints()
        d.swapColName:SetPoint("TOPLEFT", dc, "TOPLEFT", SWP_NAME + 4, y)
        d.swapColName:Show()

        d.swapColComp:ClearAllPoints()
        d.swapColComp:SetPoint("TOPLEFT", dc, "TOPLEFT", SWP_COMP + 4, y)
        d.swapColComp:Show()

        d.swapColNote:ClearAllPoints()
        d.swapColNote:SetPoint("TOPLEFT", dc, "TOPLEFT", SWP_NOTE + 4, y)
        d.swapColNote:Show()

        y = y - 18

        local compItems = {}
        for _, name in ipairs(PRT:GetCompOrder()) do
            compItems[#compItems + 1] = { text = name, value = name }
        end

        for i, trigger in ipairs(mg.swapTriggers) do
            local row = GetOrCreateSwapTrigRow(self.swapTrigRows, i)
            row._idx = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dc, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT",   dc, "RIGHT",   0, 0)
            row.nameEB:SetText(trigger.name or "")
            row.compDD:SetItems(compItems)
            row.compDD:SetSelected(trigger.compName or "")
            row.noteEB:SetText(trigger.note or "")
            row:Show()
            y = y - ROW_H
        end

        d.btnAddSwap:ClearAllPoints()
        d.btnAddSwap:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y - 2)
        d.btnAddSwap:Show()
        y = y - 28

        local secSwapBot = y - SEC_GAP
        PlaceSectionBox(secSwap, dc, secSwapTop, secSwapBot)
        y = secSwapBot - SEC_GAP

        -----------------------------------------------------------------
        -- TRIGGER REQUIREMENTS section
        -----------------------------------------------------------------
        local secTrigTop = y
        y = y - SEC_PAD   -- top padding inside section box

        d.trigReqHdr:ClearAllPoints()
        d.trigReqHdr:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y)
        d.trigReqHdr:Show()
        y = y - 22

        d.trigModeLabel:ClearAllPoints()
        d.trigModeLabel:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y - 4)
        d.trigModeLabel:Show()

        d.trigModeDD:ClearAllPoints()
        d.trigModeDD:SetPoint("LEFT", d.trigModeLabel, "RIGHT", 4, 0)
        d.trigModeDD:SetSelected(mg.triggerMode or "any")
        d.trigModeDD:Show()

        y = y - 28

        local showCond = (mg.triggerMode == "conditional")
        if showCond then
            d.condColTrig:ClearAllPoints()
            d.condColTrig:SetPoint("TOPLEFT", dc, "TOPLEFT", CND_TRIG + 4, y)
            d.condColTrig:Show()

            d.condColMust:ClearAllPoints()
            d.condColMust:SetPoint("TOPLEFT", dc, "TOPLEFT", CND_MUST + 4, y)
            d.condColMust:Show()

            d.condColFalse:ClearAllPoints()
            d.condColFalse:SetPoint("TOPLEFT", dc, "TOPLEFT", CND_FALSE + 4, y)
            d.condColFalse:Show()

            -- Compute checkbox center-X from actual header text width
            local mustW  = d.condColMust:GetStringWidth()
            if mustW < 10 then mustW = 70 end
            local falseW = d.condColFalse:GetStringWidth()
            if falseW < 10 then falseW = 74 end
            local mustCBX  = CND_MUST  + 4 + (mustW  / 2) - 10
            local falseCBX = CND_FALSE + 4 + (falseW / 2) - 10

            y = y - 18

            local trigNameItems = {}
            for _, t in ipairs(mg.npcTriggers) do
                if t.name and t.name ~= "" then
                    trigNameItems[#trigNameItems + 1] = { text = t.name, value = t.name }
                end
            end

            for i, cond in ipairs(mg.conditionals) do
                -- Migrate legacy data: old model used mustBeTrue=false as "must be false"
                if cond.mustBeFalse == nil and not cond.mustBeTrue then
                    cond.mustBeFalse = true
                end

                local row = GetOrCreateCondRow(self.condRows, i)
                row._idx = i
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", dc, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT",   dc, "RIGHT",   0, 0)
                row.trigDD:SetItems(trigNameItems)
                row.trigDD:SetSelected(cond.triggerName or "")

                -- Center checkboxes under their column headers
                row.mustCB:ClearAllPoints()
                row.mustCB:SetPoint("LEFT", mustCBX, 0)
                row.mustCB:SetChecked(cond.mustBeTrue or false)

                row.falseCB:ClearAllPoints()
                row.falseCB:SetPoint("LEFT", falseCBX, 0)
                row.falseCB:SetChecked(cond.mustBeFalse or false)

                row:Show()
                y = y - ROW_H
            end

            d.btnAddCond:ClearAllPoints()
            d.btnAddCond:SetPoint("TOPLEFT", dc, "TOPLEFT", INSET + 6, y - 2)
            d.btnAddCond:Show()
            y = y - 28
        else
            d.condColTrig:Hide()
            d.condColMust:Hide()
            d.condColFalse:Hide()
            d.btnAddCond:Hide()
        end

        local secTrigBot = y - SEC_GAP
        PlaceSectionBox(secTrigReq, dc, secTrigTop, secTrigBot)
        y = secTrigBot - SEC_GAP

        self.detailScroll:UpdateContentHeight(math.abs(y) + 20)
    end

    function panel:RequestRuleDetailsRefresh()
        local function RefreshAfterEdit()
            if panel and panel:IsShown() then
                panel:RefreshRuleDetails()
            end
        end

        if self._refreshGuard:Defer("ruleDetails", RefreshAfterEdit) then return end
        self:RefreshRuleDetails()
    end

    ---------------------------------------------------------------------------
    -- OnShow
    ---------------------------------------------------------------------------
    function panel:RefreshEnabledState()
        local db = PRT:GetDB()
        enableCB:SetChecked(db.autoMark.enabled)
    end

    function panel:OnShow()
        self:RefreshEnabledState()
        self:RefreshPresetDD()
        self:RefreshRules()
    end

    PRT:RegisterTab("automark", panel)
    PRT.autoMarkPanel = panel
end
