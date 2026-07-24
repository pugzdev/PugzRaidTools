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
    self.pendingComp     = nil
    self.pendingForcePos = false
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

    local target   = self:BuildTarget(comp.roster)
    local forcePos = self.pendingForcePos
    local runName  = self.pendingComp
    self.pendingComp     = nil
    self.pendingForcePos = false

    PRT.Print("Applying groups: " .. runName .. (forcePos and " (with positions)" or ""))

    C_Timer.After(0.2, function()
        PRT:DoReorder(target)
        PRT:ShowNotification(runName .. " applied.")
        if PRT.OnGroupSwapForAutoMark then PRT:OnGroupSwapForAutoMark(runName) end
        if forcePos then
            PRT:WaitThenForcePositions(target)
        end
    end)
end

function PRT:RequestReorder(compName, forcePos)
    if not self:GetComp(compName) then
        PRT.Print("No such composition: " .. tostring(compName))
        return
    end
    self.pendingComp     = compName
    self.pendingForcePos = forcePos or false
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
                    pRaid[grp][slot][RR_NAME]   = PRT.CanonName(name)
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

---------------------------------------------------------------------------
-- Force Positions - within-group slot sorting
-- Runs AFTER the group sort has settled.  Processes ONE position fix at
-- a time via a 3-swap bridge cycle (matching MRT's proven approach),
-- then waits for GROUP_ROSTER_UPDATE to re-read state before the next.
-- Works for any raid size (10-40) as long as >=2 groups have members.
---------------------------------------------------------------------------

--- Wait for GROUP_ROSTER_UPDATE events to stop (group sort settled),
--- then begin sequential position fixing.
function PRT:WaitThenForcePositions(target)
    if not self._posFrame then
        self._posFrame = CreateFrame("Frame")
    end
    local f = self._posFrame

    -- Sequence guard so stale callbacks are ignored
    self._posSeq = (self._posSeq or 0) + 1
    local seq = self._posSeq
    local lastEvent = GetTime()

    self._posFixCount = 0       -- reset for new sort session

    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function()
        lastEvent = GetTime()
    end)

    local function TryRun()
        if self._posSeq ~= seq then return end          -- stale
        if (GetTime() - lastEvent) >= 0.5 then
            f:UnregisterEvent("GROUP_ROSTER_UPDATE")
            f:SetScript("OnEvent", nil)
            self:DoForcePositions(target)
        else
            C_Timer.After(0.3, TryRun)
        end
    end

    -- Give the group sort time to start generating events
    C_Timer.After(0.8, TryRun)
end

--- Find and fix ONE within-group position error, then schedule the next.
--- Re-reads the full raid state every call (indices shift after swaps).
--- Uses MRT's proven 3-swap bridge cycle: all 3 SwapRaidSubgroup calls
--- fire in the same frame using the ORIGINAL indices for that cycle,
--- then we wait for GROUP_ROSTER_UPDATE before the next fix.
function PRT:DoForcePositions(pTarget)
    -- Guard against runaway loops
    self._posFixCount = (self._posFixCount or 0) + 1
    if self._posFixCount > 40 then
        PRT.Print("Position sort: max iterations reached.")
        self._posFixCount = 0
        return
    end

    local n = GetNumGroupMembers()
    if n == 0 then self._posFixCount = 0; return end

    -- Fresh state read every call (indices change after each cycle)
    local nameToIdx    = {}
    local groupMembers = {}     -- g -> { canon1, canon2, ... } in position order
    for g = 1, 8 do groupMembers[g] = {} end

    for idx = 1, n do
        local name, _, grp = GetRaidRosterInfo(idx)
        if name and grp and grp >= 1 and grp <= 8 then
            local canon = PRT.CanonName(name)
            nameToIdx[canon] = idx
            groupMembers[grp][#groupMembers[grp] + 1] = canon
        end
    end

    -- Scan all groups for the first position that needs fixing
    local fix   -- { group, rightName, wrongName }
    for g = 1, 8 do
        local members = groupMembers[g]
        if #members >= 2 then
            local tSlots    = pTarget[g]
            local memberSet = {}
            for _, c in ipairs(members) do memberSet[c] = true end

            -- Desired order of PRESENT members (absent players skipped)
            local desired = {}
            for s = 1, 5 do
                local tName = tSlots[s] and tSlots[s][RR_NAME] or ""
                if tName ~= "" and memberSet[tName] then
                    desired[#desired + 1] = tName
                end
            end

            for pos = 1, math.min(#desired, #members) do
                if members[pos] ~= desired[pos] then
                    -- Locate the player who SHOULD be here
                    local foundAt
                    for j = pos + 1, #members do
                        if members[j] == desired[pos] then
                            foundAt = j
                            break
                        end
                    end
                    if foundAt then
                        local rIdx = nameToIdx[desired[pos]]
                        local wIdx = nameToIdx[members[pos]]
                        -- Skip raid leader (index 1) – WoW won't move them
                        if rIdx ~= 1 and wIdx ~= 1 then
                            fix = {
                                group     = g,
                                rightName = desired[pos],
                                wrongName = members[pos],
                            }
                            break
                        end
                    end
                end
            end
        end
        if fix then break end
    end

    if not fix then
        local count = self._posFixCount - 1
        if count > 0 then
            PRT.Print(("Position sort complete (%d fix%s)."):format(
                count, count == 1 and "" or "es"))
        else
            PRT.Print("Positions already correct.")
        end
        self._posFixCount = 0
        return
    end

    -- Find bridge: any non-RL player in a different group
    local bridgeName
    for g = 1, 8 do
        if g ~= fix.group then
            for _, canon in ipairs(groupMembers[g]) do
                if nameToIdx[canon] ~= 1 then
                    bridgeName = canon
                    break
                end
            end
            if bridgeName then break end
        end
    end

    if not bridgeName then
        PRT.Print("Cannot sort positions: need non-RL players in at least two groups.")
        self._posFixCount = 0
        return
    end

    -- 3-swap bridge cycle (all use ORIGINAL indices – no updates between)
    -- Matches MRT's proven sequence:
    --   1. right ↔ bridge   (right leaves the group)
    --   2. bridge ↔ wrong   (bridge takes wrong's slot; wrong leaves)
    --   3. right ↔ bridge   (right returns to wrong's old slot; bridge home)
    local rightIdx  = nameToIdx[fix.rightName]
    local wrongIdx  = nameToIdx[fix.wrongName]
    local bridgeIdx = nameToIdx[bridgeName]

    SwapRaidSubgroup(rightIdx, bridgeIdx)       -- right ↔ bridge
    SwapRaidSubgroup(bridgeIdx, wrongIdx)       -- bridge(orig) ↔ wrong
    SwapRaidSubgroup(rightIdx, bridgeIdx)       -- right(orig) ↔ bridge(orig)

    -- Wait for GROUP_ROSTER_UPDATE, then re-read state and fix next position
    local f = self._posFrame
    self._posSeq = (self._posSeq or 0) + 1
    local seq = self._posSeq

    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function()
        if self._posSeq ~= seq then return end
        f:UnregisterEvent("GROUP_ROSTER_UPDATE")
        f:SetScript("OnEvent", nil)
        C_Timer.After(0.1, function()
            if self._posSeq ~= seq then return end
            self:DoForcePositions(pTarget)
        end)
    end)

    -- Safety timeout if no event arrives
    C_Timer.After(3.0, function()
        if self._posSeq ~= seq then return end
        f:UnregisterEvent("GROUP_ROSTER_UPDATE")
        f:SetScript("OnEvent", nil)
        PRT.Print("Position sort timed out.")
        self._posFixCount = 0
    end)
end
