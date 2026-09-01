---------------------------------------------------------------------------
-- PugzRaidTools - Exact Position Sort
--
-- Supported force-position path used by Shift + Left Click and the Raid
-- Groups "Force Positions" option. Membership and exact within-group
-- positions are planned together, issued in safe batches, and verified
-- against authoritative roster fingerprints after every dependent stage.
---------------------------------------------------------------------------
local _, PRT = ...

local RR_NAME     = PRT.RR_NAME
local RR_SUBGROUP = PRT.RR_SUBGROUP
local RR_INDEX    = PRT.RR_INDEX
local RR_LOCKED   = PRT.RR_LOCKED
local RR_START    = PRT.RR_START

-- Position cycles are pipelined into identity-disjoint stages. This is the
-- maximum number of independent calls sent in one acknowledged stage.
local MAX_CYCLES_PER_WAVE   = 8
local MAX_POSITION_CYCLES   = 40
local MAX_POSITION_WAVES    = 40
local MAX_POSITION_STAGES   = 240
local MAX_GROUP_PASSES      = 3
local GROUP_SETTLE_DELAY    = 0.50
local POSITION_SETTLE_DELAY = 0.50
local ACK_POLL_INTERVAL     = 0.10
-- Once the expected fingerprint is visible, yield to the next frame before
-- resolving fresh indices. C_Timer.After(0) preserves the event boundary
-- without imposing a fixed delay.
local NEXT_STAGE_DELAY      = 0
-- Live Classic tests have shown authoritative roster changes arriving more
-- than four seconds after a SwapRaidSubgroup burst. A longer watchdog does
-- not slow successful stages: events and polling still acknowledge them as
-- soon as they appear.
local WAIT_TIMEOUT          = 8.00
-- Classic accepted 50 group actions and rejected the 51st in live testing.
-- Use the full observed allowance, while still aging calls over a
-- conservative rolling window before starting a whole stage.
local GROUP_ACTION_LIMIT    = 50
local GROUP_ACTION_WINDOW   = 10.50
local GROUP_ACTION_GUARD    = 0.20
-- Candidate ranking predicts wall time with a deliberately middling
-- acknowledgement latency. The exact value is less important than modelling
-- the rolling-window pause that a sequence of burst sizes will cause.
local PREDICTED_ACK_SECONDS     = 1.50
local PREDICTED_HANDOFF_SECONDS = 0.03
-- Candidate evaluation gets a very small exact-scheduler budget; the selected
-- live route gets a larger final attempt before execution. Both fall back to
-- the proven greedy schedule on timeout or infeasibility.
local POSITION_CANDIDATE_EXACT_BUDGET_MS = 8
local POSITION_FINAL_EXACT_BUDGET_MS     = 75
-- Joint membership/position route search. Generation uses cheap analytical
-- scoring and reserves the remainder of the roughly one-second budget for
-- fully simulated finalists.
local MEMBERSHIP_SEARCH_BUDGET_MS     = 900
local MEMBERSHIP_GENERATION_BUDGET_MS = 800
-- Live validation showed that dependency-staged 48-call routes took longer
-- than the proven one-batch MRT route (10 acknowledgement stages versus 7).
-- Keep the research implementation available, but do not spend click-time
-- generating or executing it until a route can match MRT's stage count.
local ENABLE_DEEP_ROUTE_RESEARCH      = false
local MAX_MEMBERSHIP_CANDIDATES       = 4096
local MAX_MEMBERSHIP_FINALISTS        = 64
local MAX_MRT_PERMUTATION_CANDIDATES  = 512
local UNIFIED_BEAM_WIDTH              = 128
local UNIFIED_BEAM_PIVOT_CHOICES      = 4
local UNIFIED_BEAM_EXTRA_CALLS        = 4
local UNIFIED_BEAM_LOWER_BOUND_SLACK  = 8
local MAX_UNIFIED_SHADOW_FINALISTS    = 512
local MAX_LOG_LINES         = 2000

local function Now()
    if GetTime then return GetTime() end
    return 0
end

local function PlanningNowMs()
    if debugprofilestop then return debugprofilestop() end
    return Now() * 1000
end

local function CopyArray(source)
    local result = {}
    for i = 1, #(source or {}) do result[i] = source[i] end
    return result
end

local function CopyGroups(groups)
    local result = {}
    for group = 1, 8 do
        result[group] = CopyArray(groups and groups[group] or {})
    end
    return result
end

local function GroupFingerprint(groups)
    local parts = {}
    for group = 1, 8 do
        parts[group] = table.concat(groups[group] or {}, ",")
    end
    return table.concat(parts, "|")
end

local function GroupSummary(groups)
    local parts = {}
    for group = 1, 8 do
        parts[#parts + 1] = ("G%d=[%s]"):format(
            group,
            table.concat(groups[group] or {}, ", "))
    end
    return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Per-run logger
---------------------------------------------------------------------------
function PRT:ResetPositionSortLog(label)
    self._positionSortLog = {
        startedAt = Now(),
        label = label or "Position sort",
        lines = {},
        truncated = false,
        stats = {
            status = "running",
            apiCalls = 0,
            setCalls = 0,
            swapCalls = 0,
            groupApiCalls = 0,
            positionApiCalls = 0,
            groupPasses = 0,
            membershipStages = 0,
            positionWaves = 0,
            positionStages = 0,
            positionCycles = 0,
            rosterEvents = 0,
            replans = 0,
            stageRetries = 0,
        },
    }
    self:PositionSortLog("BEGIN %s", label or "Position sort")
end

function PRT:PositionSortLog(formatText, ...)
    local log = self._positionSortLog
    if not log then
        self:ResetPositionSortLog("Manual log")
        log = self._positionSortLog
    end

    if #log.lines >= MAX_LOG_LINES then
        if not log.truncated then
            log.truncated = true
            log.lines[#log.lines + 1] = "... log truncated ..."
        end
        return
    end

    local ok, message = pcall(string.format, tostring(formatText or ""), ...)
    if not ok then message = tostring(formatText or "") end
    local elapsed = math.max(
        0, (log.endedAt or Now()) - (log.startedAt or Now()))
    log.lines[#log.lines + 1] = ("%08.3f  %s"):format(elapsed, message)
end

function PRT:GetPositionSortLogText()
    local log = self._positionSortLog
    if not log then
        return "No position sort log has been recorded yet."
    end

    local stats = log.stats or {}
    local lines = CopyArray(log.lines)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "----- Summary -----"
    lines[#lines + 1] = "Run: " .. tostring(log.label or "")
    lines[#lines + 1] = "Status: " .. tostring(stats.status or "unknown")
    lines[#lines + 1] = ("Elapsed: %.3fs"):format(
        math.max(0, (log.endedAt or Now()) - (log.startedAt or Now())))
    lines[#lines + 1] =
        ("API calls: %d total (%d SetRaidSubgroup, %d SwapRaidSubgroup)"):format(
            stats.apiCalls or 0,
            stats.setCalls or 0,
            stats.swapCalls or 0)
    lines[#lines + 1] =
        ("API calls by phase: %d membership, %d position"):format(
            stats.groupApiCalls or 0,
            stats.positionApiCalls or 0)
    lines[#lines + 1] =
        ("Planning: %d group passes, %d membership stages, %d position pipelines, %d position stages, %d position cycles, %d replans, %d safe retries"):format(
            stats.groupPasses or 0,
            stats.membershipStages or 0,
            stats.positionWaves or 0,
            stats.positionStages or 0,
            stats.positionCycles or 0,
            stats.replans or 0,
            stats.stageRetries or 0)
    lines[#lines + 1] = ("GROUP_ROSTER_UPDATE events: %d"):format(
        stats.rosterEvents or 0)
    return table.concat(lines, "\n")
end

function PRT:ClearPositionSortLog()
    if self._positionSortSession
        and not self._positionSortSession.finished then
        self:CancelPositionSort("the event log was cleared")
    end
    self:ResetPositionSortLog("Cleared")
    self._positionSortLog.stats.status = "cleared"
    self._positionSortLog.endedAt = Now()
end

function PRT:ShowPositionSortLog()
    local W = self.UI
    if not W or not W.CreateTextTransferPopup then
        PRT.Print("The sort log window is not available yet.")
        return
    end

    if not self._positionSortLogPopup then
        self._positionSortLogPopup = W.CreateTextTransferPopup(
            "PRT_PositionSortLogPopup",
            {
                title = "Position Sort Event Log",
                instruction = "Select all with Ctrl+A, then copy with Ctrl+C.",
                width = 720,
                height = 560,
                boxWidth = 696,
                boxHeight = 470,
                actionText = "Close",
            })
    end

    self._positionSortLogPopup:Open({
        title = "Position Sort Event Log",
        text = self:GetPositionSortLogText(),
        actionText = "Close",
    })
end

local function LogApiCall(self, apiName, phase, details)
    local log = self._positionSortLog
    if not log then return end
    local stats = log.stats
    stats.apiCalls = stats.apiCalls + 1
    if apiName == "SetRaidSubgroup" then
        stats.setCalls = stats.setCalls + 1
    else
        stats.swapCalls = stats.swapCalls + 1
    end
    if phase == "membership" then
        stats.groupApiCalls = stats.groupApiCalls + 1
    elseif phase == "position" then
        stats.positionApiCalls = stats.positionApiCalls + 1
    end
    self:PositionSortLog("API %03d  %s  %s  %s",
        stats.apiCalls, phase, apiName, details or "")

    local history = self._groupActionTimes or {}
    self._groupActionTimes = history
    local now = Now()
    local cutoff = now - GROUP_ACTION_WINDOW
    while history[1] and history[1] <= cutoff do
        table.remove(history, 1)
    end
    history[#history + 1] = now
end

function PRT:_PositionSortSetRaidSubgroup(raidIndex, subgroup, phase)
    local name = GetRaidRosterInfo(raidIndex)
    LogApiCall(self, "SetRaidSubgroup", phase,
        ("index=%s player=%s group=%s"):format(
            tostring(raidIndex), tostring(name or "?"), tostring(subgroup)))
    SetRaidSubgroup(raidIndex, subgroup)
end

function PRT:_PositionSortSwapRaidSubgroup(
    firstIndex, secondIndex, phase, detail)
    local firstName = GetRaidRosterInfo(firstIndex)
    local secondName = GetRaidRosterInfo(secondIndex)
    LogApiCall(self, "SwapRaidSubgroup", phase,
        ("index1=%s player1=%s index2=%s player2=%s%s"):format(
            tostring(firstIndex), tostring(firstName or "?"),
            tostring(secondIndex), tostring(secondName or "?"),
            detail and (" " .. detail) or ""))
    SwapRaidSubgroup(firstIndex, secondIndex)
end

---------------------------------------------------------------------------
-- Authoritative roster snapshots
---------------------------------------------------------------------------
function PRT:ReadPositionRosterSnapshot()
    local snapshot = {
        count = GetNumGroupMembers(),
        members = {},
        groups = {},
        indexByKey = {},
        groupByKey = {},
        rankByKey = {},
        keyByIndex = {},
        leaderKey = nil,
    }
    for group = 1, 8 do snapshot.groups[group] = {} end

    for raidIndex = 1, snapshot.count do
        local name, rank, subgroup = GetRaidRosterInfo(raidIndex)
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            local key = self:GetRaidMemberIdentityKey(raidIndex, name)
            local entry = {
                key = key,
                name = name,
                index = raidIndex,
                rank = rank or 0,
                group = subgroup,
            }
            snapshot.members[#snapshot.members + 1] = entry
            snapshot.groups[subgroup][#snapshot.groups[subgroup] + 1] = key
            snapshot.indexByKey[key] = raidIndex
            snapshot.groupByKey[key] = subgroup
            snapshot.rankByKey[key] = rank or 0
            snapshot.keyByIndex[raidIndex] = key
            if rank == 2 then snapshot.leaderKey = key end
        end
    end

    -- Classic normally exposes the raid leader at index 1. Keep that
    -- compatibility fallback if rank data is unavailable.
    if not snapshot.leaderKey then
        snapshot.leaderKey = snapshot.keyByIndex[1]
    end

    snapshot.fingerprint = GroupFingerprint(snapshot.groups)
    return snapshot
end

local function BuildTargetGroupMap(target)
    local result = {}
    for group = 1, 8 do
        for slot = 1, 5 do
            local key = target[group][slot]
                and target[group][slot][RR_NAME] or ""
            if key ~= "" then result[key] = group end
        end
    end
    return result
end

local function MembershipMatchesTarget(snapshot, target)
    local targetGroups = BuildTargetGroupMap(target)
    for key, desiredGroup in pairs(targetGroups) do
        local currentGroup = snapshot.groupByKey[key]
        if currentGroup and currentGroup ~= desiredGroup then
            return false, ("%s is in G%d, expected G%d"):format(
                key, currentGroup, desiredGroup)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Position precomputation
---------------------------------------------------------------------------
local function BuildDesiredOrders(snapshot, target)
    local desiredGroups = {}
    local leaderAdjustment

    for group = 1, 8 do
        local desired = {}
        local included = {}

        -- Present composition members in saved slot order.
        for slot = 1, 5 do
            local key = target[group][slot]
                and target[group][slot][RR_NAME] or ""
            if key ~= ""
                and snapshot.groupByKey[key] == group
                and not included[key] then
                desired[#desired + 1] = key
                included[key] = true
            end
        end

        -- Preserve non-composition players, but place them after target members.
        for _, key in ipairs(snapshot.groups[group]) do
            if not included[key] then
                desired[#desired + 1] = key
                included[key] = true
            end
        end

        -- The raid leader cannot be moved. Normalize the attainable target
        -- around their current position instead of silently claiming an
        -- impossible exact layout was reached.
        local leaderKey = snapshot.leaderKey
        if leaderKey and snapshot.groupByKey[leaderKey] == group then
            local currentLeaderPosition
            local desiredLeaderPosition
            for position, key in ipairs(snapshot.groups[group]) do
                if key == leaderKey then
                    currentLeaderPosition = position
                    break
                end
            end
            for position, key in ipairs(desired) do
                if key == leaderKey then
                    desiredLeaderPosition = position
                    break
                end
            end
            if currentLeaderPosition
                and desiredLeaderPosition
                and currentLeaderPosition ~= desiredLeaderPosition then
                table.remove(desired, desiredLeaderPosition)
                table.insert(desired,
                    math.min(currentLeaderPosition, #desired + 1),
                    leaderKey)
                leaderAdjustment = {
                    key = leaderKey,
                    group = group,
                    requested = desiredLeaderPosition,
                    retained = currentLeaderPosition,
                }
            end
        end

        desiredGroups[group] = desired
    end

    return desiredGroups, leaderAdjustment
end

local function GroupsMatch(left, right)
    for group = 1, 8 do
        local a = left[group] or {}
        local b = right[group] or {}
        if #a ~= #b then return false end
        for position = 1, #a do
            if a[position] ~= b[position] then return false end
        end
    end
    return true
end

local function SwapIdentityPositions(groups, firstKey, secondKey)
    local firstGroup, firstPosition
    local secondGroup, secondPosition
    for group = 1, 8 do
        for position, key in ipairs(groups[group] or {}) do
            if key == firstKey then
                firstGroup, firstPosition = group, position
            elseif key == secondKey then
                secondGroup, secondPosition = group, position
            end
        end
    end
    if not firstGroup or not secondGroup then return false end
    groups[firstGroup][firstPosition], groups[secondGroup][secondPosition] =
        groups[secondGroup][secondPosition], groups[firstGroup][firstPosition]
    return true
end

local function GetCycleResources(cycle)
    local resources = {}
    for _, key in ipairs(cycle.memberKeys or {}) do
        resources[key] = true
    end
    if cycle.bridgeKey then resources[cycle.bridgeKey] = true end
    return resources
end

local function ResourcesOverlap(left, right)
    for key in pairs(left or {}) do
        if right and right[key] then return true end
    end
    return false
end

local function AssignCycleBridge(cycle, bridgeKey)
    cycle.bridgeKey = bridgeKey
    if cycle.steps and #cycle.steps >= 2 then
        cycle.steps[1].secondKey = bridgeKey
        cycle.steps[#cycle.steps].secondKey = bridgeKey
    end
    cycle.resources = GetCycleResources(cycle)
end

local function BuildBridgeCandidates(
    cycle, snapshot, allCycleMembers)
    local idle = {}
    local participating = {}
    for _, member in ipairs(snapshot.members or {}) do
        local key = member.key
        if key ~= snapshot.leaderKey
            and member.group ~= cycle.group
            and not cycle.memberKeySet[key] then
            local list = allCycleMembers[key]
                and participating or idle
            list[#list + 1] = key
        end
    end
    for _, key in ipairs(participating) do
        idle[#idle + 1] = key
    end
    return idle
end

-- Assign longer cycles first so a late long cycle cannot create a mostly
-- empty tail. Bridge identities are selected globally: idle players are
-- preferred, while a member of another cycle is allowed only when the
-- resulting cycle lifetimes do not overlap.
local function BuildPipelinedStages(
    cycles, maxCallsPerStage, snapshot)
    local stages = {}
    local stageUsedKeys = {}
    local allCycleMembers = {}

    for originalIndex, cycle in ipairs(cycles) do
        cycle.originalIndex = originalIndex
        cycle.memberKeySet = {}
        for _, key in ipairs(cycle.memberKeys or {}) do
            cycle.memberKeySet[key] = true
            allCycleMembers[key] = true
        end
    end
    table.sort(cycles, function(left, right)
        local leftLength = #(left.steps or {})
        local rightLength = #(right.steps or {})
        if leftLength ~= rightLength then
            return leftLength > rightLength
        end
        return (left.originalIndex or 0)
            < (right.originalIndex or 0)
    end)

    for cycleIndex, cycle in ipairs(cycles) do
        local bestBridge
        local bestStartStage
        local candidates = BuildBridgeCandidates(
            cycle, snapshot, allCycleMembers)

        for _, bridgeKey in ipairs(candidates) do
            AssignCycleBridge(cycle, bridgeKey)
            local earliestStage = 1
            for priorIndex = 1, cycleIndex - 1 do
                local prior = cycles[priorIndex]
                if ResourcesOverlap(cycle.resources, prior.resources) then
                    earliestStage = math.max(
                        earliestStage, (prior.endStage or 0) + 1)
                end
            end

            local startStage = earliestStage
            while startStage <= MAX_POSITION_STAGES do
                local fits = true
                for localStage, step in ipairs(cycle.steps or {}) do
                    local stageIndex = startStage + localStage - 1
                    local entries = stages[stageIndex] or {}
                    local used = stageUsedKeys[stageIndex] or {}
                    if #entries >= maxCallsPerStage
                        or used[step.firstKey]
                        or used[step.secondKey] then
                        fits = false
                        break
                    end
                end
                if fits then
                    if not bestStartStage
                        or startStage < bestStartStage then
                        bestBridge = bridgeKey
                        bestStartStage = startStage
                    end
                    break
                end
                startStage = startStage + 1
            end
        end

        if not bestBridge then
            return nil,
                "Pipelined position plan exceeded the 240-stage safety limit."
        end

        AssignCycleBridge(cycle, bestBridge)
        cycle.startStage = bestStartStage
        cycle.endStage =
            bestStartStage + #(cycle.steps or {}) - 1
        for localStage, step in ipairs(cycle.steps or {}) do
            local stageIndex = bestStartStage + localStage - 1
            stages[stageIndex] = stages[stageIndex] or {}
            stageUsedKeys[stageIndex] =
                stageUsedKeys[stageIndex] or {}
            stages[stageIndex][#stages[stageIndex] + 1] = {
                cycle = cycle,
                cycleIndex = cycleIndex,
                cycleStage = localStage,
                firstKey = step.firstKey,
                secondKey = step.secondKey,
            }
            stageUsedKeys[stageIndex][step.firstKey] = true
            stageUsedKeys[stageIndex][step.secondKey] = true
        end
    end

    return stages
end

local function PositionStageLowerBound(cycles, maxCallsPerStage)
    local calls = 0
    local longest = 0
    for _, cycle in ipairs(cycles or {}) do
        local length = #(cycle.steps or {})
        calls = calls + length
        longest = math.max(longest, length)
    end
    return math.max(
        longest,
        math.ceil(calls / math.max(1, maxCallsPerStage)))
end

local function ExactCycleStepPair(cycle, bridgeKey, localStage)
    local steps = cycle.steps or {}
    local step = steps[localStage]
    if not step then return nil, nil end
    if localStage == 1 or localStage == #steps then
        return step.firstKey, bridgeKey
    end
    return step.firstKey, step.secondKey
end

local function IntervalsOverlap(
    leftStart, leftEnd, rightStart, rightEnd)
    return leftStart <= rightEnd and rightStart <= leftEnd
end

-- Find a schedule with a proven fixed stage count. Calls belonging to one
-- bridge cycle remain ordered but may leave gaps, while cycles sharing any
-- identity may not overlap in time. Those constraints preserve the already
-- validated bridge semantics while independent cycles fill empty slots.
local function BuildExactPipelinedStages(
    cycles, maxCallsPerStage, snapshot, targetStageCount, deadlineMs)
    local allCycleMembers = {}
    local stageCounts = {}
    local stageAssignments = {}
    local bridgeAssignments = {}
    local expanded = 0
    local timedOut = false
    local totalCalls = 0

    for stage = 1, targetStageCount do
        stageCounts[stage] = 0
    end
    for originalIndex, cycle in ipairs(cycles or {}) do
        cycle.originalIndex = cycle.originalIndex or originalIndex
        cycle.memberKeySet = cycle.memberKeySet or {}
        for _, key in ipairs(cycle.memberKeys or {}) do
            cycle.memberKeySet[key] = true
            allCycleMembers[key] = true
        end
        totalCalls = totalCalls + #(cycle.steps or {})
    end

    local ordered = CopyArray(cycles)
    local candidateCache = {}
    local sequenceCache = {}
    for _, cycle in ipairs(ordered) do
        candidateCache[cycle] =
            BuildBridgeCandidates(cycle, snapshot, allCycleMembers)
    end
    table.sort(ordered, function(left, right)
        local leftLength = #(left.steps or {})
        local rightLength = #(right.steps or {})
        if leftLength ~= rightLength then
            return leftLength > rightLength
        end
        local leftCandidates = #(candidateCache[left] or {})
        local rightCandidates = #(candidateCache[right] or {})
        if leftCandidates ~= rightCandidates then
            return leftCandidates < rightCandidates
        end
        return (left.originalIndex or 0)
            < (right.originalIndex or 0)
    end)

    local function BuildStageSequences(length)
        local sequences = {}
        local current = {}
        local function Add(nextStage, remaining)
            if remaining == 0 then
                sequences[#sequences + 1] = CopyArray(current)
                return
            end
            local lastStage =
                targetStageCount - remaining + 1
            for stage = nextStage, lastStage do
                current[#current + 1] = stage
                Add(stage + 1, remaining - 1)
                current[#current] = nil
            end
        end
        Add(1, length)
        return sequences
    end
    for _, cycle in ipairs(ordered) do
        local length = #(cycle.steps or {})
        sequenceCache[cycle] =
            BuildStageSequences(length)
    end

    local remainingCalls = {}
    remainingCalls[#ordered + 1] = 0
    for index = #ordered, 1, -1 do
        remainingCalls[index] =
            remainingCalls[index + 1]
                + #(ordered[index].steps or {})
    end

    local function HasCapacity(index)
        local available = 0
        for stage = 1, targetStageCount do
            available = available
                + maxCallsPerStage - stageCounts[stage]
        end
        return available >= (remainingCalls[index] or 0)
    end

    local function CheckDeadline()
        expanded = expanded + 1
        if expanded % 64 == 0
            and PlanningNowMs() >= deadlineMs then
            timedOut = true
            return true
        end
        return false
    end

    -- Once call slots have been assigned, solve bridge identities separately.
    -- This avoids exploring equivalent bridge permutations for a temporal
    -- packing that is already impossible.
    local function AssignBridges()
        local stageUsedKeys = {}
        local assignedCycles = {}
        for stage = 1, targetStageCount do
            stageUsedKeys[stage] = {}
        end
        for _, cycle in ipairs(ordered) do
            local assignment = stageAssignments[cycle]
            for localStage, stage in ipairs(
                assignment.stageSequence) do
                local step = cycle.steps[localStage]
                stageUsedKeys[stage][step.firstKey] = true
                if localStage ~= 1
                    and localStage ~= #(cycle.steps or {}) then
                    stageUsedKeys[stage][step.secondKey] = true
                end
            end
        end

        local bridgeOrder = CopyArray(ordered)
        table.sort(bridgeOrder, function(left, right)
            local leftCandidates =
                #(candidateCache[left] or {})
            local rightCandidates =
                #(candidateCache[right] or {})
            if leftCandidates ~= rightCandidates then
                return leftCandidates < rightCandidates
            end
            local leftAssignment = stageAssignments[left]
            local rightAssignment = stageAssignments[right]
            local leftSpan = leftAssignment.endStage
                - leftAssignment.startStage
            local rightSpan = rightAssignment.endStage
                - rightAssignment.startStage
            if leftSpan ~= rightSpan then
                return leftSpan > rightSpan
            end
            return (left.originalIndex or 0)
                < (right.originalIndex or 0)
        end)

        local function SearchBridge(index)
            if CheckDeadline() then return false end
            if index > #bridgeOrder then return true end
            local cycle = bridgeOrder[index]
            local assignment = stageAssignments[cycle]
            local sequence = assignment.stageSequence
            local firstStage = sequence[1]
            local lastStage = sequence[#sequence]

            for _, bridgeKey in ipairs(
                candidateCache[cycle] or {}) do
                local resources = {}
                for _, key in ipairs(cycle.memberKeys or {}) do
                    resources[key] = true
                end
                resources[bridgeKey] = true
                local fits =
                    not stageUsedKeys[firstStage][bridgeKey]
                    and not stageUsedKeys[lastStage][bridgeKey]
                if fits then
                    for _, prior in ipairs(assignedCycles) do
                        if ResourcesOverlap(
                            resources, prior.resources)
                            and IntervalsOverlap(
                                assignment.startStage,
                                assignment.endStage,
                                prior.startStage,
                                prior.endStage) then
                            fits = false
                            break
                        end
                    end
                end
                if fits then
                    local bridgeAssignment = {
                        bridgeKey = bridgeKey,
                        resources = resources,
                        startStage = assignment.startStage,
                        endStage = assignment.endStage,
                    }
                    bridgeAssignments[cycle] =
                        bridgeAssignment
                    assignedCycles[#assignedCycles + 1] =
                        bridgeAssignment
                    stageUsedKeys[firstStage][bridgeKey] = true
                    stageUsedKeys[lastStage][bridgeKey] = true
                    if SearchBridge(index + 1) then
                        return true
                    end
                    stageUsedKeys[firstStage][bridgeKey] = nil
                    stageUsedKeys[lastStage][bridgeKey] = nil
                    assignedCycles[#assignedCycles] = nil
                    bridgeAssignments[cycle] = nil
                end
                if timedOut then return false end
            end
            return false
        end
        return SearchBridge(1)
    end

    local function SearchStages(index)
        if CheckDeadline() then return false end
        if index > #ordered then
            return AssignBridges()
        end
        if not HasCapacity(index) then return false end

        local cycle = ordered[index]
        local sequenceOptions =
            CopyArray(sequenceCache[cycle] or {})
        local function SequenceScore(sequence)
            local added = {}
            for _, stage in ipairs(sequence) do
                added[stage] = true
            end
            local maximum = 0
            local squares = 0
            local frontLoad = 0
            for stage = 1, targetStageCount do
                local count = stageCounts[stage]
                    + (added[stage] and 1 or 0)
                maximum = math.max(maximum, count)
                squares = squares + count * count
                frontLoad = frontLoad
                    + count * (targetStageCount - stage + 1)
            end
            return maximum, squares, frontLoad,
                table.concat(sequence, ",")
        end
        table.sort(sequenceOptions, function(left, right)
            local leftMaximum, leftSquares,
                leftFrontLoad, leftSignature =
                    SequenceScore(left)
            local rightMaximum, rightSquares,
                rightFrontLoad, rightSignature =
                    SequenceScore(right)
            if leftMaximum ~= rightMaximum then
                return leftMaximum < rightMaximum
            end
            if leftSquares ~= rightSquares then
                return leftSquares < rightSquares
            end
            -- With equal balance, defer calls slightly so a rolling action
            -- window is more likely to age out before the larger tail.
            if leftFrontLoad ~= rightFrontLoad then
                return leftFrontLoad < rightFrontLoad
            end
            return leftSignature < rightSignature
        end)
        for _, sequence in ipairs(sequenceOptions) do
            local fits = true
            for _, stage in ipairs(sequence) do
                if stageCounts[stage] >= maxCallsPerStage then
                    fits = false
                    break
                end
            end
            if fits then
                stageAssignments[cycle] = {
                    stageSequence = sequence,
                    startStage = sequence[1],
                    endStage = sequence[#sequence],
                }
                for _, stage in ipairs(sequence) do
                    stageCounts[stage] = stageCounts[stage] + 1
                end
                if SearchStages(index + 1) then return true end
                for _, stage in ipairs(sequence) do
                    stageCounts[stage] = stageCounts[stage] - 1
                end
                stageAssignments[cycle] = nil
            end
            if timedOut then return false end
        end
        return false
    end

    if totalCalls > targetStageCount * maxCallsPerStage
        or not SearchStages(1) then
        return nil, {
            expanded = expanded,
            timedOut = timedOut,
        }
    end

    local stages = {}
    for stage = 1, targetStageCount do stages[stage] = {} end
    for cycleIndex, cycle in ipairs(cycles) do
        local assignment = stageAssignments[cycle]
        local bridgeAssignment = bridgeAssignments[cycle]
        if not assignment or not bridgeAssignment then
            return nil, {
                expanded = expanded,
                timedOut = timedOut,
            }
        end
        AssignCycleBridge(cycle, bridgeAssignment.bridgeKey)
        cycle.startStage = assignment.startStage
        cycle.endStage = assignment.endStage
        cycle.stageSequence =
            CopyArray(assignment.stageSequence)
        for localStage, stage in ipairs(
            assignment.stageSequence) do
            local firstKey, secondKey =
                ExactCycleStepPair(
                    cycle,
                    bridgeAssignment.bridgeKey,
                    localStage)
            stages[stage][#stages[stage] + 1] = {
                cycle = cycle,
                cycleIndex = cycleIndex,
                cycleStage = localStage,
                firstKey = firstKey,
                secondKey = secondKey,
            }
        end
    end
    return stages, {
        expanded = expanded,
        timedOut = false,
    }
end

local function BuildStagedEntryFingerprints(beforeGroups, stages)
    local stagedGroups = CopyGroups(beforeGroups)
    local fingerprints = {}
    for stageIndex, entries in ipairs(stages or {}) do
        for _, entry in ipairs(entries) do
            if not SwapIdentityPositions(
                stagedGroups, entry.firstKey, entry.secondKey) then
                return nil, nil
            end
        end
        fingerprints[stageIndex] = GroupFingerprint(stagedGroups)
    end
    return fingerprints, stagedGroups
end

local function FindBridge(groups, targetGroup, reserved, leaderKey)
    for group = 1, 8 do
        if group ~= targetGroup then
            for _, key in ipairs(groups[group] or {}) do
                if key ~= leaderKey and not reserved[key] then
                    return key
                end
            end
        end
    end
end

local function BuildPositionWave(
    groups, desiredGroups, snapshot, maxCycles)
    local working = CopyGroups(groups)
    local reserved = {}
    local cycles = {}

    for group = 1, 8 do
        local members = working[group]
        local desired = desiredGroups[group]
        local desiredPositionByKey = {}
        for position, key in ipairs(desired) do
            desiredPositionByKey[key] = position
        end
        local visited = {}

        for startPosition = 1, math.min(#members, #desired) do
            if not visited[startPosition]
                and members[startPosition] ~= desired[startPosition] then
                local positions = {}
                local position = startPosition
                local valid = true
                repeat
                    if visited[position] then
                        valid = position == startPosition
                        break
                    end
                    visited[position] = true
                    positions[#positions + 1] = position
                    position = desiredPositionByKey[members[position]]
                    if not position then
                        valid = false
                        break
                    end
                until position == startPosition

                local memberKeys = {}
                local unavailable = {}
                for key in pairs(reserved) do unavailable[key] = true end
                if valid and #positions >= 2 then
                    for _, cyclePosition in ipairs(positions) do
                        local key = members[cyclePosition]
                        memberKeys[#memberKeys + 1] = key
                        if key == snapshot.leaderKey or reserved[key] then
                            valid = false
                        end
                        unavailable[key] = true
                    end
                end

                local bridgeKey = valid and FindBridge(
                    working, group, unavailable, snapshot.leaderKey)
                if bridgeKey then
                    local firstPosition = positions[1]
                    local initialMovingKey = desired[firstPosition]
                    local steps = {
                        {
                            firstKey = initialMovingKey,
                            secondKey = bridgeKey,
                        },
                    }
                    for index = 1, #positions - 1 do
                        steps[#steps + 1] = {
                            firstKey = index == 1
                                and initialMovingKey
                                or members[positions[index - 1]],
                            secondKey = members[positions[index]],
                        }
                    end
                    steps[#steps + 1] = {
                        firstKey = members[positions[#positions - 1]],
                        secondKey = bridgeKey,
                    }

                    cycles[#cycles + 1] = {
                        group = group,
                        position = firstPosition,
                        rightKey = initialMovingKey,
                        wrongKey = members[firstPosition],
                        bridgeKey = bridgeKey,
                        memberKeys = memberKeys,
                        positions = positions,
                        steps = steps,
                    }
                    for key in pairs(unavailable) do reserved[key] = true end
                    reserved[bridgeKey] = true
                    for _, cyclePosition in ipairs(positions) do
                        members[cyclePosition] = desired[cyclePosition]
                    end

                    if #cycles >= maxCycles then
                        return cycles, working
                    end
                end
            end
        end
    end

    return cycles, working
end

function PRT:BuildExactPositionPlan(
    snapshot, target, maxCyclesPerWave, exactBudgetMs)
    local planningStartedMs = PlanningNowMs()
    exactBudgetMs = tonumber(exactBudgetMs)
        or POSITION_FINAL_EXACT_BUDGET_MS
    maxCyclesPerWave = math.max(1,
        math.floor(tonumber(maxCyclesPerWave) or MAX_CYCLES_PER_WAVE))

    local desiredGroups, leaderAdjustment =
        BuildDesiredOrders(snapshot, target)
    local simulatedGroups = CopyGroups(snapshot.groups)
    local plan = {
        waves = {},
        desiredGroups = desiredGroups,
        leaderAdjustment = leaderAdjustment,
        cycles = {},
        totalCycles = 0,
        totalApiCalls = 0,
        sourceWaveCount = 0,
        unpipelinedStageCount = 0,
        scheduleStrategy = "greedy",
        scheduleLowerBound = 0,
        greedyStageCount = 0,
        exactAttempted = false,
        exactSearchMs = 0,
        exactExpanded = 0,
        exactTimedOut = false,
        blockedReason = nil,
    }

    for _ = 1, MAX_POSITION_WAVES do
        if GroupsMatch(simulatedGroups, desiredGroups) then
            if plan.totalCycles > 0 then
                local stages, scheduleError =
                    BuildPipelinedStages(
                        plan.cycles, maxCyclesPerWave, snapshot)
                if not stages then
                    plan.blockedReason = scheduleError
                    plan.planningMs =
                        PlanningNowMs() - planningStartedMs
                    return plan
                end
                plan.greedyStageCount = #stages
                plan.scheduleLowerBound =
                    PositionStageLowerBound(
                        plan.cycles, maxCyclesPerWave)
                if exactBudgetMs > 0
                    and #plan.cycles > 1 then
                    plan.exactAttempted = true
                    local exactStartedMs = PlanningNowMs()
                    local exactDeadlineMs =
                        exactStartedMs + exactBudgetMs
                    for targetStageCount =
                        plan.scheduleLowerBound,
                        plan.greedyStageCount do
                        local exactStages, exactStats =
                            BuildExactPipelinedStages(
                                plan.cycles,
                                maxCyclesPerWave,
                                snapshot,
                                targetStageCount,
                                exactDeadlineMs)
                        plan.exactExpanded =
                            plan.exactExpanded
                                + ((exactStats
                                    and exactStats.expanded) or 0)
                        if exactStages then
                            stages = exactStages
                            plan.scheduleStrategy =
                                targetStageCount
                                    < plan.greedyStageCount
                                    and "bounded-exact"
                                    or "bounded-exact-balanced"
                            break
                        end
                        if exactStats and exactStats.timedOut then
                            plan.exactTimedOut = true
                            break
                        end
                    end
                    plan.exactSearchMs =
                        PlanningNowMs() - exactStartedMs
                end

                local stageFingerprints, stagedGroups =
                    BuildStagedEntryFingerprints(
                        snapshot.groups, stages)
                if not stageFingerprints
                    or not GroupsMatch(stagedGroups, desiredGroups) then
                    plan.blockedReason =
                        "Internal pipelined position-plan simulation diverged."
                    plan.planningMs =
                        PlanningNowMs() - planningStartedMs
                    return plan
                end

                local pipeline = {
                    cycles = plan.cycles,
                    stages = stages,
                    stageCount = #stages,
                    beforeFingerprint =
                        GroupFingerprint(snapshot.groups),
                    expectedFingerprint =
                        GroupFingerprint(stagedGroups),
                    expectedGroups = CopyGroups(stagedGroups),
                    stageExpectedFingerprints =
                        stageFingerprints,
                    stagedExpectedGroups = stagedGroups,
                }
                plan.waves = { pipeline }
            end
            plan.planningMs = PlanningNowMs() - planningStartedMs
            return plan
        end

        local cycles, afterGroups = BuildPositionWave(
            simulatedGroups, desiredGroups, snapshot, maxCyclesPerWave)
        if #cycles == 0 then
            plan.blockedReason =
                "No independent correction with an available non-leader bridge could be planned."
            plan.planningMs = PlanningNowMs() - planningStartedMs
            return plan
        end

        plan.totalCycles = plan.totalCycles + #cycles
        if plan.totalCycles > MAX_POSITION_CYCLES then
            plan.blockedReason =
                "Position plan exceeded the 40-cycle safety limit."
            plan.planningMs = PlanningNowMs() - planningStartedMs
            return plan
        end

        plan.sourceWaveCount = plan.sourceWaveCount + 1
        local sourceStageCount = 0
        for _, cycle in ipairs(cycles) do
            cycle.sourceWave = plan.sourceWaveCount
            plan.cycles[#plan.cycles + 1] = cycle
            plan.totalApiCalls =
                plan.totalApiCalls + #(cycle.steps or {})
            sourceStageCount = math.max(
                sourceStageCount, #(cycle.steps or {}))
        end
        plan.unpipelinedStageCount =
            plan.unpipelinedStageCount + sourceStageCount
        simulatedGroups = afterGroups
    end

    plan.blockedReason = "Position plan exceeded the 40-wave safety limit."
    plan.planningMs = PlanningNowMs() - planningStartedMs
    return plan
end

---------------------------------------------------------------------------
-- Isolated copy of the proven membership action planner.
-- Keeping it separate from the fast membership-only path lets every
-- force-position API call be simulated, scored, rate-limited, and logged.
---------------------------------------------------------------------------
function PRT:BuildPositionGroupActions(pTarget, options)
    local pSubRaid = {}
    local pCurrentRaid = {}
    local pActionList = {}
    options = options or {}
    local capturedSnapshot = options.snapshot
    local groupOrder = options.groupOrder
        or { 1, 2, 3, 4, 5, 6, 7, 8 }
    local slotOrder = options.slotOrder
        or { 1, 2, 3, 4, 5 }
    local choiceRandom = options.choiceRandom
    local requestedOutcomeGroups = options.outcomeGroups

    local AL_TYPE = 1
    local AL_ID1 = 2
    local AL_ID2 = 3

    local function InitRaid(pRaid)
        for group = 1, 8 do
            pRaid[group] = {}
            for slot = 1, 5 do
                pRaid[group][slot] = {
                    [RR_NAME] = "",
                    [RR_SUBGROUP] = group,
                    [RR_START] = 0,
                    [RR_LOCKED] = 0,
                    [RR_INDEX] = 0,
                }
            end
        end
    end

    local function GetRaidInfo(pRaid)
        if capturedSnapshot then
            for group = 1, 8 do
                for slot, key in ipairs(
                    capturedSnapshot.groups[group] or {}) do
                    pRaid[group][slot][RR_NAME] = key
                    pRaid[group][slot][RR_START] = group
                    pRaid[group][slot][RR_LOCKED] = 0
                    pRaid[group][slot][RR_INDEX] =
                        capturedSnapshot.indexByKey[key] or 0
                end
            end
            return
        end
        local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for raidIndex = 1, GetNumGroupMembers() do
            local name, _, group = GetRaidRosterInfo(raidIndex)
            if name and group and group > 0 then
                counts[group] = counts[group] + 1
                local slot = counts[group]
                if slot <= 5 then
                    pRaid[group][slot][RR_NAME] =
                        PRT:GetRaidMemberIdentityKey(raidIndex, name)
                    pRaid[group][slot][RR_START] = group
                    pRaid[group][slot][RR_LOCKED] = 0
                    pRaid[group][slot][RR_INDEX] = raidIndex
                end
            end
        end
    end

    local function Match(left, right)
        return left[RR_NAME] ~= ""
            and right[RR_NAME] ~= ""
            and left[RR_NAME] == right[RR_NAME]
    end

    local function LockPlayer(raidGroup, targetSlot)
        for slot = 1, 5 do
            if raidGroup[slot][RR_LOCKED] == 0
                and Match(raidGroup[slot], targetSlot) then
                raidGroup[slot][RR_LOCKED] = 1
                return
            end
        end
    end

    local function LockTarget(targetGroup, raidSlot)
        for slot = 1, 5 do
            if Match(targetGroup[slot], raidSlot) then
                raidSlot[RR_LOCKED] = 1
                return
            end
        end
    end

    local function FindUnlockedInRaid(pRaid, targetSlot)
        for _, group in ipairs(groupOrder) do
            for _, slot in ipairs(slotOrder) do
                if pRaid[group][slot][RR_LOCKED] == 0
                    and Match(pRaid[group][slot], targetSlot) then
                    return pRaid[group][slot]
                end
            end
        end
    end

    local function FindUnlockedInGroup(raidGroup, targetGroup)
        local preferred = {}
        for _, slot in ipairs(slotOrder) do
            if raidGroup[slot][RR_LOCKED] == 0 then
                for _, targetSlot in ipairs(slotOrder) do
                    if Match(targetGroup[targetSlot], raidGroup[slot]) then
                        preferred[#preferred + 1] =
                            raidGroup[slot]
                        break
                    end
                end
            end
        end
        if #preferred > 0 then
            return preferred[choiceRandom
                and choiceRandom(#preferred) or 1]
        end
        local empty = {}
        for _, slot in ipairs(slotOrder) do
            if raidGroup[slot][RR_LOCKED] == 0
                and raidGroup[slot][RR_NAME] == "" then
                empty[#empty + 1] = raidGroup[slot]
            end
        end
        if #empty > 0 then
            return empty[choiceRandom
                and choiceRandom(#empty) or 1]
        end
        local available = {}
        for _, slot in ipairs(slotOrder) do
            if raidGroup[slot][RR_LOCKED] == 0 then
                available[#available + 1] = raidGroup[slot]
            end
        end
        if #available > 0 then
            return available[choiceRandom
                and choiceRandom(#available) or 1]
        end
    end

    local function SwapSlots(source, destination)
        source[RR_NAME], destination[RR_NAME] =
            destination[RR_NAME], source[RR_NAME]
        source[RR_INDEX], destination[RR_INDEX] =
            destination[RR_INDEX], source[RR_INDEX]
        source[RR_START], destination[RR_START] =
            destination[RR_START], source[RR_START]
        source[RR_LOCKED] = 1
    end

    local function AddAction(actionType, id1, id2)
        pActionList[#pActionList + 1] = {
            [AL_TYPE] = actionType,
            [AL_ID1] = id1,
            [AL_ID2] = id2,
        }
    end

    local function InvertActions(id1, id2)
        for _, action in ipairs(pActionList) do
            if action[AL_TYPE] == "swap" then
                if action[AL_ID1] == id1 then
                    action[AL_ID1] = id2
                elseif action[AL_ID1] == id2 then
                    action[AL_ID1] = id1
                end
                if action[AL_ID2] == id1 then
                    action[AL_ID2] = id2
                elseif action[AL_ID2] == id2 then
                    action[AL_ID2] = id1
                end
            end
        end
    end

    InitRaid(pSubRaid)
    if requestedOutcomeGroups and capturedSnapshot then
        for group = 1, 8 do
            for slot, key in ipairs(
                requestedOutcomeGroups[group] or {}) do
                pSubRaid[group][slot][RR_NAME] = key
                pSubRaid[group][slot][RR_START] =
                    capturedSnapshot.groupByKey[key] or 0
                pSubRaid[group][slot][RR_LOCKED] = 0
                pSubRaid[group][slot][RR_INDEX] =
                    capturedSnapshot.indexByKey[key] or 0
            end
        end
    else
        GetRaidInfo(pSubRaid)

        for _, group in ipairs(groupOrder) do
            for _, slot in ipairs(slotOrder) do
                LockPlayer(pSubRaid[group], pTarget[group][slot])
            end
        end

        for _, group in ipairs(groupOrder) do
            for _, slot in ipairs(slotOrder) do
                local destination = FindUnlockedInRaid(
                    pSubRaid, pTarget[group][slot])
                if destination then
                    local source = FindUnlockedInGroup(
                        pSubRaid[group],
                        pTarget[destination[RR_SUBGROUP]])
                    if source then
                        SwapSlots(source, destination)
                        if source[RR_NAME] ~= "" then
                            LockTarget(
                                pTarget[destination[RR_SUBGROUP]],
                                destination)
                        end
                    end
                end
            end
        end
    end

    InitRaid(pCurrentRaid)
    GetRaidInfo(pCurrentRaid)

    for _, group in ipairs(groupOrder) do
        for _, slot in ipairs(slotOrder) do
            LockPlayer(pCurrentRaid[group], pSubRaid[group][slot])
        end
    end

    for _, group in ipairs(groupOrder) do
        for _, slot in ipairs(slotOrder) do
            local destination = FindUnlockedInRaid(
                pCurrentRaid, pSubRaid[group][slot])
            if destination then
                local source = FindUnlockedInGroup(
                    pCurrentRaid[group],
                    pSubRaid[destination[RR_SUBGROUP]])
                if source then
                    if source[RR_START] == destination[RR_START] then
                        InvertActions(
                            source[RR_INDEX], destination[RR_INDEX])
                    elseif source[RR_NAME] == "" then
                        AddAction("move", destination[RR_INDEX], group)
                        SwapSlots(source, destination)
                    else
                        AddAction(
                            "swap", source[RR_INDEX], destination[RR_INDEX])
                        SwapSlots(source, destination)
                        LockTarget(
                            pSubRaid[destination[RR_SUBGROUP]], destination)
                    end
                end
            end
        end
    end

    return pActionList
end

local function RotatedOrder(count, offset, reverse)
    local order = {}
    offset = math.floor(tonumber(offset) or 0) % count
    for index = 1, count do
        local base = reverse and (count - index + 1) or index
        order[index] = ((base + offset - 1) % count) + 1
    end
    return order
end

local function SnapshotFromGroups(baseSnapshot, groups)
    local snapshot = {
        groups = CopyGroups(groups),
        indexByKey = {},
        groupByKey = {},
        rankByKey = {},
        keyByIndex = {},
        members = {},
        leaderKey = baseSnapshot.leaderKey,
        count = 0,
    }
    local baseMemberByKey = {}
    for _, member in ipairs(baseSnapshot.members or {}) do
        baseMemberByKey[member.key] = member
    end
    for group = 1, 8 do
        for _, key in ipairs(snapshot.groups[group]) do
            snapshot.count = snapshot.count + 1
            local index = snapshot.count
            local baseMember = baseMemberByKey[key] or {}
            snapshot.indexByKey[key] = index
            snapshot.groupByKey[key] = group
            snapshot.keyByIndex[index] = key
            snapshot.rankByKey[key] =
                baseSnapshot.rankByKey[key] or 0
            snapshot.members[#snapshot.members + 1] = {
                key = key,
                name = baseMember.name,
                index = index,
                rank = snapshot.rankByKey[key],
                group = group,
            }
        end
    end
    snapshot.fingerprint = GroupFingerprint(snapshot.groups)
    return snapshot
end

local function SimulateMembershipActions(snapshot, actions)
    local groups = CopyGroups(snapshot.groups)
    for _, action in ipairs(actions or {}) do
        local actionType, id1, id2 =
            action[1], action[2], action[3]
        if actionType ~= "swap" then
            return nil,
                "candidate simulation is limited to full-raid swaps"
        end
        local firstKey = snapshot.keyByIndex[id1]
        local secondKey = snapshot.keyByIndex[id2]
        if not firstKey or not secondKey
            or not SwapIdentityPositions(
                groups, firstKey, secondKey) then
            return nil, "candidate referenced an unknown roster index"
        end
    end
    return SnapshotFromGroups(snapshot, groups)
end

local function PositionPlanStageCount(plan)
    local pipeline = plan and plan.waves
        and plan.waves[1]
    return pipeline and pipeline.stageCount or 0
end

local function EstimatePositionCleanup(snapshot, target)
    local desiredGroups = BuildDesiredOrders(snapshot, target)
    local totalCalls = 0
    local totalCycles = 0
    local longestCycleCalls = 0

    for group = 1, 8 do
        local members = snapshot.groups[group] or {}
        local desired = desiredGroups[group] or {}
        if #members ~= #desired then return nil end
        local desiredPositionByKey = {}
        for position, key in ipairs(desired) do
            desiredPositionByKey[key] = position
        end
        local visited = {}
        for startPosition = 1, #members do
            if not visited[startPosition]
                and members[startPosition] ~= desired[startPosition] then
                local position = startPosition
                local length = 0
                repeat
                    if visited[position] then return nil end
                    visited[position] = true
                    length = length + 1
                    position =
                        desiredPositionByKey[members[position]]
                    if not position then return nil end
                until position == startPosition
                if length >= 2 then
                    local calls = length + 1
                    totalCalls = totalCalls + calls
                    totalCycles = totalCycles + 1
                    longestCycleCalls =
                        math.max(longestCycleCalls, calls)
                end
            end
        end
    end

    return {
        calls = totalCalls,
        cycles = totalCycles,
        stageLowerBound = math.max(
            longestCycleCalls,
            math.ceil(totalCalls / MAX_CYCLES_PER_WAVE)),
    }
end

local function MembershipSwapLowerBound(snapshot, target)
    local misplaced = 0
    local targetGroupByKey = {}
    for group = 1, 8 do
        for slot = 1, 5 do
            local key = target[group][slot][RR_NAME]
            if key and key ~= "" then
                targetGroupByKey[key] = group
            end
        end
    end
    for key, group in pairs(snapshot.groupByKey or {}) do
        local targetGroup = targetGroupByKey[key]
        if targetGroup and targetGroup ~= group then
            misplaced = misplaced + 1
        end
    end
    return math.ceil(misplaced / 2), misplaced
end

local function PredictBurstSequenceSeconds(
    bursts, startingHistory, predictionNow)
    local elapsed = 0
    local history = {}
    predictionNow = tonumber(predictionNow) or Now()
    for _, timestamp in ipairs(startingHistory or {}) do
        local relative = timestamp - predictionNow
        if relative > -GROUP_ACTION_WINDOW then
            history[#history + 1] = relative
        end
    end
    for _, rawBurstSize in ipairs(bursts or {}) do
        local burstSize = math.max(
            0, math.floor(tonumber(rawBurstSize) or 0))
        if burstSize > 0 then
            local cutoff = elapsed - GROUP_ACTION_WINDOW
            while history[1] and history[1] <= cutoff do
                table.remove(history, 1)
            end
            local overflow =
                #history + burstSize - GROUP_ACTION_LIMIT
            if overflow > 0 then
                elapsed = math.max(
                    elapsed,
                    (history[overflow] or elapsed)
                        + GROUP_ACTION_WINDOW
                        + GROUP_ACTION_GUARD)
                cutoff = elapsed - GROUP_ACTION_WINDOW
                while history[1] and history[1] <= cutoff do
                    table.remove(history, 1)
                end
            end
            for _ = 1, burstSize do
                history[#history + 1] = elapsed
            end
            elapsed = elapsed
                + PREDICTED_ACK_SECONDS
                + PREDICTED_HANDOFF_SECONDS
        end
    end
    return elapsed
end

local function BuildEstimatedBursts(candidate)
    local bursts = {}
    if (candidate.membershipCalls or 0) > 0 then
        bursts[#bursts + 1] = candidate.membershipCalls
    end
    local remaining = candidate.estimatedPositionCalls or 0
    local stages = candidate.estimatedPositionStages or 0
    for stage = 1, stages do
        local stagesLeft = stages - stage + 1
        local burst = math.min(
            MAX_CYCLES_PER_WAVE,
            math.max(0, remaining - (stagesLeft - 1)))
        bursts[#bursts + 1] = burst
        remaining = remaining - burst
    end
    return bursts
end

local function BuildCandidateBursts(candidate, positionPlan)
    local bursts = {}
    if candidate.membershipPlan
        and candidate.membershipPlan.stages then
        for _, stage in ipairs(candidate.membershipPlan.stages) do
            bursts[#bursts + 1] = #stage
        end
    elseif (candidate.membershipCalls or 0) > 0 then
        -- The validated MRT route is one same-frame membership batch.
        bursts[#bursts + 1] = candidate.membershipCalls
    end
    for _, wave in ipairs(
        positionPlan and positionPlan.waves or {}) do
        for _, stage in ipairs(wave.stages or {}) do
            bursts[#bursts + 1] = #stage
        end
    end
    return bursts
end

local function CandidateIsBetter(candidate, best)
    if not best then return true end
    if candidate.predictedSeconds ~= best.predictedSeconds then
        return candidate.predictedSeconds < best.predictedSeconds
    end
    if candidate.totalStages ~= best.totalStages then
        return candidate.totalStages < best.totalStages
    end
    if candidate.totalCalls ~= best.totalCalls then
        return candidate.totalCalls < best.totalCalls
    end
    if candidate.positionStages ~= best.positionStages then
        return candidate.positionStages < best.positionStages
    end
    if candidate.membershipCalls ~= best.membershipCalls then
        return candidate.membershipCalls < best.membershipCalls
    end
    return candidate.positionCalls < best.positionCalls
end

local function EstimateCandidateIsBetter(left, right)
    if left.estimatedSeconds ~= right.estimatedSeconds then
        return left.estimatedSeconds < right.estimatedSeconds
    end
    if left.estimatedTotalStages ~= right.estimatedTotalStages then
        return left.estimatedTotalStages
            < right.estimatedTotalStages
    end
    if left.estimatedTotalCalls ~= right.estimatedTotalCalls then
        return left.estimatedTotalCalls
            < right.estimatedTotalCalls
    end
    if left.estimatedPositionStages
        ~= right.estimatedPositionStages then
        return left.estimatedPositionStages
            < right.estimatedPositionStages
    end
    if left.membershipCalls ~= right.membershipCalls then
        return left.membershipCalls < right.membershipCalls
    end
    return left.estimatedPositionCalls
        < right.estimatedPositionCalls
end

local function HashSearchSeed(snapshot, target)
    local parts = { snapshot.fingerprint or "" }
    for group = 1, 8 do
        for slot = 1, 5 do
            parts[#parts + 1] =
                target[group][slot][RR_NAME] or ""
        end
    end
    local text = table.concat(parts, "|")
    local seed = 1
    for index = 1, #text do
        seed = (seed * 33 + string.byte(text, index))
            % 2147483647
    end
    return math.max(1, seed)
end

local function NewSearchRandom(seed)
    return function(maximum)
        seed = (seed * 48271) % 2147483647
        return (seed % maximum) + 1
    end
end

local function ShuffledOrder(count, random)
    local order = {}
    for index = 1, count do order[index] = index end
    for index = count, 2, -1 do
        local other = random(index)
        order[index], order[other] =
            order[other], order[index]
    end
    return order
end

local function PermuteTargetWithinGroups(target, random)
    local permuted = {}
    for group = 1, 8 do
        permuted[group] = {}
        local order = ShuffledOrder(5, random)
        for position = 1, 5 do
            permuted[group][position] =
                target[group][order[position]]
        end
    end
    return permuted
end

local function BuildBeamTargetMaps(snapshot, target)
    local groupByKey = {}
    local positionByKey = {}
    for group = 1, 8 do
        for position = 1, 5 do
            local key = target[group][position][RR_NAME]
            if key and key ~= ""
                and snapshot.groupByKey[key] then
                groupByKey[key] = group
                positionByKey[key] = position
            end
        end
    end
    local leaderKey = snapshot.leaderKey
    if leaderKey and groupByKey[leaderKey]
        ~= snapshot.groupByKey[leaderKey] then
        return nil, nil,
            "saved composition requests a different raid-leader group"
    end
    return groupByKey, positionByKey
end

local function CountBeamState(state, targetGroupByKey, targetPositionByKey)
    local wrong = 0
    local exact = 0
    for group = 1, 8 do
        for position, key in ipairs(state.groups[group] or {}) do
            if targetGroupByKey[key] ~= group then
                wrong = wrong + 1
            elseif targetPositionByKey[key] == position then
                exact = exact + 1
            end
        end
    end
    state.wrong = wrong
    state.exact = exact
end

local function BeamStateIsBetter(left, right)
    if left.searchScore ~= right.searchScore then
        return left.searchScore < right.searchScore
    end
    if left.exact ~= right.exact then
        return left.exact > right.exact
    end
    if left.wrong ~= right.wrong then
        return left.wrong < right.wrong
    end
    return left.fingerprint < right.fingerprint
end

local function BeamPivotIsBetter(left, right)
    if left.choices ~= right.choices then
        return left.choices < right.choices
    end
    if left.targetGroup ~= right.targetGroup then
        return left.targetGroup < right.targetGroup
    end
    return left.key < right.key
end

local function SelectBeamPivots(
    state, targetGroupByKey, leaderKey, maximum)
    local outgoingByGroup = {}
    for group = 1, 8 do
        local outgoing = 0
        for _, key in ipairs(state.groups[group] or {}) do
            if key ~= leaderKey
                and targetGroupByKey[key] ~= group then
                outgoing = outgoing + 1
            end
        end
        outgoingByGroup[group] = outgoing
    end

    local pivots = {}
    for group = 1, 8 do
        for position, key in ipairs(state.groups[group] or {}) do
            local targetGroup = targetGroupByKey[key]
            if key ~= leaderKey and targetGroup
                and targetGroup ~= group then
                local pivot = {
                    key = key,
                    group = group,
                    position = position,
                    targetGroup = targetGroup,
                    choices = outgoingByGroup[targetGroup] or 0,
                }
                local insertion = #pivots + 1
                while insertion > 1
                    and BeamPivotIsBetter(
                        pivot, pivots[insertion - 1]) do
                    insertion = insertion - 1
                end
                table.insert(pivots, insertion, pivot)
                if maximum and #pivots > maximum then
                    pivots[#pivots] = nil
                end
            end
        end
    end
    return pivots
end

local function CopyBeamGroupsForSwap(
    groups, firstGroup, firstPosition, secondGroup, secondPosition)
    local copy = {}
    for group = 1, 8 do copy[group] = groups[group] end
    copy[firstGroup] = CopyArray(groups[firstGroup])
    if secondGroup ~= firstGroup then
        copy[secondGroup] = CopyArray(groups[secondGroup])
    end
    copy[firstGroup][firstPosition], copy[secondGroup][secondPosition] =
        copy[secondGroup][secondPosition], copy[firstGroup][firstPosition]
    return copy
end

local function MaterializeBeamActions(path, count)
    local actions = {}
    for index = count, 1, -1 do
        actions[index] = path.action
        path = path.parent
    end
    return actions
end

local function EstimateStagedMembershipCount(actions)
    local stageCounts = {}
    local lastStageByKey = {}
    local stageCount = 0
    for _, action in ipairs(actions or {}) do
        local firstKey = action[4]
        local secondKey = action[5]
        if action[1] ~= "swap" or not firstKey or not secondKey then
            return 1
        end
        local stageIndex = math.max(
            lastStageByKey[firstKey] or 0,
            lastStageByKey[secondKey] or 0) + 1
        while (stageCounts[stageIndex] or 0)
            >= MAX_CYCLES_PER_WAVE do
            stageIndex = stageIndex + 1
        end
        stageCounts[stageIndex] =
            (stageCounts[stageIndex] or 0) + 1
        lastStageByKey[firstKey] = stageIndex
        lastStageByKey[secondKey] = stageIndex
        stageCount = math.max(stageCount, stageIndex)
    end
    return stageCount
end

local function BuildStagedMembershipPlan(beforeGroups, actions)
    local stages = {}
    local stageUsedKeys = {}
    local lastStageByKey = {}

    for actionIndex, action in ipairs(actions or {}) do
        local firstKey = action[4]
        local secondKey = action[5]
        if action[1] ~= "swap" or not firstKey or not secondKey then
            return nil,
                "unified membership action was missing identity metadata"
        end

        local stageIndex = math.max(
            lastStageByKey[firstKey] or 0,
            lastStageByKey[secondKey] or 0) + 1
        while stageIndex <= MAX_POSITION_STAGES do
            local entries = stages[stageIndex] or {}
            local used = stageUsedKeys[stageIndex] or {}
            if #entries < MAX_CYCLES_PER_WAVE
                and not used[firstKey]
                and not used[secondKey] then
                break
            end
            stageIndex = stageIndex + 1
        end
        if stageIndex > MAX_POSITION_STAGES then
            return nil,
                "unified membership plan exceeded the stage safety limit"
        end

        stages[stageIndex] = stages[stageIndex] or {}
        stageUsedKeys[stageIndex] =
            stageUsedKeys[stageIndex] or {}
        stages[stageIndex][#stages[stageIndex] + 1] = {
            actionIndex = actionIndex,
            firstKey = firstKey,
            secondKey = secondKey,
        }
        stageUsedKeys[stageIndex][firstKey] = true
        stageUsedKeys[stageIndex][secondKey] = true
        lastStageByKey[firstKey] = stageIndex
        lastStageByKey[secondKey] = stageIndex
    end

    local stagedGroups = CopyGroups(beforeGroups)
    local expectedFingerprints = {}
    for stageIndex, entries in ipairs(stages) do
        for _, entry in ipairs(entries) do
            if not SwapIdentityPositions(
                stagedGroups, entry.firstKey, entry.secondKey) then
                return nil,
                    "unified membership identity could not be simulated"
            end
        end
        expectedFingerprints[stageIndex] =
            GroupFingerprint(stagedGroups)
    end

    return {
        beforeFingerprint = GroupFingerprint(beforeGroups),
        stages = stages,
        stageCount = #stages,
        stageExpectedFingerprints = expectedFingerprints,
        finalFingerprint = GroupFingerprint(stagedGroups),
        totalApiCalls = #(actions or {}),
    }
end

-- Search monotonic cross-group membership routes. Every expansion places the
-- pivot into its requested group, while its partner is either also fixed or
-- remains a valid outgoing mismatch. Completed routes are kept separate from
-- the systematic finalists until both have been fully simulated and scored.
local function GenerateUnifiedBeamCandidates(
    snapshot, target, deadlineMs, consider)
    local targetGroupByKey, targetPositionByKey, blockedReason =
        BuildBeamTargetMaps(snapshot, target)
    if not targetGroupByKey then
        return {
            expanded = 0,
            goals = 0,
            blockedReason = blockedReason,
        }
    end

    local initial = {
        groups = CopyGroups(snapshot.groups),
        actionDepth = 0,
    }
    CountBeamState(initial, targetGroupByKey, targetPositionByKey)
    initial.membershipLowerBound = math.ceil(initial.wrong / 2)
    initial.searchScore =
        initial.membershipLowerBound * 3 - initial.exact
    local maximumMembershipBound =
        initial.membershipLowerBound
            + UNIFIED_BEAM_LOWER_BOUND_SLACK
    initial.fingerprint = GroupFingerprint(initial.groups)
    local frontier = { initial }
    local expanded = 0
    local goals = 0
    local bestGoalCalls
    local deepest = 0
    local frontierPeak = 1

    while #frontier > 0 and PlanningNowMs() < deadlineMs do
        frontierPeak = math.max(frontierPeak, #frontier)
        local nextStates = {}
        local seenNext = {}
        for _, state in ipairs(frontier) do
            if PlanningNowMs() >= deadlineMs then break end
            expanded = expanded + 1
            deepest = math.max(
                deepest, state.actionDepth or 0)
            local pivots = SelectBeamPivots(
                state, targetGroupByKey, snapshot.leaderKey,
                UNIFIED_BEAM_PIVOT_CHOICES)
            for pivotIndex = 1, #pivots do
                local pivot = pivots[pivotIndex]
                local partners = {}
                local includedPartner = {}
                local exactPosition =
                    targetPositionByKey[pivot.key]
                local exactOccupant = exactPosition
                    and state.groups[pivot.targetGroup]
                        [exactPosition]
                if exactOccupant
                    and exactOccupant ~= snapshot.leaderKey
                    and exactOccupant ~= pivot.key then
                    partners[#partners + 1] = {
                        key = exactOccupant,
                        position = exactPosition,
                    }
                    includedPartner[exactOccupant] = true
                end
                for partnerPosition, partnerKey in ipairs(
                    state.groups[pivot.targetGroup] or {}) do
                    if partnerKey ~= snapshot.leaderKey
                        and targetGroupByKey[partnerKey]
                            ~= pivot.targetGroup
                        and not includedPartner[partnerKey] then
                        partners[#partners + 1] = {
                            key = partnerKey,
                            position = partnerPosition,
                        }
                        includedPartner[partnerKey] = true
                    end
                end
                for _, partner in ipairs(partners) do
                    local partnerKey = partner.key
                    if partnerKey ~= pivot.key then
                        local groups = CopyBeamGroupsForSwap(
                            state.groups,
                            pivot.group, pivot.position,
                            pivot.targetGroup, partner.position)
                        local actionDepth = state.actionDepth + 1
                        local path = {
                            parent = state.path,
                            action = {
                                "swap",
                                snapshot.indexByKey[pivot.key],
                                snapshot.indexByKey[partnerKey],
                                pivot.key,
                                partnerKey,
                            },
                        }
                        local beforePartnerWrong =
                            targetGroupByKey[partnerKey]
                                ~= pivot.targetGroup
                                and 1 or 0
                        local afterPartnerWrong =
                            targetGroupByKey[partnerKey]
                                ~= pivot.group
                                and 1 or 0
                        -- The pivot is necessarily in the wrong group, so it
                        -- cannot contribute an exact slot before this swap.
                        local beforeExact = 0
                        if not beforePartnerWrong
                            and targetPositionByKey[partnerKey]
                                == partner.position then
                            beforeExact = beforeExact + 1
                        end
                        local afterExact = 0
                        if targetPositionByKey[pivot.key]
                            == partner.position then
                            afterExact = afterExact + 1
                        end
                        if not afterPartnerWrong
                            and targetPositionByKey[partnerKey]
                                == pivot.position then
                            afterExact = afterExact + 1
                        end
                        local child = {
                            groups = groups,
                            path = path,
                            actionDepth = actionDepth,
                            wrong = state.wrong - 1
                                - beforePartnerWrong
                                + afterPartnerWrong,
                            exact = state.exact - beforeExact
                                + afterExact,
                            fingerprint = GroupFingerprint(groups),
                        }
                        child.membershipLowerBound =
                            actionDepth + math.ceil(child.wrong / 2)
                        child.searchScore =
                            child.membershipLowerBound * 3
                                - child.exact
                        if child.wrong == 0 then
                            deepest = math.max(deepest, actionDepth)
                            goals = goals + 1
                            bestGoalCalls = math.min(
                                bestGoalCalls or actionDepth,
                                actionDepth)
                            consider(MaterializeBeamActions(
                                path, actionDepth), {
                                strategy = "unified-beam",
                                shadowOnly = true,
                            })
                        elseif (not bestGoalCalls
                            or actionDepth
                                < bestGoalCalls
                                    + UNIFIED_BEAM_EXTRA_CALLS)
                            and child.membershipLowerBound
                                <= maximumMembershipBound
                            and not seenNext[child.fingerprint] then
                            seenNext[child.fingerprint] = true
                            nextStates[#nextStates + 1] = child
                        end
                    end
                end
            end
        end
        table.sort(nextStates, BeamStateIsBetter)
        frontier = {}
        for index = 1, math.min(
            #nextStates, UNIFIED_BEAM_WIDTH) do
            frontier[index] = nextStates[index]
        end
    end

    return {
        expanded = expanded,
        goals = goals,
        bestGoalCalls = bestGoalCalls,
        deepest = deepest,
        frontierPeak = frontierPeak,
    }
end

-- Two-tier bounded search:
--   1. Generate many membership outcomes and score their exact permutation
--      cycle cost analytically.
--   2. Run bridge selection and fingerprint simulation only for finalists.
-- The validated 160 systematic candidates and original deterministic plan
-- are always included before time-bounded diverse generation begins.
function PRT:BuildOptimizedGroupPlan(target, snapshot)
    snapshot = snapshot or self:ReadPositionRosterSnapshot()
    local planningStartedMs = PlanningNowMs()
    local predictionNow = Now()
    local predictionHistory =
        CopyArray(self._groupActionTimes or {})
    local baselineActions = self:BuildPositionGroupActions(
        target, { snapshot = snapshot })
    local membershipLowerBound, misplacedPlayers =
        MembershipSwapLowerBound(snapshot, target)
    local result = {
        actions = baselineActions,
        candidates = 0,
        uniqueCandidates = 0,
        validCandidates = 0,
        finalistsEvaluated = 0,
        baselineMembershipCalls = #baselineActions,
        baselinePositionCalls = nil,
        baselinePositionStages = nil,
        bestMembershipCalls = #baselineActions,
        bestPositionCalls = nil,
        bestPositionStages = nil,
        bestGroupOffset = 0,
        bestSlotOffset = 0,
        bestGroupReverse = false,
        bestSlotReverse = false,
        bestStrategy = "baseline",
        membershipLowerBound = membershipLowerBound,
        misplacedPlayers = misplacedPlayers,
        fallback = true,
    }

    if snapshot.count < 40 then
        result.skippedReason =
            "candidate search requires a full 40-player raid"
        result.planningMs = PlanningNowMs() - planningStartedMs
        return result
    end

    local seen = {}
    local validCandidates = {}
    local baselineCandidate
    local function Consider(actions, options)
        result.candidates = result.candidates + 1
        local simulated = SimulateMembershipActions(
            snapshot, actions)
        if not simulated then return end
        local dedupeKey = simulated.fingerprint
            .. "#" .. tostring(#actions)
        if seen[dedupeKey] then return end
        seen[dedupeKey] = true
        result.uniqueCandidates = result.uniqueCandidates + 1

        local membershipMatches =
            MembershipMatchesTarget(simulated, target)
        if not membershipMatches then return end
        local estimate = EstimatePositionCleanup(
            simulated, target)
        if not estimate then return end

        result.validCandidates = result.validCandidates + 1
        local candidate = {
            actions = actions,
            simulated = simulated,
            groupOrder = options.groupOrder,
            slotOrder = options.slotOrder,
            groupOffset = options.groupOffset or 0,
            slotOffset = options.slotOffset or 0,
            groupReverse = options.groupReverse or false,
            slotReverse = options.slotReverse or false,
            strategy = options.strategy or "diverse",
            isBaseline = options.isBaseline or false,
            shadowOnly = options.shadowOnly or false,
            membershipCalls = #actions,
            estimatedPositionCalls = estimate.calls,
            estimatedPositionStages =
                estimate.stageLowerBound,
        }
        candidate.estimatedMembershipStages =
            candidate.shadowOnly and 2 or 1
        candidate.estimatedTotalCalls =
            candidate.membershipCalls
                + candidate.estimatedPositionCalls
        candidate.estimatedTotalStages =
            candidate.estimatedMembershipStages
                + candidate.estimatedPositionStages
        candidate.estimatedSeconds =
            PredictBurstSequenceSeconds(
                BuildEstimatedBursts(candidate),
                predictionHistory, predictionNow)
        validCandidates[#validCandidates + 1] = candidate
        if candidate.isBaseline then
            baselineCandidate = candidate
        end
    end

    Consider(baselineActions, {
        groupOrder = RotatedOrder(8, 0, false),
        slotOrder = RotatedOrder(5, 0, false),
        strategy = "baseline",
        isBaseline = true,
    })

    for groupReverseIndex = 0, 1 do
        for slotReverseIndex = 0, 1 do
            local groupReverse = groupReverseIndex == 1
            local slotReverse = slotReverseIndex == 1
            for groupOffset = 0, 7 do
                for slotOffset = 0, 4 do
                    local actions
                    if groupOffset == 0 and slotOffset == 0
                        and not groupReverse and not slotReverse then
                        -- Candidate 1 was already added above.
                    else
                        actions = self:BuildPositionGroupActions(
                            target,
                            {
                                groupOrder = RotatedOrder(
                                    8, groupOffset, groupReverse),
                                slotOrder = RotatedOrder(
                                    5, slotOffset, slotReverse),
                                snapshot = snapshot,
                            })
                        Consider(actions, {
                            groupOrder = RotatedOrder(
                                8, groupOffset, groupReverse),
                            slotOrder = RotatedOrder(
                                5, slotOffset, slotReverse),
                            groupOffset = groupOffset,
                            slotOffset = slotOffset,
                            groupReverse = groupReverse,
                            slotReverse = slotReverse,
                            strategy = "systematic",
                        })
                    end
                end
            end
        end
    end

    local systematicFinishedMs = PlanningNowMs()
    local generationDeadlineMs = planningStartedMs
        + MEMBERSHIP_GENERATION_BUDGET_MS
    result.permutationCandidates = 0
    if ENABLE_DEEP_ROUTE_RESEARCH then
        local searchRandom = NewSearchRandom(
            HashSearchSeed(snapshot, target))
        while result.permutationCandidates
            < MAX_MRT_PERMUTATION_CANDIDATES
            and PlanningNowMs() < generationDeadlineMs do
            result.permutationCandidates =
                result.permutationCandidates + 1
            local permutedTarget =
                PermuteTargetWithinGroups(target, searchRandom)
            local groupOrder = ShuffledOrder(8, searchRandom)
            local slotOrder = ShuffledOrder(5, searchRandom)
            local actions = self:BuildPositionGroupActions(
                permutedTarget,
                {
                    groupOrder = groupOrder,
                    slotOrder = slotOrder,
                    snapshot = snapshot,
                })
            Consider(actions, {
                groupOrder = groupOrder,
                slotOrder = slotOrder,
                strategy = "mrt-target-permutation",
            })
        end
    end
    result.permutationFinishedMs =
        PlanningNowMs() - systematicFinishedMs
    if ENABLE_DEEP_ROUTE_RESEARCH then
        result.beam = GenerateUnifiedBeamCandidates(
            snapshot, target, generationDeadlineMs, Consider)
    else
        result.beam = {
            expanded = 0,
            goals = 0,
            deepest = 0,
            frontierPeak = 0,
            blockedReason =
                "disabled after live stage-latency regression",
        }
    end
    local generationFinishedMs = PlanningNowMs()
    result.systematicMs =
        systematicFinishedMs - planningStartedMs
    result.generationMs =
        generationFinishedMs - planningStartedMs
    result.beamMs =
        generationFinishedMs - systematicFinishedMs

    table.sort(validCandidates, EstimateCandidateIsBetter)
    for _, candidate in ipairs(validCandidates) do
        if candidate.shadowOnly then
            result.shadowCheapestEstimatedCalls =
                result.shadowCheapestEstimatedCalls
                    or candidate.estimatedTotalCalls
        else
            result.cheapestEstimatedCalls =
                result.cheapestEstimatedCalls
                    or candidate.estimatedTotalCalls
        end
    end

    local finalists = {}
    if baselineCandidate then
        finalists[#finalists + 1] = baselineCandidate
    end
    for _, candidate in ipairs(validCandidates) do
        if #finalists >= MAX_MEMBERSHIP_FINALISTS then break end
        if candidate ~= baselineCandidate
            and not candidate.shadowOnly then
            finalists[#finalists + 1] = candidate
        end
    end
    local shadowFinalists = {}
    for _, candidate in ipairs(validCandidates) do
        if #shadowFinalists
            >= MAX_UNIFIED_SHADOW_FINALISTS then break end
        if candidate.shadowOnly then
            shadowFinalists[#shadowFinalists + 1] = candidate
        end
    end

    local best
    local shadowBest
    local function EvaluateFinalist(candidate)
        if candidate.shadowOnly then
            local rawPlan, rawBlockedReason =
                BuildStagedMembershipPlan(
                    snapshot.groups, candidate.actions)
            if not rawPlan or not rawPlan.stages
                or not rawPlan.stages[1] then
                candidate.membershipBlockedReason =
                    rawBlockedReason
                        or "hybrid route had no safe first stage"
                return false
            end
            local intermediateGroups = CopyGroups(snapshot.groups)
            local prefixCalls = 0
            local bestHybrid
            for prefixStages = 1, math.min(
                3, rawPlan.stageCount or 0) do
                local prefixStage = rawPlan.stages[prefixStages]
                for _, entry in ipairs(prefixStage or {}) do
                    if not SwapIdentityPositions(
                        intermediateGroups,
                        entry.firstKey, entry.secondKey) then
                        candidate.membershipBlockedReason =
                            "hybrid prefix could not be simulated"
                        return false
                    end
                    prefixCalls = prefixCalls + 1
                end
                local intermediateSnapshot =
                    SnapshotFromGroups(
                        snapshot, intermediateGroups)
                local cleanupActions =
                    self:BuildPositionGroupActions(
                        target, { snapshot = intermediateSnapshot })
                local cleanupSnapshot =
                    SimulateMembershipActions(
                        intermediateSnapshot, cleanupActions)
                if cleanupSnapshot
                    and MembershipMatchesTarget(
                        cleanupSnapshot, target) then
                    local cleanupEstimate =
                        EstimatePositionCleanup(
                            cleanupSnapshot, target)
                    if cleanupEstimate then
                        local membershipCalls =
                            prefixCalls + #cleanupActions
                        local membershipStages =
                            #cleanupActions > 0
                                and prefixStages + 1
                                or prefixStages
                        local totalCalls =
                            membershipCalls
                                + cleanupEstimate.calls
                        local totalStages =
                            membershipStages
                                + cleanupEstimate.stageLowerBound
                        local variant = {
                            prefixStages = prefixStages,
                            prefixCalls = prefixCalls,
                            intermediateSnapshot =
                                intermediateSnapshot,
                            cleanupActions = cleanupActions,
                            cleanupSnapshot = cleanupSnapshot,
                            membershipCalls = membershipCalls,
                            membershipStages = membershipStages,
                            totalCalls = totalCalls,
                            totalStages = totalStages,
                        }
                        local variantFits =
                            totalCalls <= GROUP_ACTION_LIMIT
                        local bestFits = bestHybrid
                            and bestHybrid.totalCalls
                                <= GROUP_ACTION_LIMIT
                        if not bestHybrid
                            or (variantFits ~= bestFits
                                and variantFits)
                            or (variantFits == bestFits
                                and (totalStages
                                        < bestHybrid.totalStages
                                    or (totalStages
                                            == bestHybrid.totalStages
                                        and totalCalls
                                            < bestHybrid.totalCalls))) then
                            bestHybrid = variant
                        end
                    end
                end
            end
            if not bestHybrid then
                candidate.membershipBlockedReason =
                    "hybrid MRT cleanup missed target membership"
                return false
            end
            candidate.beamMembershipCalls =
                candidate.membershipCalls
            candidate.hybridPrefixStages =
                bestHybrid.prefixStages
            candidate.hybridPrefixCalls =
                bestHybrid.prefixCalls
            candidate.hybridIntermediateSnapshot =
                bestHybrid.intermediateSnapshot
            candidate.hybridCleanupActions =
                bestHybrid.cleanupActions
            candidate.simulated =
                bestHybrid.cleanupSnapshot
            candidate.membershipCalls =
                bestHybrid.membershipCalls
            candidate.membershipStages =
                bestHybrid.membershipStages
            candidate.strategy =
                ("unified-hybrid-%d-shadow"):format(
                    bestHybrid.prefixStages)
            candidate.executable = false
        else
            candidate.membershipStages =
                candidate.membershipCalls > 0 and 1 or 0
        end
        local positionPlan = self:BuildExactPositionPlan(
            candidate.simulated, target, MAX_CYCLES_PER_WAVE,
            POSITION_CANDIDATE_EXACT_BUDGET_MS)
        if not positionPlan.blockedReason then
            candidate.positionCalls =
                positionPlan.totalApiCalls or 0
            candidate.positionStages =
                PositionPlanStageCount(positionPlan)
            candidate.totalCalls =
                candidate.membershipCalls
                    + candidate.positionCalls
            candidate.totalStages =
                candidate.membershipStages
                    + candidate.positionStages
            candidate.bursts =
                BuildCandidateBursts(candidate, positionPlan)
            candidate.predictedSeconds =
                PredictBurstSequenceSeconds(
                    candidate.bursts,
                    predictionHistory, predictionNow)
            candidate.positionScheduleStrategy =
                positionPlan.scheduleStrategy
            candidate.positionScheduleLowerBound =
                positionPlan.scheduleLowerBound
            candidate.positionGreedyStages =
                positionPlan.greedyStageCount
            if candidate.isBaseline then
                result.baselineMembershipCalls =
                    candidate.membershipCalls
                result.baselinePositionCalls =
                    candidate.positionCalls
                result.baselinePositionStages =
                    candidate.positionStages
            end
            return true
        end
        return false
    end
    for _, candidate in ipairs(finalists) do
        result.finalistsEvaluated =
            result.finalistsEvaluated + 1
        if EvaluateFinalist(candidate)
            and CandidateIsBetter(candidate, best) then
            best = candidate
        end
    end
    result.shadowFinalistsEvaluated = 0
    for _, candidate in ipairs(shadowFinalists) do
        result.shadowFinalistsEvaluated =
            result.shadowFinalistsEvaluated + 1
        if EvaluateFinalist(candidate)
            and CandidateIsBetter(candidate, shadowBest) then
            shadowBest = candidate
        end
    end

    if shadowBest then
        result.shadowMembershipCalls =
            shadowBest.membershipCalls
        result.shadowPositionCalls =
            shadowBest.positionCalls
        result.shadowPositionStages =
            shadowBest.positionStages
        result.shadowMembershipStages =
            shadowBest.membershipStages
        result.shadowTotalStages =
            shadowBest.totalStages
        result.shadowTotalCalls =
            shadowBest.totalCalls
    end
    local selected = best
    if shadowBest
        and shadowBest.executable
        and (not selected
            or shadowBest.totalStages <= selected.totalStages)
        and CandidateIsBetter(shadowBest, selected) then
        selected = shadowBest
        result.unifiedSelected = true
    else
        result.unifiedSelected = false
    end
    if selected then
        result.actions = selected.actions
        result.bestMembershipCalls = selected.membershipCalls
        result.bestPositionCalls = selected.positionCalls
        result.bestPositionStages = selected.positionStages
        result.bestMembershipStages = selected.membershipStages
        result.bestTotalStages = selected.totalStages
        result.bestPredictedSeconds =
            selected.predictedSeconds
        result.bestBursts = selected.bursts
        result.bestPositionScheduleStrategy =
            selected.positionScheduleStrategy
        result.bestPositionScheduleLowerBound =
            selected.positionScheduleLowerBound
        result.bestPositionGreedyStages =
            selected.positionGreedyStages
        result.membershipPlan = selected.membershipPlan
        result.bestGroupOffset = selected.groupOffset
        result.bestSlotOffset = selected.slotOffset
        result.bestGroupReverse = selected.groupReverse
        result.bestSlotReverse = selected.slotReverse
        result.bestStrategy = selected.strategy
        result.fallback = selected.isBaseline
    end
    result.planningMs = PlanningNowMs() - planningStartedMs
    result.overBudget =
        result.planningMs > MEMBERSHIP_SEARCH_BUDGET_MS
    return result
end

---------------------------------------------------------------------------
-- Session lifecycle and acknowledgements
---------------------------------------------------------------------------
local function HasSortAuthority()
    return IsInRaid()
        and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

function PRT:_PositionSortFinishAutoMark(session)
    if not session or session.autoMarkFinished then return end
    session.autoMarkFinished = true
    if self.FinishGroupSwapAutoMark then
        self:FinishGroupSwapAutoMark(session.autoMarkApplications)
    elseif self.OnGroupSwapForAutoMark then
        self:OnGroupSwapForAutoMark(session.compName)
    end
end

function PRT:_PositionSortActivateEventFrame()
    if not self._positionSortFrame then return end
    self._positionSortFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self._positionSortFrame:RegisterEvent("UI_INFO_MESSAGE")
end

function PRT:_PositionSortDeactivateEventFrame()
    if not self._positionSortFrame then return end
    self._positionSortFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self._positionSortFrame:UnregisterEvent("UI_INFO_MESSAGE")
end

function PRT:_PositionSortEndSession(status, message, showNotification)
    local session = self._positionSortSession
    if not session then return end

    self:_PositionSortFinishAutoMark(session)
    session.finished = true
    session.stage = "finished"
    self:_PositionSortDeactivateEventFrame()

    local log = self._positionSortLog
    if log and log.stats then
        log.stats.status = status
        log.endedAt = Now()
    end
    self:PositionSortLog("END status=%s message=%s",
        tostring(status), tostring(message or ""))

    if message and message ~= "" then PRT.Print(message) end
    if showNotification and self.ShowNotification then
        self:ShowNotification(message, { force = true })
    end
end

function PRT:CancelPositionSort(reason)
    local session = self._positionSortSession
    if not session or session.finished then return false end
    session.seq = session.seq + 1
    self:_PositionSortEndSession(
        "cancelled",
        "Position sort cancelled"
            .. (reason and (": " .. reason) or "."),
        false)
    return true
end

local function SessionCanContinue(self, session)
    if not session
        or session.finished
        or self._positionSortSession ~= session then
        return false
    end
    if not HasSortAuthority() then
        self:_PositionSortEndSession(
            "failed",
            "Position sort stopped: leader or assistant required.",
            false)
        return false
    end
    if (InCombatLockdown and InCombatLockdown())
        or UnitAffectingCombat("player") then
        self:_PositionSortEndSession(
            "failed",
            "Position sort stopped because combat began.",
            false)
        return false
    end
    return true
end

local function ScheduleStageCooldown(self, session, label, callback)
    local precedingCalls = math.max(
        1, tonumber(session.lastApiBurstSize) or 1)
    local delay = NEXT_STAGE_DELAY
    session.stage = "cooldown-" .. tostring(label or "stage")
    session.waitToken = (session.waitToken or 0) + 1
    session.settleToken = (session.settleToken or 0) + 1
    local seq = session.seq
    self:PositionSortLog(
        "HANDOFF %s next-frame before next API stage precedingCalls=%d",
        tostring(label or "stage"), precedingCalls)
    C_Timer.After(delay, function()
        if PRT._positionSortSession ~= session
            or session.finished
            or session.seq ~= seq then
            return
        end
        callback()
    end)
end

local function ScheduleForGroupActionBudget(
    self, session, burstSize, label, callback)
    burstSize = math.max(0, tonumber(burstSize) or 0)
    local history = self._groupActionTimes or {}
    self._groupActionTimes = history
    local now = Now()
    local cutoff = now - GROUP_ACTION_WINDOW
    while history[1] and history[1] <= cutoff do
        table.remove(history, 1)
    end

    local overflow = #history + burstSize - GROUP_ACTION_LIMIT
    if overflow <= 0 then return false end

    local releaseTime = (history[overflow] or now)
        + GROUP_ACTION_WINDOW + GROUP_ACTION_GUARD
    local delay = math.max(GROUP_ACTION_GUARD, releaseTime - now)
    session.stage = "rate-limit-" .. tostring(label or "stage")
    session.waitToken = (session.waitToken or 0) + 1
    session.settleToken = (session.settleToken or 0) + 1
    local seq = session.seq
    self:PositionSortLog(
        "RATE_LIMIT_WAIT %s %.2fs history=%d burst=%d limit=%d window=%.2fs",
        tostring(label or "stage"), delay, #history,
        burstSize, GROUP_ACTION_LIMIT, GROUP_ACTION_WINDOW)
    C_Timer.After(delay, function()
        if PRT._positionSortSession ~= session
            or session.finished
            or session.seq ~= seq then
            return
        end
        callback()
    end)
    return true
end

function PRT:_PositionSortArmWait(session, stage, expectedDescription)
    session.stage = stage
    session.waitToken = (session.waitToken or 0) + 1
    session.settleToken = (session.settleToken or 0) + 1
    local waitToken = session.waitToken
    local seq = session.seq
    session.waitStarted = Now()
    session.expectedDescription = expectedDescription
    session.waitSawRosterEvent = false
    self:PositionSortLog("WAIT stage=%s expected=%s",
        stage, tostring(expectedDescription or ""))

    local function PollForAcknowledgement()
        if PRT._positionSortSession ~= session
            or session.finished
            or session.seq ~= seq
            or session.waitToken ~= waitToken
            or session.stage ~= stage then
            return
        end
        if PRT:_PositionSortCheckExpectedState(session) then return end
        C_Timer.After(ACK_POLL_INTERVAL, PollForAcknowledgement)
    end
    C_Timer.After(0, PollForAcknowledgement)

    C_Timer.After(WAIT_TIMEOUT, function()
        if PRT._positionSortSession ~= session
            or session.finished
            or session.seq ~= seq
            or session.waitToken ~= waitToken
            or session.stage ~= stage then
            return
        end
        if PRT:_PositionSortCheckExpectedState(session) then return end
        local liveSnapshot = PRT:ReadPositionRosterSnapshot()
        local stageSequenceStart = session.beforeFingerprint
            or (session.membershipPlan
                and session.membershipPlan.beforeFingerprint)
            or session.positionWaveBeforeFingerprint
        local changedFromStart = stageSequenceStart
            and liveSnapshot.fingerprint ~= stageSequenceStart
        local changedFromWaitStart = session.waitBeforeFingerprint
            and liveSnapshot.fingerprint ~= session.waitBeforeFingerprint
        PRT:PositionSortLog(
            "TIMEOUT stage=%s after=%.3fs sawRosterEvent=%s changedFromStart=%s changedFromWaitStart=%s live=%s",
            stage,
            Now() - (session.waitStarted or Now()),
            tostring(session.waitSawRosterEvent == true),
            tostring(changedFromStart == true),
            tostring(changedFromWaitStart == true),
            liveSnapshot.fingerprint)

        local failureMessage =
            "Position sort timed out. Use /prt sortlog for details."
        if (stage == "wait-membership-stage"
            or stage == "wait-position")
            and (changedFromWaitStart or changedFromStart) then
            PRT:PositionSortLog(
                "WARNING staged bridge stopped in an intermediate roster state")
            failureMessage =
                "Position sort stopped mid-bridge. Left-click the composition to restore group membership, then use /prt sortlog."
        end
        PRT:_PositionSortEndSession(
            "failed",
            failureMessage,
            false)
    end)
end

function PRT:_PositionSortScheduleSettledCheck(session)
    -- A timer alone does not prove that Blizzard has processed the commands.
    -- Only begin a quiet-period mismatch decision after the client has
    -- delivered at least one authoritative roster event for this wait.
    if not session.waitSawRosterEvent then return end
    session.settleToken = (session.settleToken or 0) + 1
    local settleToken = session.settleToken
    local seq = session.seq
    local stage = session.stage
    local delay = (stage == "wait-group"
        or stage == "wait-membership-stage")
        and GROUP_SETTLE_DELAY or POSITION_SETTLE_DELAY

    C_Timer.After(delay, function()
        if PRT._positionSortSession ~= session
            or session.finished
            or session.seq ~= seq
            or session.settleToken ~= settleToken
            or session.stage ~= stage
            or not session.waitSawRosterEvent then
            return
        end
        if PRT:_PositionSortCheckExpectedState(session) then return end

        PRT:PositionSortLog(
            stage == "wait-group"
                and "SETTLED_MISMATCH stage=%s; replanning from live roster"
                or "SETTLED_MISMATCH stage=%s; staged route diverged",
            stage)
        local stats = PRT._positionSortLog.stats
        stats.replans = stats.replans + 1
        session.waitToken = (session.waitToken or 0) + 1

        if stage == "wait-group" then
            PRT:_PositionSortRunGroupPass(session)
        elseif stage == "wait-membership-stage" then
            PRT:PositionSortLog(
                "WARNING membership stage diverged; refusing to compound a dependent route")
            PRT:_PositionSortEndSession(
                "failed",
                "Position-sort membership stage diverged. Left-click the composition to restore group membership, then use /prt sortlog.",
                false)
        elseif stage == "wait-position" then
            PRT:PositionSortLog(
                "WARNING position stage diverged; refusing to compound an intermediate bridge state")
            PRT:_PositionSortEndSession(
                "failed",
                "Position stage diverged. Left-click the composition to restore group membership, then use /prt sortlog.",
                false)
        end
    end)
end

function PRT:_PositionSortAcknowledgeGroup(session, snapshot)
    session.waitToken = session.waitToken + 1
    session.settleToken = session.settleToken + 1
    self:PositionSortLog(
        "ACK membership after %.3fs",
        Now() - (session.waitStarted or Now()))
    self:PositionSortLog("ROSTER after membership\n%s",
        GroupSummary(snapshot.groups))
    ScheduleStageCooldown(
        self, session, "membership-to-position", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortPreparePositionPlan(session)
            end
        end)
end

function PRT:_PositionSortAcknowledgeMembershipStage(session, snapshot)
    local plan = session.membershipPlan
    local stageIndex = session.membershipStageIndex or 1
    local stageCount = plan and plan.stageCount or 0
    session.waitToken = session.waitToken + 1
    session.settleToken = session.settleToken + 1
    self:PositionSortLog(
        "ACK membership stage=%d/%d after %.3fs",
        stageIndex, stageCount,
        Now() - (session.waitStarted or Now()))

    if stageIndex < stageCount then
        session.membershipStageIndex = stageIndex + 1
        ScheduleStageCooldown(
            self, session, "membership-stage", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortExecuteMembershipStage(session)
            end
        end)
        return
    end

    self:PositionSortLog("ROSTER after membership\n%s",
        GroupSummary(snapshot.groups))
    self:_PositionSortFinishAutoMark(session)
    session.membershipPlan = nil
    session.membershipStageIndex = nil
    ScheduleStageCooldown(
        self, session, "membership-to-position", function()
        if SessionCanContinue(PRT, session) then
            PRT:_PositionSortPreparePositionPlan(session)
        end
    end)
end

function PRT:_PositionSortAcknowledgePosition(session, snapshot)
    local wave = session.positionPlan
        and session.positionPlan.waves[session.positionWaveIndex or 0]
    session.waitToken = session.waitToken + 1
    session.settleToken = session.settleToken + 1
    self:PositionSortLog(
        "ACK position wave=%d stage=%d/%d after %.3fs",
        session.positionWaveIndex or 0,
        session.positionStageIndex or 0,
        wave and wave.stageCount or 3,
        Now() - (session.waitStarted or Now()))

    if (session.positionStageIndex or 1)
        < (wave and wave.stageCount or 3) then
        session.positionStageIndex = session.positionStageIndex + 1
        ScheduleStageCooldown(
            self, session, "position-stage", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortExecutePositionWave(session)
            end
        end)
        return
    end

    session.positionWaveIndex = session.positionWaveIndex + 1
    session.positionStageIndex = 1
    if session.positionWaveIndex > #session.positionPlan.waves then
        self:PositionSortLog("ROSTER final\n%s",
            GroupSummary(snapshot.groups))
        local leaderNote = session.positionPlan.leaderAdjustment
            and " (raid leader position retained)" or ""
        self:_PositionSortEndSession(
            "complete",
            ("Exact position sort complete: %s%s."):format(
                session.compName, leaderNote),
            true)
        return
    end
    ScheduleStageCooldown(
        self, session, "position-wave", function()
        if SessionCanContinue(PRT, session) then
            PRT:_PositionSortExecutePositionWave(session)
        end
    end)
end

function PRT:_PositionSortCheckExpectedState(session)
    if not session or session.finished then return false end
    local snapshot = self:ReadPositionRosterSnapshot()

    if session.stage == "wait-group" then
        local matches, detail =
            MembershipMatchesTarget(snapshot, session.target)
        if matches then
            self:_PositionSortAcknowledgeGroup(session, snapshot)
            return true
        end
        session.lastMismatch = detail
    elseif session.stage == "wait-membership-stage" then
        if snapshot.fingerprint == session.expectedFingerprint then
            self:_PositionSortAcknowledgeMembershipStage(
                session, snapshot)
            return true
        end
        session.lastMismatch =
            "membership-stage fingerprint differs"
    elseif session.stage == "wait-position" then
        if snapshot.fingerprint == session.expectedFingerprint then
            self:_PositionSortAcknowledgePosition(session, snapshot)
            return true
        end
        session.lastMismatch = "position fingerprint differs"
    end
    return false
end

function PRT:_PositionSortOnRosterUpdate()
    local session = self._positionSortSession
    if not session or session.finished then return end
    local log = self._positionSortLog
    log.stats.rosterEvents = log.stats.rosterEvents + 1
    session.waitSawRosterEvent = true
    self:PositionSortLog(
        "EVENT GROUP_ROSTER_UPDATE #%d stage=%s",
        log.stats.rosterEvents, tostring(session.stage))

    if tostring(session.stage):match("^cooldown%-") then
        self:PositionSortLog(
            "EVENT ignored during post-roster API cooldown")
        return
    end
    if tostring(session.stage):match("^rate%-limit%-") then
        self:PositionSortLog(
            "EVENT ignored while waiting for group-action budget")
        return
    end

    if not self:_PositionSortCheckExpectedState(session) then
        self:_PositionSortScheduleSettledCheck(session)
    end
end

function PRT:_PositionSortOnInfoMessage(messageType, message)
    local session = self._positionSortSession
    if not session or session.finished then return end
    local throttleMessage = _G and _G.ERR_GROUP_ACTION_THROTTLED
    if not throttleMessage or message ~= throttleMessage then return end

    self:PositionSortLog(
        "SERVER_THROTTLE messageType=%s stage=%s message=%s",
        tostring(messageType), tostring(session.stage), tostring(message))
    self:_PositionSortEndSession(
        "failed",
        "Blizzard throttled a group action. Left-click the composition to restore group membership, then use /prt sortlog.",
        false)
end

---------------------------------------------------------------------------
-- Exact position sort execution
---------------------------------------------------------------------------
function PRT:_PositionSortExecuteMembershipStage(session)
    if not SessionCanContinue(self, session) then return end
    local plan = session.membershipPlan
    local stageIndex = session.membershipStageIndex or 1
    local stageCount = plan and plan.stageCount or 0
    local stageEntries = plan and plan.stages[stageIndex]
    if not plan or not stageEntries then
        self:_PositionSortEndSession(
            "failed",
            "Position-sort membership stage was missing.",
            false)
        return
    end

    local expectedBefore = stageIndex == 1
        and plan.beforeFingerprint
        or plan.stageExpectedFingerprints[stageIndex - 1]
    local snapshot = self:ReadPositionRosterSnapshot()
    if snapshot.fingerprint ~= expectedBefore then
        local expectedAfter =
            plan.stageExpectedFingerprints[stageIndex]
        if snapshot.fingerprint == expectedAfter then
            self:PositionSortLog(
                "LATE_ACK membership stage=%d/%d detected before execution",
                stageIndex, stageCount)
            self:_PositionSortAcknowledgeMembershipStage(
                session, snapshot)
            return
        end
        self:PositionSortLog(
            "PRE_STAGE_DIVERGENCE membership stage=%d/%d expectedBefore=%s live=%s",
            stageIndex, stageCount,
            tostring(expectedBefore), snapshot.fingerprint)
        self._positionSortLog.stats.replans =
            self._positionSortLog.stats.replans + 1
        if stageIndex == 1 then
            session.membershipPlan = nil
            session.membershipStageIndex = nil
            self:_PositionSortRunGroupPass(session)
        else
            self:_PositionSortEndSession(
                "failed",
                "Position-sort membership state diverged mid-route. Left-click the composition to restore group membership, then use /prt sortlog.",
                false)
        end
        return
    end

    local resolved = {}
    for _, entry in ipairs(stageEntries) do
        local firstIndex = snapshot.indexByKey[entry.firstKey]
        local secondIndex = snapshot.indexByKey[entry.secondKey]
        if not firstIndex or not secondIndex then
            self:PositionSortLog(
                "RESOLVE_FAIL membership stage=%d/%d action=%d first=%s second=%s",
                stageIndex, stageCount, entry.actionIndex or 0,
                tostring(firstIndex), tostring(secondIndex))
            self:_PositionSortEndSession(
                "failed",
                "Position-sort membership stage could not resolve a player.",
                false)
            return
        end
        resolved[#resolved + 1] = {
            actionIndex = entry.actionIndex,
            firstIndex = firstIndex,
            secondIndex = secondIndex,
            firstKey = entry.firstKey,
            secondKey = entry.secondKey,
        }
    end

    if ScheduleForGroupActionBudget(
        self, session, #resolved, "membership-stage", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortExecuteMembershipStage(session)
            end
        end) then
        return
    end

    self._positionSortLog.stats.membershipStages =
        (self._positionSortLog.stats.membershipStages or 0) + 1
    session.expectedFingerprint =
        plan.stageExpectedFingerprints[stageIndex]
    session.waitBeforeFingerprint = snapshot.fingerprint
    session.lastApiBurstSize = #resolved
    self:_PositionSortArmWait(
        session,
        "wait-membership-stage",
        ("membership stage %d/%d fingerprint"):format(
            stageIndex, stageCount))
    self:PositionSortLog(
        "EXEC membership stage=%d/%d apiCalls=%d",
        stageIndex, stageCount, #resolved)

    for _, entry in ipairs(resolved) do
        self:_PositionSortSwapRaidSubgroup(
            entry.firstIndex,
            entry.secondIndex,
            "membership",
            ("stage=%d/%d action=%d first=%s second=%s"):format(
                stageIndex, stageCount,
                entry.actionIndex or 0,
                entry.firstKey, entry.secondKey))
    end
end

function PRT:_PositionSortRunGroupPass(session)
    if not SessionCanContinue(self, session) then return end
    session.groupPasses = (session.groupPasses or 0) + 1
    if session.groupPasses > MAX_GROUP_PASSES then
        self:_PositionSortEndSession(
            "failed",
            "Position-sort membership sort exceeded its three-pass safety limit.",
            false)
        return
    end

    local snapshot = self:ReadPositionRosterSnapshot()
    local matches = MembershipMatchesTarget(snapshot, session.target)
    if matches then
        self:PositionSortLog(
            "MEMBERSHIP already correct on pass=%d", session.groupPasses)
        self:_PositionSortFinishAutoMark(session)
        self:_PositionSortPreparePositionPlan(session)
        return
    end

    local optimized = self:BuildOptimizedGroupPlan(
        session.target, snapshot)
    local actions = optimized.actions or {}
    local beam = optimized.beam or {}
    local beamMs = optimized.beamMs or 0
    local statesPerMs = beamMs > 0
        and (beam.expanded or 0) / beamMs or 0
    self._positionSortLog.stats.groupPasses =
        self._positionSortLog.stats.groupPasses + 1
    self:PositionSortLog(
        "PRECOMPUTE membership strategy=systematic-savepoint deepSearch=%s candidates=%d unique=%d valid=%d finalists=%d mrtPermutations=%d permutationMs=%.3f systematicMs=%.3f generationMs=%.3f planningMs=%.3f budgetMs=%d overBudget=%s misplaced=%d membershipLowerBound=%d cheapestEstimate=%s",
        tostring(ENABLE_DEEP_ROUTE_RESEARCH),
        optimized.candidates or 0,
        optimized.uniqueCandidates or 0,
        optimized.validCandidates or 0,
        optimized.finalistsEvaluated or 0,
        optimized.permutationCandidates or 0,
        optimized.permutationFinishedMs or 0,
        optimized.systematicMs or 0,
        optimized.generationMs or 0,
        optimized.planningMs or 0,
        MEMBERSHIP_SEARCH_BUDGET_MS,
        tostring(optimized.overBudget),
        optimized.misplacedPlayers or 0,
        optimized.membershipLowerBound or 0,
        tostring(optimized.cheapestEstimatedCalls or "?"))
    self:PositionSortLog(
        "UNIFIED_SEARCH expanded=%d goals=%d depth=%d frontierPeak=%d beamMs=%.3f statesPerMs=%.3f bestMembership=%s cheapestEstimate=%s finalists=%d predicted=%s+%s calls membershipStages=%s positionStages=%s totalStages=%s total=%s selected=%s blocked=%s",
        beam.expanded or 0,
        beam.goals or 0,
        beam.deepest or 0,
        beam.frontierPeak or 0,
        beamMs,
        statesPerMs,
        tostring(beam.bestGoalCalls or "?"),
        tostring(optimized.shadowCheapestEstimatedCalls or "?"),
        optimized.shadowFinalistsEvaluated or 0,
        tostring(optimized.shadowMembershipCalls or "?"),
        tostring(optimized.shadowPositionCalls or "?"),
        tostring(optimized.shadowMembershipStages or "?"),
        tostring(optimized.shadowPositionStages or "?"),
        tostring(optimized.shadowTotalStages or "?"),
        tostring(optimized.shadowTotalCalls or "?"),
        tostring(optimized.unifiedSelected),
        tostring(beam.blockedReason or "none"))
    self:PositionSortLog(
        "PRECOMPUTE result baseline=%d+%s calls/%s positionStages best=%d+%s calls/%s membershipStages/%s positionStages/%s totalStages predictedSeconds=%s bursts=%s positionScheduler=%s lowerBound=%s greedyStages=%s selected=%s offsets=%d,%d reverse=%s,%s fallback=%s actionLimit=%d",
        optimized.baselineMembershipCalls or 0,
        tostring(optimized.baselinePositionCalls or "?"),
        tostring(optimized.baselinePositionStages or "?"),
        optimized.bestMembershipCalls or #actions,
        tostring(optimized.bestPositionCalls or "?"),
        tostring(optimized.bestMembershipStages or "?"),
        tostring(optimized.bestPositionStages or "?"),
        tostring(optimized.bestTotalStages or "?"),
        optimized.bestPredictedSeconds
            and ("%.2f"):format(
                optimized.bestPredictedSeconds) or "?",
        optimized.bestBursts
            and table.concat(optimized.bestBursts, ",") or "?",
        tostring(
            optimized.bestPositionScheduleStrategy or "?"),
        tostring(
            optimized.bestPositionScheduleLowerBound or "?"),
        tostring(
            optimized.bestPositionGreedyStages or "?"),
        tostring(optimized.bestStrategy or "?"),
        optimized.bestGroupOffset or 0,
        optimized.bestSlotOffset or 0,
        tostring(optimized.bestGroupReverse),
        tostring(optimized.bestSlotReverse),
        tostring(optimized.fallback),
        GROUP_ACTION_LIMIT)
    if optimized.skippedReason then
        self:PositionSortLog(
            "PRECOMPUTE skipped reason=%s",
            optimized.skippedReason)
    end
    self:PositionSortLog(
        "PLAN membership pass=%d actions=%d stages=%d strategy=%s",
        session.groupPasses, #actions,
        optimized.bestMembershipStages or 1,
        tostring(optimized.bestStrategy or "?"))
    if #actions == 0 then
        self:_PositionSortEndSession(
            "failed",
            "Position-sort membership planner could not make progress.",
            false)
        return
    end
    if optimized.membershipPlan then
        session.membershipPlan = optimized.membershipPlan
        session.membershipStageIndex = 1
        self:_PositionSortExecuteMembershipStage(session)
        return
    end
    if ScheduleForGroupActionBudget(
        self, session, #actions, "membership", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortRunGroupPass(session)
            end
        end) then
        -- This pass planned but issued no calls; do not consume a pass from
        -- the safety limit when the budget callback recomputes live indices.
        session.groupPasses = session.groupPasses - 1
        self._positionSortLog.stats.groupPasses =
            self._positionSortLog.stats.groupPasses - 1
        return
    end

    self:_PositionSortArmWait(
        session, "wait-group", "target subgroup membership")
    self._positionSortLog.stats.membershipStages =
        (self._positionSortLog.stats.membershipStages or 0) + 1
    session.lastApiBurstSize = #actions
    for actionIndex, action in ipairs(actions) do
        local actionType, id1, id2 = action[1], action[2], action[3]
        self:PositionSortLog(
            "COMMAND membership %d/%d type=%s",
            actionIndex, #actions, tostring(actionType))
        if actionType == "swap" then
            self:_PositionSortSwapRaidSubgroup(
                id1, id2, "membership",
                ("action=%d/%d"):format(actionIndex, #actions))
        elseif actionType == "move" then
            self:_PositionSortSetRaidSubgroup(
                id1, id2, "membership")
        end
    end
    self:_PositionSortFinishAutoMark(session)

end

function PRT:_PositionSortPreparePositionPlan(session)
    if not SessionCanContinue(self, session) then return end
    local snapshot = self:ReadPositionRosterSnapshot()
    local membershipMatches, detail =
        MembershipMatchesTarget(snapshot, session.target)
    if not membershipMatches then
        self:PositionSortLog(
            "REPLAN membership before positions: %s", tostring(detail))
        self._positionSortLog.stats.replans =
            self._positionSortLog.stats.replans + 1
        self:_PositionSortRunGroupPass(session)
        return
    end

    local plan = self:BuildExactPositionPlan(
        snapshot, session.target, MAX_CYCLES_PER_WAVE,
        POSITION_FINAL_EXACT_BUDGET_MS)
    session.positionPlan = plan
    session.positionWaveIndex = 1
    session.positionStageIndex = 1

    local pipeline = plan.waves[1]
    local stageCount = pipeline and pipeline.stageCount or 0
    self:PositionSortLog(
        "PLAN positions scheduler=%s pipelines=%d sourceWaves=%d stages=%d lowerBound=%d greedyStages=%d exactAttempted=%s exactExpanded=%d exactMs=%.3f exactTimedOut=%s unpipelinedStages=%d savedStages=%d cycles=%d apiCalls=%d stageCap=%d planningMs=%.3f",
        tostring(plan.scheduleStrategy or "greedy"),
        #plan.waves, plan.sourceWaveCount or 0, stageCount,
        plan.scheduleLowerBound or 0,
        plan.greedyStageCount or 0,
        tostring(plan.exactAttempted),
        plan.exactExpanded or 0,
        plan.exactSearchMs or 0,
        tostring(plan.exactTimedOut),
        plan.unpipelinedStageCount or 0,
        math.max(0, (plan.unpipelinedStageCount or 0) - stageCount),
        plan.totalCycles, plan.totalApiCalls or 0,
        MAX_CYCLES_PER_WAVE, plan.planningMs or 0)
    if plan.leaderAdjustment then
        local adjustment = plan.leaderAdjustment
        self:PositionSortLog(
            "LEADER immovable key=%s group=%d requestedPos=%d retainedPos=%d",
            adjustment.key, adjustment.group,
            adjustment.requested, adjustment.retained)
    end
    for waveIndex, wave in ipairs(plan.waves) do
        self:PositionSortLog(
            "PLAN pipeline=%d cycles=%d stages=%d before=%s expected=%s",
            waveIndex, #wave.cycles, wave.stageCount or 0,
            wave.beforeFingerprint, wave.expectedFingerprint)
        for cycleIndex, cycle in ipairs(wave.cycles) do
            self:PositionSortLog(
                "PLAN pipeline=%d cycle=%d sourceWave=%d startStage=%d endStage=%d group=%d length=%d calls=%d pos=%d right=%s wrong=%s bridge=%s",
                waveIndex, cycleIndex, cycle.sourceWave or 0,
                cycle.startStage or 0, cycle.endStage or 0,
                cycle.group,
                #(cycle.memberKeys or {}),
                #(cycle.steps or {}),
                cycle.position,
                cycle.rightKey, cycle.wrongKey, cycle.bridgeKey)
        end
    end

    if plan.blockedReason then
        self:_PositionSortEndSession(
            "failed",
            "Position planning stopped: "
                .. plan.blockedReason,
            false)
        return
    end
    if #plan.waves == 0 then
        local leaderNote = plan.leaderAdjustment
            and "; raid leader position retained" or ""
        self:_PositionSortEndSession(
            "complete",
            ("Exact position sort complete: %s (positions already correct%s).")
                :format(session.compName, leaderNote),
            true)
        return
    end

    self:_PositionSortExecutePositionWave(session)
end

function PRT:_PositionSortExecutePositionWave(session)
    if not SessionCanContinue(self, session) then return end
    local waveIndex = session.positionWaveIndex
    local wave = session.positionPlan
        and session.positionPlan.waves[waveIndex]
    if not wave then
        self:_PositionSortEndSession(
            "failed", "Position wave was missing.", false)
        return
    end

    local stageIndex = session.positionStageIndex or 1
    local stageCount = wave.stageCount or 3
    if stageIndex == 1 then
        session.positionWaveBeforeFingerprint = wave.beforeFingerprint
    end
    local expectedBefore = stageIndex == 1
        and wave.beforeFingerprint
        or wave.stageExpectedFingerprints[stageIndex - 1]
    local snapshot = self:ReadPositionRosterSnapshot()
    if snapshot.fingerprint ~= expectedBefore then
        local expectedAfter =
            wave.stageExpectedFingerprints[stageIndex]
        if snapshot.fingerprint == expectedAfter then
            self:PositionSortLog(
                "LATE_ACK position wave=%d stage=%d/%d detected before execution",
                waveIndex, stageIndex, stageCount)
            self:_PositionSortAcknowledgePosition(session, snapshot)
            return
        end
        self:PositionSortLog(
            "PRE_STAGE_DIVERGENCE wave=%d stage=%d expectedBefore=%s live=%s",
            waveIndex, stageIndex, expectedBefore, snapshot.fingerprint)
        if stageIndex > 1 then
            self:PositionSortLog(
                "WARNING refusing to replan from an open bridge stage")
            self:_PositionSortEndSession(
                "failed",
                "Position state diverged mid-bridge. Left-click the composition to restore group membership, then use /prt sortlog.",
                false)
            return
        end
        self._positionSortLog.stats.replans =
            self._positionSortLog.stats.replans + 1
        self:_PositionSortPreparePositionPlan(session)
        return
    end

    local resolved = {}
    for cycleIndex, cycle in ipairs(wave.cycles) do
        local containsLeader = cycle.bridgeKey == snapshot.leaderKey
        for _, key in ipairs(cycle.memberKeys or {}) do
            if key == snapshot.leaderKey then containsLeader = true end
        end
        if containsLeader then
            self:PositionSortLog(
                "LEADER_CHANGED wave=%d cycle=%d newLeader=%s; replanning",
                waveIndex, cycleIndex, tostring(snapshot.leaderKey))
            self._positionSortLog.stats.replans =
                self._positionSortLog.stats.replans + 1
            self:_PositionSortPreparePositionPlan(session)
            return
        end
    end

    local stageEntries = wave.stages
        and wave.stages[stageIndex] or {}
    for _, entry in ipairs(stageEntries) do
        local firstIndex = snapshot.indexByKey[entry.firstKey]
        local secondIndex = snapshot.indexByKey[entry.secondKey]
        if not firstIndex or not secondIndex then
            self:PositionSortLog(
                "RESOLVE_FAIL pipeline=%d stage=%d cycle=%d first=%s second=%s",
                waveIndex, stageIndex, entry.cycleIndex,
                tostring(firstIndex), tostring(secondIndex))
            self._positionSortLog.stats.replans =
                self._positionSortLog.stats.replans + 1
            self:_PositionSortPreparePositionPlan(session)
            return
        end
        resolved[#resolved + 1] = {
            cycleIndex = entry.cycleIndex,
            cycleStage = entry.cycleStage,
            firstIndex = firstIndex,
            secondIndex = secondIndex,
            firstKey = entry.firstKey,
            secondKey = entry.secondKey,
        }
    end

    if ScheduleForGroupActionBudget(
        self, session, #resolved, "position", function()
            if SessionCanContinue(PRT, session) then
                PRT:_PositionSortExecutePositionWave(session)
            end
        end) then
        return
    end

    local stats = self._positionSortLog.stats
    if stageIndex == 1 then
        stats.positionWaves = stats.positionWaves + 1
        stats.positionCycles = stats.positionCycles + #wave.cycles
    end
    stats.positionStages = stats.positionStages + 1
    session.expectedFingerprint =
        wave.stageExpectedFingerprints[stageIndex]
    session.waitBeforeFingerprint = snapshot.fingerprint
    session.lastApiBurstSize = #resolved
    self:_PositionSortArmWait(
        session,
        "wait-position",
        ("position wave %d stage %d/%d fingerprint"):format(
            waveIndex, stageIndex, stageCount))
    self:PositionSortLog(
        "EXEC pipeline=%d stage=%d/%d activeCycles=%d apiCalls=%d",
        waveIndex, stageIndex, stageCount,
        #stageEntries, #resolved)

    for _, indices in ipairs(resolved) do
        local detailPrefix =
            ("pipeline=%d stage=%d/%d cycle=%d cycleStage=%d first=%s second=%s"):format(
                waveIndex, stageIndex, stageCount,
                indices.cycleIndex, indices.cycleStage or 0,
                indices.firstKey, indices.secondKey)
        self:_PositionSortSwapRaidSubgroup(
            indices.firstIndex,
            indices.secondIndex,
            "position",
            detailPrefix)
    end

end

function PRT:RequestPositionReorder(compName)
    if self._positionSortSession
        and not self._positionSortSession.finished then
        self:CancelPositionSort(
            "a new position sort started")
    end
    self:ResetPositionSortLog(
        "Force-position sort: " .. tostring(compName))
    if self.pendingComp then
        self:PositionSortLog(
            "CANCEL pending fast group sort comp=%s",
            tostring(self.pendingComp))
        self.pendingComp = nil
    end

    local comp = self:GetComp(compName)
    if not comp then
        self._positionSortLog.stats.status = "failed"
        self:PositionSortLog(
            "VALIDATION failed: composition not found")
        PRT.Print("No such composition: " .. tostring(compName))
        return
    end
    if not IsInRaid() then
        self._positionSortLog.stats.status = "failed"
        self:PositionSortLog("VALIDATION failed: not in raid")
        PRT.Print("You must be in a raid to reorder.")
        return
    end
    if not HasSortAuthority() then
        self._positionSortLog.stats.status = "failed"
        self:PositionSortLog(
            "VALIDATION failed: leader or assistant required")
        PRT.Print("You must be raid leader or assistant to reorder.")
        return
    end
    if (InCombatLockdown and InCombatLockdown())
        or UnitAffectingCombat("player") then
        self._positionSortLog.stats.status = "failed"
        self:PositionSortLog("VALIDATION failed: combat")
        PRT.Print("Cannot start position sorting in combat.")
        return
    end

    local target, targetError = self:BuildTarget(comp.roster)
    if not target then
        self._positionSortLog.stats.status = "failed"
        self:PositionSortLog("VALIDATION failed: %s", targetError)
        PRT.Print(targetError)
        return
    end

    self._positionSortSequence =
        (self._positionSortSequence or 0) + 1
    local session = {
        seq = self._positionSortSequence,
        compName = compName,
        target = target,
        stage = "starting",
        startedAt = Now(),
        groupPasses = 0,
        finished = false,
    }
    self._positionSortSession = session
    self:_PositionSortActivateEventFrame()

    self:PositionSortLog(
        "VALIDATION passed rosterCount=%d",
        GetNumGroupMembers())
    local startingSnapshot = self:ReadPositionRosterSnapshot()
    self:PositionSortLog("ROSTER starting\n%s",
        GroupSummary(startingSnapshot.groups))

    PRT.Print("Applying groups: " .. compName .. " (with positions)")
    if self.BeginGroupSwapAutoMark then
        session.autoMarkApplications =
            self:BeginGroupSwapAutoMark(compName)
    end

    self:PositionSortLog("STARTUP next-frame planning handoff")
    C_Timer.After(0, function()
        if SessionCanContinue(PRT, session) then
            PRT:_PositionSortRunGroupPass(session)
        end
    end)
end

function PRT:InitPositionSort()
    if self._positionSortFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "GROUP_ROSTER_UPDATE" then
            PRT:_PositionSortOnRosterUpdate()
        elseif event == "UI_INFO_MESSAGE" then
            PRT:_PositionSortOnInfoMessage(...)
        end
    end)
    self._positionSortFrame = frame
end
