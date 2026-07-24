---------------------------------------------------------------------------
-- PugzRaidTools - Profiles Tab
-- Selects and bundles the feature presets used by one overall PRT profile.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local function CreateDivider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", -12, y)
    line:SetHeight(1)
    line:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.8)
    return line
end

local function BuildPresetItems(presets)
    local items = {}
    for _, preset in ipairs(presets or {}) do
        items[#items + 1] = { text = preset.name, value = preset.name }
    end
    if #items == 0 then
        items[1] = { text = "No presets available", value = "" }
    end
    return items
end

function PRT:BuildProfilesTab()
    local panel = CreateFrame("Frame", nil, UIParent)

    local header = W.CreateHeader(panel, "Profiles")
    header:SetPoint("TOPLEFT", 12, -10)

    local description = W.CreateDescription(panel,
        "Use one PRT profile to activate the selected Group Auto Swap, Player Auto Marking, and Target Marks presets together. Imports and exports include the full data for all selected presets.")
    description:SetPoint("TOPLEFT", 12, -36)
    description:SetPoint("TOPRIGHT", -12, -36)

    local activeLabel = W.CreateLabel(panel, "Active PRT Profile:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    activeLabel:SetPoint("TOPLEFT", 12, -80)

    local profileDD = W.CreateDropdown(panel, 240, {}, function(value)
        PRT:ActivatePRTProfile(value)
    end)
    profileDD:SetPoint("TOPLEFT", 12, -98)

    local newBtn = W.CreateButton(panel, "+ New", 72, 24)
    newBtn:SetPoint("LEFT", profileDD, "RIGHT", 8, 0)

    local renameBtn = W.CreateButton(panel, "Rename", 72, 24)
    renameBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)

    local deleteBtn = W.CreateButton(panel, "Delete", 72, 24)
    deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 6, 0)

    local exportBtn = W.CreateButton(panel, "Export", 72, 24)
    exportBtn:SetPoint("TOPRIGHT", -12, -98)

    local importBtn = W.CreateButton(panel, "Import", 72, 24)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -6, 0)

    CreateDivider(panel, -136)

    local featureHeader = W.CreateHeader(panel, "Feature Presets")
    featureHeader:SetPoint("TOPLEFT", 12, -152)

    local featureDescription = W.CreateDescription(panel,
        "Preset changes apply immediately. Enable defaults apply once when switching to this PRT profile; manual feature toggles do not change them.")
    featureDescription:SetPoint("TOPLEFT", 12, -178)
    featureDescription:SetPoint("TOPRIGHT", -12, -178)

    local swapLabel = W.CreateLabel(panel, "Group Auto Swap:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    swapLabel:SetPoint("TOPLEFT", 12, -216)
    local swapDD = W.CreateDropdown(panel, 280, {}, function(value)
        local db = PRT:GetDB()
        db.autoSwap.activeSwapPreset = value
        PRT:UpdateActivePRTProfileSelection("autoSwap", value, false)
        if PRT.UpdateAutoSwapListeners then PRT:UpdateAutoSwapListeners() end
        if PRT.autoSwapPanel and PRT.autoSwapPanel:IsShown() then
            if PRT.autoSwapPanel.RefreshPresetList then PRT.autoSwapPanel:RefreshPresetList() end
            if PRT.autoSwapPanel.RefreshPresetSettings then PRT.autoSwapPanel:RefreshPresetSettings() end
            if PRT.autoSwapPanel.RefreshTriggers then PRT.autoSwapPanel:RefreshTriggers() end
        end
        panel:RefreshProfilesView()
    end)
    swapDD:SetPoint("TOPLEFT", 180, -210)
    local swapEnabledCB = W.CreateCheckbox(panel, "Enable when selected", function(checked)
        local profile = PRT:GetActivePRTProfile()
        if profile then profile.autoSwapEnabled = checked and true or false end
    end)
    swapEnabledCB:SetPoint("TOPLEFT", 480, -212)

    local markLabel = W.CreateLabel(panel, "Player Auto Marking:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    markLabel:SetPoint("TOPLEFT", 12, -260)
    local markDD = W.CreateDropdown(panel, 280, {}, function(value)
        local db = PRT:GetDB()
        db.autoMark.activePreset = value
        PRT:UpdateActivePRTProfileSelection("autoMark", value, false)
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        if PRT.autoMarkPanel and PRT.autoMarkPanel:IsShown() then
            if PRT.autoMarkPanel.RefreshPresetDD then PRT.autoMarkPanel:RefreshPresetDD() end
            if PRT.autoMarkPanel.RefreshRules then PRT.autoMarkPanel:RefreshRules() end
        end
        panel:RefreshProfilesView()
    end)
    markDD:SetPoint("TOPLEFT", 180, -254)
    local markEnabledCB = W.CreateCheckbox(panel, "Enable when selected", function(checked)
        local profile = PRT:GetActivePRTProfile()
        if profile then profile.autoMarkEnabled = checked and true or false end
    end)
    markEnabledCB:SetPoint("TOPLEFT", 480, -256)

    local targetLabel = W.CreateLabel(panel, "Target Marks:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    targetLabel:SetPoint("TOPLEFT", 12, -304)
    local targetDD = W.CreateDropdown(panel, 280, {}, function(value)
        local db = PRT:GetDB()
        db.targetMarks.activePreset = value
        PRT:UpdateActivePRTProfileSelection("targetMarks", value, false)
        if PRT.InvalidateTargetMarksCache then PRT:InvalidateTargetMarksCache() end
        if PRT.targetMarksPanel and PRT.targetMarksPanel:IsShown()
                and PRT.targetMarksPanel.RefreshTargetMarksView then
            PRT.targetMarksPanel:RefreshTargetMarksView(true)
        end
        panel:RefreshProfilesView()
    end)
    targetDD:SetPoint("TOPLEFT", 180, -298)
    local targetEnabledCB = W.CreateCheckbox(panel, "Enable when selected", function(checked)
        local profile = PRT:GetActivePRTProfile()
        if profile then profile.targetMarksEnabled = checked and true or false end
    end)
    targetEnabledCB:SetPoint("TOPLEFT", 480, -300)

    local namePopup = W.CreateNamePopup("PRT_OverallProfileNamePopup", {
        title = "PRT Profile",
        prompt = "Profile name:",
        acceptText = "Save",
    })
    local deletePopup = W.CreateConfirmPopup("PRT_OverallProfileDeletePopup", {
        title = "Delete PRT Profile",
        confirmText = "Delete",
        confirmTextColor = { 1, 0.25, 0.25 },
    })
    local importPopup = W.CreateTextTransferPopup("PRT_OverallProfileImportPopup", {
        title = "Import PRT Profile",
        instruction = "Paste a full PRT profile export below.",
        actionText = "Import",
        showCancel = true,
    })
    local exportPopup = W.CreateTextTransferPopup("PRT_OverallProfileExportPopup", {
        title = "Export PRT Profile",
        instruction = "Copy this text to share the active PRT profile and all of its selected feature presets.",
        actionText = "Close",
    })

    newBtn:SetScript("OnClick", function()
        namePopup:Open({
            title = "New PRT Profile",
            acceptText = "Create",
            onAccept = function(text)
                local profile, err = PRT:CreatePRTProfile(text)
                if not profile then
                    PRT.Print(err)
                    return false
                end
                PRT:ActivatePRTProfile(profile.name)
                return true
            end,
        })
    end)

    renameBtn:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local profile = PRT:GetActivePRTProfile()
        if not profile then return end
        namePopup:Open({
            title = "Rename PRT Profile",
            text = profile.name,
            highlight = true,
            acceptText = "Rename",
            onAccept = function(text)
                local newName = PRT.Trim(tostring(text or ""))
                if newName == "" then
                    PRT.Print("Enter a profile name.")
                    return false
                end
                local existing = PRT:GetPRTProfile(newName)
                if existing and existing ~= profile then
                    PRT.Print("A PRT profile with that name already exists.")
                    return false
                end
                profile.name = newName
                db.prtProfiles.activeProfile = newName
                panel:RefreshProfilesView()
                return true
            end,
        })
    end)

    deleteBtn:SetScript("OnClick", function()
        local db = PRT:GetDB()
        local profile = PRT:GetActivePRTProfile()
        if not profile then return end
        if #db.prtProfiles.profiles <= 1 then
            PRT.Print("At least one PRT profile must remain.")
            return
        end
        deletePopup:Open({
            message = 'Delete the PRT profile "' .. profile.name .. '"? Feature presets will not be deleted.',
            onConfirm = function()
                for index, candidate in ipairs(db.prtProfiles.profiles) do
                    if candidate == profile then
                        table.remove(db.prtProfiles.profiles, index)
                        break
                    end
                end
                PRT:ActivatePRTProfile(db.prtProfiles.profiles[1].name)
                return true
            end,
        })
    end)

    importBtn:SetScript("OnClick", function()
        importPopup:Open({
            text = "",
            onAction = function(text)
                local profile, err = PRT:ImportPRTProfileBundle(text)
                if not profile then
                    PRT.Print(err)
                    return false
                end
                panel:RefreshProfilesView()
                PRT.Print('Imported PRT profile "' .. profile.name .. '".')
                return true
            end,
        })
    end)

    exportBtn:SetScript("OnClick", function()
        local profile = PRT:GetActivePRTProfile()
        if not profile then return end
        exportPopup:Open({
            text = PRT:ExportPRTProfile(profile),
            highlight = true,
            onAction = function() return true end,
        })
    end)

    function panel:RefreshProfilesView()
        PRT:EnsurePRTProfilesDefaults()
        local db = PRT:GetDB()
        local profileItems = {}
        for _, profile in ipairs(db.prtProfiles.profiles) do
            profileItems[#profileItems + 1] = { text = profile.name, value = profile.name }
        end
        profileDD:SetItems(profileItems)
        profileDD:SetSelected(db.prtProfiles.activeProfile)

        local profile = PRT:GetActivePRTProfile()
        swapDD:SetItems(BuildPresetItems(db.autoSwap.swapPresets))
        markDD:SetItems(BuildPresetItems(db.autoMark.presets))
        targetDD:SetItems(BuildPresetItems(db.targetMarks.presets))
        swapDD:SetSelected(profile and profile.autoSwapPreset or "",
            #db.autoSwap.swapPresets == 0 and "No presets available" or nil)
        markDD:SetSelected(profile and profile.autoMarkPreset or "",
            #db.autoMark.presets == 0 and "No presets available" or nil)
        targetDD:SetSelected(profile and profile.targetMarksPreset or "",
            #db.targetMarks.presets == 0 and "No presets available" or nil)
        swapEnabledCB:SetChecked(profile and profile.autoSwapEnabled or false)
        markEnabledCB:SetChecked(profile and profile.autoMarkEnabled or false)
        targetEnabledCB:SetChecked(profile and profile.targetMarksEnabled or false)
    end

    function panel:OnShow()
        self:RefreshProfilesView()
    end

    PRT:RegisterTab("profiles", panel)
    PRT.profilesPanel = panel
end
