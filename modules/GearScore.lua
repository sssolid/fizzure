-- GearScore.lua - Gear Score Calculator Module for Fizzure
local GearScoreModule = {}

GearScoreModule.name = "Gear Score Calculator"
GearScoreModule.version = "1.0"
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
        showMinimapButton = true,
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
    self.lastCacheUpdate = 0

    -- Create UI elements
    self:CreateGearScoreFrame()
    if self.settings.showMinimapButton then
        self:CreateMinimapButton()
    end

    -- Hook tooltip functions
    self:HookTooltips()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    self.eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        GearScoreModule:OnEvent(event, ...)
    end)

    -- Update timer for cache cleanup
    self.updateTimer = FizzureCommon:NewTicker(30, function()
        self:CleanCache()
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

    if self.minimapButton then
        self.minimapButton:Hide()
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
        -- Group composition changed, clear relevant cache
        self:ClearGroupCache()
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

    for slot, weight in pairs(GEARSCORE_WEIGHTS) do
        if weight > 0 then
            local slotId = GetInventorySlotInfo(slot)
            local itemLink = GetInventoryItemLink(unit, slotId)

            if itemLink then
                local score = self:CalculateItemGearScore(itemLink, weight)
                if score > 0 then
                    totalScore = totalScore + score
                    itemCount = itemCount + 1
                end
            end
        end
    end

    local finalScore = math.floor(totalScore)

    -- Cache the result
    self.gearScoreCache[guid] = {
        score = finalScore,
        timestamp = GetTime(),
        itemCount = itemCount
    }

    return finalScore
end

-- Get unit from GUID
function GearScoreModule:GetUnitFromGUID(guid)
    if UnitGUID("target") == guid then return "target" end
    if UnitGUID("player") == guid then return "player" end

    -- Check party members
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitGUID(unit) == guid then return unit end
    end

    -- Check raid members
    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitGUID(unit) == guid then return unit end
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
    self.gearScoreFrame = FizzureUI:CreateStatusFrame("GearScoreFrame", "Gear Score", 150, 100)

    -- Player gear score display
    self.gearScoreText = FizzureUI:CreateLabel(self.gearScoreFrame, "GS: 0", "GameFontNormalLarge")
    self.gearScoreText:SetPoint("TOP", 0, -25)

    -- Item level average
    self.itemLevelText = FizzureUI:CreateLabel(self.gearScoreFrame, "Avg iLvl: 0", "GameFontNormal")
    self.itemLevelText:SetPoint("TOP", 0, -45)

    -- Details button
    local detailsBtn = FizzureUI:CreateButton(self.gearScoreFrame, "Details", 80, 20, function()
        self:ShowGearScoreDetails()
    end)
    detailsBtn:SetPoint("BOTTOM", 0, 10)

    self.gearScoreFrame:Hide()
end

-- Create minimap button
function GearScoreModule:CreateMinimapButton()
    local button = CreateFrame("Button", "GearScoreMinimapButton", Minimap)
    button:SetSize(28, 28)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, -20)

    button:SetNormalTexture("Interface\\Icons\\INV_Chest_Plate16")
    button:SetPushedTexture("Interface\\Icons\\INV_Chest_Plate17")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, clickButton)
        if clickButton == "LeftButton" then
            GearScoreModule:ToggleGearScoreFrame()
        elseif clickButton == "RightButton" then
            GearScoreModule:ShowGearScoreDetails()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Gear Score", 1, 1, 1)
        GameTooltip:AddLine("Your GS: " .. (GearScoreModule.playerGearScore or 0), 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Left-click: Toggle display", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click: Show details", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    self.minimapButton = button
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
end

-- Show detailed gear score breakdown
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

-- Create detailed breakdown frame
function GearScoreModule:CreateDetailsFrame()
    self.detailsFrame = FizzureUI:CreateWindow("GearScoreDetails", "Gear Score Breakdown", 400, 500)

    -- Scroll frame for item list
    self.detailsScroll = FizzureUI:CreateScrollFrame(self.detailsFrame.content, 380, 420)
    self.detailsScroll:SetPoint("TOPLEFT", 10, -10)

    -- Total at bottom
    self.totalLabel = FizzureUI:CreateLabel(self.detailsFrame.content, "Total: 0", "GameFontNormalLarge")
    self.totalLabel:SetPoint("BOTTOM", 0, 15)
end

-- Update details frame with current gear
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
end

-- Unhook tooltips
function GearScoreModule:UnhookTooltips()
    if self.originalItemTooltip then
        GameTooltip.SetInventoryItem = self.originalItemTooltip
    end
    if self.originalBagTooltip then
        GameTooltip.SetBagItem = self.originalBagTooltip
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
            end)
    showTooltipCheck:SetPoint("TOPLEFT", x, y)

    local showInspectCheck = FizzureUI:CreateCheckBox(parent, "Show gear score on inspect",
            self.settings.showInspect, function(checked)
                self.settings.showInspect = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    showInspectCheck:SetPoint("TOPLEFT", x, y - 25)

    local showMinimapCheck = FizzureUI:CreateCheckBox(parent, "Show minimap button",
            self.settings.showMinimapButton, function(checked)
                self.settings.showMinimapButton = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    if not self.minimapButton then
                        self:CreateMinimapButton()
                    else
                        self.minimapButton:Show()
                    end
                else
                    if self.minimapButton then
                        self.minimapButton:Hide()
                    end
                end
            end)
    showMinimapCheck:SetPoint("TOPLEFT", x, y - 50)

    local showFrameBtn = FizzureUI:CreateButton(parent, "Show GS Frame", 100, 24, function()
        self:ToggleGearScoreFrame()
    end)
    showFrameBtn:SetPoint("TOPLEFT", x, y - 80)

    local detailsBtn = FizzureUI:CreateButton(parent, "Show Details", 100, 24, function()
        self:ShowGearScoreDetails()
    end)
    detailsBtn:SetPoint("TOPLEFT", x + 110, y - 80)

    return y - 110
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