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

    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:ClearLines()

    if #missing == 0 and #extra == 0 then
        GameTooltip:AddLine(compName, 1, 1, 1)
        GameTooltip:AddLine("All roster members present.", 0.6, 1, 0.6)
        AddSortInstructions()
        GameTooltip:Show()
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
    GameTooltip:Show()
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
    local fcr, fcg, fcb = PRT.C.GOLD[1], PRT.C.GOLD[2], PRT.C.GOLD[3]
    if fl.fontColor then fcr, fcg, fcb = fl.fontColor[1], fl.fontColor[2], fl.fontColor[3] end
    local maxW = 60

    for i, compName in ipairs(order) do
        local btn = f.buttons[i]
        if not btn then
            btn = W.CreateRowButton(f, LINE_H, {
                bgColor = { 0, 0, 0, 0 },
                fontSize = fontSize,
                justifyH = "LEFT",
                textColor = { fcr, fcg, fcb, 1 },
            })

            btn:SetScript("OnEnter", function(self)
                self._bgTex:SetColorTexture(PRT.C.SIDEBAR_SEL[1], PRT.C.SIDEBAR_SEL[2], PRT.C.SIDEBAR_SEL[3], 0.5)
                ShowCompTooltip(self, self.compName)
            end)
            btn:SetScript("OnLeave", function(self)
                self._bgTex:SetColorTexture(0, 0, 0, 0)
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

        btn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + (i - 1) * LINE_H))
        btn:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        btn:Show()

        local w = btn.label:GetStringWidth() + 12
        if w > maxW then maxW = w end
    end

    ---------------------------------------------------------------------------
    -- Position separator and toggle buttons below the comp list
    -- sepY is the distance from the frame top to the bottom of the last comp.
    ---------------------------------------------------------------------------
    local sepY   = -(PAD + #order * LINE_H)   -- top of separator from frame top
    local gasY   = sepY - 1                    -- top of GAS button (1 px below sep)
    local pamY   = gasY - LINE_H               -- top of PAM button

    f.toggleSep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, sepY)
    f.toggleSep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, sepY)

    f.gasBtn:ClearAllPoints()
    f.gasBtn:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, gasY)
    f.gasBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, gasY)

    f.pamBtn:ClearAllPoints()
    f.pamBtn:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, pamY)
    f.pamBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, pamY)

    -- Resize frame: comp content + 1px separator + 2 toggle buttons + bottom pad
    local toggleBarH = 1 + LINE_H * 2
    local totalH     = #order * LINE_H + PAD * 2 + toggleBarH
    f:SetSize(maxW + PAD * 2, math.max(totalH, LINE_H + toggleBarH))
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
    if shouldShow then f:Show() else f:Hide() end

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
