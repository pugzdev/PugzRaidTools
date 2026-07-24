---------------------------------------------------------------------------
-- PugzRaidTools - Auto Marking Engine
-- Automatically applies raid marks to players based on NPC death events
-- or group swap triggers.  Each preset contains mark groups with their
-- own trigger logic and mark assignments.
--
-- Mark application uses SetRaidTarget("raidN", icon) which works in
-- combat and only requires leader/assistant.
---------------------------------------------------------------------------
local _, PRT = ...

PRT._autoMarkKills = {}   -- [npcId] = cumulative kill count (independent from AutoSwap)
PRT._autoMarkFired = {}   -- [key]   = true  (tracks which mark groups have fired)

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
function PRT:InitAutoMark()
    local db = self:GetDB()
    if db.autoMark and db.autoMark.presets then
        for _, preset in ipairs(db.autoMark.presets) do
            self:EnsureAutoMarkPresetDefaults(preset)
        end
    end

    self._autoMarkFrame = CreateFrame("Frame")
    self._autoMarkFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self._autoMarkFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self._autoMarkFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self._autoMarkFrame:SetScript("OnEvent", function()
        PRT:UpdateAutoMarkListeners()
    end)
    self:UpdateAutoMarkListeners()
end

---------------------------------------------------------------------------
-- Listener management — register/unregister from shared CLEU dispatcher
---------------------------------------------------------------------------
function PRT:UpdateAutoMarkListeners()
    local db = self:GetDB()
    local am = db.autoMark
    if not am then return end

    local shouldListen = false
    if am.enabled and am.activePreset ~= "" then
        local preset = self:GetAutoMarkPreset(am.activePreset)
        if preset and self:IsAutoMarkPresetLocationAllowed(preset) then
            for _, mg in ipairs(preset.markGroups) do
                if #mg.npcTriggers > 0 then
                    shouldListen = true
                    break
                end
            end
        end
    end

    if shouldListen then
        PRT:RegisterCLEUListener("automark", function() PRT:OnAutoMarkCombatLog() end)
    else
        PRT:UnregisterCLEUListener("automark")
    end
end

---------------------------------------------------------------------------
-- Preset helpers
---------------------------------------------------------------------------
function PRT:GetAutoMarkPreset(name)
    if not name or name == "" then return nil end
    local db = self:GetDB()
    for _, p in ipairs(db.autoMark.presets) do
        if p.name == name then return p end
    end
end

function PRT:EnsureAutoMarkPresetDefaults(preset)
    if not preset then return end
    if preset.instanceId == nil then preset.instanceId = 0 end
    if preset.allowAnywhere == nil then preset.allowAnywhere = false end
    preset.markGroups = preset.markGroups or {}
end

function PRT:IsAutoMarkPresetLocationAllowed(preset)
    if not preset then return false end
    if preset.allowAnywhere then return true end
    if not IsInRaid() then return false end

    local filterId = preset.instanceId or 0
    if filterId == 0 then return true end

    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return instanceMapID == filterId
end

---------------------------------------------------------------------------
-- CLEU callback — fast-path exit for non-death events
---------------------------------------------------------------------------
function PRT:OnAutoMarkCombatLog()
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent ~= "UNIT_DIED" then return end

    local npcId = PRT.GetNpcId(destGUID)
    if not npcId then return end

    local db = self:GetDB()
    local am = db.autoMark
    local preset = self:GetAutoMarkPreset(am.activePreset)
    if not preset then return end
    if not self:IsAutoMarkPresetLocationAllowed(preset) then return end

    self._autoMarkKills[npcId] = (self._autoMarkKills[npcId] or 0) + 1

    for _, mg in ipairs(preset.markGroups) do
        self:EvaluateMarkGroupNPCTriggers(mg, npcId, am.activePreset)
    end
end

---------------------------------------------------------------------------
-- NPC trigger evaluation
---------------------------------------------------------------------------
function PRT:EvaluateMarkGroupNPCTriggers(mg, killedNpcId, presetName)
    local key = presetName .. ":" .. mg.name

    -- Already fired and not repeatable? Skip
    if self._autoMarkFired[key] and not mg.repeatable then return end

    -- Does this mark group care about the NPC that just died?
    local relevant = false
    for _, trigger in ipairs(mg.npcTriggers) do
        if trigger.npcId == killedNpcId then
            relevant = true
            break
        end
    end
    if not relevant then return end

    -- Evaluate trigger requirements (Any / All / Conditional)
    if not self:CheckTriggerRequirements(mg) then return end

    self._autoMarkFired[key] = true
    PRT.Print(("Auto Mark: %s / %s triggered"):format(presetName, mg.name))

    -- Reset kill counters for triggers that reached their threshold.
    -- Subtract the threshold rather than zeroing so excess kills carry forward.
    -- Example: count=2, kills=3 when fired → counter becomes 1, meaning one
    -- kill is already "banked" toward the next repeat cycle.
    -- In "all" mode, all triggers will have met threshold at this point.
    -- In "any" mode, only the trigger(s) that reached threshold are subtracted.
    for _, trigger in ipairs(mg.npcTriggers) do
        local kills     = self._autoMarkKills[trigger.npcId] or 0
        local threshold = trigger.count or 1
        if kills >= threshold then
            self._autoMarkKills[trigger.npcId] = kills - threshold
        end
    end

    -- 1-second delay before applying marks (matches WeakAura behaviour)
    C_Timer.After(1.0, function()
        local preset = PRT:GetAutoMarkPreset(presetName)
        if preset and PRT:IsAutoMarkPresetLocationAllowed(preset) then
            PRT:ApplyMarkGroup(mg)
        end
    end)
end

---------------------------------------------------------------------------
-- Group swap trigger — called from Reorder.lua after a comp is applied
---------------------------------------------------------------------------
function PRT:OnGroupSwapForAutoMark(compName)
    local db = self:GetDB()
    local am = db.autoMark
    if not am or not am.enabled or am.activePreset == "" then return end

    local preset = self:GetAutoMarkPreset(am.activePreset)
    if not preset then return end
    if not self:IsAutoMarkPresetLocationAllowed(preset) then return end

    for _, mg in ipairs(preset.markGroups) do
        for _, st in ipairs(mg.swapTriggers) do
            if st.compName == compName then
                local key = am.activePreset .. ":" .. mg.name .. ":swap:" .. compName
                if not self._autoMarkFired[key] or mg.repeatable then
                    self._autoMarkFired[key] = true
                    PRT.Print(("Auto Mark: %s / %s (swap: %s)"):format(
                        am.activePreset, mg.name, compName))
                    local presetName = am.activePreset
                    C_Timer.After(1.0, function()
                        local activePreset = PRT:GetAutoMarkPreset(presetName)
                        if activePreset and PRT:IsAutoMarkPresetLocationAllowed(activePreset) then
                            PRT:ApplyMarkGroup(mg)
                        end
                    end)
                end
                break
            end
        end
    end
end

---------------------------------------------------------------------------
-- Trigger requirement logic (Any / All / Conditional)
---------------------------------------------------------------------------
function PRT:CheckTriggerRequirements(mg)
    local mode    = mg.triggerMode or "any"
    local triggers = mg.npcTriggers

    if mode == "any" then
        for _, trigger in ipairs(triggers) do
            local count = self._autoMarkKills[trigger.npcId] or 0
            if count >= (trigger.count or 1) then
                return true
            end
        end
        return false

    elseif mode == "all" then
        if #triggers == 0 then return false end
        for _, trigger in ipairs(triggers) do
            local count = self._autoMarkKills[trigger.npcId] or 0
            if count < (trigger.count or 1) then
                return false
            end
        end
        return true

    elseif mode == "conditional" then
        for _, cond in ipairs(mg.conditionals or {}) do
            local met = false
            for _, trigger in ipairs(triggers) do
                if trigger.name == cond.triggerName then
                    local count = self._autoMarkKills[trigger.npcId] or 0
                    met = count >= (trigger.count or 1)
                    break
                end
            end
            -- Legacy migration: old data used mustBeTrue=false as "must be false"
            local mustTrue  = cond.mustBeTrue or false
            local mustFalse = cond.mustBeFalse
            if mustFalse == nil then mustFalse = not mustTrue end
            if mustTrue  and not met then return false end
            if mustFalse and met     then return false end
        end
        return true
    end

    return false
end

---------------------------------------------------------------------------
-- Apply marks
---------------------------------------------------------------------------
function PRT:ApplyMarkGroup(mg)
    if not IsInRaid() then return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        PRT.Print("Auto Mark: must be leader or assistant to set marks.")
        return
    end

    -- Optionally clear all marks first
    if mg.unmarkAll then
        local n = GetNumGroupMembers()
        for i = 1, n do
            SetRaidTarget("raid" .. i, 0)
        end
    end

    local applyOn = mg.applyOn or "name"

    for _, mark in ipairs(mg.marks) do
        if mark.icon and mark.icon >= 0 and mark.icon <= 8 then
            if applyOn == "name" then
                self:ApplyMarkByName(mark)
            elseif applyOn == "position" then
                if mg.smartAssign and mg.smartComp and mg.smartComp ~= "" then
                    self:ApplyMarkBySmartPosition(mark, mg.smartComp)
                else
                    self:ApplyMarkByPosition(mark)
                end
            end
        end
    end
end

--- Player Name mode: find the named player in the raid and mark them.
function PRT:ApplyMarkByName(mark)
    if not mark.playerName or mark.playerName == "" then return end
    local canon = PRT.CanonName(mark.playerName)
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name = GetRaidRosterInfo(i)
        if name and PRT.CanonName(name) == canon then
            SetRaidTarget("raid" .. i, mark.icon)
            return
        end
    end
end

--- Raid Position mode (no Smart Assign): position maps directly to raid index.
function PRT:ApplyMarkByPosition(mark)
    local pos = mark.position or 0
    if pos < 1 or pos > 40 then return end
    local n = GetNumGroupMembers()
    if pos > n then return end
    SetRaidTarget("raid" .. pos, mark.icon)
end

--- Raid Position + Smart Assign: look up the player name from the
--- saved composition at the given position, then find that player
--- in the raid by name (stable across re-sorts).
function PRT:ApplyMarkBySmartPosition(mark, compName)
    local comp = self:GetComp(compName)
    if not comp then
        -- Fallback to direct position
        self:ApplyMarkByPosition(mark)
        return
    end

    local pos = mark.position or 0
    if pos < 1 or pos > 40 then return end

    local targetName = comp.roster[pos]
    if not targetName or targetName == "" then return end

    local canon = PRT.CanonName(targetName)
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name = GetRaidRosterInfo(i)
        if name and PRT.CanonName(name) == canon then
            SetRaidTarget("raid" .. i, mark.icon)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Kill counter / fired-state reset
---------------------------------------------------------------------------
function PRT:ResetAutoMarkCounters()
    wipe(self._autoMarkKills)
    wipe(self._autoMarkFired)
    PRT.Print("Auto Mark counters reset.")
end
