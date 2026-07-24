---------------------------------------------------------------------------
-- PugzRaidTools - Overall Profiles
-- Links one preset from each configurable feature and bundles their data
-- for one-step import and export.
---------------------------------------------------------------------------
local _, PRT = ...

local FEATURE_KEYS = {
    autoSwap = "autoSwapPreset",
    autoMark = "autoMarkPreset",
    targetMarks = "targetMarksPreset",
}

local function NormalizeProfile(profile, db)
    profile.name = PRT.Trim(tostring(profile.name or ""))
    if profile.name == "" then profile.name = "Profile" end
    profile.autoSwapPreset = tostring(profile.autoSwapPreset or "")
    profile.autoMarkPreset = tostring(profile.autoMarkPreset or "")
    profile.targetMarksPreset = tostring(profile.targetMarksPreset or "")
    if profile.autoSwapEnabled == nil then
        profile.autoSwapEnabled = db.autoSwap.enabled and true or false
    end
    if profile.autoMarkEnabled == nil then
        profile.autoMarkEnabled = db.autoMark.enabled and true or false
    end
    if profile.targetMarksEnabled == nil then
        profile.targetMarksEnabled = db.targetMarks.enabled and true or false
    end
    return profile
end

local function SanitizeLineValue(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

local function FindByName(list, name)
    for _, item in ipairs(list or {}) do
        if item.name == name then return item end
    end
end

local function MakeUniqueName(list, requestedName, fallback)
    local base = PRT.Trim(tostring(requestedName or ""))
    if base == "" then base = fallback or "Imported" end
    if not FindByName(list, base) then return base end

    local suffix = 2
    while FindByName(list, base .. " (" .. suffix .. ")") do
        suffix = suffix + 1
    end
    return base .. " (" .. suffix .. ")"
end

local function ExtractSection(raw, sectionName)
    local padded = "\n" .. raw .. "\n"
    local openMarker = "\n[" .. sectionName .. "]\n"
    local closeMarker = "\n[/" .. sectionName .. "]\n"
    local openStart, openEnd = padded:find(openMarker, 1, true)
    if not openStart then return nil end

    local closeStart = padded:find(closeMarker, openEnd + 1, true)
    if not closeStart then
        return nil, "Missing [/" .. sectionName .. "]."
    end
    return PRT.Trim(padded:sub(openEnd + 1, closeStart - 1))
end

local function ParseProfileMetadata(raw)
    local metadata = {}
    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line == "[GroupAutoSwapPreset]"
                or line == "[PlayerAutoMarkingPreset]"
                or line == "[TargetMarksPreset]" then
            break
        end

        local key, value = line:match("^(%w+)=(.*)$")
        if key then metadata[key] = PRT.Trim(value) end
    end
    return metadata
end

local function ParseOptionalBoolean(value)
    if value == nil then return nil end
    if value == "true" then return true end
    if value == "false" then return false end
    return nil, "Expected true or false."
end

local function BooleanOrDefault(value, fallback)
    if value == nil then return fallback and true or false end
    return value and true or false
end

local function RefreshFeaturePanels()
    if PRT.autoSwapPanel and PRT.autoSwapPanel:IsShown() then
        if PRT.autoSwapPanel.RefreshPresetList then PRT.autoSwapPanel:RefreshPresetList() end
        if PRT.autoSwapPanel.RefreshPresetSettings then PRT.autoSwapPanel:RefreshPresetSettings() end
        if PRT.autoSwapPanel.RefreshTriggers then PRT.autoSwapPanel:RefreshTriggers() end
    end
    if PRT.autoMarkPanel and PRT.autoMarkPanel:IsShown() then
        if PRT.autoMarkPanel.RefreshPresetDD then PRT.autoMarkPanel:RefreshPresetDD() end
        if PRT.autoMarkPanel.RefreshRules then PRT.autoMarkPanel:RefreshRules() end
    end
    if PRT.targetMarksPanel and PRT.targetMarksPanel:IsShown()
            and PRT.targetMarksPanel.RefreshTargetMarksView then
        PRT.targetMarksPanel:RefreshTargetMarksView(true)
    end
    if PRT.profilesPanel and PRT.profilesPanel:IsShown()
            and PRT.profilesPanel.RefreshProfilesView then
        PRT.profilesPanel:RefreshProfilesView()
    end
end

function PRT:EnsurePRTProfilesDefaults()
    local db = self:GetDB()
    db.prtProfiles = db.prtProfiles or {}
    local store = db.prtProfiles
    store.profiles = store.profiles or {}
    store.activeProfile = tostring(store.activeProfile or "")

    for _, profile in ipairs(store.profiles) do
        NormalizeProfile(profile, db)
    end

    if #store.profiles == 0 then
        store.profiles[1] = {
            name = "Default",
            autoSwapPreset = db.autoSwap.activeSwapPreset or "",
            autoMarkPreset = db.autoMark.activePreset or "",
            targetMarksPreset = db.targetMarks.activePreset or "",
            autoSwapEnabled = db.autoSwap.enabled and true or false,
            autoMarkEnabled = db.autoMark.enabled and true or false,
            targetMarksEnabled = db.targetMarks.enabled and true or false,
        }
    end

    if not self:GetPRTProfile(store.activeProfile) then
        store.activeProfile = store.profiles[1].name
    end
end

function PRT:GetPRTProfile(name)
    if not name or name == "" then return nil end
    local db = self:GetDB()
    return FindByName(db.prtProfiles and db.prtProfiles.profiles, name)
end

function PRT:GetActivePRTProfile()
    local db = self:GetDB()
    local store = db.prtProfiles
    if not store then return nil end
    return self:GetPRTProfile(store.activeProfile)
end

function PRT:CreatePRTProfile(name)
    self:EnsurePRTProfilesDefaults()
    local db = self:GetDB()
    local store = db.prtProfiles
    local cleanName = PRT.Trim(tostring(name or ""))
    if cleanName == "" then return nil, "Enter a profile name." end
    if self:GetPRTProfile(cleanName) then return nil, "A PRT profile with that name already exists." end

    local profile = {
        name = cleanName,
        autoSwapPreset = db.autoSwap.activeSwapPreset or "",
        autoMarkPreset = db.autoMark.activePreset or "",
        targetMarksPreset = db.targetMarks.activePreset or "",
        autoSwapEnabled = db.autoSwap.enabled and true or false,
        autoMarkEnabled = db.autoMark.enabled and true or false,
        targetMarksEnabled = db.targetMarks.enabled and true or false,
    }
    store.profiles[#store.profiles + 1] = profile
    return profile
end

function PRT:ActivatePRTProfile(name, refreshUI, applyEnabledDefaults)
    local initialDB = self:GetDB()
    local previousProfileName = initialDB.prtProfiles and initialDB.prtProfiles.activeProfile or ""
    self:EnsurePRTProfilesDefaults()
    local db = self:GetDB()
    local profile = self:GetPRTProfile(name)
    if not profile then return false end

    local profileChanged = previousProfileName ~= profile.name
    db.prtProfiles.activeProfile = profile.name

    if self:GetSwapPreset(profile.autoSwapPreset) then
        db.autoSwap.activeSwapPreset = profile.autoSwapPreset
    elseif db.autoSwap.swapPresets[1] then
        profile.autoSwapPreset = db.autoSwap.swapPresets[1].name
        db.autoSwap.activeSwapPreset = profile.autoSwapPreset
    else
        profile.autoSwapPreset = ""
        db.autoSwap.activeSwapPreset = ""
    end

    if self:GetAutoMarkPreset(profile.autoMarkPreset) then
        db.autoMark.activePreset = profile.autoMarkPreset
    elseif db.autoMark.presets[1] then
        profile.autoMarkPreset = db.autoMark.presets[1].name
        db.autoMark.activePreset = profile.autoMarkPreset
    else
        profile.autoMarkPreset = ""
        db.autoMark.activePreset = ""
    end

    if self:GetTargetMarksPreset(profile.targetMarksPreset) then
        db.targetMarks.activePreset = profile.targetMarksPreset
    elseif db.targetMarks.presets[1] then
        profile.targetMarksPreset = db.targetMarks.presets[1].name
        db.targetMarks.activePreset = profile.targetMarksPreset
    else
        profile.targetMarksPreset = ""
        db.targetMarks.activePreset = ""
    end

    if profileChanged and applyEnabledDefaults ~= false then
        db.autoSwap.enabled = profile.autoSwapEnabled and true or false
        db.autoMark.enabled = profile.autoMarkEnabled and true or false
        db.targetMarks.enabled = profile.targetMarksEnabled and true or false
    end

    if self.UpdateAutoSwapListeners then self:UpdateAutoSwapListeners() end
    if self.UpdateAutoMarkListeners then self:UpdateAutoMarkListeners() end
    if self.InvalidateTargetMarksCache then self:InvalidateTargetMarksCache() end
    if self.HandleTargetMarksModifierChange then self:HandleTargetMarksModifierChange() end
    if refreshUI ~= false and self.RefreshFeatureToggleUI then
        self:RefreshFeatureToggleUI()
    end
    if refreshUI ~= false then RefreshFeaturePanels() end
    return true
end

function PRT:UpdateActivePRTProfileSelection(featureKey, presetName, refreshUI)
    local field = FEATURE_KEYS[featureKey]
    if not field then return end
    self:EnsurePRTProfilesDefaults()

    local profile = self:GetActivePRTProfile()
    if not profile then return end
    profile[field] = tostring(presetName or "")

    if refreshUI ~= false and self.profilesPanel and self.profilesPanel.RefreshProfilesView then
        self.profilesPanel:RefreshProfilesView()
    end
end

function PRT:RenamePRTProfilePresetReference(featureKey, oldName, newName)
    local field = FEATURE_KEYS[featureKey]
    if not field or oldName == newName then return end
    local db = self:GetDB()
    for _, profile in ipairs(db.prtProfiles and db.prtProfiles.profiles or {}) do
        if profile[field] == oldName then profile[field] = newName or "" end
    end
end

function PRT:RemovePRTProfilePresetReference(featureKey, removedName, replacementName)
    local field = FEATURE_KEYS[featureKey]
    if not field then return end
    local db = self:GetDB()
    for _, profile in ipairs(db.prtProfiles and db.prtProfiles.profiles or {}) do
        if profile[field] == removedName then profile[field] = replacementName or "" end
    end
end

function PRT:ExportPRTProfile(profile)
    profile = profile or self:GetActivePRTProfile()
    if not profile then return "" end

    local swapPreset = self:GetSwapPreset(profile.autoSwapPreset)
    local markPreset = self:GetAutoMarkPreset(profile.autoMarkPreset)
    local targetPreset = self:GetTargetMarksPreset(profile.targetMarksPreset)
    local lines = {
        "[PRTProfile: " .. SanitizeLineValue(profile.name) .. "]",
        "formatVersion=2",
        "groupAutoSwap=" .. SanitizeLineValue(swapPreset and swapPreset.name or ""),
        "groupAutoSwapEnabled=" .. tostring(profile.autoSwapEnabled and true or false),
        "playerAutoMarking=" .. SanitizeLineValue(markPreset and markPreset.name or ""),
        "playerAutoMarkingEnabled=" .. tostring(profile.autoMarkEnabled and true or false),
        "targetMarks=" .. SanitizeLineValue(targetPreset and targetPreset.name or ""),
        "targetMarksEnabled=" .. tostring(profile.targetMarksEnabled and true or false),
    }

    if swapPreset then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[GroupAutoSwapPreset]"
        lines[#lines + 1] = self:ExportSwapPreset(swapPreset)
        lines[#lines + 1] = "[/GroupAutoSwapPreset]"
    end
    if markPreset then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[PlayerAutoMarkingPreset]"
        lines[#lines + 1] = self:ExportMarkPreset(markPreset)
        lines[#lines + 1] = "[/PlayerAutoMarkingPreset]"
    end
    if targetPreset then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[TargetMarksPreset]"
        lines[#lines + 1] = self:ExportTargetMarksPreset(targetPreset)
        lines[#lines + 1] = "[/TargetMarksPreset]"
    end

    return table.concat(lines, "\n")
end

function PRT:ImportPRTProfileBundle(raw)
    raw = tostring(raw or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)
    if raw == "" then return nil, "Paste a PRT profile export first." end

    local profileName = raw:match("^%[PRTProfile:%s*(.-)%]")
    if not profileName then return nil, "No [PRTProfile: Name] header was found." end
    local metadata = ParseProfileMetadata(raw)

    local swapRaw, swapSectionError = ExtractSection(raw, "GroupAutoSwapPreset")
    local markRaw, markSectionError = ExtractSection(raw, "PlayerAutoMarkingPreset")
    local targetRaw, targetSectionError = ExtractSection(raw, "TargetMarksPreset")
    local sectionError = swapSectionError or markSectionError or targetSectionError
    if sectionError then return nil, sectionError end
    if not swapRaw and not markRaw and not targetRaw then
        return nil, "The PRT profile does not contain any feature presets."
    end

    local swapPreset
    if swapRaw then
        swapPreset = self:ParseSwapPresetString(swapRaw)
        if not swapPreset then return nil, "The Group Auto Swap preset could not be read." end
    end

    local markPreset
    if markRaw then
        markPreset = self:ParseMarkPresetString(markRaw)
        if not markPreset then return nil, "The Player Auto Marking preset could not be read." end
        if self.EnsureAutoMarkPresetDefaults then self:EnsureAutoMarkPresetDefaults(markPreset) end
    end

    local targetPreset
    if targetRaw then
        targetPreset = self:ParseTargetMarksPresetString(targetRaw)
        if not targetPreset then return nil, "The Target Marks preset could not be read." end
    end

    self:EnsurePRTProfilesDefaults()
    local db = self:GetDB()
    local swapEnabled, swapEnabledError = ParseOptionalBoolean(metadata.groupAutoSwapEnabled)
    local markEnabled, markEnabledError = ParseOptionalBoolean(metadata.playerAutoMarkingEnabled)
    local targetEnabled, targetEnabledError = ParseOptionalBoolean(metadata.targetMarksEnabled)
    if swapEnabledError then return nil, "Invalid groupAutoSwapEnabled value. " .. swapEnabledError end
    if markEnabledError then return nil, "Invalid playerAutoMarkingEnabled value. " .. markEnabledError end
    if targetEnabledError then return nil, "Invalid targetMarksEnabled value. " .. targetEnabledError end

    if swapPreset then
        swapPreset.name = MakeUniqueName(db.autoSwap.swapPresets, swapPreset.name, "Imported Auto Swap")
        swapPreset.killCounters = {}
        db.autoSwap.swapPresets[#db.autoSwap.swapPresets + 1] = swapPreset
    end
    if markPreset then
        markPreset.name = MakeUniqueName(db.autoMark.presets, markPreset.name, "Imported Auto Marking")
        db.autoMark.presets[#db.autoMark.presets + 1] = markPreset
    end
    if targetPreset then
        targetPreset.name = MakeUniqueName(db.targetMarks.presets, targetPreset.name, "Imported Target Marks")
        db.targetMarks.presets[#db.targetMarks.presets + 1] = targetPreset
    end

    local profile = {
        name = MakeUniqueName(db.prtProfiles.profiles, profileName, "Imported Profile"),
        autoSwapPreset = swapPreset and swapPreset.name or "",
        autoMarkPreset = markPreset and markPreset.name or "",
        targetMarksPreset = targetPreset and targetPreset.name or "",
        autoSwapEnabled = BooleanOrDefault(swapEnabled, db.autoSwap.enabled),
        autoMarkEnabled = BooleanOrDefault(markEnabled, db.autoMark.enabled),
        targetMarksEnabled = BooleanOrDefault(targetEnabled, db.targetMarks.enabled),
    }
    db.prtProfiles.profiles[#db.prtProfiles.profiles + 1] = profile
    self:ActivatePRTProfile(profile.name)
    return profile
end

function PRT:InitPRTProfiles()
    self:EnsurePRTProfilesDefaults()
    local active = self:GetActivePRTProfile()
    if active then self:ActivatePRTProfile(active.name, false, false) end
end
