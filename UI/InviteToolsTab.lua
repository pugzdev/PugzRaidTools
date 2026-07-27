---------------------------------------------------------------------------
-- PugzRaidTools - Invite & Loot Tools Tab
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI

local function SetTopLeft(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", x, y)
end

local function SetTopFill(frame, content, x, y, right)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", right or -10, y)
end

local function CreateBanListPopup()
    local popup = W.CreatePopupFrame("PRTInviteBanListPopup", 430, 340, {
        title = "Blocked Auto-Invite Players",
    })

    local description = W.CreateDescription(popup,
        "Blocked players cannot trigger keyword invites. Names are stored separately for each realm.", {
            width = 402,
            color = { 0.75, 0.75, 0.75 },
        })
    description:SetPoint("TOPLEFT", 12, -32)

    local scroll = W.CreateScrollFrame(popup, 404, 238)
    scroll:SetPoint("TOPLEFT", 12, -76)
    scroll:SetPoint("BOTTOMRIGHT", -12, 14)
    W.StyleBox(scroll, { 0.03, 0.03, 0.03, 0.85 }, PRT.C.BORDER)

    popup.rows = {}

    function PRT:RefreshInviteBanListPopup()
        local entries = self:GetInviteBanEntries()
        popup.titleLabel:SetText(("Blocked Auto-Invite Players (%d)"):format(#entries))

        for _, row in ipairs(popup.rows) do row:Hide() end

        if #entries == 0 then
            if not popup.emptyLabel then
                popup.emptyLabel = W.CreateLabel(scroll.content, "No players are blocked.",
                    PRT.FONT_SIZE, PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])
                popup.emptyLabel:SetPoint("TOPLEFT", 8, -8)
            end
            popup.emptyLabel:Show()
            scroll:UpdateContentHeight(40)
            return
        end

        if popup.emptyLabel then popup.emptyLabel:Hide() end
        for index, entry in ipairs(entries) do
            local row = popup.rows[index]
            if not row then
                local rowColor = index % 2 == 0 and { 0.08, 0.08, 0.08, 0.55 }
                    or { 0.04, 0.04, 0.04, 0.55 }
                row = W.CreateRowFrame(scroll.content, 25)
                W.AddBackground(row, rowColor[1], rowColor[2], rowColor[3], rowColor[4])
                row.nameLabel = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
                row.nameLabel:SetPoint("LEFT", 8, 0)
                row.removeButton = W.CreateButton(row, "Unblock", 66, 20)
                row.removeButton:SetPoint("RIGHT", -4, 0)
                row.removeButton:SetScript("OnClick", function()
                    if row.identityKey then
                        PRT:RemoveInviteBanByKey(row.identityKey)
                    end
                end)
                popup.rows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, -((index - 1) * 25 + 2))
            row:SetPoint("TOPRIGHT", -2, -((index - 1) * 25 + 2))
            row.identityKey = entry.identityKey
            row.nameLabel:SetText(entry.displayName)
            row:Show()
        end
        scroll:UpdateContentHeight(#entries * 25 + 4)
    end

    function PRT:ShowInviteBanListPopup()
        self:RefreshInviteBanListPopup()
        popup:Show()
        popup:BringToFront()
    end

    return popup
end

function PRT:BuildInviteToolsTab()
    local panel = CreateFrame("Frame", nil, UIParent)
    local scroller = W.CreateScrollFrame(panel, 0, 0)
    scroller:SetPoint("TOPLEFT", 10, -8)
    scroller:SetPoint("BOTTOMRIGHT", -10, 8)
    local content = scroller.content

    local title = W.CreateHeader(content, "Invite & Loot Tools")
    local intro = W.CreateDescription(content,
        "Configure raid invites, automatic assistant promotion, loot distribution, loot announcements, and delayed snapshot reinvites.", {
            color = { 0.75, 0.75, 0.75 },
        })

    -----------------------------------------------------------------------
    -- Auto invite
    -----------------------------------------------------------------------
    local inviteHeader = W.CreateHeader(content, "Auto Invite Keywords")
    local inviteDescription = W.CreateDescription(content,
        "An exact, case-insensitive whisper of any keyword sends a group invite. Blocked players are ignored.", {
            color = { 0.75, 0.75, 0.75 },
        })

    local inviteEnabled = W.CreateCheckbox(content, "Enable auto invite from whispers", function(checked)
        PRT:GetDB().inviteTools.autoInvite.enabled = checked and true or false
        PRT:UpdateInviteToolsListeners()
    end)
    inviteEnabled:SetWidth(300)

    local guildOnly = W.CreateCheckbox(content, "Only auto-invite guild members", function(checked)
        PRT:GetDB().inviteTools.autoInvite.guildOnly = checked and true or false
    end)
    guildOnly:SetWidth(300)
    W.AttachTooltip(guildOnly.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Keyword whispers from players outside your guild are ignored.", 1, 1, 1, true },
        },
    })

    local autoAcceptTrusted = W.CreateCheckbox(content,
        "Auto-accept invites from my friends and guild members", function(checked)
            PRT:GetDB().inviteTools.autoInvite.autoAcceptTrusted = checked and true or false
            PRT:UpdateInviteToolsListeners()
        end)
    autoAcceptTrusted:SetWidth(430)
    W.AttachTooltip(autoAcceptTrusted.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "Automatically accepts incoming group invites from character friends, Battle.net friends, and guild members.", 1, 1, 1, true },
            { "Invites from everyone else still require manual confirmation.", 0.72, 0.72, 0.72, true },
        },
    })

    local keywordLabel = W.CreateLabel(content, "Add keyword:", PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local keywordEdit = W.CreateEditBox(content, 250, 22, "e.g. inv")
    local addKeywordButton = W.CreateButton(content, "Add", 58, 22)
    local keywordFeedback = W.CreateLabel(content, "", PRT.FONT_SIZE - 1,
        PRT.C.RED[1], PRT.C.RED[2], PRT.C.RED[3])

    local banListButton = W.CreateButton(content, "Blocked Players (0)", 145, 22)
    banListButton:SetScript("OnClick", function()
        PRT:ShowInviteBanListPopup()
    end)

    local keywordRows = {}
    local noKeywordLabel = W.CreateLabel(content, "No keywords configured.", PRT.FONT_SIZE,
        PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])

    local function AddKeyword()
        local ok, message = PRT:AddInviteKeyword(keywordEdit:GetText())
        if ok then
            keywordEdit:SetText("")
            keywordFeedback:SetText("")
        else
            keywordFeedback:SetText(message or "Unable to add keyword.")
        end
    end
    addKeywordButton:SetScript("OnClick", AddKeyword)
    keywordEdit:SetScript("OnEnterPressed", function(self)
        AddKeyword()
        self:ClearFocus()
    end)

    local raidInvitesHeader = W.CreateLabel(content, "Raid Invites", PRT.FONT_SIZE_HEADER - 1,
        PRT.C.TITLE[1], PRT.C.TITLE[2], PRT.C.TITLE[3])
    local raidInvitesDescription = W.CreateDescription(content,
        "Automatically converts to a raid after the party is filled. Re-invites queued players whose auto-invites were limited by the full party.", {
            color = { 0.75, 0.75, 0.75 },
        })
    local raidInvitesEnabled = W.CreateCheckbox(content,
        "Auto-convert to raid when party is full and auto-invite is requested.", function(checked)
            PRT:SetRaidInvitesEnabled(checked, false)
        end)
    raidInvitesEnabled:SetWidth(510)
    local raidInvitesCommand = W.CreateLabel(content,
        "/prt invites on  |  /prt invites off", PRT.FONT_SIZE - 1,
        PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])

    -----------------------------------------------------------------------
    -- Auto promote
    -----------------------------------------------------------------------
    local promoteHeader = W.CreateHeader(content, "Auto Promote")
    local promoteDescription = W.CreateDescription(content,
        "Automatically promote listed raid members, plus guild members at or above the selected rank. Manual demotions are respected for the current session.", {
            color = { 0.75, 0.75, 0.75 },
        })
    local promoteEnabled = W.CreateCheckbox(content, "Enable auto promote", function(checked)
        PRT:GetDB().inviteTools.autoPromote.enabled = checked and true or false
        PRT:UpdateInviteToolsListeners()
        if checked then PRT:RequestAutoPromote() end
    end)
    promoteEnabled:SetWidth(260)

    local promoteNamesLabel = W.CreateLabel(content, "Player names (space or comma separated):",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local promoteNamesEdit = W.CreateEditBox(content, 470, 22, "PlayerOne PlayerTwo-Realm")
    promoteNamesEdit:SetMaxLetters(2048)
    promoteNamesEdit:SetScript("OnEditFocusLost", function(self)
        PRT:GetDB().inviteTools.autoPromote.names = PRT.Trim(self:GetText())
        if PRT:GetDB().inviteTools.autoPromote.enabled then
            PRT:RequestAutoPromote()
        end
    end)

    local guildRankLabel = W.CreateLabel(content, "Guild promotion threshold:",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local guildRankDropdown = W.CreateDropdown(content, 300, {}, function(value)
        PRT:GetDB().inviteTools.autoPromote.guildRankThreshold = tonumber(value) or 0
        if PRT:GetDB().inviteTools.autoPromote.enabled then
            PRT:RequestAutoPromote()
        end
    end)

    -----------------------------------------------------------------------
    -- Loot configuration
    -----------------------------------------------------------------------
    local lootHeader = W.CreateHeader(content, "Loot Distribution Prompt")
    local lootDescription = W.CreateDescription(content,
        "When you enter a checked zone as group leader, or gain leadership there, PRT asks before applying these settings. It never continuously enforces them.", {
            color = { 0.75, 0.75, 0.75 },
        })
    local lootEnabled = W.CreateCheckbox(content, "Enable loot setup prompts", function(checked)
        PRT:GetDB().inviteTools.loot.enabled = checked and true or false
        PRT:UpdateInviteToolsListeners()
        if checked then PRT:ResetInviteLootPromptState() end
    end)
    lootEnabled:SetWidth(270)

    local lootMethodLabel = W.CreateLabel(content, "Loot method:",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local lootMethodDropdown = W.CreateDropdown(content, 220, PRT.INVITE_LOOT_METHODS, function(value)
        PRT:GetDB().inviteTools.loot.method = value
    end)

    local assignMasterLooter = W.CreateCheckbox(content,
        "Automatically assign the configured master looter", function(checked)
            PRT:GetDB().inviteTools.loot.assignMasterLooter = checked and true or false
        end)
    assignMasterLooter:SetWidth(390)
    W.AttachTooltip(assignMasterLooter.check, {
        anchor = "ANCHOR_TOP",
        lines = {
            { "When disabled, applying Master Loot keeps the current master looter unchanged.", 1, 1, 1, true },
            { "PRT will not enable Master Loot from another loot method unless an assignee is configured.", 0.72, 0.72, 0.72, true },
        },
    })

    local masterLooterLabel = W.CreateLabel(content, "Master looter to assign:",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local masterLooterEdit = W.CreateEditBox(content, 300, 22, "PlayerName or PlayerName-Realm")
    masterLooterEdit:SetMaxLetters(77)
    masterLooterEdit:SetScript("OnEditFocusLost", function(self)
        PRT:GetDB().inviteTools.loot.masterLooter = PRT.Trim(self:GetText())
    end)

    local lootThresholdLabel = W.CreateLabel(content, "Loot threshold:",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local lootThresholdDropdown = W.CreateDropdown(content, 220, PRT.INVITE_LOOT_THRESHOLDS, function(value)
        PRT:GetDB().inviteTools.loot.threshold = tonumber(value) or 1
    end)

    local onlyRaid = W.CreateCheckbox(content, "Only apply while in a raid group", function(checked)
        PRT:GetDB().inviteTools.loot.onlyInRaid = checked and true or false
    end)
    onlyRaid:SetWidth(290)

    local zonesLabel = W.CreateLabel(content, "Apply in these zones:",
        PRT.FONT_SIZE, 0.82, 0.82, 0.82)
    local zoneChecks = {}
    for _, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
        local zoneInfo = zone
        local checkbox = W.CreateCheckbox(content, zoneInfo.name, function(checked)
            PRT:GetDB().inviteTools.loot.zones[zoneInfo.key] = checked and true or false
        end)
        checkbox:SetWidth(250)
        zoneChecks[zoneInfo.key] = checkbox
    end

    -----------------------------------------------------------------------
    -- Loot to Chat
    -----------------------------------------------------------------------
    local lootChatHeader = W.CreateHeader(content, "Loot to Chat")
    local lootChatDescription = W.CreateDescription(content,
        "Automatically links Epic-or-higher items from raid loot windows to group chat once per loot source. Use /prt loot to link the current loot window manually.", {
            color = { 0.75, 0.75, 0.75 },
        })
    local lootChatEnabled = W.CreateCheckbox(content,
        "Automatically link raid loot to chat", function(checked)
            PRT:GetDB().inviteTools.lootToChat.enabled = checked and true or false
            PRT:UpdateInviteToolsListeners()
        end)
    lootChatEnabled:SetWidth(310)
    local lootChatItemLevel = W.CreateCheckbox(content,
        "Include item level", function(checked)
            PRT:GetDB().inviteTools.lootToChat.includeItemLevel = checked and true or false
        end)
    lootChatItemLevel:SetWidth(220)

    -----------------------------------------------------------------------
    -- Raid disband and reinvites
    -----------------------------------------------------------------------
    local raidHeader = W.CreateHeader(content, "Raid Disband and Reinvites")
    local raidDescription = W.CreateDescription(content,
        "/prt disband saves everyone currently in the group before removing them. /prt reinv can be used later to invite that saved roster.", {
            color = { 0.75, 0.75, 0.75 },
        })
    local disbandButton = W.CreateButton(content, "Save Snapshot & Disband", 190, 24)
    disbandButton:SetScript("OnClick", function() PRT:DisbandWithSnapshot() end)
    local reinviteButton = W.CreateButton(content, "Reinvite Snapshot", 160, 24)
    reinviteButton:SetScript("OnClick", function() PRT:ReinviteSnapshot() end)
    local snapshotLabel = W.CreateLabel(content, "", PRT.FONT_SIZE,
        PRT.C.GRAY[1], PRT.C.GRAY[2], PRT.C.GRAY[3])

    CreateBanListPopup()

    -----------------------------------------------------------------------
    -- Dynamic refresh and layout
    -----------------------------------------------------------------------
    local function RefreshGuildRanks(cfg)
        local items = {
            { text = "Explicit names only", value = 0 },
        }
        if IsInGuild and IsInGuild() and GuildControlGetNumRanks and GuildControlGetRankName then
            local rankCount = GuildControlGetNumRanks() or 0
            for rank = 1, rankCount do
                local rankName = GuildControlGetRankName(rank)
                if rankName and rankName ~= "" then
                    items[#items + 1] = {
                        text = rankName .. " and higher",
                        value = rank,
                    }
                end
            end
        end
        guildRankDropdown:SetItems(items)
        guildRankDropdown:SetSelected(tonumber(cfg.guildRankThreshold) or 0)
    end

    local function LayoutAndRefreshKeywords(cfg)
        for _, row in ipairs(keywordRows) do row:Hide() end

        local y = -10
        SetTopLeft(title, 2, y)
        y = y - 25
        SetTopFill(intro, content, 2, y)
        y = y - 40

        SetTopLeft(inviteHeader, 2, y)
        y = y - 24
        SetTopFill(inviteDescription, content, 2, y)
        y = y - 37
        SetTopLeft(inviteEnabled, 2, y)
        banListButton:ClearAllPoints()
        banListButton:SetPoint("LEFT", inviteEnabled, "LEFT", 310, 0)
        y = y - 25
        SetTopLeft(guildOnly, 2, y)
        y = y - 25
        SetTopLeft(autoAcceptTrusted, 2, y)
        y = y - 31
        SetTopLeft(keywordLabel, 2, y)
        y = y - 19
        SetTopLeft(keywordEdit, 2, y)
        addKeywordButton:ClearAllPoints()
        addKeywordButton:SetPoint("LEFT", keywordEdit, "RIGHT", 6, 0)
        keywordFeedback:ClearAllPoints()
        keywordFeedback:SetPoint("LEFT", addKeywordButton, "RIGHT", 8, 0)
        y = y - 29

        if #cfg.keywords == 0 then
            SetTopLeft(noKeywordLabel, 8, y)
            noKeywordLabel:Show()
            y = y - 25
        else
            noKeywordLabel:Hide()
            for index, keyword in ipairs(cfg.keywords) do
                local row = keywordRows[index]
                if not row then
                    local rowColor = index % 2 == 0 and { 0.08, 0.08, 0.08, 0.55 }
                        or { 0.04, 0.04, 0.04, 0.55 }
                    row = W.CreateRowFrame(content, 24)
                    W.AddBackground(row, rowColor[1], rowColor[2], rowColor[3], rowColor[4])
                    row.keywordLabel = W.CreateLabel(row, "", PRT.FONT_SIZE, 1, 1, 1)
                    row.keywordLabel:SetPoint("LEFT", 8, 0)
                    row.removeButton = W.CreateDeleteButton(row, function()
                        if row.keywordIndex then
                            PRT:RemoveInviteKeyword(row.keywordIndex)
                        end
                    end, {
                        text = "Remove",
                        width = 66,
                        height = 20,
                    })
                    row.removeButton:SetPoint("RIGHT", -3, 0)
                    keywordRows[index] = row
                end
                row.keywordIndex = index
                row.keywordLabel:SetText(keyword)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 2, y)
                row:SetPoint("TOPRIGHT", content, "TOPLEFT", 470, y)
                row:Show()
                y = y - 25
            end
        end

        y = y - 12
        SetTopLeft(raidInvitesHeader, 2, y)
        y = y - 22
        SetTopFill(raidInvitesDescription, content, 2, y)
        y = y - 43
        SetTopLeft(raidInvitesEnabled, 2, y)
        raidInvitesCommand:ClearAllPoints()
        raidInvitesCommand:SetPoint("LEFT", raidInvitesEnabled, "LEFT", 540, 0)
        y = y - 28

        return y - 10
    end

    local function LayoutRemaining(y)
        -- Raid disband and reinvites sits directly below Auto Invite.
        y = y - 10
        SetTopLeft(raidHeader, 2, y)
        y = y - 24
        SetTopFill(raidDescription, content, 2, y)
        y = y - 43
        SetTopLeft(disbandButton, 2, y)
        reinviteButton:ClearAllPoints()
        reinviteButton:SetPoint("LEFT", disbandButton, "RIGHT", 8, 0)
        y = y - 31
        SetTopLeft(snapshotLabel, 2, y)
        y = y - 40

        -- Small visual gap between sections.
        SetTopLeft(promoteHeader, 2, y)
        y = y - 24
        SetTopFill(promoteDescription, content, 2, y)
        y = y - 52
        SetTopLeft(promoteEnabled, 2, y)
        y = y - 31
        SetTopLeft(promoteNamesLabel, 2, y)
        y = y - 19
        SetTopLeft(promoteNamesEdit, 2, y)
        y = y - 31
        SetTopLeft(guildRankLabel, 2, y)
        y = y - 19
        SetTopLeft(guildRankDropdown, 2, y)
        y = y - 52

        SetTopLeft(lootHeader, 2, y)
        y = y - 24
        SetTopFill(lootDescription, content, 2, y)
        y = y - 52
        SetTopLeft(lootEnabled, 2, y)
        y = y - 31
        SetTopLeft(lootMethodLabel, 2, y)
        lootThresholdLabel:ClearAllPoints()
        lootThresholdLabel:SetPoint("TOPLEFT", 250, y)
        y = y - 19
        SetTopLeft(lootMethodDropdown, 2, y)
        lootThresholdDropdown:ClearAllPoints()
        lootThresholdDropdown:SetPoint("TOPLEFT", 250, y)
        y = y - 31
        SetTopLeft(assignMasterLooter, 2, y)
        y = y - 31
        SetTopLeft(masterLooterLabel, 2, y)
        y = y - 19
        SetTopLeft(masterLooterEdit, 2, y)
        y = y - 31
        SetTopLeft(onlyRaid, 2, y)
        y = y - 31
        SetTopLeft(zonesLabel, 2, y)
        y = y - 22
        for index, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            SetTopLeft(zoneChecks[zone.key], 2 + column * 250, y - row * 24)
        end
        y = y - math.ceil(#PRT.INVITE_LOOT_ZONES / 2) * 24 - 24

        SetTopLeft(lootChatHeader, 2, y)
        y = y - 24
        SetTopFill(lootChatDescription, content, 2, y)
        y = y - 43
        SetTopLeft(lootChatEnabled, 2, y)
        y = y - 25
        SetTopLeft(lootChatItemLevel, 2, y)
        y = y - 34

        scroller:UpdateContentHeight(-y)
    end

    function panel:Refresh()
        local cfg = PRT:GetDB().inviteTools
        inviteEnabled:SetChecked(cfg.autoInvite.enabled)
        guildOnly:SetChecked(cfg.autoInvite.guildOnly)
        autoAcceptTrusted:SetChecked(cfg.autoInvite.autoAcceptTrusted)
        raidInvitesEnabled:SetChecked(PRT:GetRaidInvitesEnabled())
        promoteEnabled:SetChecked(cfg.autoPromote.enabled)
        lootEnabled:SetChecked(cfg.loot.enabled)
        assignMasterLooter:SetChecked(cfg.loot.assignMasterLooter)
        onlyRaid:SetChecked(cfg.loot.onlyInRaid)
        lootChatEnabled:SetChecked(cfg.lootToChat.enabled)
        lootChatItemLevel:SetChecked(cfg.lootToChat.includeItemLevel)

        if not promoteNamesEdit:HasFocus() then
            promoteNamesEdit:SetText(cfg.autoPromote.names or "")
        end
        RefreshGuildRanks(cfg.autoPromote)
        lootMethodDropdown:SetSelected(cfg.loot.method or "group")
        lootThresholdDropdown:SetSelected(tonumber(cfg.loot.threshold) or 1)
        if not masterLooterEdit:HasFocus() then
            masterLooterEdit:SetText(cfg.loot.masterLooter or "")
        end
        for _, zone in ipairs(PRT.INVITE_LOOT_ZONES) do
            zoneChecks[zone.key]:SetChecked(cfg.loot.zones[zone.key])
        end

        local banCount = #PRT:GetInviteBanEntries()
        banListButton:SetLabel(("Blocked Players (%d)"):format(banCount))

        local snapshot = cfg.reinviteSnapshot or {}
        local memberCount = snapshot.members and #snapshot.members or 0
        if memberCount == 0 then
            snapshotLabel:SetText("No disband snapshot saved.")
        else
            local when = ""
            if snapshot.createdAt and snapshot.createdAt > 0 and date then
                when = " on " .. date("%Y-%m-%d at %H:%M", snapshot.createdAt)
            end
            snapshotLabel:SetText(("Saved snapshot: %d player%s%s.")
                :format(memberCount, memberCount == 1 and "" or "s", when))
        end

        local y = LayoutAndRefreshKeywords(cfg.autoInvite)
        LayoutRemaining(y)
    end

    function panel:OnShow()
        self:Refresh()
    end

    PRT.inviteToolsPanel = panel
    PRT:RegisterTab("invitetools", panel)
end
