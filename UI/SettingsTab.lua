---------------------------------------------------------------------------
-- PugzRaidTools - Settings Tab
-- General interface, Floating Group List, notifications, and logging.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local LEFT_X = 2
local RIGHT_X = 322
local SLIDER_WIDTH = 286
local CONTENT_HEIGHT = 1200

local function Divider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, y)
    line:SetPoint("TOPRIGHT", -8, y)
    line:SetHeight(1)
    line:SetColorTexture(
        PRT.C.BORDER[1],
        PRT.C.BORDER[2],
        PRT.C.BORDER[3],
        0.55)
    return line
end

local function Subheader(parent, text, x, y)
    local label = W.CreateLabel(
        parent,
        text,
        PRT.FONT_SIZE,
        PRT.C.TITLE[1],
        PRT.C.TITLE[2],
        PRT.C.TITLE[3])
    label:SetPoint("TOPLEFT", x, y)
    return label
end

function PRT:BuildSettingsTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    local scroller = W.CreateScrollFrame(panel, 0, 0)
    scroller:SetPoint("TOPLEFT", 10, -8)
    scroller:SetPoint("BOTTOMRIGHT", -10, 8)
    local content = scroller.content

    -----------------------------------------------------------------------
    -- Page introduction
    -----------------------------------------------------------------------
    local title = W.CreateHeader(content, "Settings")
    title:SetPoint("TOPLEFT", LEFT_X, 0)

    local intro = W.CreateDescription(content,
        "Configure PRT's general interface, Floating Group List, group-swap notifications, and automatic combat logging.", {
            color = { 0.75, 0.75, 0.75 },
        })
    intro:SetPoint("TOPLEFT", LEFT_X, -27)
    intro:SetPoint("TOPRIGHT", -8, -27)

    Divider(content, -69)

    -----------------------------------------------------------------------
    -- General interface
    -----------------------------------------------------------------------
    local generalHeader = W.CreateHeader(content, "General Interface")
    generalHeader:SetPoint("TOPLEFT", LEFT_X, -82)

    local generalDescription = W.CreateDescription(content,
        "Controls shared by the main configuration window and minimap launcher.")
    generalDescription:SetPoint("TOPLEFT", LEFT_X, -108)
    generalDescription:SetPoint("TOPRIGHT", -8, -108)

    local bgSlider = W.CreateExactSlider(
        content,
        "Main Window Background Opacity",
        0.05,
        1.0,
        0.05,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.settings.mainBgAlpha = value
            PRT:ApplyMainBgAlpha(value)
        end,
        2)
    bgSlider:SetPoint("TOPLEFT", LEFT_X, -140)

    local minimapCB = W.CreateCheckbox(
        content, "Show minimap icon", function(checked)
            local db = PRT:GetDB()
            db.settings.showMinimapIcon = checked and true or false
            if PRT.UpdateMinimapButtonVisibility then
                PRT:UpdateMinimapButtonVisibility()
            end
        end)
    minimapCB:SetPoint("TOPLEFT", RIGHT_X, -146)

    Divider(content, -200)

    -----------------------------------------------------------------------
    -- Floating Group List
    -----------------------------------------------------------------------
    local floatingHeader = W.CreateHeader(content, "Floating Group List")
    floatingHeader:SetPoint("TOPLEFT", LEFT_X, -213)

    local floatingDescription = W.CreateDescription(content,
        "Control when the raid composition float appears and how its rows, text, and background are displayed.")
    floatingDescription:SetPoint("TOPLEFT", LEFT_X, -239)
    floatingDescription:SetPoint("TOPRIGHT", -8, -239)

    Subheader(content, "Visibility and Behaviour", LEFT_X, -278)

    local showCB = W.CreateCheckbox(
        content, "Show floating list", function(checked)
            local db = PRT:GetDB()
            db.floatingList.shown = checked
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end)
    showCB:SetPoint("TOPLEFT", LEFT_X, -302)

    local hideCB = W.CreateCheckbox(
        content, "Hide outside of raid", function(checked)
            local db = PRT:GetDB()
            db.floatingList.hideOutsideRaid = checked
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end)
    hideCB:SetPoint("TOPLEFT", RIGHT_X, -302)

    local mouseoverCB = W.CreateCheckbox(
        content, "Only visible on mouse-over", function(checked)
            local db = PRT:GetDB()
            db.floatingList.mouseoverOnly = checked
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end)
    mouseoverCB:SetPoint("TOPLEFT", LEFT_X, -330)

    local lockCB = W.CreateCheckbox(
        content, "Lock position", function(checked)
            local db = PRT:GetDB()
            db.floatingList.locked = checked
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end)
    lockCB:SetPoint("TOPLEFT", RIGHT_X, -330)

    Subheader(content, "Size and Appearance", LEFT_X, -374)

    local widthSlider = W.CreateExactSlider(
        content, "Width", 70, 700, 1, SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.width = value
            db.floatingList.textWidth = value
            if PRT.RefreshFloatingList then
                PRT:RefreshFloatingList()
            end
        end)
    widthSlider:SetPoint("TOPLEFT", LEFT_X, -400)

    local rowHeightSlider = W.CreateExactSlider(
        content, "Row Height", 14, 90, 1, SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.rowHeight = value
            if PRT.RefreshFloatingList then
                PRT:RefreshFloatingList()
            end
        end)
    rowHeightSlider:SetPoint("TOPLEFT", RIGHT_X, -400)

    local fontSlider = W.CreateExactSlider(
        content, "Font Size", 6, 36, 1, SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.fontSize = value
            if PRT.RefreshFloatingList then
                PRT:RefreshFloatingList()
            end
        end)
    fontSlider:SetPoint("TOPLEFT", LEFT_X, -458)

    local scaleSlider = W.CreateExactSlider(
        content, "Scale", 0.5, 2.0, 0.05, SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.scale = value
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end,
        2)
    scaleSlider:SetPoint("TOPLEFT", RIGHT_X, -458)

    local flBgSlider = W.CreateExactSlider(
        content,
        "Background Opacity",
        0.0,
        1.0,
        0.05,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.floatingList.bgAlpha = value
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end,
        2)
    flBgSlider:SetPoint("TOPLEFT", LEFT_X, -516)

    Subheader(content, "Text Appearance", LEFT_X, -578)

    local textModeLabel = W.CreateLabel(
        content, "Long Text Handling:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    textModeLabel:SetPoint("TOPLEFT", LEFT_X, -604)
    local textModeDD = W.CreateDropdown(
        content, 140, W.TEXT_OVERFLOW_ITEMS, function(value)
            local db = PRT:GetDB()
            db.floatingList.textMode = value
            if PRT.RefreshFloatingList then
                PRT:RefreshFloatingList()
            end
        end)
    textModeDD:SetPoint("TOPLEFT", LEFT_X, -622)

    local outlineLabel = W.CreateLabel(
        content, "Font Outline:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    outlineLabel:SetPoint("TOPLEFT", 174, -604)
    local outlineDD = W.CreateDropdown(content, 130, {
        { text = "None", value = "" },
        { text = "Outline", value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
    }, function(value)
        local db = PRT:GetDB()
        db.floatingList.fontOutline = value
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)
    outlineDD:SetPoint("TOPLEFT", 174, -622)

    local colorLabel = W.CreateLabel(
        content, "Font Color:", PRT.FONT_SIZE, 0.8, 0.8, 0.8)
    colorLabel:SetPoint("TOPLEFT", RIGHT_X, -604)
    local colorSwatch = W.CreateColorSwatch(content, {
        point = { "TOPLEFT", RIGHT_X, -622 },
    })

    local function GetFontColor()
        local db = PRT:GetDB()
        local color = db.floatingList.fontColor
        if color then return color[1], color[2], color[3] end
        return PRT.C.SETTINGS_FONT[1],
            PRT.C.SETTINGS_FONT[2],
            PRT.C.SETTINGS_FONT[3]
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

    local resetColor = W.CreateButton(content, "Reset", 56, 20)
    resetColor:SetPoint("LEFT", colorSwatch, "RIGHT", 8, 0)
    resetColor:SetScript("OnClick", function()
        local db = PRT:GetDB()
        db.floatingList.fontColor = nil
        UpdateSwatchColor()
        if PRT.RefreshFloatingList then PRT:RefreshFloatingList() end
    end)

    Divider(content, -680)

    -----------------------------------------------------------------------
    -- Group swap notifications
    -----------------------------------------------------------------------
    local notificationHeader =
        W.CreateHeader(content, "Group Swap Notifications")
    notificationHeader:SetPoint("TOPLEFT", LEFT_X, -693)

    local notificationDescription = W.CreateDescription(content,
        "Configure the on-screen message shown after a group composition is applied.")
    notificationDescription:SetPoint("TOPLEFT", LEFT_X, -719)
    notificationDescription:SetPoint("TOPRIGHT", -8, -719)

    local notifEnableCB = W.CreateCheckbox(
        content, "Show group swap notification", function(checked)
            local db = PRT:GetDB()
            db.notification.enabled = checked
        end)
    notifEnableCB:SetPoint("TOPLEFT", LEFT_X, -753)
    W.AttachTooltip(notifEnableCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            {
                "Displays a large on-screen message whenever a group composition is applied.",
                1, 1, 1, true,
            },
        },
    })

    local notifSoundCB = W.CreateCheckbox(
        content, "Play sound on swap", function(checked)
            local db = PRT:GetDB()
            db.notification.sound = checked
        end)
    notifSoundCB:SetPoint("TOPLEFT", RIGHT_X, -753)

    local notifFontSlider = W.CreateExactSlider(
        content,
        "Notification Font Size",
        8,
        72,
        2,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.notification.fontSize = value
        end)
    notifFontSlider:SetPoint("TOPLEFT", LEFT_X, -790)

    local notifDurSlider = W.CreateExactSlider(
        content,
        "Duration (seconds)",
        0.5,
        10,
        0.5,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.notification.duration = value
        end,
        1)
    notifDurSlider:SetPoint("TOPLEFT", RIGHT_X, -790)

    local notifXSlider = W.CreateExactSlider(
        content,
        "Screen X Offset",
        -800,
        800,
        10,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.notification.x = value
        end)
    notifXSlider:SetPoint("TOPLEFT", LEFT_X, -848)

    local notifYSlider = W.CreateExactSlider(
        content,
        "Screen Y Offset",
        -600,
        600,
        10,
        SLIDER_WIDTH,
        function(value)
            local db = PRT:GetDB()
            db.notification.y = value
        end)
    notifYSlider:SetPoint("TOPLEFT", RIGHT_X, -848)

    local notifColorLabel = W.CreateLabel(
        content,
        "Notification Color:",
        PRT.FONT_SIZE,
        0.8, 0.8, 0.8)
    notifColorLabel:SetPoint("TOPLEFT", LEFT_X, -912)
    local notifColorSwatch = W.CreateColorSwatch(content, {
        point = { "LEFT", notifColorLabel, "RIGHT", 8, 0 },
    })

    local function GetNotifColor()
        local db = PRT:GetDB()
        local color = db.notification and db.notification.fontColor
        if color then return color[1], color[2], color[3] end
        return PRT.C.SETTINGS_FONT[1],
            PRT.C.SETTINGS_FONT[2],
            PRT.C.SETTINGS_FONT[3]
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

    local notifResetColor = W.CreateButton(content, "Reset", 56, 20)
    notifResetColor:SetPoint(
        "LEFT", notifColorSwatch, "RIGHT", 8, 0)
    notifResetColor:SetScript("OnClick", function()
        local db = PRT:GetDB()
        if db.notification then db.notification.fontColor = nil end
        UpdateNotifSwatchColor()
    end)

    local notifTest =
        W.CreateButton(content, "Test Notification", 150, 22)
    notifTest:SetPoint("TOPLEFT", RIGHT_X, -906)
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

    Divider(content, -958)

    -----------------------------------------------------------------------
    -- Combat logging
    -----------------------------------------------------------------------
    local loggingHeader = W.CreateHeader(content, "Combat Logging")
    loggingHeader:SetPoint("TOPLEFT", LEFT_X, -971)

    local loggingDescription = W.CreateDescription(content,
        "Automatically start combat logging inside raid instances and stop it on exit only when PRT started the log.")
    loggingDescription:SetPoint("TOPLEFT", LEFT_X, -997)
    loggingDescription:SetPoint("TOPRIGHT", -8, -997)

    local autologCB = W.CreateCheckbox(
        content, "Auto combat log in raid instances", function(checked)
            local db = PRT:GetDB()
            db.autoLog.enabled = checked
            PRT:UpdateAutoLogListeners()
        end)
    autologCB:SetPoint("TOPLEFT", LEFT_X, -1031)
    W.AttachTooltip(autologCB.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            {
                "Automatically starts combat logging when you enter a raid instance.",
                1, 1, 1, true,
            },
            {
                "PRT only stops logging when it started the active log.",
                0.72, 0.72, 0.72, true,
            },
        },
    })

    Divider(content, -1076)

    -----------------------------------------------------------------------
    -- About
    -----------------------------------------------------------------------
    local aboutHeader = W.CreateHeader(content, "About")
    aboutHeader:SetPoint("TOPLEFT", LEFT_X, -1089)

    local versionLabel = W.CreateLabel(
        content,
        PRT:GetVersionDisplayText(),
        PRT.FONT_SIZE,
        0.8, 0.8, 0.8)
    versionLabel:SetPoint("TOPLEFT", LEFT_X, -1117)

    local savedDescription = W.CreateDescription(
        content, "Settings are saved automatically.")
    savedDescription:SetPoint("TOPLEFT", LEFT_X, -1141)

    scroller:UpdateContentHeight(CONTENT_HEIGHT)

    -----------------------------------------------------------------------
    -- Refresh displayed values whenever the tab opens.
    -----------------------------------------------------------------------
    function panel:OnShow()
        local db = PRT:GetDB()
        bgSlider:SetExactValue(db.settings.mainBgAlpha or 0.92)
        minimapCB:SetChecked(db.settings.showMinimapIcon ~= false)

        showCB:SetChecked(db.floatingList.shown)
        hideCB:SetChecked(db.floatingList.hideOutsideRaid)
        mouseoverCB:SetChecked(db.floatingList.mouseoverOnly)
        lockCB:SetChecked(db.floatingList.locked)
        widthSlider:SetExactValue(
            db.floatingList.width
                or db.floatingList.textWidth
                or 180)
        rowHeightSlider:SetExactValue(
            db.floatingList.rowHeight or 20)
        fontSlider:SetExactValue(db.floatingList.fontSize or 14)
        scaleSlider:SetExactValue(db.floatingList.scale or 1.0)
        flBgSlider:SetExactValue(db.floatingList.bgAlpha or 0.7)

        if db.floatingList.textMode == "wrap" then
            db.floatingList.textMode = "truncate"
        end
        textModeDD:SetSelected(
            db.floatingList.textMode or "expand")
        outlineDD:SetSelected(
            db.floatingList.fontOutline or "OUTLINE")
        UpdateSwatchColor()

        local notification = db.notification or {}
        notifEnableCB:SetChecked(notification.enabled ~= false)
        notifSoundCB:SetChecked(notification.sound or false)
        notifFontSlider:SetExactValue(notification.fontSize or 32)
        notifDurSlider:SetExactValue(notification.duration or 3.0)
        notifXSlider:SetExactValue(notification.x or 0)
        notifYSlider:SetExactValue(notification.y or 80)
        UpdateNotifSwatchColor()

        autologCB:SetChecked(
            db.autoLog and db.autoLog.enabled or false)
    end

    PRT.settingsPanel = panel
    PRT:RegisterTab("settings", panel)
end
