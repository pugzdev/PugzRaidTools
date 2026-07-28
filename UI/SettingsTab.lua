---------------------------------------------------------------------------
-- PugzRaidTools - Settings Tab
-- General addon settings + floating list appearance settings.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

function PRT:BuildSettingsTab()
    local panel = CreateFrame("Frame", nil, UIParent)

    ---------------------------------------------------------------------------
    -- General settings
    ---------------------------------------------------------------------------
    local hdr = W.CreateHeader(panel, "General Settings")
    hdr:SetPoint("TOPLEFT", 12, -10)

    local bgSlider = W.CreateSlider(panel, "Main Frame Background Opacity", 0.05, 1.0, 0.05, 280, function(val)
        local db = PRT:GetDB()
        db.settings.mainBgAlpha = val
        PRT:ApplyMainBgAlpha(val)
    end)
    bgSlider:SetPoint("TOPLEFT", 12, -40)

    local minimapCB = W.CreateCheckbox(panel, "Show minimap icon", function(checked)
        local db = PRT:GetDB()
        db.settings.showMinimapIcon = checked and true or false
        if PRT.UpdateMinimapButtonVisibility then
            PRT:UpdateMinimapButtonVisibility()
        end
    end)
    minimapCB:SetPoint("TOPLEFT", 12, -82)

    ---------------------------------------------------------------------------
    -- Floating List settings
    ---------------------------------------------------------------------------
    local flHdr = W.CreateHeader(panel, "Floating Group List")
    flHdr:SetPoint("TOPLEFT", 12, -120)

    local lockCB = W.CreateCheckbox(panel, "Lock position", function(checked)
        local db = PRT:GetDB()
        db.floatingList.locked = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    lockCB:SetPoint("TOPLEFT", 12, -146)

    local hideCB = W.CreateCheckbox(panel, "Hide outside of raid", function(checked)
        local db = PRT:GetDB()
        db.floatingList.hideOutsideRaid = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    hideCB:SetPoint("TOPLEFT", 12, -170)

    local showCB = W.CreateCheckbox(panel, "Show floating list", function(checked)
        local db = PRT:GetDB()
        db.floatingList.shown = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    showCB:SetPoint("TOPLEFT", 12, -194)

    local mouseoverCB = W.CreateCheckbox(panel, "Only visible on mouse-over", function(checked)
        local db = PRT:GetDB()
        db.floatingList.mouseoverOnly = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    mouseoverCB:SetPoint("TOPLEFT", 12, -218)

    local widthSlider = W.CreateExactSlider(panel, "Width", 70, 700, 1, 130,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.width = value
            db.floatingList.textWidth = value
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        end)
    widthSlider:SetPoint("TOPLEFT", 12, -252)

    local rowHeightSlider = W.CreateExactSlider(panel, "Row Height",
        14, 90, 1, 130, function(value)
            local db = PRT:GetDB()
            db.floatingList.rowHeight = value
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        end)
    rowHeightSlider:SetPoint("TOPLEFT", 152, -252)

    local fontSlider = W.CreateExactSlider(panel, "Font Size", 6, 36, 1, 130,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.fontSize = value
            if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
        end)
    fontSlider:SetPoint("TOPLEFT", 12, -308)

    local scaleSlider = W.CreateExactSlider(panel, "Scale", 0.5, 2.0, 0.05, 130,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.scale = value
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end, 2)
    scaleSlider:SetPoint("TOPLEFT", 152, -308)

    local flBgSlider = W.CreateExactSlider(panel, "Background Opacity",
        0.0, 1.0, 0.05, 280, function(value)
            local db = PRT:GetDB()
            db.floatingList.bgAlpha = value
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end, 2)
    flBgSlider:SetPoint("TOPLEFT", 12, -364)

    local textModeLabel = W.CreateLabel(panel, "Long Text Handling:",
        PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    textModeLabel:SetPoint("TOPLEFT", 12, -420)
    local textModeDD = W.CreateDropdown(panel, 130, W.TEXT_OVERFLOW_ITEMS, function(value)
        local db = PRT:GetDB()
        db.floatingList.textMode = value
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)
    textModeDD:SetPoint("TOPLEFT", 12, -438)

    -- Font outline dropdown (below font size slider)
    local outlineLabel = W.CreateLabel(panel, "Font Outline:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    outlineLabel:SetPoint("TOPLEFT", 152, -420)

    local outlineDD = W.CreateDropdown(panel, 130, {
        { text = "None",          value = "" },
        { text = "Outline",       value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
    }, function(val)
        local db = PRT:GetDB()
        db.floatingList.fontOutline = val
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)
    outlineDD:SetPoint("TOPLEFT", 152, -438)

    -- Font color picker
    local colorLabel = W.CreateLabel(panel, "Font Color:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    colorLabel:SetPoint("TOPLEFT", 12, -478)

    local colorSwatch = W.CreateColorSwatch(panel, {
        point = { "LEFT", colorLabel, "RIGHT", 8, 0 },
    })

    local function GetFontColor()
        local db = PRT:GetDB()
        local fc = db.floatingList.fontColor
        if fc then return fc[1], fc[2], fc[3] end
        return PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3]
    end

    local function SetFontColor(r, g, b)
        local db = PRT:GetDB()
        db.floatingList.fontColor = { r, g, b }
        colorSwatch:SetColor(r, g, b, 1)
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end

    local function UpdateSwatchColor()
        local r, g, b = GetFontColor()
        colorSwatch:SetColor(r, g, b, 1)
    end

    W.AttachColorPicker(colorSwatch, {
        id = "floatFont",
        getColor = GetFontColor,
        setColor = SetFontColor,
    })

    local resetColor = W.CreateButton(panel, "Reset", 50, 20)
    resetColor:SetPoint("LEFT", colorSwatch, "RIGHT", 6, 0)
    resetColor:SetScript("OnClick", function()
        local db = PRT:GetDB()
        db.floatingList.fontColor = nil
        UpdateSwatchColor()
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)

    ---------------------------------------------------------------------------
    -- Group Swap Settings (right column, x = 310)
    ---------------------------------------------------------------------------
    local RX = 310

    local gsHdr = W.CreateHeader(panel, "Group Swap Settings")
    gsHdr:SetPoint("TOPLEFT", RX, -10)

    -- Enable toggle with tooltip
    local notifEnableCB = W.CreateCheckbox(panel, "Show group swap notification", function(checked)
        local db = PRT:GetDB()
        db.notification.enabled = checked
    end)
    notifEnableCB:SetPoint("TOPLEFT", RX, -40)
    W.AttachTooltip(notifEnableCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "When enabled, displays a large text notification on screen whenever a group composition is applied.", 1, 1, 1, true },
        },
    })

    -- Sound toggle (always plays Mario Coin when enabled)
    local notifSoundCB = W.CreateCheckbox(panel, "Play sound on swap", function(checked)
        local db = PRT:GetDB()
        db.notification.sound = checked
    end)
    notifSoundCB:SetPoint("TOPLEFT", RX, -64)

    -- Font size slider
    local notifFontSlider = W.CreateSlider(panel, "Notification Font Size", 8, 72, 2, 260, function(val)
        local db = PRT:GetDB()
        db.notification.fontSize = val
    end)
    notifFontSlider:SetPoint("TOPLEFT", RX, -96)

    -- Duration slider
    local notifDurSlider = W.CreateSlider(panel, "Duration (seconds)", 0.5, 10, 0.5, 260, function(val)
        local db = PRT:GetDB()
        db.notification.duration = val
    end)
    notifDurSlider:SetPoint("TOPLEFT", RX, -152)

    -- X offset slider
    local notifXSlider = W.CreateSlider(panel, "Screen X Offset", -800, 800, 10, 260, function(val)
        local db = PRT:GetDB()
        db.notification.x = val
    end)
    notifXSlider:SetPoint("TOPLEFT", RX, -208)

    -- Y offset slider
    local notifYSlider = W.CreateSlider(panel, "Screen Y Offset", -600, 600, 10, 260, function(val)
        local db = PRT:GetDB()
        db.notification.y = val
    end)
    notifYSlider:SetPoint("TOPLEFT", RX, -264)

    -- Notification font color picker
    local notifColorLabel = W.CreateLabel(panel, "Notification Color:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    notifColorLabel:SetPoint("TOPLEFT", RX, -320)

    local notifColorSwatch = W.CreateColorSwatch(panel, {
        point = { "LEFT", notifColorLabel, "RIGHT", 8, 0 },
    })

    local function GetNotifColor()
        local db = PRT:GetDB()
        local fc = db.notification and db.notification.fontColor
        if fc then return fc[1], fc[2], fc[3] end
        return PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3]
    end

    local function SetNotifColor(r, g, b)
        local db = PRT:GetDB()
        if db.notification then
            db.notification.fontColor = { r, g, b }
        end
        notifColorSwatch:SetColor(r, g, b, 1)
    end

    local function UpdateNotifSwatchColor()
        local r, g, b = GetNotifColor()
        notifColorSwatch:SetColor(r, g, b, 1)
    end

    W.AttachColorPicker(notifColorSwatch, {
        id = "notifFont",
        getColor = GetNotifColor,
        setColor = SetNotifColor,
    })

    local notifResetColor = W.CreateButton(panel, "Reset", 50, 20)
    notifResetColor:SetPoint("LEFT", notifColorSwatch, "RIGHT", 6, 0)
    notifResetColor:SetScript("OnClick", function()
        local db = PRT:GetDB()
        if db.notification then db.notification.fontColor = nil end
        UpdateNotifSwatchColor()
    end)

    local notifTest = W.CreateButton(panel, "Test Notification", 130, 22)
    notifTest:SetPoint("TOPLEFT", RX, -352)
    notifTest:SetScript("OnClick", function()
        local cfg = PRT:GetDB().notification or {}
        if PRT.ShowNotification then
            PRT:ShowNotification("Test Group Swap applied.", {
                force = true,
                playSound = cfg.sound and true or false,
                soundFile = PRT.SND_MARIO,
            })
        end
    end)

    ---------------------------------------------------------------------------
    -- Combat Logging
    ---------------------------------------------------------------------------
    local clHdr = W.CreateHeader(panel, "Combat Logging")
    clHdr:SetPoint("TOPLEFT", RX, -390)

    local autologCB = W.CreateCheckbox(panel, "Auto combat log", function(checked)
        local db = PRT:GetDB()
        db.autoLog.enabled = checked
        PRT:UpdateAutoLogListeners()
    end)
    autologCB:SetPoint("TOPLEFT", RX, -416)
    W.AttachTooltip(autologCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Automatically starts combat logging when you enter a raid instance.", 1, 1, 1, true },
            { "Stops logging when you leave. Only stops logging if PugzRaidTools started it.", 0.72, 0.72, 0.72, true },
        },
    })

    ---------------------------------------------------------------------------
    -- Version / info
    ---------------------------------------------------------------------------
    local verLabel = W.CreateLabel(panel, "PugzRaidTools v" .. PRT.VERSION, PRT.FONT_SIZE - 1, PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
    verLabel:SetPoint("BOTTOMLEFT", 12, 10)

    ---------------------------------------------------------------------------
    -- OnShow
    ---------------------------------------------------------------------------
    function panel:OnShow()
        local db = PRT:GetDB()
        bgSlider:SetValue(db.settings.mainBgAlpha or 0.92)
        minimapCB:SetChecked(db.settings.showMinimapIcon ~= false)
        lockCB:SetChecked(db.floatingList.locked)
        hideCB:SetChecked(db.floatingList.hideOutsideRaid)
        showCB:SetChecked(db.floatingList.shown)
        mouseoverCB:SetChecked(db.floatingList.mouseoverOnly)
        widthSlider:SetExactValue(
            db.floatingList.width or db.floatingList.textWidth or 180)
        rowHeightSlider:SetExactValue(db.floatingList.rowHeight or 20)
        fontSlider:SetExactValue(db.floatingList.fontSize or 14)
        if db.floatingList.textMode == "wrap" then
            db.floatingList.textMode = "truncate"
        end
        textModeDD:SetSelected(db.floatingList.textMode or "expand")
        scaleSlider:SetExactValue(db.floatingList.scale or 1.0)
        flBgSlider:SetExactValue(db.floatingList.bgAlpha or 0.7)
        outlineDD:SetSelected(db.floatingList.fontOutline or "OUTLINE")
        UpdateSwatchColor()

        -- Combat logging
        autologCB:SetChecked(db.autoLog and db.autoLog.enabled or false)

        -- Notification settings
        local n = db.notification or {}
        notifEnableCB:SetChecked(n.enabled ~= false)
        notifSoundCB:SetChecked(n.sound or false)
        notifFontSlider:SetValue(n.fontSize or 32)
        notifDurSlider:SetValue(n.duration or 3.0)
        notifXSlider:SetValue(n.x or 0)
        notifYSlider:SetValue(n.y or 80)
        UpdateNotifSwatchColor()
    end

    PRT:RegisterTab("settings", panel)
end
