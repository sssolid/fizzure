-- GearScore.lua - Enhanced Gear Score Calculator with Group/Inspect Support
local GearScoreModule = {}

GearScoreModule.name = "Gear Score Calculator"
GearScoreModule.version = "1.1"
GearScoreModule.author = "Fizzure"
GearScoreModule.category = "UI/UX"

-- Gear score calculation constants for WotLK 3.3.5
local GEARSCORE_WEIGHTS = {
    -- Equipment slots and their weights for overall gear score
    HEADSLOT = 1.0,
    NECKSLOT = 0.5625,
    SHOULDERSLOT = 0.75,
    SHIRTSLOT = 0,
    CHESTSLOT = 1.0,
    WAISTSLOT = 0.75,
    LEGSSLOT = 1.0,
    FEETSLOT = 0.75,
    WRISTSLOT = 0.5625,
    HANDSSLOT = 0.75,
    FINGER0SLOT = 0.5625,
    FINGER1SLOT = 0.5625,
    TRINKET0SLOT = 0.5625,
    TRINKET1SLOT = 0.5625,
    BACKSLOT = 0.5625,
    MAINHANDSLOT = 1.0,
    SECONDARYHANDSLOT = 1.0,
    RANGEDSLOT = 0.3164,
    TABARDSLOT = 0
}

-- Quality multipliers for gear score calculation
local QUALITY_MULTIPLIERS = {
    [0] = 0.005,    -- Poor (gray)
    [1] = 0.005,    -- Common (white)
    [2] = 0.01,     -- Uncommon (green)
    [3] = 0.0605,   -- Rare (blue)
    [4] = 0.1357,   -- Epic (purple)
    [5] = 0.212,    -- Legendary (orange)
    [6] = 0.24,     -- Artifact
    [7] = 0.24      -- Heirloom
}

function GearScoreModule:GetDefaultSettings()
    return {
        enabled = true,
        showTooltip = true,
        showInspect = true,
        showGroupMembers = true,
        showOtherPlayers = true,
        inspectOnTarget = true,
        colorThresholds = {
            {score = 0, color = {0.7, 0.7, 0.7}},     -- Gray
            {score = 1000, color = {1, 1, 1}},         -- White
            {score = 2000, color = {0.12, 1, 0}},      -- Green
            {score = 3000, color = {0, 0.44, 0.87}},   -- Blue
            {score = 4000, color = {0.64, 0.21, 0.93}}, -- Purple
            {score = 5000, color = {1, 0.5, 0}},       -- Orange
            {score = 6000, color = {1, 0.82, 0}}       -- Gold
        }
    }
end

function GearScoreModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showTooltip) == "boolean" and
            type(settings.showInspect) == "boolean"
end

function GearScoreModule:Initialize()
    if not self.Fizzure then
        print("|cffff0000GearScore Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize cache
    self.gearScoreCache = {}
    self.inspectQueue = {}
    self.lastCacheUpdate = 0

    -- Create UI elements
    self:CreateGearScoreFrame()
    self:CreateInspectFrame()

    -- Hook tooltip functions
    self:HookTooltips()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    self.eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        GearScoreModule:OnEvent(event, ...)
    end)

    -- Update timer for cache cleanup and group updates
    self.updateTimer = FizzureCommon:NewTicker(5, function()
        self:CleanCache()
        self:UpdateGroupGearScores()
        self:UpdateGearScoreFrame()
    end)

    -- Initial gear score calculation
    self:CalculatePlayerGearScore()

    print("|cff00ff00GearScore Module|r Initialized")
    return true
end

function GearScoreModule:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.gearScoreFrame then
        self.gearScoreFrame:Hide()
    end

    if self.inspectFrame then
        self.inspectFrame:Hide()
    end

    -- Unhook tooltips
    self:UnhookTooltips()
end

function GearScoreModule:OnEvent(event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Player's gear changed, recalculate
        self:CalculatePlayerGearScore()
        self:UpdateGearScoreFrame()
    elseif event == "INSPECT_READY" then
        local guid = ...
        if guid then
            self:CalculateInspectGearScore(guid)
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        -- Group composition changed, clear relevant cache and update
        self:ClearGroupCache()
        self:UpdateGroupGearScores()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if self.settings.inspectOnTarget then
            self:InspectTarget()
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if self.settings.showOtherPlayers then
            self:InspectMouseover()
        end
    end
end

-- Calculate gear score for player
function GearScoreModule:CalculatePlayerGearScore()
    local totalScore = 0
    local itemCount = 0
    local breakdown = {}

    for slot, weight in pairs(GEARSCORE_WEIGHTS) do
        if weight > 0 then
            local slotId = GetInventorySlotInfo(slot)
            local itemLink = GetInventoryItemLink("player", slotId)

            if itemLink then
                local score = self:CalculateItemGearScore(itemLink, weight)
                if score > 0 then
                    totalScore = totalScore + score
                    itemCount = itemCount + 1
                    breakdown[slot] = {
                        link = itemLink,
                        score = score,
                        weight = weight
                    }
                end
            end
        end
    end

    self.playerGearScore = math.floor(totalScore)
    self.playerBreakdown = breakdown
    self.playerItemCount = itemCount

    return self.playerGearScore
end

-- Calculate gear score for a specific item
function GearScoreModule:CalculateItemGearScore(itemLink, slotWeight)
    if not itemLink or not slotWeight then return 0 end

    local _, _, quality, itemLevel = GetItemInfo(itemLink)
    if not quality or not itemLevel then return 0 end

    -- Get quality multiplier
    local qualityMultiplier = QUALITY_MULTIPLIERS[quality] or 0

    -- Calculate base score
    local score = math.floor(((itemLevel - 4) / 26) * 1000 * qualityMultiplier * slotWeight)

    return math.max(0, score)
end

-- Calculate gear score for inspected target
function GearScoreModule:CalculateInspectGearScore(guid)
    if not guid then return 0 end

    local unit = self:GetUnitFromGUID(guid)
    if not unit then return 0 end

    local totalScore = 0
    local itemCount = 0
    local breakdown = {}

    for slot, weight in pairs(GEARSCORE_WEIGHTS) do
        if weight > 0 then
            local slotId = GetInventorySlotInfo(slot)
            local itemLink = GetInventoryItemLink(unit, slotId)

            if itemLink then
                local score = self:CalculateItemGearScore(itemLink, weight)
                if score > 0 then
                    totalScore = totalScore + score
                    itemCount = itemCount + 1
                    breakdown[slot] = {
                        link = itemLink,
                        score = score,
                        weight = weight
                    }
                end
            end
        end
    end

    local finalScore = math.floor(totalScore)

    -- Cache the result
    self.gearScoreCache[guid] = {
        score = finalScore,
        breakdown = breakdown,
        timestamp = GetTime(),
        itemCount = itemCount,
        unitName = UnitName(unit)
    }

    -- Update inspect frame if showing this unit
    if self.inspectFrame and self.inspectFrame:IsShown() and self.inspectFrame.currentGUID == guid then
        self:UpdateInspectFrame(guid)
    end

    return finalScore
end

-- Inspect target player
function GearScoreModule:InspectTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then return end

    local guid = UnitGUID("target")
    if not guid or guid == UnitGUID("player") then return end

    -- Check if we already have recent data
    local cached = self.gearScoreCache[guid]
    if cached and GetTime() - cached.timestamp < 30 then return end

    -- Queue for inspection
    table.insert(self.inspectQueue, {guid = guid, unit = "target"})

    -- Process queue
    self:ProcessInspectQueue()
end

-- Inspect mouseover player
function GearScoreModule:InspectMouseover()
    if not UnitExists("mouseover") or not UnitIsPlayer("mouseover") then return end

    local guid = UnitGUID("mouseover")
    if not guid or guid == UnitGUID("player") then return end

    -- Check if we already have recent data
    local cached = self.gearScoreCache[guid]
    if cached and GetTime() - cached.timestamp < 60 then return end

    -- Queue for inspection
    table.insert(self.inspectQueue, {guid = guid, unit = "mouseover"})

    -- Process queue with delay for mouseover
    FizzureCommon:After(0.5, function()
        self:ProcessInspectQueue()
    end)
end

-- Process inspect queue
function GearScoreModule:ProcessInspectQueue()
    if #self.inspectQueue == 0 then return end

    local entry = table.remove(self.inspectQueue, 1)
    local unit = self:GetUnitFromGUID(entry.guid)

    if unit and UnitIsConnected(unit) and CheckInteractDistance(unit, 1) then
        NotifyInspect(unit)
    end

    -- Continue processing queue
    if #self.inspectQueue > 0 then
        FizzureCommon:After(1, function()
            self:ProcessInspectQueue()
        end)
    end
end

-- Update group member gear scores
function GearScoreModule:UpdateGroupGearScores()
    if not self.settings.showGroupMembers then return end

    local groupSize = GetNumPartyMembers()
    if GetNumRaidMembers() > 0 then
        groupSize = GetNumRaidMembers()
    end

    if groupSize == 0 then return end

    for i = 1, groupSize do
        local unit = GetNumRaidMembers() > 0 and "raid" .. i or "party" .. i

        if UnitExists(unit) and UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid and guid ~= UnitGUID("player") then
                local cached = self.gearScoreCache[guid]
                if not cached or GetTime() - cached.timestamp > 300 then
                    table.insert(self.inspectQueue, {guid = guid, unit = unit})
                end
            end
        end
    end

    -- Process any new queue entries
    if #self.inspectQueue > 0 then
        self:ProcessInspectQueue()
    end
end

-- Get unit from GUID
function GearScoreModule:GetUnitFromGUID(guid)
    if UnitGUID("target") == guid then return "target" end
    if UnitGUID("player") == guid then return "player" end
    if UnitGUID("mouseover") == guid then return "mouseover" end

    -- Check party members
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end

    -- Check raid members
    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end

    return nil
end

-- Get gear score color based on score
function GearScoreModule:GetGearScoreColor(score)
    for i = #self.settings.colorThresholds, 1, -1 do
        local threshold = self.settings.colorThresholds[i]
        if score >= threshold.score then
            return threshold.color[1], threshold.color[2], threshold.color[3]
        end
    end

    -- Default to gray
    return 0.7, 0.7, 0.7
end

-- Format gear score with color
function GearScoreModule:FormatGearScore(score)
    local r, g, b = self:GetGearScoreColor(score)
    return string.format("|cff%02x%02x%02x%d|r", r * 255, g * 255, b * 255, score)
end

-- Create main gear score display frame
function GearScoreModule:CreateGearScoreFrame()
    self.gearScoreFrame = FizzureUI:CreateStatusFrame("GearScoreFrame", "Gear Score", 180, 120, true)

    -- Player gear score display
    self.gearScoreText = FizzureUI:CreateLabel(self.gearScoreFrame, "GS: 0", "GameFontNormalLarge")
    self.gearScoreText:SetPoint("TOP", 0, -25)

    -- Item level average
    self.itemLevelText = FizzureUI:CreateLabel(self.gearScoreFrame, "Avg iLvl: 0", "GameFontNormal")
    self.itemLevelText:SetPoint("TOP", 0, -45)

    -- Target gear score
    self.targetGSText = FizzureUI:CreateLabel(self.gearScoreFrame, "Target: N/A", "GameFontNormalSmall")
    self.targetGSText:SetPoint("TOP", 0, -65)

    -- Details button
    local detailsBtn = FizzureUI:CreateButton(self.gearScoreFrame, "Details", 60, 20, function()
        self:ShowGearScoreDetails()
    end, true)
    detailsBtn:SetPoint("BOTTOMLEFT", 5, 10)

    -- Inspect button
    local inspectBtn = FizzureUI:CreateButton(self.gearScoreFrame, "Inspect", 60, 20, function()
        self:ToggleInspectFrame()
    end, true)
    inspectBtn:SetPoint("BOTTOMRIGHT", -5, 10)

    self.gearScoreFrame:Hide()
end

-- Create inspect frame for viewing other players' gear scores
function GearScoreModule:CreateInspectFrame()
    self.inspectFrame = FizzureUI:CreateWindow("GearScoreInspect", "Gear Score Inspect", 400, 500, nil, true)

    -- Player selection
    local playerLabel = FizzureUI:CreateLabel(self.inspectFrame.content, "Inspecting: None", "GameFontNormalLarge")
    playerLabel:SetPoint("TOP", 0, -10)
    self.inspectFrame.playerLabel = playerLabel

    -- Gear score display
    local gsLabel = FizzureUI:CreateLabel(self.inspectFrame.content, "Gear Score: 0", "GameFontNormal")
    gsLabel:SetPoint("TOP", 0, -35)
    self.inspectFrame.gsLabel = gsLabel

    -- Item breakdown scroll
    self.inspectScroll = FizzureUI:CreateScrollFrame(self.inspectFrame.content, 380, 380)
    self.inspectScroll:SetPoint("TOP", 0, -60)

    -- Target/Group buttons
    local targetBtn = FizzureUI:CreateButton(self.inspectFrame.content, "Inspect Target", 100, 24, function()
        self:InspectCurrentTarget()
    end, true)
    targetBtn:SetPoint("BOTTOMLEFT", 10, 10)

    local groupBtn = FizzureUI:CreateButton(self.inspectFrame.content, "Group Scores", 100, 24, function()
        self:ShowGroupGearScores()
    end, true)
    groupBtn:SetPoint("BOTTOM", 0, 10)

    self.inspectFrame:Hide()
end

-- Toggle inspect frame
function GearScoreModule:ToggleInspectFrame()
    if self.inspectFrame:IsShown() then
        self.inspectFrame:Hide()
    else
        self.inspectFrame:Show()
        self:UpdateInspectFrameGroupList()
    end
end

-- Inspect current target
function GearScoreModule:InspectCurrentTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        self.Fizzure:ShowNotification("No Target", "Target a player to inspect their gear score", "warning", 3)
        return
    end

    local guid = UnitGUID("target")
    local name = UnitName("target")

    self.inspectFrame.currentGUID = guid
    self.inspectFrame.playerLabel:SetText("Inspecting: " .. name)

    -- Check cache first
    local cached = self.gearScoreCache[guid]
    if cached and GetTime() - cached.timestamp < 60 then
        self:UpdateInspectFrame(guid)
    else
        self.inspectFrame.gsLabel:SetText("Gear Score: Inspecting...")
        NotifyInspect("target")
    end
end

-- Update inspect frame with player data
function GearScoreModule:UpdateInspectFrame(guid)
    local cached = self.gearScoreCache[guid]
    if not cached then return end

    self.inspectFrame.gsLabel:SetText("Gear Score: " .. self:FormatGearScore(cached.score))

    -- Update item breakdown
    local content = self.inspectScroll.content

    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    local yOffset = -10

    -- Sort slots by score
    local sortedSlots = {}
    for slot, data in pairs(cached.breakdown or {}) do
        table.insert(sortedSlots, {slot = slot, data = data})
    end
    table.sort(sortedSlots, function(a, b) return a.data.score > b.data.score end)

    for _, entry in ipairs(sortedSlots) do
        local slot = entry.slot
        local data = entry.data

        -- Create item frame
        local itemFrame = CreateFrame("Frame", nil, content)
        itemFrame:SetSize(360, 25)
        itemFrame:SetPoint("TOPLEFT", 10, yOffset)

        -- Item icon
        local icon = itemFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)

        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(data.link)
        if itemIcon then
            icon:SetTexture(itemIcon)
        end

        -- Slot name
        local slotName = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotName:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        slotName:SetText(self:GetSlotDisplayName(slot))
        slotName:SetTextColor(0.8, 0.8, 0.8)

        -- Item link
        local linkText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        linkText:SetPoint("LEFT", slotName, "RIGHT", 10, 0)
        linkText:SetSize(180, 20)
        linkText:SetText(data.link)
        linkText:SetJustifyH("LEFT")

        -- Score
        local scoreText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scoreText:SetPoint("RIGHT", -5, 0)
        scoreText:SetText(math.floor(data.score))
        local r, g, b = self:GetGearScoreColor(data.score)
        scoreText:SetTextColor(r, g, b)

        yOffset = yOffset - 27
    end

    -- Update scroll height
    self.inspectScroll.content:SetHeight(math.abs(yOffset) + 20)
end

-- Show group gear scores
function GearScoreModule:ShowGroupGearScores()
    local content = self.inspectScroll.content

    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    local yOffset = -10
    self.inspectFrame.playerLabel:SetText("Group Gear Scores")
    self.inspectFrame.gsLabel:SetText("")

    -- Add player first
    local playerFrame = CreateFrame("Button", nil, content)
    playerFrame:SetSize(360, 25)
    playerFrame:SetPoint("TOPLEFT", 10, yOffset)

    local playerName = playerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerName:SetPoint("LEFT", 5, 0)
    playerName:SetText(UnitName("player") .. " (You)")
    playerName:SetTextColor(0.2, 1, 0.2)

    local playerGS = playerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerGS:SetPoint("RIGHT", -5, 0)
    playerGS:SetText(self:FormatGearScore(self.playerGearScore or 0))

    yOffset = yOffset - 30

    -- Add group members
    local groupSize = math.max(GetNumPartyMembers(), GetNumRaidMembers())

    for i = 1, groupSize do
        local unit = GetNumRaidMembers() > 0 and "raid" .. i or "party" .. i

        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local name = UnitName(unit)
            local cached = self.gearScoreCache[guid]

            local memberFrame = CreateFrame("Button", nil, content)
            memberFrame:SetSize(360, 25)
            memberFrame:SetPoint("TOPLEFT", 10, yOffset)

            -- Make it clickable to inspect
            memberFrame:SetScript("OnClick", function()
                if cached then
                    self.inspectFrame.currentGUID = guid
                    self:UpdateInspectFrame(guid)
                end
            end)

            local memberName = memberFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            memberName:SetPoint("LEFT", 5, 0)
            memberName:SetText(name)
            memberName:SetTextColor(0.9, 0.9, 0.9)

            local memberGS = memberFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            memberGS:SetPoint("RIGHT", -5, 0)

            if cached then
                memberGS:SetText(self:FormatGearScore(cached.score))
            else
                memberGS:SetText("Unknown")
                memberGS:SetTextColor(0.7, 0.7, 0.7)
            end

            yOffset = yOffset - 27
        end
    end

    -- Update scroll height
    self.inspectScroll.content:SetHeight(math.abs(yOffset) + 20)
end

-- Update group list in inspect frame
function GearScoreModule:UpdateInspectFrameGroupList()
    if self.inspectFrame:IsShown() and not self.inspectFrame.currentGUID then
        self:ShowGroupGearScores()
    end
end

-- Toggle gear score frame
function GearScoreModule:ToggleGearScoreFrame()
    if self.gearScoreFrame:IsShown() then
        self.gearScoreFrame:Hide()
    else
        self:UpdateGearScoreFrame()
        self.gearScoreFrame:Show()
    end
end

-- Update gear score frame display
function GearScoreModule:UpdateGearScoreFrame()
    if not self.gearScoreFrame or not self.gearScoreFrame:IsShown() then return end

    local score = self.playerGearScore or 0
    local itemCount = self.playerItemCount or 0

    -- Update gear score text with color
    self.gearScoreText:SetText("GS: " .. self:FormatGearScore(score))

    -- Calculate average item level
    local avgItemLevel = 0
    if self.playerBreakdown and itemCount > 0 then
        local totalItemLevel = 0
        for slot, data in pairs(self.playerBreakdown) do
            local _, _, _, itemLevel = GetItemInfo(data.link)
            if itemLevel then
                totalItemLevel = totalItemLevel + itemLevel
            end
        end
        avgItemLevel = math.floor(totalItemLevel / itemCount)
    end

    self.itemLevelText:SetText("Avg iLvl: " .. avgItemLevel)

    -- Update target gear score
    if UnitExists("target") and UnitIsPlayer("target") then
        local guid = UnitGUID("target")
        local cached = self.gearScoreCache[guid]
        if cached then
            self.targetGSText:SetText("Target: " .. self:FormatGearScore(cached.score))
        else
            self.targetGSText:SetText("Target: Inspecting...")
        end
    else
        self.targetGSText:SetText("Target: N/A")
    end
end

-- Show detailed gear score breakdown (existing function - kept the same)
function GearScoreModule:ShowGearScoreDetails()
    if self.detailsFrame then
        if self.detailsFrame:IsShown() then
            self.detailsFrame:Hide()
            return
        else
            self.detailsFrame:Show()
        end
    else
        self:CreateDetailsFrame()
    end

    self:UpdateDetailsFrame()
end

-- Create detailed breakdown frame (existing function - kept the same)
function GearScoreModule:CreateDetailsFrame()
    self.detailsFrame = FizzureUI:CreateWindow("GearScoreDetails", "Gear Score Breakdown", 400, 500, nil, true)

    -- Scroll frame for item list
    self.detailsScroll = FizzureUI:CreateScrollFrame(self.detailsFrame.content, 380, 420)
    self.detailsScroll:SetPoint("TOPLEFT", 10, -10)

    -- Total at bottom
    self.totalLabel = FizzureUI:CreateLabel(self.detailsFrame.content, "Total: 0", "GameFontNormalLarge")
    self.totalLabel:SetPoint("BOTTOM", 0, 15)
end

-- Update details frame with current gear (existing function - kept the same)
function GearScoreModule:UpdateDetailsFrame()
    if not self.detailsFrame or not self.detailsScroll then return end

    local content = self.detailsScroll.content

    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    if not self.playerBreakdown then
        self:CalculatePlayerGearScore()
    end

    local yOffset = -10
    local totalScore = 0

    -- Sort slots by score (highest first)
    local sortedSlots = {}
    for slot, data in pairs(self.playerBreakdown or {}) do
        table.insert(sortedSlots, {slot = slot, data = data})
    end
    table.sort(sortedSlots, function(a, b) return a.data.score > b.data.score end)

    for _, entry in ipairs(sortedSlots) do
        local slot = entry.slot
        local data = entry.data

        -- Create item frame
        local itemFrame = CreateFrame("Frame", nil, content)
        itemFrame:SetSize(360, 25)
        itemFrame:SetPoint("TOPLEFT", 10, yOffset)

        -- Item icon
        local icon = itemFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)

        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(data.link)
        if itemIcon then
            icon:SetTexture(itemIcon)
        end

        -- Slot name
        local slotName = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotName:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        slotName:SetText(self:GetSlotDisplayName(slot))
        slotName:SetTextColor(0.8, 0.8, 0.8)

        -- Item link (clickable)
        local itemLink = CreateFrame("Button", nil, itemFrame)
        itemLink:SetSize(150, 20)
        itemLink:SetPoint("LEFT", slotName, "RIGHT", 5, 0)

        local linkText = itemLink:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        linkText:SetAllPoints()
        linkText:SetText(data.link)
        linkText:SetJustifyH("LEFT")

        itemLink:SetScript("OnClick", function()
            ChatFrame1EditBox:Insert(data.link)
        end)

        itemLink:SetScript("OnEnter", function()
            GameTooltip:SetOwner(itemLink, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(data.link)
            GameTooltip:Show()
        end)

        itemLink:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Score
        local scoreText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scoreText:SetPoint("RIGHT", -5, 0)
        scoreText:SetText(math.floor(data.score))
        local r, g, b = self:GetGearScoreColor(data.score)
        scoreText:SetTextColor(r, g, b)

        totalScore = totalScore + data.score
        yOffset = yOffset - 27
    end

    -- Update scroll height
    self.detailsScroll.content:SetHeight(math.abs(yOffset) + 20)

    -- Update total
    self.totalLabel:SetText("Total Gear Score: " .. self:FormatGearScore(math.floor(totalScore)))
end

-- Get display name for equipment slot
function GearScoreModule:GetSlotDisplayName(slot)
    local slotNames = {
        HEADSLOT = "Head",
        NECKSLOT = "Neck",
        SHOULDERSLOT = "Shoulders",
        CHESTSLOT = "Chest",
        WAISTSLOT = "Waist",
        LEGSSLOT = "Legs",
        FEETSLOT = "Feet",
        WRISTSLOT = "Wrists",
        HANDSSLOT = "Hands",
        FINGER0SLOT = "Ring 1",
        FINGER1SLOT = "Ring 2",
        TRINKET0SLOT = "Trinket 1",
        TRINKET1SLOT = "Trinket 2",
        BACKSLOT = "Back",
        MAINHANDSLOT = "Main Hand",
        SECONDARYHANDSLOT = "Off Hand",
        RANGEDSLOT = "Ranged"
    }
    return slotNames[slot] or slot
end

-- Hook tooltip functions to show gear scores
function GearScoreModule:HookTooltips()
    if not self.settings.showTooltip then return end

    -- Hook item tooltip
    self.originalItemTooltip = GameTooltip.SetInventoryItem
    GameTooltip.SetInventoryItem = function(tooltip, unit, slot)
        self.originalItemTooltip(tooltip, unit, slot)

        local itemLink = GetInventoryItemLink(unit, slot)
        if itemLink then
            local slotInfo = self:GetSlotInfoFromID(slot)
            if slotInfo then
                local weight = GEARSCORE_WEIGHTS[slotInfo]
                if weight and weight > 0 then
                    local score = self:CalculateItemGearScore(itemLink, weight)
                    if score > 0 then
                        tooltip:AddLine("Gear Score: " .. self:FormatGearScore(math.floor(score)))
                    end
                end
            end
        end
    end

    -- Hook bag item tooltip
    self.originalBagTooltip = GameTooltip.SetBagItem
    GameTooltip.SetBagItem = function(tooltip, bag, slot)
        self.originalBagTooltip(tooltip, bag, slot)

        local itemLink = GetContainerItemLink(bag, slot)
        if itemLink then
            local _, _, _, _, _, _, subType = GetItemInfo(itemLink)
            if subType and (subType == "Cloth" or subType == "Leather" or subType == "Mail" or subType == "Plate" or
                    subType == "Shield" or subType == "Libram" or subType == "Idol" or subType == "Totem") then
                -- This is likely equipable gear, show potential gear score
                local avgWeight = 0.75 -- Average weight for most slots
                local score = self:CalculateItemGearScore(itemLink, avgWeight)
                if score > 0 then
                    tooltip:AddLine("Gear Score: ~" .. self:FormatGearScore(math.floor(score)))
                end
            end
        end
    end

    -- Hook unit tooltip to show gear scores
    self.originalUnitTooltip = GameTooltip.SetUnit
    GameTooltip.SetUnit = function(tooltip, unit)
        self.originalUnitTooltip(tooltip, unit)

        if UnitIsPlayer(unit) and unit ~= "player" then
            local guid = UnitGUID(unit)
            if guid then
                local cached = self.gearScoreCache[guid]
                if cached then
                    tooltip:AddLine("Gear Score: " .. self:FormatGearScore(cached.score))
                elseif self.settings.showOtherPlayers then
                    tooltip:AddLine("Gear Score: Inspecting...")
                    -- Queue for inspection
                    table.insert(self.inspectQueue, {guid = guid, unit = unit})
                    self:ProcessInspectQueue()
                end
            end
        end
    end
end

-- Unhook tooltips
function GearScoreModule:UnhookTooltips()
    if self.originalItemTooltip then
        GameTooltip.SetInventoryItem = self.originalItemTooltip
    end
    if self.originalBagTooltip then
        GameTooltip.SetBagItem = self.originalBagTooltip
    end
    if self.originalUnitTooltip then
        GameTooltip.SetUnit = self.originalUnitTooltip
    end
end

-- Get slot info from slot ID
function GearScoreModule:GetSlotInfoFromID(slotId)
    for slot, _ in pairs(GEARSCORE_WEIGHTS) do
        if GetInventorySlotInfo(slot) == slotId then
            return slot
        end
    end
    return nil
end

-- Cache management
function GearScoreModule:CleanCache()
    local now = GetTime()
    for guid, data in pairs(self.gearScoreCache) do
        if now - data.timestamp > 300 then -- 5 minutes
            self.gearScoreCache[guid] = nil
        end
    end
end

function GearScoreModule:ClearGroupCache()
    -- Clear cache for units that are no longer in group
    local validGUIDs = {}

    -- Add player
    validGUIDs[UnitGUID("player")] = true

    -- Add party/raid members
    local groupType = IsInRaid() and "raid" or "party"
    local groupSize = IsInRaid() and 40 or 4

    for i = 1, groupSize do
        local unit = groupType .. i
        if UnitExists(unit) then
            validGUIDs[UnitGUID(unit)] = true
        end
    end

    -- Remove invalid entries
    for guid, _ in pairs(self.gearScoreCache) do
        if not validGUIDs[guid] then
            self.gearScoreCache[guid] = nil
        end
    end
end

-- Configuration UI
function GearScoreModule:CreateConfigUI(parent, x, y)
    local showTooltipCheck = FizzureUI:CreateCheckBox(parent, "Show gear score in tooltips",
            self.settings.showTooltip, function(checked)
                self.settings.showTooltip = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self:HookTooltips()
                else
                    self:UnhookTooltips()
                end
            end, true)
    showTooltipCheck:SetPoint("TOPLEFT", x, y)

    local showInspectCheck = FizzureUI:CreateCheckBox(parent, "Show gear score on inspect",
            self.settings.showInspect, function(checked)
                self.settings.showInspect = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    showInspectCheck:SetPoint("TOPLEFT", x, y - 25)

    local showGroupCheck = FizzureUI:CreateCheckBox(parent, "Show group member gear scores",
            self.settings.showGroupMembers, function(checked)
                self.settings.showGroupMembers = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    showGroupCheck:SetPoint("TOPLEFT", x, y - 50)

    local inspectTargetCheck = FizzureUI:CreateCheckBox(parent, "Auto-inspect target",
            self.settings.inspectOnTarget, function(checked)
                self.settings.inspectOnTarget = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    inspectTargetCheck:SetPoint("TOPLEFT", x, y - 75)

    local showFrameBtn = FizzureUI:CreateButton(parent, "Show GS Frame", 100, 24, function()
        self:ToggleGearScoreFrame()
    end, true)
    showFrameBtn:SetPoint("TOPLEFT", x, y - 105)

    local inspectBtn = FizzureUI:CreateButton(parent, "Inspect Window", 100, 24, function()
        self:ToggleInspectFrame()
    end, true)
    inspectBtn:SetPoint("TOPLEFT", x + 110, y - 105)

    return y - 135
end

-- Quick status for main interface
function GearScoreModule:GetQuickStatus()
    local score = self.playerGearScore or 0
    return "Gear Score: " .. score
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Gear Score Calculator", GearScoreModule, "UI/UX")
end