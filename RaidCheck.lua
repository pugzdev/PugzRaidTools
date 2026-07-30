---------------------------------------------------------------------------
-- PugzRaidTools - Raid Check Engine
-- Classic Era roster scanning, ready-check state, chat reports, and
-- durability exchange. UI construction lives in UI/RaidCheck*.lua.
---------------------------------------------------------------------------
local addonName, PRT = ...

local ADDON_PREFIX = "PRTRaidCheck"
local MAX_AURAS = 60
local DURABILITY_CACHE_SECONDS = 120
local DEFAULT_READY_CHECK_DURATION = 35
local RAID_CHECK_ICON_WIDTH = 17
local RAID_CHECK_ICON_COLUMN_WIDTH = 28
local RAID_CHECK_COUNT_WIDTH = 15
local RAID_CHECK_MAX_CATEGORY_ICONS = 6

local raidCheckMemoryDebug = {
    enabled = false,
    counters = {},
    baseline = nil,
}

local function CountRaidCheckDebug(key, amount)
    if not raidCheckMemoryDebug.enabled then return end
    local counters = raidCheckMemoryDebug.counters
    counters[key] = (counters[key] or 0) + (amount or 1)
end

local function ReadRaidCheckLuaHeapKB(forceGC)
    if type(collectgarbage) ~= "function" then return nil end
    if forceGC then pcall(collectgarbage, "collect") end
    local ok, value = pcall(collectgarbage, "count")
    return ok and tonumber(value) or nil
end

local function ReadRaidCheckAddonMemoryKB()
    if type(UpdateAddOnMemoryUsage) == "function" then
        UpdateAddOnMemoryUsage()
    end
    if type(GetAddOnMemoryUsage) ~= "function" then return nil end
    return tonumber(GetAddOnMemoryUsage(addonName or "PugzRaidTools"))
end

local function CaptureRaidCheckMemory(forceGC)
    local luaHeapKB = ReadRaidCheckLuaHeapKB(forceGC)
    return {
        addonKB = ReadRaidCheckAddonMemoryKB(),
        luaHeapKB = luaHeapKB,
    }
end

function PRT:IsRaidCheckMemoryDebugEnabled()
    return raidCheckMemoryDebug.enabled
end

function PRT:CountRaidCheckDebug(key, amount)
    CountRaidCheckDebug(key, amount)
end

function PRT:GetRaidCheckMemoryDebugCounters()
    return raidCheckMemoryDebug.counters
end

function PRT:SetRaidCheckMemoryDebug(enabled)
    enabled = enabled and true or false
    if enabled then
        raidCheckMemoryDebug.enabled = true
        raidCheckMemoryDebug.counters = {}
        raidCheckMemoryDebug.baseline = CaptureRaidCheckMemory(false)
        PRT.Print(
            "Raid Check memory debug enabled. Run Test Preview, close it, "
            .. "then use /prt debugui raid [gc].")
        return
    end

    if raidCheckMemoryDebug.enabled then
        self:DumpRaidCheckMemoryDebug(false, "final")
    end
    raidCheckMemoryDebug.enabled = false
    raidCheckMemoryDebug.baseline = nil
    PRT.Print("Raid Check memory debug disabled.")
end

function PRT:DumpRaidCheckMemoryDebug(forceGC, label)
    local snapshot = CaptureRaidCheckMemory(forceGC)
    local baseline = raidCheckMemoryDebug.baseline or snapshot
    local addonDelta = snapshot.addonKB and baseline.addonKB
        and snapshot.addonKB - baseline.addonKB or nil
    local luaDelta = snapshot.luaHeapKB and baseline.luaHeapKB
        and snapshot.luaHeapKB - baseline.luaHeapKB or nil
    local counters = raidCheckMemoryDebug.counters

    PRT.Print(("RAID CHECK MEMORY %s%s addon=%s delta=%s "
        .. "luaHeap(all addons)=%s delta=%s"):format(
        tostring(label or "snapshot"),
        forceGC and " after-GC" or "",
        snapshot.addonKB
            and ("%.1fKB"):format(snapshot.addonKB) or "unavailable",
        addonDelta and ("%+.1fKB"):format(addonDelta) or "unavailable",
        snapshot.luaHeapKB
            and ("%.1fKB"):format(snapshot.luaHeapKB) or "unavailable",
        luaDelta and ("%+.1fKB"):format(luaDelta) or "unavailable"))
    PRT.Print(("previews=%d members=%d auras=%d refreshes=%d "
        .. "rowUpdates=%d cellUpdates=%d tooltipBuilds=%d"):format(
        counters.testSnapshotsBuilt or 0,
        counters.previewMembersBuilt or 0,
        counters.previewAurasBuilt or 0,
        counters.windowRefreshes or 0,
        counters.rowUpdates or 0,
        counters.cellUpdates or 0,
        counters.tooltipBuilds or 0))
    PRT.Print(("created while tracing windows=%d headers=%d rows=%d "
        .. "cells=%d texts=%d overlays=%d iconSlots=%d glows=%d "
        .. "iconHits=%d miniMembers=%d")
        :format(
            counters.windowsCreated or 0,
            counters.headerCellsCreated or 0,
            counters.rowsCreated or 0,
            counters.resultCellsCreated or 0,
            counters.cellTextsCreated or 0,
            counters.overlaysCreated or 0,
            counters.iconSlotsCreated or 0,
            counters.iconGlowsCreated or 0,
            counters.iconHitsCreated or 0,
            counters.miniMembersCreated or 0))
    PRT.Print(("shared tooltipTargets=%d bindingsReleased=%d"):format(
        counters.tooltipTargetsAttached or 0,
        counters.windowBindingsReleased or 0))

    local popup = self.raidCheckWindow
    if popup and popup.GetRaidCheckDebugSummary then
        local summary = popup:GetRaidCheckDebugSummary()
        PRT.Print(("current shown=%s previewRetained=%s snapshotRetained=%s "
            .. "members=%d columns=%d headers=%d rows=%d cells=%d "
            .. "texts=%d overlays=%d iconSlots=%d glows=%d "
            .. "iconHits=%d miniMembers=%d")
            :format(
                tostring(summary.shown),
                tostring(summary.previewRetained),
                tostring(summary.snapshotRetained),
                summary.members or 0,
                summary.columns or 0,
                summary.headers or 0,
                summary.rows or 0,
                summary.cells or 0,
                summary.texts or 0,
                summary.overlays or 0,
                summary.iconSlots or 0,
                summary.iconGlows or 0,
                summary.iconHits or 0,
                summary.miniMembers or 0))
    end
end

local function ResolveSpellIcon(spellId, fallback)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellId)
    elseif GetSpellTexture then
        icon = GetSpellTexture(spellId)
    end
    return icon or fallback
end

local FOOD_AURAS = {
    [18125] = true, [18141] = true, [18192] = true, [18194] = true,
    [18222] = true, [22730] = true, [22789] = true, [22790] = true,
    [24799] = true, [25661] = true, [25804] = true,
}

-- Only the four persistent raid flasks are shown in the Flask column.
local FLASK_AURAS = {
    [17626] = true, -- Flask of the Titans
    [17627] = true, -- Flask of Distilled Wisdom
    [17628] = true, -- Flask of Supreme Power
    [17629] = true, -- Flask of Chromatic Resistance
}

-- Petrification is recorded separately for the future Raid Report subsystem.
-- It deliberately does not satisfy or appear in the live Raid Check.
local PETRIFICATION_AURAS = {
    [17624] = true,
}

-- Zanza-category effects are mutually exclusive: a player can have only one
-- of these active at a time. itemId overrides intentionally use the source
-- item's icon where the spell aura icon is not the desired display icon.
local ZANZA_AURA_DEFINITIONS = {
    { spellId = 10668, name = "Spirit of Boar", itemId = 8411 },
    { spellId = 10669, name = "Strike of the Scorpok", itemId = 8412 },
    { spellId = 10693, name = "Spiritual Domination", itemId = 8424 },
    { spellId = 10667, name = "Rage of Ages", itemId = 8410 },
    { spellId = 10692, name = "Infallible Mind", itemId = 8423 },
    -- City friendship gifts: Darnassus/Orgrimmar grant 30 Agility.
    { spellId = 27666, name = "Darnassus Gift of Friendship" },
    { spellId = 27669, name = "Orgrimmar Gift of Friendship" },
    -- Ironforge/Thunder Bluff grant 30 Stamina.
    { spellId = 27665, name = "Ironforge Gift of Friendship" },
    { spellId = 27670, name = "Thunder Bluff Gift of Friendship" },
    -- Stormwind/Undercity grant 30 Intellect.
    { spellId = 27664, name = "Stormwind Gift of Friendship" },
    { spellId = 27671, name = "Undercity Gift of Friendship" },
    { spellId = 24382, name = "Spirit of Zanza" },
    { spellId = 24383, name = "Swiftness of Zanza" },
    { spellId = 24417, name = "Sheen of Zanza" },
}

-- Multiple Consumes can be active together. Array order is display priority.
local CONSUME_AURA_DEFINITIONS = {
    { spellId = 17538, name = "Elixir of the Mongoose" },
    { spellId = 11371, name = "Gift of Arthas", itemId = 9088 },
    { spellId = 16323, name = "Juju Power" },
    { spellId = 16329, name = "Juju Might" },
    { spellId = 17038, name = "Winterfall Firewater" },
    { spellId = 11348, name = "Elixir of Superior Defense" },
    { spellId = 26276, name = "Elixir of Greater Firepower" },
    { spellId = 17539, name = "Greater Arcane Elixir" },
    { spellId = 24363, name = "Mageblood Potion" },
    { spellId = 3593, name = "Elixir of Fortitude" },
    { spellId = 16325, name = "Juju Chill" },
    { spellId = 16326, name = "Juju Ember" },
    -- Bogling Root deliberately uses the item 5206 texture rather than its
    -- aura texture so the Raid Check matches the consumed item.
    { spellId = 5665, name = "Bogling Root", itemId = 5206 },
    { spellId = 11334, name = "Greater Agility" },
}

-- Normal Zanza and Consume rows use the texture resolved from their exact
-- aura spell. ApplyAuraDefinition still gives an explicit itemId precedence,
-- preserving the requested item-icon exceptions (for example Gift of Arthas,
-- Bogling Root, and the five original Blasted Lands buffs).
for _, definitions in ipairs({
        ZANZA_AURA_DEFINITIONS,
        CONSUME_AURA_DEFINITIONS,
    }) do
    for _, definition in ipairs(definitions) do
        definition.icon = ResolveSpellIcon(
            definition.spellId,
            definition.icon)
    end
end

-- Multiple protection Potions can be active together. Array order is display
-- priority, with Frozen Rune intentionally last.
local POTION_AURA_DEFINITIONS = {
    {
        spellId = 17544,
        name = "Greater Frost Protection Potion",
        itemId = 13456,
    },
    {
        spellId = 17548,
        name = "Greater Shadow Protection Potion",
        itemId = 13459,
    },
    {
        spellId = 17546,
        name = "Greater Nature Protection Potion",
        itemId = 13458,
    },
    {
        spellId = 17543,
        name = "Greater Fire Protection Potion",
        itemId = 13457,
    },
    {
        spellId = 17549,
        name = "Greater Arcane Protection Potion",
        itemId = 13461,
    },
    { spellId = 29432, name = "Frozen Rune", itemId = 22682 },
}

-- Disallowed effects use a red glow whenever detected. The column defaults to
-- "Show if detected" so it does not consume space in clean raids.
local DISALLOWED_AURA_DEFINITIONS = {
    {
        spellId = 29534,
        name = "Traces of Silithyst",
        icon = ResolveSpellIcon(29534, 135834),
    },
    -- Alterac Valley fire-buff effect; any detection should be clearly
    -- surfaced because it invalidates the expected raid-log preparation.
    {
        spellId = 18968,
        name = "AV Fire Shield",
        icon = ResolveSpellIcon(18968),
    },
    -- Soul Revival is likewise retained as a Logs! warning aura rather than
    -- being treated as a valid raid preparation effect.
    {
        spellId = 28681,
        name = "Soul Revival",
        icon = ResolveSpellIcon(28681),
    },
}

local CHRONOBOON_ICON = ResolveSpellIcon(349981, 133741)

-- World-buff auras in display-priority order. Most entries are active buffs.
-- Supercharged Chronoboon is the special container aura applied while stored
-- world buffs have their durations frozen; it is displayed but is not counted
-- for any class by default because it does not identify the buffs inside it.
local WORLD_BUFF_DEFINITIONS = {
    -- All class-valid Sayge fortunes take display precedence over every
    -- other active world buff. Their relative order remains deterministic.
    -- A player can only have one Dark Fortune at a time; previewExclusiveGroup
    -- preserves that real-game rule in generated test rosters.
    {
        spellId = 23768,
        name = "Sayge's Dark Fortune of Damage",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23769,
        name = "Sayge's Dark Fortune of Resistance",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23737,
        name = "Sayge's Dark Fortune of Stamina",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23766,
        name = "Sayge's Dark Fortune of Intelligence",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23736,
        name = "Sayge's Dark Fortune of Agility",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23738,
        name = "Sayge's Dark Fortune of Spirit",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23735,
        name = "Sayge's Dark Fortune of Strength",
        previewExclusiveGroup = "sayge",
    },
    {
        spellId = 23767,
        name = "Sayge's Dark Fortune of Armor",
        previewExclusiveGroup = "sayge",
    },
    { spellId = 22888, name = "Rallying Cry of the Dragonslayer" },
    { spellId = 24425, name = "Spirit of Zandalar" },
    -- Preview-only realism rule: Warchief's Blessing and Might of Stormwind
    -- are mutually exclusive. The two Might IDs are also alternate IDs for
    -- the same effect and can never appear together.
    {
        spellId = 16609,
        name = "Warchief's Blessing",
        previewExclusiveGroup = "factionCityBuff",
    },
    {
        spellId = 460940,
        name = "Might of Stormwind",
        previewExclusiveGroup = "factionCityBuff",
    },
    {
        spellId = 460939,
        name = "Might of Stormwind",
        previewExclusiveGroup = "factionCityBuff",
    },
    { spellId = 15366, name = "Songflower Serenade" },
    { spellId = 22817, name = "Fengus' Ferocity" },
    { spellId = 22818, name = "Mol'dar's Moxie" },
    { spellId = 22820, name = "Slip'kik's Savvy" },
    {
        spellId = 349981,
        name = "Supercharged Chronoboon Displacer",
        icon = CHRONOBOON_ICON,
        isWorldBuffContainer = true,
    },
}

-- Resolve every row icon from its world-buff spell ID. This also ensures that
-- multiple displayed buffs use their own spell textures rather than sharing
-- the generic WBs column icon.
for _, definition in ipairs(WORLD_BUFF_DEFINITIONS) do
    definition.icon = ResolveSpellIcon(
        definition.spellId,
        definition.icon)
end

local function BuildAuraDefinitionMap(definitions)
    local result = {}
    for priority, definition in ipairs(definitions) do
        definition.priority = priority
        result[definition.spellId] = definition
    end
    return result
end

local ZANZA_AURAS = BuildAuraDefinitionMap(ZANZA_AURA_DEFINITIONS)
local CONSUME_AURAS = BuildAuraDefinitionMap(CONSUME_AURA_DEFINITIONS)
local POTION_AURAS = BuildAuraDefinitionMap(POTION_AURA_DEFINITIONS)
local DISALLOWED_AURAS = BuildAuraDefinitionMap(DISALLOWED_AURA_DEFINITIONS)
local WORLD_BUFF_AURAS = BuildAuraDefinitionMap(WORLD_BUFF_DEFINITIONS)

local function SpellSet(...)
    local set = {}
    for index = 1, select("#", ...) do
        set[select(index, ...)] = true
    end
    return set
end

-- Per-class defaults define which detected world buffs contribute to that
-- player's valid world-buff count. Unlisted detected buffs can still be shown
-- in the tooltip but do not increase the counted total.
local WORLD_BUFF_DEFAULTS = {
    WARRIOR = SpellSet(
        23768, 22888, 24425, 22817, 22818, 15366, 16609,
        460940, 460939),
    ROGUE = SpellSet(
        23768, 22888, 24425, 22817, 22818, 15366, 16609,
        460940, 460939),
    HUNTER = SpellSet(
        23768, 22888, 24425, 22820, 22817, 22818, 15366, 16609,
        460940, 460939, 23769, 23737),
    DRUID = SpellSet(
        23768, 22888, 24425, 22820, 22817, 22818, 15366, 16609,
        460940, 460939, 23769),
    MAGE = SpellSet(
        23768, 22888, 24425, 22820, 22818, 15366, 16609,
        460940, 460939),
    WARLOCK = SpellSet(
        23768, 22888, 24425, 22820, 22818, 15366, 16609,
        460940, 460939),
    PALADIN = SpellSet(
        23768, 22888, 24425, 22820, 22817, 22818, 15366, 16609,
        460940, 460939, 23769, 23766),
    PRIEST = SpellSet(
        23768, 22888, 24425, 22820, 22818, 15366, 16609,
        460940, 460939, 23769, 23737, 23766, 23738),
    SHAMAN = SpellSet(
        23768, 22888, 24425, 22820, 22817, 22818, 15366, 16609,
        460940, 460939, 23769, 23766),
}

local WORLD_BUFF_CLASSES = {
    { classFile = "WARRIOR", label = "Warrior" },
    { classFile = "ROGUE", label = "Rogue" },
    { classFile = "HUNTER", label = "Hunter" },
    { classFile = "DRUID", label = "Druid" },
    { classFile = "MAGE", label = "Mage" },
    { classFile = "WARLOCK", label = "Warlock" },
    { classFile = "PALADIN", label = "Paladin" },
    { classFile = "PRIEST", label = "Priest" },
    { classFile = "SHAMAN", label = "Shaman" },
}

local WORLD_BUFF_DEFAULTS_VERSION = 2

local function MigrateWorldBuffValidityDefaults(cfg)
    if tonumber(cfg.worldBuffDefaultsVersion) == WORLD_BUFF_DEFAULTS_VERSION then
        return
    end
    -- Version 2 makes both Might of Stormwind aura IDs valid for every class.
    -- Older configuration tables stored every default as an explicit value,
    -- so clear these two generated entries to inherit the new defaults.
    for classFile, saved in pairs(cfg.worldBuffValidity or {}) do
        if type(saved) == "table" then
            saved[460940] = nil
            saved[460939] = nil
            if not next(saved) then
                cfg.worldBuffValidity[classFile] = nil
            end
        end
    end
    cfg.worldBuffDefaultsVersion = WORLD_BUFF_DEFAULTS_VERSION
end

local BASE_BUFFS = {
    {
        key = "druid",
        label = "Mark / Gift of the Wild",
        shortLabel = "GotW",
        icon = 136078,
        spells = {
            [1126] = 1, [5232] = 2, [6756] = 3, [5234] = 4,
            [8907] = 5, [9884] = 6, [9885] = 7,
            [21849] = 6, [21850] = 7,
        },
    },
    {
        key = "intellect",
        label = "Arcane Intellect / Brilliance",
        shortLabel = "Int",
        icon = 135932,
        spells = {
            [1459] = 1, [1460] = 2, [1461] = 3,
            [10156] = 4, [10157] = 5, [23028] = 5,
        },
    },
    {
        key = "attackPower",
        label = "Diamond Flask Battle Shout",
        shortLabel = "DF BS",
        icon = 132333,
        -- This column intentionally detects only the requested DF Battle
        -- Shout aura; ordinary ranked Battle Shout auras do not satisfy it.
        spells = { [25101] = 1 },
    },
    {
        key = "spirit",
        label = "Divine Spirit / Prayer of Spirit",
        shortLabel = "Spirit",
        icon = 135946,
        spells = {
            [14752] = 1, [14818] = 2, [14819] = 3,
            [27681] = 4, [27841] = 4,
        },
    },
    {
        key = "armor",
        label = "Inner Fire",
        shortLabel = "Armor",
        icon = 135926,
        defaultEnabled = false,
        spells = {
            [588] = 1, [7128] = 2, [602] = 3, [1006] = 4,
            [10951] = 5, [10952] = 6,
        },
    },
    {
        key = "shadow",
        label = "Shadow Protection",
        shortLabel = "Shadow",
        icon = 136121,
        spells = {
            [976] = 1, [10957] = 2, [10958] = 3,
            [27683] = 3,
        },
    },
    {
        key = "stamina",
        label = "Power Word: Fortitude",
        shortLabel = "Stam",
        icon = 135987,
        spells = {
            [1243] = 1, [1244] = 2, [1245] = 3,
            [2791] = 4, [10937] = 5, [10938] = 6,
            [21562] = 5, [21564] = 6,
        },
    },
}

local SALVATION_ICON = ResolveSpellIcon(25895)
local LIGHT_ICON = ResolveSpellIcon(25890)

local ALLIANCE_BUFFS = {
    {
        key = "might",
        label = "Blessing of Might",
        shortLabel = "BoM",
        icon = 135908,
        paladinBlessing = true,
        spells = {
            [19740] = 1, [19834] = 2, [19835] = 3,
            [19836] = 4, [19837] = 5, [19838] = 6,
            [25291] = 7, [25782] = 6, [25916] = 7,
        },
    },
    {
        key = "wisdom",
        label = "Blessing of Wisdom",
        shortLabel = "BoW",
        icon = 135970,
        paladinBlessing = true,
        spells = {
            [19742] = 1, [19850] = 2, [19852] = 3,
            [19853] = 4, [19854] = 5, [25290] = 6,
            [25894] = 5, [25918] = 6,
        },
    },
    {
        key = "kings",
        label = "Blessing of Kings",
        shortLabel = "BoK",
        icon = 135993,
        paladinBlessing = true,
        spells = { [20217] = 1, [25898] = 1 },
    },
    {
        key = "salvation",
        label = "Blessing of Salvation",
        shortLabel = "BoS",
        icon = SALVATION_ICON,
        iconOverride = SALVATION_ICON,
        paladinBlessing = true,
        -- Both the greater and single-target auras satisfy Salvation. The
        -- greater aura icon is used for either result to keep the column
        -- visually consistent.
        spells = { [1038] = 1, [25895] = 1 },
    },
    {
        key = "light",
        label = "Blessing of Light",
        shortLabel = "BoL",
        icon = LIGHT_ICON,
        iconOverride = LIGHT_ICON,
        paladinBlessing = true,
        -- Greater Blessing of Light and rank 3 are valid max-rank results.
        -- Ranks 1 and 2 remain present but receive the normal low-rank glow.
        spells = {
            [19977] = 1,
            [19978] = 2,
            [19979] = 3,
            [25890] = 3,
        },
    },
}

local CORE_COLUMNS = {
    {
        key = "worldBuffs",
        label = "World Buffs",
        shortLabel = "WBs",
        icon = 134153,
        configKey = "checkWorldBuffs",
        multiAura = true,
        defaultMaxDisplay = 4,
        maxDisplayLimit = 7,
        defaultShowCount = true,
        defaultAlignment = "LEFT",
    },
    {
        key = "food",
        label = "Food",
        shortLabel = "Food",
        icon = 136000,
        configKey = "checkFood",
        defaultEnabled = false,
        width = RAID_CHECK_ICON_COLUMN_WIDTH,
    },
    {
        key = "flask",
        label = "Flask",
        shortLabel = "Flask",
        icon = 134842,
        configKey = "checkFlask",
        width = RAID_CHECK_ICON_COLUMN_WIDTH,
    },
    {
        key = "zanza",
        label = "Zanza",
        shortLabel = "Zanza",
        icon = 134810,
        configKey = "checkZanza",
        multiAura = true,
        defaultMaxDisplay = 1,
        defaultShowCount = false,
        supportsCount = false,
    },
    {
        key = "consumes",
        label = "Consumes",
        shortLabel = "Consumes",
        icon = 134812,
        configKey = "checkConsumes",
        multiAura = true,
        defaultMaxDisplay = 3,
        defaultShowCount = false,
    },
    {
        key = "potions",
        label = "Potions",
        shortLabel = "Potions",
        icon = 134800,
        configKey = "checkPotions",
        multiAura = true,
        defaultMaxDisplay = 3,
        defaultShowCount = false,
    },
    {
        key = "disallowed",
        label = "Logs!",
        shortLabel = "Logs!",
        icon = DISALLOWED_AURA_DEFINITIONS[1].icon,
        configKey = "checkDisallowed",
        multiAura = true,
        defaultMaxDisplay = 1,
        defaultShowCount = false,
        defaultVisibility = "detected",
        alwaysGlow = true,
    },
}

local DURABILITY_COLUMN = {
    key = "durability",
    label = "Durability",
    shortLabel = "Dur",
    icon = 136241,
    configKey = "checkDurability",
    width = 38,
}

local PREVIEW_NAMES = {
    "Krobian", "Udwarrior", "Ezi", "Drstwo", "Straik", "Maasaki",
    "Littlechurch", "Fréakazoide", "Pugzz", "Lilbootay", "Tusqaix",
    "Wstn", "Sniffx", "Cidibaa", "Driev", "Mueslii", "Coltyy",
    "Freegoo", "Salvxdali", "Panzèrx", "Aluvena", "Sosa", "Dunkix",
    "Smokess", "Sertoh", "Skalina", "Preyqq", "Daiku", "Zurzur",
    "Clickerxx", "Shadowelitz", "Malepalax", "Benevolent", "Prestelul",
    "Scrimslave", "Bokkpriest", "Zixes", "Minicutie", "Jeezppc",
    "Calimay",
}

local PREVIEW_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local RAID_CHECK_CLASS_ORDER = {
    WARRIOR = 1,
    ROGUE = 2,
    HUNTER = 3,
    MAGE = 4,
    WARLOCK = 5,
    DRUID = 6,
    PALADIN = 7,
    PRIEST = 8,
    SHAMAN = 9,
}

local function Now()
    return GetTime and GetTime() or 0
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret
        and C_Secrets.ShouldAurasBeSecret()
end

local function GetAuraData(unit, index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
    end
    if not UnitAura then return nil end

    local name, icon, applications, dispelName, duration, expirationTime,
        sourceUnit, isStealable, nameplateShowPersonal, spellId =
        UnitAura(unit, index, "HELPFUL")
    if not name then return nil end
    return {
        name = name,
        icon = icon,
        applications = applications,
        dispelName = dispelName,
        duration = duration,
        expirationTime = expirationTime,
        sourceUnit = sourceUnit,
        isStealable = isStealable,
        nameplateShowPersonal = nameplateShowPersonal,
        spellId = spellId,
    }
end

local function GetConfiguredItemIcon(itemId)
    if not itemId then return nil end
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemId)
    end
    local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
        or GetItemInfoInstant
    if getItemInfoInstant then
        local _, _, _, _, icon = getItemInfoInstant(itemId)
        return icon
    end
end

local function ApplyAuraDefinition(aura, definition)
    if not aura or not definition then return aura end
    aura.raidCheckPriority = definition.priority or 999
    aura.raidCheckDefinitionName = definition.name
    aura.raidCheckItemId = definition.itemId
    aura.raidCheckWorldBuffContainer =
        definition.isWorldBuffContainer == true
    aura.raidCheckDisplayIcon =
        GetConfiguredItemIcon(definition.itemId)
        or ResolveSpellIcon(definition.spellId, definition.icon)
        or aura.icon
    return aura
end

local function SortAuraList(auras)
    table.sort(auras, function(left, right)
        local leftPriority = tonumber(left.raidCheckPriority) or 999
        local rightPriority = tonumber(right.raidCheckPriority) or 999
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        return (tonumber(left.spellId) or 0) < (tonumber(right.spellId) or 0)
    end)
end

local function SortWorldBuffList(auras)
    table.sort(auras, function(left, right)
        local leftCounted = left.raidCheckCounted == true
        local rightCounted = right.raidCheckCounted == true
        if leftCounted ~= rightCounted then return leftCounted end
        local leftPriority = tonumber(left.raidCheckPriority) or 999
        local rightPriority = tonumber(right.raidCheckPriority) or 999
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        return (tonumber(left.spellId) or 0)
            < (tonumber(right.spellId) or 0)
    end)
end

local function CopyBuffDefinitions(destination, source)
    for _, definition in ipairs(source) do
        if not definition.maxRank then
            local maximum = 1
            for _, rank in pairs(definition.spells) do
                maximum = math.max(maximum, tonumber(rank) or 1)
            end
            definition.maxRank = maximum
        end
        destination[#destination + 1] = definition
    end
end

local raidCheckBuffDefinitions

function PRT:GetRaidCheckBuffDefinitions()
    if raidCheckBuffDefinitions then return raidCheckBuffDefinitions end
    local definitions = {}
    CopyBuffDefinitions(definitions, BASE_BUFFS)
    -- Keep the catalog stable on both factions. Visibility of the five
    -- Paladin Blessing columns is handled by the user's faction toggle.
    CopyBuffDefinitions(definitions, ALLIANCE_BUFFS)
    raidCheckBuffDefinitions = definitions
    return raidCheckBuffDefinitions
end

function PRT:GetRaidCheckWorldBuffDefinitions()
    return WORLD_BUFF_DEFINITIONS
end

function PRT:GetRaidCheckWorldBuffClasses()
    return WORLD_BUFF_CLASSES
end

local function RefreshSnapshotWorldBuffValidity(owner, snapshot)
    for _, member in ipairs(snapshot and snapshot.members or {}) do
        member.countedWorldBuffs = {}
        for _, aura in ipairs(member.worldBuffs or {}) do
            aura.raidCheckCounted = owner:IsRaidCheckWorldBuffCounted(
                member.classFile, aura.spellId)
            if aura.raidCheckCounted then
                member.countedWorldBuffs[
                    #member.countedWorldBuffs + 1] = aura
            end
        end
        SortWorldBuffList(member.worldBuffs)
        SortAuraList(member.countedWorldBuffs)
    end
end

function PRT:IsRaidCheckWorldBuffCounted(classFile, spellId)
    spellId = tonumber(spellId)
    local cfg = self:GetDB().raidCheck or {}
    MigrateWorldBuffValidityDefaults(cfg)
    local saved = cfg.worldBuffValidity
        and cfg.worldBuffValidity[classFile] or nil
    if saved and saved[spellId] ~= nil then
        return saved[spellId] == true
    end
    local defaults = WORLD_BUFF_DEFAULTS[classFile]
    if not defaults then return true end
    return defaults[spellId] == true
end

function PRT:SetRaidCheckWorldBuffCounted(classFile, spellId, counted)
    if not WORLD_BUFF_DEFAULTS[classFile] then return false end
    spellId = tonumber(spellId)
    if not WORLD_BUFF_AURAS[spellId] then return false end
    local cfg = self:GetDB().raidCheck
    cfg.worldBuffValidity = cfg.worldBuffValidity or {}
    MigrateWorldBuffValidityDefaults(cfg)
    local saved = cfg.worldBuffValidity[classFile]
    if type(saved) ~= "table" then
        saved = {}
        cfg.worldBuffValidity[classFile] = saved
    end
    local value = counted and true or false
    local defaultValue =
        WORLD_BUFF_DEFAULTS[classFile][spellId] == true
    saved[spellId] = value ~= defaultValue and value or nil
    if not next(saved) then
        cfg.worldBuffValidity[classFile] = nil
    end
    if self.raidCheckWindow and self.raidCheckWindow._previewSnapshot then
        RefreshSnapshotWorldBuffValidity(
            self, self.raidCheckWindow._previewSnapshot)
    end
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:ResetRaidCheckWorldBuffDefaults(classFile)
    local cfg = self:GetDB().raidCheck
    if cfg.worldBuffValidity then
        cfg.worldBuffValidity[classFile] = nil
    end
    if self.raidCheckWindow and self.raidCheckWindow._previewSnapshot then
        RefreshSnapshotWorldBuffValidity(
            self, self.raidCheckWindow._previewSnapshot)
    end
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
end

function PRT:GetRaidCheckAuraCategoryDefinitions(categoryKey)
    if categoryKey == "worldBuffs" then return WORLD_BUFF_DEFINITIONS end
    if categoryKey == "zanza" then return ZANZA_AURA_DEFINITIONS end
    if categoryKey == "consumes" then return CONSUME_AURA_DEFINITIONS end
    if categoryKey == "potions" then return POTION_AURA_DEFINITIONS end
    if categoryKey == "disallowed" then
        return DISALLOWED_AURA_DEFINITIONS
    end
    return {}
end

local raidCheckColumnCatalog

function PRT:GetRaidCheckColumnCatalog()
    if raidCheckColumnCatalog then return raidCheckColumnCatalog end
    local catalog = {}
    for _, column in ipairs(CORE_COLUMNS) do
        catalog[#catalog + 1] = column
    end
    for _, definition in ipairs(self:GetRaidCheckBuffDefinitions()) do
        catalog[#catalog + 1] = {
            key = definition.key,
            label = definition.label,
            shortLabel = definition.shortLabel,
            icon = definition.icon,
            configKey = "checkBuffs",
            buffKey = definition.key,
            paladinBlessing = definition.paladinBlessing == true,
            defaultEnabled = definition.defaultEnabled,
            width = RAID_CHECK_ICON_COLUMN_WIDTH,
        }
    end
    catalog[#catalog + 1] = DURABILITY_COLUMN
    raidCheckColumnCatalog = catalog
    return raidCheckColumnCatalog
end

local function FindColumnByKey(catalog, columnKey)
    for _, column in ipairs(catalog) do
        if column.key == columnKey then return column end
    end
end

function PRT:GetRaidCheckColumnSetting(columnOrKey)
    local column = type(columnOrKey) == "table" and columnOrKey
        or FindColumnByKey(
            self:GetRaidCheckColumnCatalog(),
            columnOrKey == "potion" and "consumes" or columnOrKey)
    if not column then return nil end

    local cfg = self:GetDB().raidCheck
    cfg.columnSettings = cfg.columnSettings or {}
    if column.key == "consumes"
        and not cfg.columnSettings.consumes
        and cfg.columnSettings.potion then
        cfg.columnSettings.consumes = cfg.columnSettings.potion
        cfg.columnSettings.potion = nil
    end
    local setting = cfg.columnSettings[column.key]
    if type(setting) ~= "table" then
        setting = {}
        cfg.columnSettings[column.key] = setting
    end

    if setting.enabled == nil then
        local legacyValue = cfg[column.configKey]
        if column.key == "consumes"
            and cfg.checkPotion ~= nil then
            legacyValue = cfg.checkPotion
            cfg.checkPotion = nil
        end
        if column.defaultEnabled ~= nil then
            setting.enabled = column.defaultEnabled == true
        else
            setting.enabled = legacyValue ~= false
        end
    end
    if column.supportsCount == false then
        setting.showCount = false
    elseif setting.showCount == nil then
        setting.showCount = column.defaultShowCount == true
    end
    local maxDisplayLimit = math.max(
        1,
        tonumber(column.maxDisplayLimit)
            or RAID_CHECK_MAX_CATEGORY_ICONS)
    setting.maxDisplay = math.max(1, math.min(
        maxDisplayLimit,
        tonumber(setting.maxDisplay)
            or tonumber(column.defaultMaxDisplay)
            or 1))
    if setting.visibility == nil then
        setting.visibility = column.defaultVisibility or "always"
    end
    if setting.alignment == nil then
        setting.alignment = column.defaultAlignment or "CENTER"
    elseif setting.alignment ~= "LEFT"
        and setting.alignment ~= "RIGHT" then
        setting.alignment = "CENTER"
    end
    if column.key == "worldBuffs" then
        if setting.uncountedMode ~= "show"
            and setting.uncountedMode ~= "hide" then
            setting.uncountedMode = "fade"
        end
    end
    return setting
end

function PRT:IsRaidCheckColumnEnabled(column)
    if not column then return false end
    local setting = self:GetRaidCheckColumnSetting(column)
    if not setting or setting.enabled == false then return false end
    if column.paladinBlessing then
        local cfg = self:GetDB().raidCheck or {}
        if cfg.allianceBlessingsOnly ~= false then
            return UnitFactionGroup
                and UnitFactionGroup("player") == "Alliance"
        end
    end
    return true
end

function PRT:SetRaidCheckColumnEnabled(columnKey, enabled)
    local setting = self:GetRaidCheckColumnSetting(columnKey)
    if not setting then return false end
    setting.enabled = enabled and true or false
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:SetRaidCheckColumnShowCount(columnKey, showCount)
    local column = FindColumnByKey(
        self:GetRaidCheckColumnCatalog(), columnKey)
    local setting = self:GetRaidCheckColumnSetting(column)
    if not column or not setting then return false end
    setting.showCount =
        column.supportsCount ~= false and showCount and true or false
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:SetRaidCheckColumnMaxDisplay(columnKey, maximum)
    local column = FindColumnByKey(
        self:GetRaidCheckColumnCatalog(), columnKey)
    local setting = self:GetRaidCheckColumnSetting(column)
    if not column or not setting then return false end
    local maxDisplayLimit = math.max(
        1,
        tonumber(column.maxDisplayLimit)
            or RAID_CHECK_MAX_CATEGORY_ICONS)
    setting.maxDisplay = math.max(
        1, math.min(maxDisplayLimit, tonumber(maximum) or 1))
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:SetRaidCheckColumnVisibility(columnKey, visibility)
    local setting = self:GetRaidCheckColumnSetting(columnKey)
    if not setting then return false end
    setting.visibility = visibility == "detected" and "detected" or "always"
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:SetRaidCheckColumnAlignment(columnKey, alignment)
    local setting = self:GetRaidCheckColumnSetting(columnKey)
    if not setting then return false end
    if alignment == "LEFT" or alignment == "RIGHT" then
        setting.alignment = alignment
    else
        setting.alignment = "CENTER"
    end
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:SetRaidCheckWorldBuffUncountedMode(mode)
    local setting = self:GetRaidCheckColumnSetting("worldBuffs")
    if not setting then return false end
    if mode == "show" or mode == "hide" then
        setting.uncountedMode = mode
    else
        setting.uncountedMode = "fade"
    end
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

function PRT:GetRaidCheckColumnWidth(column)
    if not column then return 0 end
    if column.multiAura then
        local setting = self:GetRaidCheckColumnSetting(column)
        local maxDisplayLimit = math.max(
            1,
            tonumber(column.maxDisplayLimit)
                or RAID_CHECK_MAX_CATEGORY_ICONS)
        local maximum = math.max(1, math.min(
            maxDisplayLimit,
            tonumber(setting and setting.maxDisplay) or 1))
        -- World Buffs reserve the selected slots plus only the standard count
        -- width. This trims the final two pixels left by the former extra
        -- icon-width while preserving space for the adjacent count.
        if column.key == "worldBuffs" then
            return maximum * RAID_CHECK_ICON_WIDTH
                + RAID_CHECK_COUNT_WIDTH
        end
        local width = RAID_CHECK_ICON_COLUMN_WIDTH
            + (maximum - 1) * RAID_CHECK_ICON_WIDTH
        if setting and setting.showCount then
            width = width + RAID_CHECK_COUNT_WIDTH
        end
        return width
    end
    return tonumber(column.width) or 40
end

local function ColumnDetected(snapshot, columnKey)
    if not snapshot then return false end
    for _, member in ipairs(snapshot.members or {}) do
        local value = member[columnKey]
        if type(value) == "table" and #value > 0 then return true end
        if value and type(value) ~= "table" then return true end
    end
    return false
end

local function AddMissingBlessingsToSavedOrder(cfg)
    local order = cfg.columnOrder
    if type(order) ~= "table" then return end
    local seen = {}
    local insertionIndex
    for index, key in ipairs(order) do
        seen[key] = true
        if key == "kings" then
            insertionIndex = index + 1
        elseif key == "durability" and not insertionIndex then
            insertionIndex = index
        end
    end
    insertionIndex = insertionIndex or (#order + 1)
    for _, key in ipairs({ "salvation", "light" }) do
        if not seen[key] then
            table.insert(order, insertionIndex, key)
            insertionIndex = insertionIndex + 1
        end
    end
end

function PRT:GetRaidCheckColumnOrder(includeDisabled, snapshot)
    local cfg = self:GetDB().raidCheck or {}
    AddMissingBlessingsToSavedOrder(cfg)
    local catalog = self:GetRaidCheckColumnCatalog()
    local byKey, ordered, seen = {}, {}, {}
    for _, column in ipairs(catalog) do byKey[column.key] = column end

    if type(cfg.columnOrder) == "table" then
        for _, savedKey in ipairs(cfg.columnOrder) do
            local key = savedKey == "potion" and "consumes" or savedKey
            local column = byKey[key]
            if column and not seen[key] then
                local setting = self:GetRaidCheckColumnSetting(column)
                local visible = self:IsRaidCheckColumnEnabled(column)
                    and (setting.visibility ~= "detected"
                        or ColumnDetected(snapshot, column.key))
                if includeDisabled or visible then
                    ordered[#ordered + 1] = column
                end
                seen[key] = true
            end
        end
    end

    for _, column in ipairs(catalog) do
        local setting = self:GetRaidCheckColumnSetting(column)
        local visible = self:IsRaidCheckColumnEnabled(column)
            and (setting.visibility ~= "detected"
                or ColumnDetected(snapshot, column.key))
        if not seen[column.key] and (includeDisabled or visible) then
            ordered[#ordered + 1] = column
        end
    end
    return ordered
end

function PRT:MoveRaidCheckColumn(columnKey, direction)
    direction = tonumber(direction) or 0
    if direction == 0 then return false end
    local columns = self:GetRaidCheckColumnOrder(true)
    local index
    for position, column in ipairs(columns) do
        if column.key == columnKey then
            index = position
            break
        end
    end
    if not index then return false end

    local target = math.max(1, math.min(#columns,
        index + (direction < 0 and -1 or 1)))
    if target == index then return false end
    columns[index], columns[target] = columns[target], columns[index]

    local order = {}
    for _, column in ipairs(columns) do order[#order + 1] = column.key end
    self:GetDB().raidCheck.columnOrder = order
    if self.RefreshRaidCheckWindow then self:RefreshRaidCheckWindow() end
    return true
end

local function AddMember(members, unit, raidIndex, rosterName, rank, subgroup,
        level, className, classFile)
    if UnitExists and not UnitExists(unit) then return end

    local name, realm = PRT:GetUnitIdentity(unit)
    if name == "" and rosterName then
        name, realm = PRT:GetRaidMemberIdentity(raidIndex, rosterName)
    end
    if name == "" then return end

    local identityKey = PRT:MakePlayerIdentityKey(name, realm)
    local displayName = PRT:MakeCharacterFullName(name, realm, false)
    members[#members + 1] = {
        identityKey = identityKey,
        name = name,
        realm = realm,
        displayName = displayName,
        unit = unit,
        raidIndex = raidIndex,
        rank = rank or 0,
        subgroup = subgroup or 1,
        level = level or 0,
        className = className,
        classFile = classFile,
        connected = not UnitIsConnected or UnitIsConnected(unit) ~= false,
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false,
    }
end

function PRT:GetRaidCheckMembers()
    local members = {}
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            local name, rank, subgroup, level, className, classFile =
                GetRaidRosterInfo(index)
            if name then
                AddMember(members, "raid" .. index, index, name, rank,
                    subgroup, level, className, classFile)
            end
        end
    elseif IsInGroup and IsInGroup() then
        local playerClassName, playerClassFile
        if UnitClass then
            playerClassName, playerClassFile = UnitClass("player")
        end
        AddMember(members, "player", nil, nil, 0, 1,
            UnitLevel and UnitLevel("player") or 0,
            playerClassName, playerClassFile)

        local count = GetNumSubgroupMembers and GetNumSubgroupMembers()
            or math.max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1)
        for index = 1, count do
            local unit = "party" .. index
            local className, classFile
            if UnitClass then className, classFile = UnitClass(unit) end
            AddMember(members, unit, nil, nil, 0, 1,
                UnitLevel and UnitLevel(unit) or 0, className, classFile)
        end
    else
        local className, classFile
        if UnitClass then className, classFile = UnitClass("player") end
        AddMember(members, "player", nil, nil, 2, 1,
            UnitLevel and UnitLevel("player") or 0, className, classFile)
    end

    -- Capture each player's slot inside their subgroup before display sorting
    -- changes the snapshot order. Click reports can then give an exact
    -- Group/Slot location regardless of the user's selected row sort.
    local groupCounts = {}
    for _, member in ipairs(members) do
        local subgroup = tonumber(member.subgroup) or 1
        groupCounts[subgroup] = (groupCounts[subgroup] or 0) + 1
        member.groupSlot = groupCounts[subgroup]
    end
    return members
end

local function BuildSpellToBuffMap(definitions)
    local spellMap = {}
    for _, definition in ipairs(definitions) do
        for spellId, rank in pairs(definition.spells) do
            spellMap[spellId] = spellMap[spellId] or {}
            spellMap[spellId][#spellMap[spellId] + 1] = {
                key = definition.key,
                rank = tonumber(rank) or 1,
                maxRank = tonumber(definition.maxRank) or 1,
                displayIcon = definition.iconOverride,
            }
        end
    end
    return spellMap
end

local function MarkBuff(buffState, mapped, aura)
    if not mapped then return end
    for _, match in ipairs(mapped) do
        aura.raidCheckRank = match.rank
        aura.raidCheckMaxRank = match.maxRank
        aura.raidCheckLowRank = match.rank < match.maxRank
        -- Use the exact detected aura's spell texture. Salvation and Light
        -- retain their previously requested normalized icon overrides.
        aura.raidCheckDisplayIcon = match.displayIcon
            or ResolveSpellIcon(aura.spellId, aura.icon)
        buffState[match.key] = aura
    end
end

local function AnnotateAuraSource(owner, aura)
    local sourceUnit = aura and aura.sourceUnit
    if not sourceUnit or IsSecret(sourceUnit) then return end
    local sourceName, sourceRealm = owner:GetUnitIdentity(sourceUnit)
    if sourceName and sourceName ~= "" then
        aura.raidCheckSourceName = owner:MakeCharacterFullName(
            sourceName, sourceRealm, false)
    end
end

function PRT:CalculatePlayerDurability()
    if not GetInventoryItemDurability then return nil end
    local slots = {
        1, 2, 3, 15, 5, 9, 10, 6, 7, 8,
        11, 12, 13, 14, 16, 17, 18,
    }
    local currentTotal, maximumTotal = 0, 0
    for _, slotId in ipairs(slots) do
        local current, maximum = GetInventoryItemDurability(slotId)
        if current and maximum and maximum > 0 then
            currentTotal = currentTotal + current
            maximumTotal = maximumTotal + maximum
        end
    end
    if maximumTotal <= 0 then return 100 end
    return currentTotal / maximumTotal * 100
end

function PRT:GetCachedRaidCheckDurability(identityKey)
    local entry = self._raidCheckDurability
        and self._raidCheckDurability[identityKey] or nil
    if not entry then return nil end
    if Now() - (entry.receivedAt or 0) > DURABILITY_CACHE_SECONDS then
        return nil
    end
    return entry.percent
end

local function IsPlayerUnit(unit)
    if UnitIsUnit then return UnitIsUnit(unit, "player") end
    return unit == "player"
end

function PRT:ScanRaidCheckMember(member, spellToBuff)
    local result = member
    result.worldBuffs = {}
    result.countedWorldBuffs = {}
    result.zanza = {}
    result.consumes = {}
    result.potions = {}
    result.disallowed = {}
    result.food = nil
    result.flask = nil
    result.petrification = nil
    result.buffs = {}
    result.auraScanAvailable = not AurasAreSecret()

    if result.auraScanAvailable then
        for index = 1, MAX_AURAS do
            local aura = GetAuraData(member.unit, index)
            if not aura then break end
            if not IsSecret(aura.spellId) and not IsSecret(aura.icon) then
                AnnotateAuraSource(self, aura)
                local spellId = tonumber(aura.spellId)
                local icon = tonumber(aura.icon)
                if not result.food
                    and (FOOD_AURAS[spellId] or icon == 136000) then
                    result.food = aura
                end
                if not result.flask and FLASK_AURAS[spellId] then
                    result.flask = aura
                end
                if not result.petrification
                    and PETRIFICATION_AURAS[spellId] then
                    result.petrification = aura
                end
                local worldBuffDefinition = WORLD_BUFF_AURAS[spellId]
                if worldBuffDefinition then
                    ApplyAuraDefinition(aura, worldBuffDefinition)
                    aura.raidCheckCounted =
                        self:IsRaidCheckWorldBuffCounted(
                            member.classFile, spellId)
                    result.worldBuffs[#result.worldBuffs + 1] = aura
                    if aura.raidCheckCounted then
                        result.countedWorldBuffs[
                            #result.countedWorldBuffs + 1] = aura
                    end
                end
                local zanzaDefinition = ZANZA_AURAS[spellId]
                if zanzaDefinition then
                    result.zanza[#result.zanza + 1] =
                        ApplyAuraDefinition(aura, zanzaDefinition)
                end
                local consumeDefinition = CONSUME_AURAS[spellId]
                if consumeDefinition then
                    result.consumes[#result.consumes + 1] =
                        ApplyAuraDefinition(aura, consumeDefinition)
                end
                local potionDefinition = POTION_AURAS[spellId]
                if potionDefinition then
                    result.potions[#result.potions + 1] =
                        ApplyAuraDefinition(aura, potionDefinition)
                end
                local disallowedDefinition = DISALLOWED_AURAS[spellId]
                if disallowedDefinition then
                    result.disallowed[#result.disallowed + 1] =
                        ApplyAuraDefinition(aura, disallowedDefinition)
                end
                MarkBuff(result.buffs, spellToBuff[spellId], aura)
            end
        end
    end

    -- Valid buffs always occupy display slots before shown/faded uncounted
    -- detections; both groups retain the canonical definition priority.
    SortWorldBuffList(result.worldBuffs)
    SortAuraList(result.countedWorldBuffs)
    SortAuraList(result.zanza)
    SortAuraList(result.consumes)
    SortAuraList(result.potions)
    SortAuraList(result.disallowed)

    if IsPlayerUnit(member.unit) then
        result.durability = self:CalculatePlayerDurability()
    else
        result.durability =
            self:GetCachedRaidCheckDurability(member.identityKey)
    end
    result.readyStatus = self._raidCheckReadyStatus
        and self._raidCheckReadyStatus[member.identityKey] or nil
    return result
end

local function SortRaidCheckMembers(members, sortMode)
    table.sort(members, function(a, b)
        if sortMode == "name" then
            return string.lower(a.displayName) < string.lower(b.displayName)
        elseif sortMode == "class" or sortMode == "classGroup" then
            local aClass = tostring(a.classFile or "")
            local bClass = tostring(b.classFile or "")
            local aClassOrder = RAID_CHECK_CLASS_ORDER[aClass] or 99
            local bClassOrder = RAID_CHECK_CLASS_ORDER[bClass] or 99
            if aClassOrder ~= bClassOrder then
                return aClassOrder < bClassOrder
            end
            if aClass ~= bClass then return aClass < bClass end
            if sortMode == "classGroup" then
                local aGroup = tonumber(a.subgroup) or 99
                local bGroup = tonumber(b.subgroup) or 99
                if aGroup ~= bGroup then return aGroup < bGroup end
                local aIndex = tonumber(a.raidIndex) or 99
                local bIndex = tonumber(b.raidIndex) or 99
                if aIndex ~= bIndex then return aIndex < bIndex end
            end
            return string.lower(a.displayName) < string.lower(b.displayName)
        end
        if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
        return (a.raidIndex or 99) < (b.raidIndex or 99)
    end)
end

function PRT:BuildRaidCheckSnapshot()
    local cfg = self:GetDB().raidCheck or {}
    local definitions = self:GetRaidCheckBuffDefinitions()
    local spellToBuff = BuildSpellToBuffMap(definitions)
    local members = self:GetRaidCheckMembers()
    for _, member in ipairs(members) do
        self:ScanRaidCheckMember(member, spellToBuff)
    end
    SortRaidCheckMembers(members, cfg.sortMode or "classGroup")
    return {
        createdAt = Now(),
        members = members,
        buffDefinitions = definitions,
        readyCheckActive = self._raidCheckActive == true,
        readyCheckStartedAt = self._raidCheckStartedAt,
        readyCheckDeadline = self._raidCheckDeadline,
        readyCheckDuration = self._raidCheckDuration,
    }
end

local function PreviewAura(name, spellId, icon, rank, maxRank)
    CountRaidCheckDebug("previewAurasBuilt")
    return {
        name = name,
        spellId = spellId,
        icon = icon,
        raidCheckRank = rank,
        raidCheckMaxRank = maxRank,
        raidCheckLowRank = rank and maxRank and rank < maxRank or false,
    }
end

local previewSpellIdsByDefinition =
    setmetatable({}, { __mode = "k" })

local function PreviewBuffAura(definition, rank)
    local spellIdsByRank = previewSpellIdsByDefinition[definition]
    if not spellIdsByRank then
        spellIdsByRank = {}
        for spellId, spellRank in pairs(definition.spells or {}) do
            local numericRank = tonumber(spellRank)
            local spellIds = spellIdsByRank[numericRank]
            if not spellIds then
                spellIds = {}
                spellIdsByRank[numericRank] = spellIds
            end
            spellIds[#spellIds + 1] = tonumber(spellId)
        end
        for _, spellIds in pairs(spellIdsByRank) do
            table.sort(spellIds)
        end
        previewSpellIdsByDefinition[definition] = spellIdsByRank
    end
    local spellIds = spellIdsByRank[rank] or {}
    local spellId = #spellIds > 0
        and spellIds[math.random(#spellIds)] or 0
    local displayIcon = definition.iconOverride
        or ResolveSpellIcon(spellId, definition.icon)
    local aura = PreviewAura(
        definition.label,
        spellId,
        displayIcon,
        rank,
        definition.maxRank)
    aura.raidCheckDisplayIcon = displayIcon
    return aura
end

local function PreviewCategoryAura(definition, fallbackIcon)
    return ApplyAuraDefinition(
        PreviewAura(
            definition.name,
            definition.spellId,
            fallbackIcon),
        definition)
end

local PREVIEW_FLASK_DEFINITIONS = {
    { spellId = 17626, name = "Flask of the Titans", icon = 134842 },
    {
        spellId = 17627,
        name = "Flask of Distilled Wisdom",
        icon = 134877,
    },
    {
        spellId = 17628,
        name = "Flask of Supreme Power",
        icon = 134821,
    },
    {
        spellId = 17629,
        name = "Flask of Chromatic Resistance",
        icon = 134828,
    },
}

local function PreviewChance(percent)
    return math.random(100) <= percent
end

local previewAuraPool = {}

local function RandomPreviewAuras(
        definitions, maximum, fallbackIcon, options)
    options = options or {}
    local upper = math.min(
        tonumber(options.lastDefinition) or #definitions,
        #definitions)
    local pool = previewAuraPool
    for index = #pool, 1, -1 do pool[index] = nil end
    for index = 1, upper do
        local definition = definitions[index]
        if not options.includeDefinition
            or options.includeDefinition(definition) then
            pool[#pool + 1] = definition
        end
    end

    local selected = {}
    local available = math.min(
        math.max(0, tonumber(maximum) or 0), #pool)
    local count = options.forcedCount ~= nil
        and math.max(
            0,
            math.min(tonumber(options.forcedCount) or 0, available))
        or math.random(0, available)
    for _ = 1, count do
        if #pool == 0 then break end
        local poolIndex = math.random(#pool)
        local definition = pool[poolIndex]
        selected[#selected + 1] =
            PreviewCategoryAura(definition, fallbackIcon)
        -- Alternate spell IDs for the same named effect should not appear
        -- together in a generated preview (for example Might of Stormwind).
        -- Exclusive preview groups also model mutually exclusive effects such
        -- as the eight possible Sayge's Dark Fortunes.
        for index = #pool, 1, -1 do
            local candidate = pool[index]
            if candidate.name == definition.name
                or (definition.previewExclusiveGroup
                    and candidate.previewExclusiveGroup
                        == definition.previewExclusiveGroup) then
                table.remove(pool, index)
            end
        end
    end
    SortAuraList(selected)
    return selected
end

local function RandomUnusedPreviewIndex(used)
    local available = {}
    for index = 1, #PREVIEW_NAMES do
        if not used[index] then
            available[#available + 1] = index
        end
    end
    if #available == 0 then return 1 end
    local selected = available[math.random(#available)]
    used[selected] = true
    return selected
end

function PRT:BuildRaidCheckTestSnapshot()
    CountRaidCheckDebug("testSnapshotsBuilt")
    local definitions = self:GetRaidCheckBuffDefinitions()
    local now = Now()
    local members = {}
    local worldBuffLimit = tonumber(
        self:GetRaidCheckColumnSetting("worldBuffs").maxDisplay) or 1
    local consumeLimit = tonumber(
        self:GetRaidCheckColumnSetting("consumes").maxDisplay) or 1
    local potionLimit = tonumber(
        self:GetRaidCheckColumnSetting("potions").maxDisplay) or 1

    -- Randomized, distinct placements guarantee uncommon states and one
    -- full-width example for every configurable multi-icon preparation
    -- category while the rest of each preview remains variable.
    local chronoboonIndex = math.random(#PREVIEW_NAMES)
    local usedGuaranteeIndices = { [chronoboonIndex] = true }
    local worldBuffLimitIndex =
        RandomUnusedPreviewIndex(usedGuaranteeIndices)
    local consumeLimitIndex =
        RandomUnusedPreviewIndex(usedGuaranteeIndices)
    local potionLimitIndex =
        RandomUnusedPreviewIndex(usedGuaranteeIndices)
    local disallowedIndex =
        RandomUnusedPreviewIndex(usedGuaranteeIndices)
    for index, name in ipairs(PREVIEW_NAMES) do
        CountRaidCheckDebug("previewMembersBuilt")
        local classFile =
            PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
        local member = {
            identityKey = string.lower(name) .. "@preview",
            name = name,
            realm = "",
            displayName = name,
            unit = "preview" .. index,
            raidIndex = index,
            subgroup = math.ceil(index / 5),
            groupSlot = ((index - 1) % 5) + 1,
            level = 60,
            className = classFile,
            classFile = classFile,
            connected = true,
            dead = false,
            auraScanAvailable = true,
            worldBuffs = {},
            countedWorldBuffs = {},
            zanza = {},
            consumes = {},
            potions = {},
            disallowed = {},
            buffs = {},
            durability = PreviewChance(12) and nil or math.random(22, 100),
        }

        if PreviewChance(78) then
            member.food = PreviewAura("Well Fed", 18192, 136000)
        end
        if PreviewChance(72) then
            local flask = PREVIEW_FLASK_DEFINITIONS[
                math.random(#PREVIEW_FLASK_DEFINITIONS)]
            member.flask = PreviewAura(
                flask.name, flask.spellId, flask.icon)
        end
        member.consumes = RandomPreviewAuras(
            CONSUME_AURA_DEFINITIONS,
            consumeLimit,
            134812,
            {
                forcedCount = index == consumeLimitIndex
                    and consumeLimit or nil,
            })
        if PreviewChance(74) then
            local zanza = ZANZA_AURA_DEFINITIONS[
                math.random(#ZANZA_AURA_DEFINITIONS)]
            member.zanza[1] =
                PreviewCategoryAura(zanza, 134810)
        end
        member.potions = RandomPreviewAuras(
            POTION_AURA_DEFINITIONS,
            potionLimit,
            134800,
            {
                forcedCount = index == potionLimitIndex
                    and potionLimit or nil,
            })
        if index == disallowedIndex or PreviewChance(4) then
            member.disallowed[1] =
                PreviewCategoryAura(
                    DISALLOWED_AURA_DEFINITIONS[
                        math.random(#DISALLOWED_AURA_DEFINITIONS)])
        end
        if index == chronoboonIndex then
            -- Preview-only realism rule: a booned player shows only the
            -- Chronoboon container rather than active World Buffs or invented
            -- knowledge of the buffs stored inside it.
            member.worldBuffs[1] =
                PreviewCategoryAura(WORLD_BUFF_AURAS[349981], 133741)
        else
            member.worldBuffs = RandomPreviewAuras(
                WORLD_BUFF_DEFINITIONS,
                worldBuffLimit,
                134153,
                {
                    lastDefinition = #WORLD_BUFF_DEFINITIONS - 1,
                    forcedCount = index == worldBuffLimitIndex
                        and worldBuffLimit or nil,
                    includeDefinition = index == worldBuffLimitIndex
                        and function(definition)
                            return self:IsRaidCheckWorldBuffCounted(
                                classFile, definition.spellId)
                        end
                        or nil,
                })
        end
        for _, aura in ipairs(member.worldBuffs) do
            aura.raidCheckCounted = self:IsRaidCheckWorldBuffCounted(
                classFile, aura.spellId)
            if aura.raidCheckCounted then
                member.countedWorldBuffs[
                    #member.countedWorldBuffs + 1] = aura
            end
        end
        SortWorldBuffList(member.worldBuffs)
        SortAuraList(member.countedWorldBuffs)

        for _, definition in ipairs(definitions) do
            if PreviewChance(84) then
                local rank = definition.maxRank
                if definition.maxRank > 1 and PreviewChance(16) then
                    rank = math.random(1, definition.maxRank - 1)
                end
                member.buffs[definition.key] =
                    PreviewBuffAura(definition, rank)
            end
        end

        member.readyStatus =
            index <= 27 and "ready"
            or index <= 32 and "notReady"
            or "waiting"
        members[#members + 1] = member
    end

    local cfg = self:GetDB().raidCheck or {}
    SortRaidCheckMembers(members, cfg.sortMode or "classGroup")
    return {
        createdAt = now,
        members = members,
        buffDefinitions = definitions,
        readyCheckActive = true,
        readyCheckStartedAt = now,
        readyCheckDeadline = now + DEFAULT_READY_CHECK_DURATION,
        readyCheckDuration = DEFAULT_READY_CHECK_DURATION,
        preview = true,
    }
end

local function NamesMissing(snapshot, predicate)
    local names = {}
    for _, member in ipairs(snapshot.members) do
        if predicate(member) then names[#names + 1] = member.displayName end
    end
    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return names
end

local function AppendNameLines(lines, missingLabel, coveredLabel, names, total)
    if #names == 0 then
        lines[#lines + 1] = ("%s: all %d players covered."):format(
            coveredLabel, total)
        return
    end

    local prefix = ("%s (%d): "):format(missingLabel, #names)
    local current = prefix
    for index, name in ipairs(names) do
        local suffix = index < #names and ", " or ""
        if #current + #name + #suffix > 230 and current ~= prefix then
            lines[#lines + 1] = current:gsub(", $", "")
            current = prefix
        end
        current = current .. name .. suffix
    end
    lines[#lines + 1] = current:gsub(", $", "")
end

local function AppendFoundLines(lines, label, names)
    if #names == 0 then
        lines[#lines + 1] = label .. ": none detected."
        return
    end
    local prefix = ("%s (%d): "):format(label, #names)
    local current = prefix
    for index, name in ipairs(names) do
        local suffix = index < #names and ", " or ""
        if #current + #name + #suffix > 230 and current ~= prefix then
            lines[#lines + 1] = current:gsub(", $", "")
            current = prefix
        end
        current = current .. name .. suffix
    end
    lines[#lines + 1] = current:gsub(", $", "")
end

local function AppendBuffLines(lines, snapshot)
    local attention = {}
    local catalog = PRT:GetRaidCheckColumnCatalog()
    for _, definition in ipairs(snapshot.buffDefinitions) do
        local column = FindColumnByKey(catalog, definition.key)
        if PRT:IsRaidCheckColumnEnabled(column) then
            local missingCount, lowRankCount = 0, 0
            for _, member in ipairs(snapshot.members) do
                local aura = member.buffs[definition.key]
                if not aura then
                    missingCount = missingCount + 1
                elseif aura.raidCheckLowRank then
                    lowRankCount = lowRankCount + 1
                end
            end
            if missingCount > 0 or lowRankCount > 0 then
                local details = {}
                if missingCount > 0 then
                    details[#details + 1] = "missing " .. missingCount
                end
                if lowRankCount > 0 then
                    details[#details + 1] =
                        "low rank " .. lowRankCount
                end
                attention[#attention + 1] = ("%s (%s)"):format(
                    definition.shortLabel, table.concat(details, ", "))
            end
        end
    end

    if #attention == 0 then
        lines[#lines + 1] = ("Raid buffs: all %d players covered."):format(
            #snapshot.members)
        return
    end

    local prefix = "Raid buffs needing attention: "
    local current = prefix
    for index, entry in ipairs(attention) do
        local suffix = index < #attention and ", " or "."
        if #current + #entry + #suffix > 230 and current ~= prefix then
            lines[#lines + 1] = current:gsub(", $", "")
            current = prefix
        end
        current = current .. entry .. suffix
    end
    lines[#lines + 1] = current:gsub(", $", "")
end

function PRT:BuildRaidCheckReport(checkType, snapshot)
    snapshot = snapshot or self:BuildRaidCheckSnapshot()
    local lines = {}
    if #snapshot.members == 0 then
        return { "Raid Check: no group members found." }, snapshot
    end

    local function Enabled(columnKey)
        local column = FindColumnByKey(
            self:GetRaidCheckColumnCatalog(), columnKey)
        return self:IsRaidCheckColumnEnabled(column)
    end

    if checkType == "worldBuffs"
        or (checkType == "all" and Enabled("worldBuffs")) then
        AppendNameLines(lines, "Missing world buffs", "World buffs",
            NamesMissing(snapshot, function(member)
                return not member.countedWorldBuffs
                    or #member.countedWorldBuffs == 0
            end),
            #snapshot.members)
    end
    if checkType == "food" or (checkType == "all" and Enabled("food")) then
        AppendNameLines(lines, "Missing food", "Food",
            NamesMissing(snapshot, function(member) return not member.food end),
            #snapshot.members)
    end
    if checkType == "flask"
        or (checkType == "all" and Enabled("flask")) then
        AppendNameLines(lines, "Missing flask", "Flask",
            NamesMissing(snapshot, function(member) return not member.flask end),
            #snapshot.members)
    end
    if checkType == "zanza"
        or (checkType == "all" and Enabled("zanza")) then
        AppendNameLines(lines, "Missing Zanza", "Zanza",
            NamesMissing(snapshot, function(member)
                return not member.zanza or #member.zanza == 0
            end),
            #snapshot.members)
    end
    if checkType == "consumes" or checkType == "potion"
        or (checkType == "all" and Enabled("consumes")) then
        AppendNameLines(lines, "Missing consumes", "Consumes",
            NamesMissing(snapshot, function(member)
                return not member.consumes or #member.consumes == 0
            end),
            #snapshot.members)
    end
    if checkType == "potions"
        or (checkType == "all" and Enabled("potions")) then
        AppendNameLines(lines, "Missing potions", "Potions",
            NamesMissing(snapshot, function(member)
                return not member.potions or #member.potions == 0
            end),
            #snapshot.members)
    end
    if checkType == "disallowed"
        or (checkType == "all" and Enabled("disallowed")) then
        local found = NamesMissing(snapshot, function(member)
            return member.disallowed and #member.disallowed > 0
        end)
        if checkType == "disallowed" or #found > 0 then
            AppendFoundLines(lines, "Disallowed buffs found", found)
        end
    end
    local anyBuffColumnEnabled = false
    for _, definition in ipairs(snapshot.buffDefinitions or {}) do
        if Enabled(definition.key) then
            anyBuffColumnEnabled = true
            break
        end
    end
    if checkType == "buffs"
        or (checkType == "all" and anyBuffColumnEnabled) then
        AppendBuffLines(lines, snapshot)
    end
    return lines, snapshot
end

local function GetReportChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function SendChat(message, channel)
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() then
        return false
    end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(message, channel)
        return true
    elseif SendChatMessage then
        SendChatMessage(message, channel)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Self-issued group-chat Raid Check commands
---------------------------------------------------------------------------
local RAID_CHECK_CHAT_PREFIX = "PRT: "
local RAID_CHECK_CHAT_LIMIT = 255
local RAID_CHECK_CHAT_CHANNELS = {
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

local RAID_CHECK_CHAT_COMMANDS = {
    {
        key = "flask",
        aliases = { "!flask" },
        description = "Missing flask count and player names.",
    },
    {
        key = "worldBuffs",
        aliases = { "!worldbuffs", "!wb", "!wbs" },
        description = "Players with at least one active World Buff.",
    },
    {
        key = "twoHours",
        aliases = { "!2hours", "!2hrs", "!twohours", "!twohrs" },
        description = "Players with at least one two-hour World Buff.",
    },
    {
        key = "oneHours",
        aliases = { "!1hours", "!1hrs", "!onehours", "!onehrs" },
        description = "Players with at least one one-hour World Buff.",
    },
    {
        key = "boon",
        aliases = { "!boon" },
        description = "Players with Supercharged Chronoboon active.",
    },
    {
        key = "disallowed",
        aliases = { "!logs", "!disallowed", "!banned", "!invalid" },
        description = "Detected Logs! auras and affected players.",
    },
    {
        key = "battleShout",
        aliases = { "!bs", "!bshout", "!battleshout" },
        description = "Eligible players with Diamond Flask Battle Shout.",
    },
    {
        key = "fortitude",
        aliases = { "!fort", "!stam" },
        description = "Players missing max-rank Fortitude.",
    },
    {
        key = "gotw",
        aliases = { "!gotw", "!motw" },
        description = "Players missing max-rank Mark or Gift of the Wild.",
    },
    {
        key = "intellect",
        aliases = { "!int", "!ai", "!ab" },
        description = "Eligible players missing max-rank Intellect.",
    },
    {
        key = "spirit",
        aliases = { "!spirit", "!spi" },
        description = "Eligible players missing max-rank Spirit.",
    },
    {
        key = "shadow",
        aliases = { "!shadow", "!shadowprotection" },
        description = "Players missing max-rank Shadow Protection.",
    },
    {
        key = "kings",
        aliases = { "!kings", "!bok" },
        description = "Players missing max-rank Blessing of Kings.",
    },
    {
        key = "might",
        aliases = { "!might", "!bom" },
        description = "Players missing max-rank Blessing of Might.",
    },
    {
        key = "wisdom",
        aliases = { "!wisdom", "!bow" },
        description = "Players missing max-rank Blessing of Wisdom.",
    },
    {
        key = "light",
        aliases = { "!light", "!bol" },
        description = "Players missing max-rank Blessing of Light.",
    },
    {
        key = "durability",
        aliases = { "!durability", "!dur" },
        description = "Raid average and counts below durability thresholds.",
    },
    {
        key = "jujuChill",
        aliases = { "!jchill", "!jujuchill", "!chill" },
        description = "Players missing Juju Chill.",
    },
    {
        key = "gfpp",
        aliases = { "!gfpp" },
        description = "Players missing Greater Frost Protection Potion.",
    },
    {
        key = "gnpp",
        aliases = { "!gnpp" },
        description = "Players missing Greater Nature Protection Potion.",
    },
    {
        key = "gspp",
        aliases = { "!gspp" },
        description = "Players missing Greater Shadow Protection Potion.",
    },
    {
        key = "gapp",
        aliases = { "!gapp" },
        description = "Players missing Greater Arcane Protection Potion.",
    },
    {
        key = "gfipp",
        aliases = { "!gfipp" },
        description = "Players missing Greater Fire Protection Potion.",
    },
}

local RAID_CHECK_CHAT_COMMAND_BY_ALIAS = {}
for _, command in ipairs(RAID_CHECK_CHAT_COMMANDS) do
    for _, alias in ipairs(command.aliases) do
        RAID_CHECK_CHAT_COMMAND_BY_ALIAS[alias] = command
    end
end

local ONE_HOUR_WORLD_BUFFS = {
    [15366] = true,  -- Songflower Serenade
    [16609] = true,  -- Warchief's Blessing
    [460940] = true, -- Might of Stormwind
    [460939] = true, -- Might of Stormwind
}
local TWO_HOUR_WORLD_BUFFS = {}
for _, definition in ipairs(WORLD_BUFF_DEFINITIONS) do
    if not definition.isWorldBuffContainer
        and not ONE_HOUR_WORLD_BUFFS[definition.spellId] then
        TWO_HOUR_WORLD_BUFFS[definition.spellId] = true
    end
end

local BATTLE_SHOUT_CLASSES = {
    WARRIOR = true,
    ROGUE = true,
    HUNTER = true,
}
local MANA_BUFF_CLASSES = {
    HUNTER = true,
    DRUID = true,
    WARLOCK = true,
    PRIEST = true,
    SHAMAN = true,
    MAGE = true,
    PALADIN = true,
}
local CLICK_BUFF_REPORTS = {
    stamina = {
        label = "Fortitude",
    },
    druid = {
        label = "Mark / Gift of the Wild",
    },
    intellect = {
        label = "Arcane Intellect / Brilliance",
        classes = MANA_BUFF_CLASSES,
    },
    spirit = {
        label = "Divine Spirit / Prayer of Spirit",
        classes = MANA_BUFF_CLASSES,
    },
    shadow = {
        label = "Shadow Protection",
    },
    kings = {
        label = "Blessing of Kings",
    },
    might = {
        label = "Blessing of Might",
    },
    wisdom = {
        label = "Blessing of Wisdom",
        classes = MANA_BUFF_CLASSES,
    },
    salvation = {
        label = "Blessing of Salvation",
    },
    light = {
        label = "Blessing of Light",
    },
}
local BUFF_CHAT_COMMANDS = {
    fortitude = {
        label = "Fortitude",
        buffKey = "stamina",
    },
    gotw = {
        label = "GotW",
        buffKey = "druid",
    },
    intellect = {
        label = "Intellect",
        buffKey = "intellect",
        classes = MANA_BUFF_CLASSES,
    },
    spirit = {
        label = "Spirit",
        buffKey = "spirit",
        classes = MANA_BUFF_CLASSES,
    },
    shadow = {
        label = "Shadow Protection",
        buffKey = "shadow",
    },
    kings = {
        label = "Blessing of Kings",
        buffKey = "kings",
    },
    might = {
        label = "Blessing of Might",
        buffKey = "might",
    },
    wisdom = {
        label = "Blessing of Wisdom",
        buffKey = "wisdom",
    },
    light = {
        label = "Blessing of Light",
        buffKey = "light",
    },
}
local AURA_CHAT_COMMANDS = {
    jujuChill = {
        label = "Juju Chill",
        memberKey = "consumes",
        spellId = 16325,
    },
    gfpp = {
        label = "Greater Frost Protection Potion",
        memberKey = "potions",
        spellId = 17544,
    },
    gnpp = {
        label = "Greater Nature Protection Potion",
        memberKey = "potions",
        spellId = 17546,
    },
    gspp = {
        label = "Greater Shadow Protection Potion",
        memberKey = "potions",
        spellId = 17548,
    },
    gapp = {
        label = "Greater Arcane Protection Potion",
        memberKey = "potions",
        spellId = 17549,
    },
    gfipp = {
        label = "Greater Fire Protection Potion",
        memberKey = "potions",
        spellId = 17543,
    },
}

local function ChatCommandSyntax(command)
    return table.concat(command.aliases or {}, " / ")
end

local RAID_CHECK_COMMAND_COLOR = "|cff33ff99"
local RAID_CHECK_COLOR_END = "|r"

function PRT:GetRaidCheckChatCommandDefinitions()
    return RAID_CHECK_CHAT_COMMANDS
end

function PRT:GetRaidCheckChatCommandTooltipLines()
    local lines = {}
    for _, command in ipairs(RAID_CHECK_CHAT_COMMANDS) do
        lines[#lines + 1] = {
            RAID_CHECK_COMMAND_COLOR
                .. ChatCommandSyntax(command)
                .. RAID_CHECK_COLOR_END
                .. " - "
                .. command.description,
            0.88, 0.88, 0.88, false,
        }
    end
    return lines
end

function PRT:PrintRaidCheckChatCommands()
    self.Print("Raid Check chat commands:")
    for _, command in ipairs(RAID_CHECK_CHAT_COMMANDS) do
        self.Print("  " .. ChatCommandSyntax(command)
            .. " - " .. command.description)
    end
end

local function MemberDisplayName(member)
    return tostring(member.displayName or member.name or "Unknown")
end

local function EligibleMembers(snapshot, classes)
    local members = {}
    for _, member in ipairs(snapshot.members or {}) do
        if not classes or classes[member.classFile] then
            members[#members + 1] = member
        end
    end
    return members
end

local function SortedNames(members)
    local names = {}
    for _, member in ipairs(members or {}) do
        names[#names + 1] = MemberDisplayName(member)
    end
    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)
    return names
end

local function MissingMembers(members, hasRequirement)
    local missing = {}
    for _, member in ipairs(members or {}) do
        if not hasRequirement(member) then
            missing[#missing + 1] = member
        end
    end
    return missing
end

local function HasAuraSpell(auras, spellId)
    for _, aura in ipairs(auras or {}) do
        if tonumber(aura.spellId) == spellId then return true end
    end
    return false
end

local function HasWorldBuff(member, spellSet)
    for _, aura in ipairs(member.worldBuffs or {}) do
        local spellId = tonumber(aura.spellId)
        if not aura.raidCheckWorldBuffContainer
            and (not spellSet or spellSet[spellId]) then
            return true
        end
    end
    return false
end

local function HasMaxRankBuff(member, buffKey)
    local aura = member.buffs and member.buffs[buffKey]
    return aura ~= nil and aura.raidCheckLowRank ~= true
end

local function MissingSummary(label, members, hasRequirement, eligible)
    local missing = MissingMembers(members, hasRequirement)
    local scope = eligible
        and "eligible players missing" or "players missing"
    local line = ("%s - %d/%d %s"):format(
        label, #missing, #members, scope)
    if #missing > 0 then
        line = line .. " - " .. table.concat(SortedNames(missing), ", ")
    end
    return { line .. "." }
end

local function WorldBuffSummary(label, buffLabel, members, spellSet)
    local missing = MissingMembers(members, function(member)
        return HasWorldBuff(member, spellSet)
    end)
    local covered = #members - #missing
    local lines = {
        ("%s - %d/%d players have at least 1 %s."):format(
            label, covered, #members, buffLabel),
    }
    if #missing > 0 then
        lines[#lines + 1] = "Missing " .. label .. ": "
            .. table.concat(SortedNames(missing), ", ") .. "."
    end
    return lines
end

local function DurabilitySummary(snapshot)
    local known, totalPercent = 0, 0
    local thresholds = {
        { value = 75, count = 0 },
        { value = 50, count = 0 },
        { value = 30, count = 0 },
        { value = 20, count = 0 },
    }
    for _, member in ipairs(snapshot.members or {}) do
        local durability = tonumber(member.durability)
        if durability then
            known = known + 1
            totalPercent = totalPercent + durability
            for _, threshold in ipairs(thresholds) do
                if durability < threshold.value then
                    threshold.count = threshold.count + 1
                end
            end
        end
    end
    if known == 0 then
        return { "Durability - no player durability data available." }
    end

    local lines = {
        ("Durability - Raid average %.1f%% (%d/%d players reporting)."):format(
            totalPercent / known, known, #(snapshot.members or {})),
    }
    for _, threshold in ipairs(thresholds) do
        lines[#lines + 1] = ("Under %d%% durability - %d players."):format(
            threshold.value, threshold.count)
    end
    return lines
end

local function DisallowedSummary(members)
    local affected = {}
    local foundBySpell = {}
    local detections = 0

    for _, member in ipairs(members or {}) do
        local memberFound = false
        for _, aura in ipairs(member.disallowed or {}) do
            local spellId = tonumber(aura.spellId)
            if DISALLOWED_AURAS[spellId] then
                foundBySpell[spellId] = foundBySpell[spellId] or {}
                foundBySpell[spellId][#foundBySpell[spellId] + 1] = member
                detections = detections + 1
                memberFound = true
            end
        end
        if memberFound then affected[#affected + 1] = member end
    end

    if detections == 0 then
        return { "Logs! - no disallowed auras found." }
    end

    local lines = {
        ("Logs! - %d disallowed aura%s found on %d/%d players."):format(
            detections,
            detections == 1 and "" or "s",
            #affected,
            #(members or {})),
    }
    for _, definition in ipairs(DISALLOWED_AURA_DEFINITIONS) do
        local found = foundBySpell[definition.spellId]
        if found and #found > 0 then
            lines[#lines + 1] = definition.name .. " - "
                .. table.concat(SortedNames(found), ", ") .. "."
        end
    end
    return lines
end

local function BuildRaidCheckChatCommandBody(command, snapshot)
    local members = snapshot.members or {}
    if #members == 0 then return { "No group members found." } end
    local key = command.key

    if key == "flask" then
        return MissingSummary("Flasks", members, function(member)
            return member.flask ~= nil
        end)
    elseif key == "worldBuffs" then
        return WorldBuffSummary(
            "World Buffs", "World Buff", members, nil)
    elseif key == "twoHours" then
        return WorldBuffSummary(
            "2-Hour World Buffs",
            "2-hour World Buff",
            members,
            TWO_HOUR_WORLD_BUFFS)
    elseif key == "oneHours" then
        return WorldBuffSummary(
            "1-Hour World Buffs",
            "1-hour World Buff",
            members,
            ONE_HOUR_WORLD_BUFFS)
    elseif key == "boon" then
        local covered = 0
        for _, member in ipairs(members) do
            if HasAuraSpell(member.worldBuffs, 349981) then
                covered = covered + 1
            end
        end
        return {
            ("Chronoboon - %d/%d players have Supercharged Chronoboon "
                .. "Displacer active."):format(covered, #members),
        }
    elseif key == "disallowed" then
        return DisallowedSummary(members)
    elseif key == "battleShout" then
        local eligible = EligibleMembers(snapshot, BATTLE_SHOUT_CLASSES)
        local covered = 0
        for _, member in ipairs(eligible) do
            if HasMaxRankBuff(member, "attackPower") then
                covered = covered + 1
            end
        end
        return {
            ("Battle Shout - %d/%d eligible players have Battle Shout."):format(
                covered, #eligible),
        }
    elseif key == "durability" then
        return DurabilitySummary(snapshot)
    end

    local buffCommand = BUFF_CHAT_COMMANDS[key]
    if buffCommand then
        local eligible = EligibleMembers(snapshot, buffCommand.classes)
        return MissingSummary(
            buffCommand.label,
            eligible,
            function(member)
                return HasMaxRankBuff(member, buffCommand.buffKey)
            end,
            buffCommand.classes ~= nil)
    end

    local auraCommand = AURA_CHAT_COMMANDS[key]
    if auraCommand then
        return MissingSummary(
            auraCommand.label,
            members,
            function(member)
                return HasAuraSpell(
                    member[auraCommand.memberKey],
                    auraCommand.spellId)
            end)
    end
    return {}
end

local function PrefixAndSplitChatLines(lines, prefix)
    local result = {}
    prefix = prefix or RAID_CHECK_CHAT_PREFIX
    local maximumBody = RAID_CHECK_CHAT_LIMIT - #prefix
    for _, rawLine in ipairs(lines or {}) do
        local remaining = tostring(rawLine or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if remaining == "" then remaining = "No results." end
        while #remaining > maximumBody do
            local window = remaining:sub(1, maximumBody + 1)
            local splitAt = window:match("^.*()%s")
            local nextStart
            if not splitAt or splitAt <= 1 then
                splitAt = maximumBody + 1
                nextStart = maximumBody + 1
            else
                nextStart = splitAt + 1
            end
            local segment = remaining:sub(1, splitAt - 1):gsub("%s+$", "")
            result[#result + 1] = prefix .. segment
            remaining = remaining:sub(nextStart):gsub("^%s+", "")
        end
        result[#result + 1] = prefix .. remaining
    end
    return result
end

---------------------------------------------------------------------------
-- Click reports from the compact Raid Check window
---------------------------------------------------------------------------
local RAID_CHECK_CLICK_REPORT_PREFIX = "PRT - "

local function MembersMatching(members, predicate)
    local result = {}
    for _, member in ipairs(members or {}) do
        if predicate(member) then
            result[#result + 1] = member
        end
    end
    return result
end

local function NameListLine(label, members)
    local names = SortedNames(members)
    return label .. ": "
        .. (#names > 0 and table.concat(names, ", ") or "None")
        .. "."
end

local function MemberClassLabel(member)
    local className = tostring(member and member.className or "")
    local classFile = tostring(member and member.classFile or "")
    if className ~= "" and className ~= classFile then
        return className
    end
    if classFile == "" then return "Unknown class" end
    local lower = string.lower(classFile)
    return string.upper(lower:sub(1, 1)) .. lower:sub(2)
end

local function MemberGroupSlot(snapshot, target)
    local saved = tonumber(target and target.groupSlot)
    if saved and saved > 0 then return saved end

    local subgroup = tonumber(target and target.subgroup) or 1
    local raidIndex = tonumber(target and target.raidIndex)
    local slot = 0
    for _, member in ipairs(snapshot and snapshot.members or {}) do
        if (tonumber(member.subgroup) or 1) == subgroup then
            if raidIndex and tonumber(member.raidIndex) then
                if tonumber(member.raidIndex) <= raidIndex then
                    slot = slot + 1
                end
            else
                slot = slot + 1
                if member == target then break end
            end
        end
    end
    return math.max(1, slot)
end

local function AuraReportName(aura, fallback)
    return tostring(
        aura and (aura.raidCheckDefinitionName or aura.name)
            or fallback
            or "buff")
end

local function WrongRankEntry(member, aura, fallback)
    local text = MemberDisplayName(member)
        .. " (" .. AuraReportName(aura, fallback)
    if aura and aura.raidCheckRank and aura.raidCheckMaxRank then
        text = text .. (" R%d/%d"):format(
            aura.raidCheckRank, aura.raidCheckMaxRank)
    else
        text = text .. " wrong rank"
    end
    if aura and aura.raidCheckSourceName
        and aura.raidCheckSourceName ~= "" then
        text = text .. ", by " .. aura.raidCheckSourceName
    end
    return text .. ")"
end

local function BuffClickSummary(snapshot, buffKey, report)
    local eligible = EligibleMembers(snapshot, report.classes)
    local correct, wrong, missing = 0, {}, {}
    for _, member in ipairs(eligible) do
        local aura = member.buffs and member.buffs[buffKey]
        if aura and aura.raidCheckLowRank then
            wrong[#wrong + 1] = WrongRankEntry(
                member, aura, report.label)
        elseif aura then
            correct = correct + 1
        else
            missing[#missing + 1] = member
        end
    end

    local lines = {
        ("%s - %d/%d players have the correct rank."):format(
            report.label, correct, #eligible),
    }
    if #wrong > 0 then
        lines[#lines + 1] = "Wrong Rank " .. report.label
            .. ": " .. table.concat(wrong, ", ") .. "."
    end
    lines[#lines + 1] = NameListLine(
        "Missing " .. report.label, missing)
    return lines
end

local function PlayerBuffClickSummary(
        snapshot, member, buffKey, report)
    if report.classes and not report.classes[member.classFile] then
        return {
            ("%s - %s - Group %d, Slot %d - %s is not required "
                .. "for this class."):format(
                MemberDisplayName(member),
                MemberClassLabel(member),
                tonumber(member.subgroup) or 1,
                MemberGroupSlot(snapshot, member),
                report.label),
        }
    end

    local playerName = MemberDisplayName(member)
    local subgroup = tonumber(member.subgroup) or 1
    local groupSlot = MemberGroupSlot(snapshot, member)
    local location = ("%s - %s - Group %d, Slot %d"):format(
        playerName, MemberClassLabel(member), subgroup, groupSlot)
    local aura = member.buffs and member.buffs[buffKey]
    if aura and not aura.raidCheckLowRank then
        return {
            location .. " - Has "
                .. AuraReportName(aura, report.label) .. ".",
        }
    end

    local lines = {}
    if aura then
        local status = "Wrong rank "
            .. AuraReportName(aura, report.label)
        if aura.raidCheckRank and aura.raidCheckMaxRank then
            status = status .. (" (Rank %d/%d)"):format(
                aura.raidCheckRank, aura.raidCheckMaxRank)
        end
        if aura.raidCheckSourceName
            and aura.raidCheckSourceName ~= "" then
            status = status .. ", buffed by "
                .. aura.raidCheckSourceName
        end
        lines[#lines + 1] = location .. " - " .. status .. "."
    else
        lines[#lines + 1] = location
            .. " - Missing " .. report.label .. "."
    end
    lines[#lines + 1] = ("Please buff %s on %s in Group %d, Slot %d."):format(
        report.label, playerName, subgroup, groupSlot)
    return lines
end

local function ReadyClickSummary(members)
    local ready = MembersMatching(members, function(member)
        return member.readyStatus == "ready"
    end)
    local notReady = MembersMatching(members, function(member)
        return member.readyStatus == "notReady"
    end)
    local awaiting = MembersMatching(members, function(member)
        return member.readyStatus ~= "ready"
            and member.readyStatus ~= "notReady"
    end)
    return {
        ("Ready Check - %d/%d players Ready."):format(
            #ready, #members),
        NameListLine("Not Ready", notReady),
        NameListLine("Awaiting Response", awaiting),
    }
end

local function WorldBuffClickSummary(members, oneHourOnly)
    if oneHourOnly then
        local covered = MembersMatching(members, function(member)
            return HasWorldBuff(member, ONE_HOUR_WORLD_BUFFS)
        end)
        return {
            ("1-Hour World Buffs - %d/%d players have at least 1 "
                .. "one-hour World Buff."):format(
                #covered, #members),
        }
    end

    local active = MembersMatching(members, function(member)
        return HasWorldBuff(member)
    end)
    local booned = MembersMatching(members, function(member)
        return HasAuraSpell(member.worldBuffs, 349981)
    end)
    local empty = MembersMatching(members, function(member)
        return not HasWorldBuff(member)
            and not HasAuraSpell(member.worldBuffs, 349981)
    end)
    return {
        ("World Buffs - %d/%d players have at least 1 World Buff."):format(
            #active, #members),
        NameListLine("Booned", booned),
        NameListLine("No World Buffs", empty),
    }
end

local function BattleShoutClickSummary(members, listPlayers)
    local found = MembersMatching(members, function(member)
        return HasMaxRankBuff(member, "attackPower")
    end)
    if listPlayers then
        return {
            NameListLine("Players with Battle Shout", found),
        }
    end
    return {
        ("Battle Shout - %d/%d players have Battle Shout."):format(
            #found, #members),
    }
end

local function DisallowedClickSummary(members)
    local affected = {}
    local foundBySpell = {}
    for _, member in ipairs(members) do
        local memberFound = false
        for _, aura in ipairs(member.disallowed or {}) do
            local spellId = tonumber(aura.spellId)
            if DISALLOWED_AURAS[spellId] then
                foundBySpell[spellId] =
                    foundBySpell[spellId] or {}
                foundBySpell[spellId][
                    #foundBySpell[spellId] + 1] = member
                memberFound = true
            end
        end
        if memberFound then affected[#affected + 1] = member end
    end

    local lines = {
        ("Disqualifying Buffs Found - %d/%d"):format(
            #affected, #members),
    }
    for _, definition in ipairs(DISALLOWED_AURA_DEFINITIONS) do
        local found = foundBySpell[definition.spellId]
        if found and #found > 0 then
            lines[#lines + 1] = definition.name .. " - "
                .. table.concat(SortedNames(found), ", ") .. "."
        end
    end
    if #affected == 0 then
        lines[#lines + 1] =
            "No disqualifying buffs detected."
    end
    return lines
end

local function PresenceClickSummary(
        label, members, hasRequirement, missingLabel, coveredText)
    local found = MembersMatching(members, hasRequirement)
    local missing = MissingMembers(members, hasRequirement)
    return {
        ("%s - %d/%d players %s."):format(
            label, #found, #members, coveredText or "covered"),
        NameListLine(missingLabel or ("Missing " .. label), missing),
    }
end

local function PotionClickSummary(members, spellId)
    spellId = tonumber(spellId)
    local definition = POTION_AURAS[spellId]
    if not definition then return nil end
    return PresenceClickSummary(
        definition.name,
        members,
        function(member)
            return HasAuraSpell(member.potions, spellId)
        end,
        "Missing " .. definition.name,
        "have " .. definition.name)
end

local function ConsumesClickSummary(members)
    local atLeastTwo = MembersMatching(members, function(member)
        return #(member.consumes or {}) >= 2
    end)
    local atLeastOne = MembersMatching(members, function(member)
        return #(member.consumes or {}) >= 1
    end)
    local none = MembersMatching(members, function(member)
        return #(member.consumes or {}) == 0
    end)
    return {
        ("Consumes - %d/%d players have at least 2; %d/%d have "
            .. "at least 1."):format(
                #atLeastTwo, #members, #atLeastOne, #members),
        NameListLine("No Consumes", none),
    }
end

function PRT:BuildRaidCheckClickReport(columnKey, snapshot, options)
    snapshot = snapshot or self:BuildRaidCheckSnapshot()
    options = options or {}
    local members = snapshot.members or {}
    if #members == 0 then
        return PrefixAndSplitChatLines(
            { "No group members found." },
            RAID_CHECK_CLICK_REPORT_PREFIX),
            snapshot
    end

    local lines
    if columnKey == "player" then
        lines = ReadyClickSummary(members)
    elseif columnKey == "worldBuffs" then
        lines = WorldBuffClickSummary(
            members, options.shift == true)
    elseif columnKey == "attackPower" then
        lines = BattleShoutClickSummary(
            members, options.shift == true)
    elseif columnKey == "disallowed" then
        lines = DisallowedClickSummary(members)
    elseif columnKey == "flask" then
        lines = PresenceClickSummary(
            "Flask",
            members,
            function(member) return member.flask ~= nil end,
            "Missing Flask",
            "have a Flask")
    elseif columnKey == "zanza" then
        lines = PresenceClickSummary(
            "Zanza",
            members,
            function(member)
                return #(member.zanza or {}) > 0
            end,
            "Missing Zanza",
            "have a Zanza buff")
    elseif columnKey == "potions" then
        lines = PotionClickSummary(
            members, options.spellId)
    elseif columnKey == "consumes" then
        lines = ConsumesClickSummary(members)
    elseif columnKey == "durability" then
        lines = DurabilitySummary(snapshot)
    else
        local buffReport = CLICK_BUFF_REPORTS[columnKey]
        if buffReport then
            if options.shift and options.member then
                lines = PlayerBuffClickSummary(
                    snapshot,
                    options.member,
                    columnKey,
                    buffReport)
            else
                lines = BuffClickSummary(
                    snapshot, columnKey, buffReport)
            end
        end
    end

    if not lines then return nil, snapshot end
    return PrefixAndSplitChatLines(
        lines, RAID_CHECK_CLICK_REPORT_PREFIX),
        snapshot
end

function PRT:SendRaidCheckClickReport(columnKey, snapshot, options)
    options = options or {}
    if columnKey == "durability"
        and not options._durabilityRefreshed
        and not (snapshot and snapshot.preview) then
        self:RequestRaidCheckDurability()
        if C_Timer and C_Timer.After then
            local nextOptions = {}
            for key, value in pairs(options) do
                nextOptions[key] = value
            end
            nextOptions._durabilityRefreshed = true
            C_Timer.After(0.75, function()
                self:SendRaidCheckClickReport(
                    columnKey,
                    self:BuildRaidCheckSnapshot(),
                    nextOptions)
            end)
            return true
        end
    end

    local lines = self:BuildRaidCheckClickReport(
        columnKey, snapshot, options)
    if not lines then return false end

    -- The generated Test Preview never sends fabricated preparation results
    -- to group chat. Its click reports remain available locally for UI tests.
    if snapshot and snapshot.preview then
        for _, line in ipairs(lines) do self.Print(line) end
        return true
    end

    local channel = GetReportChannel()
    if not channel then
        for _, line in ipairs(lines) do self.Print(line) end
        self.Print(
            "Raid Check report printed locally because you are not grouped.")
        return true
    end

    local sent = false
    for _, line in ipairs(lines) do
        sent = SendChat(line, channel) or sent
    end
    return sent
end

function PRT:BuildRaidCheckChatCommandResponse(commandText, snapshot)
    local normalized = string.lower(self.Trim(commandText or ""))
    local command = RAID_CHECK_CHAT_COMMAND_BY_ALIAS[normalized]
    if not command then return nil end
    snapshot = snapshot or self:BuildRaidCheckSnapshot()
    return PrefixAndSplitChatLines(
        BuildRaidCheckChatCommandBody(command, snapshot)),
        snapshot,
        command
end

function PRT:SendRaidCheckChatCommandResponse(commandText, channel)
    local lines = self:BuildRaidCheckChatCommandResponse(commandText)
    if not lines then return false end
    local sent = false
    for _, line in ipairs(lines) do
        sent = SendChat(line, channel) or sent
    end
    return sent
end

local function IsOwnRaidCheckChatSender(owner, sender)
    local ownKey = owner:GetUnitIdentityKey("player")
    local senderKey = owner:GetPlayerIdentityKey(sender)
    return ownKey ~= "" and senderKey == ownKey
end

function PRT:HandleRaidCheckChatMessage(event, message, sender)
    local channel = RAID_CHECK_CHAT_CHANNELS[event]
    if not channel or not IsOwnRaidCheckChatSender(self, sender) then
        return false
    end
    local normalized = string.lower(self.Trim(message or ""))
    local command = RAID_CHECK_CHAT_COMMAND_BY_ALIAS[normalized]
    if not command then return false end

    local function Respond()
        PRT:SendRaidCheckChatCommandResponse(normalized, channel)
    end
    if command.key == "durability" then
        self:RequestRaidCheckDurability()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.75, Respond)
        else
            Respond()
        end
    else
        Respond()
    end
    return true
end

function PRT:RunRaidCheckReport(checkType, toChat)
    local lines, snapshot = self:BuildRaidCheckReport(checkType or "all")
    local channel = toChat and GetReportChannel() or nil
    for _, line in ipairs(lines) do
        if channel then
            SendChat(line, channel)
        else
            PRT.Print(line)
        end
    end
    if toChat and not channel then
        PRT.Print("Raid Check report printed locally because you are not grouped.")
    end
    return snapshot
end

local function AddonMessageAPI()
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage
    end
    return SendAddonMessage
end

local function GetAddonDistribution()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

function PRT:StoreRaidCheckDurability(identityKey, percent)
    percent = tonumber(percent)
    if not identityKey or identityKey == "" or not percent then return end
    percent = math.max(0, math.min(100, percent))
    self._raidCheckDurability = self._raidCheckDurability or {}
    self._raidCheckDurability[identityKey] = {
        percent = percent,
        receivedAt = Now(),
    }
end

function PRT:RequestRaidCheckDurability()
    local ownKey = self:GetUnitIdentityKey("player")
    if ownKey ~= "" then
        self:StoreRaidCheckDurability(ownKey, self:CalculatePlayerDurability())
    end

    local distribution = GetAddonDistribution()
    local send = AddonMessageAPI()
    if not distribution or not send then return end
    self._raidCheckRequestSerial = (self._raidCheckRequestSerial or 0) + 1
    local requestId = tostring(self._raidCheckRequestSerial)
    self._raidCheckLatestRequest = requestId
    send(ADDON_PREFIX, "Q:" .. requestId, distribution)
end

function PRT:HandleRaidCheckAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX or type(message) ~= "string" then return end
    if channel ~= "RAID" and channel ~= "PARTY"
        and channel ~= "INSTANCE_CHAT" then
        return
    end

    local requestId = message:match("^Q:(%d+)$")
    if requestId then
        local send = AddonMessageAPI()
        local distribution = channel == "INSTANCE_CHAT"
            and "INSTANCE_CHAT" or GetAddonDistribution()
        local durability = self:CalculatePlayerDurability()
        if send and distribution and durability then
            send(ADDON_PREFIX,
                ("R:%s:%.1f"):format(requestId, durability), distribution)
        end
        return
    end

    local responseId, percent = message:match("^R:(%d+):([%d%.]+)$")
    if not responseId or not percent then return end
    local identityKey = self:GetPlayerIdentityKey(sender)
    self:StoreRaidCheckDurability(identityKey, percent)
    self:RequestRaidCheckUIRefresh()
end

function PRT:RequestRaidCheckUIRefresh()
    if self._raidCheckRefreshPending then return end
    self._raidCheckRefreshPending = true
    local function Refresh()
        PRT._raidCheckRefreshPending = nil
        if PRT.RefreshRaidCheckWindow then PRT:RefreshRaidCheckWindow() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, Refresh)
    else
        Refresh()
    end
end

local function ResolveReadyIdentity(unitOrName)
    if not unitOrName then return "" end
    if UnitExists and UnitExists(unitOrName) then
        return PRT:GetUnitIdentityKey(unitOrName)
    end
    return PRT:GetPlayerIdentityKey(unitOrName)
end

function PRT:CanShowAutomaticRaidCheck()
    local cfg = self:GetDB().raidCheck or {}
    if not cfg.onlyLeaderAssist then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player"))
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or false
end

function PRT:HandleRaidCheckRTSlash(message, fallback)
    local rawMessage = self.Trim(message or "")
    local normalized = string.lower(rawMessage):gsub("%s+", " ")
    if normalized == "check" then
        if self.ToggleRaidCheckWindow then self:ToggleRaidCheckWindow() end
        return true
    end
    if fallback then
        fallback(message)
    else
        self.Print("Usage: /rt check")
    end
    return false
end

function PRT:InstallRaidCheckRTSlash()
    if self._raidCheckRTSlashInstalled then return end
    SlashCmdList = SlashCmdList or {}

    local handlerKey, existingHandler
    for globalName, slashCommand in pairs(_G or {}) do
        if type(globalName) == "string"
            and type(slashCommand) == "string"
            and string.lower(slashCommand) == "/rt" then
            local key = globalName:match("^SLASH_(.-)%d+$")
            local handler = key and SlashCmdList[key]
            if handler and key ~= "PRTRAIDCHECK" then
                handlerKey, existingHandler = key, handler
                break
            end
        end
    end

    if handlerKey and existingHandler then
        SlashCmdList[handlerKey] = function(message)
            return PRT:HandleRaidCheckRTSlash(message, existingHandler)
        end
        self._raidCheckRTSlashHandlerKey = handlerKey
    else
        _G.SLASH_PRTRAIDCHECK1 = "/rt"
        SlashCmdList["PRTRAIDCHECK"] = function(message)
            return PRT:HandleRaidCheckRTSlash(message)
        end
        self._raidCheckRTSlashHandlerKey = "PRTRAIDCHECK"
    end
    self._raidCheckRTSlashInstalled = true
end

function PRT:HandleRaidCheckStarted(starter, timeout)
    local duration = tonumber(timeout) or DEFAULT_READY_CHECK_DURATION
    if duration <= 0 then duration = DEFAULT_READY_CHECK_DURATION end
    self._raidCheckActive = true
    self._raidCheckReadySerial = (self._raidCheckReadySerial or 0) + 1
    self._raidCheckStartedAt = Now()
    self._raidCheckDuration = duration
    self._raidCheckDeadline = self._raidCheckStartedAt + duration
    self._raidCheckReadyStatus = {}
    for _, member in ipairs(self:GetRaidCheckMembers()) do
        self._raidCheckReadyStatus[member.identityKey] = "waiting"
    end

    local starterKey = ResolveReadyIdentity(starter)
    if starterKey ~= "" then self._raidCheckReadyStatus[starterKey] = "ready" end
    self:RequestRaidCheckDurability()

    local cfg = self:GetDB().raidCheck or {}
    if cfg.showOnReadyCheck ~= false and self:CanShowAutomaticRaidCheck()
        and self.ShowRaidCheckWindow then
        self:ShowRaidCheckWindow({
            source = "readyCheck",
            timeout = duration,
        })
    end

    local serial = self._raidCheckReadySerial
    if C_Timer and C_Timer.After then
        C_Timer.After(duration, function()
            if PRT._raidCheckActive and PRT._raidCheckReadySerial == serial then
                PRT:HandleRaidCheckFinished()
            end
        end)
    end
end

function PRT:HandleRaidCheckConfirmation(unit, response)
    local identityKey = ResolveReadyIdentity(unit)
    if identityKey == "" then return end
    self._raidCheckReadyStatus = self._raidCheckReadyStatus or {}
    self._raidCheckReadyStatus[identityKey] =
        response == true and "ready"
        or response == false and "notReady"
        or "waiting"
    self:RequestRaidCheckUIRefresh()
end

function PRT:HandleRaidCheckFinished()
    local serial = self._raidCheckReadySerial or 0
    if self._raidCheckFinishedSerial == serial then return end
    self._raidCheckFinishedSerial = serial
    self._raidCheckActive = false
    self._raidCheckFinishedAt = Now()
    if self.FinishRaidCheckWindow then
        self:FinishRaidCheckWindow(serial)
    end
    self:RequestRaidCheckUIRefresh()
end

function PRT:InitRaidCheck()
    if self._raidCheckEventFrame then return end
    self._raidCheckDurability = self._raidCheckDurability or {}
    self._raidCheckReadyStatus = self._raidCheckReadyStatus or {}

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(ADDON_PREFIX)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("READY_CHECK")
    frame:RegisterEvent("READY_CHECK_CONFIRM")
    frame:RegisterEvent("READY_CHECK_FINISHED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("CHAT_MSG_RAID")
    frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    frame:RegisterEvent("CHAT_MSG_PARTY")
    frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
    frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "READY_CHECK" then
            PRT:HandleRaidCheckStarted(...)
        elseif event == "READY_CHECK_CONFIRM" then
            PRT:HandleRaidCheckConfirmation(...)
        elseif event == "READY_CHECK_FINISHED" then
            PRT:HandleRaidCheckFinished()
        elseif event == "CHAT_MSG_ADDON" then
            PRT:HandleRaidCheckAddonMessage(...)
        elseif RAID_CHECK_CHAT_CHANNELS[event] then
            PRT:HandleRaidCheckChatMessage(event, ...)
        elseif event == "PLAYER_LOGIN" then
            PRT:InstallRaidCheckRTSlash()
        else
            PRT:RequestRaidCheckUIRefresh()
        end
    end)
    self._raidCheckEventFrame = frame
    self:InstallRaidCheckRTSlash()
end
