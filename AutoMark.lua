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
PRT._autoMarkRetryJobs = {}

local AUTO_MARK_RETRY_INTERVAL = 0.25
local AUTO_MARK_VERIFY_DELAY   = 0.45
local AUTO_MARK_POST_SWAP_DELAY = 0.30
local AUTO_MARK_DEFAULT_RETRY_DURATION = 3
local AUTO_MARK_MAX_RETRY_DURATION = 10

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
    for _, mg in ipairs(preset.markGroups) do
        self:EnsureAutoMarkRuleDefaults(mg)
    end
end

function PRT:EnsureAutoMarkRuleDefaults(mg)
    if not mg then return end
    if mg.retryUnavailable == nil then mg.retryUnavailable = false end
    mg.retryDuration = tonumber(mg.retryDuration) or AUTO_MARK_DEFAULT_RETRY_DURATION
    mg.retryDuration = math.max(1, math.min(AUTO_MARK_MAX_RETRY_DURATION, mg.retryDuration))
    mg.marks = mg.marks or {}
    mg.npcTriggers = mg.npcTriggers or {}
    mg.swapTriggers = mg.swapTriggers or {}
    mg.conditionals = mg.conditionals or {}
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
            PRT:ApplyMarkGroup(mg, {
                presetName = presetName,
                queueKey = key,
            })
        end
    end)
end

---------------------------------------------------------------------------
-- Group swap trigger - called by Reorder.lua before and after a comp is applied
---------------------------------------------------------------------------
function PRT:BeginGroupSwapAutoMark(compName)
    local db = self:GetDB()
    local am = db.autoMark
    if not am or not am.enabled or am.activePreset == "" then return end

    local preset = self:GetAutoMarkPreset(am.activePreset)
    if not preset then return end
    if not self:IsAutoMarkPresetLocationAllowed(preset) then return end

    local applications = {}
    for _, mg in ipairs(preset.markGroups) do
        for _, st in ipairs(mg.swapTriggers) do
            if st.compName == compName then
                local key = am.activePreset .. ":" .. mg.name .. ":swap:" .. compName
                if not self._autoMarkFired[key] or mg.repeatable then
                    self._autoMarkFired[key] = true
                    PRT.Print(("Auto Mark: %s / %s (swap: %s)"):format(
                        am.activePreset, mg.name, compName))

                    self:EnsureAutoMarkRuleDefaults(mg)
                    local application = self:CreateAutoMarkApplication(mg, {
                        presetName = am.activePreset,
                        queueKey = key,
                    })
                    applications[#applications + 1] = application

                    -- Raw raid-index rules only have meaning after the reorder.
                    if application.stableTargets then
                        self:ApplyAutoMarkApplication(application, {
                            clear = true,
                            queue = false,
                        })
                    end
                end
                break
            end
        end
    end

    return applications
end

function PRT:FinishGroupSwapAutoMark(applications)
    if not applications or #applications == 0 then return end

    C_Timer.After(AUTO_MARK_POST_SWAP_DELAY, function()
        for _, application in ipairs(applications) do
            local preset = PRT:GetAutoMarkPreset(application.presetName)
            if preset and PRT:IsAutoMarkPresetLocationAllowed(preset) then
                -- A successful pre-swap observation must be checked again after
                -- the roster changes, but the clear step remains one-shot.
                for _, assignment in ipairs(application.assignments) do
                    assignment.complete = nil
                end
                PRT:ApplyAutoMarkApplication(application, {
                    clear = not application.cleared,
                    queue = application.mg.retryUnavailable,
                    rebuild = not application.stableTargets,
                })
            end
        end
    end)
end

-- Compatibility path for callers that do not support the explicit pre/post API.
function PRT:OnGroupSwapForAutoMark(compName)
    self:FinishGroupSwapAutoMark(self:BeginGroupSwapAutoMark(compName))
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
local function AutoMarkNow()
    return GetTime and GetTime() or 0
end

local function IsValidMarkIcon(icon)
    return icon and icon >= 0 and icon <= 8
end

function PRT:IsAutoMarkUnitAddressable(unit)
    if not unit then return false end
    if UnitExists and not UnitExists(unit) then return false end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    return true
end

function PRT:BuildAutoMarkAssignments(mg)
    local assignments = {}
    local assignmentIndexByIcon = {}
    local applyOn = mg.applyOn or "name"
    local smartComp
    if applyOn == "position" and mg.smartAssign and mg.smartComp and mg.smartComp ~= "" then
        smartComp = self:GetComp(mg.smartComp)
    end
    local stableTargets = applyOn == "name" or smartComp ~= nil

    for _, mark in ipairs(mg.marks or {}) do
        local icon = tonumber(mark.icon)
        if IsValidMarkIcon(icon) then
            local assignment = {
                icon = icon,
                sourceName = mark.playerName or "",
                position = tonumber(mark.position) or 0,
            }

            if applyOn == "name" then
                if assignment.sourceName ~= "" then
                    assignment.identityKey = self:GetPlayerIdentityKey(assignment.sourceName)
                end
            elseif smartComp then
                local targetName = smartComp.roster[assignment.position]
                if targetName and targetName ~= "" then
                    assignment.sourceName = targetName
                    assignment.identityKey = self:GetPlayerIdentityKey(targetName)
                end
            elseif assignment.position >= 1 and assignment.position <= 40 then
                assignment.raidPosition = assignment.position
            end

            if assignment.identityKey or assignment.raidPosition then
                local existingIndex = icon ~= 0 and assignmentIndexByIcon[icon]
                if existingIndex then
                    -- A raid icon can only belong to one unit. Preserve the
                    -- old sequential behavior where the last row wins.
                    assignments[existingIndex] = assignment
                else
                    assignments[#assignments + 1] = assignment
                    if icon ~= 0 then
                        assignmentIndexByIcon[icon] = #assignments
                    end
                end
            end
        end
    end

    return assignments, stableTargets
end

function PRT:CreateAutoMarkApplication(mg, opts)
    opts = opts or {}
    self:EnsureAutoMarkRuleDefaults(mg)
    local assignments, stableTargets = self:BuildAutoMarkAssignments(mg)
    return {
        mg = mg,
        presetName = opts.presetName,
        queueKey = opts.queueKey or tostring(mg),
        assignments = assignments,
        stableTargets = stableTargets,
        cleared = false,
    }
end

function PRT:ResolveAutoMarkAssignmentUnit(assignment)
    if assignment.identityKey then
        return self:FindRaidUnitByIdentityKey(assignment.identityKey)
    end
    if assignment.raidPosition
        and assignment.raidPosition <= GetNumGroupMembers() then
        return "raid" .. assignment.raidPosition, assignment.raidPosition
    end
end

function PRT:ClearAddressableRaidMarks()
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if self:IsAutoMarkUnitAddressable(unit) and GetRaidTargetIndex(unit) then
            SetRaidTarget(unit, 0)
        end
    end
end

function PRT:TryAutoMarkAssignment(assignment)
    local unit = self:ResolveAutoMarkAssignmentUnit(assignment)

    if not self:IsAutoMarkUnitAddressable(unit) then
        return false
    end

    local observed = GetRaidTargetIndex(unit) or 0
    if observed == assignment.icon then
        assignment.complete = true
        assignment.awaitingVerification = nil
        return true
    end

    local now = AutoMarkNow()
    if assignment.awaitingVerification
        and (now - (assignment.lastAttempt or 0)) < AUTO_MARK_VERIFY_DELAY then
        return false
    end

    SetRaidTarget(unit, assignment.icon)
    assignment.awaitingVerification = true
    assignment.lastAttempt = now
    return false
end

function PRT:StartAutoMarkRetryQueue(application)
    local pending = false
    for _, assignment in ipairs(application.assignments) do
        if not assignment.complete then
            pending = true
            break
        end
    end
    if not pending then return end

    local duration = tonumber(application.mg.retryDuration) or AUTO_MARK_DEFAULT_RETRY_DURATION
    duration = math.max(1, math.min(AUTO_MARK_MAX_RETRY_DURATION, duration))

    self._autoMarkRetrySerial = (self._autoMarkRetrySerial or 0) + 1
    local serial = self._autoMarkRetrySerial
    local queueKey = application.queueKey
    local deadline = AutoMarkNow() + duration
    self._autoMarkRetryJobs[queueKey] = serial

    local function Finish()
        if PRT._autoMarkRetryJobs[queueKey] == serial then
            PRT._autoMarkRetryJobs[queueKey] = nil
        end
    end

    local function Retry()
        if PRT._autoMarkRetryJobs[queueKey] ~= serial then return end

        local db = PRT:GetDB()
        local preset = application.presetName and PRT:GetAutoMarkPreset(application.presetName)
        if not db.autoMark.enabled
            or (application.presetName and db.autoMark.activePreset ~= application.presetName)
            or (application.presetName and not preset)
            or (preset and not PRT:IsAutoMarkPresetLocationAllowed(preset)) then
            Finish()
            return
        end

        local pending = 0
        for _, assignment in ipairs(application.assignments) do
            if not assignment.complete then
                PRT:TryAutoMarkAssignment(assignment)
                if not assignment.complete then
                    pending = pending + 1
                end
            end
        end

        if pending == 0 or AutoMarkNow() >= deadline then
            Finish()
            return
        end

        C_Timer.After(AUTO_MARK_RETRY_INTERVAL, Retry)
    end

    C_Timer.After(AUTO_MARK_RETRY_INTERVAL, Retry)
end

function PRT:ApplyAutoMarkApplication(application, opts)
    opts = opts or {}
    local mg = application.mg

    if not IsInRaid() then return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        PRT.Print("Auto Mark: must be leader or assistant to set marks.")
        return
    end

    if opts.rebuild then
        application.assignments = self:BuildAutoMarkAssignments(mg)
    end

    if opts.clear and mg.unmarkAll and not application.cleared then
        self:ClearAddressableRaidMarks()
        application.cleared = true
    end

    for _, assignment in ipairs(application.assignments) do
        if not assignment.complete then
            self:TryAutoMarkAssignment(assignment)
        end
    end

    if opts.queue and mg.retryUnavailable then
        self:StartAutoMarkRetryQueue(application)
    end
end

function PRT:ApplyMarkGroup(mg, opts)
    opts = opts or {}
    local application = self:CreateAutoMarkApplication(mg, opts)
    self:ApplyAutoMarkApplication(application, {
        clear = true,
        queue = mg.retryUnavailable,
    })
    return application
end

--- Player Name mode: find the named player in the raid and mark them.
function PRT:ApplyMarkByName(mark)
    if not mark.playerName or mark.playerName == "" then return end
    local assignment = {
        icon = mark.icon,
        sourceName = mark.playerName,
        identityKey = self:GetPlayerIdentityKey(mark.playerName),
    }
    return self:TryAutoMarkAssignment(assignment)
end

--- Raid Position mode (no Smart Assign): position maps directly to raid index.
function PRT:ApplyMarkByPosition(mark)
    local pos = mark.position or 0
    if pos < 1 or pos > 40 then return end
    local assignment = {
        icon = mark.icon,
        sourceName = "",
        position = pos,
        raidPosition = pos,
    }
    return self:TryAutoMarkAssignment(assignment)
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

    local assignment = {
        icon = mark.icon,
        sourceName = targetName,
        position = pos,
        identityKey = self:GetPlayerIdentityKey(targetName),
    }
    return self:TryAutoMarkAssignment(assignment)
end

---------------------------------------------------------------------------
-- Kill counter / fired-state reset
---------------------------------------------------------------------------
function PRT:ResetAutoMarkCounters()
    wipe(self._autoMarkKills)
    wipe(self._autoMarkFired)
    wipe(self._autoMarkRetryJobs)
    PRT.Print("Auto Mark counters reset.")
end
