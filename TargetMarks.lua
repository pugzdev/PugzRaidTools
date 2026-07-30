---------------------------------------------------------------------------
-- PugzRaidTools - Target Marks
-- Mouseover-driven NPC marking based on the active preset. Each NPC entry can
-- hold multiple mark priorities per modifier slot, matching the old
-- AutoMarker flow without requiring duplicate UI rows.
---------------------------------------------------------------------------
local addonName, PRT = ...

PRT.TARGET_MARK_SLOTS = { "main", "alt1", "alt2" }
PRT.TARGET_MARKS_DEFAULT_VERSION = 2

local normalizedTargetMarksEntries = setmetatable({}, { __mode = "k" })
local targetMarksDebug = {
    enabled = false,
    counters = {},
    baseline = nil,
}

local function CountTargetMarksDebug(key, amount)
    if not targetMarksDebug.enabled then return end
    local counters = targetMarksDebug.counters
    counters[key] = (counters[key] or 0) + (amount or 1)
end

local function ReadLuaHeapKB(forceGC)
    if type(collectgarbage) ~= "function" then return nil end
    if forceGC then
        pcall(collectgarbage, "collect")
    end
    local ok, value = pcall(collectgarbage, "count")
    return ok and tonumber(value) or nil
end

local function ReadAddonMemoryKB()
    if type(UpdateAddOnMemoryUsage) == "function" then
        UpdateAddOnMemoryUsage()
    end
    if type(GetAddOnMemoryUsage) ~= "function" then return nil end
    return tonumber(GetAddOnMemoryUsage(addonName or "PugzRaidTools"))
end

local function CaptureTargetMarksMemory(forceGC)
    local luaHeapKB = ReadLuaHeapKB(forceGC)
    return {
        addonKB = ReadAddonMemoryKB(),
        luaHeapKB = luaHeapKB,
        time = type(GetTime) == "function" and GetTime() or 0,
    }
end

function PRT:IsTargetMarksMemoryDebugEnabled()
    return targetMarksDebug.enabled
end

function PRT:CountTargetMarksDebug(key, amount)
    CountTargetMarksDebug(key, amount)
end

function PRT:GetTargetMarksDebugCounters()
    return targetMarksDebug.counters
end

function PRT:SetTargetMarksMemoryDebug(enabled)
    enabled = enabled and true or false
    if enabled then
        targetMarksDebug.enabled = true
        targetMarksDebug.counters = {}
        targetMarksDebug.baseline = CaptureTargetMarksMemory(false)
        PRT.Print("Target Marks memory debug enabled. Scroll the list, then use /prt debugui mem.")
        return
    end

    if targetMarksDebug.enabled then
        self:DumpTargetMarksMemoryDebug(false, "final")
    end
    targetMarksDebug.enabled = false
    targetMarksDebug.baseline = nil
    PRT.Print("Target Marks memory debug disabled.")
end

function PRT:DumpTargetMarksMemoryDebug(forceGC, label)
    local snapshot = CaptureTargetMarksMemory(forceGC)
    local baseline = targetMarksDebug.baseline or snapshot
    local addonDelta = snapshot.addonKB and baseline.addonKB
        and (snapshot.addonKB - baseline.addonKB) or nil
    local luaDelta = snapshot.luaHeapKB and baseline.luaHeapKB
        and (snapshot.luaHeapKB - baseline.luaHeapKB) or nil
    local counters = targetMarksDebug.counters

    PRT.Print(("TARGET MARKS MEMORY %s%s addon=%s delta=%s luaHeap(all addons)=%s delta=%s"):format(
        tostring(label or "snapshot"),
        forceGC and " after-GC" or "",
        snapshot.addonKB and ("%.1fKB"):format(snapshot.addonKB) or "unavailable",
        addonDelta and ("%+.1fKB"):format(addonDelta) or "unavailable",
        snapshot.luaHeapKB and ("%.1fKB"):format(snapshot.luaHeapKB) or "unavailable",
        luaDelta and ("%+.1fKB"):format(luaDelta) or "unavailable"))
    PRT.Print(("normalization calls=%d rebuilt=%d slotReads=%d groupScans=%d entriesScanned=%d"):format(
        counters.entryEnsureCalls or 0,
        counters.entryNormalizationRebuilds or 0,
        counters.slotListReads or 0,
        counters.groupEnsureCalls or 0,
        counters.groupEntriesScanned or 0))
    PRT.Print(("scroll requests=%d refreshes=%d unchangedSkips=%d rowBindings=%d refreshTime=%.2fms"):format(
        counters.visibleRefreshRequests or 0,
        counters.visibleRefreshes or 0,
        counters.unchangedRangeSkips or 0,
        counters.rowBindings or 0,
        counters.visibleRefreshMs or 0))
    PRT.Print(("created while tracing rows=%d markButtons=%d"):format(
        counters.rowFramesCreated or 0,
        counters.markButtonsCreated or 0))

    local panel = self.targetMarksPanel
    if panel and panel.GetTargetMarksDebugSummary then
        local summary = panel:GetTargetMarksDebugSummary()
        PRT.Print(("current groupEntries=%d visible=%d-%d pooledRows=%d markButtons=%d editStates=%d scroll=%.1f"):format(
            summary.groupEntries or 0,
            summary.visibleStart or 0,
            summary.visibleEnd or 0,
            summary.pooledRows or 0,
            summary.markButtons or 0,
            summary.editStates or 0,
            summary.scrollOffset or 0))
    end
end

PRT.TARGET_MARK_MODIFIER_ITEMS = {
    { text = "CTRL",     value = "CTRL" },
    { text = "ALT",      value = "ALT"  },
    { text = "SHIFT",    value = "SHIFT" },
    { text = "Disabled", value = "NONE" },
}

local LEGACY_TARGET_MARK_GROUPS = {
    { name = "Naxxramas", rows = {
        { 15976, "Venom Stalker", 8 },
        { 15975, "Carrion Spinner", 7 },
        { 15975, "Carrion Spinner", 5 },
        { 15975, "Carrion Spinner", 6 },
        { 15975, "Carrion Spinner", 4 },
        { 15975, "Carrion Spinner", 3 },
        { 15974, "Dread Creeper", 7 },
        { 15974, "Dread Creeper", 5 },
        { 15974, "Dread Creeper", 6 },
        { 15974, "Dread Creeper", 4 },
        { 15974, "Dread Creeper", 3 },
        { 15956, "Anub'Rekhan", 8 },
        { 16573, "Crypt Guard", 7 },
        { 16573, "Crypt Guard", 6 },
        { 15978, "Crypt Reaver", 8 },
        { 16453, "Necro Stalker", 8 },
        { 16453, "Necro Stalker", 7 },
        { 16453, "Necro Stalker", 6 },
        { 16453, "Necro Stalker", 5 },
        { 16505, "Naxxramas Follower", 8 },
        { 16505, "Naxxramas Follower", 7 },
        { 16506, "Naxxramas Worshipper", 5 },
        { 16506, "Naxxramas Worshipper", 4 },
        { 16506, "Naxxramas Worshipper", 3 },
        { 16506, "Naxxramas Worshipper", 6 },
        { 15953, "Faerlina", 2 },
        { 15979, "Tomb Horror", 8 },
        { 16447, "Plagued Ghoul", 8 },
        { 16447, "Plagued Ghoul", 7 },
        { 16447, "Plagued Ghoul", 6 },
        { 16447, "Plagued Ghoul", 5 },
        { 16146, "Deathknight", 7 },
        { 16146, "Deathknight", 6 },
        { 16146, "Deathknight", 5 },
        { 16145, "Deathknight Captain", 8 },
        { 16145, "Deathknight Captain", 7 },
        { 16145, "Deathknight Captain", 6 },
        { 16145, "Deathknight Captain", 5 },
        { 16165, "Necro Knight", 8 },
        { 16165, "Necro Knight", 7 },
        { 16164, "Shade of Naxxramas", 4 },
        { 16156, "Dark Touched Warrior", 5 },
        { 16156, "Dark Touched Warrior", 4 },
        { 16156, "Dark Touched Warrior", 3 },
        { 16157, "Doom Touched Warrior", 5 },
        { 16157, "Doom Touched Warrior", 4 },
        { 16157, "Doom Touched Warrior", 3 },
        { 16158, "Death Touched Warrior", 5 },
        { 16158, "Death Touched Warrior", 4 },
        { 16158, "Death Touched Warrior", 3 },
        { 16163, "Deathknight Cavalier", 8 },
        { 16163, "Deathknight Cavalier", 7 },
        { 16163, "Deathknight Cavalier", 6 },
        { 16861, "Death Lord", 6 },
        { 16067, "Skeletal Steed", 8 },
        { 16067, "Skeletal Steed", 7 },
        { 16803, "Deathknight Understudy", 8 },
        { 16803, "Deathknight Understudy", 7 },
        { 16803, "Deathknight Understudy", 6 },
        { 16803, "Deathknight Understudy", 5 },
        { 16194, "Unholy Axe", 7 },
        { 16194, "Unholy Axe", 8 },
        { 16215, "Unholy Staff", 8 },
        { 16215, "Unholy Staff", 7 },
        { 16216, "Unholy Sword", 7 },
        { 16216, "Unholy Sword", 8 },
        { 16216, "Unholy Sword", 6 },
        { 16216, "Unholy Sword", 5 },
        { 16452, "Necro Knight Guardian", 8 },
        { 16452, "Necro Knight Guardian", 7 },
        { 16451, "Deathknight Vindicator", 6 },
        { 16064, "Thane Korth'azz", 8 },
        { 16062, "Highlord Mograine", 7 },
        { 16063, "Sir Zeliek", 6 },
        { 16065, "Lady Blaumeux", 5 },
        { 16017, "Patchwork Golem", 8 },
        { 16017, "Patchwork Golem", 7 },
        { 16017, "Patchwork Golem", 6 },
        { 16017, "Patchwork Golem", 5 },
        { 16018, "Bile Retcher", 6 },
        { 16018, "Bile Retcher", 8 },
        { 16375, "Sewage Slime", 8 },
        { 16375, "Sewage Slime", 7 },
        { 16375, "Sewage Slime", 6 },
        { 16029, "Sludge Belcher", 8 },
        { 16029, "Sludge Belcher", 7 },
        { 16021, "Living Monstrosity", 8 },
        { 16020, "Mad Scientist", 7 },
        { 16020, "Mad Scientist", 6 },
        { 16020, "Mad Scientist", 5 },
        { 16020, "Mad Scientist", 4 },
        { 16022, "Surgical Assistant", 2 },
        { 16022, "Surgical Assistant", 1 },
        { 16025, "Stitched Spewer", 8 },
        { 16025, "Stitched Spewer", 7 },
        { 16025, "Stitched Spewer", 6 },
        { 16025, "Stitched Spewer", 5 },
        { 16244, "Infectious Ghoul", 6 },
        { 16244, "Infectious Ghoul", 5 },
        { 16244, "Infectious Ghoul", 4 },
        { 16244, "Infectious Ghoul", 3 },
        { 16243, "Plague Slime", 8 },
        { 16243, "Plague Slime", 7 },
        { 16168, "Stoneskin Gargoyle", 8 },
        { 16168, "Stoneskin Gargoyle", 7 },
        { 16297, "Mutated Grub", 8 },
        { 16297, "Mutated Grub", 7 },
        { 16286, "Spore", 8 },
        { 16286, "Spore", 7 },
        { 16286, "Spore", 6 },
        { 16368, "Necropolis Acolytes", 8 },
        { 16368, "Necropolis Acolytes", 7 },
        { 16449, "Spirit of Naxxramas", 4 },
        { 16193, "Skeletal Smith", 8 },
        { 16193, "Skeletal Smith", 7 },
        { 16193, "Skeletal Smith", 6 },
        { 16446, "Plagued Gargoyle", 8 },
        { 16446, "Plagued Gargoyle", 7 },
        { 16446, "Plagued Gargoyle", 6 },
    } },
    { name = "AQ40", rows = {
        { 15263, "Boss", 4 },
        { 15511, "Lord Kri", 8 },
        { 15543, "Princess Yauj", 7 },
        { 15544, "Vem", 6 },
        { 15516, "Battleguard Sartura", 8 },
        { 15984, "Sartura's Royal Guard", 7 },
        { 15984, "Sartura's Royal Guard", 6 },
        { 15984, "Sartura's Royal Guard", 5 },
        { 15229, "Vekniss Soldier", 8 },
        { 15262, "Obsidian Eradicator", 4 },
        { 15262, "Obsidian Eradicator", 3 },
        { 15264, "Anubisath Sentinel (Start 4 packs)", 8 },
        { 15264, "Anubisath Sentinel (Start 4 packs)", 7 },
        { 15264, "Anubisath Sentinel (Start 4 packs)", 6 },
        { 15264, "Anubisath Sentinel (Start 4 packs)", 5 },
        { 15247, "Qiraji Brainwasher", 8 },
        { 15247, "Qiraji Brainwasher", 7 },
        { 15230, "Vekniss Warrior", 8 },
        { 15230, "Vekniss Warrior", 7 },
        { 15230, "Vekniss Warrior", 6 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 6 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 5 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 4 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 4 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 8 },
        { 15233, "Vekniss Guardian (Knockup / Bleed packs)", 7 },
        { 15240, "Vekniss Hive Crawler (Scorpians Fankriss)", 8 },
        { 15240, "Vekniss Hive Crawler (Scorpians Fankriss)", 7 },
        { 15240, "Vekniss Hive Crawler (Scorpians Fankriss)", 6 },
        { 15240, "Vekniss Hive Crawler (Scorpians Fankriss)", 5 },
        { 15235, "Vekniss Stinger (Big White Wasps)", 7 },
        { 15236, "Vekniss Wasp (Small wasps)", 6 },
        { 15236, "Vekniss Wasp (Small wasps)", 5 },
        { 15236, "Vekniss Wasp (Small wasps)", 4 },
        { 15249, "Qiraji Lasher", 8 },
        { 15249, "Qiraji Lasher", 3 },
        { 15277, "Anubisath Defender", 8 },
        { 15277, "Anubisath Defender", 7 },
        { 15277, "Anubisath Defender", 6 },
        { 15277, "Anubisath Defender", 5 },
        { 234830, "Anubisath Defender", 8 },
        { 234830, "Anubisath Defender", 7 },
        { 234830, "Anubisath Defender", 6 },
        { 234830, "Anubisath Defender", 5 },
        { 15537, "Anubisath Warrior", 5 },
        { 15538, "Anubisath Swarmguard", 5 },
        { 15252, "Qiraji Champion", 4 },
        { 15246, "Qiraji Mindslayer", 5 },
        { 15246, "Qiraji Mindslayer", 6 },
        { 15246, "Qiraji Mindslayer", 7 },
        { 15246, "Qiraji Mindslayer", 8 },
        { 234762, "Qiraji Mindslayer", 6 },
        { 234762, "Qiraji Mindslayer", 5 },
        { 234762, "Qiraji Mindslayer", 7 },
        { 234762, "Qiraji Mindslayer", 8 },
        { 15250, "Qiraji Slayer", 8 },
        { 15250, "Qiraji Slayer", 7 },
        { 15250, "Qiraji Slayer", 6 },
        { 15250, "Qiraji Slayer", 5 },
        { 234800, "Qiraji Slayer", 8 },
        { 234800, "Qiraji Slayer", 7 },
        { 234800, "Qiraji Slayer", 6 },
        { 234800, "Qiraji Slayer", 5 },
        { 15312, "Obsidian Nullifier", 8 },
        { 15312, "Obsidian Nullifier", 7 },
        { 15311, "Anubisath Warder", 6 },
    } },
    { name = "BWL", rows = {
        { 12464, "Death Talon Seether", 5 },
        { 12464, "Death Talon Seether", 6 },
        { 12464, "Death Talon Seether", 7 },
        { 12465, "Death Talon Wyrmkin", 8 },
        { 12465, "Death Talon Wyrmkin", 3 },
        { 12463, "Death Talon Flamescale", 7 },
        { 12463, "Death Talon Flamescale", 6 },
        { 12463, "Death Talon Flamescale", 5 },
        { 12467, "Death Talon Captain", 4 },
        { 12468, "Death Talon Hatcher", 8 },
        { 12468, "Death Talon Hatcher", 7 },
        { 12468, "Death Talon Hatcher", 6 },
        { 12458, "Blackwing Taskmaster", 4 },
        { 12458, "Blackwing Taskmaster", 5 },
        { 12458, "Blackwing Taskmaster", 6 },
        { 12458, "Blackwing Taskmaster", 7 },
        { 12458, "Blackwing Taskmaster", 8 },
        { 12459, "Blackwing Warlock", 8 },
        { 12459, "Blackwing Warlock", 7 },
        { 12461, "Death Talon Overseer", 6 },
        { 12457, "Blackwing Spellbinder", 5 },
        { 12457, "Blackwing Spellbinder", 4 },
        { 12460, "Death Talon Wyrmguard", 2 },
        { 12460, "Death Talon Wyrmguard", 7 },
        { 12460, "Death Talon Wyrmguard", 6 },
    } },
    { name = "MC", rows = {
        { 12118, "Lucifron", 8 },
        { 12118, "Lucifron", 7 },
        { 12119, "Flamewaker Protector", 8 },
        { 12119, "Flamewaker Protector", 7 },
        { 12259, "Gehennas", 8 },
        { 11664, "Flamewaker Elite", 7 },
        { 11664, "Flamewaker Elite", 6 },
        { 11664, "Flamewaker Elite", 3 },
        { 11664, "Flamewaker Elite", 4 },
        { 11664, "Flamewaker Elite", 5 },
        { 12099, "Firesworn", 1 },
        { 12099, "Firesworn", 2 },
        { 12099, "Firesworn", 3 },
        { 12099, "Firesworn", 4 },
        { 12099, "Firesworn", 5 },
        { 12099, "Firesworn", 6 },
        { 12099, "Firesworn", 7 },
        { 12099, "Firesworn", 8 },
        { 12098, "Sulfuron", 8 },
        { 11662, "Flamewaker Priest", 7 },
        { 11662, "Flamewaker Priest", 6 },
        { 11662, "Flamewaker Priest", 5 },
        { 11662, "Flamewaker Priest", 4 },
        { 11988, "Golemagg", 8 },
        { 11672, "Core Rager", 7 },
        { 11672, "Core Rager", 6 },
        { 11663, "Flamewaker Healer", 7 },
        { 11663, "Flamewaker Healer", 8 },
        { 11663, "Flamewaker Healer", 6 },
        { 11663, "Flamewaker Healer", 5 },
        { 11663, "Flamewaker Healer", 4 },
        { 11659, "Molten Destroyer", 8 },
        { 11659, "Molten Destroyer", 7 },
        { 11658, "Molten Giant", 7 },
        { 11658, "Molten Giant", 8 },
        { 11668, "Firelord", 6 },
        { 11668, "Firelord", 7 },
        { 11665, "Lava Annihilator", 5 },
        { 11665, "Lava Annihilator", 6 },
        { 12101, "Lava Surger", 4 },
        { 11673, "Ancient Core Hound", 8 },
        { 11673, "Ancient Core Hound", 7 },
        { 11673, "Ancient Core Hound", 6 },
        { 11666, "Firewalker", 8 },
        { 11667, "Flameguard", 7 },
        { 12076, "Lava Elemental", 6 },
        { 12076, "Lava Elemental", 5 },
        { 12100, "Lava Reaver", 6 },
    } },
}

local function GetModifierDown(key)
    if key == "CTRL" then return IsControlKeyDown() end
    if key == "ALT" then return IsAltKeyDown() end
    if key == "SHIFT" then return IsShiftKeyDown() end
    return false
end

local function SaveObservedMark(state, guid, markId, name)
    if not guid or not markId or markId <= 0 then return end

    for existingMarkId, info in pairs(state) do
        if info and info.guid == guid and existingMarkId ~= markId then
            state[existingMarkId] = nil
        end
    end

    state[markId] = {
        guid = guid,
        name = name or "",
    }
end

local function UnitAlreadyTracked(state, guid)
    for _, info in pairs(state) do
        if info and info.guid == guid then
            return true
        end
    end
    return false
end

local function FinalizeGroupImport(groups, currentGroup, currentEntry)
    if currentEntry and currentGroup then
        currentGroup.entries[#currentGroup.entries + 1] = currentEntry
    end
    if currentGroup then
        groups[#groups + 1] = currentGroup
    end
end

local function SanitizeExportValue(text)
    text = tostring(text or "")
    text = text:gsub("\r\n", " "):gsub("\r", " "):gsub("\n", " ")
    return text
end

local function AppendMark(list, markId)
    markId = tonumber(markId) or 0
    if markId > 0 then
        list[#list + 1] = markId
    end
end

local function AppendMarks(list, marks)
    if type(marks) == "table" then
        for _, markId in ipairs(marks) do
            AppendMark(list, markId)
        end
    else
        AppendMark(list, marks)
    end
end

local function ParseMarkList(text)
    local out = {}
    text = tostring(text or "")
    for token in text:gmatch("[^,%s]+") do
        AppendMark(out, token)
    end
    return out
end

local function SerializeMarkList(list)
    local out = {}
    for _, markId in ipairs(list or {}) do
        markId = tonumber(markId) or 0
        if markId > 0 then
            out[#out + 1] = tostring(markId)
        end
    end
    return table.concat(out, ",")
end

local function NewEntry(npcId, targetName)
    local entry = {
        npcId = tonumber(npcId) or 0,
        targetName = tostring(targetName or ""),
        marks = {
            main = {},
            alt1 = {},
            alt2 = {},
        },
    }
    normalizedTargetMarksEntries[entry] = true
    return entry
end

local function BuildLegacyEntries(rows)
    local entries = {}
    local lookup = {}

    for _, row in ipairs(rows or {}) do
        local npcId = tonumber(row[1]) or 0
        local key = tostring(npcId)
        local entry = lookup[key]
        if not entry then
            entry = NewEntry(npcId, row[2] or "")
            lookup[key] = entry
            entries[#entries + 1] = entry
        elseif (entry.targetName or "") == "" and row[2] and row[2] ~= "" then
            entry.targetName = tostring(row[2])
        end
        AppendMark(entry.marks.main, row[3])
    end

    return entries
end

function PRT:CreateTargetMarksEntry(npcId, targetName)
    return NewEntry(npcId, targetName)
end

function PRT:CreateLegacyTargetMarksPreset()
    local groups = {}
    for i, group in ipairs(LEGACY_TARGET_MARK_GROUPS) do
        groups[i] = {
            name = group.name,
            entries = BuildLegacyEntries(group.rows),
        }
    end
    return {
        name = "Default",
        groups = groups,
    }
end

function PRT:GetTargetMarksPreset(name)
    if not name or name == "" then return nil end
    local db = self:GetDB()
    local tm = db.targetMarks or {}
    for _, preset in ipairs(tm.presets or {}) do
        if preset.name == name then
            return preset
        end
    end
    return nil
end

function PRT:GetActiveTargetMarksPreset()
    local db = self:GetDB()
    local tm = db.targetMarks or {}
    return self:GetTargetMarksPreset(tm.activePreset)
end

function PRT:EnsureTargetMarksEntryDefaults(entry)
    if not entry then return end
    CountTargetMarksDebug("entryEnsureCalls")
    if normalizedTargetMarksEntries[entry] then
        return entry
    end
    CountTargetMarksDebug("entryNormalizationRebuilds")

    entry.npcId = tonumber(entry.npcId) or 0
    entry.targetName = tostring(entry.targetName or "")

    local marks = type(entry.marks) == "table" and entry.marks or {}
    local normalized = {
        main = {},
        alt1 = {},
        alt2 = {},
    }

    AppendMarks(normalized.main, marks.main)
    AppendMarks(normalized.alt1, marks.alt1)
    AppendMarks(normalized.alt2, marks.alt2)

    -- Migrate prior scalar/flat storage to the new list-based structure.
    AppendMarks(normalized.main, entry.mainMarks)
    AppendMarks(normalized.alt1, entry.alt1Marks or entry.altMarks1)
    AppendMarks(normalized.alt2, entry.alt2Marks or entry.altMarks2)

    AppendMark(normalized.main, entry.mainMark)
    AppendMark(normalized.alt1, entry.altMark1)
    AppendMark(normalized.alt2, entry.altMark2)

    entry.marks = normalized
    entry.mainMarks = nil
    entry.alt1Marks = nil
    entry.alt2Marks = nil
    entry.alt3Marks = nil
    entry.altMarks1 = nil
    entry.altMarks2 = nil
    entry.altMarks3 = nil
    entry.mainMark = nil
    entry.altMark1 = nil
    entry.altMark2 = nil
    entry.altMark3 = nil
    normalizedTargetMarksEntries[entry] = true
    return entry
end

local function GroupHasDuplicateNpcIds(entries)
    local seen = {}
    for _, entry in ipairs(entries or {}) do
        local npcId = tonumber(entry and entry.npcId) or 0
        if npcId > 0 then
            if seen[npcId] then
                return true
            end
            seen[npcId] = true
        end
    end
    return false
end

function PRT:CollapseTargetMarksEntries(entries)
    local collapsed = {}
    local lookup = {}

    for _, rawEntry in ipairs(entries or {}) do
        self:EnsureTargetMarksEntryDefaults(rawEntry)

        local npcId = tonumber(rawEntry.npcId) or 0
        local entry
        if npcId > 0 then
            local key = tostring(npcId)
            entry = lookup[key]
            if not entry then
                entry = NewEntry(rawEntry.npcId, rawEntry.targetName)
                lookup[key] = entry
                collapsed[#collapsed + 1] = entry
            elseif entry.targetName == "" and rawEntry.targetName ~= "" then
                entry.targetName = rawEntry.targetName
            end
        else
            entry = NewEntry(rawEntry.npcId, rawEntry.targetName)
            collapsed[#collapsed + 1] = entry
        end

        for _, slot in ipairs(self.TARGET_MARK_SLOTS) do
            AppendMarks(entry.marks[slot], rawEntry.marks and rawEntry.marks[slot])
        end
    end

    return collapsed
end

function PRT:GetTargetMarksSlotList(entry, slot)
    CountTargetMarksDebug("slotListReads")
    self:EnsureTargetMarksEntryDefaults(entry)
    entry.marks[slot] = entry.marks[slot] or {}
    return entry.marks[slot]
end

function PRT:EnsureTargetMarksGroupDefaults(group)
    if not group then return end
    CountTargetMarksDebug("groupEnsureCalls")
    group.name = PRT.Trim(group.name or "") ~= "" and group.name or "Group"
    group.entries = group.entries or {}
    CountTargetMarksDebug("groupEntriesScanned", #group.entries)

    if GroupHasDuplicateNpcIds(group.entries) then
        group.entries = self:CollapseTargetMarksEntries(group.entries)
    else
        for _, entry in ipairs(group.entries) do
            self:EnsureTargetMarksEntryDefaults(entry)
        end
    end
end

function PRT:EnsureTargetMarksPresetDefaults(preset)
    if not preset then return end
    CountTargetMarksDebug("presetEnsureCalls")
    preset.name = PRT.Trim(preset.name or "") ~= "" and preset.name or "Preset"
    preset.groups = preset.groups or {}
    for _, group in ipairs(preset.groups) do
        self:EnsureTargetMarksGroupDefaults(group)
    end
end

function PRT:EnsureTargetMarksDBDefaults()
    local db = self:GetDB()
    db.targetMarks = db.targetMarks or {}

    local tm = db.targetMarks
    if tm.enabled == nil then tm.enabled = false end
    tm.activePreset = tm.activePreset or ""
    tm.presets = tm.presets or {}
    tm.modifiers = tm.modifiers or {}

    if tm.modifiers.main == nil then tm.modifiers.main = "CTRL" end
    if tm.modifiers.alt1 == nil then tm.modifiers.alt1 = "ALT" end
    if tm.modifiers.alt2 == nil then tm.modifiers.alt2 = "SHIFT" end

    if #tm.presets == 0 then
        tm.presets[1] = self:CreateLegacyTargetMarksPreset()
        tm.defaultVersion = self.TARGET_MARKS_DEFAULT_VERSION
    elseif (tm.defaultVersion or 0) < self.TARGET_MARKS_DEFAULT_VERSION then
        for i, preset in ipairs(tm.presets) do
            if preset.name == "Default" then
                tm.presets[i] = self:CreateLegacyTargetMarksPreset()
                break
            end
        end
        tm.defaultVersion = self.TARGET_MARKS_DEFAULT_VERSION
    end

    for _, preset in ipairs(tm.presets) do
        self:EnsureTargetMarksPresetDefaults(preset)
    end

    if tm.activePreset == "" and tm.presets[1] then
        tm.activePreset = tm.presets[1].name
    end

    tm.modifiers.alt3 = nil
end

function PRT:InvalidateTargetMarksCache()
    self._targetMarksCache = nil
    self:ResetTargetMarksState()
end

function PRT:RebuildTargetMarksCache()
    local preset = self:GetActiveTargetMarksPreset()
    if not preset then
        self._targetMarksCache = nil
        return nil
    end

    local lookup = {}
    for _, slot in ipairs(self.TARGET_MARK_SLOTS) do
        lookup[slot] = {}
    end

    for _, group in ipairs(preset.groups) do
        for _, entry in ipairs(group.entries) do
            self:EnsureTargetMarksEntryDefaults(entry)
            if entry.npcId > 0 then
                for _, slot in ipairs(self.TARGET_MARK_SLOTS) do
                    local marks = entry.marks[slot]
                    if #marks > 0 then
                        local list = lookup[slot][entry.npcId] or {}
                        for _, markId in ipairs(marks) do
                            AppendMark(list, markId)
                        end
                        lookup[slot][entry.npcId] = list
                    end
                end
            end
        end
    end

    self._targetMarksCache = {
        presetName = preset.name,
        lookup = lookup,
    }
    return self._targetMarksCache
end

function PRT:GetTargetMarksLookup()
    local preset = self:GetActiveTargetMarksPreset()
    if not preset then return nil end
    if not self._targetMarksCache or self._targetMarksCache.presetName ~= preset.name then
        self:RebuildTargetMarksCache()
    end
    return self._targetMarksCache and self._targetMarksCache.lookup or nil
end

function PRT:ResetTargetMarksState()
    self._targetMarkState = {}
end

function PRT:GetActiveTargetMarkSlot()
    local db = self:GetDB()
    local tm = db.targetMarks or {}
    if not tm.enabled then return nil end

    local modifiers = tm.modifiers or {}
    for _, slot in ipairs(self.TARGET_MARK_SLOTS) do
        local key = modifiers[slot] or "NONE"
        if key ~= "NONE" and GetModifierDown(key) then
            return slot
        end
    end
    return nil
end

function PRT:HandleTargetMarksModifierChange()
    local slot = self:GetActiveTargetMarkSlot()
    if slot ~= self._targetMarkActiveSlot then
        self._targetMarkActiveSlot = slot
        self:ResetTargetMarksState()
    end
end

function PRT:TryTargetMarkMouseover()
    local db = self:GetDB()
    local tm = db.targetMarks or {}
    if not tm.enabled then return end

    local preset = self:GetActiveTargetMarksPreset()
    if not preset then return end

    local slot = self:GetActiveTargetMarkSlot()
    if not slot then return end

    if not IsInGroup() then return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
    if UnitIsPlayer("mouseover") then return end

    local guid = UnitGUID("mouseover")
    if not guid then return end

    self._targetMarkState = self._targetMarkState or {}
    if UnitAlreadyTracked(self._targetMarkState, guid) then
        return
    end

    local name = UnitName("mouseover") or ""
    local currentMark = GetRaidTargetIndex("mouseover")
    if currentMark and currentMark > 0 then
        SaveObservedMark(self._targetMarkState, guid, currentMark, name)
        return
    end

    local npcId = self.GetNpcId(guid)
    if not npcId then return end

    local lookup = self:GetTargetMarksLookup()
    local marks = lookup and lookup[slot] and lookup[slot][npcId]
    if not marks then return end

    local chosen
    for _, markId in ipairs(marks) do
        if markId > 0 and not self._targetMarkState[markId] then
            chosen = markId
            break
        end
    end

    if not chosen then return end

    SetRaidTarget("mouseover", chosen)
    SaveObservedMark(self._targetMarkState, guid, chosen, name)
end

function PRT:InitTargetMarks()
    self:EnsureTargetMarksDBDefaults()
    self:InvalidateTargetMarksCache()
    self:ResetTargetMarksState()

    if self._targetMarksFrame then return end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("MODIFIER_STATE_CHANGED")
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            PRT:ResetTargetMarksState()
            PRT:HandleTargetMarksModifierChange()
        elseif event == "MODIFIER_STATE_CHANGED" then
            PRT:HandleTargetMarksModifierChange()
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            PRT:TryTargetMarkMouseover()
        end
    end)

    self._targetMarksFrame = f
end

function PRT:ExportTargetMarksGroup(group)
    if not group then return "" end
    self:EnsureTargetMarksGroupDefaults(group)

    local lines = {}
    lines[#lines + 1] = "[TargetMarksGroup: " .. SanitizeExportValue(group.name or "Group") .. "]"

    for _, entry in ipairs(group.entries) do
        self:EnsureTargetMarksEntryDefaults(entry)
        lines[#lines + 1] = "[TargetMark]"
        lines[#lines + 1] = "npcId=" .. tostring(entry.npcId or 0)
        lines[#lines + 1] = "targetName=" .. SanitizeExportValue(entry.targetName or "")
        lines[#lines + 1] = "mainMarks=" .. SerializeMarkList(entry.marks.main)
        lines[#lines + 1] = "alt1Marks=" .. SerializeMarkList(entry.marks.alt1)
        lines[#lines + 1] = "alt2Marks=" .. SerializeMarkList(entry.marks.alt2)
    end

    return table.concat(lines, "\n")
end

function PRT:ExportTargetMarksPreset(preset)
    if not preset then return "" end
    self:EnsureTargetMarksPresetDefaults(preset)

    local lines = {}
    lines[#lines + 1] = "[TargetMarksPreset: " .. SanitizeExportValue(preset.name or "Preset") .. "]"
    for _, group in ipairs(preset.groups) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = self:ExportTargetMarksGroup(group)
    end

    return table.concat(lines, "\n")
end

function PRT:ParseTargetMarksGroupBlocks(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)
    if raw == "" then return {} end

    local groups = {}
    local currentGroup = nil
    local currentEntry = nil

    for line in raw:gmatch("[^\n]+") do
        line = PRT.Trim(line)
        if line ~= "" then
            local groupName = line:match("^%[TargetMarksGroup:%s*(.-)%]$")
            if groupName then
                FinalizeGroupImport(groups, currentGroup, currentEntry)
                currentGroup = {
                    name = PRT.Trim(groupName),
                    entries = {},
                }
                currentEntry = nil
            elseif line:match("^%[TargetMarksPreset:%s*.-%]$") then
                -- Preset header is handled by ParseTargetMarksPresetString.
            elseif line == "[TargetMark]" then
                if not currentGroup then
                    currentGroup = {
                        name = "Imported Group",
                        entries = {},
                    }
                end
                if currentEntry then
                    currentGroup.entries[#currentGroup.entries + 1] = currentEntry
                end
                currentEntry = self:CreateTargetMarksEntry(0, "")
            else
                local key, value = line:match("^(%w+)=(.*)$")
                if key and currentEntry then
                    if key == "npcId" then
                        currentEntry.npcId = tonumber(value) or 0
                    elseif key == "targetName" then
                        currentEntry.targetName = value
                    elseif key == "mainMarks" then
                        currentEntry.marks.main = ParseMarkList(value)
                    elseif key == "alt1Marks" or key == "altMarks1" then
                        currentEntry.marks.alt1 = ParseMarkList(value)
                    elseif key == "alt2Marks" or key == "altMarks2" then
                        currentEntry.marks.alt2 = ParseMarkList(value)
                    elseif key == "mainMark" then
                        AppendMark(currentEntry.marks.main, value)
                    elseif key == "altMark1" then
                        AppendMark(currentEntry.marks.alt1, value)
                    elseif key == "altMark2" then
                        AppendMark(currentEntry.marks.alt2, value)
                    end
                end
            end
        end
    end

    FinalizeGroupImport(groups, currentGroup, currentEntry)

    for _, group in ipairs(groups) do
        self:EnsureTargetMarksGroupDefaults(group)
    end
    return groups
end

function PRT:ParseTargetMarksPresetString(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    raw = PRT.Trim(raw)
    if raw == "" then return nil end

    local presetName = raw:match("^%[TargetMarksPreset:%s*(.-)%]")
    if not presetName then return nil end

    local groups = self:ParseTargetMarksGroupBlocks(raw)
    local preset = {
        name = PRT.Trim(presetName),
        groups = groups,
    }
    self:EnsureTargetMarksPresetDefaults(preset)
    return preset
end
