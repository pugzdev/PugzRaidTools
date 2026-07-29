---------------------------------------------------------------------------
-- PugzRaidTools - Compact Raid Check Results Window
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local HEADER_HEIGHT = 20
local COLUMN_HEADER_HEIGHT = 27
local NAME_WIDTH = 108
local DEFAULT_COLUMN_WIDTH = 40
local MINI_COLUMN_WIDTH = 128
local MINI_ROW_HEIGHT = 14
local MINI_COLUMNS = 4
local MAX_ROWS = 40
local MAX_COLUMNS = 22
local MAX_CATEGORY_ICONS = 6
local COUNT_LABEL_WIDTH = 14
local COUNT_LABEL_GAP = 1
local PROGRESS_TAIL_WIDTH = 18
local FADE_DURATION = 2
local VALID_FRAME_STRATA = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

local function NormalizeFrameStrata(value)
    return VALID_FRAME_STRATA[value] and value or "FULLSCREEN_DIALOG"
end

local function Now()
    return GetTime and GetTime() or 0
end

local function SaveWindowPosition(frame)
    local cfg = PRT:GetDB().raidCheck
    if not cfg then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    cfg.point = point or "CENTER"
    cfg.relPoint = relPoint or cfg.point
    cfg.x = x or 0
    cfg.y = y or 0
end

local function ApplySavedPosition(frame)
    local cfg = PRT:GetDB().raidCheck or {}
    frame:ClearAllPoints()
    frame:SetPoint(
        cfg.point or "CENTER",
        UIParent,
        cfg.relPoint or cfg.point or "CENTER",
        tonumber(cfg.x) or 0,
        tonumber(cfg.y) or 0)
end

local function ReadyTexture(status)
    if status == "ready" then
        return "Interface\\RaidFrame\\ReadyCheck-Ready"
    elseif status == "notReady" then
        return "Interface\\RaidFrame\\ReadyCheck-NotReady"
    elseif status == "waiting" then
        return "Interface\\RaidFrame\\ReadyCheck-Waiting"
    end
end

-- Match the live reference window: custom class colours take precedence over
-- Blizzard's defaults, and each row fades from 40% class colour to transparent.
local function GetClassColor(classFile)
    local custom = type(CUSTOM_CLASS_COLORS) == "table"
        and CUSTOM_CLASS_COLORS[classFile] or nil
    local color = custom
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if color then return color.r, color.g, color.b end
    return 0.7, 0.7, 0.7
end

local function SetHorizontalGradient(texture, left, right)
    -- A gradient modifies an existing texture. Initializing the colour surface
    -- first keeps both class-row gradients and the timer tail visible.
    texture:SetColorTexture(1, 1, 1, 1)
    if texture.SetGradient and CreateColor then
        texture:SetGradient(
            "HORIZONTAL",
            CreateColor(left[1], left[2], left[3], left[4] or 1),
            CreateColor(right[1], right[2], right[3], right[4] or 1))
    elseif texture.SetGradientAlpha then
        texture:SetGradientAlpha(
            "HORIZONTAL",
            left[1], left[2], left[3], left[4] or 1,
            right[1], right[2], right[3], right[4] or 1)
    else
        texture:SetColorTexture(
            left[1], left[2], left[3], left[4] or 1)
    end
end

local function ColumnValue(member, column)
    if column.buffKey then
        return member.buffs and member.buffs[column.buffKey]
    end
    return member[column.key]
end

local function ColumnWidth(column)
    if PRT.GetRaidCheckColumnWidth then
        return PRT:GetRaidCheckColumnWidth(column)
    end
    return tonumber(column and column.width) or DEFAULT_COLUMN_WIDTH
end

local REPORTABLE_COLUMNS = {
    worldBuffs = true,
    attackPower = true,
    disallowed = true,
    flask = true,
    zanza = true,
    potions = true,
    consumes = true,
    stamina = true,
    druid = true,
    intellect = true,
    spirit = true,
    shadow = true,
    kings = true,
    might = true,
    wisdom = true,
    salvation = true,
    light = true,
    durability = true,
}

local function ShiftIsDown()
    return IsShiftKeyDown and IsShiftKeyDown() or false
end

local function SendColumnClick(
        popup, column, member, button, aura)
    if button ~= "LeftButton" or not popup or not popup.snapshot then
        return
    end
    local columnKey = column and column.key or "player"
    if columnKey ~= "player"
        and not REPORTABLE_COLUMNS[columnKey] then
        return
    end
    if columnKey == "potions" and not aura then
        return
    end
    PRT:SendRaidCheckClickReport(
        columnKey,
        popup.snapshot,
        {
            shift = ShiftIsDown(),
            member = member,
            spellId = aura and aura.spellId,
        })
end

local function ColumnClickHints(column, member)
    if not column or not REPORTABLE_COLUMNS[column.key] then
        return {}
    end
    if column.key == "potions" then
        return {
            "Left-click a displayed potion icon to report that potion.",
        }
    elseif column.key == "worldBuffs" then
        return {
            "Left-click to report active World Buffs.",
            "Shift-left-click to report one-hour World Buffs.",
        }
    elseif column.key == "attackPower" then
        return {
            "Left-click to report the Battle Shout count.",
            "Shift-left-click to list players with Battle Shout.",
        }
    elseif column.buffKey then
        if member then
            return {
                "Left-click to report the raid's buff status.",
                "Shift-left-click to report this player's buff status.",
            }
        end
        return {
            "Left-click to report the raid's buff status.",
            "Shift-left-click a player's cell for their status.",
        }
    end
    return {
        "Left-click to report this column to group chat.",
    }
end

local function AppendClickHints(lines, column, member)
    lines = lines or {}
    for _, hint in ipairs(ColumnClickHints(column, member)) do
        lines[#lines + 1] = { hint, 0.35, 1, 0.7, true }
    end
    return lines
end

local function NormalizeAlignment(value)
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end

local function CreateHeaderCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(DEFAULT_COLUMN_WIDTH, COLUMN_HEADER_HEIGHT)
    cell:EnableMouse(true)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(14, 14)
    cell.icon:SetPoint("TOP", 0, -2)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cell.label = W.CreateLabel(cell, "", math.max(8, PRT.FONT_SIZE - 3),
        0.9, 0.9, 0.9)
    cell.label:SetPoint("BOTTOM", 0, 1)
    cell.label:SetJustifyH("CENTER")

    W.AttachTooltip(cell, {
        anchor = "ANCHOR_TOP",
        getLines = function() return cell._tooltipLines or {} end,
    })
    cell:HookScript("OnMouseUp", function(self, button)
        SendColumnClick(
            self._popup, self._column, nil, button)
    end)
    cell:Hide()
    return cell
end

local function ApplyHeaderCellAlignment(cell, alignment)
    alignment = NormalizeAlignment(alignment)
    cell.icon:ClearAllPoints()
    if alignment == "LEFT" then
        cell.icon:SetPoint("TOPLEFT", 2, -2)
    elseif alignment == "RIGHT" then
        cell.icon:SetPoint("TOPRIGHT", -2, -2)
    else
        cell.icon:SetPoint("TOP", 0, -2)
    end

    cell.label:ClearAllPoints()
    -- Classic can ignore FontString justification within a constrained
    -- two-anchor region. Physically anchor the naturally sized text instead,
    -- so its visible edge follows the same alignment as the header icon.
    if alignment == "LEFT" then
        cell.label:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 2, 1)
    elseif alignment == "RIGHT" then
        cell.label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 1)
    else
        cell.label:SetPoint("BOTTOM", cell, "BOTTOM", 0, 1)
    end
    cell.label:SetJustifyH("CENTER")
end

local function CreateResultCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(DEFAULT_COLUMN_WIDTH, 20)
    cell:EnableMouse(true)
    cell.iconSlots = {}

    cell.text = W.CreateLabel(cell, "", math.max(8, PRT.FONT_SIZE - 2),
        1, 1, 1)
    cell.text:SetPoint("CENTER")
    cell.text:SetJustifyH("CENTER")

    cell.overlay = W.CreateLabel(cell, "", 8, 1, 1, 1)
    cell.overlay:SetPoint("BOTTOMRIGHT", -1, 0)
    cell.overlay:SetFont(PRT.FONT, 8, "OUTLINE")

    W.AttachTooltip(cell, {
        anchor = "ANCHOR_TOP",
        getLines = function() return cell._tooltipLines or {} end,
    })
    cell:HookScript("OnMouseUp", function(self, button)
        SendColumnClick(
            self._popup,
            self._column,
            self._member,
            button)
    end)
    return cell
end

local function EnsureIconSlot(cell, index)
    local slot = cell.iconSlots[index]
    if slot then return slot end
    slot = {}

    slot.icon = cell:CreateTexture(nil, "ARTWORK")
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.glow = cell:CreateTexture(nil, "OVERLAY")
    slot.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    slot.glow:SetBlendMode("ADD")
    slot.glow:SetVertexColor(1, 0.05, 0.05, 1)
    slot.glow:Hide()

    slot.hit = CreateFrame("Button", nil, cell)
    slot.hit:SetPoint("TOPLEFT", slot.icon, "TOPLEFT")
    slot.hit:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT")
    slot.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.hit:SetFrameLevel((cell:GetFrameLevel() or 1) + 3)
    slot.hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local popup = cell._popup
            local cfg = PRT:GetDB().raidCheck or {}
            if popup and cfg.dismissOnRightClick ~= false then
                popup:Hide()
            end
            return
        end
        SendColumnClick(
            cell._popup,
            slot._column,
            cell._member,
            button,
            slot._aura)
    end)
    W.AttachTooltip(slot.hit, {
        anchor = "ANCHOR_TOP",
        getLines = function()
            return slot._tooltipLines or {}
        end,
    })
    slot.hit:Hide()

    cell.iconSlots[index] = slot
    return slot
end

local function HideCellIcons(cell)
    for _, slot in ipairs(cell.iconSlots) do
        slot.icon:Hide()
        slot.glow:Hide()
        slot.hit:Hide()
        slot._aura = nil
        slot._column = nil
        slot._tooltipLines = nil
    end
end

local function ApplyCellAlignment(cell, alignment)
    alignment = NormalizeAlignment(alignment)
    cell.text:ClearAllPoints()
    cell.text:SetPoint("LEFT", 2, 0)
    cell.text:SetPoint("RIGHT", -2, 0)
    cell.text:SetJustifyH(alignment)

    cell.overlay:ClearAllPoints()
    cell.overlay:SetWidth(COUNT_LABEL_WIDTH)
    cell.overlay:SetJustifyH(alignment)
    if alignment == "LEFT" then
        cell.overlay:SetPoint("BOTTOMLEFT", 1, 0)
    elseif alignment == "RIGHT" then
        cell.overlay:SetPoint("BOTTOMRIGHT", -1, 0)
    else
        cell.overlay:SetPoint("BOTTOM", 0, 0)
    end
end

local function AuraDisplayName(aura)
    return tostring(
        aura and (aura.raidCheckDefinitionName or aura.name)
        or "Present")
end

local function AuraTooltip(column, aura)
    if not aura then
        return {
            { column.label, 1, 1, 1 },
            { "Missing", 1, 0.3, 0.3 },
        }
    end

    local lines = {
        { column.label, 1, 1, 1 },
        {
            AuraDisplayName(aura),
            aura.raidCheckLowRank and 1 or 0.35,
            aura.raidCheckLowRank and 0.35 or 1,
            aura.raidCheckLowRank and 0.25 or 0.35,
        },
    }
    if aura.raidCheckWorldBuffContainer then
        lines[#lines + 1] = {
            "Contains stored world buffs and freezes their durations.",
            0.35, 1, 0.7,
        }
    end
    if aura.raidCheckRank and aura.raidCheckMaxRank then
        local rankText = ("Rank %d of %d"):format(
            aura.raidCheckRank, aura.raidCheckMaxRank)
        if aura.raidCheckLowRank then rankText = rankText .. " - low rank" end
        lines[#lines + 1] = {
            rankText,
            aura.raidCheckLowRank and 1 or 0.72,
            aura.raidCheckLowRank and 0.3 or 0.72,
            aura.raidCheckLowRank and 0.2 or 0.72,
        }
    end

    local expiration = tonumber(aura.expirationTime)
    if expiration and expiration > 0 then
        local remaining = math.max(0, expiration - Now())
        lines[#lines + 1] = {
            ("%.0f minutes remaining"):format(remaining / 60),
            remaining < 600 and 1 or 0.72,
            remaining < 600 and 0.75 or 0.72,
            remaining < 600 and 0.25 or 0.72,
        }
    end
    return lines
end

local function CategoryTooltip(column, member, auras)
    if not auras or #auras == 0 then return AuraTooltip(column, nil) end

    local counted = #auras
    if column.key == "worldBuffs" then
        counted = #(member.countedWorldBuffs or {})
    end
    local title = column.key == "worldBuffs"
        and ("%s (%d counted / %d detected)"):format(
            column.label, counted, #auras)
        or ("%s (%d)"):format(column.label, #auras)
    local lines = { { title, 1, 1, 1 } }
    for _, aura in ipairs(auras) do
        if aura.raidCheckWorldBuffContainer then
            lines[#lines + 1] = {
                AuraDisplayName(aura)
                    .. " - stored world buffs (durations frozen)",
                0.35, 1, 0.7,
            }
        elseif column.key == "worldBuffs" and not aura.raidCheckCounted then
            lines[#lines + 1] = {
                AuraDisplayName(aura) .. " - not counted for "
                    .. tostring(member.className or member.classFile or "class"),
                0.55, 0.55, 0.55,
            }
        elseif column.alwaysGlow then
            lines[#lines + 1] = {
                AuraDisplayName(aura), 1, 0.2, 0.2,
            }
        else
            lines[#lines + 1] = {
                AuraDisplayName(aura), 0.35, 1, 0.35,
            }
        end
    end
    return lines
end

local function PositionIconSlots(
        cell, displayed, iconSize, alignment, trailingWidth)
    if displayed <= 0 then return end
    local gap = 0
    local totalWidth = displayed * iconSize
        + (displayed - 1) * gap
        + (tonumber(trailingWidth) or 0)
    local cellWidth = cell:GetWidth()
    local firstX
    alignment = NormalizeAlignment(alignment)
    if alignment == "LEFT" then
        firstX = -cellWidth / 2 + iconSize / 2
    elseif alignment == "RIGHT" then
        firstX = cellWidth / 2 - totalWidth + iconSize / 2
    else
        firstX = -totalWidth / 2 + iconSize / 2
    end
    for index = 1, displayed do
        local slot = EnsureIconSlot(cell, index)
        slot.icon:ClearAllPoints()
        slot.icon:SetSize(iconSize, iconSize)
        slot.icon:SetPoint(
            "CENTER", cell, "CENTER",
            firstX + (index - 1) * (iconSize + gap), 0)
        slot.glow:ClearAllPoints()
        slot.glow:SetPoint("CENTER", slot.icon, "CENTER")
        slot.glow:SetSize(iconSize + 12, iconSize + 12)
    end
    return EnsureIconSlot(cell, displayed)
end

local function ShowAuraIcon(slot, aura, column, glow, uncountedMode)
    slot.icon:SetTexture(
        aura.raidCheckDisplayIcon or aura.icon or column.icon)
    if column.key == "worldBuffs"
        and not aura.raidCheckCounted
        and uncountedMode == "fade" then
        slot.icon:SetVertexColor(0.5, 0.5, 0.5, 1)
    else
        slot.icon:SetVertexColor(1, 1, 1, 1)
    end
    slot.icon:Show()
    slot.glow:SetShown(glow == true)
    slot._aura = aura
    slot._column = column
    slot._tooltipLines = AuraTooltip(column, aura)
    if column.key == "potions" then
        slot._tooltipLines[#slot._tooltipLines + 1] = {
            "Left-click to report this potion to group chat.",
            0.35, 1, 0.7, true,
        }
        slot.hit:Show()
    else
        slot.hit:Hide()
    end
end

local function UpdateCategoryCell(
        cell, member, column, auras, iconSize, setting, alignment)
    if not auras or #auras == 0 then
        cell.text:SetText("x")
        cell.text:SetTextColor(
            PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
        cell._tooltipLines = CategoryTooltip(column, member, auras)
        return
    end

    local displayedAuras = auras
    if column.key == "worldBuffs"
        and setting
        and setting.uncountedMode == "hide" then
        displayedAuras = {}
        for _, aura in ipairs(auras) do
            if aura.raidCheckCounted then
                displayedAuras[#displayedAuras + 1] = aura
            end
        end
    end
    if #displayedAuras == 0 then
        cell.text:SetText("x")
        cell.text:SetTextColor(
            PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
        cell._tooltipLines = CategoryTooltip(column, member, auras)
        return
    end

    local maximum = math.max(1, math.min(
        tonumber(column.maxDisplayLimit) or MAX_CATEGORY_ICONS,
        tonumber(setting and setting.maxDisplay) or 1))
    local displayed = math.min(#displayedAuras, maximum)
    local showCount = setting and setting.showCount == true
    local countSpace = showCount
        and (COUNT_LABEL_WIDTH + COUNT_LABEL_GAP) or 0
    local lastSlot = PositionIconSlots(
        cell, displayed, iconSize, alignment, countSpace)
    cell.text:Hide()

    for index = 1, displayed do
        local slot = EnsureIconSlot(cell, index)
        ShowAuraIcon(
            slot,
            displayedAuras[index],
            column,
            column.alwaysGlow,
            setting and setting.uncountedMode or "fade")
    end

    if showCount then
        local count = column.key == "worldBuffs"
            and #(member.countedWorldBuffs or {}) or #auras
        cell.overlay:ClearAllPoints()
        cell.overlay:SetWidth(COUNT_LABEL_WIDTH)
        cell.overlay:SetPoint(
            "LEFT", lastSlot.icon, "RIGHT", COUNT_LABEL_GAP, 0)
        cell.overlay:SetJustifyH("LEFT")
        cell.overlay:SetText(tostring(count))
    end
    cell._tooltipLines = CategoryTooltip(column, member, auras)
end

local function UpdateResultCell(cell, member, column, rowHeight, width)
    cell:SetSize(width, rowHeight)
    local iconSize = math.max(10, rowHeight)
    local setting = PRT:GetRaidCheckColumnSetting(column)
    local alignment = NormalizeAlignment(setting and setting.alignment)
    HideCellIcons(cell)
    ApplyCellAlignment(cell, alignment)
    cell.text:Show()
    cell.text:SetText("")
    cell.overlay:SetText("")
    cell.overlay:SetTextColor(1, 1, 1)
    cell:SetAlpha(member.connected and 1 or 0.35)

    local value = ColumnValue(member, column)
    if column.key == "durability" then
        if value == nil then
            cell.text:SetText("-")
            cell.text:SetTextColor(
                PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
            cell._tooltipLines = {
                { "Durability", 1, 1, 1 },
                {
                    "No recent PRT durability response.",
                    0.72, 0.72, 0.72, true,
                },
            }
        else
            cell.text:SetText(("%d%%"):format(math.floor(value + 0.5)))
            if value < 25 then
                cell.text:SetTextColor(
                    PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
            elseif value <= 50 then
                cell.text:SetTextColor(
                    PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3])
            else
                cell.text:SetTextColor(1, 1, 1)
            end
            cell._tooltipLines = {
                { "Durability", 1, 1, 1 },
                { ("%.1f%%"):format(value), 0.72, 0.72, 0.72 },
            }
        end
        return
    end

    if not member.auraScanAvailable then
        cell.text:SetText("?")
        cell.text:SetTextColor(
            PRT.C.YELLOW[1], PRT.C.YELLOW[2], PRT.C.YELLOW[3])
        cell._tooltipLines = {
            { column.label, 1, 1, 1 },
            { "Aura data is unavailable.", 1, 0.8, 0.2 },
        }
        return
    end

    if column.multiAura then
        UpdateCategoryCell(
            cell, member, column, value, iconSize, setting, alignment)
        return
    end

    if value then
        local slot = EnsureIconSlot(cell, 1)
        PositionIconSlots(cell, 1, iconSize, alignment)
        cell.text:Hide()
        ShowAuraIcon(
            slot, value, column, value.raidCheckLowRank, nil)
        if value.raidCheckLowRank then
            cell.overlay:SetText("R" .. tostring(value.raidCheckRank or "?"))
            cell.overlay:SetTextColor(1, 0.25, 0.2)
        end
        cell._tooltipLines = AuraTooltip(column, value)
    else
        cell.text:SetText("x")
        cell.text:SetTextColor(
            PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])
        cell._tooltipLines = AuraTooltip(column, nil)
    end
end

local function CreateResultRow(parent)
    local row = W.CreateRowFrame(parent, 20)
    row:EnableMouse(true)

    row.alternate = row:CreateTexture(nil, "BACKGROUND")
    row.alternate:SetAllPoints()
    row.alternate:SetColorTexture(1, 1, 1, 0.05)

    row.classGradient = row:CreateTexture(nil, "BACKGROUND", nil, 5)
    row.classGradient:SetAllPoints()

    row.readyIcon = row:CreateTexture(nil, "ARTWORK")
    row.readyIcon:SetSize(14, 14)
    row.readyIcon:SetPoint("LEFT", 6, 0)

    row.nameLabel = W.CreateLabel(row, "", math.max(9, PRT.FONT_SIZE - 1),
        1, 1, 1)
    row.nameLabel:SetPoint("LEFT", 24, 0)
    row.nameLabel:SetWidth(NAME_WIDTH - 27)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetFont(
        PRT.FONT, math.max(9, PRT.FONT_SIZE - 1), "OUTLINE")

    row.cells = {}
    for index = 1, MAX_COLUMNS do
        row.cells[index] = CreateResultCell(row)
    end

    W.AttachTooltip(row, {
        anchor = "ANCHOR_LEFT",
        getLines = function()
            local member = row.member
            if not member then return {} end
            return {
                { member.displayName or member.name or "", 1, 1, 1 },
                {
                    ("Group %d%s"):format(
                        member.subgroup or 1,
                        member.dead and " - Dead" or ""),
                    0.78, 0.78, 0.78,
                },
                {
                    member.connected and "Online" or "Offline",
                    member.connected and 0.45 or 1,
                    member.connected and 0.9 or 0.35,
                    member.connected and 0.45 or 0.35,
                },
            }
        end,
    })
    row:HookScript("OnMouseUp", function(self, button)
        SendColumnClick(
            self._popup, nil, self.member, button)
    end)
    row:Hide()
    return row
end

local function UpdateResultRow(
        row, member, columns, columnLayout, rowHeight, index)
    row.member = member
    row:SetHeight(rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * rowHeight))

    local r, g, b = GetClassColor(member.classFile)
    SetHorizontalGradient(
        row.classGradient,
        { r, g, b, 0.4 },
        { r, g, b, 0 })
    row.alternate:SetShown(index % 2 == 0)
    row.nameLabel:SetText(member.name or member.displayName or "")
    if member.connected then
        row.nameLabel:SetTextColor(1, 1, 1)
    else
        row.nameLabel:SetTextColor(
            PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
    end

    local readyTexture = ReadyTexture(member.readyStatus)
    local readySize = math.max(10, math.min(14, rowHeight - 2))
    row.readyIcon:SetSize(readySize, readySize)
    row.readyIcon:SetTexture(readyTexture)
    row.readyIcon:SetShown(readyTexture ~= nil)

    for columnIndex, cell in ipairs(row.cells) do
        local column = columns[columnIndex]
        local layout = columnLayout[columnIndex]
        if column and layout then
            cell._column = column
            cell._member = member
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", layout.x, 0)
            UpdateResultCell(
                cell, member, column, rowHeight, layout.width)
            cell._tooltipLines = AppendClickHints(
                cell._tooltipLines, column, member)
            cell:Show()
        else
            cell._column = nil
            cell._member = nil
            cell:Hide()
        end
    end
    row:Show()
end

local function CreateMiniMember(parent)
    local memberFrame = CreateFrame("Frame", nil, parent)
    memberFrame:SetSize(MINI_COLUMN_WIDTH, MINI_ROW_HEIGHT)

    memberFrame.readyIcon = memberFrame:CreateTexture(nil, "ARTWORK")
    memberFrame.readyIcon:SetSize(12, 12)
    memberFrame.readyIcon:SetPoint("LEFT", 3, 0)

    memberFrame.nameLabel = W.CreateLabel(
        memberFrame, "", math.max(8, PRT.FONT_SIZE - 2), 1, 1, 1)
    memberFrame.nameLabel:SetPoint("LEFT", 18, 0)
    memberFrame.nameLabel:SetWidth(MINI_COLUMN_WIDTH - 20)
    memberFrame.nameLabel:SetJustifyH("LEFT")
    memberFrame.nameLabel:SetFont(
        PRT.FONT, math.max(8, PRT.FONT_SIZE - 2), "OUTLINE")
    memberFrame:EnableMouse(true)
    memberFrame:HookScript("OnMouseUp", function(self, button)
        SendColumnClick(
            self._popup, nil, self._member, button)
    end)
    memberFrame:Hide()
    return memberFrame
end

local function UpdateMiniMembers(popup, members)
    local rows = math.max(1, math.ceil(#members / MINI_COLUMNS))
    for index, mini in ipairs(popup.miniMembers) do
        local member = members[index]
        if member then
            mini._member = member
            local column = (index - 1) % MINI_COLUMNS
            local row = math.floor((index - 1) / MINI_COLUMNS)
            mini:ClearAllPoints()
            mini:SetPoint(
                "TOPLEFT",
                column * MINI_COLUMN_WIDTH,
                -(row * MINI_ROW_HEIGHT))
            mini.nameLabel:SetText(member.name or member.displayName or "")
            local r, g, b = GetClassColor(member.classFile)
            mini.nameLabel:SetTextColor(r, g, b)
            mini:SetAlpha(member.connected and 1 or 0.4)
            local readyTexture = ReadyTexture(member.readyStatus)
            mini.readyIcon:SetTexture(readyTexture)
            mini.readyIcon:SetShown(readyTexture ~= nil)
            mini:Show()
        else
            mini._member = nil
            mini:SetAlpha(1)
            mini:Hide()
        end
    end
    return rows
end

local function CountReady(snapshot)
    local ready, notReady, waiting = 0, 0, 0
    for _, member in ipairs(snapshot.members or {}) do
        if member.readyStatus == "ready" then
            ready = ready + 1
        elseif member.readyStatus == "notReady" then
            notReady = notReady + 1
        elseif member.readyStatus == "waiting" then
            waiting = waiting + 1
        end
    end
    return ready, notReady, waiting
end

local function ProgressRatio(popup)
    local snapshot = popup.snapshot
    if not snapshot then return 1 end
    local deadline = tonumber(snapshot.readyCheckDeadline)
    local duration = tonumber(snapshot.readyCheckDuration)
    if deadline and duration and duration > 0 and snapshot.readyCheckActive then
        local ratio = math.max(0, math.min(
            1, (deadline - Now()) / duration))
        popup._lastProgressRatio = ratio
        return ratio
    end
    if popup._lastProgressRatio ~= nil then
        return popup._lastProgressRatio
    end
    local ready, notReady = CountReady(snapshot)
    local total = #snapshot.members
    return total > 0 and (ready + notReady) / total or 1
end

local function UpdateProgressVisual(popup)
    if not popup.progressFill or not popup.progressTail then return end
    local width = math.max(1, popup.progress:GetWidth() or popup:GetWidth())
    local tailWidth = math.min(PROGRESS_TAIL_WIDTH, width)
    local ratio = ProgressRatio(popup)
    if ratio <= 0 then
        popup.progressFill:Hide()
        popup.progressTail:Hide()
        return
    end

    local solidWidth = math.max(1, ratio * math.max(1, width - tailWidth))
    popup.progressFill:SetWidth(solidWidth)
    popup.progressFill:Show()
    popup.progressTail:SetWidth(tailWidth)
    popup.progressTail:ClearAllPoints()
    popup.progressTail:SetPoint(
        "TOPLEFT", popup.progressFill, "TOPRIGHT", 0, 0)
    popup.progressTail:SetPoint(
        "BOTTOMLEFT", popup.progressFill, "BOTTOMRIGHT", 0, 0)
    popup.progressTail:Show()
end

local function UpdateProgressText(popup)
    local snapshot = popup.snapshot
    if not snapshot then return end

    local ready, notReady, waiting = CountReady(snapshot)
    local total = #snapshot.members
    local titlePrefix = snapshot.preview
        and "PRT Raid Check - Test"
        or "PRT Raid Check"
    local statusText
    if ready + notReady + waiting > 0 then
        statusText = (
            "%s - %d/%d Ready - %d Not Ready - %d Awaiting Response"
        ):format(titlePrefix, ready, total, notReady, waiting)
    else
        statusText = ("%s - %d Players"):format(titlePrefix, total)
    end

    local deadline = tonumber(snapshot.readyCheckDeadline)
    local duration = tonumber(snapshot.readyCheckDuration)
    if deadline and duration and duration > 0 and snapshot.readyCheckActive then
        statusText = statusText
            .. (" - %ds"):format(math.ceil(math.max(0, deadline - Now())))
    end
    popup.progressText:SetText(statusText)
end

local function BeginFade(popup, delay)
    popup._fadeStart = Now() + math.max(0, tonumber(delay) or 4)
    popup._fadeEnd = popup._fadeStart + FADE_DURATION
end

local function BuildColumnLayout(columns)
    local layout = {}
    local x = NAME_WIDTH
    for index, column in ipairs(columns) do
        local width = ColumnWidth(column)
        layout[index] = { x = x, width = width }
        x = x + width
    end
    return layout, x
end

local function AttachRightClickDismiss(frame, popup)
    if not frame or not frame.HookScript then return end
    frame:HookScript("OnMouseDown", function(_, button)
        local cfg = PRT:GetDB().raidCheck or {}
        if button == "RightButton"
            and cfg.dismissOnRightClick ~= false then
            popup:Hide()
        end
    end)
end

local function ApplyWindowMode(popup, snapshot, columns)
    local cfg = PRT:GetDB().raidCheck or {}
    local collapsed = cfg.collapsed == true
    popup.expanded:SetShown(not collapsed)
    popup.minimized:SetShown(collapsed)
    popup.collapseButton.label:SetText(collapsed and "v" or "^")

    if collapsed then
        local miniRows = UpdateMiniMembers(popup, snapshot.members)
        popup:SetSize(
            MINI_COLUMN_WIDTH * MINI_COLUMNS,
            HEADER_HEIGHT + miniRows * MINI_ROW_HEIGHT)
        return
    end

    local columnLayout, contentWidth = BuildColumnLayout(columns)
    local rowHeight = #snapshot.members <= 20 and 20 or 14
    local width = math.max(360, contentWidth + 2)
    local bodyHeight = math.max(rowHeight, #snapshot.members * rowHeight)
    popup:SetSize(
        width,
        HEADER_HEIGHT + COLUMN_HEADER_HEIGHT + bodyHeight)

    popup.playerHeader:SetWidth(NAME_WIDTH)
    for index, header in ipairs(popup.headerCells) do
        local column = columns[index]
        local layout = columnLayout[index]
        if column and layout then
            header._column = column
            header:ClearAllPoints()
            header:SetPoint("LEFT", layout.x, 0)
            header:SetWidth(layout.width)
            header.icon:SetTexture(column.icon)
            header.icon:SetShown(column.icon ~= nil)
            header.label:SetText(column.shortLabel)
            local setting = PRT:GetRaidCheckColumnSetting(column)
            ApplyHeaderCellAlignment(
                header, setting and setting.alignment)
            local details = column.multiAura
                and ("Showing up to %d icon%s%s."):format(
                    tonumber(setting.maxDisplay) or 1,
                    tonumber(setting.maxDisplay) == 1 and "" or "s",
                    setting.showCount and " with count" or "")
                or nil
            header._tooltipLines = {
                { column.label, 1, 1, 1 },
            }
            if details then
                header._tooltipLines[#header._tooltipLines + 1] = {
                    details, 0.72, 0.72, 0.72,
                }
            end
            header._tooltipLines = AppendClickHints(
                header._tooltipLines, column, nil)
            header:Show()
        else
            header._column = nil
            header:Hide()
        end
    end

    for index, row in ipairs(popup.rows) do
        local member = snapshot.members[index]
        if member then
            UpdateResultRow(
                row,
                member,
                columns,
                columnLayout,
                rowHeight,
                index)
        else
            row.member = nil
            for _, cell in ipairs(row.cells) do
                cell._column = nil
                cell._member = nil
            end
            row:Hide()
        end
    end
end

local function CreateRaidCheckWindow()
    local popup = W.CreatePopupFrame(
        "PRTRaidCheckWindow",
        620,
        240,
        {
            title = "",
            titleBarHeight = HEADER_HEIGHT,
            closeButton = false,
            bgColor = { 0.015, 0.015, 0.015, 0.96 },
            borderColor = { 0.28, 0.28, 0.28, 1 },
            strata = "FULLSCREEN_DIALOG",
        })

    popup.drag:HookScript("OnDragStop", function()
        SaveWindowPosition(popup)
    end)
    AttachRightClickDismiss(popup, popup)
    AttachRightClickDismiss(popup.drag, popup)

    popup.progress = CreateFrame("Frame", nil, popup.drag)
    popup.progress:SetAllPoints()

    popup.progressBackground =
        popup.progress:CreateTexture(nil, "BACKGROUND")
    popup.progressBackground:SetAllPoints()
    popup.progressBackground:SetColorTexture(0.08, 0.08, 0.08, 0.96)

    local teal = PRT.C.TITLE
    popup.progressFill = popup.progress:CreateTexture(nil, "ARTWORK")
    popup.progressFill:SetPoint("TOPLEFT")
    popup.progressFill:SetPoint("BOTTOMLEFT")
    popup.progressFill:SetColorTexture(teal[1], teal[2], teal[3], 0.92)

    popup.progressTail = popup.progress:CreateTexture(nil, "ARTWORK")
    popup.progressTail:SetPoint("TOP")
    popup.progressTail:SetPoint("BOTTOM")
    SetHorizontalGradient(
        popup.progressTail,
        { teal[1], teal[2], teal[3], 0.92 },
        { teal[1], teal[2], teal[3], 0 })

    popup.progressText = W.CreateLabel(
        popup.progress, "Raid Check", math.max(9, PRT.FONT_SIZE - 1),
        1, 1, 1)
    popup.progressText:SetPoint("CENTER")
    popup.progressText:SetFont(
        PRT.FONT, math.max(9, PRT.FONT_SIZE - 1), "OUTLINE")

    popup.closeButton = W.CreateCloseButton(
        popup.progress,
        function() popup:Hide() end,
        { size = 18, fontSize = 10 })
    popup.closeButton:SetPoint("RIGHT", -1, 0)
    AttachRightClickDismiss(popup.closeButton, popup)

    popup.collapseButton = W.CreateCloseButton(
        popup.progress,
        function()
            PRT:SetRaidCheckCollapsed(
                not (PRT:GetDB().raidCheck.collapsed == true))
        end,
        {
            text = "^",
            size = 18,
            fontSize = 11,
            textColor = { 0.9, 0.9, 0.9 },
            hoverTextColor = { 1, 0.82, 0 },
        })
    popup.collapseButton:SetPoint(
        "RIGHT", popup.closeButton, "LEFT", 0, 0)
    AttachRightClickDismiss(popup.collapseButton, popup)

    popup.expanded = CreateFrame("Frame", nil, popup)
    popup.expanded:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT)
    popup.expanded:SetPoint("BOTTOMRIGHT", -1, 1)

    popup.columnHeader = CreateFrame("Frame", nil, popup.expanded)
    popup.columnHeader:SetPoint("TOPLEFT")
    popup.columnHeader:SetPoint("TOPRIGHT")
    popup.columnHeader:SetHeight(COLUMN_HEADER_HEIGHT)
    W.AddBackground(popup.columnHeader, 0.055, 0.055, 0.055, 0.96)

    popup.playerHeader = W.CreateLabel(
        popup.columnHeader,
        "Player",
        math.max(9, PRT.FONT_SIZE - 1),
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    popup.playerHeader:SetPoint("LEFT", 7, 0)
    popup.playerHeader:SetJustifyH("LEFT")

    popup.playerHeaderHit =
        CreateFrame("Button", nil, popup.columnHeader)
    popup.playerHeaderHit:SetPoint("TOPLEFT")
    popup.playerHeaderHit:SetSize(
        NAME_WIDTH, COLUMN_HEADER_HEIGHT)
    popup.playerHeaderHit:RegisterForClicks(
        "LeftButtonUp", "RightButtonUp")
    popup.playerHeaderHit:SetFrameLevel(
        (popup.columnHeader:GetFrameLevel() or 1) + 3)
    popup.playerHeaderHit:SetScript("OnClick", function(_, button)
        SendColumnClick(popup, nil, nil, button)
    end)
    W.AttachTooltip(popup.playerHeaderHit, {
        anchor = "ANCHOR_TOP",
        getLines = function()
            return {
                { "Player List", 1, 1, 1 },
                {
                    "Left-click to report ready-check responses.",
                    0.35, 1, 0.7, true,
                },
            }
        end,
    })
    AttachRightClickDismiss(popup.playerHeaderHit, popup)

    popup.headerCells = {}
    for index = 1, MAX_COLUMNS do
        popup.headerCells[index] = CreateHeaderCell(popup.columnHeader)
        popup.headerCells[index]._popup = popup
        AttachRightClickDismiss(popup.headerCells[index], popup)
    end

    popup.body = CreateFrame("Frame", nil, popup.expanded)
    popup.body:SetPoint(
        "TOPLEFT", popup.columnHeader, "BOTTOMLEFT", 0, 0)
    popup.body:SetPoint(
        "BOTTOMRIGHT", popup.expanded, "BOTTOMRIGHT", 0, 0)

    popup.rows = {}
    for index = 1, MAX_ROWS do
        popup.rows[index] = CreateResultRow(popup.body)
        popup.rows[index]._popup = popup
        AttachRightClickDismiss(popup.rows[index], popup)
        for _, cell in ipairs(popup.rows[index].cells) do
            cell._popup = popup
            AttachRightClickDismiss(cell, popup)
        end
    end

    popup.minimized = CreateFrame("Frame", nil, popup)
    popup.minimized:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    popup.minimized:SetPoint("BOTTOMRIGHT")
    popup.miniMembers = {}
    for index = 1, MAX_ROWS do
        popup.miniMembers[index] = CreateMiniMember(popup.minimized)
        popup.miniMembers[index]._popup = popup
        AttachRightClickDismiss(popup.miniMembers[index], popup)
    end

    popup:SetScript("OnUpdate", function(self, elapsed)
        if self.snapshot and self.snapshot.preview
            and self.snapshot.readyCheckActive
            and self.snapshot.readyCheckDeadline
            and Now() >= self.snapshot.readyCheckDeadline then
            self.snapshot.readyCheckActive = false
            local cfg = PRT:GetDB().raidCheck or {}
            if cfg.autoClose ~= false then
                BeginFade(self, cfg.closeDelay)
            end
        end

        -- Both the timer bar and the window fade run every rendered frame.
        UpdateProgressVisual(self)
        if self._fadeStart and Now() >= self._fadeStart then
            local duration = math.max(0.01, self._fadeEnd - self._fadeStart)
            local progress = math.min(
                1, math.max(0, (Now() - self._fadeStart) / duration))
            local eased = progress * progress * (3 - 2 * progress)
            self:SetAlpha(1 - eased)
            if progress >= 1 then self:Hide() end
        end

        self._textElapsed = (self._textElapsed or 0) + elapsed
        if self._textElapsed >= 0.1 then
            self._textElapsed = 0
            UpdateProgressText(self)
        end
    end)

    popup:HookScript("OnHide", function(self)
        self:SetAlpha(1)
        self._fadeStart = nil
        self._fadeEnd = nil
        self._lastProgressRatio = nil
    end)

    ApplySavedPosition(popup)
    return popup
end

function PRT:SetRaidCheckCollapsed(collapsed)
    self:GetDB().raidCheck.collapsed = collapsed and true or false
    self:RefreshRaidCheckWindow()
end

function PRT:ApplyRaidCheckWindowSettings()
    local popup = self.raidCheckWindow
    if not popup then return end
    local cfg = self:GetDB().raidCheck or {}
    local frameStrata = NormalizeFrameStrata(cfg.frameStrata)
    popup._frontStrata = frameStrata
    popup:SetFrameStrata(frameStrata)
    popup:SetScale(math.max(0.5, math.min(
        1.5, tonumber(cfg.scale) or 1)))
    ApplySavedPosition(popup)
end

function PRT:ResetRaidCheckWindowPosition()
    local cfg = self:GetDB().raidCheck
    cfg.point, cfg.relPoint, cfg.x, cfg.y =
        "CENTER", "CENTER", 0, 0
    if self.raidCheckWindow then
        ApplySavedPosition(self.raidCheckWindow)
    end
end

function PRT:RefreshRaidCheckWindow()
    local popup = self.raidCheckWindow
    if not popup or not popup:IsShown() then return end

    local snapshot = popup._previewSnapshot
        or self:BuildRaidCheckSnapshot()
    local columns = self:GetRaidCheckColumnOrder(false, snapshot)
    popup.snapshot = snapshot
    popup.columns = columns
    ApplyWindowMode(popup, snapshot, columns)
    UpdateProgressVisual(popup)
    UpdateProgressText(popup)
end

function PRT:ShowRaidCheckWindow(opts)
    opts = opts or {}
    if not self.raidCheckWindow then
        self.raidCheckWindow = CreateRaidCheckWindow()
    end

    local popup = self.raidCheckWindow
    popup._source = opts.source or "manual"
    popup._readySerial = self._raidCheckReadySerial
    popup._previewSnapshot = opts.snapshot
    popup._fadeStart = nil
    popup._fadeEnd = nil
    popup._lastProgressRatio = nil
    popup:SetAlpha(1)

    self:ApplyRaidCheckWindowSettings()
    popup:Show()
    popup:BringToFront()
    if not popup._previewSnapshot then
        self:RequestRaidCheckDurability()
    end
    self:RefreshRaidCheckWindow()
end

function PRT:ShowRaidCheckTestPreview()
    self:ShowRaidCheckWindow({
        source = "preview",
        snapshot = self:BuildRaidCheckTestSnapshot(),
    })
end

function PRT:ToggleRaidCheckWindow()
    if self.raidCheckWindow and self.raidCheckWindow:IsShown() then
        self.raidCheckWindow:Hide()
    else
        self:ShowRaidCheckWindow({ source = "slash" })
    end
end

function PRT:FinishRaidCheckWindow(serial)
    local popup = self.raidCheckWindow
    if not popup or not popup:IsShown() then return end
    if popup._source ~= "readyCheck"
        or popup._readySerial ~= serial then
        return
    end
    local cfg = self:GetDB().raidCheck or {}
    if cfg.autoClose == false then return end
    BeginFade(popup, cfg.closeDelay)
end
