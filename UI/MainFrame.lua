---------------------------------------------------------------------------
-- PugzRaidTools - Main Frame
-- MRT-style config window: left sidebar + right content area.
-- Resizable, saves size and position in settings.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local MIN_W = 960
local MIN_H = 562   -- title(28) + topbar(36) + 4rows*116 + bottombar(34) = 562
local DEFAULT_W = 1000
local DEFAULT_H = 600
local SCREEN_MARGIN = 20
local SIDEBAR_W = 155

local function RefreshManagedChildLayers(frame, strata)
    if not frame then return end
    local frameLevel = frame.GetFrameLevel and frame:GetFrameLevel() or 100
    local targetStrata = strata or (frame.GetFrameStrata and frame:GetFrameStrata()) or "FULLSCREEN_DIALOG"

    if frame._resizeGrip then
        if frame._resizeGrip.SetFrameStrata then
            frame._resizeGrip:SetFrameStrata(targetStrata)
        end
        if frame._resizeGrip.SetFrameLevel then
            frame._resizeGrip:SetFrameLevel(frameLevel + 20)
        end
    end

    if frame._borderOverlay then
        if frame._borderOverlay.SetFrameStrata then
            frame._borderOverlay:SetFrameStrata(targetStrata)
        end
        if frame._borderOverlay.SetFrameLevel then
            frame._borderOverlay:SetFrameLevel(frameLevel + 10)
        end
    end
end

local function BringManagedFrameToFront(frame, strata)
    if not frame then return end
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    if frame.SetFrameStrata then
        frame:SetFrameStrata(strata or "FULLSCREEN_DIALOG")
    end
    if frame.Raise and not frame._preserveChildFrameLevels then
        frame:Raise()
    end
    RefreshManagedChildLayers(frame, strata)
end

PRT.BringManagedFrameToFront = BringManagedFrameToFront

local TABS = {
    { key = "groups",   label = "Raid Groups" },
    { key = "autoswap", label = "Group Auto Swap" },
    { key = "automark", label = "Player Auto Marking" },
    { key = "targetmarks", label = "Target Marks" },
    { key = "invitetools", label = "Invite & Loot Tools" },
    { key = "raidcheck", label = "Raid Check" },
    { key = "profiles", label = "Profiles" },
    { key = "settings", label = "Settings" },
}

local function GetResizeBounds()
    local screenW = UIParent and UIParent.GetWidth and UIParent:GetWidth() or DEFAULT_W
    local screenH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or DEFAULT_H
    local maxW = math.max(1, math.floor((screenW or DEFAULT_W) - SCREEN_MARGIN))
    local maxH = math.max(1, math.floor((screenH or DEFAULT_H) - SCREEN_MARGIN))
    local minW = math.min(MIN_W, maxW)
    local minH = math.min(MIN_H, maxH)
    return minW, minH, maxW, maxH
end

local function SnapToPhysicalPixel(value, frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
        or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
        or 1
    if not scale or scale <= 0 then scale = 1 end
    return math.floor(value * scale + 0.5) / scale
end

local function ClampFrameSize(w, h, frame)
    local minW, minH, maxW, maxH = GetResizeBounds()
    w = tonumber(w) or DEFAULT_W
    h = tonumber(h) or DEFAULT_H
    w = math.min(math.max(w, minW), maxW)
    h = math.min(math.max(h, minH), maxH)
    w = math.min(math.max(SnapToPhysicalPixel(w, frame), minW), maxW)
    h = math.min(math.max(SnapToPhysicalPixel(h, frame), minH), maxH)
    return w, h
end

local function ClampMainFramePosition(x, y, width, height, frame)
    local screenW = UIParent and UIParent.GetWidth
        and UIParent:GetWidth() or DEFAULT_W
    local screenH = UIParent and UIParent.GetHeight
        and UIParent:GetHeight() or DEFAULT_H
    width = tonumber(width) or (frame and frame:GetWidth()) or DEFAULT_W
    height = tonumber(height) or (frame and frame:GetHeight()) or DEFAULT_H

    local margin = SCREEN_MARGIN / 2
    local maxX = math.max(0, (screenW - width) / 2 - margin)
    local maxY = math.max(0, (screenH - height) / 2 - margin)
    x = math.min(math.max(tonumber(x) or 0, -maxX), maxX)
    y = math.min(math.max(tonumber(y) or 0, -maxY), maxY)
    return SnapToPhysicalPixel(x, frame), SnapToPhysicalPixel(y, frame)
end

local function PersistMainFrameGeometry(frame)
    local settings = PRT.db and PRT.db.settings
    if not frame or not settings then return false end

    local width, height = frame:GetSize()
    local frameX, frameY = frame:GetCenter()
    local parentX, parentY
    if UIParent and UIParent.GetCenter then
        parentX, parentY = UIParent:GetCenter()
    end
    if not parentX or not parentY then
        parentX = (UIParent and UIParent:GetWidth() or DEFAULT_W) / 2
        parentY = (UIParent and UIParent:GetHeight() or DEFAULT_H) / 2
    end
    if not frameX or not frameY then return false end

    local x, y = ClampMainFramePosition(
        frameX - parentX,
        frameY - parentY,
        width,
        height,
        frame)
    settings.frameW = width
    settings.frameH = height
    settings.frameX = x
    settings.frameY = y
    return true
end

local function RestoreMainFrameGeometry(frame, settings, width, height)
    if not frame then return end
    settings = settings or {}
    local x, y = ClampMainFramePosition(
        settings.frameX,
        settings.frameY,
        width,
        height,
        frame)
    settings.frameX = x
    settings.frameY = y
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function PRT:SaveMainFrameGeometry(frame)
    return PersistMainFrameGeometry(frame or self.mainFrame)
end

function PRT:RestoreMainFrameGeometry(frame, settings, width, height)
    return RestoreMainFrameGeometry(
        frame or self.mainFrame,
        settings or (self.db and self.db.settings),
        width,
        height)
end

PRT.ClampMainFramePosition = ClampMainFramePosition

local function ApplyResizeBounds(frame)
    local minW, minH, maxW, maxH = GetResizeBounds()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

local function SetSizeIfChanged(frame, width, height)
    if not frame then return end
    if math.abs((frame:GetWidth() or 0) - width) > 0.5
        or math.abs((frame:GetHeight() or 0) - height) > 0.5 then
        frame:SetSize(width, height)
    end
end

local function AnchorMainFrameChild(child, point, relativeTo, relativePoint, x, y)
    if not child or child._prtMainFrameAnchored then return end
    child:ClearAllPoints()
    child:SetPoint(point, relativeTo, relativePoint, x, y)
    child._prtMainFrameAnchored = true
end

local function LayoutMainFrameChildren(frame, width, height, liveResize)
    if not frame then return end
    width = tonumber(width) or frame:GetWidth() or DEFAULT_W
    height = tonumber(height) or frame:GetHeight() or DEFAULT_H

    if frame.titleBar then
        AnchorMainFrameChild(frame.titleBar, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        SetSizeIfChanged(frame.titleBar, width, 28)
    end

    if frame.sidebar then
        AnchorMainFrameChild(frame.sidebar, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        SetSizeIfChanged(frame.sidebar, SIDEBAR_W, height)
    end

    local contentWidth = math.max(1, width - SIDEBAR_W - 1)
    local contentHeight = math.max(1, height - 28)
    if frame.content then
        AnchorMainFrameChild(frame.content, "TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + 1, -28)
        SetSizeIfChanged(frame.content, contentWidth, contentHeight)
    end

    for _, panel in pairs(frame.tabPanels or {}) do
        if not liveResize or panel:IsShown() then
            AnchorMainFrameChild(panel, "TOPLEFT", frame.content, "TOPLEFT", 0, 0)
            SetSizeIfChanged(panel, contentWidth, contentHeight)
        end
    end
end

local function RestoreResizeGrip(frame)
    local grip = frame and frame._resizeGrip
    if not grip then return end

    grip:ClearAllPoints()
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    if grip.Enable then grip:Enable() end
    if grip.SetButtonState then grip:SetButtonState("NORMAL", false) end
    grip:SetAlpha(1)
    grip:Show()
    if grip._gripTex then grip._gripTex:Show() end
    RefreshManagedChildLayers(frame, "FULLSCREEN_DIALOG")
end

local function FrameFlag(value)
    return value and "1" or "0"
end

local function FrameDebugName(frame)
    if not frame then return "<nil>" end
    return frame:GetName() or frame:GetObjectType() or "<unnamed>"
end

local function FrameDebugSummary(label, frame)
    if not frame then return label .. "=<nil>" end
    local parent = frame:GetParent()
    return ("%s shown=%s visible=%s mouse=%s alpha=%.2f strata=%s level=%d"
        .. " size=%.2fx%.2f scale=%.3f parent=%s"):format(
        label,
        FrameFlag(frame:IsShown()),
        FrameFlag(frame:IsVisible()),
        FrameFlag(frame.IsMouseEnabled and frame:IsMouseEnabled()),
        frame:GetAlpha() or 0,
        frame:GetFrameStrata() or "?",
        frame:GetFrameLevel() or -1,
        frame:GetWidth() or 0,
        frame:GetHeight() or 0,
        frame:GetEffectiveScale() or 0,
        FrameDebugName(parent))
end

local function CompactFrameDebug(frame)
    if not frame then return "<nil>" end
    return ("%s/%d/S%sV%s/%.1fx%.1f"):format(
        frame:GetFrameStrata() or "?",
        frame:GetFrameLevel() or -1,
        FrameFlag(frame:IsShown()),
        FrameFlag(frame:IsVisible()),
        frame:GetWidth() or 0,
        frame:GetHeight() or 0)
end

local function RecordMainFrameTrace(frame, reason)
    if not frame or not frame._uiDebugEnabled then return end
    frame._uiDebugTrace = frame._uiDebugTrace or {}
    local activePanel = frame.tabPanels
        and frame.tabPanels[frame.activeTab or ""] or nil
    local entry = ("%.2f %s main=%s side=%s content=%s panel=%s grip=%s"):format(
        GetTime and GetTime() or 0,
        reason or "snapshot",
        CompactFrameDebug(frame),
        CompactFrameDebug(frame.sidebar),
        CompactFrameDebug(frame.content),
        CompactFrameDebug(activePanel),
        CompactFrameDebug(frame._resizeGrip))
    table.insert(frame._uiDebugTrace, entry)
    while #frame._uiDebugTrace > 12 do
        table.remove(frame._uiDebugTrace, 1)
    end
end

local function StopManualResize(frame)
    if not frame then return end
    frame._manualResize = nil
    frame._uiDebugLastTrace = nil
    frame:SetScript("OnUpdate", nil)
    local width, height = frame:GetSize()
    LayoutMainFrameChildren(frame, width, height, false)
    PersistMainFrameGeometry(frame)
    RestoreResizeGrip(frame)
    RecordMainFrameTrace(frame, "resize-stop")
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if frame:IsShown() then RestoreResizeGrip(frame) end
        end)
    end
end

local function StartManualResize(frame)
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if not left or not top then return end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local width, height = frame:GetSize()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    frame._manualResize = {
        cursorX = cursorX,
        cursorY = cursorY,
        width = width,
        height = height,
        left = left,
        top = top,
    }
    RecordMainFrameTrace(frame, "resize-start")

    frame:SetScript("OnUpdate", function(self)
        local state = self._manualResize
        if not state then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopManualResize(self)
            return
        end

        local currentX, currentY = GetCursorPosition()
        currentX = currentX / scale
        currentY = currentY / scale

        local minW, minH, maxW, maxH = GetResizeBounds()
        local screenW = UIParent:GetWidth()
        local maxAtPositionW = screenW - state.left - SCREEN_MARGIN / 2
        local maxAtPositionH = state.top - SCREEN_MARGIN / 2
        maxW = math.min(maxW, math.max(minW, maxAtPositionW))
        maxH = math.min(maxH, math.max(minH, maxAtPositionH))

        local newW = state.width + currentX - state.cursorX
        local newH = state.height - currentY + state.cursorY
        local targetW = SnapToPhysicalPixel(
            math.min(math.max(newW, minW), maxW), self)
        local targetH = SnapToPhysicalPixel(
            math.min(math.max(newH, minH), maxH), self)
        targetW = math.min(math.max(targetW, minW), maxW)
        targetH = math.min(math.max(targetH, minH), maxH)
        if math.abs(self:GetWidth() - targetW) <= 0.01
            and math.abs(self:GetHeight() - targetH) <= 0.01 then
            return
        end
        self:SetSize(targetW, targetH)

        if self._uiDebugEnabled then
            local now = GetTime and GetTime() or 0
            if not self._uiDebugLastTrace
                or now - self._uiDebugLastTrace >= 0.25 then
                self._uiDebugLastTrace = now
                RecordMainFrameTrace(self, "resize")
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Create the main frame (once)
---------------------------------------------------------------------------
local function CreateMainFrame()
    local db = PRT.db or PRT.DEFAULTS
    local fw = (db.settings and db.settings.frameW) or DEFAULT_W
    local fh = (db.settings and db.settings.frameH) or DEFAULT_H
    fw, fh = ClampFrameSize(fw, fh)

    local f = CreateFrame("Frame", "PugzRaidToolsMainFrame", UIParent)
    -- Raising this parent directly can place its backdrop above child tab frames.
    -- Toplevel focus already raises the complete window hierarchy when clicked.
    f._preserveChildFrameLevels = true
    f:SetSize(fw, fh)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    RestoreMainFrameGeometry(f, db.settings, fw, fh)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    f:HookScript("OnShow", function(self)
        BringManagedFrameToFront(self, "FULLSCREEN_DIALOG")
    end)
    f:HookScript("OnMouseDown", function(self)
        BringManagedFrameToFront(self, "FULLSCREEN_DIALOG")
    end)
    f:HookScript("OnHide", function(self)
        StopManualResize(self)
    end)
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGOUT" then
            PersistMainFrameGeometry(self)
        end
    end)

    ApplyResizeBounds(f)

    -- Layout from the dimensions WoW actually resolved. Calling SetSize() from
    -- this callback causes feedback loops at fractional UI scales.
    f:SetScript("OnSizeChanged", function(self, w, h)
        local resolvedW, resolvedH = self:GetSize()
        LayoutMainFrameChildren(self, resolvedW, resolvedH, self._manualResize ~= nil)
        if not self._manualResize and PRT.db and PRT.db.settings then
            PRT.db.settings.frameW = resolvedW
            PRT.db.settings.frameH = resolvedH
        end
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "PugzRaidToolsMainFrame")

    -- background
    W.AddBackground(f, 0, 0, 0, db.settings and db.settings.mainBgAlpha or 0.92)

    -- drag to move (title bar region)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetSize(fw, 28)
    titleBar._prtMainFrameAnchored = true
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
        f:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        PersistMainFrameGeometry(f)
    end)
    titleBar:HookScript("OnMouseDown", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
    end)
    f.titleBar = titleBar

    -- title text
    local title = W.CreateLabel(titleBar, "|cFF33FF99Pugz|rRaidTools", PRT.FONT_SIZE_TITLE)
    title:SetPoint("LEFT", SIDEBAR_W + 12, 0)

    -- close button
    local closeBtn = W.CreateCloseButton(titleBar, function() f:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)

    ---------------------------------------------------------------------------
    -- Sidebar
    ---------------------------------------------------------------------------
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    sidebar:SetSize(SIDEBAR_W, fh)
    sidebar._prtMainFrameAnchored = true
    W.AddBackground(sidebar, PRT.C.SIDEBAR_BG[1], PRT.C.SIDEBAR_BG[2], PRT.C.SIDEBAR_BG[3], PRT.C.SIDEBAR_BG[4])
    sidebar:HookScript("OnMouseDown", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
    end)

    local sTitle = W.CreateLabel(sidebar, "|cFF33FF99PRT|r", PRT.FONT_SIZE_HEADER)
    sTitle:SetPoint("TOP", 0, -6)

    local div = sidebar:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", 4, -28)
    div:SetPoint("TOPRIGHT", -4, -28)
    div:SetHeight(1)
    div:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.6)

    f.sidebar = sidebar
    f.tabButtons = {}
    f.tabPanels  = {}

    for i, tab in ipairs(TABS) do
        local btn = W.CreateSelectableButton(sidebar, tab.label, {
            width = SIDEBAR_W,
            height = 26,
            bgColor = { 0, 0, 0, 0 },
            selectedBgColor = PRT.C.SIDEBAR_SEL,
            borderColor = { 0, 0, 0, 0 },
            selectedBorderColor = { 0, 0, 0, 0 },
            textColor = { 1, 1, 1, 1 },
            selectedTextColor = PRT.C.TITLE,
            fontSize = PRT.FONT_SIZE,
            justifyH = "LEFT",
            labelPoint = { "LEFT", 14, 0 },
            hoverAnimation = "MRT",
            hoverAnimationHeight = 24,
        })
        btn:SetPoint("TOPLEFT", 0, -(28 + (i - 1) * 26))
        btn.tabKey = tab.key
        btn:SetScript("OnClick", function(self) PRT:SelectTab(self.tabKey) end)

        f.tabButtons[tab.key] = btn
    end

    ---------------------------------------------------------------------------
    -- Content area
    ---------------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + 1, -28)
    content:SetSize(math.max(1, fw - SIDEBAR_W - 1), math.max(1, fh - 28))
    content._prtMainFrameAnchored = true
    W.AddBackground(content, PRT.C.CONTENT_BG[1], PRT.C.CONTENT_BG[2], PRT.C.CONTENT_BG[3], PRT.C.CONTENT_BG[4])
    content:HookScript("OnMouseDown", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
    end)
    f.content = content

    -- sidebar right-edge divider
    local sDiv = f:CreateTexture(nil, "ARTWORK")
    sDiv:SetPoint("TOPLEFT", SIDEBAR_W, 0)
    sDiv:SetPoint("BOTTOMLEFT", SIDEBAR_W, 0)
    sDiv:SetWidth(1)
    sDiv:SetColorTexture(PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], 0.8)

    -- Keep the outer outline above child-frame backgrounds at every opacity.
    local borderOverlay = CreateFrame("Frame", nil, f)
    borderOverlay:SetAllPoints(f)
    borderOverlay:EnableMouse(false)
    borderOverlay:SetFrameStrata(f:GetFrameStrata())
    borderOverlay:SetFrameLevel(f:GetFrameLevel() + 10)
    W.AddBorders(borderOverlay,
        PRT.C.BORDER[1], PRT.C.BORDER[2], PRT.C.BORDER[3], PRT.C.BORDER[4])
    f._borderOverlay = borderOverlay

    ---------------------------------------------------------------------------
    -- Resize grip (bottom-right corner)
    ---------------------------------------------------------------------------
    local grip = W.CreateResizeGrip(f, function(self, btn)
        if btn == "LeftButton" then
            BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
            StartManualResize(f)
        end
    end, {
        point = { "BOTTOMRIGHT", 0, 0 },
        size = 16,
        color = { 0.45, 0.45, 0.45, 0.5 },
        hoverColor = { 0.8, 0.8, 0.8, 0.8 },
        onEnter = function()
            BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
        end,
        onMouseUp = function()
            StopManualResize(f)
        end,
    })
    f._resizeGrip = grip
    LayoutMainFrameChildren(f, fw, fh)
    RestoreResizeGrip(f)

    PRT.mainFrame = f
    return f
end

function PRT:ResetMainFrameSize()
    local db = self:GetDB()
    local w, h = ClampFrameSize(DEFAULT_W, DEFAULT_H, self.mainFrame)

    if db and db.settings then
        db.settings.frameW = w
        db.settings.frameH = h
        db.settings.frameX = 0
        db.settings.frameY = 0
    end

    if self.mainFrame then
        ApplyResizeBounds(self.mainFrame)
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint("CENTER")
        self.mainFrame:SetSize(w, h)
        LayoutMainFrameChildren(self.mainFrame, w, h)
    end

    PRT.Print(("Config window reset to %dx%d at screen center."):format(w, h))
end

function PRT:SetMainFrameDebug(enabled)
    local frame = self.mainFrame
    if not frame then
        PRT.Print("Open the PRT configuration window before enabling UI debug.")
        return
    end

    frame._uiDebugEnabled = enabled and true or false
    frame._uiDebugTrace = {}
    frame._uiDebugLastTrace = nil
    if frame._uiDebugEnabled then
        RecordMainFrameTrace(frame, "debug-enabled")
    end
    PRT.Print("UI debug " .. (frame._uiDebugEnabled and "enabled." or "disabled."))
end

function PRT:DumpMainFrameDebug()
    local frame = self.mainFrame
    if not frame then
        PRT.Print("The PRT configuration window has not been created.")
        return
    end

    PRT.Print(("UI DEBUG active=%s resizing=%s points=%d"):format(
        tostring(frame.activeTab or "<nil>"),
        FrameFlag(frame._manualResize ~= nil),
        frame:GetNumPoints() or 0))
    PRT.Print(FrameDebugSummary("main", frame))
    PRT.Print(FrameDebugSummary("sidebar", frame.sidebar))
    PRT.Print(FrameDebugSummary("content", frame.content))
    PRT.Print(FrameDebugSummary("resize-grip", frame._resizeGrip))

    for _, tab in ipairs(TABS) do
        local panel = frame.tabPanels and frame.tabPanels[tab.key]
        PRT.Print(FrameDebugSummary("panel:" .. tab.key, panel))
    end

    if frame:GetNumPoints() > 0 then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        PRT.Print(("anchor=%s -> %s:%s x=%.2f y=%.2f"):format(
            tostring(point),
            FrameDebugName(relativeTo),
            tostring(relativePoint),
            tonumber(x) or 0,
            tonumber(y) or 0))
    end

    local trace = frame._uiDebugTrace or {}
    PRT.Print(("UI DEBUG trace entries=%d"):format(#trace))
    for index, entry in ipairs(trace) do
        PRT.Print(("trace %02d %s"):format(index, entry))
    end
end

---------------------------------------------------------------------------
-- Background opacity (applies to all panel backgrounds uniformly)
---------------------------------------------------------------------------
function PRT:ApplyMainBgAlpha(val)
    local f = self.mainFrame
    if not f then return end
    if f._bgTex then
        f._bgTex:SetColorTexture(0, 0, 0, val)
    end
    if f.sidebar and f.sidebar._bgTex then
        local s = PRT.C.SIDEBAR_BG
        f.sidebar._bgTex:SetColorTexture(s[1], s[2], s[3], val)
    end
    if f.content and f.content._bgTex then
        local c = PRT.C.CONTENT_BG
        f.content._bgTex:SetColorTexture(c[1], c[2], c[3], val)
    end
end

---------------------------------------------------------------------------
-- Tab management
---------------------------------------------------------------------------
function PRT:SelectTab(key)
    local f = self.mainFrame
    if not f then return end

    f.activeTab = key

    for k, btn in pairs(f.tabButtons) do
        if btn.SetSelected then btn:SetSelected(k == key) end
    end

    for k, panel in pairs(f.tabPanels) do
        if k == key then
            panel:Show()
            if panel.OnShow then panel:OnShow() end
        else
            panel:Hide()
        end
    end
    RecordMainFrameTrace(f, "tab:" .. tostring(key))
end

function PRT:RegisterTab(key, panel)
    if not self.mainFrame then CreateMainFrame() end
    panel:SetParent(self.mainFrame.content)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self.mainFrame.content, "TOPLEFT", 0, 0)
    panel:SetSize(
        math.max(1, self.mainFrame.content:GetWidth()),
        math.max(1, self.mainFrame.content:GetHeight()))
    panel._prtMainFrameAnchored = true
    panel:Hide()
    self.mainFrame.tabPanels[key] = panel
end

function PRT:RefreshFeatureToggleUI()
    if self.autoSwapPanel and self.autoSwapPanel.RefreshEnabledState then
        self.autoSwapPanel:RefreshEnabledState()
    end
    if self.autoMarkPanel and self.autoMarkPanel.RefreshEnabledState then
        self.autoMarkPanel:RefreshEnabledState()
    end
    if self.targetMarksPanel and self.targetMarksPanel.RefreshEnabledState then
        self.targetMarksPanel:RefreshEnabledState()
    end
    if self.UpdateFloatingList then self:UpdateFloatingList() end
    if self.UpdateMinimapIconTint then self:UpdateMinimapIconTint() end
end

function PRT:RefreshRosterSensitiveUI()
    local f = self.mainFrame
    if not f or not f:IsShown() then return end

    local key = f.activeTab
    if key == "groups" then
        if self.groupsPanel and self.groupsPanel.RefreshHighlights then
            self.groupsPanel:RefreshHighlights()
        end
    elseif key == "automark" then
        if self.autoMarkPanel and self.autoMarkPanel.RequestRuleDetailsRefresh then
            self.autoMarkPanel:RequestRuleDetailsRefresh()
        elseif self.autoMarkPanel and self.autoMarkPanel.RefreshRuleDetails then
            self.autoMarkPanel:RefreshRuleDetails()
        end
    elseif key == "raidcheck" then
        if self.raidCheckPanel and self.raidCheckPanel.Refresh then
            self.raidCheckPanel:Refresh()
        end
    end

    if self.RefreshRosterMatcherPopup then
        self:RefreshRosterMatcherPopup()
    end
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------
function PRT:ToggleMainFrame()
    if not self.mainFrame then
        CreateMainFrame()
        if PRT.BuildGroupsTab then PRT:BuildGroupsTab() end
        if PRT.BuildAutoSwapTab then PRT:BuildAutoSwapTab() end
        if PRT.BuildAutoMarkTab then PRT:BuildAutoMarkTab() end
        if PRT.BuildTargetMarksTab then PRT:BuildTargetMarksTab() end
        if PRT.BuildInviteToolsTab then PRT:BuildInviteToolsTab() end
        if PRT.BuildRaidCheckTab then PRT:BuildRaidCheckTab() end
        if PRT.BuildProfilesTab then PRT:BuildProfilesTab() end
        if PRT.BuildSettingsTab then PRT:BuildSettingsTab() end
        self:SelectTab("groups")
    end

    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        if self.db then
            local a = self.db.settings.mainBgAlpha or 0.92
            self:ApplyMainBgAlpha(a)
            ApplyResizeBounds(self.mainFrame)
            -- Restore saved size
            local fw, fh = ClampFrameSize(
                self.db.settings.frameW or DEFAULT_W,
                self.db.settings.frameH or DEFAULT_H,
                self.mainFrame)
            self.db.settings.frameW = fw
            self.db.settings.frameH = fh
            self.mainFrame:SetSize(fw, fh)
            RestoreMainFrameGeometry(
                self.mainFrame,
                self.db.settings,
                fw,
                fh)
            LayoutMainFrameChildren(self.mainFrame, fw, fh)
        end
        self.mainFrame:Show()
        BringManagedFrameToFront(self.mainFrame, "FULLSCREEN_DIALOG")
        self:SelectTab(self.mainFrame.activeTab or "groups")
    end
end

do
    local rosterRefreshFrame = CreateFrame("Frame")
    rosterRefreshFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterRefreshFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    rosterRefreshFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    rosterRefreshFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rosterRefreshFrame._pending = false
    rosterRefreshFrame:SetScript("OnEvent", function(self)
        if self._pending then return end
        self._pending = true
        C_Timer.After(0.05, function()
            self._pending = false
            if PRT and PRT.RefreshRosterSensitiveUI then
                PRT:RefreshRosterSensitiveUI()
            end
        end)
    end)
end
