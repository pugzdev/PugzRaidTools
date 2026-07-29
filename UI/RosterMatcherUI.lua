---------------------------------------------------------------------------
-- PugzRaidTools - Roster Matcher Popups
-- Raid Groups "Auto Match" and Alias Database windows.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local MATCHER_WIDTH = 1120
local MATCHER_HEIGHT = 700
local ALIAS_WIDTH = 540
local ALIAS_HEIGHT = 640
local ALIAS_MIN_WIDTH = 540
local ALIAS_MIN_HEIGHT = 320
local SCREEN_MARGIN = 20
local RESIZE_GRIP_SIZE = 16

local matcherPopup
local aliasPopup
local aliasNamePopup
local aliasCharacterPopup
local aliasImportPopup
local aliasExportPopup
local aliasImportOptionsPopup
local aliasMergePopup
local aliasDeleteConfirmPopup
local matcherConfirmPopup
local MatcherApplySelections
local MatcherRefresh
local popupFocusSerial = 0

local function CreateBareCheck(parent)
    local cb = W.CreateCheckButton(parent, 20)
    cb:SetSize(20, 20)
    return cb
end

local function SetAliasInputState(editBox, enabled, text)
    if not editBox then return end
    local hasFocus = editBox.HasFocus and editBox:HasFocus()
    if not hasFocus then
        editBox:SetText(text or "")
    end
    if enabled then
        if editBox.Enable then editBox:Enable() end
        editBox:SetAlpha(1)
    else
        if hasFocus then
            editBox:ClearFocus()
        end
        if editBox.Disable then editBox:Disable() end
        editBox:SetAlpha(0.45)
    end
    if editBox._ph then
        editBox._ph:SetShown(editBox:GetText() == "")
    end
end

local function GetPopupResizeBounds(minW, minH)
    local screenW = UIParent and UIParent.GetWidth and UIParent:GetWidth() or minW
    local screenH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or minH
    local maxW = math.max(minW, math.floor((screenW or minW) - SCREEN_MARGIN))
    local maxH = math.max(minH, math.floor((screenH or minH) - SCREEN_MARGIN))
    return minW, minH, maxW, maxH
end

local function ApplyPopupResizeBounds(frame, minW, minH)
    local boundedMinW, boundedMinH, maxW, maxH = GetPopupResizeBounds(minW, minH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(boundedMinW, boundedMinH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(boundedMinW, boundedMinH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

local function BringPopupToFront(frame)
    if not frame then return end
    if PRT.BringManagedFrameToFront then
        PRT.BringManagedFrameToFront(frame, "FULLSCREEN_DIALOG")
        return
    end
    popupFocusSerial = popupFocusSerial + 1
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    if frame.SetFrameStrata then
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if frame.SetFrameLevel then
        frame:SetFrameLevel(200 + popupFocusSerial)
    end
end

local function PromotePopup(frame, strata)
    if not frame then return end
    if PRT.BringManagedFrameToFront then
        PRT.BringManagedFrameToFront(frame, strata or "FULLSCREEN_DIALOG")
    else
        BringPopupToFront(frame)
    end
end

local function OpenPopupOnTop(popup, openOpts, strata)
    if not popup or not popup.Open then return end
    popup:Open(openOpts)
    PromotePopup(popup, strata or "TOOLTIP")
    C_Timer.After(0, function()
        if popup and popup.IsShown and popup:IsShown() then
            PromotePopup(popup, strata or "TOOLTIP")
        end
    end)
    C_Timer.After(0.05, function()
        if popup and popup.IsShown and popup:IsShown() then
            PromotePopup(popup, strata or "TOOLTIP")
        end
    end)
end

local function MakePopupInteractive(frame, minW, minH)
    if not frame then return end

    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    ApplyPopupResizeBounds(frame, minW, minH)
    frame:HookScript("OnSizeChanged", function(self)
        ApplyPopupResizeBounds(self, minW, minH)
    end)
    frame:HookScript("OnShow", function(self)
        BringPopupToFront(self)
    end)
    frame:HookScript("OnMouseDown", function(self)
        BringPopupToFront(self)
    end)
    if frame.drag then
        frame.drag:HookScript("OnMouseDown", function()
            BringPopupToFront(frame)
        end)
    end

    if not frame._resizeGrip then
        frame._resizeGrip = W.CreateResizeGrip(frame, function(_, btn)
            if btn == "LeftButton" then
                frame:StartSizing("BOTTOMRIGHT")
            end
        end, {
            point = { "BOTTOMRIGHT", 0, 0 },
            size = RESIZE_GRIP_SIZE,
            color = { 0.45, 0.45, 0.45, 0.5 },
            hoverColor = { 0.8, 0.8, 0.8, 0.8 },
            onEnter = function()
                BringPopupToFront(frame)
            end,
            onMouseUp = function()
                frame:StopMovingOrSizing()
            end,
        })
    end
end

local function GetUnknownClassColor()
    return PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3]
end

local function SetAliasCharacterText(fs, name, classFile)
    local r, g, b
    if classFile and classFile ~= "" then
        r, g, b = PRT:GetMatcherClassColor(classFile)
    else
        r, g, b = GetUnknownClassColor()
    end
    fs:SetText(name or "")
    fs:SetTextColor(r, g, b)
end

local function RefreshGroupsPanel(panel, compName)
    if not panel or not panel.LoadComp then return end
    if compName and panel.selectedComp == compName then
        panel:LoadComp(compName)
    else
        panel:RefreshHighlights()
        panel:RefreshQuickLoad()
    end
    if PRT.RefreshFloatingList then
        PRT:RefreshFloatingList()
    end
end

local function RequestAliasRefresh()
    if not aliasPopup or not aliasPopup:IsShown() or not aliasPopup.Refresh then return end
    if aliasPopup._refreshGuard
        and aliasPopup._refreshGuard:Defer("aliasPopup", RequestAliasRefresh) then
        return
    end
    if aliasPopup._refreshQueued then return end
    aliasPopup._refreshQueued = true
    C_Timer.After(0, function()
        if not aliasPopup then return end
        aliasPopup._refreshQueued = false
        if aliasPopup:IsShown() then
            aliasPopup:Refresh()
        end
    end)
end

local function RequestMatcherRefresh()
    if not matcherPopup or not matcherPopup:IsShown() or not matcherPopup.Refresh then return end
    if matcherPopup._refreshGuard
        and matcherPopup._refreshGuard:Defer("matcherPopup", RequestMatcherRefresh) then
        return
    end
    if matcherPopup._refreshQueued then return end
    matcherPopup._refreshQueued = true
    C_Timer.After(0, function()
        if not matcherPopup then return end
        matcherPopup._refreshQueued = false
        if matcherPopup:IsShown() then
            matcherPopup:Refresh()
        end
    end)
end

local function GetPanelRosterSnapshot(panel)
    if not panel or not panel.slots then return nil end
    local roster = {}
    for i = 1, 40 do
        local slot = panel.slots[i]
        roster[i] = PRT.Trim(slot and slot:GetText() or "")
    end
    return roster
end

local function EnsureCommonPopups()
    if not matcherConfirmPopup then
        matcherConfirmPopup = W.CreateConfirmPopup("PRT_RosterMatcherConfirmPopup", {
            width = 360,
            height = 120,
            confirmTextColor = PRT.C.RED,
            bgColor = { 0, 0, 0, 1.0 },
        })
        matcherConfirmPopup:HookScript("OnShow", function(self)
            BringPopupToFront(self)
        end)
        matcherConfirmPopup:HookScript("OnMouseDown", function(self)
            BringPopupToFront(self)
        end)
    end

    if not aliasDeleteConfirmPopup then
        aliasDeleteConfirmPopup = W.CreateConfirmPopup(
            "PRT_RosterAliasDeleteConfirmPopup", {
                width = 300,
                height = 92,
                buttonWidth = 134,
                cancelWidth = 134,
                buttonHeight = 22,
                buttonY = 7,
                confirmTextColor = PRT.C.RED,
                bgColor = { 0, 0, 0, 1.0 },
            })
        aliasDeleteConfirmPopup:HookScript("OnShow", function(self)
            BringPopupToFront(self)
        end)
        aliasDeleteConfirmPopup:HookScript(
            "OnMouseDown", function(self)
                BringPopupToFront(self)
            end)
    end

    if not aliasNamePopup then
        aliasNamePopup = W.CreateNamePopup("PRT_RosterAliasNamePopup", {
            width = 340,
            height = 118,
            title = "New Alias",
            prompt = "Enter alias name:",
            acceptText = "Create",
            placeholder = "Alias name...",
            bgColor = { 0, 0, 0, 1.0 },
        })
        aliasNamePopup:HookScript("OnShow", function(self)
            BringPopupToFront(self)
        end)
        aliasNamePopup:HookScript("OnMouseDown", function(self)
            BringPopupToFront(self)
        end)
    end

    if aliasCharacterPopup then return end

    aliasCharacterPopup = W.CreatePopupFrame("PRT_RosterAliasCharacterPopup", 360, 190, {
        title = "Add Character",
        bgColor = { 0, 0, 0, 1.0 },
    })
    aliasCharacterPopup:HookScript("OnShow", function(self)
        BringPopupToFront(self)
    end)
    aliasCharacterPopup:HookScript("OnMouseDown", function(self)
        BringPopupToFront(self)
    end)

    local nameLbl = W.CreateLabel(aliasCharacterPopup, "Character Name", PRT.FONT_SIZE, 1, 1, 1)
    nameLbl:SetPoint("TOPLEFT", 12, -34)
    local nameBox = W.CreateEditBox(aliasCharacterPopup, 156, 22, "Character name...")
    nameBox:SetPoint("TOPLEFT", 12, -52)
    aliasCharacterPopup.nameBox = nameBox

    local realmLbl = W.CreateLabel(aliasCharacterPopup, "Server", PRT.FONT_SIZE, 1, 1, 1)
    realmLbl:SetPoint("TOPLEFT", 186, -34)
    local realmBox = W.CreateEditBox(aliasCharacterPopup, 162, 22, PRT:GetHomeRealmName())
    realmBox:SetPoint("TOPLEFT", 186, -52)
    aliasCharacterPopup.realmBox = realmBox

    local classLbl = W.CreateLabel(aliasCharacterPopup, "Class", PRT.FONT_SIZE, 1, 1, 1)
    classLbl:SetPoint("TOPLEFT", 12, -84)
    local classItems = {
        {
            text = "Unknown",
            value = "",
            textColor = {
                PRT.C.GRAY[1], PRT.C.GRAY[2],
                PRT.C.GRAY[3], 1,
            },
        },
    }
    for _, classFile in ipairs(PRT:GetRosterMatcherClassOptions()) do
        local r, g, b = PRT:GetMatcherClassColor(classFile)
        classItems[#classItems + 1] = {
            text = PRT:GetMatcherClassLabel(classFile),
            value = classFile,
            textColor = { r, g, b, 1 },
        }
    end
    local classDD = W.CreateDropdown(
        aliasCharacterPopup, 156, classItems, nil, {
            hoverAnimation = "MRT",
        })
    classDD:SetPoint("TOPLEFT", 12, -102)
    classDD:SetSelected("", "Unknown")
    aliasCharacterPopup.classDD = classDD

    local saveBtn = W.CreateButton(aliasCharacterPopup, "Save", 160, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 12, 10)
    local cancelBtn = W.CreateButton(aliasCharacterPopup, "Cancel", 160, 24)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function() aliasCharacterPopup:Hide() end)

    saveBtn:SetScript("OnClick", function()
        local aliasId = aliasCharacterPopup._aliasId
        if not aliasId then
            aliasCharacterPopup:Hide()
            return
        end

        local character, err = PRT:AddCharacterToAlias(aliasId, {
            name = aliasCharacterPopup.nameBox:GetText(),
            realm = aliasCharacterPopup.realmBox:GetText(),
            classFile = aliasCharacterPopup.classDD:GetSelected(),
        })
        if not character then
            PRT.Print(err or "Unable to add character.")
            return
        end

        aliasCharacterPopup:Hide()
        if aliasPopup and aliasPopup:IsShown() then
            RequestAliasRefresh()
        end
        if matcherPopup and matcherPopup:IsShown() then
            RequestMatcherRefresh()
        end
    end)

    function aliasCharacterPopup:Open(aliasId, defaults)
        defaults = defaults or {}
        self._aliasId = aliasId
        self.nameBox:SetText(defaults.name or "")
        self.realmBox:SetText(defaults.realm or PRT:GetHomeRealmName())
        self.classDD:SetSelected(defaults.classFile or "", defaults.classFile and PRT:GetMatcherClassLabel(defaults.classFile) or "Unknown")
        BringPopupToFront(self)
        self:Show()
        self.nameBox:SetFocus()
    end
end

local function EnsureAliasMergePopup()
    if aliasMergePopup then return aliasMergePopup end

    aliasMergePopup = W.CreatePopupFrame(
        "PRT_RosterAliasMergePopup", 440, 320, {
            title = "Merge Alias",
            bgColor = { 0, 0, 0, 1.0 },
        })
    aliasMergePopup:HookScript("OnShow", function(self)
        BringPopupToFront(self)
    end)
    aliasMergePopup:HookScript("OnMouseDown", function(self)
        BringPopupToFront(self)
    end)

    local description = W.CreateDescription(aliasMergePopup, "", {
        width = 416,
    })
    description:SetPoint("TOPLEFT", 12, -34)
    aliasMergePopup.description = description

    local searchLabel =
        W.CreateLabel(aliasMergePopup, "Merge into", PRT.FONT_SIZE, 1, 1, 1)
    searchLabel:SetPoint("TOPLEFT", 12, -62)

    local searchBox = W.CreateEditBox(
        aliasMergePopup, 416, 24, "Type an alias name...")
    searchBox:SetPoint("TOPLEFT", 12, -80)
    searchBox:SetPoint("TOPRIGHT", -12, -80)
    aliasMergePopup.searchBox = searchBox

    local scroll = W.CreateScrollFrame(aliasMergePopup, 416, 150)
    scroll:SetPoint("TOPLEFT", 12, -114)
    scroll:SetPoint("BOTTOMRIGHT", -12, 48)
    aliasMergePopup.scroll = scroll
    aliasMergePopup.rows = {}

    local noResults = W.CreateDescription(
        scroll.content, "No matching aliases.", {
            width = 388,
            justifyH = "CENTER",
        })
    noResults:SetPoint("TOPLEFT", 8, -12)
    noResults:SetPoint("TOPRIGHT", -8, -12)
    aliasMergePopup.noResults = noResults

    local mergeBtn = W.CreateButton(aliasMergePopup, "Merge", 110, 24)
    mergeBtn:SetPoint("BOTTOMLEFT", 12, 12)
    W.SetControlEnabled(mergeBtn, false)
    aliasMergePopup.mergeBtn = mergeBtn

    local cancelBtn = W.CreateButton(aliasMergePopup, "Cancel", 110, 24)
    cancelBtn:SetPoint("LEFT", mergeBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function()
        aliasMergePopup:Hide()
    end)

    local function GetFilteredDestinations(popup)
        local query = PRT:NormalizeMatchText(popup.searchBox:GetText())
        local destinations = {}
        for _, alias in ipairs(PRT:GetRosterAliasList()) do
            if alias.id ~= popup._sourceAliasId then
                local labelNorm = PRT:NormalizeMatchText(alias.label)
                local matchAt = query == ""
                    and 1 or labelNorm:find(query, 1, true)
                if matchAt then
                    destinations[#destinations + 1] = {
                        alias = alias,
                        matchAt = matchAt,
                    }
                end
            end
        end

        table.sort(destinations, function(a, b)
            local aPrefix = a.matchAt == 1
            local bPrefix = b.matchAt == 1
            if aPrefix ~= bPrefix then
                return aPrefix
            end
            return string.lower(a.alias.label or "")
                < string.lower(b.alias.label or "")
        end)
        return destinations
    end

    function aliasMergePopup:RefreshResults()
        local source = PRT:GetAliasById(self._sourceAliasId)
        if not source then
            self:Hide()
            return
        end

        if self._destinationAliasId
            and not PRT:GetAliasById(self._destinationAliasId) then
            self._destinationAliasId = nil
        end

        local destinations = GetFilteredDestinations(self)
        self._visibleDestinationIds = {}

        for _, row in ipairs(self.rows) do
            row:Hide()
            row:SetSelected(false)
        end

        for index, entry in ipairs(destinations) do
            local alias = entry.alias
            local row = self.rows[index]
            if not row then
                row = W.CreateSelectableButton(self.scroll.content, "", {
                    height = 24,
                    bgColor = { 0.025, 0.025, 0.025, 1.0 },
                    hoverAnimation = "MRT",
                    labelPoint = { "LEFT", 8, 0 },
                    justifyH = "LEFT",
                })
                row.label:SetPoint("RIGHT", -8, 0)
                row:SetScript("OnClick", function(button)
                    local selected =
                        PRT:GetAliasById(button._aliasId)
                    if not selected then return end
                    aliasMergePopup._destinationAliasId =
                        selected.id
                    aliasMergePopup._settingSearch = true
                    aliasMergePopup.searchBox:SetText(
                        selected.label or "")
                    aliasMergePopup._settingSearch = false
                    aliasMergePopup:RefreshResults()
                end)
                self.rows[index] = row
            end

            local characterCount = #(alias.characters or {})
            local characterWord =
                characterCount == 1 and "character" or "characters"
            row.label:SetText((alias.label or "")
                .. "  (" .. tostring(characterCount)
                .. " " .. characterWord .. ")")
            row._aliasId = alias.id
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((index - 1) * 26))
            row:SetPoint("TOPRIGHT", 0, -((index - 1) * 26))
            row:SetSelected(
                self._destinationAliasId == alias.id)
            row:Show()
            self._visibleDestinationIds[index] = alias.id
        end

        self.noResults:SetShown(#destinations == 0)
        self.scroll:UpdateContentHeight(
            math.max(32, (#destinations * 26) + 2))
        W.SetControlEnabled(
            self.mergeBtn, self._destinationAliasId ~= nil)
    end

    function aliasMergePopup:OpenForAlias(sourceAliasId)
        local source = PRT:GetAliasById(sourceAliasId)
        if not source then
            PRT.Print("Alias not found.")
            return
        end
        if #PRT:GetRosterAliasList() < 2 then
            PRT.Print("Create another alias before merging.")
            return
        end

        self._sourceAliasId = source.id
        self._destinationAliasId = nil
        self.description:SetText(
            "Merge '" .. (source.label or "")
                .. "' into another alias. The selected alias name is retained.")
        self._settingSearch = true
        self.searchBox:SetText("")
        self._settingSearch = false
        self:RefreshResults()
        self:Show()
        PromotePopup(self, "TOOLTIP")
        self.searchBox:SetFocus()
    end

    searchBox:HookScript("OnTextChanged", function()
        if aliasMergePopup._settingSearch then return end
        aliasMergePopup._destinationAliasId = nil
        aliasMergePopup:RefreshResults()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        aliasMergePopup:Hide()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        local firstId =
            aliasMergePopup._visibleDestinationIds
                and aliasMergePopup._visibleDestinationIds[1]
        if firstId then
            local selected = PRT:GetAliasById(firstId)
            aliasMergePopup._destinationAliasId = firstId
            aliasMergePopup._settingSearch = true
            self:SetText(selected and selected.label or self:GetText())
            aliasMergePopup._settingSearch = false
            aliasMergePopup:RefreshResults()
        end
        self:ClearFocus()
    end)

    mergeBtn:SetScript("OnClick", function()
        local source =
            PRT:GetAliasById(aliasMergePopup._sourceAliasId)
        local destination =
            PRT:GetAliasById(aliasMergePopup._destinationAliasId)
        if not source or not destination then
            PRT.Print("Choose an alias to merge into.")
            return
        end

        OpenPopupOnTop(matcherConfirmPopup, {
            title = "Merge Aliases",
            message = "Merge '" .. (source.label or "")
                .. "' into '" .. (destination.label or "")
                .. "'? Characters will be combined and '"
                .. (source.label or "") .. "' will be removed.",
            confirmText = "Merge",
            onConfirm = function()
                local result, err = PRT:MergeRosterAliases(
                    source.id, destination.id)
                if not result then
                    PRT.Print(err or "Unable to merge aliases.")
                    return false
                end

                aliasMergePopup:Hide()
                RequestAliasRefresh()
                if matcherPopup and matcherPopup:IsShown() then
                    RequestMatcherRefresh()
                end

                local duplicateCount =
                    result.charactersSkippedDuplicate or 0
                PRT.Print("Merged '" .. (result.sourceLabel or "")
                    .. "' into '" .. (result.destinationLabel or "")
                    .. "': " .. tostring(result.charactersAdded or 0)
                    .. " added, " .. tostring(duplicateCount)
                    .. " duplicate"
                    .. (duplicateCount == 1 and "" or "s")
                    .. " combined.")
                return true
            end,
        })
    end)

    return aliasMergePopup
end

local function FormatAliasImportResult(result)
    local aliasParts = {
        tostring(result.aliasesCreated or 0) .. " created",
        tostring(result.aliasesMerged or 0) .. " merged",
    }
    if (result.aliasesRenamed or 0) > 0 then
        aliasParts[#aliasParts + 1] =
            tostring(result.aliasesRenamed) .. " renamed"
    end
    if (result.aliasesSkipped or 0) > 0 then
        aliasParts[#aliasParts + 1] =
            tostring(result.aliasesSkipped) .. " skipped"
    end

    local characterParts = {
        tostring(result.charactersAdded or 0) .. " added",
    }
    if (result.charactersSkippedDuplicate or 0) > 0 then
        characterParts[#characterParts + 1] =
            tostring(result.charactersSkippedDuplicate)
                .. " exact duplicates skipped"
    end
    if (result.charactersSkippedConflict or 0) > 0 then
        characterParts[#characterParts + 1] =
            tostring(result.charactersSkippedConflict)
                .. " shared-character copies skipped"
    end
    if (result.charactersSkippedAlias or 0) > 0 then
        characterParts[#characterParts + 1] =
            tostring(result.charactersSkippedAlias)
                .. " skipped with aliases"
    end

    return "Alias import complete: "
        .. table.concat(aliasParts, ", ")
        .. "; characters " .. table.concat(characterParts, ", ") .. "."
end

local function EnsureAliasTransferPopups()
    if aliasImportPopup then return end

    aliasImportPopup = W.CreateTextTransferPopup(
        "PRT_RosterAliasImportPopup", {
            width = 560,
            height = 330,
            title = "Import Alias Database",
            instruction =
                "Paste a PRT Alias Database export. Existing aliases are kept; conflict choices follow after validation.",
            actionText = "Continue",
            actionWidth = 90,
            showCancel = true,
            bgColor = { 0, 0, 0, 1.0 },
        })
    aliasExportPopup = W.CreateTextTransferPopup(
        "PRT_RosterAliasExportPopup", {
            width = 560,
            height = 330,
            title = "Export Alias Database",
            instruction =
                "Copy this text to transfer every alias and its realm-aware characters.",
            actionText = "Close",
            bgColor = { 0, 0, 0, 1.0 },
        })

    aliasImportOptionsPopup = W.CreatePopupFrame(
        "PRT_RosterAliasImportOptionsPopup", 560, 228, {
            title = "Alias Import Conflicts",
            bgColor = { 0, 0, 0, 1.0 },
        })

    local summary = W.CreateDescription(
        aliasImportOptionsPopup, "", {
            width = 536,
            color = { 0.9, 0.9, 0.9, 1 },
        })
    summary:SetPoint("TOPLEFT", 12, -34)
    summary:SetPoint("TOPRIGHT", -12, -34)
    aliasImportOptionsPopup.summary = summary

    local aliasStrategyLabel = W.CreateLabel(
        aliasImportOptionsPopup, "Duplicate alias names:",
        PRT.FONT_SIZE, 1, 1, 1)
    aliasStrategyLabel:SetPoint("TOPLEFT", 12, -94)
    local aliasStrategy = W.CreateDropdown(
        aliasImportOptionsPopup, 250, {
            { text = "Merge into existing alias", value = "merge" },
            { text = "Keep both (rename import)", value = "rename" },
            { text = "Skip imported alias", value = "skip" },
        })
    aliasStrategy:SetPoint("TOPLEFT", 294, -88)
    aliasImportOptionsPopup.aliasStrategy = aliasStrategy

    local characterStrategyLabel = W.CreateLabel(
        aliasImportOptionsPopup,
        "Character already in another alias:",
        PRT.FONT_SIZE, 1, 1, 1)
    characterStrategyLabel:SetPoint("TOPLEFT", 12, -130)
    local characterStrategy = W.CreateDropdown(
        aliasImportOptionsPopup, 250, {
            { text = "Keep in both aliases", value = "keep" },
            { text = "Skip imported copy", value = "skip" },
        })
    characterStrategy:SetPoint("TOPLEFT", 294, -124)
    aliasImportOptionsPopup.characterStrategy = characterStrategy

    local note = W.CreateDescription(
        aliasImportOptionsPopup,
        "Exact duplicates inside one alias are always skipped. Character conflicts use name and realm together.",
        { width = 536, color = { 0.7, 0.7, 0.7, 1 } })
    note:SetPoint("TOPLEFT", 12, -160)
    note:SetPoint("TOPRIGHT", -12, -160)

    local importBtn = W.CreateButton(
        aliasImportOptionsPopup, "Import", 100, 22)
    importBtn:SetPoint("BOTTOMLEFT", 12, 10)
    local cancelBtn = W.CreateButton(
        aliasImportOptionsPopup, "Cancel", 90, 22)
    cancelBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function()
        aliasImportOptionsPopup:Hide()
    end)

    function aliasImportOptionsPopup:OpenImport(importData, analysis)
        self._importData = importData
        self._analysis = analysis
        self.aliasStrategy:SetSelected(
            "merge", "Merge into existing alias")
        self.characterStrategy:SetSelected(
            "keep", "Keep in both aliases")

        local extra = {}
        if (analysis.duplicateAliasBlocks or 0) > 0 then
            extra[#extra + 1] =
                tostring(analysis.duplicateAliasBlocks)
                .. " repeated alias blocks merged"
        end
        if (analysis.duplicateCharacters or 0) > 0 then
            extra[#extra + 1] =
                tostring(analysis.duplicateCharacters)
                .. " within-alias duplicates collapsed"
        end
        local extraText = #extra > 0
            and (" " .. table.concat(extra, "; ") .. ".") or ""
        self.summary:SetText(
            ("Validated %d aliases and %d characters. "
                .. "%d alias-name conflicts and %d shared-character "
                .. "conflicts were found.%s"):format(
                analysis.aliases or 0,
                analysis.characters or 0,
                analysis.existingAliasConflicts or 0,
                analysis.crossAliasCharacterConflicts or 0,
                extraText))

        W.SetControlEnabled(
            aliasStrategyLabel,
            (analysis.existingAliasConflicts or 0) > 0)
        W.SetControlEnabled(
            self.aliasStrategy,
            (analysis.existingAliasConflicts or 0) > 0)
        W.SetControlEnabled(
            characterStrategyLabel,
            (analysis.crossAliasCharacterConflicts or 0) > 0)
        W.SetControlEnabled(
            self.characterStrategy,
            (analysis.crossAliasCharacterConflicts or 0) > 0)

        self:Show()
        PromotePopup(self, "TOOLTIP")
    end

    importBtn:SetScript("OnClick", function()
        local result, err = PRT:ImportRosterAliases(
            aliasImportOptionsPopup._importData, {
                aliasStrategy =
                    aliasImportOptionsPopup.aliasStrategy:GetSelected(),
                characterStrategy =
                    aliasImportOptionsPopup.characterStrategy:GetSelected(),
            })
        if not result then
            PRT.Print(err or "Unable to import aliases.")
            return
        end
        aliasImportOptionsPopup:Hide()
        PRT.Print(FormatAliasImportResult(result))
        RequestAliasRefresh()
        RequestMatcherRefresh()
    end)

    aliasImportPopup._processImport = function(text)
        local importData, err = PRT:ParseRosterAliasImport(text)
        if not importData then
            PRT.Print(err or "Unable to read alias import.")
            return false
        end
        local analysis, analysisErr =
            PRT:AnalyzeRosterAliasImport(importData)
        if not analysis then
            PRT.Print(analysisErr or "Unable to analyze alias import.")
            return false
        end
        aliasImportOptionsPopup:OpenImport(importData, analysis)
        return true
    end
    aliasExportPopup._closeExport = function()
        return true
    end
end

local function GetAliasFilterText()
    if not aliasPopup or not aliasPopup.searchBox then return "" end
    return PRT.Trim(aliasPopup.searchBox:GetText())
end

local function AliasMatchesQuery(alias, query)
    if query == "" then return true end

    local queryNorm = PRT:NormalizeMatchText(query)
    local queryRealm = string.lower(PRT.Trim(query))

    if alias._labelNorm and alias._labelNorm:find(queryNorm, 1, true) then
        return true
    end

    for _, character in ipairs(alias.characters or {}) do
        local classLabel = string.lower(PRT:GetMatcherClassLabel(character.classFile))
        if character.baseNorm and character.baseNorm:find(queryNorm, 1, true) then
            return true
        end
        if character.realm and string.lower(character.realm):find(queryRealm, 1, true) then
            return true
        end
        if classLabel:find(queryRealm, 1, true) then
            return true
        end
    end

    return false
end

local function EnsureAliasPopup()
    if aliasPopup then return aliasPopup end
    EnsureCommonPopups()
    EnsureAliasMergePopup()

    aliasPopup = W.CreatePopupFrame("PRT_RosterAliasPopup", ALIAS_WIDTH, ALIAS_HEIGHT, {
        title = "Alias Database",
        bgColor = { 0, 0, 0, 1.0 },
    })
    MakePopupInteractive(
        aliasPopup, ALIAS_MIN_WIDTH, ALIAS_MIN_HEIGHT)
    EnsureAliasTransferPopups()
    aliasPopup._refreshGuard = W.CreateDeferredRefreshGuard()

    local searchLbl = W.CreateLabel(aliasPopup, "Search", PRT.FONT_SIZE, 1, 1, 1)
    searchLbl:SetPoint("TOPLEFT", 12, -34)
    local searchBox = W.CreateEditBox(aliasPopup, ALIAS_WIDTH - 120, 24, "Search aliases or characters...")
    searchBox:SetPoint("TOPLEFT", 84, -30)
    searchBox:SetPoint("TOPRIGHT", -12, -30)
    aliasPopup.searchBox = searchBox

    local scroll = W.CreateScrollFrame(aliasPopup, 0, 0)
    scroll:SetPoint("TOPLEFT", 12, -74)
    scroll:SetPoint("BOTTOMRIGHT", -12, 44)
    aliasPopup.scroll = scroll
    aliasPopup.blocks = {}

    local exportAliasBtn =
        W.CreateButton(aliasPopup, "Export", 90, 24)
    exportAliasBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    local importAliasBtn =
        W.CreateButton(aliasPopup, "Import", 90, 24)
    importAliasBtn:SetPoint(
        "RIGHT", exportAliasBtn, "LEFT", -8, 0)
    local addAliasBtn =
        W.CreateButton(aliasPopup, "+ New Alias", 200, 24)
    addAliasBtn:SetPoint("BOTTOMLEFT", 12, 12)
    addAliasBtn:SetPoint(
        "BOTTOMRIGHT", importAliasBtn, "BOTTOMLEFT", -8, 0)
    addAliasBtn:SetScript("OnClick", function()
        OpenPopupOnTop(aliasNamePopup, {
            title = "New Alias",
            prompt = "Enter alias name:",
            acceptText = "Create",
            text = "",
            onAccept = function(text)
                local alias, err = PRT:CreateRosterAlias(text)
                if not alias then
                    PRT.Print(err or "Unable to create alias.")
                    return false
                end
                RequestAliasRefresh()
                RequestMatcherRefresh()
                return true
            end,
        })
    end)
    importAliasBtn:SetScript("OnClick", function()
        OpenPopupOnTop(aliasImportPopup, {
            text = "",
            highlight = false,
            onAction = aliasImportPopup._processImport,
        })
    end)
    exportAliasBtn:SetScript("OnClick", function()
        if #PRT:GetRosterAliasList() == 0 then
            PRT.Print("No aliases to export.")
            return
        end
        OpenPopupOnTop(aliasExportPopup, {
            text = PRT:ExportRosterAliases(),
            highlight = true,
            onAction = aliasExportPopup._closeExport,
        })
    end)

    searchBox:HookScript("OnTextChanged", function()
        RequestAliasRefresh()
    end)

    local function GetAliasBlock(index)
        local block = aliasPopup.blocks[index]
        if block then return block end

        block = CreateFrame("Frame", nil, aliasPopup.scroll.content)
        W.StyleBox(block, { 0.06, 0.06, 0.06, 1.0 }, PRT.C.BORDER)
        block.rows = {}

        local aliasLabel = W.CreateLabel(block, "Alias:", PRT.FONT_SIZE, 1, 1, 1)
        aliasLabel:SetPoint("TOPLEFT", 10, -10)

        local aliasEdit = W.CreateEditBox(block, 210, 22)
        aliasEdit:SetPoint("LEFT", aliasLabel, "RIGHT", 8, 0)
        block.aliasEdit = aliasEdit

        local deleteAliasBtn = W.CreateDeleteButton(block, nil, { width = 24, height = 20 })
        deleteAliasBtn:SetPoint("TOPRIGHT", -10, -8)
        block.deleteAliasBtn = deleteAliasBtn

        local mergeAliasBtn =
            W.CreateButton(block, "Merge...", 76, 20)
        mergeAliasBtn:SetPoint(
            "RIGHT", deleteAliasBtn, "LEFT", -8, 0)
        block.mergeAliasBtn = mergeAliasBtn

        local hdrName = W.CreateLabel(block, "Known Characters", PRT.FONT_SIZE, 1, 1, 1)
        hdrName:SetPoint("TOPLEFT", 18, -40)
        local hdrRealm = W.CreateLabel(block, "Server", PRT.FONT_SIZE, 1, 1, 1)
        hdrRealm:SetPoint("TOPLEFT", 260, -40)
        local hdrDelete = W.CreateLabel(block, "Delete", PRT.FONT_SIZE, 1, 1, 1)
        hdrDelete:SetPoint("TOPRIGHT", -26, -40)

        local addCharacterBtn = W.CreateButton(block, "+ Add Character", 180, 22)
        block.addCharacterBtn = addCharacterBtn

        aliasEdit:SetScript("OnEditFocusLost", function(self)
            local aliasId = self._aliasId
            if not aliasId then return end
            local original = self._originalLabel or ""
            local newLabel = PRT.Trim(self:GetText())
            if newLabel == "" then
                self:SetText(original)
                return
            end
            if newLabel == original then
                return
            end
            local ok, err = PRT:RenameRosterAlias(aliasId, newLabel)
            if not ok then
                PRT.Print(err or "Unable to rename alias.")
                self:SetText(original)
                return
            end
            self._originalLabel = newLabel
            RequestAliasRefresh()
            if matcherPopup and matcherPopup:IsShown() then
                RequestMatcherRefresh()
            end
        end)

        aliasEdit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        aliasPopup._refreshGuard:Track(aliasEdit)

        block.deleteAliasBtn:SetScript("OnClick", function(btn)
            local aliasId = btn._aliasId
            local alias = PRT:GetAliasById(aliasId)
            if not alias then return end
            OpenPopupOnTop(aliasDeleteConfirmPopup, {
                title = "Delete Alias",
                message = "Delete '" .. (alias.label or "")
                    .. "' and its characters?",
                confirmText = "Delete",
                onConfirm = function()
                    PRT:DeleteRosterAlias(aliasId)
                    RequestAliasRefresh()
                    if matcherPopup and matcherPopup:IsShown() then
                        RequestMatcherRefresh()
                    end
                end,
            })
        end)

        block.mergeAliasBtn:SetScript("OnClick", function(btn)
            aliasMergePopup:OpenForAlias(btn._aliasId)
        end)

        block.addCharacterBtn:SetScript("OnClick", function(btn)
            aliasCharacterPopup:Open(btn._aliasId)
        end)

        aliasPopup.blocks[index] = block
        return block
    end

    function aliasPopup:Refresh()
        local aliases = PRT:GetRosterAliasList()
        local query = GetAliasFilterText()
        local content = self.scroll.content
        local y = 0
        local visibleCount = 0

        for _, block in ipairs(self.blocks) do
            block:Hide()
            if block.rows then
                for _, row in ipairs(block.rows) do
                    row:Hide()
                end
            end
        end

        table.sort(aliases, function(a, b)
            return string.lower(a.label or "") < string.lower(b.label or "")
        end)

        for _, alias in ipairs(aliases) do
            if AliasMatchesQuery(alias, query) then
                visibleCount = visibleCount + 1
                local block = GetAliasBlock(visibleCount)
                block:ClearAllPoints()
                block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                block:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

                block.aliasEdit._aliasId = alias.id
                block.aliasEdit._originalLabel = alias.label
                block.aliasEdit:SetText(alias.label or "")
                block.deleteAliasBtn._aliasId = alias.id
                block.mergeAliasBtn._aliasId = alias.id
                block.addCharacterBtn._aliasId = alias.id

                for _, row in ipairs(block.rows) do
                    row:Hide()
                end

                local rowY = -62
                local rowHeight = 20
                for rowIndex, character in ipairs(alias.characters or {}) do
                    local row = block.rows[rowIndex]
                    if not row then
                        row = CreateFrame("Frame", nil, block)
                        row:SetHeight(rowHeight)
                        row.name = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
                        row.name:SetPoint("LEFT", 18, 0)
                        row.name:SetWidth(220)
                        row.name:SetJustifyH("LEFT")
                        row.realm = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
                        row.realm:SetPoint("LEFT", 260, 0)
                        row.realm:SetWidth(160)
                        row.realm:SetJustifyH("LEFT")
                        row.deleteBtn = W.CreateDeleteButton(row, nil, { width = 20, height = 18 })
                        row.deleteBtn:SetPoint("RIGHT", -12, 0)
                        block.rows[rowIndex] = row
                    end

                    row:SetPoint("TOPLEFT", block, "TOPLEFT", 0, rowY)
                    row:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, rowY)
                    SetAliasCharacterText(row.name, character.name or "", character.classFile)
                    row.realm:SetText(character.realm or "")
                    row.deleteBtn:SetScript("OnClick", function()
                        local displayName = PRT:MakeCharacterFullName(character.name, character.realm, true)
                        OpenPopupOnTop(aliasDeleteConfirmPopup, {
                            title = "Delete Character",
                            message = "Remove '" .. displayName
                                .. "' from '" .. (alias.label or "") .. "'?",
                            confirmText = "Delete",
                            onConfirm = function()
                                PRT:RemoveCharacterFromAlias(alias.id, displayName)
                                RequestAliasRefresh()
                                if matcherPopup and matcherPopup:IsShown() then
                                    RequestMatcherRefresh()
                                end
                            end,
                        })
                    end)
                    row:Show()
                    rowY = rowY - rowHeight
                end

                block.addCharacterBtn:ClearAllPoints()
                block.addCharacterBtn:SetPoint("TOPLEFT", 18, rowY - 4)
                local blockHeight = 96 + (#(alias.characters or {}) * rowHeight)
                block:SetHeight(blockHeight)
                block.addCharacterBtn:Show()
                block:Show()

                y = y + blockHeight + 10
            end
        end

        self.scroll:UpdateContentHeight(y + 4)
    end

    aliasPopup:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    return aliasPopup
end

local function EnsureMatcherPopup()
    if matcherPopup then return matcherPopup end
    EnsureCommonPopups()
    EnsureAliasPopup()

    matcherPopup = W.CreatePopupFrame("PRT_RosterMatcherPopup", MATCHER_WIDTH, MATCHER_HEIGHT, {
        title = "Auto Name Matcher",
    })
    MakePopupInteractive(matcherPopup, MATCHER_WIDTH, MATCHER_HEIGHT)
    matcherPopup._topRows = {}
    matcherPopup._lowerRows = {}
    matcherPopup._pillButtons = {}
    matcherPopup._state = { top = {}, lower = {} }
    matcherPopup._manualTargets = {}
    matcherPopup._refreshGuard = W.CreateDeferredRefreshGuard()

    local desc = W.CreateDescription(matcherPopup,
        "This tool finds likely name matches for unresolved roster names against the current live raid roster. You can then apply matches to your current raid group and optionally save characters into your alias database. You can utilize the database by saving multiple characters to the same alias to automatically match player alts. Leave the 'Save Character to Alias' field empty if you do not want to save the character as a new or known alias. For Uncertain / No Match Found you can drag players from the bottom to manually match them.",
        { width = MATCHER_WIDTH - 24 })
    desc:SetPoint("TOPLEFT", 12, -32)
    matcherPopup.desc = desc

    local scroll = W.CreateScrollFrame(matcherPopup, 0, 0)
    scroll:SetPoint("TOPLEFT", 12, -64)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    matcherPopup.scroll = scroll
    matcherPopup.content = scroll.content

    local ghost = W.CreateGhostLabelFrame(UIParent, {
        width = 160,
        height = 20,
        fontSize = PRT.FONT_SIZE,
        alpha = 0.95,
    })
    matcherPopup.dragGhost = ghost
    matcherPopup.drag = {
        active = false,
        liveIndex = nil,
        hoverSlotIndex = nil,
    }

    local function FindManualTargetAtCursor()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = x / scale, y / scale

        for slotIndex, target in pairs(matcherPopup._manualTargets) do
            if target and target:IsShown() then
                local left = target:GetLeft()
                local right = target:GetRight()
                local top = target:GetTop()
                local bottom = target:GetBottom()
                if left and right and top and bottom and cx >= left and cx <= right and cy >= bottom and cy <= top then
                    return slotIndex
                end
            end
        end
    end

    local function HighlightManualTarget(slotIndex, highlight)
        local target = matcherPopup._manualTargets[slotIndex]
        if not target or not target._bgTex then return end
        if highlight then
            target._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2], PRT.C.SIDEBAR_SEL[3], 0.35)
        else
            target._bgTex:SetColorTexture(PRT.C.INPUT_BG[1], PRT.C.INPUT_BG[2], PRT.C.INPUT_BG[3], PRT.C.INPUT_BG[4])
        end
    end

    local function FinishManualDrag()
        if not matcherPopup.drag.active then return end

        local slotIndex = matcherPopup.drag.hoverSlotIndex or FindManualTargetAtCursor()
        if matcherPopup.drag.hoverSlotIndex then
            HighlightManualTarget(matcherPopup.drag.hoverSlotIndex, false)
        end

        if slotIndex and matcherPopup._analysis then
            local liveWrapper
            for _, wrapper in ipairs(matcherPopup._analysis.unmatchedLive or {}) do
                if wrapper.liveIndex == matcherPopup.drag.liveIndex then
                    liveWrapper = wrapper
                    break
                end
            end

            if liveWrapper then
                for existingSlotIndex, slotState in pairs(matcherPopup._state.lower) do
                    if existingSlotIndex ~= slotIndex and slotState.manualLiveIndex == liveWrapper.liveIndex then
                        slotState.manualLiveIndex = nil
                    end
                end
                matcherPopup._state.lower[slotIndex] = matcherPopup._state.lower[slotIndex] or {}
                matcherPopup._state.lower[slotIndex].manualLiveIndex = liveWrapper.liveIndex
                RequestMatcherRefresh()
            end
        end

        matcherPopup.drag.active = false
        matcherPopup.drag.liveIndex = nil
        matcherPopup.drag.hoverSlotIndex = nil
        matcherPopup.dragGhost:Hide()
    end

    ghost:SetScript("OnUpdate", function()
        if not matcherPopup.drag.active then return end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

        local hovered = FindManualTargetAtCursor()
        if hovered ~= matcherPopup.drag.hoverSlotIndex then
            if matcherPopup.drag.hoverSlotIndex then
                HighlightManualTarget(matcherPopup.drag.hoverSlotIndex, false)
            end
            if hovered then
                HighlightManualTarget(hovered, true)
            end
            matcherPopup.drag.hoverSlotIndex = hovered
        end
    end)

    matcherPopup:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            FinishManualDrag()
        end
    end)

    matcherPopup._finishManualDrag = FinishManualDrag
    matcherPopup.ApplySelections = function(self)
        return MatcherApplySelections(self)
    end
    matcherPopup.Refresh = function(self)
        return MatcherRefresh(self)
    end
    matcherPopup:SetScript("OnShow", function(self)
        BringPopupToFront(self)
        MatcherRefresh(self)
        RequestMatcherRefresh()
    end)
    matcherPopup:HookScript("OnSizeChanged", function(self)
        if self:IsShown() then
            RequestMatcherRefresh()
        end
    end)
    return matcherPopup
end

local function GetOrCreateTopRow(index)
    local row = matcherPopup._topRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, matcherPopup.content)
    row:SetHeight(24)

    row.import = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.import:SetPoint("LEFT", 10, 0)
    row.import:SetWidth(150)
    row.import:SetJustifyH("LEFT")

    row.match = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.match:SetPoint("LEFT", 170, 0)
    row.match:SetWidth(190)
    row.match:SetJustifyH("LEFT")

    row.server = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.server:SetPoint("LEFT", 374, 0)
    row.server:SetWidth(110)
    row.server:SetJustifyH("LEFT")

    row.confidence = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.confidence:SetPoint("LEFT", 500, 0)
    row.confidence:SetWidth(120)
    row.confidence:SetJustifyH("LEFT")

    row.accept = CreateBareCheck(row)
    row.accept:SetPoint("LEFT", 648, 0)

    row.saveAlias = W.CreateEditBox(row, 154, 20, "Alias...")
    row.saveAlias:SetPoint("LEFT", 740, 0)
    matcherPopup._refreshGuard:Track(row.saveAlias)
    row.saveAlias:HookScript("OnTextChanged", function(self)
        if not row.slotIndex then return end
        matcherPopup._state.top[row.slotIndex] = matcherPopup._state.top[row.slotIndex] or {}
        matcherPopup._state.top[row.slotIndex].aliasText = self:GetText() or ""
    end)

    row.deleteBtn = W.CreateDeleteButton(row, nil, { width = 20, height = 18 })
    row.deleteBtn:SetPoint("LEFT", 912, 0)

    matcherPopup._topRows[index] = row
    return row
end

local function GetOrCreateLowerRow(index)
    local row = matcherPopup._lowerRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, matcherPopup.content)
    row:SetHeight(24)

    row.import = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.import:SetPoint("LEFT", 10, 0)
    row.import:SetWidth(140)
    row.import:SetJustifyH("LEFT")

    row.groupPos = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.groupPos:SetPoint("LEFT", 168, 0)
    row.groupPos:SetWidth(80)
    row.groupPos:SetJustifyH("LEFT")

    row.matchTarget = CreateFrame("Button", nil, row)
    row.matchTarget:SetSize(210, 20)
    row.matchTarget:SetPoint("LEFT", 262, 0)
    W.StyleBox(row.matchTarget, PRT.C.INPUT_BG, PRT.C.BORDER)
    row.matchTarget.label = W.CreateLabel(row.matchTarget, "", PRT.FONT_SIZE, 1, 1, 1)
    row.matchTarget.label:SetPoint("LEFT", 8, 0)
    row.matchTarget.label:SetPoint("RIGHT", -8, 0)
    row.matchTarget.label:SetJustifyH("LEFT")

    row.server = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.server:SetPoint("LEFT", 488, 0)
    row.server:SetWidth(110)
    row.server:SetJustifyH("LEFT")

    row.confidence = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
    row.confidence:SetPoint("LEFT", 612, 0)
    row.confidence:SetWidth(120)
    row.confidence:SetJustifyH("LEFT")

    row.saveAlias = W.CreateEditBox(row, 186, 20, "Alias...")
    row.saveAlias:SetPoint("LEFT", 806, 0)
    matcherPopup._refreshGuard:Track(row.saveAlias)
    row.saveAlias:HookScript("OnTextChanged", function(self)
        if not row.slotIndex then return end
        matcherPopup._state.lower[row.slotIndex] = matcherPopup._state.lower[row.slotIndex] or {}
        matcherPopup._state.lower[row.slotIndex].aliasText = self:GetText() or ""
    end)

    row.matchTarget:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            matcherPopup:_finishManualDrag()
        end
    end)
    row.matchTarget:SetScript("OnMouseDown", function()
        local slotState = matcherPopup._state.lower[row.slotIndex]
        if slotState and slotState.manualLiveIndex then
            slotState.manualLiveIndex = nil
            RequestMatcherRefresh()
        end
    end)

    matcherPopup._lowerRows[index] = row
    return row
end

local function GetOrCreatePillButton(index)
    local btn = matcherPopup._pillButtons[index]
    if btn then return btn end

    btn = W.CreateButton(matcherPopup.content, "", 110, 20, {
        bgColor = { 0.08, 0.08, 0.08, 0.95 },
        hoverBgColor = { 0.12, 0.12, 0.12, 1.0 },
    })
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        matcherPopup.drag.active = true
        matcherPopup.drag.liveIndex = self.liveIndex
        matcherPopup.drag.hoverSlotIndex = nil
        matcherPopup.dragGhost.label:SetText(self.displayName or "")
        matcherPopup.dragGhost:Show()
    end)
    btn:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            matcherPopup:_finishManualDrag()
        end
    end)

    matcherPopup._pillButtons[index] = btn
    return btn
end

local function EnsureMatcherHeaderWidgets()
    if matcherPopup._topHeader then return end

    local content = matcherPopup.content

    matcherPopup._topHeader = W.CreateHeader(content, "Possible Matches")
    matcherPopup._thresholdLabel = W.CreateLabel(content, "Confidence Threshold:", PRT.FONT_SIZE, 1, 1, 1)
    matcherPopup._thresholdValue = W.CreateLabel(content, "50%", PRT.FONT_SIZE, 1, 1, 1)
    matcherPopup._thresholdSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    local slider = matcherPopup._thresholdSlider
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(220)
    slider:SetHeight(16)
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end
    slider:SetFrameLevel(content:GetFrameLevel() + 2)
    matcherPopup._thresholdValue:SetDrawLayer("OVERLAY", 7)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        matcherPopup._thresholdValue:SetText(value .. "%")
        if not self._syncing then
            local db = PRT:GetRosterMatcherDB()
            db.threshold = value
            RequestMatcherRefresh()
        end
    end)

    matcherPopup._savedAliasesBtn = W.CreateButton(content, "Saved Aliases", 160, 24)
    matcherPopup._savedAliasesBtn:SetScript("OnClick", function()
        PRT:OpenRosterAliasPopup(matcherPopup._panel)
    end)
    matcherPopup._applyTopBtn = W.CreateButton(content, "Apply Matches", 160, 24)
    matcherPopup._applyTopBtn:SetScript("OnClick", function()
        matcherPopup:ApplySelections()
    end)

    matcherPopup._topColumns = {
        import = W.CreateLabel(content, "Import Name", PRT.FONT_SIZE, 1, 1, 1),
        match = W.CreateLabel(content, "Possible Match", PRT.FONT_SIZE, 1, 1, 1),
        server = W.CreateLabel(content, "Server", PRT.FONT_SIZE, 1, 1, 1),
        confidence = W.CreateLabel(content, "Match Confidence", PRT.FONT_SIZE, 1, 1, 1),
        accept = W.CreateLabel(content, "Accept Match", PRT.FONT_SIZE, 1, 1, 1),
        save = W.CreateLabel(content, "Save Character to Alias", PRT.FONT_SIZE, 1, 1, 1),
        deleteAlias = W.CreateLabel(content, "Delete Alias", PRT.FONT_SIZE, 1, 1, 1),
    }

    matcherPopup._acceptAllLabel = W.CreateLabel(content, "Accept All Matches", PRT.FONT_SIZE, 1, 1, 1)
    matcherPopup._acceptAll = CreateBareCheck(content)

    matcherPopup._acceptAll:SetScript("OnClick", function(self)
        local analysis = matcherPopup._analysis
        for _, match in ipairs(analysis and analysis.topMatches or {}) do
            matcherPopup._state.top[match.importEntry.slotIndex] = matcherPopup._state.top[match.importEntry.slotIndex] or {}
            matcherPopup._state.top[match.importEntry.slotIndex].accept = self:GetChecked()
        end
        RequestMatcherRefresh()
    end)

    matcherPopup._topDivider = content:CreateTexture(nil, "ARTWORK")
    matcherPopup._topDivider:SetHeight(1)
    matcherPopup._topDivider:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 1)

    matcherPopup._lowerHeader = W.CreateHeader(content, "Uncertain / No Match Found")
    matcherPopup._applyBottomBtn = W.CreateButton(content, "Apply Matches", 160, 24)
    matcherPopup._applyBottomBtn:SetScript("OnClick", function()
        matcherPopup:ApplySelections()
    end)
    matcherPopup._lowerDivider = content:CreateTexture(nil, "ARTWORK")
    matcherPopup._lowerDivider:SetHeight(1)
    matcherPopup._lowerDivider:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 1)
    matcherPopup._lowerColumns = {
        import = W.CreateLabel(content, "Import Name", PRT.FONT_SIZE, 1, 1, 1),
        groupPos = W.CreateLabel(content, "Group / Position", PRT.FONT_SIZE, 1, 1, 1),
        match = W.CreateLabel(content, "Match", PRT.FONT_SIZE, 1, 1, 1),
        server = W.CreateLabel(content, "Server", PRT.FONT_SIZE, 1, 1, 1),
        confidence = W.CreateLabel(content, "Match Confidence", PRT.FONT_SIZE, 1, 1, 1),
        save = W.CreateLabel(content, "Save Character to Alias", PRT.FONT_SIZE, 1, 1, 1),
    }
    matcherPopup._unmatchedHeader = W.CreateLabel(content, "Unmatched Characters", PRT.FONT_SIZE, 1, 1, 1)
end

local function RenderTopSection(startY)
    EnsureMatcherHeaderWidgets()
    local analysis = matcherPopup._analysis

    matcherPopup._topHeader:SetPoint("TOPLEFT", 6, startY)
    matcherPopup._thresholdLabel:SetPoint("TOPLEFT", 8, startY - 30)
    matcherPopup._thresholdSlider:SetPoint("TOPLEFT", 178, startY - 32)
    matcherPopup._thresholdValue:ClearAllPoints()
    matcherPopup._thresholdValue:SetPoint("LEFT", matcherPopup._thresholdSlider, "RIGHT", 16, 0)
    matcherPopup._thresholdSlider._syncing = true
    matcherPopup._thresholdSlider:SetValue(analysis.threshold or 50)
    matcherPopup._thresholdSlider._syncing = false
    matcherPopup._thresholdValue:SetText((analysis.threshold or 50) .. "%")
    matcherPopup._savedAliasesBtn:SetPoint("TOPLEFT", 520, startY - 32)
    matcherPopup._applyTopBtn:SetPoint("TOPLEFT", 696, startY - 32)

    matcherPopup._topDivider:SetPoint("TOPLEFT", 0, startY - 64)
    matcherPopup._topDivider:SetPoint("TOPRIGHT", 0, startY - 64)

    local cols = matcherPopup._topColumns
    cols.import:SetPoint("TOPLEFT", 10, startY - 84)
    cols.match:SetPoint("TOPLEFT", 170, startY - 84)
    cols.server:SetPoint("TOPLEFT", 374, startY - 84)
    cols.confidence:SetPoint("TOPLEFT", 500, startY - 84)
    cols.accept:SetPoint("TOPLEFT", 624, startY - 84)
    cols.save:SetPoint("TOPLEFT", 740, startY - 84)
    cols.deleteAlias:SetPoint("TOPLEFT", 908, startY - 84)

    for _, row in ipairs(matcherPopup._topRows) do
        row:Hide()
    end

    local rowY = startY - 108
    local anyAcceptOff = false

    for index, match in ipairs(analysis.topMatches or {}) do
        local row = GetOrCreateTopRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, rowY)
        row:SetPoint("TOPRIGHT", 0, rowY)
        row.slotIndex = match.importEntry.slotIndex

        row.import:SetText(match.importEntry.rawName)
        SetAliasCharacterText(row.match, match.liveEntry.name, match.liveEntry.classFile)
        row.server:SetText(match.liveEntry.realm or "")
        row.confidence:SetText(match.confidenceText)
        if match.knownAlias then
            row.confidence:SetTextColor(PRT.C.GREEN[1], PRT.C.GREEN[2], PRT.C.GREEN[3], 1)
        else
            row.confidence:SetTextColor(1, 1, 1, 1)
        end

        local state = matcherPopup._state.top[match.importEntry.slotIndex] or {}
        if state.accept == nil then state.accept = true end
        if state.aliasText == nil then state.aliasText = "" end
        matcherPopup._state.top[match.importEntry.slotIndex] = state

        row.accept:SetChecked(state.accept)
        row.accept:SetScript("OnClick", function(self)
            matcherPopup._state.top[match.importEntry.slotIndex].accept = self:GetChecked()
            RequestMatcherRefresh()
        end)

        if match.canSave then
            SetAliasInputState(row.saveAlias, true, state.aliasText or "")
        else
            SetAliasInputState(row.saveAlias, false, match.alias and match.alias.label or "")
        end

        if match.canDeleteAlias and match.alias then
            row.deleteBtn:Show()
            row.deleteBtn:SetScript("OnClick", function()
                OpenPopupOnTop(aliasDeleteConfirmPopup, {
                    title = "Delete Alias",
                    message = "Delete '" .. (match.alias.label or "")
                        .. "' and its characters?",
                    confirmText = "Delete",
                    onConfirm = function()
                        PRT:DeleteRosterAlias(match.alias.id)
                        RequestMatcherRefresh()
                        if aliasPopup and aliasPopup:IsShown() then
                            RequestAliasRefresh()
                        end
                    end,
                })
            end)
        else
            row.deleteBtn:Hide()
        end

        if not state.accept then anyAcceptOff = true end
        row:Show()
        rowY = rowY - 24
    end

    matcherPopup._acceptAllLabel:SetPoint("TOPLEFT", 624, rowY - 8)
    matcherPopup._acceptAllLabel:SetJustifyH("LEFT")
    matcherPopup._acceptAll:SetPoint("LEFT", matcherPopup._acceptAllLabel, "RIGHT", 8, 0)
    matcherPopup._acceptAll:SetChecked(not anyAcceptOff and #(analysis.topMatches or {}) > 0)

    return rowY - 40
end

local function RenderLowerSection(startY)
    EnsureMatcherHeaderWidgets()
    local analysis = matcherPopup._analysis

    matcherPopup._lowerHeader:SetPoint("TOPLEFT", 6, startY)
    matcherPopup._applyBottomBtn:SetPoint("TOPLEFT", 696, startY - 2)
    matcherPopup._lowerDivider:SetPoint("TOPLEFT", 0, startY - 30)
    matcherPopup._lowerDivider:SetPoint("TOPRIGHT", 0, startY - 30)

    local cols = matcherPopup._lowerColumns
    cols.import:SetPoint("TOPLEFT", 10, startY - 50)
    cols.groupPos:SetPoint("TOPLEFT", 168, startY - 50)
    cols.match:SetPoint("TOPLEFT", 262, startY - 50)
    cols.server:SetPoint("TOPLEFT", 488, startY - 50)
    cols.confidence:SetPoint("TOPLEFT", 612, startY - 50)
    cols.save:SetPoint("TOPLEFT", 806, startY - 50)

    for _, row in ipairs(matcherPopup._lowerRows) do
        row:Hide()
    end
    wipe(matcherPopup._manualTargets)

    local rowY = startY - 74
    local usedManualLive = {}
    for index, lowerRow in ipairs(analysis.lowerRows or {}) do
        local row = GetOrCreateLowerRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, rowY)
        row:SetPoint("TOPRIGHT", 0, rowY)
        row.slotIndex = lowerRow.importEntry.slotIndex
        matcherPopup._manualTargets[row.slotIndex] = row.matchTarget

        row.import:SetText(lowerRow.importEntry.rawName)
        row.groupPos:SetText(lowerRow.importEntry.groupPos)

        local state = matcherPopup._state.lower[row.slotIndex] or {}
        matcherPopup._state.lower[row.slotIndex] = state

        local manualLive
        if state.manualLiveIndex then
            if usedManualLive[state.manualLiveIndex] then
                state.manualLiveIndex = nil
            else
                usedManualLive[state.manualLiveIndex] = true
            end
        end

        if state.manualLiveIndex then
            for _, wrapper in ipairs(analysis.unmatchedLive or {}) do
                if wrapper.liveIndex == state.manualLiveIndex then
                    manualLive = wrapper.liveEntry
                    break
                end
            end
            if not manualLive then
                state.manualLiveIndex = nil
            end
        end

        if state.aliasText == nil then
            state.aliasText = ""
        end

        if manualLive then
            SetAliasCharacterText(row.matchTarget.label, manualLive.name, manualLive.classFile)
            row.server:SetText(manualLive.realm or "")
            row.confidence:SetText("Manual")
            row.confidence:SetTextColor(PRT.C.GREEN[1], PRT.C.GREEN[2], PRT.C.GREEN[3], 1)
            SetAliasInputState(row.saveAlias, true, state.aliasText or "")
        elseif lowerRow.suggestion then
            SetAliasCharacterText(row.matchTarget.label, lowerRow.suggestion.liveEntry.name, lowerRow.suggestion.liveEntry.classFile)
            row.server:SetText(lowerRow.suggestion.liveEntry.realm or "")
            row.confidence:SetText(lowerRow.suggestion.confidenceText)
            if lowerRow.suggestion.knownAlias then
                row.confidence:SetTextColor(PRT.C.GREEN[1], PRT.C.GREEN[2], PRT.C.GREEN[3], 1)
            else
                row.confidence:SetTextColor(PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3], 1)
            end
            SetAliasInputState(row.saveAlias, false, "")
        else
            row.matchTarget.label:SetText("No match")
            row.matchTarget.label:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3], 1)
            row.server:SetText("-")
            row.confidence:SetText("0%")
            row.confidence:SetTextColor(PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3], 1)
            SetAliasInputState(row.saveAlias, false, "")
        end

        row:Show()
        rowY = rowY - 24
    end

    matcherPopup._unmatchedHeader:SetPoint("TOPLEFT", 10, rowY - 12)

    for _, btn in ipairs(matcherPopup._pillButtons) do
        btn:Hide()
    end

    local pillX = 10
    local pillY = rowY - 34
    local pillRowHeight = 24
    local maxWidth = MATCHER_WIDTH - 76

    for index, wrapper in ipairs(analysis.unmatchedLive or {}) do
        if not usedManualLive[wrapper.liveIndex] then
            local btn = GetOrCreatePillButton(index)
            btn.liveIndex = wrapper.liveIndex
            btn.displayName = wrapper.liveEntry.displayName
            btn:SetLabel(wrapper.liveEntry.displayName)
            local r, g, b = PRT:GetMatcherClassColor(wrapper.liveEntry.classFile)
            btn.label:SetTextColor(r, g, b, 1)

            local btnWidth = math.max(96, math.floor(btn.label:GetStringWidth() + 20))
            btn:SetWidth(btnWidth)
            if pillX + btnWidth > maxWidth then
                pillX = 10
                pillY = pillY - pillRowHeight
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", pillX, pillY)
            btn:Show()
            pillX = pillX + btnWidth + 6
        end
    end

    return pillY - pillRowHeight - 8
end

MatcherApplySelections = function(self)
    local analysis = self._analysis
    if not analysis or not analysis.compName then
        PRT.Print("No composition selected.")
        return
    end

    local actions = {}
    for _, match in ipairs(analysis.topMatches or {}) do
        local state = self._state.top[match.importEntry.slotIndex]
        if state and state.accept then
            local aliasLabel = PRT.Trim(state.aliasText or "")
            actions[#actions + 1] = {
                slotIndex = match.importEntry.slotIndex,
                importName = match.importEntry.rawName,
                liveEntry = match.liveEntry,
                aliasLabel = match.canSave and aliasLabel or "",
            }
        end
    end

    for _, lowerRow in ipairs(analysis.lowerRows or {}) do
        local state = self._state.lower[lowerRow.importEntry.slotIndex]
        if state and state.manualLiveIndex then
            local liveEntry
            for _, wrapper in ipairs(analysis.unmatchedLive or {}) do
                if wrapper.liveIndex == state.manualLiveIndex then
                    liveEntry = wrapper.liveEntry
                    break
                end
            end
            if liveEntry then
                local aliasLabel = PRT.Trim(state.aliasText or "")
                actions[#actions + 1] = {
                    slotIndex = lowerRow.importEntry.slotIndex,
                    importName = lowerRow.importEntry.rawName,
                    liveEntry = liveEntry,
                    aliasLabel = aliasLabel,
                }
            end
        end
    end

    local ok, result = PRT:ApplyRosterMatchActions(analysis.compName, actions)
    if not ok then
        PRT.Print(result or "No matches selected.")
        return
    end

    PRT.Print("Applied " .. tostring(result) .. " roster match" .. (result == 1 and "" or "es") .. ".")
    RefreshGroupsPanel(self._panel, analysis.compName)
    RequestMatcherRefresh()
    if aliasPopup and aliasPopup:IsShown() then
        RequestAliasRefresh()
    end
end

MatcherRefresh = function(self)
    if not self._panel or not self._panel.selectedComp then
        return
    end

    local analysis = PRT:BuildRosterMatchAnalysis(self._panel.selectedComp, nil, GetPanelRosterSnapshot(self._panel))
    if not analysis then
        return
    end
    self._analysis = analysis

    local startY = -6
    local nextY = RenderTopSection(startY)
    local endY = RenderLowerSection(nextY - 8)
    self.scroll:UpdateContentHeight(-endY + 20)
end

function PRT:OpenRosterAliasPopup(panel)
    EnsureAliasPopup()
    aliasPopup._panel = panel
    BringPopupToFront(aliasPopup)
    aliasPopup:Show()
    RequestAliasRefresh()
end

function PRT:OpenRosterMatcher(panel)
    if not panel or not panel.selectedComp then
        PRT.Print("Select a raid group composition first.")
        return
    end

    EnsureMatcherPopup()
    matcherPopup._panel = panel
    BringPopupToFront(matcherPopup)
    matcherPopup:Show()
    MatcherRefresh(matcherPopup)
    C_Timer.After(0, function()
        RequestMatcherRefresh()
    end)
    C_Timer.After(0.05, function()
        RequestMatcherRefresh()
    end)
end

function PRT:RefreshRosterAliasPopup()
    RequestAliasRefresh()
end

function PRT:RefreshRosterMatcherPopup()
    RequestMatcherRefresh()
end
