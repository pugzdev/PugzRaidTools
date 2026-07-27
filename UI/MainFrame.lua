---------------------------------------------------------------------------
-- PugzRaidTools - Main Frame
-- MRT-style config window: left sidebar + right content area.
-- Resizable, saves size in settings.
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
    PRT._uiFocusSerial = (PRT._uiFocusSerial or 0) + 1
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    if frame.SetFrameStrata then
        frame:SetFrameStrata(strata or "FULLSCREEN_DIALOG")
    end
    if frame.SetFrameLevel then
        frame:SetFrameLevel(100 + PRT._uiFocusSerial)
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

local function ClampFrameSize(w, h)
    local minW, minH, maxW, maxH = GetResizeBounds()
    w = math.floor(tonumber(w) or DEFAULT_W)
    h = math.floor(tonumber(h) or DEFAULT_H)
    w = math.min(math.max(w, minW), maxW)
    h = math.min(math.max(h, minH), maxH)
    return w, h
end

local function ApplyResizeBounds(frame)
    local minW, minH, maxW, maxH = GetResizeBounds()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
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
    f:SetSize(fw, fh)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    f:HookScript("OnShow", function(self)
        BringManagedFrameToFront(self, "FULLSCREEN_DIALOG")
    end)
    f:HookScript("OnMouseDown", function(self)
        BringManagedFrameToFront(self, "FULLSCREEN_DIALOG")
    end)

    ApplyResizeBounds(f)

    -- Save size when resized
    f:SetScript("OnSizeChanged", function(self, w, h)
        local clampedW, clampedH = ClampFrameSize(w, h)
        if not self._sizeClampActive and (math.abs(w - clampedW) > 0.5 or math.abs(h - clampedH) > 0.5) then
            self._sizeClampActive = true
            self:SetSize(clampedW, clampedH)
            self._sizeClampActive = false
            return
        end

        if PRT.db and PRT.db.settings then
            PRT.db.settings.frameW = clampedW
            PRT.db.settings.frameH = clampedH
        end
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "PugzRaidToolsMainFrame")

    -- background
    W.AddBackground(f, 0, 0, 0, db.settings and db.settings.mainBgAlpha or 0.92)

    -- drag to move (title bar region)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
        f:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    titleBar:HookScript("OnMouseDown", function()
        BringManagedFrameToFront(f, "FULLSCREEN_DIALOG")
    end)

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
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_W)
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
    content:SetPoint("TOPLEFT", SIDEBAR_W + 1, -28)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
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
            f:StartSizing("BOTTOMRIGHT")
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
            f:StopMovingOrSizing()
        end,
    })
    f._resizeGrip = grip
    RefreshManagedChildLayers(f, "FULLSCREEN_DIALOG")

    PRT.mainFrame = f
    return f
end

function PRT:ResetMainFrameSize()
    local db = self:GetDB()
    local w, h = ClampFrameSize(DEFAULT_W, DEFAULT_H)

    if db and db.settings then
        db.settings.frameW = w
        db.settings.frameH = h
    end

    if self.mainFrame then
        ApplyResizeBounds(self.mainFrame)
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint("CENTER")
        self.mainFrame:SetSize(w, h)
    end

    PRT.Print(("Config window size reset to %dx%d."):format(w, h))
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
end

function PRT:RegisterTab(key, panel)
    if not self.mainFrame then CreateMainFrame() end
    panel:SetParent(self.mainFrame.content)
    panel:SetAllPoints(self.mainFrame.content)
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
                self.db.settings.frameH or DEFAULT_H)
            self.db.settings.frameW = fw
            self.db.settings.frameH = fh
            self.mainFrame:SetSize(fw, fh)
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
