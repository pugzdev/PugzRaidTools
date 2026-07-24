---------------------------------------------------------------------------
-- PugzRaidTools - Minimap Button
-- Modelled on ShadowNetwork's UI_Minimap.lua for HidingBar compatibility.
--   Left click       : open / close config
--   Shift+Left click : toggle floating list lock
--   Ctrl+Left click  : toggle floating list show / hide
--   Right click      : toggle Auto Swap on / off
--   Drag             : reposition around the minimap
---------------------------------------------------------------------------
local _, PRT = ...

---------------------------------------------------------------------------
-- Positioning  (degrees, matching ShadowNetwork convention)
---------------------------------------------------------------------------
local function UpdateMinimapButtonPosition(btn, angle)
    local rad    = math.rad(angle)
    local x, y   = math.cos(rad), math.sin(rad)
    local width  = Minimap:GetWidth()  or 140
    local height = Minimap:GetHeight() or width
    local shape  = GetMinimapShape and GetMinimapShape() or "ROUND"

    if shape == "ROUND" then
        local radius = math.min(width, height) / 2 + 22
        x = x * radius
        y = y * radius
    else
        local mx = math.max(math.abs(x), math.abs(y))
        if mx > 0 then x = x / mx; y = y / mx end
        local boost = 12 * math.min(math.abs(math.cos(rad)), math.abs(math.sin(rad)))
        x = math.max(-width  / 2 - 22 - boost, math.min(x * (width  / 2 + 22 + boost), width  / 2 + 22 + boost))
        y = math.max(-height / 2 - 22 - boost, math.min(y * (height / 2 + 22 + boost), height / 2 + 22 + boost))
    end

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- Icon tint — green when Auto Swap is enabled, white otherwise
---------------------------------------------------------------------------
function PRT:UpdateMinimapIconTint()
    local btn = PRT.minimapBtn
    if not btn then return end
    local db = PRT:GetDB()
    if db.autoSwap and db.autoSwap.enabled then
        btn.icon:SetVertexColor(0.3, 1.0, 0.3)
    else
        btn.icon:SetVertexColor(1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Create button (called from CreateMinimapButton on PLAYER_LOGIN)
---------------------------------------------------------------------------
local function BuildButton()
    local db    = PRT:GetDB()
    local angle = db.settings.minimapAngle or 195   -- degrees; south by default

    local btn = CreateFrame("Button", "PugzRaidToolsMinimapBtn", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Icon: 20x20 centred — same size/layer as ShadowNetwork
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\AddOns\\PugzRaidTools\\Media\\Textures\\MinimapIcon")
    icon:SetPoint("CENTER", 0, 1)
    btn.icon = icon   -- HidingBar reads btn.icon

    -- Circular border overlay: 54x54 anchored at TOPLEFT — same as ShadowNetwork
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    UpdateMinimapButtonPosition(btn, angle)

    ---------------------------------------------------------------------------
    -- Drag — OnUpdate is only registered while a drag is active
    ---------------------------------------------------------------------------
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale  = Minimap:GetEffectiveScale()
            local newAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            db.settings.minimapAngle = newAngle
            UpdateMinimapButtonPosition(self, newAngle)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    ---------------------------------------------------------------------------
    -- Clicks
    ---------------------------------------------------------------------------
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if IsControlKeyDown() then
                -- Toggle floating list visibility
                if PRT.db then
                    PRT.db.floatingList.shown = not PRT.db.floatingList.shown
                    PRT.Print("Floating list "
                        .. (PRT.db.floatingList.shown and "shown" or "hidden"))
                    if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
                end
            elseif IsShiftKeyDown() then
                -- Toggle floating list lock
                if PRT.db then
                    PRT.db.floatingList.locked = not PRT.db.floatingList.locked
                    PRT.Print("Floating list "
                        .. (PRT.db.floatingList.locked and "locked" or "unlocked"))
                    if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
                end
            else
                PRT:ToggleMainFrame()
            end
        elseif button == "RightButton" then
            -- Toggle Auto Swap
            if PRT.db then
                PRT.db.autoSwap.enabled = not PRT.db.autoSwap.enabled
                PRT.Print("Auto Swap "
                    .. (PRT.db.autoSwap.enabled and "enabled" or "disabled"))
                if PRT.UpdateAutoSwapListeners then PRT:UpdateAutoSwapListeners() end
                PRT:UpdateMinimapIconTint()
                if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
                if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("autoswap") end
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Tooltip
    ---------------------------------------------------------------------------
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("PugzRaidTools",
            PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
        GameTooltip:AddLine("Left click: Open / Close Config", 1, 1, 1)
        GameTooltip:AddLine("Shift+Left: Toggle Floating List Lock", 1, 1, 1)
        GameTooltip:AddLine("Ctrl+Left: Toggle Floating List", 1, 1, 1)
        GameTooltip:AddLine("Right click: Toggle Group Auto Swap", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move Button", 0.55, 0.55, 0.55)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PRT.minimapBtn = btn

    -- Apply initial tint based on saved Auto Swap state
    PRT:UpdateMinimapIconTint()
end

---------------------------------------------------------------------------
-- Public entry point — called from Core.lua on ADDON_LOADED,
-- but actual build is deferred to PLAYER_LOGIN so the Minimap has its
-- final size and position (same pattern as ShadowNetwork).
---------------------------------------------------------------------------
function PRT:CreateMinimapButton()
    local loginFrame = CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        BuildButton()
        -- Second pass after 2s in case another addon repositioned us
        C_Timer.After(2, function()
            if PRT.minimapBtn then
                local db = PRT:GetDB()
                UpdateMinimapButtonPosition(PRT.minimapBtn, db.settings.minimapAngle or 195)
                PRT:UpdateMinimapIconTint()
            end
        end)
    end)
end
