---------------------------------------------------------------------------
-- PugzRaidTools - Floating Group List
-- Moveable, lockable frame that shows composition names as click-to-swap
-- buttons. Left-click applies group membership quickly; Shift + Left Click
-- also sorts exact positions. Right-click prints the composition name.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local LINE_H = 20
local PAD    = 4
local MIN_WIDTH = 70
local MIN_ROW_HEIGHT = 14

local function IsMouseOverFrame(frame)
    if not frame or not frame:IsShown() then return false end
    if MouseIsOver then return MouseIsOver(frame) end
    if frame.IsMouseOver then return frame:IsMouseOver() end
    return false
end

local function FadeListTo(frame, alpha)
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

-- Toggle-button colour states (green = on, red = off)
local COL_ON      = { 0.10, 0.45, 0.10, 0.92 }
local COL_ON_HOV  = { 0.15, 0.62, 0.15, 0.95 }
local COL_OFF     = { 0.45, 0.10, 0.10, 0.92 }
local COL_OFF_HOV = { 0.62, 0.15, 0.15, 0.95 }

---------------------------------------------------------------------------
-- Tooltip (shared)
---------------------------------------------------------------------------
local function AddSortInstructions()
    GameTooltip:AddLine(
        "|cff59ff8cLeft Click|r - Fast group sort.",
        1, 1, 1)
    GameTooltip:AddLine(
        "|cff73cfffShift + Left Click|r - Exact position sort.",
        1, 1, 1)
end

local function PositionTooltipOutsideList()
    local frame = PRT.floatingFrame
    if not frame or not frame:IsShown() then return end

    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom then return end

    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local tooltipWidth = GameTooltip:GetWidth()
    local tooltipHeight = GameTooltip:GetHeight()
    local gap = 8
    local spaces = {
        right = screenWidth - right,
        left = left,
        top = screenHeight - top,
        bottom = bottom,
    }

    local side
    if spaces.right >= tooltipWidth + gap or spaces.left >= tooltipWidth + gap then
        side = spaces.right >= tooltipWidth + gap
            and (spaces.left < tooltipWidth + gap or spaces.right >= spaces.left)
            and "right" or "left"
    elseif spaces.top >= tooltipHeight + gap or spaces.bottom >= tooltipHeight + gap then
        side = spaces.top >= tooltipHeight + gap
            and (spaces.bottom < tooltipHeight + gap or spaces.top >= spaces.bottom)
            and "top" or "bottom"
    else
        local horizontalFit = math.max(spaces.right, spaces.left) / math.max(1, tooltipWidth)
        local verticalFit = math.max(spaces.top, spaces.bottom) / math.max(1, tooltipHeight)
        if horizontalFit >= verticalFit then
            side = spaces.right >= spaces.left and "right" or "left"
        else
            side = spaces.top >= spaces.bottom and "top" or "bottom"
        end
    end

    GameTooltip:ClearAllPoints()
    if side == "right" or side == "left" then
        local tooltipPoint = side == "right" and "TOPLEFT" or "TOPRIGHT"
        local framePoint = side == "right" and "TOPRIGHT" or "TOPLEFT"
        local x = side == "right" and gap or -gap
        if top >= tooltipHeight + gap then
            GameTooltip:SetPoint(tooltipPoint, frame, framePoint, x, 0)
        else
            tooltipPoint = side == "right" and "BOTTOMLEFT" or "BOTTOMRIGHT"
            framePoint = side == "right" and "BOTTOMRIGHT" or "BOTTOMLEFT"
            GameTooltip:SetPoint(tooltipPoint, frame, framePoint, x, 0)
        end
    else
        local tooltipPoint = side == "top" and "BOTTOMLEFT" or "TOPLEFT"
        local framePoint = side == "top" and "TOPLEFT" or "BOTTOMLEFT"
        local y = side == "top" and gap or -gap
        if screenWidth - left >= tooltipWidth + gap then
            GameTooltip:SetPoint(tooltipPoint, frame, framePoint, 0, y)
        else
            tooltipPoint = side == "top" and "BOTTOMRIGHT" or "TOPRIGHT"
            framePoint = side == "top" and "TOPRIGHT" or "BOTTOMRIGHT"
            GameTooltip:SetPoint(tooltipPoint, frame, framePoint, 0, y)
        end
    end
end

local function ShowPositionedTooltip()
    GameTooltip:Show()
    PositionTooltipOutsideList()
end

local function ShowCompTooltip(btn, compName)
    local comp = PRT:GetComp(compName)
    if not comp then return end

    local rosterSet, pretty = {}, {}
    for _, w in ipairs(comp.roster or {}) do
        local k = PRT:GetPlayerIdentityKey(w)
        if k ~= "" then
            rosterSet[k] = true
            if not pretty[k] then pretty[k] = PRT.Trim(w) end
        end
    end

    local raid = PRT.GetRaidRoster()

    local missing, extra = {}, {}
    for k, p in pairs(pretty) do
        if not raid[k] then missing[#missing + 1] = p end
    end
    for k, info in pairs(raid) do
        if not rosterSet[k] then
            extra[#extra + 1] = {
                name = info.displayName or info.name,
                group = info.subgroup or 0,
                classFile = info.classFile,
            }
        end
    end
    table.sort(missing)
    table.sort(extra, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)

    GameTooltip:SetOwner(btn, "ANCHOR_NONE")
    GameTooltip:ClearLines()

    if #missing == 0 and #extra == 0 then
        GameTooltip:AddLine(compName, 1, 1, 1)
        GameTooltip:AddLine("All roster members present.", 0.6, 1, 0.6)
        AddSortInstructions()
        ShowPositionedTooltip()
        return
    end

    GameTooltip:AddLine(compName, 1, 1, 1)
    GameTooltip:AddDoubleLine("Missing", "Not in Roster", 1, 0.3, 0.3, 1, 1, 0.3)
    local longest = math.max(#missing, #extra)
    local cap = math.min(longest, 12)
    for i = 1, cap do
        local left = missing[i] or "-"
        local right = "-"
        local rr, rg, rb = 1, 1, 1
        if extra[i] then
            right = ("%s (G%d)"):format(extra[i].name, extra[i].group)
            rr, rg, rb = PRT.GetClassColor(extra[i].classFile)
        end
        GameTooltip:AddDoubleLine(left, right, 1, 1, 1, rr, rg, rb)
    end
    if longest > cap then
        GameTooltip:AddDoubleLine("...", "...", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
    end
    AddSortInstructions()
    ShowPositionedTooltip()
end

---------------------------------------------------------------------------
-- Toggle-button state refresh
-- Sets each button's background colour and _active flag to match the DB.
-- Called from UpdateFloatingList and from each button's own OnClick.
---------------------------------------------------------------------------
local function UpdateToggleButtons()
    local f = PRT.floatingFrame
    if not f then return end
    local db = PRT:GetDB()

    local function Apply(btn, active)
        btn._active = active
        local c = active and COL_ON or COL_OFF
        if btn._bgTex then
            btn._bgTex:SetColorTexture(c[1], c[2], c[3], c[4])
        end
    end

    if f.gasBtn then Apply(f.gasBtn, db.autoSwap.enabled) end
    if f.pamBtn then Apply(f.pamBtn, db.autoMark.enabled) end
end

---------------------------------------------------------------------------
-- Toggle-button factory
-- Creates a styled on/off button that is visually part of the floating
-- frame.  Drag is forwarded to the parent frame so the widget stays
-- movable even when the user drags across a toggle button.
---------------------------------------------------------------------------
local function MakeToggleButton(f, label, onClickFn)
    local btn = CreateFrame("Button", nil, f)
    btn:SetHeight(LINE_H)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    -- Background (colour set by UpdateToggleButtons; placeholder here)
    W.AddBackground(btn, 0, 0, 0, 0)

    -- Label
    local lbl = W.CreateLabel(btn, label, PRT.FONT_SIZE, 1, 1, 1)
    lbl:SetPoint("CENTER")
    btn.label = lbl

    -- State-aware hover: read _active at hover-time so colour is always correct
    btn:SetScript("OnEnter", function(self)
        local c = self._active and COL_ON_HOV or COL_OFF_HOV
        if self._bgTex then self._bgTex:SetColorTexture(c[1], c[2], c[3], c[4]) end
    end)
    btn:SetScript("OnLeave", function(self)
        local c = self._active and COL_ON or COL_OFF
        if self._bgTex then self._bgTex:SetColorTexture(c[1], c[2], c[3], c[4]) end
    end)

    btn:SetScript("OnClick", function()
        onClickFn()
        UpdateToggleButtons()
        if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
        GameTooltip:Hide()
    end)

    -- Forward drag to the floating frame (mirrors comp-button behaviour)
    btn:SetScript("OnDragStart", function()
        local db = PRT:GetDB()
        if not db.floatingList.locked then f:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local db = PRT:GetDB()
        local point, _, relPoint, x, y = f:GetPoint()
        db.floatingList.point    = point
        db.floatingList.relPoint = relPoint
        db.floatingList.x        = x
        db.floatingList.y        = y
    end)

    return btn
end

local function AttachFeatureTooltip(btn, title, isEnabledFn)
    W.AttachTooltip(btn, {
        anchor = "ANCHOR_LEFT",
        title = title,
        titleColor = { PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1 },
        getLines = function()
            local enabled = isEnabledFn()
            if enabled then
                return { { "Enabled", 0.35, 1.0, 0.35, true } }
            end
            return { { "Disabled", 1.0, 0.35, 0.35, true } }
        end,
    })
end

---------------------------------------------------------------------------
-- Create / Init
---------------------------------------------------------------------------
function PRT:InitFloatingList()
    if self.floatingFrame then return end

    local f = CreateFrame("Frame", "PugzRaidToolsFloatingList", UIParent)
    f:SetSize(140, LINE_H + PAD * 2)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")

    W.AddBackground(f, 0, 0, 0, 0.7)
    W.AddBorders(f, PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.6)

    -- drag support (moveable)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local db = PRT:GetDB()
        if not db.floatingList.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = PRT:GetDB()
        local point, _, relPoint, x, y = self:GetPoint()
        db.floatingList.point    = point
        db.floatingList.relPoint = relPoint
        db.floatingList.x        = x
        db.floatingList.y        = y
    end)
    f:SetScript("OnUpdate", function(self, elapsed)
        self._mouseoverElapsed = (self._mouseoverElapsed or 0) + elapsed
        if self._mouseoverElapsed < 0.05 then return end
        self._mouseoverElapsed = 0

        local cfg = PRT:GetDB().floatingList
        if not cfg.mouseoverOnly then return end
        local isOver = IsMouseOverFrame(self)
            or IsMouseOverFrame(self.profileMenu)
        if isOver then
            self._mouseoverLeaveAt = nil
            if not self._mouseoverActive then
                self._mouseoverActive = true
                FadeListTo(self, 1)
            end
        elseif self._mouseoverActive then
            self._mouseoverLeaveAt = self._mouseoverLeaveAt
                or (GetTime() + 0.12)
            if GetTime() >= self._mouseoverLeaveAt then
                self._mouseoverLeaveAt = nil
                self._mouseoverActive = false
                if self.profileMenu then self.profileMenu:Hide() end
                FadeListTo(self, 0)
            end
        end
    end)

    f.buttons = {}

    ---------------------------------------------------------------------------
    -- Separator between comp list and toggle buttons
    ---------------------------------------------------------------------------
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.5)
    f.toggleSep = sep

    ---------------------------------------------------------------------------
    -- GAS — Group Auto Swap toggle
    ---------------------------------------------------------------------------
    f.gasBtn = MakeToggleButton(f, "GAS", function()
        local db = PRT:GetDB()
        db.autoSwap.enabled = not db.autoSwap.enabled
        PRT.Print("Auto Swap " .. (db.autoSwap.enabled and "enabled" or "disabled") .. ".")
        if PRT.UpdateAutoSwapListeners then PRT:UpdateAutoSwapListeners() end
        if PRT.UpdateMinimapIconTint   then PRT:UpdateMinimapIconTint()   end
        if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("autoswap") end
    end)
    AttachFeatureTooltip(f.gasBtn, "Group Auto Swapping", function()
        return PRT:GetDB().autoSwap.enabled
    end)

    ---------------------------------------------------------------------------
    -- PAM — Player Auto Marking toggle
    ---------------------------------------------------------------------------
    f.pamBtn = MakeToggleButton(f, "PAM", function()
        local db = PRT:GetDB()
        db.autoMark.enabled = not db.autoMark.enabled
        PRT.Print("Auto Marking " .. (db.autoMark.enabled and "enabled" or "disabled") .. ".")
        if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
        if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("automark") end
    end)
    AttachFeatureTooltip(f.pamBtn, "Player Auto Marking", function()
        return PRT:GetDB().autoMark.enabled
    end)

    self.floatingFrame = f

    self:RefreshFloatingList()
    self:UpdateFloatingList()
end

---------------------------------------------------------------------------
-- Rebuild buttons from current compositions
---------------------------------------------------------------------------
function PRT:RefreshFloatingList()
    local f = self.floatingFrame
    if not f then return end

    local db = self:GetDB()
    local fl = db.floatingList
    local order = self:GetCompOrder()

    -- hide old buttons
    for _, btn in ipairs(f.buttons) do btn:Hide() end

    local fontSize = fl.fontSize or 14
    local outline  = fl.fontOutline or "OUTLINE"
    local textMode = fl.textMode or "expand"
    if textMode == "wrap" then
        textMode = "truncate"
        fl.textMode = textMode
    end
    local textWidth = math.max(MIN_WIDTH,
        math.min(700, tonumber(fl.width) or tonumber(fl.textWidth) or 180))
    local rowHeight = math.max(MIN_ROW_HEIGHT,
        math.min(90, tonumber(fl.rowHeight) or LINE_H))
    local profileEmbedded = db.profileFloat
        and db.profileFloat.embedInGroupList and f.profileButton
    local profilePosition = db.profileFloat
        and db.profileFloat.embeddedPosition == "bottom" and "bottom" or "top"
    local profileAtTop = profileEmbedded and profilePosition == "top"
    local profileAtBottom = profileEmbedded and profilePosition == "bottom"
    local topProfileRows = profileAtTop and 1 or 0
    local bottomProfileRows = profileAtBottom and 1 or 0
    local fcr, fcg, fcb = PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3]
    if fl.fontColor then fcr, fcg, fcb = fl.fontColor[1], fl.fontColor[2], fl.fontColor[3] end
    local maxW = 60

    fl.width = textWidth
    fl.textWidth = textWidth
    fl.rowHeight = rowHeight

    for i, compName in ipairs(order) do
        local btn = f.buttons[i]
        if not btn then
            btn = W.CreateSelectableButton(f, "", {
                width = 60,
                height = LINE_H,
                labelPoint = { "LEFT", 6, 0 },
                justifyH = "LEFT",
                bgColor = { 0, 0, 0, 0 },
                borderColor = { 0, 0, 0, 0 },
                textColor = { fcr, fcg, fcb, 1 },
                hoverAnimation = "MRT",
                hoverAnimationHeight = LINE_H,
            })

            btn:HookScript("OnEnter", function(self)
                ShowCompTooltip(self, self.compName)
            end)
            btn:HookScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    PRT.Print(("Dump: %s"):format(self.compName))
                    return
                end
                if IsShiftKeyDown() then
                    PRT:RequestReorder(self.compName, true)
                else
                    PRT:RequestReorder(self.compName, false)
                end
            end)

            -- Buttons cover the whole frame, so forward drag to the parent frame.
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function()
                local db = PRT:GetDB()
                if not db.floatingList.locked then
                    f:StartMoving()
                end
            end)
            btn:SetScript("OnDragStop", function()
                f:StopMovingOrSizing()
                local db = PRT:GetDB()
                local point, _, relPoint, x, y = f:GetPoint()
                db.floatingList.point    = point
                db.floatingList.relPoint = relPoint
                db.floatingList.x        = x
                db.floatingList.y        = y
            end)

            f.buttons[i] = btn
        end

        btn.compName = compName
        btn.label:SetFont(PRT.FONT, fontSize, outline)
        btn.label:SetText(compName)
        btn.label:SetTextColor(fcr, fcg, fcb, 1)

        local w = btn.label:GetStringWidth() + 12
        if w > maxW then maxW = w end
    end

    if profileEmbedded then
        f.profileButton.label:SetFont(PRT.FONT, fontSize, outline)
        local activeProfileLabel =
            "Profile: " .. (db.prtProfiles.activeProfile or "")
        f.profileButton.label:SetText(activeProfileLabel)
        maxW = math.max(maxW, f.profileButton.label:GetStringWidth() + 28)
        for _, profile in ipairs(db.prtProfiles.profiles or {}) do
            f.profileButton.label:SetText(profile.name or "")
            maxW = math.max(maxW, f.profileButton.label:GetStringWidth() + 28)
        end
        f.profileButton.label:SetText(activeProfileLabel)
    end

    local frameWidth = textMode == "expand"
        and math.max(textWidth, maxW + PAD * 2) or textWidth
    if not profileEmbedded and f.profileButton then
        f.profileButton:Hide()
        if f.profileMenu then f.profileMenu:Hide() end
    end

    for i, compName in ipairs(order) do
        local btn = f.buttons[i]
        btn:SetHeight(rowHeight)
        if btn.SetHoverAnimationHeight then
            btn:SetHoverAnimationHeight(rowHeight)
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD,
            -(PAD + (topProfileRows + i - 1) * rowHeight))
        btn:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        W.ApplyTextOverflow(btn.label, compName, {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = 8,
            width = math.max(1, frameWidth - PAD * 2 - 10),
            height = rowHeight,
            outline = outline,
            setWidth = false,
        })
        btn:Show()
    end

    ---------------------------------------------------------------------------
    -- Position separator and toggle buttons below the comp list
    -- sepY is the distance from the frame top to the bottom of the last comp.
    ---------------------------------------------------------------------------
    local contentRows = #order + topProfileRows
    local sepY   = -(PAD + contentRows * rowHeight) -- top of separator from frame top
    local gasY   = sepY - 1                    -- top of GAS button (1 px below sep)
    local pamY   = gasY - rowHeight            -- top of PAM button
    local profileBottomY = pamY - rowHeight

    f.toggleSep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, sepY)
    f.toggleSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, sepY)

    f.gasBtn:ClearAllPoints()
    f.gasBtn:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, gasY)
    f.gasBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, gasY)
    f.gasBtn:SetHeight(rowHeight)

    f.pamBtn:ClearAllPoints()
    f.pamBtn:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, pamY)
    f.pamBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, pamY)
    f.pamBtn:SetHeight(rowHeight)

    if profileEmbedded then
        local profileY = profileAtTop and -PAD or profileBottomY
        f.profileButton:ClearAllPoints()
        f.profileButton:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, profileY)
        f.profileButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, profileY)
        f.profileButton:SetHeight(rowHeight)
    end

    for _, toggle in ipairs({ f.gasBtn, f.pamBtn }) do
        W.ApplyTextOverflow(toggle.label, toggle == f.gasBtn and "GAS" or "PAM", {
            mode = textMode,
            fontSize = fontSize,
            minFontSize = 6,
            width = math.max(1, frameWidth - PAD * 2 - 10),
            height = rowHeight,
            outline = outline,
            setWidth = false,
        })
    end

    -- Resize frame: comp content + 1px separator + 2 toggle buttons + bottom pad
    local toggleBarH = 1 + rowHeight * 2
    local totalH = (#order + topProfileRows + bottomProfileRows) * rowHeight
        + PAD * 2 + toggleBarH
    f:SetSize(frameWidth, math.max(totalH, rowHeight + toggleBarH))

    if profileEmbedded and self.RefreshEmbeddedProfileSelector then
        self:RefreshEmbeddedProfileSelector(
            frameWidth, rowHeight, fontSize, textMode, outline)
    end
end

---------------------------------------------------------------------------
-- Update visibility, position, scale, alpha, and toggle-button states
---------------------------------------------------------------------------
function PRT:UpdateFloatingList()
    local f = self.floatingFrame
    if not f then return end

    local db = self:GetDB()
    local fl = db.floatingList

    -- visibility
    local shouldShow = fl.shown
    if fl.hideOutsideRaid and not IsInRaid() then
        shouldShow = false
    end
    if shouldShow then
        f:Show()
        if fl.mouseoverOnly then
            local isOver = IsMouseOverFrame(f)
                or IsMouseOverFrame(f.profileMenu)
            f._mouseoverActive = isOver
            f._mouseoverLeaveAt = nil
            f:SetAlpha(isOver and 1 or 0)
        else
            f._mouseoverActive = nil
            f._mouseoverLeaveAt = nil
            f:SetAlpha(1)
        end
    else
        f:Hide()
        if f.profileMenu then f.profileMenu:Hide() end
    end

    -- position
    f:ClearAllPoints()
    f:SetPoint(
        fl.point or "CENTER",
        UIParent,
        fl.relPoint or "CENTER",
        fl.x or 0,
        fl.y or 0
    )

    -- scale
    f:SetScale(fl.scale or 1.0)

    -- background + border alpha
    local bgA = fl.bgAlpha or 0.7
    if f._bgTex then
        f._bgTex:SetColorTexture(0, 0, 0, bgA)
    end
    if f._borders then
        local borderA = bgA > 0.05 and math.min(bgA + 0.15, 0.8) or 0
        for _, b in ipairs(f._borders) do
            b:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], borderA)
        end
    end
    if f.profileMenu and f.profileMenu._bgTex then
        f.profileMenu._bgTex:SetColorTexture(0.02, 0.02, 0.02, bgA)
    end

    -- toggle button colours
    UpdateToggleButtons()
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------
function PRT:ToggleFloatingList()
    local db = self:GetDB()
    db.floatingList.shown = not db.floatingList.shown
    PRT.Print("Floating list " .. (db.floatingList.shown and "shown" or "hidden"))
    self:UpdateFloatingList()
end
