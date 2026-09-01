---------------------------------------------------------------------------
-- Raid Groups input boundary. Exact name helpers and execution engines do
-- not perform base-name matching. Only this layer may accept an unspecified
-- realm, and accepted entries are written as full Name-Realm strings.
---------------------------------------------------------------------------
local _, PRT = ...

function PRT:CopyRealmRoster(source)
    source = source or {}
    local copy = { _prtRealmVersion = source._prtRealmVersion or 1 }
    for i = 1, 40 do
        -- Explicitly saving/editing an old roster freezes its current legacy
        -- meaning. Merely loading it never migrates the saved original.
        copy[i] = self:GetRosterExportName(source, i)
    end
    if type(source._prtRealmAmbiguous) == "table" then
        copy._prtRealmAmbiguous = {}
        for i = 1, 40 do copy._prtRealmAmbiguous[i] = source._prtRealmAmbiguous[i] end
    end
    return copy
end

function PRT:SetRealmRosterSlot(roster, index, value)
    value = self.Trim(value or "")
    if roster[index] == value then return false end
    roster[index] = value
    if roster._prtRealmAmbiguous then roster._prtRealmAmbiguous[index] = nil end
    return true
end

local function Base(raw)
    local name = PRT:SplitNameRealm(raw, false)
    return string.lower(name)
end

function PRT:BuildRealmCandidateIndex(raid)
    local byBase = {}
    for key, info in pairs(raid or {}) do
        local name, realm = info.baseName, info.realm
        if name and name ~= "" and realm and realm ~= "" then
            local base = string.lower(name)
            byBase[base] = byBase[base] or {}
            byBase[base][#byBase[base] + 1] = {
                key = key,
                fullName = self:MakeCharacterFullName(name, realm, true),
                info = info,
            }
        end
    end
    for _, candidates in pairs(byBase) do
        table.sort(candidates, function(a, b) return a.key < b.key end)
    end
    return byBase
end

local function Reservations(roster)
    local claimed, pending = {}, {}
    for i = 1, 40 do
        local key = PRT:GetRosterSlotIdentityKey(roster, i)
        if key and key ~= "" then
            claimed[key] = claimed[key] or i
        elseif key == nil then
            local base = Base(roster[i])
            pending[base] = (pending[base] or 0) + 1
        end
    end
    return claimed, pending
end

local function Available(candidates, claimed, index)
    local available = {}
    for _, candidate in ipairs(candidates) do
        if not claimed[candidate.key] or claimed[candidate.key] == index then
            available[#available + 1] = candidate
        end
    end
    return available
end

-- Mutates only this roster model. Caller decides whether it is an editor
-- buffer or an explicitly autosaved composition. No actions/marks occur.
function PRT:ReconcileRealmRoster(roster, raid, requireServerNames)
    if not roster or roster._prtRealmVersion ~= 1 then return false end
    local byBase = self:BuildRealmCandidateIndex(raid)
    local claimed, pending = Reservations(roster)
    local changed = false
    for i = 1, 40 do
        if self:GetRosterSlotIdentityKey(roster, i) == nil then
            local raw = roster[i]
            local base = Base(raw)
            local candidates = Available(byBase[base] or {}, claimed, i)
            if #candidates > 1 or (pending[base] or 0) > 1 then
                -- Once ambiguity is seen, a subsequent leave must not silently
                -- make the survivor the intended person. Persist with the model.
                roster._prtRealmAmbiguous = roster._prtRealmAmbiguous or {}
                if roster._prtRealmAmbiguous[i] ~= raw then
                    roster._prtRealmAmbiguous[i] = raw
                    changed = true
                end
            elseif #candidates == 1 and not requireServerNames
                and not (roster._prtRealmAmbiguous and roster._prtRealmAmbiguous[i] == raw) then
                self:SetRealmRosterSlot(roster, i, candidates[1].fullName)
                claimed[candidates[1].key] = i
                changed = true
            end
        end
    end
    return changed
end

function PRT:GetRealmRosterStates(roster, raid, dismissals)
    local byBase = self:BuildRealmCandidateIndex(raid)
    local claimed = Reservations(roster)
    local exactDuplicates = self:FindDuplicateRosterSlots(roster)
    local states = {}
    for i = 1, 40 do
        local raw = self.Trim(roster[i] or "")
        local key = self:GetRosterSlotIdentityKey(roster, i)
        local base = Base(raw)
        local candidates = byBase[base] or {}
        local available = Available(candidates, claimed, i)
        local state = { raw = raw, key = key, candidates = candidates, available = available }
        states[i] = state
        if raw ~= "" then
            local live = key and raid[key]
            state.member = live
            state.display = raw
            if exactDuplicates[i] then
                state.kind, state.exactDuplicate = "invalid", exactDuplicates[i]
            elseif live then
                state.display = self:MakeCharacterFullName(live.baseName, live.realm, true)
                -- Another exact slot already accounts for its live identity.
                -- Warn only when a same-base live candidate is still unassigned.
                if #available > 1 then
                    local keys, names = {}, {}
                    for _, candidate in ipairs(available) do
                        keys[#keys + 1] = candidate.key
                        names[candidate.key] = candidate.fullName
                    end
                    table.sort(keys)
                    state.signature = key .. ":" .. table.concat(keys, ",")
                    state.duplicateNames = {}
                    for _, otherKey in ipairs(keys) do state.duplicateNames[#state.duplicateNames + 1] = names[otherKey] end
                    if not dismissals or dismissals[i] ~= state.signature then state.kind = "duplicate" end
                end
            elseif #candidates > 0 then
                state.kind = key == nil and "verify" or "mismatch"
                if #available > 1 then state.kind = "choose" end
                if #available == 0 then state.kind = "claimed" end
                if #available == 1 then
                    state.member = available[1].info -- recognition, NOT acceptance
                    state.display = available[1].fullName
                    state.previewKey = available[1].key
                end
            elseif key == nil then
                state.kind = "waiting"
            end
            state.missing = not live and #candidates == 0
        end
        -- Dismissals expire when the identity set actually changes, not on a
        -- routine redraw. They are session/editor-only, never matching rules.
        if dismissals and dismissals[i] ~= state.signature then dismissals[i] = nil end
    end
    return states
end

function PRT:AcceptRealmRosterCandidate(roster, index, expectedRaw, candidateKey, raid)
    if roster._prtRealmVersion ~= 1 or roster[index] ~= expectedRaw then
        return false, "This cell changed. Review its server warning again."
    end
    local state = self:GetRealmRosterStates(roster, raid)[index]
    if not state or (state.key and raid[state.key]) then
        return false, "The expected player is already present. No replacement was made."
    end
    for _, candidate in ipairs(state.available) do
        if candidate.key == candidateKey then
            self:SetRealmRosterSlot(roster, index, candidate.fullName)
            return true
        end
    end
    return false, "That player left or is assigned to another cell. Review the warning again."
end

function PRT:RefreshRealmCompositions()
    local db = self:GetDB()
    if not db.settings.keepChanges then return end
    local raid = IsInRaid() and self.GetRaidRoster() or {}
    local panel = self.groupsPanel
    local editing = panel and panel:IsVisible() and panel.selectedComp
    local changed = false
    for _, comp in ipairs(db.compositions) do
        if comp.name ~= editing then
            changed = self:ReconcileRealmRoster(comp.roster, raid, db.settings.requireServerNames) or changed
        end
    end
    if changed and self.RefreshFloatingList then self:RefreshFloatingList() end
end

function PRT:InitRosterReconciliation()
    if self._realmReconciliationFrame then return end
    local frame = CreateFrame("Frame")
    self._realmReconciliationFrame = frame
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function()
        -- Defer a frame to avoid consuming a partially updated raid index.
        if frame.queued then return end
        frame.queued = true
        C_Timer.After(0, function()
            frame.queued = nil
            PRT:RefreshRealmCompositions()
        end)
    end)
end
