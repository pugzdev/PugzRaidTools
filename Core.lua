---------------------------------------------------------------------------
-- PugzRaidTools - Core
-- Addon namespace, utilities, saved variables, slash commands
---------------------------------------------------------------------------
local addonName, PRT = ...
_G.PugzRaidTools = PRT

PRT.VERSION = "1.3.0"

-- Media
PRT.FONT       = "Interface\\AddOns\\PugzRaidTools\\Media\\Fonts\\PTSansNarrow.ttf"
PRT.SND_MARIO  = "Interface\\AddOns\\PugzRaidTools\\Media\\Sounds\\MarioCoin.ogg"
PRT.SND_LINK   = "Interface\\AddOns\\PugzRaidTools\\Media\\Sounds\\Link.ogg"
PRT.FONT_SIZE = 12
PRT.FONT_SIZE_HEADER = 16
PRT.FONT_SIZE_TITLE = 20

-- Roster slot indices (shared with reorder engine)
PRT.RR_NAME     = 1
PRT.RR_SUBGROUP = 2
PRT.RR_INDEX    = 3
PRT.RR_LOCKED   = 4
PRT.RR_START    = 5

-- Classic Era Raid Instances (instanceMapID from GetInstanceInfo)
PRT.RAID_INSTANCES = {
    { id = 0,   name = "Any Raid" },
    { id = 249, name = "Onyxia's Lair" },
    { id = 309, name = "Zul'Gurub" },
    { id = 409, name = "Molten Core" },
    { id = 469, name = "Blackwing Lair" },
    { id = 509, name = "Ruins of Ahn'Qiraj" },
    { id = 531, name = "Temple of Ahn'Qiraj" },
    { id = 533, name = "Naxxramas" },
}

PRT.RAID_INSTANCE_MAP = {}
for _, info in ipairs(PRT.RAID_INSTANCES) do
    PRT.RAID_INSTANCE_MAP[info.id] = info.name
end

---------------------------------------------------------------------------
-- Raid Mark Icons
---------------------------------------------------------------------------
PRT.MARK_ICONS = {
    { id = 0, name = "Clear",    color = { 0.5, 0.5, 0.5 } },
    { id = 1, name = "Star",     color = { 1.0, 1.0, 0.0 } },
    { id = 2, name = "Circle",   color = { 1.0, 0.5, 0.0 } },
    { id = 3, name = "Diamond",  color = { 0.8, 0.2, 1.0 } },
    { id = 4, name = "Triangle", color = { 0.0, 1.0, 0.0 } },
    { id = 5, name = "Moon",     color = { 0.7, 0.7, 1.0 } },
    { id = 6, name = "Square",   color = { 0.0, 0.5, 1.0 } },
    { id = 7, name = "Cross",    color = { 1.0, 0.2, 0.2 } },
    { id = 8, name = "Skull",    color = { 1.0, 1.0, 1.0 } },
}

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
PRT.C = {
    TITLE       = { 0.2, 1.0, 0.6 },
    GOLD        = { 1.0, 0.82, 0.0 },
    WHITE       = { 1.0, 1.0, 1.0 },
    GRAY        = { 0.5, 0.5, 0.5 },
    RED         = { 1.0, 0.3, 0.3 },
    GREEN       = { 0.3, 1.0, 0.3 },
    YELLOW      = { 1.0, 1.0, 0.3 },
    SIDEBAR_BG  = { 0.08, 0.08, 0.08, 0.95 },
    SIDEBAR_SEL = { 0.13, 0.38, 0.13, 1.0 },
    CONTENT_BG  = { 0.04, 0.04, 0.04, 0.92 },
    FRAME_BG    = { 0.0, 0.0, 0.0, 0.92 },
    BORDER      = { 0.25, 0.25, 0.25, 1.0 },
    INPUT_BG    = { 0.08, 0.08, 0.08, 0.9 },
    BTN_BG      = { 0.14, 0.14, 0.14, 0.95 },
    BTN_HOVER   = { 0.22, 0.22, 0.22, 1.0 },
}

---------------------------------------------------------------------------
-- Utility functions
---------------------------------------------------------------------------
function PRT.CanonName(n)
    if not n then return "" end
    n = tostring(n)
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    n = n:gsub('^"+', ''):gsub('"+$', '')
    n = n:gsub("^'+", ""):gsub("'+$", "")
    n = n:gsub("%-.*$", "")
    return string.lower(n)
end

function PRT.Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function PRT:GetHomeRealmName()
    local realm = GetRealmName and GetRealmName() or ""
    realm = self.Trim(realm)
    if realm == "" and GetNormalizedRealmName then
        realm = self.Trim(GetNormalizedRealmName() or "")
    end
    return realm
end

function PRT.NormalizeRealmName(realm)
    realm = PRT.Trim(realm or "")
    if realm == "" then return "" end
    realm = string.lower(realm)
    realm = realm:gsub("[%s%p_]+", "")
    return realm
end

function PRT:SplitNameRealm(fullName, fillHomeRealm)
    local raw = self.Trim(fullName or "")
    raw = raw:gsub('^"+', ""):gsub('"+$', "")
    raw = raw:gsub("^'+", ""):gsub("'+$", "")
    if raw == "" then
        return "", ""
    end

    local name, realm = raw:match("^(.-)%-(.+)$")
    if not name then
        name = raw
        realm = ""
    end

    name = self.Trim(name)
    realm = self.Trim(realm or "")

    if fillHomeRealm and name ~= "" and realm == "" then
        realm = self:GetHomeRealmName()
    end

    return name, realm
end

function PRT:MakeCharacterFullName(name, realm, forceRealm)
    name = self.Trim(name or "")
    realm = self.Trim(realm or "")
    if name == "" then return "" end
    if realm == "" then return name end
    if not forceRealm
        and self.NormalizeRealmName(realm) == self.NormalizeRealmName(self:GetHomeRealmName()) then
        return name
    end
    return name .. "-" .. realm
end

function PRT:MakePlayerIdentityKey(name, realm)
    name = self.Trim(name or "")
    realm = self.Trim(realm or "")
    if name == "" then return "" end

    local baseName, embeddedRealm = self:SplitNameRealm(name, false)
    if embeddedRealm ~= "" then
        name = baseName
        realm = embeddedRealm
    end

    return string.lower(name) .. "@" .. self.NormalizeRealmName(realm)
end

-- Unsuffixed saved names represent characters on the user's current realm.
function PRT:GetPlayerIdentityKey(fullName)
    local name, realm = self:SplitNameRealm(fullName, true)
    return self:MakePlayerIdentityKey(name, realm)
end

-- GetRaidRosterInfo normally includes remote realms, but UnitFullName is used
-- as a fallback so cross-realm identity remains intact on clients that omit it.
function PRT:GetRaidMemberIdentity(raidIndex, rosterName)
    local name, realm = self:SplitNameRealm(rosterName, false)
    if realm == "" and raidIndex and UnitFullName then
        local unitName, unitRealm = UnitFullName("raid" .. raidIndex)
        if unitName and unitName ~= "" then
            local unitBaseName, embeddedRealm = self:SplitNameRealm(unitName, false)
            name = unitBaseName
            if embeddedRealm ~= "" then
                realm = embeddedRealm
            end
        end
        if unitRealm and unitRealm ~= "" then
            realm = unitRealm
        end
    end
    if realm == "" and name ~= "" then
        realm = self:GetHomeRealmName()
    end
    return name, realm
end

function PRT:GetRaidMemberIdentityKey(raidIndex, rosterName)
    local name, realm = self:GetRaidMemberIdentity(raidIndex, rosterName)
    return self:MakePlayerIdentityKey(name, realm)
end

function PRT:GetUnitIdentity(unit)
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    end
    if (not name or name == "") and UnitName then
        name, realm = UnitName(unit)
    end

    name = self.Trim(name or "")
    realm = self.Trim(realm or "")
    local baseName, embeddedRealm = self:SplitNameRealm(name, false)
    if embeddedRealm ~= "" then
        name = baseName
        realm = embeddedRealm
    end
    if name ~= "" and realm == "" then
        realm = self:GetHomeRealmName()
    end
    return name, realm
end

function PRT:GetUnitIdentityKey(unit)
    local name, realm = self:GetUnitIdentity(unit)
    return self:MakePlayerIdentityKey(name, realm)
end

function PRT:FindRaidUnitByIdentityKey(identityKey)
    if not identityKey or identityKey == "" then return nil end

    local count = GetNumGroupMembers()
    local sawUnitIdentity = false
    for raidIndex = 1, count do
        local unit = "raid" .. raidIndex
        local unitIdentityKey = self:GetUnitIdentityKey(unit)
        if unitIdentityKey ~= "" then
            sawUnitIdentity = true
        end
        if unitIdentityKey == identityKey then
            return unit, raidIndex
        end
    end

    -- Avoid pairing a partially rebuilt roster index with a different raidN
    -- token.
    if sawUnitIdentity then return nil end

    -- Compatibility fallback when this client exposes no unit identities.
    for raidIndex = 1, count do
        local rosterName = GetRaidRosterInfo(raidIndex)
        if rosterName and self:GetRaidMemberIdentityKey(raidIndex, rosterName) == identityKey then
            return "raid" .. raidIndex, raidIndex
        end
    end
end

function PRT.Print(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = tostring(select(i, ...)) end
    print("|cFF33FF99PugzRaidTools|r " .. table.concat(t, " "))
end

function PRT.GetNpcId(guid)
    if not guid then return nil end
    local npcId = select(6, strsplit("-", guid))
    return tonumber(npcId)
end

function PRT.StripRealm(name)
    if not name then return "" end
    return tostring(name):gsub("%-.*$", "")
end

function PRT.GetClassColor(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- Returns table of realm-aware identity key -> raid member information.
function PRT.GetRaidRoster()
    local roster = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup, _, _, classFile = GetRaidRosterInfo(i)
        if name and subgroup then
            local baseName, realm = PRT:GetRaidMemberIdentity(i, name)
            local key = PRT:MakePlayerIdentityKey(baseName, realm)
            if key ~= "" then
                roster[key] = {
                    name = name,
                    baseName = baseName,
                    realm = realm,
                    displayName = PRT:MakeCharacterFullName(baseName, realm, false),
                    classFile = classFile,
                    subgroup = subgroup,
                    index = i,
                }
            end
        end
    end
    return roster
end

---------------------------------------------------------------------------
-- Shared CLEU Dispatcher
-- Both AutoSwap and AutoMark register callbacks here so we only listen
-- to COMBAT_LOG_EVENT_UNFILTERED when at least one feature needs it.
---------------------------------------------------------------------------
PRT._cleuListeners  = {}
PRT._cleuRegistered = false

function PRT:RegisterCLEUListener(key, fn)
    self._cleuListeners[key] = fn
    self:_UpdateCLEURegistration()
end

function PRT:UnregisterCLEUListener(key)
    self._cleuListeners[key] = nil
    self:_UpdateCLEURegistration()
end

function PRT:_UpdateCLEURegistration()
    local need = false
    for _ in pairs(self._cleuListeners) do need = true; break end
    if need and not self._cleuRegistered then
        if not self._cleuFrame then
            self._cleuFrame = CreateFrame("Frame")
            self._cleuFrame:SetScript("OnEvent", function()
                for _, fn in pairs(PRT._cleuListeners) do fn() end
            end)
        end
        self._cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self._cleuRegistered = true
    elseif not need and self._cleuRegistered then
        self._cleuFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self._cleuRegistered = false
    end
end

---------------------------------------------------------------------------
-- Saved Variables defaults
---------------------------------------------------------------------------
PRT.DEFAULTS = {
    version = 1,
    compositions = {},   -- array of { name=string, roster={40 strings} }
    autoSwap = {
        enabled = false,
        triggers = {},            -- legacy flat array (migrated to swapPresets on load)
        swapPresets = {},         -- array of { name, triggers[], instanceId, allowAnywhere }; excluded from DeepMerge
        activeSwapPreset = "",    -- name of active preset
    },
    floatingList = {
        locked = false,
        hideOutsideRaid = false,
        mouseoverOnly = false,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
        scale = 1.0,
        fontSize = 14,
        fontOutline = "OUTLINE",
        textMode = "expand",
        width = 180,
        rowHeight = 20,
        textWidth = 180,
        bgAlpha = 0.7,
        shown = true,
    },
    settings = {
        mainBgAlpha      = 0.92,
        keepChanges      = false,
        forcePositions   = false,
        frameW           = 1000,
        frameH           = 600,
        minimapAngle     = 195,    -- degrees; 195° = bottom-left of minimap
        showMinimapIcon  = true,
        lastImportShape  = "",     -- last used import shape key ("8col","2col","1col","cooked")
        lastExportShape  = "8col", -- last used single-composition export shape
    },
    notification = {
        enabled   = true,
        fontSize  = 32,
        fontColor = { 1.0, 0.82, 0.0 },
        x         = 0,
        y         = 80,
        duration  = 3.0,
        sound     = false,
    },
    autoMark = {
        enabled       = false,
        activePreset  = "",
        presets       = {},   -- array of { name, markGroups[], instanceId, allowAnywhere }; excluded from DeepMerge
    },
    targetMarks = {
        enabled = false,
        activePreset = "",
        modifiers = {
            main = "CTRL",
            alt1 = "ALT",
            alt2 = "SHIFT",
        },
        presets = {},         -- array of { name, groups[] }; excluded from DeepMerge
    },
    prtProfiles = {
        activeProfile = "",
        profiles = {},        -- array of overall feature-preset and enabled-default mappings
    },
    profileFloat = {
        embedInGroupList = false,
        embeddedPosition = "top",
        embeddedHighlight = true,
        embeddedAlignment = "left",
        shown = false,
        mouseoverOnly = false,
        locked = false,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 160,
        scale = 1.0,
        width = 220,
        height = 30,
        fontSize = 12,
        textMode = "truncate",
        bgAlpha = 0.92,
        notificationEnabled = true,
        notificationSound = true,
        notificationX = 0,
        notificationY = 80,
    },
    rosterMatcher = {
        threshold = 50,
        aliases = {},         -- array of { id, label, characters={ { name, realm, classFile } } }
        nextAliasId = 1,
    },
    autoLog = {
        enabled = false,
    },
    raidCheck = {
        showOnReadyCheck = true,
        onlyLeaderAssist = true,
        checkWorldBuffs = true,
        checkFood = false,
        checkFlask = true,
        checkZanza = true,
        checkConsumes = true,
        checkPotions = true,
        checkDisallowed = true,
        checkBuffs = true,
        checkDurability = true,
        allianceBlessingsOnly = true,
        dismissOnRightClick = true,
        columnSettings = {},
        worldBuffValidity = {},
        sortMode = "classGroup",
        autoClose = true,
        closeDelay = 5,
        collapsed = false,
        columnOrder = {
            "worldBuffs",
            "attackPower",
            "disallowed",
            "flask",
            "zanza",
            "potions",
            "consumes",
            "food",
            "stamina",
            "druid",
            "intellect",
            "spirit",
            "shadow",
            "armor",
            "kings",
            "might",
            "wisdom",
            "salvation",
            "light",
            "durability",
        },
        scale = 1.0,
        frameStrata = "FULLSCREEN_DIALOG",
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
    },
    inviteTools = {
        enabled = true,
        activePreset = "",
        presets = {},
        bannedPlayers = {},       -- global realm-aware block list; not part of presets
        autoInvite = {
            enabled = false,
            keywords = { "inv" },
            guildOnly = false,
            autoAcceptTrusted = false,
            raidInvites = {
                enabled = false,
            },
        },
        autoPromote = {
            enabled = false,
            names = "",
            guildRankThreshold = 0, -- 0 = explicit names only; otherwise top N guild ranks
        },
        loot = {
            enabled = false,
            method = "group",
            assignMasterLooter = false,
            masterLooter = "",
            threshold = 1,
            onlyInRaid = true,
            zones = {
                naxxramas = false,
                aq40 = false,
                bwl = false,
                moltenCore = false,
                zulgurub = false,
                aq20 = false,
                blastedLands = false,
                azshara = false,
                ashenvale = false,
                hinterlands = false,
                duskwood = false,
                feralas = false,
            },
            customZones = {},
        },
        lootToChat = {
            enabled = false,
            includeItemLevel = false,
        },
        reinviteSnapshot = {
            createdAt = 0,
            members = {},
        },
    },
}

---------------------------------------------------------------------------
-- Deep merge defaults into saved table (preserves existing values)
---------------------------------------------------------------------------
local function DeepMerge(defaults, saved)
    if type(defaults) ~= "table" then return saved end
    if type(saved) ~= "table" then return defaults end
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            if type(v) == "table" then
                saved[k] = {}
                DeepMerge(v, saved[k])
            else
                saved[k] = v
            end
        elseif type(v) == "table" and type(saved[k]) == "table"
               and k ~= "compositions" and k ~= "triggers"
               and k ~= "presets" and k ~= "swapPresets"
               and k ~= "keywords" and k ~= "columnOrder" then
            DeepMerge(v, saved[k])
        end
    end
    return saved
end

---------------------------------------------------------------------------
-- Composition management
---------------------------------------------------------------------------
function PRT:GetDB()
    return PugzRaidToolsDB or self.DEFAULTS
end

function PRT:GetComp(name)
    local db = self:GetDB()
    for _, comp in ipairs(db.compositions) do
        if comp.name == name then return comp end
    end
end

function PRT:GetCompOrder()
    local db = self:GetDB()
    local order = {}
    for _, comp in ipairs(db.compositions) do
        order[#order + 1] = comp.name
    end
    return order
end

function PRT:AddComp(name, roster)
    local db = self:GetDB()
    roster = roster or {}
    while #roster < 40 do roster[#roster + 1] = "" end
    db.compositions[#db.compositions + 1] = { name = name, roster = roster }
    return true
end

function PRT:RemoveComp(name)
    local db = self:GetDB()
    for i, comp in ipairs(db.compositions) do
        if comp.name == name then
            table.remove(db.compositions, i)
            return true
        end
    end
    return false
end

function PRT:RenameComp(oldName, newName)
    local comp = self:GetComp(oldName)
    if not comp then return false end
    comp.name = newName
    local db = self:GetDB()
    -- Legacy flat triggers
    for _, trigger in ipairs(db.autoSwap.triggers) do
        if trigger.compName == oldName then trigger.compName = newName end
    end
    -- Swap presets
    for _, preset in ipairs(db.autoSwap.swapPresets or {}) do
        for _, trigger in ipairs(preset.triggers or {}) do
            if trigger.compName == oldName then trigger.compName = newName end
        end
    end
    -- Auto mark: swap triggers and smart comp references
    for _, amPreset in ipairs(db.autoMark.presets or {}) do
        for _, mg in ipairs(amPreset.markGroups or {}) do
            for _, st in ipairs(mg.swapTriggers or {}) do
                if st.compName == oldName then st.compName = newName end
            end
            if mg.smartComp == oldName then mg.smartComp = newName end
        end
    end
    return true
end

function PRT:UpdateCompRoster(name, roster)
    local comp = self:GetComp(name)
    if not comp then return false end
    while #roster < 40 do roster[#roster + 1] = "" end
    comp.roster = roster
    return true
end

function PRT:MoveComp(fromIndex, toIndex)
    local db = self:GetDB()
    if fromIndex == toIndex then return false end
    if fromIndex < 1 or fromIndex > #db.compositions then return false end
    if toIndex < 1 or toIndex > #db.compositions then return false end
    local comp = table.remove(db.compositions, fromIndex)
    table.insert(db.compositions, toIndex, comp)
    return true
end

-- Build target table (8 groups x 5 slots) from a flat roster array
function PRT:BuildTarget(roster)
    local target = {}
    for g = 1, 8 do
        target[g] = {}
        for s = 1, 5 do
            target[g][s] = { [self.RR_NAME] = "" }
        end
    end
    for i, name in ipairs(roster) do
        local g = math.floor((i - 1) / 5) + 1
        local s = ((i - 1) % 5) + 1
        if g >= 1 and g <= 8 then
            target[g][s][self.RR_NAME] = self:GetPlayerIdentityKey(name)
        end
    end
    return target
end

function PRT:FindDuplicateRosterSlots(roster)
    local identities = {}
    roster = roster or {}

    for slotIndex = 1, 40 do
        local raw = self.Trim(roster[slotIndex] or "")
        local key = self:GetPlayerIdentityKey(raw)
        if key ~= "" then
            local entry = identities[key]
            if not entry then
                local name, realm = self:SplitNameRealm(raw, true)
                entry = {
                    key = key,
                    displayName = self:MakeCharacterFullName(name, realm, true),
                    slots = {},
                }
                identities[key] = entry
            end
            entry.slots[#entry.slots + 1] = slotIndex
        end
    end

    local duplicatesBySlot = {}
    for _, entry in pairs(identities) do
        if #entry.slots > 1 then
            for _, slotIndex in ipairs(entry.slots) do
                duplicatesBySlot[slotIndex] = entry
            end
        end
    end

    return duplicatesBySlot
end

---------------------------------------------------------------------------
-- Import / Export
---------------------------------------------------------------------------
local function AppendRosterExportLines(lines, roster)
    roster = roster or {}
    local row = {}
    for i, name in ipairs(roster) do
        if name ~= "" then row[#row + 1] = name end
        if i % 5 == 0 or i == #roster then
            if #row > 0 then
                lines[#lines + 1] = table.concat(row, " ")
                row = {}
            end
        end
    end
end

function PRT:ExportRosterByShape(name, roster, shape)
    roster = roster or {}
    shape = shape or "8col"
    local lines = {}

    local function Slot(index)
        local value = PRT.Trim(tostring(roster[index] or ""))
        return value ~= "" and value or "-"
    end

    if shape == "2col" then
        for pair = 0, 3 do
            local leftGroup = pair * 2 + 1
            local rightGroup = leftGroup + 1
            for position = 1, 5 do
                lines[#lines + 1] = table.concat({
                    Slot((leftGroup - 1) * 5 + position),
                    Slot((rightGroup - 1) * 5 + position),
                }, " ")
            end
        end
    elseif shape == "1col" then
        for index = 1, 40 do
            lines[#lines + 1] = Slot(index)
        end
    elseif shape == "cooked" then
        lines[#lines + 1] = "[" .. tostring(name or "Imported") .. "]"
        for group = 1, 8 do
            local row = {}
            for position = 1, 5 do
                row[#row + 1] = Slot((group - 1) * 5 + position)
            end
            lines[#lines + 1] = table.concat(row, " ")
        end
    else
        -- 8 columns (one per group), with five raid-position rows.
        for position = 1, 5 do
            local row = {}
            for group = 1, 8 do
                row[#row + 1] = Slot((group - 1) * 5 + position)
            end
            lines[#lines + 1] = table.concat(row, " ")
        end
    end

    return table.concat(lines, "\n")
end

function PRT:ExportCompRoster(name, shape)
    local comp = self:GetComp(name)
    if not comp then return "" end
    return self:ExportRosterByShape(comp.name, comp.roster, shape)
end

function PRT:ExportComps(names)
    local db = self:GetDB()
    local lines = {}

    for _, comp in ipairs(db.compositions) do
        local include = not names
        if names then
            for _, n in ipairs(names) do
                if n == comp.name then include = true; break end
            end
        end
        if include then
            lines[#lines + 1] = "[" .. comp.name .. "]"
            AppendRosterExportLines(lines, comp.roster)
            lines[#lines + 1] = ""
        end
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Shaped Import: parse pasted text into a 40-slot roster based on layout.
-- shape = "8col" | "2col" | "1col" | "cooked"
---------------------------------------------------------------------------
function PRT:ParseCookedImport(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw):gsub('^"+', ""):gsub('"+$', "")

    local comps = {}
    local current

    local function FinishCurrent()
        if not current or current.name == "" or #current.roster == 0 then return end
        while #current.roster < 40 do current.roster[#current.roster + 1] = "" end
        for i = #current.roster, 41, -1 do current.roster[i] = nil end
        comps[#comps + 1] = current
    end

    local function AddRosterNames(line)
        if not current then return end
        for name in line:gmatch("%S+") do
            if #current.roster < 40 then
                current.roster[#current.roster + 1] = name == "-" and "" or name
            end
        end
    end

    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line ~= "" then
            local header, rest = line:match("^%[(.-)%]%s*(.*)$")
            if header then
                FinishCurrent()
                current = {
                    name = PRT.Trim(header),
                    roster = {},
                }
                AddRosterNames(rest or "")
            elseif current then
                AddRosterNames(line)
            end
        end
    end

    FinishCurrent()
    return comps
end

function PRT:ParseShapedImport(raw, shape)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")

    local lines = {}
    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end

    local roster = {}
    for i = 1, 40 do roster[i] = "" end

    if shape == "8col" then
        -- 8 columns (each column = one group), 5 rows
        for row = 1, math.min(5, #lines) do
            local words = {}
            for w in lines[row]:gmatch("%S+") do words[#words + 1] = w end
            for col = 1, math.min(8, #words) do
                roster[(col - 1) * 5 + row] = words[col] == "-" and "" or words[col]
            end
        end

    elseif shape == "2col" then
        -- 2 columns (group pairs), 20 rows: G1+G2, G3+G4, G5+G6, G7+G8
        for i = 1, math.min(20, #lines) do
            local pairIdx = math.floor((i - 1) / 5)  -- 0..3
            local pos     = ((i - 1) % 5) + 1        -- 1..5
            local leftG   = pairIdx * 2 + 1           -- 1,3,5,7
            local rightG  = leftG + 1                 -- 2,4,6,8
            local words = {}
            for w in lines[i]:gmatch("%S+") do words[#words + 1] = w end
            if words[1] and leftG <= 8 then
                roster[(leftG - 1) * 5 + pos] = words[1] == "-" and "" or words[1]
            end
            if words[2] and rightG <= 8 then
                roster[(rightG - 1) * 5 + pos] = words[2] == "-" and "" or words[2]
            end
        end

    elseif shape == "1col" then
        -- Single column, 40 rows (one name per line)
        for i = 1, math.min(40, #lines) do
            local value = PRT.Trim(lines[i])
            roster[i] = value == "-" and "" or value
        end

    elseif shape == "cooked" then
        local cookedComps = PRT:ParseCookedImport(raw)
        if cookedComps[1] then
            return cookedComps[1].roster
        end

        -- 5 columns (positions across), 8 rows (each row = one group)
        for row = 1, math.min(8, #lines) do
            local words = {}
            for w in lines[row]:gmatch("%S+") do words[#words + 1] = w end
            for col = 1, math.min(5, #words) do
                roster[(row - 1) * 5 + col] = words[col] == "-" and "" or words[col]
            end
        end
    end

    return roster
end

function PRT:ParseAutoSwapString(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- New block format: [AutoSwapTrigger] key=value blocks
    if raw:find("%[AutoSwapTrigger%]") or raw:find("%[AutoSwapPreset:") then
        return self:_ParseAutoSwapTriggerBlocks(raw)
    end

    -- Legacy format: [CompName] = npcId1 npcId2 ...
    local triggers = {}
    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line ~= "" then
            local comp, ids = line:match("^%[(.-)%]%s*=%s*(.*)$")
            if not comp then comp, ids = line:match("^(.-)%s*=%s*(.*)$") end
            comp = PRT.Trim(comp or "")
            ids = ids or ""
            if comp ~= "" then
                for num in ids:gmatch("%d+") do
                    local id = tonumber(num)
                    if id and id > 0 then
                        triggers[#triggers + 1] = {
                            compName  = comp,
                            npcId     = id,
                            count     = 1,
                            repeating = false,
                            enabled   = true,
                            note      = "",
                        }
                    end
                end
            end
        end
    end
    return triggers
end

---------------------------------------------------------------------------
-- Swap Preset helpers
---------------------------------------------------------------------------
function PRT:GetSwapPreset(name)
    if not name or name == "" then return nil end
    local db = self:GetDB()
    for _, p in ipairs(db.autoSwap.swapPresets or {}) do
        if p.name == name then return p end
    end
end

function PRT:GetActiveSwapPreset()
    local db = self:GetDB()
    local name = db.autoSwap.activeSwapPreset
    if name and name ~= "" then
        local p = self:GetSwapPreset(name)
        if p then return p end
    end
    -- Fallback: first preset
    if db.autoSwap.swapPresets and #db.autoSwap.swapPresets > 0 then
        db.autoSwap.activeSwapPreset = db.autoSwap.swapPresets[1].name
        return db.autoSwap.swapPresets[1]
    end
    return nil
end

---------------------------------------------------------------------------
-- Swap Preset Export / Import
---------------------------------------------------------------------------
--- Export a list of triggers to the block format
function PRT:ExportSwapTriggers(triggers)
    local lines = {}
    for _, t in ipairs(triggers or {}) do
        lines[#lines + 1] = "[AutoSwapTrigger]"
        lines[#lines + 1] = "comp="      .. (t.compName or "")
        lines[#lines + 1] = "npcId="     .. tostring(t.npcId or 0)
        lines[#lines + 1] = "count="     .. tostring(t.count or 1)
        lines[#lines + 1] = "repeating=" .. tostring(t.repeating and true or false)
        lines[#lines + 1] = "enabled="   .. tostring(t.enabled ~= false and true or false)
        lines[#lines + 1] = "note="      .. (t.note or "")
    end
    return table.concat(lines, "\n")
end

--- Export a full preset to a string
function PRT:ExportSwapPreset(preset)
    if not preset then return "" end
    local lines = {}
    lines[#lines + 1] = "[AutoSwapPreset: " .. (preset.name or "Unnamed") .. "]"
    lines[#lines + 1] = "instanceId="          .. tostring(preset.instanceId or 0)
    lines[#lines + 1] = "allowAnywhere="       .. tostring(preset.allowAnywhere and true or false)
    lines[#lines + 1] = "resetOnZoneOut="      .. tostring(preset.resetOnZoneOut and true or false)
    local rod = preset.resetOnDeath or {}
    lines[#lines + 1] = "resetOnDeathNpcId="   .. tostring(rod.npcId or 0)
    lines[#lines + 1] = "resetOnDeathCount="   .. tostring(rod.count or 1)
    lines[#lines + 1] = "resetOnDeathNote="    .. (rod.note or "")
    if #(preset.triggers or {}) > 0 then
        lines[#lines + 1] = self:ExportSwapTriggers(preset.triggers)
    end
    return table.concat(lines, "\n")
end

--- Parse [AutoSwapTrigger] blocks (new format)
function PRT:_ParseAutoSwapTriggerBlocks(raw)
    local triggers = {}
    local cur = nil
    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line == "[AutoSwapTrigger]" then
            cur = { compName = "", npcId = 0, count = 1,
                    repeating = false, enabled = true, note = "" }
            triggers[#triggers + 1] = cur
        elseif cur then
            local key, val = line:match("^(%w+)=(.*)$")
            if key then
                if     key == "comp"      then cur.compName  = val
                elseif key == "npcId"     then cur.npcId     = tonumber(val) or 0
                elseif key == "count"     then cur.count     = tonumber(val) or 1
                elseif key == "repeating" then cur.repeating = (val == "true")
                elseif key == "enabled"   then cur.enabled   = (val ~= "false")
                elseif key == "note"      then cur.note      = val
                end
            end
        end
    end
    return triggers
end

--- Parse a full preset string; returns (preset, nil) or (nil, triggers[])
--- If the string has a [AutoSwapPreset: Name] header, returns a preset object.
--- If it contains bare triggers or the old [Comp] = id format, returns triggers.
function PRT:ParseSwapPresetString(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)

    local presetName = raw:match("^%[AutoSwapPreset:%s*(.-)%]")
    if presetName then
        -- Parse preset-level fields from lines before the first trigger block
        local instanceId     = 0
        local allowAnywhere  = false
        local resetOnZoneOut = false
        local rodNpcId       = 0
        local rodCount       = 1
        local rodNote        = ""
        for line in raw:gmatch("[^\n]+") do
            line = PRT.Trim(line)
            if line:find("^%[AutoSwapTrigger%]") then break end
            local key, val = line:match("^(%w+)=(.*)$")
            if key then
                if     key == "instanceId"        then instanceId    = tonumber(val) or 0
                elseif key == "allowAnywhere"     then allowAnywhere = (val == "true")
                elseif key == "resetOnZoneOut"    then resetOnZoneOut = (val == "true")
                elseif key == "resetOnDeathNpcId" then rodNpcId = tonumber(val) or 0
                elseif key == "resetOnDeathCount" then rodCount = math.max(1, tonumber(val) or 1)
                elseif key == "resetOnDeathNote"  then rodNote  = val
                end
            end
        end
        local triggers = self:_ParseAutoSwapTriggerBlocks(raw)
        return {
            name          = PRT.Trim(presetName),
            triggers      = triggers,
            instanceId    = instanceId,
            allowAnywhere = allowAnywhere,
            resetOnZoneOut = resetOnZoneOut,
            resetOnDeath  = { npcId = rodNpcId, count = rodCount, note = rodNote },
        }, nil
    end

    -- No preset header — parse as triggers
    return nil, self:ParseAutoSwapString(raw)
end

---------------------------------------------------------------------------
-- Auto Mark Import/Export Serialization
---------------------------------------------------------------------------

--- Split string into at most N parts (last part keeps remaining text)
local function SplitN(s, sep, n)
    local parts = {}
    local start = 1
    for i = 1, n - 1 do
        local pos = s:find(sep, start, true)
        if not pos then break end
        parts[#parts + 1] = s:sub(start, pos - 1)
        start = pos + #sep
    end
    parts[#parts + 1] = s:sub(start)
    return parts
end

--- Export a single marking rule to a string
function PRT:ExportMarkRule(mg)
    if not mg then return "" end
    local lines = {}
    lines[#lines + 1] = "[Rule: " .. (mg.name or "Unnamed") .. "]"
    lines[#lines + 1] = "applyOn=" .. (mg.applyOn or "position")
    lines[#lines + 1] = "smartAssign=" .. tostring(mg.smartAssign and true or false)
    lines[#lines + 1] = "smartComp=" .. (mg.smartComp or "")
    lines[#lines + 1] = "unmarkAll=" .. tostring(mg.unmarkAll and true or false)
    lines[#lines + 1] = "repeatable=" .. tostring(mg.repeatable and true or false)
    lines[#lines + 1] = "retryUnavailable=" .. tostring(mg.retryUnavailable and true or false)
    lines[#lines + 1] = "retryDuration=" .. tostring(tonumber(mg.retryDuration) or 3)
    lines[#lines + 1] = "triggerMode=" .. (mg.triggerMode or "any")
    if mg.note and mg.note ~= "" then
        -- Escape embedded newlines so note fits on one key=value line
        lines[#lines + 1] = "note=" .. mg.note:gsub("\n", "\\n")
    end

    for _, mark in ipairs(mg.marks or {}) do
        lines[#lines + 1] = string.format("Mark: %d;%d;%s;%s",
            mark.icon or 0,
            mark.position or 0,
            mark.playerName or "",
            mark.note or "")
    end

    for _, trigger in ipairs(mg.npcTriggers or {}) do
        lines[#lines + 1] = string.format("NpcTrigger: %s;%d;%d;%s",
            trigger.name or "",
            trigger.npcId or 0,
            trigger.count or 1,
            trigger.note or "")
    end

    for _, trigger in ipairs(mg.swapTriggers or {}) do
        lines[#lines + 1] = string.format("SwapTrigger: %s;%s;%s",
            trigger.name or "",
            trigger.compName or "",
            trigger.note or "")
    end

    for _, cond in ipairs(mg.conditionals or {}) do
        lines[#lines + 1] = string.format("Conditional: %s;%s;%s",
            cond.triggerName or "",
            tostring(cond.mustBeTrue and true or false),
            tostring(cond.mustBeFalse and true or false))
    end

    return table.concat(lines, "\n")
end

--- Export an entire preset (header + all rules) to a string
function PRT:ExportMarkPreset(preset)
    if not preset then return "" end
    local lines = {}
    lines[#lines + 1] = "[Preset: " .. (preset.name or "Unnamed") .. "]"
    lines[#lines + 1] = "instanceId=" .. tostring(preset.instanceId or 0)
    lines[#lines + 1] = "allowAnywhere=" .. tostring(preset.allowAnywhere and true or false)
    for _, mg in ipairs(preset.markGroups or {}) do
        lines[#lines + 1] = self:ExportMarkRule(mg)
    end
    return table.concat(lines, "\n")
end

--- Parse one or more marking rules from a string
function PRT:ParseMarkRuleString(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)

    local rules = {}
    local cur = nil

    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line ~= "" then
            -- [Rule: Name] header
            local ruleName = line:match("^%[Rule:%s*(.-)%]$")
            if ruleName then
                cur = {
                    name         = PRT.Trim(ruleName),
                    note         = "",
                    applyOn      = "position",
                    smartAssign  = true,
                    smartComp    = "",
                    unmarkAll    = false,
                    repeatable   = false,
                    retryUnavailable = false,
                    retryDuration = 3,
                    triggerMode  = "any",
                    marks        = {},
                    npcTriggers  = {},
                    swapTriggers = {},
                    conditionals = {},
                }
                rules[#rules + 1] = cur
            elseif cur then
                -- Key=value settings
                local key, val = line:match("^(%w+)=(.*)$")
                if key then
                    if key == "applyOn" then        cur.applyOn     = val
                    elseif key == "smartAssign" then cur.smartAssign = (val == "true")
                    elseif key == "smartComp" then   cur.smartComp   = val
                    elseif key == "unmarkAll" then   cur.unmarkAll   = (val == "true")
                    elseif key == "repeatable" then  cur.repeatable  = (val == "true")
                    elseif key == "retryUnavailable" then cur.retryUnavailable = (val == "true")
                    elseif key == "retryDuration" then cur.retryDuration = tonumber(val) or 3
                    elseif key == "triggerMode" then  cur.triggerMode = val
                    elseif key == "note" then         cur.note = val:gsub("\\n", "\n")
                    end
                end

                -- Mark: icon;position;playerName;note
                local markData = line:match("^Mark:%s*(.+)$")
                if markData then
                    local parts = SplitN(markData, ";", 4)
                    cur.marks[#cur.marks + 1] = {
                        icon       = tonumber(parts[1]) or 0,
                        position   = tonumber(parts[2]) or 0,
                        playerName = parts[3] or "",
                        note       = parts[4] or "",
                    }
                end

                -- NpcTrigger: name;npcId;count;note
                local npcData = line:match("^NpcTrigger:%s*(.+)$")
                if npcData then
                    local parts = SplitN(npcData, ";", 4)
                    cur.npcTriggers[#cur.npcTriggers + 1] = {
                        name  = parts[1] or "",
                        npcId = tonumber(parts[2]) or 0,
                        count = tonumber(parts[3]) or 1,
                        note  = parts[4] or "",
                    }
                end

                -- SwapTrigger: name;compName;note
                local swapData = line:match("^SwapTrigger:%s*(.+)$")
                if swapData then
                    local parts = SplitN(swapData, ";", 3)
                    cur.swapTriggers[#cur.swapTriggers + 1] = {
                        name     = parts[1] or "",
                        compName = parts[2] or "",
                        note     = parts[3] or "",
                    }
                end

                -- Conditional: triggerName;mustBeTrue;mustBeFalse
                local condData = line:match("^Conditional:%s*(.+)$")
                if condData then
                    local parts = SplitN(condData, ";", 3)
                    local mustTrue  = (parts[2] or "true") == "true"
                    local mustFalse
                    if parts[3] then
                        mustFalse = parts[3] == "true"
                    else
                        -- Legacy 2-field format: derive mustBeFalse from mustBeTrue
                        mustFalse = not mustTrue
                    end
                    cur.conditionals[#cur.conditionals + 1] = {
                        triggerName = parts[1] or "",
                        mustBeTrue  = mustTrue,
                        mustBeFalse = mustFalse,
                    }
                end
            end
        end
    end

    return rules
end

--- Parse a full preset (header + rules) from a string
function PRT:ParseMarkPresetString(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)

    local presetName = raw:match("^%[Preset:%s*(.-)%]")
    if not presetName then return nil end

    local instanceId = 0
    local allowAnywhere = false
    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line:match("^%[Rule:%s*.-%]$") then
            break
        end

        local key, val = line:match("^(%w+)=(.*)$")
        if key == "instanceId" then
            instanceId = tonumber(val) or 0
        elseif key == "allowAnywhere" then
            allowAnywhere = (val == "true")
        end
    end

    local rules = self:ParseMarkRuleString(raw)

    return {
        name          = PRT.Trim(presetName),
        instanceId    = instanceId,
        allowAnywhere = allowAnywhere,
        markGroups    = rules,
    }
end

---------------------------------------------------------------------------
-- Raid-entry feature status warning
---------------------------------------------------------------------------
local function PRT_ColorText(text, color)
    color = color or PRT.C.WHITE
    local r = math.floor((color[1] or 1) * 255 + 0.5)
    local g = math.floor((color[2] or 1) * 255 + 0.5)
    local b = math.floor((color[3] or 1) * 255 + 0.5)
    return ("|cff%02x%02x%02x%s|r"):format(r, g, b, tostring(text or ""))
end

local function PRT_IsPresetActiveInCurrentZone(preset)
    if not preset then return false end
    if preset.allowAnywhere then return true end

    local filterId = preset.instanceId or 0
    local inInstance, instanceType = IsInInstance()
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()

    if filterId == 0 then
        return inInstance and instanceType == "raid"
    end
    return instanceMapID == filterId
end

local function PRT_FormatFeatureStatus(label, enabled, presetName, loadedHere, activeHere)
    local line = PRT_ColorText(label .. ":", PRT.C.TITLE) .. " "
    line = line .. PRT_ColorText(enabled and "Enabled" or "Disabled", enabled and PRT.C.GREEN or PRT.C.RED)
    line = line .. " " .. PRT_ColorText("-", PRT.C.TITLE) .. " "
    line = line .. PRT_ColorText(presetName and presetName ~= "" and presetName or "No preset", PRT.C.WHITE)
    if enabled then
        line = line .. " " .. PRT_ColorText(loadedHere and "(Profile Loaded)" or "(Profile Not Loaded)", PRT.C.TITLE)
        line = line .. " " .. PRT_ColorText(
            activeHere and "Active in this zone!" or "Not active in this zone!",
            activeHere and PRT.C.GREEN or PRT.C.RED)
    end
    return line
end

function PRT:GetRaidFeatureStatusLines(instanceMapID, featureKey)
    local db = self:GetDB()
    local swapPreset = self.GetActiveSwapPreset and self:GetActiveSwapPreset() or nil
    local markPreset = self.GetAutoMarkPreset and self:GetAutoMarkPreset(db.autoMark.activePreset) or nil

    local swapLoaded = false
    if swapPreset then
        local filterId = swapPreset.instanceId or 0
        swapLoaded = swapPreset.allowAnywhere or filterId == 0 or filterId == instanceMapID
    end

    local markLoaded = false
    if markPreset then
        local filterId = markPreset.instanceId or 0
        markLoaded = markPreset.allowAnywhere or filterId == 0 or filterId == instanceMapID
    end

    local lines = {}
    if not featureKey or featureKey == "autoswap" then
        lines[#lines + 1] = PRT_FormatFeatureStatus(
            "Group Auto Swapping",
            db.autoSwap.enabled,
            swapPreset and swapPreset.name,
            swapLoaded,
            PRT_IsPresetActiveInCurrentZone(swapPreset))
    end
    if not featureKey or featureKey == "automark" then
        lines[#lines + 1] = PRT_FormatFeatureStatus(
            "Player Auto Marking",
            db.autoMark.enabled,
            markPreset and markPreset.name,
            markLoaded,
            PRT_IsPresetActiveInCurrentZone(markPreset))
    end
    return lines
end

function PRT:ShowManualFeatureToggleNotification(featureKey)
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    local lines = self:GetRaidFeatureStatusLines(instanceMapID, featureKey)
    local text = table.concat(lines, "\n")

    if self.ShowNotification then
        self:ShowNotification(text, {
            color = { 1.0, 0.82, 0.0 },
            duration = 6,
            fontSize = 24,
            force = true,
            forceSound = true,
            soundFile = PRT.SND_LINK,
            width = 900,
        })
    end
end

function PRT:CheckRaidFeatureStatusWarning()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then
        self._lastRaidFeatureWarningKey = nil
        return
    end

    local instanceName, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    local key = tostring(instanceMapID or instanceName or "raid")
    if self._lastRaidFeatureWarningKey == key then return end
    self._lastRaidFeatureWarningKey = key

    local lines = self:GetRaidFeatureStatusLines(instanceMapID)
    local profile = self.GetActivePRTProfile and self:GetActivePRTProfile() or nil
    local profileLine = PRT_ColorText("PRT Profile:", PRT.C.TITLE)
        .. " " .. PRT_ColorText(profile and profile.name or "None", PRT.C.WHITE)
    local text = PRT_ColorText("PRT Zone Detected:", PRT.C.TITLE)
        .. " " .. PRT_ColorText(instanceName or "Raid", PRT.C.WHITE)
        .. "\n" .. profileLine
        .. "\n" .. table.concat(lines, "\n")
    if self.ShowNotification then
        self:ShowNotification(text, {
            color = { 1.0, 0.82, 0.0 },
            duration = 6,
            fontSize = 24,
            force = true,
            forceSound = true,
            soundFile = PRT.SND_LINK,
            width = 900,
        })
    end
end

function PRT:InitRaidFeatureStatusWarning()
    if self._raidFeatureWarningFrame then return end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function()
        C_Timer.After(1.0, function()
            if PRT.CheckRaidFeatureStatusWarning then
                PRT:CheckRaidFeatureStatusWarning()
            end
        end)
    end)
    self._raidFeatureWarningFrame = f
end

---------------------------------------------------------------------------
-- Auto Combat Logging
---------------------------------------------------------------------------

-- _autoLogActive tracks whether WE started logging, so we don't switch off
-- combat logging the user manually enabled themselves.
PRT._autoLogActive = false

function PRT:CheckAutoLog()
    local db = self:GetDB()
    if not (db.autoLog and db.autoLog.enabled) then return end
    -- Small delay so GetInstanceInfo() reflects the new zone accurately.
    C_Timer.After(2, function()
        local _, zoneType = GetInstanceInfo()
        if zoneType == "raid" then
            if not LoggingCombat() then
                LoggingCombat(true)
                PRT._autoLogActive = true
                PRT.Print("Combat logging started.")
            end
        else
            if PRT._autoLogActive then
                LoggingCombat(false)
                PRT._autoLogActive = false
                PRT.Print("Combat logging stopped.")
            end
        end
    end)
end

function PRT:UpdateAutoLogListeners()
    local db = self:GetDB()
    local frame = PRT._autoLogFrame
    if not frame then return end
    frame:UnregisterAllEvents()
    if db.autoLog and db.autoLog.enabled then
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:CheckAutoLog()
    elseif PRT._autoLogActive and LoggingCombat() then
        LoggingCombat(false)
        PRT._autoLogActive = false
        PRT.Print("Combat logging stopped.")
    end
end

function PRT:InitAutoLog()
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function()
        PRT:CheckAutoLog()
    end)
    PRT._autoLogFrame = frame
    PRT:UpdateAutoLogListeners()
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if addon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    if not PugzRaidToolsDB then PugzRaidToolsDB = {} end
    local savedFloat = PugzRaidToolsDB.floatingList
    local migrateFloatWidth = type(savedFloat) == "table"
        and savedFloat.width == nil
        and tonumber(savedFloat.textWidth)
    local legacyFloatWidth = migrateFloatWidth
        and tonumber(savedFloat.textWidth) or nil
    DeepMerge(PRT.DEFAULTS, PugzRaidToolsDB)
    if migrateFloatWidth then
        PugzRaidToolsDB.floatingList.width = legacyFloatWidth
    end
    PRT.db = PugzRaidToolsDB

    PRT.Print("v" .. PRT.VERSION .. " loaded. Type /prt to open.")

    if PRT.InitReorder then PRT:InitReorder() end
    if PRT.InitPositionSort then PRT:InitPositionSort() end
    if PRT.InitAutoSwap then PRT:InitAutoSwap() end
    if PRT.InitAutoMark then PRT:InitAutoMark() end
    if PRT.InitTargetMarks then PRT:InitTargetMarks() end
    if PRT.InitInviteToolsPresets then PRT:InitInviteToolsPresets() end
    if PRT.InitPRTProfiles then PRT:InitPRTProfiles() end
    if PRT.InitRaidFeatureStatusWarning then PRT:InitRaidFeatureStatusWarning() end
    if PRT.InitAutoLog then PRT:InitAutoLog() end
    if PRT.InitRaidCheck then PRT:InitRaidCheck() end
    if PRT.InitInviteTools then PRT:InitInviteTools() end
    if PRT.InitFloatingList then PRT:InitFloatingList() end
    if PRT.InitProfileFloat then PRT:InitProfileFloat() end
    if PRT.CreateMinimapButton then PRT:CreateMinimapButton() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_PRT1 = "/prt"
local function PRT_ExtractSlashArgument(rawMsg, command)
    rawMsg = PRT.Trim(rawMsg or "")
    local typedCommand, arg = rawMsg:match("^(%S+)%s+(.+)$")
    if not typedCommand or string.lower(typedCommand) ~= command then arg = "" end
    arg = arg or ""
    arg = PRT.Trim(arg)
    arg = arg:gsub('^"(.*)"$', "%1")
    arg = arg:gsub("^'(.*)'$", "%1")
    return PRT.Trim(arg)
end

local function PRT_ClassColorText(name, classFile)
    if classFile and classFile ~= "" then
        local r, g, b = PRT.GetClassColor(classFile)
        return PRT_ColorText(name, { r, g, b })
    end
    return PRT_ColorText(name, PRT.C.GRAY)
end

SlashCmdList["PRT"] = function(msg)
    local rawMsg = PRT.Trim(msg or "")
    local msg = string.lower(rawMsg):gsub("%s+", " ")

    if msg == "" or msg == "config" or msg == "options" then
        if PRT.ToggleMainFrame then PRT:ToggleMainFrame() end
    elseif msg == "check" then
        if PRT.ToggleRaidCheckWindow then PRT:ToggleRaidCheckWindow() end
    elseif msg == "invites on" then
        if PRT.SetRaidInvitesEnabled then PRT:SetRaidInvitesEnabled(true, true) end
    elseif msg == "invites off" then
        if PRT.SetRaidInvitesEnabled then PRT:SetRaidInvitesEnabled(false, true) end
    elseif msg == "invites" then
        if PRT.GetRaidInvitesEnabled and PRT:GetRaidInvitesEnabled() then
            PRT.Print("Raid Invites is enabled.")
        else
            PRT.Print("Raid Invites is disabled.")
        end
    elseif msg == "loot" then
        if PRT.LinkLootToChat then PRT:LinkLootToChat(true) end
    elseif msg == "ban" then
        PRT.Print("Usage: /prt ban PlayerName or PlayerName-Realm")
    elseif msg == "unban" then
        PRT.Print("Usage: /prt unban PlayerName or PlayerName-Realm")
    elseif msg:match("^ban%s+") then
        local playerName = PRT_ExtractSlashArgument(rawMsg, "ban")
        if playerName == "" then
            PRT.Print("Usage: /prt ban PlayerName or PlayerName-Realm")
        elseif PRT.AddInviteBan then
            PRT:AddInviteBan(playerName)
        end
    elseif msg:match("^unban%s+") then
        local playerName = PRT_ExtractSlashArgument(rawMsg, "unban")
        if playerName == "" then
            PRT.Print("Usage: /prt unban PlayerName or PlayerName-Realm")
        elseif PRT.RemoveInviteBan then
            PRT:RemoveInviteBan(playerName)
        end
    elseif msg == "banlist" then
        if PRT.PrintInviteBanList then PRT:PrintInviteBanList() end
    elseif msg == "disband" or msg == "dis" then
        if PRT.DisbandWithSnapshot then PRT:DisbandWithSnapshot() end
    elseif msg == "reinv" or msg == "reinvite" then
        if PRT.ReinviteSnapshot then PRT:ReinviteSnapshot() end
    elseif msg:match("^who%s+") then
        local query = PRT_ExtractSlashArgument(rawMsg, "who")
        if query == "" then
            PRT.Print("Usage: /prt who charactername (quotes optional)")
            return
        end
        local matches = PRT.FindAliasesByCharacterQuery and PRT:FindAliasesByCharacterQuery(query) or {}
        if #matches == 0 then
            PRT.Print("No alias match found for \"" .. query .. "\".")
            return
        end
        for _, result in ipairs(matches) do
            local displayName = PRT:MakeCharacterFullName(result.character.name, result.character.realm, true)
            local prefix = PRT_ColorText("PRT", PRT.C.TITLE)
            print(prefix .. " \"" .. PRT_ClassColorText(displayName, result.character.classFile)
                .. "\" is \"" .. PRT_ColorText(result.alias.label or "", PRT.C.WHITE) .. "\".")
        end
    elseif msg:match("^alias%s+") then
        local query = PRT_ExtractSlashArgument(rawMsg, "alias")
        if query == "" then
            PRT.Print("Usage: /prt alias aliasname (quotes optional)")
            return
        end
        local alias = PRT.GetAliasByLabel and PRT:GetAliasByLabel(query) or nil
        if not alias then
            PRT.Print("Alias \"" .. query .. "\" not found.")
            return
        end
        print(PRT_ColorText("PRT", PRT.C.TITLE) .. " \""
            .. PRT_ColorText(alias.label or query, PRT.C.WHITE) .. "\" characters:")
        for _, character in ipairs(alias.characters or {}) do
            local displayName = PRT:MakeCharacterFullName(character.name, character.realm, true)
            print(PRT_ClassColorText(displayName, character.classFile))
        end
    elseif msg == "reset" then
        if PRT.ResetKillCounters then PRT:ResetKillCounters() end
    elseif msg == "resetframe" or msg == "frame reset" or msg == "size reset" then
        if PRT.ResetMainFrameSize then PRT:ResetMainFrameSize() end
    elseif msg == "debugui on" then
        if PRT.SetMainFrameDebug then PRT:SetMainFrameDebug(true) end
    elseif msg == "debugui off" then
        if PRT.SetMainFrameDebug then PRT:SetMainFrameDebug(false) end
    elseif msg == "debugui" or msg == "debug ui" then
        if PRT.DumpMainFrameDebug then PRT:DumpMainFrameDebug() end
    elseif msg == "list" then
        if PRT.ToggleFloatingList then PRT:ToggleFloatingList() end
    elseif msg == "lock" then
        if PRT.db then
            PRT.db.floatingList.locked = not PRT.db.floatingList.locked
            PRT.Print("Floating list " .. (PRT.db.floatingList.locked and "locked" or "unlocked"))
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
        end
    elseif msg == "groups show" then
        if PRT.db then
            PRT.db.floatingList.shown = true
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
            PRT.Print("Floating list shown.")
        end
    elseif msg == "groups hide" then
        if PRT.db then
            PRT.db.floatingList.shown = false
            if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
            PRT.Print("Floating list hidden.")
        end
    elseif msg == "autoswap on" then
        if PRT.db then
            PRT.db.autoSwap.enabled = true
            if PRT.UpdateAutoSwapListeners then PRT:UpdateAutoSwapListeners() end
            if PRT.UpdateMinimapIconTint then PRT:UpdateMinimapIconTint() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("autoswap") end
            PRT.Print("Auto Swap enabled.")
        end
    elseif msg == "autoswap off" then
        if PRT.db then
            PRT.db.autoSwap.enabled = false
            if PRT.UpdateAutoSwapListeners then PRT:UpdateAutoSwapListeners() end
            if PRT.UpdateMinimapIconTint then PRT:UpdateMinimapIconTint() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("autoswap") end
            PRT.Print("Auto Swap disabled.")
        end
    elseif msg == "automark on" then
        if PRT.db then
            PRT.db.autoMark.enabled = true
            if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("automark") end
            PRT.Print("Auto Marking enabled.")
        end
    elseif msg == "automark off" then
        if PRT.db then
            PRT.db.autoMark.enabled = false
            if PRT.UpdateAutoMarkListeners then PRT:UpdateAutoMarkListeners() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            if PRT.ShowManualFeatureToggleNotification then PRT:ShowManualFeatureToggleNotification("automark") end
            PRT.Print("Auto Marking disabled.")
        end
    elseif msg == "targetmarks on" then
        if PRT.db then
            PRT.db.targetMarks.enabled = true
            if PRT.HandleTargetMarksModifierChange then PRT:HandleTargetMarksModifierChange() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            PRT.Print("Target Marks enabled.")
        end
    elseif msg == "targetmarks off" then
        if PRT.db then
            PRT.db.targetMarks.enabled = false
            if PRT.HandleTargetMarksModifierChange then PRT:HandleTargetMarksModifierChange() end
            if PRT.RefreshFeatureToggleUI then PRT:RefreshFeatureToggleUI() end
            PRT.Print("Target Marks disabled.")
        end
    elseif msg == "markreset" then
        if PRT.ResetAutoMarkCounters then PRT:ResetAutoMarkCounters() end
    elseif msg == "sortlog" or msg == "sort log" then
        if PRT.ShowPositionSortLog then PRT:ShowPositionSortLog() end
    elseif msg == "sortlog clear" or msg == "sort log clear" then
        if PRT.ClearPositionSortLog then
            PRT:ClearPositionSortLog()
            PRT.Print("Position sort log cleared.")
        end
    elseif msg == "commands" then
        if PRT.PrintRaidCheckChatCommands then
            PRT:PrintRaidCheckChatCommands()
        end
    elseif msg == "help" then
        PRT.Print("Commands:")
        PRT.Print("  /prt - Toggle config window")
        PRT.Print("  /prt check - Toggle the Raid Check window")
        PRT.Print("  /rt check - Toggle the Raid Check window")
        PRT.Print("  /prt commands - List Raid Check chat commands")
        PRT.Print("  /prt list - Toggle floating list")
        PRT.Print("  /prt lock - Toggle floating list lock")
        PRT.Print("  /prt resetframe - Reset config window size")
        PRT.Print("  /prt debugui on|off - Record config-window resize diagnostics")
        PRT.Print("  /prt debugui - Print config-window state and recent resize trace")
        PRT.Print("  /prt groups show - Show floating list")
        PRT.Print("  /prt groups hide - Hide floating list")
        PRT.Print("  /prt autoswap on - Enable Auto Swap")
        PRT.Print("  /prt autoswap off - Disable Auto Swap")
        PRT.Print("  /prt reset - Reset auto-swap kill counters")
        PRT.Print("  /prt automark on - Enable Auto Marking")
        PRT.Print("  /prt automark off - Disable Auto Marking")
        PRT.Print("  /prt targetmarks on - Enable Target Marks")
        PRT.Print("  /prt targetmarks off - Disable Target Marks")
        PRT.Print("  /prt markreset - Reset auto-mark kill counters")
        PRT.Print("  /prt ban PlayerName[-Realm] - Block a player from keyword invites")
        PRT.Print("  /prt unban PlayerName[-Realm] - Remove an invite block")
        PRT.Print("  /prt banlist - List players blocked from keyword invites")
        PRT.Print("  /prt invites on - Enable queued party-to-raid invites")
        PRT.Print("  /prt invites off - Disable queued party-to-raid invites")
        PRT.Print("  /prt loot - Link items from the current loot window to chat")
        PRT.Print("  /prt disband - Save the raid roster and disband")
        PRT.Print("  /prt reinv - Invite players from the last disband snapshot")
        PRT.Print("  /prt sortlog - Open the position sort event log")
        PRT.Print("  /prt sortlog clear - Clear the position sort event log")
        PRT.Print("  /prt who charactername - Show the alias for a stored character")
        PRT.Print("  /prt alias aliasname - List characters stored under an alias")
        PRT.Print("  /prt help - Show this help")
    else
        PRT.Print("Unknown command. Type /prt help")
    end
end
