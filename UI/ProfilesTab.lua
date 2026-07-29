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
    local tab = CreateFrame("Frame", nil, UIParent)
    local scroller = W.CreateScrollFrame(tab, 300, 400)
    scroller:SetPoint("TOPLEFT")
    scroller:SetPoint("BOTTOMRIGHT")
    local panel = scroller.content

    local header = W.CreateHeader(panel, "Profiles")
    header:SetPoint("TOPLEFT", 12, -10)

    local description = W.CreateDescription(panel,
        "Use one PRT profile to activate the selected Group Auto Swap, Player Auto Marking, Target Marks, and Invite & Loot Tools presets together. Imports and exports include the full data for all selected presets.")
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

    local inviteLabel = W.CreateLabel(panel, "Invite & Loot Tools:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    inviteLabel:SetPoint("TOPLEFT", 12, -348)
    local inviteDD = W.CreateDropdown(panel, 280, {}, function(value)
        if PRT:ActivateInviteToolsPreset(value) then
            PRT:UpdateActivePRTProfileSelection("inviteTools", value, false)
        end
        panel:RefreshProfilesView()
    end)
    inviteDD:SetPoint("TOPLEFT", 180, -342)
    local inviteEnabledCB = W.CreateCheckbox(panel, "Enable when selected", function(checked)
        local profile = PRT:GetActivePRTProfile()
        if profile then profile.inviteToolsEnabled = checked and true or false end
    end)
    inviteEnabledCB:SetPoint("TOPLEFT", 480, -344)

    CreateDivider(panel, -384)

    local floatContent = CreateFrame("Frame", nil, panel)
    floatContent:SetPoint("TOPLEFT", 12, -396)
    floatContent:SetPoint("TOPRIGHT", -12, -396)
    floatContent:SetHeight(474)

    local floatHeader = W.CreateHeader(floatContent, "Profile Float")
    floatHeader:SetPoint("TOPLEFT", 2, -8)
    local floatDescription = W.CreateDescription(floatContent,
        "Keep the active PRT profile within reach as a standalone float, or place the selector inside the Floating Group List.")
    floatDescription:SetPoint("TOPLEFT", 2, -34)
    floatDescription:SetPoint("TOPRIGHT", -12, -34)

    local embedInGroupList = W.CreateCheckbox(floatContent,
        "Place profile selector inside Floating Group List", function(checked)
            PRT:GetDB().profileFloat.embedInGroupList = checked and true or false
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
            panel:RefreshProfilesView()
        end)
    embedInGroupList:SetPoint("TOPLEFT", 2, -70)

    local embeddedPositionLabel = W.CreateLabel(floatContent, "Placement:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    embeddedPositionLabel:SetPoint("TOPLEFT", 360, -74)
    local embeddedPosition = W.CreateDropdown(floatContent, 90, {
        { text = "Top", value = "top" },
        { text = "Bottom", value = "bottom" },
    }, function(value)
        PRT:GetDB().profileFloat.embeddedPosition = value
        if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
    end)
    embeddedPosition:SetPoint("TOPLEFT", 425, -68)

    local embeddedAlignmentLabel = W.CreateLabel(floatContent, "Alignment:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    embeddedAlignmentLabel:SetPoint("TOPLEFT", 530, -74)
    local embeddedAlignment = W.CreateDropdown(floatContent, 90, {
        { text = "Left", value = "left" },
        { text = "Center", value = "center" },
        { text = "Right", value = "right" },
    }, function(value)
        PRT:GetDB().profileFloat.embeddedAlignment = value
        if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
    end)
    embeddedAlignment:SetPoint("TOPLEFT", 600, -68)

    local embeddedHighlight = W.CreateCheckbox(floatContent,
        "Highlight selector", function(checked)
            PRT:GetDB().profileFloat.embeddedHighlight = checked and true or false
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end)
    embeddedHighlight:SetPoint("TOPLEFT", 450, -98)

    local floatShowCB = W.CreateCheckbox(floatContent, "Show Profile Float", function(checked)
        PRT:GetDB().profileFloat.shown = checked and true or false
        if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
    end)
    floatShowCB:SetPoint("TOPLEFT", 2, -98)

    local floatMouseoverCB = W.CreateCheckbox(floatContent, "Only visible on mouse-over", function(checked)
        PRT:GetDB().profileFloat.mouseoverOnly = checked and true or false
        if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
    end)
    floatMouseoverCB:SetPoint("TOPLEFT", 200, -98)

    local floatLockCB = W.CreateCheckbox(floatContent, "Lock position", function(checked)
        PRT:GetDB().profileFloat.locked = checked and true or false
    end)
    floatLockCB:SetPoint("TOPLEFT", 620, -98)

    local floatWidth = W.CreateExactSlider(floatContent, "Width (pixels)",
        80, 700, 1, 260, function(value)
            PRT:GetDB().profileFloat.width = value
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end)
    floatWidth:SetPoint("TOPLEFT", 2, -136)

    local floatHeight = W.CreateExactSlider(floatContent, "Height (pixels)",
        18, 90, 1, 260, function(value)
            PRT:GetDB().profileFloat.height = value
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end)
    floatHeight:SetPoint("TOPLEFT", 292, -136)

    local floatFontSize = W.CreateExactSlider(floatContent, "Font Size",
        6, 36, 1, 260, function(value)
            PRT:GetDB().profileFloat.fontSize = value
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end)
    floatFontSize:SetPoint("TOPLEFT", 2, -192)

    local floatOpacity = W.CreateExactSlider(floatContent, "Background Opacity",
        0, 1, 0.05, 260, function(value)
            PRT:GetDB().profileFloat.bgAlpha = value
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end, 2)
    floatOpacity:SetPoint("TOPLEFT", 292, -192)

    local floatTextModeLabel = W.CreateLabel(floatContent, "Long Text Handling:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    floatTextModeLabel:SetPoint("TOPLEFT", 2, -248)
    local floatTextMode = W.CreateDropdown(floatContent, 220,
        W.CONSTRAINED_TEXT_OVERFLOW_ITEMS, function(value)
            PRT:GetDB().profileFloat.textMode = value
            if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
        end)
    floatTextMode:SetPoint("TOPLEFT", 2, -266)

    local floatButtonTextLabel = W.CreateLabel(
        floatContent, "Main Button Text:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    floatButtonTextLabel:SetPoint("TOPLEFT", 292, -248)
    local floatButtonTextMode = W.CreateDropdown(floatContent, 210, {
        { text = "Profile: ProfileName", value = "full" },
        { text = "P: ProfileName:", value = "short" },
        { text = "ProfileName", value = "name" },
    }, function(value)
        PRT:SetProfileFloatButtonTextMode(value)
    end)
    floatButtonTextMode:SetPoint("TOPLEFT", 292, -266)

    local notificationHeader = W.CreateHeader(floatContent, "Profile Change Notification")
    notificationHeader:SetPoint("TOPLEFT", 2, -310)
    local notificationDescription = W.CreateDescription(floatContent,
        "Shows the newly selected profile on screen. Raid-entry status includes the active profile in its existing combined notification.")
    notificationDescription:SetPoint("TOPLEFT", 2, -336)
    notificationDescription:SetPoint("TOPRIGHT", -12, -336)

    local notificationEnabled = W.CreateCheckbox(floatContent,
        "Show notification when profile changes", function(checked)
            PRT:GetDB().profileFloat.notificationEnabled = checked and true or false
        end)
    notificationEnabled:SetPoint("TOPLEFT", 2, -376)

    local notificationSound = W.CreateCheckbox(floatContent,
        "Play notification sound", function(checked)
            PRT:GetDB().profileFloat.notificationSound = checked and true or false
        end)
    notificationSound:SetPoint("TOPLEFT", 292, -376)

    local testNotification = W.CreateButton(floatContent, "Test Notification", 130, 22)
    testNotification:SetPoint("TOPLEFT", 512, -374)
    testNotification:SetScript("OnClick", function()
        local profile = PRT:GetActivePRTProfile()
        if PRT.ShowPRTProfileNotification then
            PRT:ShowPRTProfileNotification(profile and profile.name or "None", true)
        end
    end)

    local notificationX = W.CreateExactSlider(floatContent, "Notification X Position",
        -1000, 1000, 1, 260, function(value)
            PRT:GetDB().profileFloat.notificationX = value
        end)
    notificationX:SetPoint("TOPLEFT", 2, -420)

    local notificationY = W.CreateExactSlider(floatContent, "Notification Y Position",
        -800, 800, 1, 260, function(value)
            PRT:GetDB().profileFloat.notificationY = value
        end)
    notificationY:SetPoint("TOPLEFT", 292, -420)
    scroller:UpdateContentHeight(880)

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
                if PRT.UpdateProfileFloat then PRT:UpdateProfileFloat() end
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
        inviteDD:SetItems(BuildPresetItems(db.inviteTools.presets))
        swapDD:SetSelected(profile and profile.autoSwapPreset or "",
            #db.autoSwap.swapPresets == 0 and "No presets available" or nil)
        markDD:SetSelected(profile and profile.autoMarkPreset or "",
            #db.autoMark.presets == 0 and "No presets available" or nil)
        targetDD:SetSelected(profile and profile.targetMarksPreset or "",
            #db.targetMarks.presets == 0 and "No presets available" or nil)
        inviteDD:SetSelected(profile and profile.inviteToolsPreset or "",
            #db.inviteTools.presets == 0 and "No presets available" or nil)
        swapEnabledCB:SetChecked(profile and profile.autoSwapEnabled or false)
        markEnabledCB:SetChecked(profile and profile.autoMarkEnabled or false)
        targetEnabledCB:SetChecked(profile and profile.targetMarksEnabled or false)
        inviteEnabledCB:SetChecked(profile and profile.inviteToolsEnabled or false)
        if db.profileFloat.textMode == "wrap" then
            db.profileFloat.textMode = "truncate"
        end
        embedInGroupList:SetChecked(db.profileFloat.embedInGroupList)
        embeddedPosition:SetSelected(
            db.profileFloat.embeddedPosition == "bottom" and "bottom" or "top")
        local alignment = db.profileFloat.embeddedAlignment
        if alignment ~= "center" and alignment ~= "right" then
            alignment = "left"
            db.profileFloat.embeddedAlignment = alignment
        end
        embeddedAlignment:SetSelected(alignment)
        embeddedHighlight:SetChecked(db.profileFloat.embeddedHighlight ~= false)
        floatShowCB:SetChecked(db.profileFloat.shown)
        floatMouseoverCB:SetChecked(db.profileFloat.mouseoverOnly)
        floatLockCB:SetChecked(db.profileFloat.locked)
        floatWidth:SetExactValue(db.profileFloat.width or 220)
        floatHeight:SetExactValue(db.profileFloat.height or 30)
        floatFontSize:SetExactValue(db.profileFloat.fontSize or PRT.FONT_SIZE)
        floatOpacity:SetExactValue(db.profileFloat.bgAlpha or 0.92)
        floatTextMode:SetSelected(db.profileFloat.textMode or "truncate")
        floatButtonTextMode:SetSelected(
            PRT:GetProfileFloatButtonTextMode())
        notificationEnabled:SetChecked(db.profileFloat.notificationEnabled ~= false)
        notificationSound:SetChecked(db.profileFloat.notificationSound ~= false)
        notificationX:SetExactValue(db.profileFloat.notificationX or 0)
        notificationY:SetExactValue(db.profileFloat.notificationY or 80)

        local standaloneEnabled = not db.profileFloat.embedInGroupList
        W.SetControlEnabled(embeddedPositionLabel, not standaloneEnabled)
        W.SetControlEnabled(embeddedPosition, not standaloneEnabled)
        W.SetControlEnabled(embeddedAlignmentLabel, not standaloneEnabled)
        W.SetControlEnabled(embeddedAlignment, not standaloneEnabled)
        W.SetControlEnabled(embeddedHighlight, not standaloneEnabled)
        W.SetControlEnabled(floatShowCB, standaloneEnabled)
        W.SetControlEnabled(floatMouseoverCB, standaloneEnabled)
        W.SetControlEnabled(floatLockCB, standaloneEnabled)
        W.SetControlEnabled(floatWidth, standaloneEnabled)
        W.SetControlEnabled(floatHeight, standaloneEnabled)
        W.SetControlEnabled(floatFontSize, standaloneEnabled)
        W.SetControlEnabled(floatOpacity, standaloneEnabled)
        W.SetControlEnabled(floatTextModeLabel, standaloneEnabled)
        W.SetControlEnabled(floatTextMode, standaloneEnabled)
    end

    function panel:OnShow()
        self:RefreshProfilesView()
    end

    function tab:RefreshProfilesView()
        panel:RefreshProfilesView()
    end

    function tab:OnShow()
        panel:OnShow()
    end

    PRT:RegisterTab("profiles", tab)
    PRT.profilesPanel = tab
end
