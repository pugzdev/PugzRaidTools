---------------------------------------------------------------------------
-- PugzRaidTools - Invite & Loot Tools
-- Keyword invites, realm-aware blocks, auto-promote, loot prompts, and
-- disband/reinvite snapshots.
---------------------------------------------------------------------------
local _, PRT = ...

PRT.INVITE_LOOT_METHODS = {
    { value = "freeforall",      text = "Free For All",       id = 0 },
    { value = "roundrobin",      text = "Round Robin",        id = 1 },
    { value = "master",          text = "Master Loot",        id = 2 },
    { value = "group",           text = "Group Loot",         id = 3 },
    { value = "needbeforegreed", text = "Need Before Greed",  id = 4 },
}

local function GetQualityText(quality, label, fallbackHex)
    local colorHex = fallbackHex
    if GetItemQualityColor then
        local _, _, _, apiHex = GetItemQualityColor(quality)
        if apiHex and apiHex ~= "" then
            colorHex = apiHex:gsub("^|c", ""):gsub("|r$", "")
        end
    end
    return "|c" .. colorHex .. label .. "|r"
end

PRT.INVITE_LOOT_THRESHOLDS = {
    {
        value = 1,
        text = GetQualityText(1, "Common (White)", "ffffffff"),
        plainText = "Common (White)",
    },
    {
        value = 2,
        text = GetQualityText(2, "Uncommon (Green)", "ff1eff00"),
        plainText = "Uncommon (Green)",
    },
    {
        value = 3,
        text = GetQualityText(3, "Rare (Blue)", "ff0070dd"),
        plainText = "Rare (Blue)",
    },
    {
        value = 4,
        text = GetQualityText(4, "Epic (Purple)", "ffa335ee"),
        plainText = "Epic (Purple)",
    },
}

PRT.INVITE_LOOT_ZONES = {
    { key = "naxxramas",    name = "Naxxramas",             instanceId = 533 },
    { key = "aq40",         name = "Ahn'Qiraj",             instanceId = 531 },
    { key = "bwl",          name = "Blackwing Lair",        instanceId = 469 },
    { key = "moltenCore",   name = "Molten Core",           instanceId = 409 },
    { key = "zulgurub",     name = "Zul'Gurub",             instanceId = 309 },
    { key = "aq20",         name = "Ruins of Ahn'Qiraj",    instanceId = 509 },
    { key = "blastedLands", name = "Blasted Lands",         uiMapId = 1419 },
    { key = "azshara",      name = "Azshara",               uiMapId = 1447 },
    { key = "ashenvale",    name = "Ashenvale",              uiMapId = 1440 },
    { key = "hinterlands",  name = "The Hinterlands",        uiMapId = 1425 },
    { key = "duskwood",     name = "Duskwood",               uiMapId = 1431 },
    { key = "feralas",      name = "Feralas",                uiMapId = 1444 },
}

local lootMethodByValue = {}
local lootMethodById = {}
for _, method in ipairs(PRT.INVITE_LOOT_METHODS) do
    lootMethodByValue[method.value] = method
    lootMethodById[method.id] = method
end

local lootThresholdByValue = {}
for _, threshold in ipairs(PRT.INVITE_LOOT_THRESHOLDS) do
    lootThresholdByValue[threshold.value] = threshold
end

local lootZoneByInstanceId = {}
local lootZoneByMapId = {}
local lootZoneByName = {}
for _, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
    if zone.instanceId then lootZoneByInstanceId[zone.instanceId] = zone end
    if zone.uiMapId then lootZoneByMapId[zone.uiMapId] = zone end
    lootZoneByName[string.lower(zone.name)] = zone
end

local function GetConfig()
    return PRT:GetDB().inviteTools
end

local RefreshPanel

local function GetInviteBanStore()
    local store = GetConfig()
    local legacy = type(store.autoInvite) == "table"
        and type(store.autoInvite.bannedPlayers) == "table"
        and store.autoInvite.bannedPlayers
        or nil
    if type(store.bannedPlayers) ~= "table" then store.bannedPlayers = {} end
    if legacy and legacy ~= store.bannedPlayers then
        for identityKey, entry in pairs(legacy) do
            if store.bannedPlayers[identityKey] == nil then
                store.bannedPlayers[identityKey] = entry
            end
        end
    end
    if type(store.autoInvite) == "table" then
        store.autoInvite.bannedPlayers = nil
    end
    return store.bannedPlayers
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function Bool(value, fallback)
    if value == nil then return fallback and true or false end
    return value and true or false
end

local function NormalizeCustomZones(zones)
    local normalized = {}
    local seen = {}
    for _, zone in ipairs(type(zones) == "table" and zones or {}) do
        local name
        local uiMapId
        if type(zone) == "table" then
            name = PRT.Trim(tostring(zone.name or ""))
            uiMapId = tonumber(zone.uiMapId)
        else
            name = PRT.Trim(tostring(zone or ""))
        end
        local key = string.lower(name)
        if name ~= "" and not seen[key] then
            seen[key] = true
            normalized[#normalized + 1] = {
                name = name,
                uiMapId = uiMapId,
            }
        end
    end
    return normalized
end

local function NormalizeInviteToolsPreset(preset)
    preset = type(preset) == "table" and preset or {}
    preset.name = PRT.Trim(tostring(preset.name or ""))
    if preset.name == "" then preset.name = "Preset" end

    local autoInvite = type(preset.autoInvite) == "table" and preset.autoInvite or {}
    autoInvite.enabled = Bool(autoInvite.enabled, false)
    autoInvite.keywords = type(autoInvite.keywords) == "table" and autoInvite.keywords or { "inv" }
    autoInvite.guildOnly = Bool(autoInvite.guildOnly, false)
    autoInvite.autoAcceptTrusted = Bool(autoInvite.autoAcceptTrusted, false)
    autoInvite.raidInvites = type(autoInvite.raidInvites) == "table" and autoInvite.raidInvites or {}
    autoInvite.raidInvites.enabled = Bool(autoInvite.raidInvites.enabled, false)
    autoInvite.bannedPlayers = nil
    preset.autoInvite = autoInvite

    local autoPromote = type(preset.autoPromote) == "table" and preset.autoPromote or {}
    autoPromote.enabled = Bool(autoPromote.enabled, false)
    autoPromote.names = tostring(autoPromote.names or "")
    autoPromote.guildRankThreshold = tonumber(autoPromote.guildRankThreshold) or 0
    preset.autoPromote = autoPromote

    local loot = type(preset.loot) == "table" and preset.loot or {}
    loot.enabled = Bool(loot.enabled, false)
    loot.method = lootMethodByValue[loot.method] and loot.method or "group"
    loot.assignMasterLooter = Bool(loot.assignMasterLooter, false)
    loot.masterLooter = PRT.Trim(tostring(loot.masterLooter or ""))
    loot.threshold = tonumber(loot.threshold) or 1
    if not lootThresholdByValue[loot.threshold] then loot.threshold = 1 end
    loot.onlyInRaid = Bool(loot.onlyInRaid, true)
    loot.zones = type(loot.zones) == "table" and loot.zones or {}
    for _, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
        loot.zones[zone.key] = Bool(loot.zones[zone.key], false)
    end
    loot.customZones = NormalizeCustomZones(loot.customZones)
    preset.loot = loot

    local lootToChat = type(preset.lootToChat) == "table" and preset.lootToChat or {}
    lootToChat.enabled = Bool(lootToChat.enabled, false)
    lootToChat.includeItemLevel = Bool(lootToChat.includeItemLevel, false)
    preset.lootToChat = lootToChat
    return preset
end

local function SnapshotInviteToolsPreset(name, source)
    source = source or GetConfig()
    return NormalizeInviteToolsPreset({
        name = name,
        autoInvite = DeepCopy(source.autoInvite),
        autoPromote = DeepCopy(source.autoPromote),
        loot = DeepCopy(source.loot),
        lootToChat = DeepCopy(source.lootToChat),
    })
end

local function FindInviteToolsPreset(store, name)
    for _, preset in ipairs(store and store.presets or {}) do
        if preset.name == name then return preset end
    end
end

local function MakeUniqueInviteToolsPresetName(store, requested)
    local base = PRT.Trim(tostring(requested or ""))
    if base == "" then base = "Imported Preset" end
    if not FindInviteToolsPreset(store, base) then return base end
    local suffix = 2
    while FindInviteToolsPreset(store, base .. " (" .. suffix .. ")") do
        suffix = suffix + 1
    end
    return base .. " (" .. suffix .. ")"
end

function PRT:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    store.enabled = Bool(store.enabled, true)
    store.presets = type(store.presets) == "table" and store.presets or {}
    store.activePreset = tostring(store.activePreset or "")
    GetInviteBanStore()

    for index, preset in ipairs(store.presets) do
        store.presets[index] = NormalizeInviteToolsPreset(preset)
    end
    if #store.presets == 0 then
        store.presets[1] = SnapshotInviteToolsPreset("Default", store)
    end
    if not FindInviteToolsPreset(store, store.activePreset) then
        store.activePreset = store.presets[1].name
    end
end

function PRT:GetInviteToolsPreset(name)
    return FindInviteToolsPreset(GetConfig(), name)
end

function PRT:GetActiveInviteToolsPreset()
    local store = GetConfig()
    return FindInviteToolsPreset(store, store.activePreset)
end

function PRT:CreateInviteToolsPreset(name)
    self:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    local cleanName = PRT.Trim(tostring(name or ""))
    if cleanName == "" then return nil, "Enter a preset name." end
    if FindInviteToolsPreset(store, cleanName) then
        return nil, "An Invite & Loot preset with that name already exists."
    end
    local preset = SnapshotInviteToolsPreset(cleanName, store)
    store.presets[#store.presets + 1] = preset
    return preset
end

function PRT:RenameInviteToolsPreset(oldName, newName)
    self:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    local preset = FindInviteToolsPreset(store, oldName)
    local cleanName = PRT.Trim(tostring(newName or ""))
    if not preset then return false, "That Invite & Loot preset no longer exists." end
    if cleanName == "" then return false, "Enter a preset name." end
    local existing = FindInviteToolsPreset(store, cleanName)
    if existing and existing ~= preset then
        return false, "An Invite & Loot preset with that name already exists."
    end

    preset.name = cleanName
    if store.activePreset == oldName then store.activePreset = cleanName end
    if self.RenamePRTProfilePresetReference then
        self:RenamePRTProfilePresetReference("inviteTools", oldName, cleanName)
    end
    return true
end

function PRT:DeleteInviteToolsPreset(name)
    self:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    if #store.presets <= 1 then
        return false, "At least one Invite & Loot preset must remain."
    end

    local removedIndex
    for index, preset in ipairs(store.presets) do
        if preset.name == name then
            removedIndex = index
            break
        end
    end
    if not removedIndex then return false, "That Invite & Loot preset no longer exists." end

    table.remove(store.presets, removedIndex)
    local replacement = store.presets[math.min(removedIndex, #store.presets)] or store.presets[1]
    if self.RemovePRTProfilePresetReference then
        self:RemovePRTProfilePresetReference("inviteTools", name, replacement and replacement.name or "")
    end
    if store.activePreset == name and replacement then
        self:ActivateInviteToolsPreset(replacement.name)
    end
    return true
end

function PRT:ActivateInviteToolsPreset(name, refreshUI, runAutomation)
    self:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    local preset = FindInviteToolsPreset(store, name)
    if not preset then return false end

    store.activePreset = preset.name
    store.autoInvite = preset.autoInvite
    store.autoPromote = preset.autoPromote
    store.loot = preset.loot
    store.lootToChat = preset.lootToChat

    if self.UpdateInviteToolsListeners then self:UpdateInviteToolsListeners() end
    if runAutomation ~= false then
        if store.enabled and store.autoPromote.enabled and self.RequestAutoPromote then
            self:RequestAutoPromote()
        end
        if store.enabled and store.loot.enabled and self.ResetInviteLootPromptState then
            self:ResetInviteLootPromptState()
        end
    end
    if refreshUI ~= false then
        if self.inviteToolsPanel and self.inviteToolsPanel.Refresh then
            self.inviteToolsPanel:Refresh()
        end
        if self.profilesPanel and self.profilesPanel.RefreshProfilesView then
            self.profilesPanel:RefreshProfilesView()
        end
    end
    return true
end

local function EncodeInviteField(value)
    return tostring(value or ""):gsub("([^%w%-%._ ])", function(char)
        return ("%%%02X"):format(string.byte(char))
    end)
end

local function DecodeInviteField(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function ParseBool(value)
    if value == "true" then return true end
    if value == "false" then return false end
end

function PRT:ExportInviteToolsPreset(preset)
    preset = NormalizeInviteToolsPreset(DeepCopy(preset or self:GetActiveInviteToolsPreset()))
    if not preset then return "" end

    local lines = {
        "[InviteLootPreset: " .. EncodeInviteField(preset.name) .. "]",
        "formatVersion=1",
        "autoInviteEnabled=" .. tostring(preset.autoInvite.enabled),
        "guildOnly=" .. tostring(preset.autoInvite.guildOnly),
        "autoAcceptTrusted=" .. tostring(preset.autoInvite.autoAcceptTrusted),
        "raidInvitesEnabled=" .. tostring(preset.autoInvite.raidInvites.enabled),
    }
    for _, keyword in ipairs(preset.autoInvite.keywords) do
        lines[#lines + 1] = "keyword=" .. EncodeInviteField(keyword)
    end
    lines[#lines + 1] = "autoPromoteEnabled=" .. tostring(preset.autoPromote.enabled)
    lines[#lines + 1] = "autoPromoteNames=" .. EncodeInviteField(preset.autoPromote.names)
    lines[#lines + 1] = "guildRankThreshold=" .. tostring(preset.autoPromote.guildRankThreshold)
    lines[#lines + 1] = "lootPromptEnabled=" .. tostring(preset.loot.enabled)
    lines[#lines + 1] = "lootMethod=" .. tostring(preset.loot.method)
    lines[#lines + 1] = "assignMasterLooter=" .. tostring(preset.loot.assignMasterLooter)
    lines[#lines + 1] = "masterLooter=" .. EncodeInviteField(preset.loot.masterLooter)
    lines[#lines + 1] = "lootThreshold=" .. tostring(preset.loot.threshold)
    lines[#lines + 1] = "onlyInRaid=" .. tostring(preset.loot.onlyInRaid)
    for _, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
        lines[#lines + 1] = "zone." .. zone.key .. "=" .. tostring(preset.loot.zones[zone.key] and true or false)
    end
    for _, zone in ipairs(preset.loot.customZones) do
        lines[#lines + 1] = "customZone=" .. EncodeInviteField(zone.name)
            .. "|" .. tostring(zone.uiMapId or "")
    end
    lines[#lines + 1] = "lootToChatEnabled=" .. tostring(preset.lootToChat.enabled)
    lines[#lines + 1] = "includeItemLevel=" .. tostring(preset.lootToChat.includeItemLevel)
    return table.concat(lines, "\n")
end

function PRT:ParseInviteToolsPresetString(raw)
    raw = tostring(raw or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local encodedName = raw:match("^%s*%[InviteLootPreset:%s*(.-)%]%s*\n")
    if not encodedName then return nil, "No [InviteLootPreset: Name] header was found." end

    local defaults = PRT.DEFAULTS and PRT.DEFAULTS.inviteTools or {}
    local preset = SnapshotInviteToolsPreset(DecodeInviteField(encodedName), defaults)
    preset.autoInvite.keywords = {}
    preset.loot.customZones = {}
    for line in raw:gmatch("[^\n]+") do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key == "autoInviteEnabled" then preset.autoInvite.enabled = ParseBool(value)
        elseif key == "guildOnly" then preset.autoInvite.guildOnly = ParseBool(value)
        elseif key == "autoAcceptTrusted" then preset.autoInvite.autoAcceptTrusted = ParseBool(value)
        elseif key == "raidInvitesEnabled" then preset.autoInvite.raidInvites.enabled = ParseBool(value)
        elseif key == "keyword" then preset.autoInvite.keywords[#preset.autoInvite.keywords + 1] = DecodeInviteField(value)
        elseif key == "autoPromoteEnabled" then preset.autoPromote.enabled = ParseBool(value)
        elseif key == "autoPromoteNames" then preset.autoPromote.names = DecodeInviteField(value)
        elseif key == "guildRankThreshold" then preset.autoPromote.guildRankThreshold = tonumber(value) or 0
        elseif key == "lootPromptEnabled" then preset.loot.enabled = ParseBool(value)
        elseif key == "lootMethod" then preset.loot.method = value
        elseif key == "assignMasterLooter" then preset.loot.assignMasterLooter = ParseBool(value)
        elseif key == "masterLooter" then preset.loot.masterLooter = DecodeInviteField(value)
        elseif key == "lootThreshold" then preset.loot.threshold = tonumber(value) or 1
        elseif key == "onlyInRaid" then preset.loot.onlyInRaid = ParseBool(value)
        elseif key and key:match("^zone%.") then
            preset.loot.zones[key:sub(6)] = ParseBool(value)
        elseif key == "customZone" then
            local nameValue, mapValue = value:match("^(.-)|(%d*)$")
            preset.loot.customZones[#preset.loot.customZones + 1] = {
                name = DecodeInviteField(nameValue or value),
                uiMapId = tonumber(mapValue),
            }
        elseif key == "lootToChatEnabled" then preset.lootToChat.enabled = ParseBool(value)
        elseif key == "includeItemLevel" then preset.lootToChat.includeItemLevel = ParseBool(value)
        end
    end
    return NormalizeInviteToolsPreset(preset)
end

function PRT:ImportInviteToolsPreset(raw)
    local preset, err = self:ParseInviteToolsPresetString(raw)
    if not preset then return nil, err end
    self:EnsureInviteToolsPresetDefaults()
    local store = GetConfig()
    preset.name = MakeUniqueInviteToolsPresetName(store, preset.name)
    store.presets[#store.presets + 1] = preset
    self:ActivateInviteToolsPreset(preset.name)
    return preset
end

function PRT:InitInviteToolsPresets()
    self:EnsureInviteToolsPresetDefaults()
    self:ActivateInviteToolsPreset(GetConfig().activePreset, false, false)
end

local function Now()
    if GetTime then return GetTime() end
    if time then return time() end
    return 0
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function IsGrouped()
    if IsInGroup then return IsInGroup() end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

local function IsGroupLeader()
    return UnitIsGroupLeader and UnitIsGroupLeader("player")
end

local function CanInvite()
    if not IsGrouped() then return true end
    return IsGroupLeader() or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
end

local function InviteUnitCompat(name)
    if not name or name == "" then return false end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
        return true
    elseif InviteUnit then
        InviteUnit(name)
        return true
    end
    return false
end

local function ConvertToRaidCompat()
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
        return true
    elseif ConvertToRaid then
        ConvertToRaid()
        return true
    end
    return false
end

local function UninviteUnitCompat(name)
    if C_PartyInfo and C_PartyInfo.UninviteUnit then
        C_PartyInfo.UninviteUnit(name)
        return true
    elseif UninviteUnit then
        UninviteUnit(name)
        return true
    end
    return false
end

local function SendChatMessageCompat(message, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(message, chatType, nil, target)
        return true
    elseif SendChatMessage then
        SendChatMessage(message, chatType, nil, target)
        return true
    end
    return false
end

RefreshPanel = function()
    if PRT.inviteToolsPanel and PRT.inviteToolsPanel.Refresh then
        PRT.inviteToolsPanel:Refresh()
    end
    if PRT.RefreshInviteBanListPopup then
        PRT:RefreshInviteBanListPopup()
    end
end

---------------------------------------------------------------------------
-- Auto invite keywords and realm-aware block list
---------------------------------------------------------------------------
local function CanonicalKeyword(keyword)
    return string.lower(PRT.Trim(keyword or ""))
end

function PRT:AddInviteKeyword(keyword)
    keyword = CanonicalKeyword(keyword)
    if keyword == "" then
        return false, "Enter a keyword first."
    end

    local keywords = GetConfig().autoInvite.keywords
    for _, existing in ipairs(keywords) do
        if CanonicalKeyword(existing) == keyword then
            return false, "That keyword already exists."
        end
    end

    keywords[#keywords + 1] = keyword
    RefreshPanel()
    return true
end

function PRT:RemoveInviteKeyword(index)
    local keywords = GetConfig().autoInvite.keywords
    index = tonumber(index)
    if not index or not keywords[index] then return false end
    table.remove(keywords, index)
    RefreshPanel()
    return true
end

function PRT:GetInviteBanEntries()
    local entries = {}
    local blocked = GetInviteBanStore()
    for identityKey, value in pairs(blocked) do
        local name
        local realm
        if type(value) == "table" then
            name = value.name
            realm = value.realm
        end
        if not name or name == "" then
            name, realm = identityKey:match("^([^@]+)@(.*)$")
        end
        if name and name ~= "" then
            entries[#entries + 1] = {
                identityKey = identityKey,
                name = name,
                realm = realm or "",
                displayName = self:MakeCharacterFullName(name, realm or "", true),
            }
        end
    end
    table.sort(entries, function(a, b)
        return string.lower(a.displayName) < string.lower(b.displayName)
    end)
    return entries
end

function PRT:AddInviteBan(fullName)
    local name, realm = self:SplitNameRealm(fullName, true)
    if name == "" then
        PRT.Print("Usage: /prt ban PlayerName or PlayerName-Realm")
        return false
    end

    local identityKey = self:MakePlayerIdentityKey(name, realm)
    local blocked = GetInviteBanStore()
    local displayName = self:MakeCharacterFullName(name, realm, true)
    if blocked[identityKey] then
        PRT.Print(displayName .. " is already blocked from keyword invites.")
        return false
    end

    blocked[identityKey] = { name = name, realm = realm }
    PRT.Print(displayName .. " blocked from keyword invites.")
    RefreshPanel()
    return true
end

function PRT:RemoveInviteBan(fullName)
    local identityKey = self:GetPlayerIdentityKey(fullName)
    local blocked = GetInviteBanStore()
    if identityKey == "" or not blocked[identityKey] then
        PRT.Print((fullName or "Player") .. " is not on the invite block list.")
        return false
    end

    local value = blocked[identityKey]
    local displayName = fullName
    if type(value) == "table" then
        displayName = self:MakeCharacterFullName(value.name, value.realm, true)
    end
    blocked[identityKey] = nil
    PRT.Print(displayName .. " removed from the invite block list.")
    RefreshPanel()
    return true
end

function PRT:RemoveInviteBanByKey(identityKey)
    local blocked = GetInviteBanStore()
    local value = blocked[identityKey]
    if not value then return false end
    blocked[identityKey] = nil
    local displayName = identityKey
    if type(value) == "table" then
        displayName = self:MakeCharacterFullName(value.name, value.realm, true)
    end
    PRT.Print(displayName .. " removed from the invite block list.")
    RefreshPanel()
    return true
end

function PRT:IsInviteBanned(fullName)
    local identityKey = self:GetPlayerIdentityKey(fullName)
    return identityKey ~= "" and GetInviteBanStore()[identityKey] ~= nil
end

function PRT:PrintInviteBanList()
    local entries = self:GetInviteBanEntries()
    if #entries == 0 then
        PRT.Print("Invite block list is empty.")
        return
    end
    PRT.Print(("Invite block list (%d):"):format(#entries))
    for _, entry in ipairs(entries) do
        print("  " .. entry.displayName)
    end
end

local function BuildKeywordLookup()
    local lookup = {}
    for _, keyword in ipairs(GetConfig().autoInvite.keywords or {}) do
        keyword = CanonicalKeyword(keyword)
        if keyword ~= "" then lookup[keyword] = true end
    end
    return lookup
end

local function RequestGuildRosterRefresh()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function PRT:IsInviteGuildMember(fullName, guid)
    if not IsInGuild or not IsInGuild() then return false end

    local name = self:SplitNameRealm(fullName, false)
    if UnitIsInMyGuild and (UnitIsInMyGuild(fullName) or UnitIsInMyGuild(name)) then
        return true
    end

    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    if count == 0 then
        RequestGuildRosterRefresh()
        return nil
    end

    local targetKey = self:GetPlayerIdentityKey(fullName)
    for index = 1, count do
        local guildName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guildGuid =
            GetGuildRosterInfo(index)
        if guildName then
            if guid and guildGuid and guid == guildGuid then return true end
            if self:GetPlayerIdentityKey(guildName) == targetKey then return true end
        end
    end
    return false
end

local function InviteIdentityMatches(fullName, guid, candidateName, candidateRealm, candidateGuid)
    if guid and candidateGuid and guid == candidateGuid then return true end
    if not candidateName or candidateName == "" then return false end

    local targetName = PRT:SplitNameRealm(fullName, false)
    local candidateBase, embeddedRealm = PRT:SplitNameRealm(candidateName, false)
    candidateRealm = embeddedRealm ~= "" and embeddedRealm or candidateRealm or ""

    if candidateRealm ~= "" then
        return PRT:GetPlayerIdentityKey(fullName)
            == PRT:MakePlayerIdentityKey(candidateBase, candidateRealm)
    end
    return string.lower(targetName or "") == string.lower(candidateBase or "")
end

function PRT:IsInviteFriend(fullName, guid)
    if C_FriendList then
        if C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
        local count = C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
        for index = 1, count do
            local info = C_FriendList.GetFriendInfoByIndex
                and C_FriendList.GetFriendInfoByIndex(index)
            if info and InviteIdentityMatches(fullName, guid, info.name, nil, info.guid) then
                return true
            end
        end
    end

    local bnetCount = BNGetNumFriends and BNGetNumFriends() or 0
    for friendIndex = 1, bnetCount do
        local checkedGameAccounts = false

        if C_BattleNet and C_BattleNet.GetFriendNumGameAccounts
            and C_BattleNet.GetFriendGameAccountInfo then
            local gameCount = C_BattleNet.GetFriendNumGameAccounts(friendIndex) or 0
            for accountIndex = 1, gameCount do
                checkedGameAccounts = true
                local info = C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)
                if info and info.clientProgram == BNET_CLIENT_WOW
                    and InviteIdentityMatches(fullName, guid, info.characterName,
                        info.realmName, info.playerGuid) then
                    return true
                end
            end
        elseif BNGetNumFriendGameAccounts and BNGetFriendGameAccountInfo then
            local gameCount = BNGetNumFriendGameAccounts(friendIndex) or 0
            for accountIndex = 1, gameCount do
                checkedGameAccounts = true
                local _, characterName, client, realmName, _, _, _, _, _, _, _, _, _, _, _,
                    _, playerGuid = BNGetFriendGameAccountInfo(friendIndex, accountIndex)
                if client == BNET_CLIENT_WOW
                    and InviteIdentityMatches(fullName, guid, characterName, realmName, playerGuid) then
                    return true
                end
            end
        end

        if not checkedGameAccounts and BNGetFriendInfo then
            local activeCharacter = select(5, BNGetFriendInfo(friendIndex))
            if InviteIdentityMatches(fullName, guid, activeCharacter) then return true end
        end
    end
    return false
end

local function HideAcceptedInvitePopup()
    local function HideIfInvite(frame)
        if not frame then return end
        local visible = frame.IsShown and frame:IsShown()
        if visible and (frame.which == "PARTY_INVITE" or frame.which == "PARTY_INVITE_XREALM") then
            frame.inviteAccepted = 1
            if StaticPopup_Hide then StaticPopup_Hide(frame.which) end
        end
    end

    if StaticPopup_ForEachShownDialog then
        StaticPopup_ForEachShownDialog(HideIfInvite)
    else
        for index = 1, 4 do HideIfInvite(_G["StaticPopup" .. index]) end
    end
end

function PRT:HandleTrustedInviteRequest(inviterName, inviterGuid, retried)
    local store = GetConfig()
    local cfg = store.autoInvite
    if store.enabled == false or not cfg.autoAcceptTrusted
        or IsSecret(inviterName) or IsSecret(inviterGuid) then return false end

    local isFriend = self:IsInviteFriend(inviterName, inviterGuid)
    local isGuildMember = self:IsInviteGuildMember(inviterName, inviterGuid)
    if isFriend or isGuildMember then
        if AcceptGroup then
            AcceptGroup()
            HideAcceptedInvitePopup()
            return true
        end
        return false
    end

    if isGuildMember == nil and not retried then
        C_Timer.After(1, function()
            PRT:HandleTrustedInviteRequest(inviterName, inviterGuid, true)
        end)
    end
    return false
end

---------------------------------------------------------------------------
-- Queued party-to-raid invites
---------------------------------------------------------------------------
local PARTY_INVITE_RESERVATION_SECONDS = 20

function PRT:GetRaidInvitesEnabled()
    local raidInvites = GetConfig().autoInvite.raidInvites
    return raidInvites and raidInvites.enabled or false
end

function PRT:ClearRaidInviteQueue()
    self._raidInviteQueueState = nil
    self._raidInviteQueueSerial = (self._raidInviteQueueSerial or 0) + 1
end

function PRT:SetRaidInvitesEnabled(enabled, announce)
    local cfg = GetConfig().autoInvite
    cfg.raidInvites = cfg.raidInvites or {}
    cfg.raidInvites.enabled = enabled and true or false
    if not cfg.raidInvites.enabled then self:ClearRaidInviteQueue() end
    self:UpdateInviteToolsListeners()
    RefreshPanel()
    if announce then
        PRT.Print("Raid Invites " .. (cfg.raidInvites.enabled and "enabled." or "disabled."))
    end
end

local function GetCurrentInviteGroupLookup()
    local lookup = {}
    if PRT.GetCurrentGroupMemberEntries then
        for _, member in ipairs(PRT:GetCurrentGroupMemberEntries(true)) do
            lookup[member.identityKey] = true
        end
    else
        lookup[PRT:GetUnitIdentityKey("player")] = true
    end
    return lookup
end

function PRT:ScheduleRaidInviteQueue(delay)
    local state = self._raidInviteQueueState
    if not state then return end
    delay = delay or 1
    local dueAt = Now() + delay
    if state.processScheduled and state.processDueAt and state.processDueAt <= dueAt then
        return
    end

    state.processScheduled = true
    state.processDueAt = dueAt
    state.processScheduleSerial = (state.processScheduleSerial or 0) + 1
    local processScheduleSerial = state.processScheduleSerial
    local serial = self._raidInviteQueueSerial
    C_Timer.After(delay, function()
        local currentState = PRT._raidInviteQueueState
        if not currentState or PRT._raidInviteQueueSerial ~= serial then return end
        if currentState.processScheduleSerial ~= processScheduleSerial then return end
        currentState.processScheduled = false
        currentState.processDueAt = nil
        PRT:ProcessRaidInviteQueue()
    end)
end

function PRT:HandleRaidConvertPopup()
    local state = self._raidInviteQueueState
    if not state or #state.queue == 0 or not self:GetRaidInvitesEnabled()
        or (IsInRaid and IsInRaid()) or not IsGrouped() or not IsGroupLeader() then
        return false
    end

    local handled = false
    local function HandleIfTrackedConvert(frame)
        if handled or not frame or frame.which ~= "CONVERT_TO_RAID" then return end
        if frame.IsShown and not frame:IsShown() then return end
        if IsSecret(frame.data) then return end

        local identityKey = PRT:GetPlayerIdentityKey(frame.data)
        if identityKey == ""
            or (not state.queued[identityKey] and not state.pending[identityKey]) then
            return
        end

        if ConvertToRaidCompat() then
            handled = true
            state.converting = true
            state.conversionRequestedAt = Now()
            if StaticPopup_Hide then
                StaticPopup_Hide("CONVERT_TO_RAID")
            elseif frame.Hide then
                frame:Hide()
            end
        end
    end

    if StaticPopup_ForEachShownDialog then
        StaticPopup_ForEachShownDialog(HandleIfTrackedConvert)
    else
        for index = 1, 4 do
            HandleIfTrackedConvert(_G["StaticPopup" .. index])
        end
    end

    if handled then self:ScheduleRaidInviteQueue(0.1) end
    return handled
end

function PRT:ProcessRaidInviteQueue()
    local state = self._raidInviteQueueState
    local store = GetConfig()
    local cfg = store.autoInvite
    if not state then return end
    if store.enabled == false or not cfg.enabled or not self:GetRaidInvitesEnabled() then
        self:ClearRaidInviteQueue()
        return
    end
    if not CanInvite() then return end
    if self:HandleRaidConvertPopup() then return end

    local current = GetCurrentInviteGroupLookup()
    local now = Now()

    for identityKey in pairs(state.pending) do
        if current[identityKey] then state.pending[identityKey] = nil end
    end

    local liveQueue = {}
    for _, entry in ipairs(state.queue) do
        if not current[entry.identityKey] and not state.pending[entry.identityKey] then
            liveQueue[#liveQueue + 1] = entry
        else
            state.queued[entry.identityKey] = nil
        end
    end
    state.queue = liveQueue

    if IsInRaid and IsInRaid() then
        local targets = {}
        local seen = {}
        for _, entry in ipairs(state.queue) do
            if not current[entry.identityKey] and not seen[entry.identityKey] then
                seen[entry.identityKey] = true
                targets[#targets + 1] = entry
            end
        end
        for identityKey, pending in pairs(state.pending) do
            if not current[identityKey] and not seen[identityKey] then
                seen[identityKey] = true
                targets[#targets + 1] = pending.entry
            end
        end

        local capacity = math.max(0, 40 - (GetNumGroupMembers and GetNumGroupMembers() or 0))
        self:ClearRaidInviteQueue()
        for index = 1, math.min(capacity, #targets) do
            local inviteName = targets[index].inviteName
            C_Timer.After((index - 1) * 0.1, function()
                InviteUnitCompat(inviteName)
            end)
        end
        return
    end

    local groupCount = GetNumGroupMembers and GetNumGroupMembers() or 0
    -- A queued request means the four initial party invite slots are already
    -- reserved. Convert as soon as one invite has been accepted and a real
    -- party exists; waiting for all five members only delays the queued invite.
    if groupCount >= 2 and #state.queue > 0 then
        local conversionAge = now - (state.conversionRequestedAt or 0)
        if IsGroupLeader() and (not state.converting or conversionAge >= 1) then
            state.converting = true
            state.conversionRequestedAt = now
            if ConvertToRaidCompat() then
                self:ScheduleRaidInviteQueue(0.1)
            else
                state.converting = false
                state.conversionRequestedAt = nil
            end
        end
        return
    end
    state.converting = false

    if #state.queue > 0 then
        for identityKey, pending in pairs(state.pending) do
            if now - pending.sentAt >= PARTY_INVITE_RESERVATION_SECONDS then
                state.pending[identityKey] = nil
                if (pending.entry.attempts or 0) < 2 and not current[identityKey]
                    and not state.queued[identityKey] then
                    state.queue[#state.queue + 1] = pending.entry
                    state.queued[identityKey] = true
                end
            end
        end
    end

    local pendingCount = 0
    for _ in pairs(state.pending) do pendingCount = pendingCount + 1 end
    local effectiveCount = groupCount > 0 and groupCount or 1
    local capacity = math.max(0, 5 - effectiveCount - pendingCount)

    while capacity > 0 and #state.queue > 0 do
        local entry = table.remove(state.queue, 1)
        state.queued[entry.identityKey] = nil
        if not current[entry.identityKey] then
            entry.attempts = (entry.attempts or 0) + 1
            InviteUnitCompat(entry.inviteName)
            state.pending[entry.identityKey] = {
                entry = entry,
                sentAt = now,
            }
            capacity = capacity - 1
        end
    end

    if #state.queue > 0 then self:ScheduleRaidInviteQueue(1) end
end

function PRT:QueueRaidInvite(sender)
    if GetConfig().enabled == false then return false end
    local name, realm = self:SplitNameRealm(sender, true)
    local identityKey = self:MakePlayerIdentityKey(name, realm)
    if identityKey == "" then return false end

    local state = self._raidInviteQueueState
    if not state then
        self._raidInviteQueueSerial = (self._raidInviteQueueSerial or 0) + 1
        state = {
            queue = {},
            queued = {},
            pending = {},
        }
        self._raidInviteQueueState = state
    end

    local pending = state.pending[identityKey]
    if pending and Now() - pending.sentAt >= PARTY_INVITE_RESERVATION_SECONDS then
        state.pending[identityKey] = nil
        pending = nil
    end
    if pending or state.queued[identityKey] or GetCurrentInviteGroupLookup()[identityKey] then
        return true
    end

    state.queue[#state.queue + 1] = {
        name = name,
        realm = realm,
        identityKey = identityKey,
        inviteName = self:MakeCharacterFullName(name, realm, false),
        attempts = 0,
    }
    state.queued[identityKey] = true
    self:UpdateInviteToolsListeners()
    self:ProcessRaidInviteQueue()
    return true
end

function PRT:HandleAutoInviteWhisper(message, sender, senderGuid, guildRetry)
    local store = GetConfig()
    local cfg = store.autoInvite
    if store.enabled == false or not cfg.enabled
        or IsSecret(message) or IsSecret(sender) then return false end

    local keyword = CanonicalKeyword(message)
    if keyword == "" or not BuildKeywordLookup()[keyword] then return false end

    local senderKey = self:GetPlayerIdentityKey(sender)
    if senderKey == "" or senderKey == self:GetUnitIdentityKey("player") then return false end
    if GetInviteBanStore()[senderKey] then return false end

    if cfg.guildOnly then
        local isGuildMember = self:IsInviteGuildMember(sender, senderGuid)
        if isGuildMember == nil and not guildRetry then
            C_Timer.After(1, function()
                PRT:HandleAutoInviteWhisper(message, sender, senderGuid, true)
            end)
            return true
        elseif not isGuildMember then
            return false
        end
    end

    if not CanInvite() then return false end

    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        if count >= 40 then return false end
    end

    if self:GetRaidInvitesEnabled() then return self:QueueRaidInvite(sender) end

    local name, realm = self:SplitNameRealm(sender, true)
    return InviteUnitCompat(self:MakeCharacterFullName(name, realm, false))
end

---------------------------------------------------------------------------
-- Auto promote
---------------------------------------------------------------------------
PRT._inviteToolsManualDemotions = {}

local function BuildPromoteNameLookup()
    local lookup = {}
    local raw = GetConfig().autoPromote.names or ""
    for token in raw:gmatch("[^,%s;]+") do
        local identityKey = PRT:GetPlayerIdentityKey(token)
        if identityKey ~= "" then lookup[identityKey] = true end
    end
    return lookup
end

local function BuildGuildPromoteLookup(threshold)
    local lookup = {}
    if threshold <= 0 or not IsInGuild or not IsInGuild() then return lookup end

    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    if count == 0 then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
        return lookup
    end

    for index = 1, count do
        local name, _, rankIndex = GetGuildRosterInfo(index)
        if name and rankIndex and rankIndex < threshold then
            lookup[PRT:GetPlayerIdentityKey(name)] = true
        end
    end
    return lookup
end

function PRT:RunAutoPromote()
    local store = GetConfig()
    local cfg = store.autoPromote
    if store.enabled == false or not cfg.enabled
        or not IsInRaid or not IsInRaid() or not IsGroupLeader() then return end
    if not PromoteToAssistant then return end

    local explicit = BuildPromoteNameLookup()
    local guild = BuildGuildPromoteLookup(tonumber(cfg.guildRankThreshold) or 0)
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0

    for index = 1, count do
        local name, rank = GetRaidRosterInfo(index)
        if name and rank == 0 then
            local identityKey = self:GetRaidMemberIdentityKey(index, name)
            if (explicit[identityKey] or guild[identityKey])
                and not self._inviteToolsManualDemotions[identityKey] then
                PromoteToAssistant(name)
            end
        end
    end
end

function PRT:RequestAutoPromote()
    if self._inviteToolsPromotePending then return end
    self._inviteToolsPromotePending = true
    C_Timer.After(1, function()
        PRT._inviteToolsPromotePending = false
        PRT:RunAutoPromote()
    end)
end

---------------------------------------------------------------------------
-- One-shot loot configuration prompt
---------------------------------------------------------------------------
function PRT:GetCurrentInviteLootZone()
    local _, _, _, _, _, _, _, instanceMapId = GetInstanceInfo()
    local zone = lootZoneByInstanceId[instanceMapId]
    if zone then return zone end

    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    zone = lootZoneByMapId[uiMapId]
    if zone then return zone end

    local zoneName
    if GetRealZoneText then zoneName = GetRealZoneText() end
    if (not zoneName or zoneName == "") and GetZoneText then zoneName = GetZoneText() end
    zoneName = PRT.Trim(zoneName or "")
    zone = lootZoneByName[string.lower(zoneName)]
    if zone then return zone end

    local cfg = GetConfig().loot
    for index, customZone in ipairs(cfg.customZones or {}) do
        if (customZone.uiMapId and customZone.uiMapId == uiMapId)
                or string.lower(customZone.name or "") == string.lower(zoneName) then
            return {
                key = "custom:" .. string.lower(customZone.name),
                name = customZone.name,
                uiMapId = customZone.uiMapId,
                customIndex = index,
            }
        end
    end
end

function PRT:IsInviteLootZoneEnabled(zone, cfg)
    if not zone then return false end
    cfg = cfg or GetConfig().loot
    if zone.customIndex then return cfg.customZones and cfg.customZones[zone.customIndex] ~= nil end
    return cfg.zones and cfg.zones[zone.key] and true or false
end

function PRT:GetCurrentWorldZoneInfo()
    local name
    if GetRealZoneText then name = GetRealZoneText() end
    if (not name or name == "") and GetZoneText then name = GetZoneText() end
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return PRT.Trim(name or ""), tonumber(uiMapId)
end

function PRT:AddInviteLootCustomZone(name, uiMapId)
    local cfg = GetConfig().loot
    name = PRT.Trim(tostring(name or ""))
    if name == "" then return false, "Enter a zone name first." end
    local normalizedName = string.lower(name)
    if lootZoneByName[normalizedName] then
        return false, name .. " is already available in the default zone list."
    end
    for _, zone in ipairs(cfg.customZones or {}) do
        if string.lower(zone.name or "") == normalizedName then
            return false, name .. " is already in the custom zone list."
        end
    end
    cfg.customZones = cfg.customZones or {}
    cfg.customZones[#cfg.customZones + 1] = {
        name = name,
        uiMapId = tonumber(uiMapId),
    }
    RefreshPanel()
    self:ResetInviteLootPromptState()
    return true
end

function PRT:AddCurrentInviteLootCustomZone()
    local name, uiMapId = self:GetCurrentWorldZoneInfo()
    if name == "" then return false, "The current zone could not be identified." end
    return self:AddInviteLootCustomZone(name, uiMapId)
end

function PRT:RemoveInviteLootCustomZone(index)
    local cfg = GetConfig().loot
    index = tonumber(index)
    if not index or not cfg.customZones or not cfg.customZones[index] then return false end
    table.remove(cfg.customZones, index)
    RefreshPanel()
    self:ResetInviteLootPromptState()
    return true
end

local function GetLootMethodCompat()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        return C_PartyInfo.GetLootMethod()
    elseif GetLootMethod then
        return GetLootMethod()
    end
end

local function GetLootThresholdCompat()
    if GetLootThreshold then return GetLootThreshold() end
end

function PRT:GetCurrentInviteLootSettings()
    local rawMethod, masterPartyId, masterRaidId = GetLootMethodCompat()
    local method = lootMethodById[tonumber(rawMethod)]
        or lootMethodByValue[tostring(rawMethod or "")]
        or {
            value = tostring(rawMethod or "unknown"),
            text = rawMethod ~= nil and tostring(rawMethod) or "Unknown",
        }
    local thresholdValue = tonumber(GetLootThresholdCompat())
    local threshold = lootThresholdByValue[thresholdValue] or {
        value = thresholdValue,
        text = "|cffffffffUnknown|r",
        plainText = "Unknown",
    }

    local masterLooter
    if method.value == "master" then
        local unit
        if tonumber(masterRaidId) and tonumber(masterRaidId) > 0 then
            unit = "raid" .. tonumber(masterRaidId)
        elseif masterPartyId ~= nil then
            unit = tonumber(masterPartyId) == 0 and "player"
                or ("party" .. tostring(masterPartyId))
        end

        if unit then
            local name, realm = self:GetUnitIdentity(unit)
            if name ~= "" then
                masterLooter = self:MakeCharacterFullName(name, realm, false)
            end
        end
        masterLooter = masterLooter or "Unknown"
    end

    return {
        method = method,
        threshold = threshold,
        masterLooter = masterLooter,
    }
end

function PRT:GetInviteLootDescription()
    local cfg = GetConfig().loot
    local method = lootMethodByValue[cfg.method] or lootMethodByValue.group
    local threshold = lootThresholdByValue[tonumber(cfg.threshold) or 1] or lootThresholdByValue[1]
    local description = "Loot method: " .. method.text
    if method.value == "master" then
        local masterLooter = PRT.Trim(cfg.masterLooter or "")
        if cfg.assignMasterLooter then
            description = description .. "\nMaster looter: "
                .. (masterLooter ~= "" and masterLooter or "Not configured")
        else
            local current = self:GetCurrentInviteLootSettings()
            local currentName = current.method.value == "master"
                and (current.masterLooter or "Unknown")
                or "none; game default when enabling Master Loot"
            description = description .. "\nMaster looter: Keep current (" .. currentName .. ")"
        end
    end
    return description .. "\nLoot threshold: " .. threshold.text
end

function PRT:ResolveInviteMasterLooter()
    local configured = PRT.Trim(GetConfig().loot.masterLooter or "")
    if configured == "" then return nil, "No player is configured" end

    local identityKey = self:GetPlayerIdentityKey(configured)
    if identityKey ~= "" and self.GetCurrentGroupMemberEntries then
        for _, member in ipairs(self:GetCurrentGroupMemberEntries(true)) do
            if member.identityKey == identityKey then return member.inviteName end
        end
    end
    return nil, configured
end

function PRT:ApplyInviteLootSettings()
    local store = GetConfig()
    local cfg = store.loot
    local zone = self:GetCurrentInviteLootZone()
    if store.enabled == false then
        PRT.Print("Loot settings were not applied because Invite & Loot automation is disabled.")
        return false
    end
    if not cfg.enabled or not self:IsInviteLootZoneEnabled(zone, cfg) then
        PRT.Print("Loot settings were not applied because this zone is no longer enabled.")
        return false
    end
    if not IsGrouped() or not IsGroupLeader() then
        PRT.Print("Loot settings were not applied because you are no longer group leader.")
        return false
    end
    if cfg.onlyInRaid and (not IsInRaid or not IsInRaid()) then
        PRT.Print("Loot settings were not applied because you are not in a raid group.")
        return false
    end

    local method = lootMethodByValue[cfg.method] or lootMethodByValue.group
    local current = self:GetCurrentInviteLootSettings()
    local masterName
    local setLootMethod = current.method.value ~= method.value
    if method.value == "master" then
        if cfg.assignMasterLooter then
            local configuredName
            masterName, configuredName = self:ResolveInviteMasterLooter()
            if not masterName or masterName == "" then
                if configuredName == "No player is configured" then
                    PRT.Print("Choose a master looter before applying these settings.")
                else
                    PRT.Print(("%s cannot be assigned as master looter because they are not in your group.")
                        :format(configuredName or "That player"))
                end
                return false
            end
            if current.method.value == "master"
                    and self:GetPlayerIdentityKey(current.masterLooter or "")
                        == self:GetPlayerIdentityKey(masterName) then
                setLootMethod = false
            else
                setLootMethod = true
            end
        elseif current.method.value == "master" then
            -- Keep the active master looter exactly as-is. Calling SetLootMethod
            -- with no assignee can cause the client to default back to the leader.
            setLootMethod = false
            masterName = current.masterLooter
        else
            -- Enabling Master Loot without an explicit assignee lets the game
            -- choose its normal default master looter.
            setLootMethod = true
            masterName = nil
        end
    end

    local ok
    local err
    if setLootMethod then
        if C_PartyInfo and C_PartyInfo.SetLootMethod then
            ok, err = pcall(C_PartyInfo.SetLootMethod, method.id, masterName)
        elseif SetLootMethod then
            ok, err = pcall(SetLootMethod, method.value, masterName)
        else
            PRT.Print("This client does not expose a loot-method API.")
            return false
        end
        if ok == false then
            PRT.Print("Unable to set loot method: " .. tostring(err))
            return false
        end
    end

    local threshold = tonumber(cfg.threshold) or 1
    local setLootThreshold = tonumber(current.threshold.value) ~= threshold
    if setLootThreshold then
        C_Timer.After(setLootMethod and 0.5 or 0, function()
            if SetLootThreshold and IsGroupLeader() then
                local thresholdOk, thresholdErr = pcall(SetLootThreshold, threshold)
                if thresholdOk == false then
                    PRT.Print("Unable to set loot threshold: " .. tostring(thresholdErr))
                end
            end
        end)
    end

    local methodSummary = method.text
    if method.value == "master" then
        if cfg.assignMasterLooter then
            methodSummary = methodSummary .. " (" .. masterName .. ")"
        elseif current.method.value == "master" then
            methodSummary = methodSummary .. " (kept "
                .. (masterName or "current master looter") .. ")"
        else
            methodSummary = methodSummary .. " (game default master looter)"
        end
    end
    if not setLootMethod and not setLootThreshold then
        PRT.Print("Configured loot settings are already active; no changes were needed.")
        return true
    end
    PRT.Print(("Applied %s with %s threshold."):format(
        methodSummary, (lootThresholdByValue[threshold] or lootThresholdByValue[1]).plainText))
    return true
end

function PRT:ShowInviteLootPrompt(zone)
    local W = self.UI
    if not W or not W.CreateSettingsComparisonPopup then return end

    if not self._inviteLootPrompt then
        local popup = W.CreateSettingsComparisonPopup("PRTInviteLootPrompt", {
            title = "Apply Configured Loot Settings?",
            minWidth = 330,
            maxWidth = 430,
            onApply = function()
                return PRT:ApplyInviteLootSettings()
            end,
        })

        popup:HookScript("OnHide", function()
            PRT._inviteLootPromptOpen = false
        end)
        self._inviteLootPrompt = popup
    end

    local cfg = GetConfig().loot
    local method = lootMethodByValue[cfg.method] or lootMethodByValue.group
    local threshold = lootThresholdByValue[tonumber(cfg.threshold) or 1] or lootThresholdByValue[1]
    local current = self:GetCurrentInviteLootSettings()
    local popup = self._inviteLootPrompt

    local configuredRows = {
        "Loot method: |cffffffff" .. method.text .. "|r",
    }
    if method.value == "master" then
        local masterLooter = PRT.Trim(cfg.masterLooter or "")
        local masterText
        if not cfg.assignMasterLooter then
            local currentName = current.method.value == "master"
                and (current.masterLooter or "Unknown")
                or "none; game default when enabling Master Loot"
            masterText = "|cffffffffKeep current (" .. currentName .. ")|r"
        elseif masterLooter == "" then
            masterText = "|cffff5555Not configured|r"
        else
            masterText = "|cffffffff" .. masterLooter .. "|r"
        end
        configuredRows[#configuredRows + 1] = "Master looter: " .. masterText
    end
    configuredRows[#configuredRows + 1] = "Loot threshold: " .. threshold.text

    local currentRows = {
        "Loot method: |cffffffff" .. current.method.text .. "|r",
    }
    if current.method.value == "master" then
        currentRows[#currentRows + 1] = "Master looter: |cffffffff"
            .. (current.masterLooter or "Unknown") .. "|r"
    end
    currentRows[#currentRows + 1] = "Loot threshold: " .. current.threshold.text

    popup:SetComparison({
        contextText = "You are group leader in " .. zone.name .. ".",
        configuredRows = configuredRows,
        currentRows = currentRows,
        questionText = "Which settings would you like to use?",
    })

    self._inviteLootPromptOpen = true
    popup:Show()
    popup:BringToFront()
end

function PRT:CheckInviteLootPrompt(force)
    local store = GetConfig()
    local cfg = store.loot
    local zone = self:GetCurrentInviteLootZone()
    local zoneKey = zone and zone.key or ""
    local leader = IsGrouped() and IsGroupLeader() or false
    local zoneChanged = zoneKey ~= (self._inviteLootLastZoneKey or "")
    local becameLeader = leader and not self._inviteLootWasLeader

    self._inviteLootLastZoneKey = zoneKey
    self._inviteLootWasLeader = leader

    if store.enabled == false or not cfg.enabled
        or not self:IsInviteLootZoneEnabled(zone, cfg) then return end
    if not leader or (cfg.onlyInRaid and (not IsInRaid or not IsInRaid())) then return end
    if not force and not zoneChanged and not becameLeader then return end
    if self._inviteLootPromptOpen then return end

    self:ShowInviteLootPrompt(zone)
end

function PRT:ResetInviteLootPromptState()
    self._inviteLootLastZoneKey = nil
    self._inviteLootWasLeader = false
    C_Timer.After(0.2, function()
        PRT:CheckInviteLootPrompt(true)
    end)
end

---------------------------------------------------------------------------
-- Loot to Chat
---------------------------------------------------------------------------
PRT._inviteLootChatSourceCache = PRT._inviteLootChatSourceCache or {}

local function GetLootChatDestination()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE
        and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsGrouped() then
        return "PARTY"
    end
    return "WHISPER", UnitName("player")
end

local function GetLootItemLevel(itemLink)
    local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getItemInfo then return nil end
    return select(4, getItemInfo(itemLink))
end

function PRT:LinkLootToChat(linkCurrentWindow)
    local store = GetConfig()
    local cfg = store.lootToChat or {}
    if not linkCurrentWindow and (store.enabled == false or not cfg.enabled) then return 0 end
    if not GetNumLootItems or not GetLootSlotLink or not GetLootSlotInfo then
        if linkCurrentWindow then PRT.Print("This client does not expose the loot-window API.") end
        return 0
    end

    local _, instanceType = GetInstanceInfo()
    if not linkCurrentWindow and instanceType ~= "raid" then return 0 end

    local items = {}
    local openedSources = {}
    for slot = 1, GetNumLootItems() do
        local sourceGuid = GetLootSourceInfo and GetLootSourceInfo(slot)
        local sourceAlreadyLinked = sourceGuid and self._inviteLootChatSourceCache[sourceGuid]
        if linkCurrentWindow or not sourceAlreadyLinked then
            local itemLink = GetLootSlotLink(slot)
            local _, _, _, _, quality = GetLootSlotInfo(slot)
            if itemLink and (linkCurrentWindow or (quality and quality >= 4)) then
                items[#items + 1] = {
                    link = itemLink,
                    itemLevel = cfg.includeItemLevel and GetLootItemLevel(itemLink) or nil,
                }
            end
        end
        if sourceGuid then openedSources[sourceGuid] = true end
    end

    for sourceGuid in pairs(openedSources) do
        self._inviteLootChatSourceCache[sourceGuid] = true
    end

    local chatType, target = GetLootChatDestination()
    local sent = 0
    for index, item in ipairs(items) do
        local message = ("%d: %s"):format(index, item.link)
        if item.itemLevel then message = message .. (" (%d)"):format(item.itemLevel) end
        if SendChatMessageCompat(message, chatType, target) then sent = sent + 1 end
    end

    if linkCurrentWindow and sent == 0 then
        PRT.Print("No linkable items were found in the current loot window.")
    end
    return sent
end

---------------------------------------------------------------------------
-- Disband snapshot and delayed reinvite
---------------------------------------------------------------------------
local function GetPartyMemberEntry(unit)
    local name, realm = PRT:GetUnitIdentity(unit)
    if name == "" then return nil end
    return {
        name = name,
        realm = realm,
        identityKey = PRT:MakePlayerIdentityKey(name, realm),
        inviteName = PRT:MakeCharacterFullName(name, realm, false),
    }
end

function PRT:GetCurrentGroupMemberEntries(includePlayer)
    local members = {}
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        local playerKey = self:GetUnitIdentityKey("player")
        for index = 1, count do
            local rosterName = GetRaidRosterInfo(index)
            if rosterName then
                local name, realm = self:GetRaidMemberIdentity(index, rosterName)
                local identityKey = self:MakePlayerIdentityKey(name, realm)
                if includePlayer or identityKey ~= playerKey then
                    members[#members + 1] = {
                        name = name,
                        realm = realm,
                        identityKey = identityKey,
                        inviteName = self:MakeCharacterFullName(name, realm, false),
                    }
                end
            end
        end
    else
        if includePlayer then
            local player = GetPartyMemberEntry("player")
            if player then members[#members + 1] = player end
        end
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, math.max(0, count - 1) do
            local member = GetPartyMemberEntry("party" .. index)
            if member then members[#members + 1] = member end
        end
    end
    return members
end

function PRT:DisbandWithSnapshot()
    if not IsGrouped() then
        PRT.Print("You are not in a group.")
        return false
    end
    if not IsGroupLeader() then
        PRT.Print("You must be group leader to disband the group.")
        return false
    end

    local members = self:GetCurrentGroupMemberEntries(false)
    local snapshot = GetConfig().reinviteSnapshot
    snapshot.createdAt = time and time() or 0
    snapshot.members = {}
    for _, member in ipairs(members) do
        snapshot.members[#snapshot.members + 1] = {
            name = member.name,
            realm = member.realm,
        }
    end

    for index = #members, 1, -1 do
        UninviteUnitCompat(members[index].inviteName)
    end

    PRT.Print(("Saved %d player%s to the reinvite snapshot and disbanded the group.")
        :format(#members, #members == 1 and "" or "s"))
    RefreshPanel()
    return true
end

local function SnapshotMemberToEntry(value)
    if type(value) == "string" then
        local name, realm = PRT:SplitNameRealm(value, true)
        return {
            name = name,
            realm = realm,
            identityKey = PRT:MakePlayerIdentityKey(name, realm),
            inviteName = PRT:MakeCharacterFullName(name, realm, false),
        }
    elseif type(value) == "table" then
        local name, realm = PRT:SplitNameRealm(value.name, false)
        if realm == "" then realm = value.realm or PRT:GetHomeRealmName() end
        return {
            name = name,
            realm = realm,
            identityKey = PRT:MakePlayerIdentityKey(name, realm),
            inviteName = PRT:MakeCharacterFullName(name, realm, false),
        }
    end
end

local function BuildCurrentGroupLookup()
    local lookup = {}
    for _, member in ipairs(PRT:GetCurrentGroupMemberEntries(true)) do
        lookup[member.identityKey] = true
    end
    return lookup
end

function PRT:StopSnapshotReinvite(message)
    self._inviteToolsReinviteState = nil
    self._inviteToolsReinviteSerial = (self._inviteToolsReinviteSerial or 0) + 1
    self:UpdateInviteToolsListeners()
    if message then PRT.Print(message) end
end

function PRT:ProcessSnapshotReinvite()
    local state = self._inviteToolsReinviteState
    if not state then return end

    if IsGrouped() and not IsGroupLeader() then
        self:StopSnapshotReinvite("Reinvite stopped because you are no longer group leader.")
        return
    end

    local current = BuildCurrentGroupLookup()
    local remaining = {}
    local allSent = true
    for _, target in ipairs(state.targets) do
        if not current[target.identityKey] then
            remaining[#remaining + 1] = target
            if not state.sentAt[target.identityKey] then allSent = false end
        end
    end

    if #remaining == 0 then
        self:StopSnapshotReinvite("All snapshot players are now in the group.")
        return
    end

    if IsInRaid and IsInRaid() then
        local capacity = math.max(0, 40 - (GetNumGroupMembers() or 0))
        local sent = 0
        for _, target in ipairs(remaining) do
            if sent >= capacity then break end
            if not state.sentAt[target.identityKey] then
                sent = sent + 1
                state.sentAt[target.identityKey] = Now()
                local inviteName = target.inviteName
                C_Timer.After((sent - 1) * 0.1, function()
                    InviteUnitCompat(inviteName)
                end)
            end
        end
        self:StopSnapshotReinvite(("Sent %d reinvite%s from the saved snapshot.")
            :format(sent, sent == 1 and "" or "s"))
        return
    end

    local groupCount = GetNumGroupMembers and GetNumGroupMembers() or 0
    if groupCount >= 5 then
        if ConvertToRaidCompat() then
            C_Timer.After(0.5, function() PRT:ProcessSnapshotReinvite() end)
        else
            self:StopSnapshotReinvite("Unable to convert the full party to a raid.")
        end
        return
    end

    if allSent then
        self:StopSnapshotReinvite("Every player in the saved snapshot has been sent a reinvite.")
        return
    end

    local now = Now()
    local effectiveCount = groupCount > 0 and groupCount or 1
    local inFlight = 0
    for identityKey, sentAt in pairs(state.sentAt) do
        if not current[identityKey] and now - sentAt < 12 then
            inFlight = inFlight + 1
        end
    end
    local capacity = math.max(0, 5 - effectiveCount - inFlight)
    for _, target in ipairs(remaining) do
        if capacity <= 0 then break end
        if not state.sentAt[target.identityKey] then
            InviteUnitCompat(target.inviteName)
            state.sentAt[target.identityKey] = now
            capacity = capacity - 1
        end
    end

    if now - state.startedAt >= 300 then
        self:StopSnapshotReinvite("Reinvite stopped after five minutes; some snapshot players could not be invited.")
        return
    end

    local serial = self._inviteToolsReinviteSerial
    C_Timer.After(2, function()
        if PRT._inviteToolsReinviteState and PRT._inviteToolsReinviteSerial == serial then
            PRT:ProcessSnapshotReinvite()
        end
    end)
end

function PRT:ReinviteSnapshot()
    local snapshot = GetConfig().reinviteSnapshot
    if not snapshot or not snapshot.members or #snapshot.members == 0 then
        PRT.Print("There is no saved disband snapshot to reinvite.")
        return false
    end
    if IsGrouped() and not IsGroupLeader() then
        PRT.Print("You must be group leader to reinvite the saved snapshot.")
        return false
    end

    local targets = {}
    local playerKey = self:GetUnitIdentityKey("player")
    local seen = {}
    for _, value in ipairs(snapshot.members) do
        local target = SnapshotMemberToEntry(value)
        if target and target.identityKey ~= "" and target.identityKey ~= playerKey
            and not seen[target.identityKey] then
            seen[target.identityKey] = true
            targets[#targets + 1] = target
        end
    end
    if #targets == 0 then
        PRT.Print("The saved disband snapshot contains no other players.")
        return false
    end

    self._inviteToolsReinviteSerial = (self._inviteToolsReinviteSerial or 0) + 1
    self._inviteToolsReinviteState = {
        targets = targets,
        sentAt = {},
        startedAt = Now(),
    }
    self:UpdateInviteToolsListeners()
    self:ProcessSnapshotReinvite()
    return true
end

---------------------------------------------------------------------------
-- Event registration and initialization
---------------------------------------------------------------------------
function PRT:UpdateInviteToolsListeners()
    local cfg = GetConfig()
    local automationEnabled = cfg.enabled ~= false
    if (not automationEnabled or not cfg.autoInvite.enabled or not self:GetRaidInvitesEnabled())
        and self._raidInviteQueueState then
        self:ClearRaidInviteQueue()
    end

    local frame = self._inviteToolsFrame
    if not frame then return end
    frame:UnregisterAllEvents()

    if automationEnabled and cfg.autoInvite.enabled then
        frame:RegisterEvent("CHAT_MSG_WHISPER")
    end
    if automationEnabled and cfg.autoInvite.autoAcceptTrusted then
        frame:RegisterEvent("PARTY_INVITE_REQUEST")
    end
    if self._raidInviteQueueState then
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
    end
    if automationEnabled and cfg.autoPromote.enabled then
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
        frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    end
    if automationEnabled and cfg.loot.enabled then
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("ZONE_CHANGED")
        frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    end
    if automationEnabled and cfg.lootToChat and cfg.lootToChat.enabled then
        frame:RegisterEvent("LOOT_OPENED")
    end
    if self._inviteToolsReinviteState then
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
    end
end

function PRT:InitInviteTools()
    if self._inviteToolsFrame then return end

    if hooksecurefunc and StaticPopup_Show and not self._inviteToolsRaidConvertPopupHooked then
        self._inviteToolsRaidConvertPopupHooked = true
        hooksecurefunc("StaticPopup_Show", function(which)
            if which == "CONVERT_TO_RAID" and PRT._raidInviteQueueState then
                C_Timer.After(0, function()
                    PRT:HandleRaidConvertPopup()
                end)
            end
        end)
    end

    if hooksecurefunc and DemoteAssistant then
        hooksecurefunc("DemoteAssistant", function(unit)
            local name
            if UnitName then name = UnitName(unit) end
            name = name or unit
            local identityKey = PRT:GetPlayerIdentityKey(name)
            if identityKey ~= "" then
                PRT._inviteToolsManualDemotions[identityKey] = true
            end
        end)
    end

    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_WHISPER" then
            local message, sender = ...
            local senderGuid = select(12, ...)
            PRT:HandleAutoInviteWhisper(message, sender, senderGuid)
        elseif event == "PARTY_INVITE_REQUEST" then
            local inviterName = ...
            local inviterGuid = select(7, ...)
            PRT:HandleTrustedInviteRequest(inviterName, inviterGuid)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
            if GetConfig().enabled and GetConfig().autoPromote.enabled then PRT:RequestAutoPromote() end
            if PRT._raidInviteQueueState then PRT:ProcessRaidInviteQueue() end
            if PRT._inviteToolsReinviteState then PRT:ProcessSnapshotReinvite() end
            if GetConfig().enabled and GetConfig().loot.enabled then
                C_Timer.After(0.2, function() PRT:CheckInviteLootPrompt(false) end)
            end
        elseif event == "GUILD_ROSTER_UPDATE" then
            PRT:RequestAutoPromote()
        elseif event == "LOOT_OPENED" then
            PRT:LinkLootToChat(false)
        else
            C_Timer.After(0.8, function() PRT:CheckInviteLootPrompt(false) end)
        end
    end)
    self._inviteToolsFrame = frame
    self:UpdateInviteToolsListeners()

    if GetConfig().enabled and GetConfig().autoPromote.enabled then self:RequestAutoPromote() end
    if GetConfig().enabled and GetConfig().loot.enabled then self:ResetInviteLootPromptState() end
end
