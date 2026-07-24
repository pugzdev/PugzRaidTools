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

    ---------------------------------------------------------------------------
    -- Floating List settings
    ---------------------------------------------------------------------------
    local flHdr = W.CreateHeader(panel, "Floating Group List")
    flHdr:SetPoint("TOPLEFT", 12, -100)

    local lockCB = W.CreateCheckbox(panel, "Lock position", function(checked)
        local db = PRT:GetDB()
        db.floatingList.locked = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    lockCB:SetPoint("TOPLEFT", 12, -126)

    local hideCB = W.CreateCheckbox(panel, "Hide outside of raid", function(checked)
        local db = PRT:GetDB()
        db.floatingList.hideOutsideRaid = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    hideCB:SetPoint("TOPLEFT", 12, -150)

    local showCB = W.CreateCheckbox(panel, "Show floating list", function(checked)
        local db = PRT:GetDB()
        db.floatingList.shown = checked
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    showCB:SetPoint("TOPLEFT", 12, -174)

    local fontSlider = W.CreateSlider(panel, "Font Size", 8, 24, 1, 280, function(val)
        local db = PRT:GetDB()
        db.floatingList.fontSize = val
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)
    fontSlider:SetPoint("TOPLEFT", 12, -210)

    local scaleSlider = W.CreateSlider(panel, "Scale", 0.5, 2.0, 0.05, 280, function(val)
        local db = PRT:GetDB()
        db.floatingList.scale = val
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    scaleSlider:SetPoint("TOPLEFT", 12, -340)

    local flBgSlider = W.CreateSlider(panel, "List Background Opacity", 0.0, 1.0, 0.05, 280, function(val)
        local db = PRT:GetDB()
        db.floatingList.bgAlpha = val
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)
    flBgSlider:SetPoint("TOPLEFT", 12, -400)

    -- Font outline dropdown (below font size slider)
    local outlineLabel = W.CreateLabel(panel, "Font Outline:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    outlineLabel:SetPoint("TOPLEFT", 12, -258)

    local outlineDD = W.CreateDropdown(panel, 160, {
        { text = "None",          value = "" },
        { text = "Outline",       value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
    }, function(val)
        local db = PRT:GetDB()
        db.floatingList.fontOutline = val
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)
    outlineDD:SetPoint("TOPLEFT", 12, -274)

    -- Font color picker
    local colorLabel = W.CreateLabel(panel, "Font Color:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    colorLabel:SetPoint("TOPLEFT", 12, -306)

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
    -- Combat Logging
    ---------------------------------------------------------------------------
    local clHdr = W.CreateHeader(panel, "Combat Logging")
    clHdr:SetPoint("TOPLEFT", 12, -460)

    local autologCB = W.CreateCheckbox(panel, "Auto combat log", function(checked)
        local db = PRT:GetDB()
        db.autoLog.enabled = checked
        PRT:UpdateAutoLogListeners()
    end)
    autologCB:SetPoint("TOPLEFT", 12, -486)
    W.AttachTooltip(autologCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Automatically starts combat logging when you enter a raid instance.", 1, 1, 1, true },
            { "Stops logging when you leave. Only stops logging if PugzRaidTools started it.", 0.72, 0.72, 0.72, true },
        },
    })

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
        lockCB:SetChecked(db.floatingList.locked)
        hideCB:SetChecked(db.floatingList.hideOutsideRaid)
        showCB:SetChecked(db.floatingList.shown)
        fontSlider:SetValue(db.floatingList.fontSize or 14)
        scaleSlider:SetValue(db.floatingList.scale or 1.0)
        flBgSlider:SetValue(db.floatingList.bgAlpha or 0.7)
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
