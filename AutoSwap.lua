---------------------------------------------------------------------------
-- PugzRaidTools - Auto Swap
-- Tracks NPC kills via COMBAT_LOG_EVENT_UNFILTERED and fires composition
-- swaps based on user-configured triggers.
--
-- Performance: CLEU is only registered when ALL of these are true:
--   1. auto-swap is enabled
--   2. player is in a raid group
--   3. player is in a matching instance (or the preset's allowAnywhere is set)
--   4. at least one trigger in the active preset is enabled
-- The listener is unregistered as soon as any condition becomes false.
---------------------------------------------------------------------------
local _, PRT = ...

function PRT:InitAutoSwap()
    local db = self:GetDB()

    -- Migrate legacy flat triggers into a "Default" preset, or create one
    if not db.autoSwap.swapPresets or #db.autoSwap.swapPresets == 0 then
        db.autoSwap.swapPresets = db.autoSwap.swapPresets or {}
        if db.autoSwap.triggers and #db.autoSwap.triggers > 0 then
            -- Migrate existing triggers to a Default preset
            db.autoSwap.swapPresets[1] = {
                name     = "Default",
                triggers = db.autoSwap.triggers,
            }
            db.autoSwap.triggers = {}
        else
            -- Fresh install: create empty Default preset
            db.autoSwap.swapPresets[1] = { name = "Default", triggers = {} }
        end
        db.autoSwap.activeSwapPreset = "Default"
    end

    -- Migrate global instanceId/allowAnywhere to per-preset (one-time), and
    -- ensure all new per-preset fields exist on every preset.
    local legacyInstanceId    = db.autoSwap.instanceId or 0
    local legacyAllowAnywhere = db.autoSwap.allowAnywhere or false
    for _, preset in ipairs(db.autoSwap.swapPresets) do
        if preset.instanceId == nil then
            preset.instanceId = legacyInstanceId
        end
        if preset.allowAnywhere == nil then
            preset.allowAnywhere = legacyAllowAnywhere
        end
        if preset.resetOnZoneOut == nil then
            preset.resetOnZoneOut = false
        end
        if preset.resetOnDeath == nil then
            preset.resetOnDeath = { npcId = 0, count = 1, note = "" }
        end
        -- Kill counters are runtime-only (never persisted in SavedVariables)
        preset.killCounters = {}
    end

    self.autoFrame = CreateFrame("Frame")
    self.autoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.autoFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.autoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.autoFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    self.autoFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then
            PRT:TryReorder()
        end
        if event == "ZONE_CHANGED_NEW_AREA" then
            PRT:CheckZoneOutReset()
        end
        -- Re-evaluate whether we should listen to CLEU
        PRT:UpdateAutoSwapListeners()
        -- Also update the floating list visibility
        if PRT.UpdateFloatingList then PRT:UpdateFloatingList() end
    end)

    self:UpdateAutoSwapListeners()
end

---------------------------------------------------------------------------
-- Listener management
---------------------------------------------------------------------------
function PRT:UpdateAutoSwapListeners()
    if not self.autoFrame then return end
    local db = self:GetDB()

    local preset        = self:GetActiveSwapPreset()
    local allowAnywhere = preset and preset.allowAnywhere or false
    local locationOk    = allowAnywhere or (IsInRaid() and self:IsInMatchingInstance())

    local shouldListen = false
    if db.autoSwap.enabled and locationOk then
        if preset then
            for _, trigger in ipairs(preset.triggers) do
                if trigger.enabled then
                    shouldListen = true
                    break
                end
            end
        end
    end

    if shouldListen then
        PRT:RegisterCLEUListener("autoswap", function() PRT:OnCombatLog() end)
    else
        PRT:UnregisterCLEUListener("autoswap")
    end
end

function PRT:IsInMatchingInstance()
    local preset   = self:GetActiveSwapPreset()
    local filterId = (preset and preset.instanceId) or 0
    if filterId == 0 then return true end

    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return instanceMapID == filterId
end

---------------------------------------------------------------------------
-- Zone-out kill counter reset
-- Called on ZONE_CHANGED_NEW_AREA. Resets counters when the player leaves
-- the instance the active preset is locked to (if resetOnZoneOut is set).
---------------------------------------------------------------------------
function PRT:CheckZoneOutReset()
    local preset = self:GetActiveSwapPreset()
    if not preset then return end
    if not preset.resetOnZoneOut then return end
    local instanceId = preset.instanceId or 0
    if instanceId == 0 then return end   -- "Any Raid" — no specific zone to leave

    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    if instanceMapID ~= instanceId then
        -- Only print if there's actually something to reset
        if next(preset.killCounters or {}) then
            preset.killCounters = {}
            local instName = PRT.RAID_INSTANCE_MAP[instanceId] or tostring(instanceId)
            PRT.Print("Kill counters reset (left " .. instName .. ").")
        end
    end
end

---------------------------------------------------------------------------
-- Combat log handler (only runs when CLEU is registered)
---------------------------------------------------------------------------
function PRT:OnCombatLog()
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent ~= "UNIT_DIED" then return end

    local npcId = PRT.GetNpcId(destGUID)
    if not npcId then return end

    local preset = self:GetActiveSwapPreset()
    if not preset then return end

    preset.killCounters         = preset.killCounters or {}
    preset.killCounters[npcId]  = (preset.killCounters[npcId] or 0) + 1
    local count                 = preset.killCounters[npcId]

    -- Check regular swap triggers
    for _, trigger in ipairs(preset.triggers) do
        if trigger.enabled and trigger.npcId == npcId then
            local threshold = trigger.count or 1
            if trigger.repeating then
                if count > 0 and (count % threshold) == 0 then
                    PRT.Print(("Auto-swap [repeat]: %s (NPC %d x%d)"):format(
                        trigger.compName, npcId, count))
                    self:RequestReorder(trigger.compName)
                    break
                end
            else
                if count == threshold then
                    PRT.Print(("Auto-swap: %s (NPC %d x%d)"):format(
                        trigger.compName, npcId, count))
                    self:RequestReorder(trigger.compName)
                    break
                end
            end
        end
    end

    -- Check reset-on-death trigger (resets all counters every N kills of the NPC)
    -- Evaluated after swap triggers so a swap can still fire before the reset.
    local rod = preset.resetOnDeath
    if rod and (rod.npcId or 0) > 0 and rod.npcId == npcId then
        local threshold = rod.count or 1
        if count > 0 and (count % threshold) == 0 then
            preset.killCounters = {}
            local noteStr = (rod.note and rod.note ~= "") and (" [" .. rod.note .. "]") or ""
            PRT.Print("Kill counters reset by NPC death" .. noteStr .. ".")
        end
    end
end

---------------------------------------------------------------------------
-- Kill counter reset (active preset only)
---------------------------------------------------------------------------
function PRT:ResetKillCounters()
    local preset = self:GetActiveSwapPreset()
    if preset then
        preset.killCounters = {}
        PRT.Print("Kill counters reset for preset '" .. preset.name .. "'.")
    else
        PRT.Print("No active preset.")
    end
end
