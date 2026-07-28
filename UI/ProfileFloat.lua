---------------------------------------------------------------------------
-- PugzRaidTools - Profile Float
-- Compact profile switcher for activating an overall PRT profile.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local DEFAULT_WIDTH = 220
local DEFAULT_HEIGHT = 30
local PADDING = 3
local MIN_WIDTH = 80
local MIN_HEIGHT = 18
local MIN_FONT_SIZE = 6

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

local function RefreshHoverTextureHeight(button, height)
    if button and button.SetHoverAnimationHeight then
        button:SetHoverAnimationHeight(height)
    elseif button and button._mrtHoverTexture then
        button._mrtHoverTexture:SetHeight(height)
    end
end

local function IsMouseOverFrame(frame)
    if not frame or not frame:IsShown() then return false end
    if MouseIsOver then return MouseIsOver(frame) end
    if frame.IsMouseOver then return frame:IsMouseOver() end
    return false
end

local function SavePosition(frame)
    local cfg = PRT:GetDB().profileFloat
    local point, _, relativePoint, x, y = frame:GetPoint()
    cfg.point = point
    cfg.relPoint = relativePoint
    cfg.x = x
    cfg.y = y
end

local function FadeTo(frame, alpha)
    if UIFrameFade then
        UIFrameFade(frame, {
            mode = alpha > frame:GetAlpha() and "IN" or "OUT",
            timeToFade = 0.15,
            startAlpha = frame:GetAlpha(),
            endAlpha = alpha,
        })
    else
        frame:SetAlpha(alpha)
    end
end

local function ScheduleMouseoverFade(frame)
    frame._fadeSerial = (frame._fadeSerial or 0) + 1
    local serial = frame._fadeSerial
    C_Timer.After(0.12, function()
        if not frame:IsShown() or frame._fadeSerial ~= serial then return end
        local cfg = PRT:GetDB().profileFloat
        if cfg.mouseoverOnly and not IsMouseOverFrame(frame)
                and not IsMouseOverFrame(frame.menu) then
            frame.menu:Hide()
            FadeTo(frame, 0)
        end
    end)
end

local function CreateProfileRow(frame, index)
    local row = W.CreateSelectableButton(frame.menu, "", {
        width = DEFAULT_WIDTH - PADDING * 2,
        height = DEFAULT_HEIGHT,
        labelPoint = { "LEFT", 8, 0 },
        justifyH = "LEFT",
        bgColor = { 0, 0, 0, 0 },
        selectedBgColor = {
            PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
            PRT.C.SIDEBAR_SEL[3], 0.92,
        },
        selectedTextColor = { PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1 },
        borderColor = { 0, 0, 0, 0 },
        selectedBorderColor = { 0, 0, 0, 0 },
        hoverAnimation = "MRT",
        hoverAnimationHeight = DEFAULT_HEIGHT,
    })
    row:SetScript("OnClick", function(self)
        if self.profileName and PRT:ActivatePRTProfile(self.profileName) then
            PRT.Print('Activated PRT profile "' .. self.profileName .. '".')
        end
        frame.menu:Hide()
        if PRT:GetDB().profileFloat.mouseoverOnly then
            ScheduleMouseoverFade(frame)
        end
    end)
    row:HookScript("OnEnter", function()
        frame._fadeSerial = (frame._fadeSerial or 0) + 1
        FadeTo(frame, 1)
    end)
    row:HookScript("OnLeave", function()
        ScheduleMouseoverFade(frame)
    end)
    frame.rows[index] = row
    return row
end

local function SaveGroupFloatPosition(frame)
    local cfg = PRT:GetDB().floatingList
    local point, _, relativePoint, x, y = frame:GetPoint()
    cfg.point = point
    cfg.relPoint = relativePoint
    cfg.x = x
    cfg.y = y
end

local function PositionEmbeddedMenu()
    local frame = PRT.floatingFrame
    local menu = frame and frame.profileMenu
    if not frame or not menu or not menu:IsShown() then return end

    local gap = 0
    local left = frame:GetLeft() or 0
    local right = frame:GetRight() or 0
    local top = frame:GetTop() or 0
    local bottom = frame:GetBottom() or 0
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local menuScale = menu:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local menuWidth = menu:GetWidth() * menuScale
    local menuHeight = menu:GetHeight() * menuScale
    local alignBottom = PRT:GetDB().profileFloat.embeddedPosition == "bottom"

    menu:ClearAllPoints()
    if screenWidth - right >= menuWidth + gap then
        if alignBottom then
            menu:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", gap, 0)
        else
            menu:SetPoint("TOPLEFT", frame, "TOPRIGHT", gap, 0)
        end
    elseif left >= menuWidth + gap then
        if alignBottom then
            menu:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -gap, 0)
        else
            menu:SetPoint("TOPRIGHT", frame, "TOPLEFT", -gap, 0)
        end
    elseif bottom >= menuHeight + gap then
        menu:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -gap)
    elseif screenHeight - top >= menuHeight + gap then
        menu:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, gap)
    else
        menu:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -gap)
    end
end

local function CreateEmbeddedProfileRow(frame, index)
    local row = W.CreateSelectableButton(frame.profileMenu, "", {
        width = DEFAULT_WIDTH - PADDING * 2,
        height = DEFAULT_HEIGHT,
        labelPoint = { "LEFT", 8, 0 },
        justifyH = "LEFT",
        bgColor = { 0, 0, 0, 0 },
        selectedBgColor = {
            PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
            PRT.C.SIDEBAR_SEL[3], 0.92,
        },
        selectedTextColor = {
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1,
        },
        borderColor = { 0, 0, 0, 0 },
        selectedBorderColor = { 0, 0, 0, 0 },
        hoverAnimation = "MRT",
        hoverAnimationHeight = DEFAULT_HEIGHT,
    })
    row:SetScript("OnClick", function(self)
        if self.profileName and PRT:ActivatePRTProfile(self.profileName) then
            PRT.Print('Activated PRT profile "' .. self.profileName .. '".')
        end
        frame.profileMenu:Hide()
    end)
    frame.profileRows[index] = row
    return row
end

function PRT:InitEmbeddedProfileSelector()
    local frame = self.floatingFrame
    if not frame or frame.profileButton then return end

    local button = W.CreateSelectableButton(frame, "", {
        width = DEFAULT_WIDTH - PADDING * 2,
        height = DEFAULT_HEIGHT,
        labelPoint = { "LEFT", 6, 0 },
        justifyH = "LEFT",
        bgColor = { 0, 0, 0, 0 },
        selectedBgColor = {
            PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2],
            PRT.C.SIDEBAR_SEL[3], 0.92,
        },
        textColor = { 1, 1, 1, 1 },
        selectedTextColor = { 1, 1, 1, 1 },
        borderColor = { 0, 0, 0, 0 },
        selectedBorderColor = { 0, 0, 0, 0 },
        hoverAnimation = "MRT",
        hoverAnimationHeight = DEFAULT_HEIGHT,
        dragButton = "LeftButton",
    })
    button:RegisterForDrag("LeftButton")
    frame.profileButton = button

    local arrow = W.CreateLabel(button, "v", PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    arrow:SetJustifyH("RIGHT")
    frame.profileArrow = arrow

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    W.AddBackground(menu, 0.02, 0.02, 0.02, 0.98)
    W.AddBorders(menu, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.9)
    menu:Hide()
    frame.profileMenu = menu
    frame.profileRows = {}

    button:SetScript("OnClick", function()
        if frame._profileSuppressClick then return end
        if menu:IsShown() then
            menu:Hide()
        else
            PRT:RefreshEmbeddedProfileSelector()
            menu:Show()
            PositionEmbeddedMenu()
        end
    end)
    button:SetScript("OnDragStart", function()
        if not PRT:GetDB().floatingList.locked then
            frame._profileSuppressClick = true
            frame:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveGroupFloatPosition(frame)
        C_Timer.After(0, function()
            frame._profileSuppressClick = false
        end)
    end)
end

function PRT:InitProfileFloat()
    if self.profileFloatFrame then return end

    local frame = CreateFrame("Frame", "PugzRaidToolsProfileFloat", UIParent)
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("MEDIUM")
    if frame.SetToplevel then frame:SetToplevel(true) end
    W.AddBackground(frame, 0.02, 0.02, 0.02, 0.92)
    W.AddBorders(frame, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.85)

    local button = W.CreateSelectableButton(frame, "", {
        width = DEFAULT_WIDTH - PADDING * 2,
        height = DEFAULT_HEIGHT - PADDING * 2,
        labelPoint = { "LEFT", 8, 0 },
        justifyH = "LEFT",
        bgColor = { 0, 0, 0, 0 },
        borderColor = { 0, 0, 0, 0 },
        hoverAnimation = "MRT",
        hoverAnimationHeight = DEFAULT_HEIGHT - PADDING * 2,
        dragButton = "LeftButton",
    })
    button:SetPoint("TOPLEFT", PADDING, -PADDING)
    button:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    frame.button = button

    local menu = CreateFrame("Frame", nil, frame)
    menu:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
    menu:SetFrameLevel(frame:GetFrameLevel() + 20)
    W.AddBackground(menu, 0.02, 0.02, 0.02, 0.98)
    W.AddBorders(menu, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.9)
    menu:Hide()
    frame.menu = menu
    frame.rows = {}

    button:SetScript("OnClick", function()
        if frame._suppressClick then return end
        if menu:IsShown() then
            menu:Hide()
        else
            PRT:RefreshProfileFloat()
            menu:Show()
            FadeTo(frame, 1)
        end
    end)
    button:SetScript("OnDragStart", function()
        if not PRT:GetDB().profileFloat.locked then
            frame._suppressClick = true
            frame:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        C_Timer.After(0, function()
            frame._suppressClick = false
        end)
    end)
    button:HookScript("OnEnter", function()
        frame._fadeSerial = (frame._fadeSerial or 0) + 1
        FadeTo(frame, 1)
    end)
    button:HookScript("OnLeave", function()
        ScheduleMouseoverFade(frame)
    end)

    frame:SetScript("OnMouseDown", function(self)
        if not PRT:GetDB().profileFloat.locked then self:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:HookScript("OnEnter", function(self)
        self._fadeSerial = (self._fadeSerial or 0) + 1
        FadeTo(self, 1)
    end)
    frame:HookScript("OnLeave", function(self)
        ScheduleMouseoverFade(self)
    end)
    menu:HookScript("OnEnter", function()
        frame._fadeSerial = (frame._fadeSerial or 0) + 1
        FadeTo(frame, 1)
    end)
    menu:HookScript("OnLeave", function()
        ScheduleMouseoverFade(frame)
    end)

    self.profileFloatFrame = frame
    self:InitEmbeddedProfileSelector()
    self:UpdateProfileFloat()
end

function PRT:RefreshProfileFloat()
    local frame = self.profileFloatFrame
    if not frame then return end
    self:EnsurePRTProfilesDefaults()

    local cfg = self:GetDB().profileFloat
    local store = self:GetDB().prtProfiles
    local width = Clamp(cfg.width, MIN_WIDTH, 700, DEFAULT_WIDTH)
    local height = Clamp(cfg.height, MIN_HEIGHT, 90, DEFAULT_HEIGHT)
    local fontSize = Clamp(cfg.fontSize, MIN_FONT_SIZE, 36, PRT.FONT_SIZE)
    local textMode = cfg.textMode or "truncate"
    if textMode == "wrap" then
        textMode = "truncate"
    end
    local innerWidth = math.max(1, width - PADDING * 2)
    local innerHeight = math.max(1, height - PADDING * 2)
    local rowHeight = math.max(MIN_HEIGHT, height)

    cfg.width = width
    cfg.height = height
    cfg.fontSize = fontSize
    cfg.textMode = textMode
    cfg.scale = 1

    frame:SetSize(width, height)
    frame.button:SetSize(innerWidth, innerHeight)
    W.ApplyTextOverflow(frame.button.label,
        "Profile: " .. (store.activeProfile or ""), {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = MIN_FONT_SIZE,
            width = math.max(1, innerWidth - 16),
            height = innerHeight,
        })
    RefreshHoverTextureHeight(frame.button, innerHeight)
    for _, row in ipairs(frame.rows) do row:Hide() end

    for index, profile in ipairs(store.profiles or {}) do
        local row = frame.rows[index] or CreateProfileRow(frame, index)
        row.profileName = profile.name
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PADDING, -(PADDING + (index - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", -PADDING, -(PADDING + (index - 1) * rowHeight))
        row:SetHeight(rowHeight)
        W.ApplyTextOverflow(row.label, profile.name, {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = MIN_FONT_SIZE,
            width = math.max(1, innerWidth - 16),
            height = rowHeight,
        })
        RefreshHoverTextureHeight(row, rowHeight)
        row:SetSelected(profile.name == store.activeProfile)
        row:Show()
    end

    frame.menu:SetHeight(math.max(rowHeight + PADDING * 2,
        #(store.profiles or {}) * rowHeight + PADDING * 2))
end

function PRT:RefreshEmbeddedProfileSelector(frameWidth, rowHeight, fontSize,
        textMode, outline)
    local frame = self.floatingFrame
    if not frame or not frame.profileButton then return end
    self:EnsurePRTProfilesDefaults()

    local cfg = self:GetDB().profileFloat
    local listCfg = self:GetDB().floatingList
    local store = self:GetDB().prtProfiles
    local embedded = cfg.embedInGroupList and true or false
    if not embedded then
        frame.profileButton:Hide()
        if frame.profileArrow then frame.profileArrow:Hide() end
        frame.profileMenu:Hide()
        return
    end

    frameWidth = tonumber(frameWidth) or frame:GetWidth() or 180
    rowHeight = Clamp(rowHeight or listCfg.rowHeight, 14, 90, 20)
    fontSize = Clamp(fontSize or listCfg.fontSize, MIN_FONT_SIZE, 36, 14)
    textMode = textMode or listCfg.textMode or "expand"
    if textMode == "wrap" then
        textMode = "truncate"
        listCfg.textMode = textMode
    end
    outline = outline or listCfg.fontOutline or "OUTLINE"
    local alignment = cfg.embeddedAlignment == "right" and "RIGHT"
        or cfg.embeddedAlignment == "center" and "CENTER" or "LEFT"
    local innerWidth = math.max(1, frameWidth - PADDING * 2)
    local textWidth = math.max(1, innerWidth - 30)
    local menuTextWidth = math.max(1, innerWidth - 12)

    frame.profileButton:SetHeight(rowHeight)
    frame.profileButton.label:ClearAllPoints()
    frame.profileButton.label:SetPoint("LEFT", frame.profileButton, "LEFT", 6, 0)
    frame.profileButton.label:SetJustifyH(alignment)
    W.ApplyTextOverflow(frame.profileButton.label,
        "Profile: " .. (store.activeProfile or ""), {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = MIN_FONT_SIZE,
            width = textWidth,
            height = rowHeight,
            outline = outline,
        })
    frame.profileButton.label:SetTextColor(1, 1, 1, 1)
    frame.profileButton:SetSelected(cfg.embeddedHighlight ~= false)
    frame.profileArrow:SetFont(PRT.FONT, fontSize, outline)
    frame.profileArrow:SetTextColor(
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1)
    frame.profileArrow:Show()
    RefreshHoverTextureHeight(frame.profileButton, rowHeight)
    frame.profileButton:Show()

    for _, row in ipairs(frame.profileRows) do row:Hide() end
    for index, profile in ipairs(store.profiles or {}) do
        local row = frame.profileRows[index]
            or CreateEmbeddedProfileRow(frame, index)
        row.profileName = profile.name
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PADDING,
            -(PADDING + (index - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", -PADDING,
            -(PADDING + (index - 1) * rowHeight))
        row:SetHeight(rowHeight)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.label:SetJustifyH(alignment)
        W.ApplyTextOverflow(row.label, profile.name, {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = MIN_FONT_SIZE,
            width = menuTextWidth,
            height = rowHeight,
            outline = outline,
        })
        RefreshHoverTextureHeight(row, rowHeight)
        row:SetSelected(profile.name == store.activeProfile)
        row:Show()
    end

    local bgAlpha = Clamp(listCfg.bgAlpha, 0, 1, 0.7)
    local groupScale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame.profileMenu:SetScale(groupScale)
    frame.profileMenu:SetSize(frameWidth,
        math.max(rowHeight + PADDING * 2,
            #(store.profiles or {}) * rowHeight + PADDING * 2))
    if frame.profileMenu._bgTex then
        frame.profileMenu._bgTex:SetColorTexture(0.02, 0.02, 0.02, bgAlpha)
    end
    PositionEmbeddedMenu()
end

function PRT:UpdateProfileFloat()
    local frame = self.profileFloatFrame
    if not frame then return end
    local cfg = self:GetDB().profileFloat

    self:RefreshProfileFloat()
    if self.RefreshFloatingList then self:RefreshFloatingList() end
    if self.UpdateFloatingList then self:UpdateFloatingList() end
    frame:ClearAllPoints()
    frame:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER",
        cfg.x or 0, cfg.y or 160)
    frame:SetScale(1)

    local bgAlpha = Clamp(cfg.bgAlpha, 0, 1, 0.92)
    cfg.bgAlpha = bgAlpha
    if frame._bgTex then
        frame._bgTex:SetColorTexture(0.02, 0.02, 0.02, bgAlpha)
    end
    if frame.menu._bgTex then
        frame.menu._bgTex:SetColorTexture(0.02, 0.02, 0.02, bgAlpha)
    end
    if frame._borders then
        local borderAlpha = bgAlpha > 0.05 and math.min(bgAlpha + 0.15, 0.9) or 0
        for _, border in ipairs(frame._borders) do
            border:SetColorTexture(
                PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], borderAlpha)
        end
        for _, border in ipairs(frame.menu._borders or {}) do
            border:SetColorTexture(
                PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], borderAlpha)
        end
    end

    if cfg.embedInGroupList then
        frame.menu:Hide()
        frame:Hide()
    elseif cfg.shown then
        frame:Show()
        frame:SetAlpha(cfg.mouseoverOnly and 0 or 1)
        if cfg.mouseoverOnly then frame.menu:Hide() end
    else
        frame.menu:Hide()
        frame:Hide()
    end
end
