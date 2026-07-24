---------------------------------------------------------------------------
-- PugzRaidTools - Roster Matcher / Alias Database
-- Realm-aware alias storage and on-demand roster reconciliation helpers.
---------------------------------------------------------------------------
local _, PRT = ...

local UNKNOWN_CLASS = ""

local CHAR_FOLD = {
    ["À"] = "A", ["Á"] = "A", ["Â"] = "A", ["Ã"] = "A", ["Ä"] = "A", ["Å"] = "A",
    ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
    ["Ā"] = "A", ["ā"] = "a", ["Ă"] = "A", ["ă"] = "a", ["Ą"] = "A", ["ą"] = "a",
    ["Æ"] = "AE", ["æ"] = "ae",
    ["Ç"] = "C", ["ç"] = "c", ["Ć"] = "C", ["ć"] = "c", ["Č"] = "C", ["č"] = "c",
    ["Ð"] = "D", ["ð"] = "d",
    ["È"] = "E", ["É"] = "E", ["Ê"] = "E", ["Ë"] = "E",
    ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["Ē"] = "E", ["ē"] = "e", ["Ė"] = "E", ["ė"] = "e", ["Ę"] = "E", ["ę"] = "e",
    ["Ì"] = "I", ["Í"] = "I", ["Î"] = "I", ["Ï"] = "I",
    ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
    ["Ī"] = "I", ["ī"] = "i", ["İ"] = "I", ["ı"] = "i",
    ["Ñ"] = "N", ["ñ"] = "n",
    ["Ò"] = "O", ["Ó"] = "O", ["Ô"] = "O", ["Õ"] = "O", ["Ö"] = "O", ["Ø"] = "O",
    ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ø"] = "o",
    ["Ō"] = "O", ["ō"] = "o", ["Ő"] = "O", ["ő"] = "o",
    ["Š"] = "S", ["š"] = "s", ["Ś"] = "S", ["ś"] = "s", ["ß"] = "ss",
    ["Ù"] = "U", ["Ú"] = "U", ["Û"] = "U", ["Ü"] = "U",
    ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u",
    ["Ū"] = "U", ["ū"] = "u", ["Ů"] = "U", ["ů"] = "u",
    ["Ý"] = "Y", ["ý"] = "y", ["ÿ"] = "y",
    ["Ž"] = "Z", ["ž"] = "z", ["Ź"] = "Z", ["ź"] = "z", ["Ż"] = "Z", ["ż"] = "z",
}

local CLASS_OPTIONS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function EnsureMatcherDB()
    local db = PRT:GetDB()
    db.rosterMatcher = db.rosterMatcher or {}
    local rm = db.rosterMatcher
    if type(rm.threshold) ~= "number" then rm.threshold = 50 end
    if type(rm.aliases) ~= "table" then rm.aliases = {} end
    if type(rm.nextAliasId) ~= "number" then rm.nextAliasId = 1 end
    return rm
end

local function FoldCharacters(text)
    text = tostring(text or "")
    for src, dst in pairs(CHAR_FOLD) do
        text = text:gsub(src, dst)
    end
    return text
end

local function NormalizeRealm(realm)
    realm = PRT.Trim(realm or "")
    if realm == "" then return "" end
    realm = FoldCharacters(realm)
    realm = string.lower(realm)
    realm = realm:gsub("[%s%p_]+", "")
    return realm
end

local function StrictNormalizeRealm(realm)
    realm = PRT.Trim(realm or "")
    if realm == "" then return "" end
    return string.lower(realm)
end

local function NormalizeName(name)
    name = PRT.Trim(name or "")
    if name == "" then return "" end
    name = name:gsub('^"+', ""):gsub('"+$', "")
    name = name:gsub("^'+", ""):gsub("'+$", "")
    name = FoldCharacters(name)
    name = string.lower(name)
    name = name:gsub("[%s%p_]+", "")
    return name
end

local function StrictNormalizeName(name)
    name = PRT.Trim(name or "")
    if name == "" then return "" end
    name = name:gsub('^"+', ""):gsub('"+$', "")
    name = name:gsub("^'+", ""):gsub("'+$", "")
    return string.lower(name)
end

local function MakeFullNorm(baseNorm, realmNorm)
    if baseNorm == "" then return "" end
    if realmNorm == "" then return baseNorm end
    return baseNorm .. "@" .. realmNorm
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function CommonPrefixLength(a, b)
    local maxLen = math.min(#a, #b)
    local idx = 0
    while idx < maxLen do
        local pos = idx + 1
        if a:sub(pos, pos) ~= b:sub(pos, pos) then
            break
        end
        idx = idx + 1
    end
    return idx
end

local function Levenshtein(a, b)
    local lenA, lenB = #a, #b
    if lenA == 0 then return lenB end
    if lenB == 0 then return lenA end

    local prev = {}
    local curr = {}
    for j = 0, lenB do
        prev[j] = j
    end

    for i = 1, lenA do
        curr[0] = i
        local charA = a:sub(i, i)
        for j = 1, lenB do
            local cost = (charA == b:sub(j, j)) and 0 or 1
            local del = prev[j] + 1
            local ins = curr[j - 1] + 1
            local sub = prev[j - 1] + cost
            curr[j] = math.min(del, ins, sub)
        end
        for j = 0, lenB do
            prev[j] = curr[j]
        end
    end

    return prev[lenB]
end

local function ComputeLooseScore(importEntry, liveEntry)
    local a = importEntry.baseNorm
    local b = liveEntry.baseNorm
    if a == "" or b == "" then return 0 end

    if a == b then
        if importEntry.realmNorm ~= "" and importEntry.realmNorm == liveEntry.realmNorm then
            return 99
        end
        return 96
    end

    local maxLen = math.max(#a, #b)
    if maxLen == 0 then return 0 end

    local prefixLen = CommonPrefixLength(a, b)
    local dist = Levenshtein(a, b)
    local lengthGap = math.abs(#a - #b)

    local score = 0
    score = score + math.floor((prefixLen / maxLen) * 48)
    score = score + math.floor((math.min(#a, #b) / maxLen) * 18)

    if a:find(b, 1, true) or b:find(a, 1, true) then
        score = score + 18
    end
    if prefixLen >= 3 then
        score = score + 8
    end

    if dist == 1 then
        score = score + 26
    elseif dist == 2 then
        score = score + 16
    elseif dist == 3 then
        score = score + 8
    else
        score = score - math.max(0, dist - 3) * 5
    end

    score = score - lengthGap * 3
    if a:sub(1, 1) ~= b:sub(1, 1) then
        score = score - 18
    end
    if importEntry.realmNorm ~= "" and importEntry.realmNorm == liveEntry.realmNorm then
        score = score + 4
    end

    return Clamp(score, 0, 95)
end

local function GetClassLabel(classFile)
    if classFile and classFile ~= "" then
        if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] then
            return LOCALIZED_CLASS_NAMES_MALE[classFile]
        end
        if LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile] then
            return LOCALIZED_CLASS_NAMES_FEMALE[classFile]
        end
    end
    return "Unknown"
end

local function GetSafeClassColor(classFile)
    if classFile and classFile ~= "" then
        return PRT.GetClassColor(classFile)
    end
    return PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3]
end

local function MakeAliasCache(alias)
    alias._labelNorm = NormalizeName(alias.label)
    for _, character in ipairs(alias.characters or {}) do
        character.name = PRT.Trim(character.name or "")
        character.realm = PRT.Trim(character.realm or "")
        character.classFile = PRT.Trim(character.classFile or "")
        character.baseNorm = NormalizeName(character.name)
        character.realmNorm = NormalizeRealm(character.realm)
        character.fullNorm = MakeFullNorm(character.baseNorm, character.realmNorm)
    end
end

local function RefreshAliasCache()
    local rm = EnsureMatcherDB()
    for idx, alias in ipairs(rm.aliases) do
        if type(alias.characters) ~= "table" then
            alias.characters = {}
        end
        if not alias.id or alias.id == "" then
            alias.id = "alias_" .. tostring(rm.nextAliasId)
            rm.nextAliasId = rm.nextAliasId + 1
        end
        MakeAliasCache(alias)
        alias.sortIndex = idx
    end
end

local function SortAliasCharacters(alias)
    table.sort(alias.characters, function(a, b)
        if a.baseNorm ~= b.baseNorm then
            return a.baseNorm < b.baseNorm
        end
        return a.realmNorm < b.realmNorm
    end)
end

local function FindAliasImportHits(importEntry)
    local rm = EnsureMatcherDB()
    local hits = {}

    for _, alias in ipairs(rm.aliases) do
        local strength
        if alias._labelNorm == importEntry.baseNorm then
            strength = 70
        end
        for _, character in ipairs(alias.characters or {}) do
            if importEntry.realmNorm ~= "" and character.fullNorm == importEntry.fullNorm then
                strength = math.max(strength or 0, 90)
            elseif character.baseNorm == importEntry.baseNorm then
                strength = math.max(strength or 0, 80)
            end
        end
        if strength then
            hits[#hits + 1] = {
                alias = alias,
                strength = strength,
            }
        end
    end

    return hits
end

local function GetAliasLiveStrength(alias, liveEntry)
    local best
    for _, character in ipairs(alias.characters or {}) do
        if character.fullNorm == liveEntry.fullNorm then
            best = math.max(best or 0, 30)
        elseif character.baseNorm == liveEntry.baseNorm then
            best = math.max(best or 0, 22)
        end
    end
    return best
end

local function EvaluateCandidate(importEntry, liveEntry)
    local aliasHits = FindAliasImportHits(importEntry)
    local bestAlias, bestRank

    for _, aliasHit in ipairs(aliasHits) do
        local liveStrength = GetAliasLiveStrength(aliasHit.alias, liveEntry)
        if liveStrength then
            local rank = aliasHit.strength + liveStrength
            if not bestRank or rank > bestRank then
                bestAlias = aliasHit.alias
                bestRank = rank
            end
        end
    end

    if bestAlias then
        return {
            importEntry = importEntry,
            liveEntry = liveEntry,
            alias = bestAlias,
            knownAlias = true,
            confidence = 100,
            confidenceText = "Known Alias",
            rank = 1000 + bestRank,
            canSave = false,
            canDeleteAlias = true,
        }
    end

    local score = ComputeLooseScore(importEntry, liveEntry)
    if score <= 0 then
        return nil
    end

    return {
        importEntry = importEntry,
        liveEntry = liveEntry,
        alias = nil,
        knownAlias = false,
        confidence = score,
        confidenceText = tostring(score) .. "%",
        rank = score,
        canSave = true,
        canDeleteAlias = false,
    }
end

local function BuildImportEntries(comp)
    local entries = {}
    local roster = comp and comp.roster or {}
    for slotIndex = 1, 40 do
        local rawName = PRT.Trim(roster[slotIndex] or "")
        if rawName ~= "" then
            local baseName, realm = PRT:SplitNameRealm(rawName, false)
            local baseNorm = NormalizeName(baseName)
            local realmNorm = NormalizeRealm(realm)
            entries[#entries + 1] = {
                slotIndex = slotIndex,
                group = math.floor((slotIndex - 1) / 5) + 1,
                position = ((slotIndex - 1) % 5) + 1,
                groupPos = ("G%d:%d"):format(math.floor((slotIndex - 1) / 5) + 1, ((slotIndex - 1) % 5) + 1),
                rawName = rawName,
                baseName = baseName,
                realm = realm,
                strictBaseNorm = StrictNormalizeName(baseName),
                strictRealmNorm = StrictNormalizeRealm(realm),
                strictFullNorm = MakeFullNorm(StrictNormalizeName(baseName), StrictNormalizeRealm(realm)),
                baseNorm = baseNorm,
                realmNorm = realmNorm,
                fullNorm = MakeFullNorm(baseNorm, realmNorm),
            }
        end
    end
    return entries
end

local function AssignUniqueExact(importEntries, liveEntries)
    local assignedSlots = {}
    local assignedLives = {}

    for _, importEntry in ipairs(importEntries) do
        if importEntry.strictRealmNorm ~= "" then
            local matches = {}
            for liveIndex, liveEntry in ipairs(liveEntries) do
                if not assignedLives[liveIndex] and liveEntry.strictFullNorm == importEntry.strictFullNorm then
                    matches[#matches + 1] = liveIndex
                end
            end
            if #matches == 1 then
                assignedSlots[importEntry.slotIndex] = matches[1]
                assignedLives[matches[1]] = true
            end
        end
    end

    for _, importEntry in ipairs(importEntries) do
        if not assignedSlots[importEntry.slotIndex] then
            local matches = {}
            for liveIndex, liveEntry in ipairs(liveEntries) do
                if not assignedLives[liveIndex] and liveEntry.strictBaseNorm == importEntry.strictBaseNorm then
                    matches[#matches + 1] = liveIndex
                end
            end
            if #matches == 1 then
                assignedSlots[importEntry.slotIndex] = matches[1]
                assignedLives[matches[1]] = true
            end
        end
    end

    return assignedSlots, assignedLives
end

function PRT:GetRosterMatcherDB()
    return EnsureMatcherDB()
end

function PRT:GetRosterMatcherClassOptions()
    return CLASS_OPTIONS
end

function PRT:GetHomeRealmName()
    local realm = GetRealmName and GetRealmName() or ""
    realm = PRT.Trim(realm)
    if realm == "" and GetNormalizedRealmName then
        realm = PRT.Trim(GetNormalizedRealmName() or "")
    end
    return realm
end

function PRT:SplitNameRealm(fullName, fillHomeRealm)
    local raw = PRT.Trim(fullName or "")
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

    name = PRT.Trim(name)
    realm = PRT.Trim(realm or "")

    if fillHomeRealm and name ~= "" and realm == "" then
        realm = self:GetHomeRealmName()
    end

    return name, realm
end

function PRT:MakeCharacterFullName(name, realm, forceRealm)
    name = PRT.Trim(name or "")
    realm = PRT.Trim(realm or "")
    if name == "" then return "" end
    if realm == "" then return name end
    if not forceRealm and NormalizeRealm(realm) == NormalizeRealm(self:GetHomeRealmName()) then
        return name
    end
    return name .. "-" .. realm
end

function PRT:NormalizeMatchText(text)
    return NormalizeName(text)
end

function PRT:GetDetailedRaidRoster()
    local roster = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for raidIndex = 1, count do
        local rawName, _, subgroup, _, _, classFile = GetRaidRosterInfo(raidIndex)
        if rawName and subgroup then
            local name, realm = self:SplitNameRealm(rawName, true)
            local baseNorm = NormalizeName(name)
            if baseNorm ~= "" then
                roster[#roster + 1] = {
                    raidIndex = raidIndex,
                    subgroup = subgroup,
                    apiName = rawName,
                    name = name,
                    realm = realm,
                    strictBaseNorm = StrictNormalizeName(name),
                    strictRealmNorm = StrictNormalizeRealm(realm),
                    strictFullNorm = MakeFullNorm(StrictNormalizeName(name), StrictNormalizeRealm(realm)),
                    baseNorm = baseNorm,
                    realmNorm = NormalizeRealm(realm),
                    fullNorm = MakeFullNorm(baseNorm, NormalizeRealm(realm)),
                    classFile = classFile or UNKNOWN_CLASS,
                    fullName = self:MakeCharacterFullName(name, realm, true),
                    displayName = self:MakeCharacterFullName(name, realm, false),
                }
            end
        end
    end
    return roster
end

function PRT:GetMatcherClassColor(classFile)
    return GetSafeClassColor(classFile)
end

function PRT:GetMatcherClassLabel(classFile)
    return GetClassLabel(classFile)
end

function PRT:GetAliasById(aliasId)
    RefreshAliasCache()
    for _, alias in ipairs(EnsureMatcherDB().aliases) do
        if alias.id == aliasId then
            return alias
        end
    end
end

function PRT:GetAliasByLabel(label)
    local labelNorm = NormalizeName(label)
    if labelNorm == "" then return nil end
    RefreshAliasCache()
    for _, alias in ipairs(EnsureMatcherDB().aliases) do
        if alias._labelNorm == labelNorm then
            return alias
        end
    end
end

function PRT:GetAliasContainingCharacter(name, realm)
    local baseName = PRT.Trim(name or "")
    if baseName == "" then return nil end

    local baseNorm = NormalizeName(baseName)
    local realmNorm = NormalizeRealm(realm)
    local fullNorm = MakeFullNorm(baseNorm, realmNorm)

    RefreshAliasCache()
    for _, alias in ipairs(EnsureMatcherDB().aliases) do
        for _, character in ipairs(alias.characters or {}) do
            if fullNorm ~= baseNorm and character.fullNorm == fullNorm then
                return alias, character
            end
            if character.baseNorm == baseNorm then
                return alias, character
            end
        end
    end
    return nil
end

function PRT:CreateRosterAlias(label)
    label = PRT.Trim(label or "")
    if label == "" then
        return nil, "Alias name is required."
    end
    if self:GetAliasByLabel(label) then
        return nil, "Alias already exists."
    end

    local rm = EnsureMatcherDB()
    local alias = {
        id = "alias_" .. tostring(rm.nextAliasId),
        label = label,
        characters = {},
    }
    rm.nextAliasId = rm.nextAliasId + 1
    rm.aliases[#rm.aliases + 1] = alias
    MakeAliasCache(alias)
    return alias
end

function PRT:RenameRosterAlias(aliasId, newLabel)
    local alias = self:GetAliasById(aliasId)
    if not alias then
        return false, "Alias not found."
    end

    newLabel = PRT.Trim(newLabel or "")
    if newLabel == "" then
        return false, "Alias name is required."
    end

    local existing = self:GetAliasByLabel(newLabel)
    if existing and existing.id ~= aliasId then
        return false, "Alias already exists."
    end

    alias.label = newLabel
    MakeAliasCache(alias)
    return true
end

function PRT:DeleteRosterAlias(aliasId)
    local rm = EnsureMatcherDB()
    for idx, alias in ipairs(rm.aliases) do
        if alias.id == aliasId then
            table.remove(rm.aliases, idx)
            return true
        end
    end
    return false, "Alias not found."
end

function PRT:AddCharacterToAlias(aliasId, characterInfo)
    local alias = self:GetAliasById(aliasId)
    if not alias then
        return nil, "Alias not found."
    end

    local name = PRT.Trim(characterInfo and characterInfo.name or "")
    if name == "" then
        return nil, "Character name is required."
    end

    local realm = PRT.Trim(characterInfo and characterInfo.realm or "")
    if realm == "" then
        realm = self:GetHomeRealmName()
    end

    local classFile = PRT.Trim(characterInfo and characterInfo.classFile or "")
    if classFile ~= "" then
        classFile = string.upper(classFile)
    end

    local baseNorm = NormalizeName(name)
    local realmNorm = NormalizeRealm(realm)
    local fullNorm = MakeFullNorm(baseNorm, realmNorm)

    for _, character in ipairs(alias.characters or {}) do
        if character.fullNorm == fullNorm then
            if character.classFile == "" and classFile ~= "" then
                character.classFile = classFile
            end
            MakeAliasCache(alias)
            return character, true
        end
    end

    local character = {
        name = name,
        realm = realm,
        classFile = classFile,
    }
    alias.characters[#alias.characters + 1] = character
    MakeAliasCache(alias)
    SortAliasCharacters(alias)
    MakeAliasCache(alias)
    return character, true
end

function PRT:RemoveCharacterFromAlias(aliasId, characterKey)
    local alias = self:GetAliasById(aliasId)
    if not alias then
        return false, "Alias not found."
    end

    if type(characterKey) == "number" then
        if alias.characters[characterKey] then
            table.remove(alias.characters, characterKey)
            MakeAliasCache(alias)
            return true
        end
        return false, "Character not found."
    end

    local name, realm = self:SplitNameRealm(characterKey, true)
    local fullNorm = MakeFullNorm(NormalizeName(name), NormalizeRealm(realm))
    for idx, character in ipairs(alias.characters or {}) do
        if character.fullNorm == fullNorm then
            table.remove(alias.characters, idx)
            MakeAliasCache(alias)
            return true
        end
    end

    return false, "Character not found."
end

function PRT:GetRosterAliasList()
    RefreshAliasCache()
    return EnsureMatcherDB().aliases
end

function PRT:SaveCharacterToAliasLabel(aliasLabel, liveEntry)
    aliasLabel = PRT.Trim(aliasLabel or "")
    if aliasLabel == "" then
        return nil, "Alias name is required."
    end
    if not liveEntry then
        return nil, "Live character missing."
    end

    local alias = self:GetAliasByLabel(aliasLabel)
    if not alias then
        alias = self:CreateRosterAlias(aliasLabel)
        if not alias then
            return nil, "Failed to create alias."
        end
    end

    return self:AddCharacterToAlias(alias.id, {
        name = liveEntry.name,
        realm = liveEntry.realm,
        classFile = liveEntry.classFile,
    })
end

function PRT:SaveMatchedCharacterToAlias(importName, liveEntry, explicitAliasLabel)
    explicitAliasLabel = PRT.Trim(explicitAliasLabel or "")
    if explicitAliasLabel ~= "" then
        return self:SaveCharacterToAliasLabel(explicitAliasLabel, liveEntry)
    end

    if not liveEntry then
        return nil, "Live character missing."
    end

    local baseImport, importRealm = self:SplitNameRealm(importName, false)
    local alias = self:GetAliasByLabel(baseImport)
    if not alias then
        alias = self:GetAliasContainingCharacter(baseImport, importRealm)
    end
    if not alias then
        alias = self:CreateRosterAlias(PRT.StripRealm(baseImport))
        if not alias then
            return nil, "Failed to create alias."
        end
    end

    return self:AddCharacterToAlias(alias.id, {
        name = liveEntry.name,
        realm = liveEntry.realm,
        classFile = liveEntry.classFile,
    })
end

function PRT:FindAliasesByCharacterQuery(query)
    local baseName, realm = self:SplitNameRealm(query, false)
    local baseNorm = NormalizeName(baseName)
    if baseNorm == "" then return {} end

    local realmNorm = NormalizeRealm(realm)
    local fullNorm = MakeFullNorm(baseNorm, realmNorm)
    local exact = {}
    local baseMatches = {}

    RefreshAliasCache()
    for _, alias in ipairs(EnsureMatcherDB().aliases) do
        for _, character in ipairs(alias.characters or {}) do
            if realmNorm ~= "" and character.fullNorm == fullNorm then
                exact[#exact + 1] = { alias = alias, character = character }
            elseif character.baseNorm == baseNorm then
                baseMatches[#baseMatches + 1] = { alias = alias, character = character }
            end
        end
    end

    if #exact > 0 then
        table.sort(exact, function(a, b)
            if (a.alias.label or "") ~= (b.alias.label or "") then
                return (a.alias.label or "") < (b.alias.label or "")
            end
            if (a.character.name or "") ~= (b.character.name or "") then
                return (a.character.name or "") < (b.character.name or "")
            end
            return (a.character.realm or "") < (b.character.realm or "")
        end)
        return exact
    end
    table.sort(baseMatches, function(a, b)
        if (a.alias.label or "") ~= (b.alias.label or "") then
            return (a.alias.label or "") < (b.alias.label or "")
        end
        if (a.character.name or "") ~= (b.character.name or "") then
            return (a.character.name or "") < (b.character.name or "")
        end
        return (a.character.realm or "") < (b.character.realm or "")
    end)
    return baseMatches
end

function PRT:BuildRosterMatchAnalysis(compName, thresholdOverride, rosterOverride)
    local comp = self:GetComp(compName)
    if not comp then
        return nil, "No composition selected."
    end

    RefreshAliasCache()

    local rm = EnsureMatcherDB()
    local threshold = Clamp(tonumber(thresholdOverride) or tonumber(rm.threshold) or 50, 0, 100)
    local importEntries = BuildImportEntries({
        roster = rosterOverride or comp.roster,
    })
    local liveEntries = self:GetDetailedRaidRoster()
    local assignedSlots, assignedLives = AssignUniqueExact(importEntries, liveEntries)

    local unresolvedImports = {}
    for _, importEntry in ipairs(importEntries) do
        if not assignedSlots[importEntry.slotIndex] then
            unresolvedImports[#unresolvedImports + 1] = importEntry
        end
    end

    local strongPairs = {}
    for _, importEntry in ipairs(unresolvedImports) do
        for liveIndex, liveEntry in ipairs(liveEntries) do
            if not assignedLives[liveIndex] then
                local candidate = EvaluateCandidate(importEntry, liveEntry)
                if candidate and (candidate.knownAlias or candidate.confidence >= threshold) then
                    candidate.liveIndex = liveIndex
                    strongPairs[#strongPairs + 1] = candidate
                end
            end
        end
    end

    table.sort(strongPairs, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        if a.importEntry.slotIndex ~= b.importEntry.slotIndex then
            return a.importEntry.slotIndex < b.importEntry.slotIndex
        end
        return a.liveEntry.name < b.liveEntry.name
    end)

    local strongBySlot = {}
    local strongUsedLives = {}
    local topMatches = {}
    for _, candidate in ipairs(strongPairs) do
        if not strongBySlot[candidate.importEntry.slotIndex] and not strongUsedLives[candidate.liveIndex] then
            strongBySlot[candidate.importEntry.slotIndex] = candidate
            strongUsedLives[candidate.liveIndex] = true
            topMatches[#topMatches + 1] = candidate
        end
    end

    table.sort(topMatches, function(a, b)
        return a.importEntry.slotIndex < b.importEntry.slotIndex
    end)

    local lowerRows = {}
    for _, importEntry in ipairs(unresolvedImports) do
        if not strongBySlot[importEntry.slotIndex] then
            local bestCandidate
            for liveIndex, liveEntry in ipairs(liveEntries) do
                if not assignedLives[liveIndex] and not strongUsedLives[liveIndex] then
                    local candidate = EvaluateCandidate(importEntry, liveEntry)
                    if candidate then
                        candidate.liveIndex = liveIndex
                        if (not bestCandidate) or candidate.rank > bestCandidate.rank then
                            bestCandidate = candidate
                        end
                    end
                end
            end

            lowerRows[#lowerRows + 1] = {
                importEntry = importEntry,
                suggestion = bestCandidate,
            }
        end
    end

    local unmatchedLive = {}
    for liveIndex, liveEntry in ipairs(liveEntries) do
        if not assignedLives[liveIndex] and not strongUsedLives[liveIndex] then
            unmatchedLive[#unmatchedLive + 1] = {
                liveIndex = liveIndex,
                liveEntry = liveEntry,
            }
        end
    end

    table.sort(unmatchedLive, function(a, b)
        if a.liveEntry.subgroup ~= b.liveEntry.subgroup then
            return a.liveEntry.subgroup < b.liveEntry.subgroup
        end
        return a.liveEntry.name < b.liveEntry.name
    end)

    return {
        compName = compName,
        threshold = threshold,
        exactAssignments = assignedSlots,
        liveEntries = liveEntries,
        topMatches = topMatches,
        lowerRows = lowerRows,
        unmatchedLive = unmatchedLive,
    }
end

function PRT:ApplyRosterMatchActions(compName, actions)
    local comp = self:GetComp(compName)
    if not comp then
        return false, "No composition selected."
    end

    local roster = {}
    for i = 1, 40 do
        roster[i] = comp.roster[i] or ""
    end

    local changed = 0
    for _, action in ipairs(actions or {}) do
        if action.slotIndex and action.liveEntry then
            roster[action.slotIndex] = action.liveEntry.apiName or action.liveEntry.displayName
            changed = changed + 1
            if PRT.Trim(action.aliasLabel or "") ~= "" then
                self:SaveMatchedCharacterToAlias(action.importName or action.liveEntry.name, action.liveEntry, action.aliasLabel)
            end
        end
    end

    if changed == 0 then
        return false, "No matches selected."
    end

    self:UpdateCompRoster(compName, roster)
    return true, changed
end
