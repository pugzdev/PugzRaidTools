---------------------------------------------------------------------------
-- PugzRaidTools - UI Widgets
-- Dependency-free styled widget factories.  Every widget uses simple
-- ColorTexture backgrounds and border textures so we never rely on
-- BackdropTemplate (which may or may not exist in Classic Era 1.15.x).
---------------------------------------------------------------------------
local _, PRT = ...
PRT.UI = PRT.UI or {}
local W = PRT.UI

---------------------------------------------------------------------------
-- Border / background helpers
---------------------------------------------------------------------------
function W.AddBorders(frame, r, g, b, a, size)
    r, g, b, a = r or 0.25, g or 0.25, b or 0.25, a or 1
    size = size or 1
    if frame._borders then
        for _, t in ipairs(frame._borders) do
            t:SetColorTexture(r, g, b, a)
        end
        return
    end
    frame._borders = {}
    local function mk(...)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local top = mk(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(size)
    local bot = mk(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(size)
    local lft = mk(); lft:SetPoint("TOPLEFT", 0, -size); lft:SetPoint("BOTTOMLEFT", 0, size); lft:SetWidth(size)
    local rgt = mk(); rgt:SetPoint("TOPRIGHT", 0, -size); rgt:SetPoint("BOTTOMRIGHT", 0, size); rgt:SetWidth(size)
    frame._borders = { top, bot, lft, rgt }
end

function W.AddBackground(frame, r, g, b, a)
    if frame._bgTex then
        frame._bgTex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
        return frame._bgTex
    end
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    frame._bgTex = bg
    return bg
end

function W.StyleBox(frame, bgColor, borderColor)
    local bg = bgColor or PRT.C.INPUT_BG
    local bd = borderColor or PRT.C.BORDER
    W.AddBackground(frame, bg[1], bg[2], bg[3], bg[4])
    W.AddBorders(frame, bd[1], bd[2], bd[3], bd[4])
end

---------------------------------------------------------------------------
-- Font string
---------------------------------------------------------------------------
function W.CreateLabel(parent, text, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(PRT.FONT, size or PRT.FONT_SIZE, "")
    fs:SetText(text or "")
    if r then fs:SetTextColor(r, g, b, 1) end
    return fs
end

function W.CreateHeader(parent, text)
    local fs = W.CreateLabel(parent, text, PRT.FONT_SIZE_HEADER)
    fs:SetTextColor(PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1)
    return fs
end

W.TEXT_OVERFLOW_ITEMS = {
    { text = "Expand to fit", value = "expand" },
    { text = "Truncate with ...", value = "truncate" },
    { text = "Shrink to fit", value = "shrink" },
}

W.CONSTRAINED_TEXT_OVERFLOW_ITEMS = {
    { text = "Truncate with ...", value = "truncate" },
    { text = "Shrink to fit", value = "shrink" },
}

local function Utf8CodepointEnds(text)
    local ends = {}
    local index = 1
    local length = #text
    while index <= length do
        local byte = string.byte(text, index) or 0
        local charLength = byte < 0x80 and 1
            or byte < 0xE0 and 2
            or byte < 0xF0 and 3
            or byte < 0xF8 and 4
            or 1
        index = math.min(length + 1, index + charLength)
        ends[#ends + 1] = index - 1
    end
    return ends
end

function W.ApplyTextOverflow(label, text, opts)
    opts = opts or {}
    text = tostring(text or "")
    local mode = opts.mode or "truncate"
    local fontSize = math.max(6, tonumber(opts.fontSize) or PRT.FONT_SIZE)
    local minFontSize = math.max(6, tonumber(opts.minFontSize) or 8)
    local width = math.max(1, tonumber(opts.width) or 1)
    local height = math.max(1, tonumber(opts.height) or fontSize + 4)
    local outline = opts.outline or ""

    label:SetFont(PRT.FONT, fontSize, outline)
    if opts.setWidth ~= false then label:SetWidth(width) end
    label:SetHeight(height)
    if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
    pcall(function() label:SetWordWrap(mode == "wrap") end)
    pcall(function() label:SetNonSpaceWrap(mode == "wrap") end)
    pcall(function()
        label:SetMaxLines(mode == "wrap"
            and math.max(1, math.floor(height / math.max(1, fontSize)))
            or 1)
    end)
    label:SetText(text)

    if mode == "shrink" then
        local fittedSize = fontSize
        while fittedSize > minFontSize and label:GetStringWidth() > width do
            fittedSize = fittedSize - 1
            label:SetFont(PRT.FONT, fittedSize, outline)
        end
        return fittedSize
    end

    if mode ~= "truncate" or label:GetStringWidth() <= width then
        return fontSize
    end

    local suffix = "..."
    local ends = Utf8CodepointEnds(text)
    local low, high = 0, #ends
    local best = suffix
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = middle == 0 and suffix
            or string.sub(text, 1, ends[middle]) .. suffix
        label:SetText(candidate)
        if label:GetStringWidth() <= width then
            best = candidate
            low = middle + 1
        else
            high = middle - 1
        end
    end
    label:SetText(best)
    return fontSize
end

function W.CreateDescription(parent, text, opts)
    opts = opts or {}
    local fs = W.CreateLabel(parent, text or "", opts.fontSize or PRT.FONT_SIZE,
        opts.color and opts.color[1] or 0.72,
        opts.color and opts.color[2] or 0.72,
        opts.color and opts.color[3] or 0.72)
    fs:SetJustifyH(opts.justifyH or "LEFT")
    pcall(function() fs:SetWordWrap(opts.wordWrap ~= false) end)
    pcall(function() fs:SetNonSpaceWrap(opts.nonSpaceWrap or false) end)
    if opts.width then
        fs:SetWidth(opts.width)
    end
    return fs
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
function W.CreateButton(parent, text, width, height, opts)
    opts = opts or {}
    local bgColor    = opts.bgColor or PRT.C.BTN_BG
    local hoverColor = opts.hoverBgColor or PRT.C.BTN_HOVER
    local border     = opts.borderColor or PRT.C.BORDER
    local textColor  = opts.textColor or PRT.C.TITLE

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 120, height or 24)
    W.StyleBox(btn, bgColor, border)

    btn.label = W.CreateLabel(btn, text, opts.fontSize or PRT.FONT_SIZE)
    btn.label:SetPoint("CENTER")
    btn.label:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

    btn:EnableMouse(true)
    btn:RegisterForClicks(opts.clicks or "AnyUp")

    btn:SetScript("OnEnter", function(self)
        if self._bgTex then
            self._bgTex:SetColorTexture(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._bgTex then
            self._bgTex:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        end
    end)

    if opts.onClick then
        btn:SetScript("OnClick", opts.onClick)
    end

    function btn:SetLabel(t)
        self.label:SetText(t)
    end

    return btn
end

function W.CreateRowFrame(parent, height, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or opts.height or 20)
    if opts.width then row:SetWidth(opts.width) end
    return row
end

function W.CreateGhostLabelFrame(parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", opts.name, parent)
    frame:SetSize(opts.width or 100, opts.height or 20)
    frame:SetFrameStrata(opts.strata or "TOOLTIP")
    frame:SetAlpha(opts.alpha or 0.9)
    if opts.hidden ~= false then
        frame:Hide()
    end

    W.AddBackground(frame, (opts.bgColor and opts.bgColor[1]) or 0.08,
        (opts.bgColor and opts.bgColor[2]) or 0.08,
        (opts.bgColor and opts.bgColor[3]) or 0.08,
        (opts.bgColor and opts.bgColor[4]) or 0.95)
    local border = opts.borderColor or { 1, 0.82, 0, 1 }
    W.AddBorders(frame, border[1], border[2], border[3], border[4] or 1)

    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetAllPoints()
    frame.label:SetFont(PRT.FONT, opts.fontSize or PRT.FONT_SIZE, "")
    frame.label:SetJustifyH(opts.justifyH or "CENTER")
    local textColor = opts.textColor or { 1, 0.82, 0, 1 }
    frame.label:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

    return frame
end

function W.CreateRowButton(parent, height, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetHeight(height or opts.height or 20)
    if opts.width then btn:SetWidth(opts.width) end
    btn:EnableMouse(opts.enableMouse ~= false)
    btn:RegisterForClicks(opts.clicks or "AnyUp")

    if opts.dragButton then
        btn:RegisterForDrag(opts.dragButton)
    end

    local bg = opts.bgColor or { 0, 0, 0, 0 }
    W.AddBackground(btn, bg[1], bg[2], bg[3], bg[4])

    local label = W.CreateLabel(btn, opts.text or "", opts.fontSize or PRT.FONT_SIZE)
    label:SetPoint("LEFT", opts.labelLeft or 6, opts.labelY or 0)
    label:SetPoint("RIGHT", opts.labelRight or -4, opts.labelY or 0)
    label:SetJustifyH(opts.justifyH or "LEFT")
    if opts.textColor then
        local color = opts.textColor
        label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    btn.label = label

    function btn:SetLabel(text)
        self.label:SetText(text)
    end

    return btn
end

function W.CreateSelectableButton(parent, text, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(opts.width or 120, opts.height or 24)
    btn:EnableMouse(true)
    btn:RegisterForClicks(opts.clicks or "AnyUp")
    if opts.dragButton then
        btn:RegisterForDrag(opts.dragButton)
    end

    local bg = opts.bgColor or { 0, 0, 0, 0 }
    local hover = opts.hoverBgColor or { bg[1], bg[2], bg[3], math.min((bg[4] or 1) + 0.15, 1) }
    local selected = opts.selectedBgColor or bg
    local border = opts.borderColor or PRT.C.BORDER
    local selectedBorder = opts.selectedBorderColor or border
    local normalText = opts.textColor or { 0.8, 0.8, 0.8, 1 }
    local selectedText = opts.selectedTextColor or (PRT.C.TITLE and { PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 1 } or normalText)

    if opts.noBorder then
        W.AddBackground(btn, bg[1], bg[2], bg[3], bg[4])
    else
        W.StyleBox(btn, bg, border)
    end

    btn.label = W.CreateLabel(btn, text or "", opts.fontSize or PRT.FONT_SIZE)
    if opts.labelPoint then
        btn.label:SetPoint(unpack(opts.labelPoint))
    else
        btn.label:SetPoint("CENTER")
    end
    btn.label:SetJustifyH(opts.justifyH or "CENTER")
    btn.label:SetTextColor(normalText[1], normalText[2], normalText[3], normalText[4] or 1)

    btn._normalBg = bg
    btn._hoverBg = hover
    btn._selectedBg = selected
    btn._normalBorder = border
    btn._selectedBorder = selectedBorder
    btn._normalText = normalText
    btn._selectedText = selectedText
    btn._selected = false
    btn._hasSelectableBorder = not opts.noBorder
    btn._mrtHoverAnimation = opts.hoverAnimation == "MRT"
    btn._mrtHoverHeight = opts.hoverAnimationHeight or btn:GetHeight()

    local function ApplyBackground(self, color)
        self._bgTex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end

    local function EnsureMRTHoverAnimation(self)
        if self._mrtHoverAnim then return end

        local texture = self:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("LEFT", 0, 0)
        texture:SetPoint("RIGHT", 0, 0)
        texture:SetHeight(self._mrtHoverHeight or self:GetHeight())
        texture:SetColorTexture(0.5, 0.5, 0.5, 0.2)

        local anim = self:CreateAnimationGroup()
        anim:SetLooping("NONE")
        local timer = anim:CreateAnimation()
        timer:SetDuration(0.25)
        timer.cR, timer.cG, timer.cB, timer.cA = 0.5, 0.5, 0.5, 0.2
        timer:SetScript("OnUpdate", function(animation)
            local progress = animation:GetProgress()
            local r = animation.fR + (animation.tR - animation.fR) * progress
            local g = animation.fG + (animation.tG - animation.fG) * progress
            local b = animation.fB + (animation.tB - animation.fB) * progress
            local a = animation.fA + (animation.tA - animation.fA) * progress
            animation.cR, animation.cG, animation.cB, animation.cA = r, g, b, a
            texture:SetColorTexture(r, g, b, a)
        end)
        anim:SetScript("OnFinished", function(group)
            if timer.hideOnEnd then
                texture:Hide()
                texture:SetColorTexture(0.5, 0.5, 0.5, 0.2)
                timer.cR, timer.cG, timer.cB, timer.cA = 0.5, 0.5, 0.5, 0.2
            end
        end)

        self._mrtHoverTexture = texture
        self._mrtHoverAnim = anim
        self._mrtHoverTimer = timer
    end

    local function AnimateMRTHover(self, entering)
        EnsureMRTHoverAnimation(self)
        local anim = self._mrtHoverAnim
        local timer = self._mrtHoverTimer
        if anim:IsPlaying() then
            anim:Stop()
        end

        timer.fR, timer.fG, timer.fB, timer.fA = timer.cR, timer.cG, timer.cB, timer.cA
        if entering then
            timer.tR, timer.tG, timer.tB, timer.tA = 1, 1, 1, 0.5
            timer.hideOnEnd = false
        else
            timer.tR, timer.tG, timer.tB, timer.tA = 0.5, 0.5, 0.5, 0
            timer.hideOnEnd = true
        end

        anim:Play()
        self._mrtHoverTexture:Show()
    end

    function btn:ResetHoverAnimation()
        if not self._mrtHoverAnim then return end
        if self._mrtHoverAnim:IsPlaying() then
            self._mrtHoverAnim:Stop()
        end
        self._mrtHoverTexture:Hide()
        self._mrtHoverTexture:SetColorTexture(0.5, 0.5, 0.5, 0.2)
        local timer = self._mrtHoverTimer
        timer.cR, timer.cG, timer.cB, timer.cA = 0.5, 0.5, 0.5, 0.2
        timer.hideOnEnd = false
    end

    function btn:SetHoverAnimationHeight(height)
        self._mrtHoverHeight = math.max(1, tonumber(height) or self:GetHeight())
        if self._mrtHoverTexture then
            self._mrtHoverTexture:SetHeight(self._mrtHoverHeight)
        end
    end

    function btn:SetHoverAnimationSuspended(suspended)
        self._hoverAnimationSuspended = suspended and true or false
        if self._hoverAnimationSuspended then
            self:ResetHoverAnimation()
        end
    end

    function btn:SetSelected(isSelected)
        self._selected = isSelected and true or false
        if self._selected then
            ApplyBackground(self, self._selectedBg)
            if self._hasSelectableBorder then
                W.AddBorders(self, self._selectedBorder[1],
                    self._selectedBorder[2], self._selectedBorder[3],
                    self._selectedBorder[4] or 1)
            end
            self.label:SetTextColor(self._selectedText[1], self._selectedText[2], self._selectedText[3], self._selectedText[4] or 1)
        else
            ApplyBackground(self, self._normalBg)
            if self._hasSelectableBorder then
                W.AddBorders(self, self._normalBorder[1],
                    self._normalBorder[2], self._normalBorder[3],
                    self._normalBorder[4] or 1)
            end
            self.label:SetTextColor(self._normalText[1], self._normalText[2], self._normalText[3], self._normalText[4] or 1)
        end
    end

    btn:SetScript("OnEnter", function(self)
        if self._hoverAnimationSuspended then return end
        if self._mrtHoverAnimation then
            AnimateMRTHover(self, true)
        elseif not self._selected then
            ApplyBackground(self, self._hoverBg)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._hoverAnimationSuspended then return end
        if self._mrtHoverAnimation then
            AnimateMRTHover(self, false)
        elseif self._selected then
            ApplyBackground(self, self._selectedBg)
        else
            ApplyBackground(self, self._normalBg)
        end
    end)

    if opts.onClick then
        btn:SetScript("OnClick", opts.onClick)
    end

    return btn
end

function W.CreateOverlayButton(parent, target, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    if target then
        btn:SetAllPoints(target)
        btn:SetFrameLevel((target:GetFrameLevel() or 1) + (opts.frameLevelOffset or 5))
    end
    btn:EnableMouse(opts.enableMouse ~= false)
    btn:RegisterForClicks(opts.clicks or "LeftButtonUp")
    if opts.dragButton then
        btn:RegisterForDrag(opts.dragButton)
    end
    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    if opts.onDragStart then btn:SetScript("OnDragStart", opts.onDragStart) end
    if opts.onDragStop then btn:SetScript("OnDragStop", opts.onDragStop) end
    if opts.onEnter then btn:SetScript("OnEnter", opts.onEnter) end
    if opts.onLeave then btn:SetScript("OnLeave", opts.onLeave) end
    return btn
end

function W.CreateDeleteButton(parent, onClick, opts)
    opts = opts or {}
    local buttonOpts = opts.buttonOpts or {}
    local btn = W.CreateButton(parent, opts.text or "X", opts.width or 22, opts.height or 20, buttonOpts)
    local color = opts.textColor or PRT.C.RED
    btn.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    if opts.point then
        btn:SetPoint(unpack(opts.point))
    end
    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

function W.CreateCloseButton(parent, onClick, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(opts.size or 20, opts.size or 20)

    local normal = opts.textColor or { 1, 0.3, 0.3 }
    local hover  = opts.hoverTextColor or { 1, 0.6, 0.6 }
    local label  = W.CreateLabel(btn, opts.text or "X", opts.fontSize or PRT.FONT_SIZE,
        normal[1], normal[2], normal[3])
    label:SetPoint("CENTER")

    btn.label = label
    btn:SetScript("OnClick", onClick or function(self) self:GetParent():Hide() end)
    btn:SetScript("OnEnter", function() label:SetTextColor(hover[1], hover[2], hover[3], hover[4] or 1) end)
    btn:SetScript("OnLeave", function() label:SetTextColor(normal[1], normal[2], normal[3], normal[4] or 1) end)

    return btn
end

function W.CreateResizeGrip(parent, onMouseDown, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(opts.size or 16, opts.size or 16)
    if opts.point then
        btn:SetPoint(unpack(opts.point))
    end
    btn:EnableMouse(opts.enableMouse ~= false)

    local tex = btn:CreateTexture(nil, opts.textureLayer or "OVERLAY")
    tex:SetAllPoints()
    local base = opts.color or { 0.45, 0.45, 0.45, 0.5 }
    local hover = opts.hoverColor or { 0.8, 0.8, 0.8, 0.8 }
    tex:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    btn._gripTex = tex

    btn:SetScript("OnEnter", function(self)
        tex:SetColorTexture(hover[1], hover[2], hover[3], hover[4] or 1)
        if opts.onEnter then
            opts.onEnter(self)
        end
    end)
    btn:SetScript("OnLeave", function()
        tex:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    end)
    btn:SetScript("OnMouseDown", function(self, mouseButton)
        if onMouseDown then
            onMouseDown(self, mouseButton)
        end
    end)
    btn:SetScript("OnMouseUp", function(self, mouseButton)
        if opts.onMouseUp then
            opts.onMouseUp(self, mouseButton)
        end
    end)

    return btn
end

function W.CreateColorSwatch(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(opts.size or 20, opts.size or 20)
    if opts.point then
        btn:SetPoint(unpack(opts.point))
    end
    btn:EnableMouse(opts.enableMouse ~= false)

    local border = opts.borderColor or PRT.C.BORDER
    W.AddBorders(btn, border[1], border[2], border[3], border[4] or 1)

    local tex = btn:CreateTexture(nil, opts.textureLayer or "BACKGROUND")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.tex = tex

    function btn:SetColor(r, g, b, a)
        self.tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    if opts.color then
        btn:SetColor(opts.color[1], opts.color[2], opts.color[3], opts.color[4])
    end
    if opts.onClick then
        btn:SetScript("OnClick", opts.onClick)
    end

    return btn
end

function W.AttachTooltip(frame, opts)
    opts = opts or {}
    local anchor = opts.anchor or "ANCHOR_TOP"
    local title = opts.title
    local titleColor = opts.titleColor or { 1, 1, 1, 1 }
    local lineColor = opts.lineColor or { 1, 1, 1, 1 }
    local minWidth = math.max(0, tonumber(opts.minWidth) or 0)
    local lines    = opts.lines    or {}   -- static lines array
    local getLines = opts.getLines         -- optional function() → lines array for dynamic content

    local shouldShow = opts.shouldShow

    local function showTooltip(self)
        if shouldShow and not shouldShow(self) then return end
        GameTooltip:SetOwner(self, anchor)
        GameTooltip:ClearLines()
        if GameTooltip.SetMinimumWidth then
            GameTooltip:SetMinimumWidth(minWidth)
        end
        if title then
            GameTooltip:AddLine(title, titleColor[1], titleColor[2], titleColor[3], titleColor[4] or 1)
        end
        local displayLines = getLines and getLines() or lines
        for _, line in ipairs(displayLines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1] or "", line[2] or 1, line[3] or 1, line[4] or 1, line[5])
            else
                GameTooltip:AddLine(line, lineColor[1], lineColor[2], lineColor[3], lineColor[4] or 1)
            end
        end
        GameTooltip:Show()
    end

    -- HookScript instead of SetScript so tooltip composes with existing
    -- OnEnter/OnLeave handlers (e.g. hover-colour effects on buttons).
    frame:HookScript("OnEnter", showTooltip)
    frame:HookScript("OnLeave", function()
        if GameTooltip.SetMinimumWidth then
            GameTooltip:SetMinimumWidth(0)
        end
        GameTooltip:Hide()
    end)
    return frame
end

function W.AttachColorPicker(swatch, opts)
    opts = opts or {}
    local pickerId = opts.id
    local getColor = opts.getColor
    local setColor = opts.setColor

    local function RaisePicker()
        if ColorPickerFrame.SetToplevel then
            ColorPickerFrame:SetToplevel(true)
        end
        if ColorPickerFrame.SetFrameStrata then
            ColorPickerFrame:SetFrameStrata("TOOLTIP")
        end
        if ColorPickerFrame.SetFrameLevel then
            ColorPickerFrame:SetFrameLevel(1000)
        end
        if ColorPickerFrame.Raise then ColorPickerFrame:Raise() end
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = getColor()
        local prev = { r, g, b }
        PRT._cpId = pickerId

        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = prev
        ColorPickerFrame.func = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            setColor(nr, ng, nb)
        end
        ColorPickerFrame.cancelFunc = function()
            PRT._cpId = nil
            setColor(prev[1], prev[2], prev[3])
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        RaisePicker()
        ColorPickerFrame:Show()
        RaisePicker()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if PRT._cpId == pickerId
                    and ColorPickerFrame:IsShown() then
                    RaisePicker()
                end
            end)
        end
    end)

    ColorPickerFrame:HookScript("OnHide", function()
        if PRT._cpId == pickerId then
            PRT._cpId = nil
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            setColor(nr, ng, nb)
        end
    end)

    return swatch
end

function W.MakeMovable(frame, dragHandle)
    dragHandle = dragHandle or frame
    frame:SetMovable(true)
    frame:EnableMouse(true)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        if frame.BringToFront then
            frame:BringToFront()
        end
        frame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    return dragHandle
end

local function BringPopupToFront(frame, strata)
    if not frame then return end
    local targetStrata = strata or frame._frontStrata or frame:GetFrameStrata() or "TOOLTIP"
    if PRT.BringManagedFrameToFront then
        PRT.BringManagedFrameToFront(frame, targetStrata)
    else
        PRT._widgetPopupSerial = (PRT._widgetPopupSerial or 0) + 1
        if frame.SetToplevel then
            frame:SetToplevel(true)
        end
        if frame.SetFrameStrata then
            frame:SetFrameStrata(targetStrata)
        end
        if frame.SetFrameLevel then
            frame:SetFrameLevel(400 + PRT._widgetPopupSerial)
        end
    end
    if frame.Raise then
        frame:Raise()
    end
end

function W.CreatePopupFrame(name, width, height, opts)
    opts = opts or {}

    local f = CreateFrame("Frame", name, opts.parent or UIParent)
    f:SetSize(width or 400, height or 240)
    f:SetPoint(opts.point or "CENTER")
    f:SetFrameStrata(opts.strata or opts.frontStrata or "TOOLTIP")
    f:SetClampedToScreen(opts.clampedToScreen ~= false)
    f:EnableMouse(true)
    f:Hide()
    f._frontStrata = opts.frontStrata or opts.strata or "TOOLTIP"
    f.BringToFront = function(self)
        BringPopupToFront(self, self._frontStrata)
        local dropdownMenu = self._activeDropdownMenu
        if dropdownMenu and dropdownMenu.IsShown
            and dropdownMenu:IsShown()
            and dropdownMenu._raiseAboveOwner then
            dropdownMenu:_raiseAboveOwner()
        end
    end
    f:HookScript("OnShow", function(self)
        self:BringToFront()
        C_Timer.After(0, function()
            if self and self.IsShown and self:IsShown() then
                self:BringToFront()
            end
        end)
        C_Timer.After(0.05, function()
            if self and self.IsShown and self:IsShown() then
                self:BringToFront()
            end
        end)
    end)
    f:HookScript("OnMouseDown", function(self)
        self:BringToFront()
    end)

    local bg = opts.bgColor or { 0, 0, 0, 0.95 }
    local bd = opts.borderColor or PRT.C.BORDER
    W.AddBackground(f, bg[1], bg[2], bg[3], bg[4] or 1)
    W.AddBorders(f, bd[1], bd[2], bd[3], bd[4] or 1)

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(opts.titleBarHeight or 24)
    f.drag = titleBar
    W.MakeMovable(f, titleBar)
    titleBar:HookScript("OnMouseDown", function()
        f:BringToFront()
    end)

    local titleColor = opts.titleColor or PRT.C.TITLE
    local title = W.CreateLabel(titleBar, opts.title or "", opts.titleFontSize or PRT.FONT_SIZE_HEADER,
        titleColor[1], titleColor[2], titleColor[3])
    title:SetPoint("LEFT", opts.titleX or 10, 0)
    f.titleLabel = title

    if opts.closeButton ~= false then
        local closeBtn = W.CreateCloseButton(titleBar, opts.onClose or function() f:Hide() end, opts.closeButtonOpts)
        closeBtn:SetPoint("RIGHT", opts.closeX or -4, 0)
        f.closeBtn = closeBtn
    end

    if name and opts.addToSpecialFrames ~= false then
        tinsert(UISpecialFrames, name)
    end

    return f
end

-- Reusable centered prompt for comparing configured and current settings.
-- Call popup:SetComparison({ contextText, configuredRows, currentRows,
-- questionText }) each time before showing it. Rows are preformatted strings,
-- so callers may include WoW color codes where appropriate.
function W.CreateSettingsComparisonPopup(name, opts)
    opts = opts or {}

    local applyWidth = opts.applyWidth or 120
    local keepWidth = opts.keepWidth or 140
    local buttonGap = opts.buttonGap or 8
    local popup = W.CreatePopupFrame(name, opts.minWidth or 330, opts.minHeight or 190, {
        parent = opts.parent,
        title = opts.title or "Apply Configured Settings?",
        titleBarHeight = opts.titleBarHeight or 30,
        titleX = opts.titleX or 12,
        strata = opts.strata,
        frontStrata = opts.frontStrata,
        addToSpecialFrames = opts.addToSpecialFrames,
    })
    if opts.centerTitle ~= false then
        popup.titleLabel:ClearAllPoints()
        popup.titleLabel:SetPoint("TOP", popup, "TOP", 0, -(opts.titleTop or 7))
        popup.titleLabel:SetJustifyH("CENTER")
    end

    popup.contextLabel = W.CreateLabel(popup, "", opts.fontSize or PRT.FONT_SIZE, 1, 1, 1)
    popup.contextLabel:SetJustifyH("CENTER")

    local configuredColor = opts.configuredColor or PRT.C.TITLE
    popup.configuredHeader = W.CreateLabel(popup,
        opts.configuredTitle or "Configured settings",
        opts.fontSize or PRT.FONT_SIZE,
        configuredColor[1], configuredColor[2], configuredColor[3])
    popup.configuredHeader:SetJustifyH("CENTER")

    local currentColor = opts.currentColor or { 1, 0.82, 0 }
    popup.currentHeader = W.CreateLabel(popup,
        opts.currentTitle or "Current settings",
        opts.fontSize or PRT.FONT_SIZE,
        currentColor[1], currentColor[2], currentColor[3])
    popup.currentHeader:SetJustifyH("CENTER")

    popup.questionLabel = W.CreateLabel(popup, "",
        opts.fontSize or PRT.FONT_SIZE, 1, 1, 1)
    popup.questionLabel:SetJustifyH("CENTER")

    popup.applyButton = W.CreateButton(popup,
        opts.applyText or "Apply Configured", applyWidth, opts.buttonHeight or 24)
    popup.keepButton = W.CreateButton(popup,
        opts.keepText or "Keep Current Settings", keepWidth, opts.buttonHeight or 24)

    local buttonGroupWidth = applyWidth + buttonGap + keepWidth
    local applyOffset = -(buttonGroupWidth / 2) + (applyWidth / 2)
    popup.applyButton:SetPoint("BOTTOM", popup, "BOTTOM", applyOffset, opts.buttonBottom or 10)
    popup.keepButton:SetPoint("LEFT", popup.applyButton, "RIGHT", buttonGap, 0)

    popup.applyButton:SetScript("OnClick", function()
        local result = true
        if opts.onApply then result = opts.onApply(popup) end
        if result ~= false then popup:Hide() end
    end)
    popup.keepButton:SetScript("OnClick", function()
        if opts.onKeep then opts.onKeep(popup) end
        popup:Hide()
    end)

    popup.configuredRows = {}
    popup.currentRows = {}

    local function EnsureRows(rows, count)
        for index = #rows + 1, count do
            local label = W.CreateLabel(popup, "",
                opts.fontSize or PRT.FONT_SIZE, 0.85, 0.85, 0.85)
            label:SetJustifyH("CENTER")
            rows[index] = label
        end
        for index, label in ipairs(rows) do
            if index <= count then label:Show() else label:Hide() end
        end
    end

    local function PositionCentered(label, y)
        label:ClearAllPoints()
        label:SetPoint("TOP", popup, "TOP", 0, y)
    end

    local function LabelWidth(label)
        if label.GetStringWidth then
            local width = label:GetStringWidth()
            if width and width > 0 then return width end
        end
        local text = label.GetText and label:GetText() or ""
        text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return #text * ((opts.fontSize or PRT.FONT_SIZE) * 0.55)
    end

    function popup:SetComparison(data)
        data = data or {}
        local configuredRows = data.configuredRows or {}
        local currentRows = data.currentRows or {}
        EnsureRows(self.configuredRows, #configuredRows)
        EnsureRows(self.currentRows, #currentRows)

        self.contextLabel:SetText(data.contextText or "")
        self.questionLabel:SetText(data.questionText or "Which settings would you like to use?")
        self.configuredHeader:SetText(data.configuredTitle
            or opts.configuredTitle or "Configured settings")
        self.currentHeader:SetText(data.currentTitle or opts.currentTitle or "Current settings")

        for index, text in ipairs(configuredRows) do
            self.configuredRows[index]:SetText(text)
        end
        for index, text in ipairs(currentRows) do
            self.currentRows[index]:SetText(text)
        end

        local y = -(opts.contentTop or 42)
        PositionCentered(self.contextLabel, y)
        y = y - (opts.contextGap or 22)

        PositionCentered(self.configuredHeader, y)
        y = y - (opts.headerGap or 16)
        for index = 1, #configuredRows do
            PositionCentered(self.configuredRows[index], y)
            y = y - (opts.rowHeight or 16)
        end
        y = y - (opts.sectionGap or 8)

        PositionCentered(self.currentHeader, y)
        y = y - (opts.headerGap or 16)
        for index = 1, #currentRows do
            PositionCentered(self.currentRows[index], y)
            y = y - (opts.rowHeight or 16)
        end
        y = y - (opts.questionGap or 10)

        PositionCentered(self.questionLabel, y)
        y = y - (opts.questionHeight or 20)

        local labels = {
            self.titleLabel,
            self.contextLabel,
            self.configuredHeader,
            self.currentHeader,
            self.questionLabel,
        }
        for index = 1, #configuredRows do labels[#labels + 1] = self.configuredRows[index] end
        for index = 1, #currentRows do labels[#labels + 1] = self.currentRows[index] end

        local widest = buttonGroupWidth + 32
        for _, label in ipairs(labels) do
            local extra = label == self.titleLabel and 58 or 34
            widest = math.max(widest, LabelWidth(label) + extra)
        end

        local width = math.ceil(math.min(opts.maxWidth or 430,
            math.max(opts.minWidth or 330, widest)))
        local height = math.ceil(math.max(opts.minHeight or 190,
            -y + (opts.footerHeight or 38)))
        self:SetSize(width, height)
        return width, height
    end

    return popup
end

function W.CreateNamePopup(name, opts)
    opts = opts or {}

    local width  = opts.width or 340
    local height = opts.height or 118
    local popup = W.CreatePopupFrame(name, width, height, opts)

    popup.titleLbl = popup.titleLabel

    local hasPrompt = opts.prompt ~= false
    if hasPrompt then
        local promptColor = opts.promptColor or { 0.85, 0.85, 0.85 }
        local prompt = W.CreateLabel(popup, opts.prompt or "", opts.promptFontSize or PRT.FONT_SIZE,
            promptColor[1], promptColor[2], promptColor[3])
        prompt:SetPoint("TOPLEFT", opts.promptX or 12, opts.promptY or -32)
        prompt:SetPoint("TOPRIGHT", opts.promptRight or -12, opts.promptY or -32)
        pcall(function() prompt:SetWordWrap(true) end)
        popup.promptLabel = prompt
        popup.promptLbl = prompt
    end

    local edit = W.CreateEditBox(popup, opts.editWidth or (width - 24), opts.editHeight or 22, opts.placeholder)
    local editY = opts.editY or (hasPrompt and -50 or -30)
    edit:SetPoint("TOPLEFT", opts.editX or 12, editY)
    if opts.editFill ~= false then
        edit:SetPoint("TOPRIGHT", opts.editRight or -12, editY)
    end
    popup.editBox = edit
    popup.eb = edit

    local acceptBtn = W.CreateButton(popup, opts.acceptText or "OK", opts.buttonWidth or 80, opts.buttonHeight or 24)
    acceptBtn:SetPoint("BOTTOMLEFT", opts.buttonX or 12, opts.buttonY or 8)
    if opts.acceptFill then
        acceptBtn:SetPoint("BOTTOMRIGHT", opts.buttonRight or -12, opts.buttonY or 8)
    end
    popup.acceptButton = acceptBtn
    popup.okBtn = acceptBtn

    if opts.cancelText ~= false then
        local cancelBtn = W.CreateButton(popup, opts.cancelText or "Cancel", opts.cancelWidth or 80, opts.buttonHeight or 24)
        cancelBtn:SetPoint("LEFT", acceptBtn, "RIGHT", opts.buttonGap or 8, 0)
        cancelBtn:SetScript("OnClick", function() popup:Hide() end)
        popup.cancelButton = cancelBtn
        popup.cancelBtn = cancelBtn
    end

    local function DoAccept()
        local shouldClose = true
        if popup.onAccept then
            shouldClose = popup.onAccept(edit:GetText(), popup)
        end
        if shouldClose ~= false then
            popup:Hide()
        end
    end

    acceptBtn:SetScript("OnClick", DoAccept)
    edit:SetScript("OnEnterPressed", DoAccept)

    function popup:Open(openOpts)
        openOpts = openOpts or {}
        self.titleLabel:SetText(openOpts.title or opts.title or "")
        if self.promptLabel then
            self.promptLabel:SetText(openOpts.prompt or opts.prompt or "")
        end
        self.editBox:SetText(openOpts.text or "")
        self.acceptButton:SetLabel(openOpts.acceptText or opts.acceptText or "OK")
        self.onAccept = openOpts.onAccept or opts.onAccept or self.onAccept
        self:Show()
        self:BringToFront()
        self.editBox:SetFocus()
        if openOpts.highlight then
            self.editBox:HighlightText()
        end
    end

    return popup
end

function W.CreateConfirmPopup(name, opts)
    opts = opts or {}

    local width  = opts.width or 340
    local height = opts.height or 110
    local popup = W.CreatePopupFrame(name, width, height, opts)

    popup.titleLbl = popup.titleLabel

    local messageColor = opts.messageColor or { 0.9, 0.9, 0.9 }
    local message = W.CreateLabel(popup, opts.message or "", opts.messageFontSize or PRT.FONT_SIZE,
        messageColor[1], messageColor[2], messageColor[3])
    message:SetPoint("TOPLEFT", opts.messageX or 12, opts.messageY or -32)
    message:SetPoint("TOPRIGHT", opts.messageRight or -12, opts.messageY or -32)
    pcall(function() message:SetWordWrap(true) end)
    popup.messageLabel = message
    popup.msgLbl = message

    local confirmBtn = W.CreateButton(popup, opts.confirmText or "OK", opts.buttonWidth or 80, opts.buttonHeight or 24)
    confirmBtn:SetPoint("BOTTOMLEFT", opts.buttonX or 12, opts.buttonY or 8)
    if opts.confirmTextColor then
        confirmBtn.label:SetTextColor(opts.confirmTextColor[1], opts.confirmTextColor[2], opts.confirmTextColor[3],
            opts.confirmTextColor[4] or 1)
    end
    popup.confirmButton = confirmBtn

    local cancelBtn = W.CreateButton(popup, opts.cancelText or "Cancel", opts.cancelWidth or 80, opts.buttonHeight or 24)
    cancelBtn:SetPoint("LEFT", confirmBtn, "RIGHT", opts.buttonGap or 8, 0)
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)
    popup.cancelButton = cancelBtn
    popup.cancelBtn = cancelBtn

    local function DoConfirm()
        local shouldClose = true
        if popup.onConfirm then
            shouldClose = popup.onConfirm(popup)
        end
        if shouldClose ~= false then
            popup:Hide()
        end
    end

    confirmBtn:SetScript("OnClick", DoConfirm)

    function popup:Open(openOpts)
        openOpts = openOpts or {}
        self.titleLabel:SetText(openOpts.title or opts.title or "")
        self.messageLabel:SetText(openOpts.message or opts.message or "")
        self.confirmButton:SetLabel(openOpts.confirmText or opts.confirmText or "OK")
        self.onConfirm = openOpts.onConfirm
        self:Show()
        self:BringToFront()
    end

    return popup
end

function W.CreateTextTransferPopup(name, opts)
    opts = opts or {}

    local width  = opts.width or 450
    local height = opts.height or 260
    local popup = W.CreatePopupFrame(name, width, height, opts)

    popup.title = popup.titleLabel

    local instructionColor = opts.instructionColor or { 0.8, 0.8, 0.8 }
    local instruction = W.CreateLabel(popup, opts.instruction or "", opts.instructionFontSize or PRT.FONT_SIZE,
        instructionColor[1], instructionColor[2], instructionColor[3])
    instruction:SetPoint("TOPLEFT", opts.instructionX or 12, opts.instructionY or -30)
    if opts.instructionFill ~= false then
        instruction:SetPoint("TOPRIGHT", opts.instructionRight or -12, opts.instructionY or -30)
    end
    pcall(function() instruction:SetWordWrap(true) end)
    popup.instructionLabel = instruction
    popup.instr = instruction

    local textBox = W.CreateMultiLineEditBox(popup, opts.boxWidth or (width - 24), opts.boxHeight or (height - 100))
    textBox:SetPoint("TOPLEFT", opts.boxX or 12, opts.boxY or -46)
    if opts.boxFill ~= false then
        textBox:SetPoint("TOPRIGHT", opts.boxRight or -12, opts.boxY or -46)
    end
    popup.textBox = textBox
    popup.editBox = textBox

    local actionBtn = W.CreateButton(popup, opts.actionText or "Close", opts.actionWidth or 80,
        opts.buttonHeight or 24)
    actionBtn:SetPoint("BOTTOMLEFT", opts.buttonX or 12, opts.buttonY or 8)
    popup.actionButton = actionBtn
    popup.importBtn = actionBtn

    local cancelText = opts.cancelText
    if cancelText == nil and opts.showCancel then cancelText = "Cancel" end
    if cancelText then
        local cancelBtn = W.CreateButton(popup, cancelText, opts.cancelWidth or 80, opts.buttonHeight or 24)
        cancelBtn:SetPoint("LEFT", actionBtn, "RIGHT", opts.buttonGap or 8, 0)
        cancelBtn:SetScript("OnClick", function() popup:Hide() end)
        popup.cancelButton = cancelBtn
        popup.cancelBtn = cancelBtn
    end

    local function DoAction()
        local shouldClose = true
        if popup.onAction then
            shouldClose = popup.onAction(textBox:GetText(), popup)
        end
        if shouldClose then
            popup:Hide()
        end
    end

    actionBtn:SetScript("OnClick", DoAction)

    function popup:Open(openOpts)
        openOpts = openOpts or {}
        self.titleLabel:SetText(openOpts.title or opts.title or "")
        self.instructionLabel:SetText(openOpts.instruction or opts.instruction or "")
        self.textBox:SetText(openOpts.text or opts.text or "")
        self.actionButton:SetLabel(openOpts.actionText or opts.actionText or "Close")
        self.onAction = openOpts.onAction or opts.onAction
        self:Show()
        self:BringToFront()
        self.textBox.editBox:SetFocus()
        if openOpts.highlight then
            self.textBox.editBox:HighlightText()
        end
    end

    return popup
end

---------------------------------------------------------------------------
-- Checkbox
---------------------------------------------------------------------------
function W.CreateCheckButton(parent, size, onClick, opts)
    opts = opts or {}
    local btn = CreateFrame("CheckButton", opts.name, parent, opts.template or "UICheckButtonTemplate")
    btn:SetSize(size or opts.size or 20, size or opts.size or 20)
    if opts.point then
        btn:SetPoint(unpack(opts.point))
    end
    if onClick then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

function W.CreateCheckbox(parent, text, onClick)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(200, 20)

    local btn = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    btn:SetPoint("LEFT", 0, 0)
    btn:SetSize(24, 24)

    local label = W.CreateLabel(frame, text, PRT.FONT_SIZE, 1, 1, 1)
    label:SetPoint("LEFT", btn, "RIGHT", 4, 0)

    frame.check = btn
    frame.label = label

    function frame:GetChecked() return self.check:GetChecked() end
    function frame:SetChecked(v) self.check:SetChecked(v) end

    if onClick then
        btn:SetScript("OnClick", function(self)
            onClick(self:GetChecked())
        end)
    end

    return frame
end

---------------------------------------------------------------------------
-- EditBox (single line)
---------------------------------------------------------------------------
function W.CreateEditBox(parent, width, height, placeholder)
    local f = CreateFrame("EditBox", nil, parent)
    f:SetSize(width or 180, height or 22)
    f:SetAutoFocus(false)
    f:SetFont(PRT.FONT, PRT.FONT_SIZE, "")
    f:SetTextColor(1, 1, 1, 1)
    f:SetTextInsets(6, 6, 0, 0)
    f:SetMaxLetters(256)

    W.StyleBox(f, PRT.C.INPUT_BG, PRT.C.BORDER)

    if placeholder then
        f._ph = f:CreateFontString(nil, "OVERLAY")
        f._ph:SetFont(PRT.FONT, PRT.FONT_SIZE, "")
        f._ph:SetTextColor(PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3], 0.6)
        f._ph:SetPoint("LEFT", 6, 0)
        f._ph:SetText(placeholder)
        f:SetScript("OnTextChanged", function(self)
            if self._ph then
                self._ph:SetShown(self:GetText() == "")
            end
        end)
    end

    f:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Click anywhere in the field activates it (not just the text area)
    f:SetScript("OnMouseDown", function(self) self:SetFocus() end)

    return f
end

---------------------------------------------------------------------------
-- Deferred refresh guard
--
-- Tracks edit boxes owned by a refreshable panel. Call Defer() before an
-- automatic redraw; if a tracked field is active, the latest callback for
-- that key runs on the next frame after editing ends.
---------------------------------------------------------------------------
function W.CreateDeferredRefreshGuard()
    local guard = {
        _tracked = setmetatable({}, { __mode = "k" }),
        _active = setmetatable({}, { __mode = "k" }),
        _pending = {},
        _pendingOrder = {},
        _flushQueued = false,
    }

    function guard:IsEditing()
        local editing = false
        for editBox in pairs(self._active) do
            if editBox.HasFocus and editBox:HasFocus() then
                editing = true
            else
                self._active[editBox] = nil
            end
        end
        return editing
    end

    function guard:Flush()
        if self:IsEditing() then return end

        local pending = self._pending
        local order = self._pendingOrder
        self._pending = {}
        self._pendingOrder = {}

        for _, key in ipairs(order) do
            local callback = pending[key]
            if callback then callback() end
        end
    end

    function guard:QueueFlush()
        if self._flushQueued then return end
        self._flushQueued = true
        C_Timer.After(0, function()
            guard._flushQueued = false
            guard:Flush()
        end)
    end

    function guard:Track(editBox)
        if not editBox or self._tracked[editBox] then return editBox end
        self._tracked[editBox] = true

        editBox:HookScript("OnEditFocusGained", function(self)
            guard._active[self] = true
        end)
        editBox:HookScript("OnEditFocusLost", function(self)
            guard._active[self] = nil
            guard:QueueFlush()
        end)

        return editBox
    end

    function guard:Defer(key, callback)
        if not callback or not self:IsEditing() then return false end

        key = key or callback
        if not self._pending[key] then
            self._pendingOrder[#self._pendingOrder + 1] = key
        end
        self._pending[key] = callback
        return true
    end

    return guard
end

---------------------------------------------------------------------------
-- Scrollbar helper (shared by CreateMultiLineEditBox & CreateScrollFrame)
-- Attaches a custom thin dark-track + themed-thumb scrollbar to any
-- container/scroll pair.  Returns a table with UpdateRange() and DoScroll().
--
-- opts fields (all optional):
--   barWidth           - scrollbar width in px  (default 8)
--   insetX             - horizontal offset from right edge  (default -1)
--   insetTop           - top offset  (default -1)
--   insetBot           - bottom offset  (default 1)
--   step               - fixed scroll step; nil = proportional to view
--   hookContainerWheel - also hook OnMouseWheel on container  (default false)
---------------------------------------------------------------------------
function W.AttachScrollbar(container, scroll, contentOrEdit, opts)
    opts = opts or {}
    local SB_W     = opts.barWidth  or 8
    local insetX   = opts.insetX    or -1
    local insetTop = opts.insetTop  or -1
    local insetBot = opts.insetBot  or 1

    -- Dark track background
    local trackBg = container:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("TOPRIGHT",    insetX, insetTop)
    trackBg:SetPoint("BOTTOMRIGHT", insetX, insetBot)
    trackBg:SetWidth(SB_W)
    trackBg:SetColorTexture(0.04, 0.04, 0.04, 0.85)

    -- Slider (VERTICAL: val=0 → thumb at TOP, val=max → thumb at BOTTOM)
    local slider = CreateFrame("Slider", nil, container)
    slider:SetPoint("TOPRIGHT",    insetX, insetTop)
    slider:SetPoint("BOTTOMRIGHT", insetX, insetBot)
    slider:SetWidth(SB_W)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:EnableMouseWheel(false)
    slider:EnableMouse(true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3], 0.85)
    thumb:SetSize(SB_W - 2, 28)
    slider:SetThumbTexture(thumb)

    -- Direct mapping: sliderVal == scrollPos
    slider:SetScript("OnValueChanged", function(self, val)
        if self._updating then return end
        scroll:SetVerticalScroll(val)
    end)

    -- Recompute slider range and reposition thumb to match current scroll
    local function UpdateRange()
        local maxScroll = math.max(0, contentOrEdit:GetHeight() - scroll:GetHeight())
        local curScroll = math.max(0, math.min(maxScroll, scroll:GetVerticalScroll()))
        slider._updating = true
        slider:SetMinMaxValues(0, maxScroll)
        slider:SetValue(curScroll)
        slider._updating = false
    end

    -- Mouse wheel: delta=+1 (up) → decrease slider → scroll up
    local fixedStep = opts.step   -- nil means proportional
    local function DoScroll(delta)
        local _, max = slider:GetMinMaxValues()
        local step = fixedStep or math.max(20, scroll:GetHeight() * 0.15)
        slider:SetValue(math.max(0, math.min(max, slider:GetValue() - delta * step)))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)

    if opts.hookContainerWheel then
        container:EnableMouseWheel(true)
        container:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)
    end

    return {
        slider      = slider,
        thumb       = thumb,
        trackBg     = trackBg,
        UpdateRange = UpdateRange,
        DoScroll    = DoScroll,
    }
end

---------------------------------------------------------------------------
-- Multi-line EditBox (scrollable, for large input areas like import/export)
-- Custom thin scrollbar via W.AttachScrollbar.
---------------------------------------------------------------------------
function W.CreateMultiLineEditBox(parent, width, height)
    local SB_W = 8
    width  = width or 400
    height = height or 200

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)
    W.StyleBox(container, PRT.C.INPUT_BG, PRT.C.BORDER)

    local scroll = CreateFrame("ScrollFrame", nil, container)
    scroll:SetPoint("TOPLEFT",     6,          -6)
    scroll:SetPoint("BOTTOMRIGHT", -(SB_W+10),  6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(PRT.FONT, PRT.FONT_SIZE, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetWidth(width - SB_W - 22)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnMouseDown",     function(self) self:SetFocus() end)
    scroll:HookScript("OnMouseDown",  function() edit:SetFocus() end)
    scroll:SetScrollChild(edit)

    -- Scrollbar (fixed 30px step, inset for edit box padding)
    local sb = W.AttachScrollbar(container, scroll, edit, {
        insetX = -2, insetTop = -6, insetBot = 6,
        step = 30,
    })

    -- Recompute slider range whenever editbox grows/shrinks
    edit:HookScript("OnSizeChanged", function() sb.UpdateRange() end)

    container.scroll  = scroll
    container.editBox = edit

    container:SetScript("OnSizeChanged", function(self, w, h)
        if self.editBox then
            self.editBox:SetWidth(math.max(1, w - SB_W - 22))
        end
    end)

    function container:GetText() return self.editBox:GetText() end
    function container:SetText(t) self.editBox:SetText(t or "") end

    return container
end

---------------------------------------------------------------------------
-- TextArea (inline multiline note box — no scrollbar, fills available width)
-- Width is controlled by external anchoring (TOPLEFT/TOPRIGHT).
-- Height is fixed at the given value (default 60).
---------------------------------------------------------------------------
function W.CreateTextArea(parent, height, placeholder)
    height = height or 60
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(height)
    W.StyleBox(container, PRT.C.INPUT_BG, PRT.C.BORDER)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(PRT.FONT, PRT.FONT_SIZE, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetTextInsets(6, 6, 4, 4)
    edit:SetPoint("TOPLEFT",     1, -1)
    edit:SetPoint("BOTTOMRIGHT", -1, 1)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTabPressed",    function(self) self:ClearFocus() end)
    edit:SetScript("OnMouseDown",     function(self) self:SetFocus() end)
    -- Enter confirms the note (strips trailing newline) and saves via OnEditFocusLost
    edit:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        text = text:gsub("\n+$", "")
        self:SetText(text)
        self:ClearFocus()
    end)

    if placeholder then
        local ph = edit:CreateFontString(nil, "OVERLAY")
        ph:SetFont(PRT.FONT, PRT.FONT_SIZE, "")
        ph:SetTextColor(PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3], 0.6)
        ph:SetPoint("TOPLEFT", 6, -4)
        ph:SetText(placeholder)
        edit:HookScript("OnTextChanged", function(self)
            ph:SetShown(self:GetText() == "")
        end)
        edit._ph = ph
    end

    -- Clicking blank space below the text also focuses the edit box
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", function() edit:SetFocus() end)

    container.editBox = edit

    function container:GetText()
        return self.editBox:GetText()
    end
    function container:SetText(t)
        self.editBox:SetText(t or "")
        if self.editBox._ph then
            self.editBox._ph:SetShown(t == nil or t == "")
        end
    end
    function container:SetScript_OnFocusLost(fn)
        self.editBox:SetScript("OnEditFocusLost", fn)
    end
    function container:HighlightText()
        self.editBox:HighlightText()
    end

    return container
end

---------------------------------------------------------------------------
-- Dropdown (custom, no UIDropDownMenu dependency)
---------------------------------------------------------------------------
local DROPDOWN_ROW_HEIGHT = 20
local DROPDOWN_TEXT_COLOR = { 1, 1, 1, 1 }
local DROPDOWN_ROW_BG = { 0.05, 0.05, 0.05, 0 }
local DROPDOWN_CLEAR_BORDER = { 0, 0, 0, 0 }
local DROPDOWN_MENU_BG = { 0.05, 0.05, 0.05, 0.98 }

-- Shared shell for dropdowns and other lightweight popup menus. Feature
-- modules can keep their specialised layout/positioning without duplicating
-- the frame styling and setup used by the standard dropdown.
function W.CreateMenuFrame(parent, opts)
    opts = opts or {}
    local menu = CreateFrame("Frame", opts.name, parent or UIParent)
    if opts.width or opts.height then
        menu:SetSize(opts.width or 1, opts.height or 1)
    end
    if opts.strata then menu:SetFrameStrata(opts.strata) end
    if opts.frameLevel then menu:SetFrameLevel(opts.frameLevel) end
    if opts.clampedToScreen ~= nil then
        menu:SetClampedToScreen(opts.clampedToScreen)
    end
    if opts.enableMouse ~= nil then menu:EnableMouse(opts.enableMouse) end
    W.StyleBox(
        menu,
        opts.bgColor or DROPDOWN_MENU_BG,
        opts.borderColor or PRT.C.BORDER)
    if opts.hidden ~= false then menu:Hide() end
    return menu
end

-- Standard dropdown items support text, value, textColor, icon, iconSize,
-- iconTexCoord, and iconColor. Plain values are also accepted and displayed
-- with tostring(value).
local function DropdownItemValue(item)
    if type(item) == "table" then return item.value end
    return item
end

local function DropdownItemText(item)
    if type(item) == "table" then
        if item.text ~= nil then return tostring(item.text) end
        if item.label ~= nil then return tostring(item.label) end
        return tostring(item.value)
    end
    return tostring(item)
end

local function DropdownItemOption(item, key)
    return type(item) == "table" and item[key] or nil
end

local function ApplyDropdownItemIcon(
        container, label, item, leftInset, rightInset, defaultSize)
    local texturePath = DropdownItemOption(item, "icon")
    label:ClearAllPoints()
    if texturePath then
        local icon = container._dropdownItemIcon
        if not icon then
            icon = container:CreateTexture(nil, "OVERLAY")
            container._dropdownItemIcon = icon
        end
        local iconSize = math.max(1,
            tonumber(DropdownItemOption(item, "iconSize"))
                or defaultSize or 14)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", leftInset, 0)
        icon:SetSize(iconSize, iconSize)
        icon:SetTexture(texturePath)
        local texCoord = DropdownItemOption(item, "iconTexCoord")
        if texCoord then
            icon:SetTexCoord(unpack(texCoord))
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end
        local iconColor = DropdownItemOption(item, "iconColor")
        if iconColor then
            icon:SetVertexColor(
                iconColor[1], iconColor[2], iconColor[3],
                iconColor[4] or 1)
        else
            icon:SetVertexColor(1, 1, 1, 1)
        end
        icon:Show()
        label:SetPoint("LEFT", leftInset + iconSize + 4, 0)
    else
        local icon = container._dropdownItemIcon
        if icon then icon:Hide() end
        label:SetPoint("LEFT", leftInset, 0)
    end
    label:SetPoint("RIGHT", rightInset, 0)
    label:SetJustifyH("LEFT")
end

-- Portable raid-marker item builder for any dropdown or other menu that uses
-- the standard item contract above.
function W.BuildRaidTargetDropdownItems(markIcons, opts)
    opts = opts or {}
    local result = {}
    for _, marker in ipairs(markIcons or {}) do
        local markerId = tonumber(marker.id) or 0
        if markerId > 0 then
            result[#result + 1] = {
                text = marker.name or tostring(markerId),
                value = markerId,
                icon = string.format(
                    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d",
                    markerId),
                iconSize = opts.iconSize or 14,
                iconTexCoord = opts.iconTexCoord,
            }
        elseif opts.includeClear ~= false then
            result[#result + 1] = {
                text = opts.clearText or marker.name or "Clear mark",
                value = markerId,
                textColor = opts.clearTextColor,
            }
        end
    end
    return result
end

local function FindDropdownMenuOwnerAndLevel(menu)
    local dropdown = menu.ownerDropdown
    if not dropdown then return nil, 0 end
    local owner
    local highestLevel = dropdown.GetFrameLevel
        and dropdown:GetFrameLevel() or 0
    local current = dropdown.GetParent and dropdown:GetParent() or nil
    while current and current ~= UIParent do
        if current.GetFrameLevel then
            highestLevel = math.max(
                highestLevel, current:GetFrameLevel())
        end
        if not owner and current.BringToFront then owner = current end
        current = current.GetParent and current:GetParent() or nil
    end
    return owner, highestLevel
end

local function RaiseDropdownMenu(menu)
    if not menu:IsShown() then return end
    local owner, highestLevel = FindDropdownMenuOwnerAndLevel(menu)
    menu._popupOwner = owner
    if owner then
        local previous = owner._activeDropdownMenu
        if previous and previous ~= menu
            and previous.IsShown and previous:IsShown() then
            previous:Hide()
        end
        owner._activeDropdownMenu = menu
    end
    if menu.SetToplevel then menu:SetToplevel(true) end
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(highestLevel + 100)
    if menu.Raise then menu:Raise() end
end

local function DropdownRowClicked(row)
    local dropdown = row._dropdown
    local item = row._dropdownItem
    if not dropdown or not item then return end
    if DropdownItemOption(item, "disabled") then return end

    local value = DropdownItemValue(item)
    local text = DropdownItemText(item)
    dropdown:SetSelected(value)
    dropdown.menu:Hide()
    if dropdown.onSelect then
        dropdown.onSelect(value, text, item, dropdown)
    end
end

local function RefreshDropdownMenu(menu)
    local dropdown = menu.ownerDropdown
    if not dropdown then return end
    local opts = dropdown._dropdownOptions
    local rowHeight = math.max(1,
        tonumber(opts.rowHeight) or DROPDOWN_ROW_HEIGHT)
    local hoverAnimation = opts.hoverAnimation
    if hoverAnimation == nil then hoverAnimation = "MRT" end
    local textColorFallback = opts.textColor or DROPDOWN_TEXT_COLOR

    menu:SetWidth(opts.menuWidth or dropdown:GetWidth())
    for _, row in ipairs(menu.rows) do row:Hide() end

    local height = 0
    for index, item in ipairs(dropdown.items) do
        local row = menu.rows[index]
        if not row then
            row = W.CreateSelectableButton(menu, "", {
                width = opts.menuWidth or dropdown:GetWidth(),
                height = rowHeight,
                bgColor = DROPDOWN_ROW_BG,
                borderColor = DROPDOWN_CLEAR_BORDER,
                noBorder = true,
                textColor = DROPDOWN_TEXT_COLOR,
                selectedTextColor = DROPDOWN_TEXT_COLOR,
                labelPoint = { "LEFT", 8, 0 },
                justifyH = "LEFT",
                hoverAnimation = hoverAnimation,
                hoverAnimationHeight = rowHeight,
            })
            row.text = row.label
            row:SetScript("OnClick", DropdownRowClicked)
            menu.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -height)
        row:SetPoint("TOPRIGHT", 0, -height)
        row:SetHeight(rowHeight)
        row._mrtHoverAnimation = hoverAnimation == "MRT"
        row:SetHoverAnimationHeight(rowHeight)
        row._dropdown = dropdown
        row._dropdownItem = item
        row.value = DropdownItemValue(item)
        row.text:SetText(DropdownItemText(item))

        local textColor = DropdownItemOption(item, "textColor")
            or textColorFallback
        row._normalText = textColor
        row._selectedText = textColor
        row:SetSelected(false)
        ApplyDropdownItemIcon(
            row, row.text, item, 8, -8, opts.iconSize or 14)
        row:ResetHoverAnimation()

        local disabled = DropdownItemOption(item, "disabled")
        if disabled then
            row:Disable()
            row:SetAlpha(0.45)
        else
            row:Enable()
            row:SetAlpha(1)
        end
        row:Show()
        height = height + rowHeight
    end
    menu:SetHeight(math.max(height, 1))
end

local function DropdownMenuShown(menu)
    RaiseDropdownMenu(menu)
    C_Timer.After(0, menu._deferredRaise)
    C_Timer.After(0.05, menu._deferredRaise)
    RefreshDropdownMenu(menu)
end

local function DropdownMenuHidden(menu)
    local owner = menu._popupOwner
    if owner and owner._activeDropdownMenu == menu then
        owner._activeDropdownMenu = nil
    end
    menu._popupOwner = nil
    menu.ownerDropdown = nil
end

-- A menu can be shared by many dropdown controls. This is useful for pooled
-- table cells (such as Target Marks) and avoids retaining one menu and row
-- collection per control.
function W.CreateDropdownMenu(opts)
    opts = opts or {}
    local menu = W.CreateMenuFrame(opts.parent or UIParent, {
        name = opts.name,
        strata = opts.strata or "TOOLTIP",
        clampedToScreen = opts.clampedToScreen ~= false,
        bgColor = opts.bgColor or DROPDOWN_MENU_BG,
        borderColor = opts.borderColor or PRT.C.BORDER,
    })
    menu.rows = {}
    menu._deferredRaise = function()
        if menu.IsShown and menu:IsShown() then RaiseDropdownMenu(menu) end
    end
    menu._raiseAboveOwner = RaiseDropdownMenu
    menu:SetScript("OnShow", DropdownMenuShown)
    menu:SetScript("OnHide", DropdownMenuHidden)
    return menu
end

local function DropdownMouseUp(dropdown)
    local menu = dropdown.menu
    if menu:IsShown() then
        if menu.ownerDropdown == dropdown then
            menu:Hide()
            return
        end
        menu:Hide()
    end

    if dropdown.onBeforeOpen then dropdown.onBeforeOpen(dropdown) end
    menu.ownerDropdown = dropdown
    menu:ClearAllPoints()
    local positionMenu = dropdown._dropdownOptions.positionMenu
    if positionMenu then
        positionMenu(dropdown, menu)
    else
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -1)
    end
    menu:Show()
end

local function DropdownHidden(dropdown)
    local menu = dropdown.menu
    if menu and menu.ownerDropdown == dropdown then menu:Hide() end
end

function W.CreateDropdown(parent, width, items, onSelect, opts)
    opts = opts or {}
    local dd = CreateFrame("Frame", nil, parent)
    dd:SetSize(width or 180, opts.height or 24)
    W.StyleBox(
        dd,
        opts.bgColor or PRT.C.INPUT_BG,
        opts.borderColor or PRT.C.BORDER)

    dd.selectedValue = nil
    dd.items = items or {}
    dd.onSelect = onSelect
    dd.onBeforeOpen = opts.onBeforeOpen
    dd._dropdownOptions = opts

    dd.label = W.CreateLabel(
        dd, "", opts.fontSize or PRT.FONT_SIZE, 1, 1, 1)
    ApplyDropdownItemIcon(dd, dd.label, nil, 8, -20, opts.iconSize or 14)

    dd.arrow = W.CreateLabel(
        dd, opts.arrowText or "v", opts.fontSize or PRT.FONT_SIZE,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    dd.arrow:SetPoint("RIGHT", -6, 0)

    dd.menu = opts.sharedMenu or W.CreateDropdownMenu(opts.menuOptions)

    dd:EnableMouse(true)
    dd:SetScript("OnMouseUp", DropdownMouseUp)
    dd:SetScript("OnHide", DropdownHidden)

    function dd:SetSelected(value, text)
        self.selectedValue = value
        local selectedItem
        for _, item in ipairs(self.items) do
            if DropdownItemValue(item) == value then
                selectedItem = item
                break
            end
        end
        if text ~= nil then
            self.label:SetText(tostring(text))
        elseif selectedItem then
            self.label:SetText(DropdownItemText(selectedItem))
        else
            self.label:SetText(tostring(value))
        end
        local textColor = DropdownItemOption(selectedItem, "textColor")
            or opts.textColor or DROPDOWN_TEXT_COLOR
        self.label:SetTextColor(
            textColor[1], textColor[2], textColor[3],
            textColor[4] or 1)
        ApplyDropdownItemIcon(
            self, self.label, selectedItem, 8, -20,
            opts.iconSize or 14)
    end

    function dd:GetSelected()
        return self.selectedValue
    end

    function dd:GetSelectedItem()
        for _, item in ipairs(self.items) do
            if DropdownItemValue(item) == self.selectedValue then
                return item
            end
        end
    end

    function dd:SetItems(newItems)
        self.items = newItems or {}
        if self.selectedValue ~= nil then
            self:SetSelected(self.selectedValue)
        end
        if self.menu:IsShown() and self.menu.ownerDropdown == self then
            RefreshDropdownMenu(self.menu)
        end
    end

    function dd:SetOnSelect(callback)
        self.onSelect = callback
    end

    function dd:SetOnBeforeOpen(callback)
        self.onBeforeOpen = callback
    end

    function dd:OpenMenu()
        if not self.menu:IsShown()
            or self.menu.ownerDropdown ~= self then
            DropdownMouseUp(self)
        end
    end

    function dd:CloseMenu()
        if self.menu.ownerDropdown == self then self.menu:Hide() end
    end

    return dd
end

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------
function W.CreateSlider(parent, label, minVal, maxVal, step, width, onChanged)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or 200, 40)

    local title = W.CreateLabel(frame, label, PRT.FONT_SIZE, PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    title:SetPoint("TOPLEFT", 0, 0)

    local valText = W.CreateLabel(frame, "", PRT.FONT_SIZE, 1, 1, 1)
    valText:SetPoint("TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -16)
    slider:SetPoint("TOPRIGHT", 0, -16)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minVal or 0, maxVal or 1)
    slider:SetValueStep(step or 0.01)
    slider:SetObeyStepOnDrag(true)

    -- hide the default template labels
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / (step or 0.01) + 0.5) * (step or 0.01)
        valText:SetText(string.format("%.2f", val))
        if onChanged then onChanged(val) end
    end)

    frame.slider = slider
    frame.title = title
    frame.valText = valText

    function frame:SetValue(v)
        self.slider:SetValue(v)
        self.valText:SetText(string.format("%.2f", v))
    end
    function frame:GetValue()
        return self.slider:GetValue()
    end

    return frame
end

function W.CreateExactSlider(parent, label, minVal, maxVal, step, width,
        onChanged, decimals)
    local exactEdit
    decimals = decimals or 0
    local format = "%." .. decimals .. "f"
    local frame = W.CreateSlider(parent, label, minVal, maxVal, step, width,
        function(value)
            if exactEdit and not exactEdit:HasFocus() then
                exactEdit:SetText(format:format(value))
            end
            if onChanged then onChanged(value) end
        end)
    frame.valText:Hide()

    exactEdit = W.CreateEditBox(frame, 62, 20)
    exactEdit:SetPoint("TOPRIGHT", 0, 3)
    exactEdit:SetMaxLetters(8)

    local function Commit()
        local value = tonumber(exactEdit:GetText())
        if not value then value = frame:GetValue() end
        value = math.max(minVal, math.min(maxVal, value))
        value = math.floor(value / step + 0.5) * step
        frame:SetValue(value)
        exactEdit:SetText(format:format(value))
    end
    exactEdit:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)
    exactEdit:SetScript("OnEditFocusLost", Commit)

    function frame:SetExactValue(value)
        value = tonumber(value) or minVal
        self:SetValue(value)
        exactEdit:SetText(format:format(value))
    end
    frame.exactEdit = exactEdit
    return frame
end

function W.SetControlEnabled(control, enabled)
    if not control then return end
    enabled = enabled and true or false
    control._prtEnabled = enabled
    control:SetAlpha(enabled and 1 or 0.35)

    local targets = {
        control,
        control.check,
        control.slider,
        control.exactEdit,
        control.editBox,
    }
    for _, target in ipairs(targets) do
        if target then
            if target.SetEnabled then
                target:SetEnabled(enabled)
            elseif target.Enable and target.Disable then
                if enabled then target:Enable() else target:Disable() end
            elseif target.EnableMouse then
                target:EnableMouse(enabled)
            end
        end
    end
    if not enabled and control.menu then control.menu:Hide() end
end

---------------------------------------------------------------------------
-- Scroll list (generic scrollable container)
-- Custom thin scrollbar — no UIPanelScrollFrameTemplate dependency.
---------------------------------------------------------------------------
function W.CreateScrollFrame(parent, width, height)
    local SB_W = 8   -- scrollbar width

    width  = width or 300
    height = height or 400

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- ScrollFrame leaves room on the right for the custom bar
    local scroll = CreateFrame("ScrollFrame", nil, container)
    scroll:SetPoint("TOPLEFT",     1,          -1)
    scroll:SetPoint("BOTTOMRIGHT", -(SB_W+3),   1)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(width - SB_W - 6)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    -- Scrollbar (proportional step, hooks container wheel for full-area scroll)
    local sb = W.AttachScrollbar(container, scroll, content, {
        hookContainerWheel = true,
    })

    container.scroll  = scroll
    container.content = content

    container:SetScript("OnSizeChanged", function(self, w, h)
        if self.content then
            self.content:SetWidth(math.max(1, w - SB_W - 6))
        end
        sb.UpdateRange()
    end)

    function container:UpdateContentHeight(h)
        self.content:SetHeight(math.max(h, 1))
        sb.UpdateRange()
    end

    function container:ScrollToBottom()
        sb.UpdateRange()
        local _, maximum = sb.slider:GetMinMaxValues()
        sb.slider:SetValue(maximum)
    end

    return container
end

---------------------------------------------------------------------------
-- On-Screen Notification
-- Lazily creates a single shared notification frame and displays text with
-- a hold-then-fade animation driven by saved Settings tab values.
--
-- opts.color = {r, g, b}  overrides the saved notification font color for
--                          this call only (all other settings still come from
--                          db.notification so the user's Settings tab applies).
-- opts.soundFile           overrides the saved notification sound for this call.
-- opts.forceSound          plays opts.soundFile even when notification sound is off.
-- opts.playSound           explicitly enables/disables sound for this call.
-- opts.force               shows the notification even when notifications are off.
-- opts.fontSize/duration   override saved settings for this call only.
-- opts.x/opts.y            override saved screen offsets for this call only.
---------------------------------------------------------------------------
function PRT:ShowNotification(text, opts)
    opts = opts or {}
    local db  = self:GetDB()
    local cfg = db.notification or {}
    if cfg.enabled == false and not opts.force then return end

    -- Build notification frame lazily (once)
    if not self._notifFrame then
        local nf = CreateFrame("Frame", "PRT_NotifFrame", UIParent)
        nf:SetSize(800, 120)
        nf:SetFrameStrata("TOOLTIP")
        nf:SetFrameLevel(1000)
        if nf.SetToplevel then nf:SetToplevel(true) end
        nf:SetClampedToScreen(false)
        nf.label = nf:CreateFontString(nil, "OVERLAY")
        nf.label:SetPoint("CENTER")
        nf.label:SetJustifyH("CENTER")
        nf:Hide()
        self._notifFrame = nf
    end

    local nf = self._notifFrame
    nf:SetFrameStrata("TOOLTIP")
    nf:SetFrameLevel(1000)
    if nf.SetToplevel then nf:SetToplevel(true) end
    if nf.Raise then nf:Raise() end
    local fc = opts.color or cfg.fontColor or PRT.C.SETTINGS_FONT
    local fs = opts.fontSize or cfg.fontSize or 32

    nf.label:SetFont(PRT.FONT, fs, "OUTLINE")
    nf.label:SetWidth(opts.width or 760)
    nf.label:SetWordWrap(true)
    nf.label:SetText(text)
    nf.label:SetTextColor(fc[1], fc[2], fc[3], 1)

    nf:ClearAllPoints()
    nf:SetPoint("CENTER", UIParent, "CENTER",
        opts.x ~= nil and opts.x or cfg.x or 0,
        opts.y ~= nil and opts.y or cfg.y or 80)
    nf:SetAlpha(1)
    nf:Show()

    -- Play sound if enabled
    local playSound = opts.playSound
    if playSound == nil then playSound = cfg.sound or opts.forceSound end
    if playSound then
        PlaySoundFile(opts.soundFile or PRT.SND_MARIO, "Master")
    end

    -- Cancel any previous fade sequence
    self._notifSeq = (self._notifSeq or 0) + 1
    local seq = self._notifSeq

    local dur  = math.max(0.5, opts.duration or cfg.duration or 3.0)
    local hold = dur * 0.7
    local fade = dur * 0.3

    -- Hold at full alpha, then fade via OnUpdate
    C_Timer.After(hold, function()
        if self._notifSeq ~= seq then return end
        local elapsed = 0
        nf:SetScript("OnUpdate", function(self, dt)
            if PRT._notifSeq ~= seq then
                self:SetScript("OnUpdate", nil)
                return
            end
            elapsed = elapsed + dt
            local alpha = math.max(0, 1 - elapsed / fade)
            self:SetAlpha(alpha)
            if elapsed >= fade then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                self:SetAlpha(1)
            end
        end)
    end)
end
