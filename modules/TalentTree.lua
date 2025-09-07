-- TalentTreeOverhaul.lua - Unified Talent Tree Display for Fizzure
local TalentTreeModule = {}

TalentTreeModule.name = "Talent Tree Overhaul"
TalentTreeModule.version = "1.0"
TalentTreeModule.author = "Fizzure"
TalentTreeModule.category = "UI/UX"

function TalentTreeModule:GetDefaultSettings()
    return {
        enabled = true,
        replaceDefaultFrame = true,
        showAllSpecs = true,
        compactView = false,
        showTalentTooltips = true,
        showPointsRemaining = true,
        showTalentPreview = true,
        treeSpacing = 10,
        talentSize = 32,
        windowWidth = 1000,
        windowHeight = 600
    }
end

function TalentTreeModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.replaceDefaultFrame) == "boolean" and
            type(settings.showAllSpecs) == "boolean"
end

function TalentTreeModule:Initialize()
    if not self.Fizzure then
        print("|cffff0000TalentTree Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize talent data storage
    self.talentData = {}
    self.classInfo = {}

    -- Get player class info
    local _, playerClass = UnitClass("player")
    self.playerClass = playerClass

    -- Create the unified talent frame
    self:CreateUnifiedTalentFrame()

    -- Hook the original talent frame if replacing
    if self.settings.replaceDefaultFrame then
        self:HookTalentFrame()
    end

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("TALENT_TREE_CHANGED")
    self.eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        TalentTreeModule:OnEvent(event, ...)
    end)

    -- Initialize talent data
    self:LoadTalentData()

    print("|cff00ff00Talent Tree Module|r Initialized")
    return true
end

function TalentTreeModule:Shutdown()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.unifiedFrame then
        self.unifiedFrame:Hide()
    end

    self:UnhookTalentFrame()
end

function TalentTreeModule:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_TalentUI" then
            if self.settings.replaceDefaultFrame then
                self:HookTalentFrame()
            end
        end
    elseif event == "TALENT_TREE_CHANGED" or
            event == "CHARACTER_POINTS_CHANGED" or
            event == "PLAYER_TALENT_UPDATE" then
        self:LoadTalentData()
        self:UpdateTalentDisplay()
    end
end

function TalentTreeModule:CreateUnifiedTalentFrame()
    -- Create main window
    self.unifiedFrame = FizzureUI:CreateWindow("FizzureUnifiedTalents", "Talent Trees - " .. UnitName("player"),
            self.settings.windowWidth, self.settings.windowHeight)

    -- Create header with talent points info
    self:CreateTalentHeader()

    -- Create the main content area
    self:CreateTalentContent()

    -- Create control buttons
    self:CreateTalentControls()

    self.unifiedFrame:Hide()
end

function TalentTreeModule:CreateTalentHeader()
    local header = CreateFrame("Frame", nil, self.unifiedFrame.content)
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 10, -5)
    header:SetPoint("TOPRIGHT", -10, -5)

    -- Available talent points
    self.talentPointsLabel = FizzureUI:CreateLabel(header, "Talent Points: 0", "GameFontNormalLarge")
    self.talentPointsLabel:SetPoint("LEFT", 10, 0)

    -- Level info
    self.levelLabel = FizzureUI:CreateLabel(header, "Level " .. UnitLevel("player"), "GameFontNormal")
    self.levelLabel:SetPoint("RIGHT", -10, 0)

    self.headerFrame = header
end

function TalentTreeModule:CreateTalentContent()
    local contentFrame = CreateFrame("Frame", nil, self.unifiedFrame.content)
    contentFrame:SetPoint("TOPLEFT", 10, -50)
    contentFrame:SetPoint("BOTTOMRIGHT", -10, 40)

    -- Create scroll frame for all talent trees
    self.talentScroll = CreateFrame("ScrollFrame", "FizzureTalentScroll", contentFrame, "UIPanelScrollFrameTemplate")
    self.talentScroll:SetAllPoints()

    local scrollContent = CreateFrame("Frame", "FizzureTalentScrollContent", self.talentScroll)
    scrollContent:SetSize(self.settings.windowWidth - 50, 1)
    self.talentScroll:SetScrollChild(scrollContent)
    self.talentScrollContent = scrollContent

    -- Enable mousewheel
    self.talentScroll:EnableMouseWheel(true)
    self.talentScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 20), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)

    self.contentFrame = contentFrame
end

function TalentTreeModule:CreateTalentControls()
    local controls = CreateFrame("Frame", nil, self.unifiedFrame.content)
    controls:SetHeight(30)
    controls:SetPoint("BOTTOMLEFT", 10, 5)
    controls:SetPoint("BOTTOMRIGHT", -10, 5)

    -- Reset talents button
    local resetBtn = FizzureUI:CreateButton(controls, "Reset Talents", 100, 24, function()
        self:ShowResetConfirmation()
    end)
    resetBtn:SetPoint("LEFT", 10, 0)

    -- Learn talents button
    local learnBtn = FizzureUI:CreateButton(controls, "Learn Talents", 100, 24, function()
        self:LearnTalents()
    end)
    learnBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)

    -- Close button
    local closeBtn = FizzureUI:CreateButton(controls, "Close", 80, 24, function()
        self.unifiedFrame:Hide()
    end)
    closeBtn:SetPoint("RIGHT", -10, 0)

    -- Preview mode toggle
    local previewBtn = FizzureUI:CreateButton(controls, "Preview Mode", 100, 24, function()
        self:TogglePreviewMode()
    end)
    previewBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)

    self.controlsFrame = controls
    self.resetBtn = resetBtn
    self.learnBtn = learnBtn
    self.previewBtn = previewBtn
end

function TalentTreeModule:LoadTalentData()
    if not GetNumTalentTabs then return end

    self.talentData = {}
    local numTabs = GetNumTalentTabs()

    for tabIndex = 1, numTabs do
        local tabName, iconTexture, pointsSpent, fileName = GetTalentTabInfo(tabIndex)

        self.talentData[tabIndex] = {
            name = tabName,
            icon = iconTexture,
            pointsSpent = pointsSpent,
            fileName = fileName,
            talents = {}
        }

        local numTalents = GetNumTalents(tabIndex)
        for talentIndex = 1, numTalents do
            local nameTalent, iconPath, tier, column, currentRank, maxRank, isExceptional, meetsPrereq = GetTalentInfo(tabIndex, talentIndex)

            if nameTalent then
                self.talentData[tabIndex].talents[talentIndex] = {
                    name = nameTalent,
                    icon = iconPath,
                    tier = tier,
                    column = column,
                    currentRank = currentRank,
                    maxRank = maxRank,
                    isExceptional = isExceptional,
                    meetsPrereq = meetsPrereq,
                    tabIndex = tabIndex,
                    talentIndex = talentIndex
                }
            end
        end
    end
end

function TalentTreeModule:UpdateTalentDisplay()
    if not self.unifiedFrame or not self.unifiedFrame:IsShown() then return end

    -- Update header
    local availablePoints = UnitCharacterPoints("player")
    self.talentPointsLabel:SetText("Talent Points: " .. availablePoints)
    self.levelLabel:SetText("Level " .. UnitLevel("player"))

    -- Clear existing talent display
    local content = self.talentScrollContent
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    -- Rebuild talent trees
    self:BuildTalentTrees()
end

function TalentTreeModule:BuildTalentTrees()
    local content = self.talentScrollContent
    local numTabs = #self.talentData

    if numTabs == 0 then return end

    local treeWidth = (self.settings.windowWidth - 80) / numTabs
    local xOffset = 10

    for tabIndex = 1, numTabs do
        local tabData = self.talentData[tabIndex]
        if tabData then
            self:CreateTalentTree(content, tabData, xOffset, treeWidth, tabIndex)
            xOffset = xOffset + treeWidth + self.settings.treeSpacing
        end
    end

    -- Update scroll content height
    local maxHeight = self:CalculateMaxTreeHeight()
    content:SetHeight(math.max(maxHeight + 100, self.settings.windowHeight - 150))
end

function TalentTreeModule:CreateTalentTree(parent, tabData, xOffset, width, tabIndex)
    -- Tree header
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, 50)
    header:SetPoint("TOPLEFT", xOffset, -10)

    -- Tree icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", 0, -5)
    icon:SetTexture(tabData.icon)

    -- Tree name
    local nameLabel = FizzureUI:CreateLabel(header, tabData.name, "GameFontNormal")
    nameLabel:SetPoint("TOP", 0, -40)

    -- Points spent
    local pointsLabel = FizzureUI:CreateLabel(header, "(" .. tabData.pointsSpent .. ")", "GameFontNormalSmall")
    pointsLabel:SetPoint("TOP", nameLabel, "BOTTOM", 0, -2)
    pointsLabel:SetTextColor(0, 1, 0)

    -- Create talent grid
    local startY = -70
    local maxTier = self:GetMaxTierForTab(tabData)

    for tier = 1, maxTier do
        local talents = self:GetTalentsForTier(tabData, tier)
        local tierY = startY - ((tier - 1) * (self.settings.talentSize + 10))

        for _, talent in ipairs(talents) do
            self:CreateTalentButton(parent, talent, xOffset, tierY, width)
        end
    end
end

function TalentTreeModule:CreateTalentButton(parent, talent, treeX, tierY, treeWidth)
    local button = CreateFrame("Button", "FizzureTalent_" .. talent.tabIndex .. "_" .. talent.talentIndex, parent)
    button:SetSize(self.settings.talentSize, self.settings.talentSize)

    -- Position button within tree
    local columnSpacing = treeWidth / 5 -- Assuming max 4 columns
    local buttonX = treeX + (talent.column - 1) * columnSpacing + (treeWidth - columnSpacing * 4) / 2
    button:SetPoint("TOPLEFT", buttonX, tierY)

    -- Button background based on state
    self:SetTalentButtonAppearance(button, talent)

    -- Talent icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(talent.icon)
    button.icon = icon

    -- Rank text
    if talent.maxRank > 1 then
        local rankText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        rankText:SetPoint("BOTTOMRIGHT", -2, 2)
        rankText:SetText(talent.currentRank .. "/" .. talent.maxRank)
        button.rankText = rankText
    end

    -- Store talent info
    button.talentData = talent

    -- Click handler
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, clickButton)
        TalentTreeModule:OnTalentClick(self, clickButton)
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        TalentTreeModule:ShowTalentTooltip(self)
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    return button
end

function TalentTreeModule:SetTalentButtonAppearance(button, talent)
    if talent.currentRank > 0 then
        -- Learned talent
        button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    elseif talent.meetsPrereq and UnitCharacterPoints("player") > 0 then
        -- Available talent
        button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    else
        -- Unavailable talent
        button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        button:SetAlpha(0.5)
    end
end

function TalentTreeModule:OnTalentClick(button, clickButton)
    local talent = button.talentData
    if not talent then return end

    if clickButton == "LeftButton" then
        -- Add talent point
        if talent.currentRank < talent.maxRank and talent.meetsPrereq and UnitCharacterPoints("player") > 0 then
            if self.previewMode then
                -- Preview mode - just update display
                talent.currentRank = talent.currentRank + 1
                self:UpdateTalentDisplay()
            else
                -- Actually learn the talent
                LearnTalent(talent.tabIndex, talent.talentIndex)
            end
        end
    elseif clickButton == "RightButton" then
        -- Remove talent point (preview mode only)
        if self.previewMode and talent.currentRank > 0 then
            talent.currentRank = talent.currentRank - 1
            self:UpdateTalentDisplay()
        end
    end
end

function TalentTreeModule:ShowTalentTooltip(button)
    if not self.settings.showTalentTooltips then return end

    local talent = button.talentData
    if not talent then return end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetTalent(talent.tabIndex, talent.talentIndex)
    GameTooltip:Show()
end

function TalentTreeModule:GetMaxTierForTab(tabData)
    local maxTier = 0
    for _, talent in pairs(tabData.talents) do
        if talent.tier > maxTier then
            maxTier = talent.tier
        end
    end
    return maxTier
end

function TalentTreeModule:GetTalentsForTier(tabData, tier)
    local talents = {}
    for _, talent in pairs(tabData.talents) do
        if talent.tier == tier then
            table.insert(talents, talent)
        end
    end
    -- Sort by column
    table.sort(talents, function(a, b) return a.column < b.column end)
    return talents
end

function TalentTreeModule:CalculateMaxTreeHeight()
    local maxHeight = 0
    for _, tabData in pairs(self.talentData) do
        local maxTier = self:GetMaxTierForTab(tabData)
        local height = 100 + (maxTier * (self.settings.talentSize + 10))
        if height > maxHeight then
            maxHeight = height
        end
    end
    return maxHeight
end

function TalentTreeModule:HookTalentFrame()
    -- Hook the talent frame show function
    if TalentFrame then
        self.originalTalentFrameShow = TalentFrame_LoadUI
        TalentFrame_LoadUI = function()
            if TalentTreeModule.settings.replaceDefaultFrame then
                TalentTreeModule:ShowUnifiedFrame()
            else
                if TalentTreeModule.originalTalentFrameShow then
                    TalentTreeModule.originalTalentFrameShow()
                end
            end
        end
    end
end

function TalentTreeModule:UnhookTalentFrame()
    if self.originalTalentFrameShow then
        TalentFrame_LoadUI = self.originalTalentFrameShow
    end
end

function TalentTreeModule:ShowUnifiedFrame()
    self:LoadTalentData()
    self:UpdateTalentDisplay()
    self.unifiedFrame:Show()
end

function TalentTreeModule:TogglePreviewMode()
    self.previewMode = not self.previewMode

    if self.previewMode then
        self.previewBtn:SetText("Exit Preview")
        self.learnBtn:Enable()
        self.resetBtn:SetText("Reset Preview")
    else
        self.previewBtn:SetText("Preview Mode")
        self.learnBtn:Disable()
        self.resetBtn:SetText("Reset Talents")
        -- Reload actual talent data
        self:LoadTalentData()
        self:UpdateTalentDisplay()
    end
end

function TalentTreeModule:LearnTalents()
    if not self.previewMode then return end

    -- Apply all preview changes
    for tabIndex, tabData in pairs(self.talentData) do
        for talentIndex, talent in pairs(tabData.talents) do
            local actualRank = select(5, GetTalentInfo(tabIndex, talentIndex))
            while talent.currentRank > actualRank do
                LearnTalent(tabIndex, talentIndex)
                actualRank = actualRank + 1
            end
        end
    end

    self:TogglePreviewMode()
end

function TalentTreeModule:ShowResetConfirmation()
    -- Create confirmation dialog
    StaticPopup_Show("FIZZURE_RESET_TALENTS")
end

-- Create static popup for talent reset confirmation
StaticPopupDialogs["FIZZURE_RESET_TALENTS"] = {
    text = "Are you sure you want to reset your talents? This will cost money.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        if TalentTreeModule.previewMode then
            -- Reset preview
            TalentTreeModule:LoadTalentData()
            TalentTreeModule:UpdateTalentDisplay()
        else
            -- Actually reset talents (would need server support)
            -- ResetTalents() -- This function may not exist in 3.3.5
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function TalentTreeModule:CreateConfigUI(parent, x, y)
    local replaceCheck = FizzureUI:CreateCheckBox(parent, "Replace default talent frame",
            self.settings.replaceDefaultFrame, function(checked)
                self.settings.replaceDefaultFrame = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self:HookTalentFrame()
                else
                    self:UnhookTalentFrame()
                end
            end)
    replaceCheck:SetPoint("TOPLEFT", x, y)

    local showAllCheck = FizzureUI:CreateCheckBox(parent, "Show all specs in one view",
            self.settings.showAllSpecs, function(checked)
                self.settings.showAllSpecs = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateTalentDisplay()
            end)
    showAllCheck:SetPoint("TOPLEFT", x, y - 25)

    local tooltipCheck = FizzureUI:CreateCheckBox(parent, "Show talent tooltips",
            self.settings.showTalentTooltips, function(checked)
                self.settings.showTalentTooltips = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    tooltipCheck:SetPoint("TOPLEFT", x, y - 50)

    local previewCheck = FizzureUI:CreateCheckBox(parent, "Enable talent preview",
            self.settings.showTalentPreview, function(checked)
                self.settings.showTalentPreview = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    previewCheck:SetPoint("TOPLEFT", x, y - 75)

    local showBtn = FizzureUI:CreateButton(parent, "Show Talent Frame", 120, 24, function()
        self:ShowUnifiedFrame()
    end)
    showBtn:SetPoint("TOPLEFT", x, y - 105)

    return y - 135
end

function TalentTreeModule:GetQuickStatus()
    local totalPoints = 0
    for _, tabData in pairs(self.talentData) do
        totalPoints = totalPoints + tabData.pointsSpent
    end

    local availablePoints = UnitCharacterPoints("player")
    return string.format("Talents: %d spent, %d available", totalPoints, availablePoints)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Talent Tree Overhaul", TalentTreeModule, "UI/UX")
end