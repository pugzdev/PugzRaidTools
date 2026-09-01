---------------------------------------------------------------------------
-- PugzRaidTools - Reorder Engine
-- Ported from WeakAura: two-pass algorithm that computes minimal
-- SetRaidSubgroup / SwapRaidSubgroup calls to reach a target layout.
---------------------------------------------------------------------------
local _, PRT = ...

local RR_NAME     = PRT.RR_NAME
local RR_SUBGROUP = PRT.RR_SUBGROUP
local RR_INDEX    = PRT.RR_INDEX
local RR_LOCKED   = PRT.RR_LOCKED
local RR_START    = PRT.RR_START

function PRT:InitReorder()
    self.pendingComp = nil
end

---------------------------------------------------------------------------
-- Queue / gate
---------------------------------------------------------------------------
function PRT:TryReorder()
    if not self.pendingComp then return end

    if not IsInRaid() then return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        PRT.Print("You must be raid leader or assistant to reorder.")
        self.pendingComp = nil
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    if UnitAffectingCombat("player") then return end

    local comp = self:GetComp(self.pendingComp)
    if not comp then
        self.pendingComp = nil
        return
    end

    local target, targetError = self:BuildTarget(comp.roster)
    local runName = self.pendingComp
    self.pendingComp = nil
    if not target then
        PRT.Print(targetError)
        return
    end

    PRT.Print("Applying groups: " .. runName)

    local autoMarkApplications
    if PRT.BeginGroupSwapAutoMark then
        autoMarkApplications = PRT:BeginGroupSwapAutoMark(runName)
    end

    C_Timer.After(0.2, function()
        PRT:DoReorder(target)
        PRT:ShowNotification(runName .. " applied.")
        if PRT.FinishGroupSwapAutoMark then
            PRT:FinishGroupSwapAutoMark(autoMarkApplications)
        elseif PRT.OnGroupSwapForAutoMark then
            PRT:OnGroupSwapForAutoMark(runName)
        end
    end)
end

function PRT:RequestReorder(compName, forcePos)
    if not self:GetComp(compName) then
        PRT.Print("No such composition: " .. tostring(compName))
        return
    end
    if forcePos then
        if self.RequestPositionReorder then
            self:RequestPositionReorder(compName)
        else
            PRT.Print("The exact position sorter is not available.")
        end
        return
    end
    if self.CancelPositionSort then
        self:CancelPositionSort("a fast group sort started")
    end
    self.pendingComp = compName
    self:TryReorder()
end

---------------------------------------------------------------------------
-- Core reorder algorithm
---------------------------------------------------------------------------
function PRT:DoReorder(pTarget)
    local pSubRaid     = {}
    local pCurrentRaid = {}
    local pActionList  = {}

    local AL_TYPE = 1
    local AL_ID1  = 2
    local AL_ID2  = 3

    -- helpers ---------------------------------------------------------------
    local function InitRaid(pRaid)
        for g = 1, 8 do
            pRaid[g] = {}
            for s = 1, 5 do
                pRaid[g][s] = {
                    [RR_NAME]     = "",
                    [RR_SUBGROUP] = g,
                    [RR_START]    = 0,
                    [RR_LOCKED]   = 0,
                    [RR_INDEX]    = 0,
                }
            end
        end
    end

    local function GetRaidInfo(pRaid)
        local n = GetNumGroupMembers()
        local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for idx = 1, n do
            local name, _, grp = GetRaidRosterInfo(idx)
            if name and grp and grp > 0 then
                counts[grp] = counts[grp] + 1
                local slot = counts[grp]
                if slot <= 5 then
                    pRaid[grp][slot][RR_NAME]   = PRT:GetRaidMemberIdentityKey(idx, name)
                    pRaid[grp][slot][RR_START]  = grp
                    pRaid[grp][slot][RR_LOCKED] = 0
                    pRaid[grp][slot][RR_INDEX]  = idx
                end
            end
        end
    end

    local function Match(a, b)
        return a[RR_NAME] ~= "" and b[RR_NAME] ~= "" and a[RR_NAME] == b[RR_NAME]
    end

    local function LockPlayer(raidGroup, targetSlot)
        for s = 1, 5 do
            if raidGroup[s][RR_LOCKED] == 0 and Match(raidGroup[s], targetSlot) then
                raidGroup[s][RR_LOCKED] = 1
                return
            end
        end
    end

    local function LockTarget(targetGroup, raidSlot)
        for s = 1, 5 do
            if Match(targetGroup[s], raidSlot) then
                raidSlot[RR_LOCKED] = 1
                return
            end
        end
    end

    local function FindUnlockedInRaid(pRaid, targetSlot)
        for g = 1, 8 do
            for s = 1, 5 do
                if pRaid[g][s][RR_LOCKED] == 0 and Match(pRaid[g][s], targetSlot) then
                    return pRaid[g][s]
                end
            end
        end
    end

    local function FindUnlockedInGroup(raidGroup, destSlot, targetGroup)
        -- prefer someone who belongs in the dest group
        for s = 1, 5 do
            if raidGroup[s][RR_LOCKED] == 0 then
                for t = 1, 5 do
                    if Match(targetGroup[t], raidGroup[s]) then
                        return raidGroup[s]
                    end
                end
            end
        end
        -- then an empty slot
        for s = 1, 5 do
            if raidGroup[s][RR_LOCKED] == 0 and raidGroup[s][RR_NAME] == "" then
                return raidGroup[s]
            end
        end
        -- then anyone unlocked
        for s = 1, 5 do
            if raidGroup[s][RR_LOCKED] == 0 then
                return raidGroup[s]
            end
        end
    end

    local function SwapSlots(src, dest)
        src[RR_NAME],  dest[RR_NAME]  = dest[RR_NAME],  src[RR_NAME]
        src[RR_INDEX], dest[RR_INDEX] = dest[RR_INDEX], src[RR_INDEX]
        src[RR_START], dest[RR_START] = dest[RR_START], src[RR_START]
        src[RR_LOCKED] = 1
    end

    local function AddAction(aType, id1, id2)
        pActionList[#pActionList + 1] = {
            [AL_TYPE] = aType,
            [AL_ID1]  = id1,
            [AL_ID2]  = id2,
        }
    end

    local function InvertActions(id1, id2)
        for i = 1, #pActionList do
            local a = pActionList[i]
            if a[AL_TYPE] == "swap" then
                if a[AL_ID1] == id1 then a[AL_ID1] = id2
                elseif a[AL_ID1] == id2 then a[AL_ID1] = id1 end
                if a[AL_ID2] == id1 then a[AL_ID2] = id2
                elseif a[AL_ID2] == id2 then a[AL_ID2] = id1 end
            end
        end
    end

    local function ExecuteActions()
        for i = 1, #pActionList do
            local a = pActionList[i]
            if a[AL_TYPE] == "swap" then
                SwapRaidSubgroup(a[AL_ID1], a[AL_ID2])
            elseif a[AL_TYPE] == "move" then
                SetRaidSubgroup(a[AL_ID1], a[AL_ID2])
            end
        end
    end

    -- Pass 1: build intermediate raid by locking players already correct ---
    InitRaid(pSubRaid)
    GetRaidInfo(pSubRaid)

    for g = 1, 8 do
        for s = 1, 5 do
            LockPlayer(pSubRaid[g], pTarget[g][s])
        end
    end

    for g = 1, 8 do
        for s = 1, 5 do
            local dest = FindUnlockedInRaid(pSubRaid, pTarget[g][s])
            if dest then
                local src = FindUnlockedInGroup(pSubRaid[g], dest, pTarget[dest[RR_SUBGROUP]])
                if src then
                    SwapSlots(src, dest)
                    if src[RR_NAME] ~= "" then
                        LockTarget(pTarget[dest[RR_SUBGROUP]], dest)
                    end
                end
            end
        end
    end

    -- Pass 2: generate moves/swaps from current raid -> subRaid ------------
    InitRaid(pCurrentRaid)
    GetRaidInfo(pCurrentRaid)

    for g = 1, 8 do
        for s = 1, 5 do
            LockPlayer(pCurrentRaid[g], pSubRaid[g][s])
        end
    end

    for g = 1, 8 do
        for s = 1, 5 do
            local dest = FindUnlockedInRaid(pCurrentRaid, pSubRaid[g][s])
            if dest then
                local src = FindUnlockedInGroup(pCurrentRaid[g], dest, pSubRaid[dest[RR_SUBGROUP]])
                if src then
                    if src[RR_START] == dest[RR_START] then
                        InvertActions(src[RR_INDEX], dest[RR_INDEX])
                    elseif src[RR_NAME] == "" then
                        AddAction("move", dest[RR_INDEX], g)
                        SwapSlots(src, dest)
                    else
                        AddAction("swap", src[RR_INDEX], dest[RR_INDEX])
                        SwapSlots(src, dest)
                        LockTarget(pSubRaid[dest[RR_SUBGROUP]], dest)
                    end
                end
            end
        end
    end

    ExecuteActions()
end
