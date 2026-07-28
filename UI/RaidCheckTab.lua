---------------------------------------------------------------------------
-- PugzRaidTools - Raid Check Configuration Tab
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local function Divider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", 0, y)
    line:SetHeight(1)
    line:SetColorTexture(
        PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.55)
    return line
end

local function ActionButton(parent, text, x, y, callback, width)
    local button = W.CreateButton(parent, text, width or 150, 24)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end

local function SetButtonEnabled(button, enabled)
    W.SetControlEnabled(button, enabled)
    button:SetAlpha(enabled and 1 or 0.35)
end

local function ColumnReportButton(
        parent, localText, reportText, y, checkType)
    ActionButton(parent, localText, 2, y, function()
        PRT:RunRaidCheckReport(checkType, false)
    end)
    ActionButton(parent, reportText, 160, y, function()
        PRT:RunRaidCheckReport(checkType, true)
    end)
end

function PRT:BuildRaidCheckTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    local scroller = W.CreateScrollFrame(panel, 0, 0)
    scroller:SetPoint("TOPLEFT", 10, -8)
    scroller:SetPoint("BOTTOMRIGHT", -10, 8)
    local content = scroller.content

    local title = W.CreateHeader(content, "Raid Check")
    title:SetPoint("TOPLEFT", 2, 0)

    local description = W.CreateDescription(content,
        "Run a compact live raid-preparation check with /prt check or /rt check. Player always remains first; configure every other column below.", {
            color = { 0.75, 0.75, 0.75 },
        })
    description:SetPoint("TOPLEFT", 2, -27)
    description:SetPoint("TOPRIGHT", -8, -27)

    Divider(content, -69)

    local actionsHeader = W.CreateHeader(content, "Quick Actions")
    actionsHeader:SetPoint("TOPLEFT", 2, -82)

    ActionButton(content, "Open Raid Check", 2, -108, function()
        PRT:ShowRaidCheckWindow({ source = "tab" })
    end)
    ActionButton(content, "Test Preview", 160, -108, function()
        PRT:ShowRaidCheckTestPreview()
    end)
    ActionButton(content, "Refresh Results", 318, -108, function()
        PRT:ShowRaidCheckWindow({ source = "tab" })
        PRT:RequestRaidCheckDurability()
        PRT:RefreshRaidCheckWindow()
    end)
    ActionButton(content, "Report Missing", 476, -108, function()
        PRT:RunRaidCheckReport("all", true)
    end)

    local checksHeader = W.CreateHeader(content, "Checks and Reports")
    checksHeader:SetPoint("TOPLEFT", 2, -151)

    local chatCommands = W.CreateButton(
        content, "Chat Commands ?", 140, 22)
    chatCommands:SetPoint("TOPRIGHT", -8, -146)
    chatCommands:SetScript("OnClick", function()
        PRT:PrintRaidCheckChatCommands()
    end)
    W.AttachTooltip(chatCommands, {
        anchor = "ANCHOR_LEFT",
        minWidth = 650,
        title = "Raid Check Chat Commands",
        titleColor = {
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1,
        },
        lines = PRT:GetRaidCheckChatCommandTooltipLines(),
    })

    local checksDescription = W.CreateDescription(content,
        "Buttons run reports. Example: type !flask in raid chat for a live missing-flask reply.", {
            color = { 0.7, 0.7, 0.7 },
        })
    checksDescription:SetPoint("TOPLEFT", 2, -174)
    checksDescription:SetPoint("TOPRIGHT", -8, -174)

    ColumnReportButton(
        content, "Check World Buffs", "Report World Buffs", -202,
        "worldBuffs")
    ActionButton(content, "Check Food", 318, -202, function()
        PRT:RunRaidCheckReport("food", false)
    end)
    ActionButton(content, "Report Food", 476, -202, function()
        PRT:RunRaidCheckReport("food", true)
    end)

    ColumnReportButton(
        content, "Check Flask", "Report Flask", -232, "flask")
    ActionButton(content, "Check Zanza", 318, -232, function()
        PRT:RunRaidCheckReport("zanza", false)
    end)
    ActionButton(content, "Report Zanza", 476, -232, function()
        PRT:RunRaidCheckReport("zanza", true)
    end)

    ColumnReportButton(
        content, "Check Consumes", "Report Consumes", -262, "consumes")
    ActionButton(content, "Check Potions", 318, -262, function()
        PRT:RunRaidCheckReport("potions", false)
    end)
    ActionButton(content, "Report Potions", 476, -262, function()
        PRT:RunRaidCheckReport("potions", true)
    end)

    ColumnReportButton(
        content, "Check Raid Buffs", "Report Raid Buffs", -292, "buffs")
    ActionButton(content, "Check Disallowed", 318, -292, function()
        PRT:RunRaidCheckReport("disallowed", false)
    end)
    ActionButton(content, "Report Disallowed", 476, -292, function()
        PRT:RunRaidCheckReport("disallowed", true)
    end)

    Divider(content, -332)

    local readyHeader = W.CreateHeader(content, "Ready Check")
    readyHeader:SetPoint("TOPLEFT", 2, -345)

    local showOnReady = W.CreateCheckbox(content,
        "Show automatically when a ready check starts",
        function(checked)
            PRT:GetDB().raidCheck.showOnReadyCheck =
                checked and true or false
        end)
    showOnReady:SetWidth(380)
    showOnReady:SetPoint("TOPLEFT", 2, -372)

    local leadersOnly = W.CreateCheckbox(content,
        "Only show automatically for raid leaders and assistants",
        function(checked)
            PRT:GetDB().raidCheck.onlyLeaderAssist =
                checked and true or false
        end)
    leadersOnly:SetWidth(430)
    leadersOnly:SetPoint("TOPLEFT", 2, -400)

    local autoClose = W.CreateCheckbox(content,
        "Fade automatically when the ready check finishes",
        function(checked)
            PRT:GetDB().raidCheck.autoClose = checked and true or false
            panel:Refresh()
        end)
    autoClose:SetWidth(430)
    autoClose:SetPoint("TOPLEFT", 2, -428)

    local closeDelay = W.CreateExactSlider(content,
        "Hold Before Fade (seconds)", 0, 20, 1, 210,
        function(value)
            PRT:GetDB().raidCheck.closeDelay = value
        end, 0)
    closeDelay:SetPoint("TOPLEFT", 27, -458)

    local collapsed = W.CreateCheckbox(content,
        "Use collapsed ready-status view",
        function(checked)
            PRT:SetRaidCheckCollapsed(checked)
        end)
    collapsed:SetWidth(300)
    collapsed:SetPoint("TOPLEFT", 315, -462)

    Divider(content, -508)

    local layoutHeader = W.CreateHeader(content, "Layout")
    layoutHeader:SetPoint("TOPLEFT", 2, -521)

    local sortLabel = W.CreateLabel(content, "Sort players by:",
        PRT.FONT_SIZE, PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    sortLabel:SetPoint("TOPLEFT", 2, -550)

    local sortMode = W.CreateDropdown(content, 190, {
        { text = "Raid group", value = "group" },
        { text = "Player name", value = "name" },
        { text = "Class, then name", value = "class" },
        { text = "Class, then group", value = "classGroup" },
    }, function(value)
        PRT:GetDB().raidCheck.sortMode = value
        if PRT.raidCheckWindow
            and PRT.raidCheckWindow._previewSnapshot then
            PRT.raidCheckWindow._previewSnapshot =
                PRT:BuildRaidCheckTestSnapshot()
        end
        PRT:RefreshRaidCheckWindow()
    end)
    sortMode:SetPoint("TOPLEFT", 2, -568)

    local scale = W.CreateExactSlider(content,
        "Window Scale", 0.5, 1.5, 0.05, 210,
        function(value)
            PRT:GetDB().raidCheck.scale = value
            PRT:ApplyRaidCheckWindowSettings()
        end, 2)
    scale:SetPoint("TOPLEFT", 235, -550)

    local strataLabel = W.CreateLabel(content, "Frame strata:",
        PRT.FONT_SIZE, PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    strataLabel:SetPoint("TOPLEFT", 485, -550)

    local frameStrata = W.CreateDropdown(content, 160, {
        {
            text = "Fullscreen dialog (default)",
            value = "FULLSCREEN_DIALOG",
        },
        { text = "Tooltip (highest)", value = "TOOLTIP" },
        { text = "Fullscreen", value = "FULLSCREEN" },
        { text = "Dialog", value = "DIALOG" },
        { text = "High", value = "HIGH" },
        { text = "Medium", value = "MEDIUM" },
        { text = "Low", value = "LOW" },
        { text = "Background", value = "BACKGROUND" },
    }, function(value)
        PRT:GetDB().raidCheck.frameStrata = value
        PRT:ApplyRaidCheckWindowSettings()
    end)
    frameStrata:SetPoint("TOPLEFT", 485, -568)

    local resetPosition = W.CreateButton(
        content, "Reset Window Position", 160, 24)
    resetPosition:SetPoint("TOPLEFT", 485, -600)
    resetPosition:SetScript("OnClick", function()
        PRT:ResetRaidCheckWindowPosition()
        PRT.Print("Raid Check window position reset.")
    end)

    local allianceBlessingsOnly = W.CreateCheckbox(content,
        "Only show Paladin Blessing columns when you are Alliance",
        function(checked)
            PRT:GetDB().raidCheck.allianceBlessingsOnly =
                checked and true or false
            PRT:RefreshRaidCheckWindow()
        end)
    allianceBlessingsOnly:SetWidth(460)
    allianceBlessingsOnly:SetPoint("TOPLEFT", 2, -604)

    local dismissOnRightClick = W.CreateCheckbox(content,
        "Right-click the Raid Check window to dismiss it",
        function(checked)
            PRT:GetDB().raidCheck.dismissOnRightClick =
                checked and true or false
        end)
    dismissOnRightClick:SetWidth(430)
    dismissOnRightClick:SetPoint("TOPLEFT", 2, -632)

    Divider(content, -663)

    local orderHeader = W.CreateHeader(content, "Column Order")
    orderHeader:SetPoint("TOPLEFT", 2, -676)

    local orderDescription = W.CreateDescription(content,
        "Player is fixed first. Each row controls visibility, alignment, category options, and ordering. Disabled columns retain their saved position.", {
            color = { 0.7, 0.7, 0.7 },
        })
    orderDescription:SetPoint("TOPLEFT", 2, -701)
    orderDescription:SetPoint("TOPRIGHT", -8, -701)

    local playerRow = W.CreateRowFrame(content, 24)
    playerRow:SetPoint("TOPLEFT", 2, -735)
    playerRow:SetPoint("TOPRIGHT", -8, -735)
    W.AddBackground(playerRow, 0.055, 0.055, 0.055, 0.72)
    local playerLabel = W.CreateLabel(playerRow, "Player", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    playerLabel:SetPoint("LEFT", 8, 0)
    local fixedLabel = W.CreateLabel(
        playerRow, "Always shown first", math.max(8, PRT.FONT_SIZE - 2),
        0.58, 0.58, 0.58)
    fixedLabel:SetPoint("RIGHT", -8, 0)

    local catalog = PRT:GetRaidCheckColumnCatalog()
    local orderRows = {}
    local iconCountItems = {}
    local worldBuffIconCountItems = {}
    local alignmentItems = {
        { text = "Left", value = "LEFT" },
        { text = "Centre", value = "CENTER" },
        { text = "Right", value = "RIGHT" },
    }
    for value = 1, 6 do
        iconCountItems[#iconCountItems + 1] = {
            text = tostring(value),
            value = value,
        }
    end
    for value = 1, 7 do
        worldBuffIconCountItems[#worldBuffIconCountItems + 1] = {
            text = tostring(value),
            value = value,
        }
    end

    local orderRowTop = 761
    local orderRowStep = 26
    for index = 1, #catalog do
        local row = W.CreateRowFrame(content, 24)
        row:SetPoint(
            "TOPLEFT", 2, -(orderRowTop + (index - 1) * orderRowStep))
        row:SetPoint(
            "TOPRIGHT", -8, -(orderRowTop + (index - 1) * orderRowStep))
        W.AddBackground(
            row,
            index % 2 == 0 and 0.05 or 0.035,
            index % 2 == 0 and 0.05 or 0.035,
            index % 2 == 0 and 0.05 or 0.035,
            0.72)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 7, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.label = W.CreateLabel(row, "", PRT.FONT_SIZE, 0.9, 0.9, 0.9)
        row.label:SetPoint("LEFT", 30, 0)
        row.label:SetWidth(138)
        row.label:SetJustifyH("LEFT")

        row.enabled = W.CreateCheckbox(row, "Show", function(checked)
            if row.columnKey then
                PRT:SetRaidCheckColumnEnabled(row.columnKey, checked)
            end
        end)
        row.enabled:SetSize(68, 20)
        row.enabled:SetPoint("LEFT", 172, 0)

        row.alignmentLabel = W.CreateLabel(
            row, "Align", math.max(8, PRT.FONT_SIZE - 2),
            0.72, 0.72, 0.72)
        row.alignmentLabel:SetPoint("LEFT", 244, 0)

        row.alignment = W.CreateDropdown(
            row, 80, alignmentItems, function(value)
                if row.columnKey then
                    PRT:SetRaidCheckColumnAlignment(row.columnKey, value)
                end
            end)
        row.alignment:SetPoint("LEFT", 279, 0)

        row.count = W.CreateCheckbox(row, "Count", function(checked)
            if row.columnKey then
                PRT:SetRaidCheckColumnShowCount(row.columnKey, checked)
            end
        end)
        row.count:SetSize(72, 20)
        row.count:SetPoint("LEFT", 365, 0)

        row.iconsLabel = W.CreateLabel(
            row, "Icons", math.max(8, PRT.FONT_SIZE - 2),
            0.72, 0.72, 0.72)
        row.iconsLabel:SetPoint("LEFT", 442, 0)

        row.maxIcons = W.CreateDropdown(
            row, 54, iconCountItems, function(value)
                if row.columnKey then
                    PRT:SetRaidCheckColumnMaxDisplay(
                        row.columnKey, value)
                end
            end)
        row.maxIcons:SetPoint("LEFT", 478, 0)

        row.detectedOnly = W.CreateCheckbox(
            row, "Show if detected", function(checked)
                if row.columnKey then
                    PRT:SetRaidCheckColumnVisibility(
                        row.columnKey,
                        checked and "detected" or "always")
                end
            end)
        row.detectedOnly:SetSize(128, 20)
        row.detectedOnly:SetPoint("LEFT", 440, 0)

        row.up = W.CreateButton(row, "Up", 52, 20)
        row.up:SetPoint("RIGHT", -60, 0)
        row.up:SetScript("OnClick", function()
            if row.columnKey
                and PRT:MoveRaidCheckColumn(row.columnKey, -1) then
                panel:Refresh()
            end
        end)

        row.down = W.CreateButton(row, "Down", 54, 20)
        row.down:SetPoint("RIGHT", -3, 0)
        row.down:SetScript("OnClick", function()
            if row.columnKey
                and PRT:MoveRaidCheckColumn(row.columnKey, 1) then
                panel:Refresh()
            end
        end)
        orderRows[index] = row
    end

    local worldDividerY =
        -(orderRowTop + #catalog * orderRowStep + 4)
    Divider(content, worldDividerY)

    local worldHeaderY = worldDividerY - 13
    local worldHeader = W.CreateHeader(content, "World Buff Validity")
    worldHeader:SetPoint("TOPLEFT", 2, worldHeaderY)

    local worldDescription = W.CreateDescription(content,
        "Choose which detected world buffs contribute to the valid count for each class. The display setting controls how other detected buffs appear in the Raid Check.", {
            color = { 0.7, 0.7, 0.7 },
        })
    worldDescription:SetPoint("TOPLEFT", 2, worldHeaderY - 25)
    worldDescription:SetPoint("TOPRIGHT", -8, worldHeaderY - 25)

    local classLabel = W.CreateLabel(
        content, "Configure class:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    classLabel:SetPoint("TOPLEFT", 2, worldHeaderY - 64)

    local worldClassItems = {}
    for _, classInfo in ipairs(PRT:GetRaidCheckWorldBuffClasses()) do
        worldClassItems[#worldClassItems + 1] = {
            text = classInfo.label,
            value = classInfo.classFile,
        }
    end

    local playerClassFile
    if UnitClass then
        local _
        _, playerClassFile = UnitClass("player")
    end
    local selectedWorldBuffClass = playerClassFile or "WARRIOR"
    local worldClass
    worldClass = W.CreateDropdown(
        content, 170, worldClassItems, function(value)
            selectedWorldBuffClass = value
            panel:RefreshWorldBuffs()
        end)
    worldClass:SetPoint("TOPLEFT", 2, worldHeaderY - 82)

    local resetWorldBuffs = W.CreateButton(
        content, "Restore Class Defaults", 170, 24)
    resetWorldBuffs:SetPoint("TOPLEFT", 184, worldHeaderY - 82)
    resetWorldBuffs:SetScript("OnClick", function()
        PRT:ResetRaidCheckWorldBuffDefaults(selectedWorldBuffClass)
        panel:RefreshWorldBuffs()
    end)

    local uncountedLabel = W.CreateLabel(
        content, "Uncounted detected buffs:", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    uncountedLabel:SetPoint("TOPLEFT", 380, worldHeaderY - 64)

    local uncountedMode = W.CreateDropdown(content, 170, {
        {
            text = "Show",
            value = "show",
        },
        {
            text = "Fade",
            value = "fade",
        },
        {
            text = "Hide",
            value = "hide",
        },
    }, function(value)
        PRT:SetRaidCheckWorldBuffUncountedMode(value)
    end)
    uncountedMode:SetPoint("TOPLEFT", 380, worldHeaderY - 82)

    local worldBuffDefinitions = PRT:GetRaidCheckWorldBuffDefinitions()
    local worldBuffChecks = {}
    local worldChecksY = worldHeaderY - 120
    for index, definition in ipairs(worldBuffDefinitions) do
        local spellId = definition.spellId
        local column = index <= math.ceil(#worldBuffDefinitions / 2)
            and 0 or 1
        local rowIndex = column == 0
            and index - 1
            or index - math.ceil(#worldBuffDefinitions / 2) - 1
        local checkbox = W.CreateCheckbox(
            content,
            ("%s (%d)"):format(definition.name, definition.spellId),
            function(checked)
                PRT:SetRaidCheckWorldBuffCounted(
                    selectedWorldBuffClass,
                    spellId,
                    checked)
            end)
        checkbox:SetWidth(335)
        checkbox:SetPoint(
            "TOPLEFT",
            2 + column * 350,
            worldChecksY - rowIndex * 26)
        worldBuffChecks[index] = checkbox
    end

    local worldRows = math.ceil(#worldBuffDefinitions / 2)
    local noteY = worldChecksY - worldRows * 26 - 18
    local note = W.CreateDescription(content,
        "Raid Report activity history, including world buffs, unbooning, rebooning, and consumable activity, remains a separate follow-up subsystem.", {
            color = { 0.68, 0.68, 0.68 },
        })
    note:SetPoint("TOPLEFT", 2, noteY)
    note:SetPoint("TOPRIGHT", -8, noteY)

    scroller:UpdateContentHeight(math.abs(noteY) + 62)

    function panel:RefreshWorldBuffs()
        worldClass:SetSelected(selectedWorldBuffClass)
        local worldBuffSetting =
            PRT:GetRaidCheckColumnSetting("worldBuffs")
        uncountedMode:SetSelected(
            worldBuffSetting and worldBuffSetting.uncountedMode or "fade")
        for index, definition in ipairs(worldBuffDefinitions) do
            worldBuffChecks[index]:SetChecked(
                PRT:IsRaidCheckWorldBuffCounted(
                    selectedWorldBuffClass,
                    definition.spellId))
        end
    end

    function panel:Refresh()
        local cfg = PRT:GetDB().raidCheck
        showOnReady:SetChecked(cfg.showOnReadyCheck ~= false)
        leadersOnly:SetChecked(cfg.onlyLeaderAssist == true)
        autoClose:SetChecked(cfg.autoClose ~= false)
        closeDelay:SetExactValue(tonumber(cfg.closeDelay) or 5)
        W.SetControlEnabled(closeDelay, cfg.autoClose ~= false)
        collapsed:SetChecked(cfg.collapsed == true)
        sortMode:SetSelected(cfg.sortMode or "classGroup")
        scale:SetExactValue(tonumber(cfg.scale) or 1)
        frameStrata:SetSelected(
            cfg.frameStrata or "FULLSCREEN_DIALOG")
        allianceBlessingsOnly:SetChecked(
            cfg.allianceBlessingsOnly ~= false)
        dismissOnRightClick:SetChecked(
            cfg.dismissOnRightClick ~= false)

        local orderedColumns = PRT:GetRaidCheckColumnOrder(true)
        for index, row in ipairs(orderRows) do
            local column = orderedColumns[index]
            if column then
                local setting = PRT:GetRaidCheckColumnSetting(column)
                row.columnKey = column.key
                row.icon:SetTexture(column.icon)
                row.icon:SetShown(column.icon ~= nil)
                row.label:SetText(column.label)
                row.enabled:SetChecked(setting.enabled ~= false)
                row.alignment:SetSelected(
                    setting.alignment or "CENTER")
                row.count:SetChecked(setting.showCount == true)
                row.count:SetShown(
                    column.multiAura == true
                    and column.supportsCount ~= false)

                local hasIconLimit = column.multiAura
                    and (tonumber(column.defaultMaxDisplay) or 1) > 1
                row.iconsLabel:SetShown(hasIconLimit)
                row.maxIcons:SetShown(hasIconLimit)
                if hasIconLimit then
                    row.maxIcons:SetItems(
                        column.key == "worldBuffs"
                            and worldBuffIconCountItems
                            or iconCountItems)
                    row.maxIcons:SetSelected(
                        tonumber(setting.maxDisplay) or 1)
                end

                local detectedOnly = column.key == "disallowed"
                row.detectedOnly:SetShown(detectedOnly)
                if detectedOnly then
                    row.detectedOnly:SetChecked(
                        setting.visibility == "detected")
                end

                row:Show()
                SetButtonEnabled(row.up, index > 1)
                SetButtonEnabled(row.down, index < #orderedColumns)
            else
                row.columnKey = nil
                row:Hide()
            end
        end
        panel:RefreshWorldBuffs()
    end

    panel.OnShow = function() panel:Refresh() end
    panel:Refresh()
    PRT.raidCheckPanel = panel
    PRT:RegisterTab("raidcheck", panel)
end
