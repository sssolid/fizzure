-- FishingHelper.lua - Comprehensive Fishing Assistant Module for Fizzure
local FishingModule = {}

FishingModule.name = "Fishing Helper"
FishingModule.version = "1.0"
FishingModule.author = "Fizzure"
FishingModule.category = "General"

-- Fishing-related constants for WotLK 3.3.5
local FISHING_BAITS = {
    ["Shiny Bauble"] = {bonus = 25, duration = 600, type = "bait"},
    ["Nightcrawlers"] = {bonus = 50, duration = 600, type = "bait"},
    ["Bright Baubles"] = {bonus = 75, duration = 600, type = "bait"},
    ["Aquadynamic Fish Attractor"] = {bonus = 100, duration = 600, type = "bait"},
    ["Flesh Eating Worm"] = {bonus = 75, duration = 600, type = "bait"},
    ["Feathered Lure"] = {bonus = 100, duration = 600, type = "bait"},
    ["Zulian Mudskunk Lure"] = {bonus = 150, duration = 600, type = "bait"}
}

local FISHING_POLES = {
    ["Fishing Pole"] = {bonus = 0},
    ["Strong Fishing Pole"] = {bonus = 5},
    ["Darkwood Fishing Pole"] = {bonus = 15},
    ["Big Iron Fishing Pole"] = {bonus = 20},
    ["Nat Pagle's Extreme Angler FC-5000"] = {bonus = 25},
    ["Arcanite Fishing Pole"] = {bonus = 35},
    ["Seth's Graphite Fishing Pole"] = {bonus = 20},
    ["The Master's Fishing Pole"] = {bonus = 30},
    ["Jeweled Fishing Pole"] = {bonus = 30},
    ["Draconic Fishing Pole"] = {bonus = 40}
}

function FishingModule:GetDefaultSettings()
    return {
        enabled = true,
        showFishingFrame = true,
        autoApplyBait = false,
        oneClickFishing = true,
        autoLoot = true,
        soundAlerts = true,
        trackCatches = true,
        showBobberAlert = true,
        easyClickRadius = 50,
        framePosition = {
            point = "TOPRIGHT",
            x = -50,
            y = -150
        },
        sessionTracking = {
            trackByZone = true,
            trackByTime = true,
            showStatistics = true
        },
        notifications = {
            rareChatch = true,
            skillUp = true,
            noBait = true,
            poleNotEquipped = true
        }
    }
end

function FishingModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showFishingFrame) == "boolean" and
            type(settings.autoLoot) == "boolean"
end

function FishingModule:Initialize()
    if not self.Fizzure then
        print("|cffff0000Fishing Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize session data
    self.sessionData = {
        catches = {},
        startTime = GetTime(),
        totalCasts = 0,
        successfulCasts = 0,
        skillGains = 0,
        currentZone = GetZoneText(),
        rareItems = {},
        totalValue = 0
    }

    -- Initialize state tracking
    self.fishingState = {
        isFishing = false,
        hasBobber = false,
        bobberGUID = nil,
        lastCastTime = 0,
        oneClickActive = false,
        currentBaitExpiry = 0
    }

    -- Create UI components
    self:CreateFishingFrame()
    self:CreateBaitPanel()
    self:CreateCatchTracker()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
    self.eventFrame:RegisterEvent("CHAT_MSG_SKILL")
    self.eventFrame:RegisterEvent("LOOT_OPENED")
    self.eventFrame:RegisterEvent("LOOT_CLOSED")
    self.eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:RegisterEvent("ADDON_LOADED")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        FishingModule:OnEvent(event, ...)
    end)

    -- Set up fishing detection
    self:SetupFishingDetection()

    -- Create secure action button for one-click fishing
    if self.settings.oneClickFishing then
        self:CreateOneClickFishing()
    end

    -- Initialize update timer
    self.updateTimer = FizzureCommon:NewTicker(0.5, function()
        self:UpdateFishingState()
        self:UpdateBaitStatus()
        self:UpdateFishingFrame()
    end)

    print("|cff00ff00Fishing Helper|r Initialized")
    return true
end

function FishingModule:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.fishingFrame then
        self.fishingFrame:Hide()
    end

    self:DisableOneClickFishing()

    -- Only save session data if we have valid session data
    if self.sessionData and self.Fizzure then
        self:SaveSessionData()
    end
end

function FishingModule:OnEvent(event, ...)
    if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        self:UpdateFishingSkill()
    elseif event == "LOOT_OPENED" then
        if self.fishingState.isFishing then
            self:HandleFishingLoot()
        end
    elseif event == "LOOT_CLOSED" then
        if self.settings.autoLoot and self.fishingState.isFishing then
            self:AutoLootFish()
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local messageType = ...
        self:HandleFishingError(messageType)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        self:OnZoneChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UpdateFishingSkill()
        self:ScanAvailableBaits()
    end
end

function FishingModule:CreateFishingFrame()
    self.fishingFrame = FizzureUI:CreateStatusFrame("FishingHelperFrame", "Fishing Helper", 250, 300)

    -- Position frame
    if self.settings.framePosition then
        self.fishingFrame:ClearAllPoints()
        self.fishingFrame:SetPoint(self.settings.framePosition.point,
                UIParent, self.settings.framePosition.point,
                self.settings.framePosition.x, self.settings.framePosition.y)
    end

    -- Fishing skill display
    self.skillLabel = FizzureUI:CreateLabel(self.fishingFrame, "Fishing: 0/450", "GameFontNormal")
    self.skillLabel:SetPoint("TOP", 0, -25)

    -- Current zone and conditions
    self.zoneLabel = FizzureUI:CreateLabel(self.fishingFrame, "Zone: Unknown", "GameFontNormalSmall")
    self.zoneLabel:SetPoint("TOP", 0, -45)

    -- Bait status
    self.baitLabel = FizzureUI:CreateLabel(self.fishingFrame, "No Bait Applied", "GameFontNormalSmall")
    self.baitLabel:SetPoint("TOP", 0, -65)

    -- Session stats
    self.sessionLabel = FizzureUI:CreateLabel(self.fishingFrame, "Session: 0 catches", "GameFontNormalSmall")
    self.sessionLabel:SetPoint("TOP", 0, -85)

    -- One-click fishing toggle
    self.oneClickBtn = FizzureUI:CreateButton(self.fishingFrame, "One-Click: OFF", 120, 20, function()
        self:ToggleOneClickFishing()
    end)
    self.oneClickBtn:SetPoint("TOP", 0, -110)

    -- Auto-cast button
    self.autoCastBtn = FizzureUI:CreateButton(self.fishingFrame, "Cast", 80, 24, function()
        self:CastFishingLine()
    end)
    self.autoCastBtn:SetPoint("TOP", 0, -140)

    -- Baits and catches buttons
    self.baitsBtn = FizzureUI:CreateButton(self.fishingFrame, "Baits", 50, 20, function()
        self:ToggleBaitPanel()
    end)
    self.baitsBtn:SetPoint("BOTTOMLEFT", 10, 35)

    self.catchesBtn = FizzureUI:CreateButton(self.fishingFrame, "Catches", 50, 20, function()
        self:ToggleCatchTracker()
    end)
    self.catchesBtn:SetPoint("BOTTOMRIGHT", -10, 35)

    -- Minimize button
    self.minimizeBtn = FizzureUI:CreateButton(self.fishingFrame, "-", 20, 20, function()
        self:MinimizeFishingFrame()
    end)
    self.minimizeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Save position on move
    self.fishingFrame.OnPositionChanged = function()
        local point, _, _, x, y = self.fishingFrame:GetPoint()
        self.settings.framePosition = {point = point, x = x, y = y}
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    if not self.settings.showFishingFrame then
        self.fishingFrame:Hide()
    end
end

function FishingModule:CreateBaitPanel()
    self.baitPanel = FizzureUI:CreateWindow("FishingBaitPanel", "Fishing Baits", 300, 400)

    -- Available baits scroll frame
    self.baitScroll = FizzureUI:CreateScrollFrame(self.baitPanel.content, 280, 320)
    self.baitScroll:SetPoint("TOPLEFT", 10, -10)

    -- Refresh button
    local refreshBtn = FizzureUI:CreateButton(self.baitPanel.content, "Refresh", 80, 24, function()
        self:ScanAvailableBaits()
        self:UpdateBaitPanel()
    end)
    refreshBtn:SetPoint("BOTTOM", -50, 10)

    -- Auto-apply toggle
    self.autoApplyCheck = FizzureUI:CreateCheckBox(self.baitPanel.content, "Auto-apply best bait",
            self.settings.autoApplyBait, function(checked)
                self.settings.autoApplyBait = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    self.autoApplyCheck:SetPoint("BOTTOM", 0, 35)

    self.baitPanel:Hide()
    self.availableBaits = {}
end

function FishingModule:CreateCatchTracker()
    self.catchTracker = FizzureUI:CreateWindow("FishingCatchTracker", "Fishing Session", 400, 500)

    -- Session summary
    self.summaryLabel = FizzureUI:CreateLabel(self.catchTracker.content, "Session Summary", "GameFontNormalLarge")
    self.summaryLabel:SetPoint("TOP", 0, -10)

    -- Stats panel
    local statsPanel = CreateFrame("Frame", nil, self.catchTracker.content)
    statsPanel:SetSize(380, 100)
    statsPanel:SetPoint("TOP", 0, -35)
    statsPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    statsPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    -- Session stats labels
    self.sessionTimeLabel = FizzureUI:CreateLabel(statsPanel, "Time: 0:00", "GameFontNormalSmall")
    self.sessionTimeLabel:SetPoint("TOPLEFT", 10, -10)

    self.totalCastsLabel = FizzureUI:CreateLabel(statsPanel, "Casts: 0", "GameFontNormalSmall")
    self.totalCastsLabel:SetPoint("TOPLEFT", 10, -25)

    self.successRateLabel = FizzureUI:CreateLabel(statsPanel, "Success: 0%", "GameFontNormalSmall")
    self.successRateLabel:SetPoint("TOPLEFT", 10, -40)

    self.skillGainsLabel = FizzureUI:CreateLabel(statsPanel, "Skill Gains: 0", "GameFontNormalSmall")
    self.skillGainsLabel:SetPoint("TOPLEFT", 10, -55)

    self.totalValueLabel = FizzureUI:CreateLabel(statsPanel, "Est. Value: 0g", "GameFontNormalSmall")
    self.totalValueLabel:SetPoint("TOPRIGHT", -10, -10)

    self.catchesCountLabel = FizzureUI:CreateLabel(statsPanel, "Total Catches: 0", "GameFontNormalSmall")
    self.catchesCountLabel:SetPoint("TOPRIGHT", -10, -25)

    -- Catches list
    self.catchesScroll = FizzureUI:CreateScrollFrame(self.catchTracker.content, 380, 300)
    self.catchesScroll:SetPoint("TOP", 0, -145)

    -- Clear session button
    local clearBtn = FizzureUI:CreateButton(self.catchTracker.content, "Clear Session", 100, 24, function()
        self:ClearSessionData()
    end)
    clearBtn:SetPoint("BOTTOM", 0, 10)

    self.catchTracker:Hide()
end

function FishingModule:ScanAvailableBaits()
    self.availableBaits = {}

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemName = GetItemInfo(itemLink)
                local _, itemCount = GetContainerItemInfo(bag, slot)

                if itemName and FISHING_BAITS[itemName] and itemCount > 0 then
                    table.insert(self.availableBaits, {
                        name = itemName,
                        link = itemLink,
                        count = itemCount,
                        bonus = FISHING_BAITS[itemName].bonus,
                        duration = FISHING_BAITS[itemName].duration,
                        bag = bag,
                        slot = slot
                    })
                end
            end
        end
    end

    -- Sort by bonus (best first)
    table.sort(self.availableBaits, function(a, b) return a.bonus > b.bonus end)
end

function FishingModule:ApplyBait(baitName)
    if not baitName then return false end

    -- Find the bait in bags
    for _, bait in ipairs(self.availableBaits) do
        if bait.name == baitName then
            -- Check if we have a fishing pole equipped
            local mainHandLink = GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))
            if not mainHandLink then
                self.Fizzure:ShowNotification("No Fishing Pole", "Equip a fishing pole first!", "error", 3)
                return false
            end

            local itemName = GetItemInfo(mainHandLink)
            if not FISHING_POLES[itemName] then
                self.Fizzure:ShowNotification("No Fishing Pole", "Equip a fishing pole first!", "error", 3)
                return false
            end

            -- Apply the bait
            UseContainerItem(bait.bag, bait.slot)
            self.fishingState.currentBaitExpiry = GetTime() + bait.duration

            self.Fizzure:ShowNotification("Bait Applied",
                    baitName .. " applied (++" .. bait.bonus .. " fishing)", "success", 3)

            -- Rescan baits after use
            FizzureCommon:After(0.5, function()
                self:ScanAvailableBaits()
                self:UpdateBaitPanel()
            end)

            return true
        end
    end

    return false
end

function FishingModule:UpdateBaitPanel()
    if not self.baitPanel or not self.baitPanel:IsShown() then return end

    local content = self.baitScroll.content

    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    local yOffset = -10

    if #self.availableBaits == 0 then
        local noBaitsLabel = FizzureUI:CreateLabel(content, "No fishing baits found in bags", "GameFontNormal")
        noBaitsLabel:SetPoint("TOPLEFT", 10, yOffset)
        noBaitsLabel:SetTextColor(0.7, 0.7, 0.7)
        return
    end

    for i, bait in ipairs(self.availableBaits) do
        local baitFrame = CreateFrame("Button", "FishingBait" .. i, content)
        baitFrame:SetSize(260, 30)
        baitFrame:SetPoint("TOPLEFT", 10, yOffset)

        -- Background
        local bg = baitFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        bg:SetAlpha(0)
        baitFrame:SetHighlightTexture(bg)

        -- Bait icon
        local icon = baitFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 2, 0)

        local itemIcon = GetItemIcon(bait.name)
        if itemIcon then
            icon:SetTexture(itemIcon)
        else
            icon:SetTexture("Interface\\Icons\\Trade_Fishing")
        end

        -- Bait name and bonus
        local nameText = baitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 3)
        nameText:SetText(bait.name)

        local bonusText = baitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bonusText:SetPoint("LEFT", icon, "RIGHT", 5, -8)
        bonusText:SetText("+" .. bait.bonus .. " fishing")
        bonusText:SetTextColor(0, 1, 0)

        -- Count
        local countText = baitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        countText:SetPoint("RIGHT", -5, 0)
        countText:SetText("x" .. bait.count)
        countText:SetTextColor(1, 1, 1)

        -- Click to apply
        baitFrame:SetScript("OnClick", function()
            self:ApplyBait(bait.name)
        end)

        -- Tooltip
        baitFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(baitFrame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(bait.link)
            GameTooltip:AddLine("Click to apply to fishing pole", 0.7, 0.7, 1)
            GameTooltip:Show()
        end)

        baitFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        yOffset = yOffset - 35
    end

    -- Update scroll height
    local totalHeight = math.abs(yOffset) + 20
    content:SetHeight(math.max(totalHeight, 320))
end

function FishingModule:SetupFishingDetection()
    -- Monitor for fishing spell casting
    self.fishingDetectionFrame = CreateFrame("Frame")
    self.fishingDetectionFrame:RegisterEvent("UNIT_SPELLCAST_START")
    self.fishingDetectionFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    self.fishingDetectionFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self.fishingDetectionFrame:RegisterEvent("LOOT_READY")

    self.fishingDetectionFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_START" then
            local unit, spellName = ...
            if unit == "player" and spellName == "Fishing" then
                FishingModule:OnFishingStart()
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit = ...
            if unit == "player" then
                FishingModule:OnFishingEnd()
            end
        elseif event == "LOOT_READY" then
            if FishingModule.fishingState.isFishing then
                FishingModule:OnFishCaught()
            end
        end
    end)
end

function FishingModule:OnFishingStart()
    self.fishingState.isFishing = true
    self.fishingState.lastCastTime = GetTime()
    self.sessionData.totalCasts = self.sessionData.totalCasts + 1

    -- Auto-apply bait if enabled and no bait active
    if self.settings.autoApplyBait and GetTime() > self.fishingState.currentBaitExpiry then
        if #self.availableBaits > 0 then
            self:ApplyBait(self.availableBaits[1].name)
        end
    end

    -- Start bobber watching
    self:StartBobberWatch()
end

function FishingModule:OnFishingEnd()
    self.fishingState.isFishing = false
    self.fishingState.hasBobber = false
    self.fishingState.bobberGUID = nil
    self:StopBobberWatch()
end

function FishingModule:OnFishCaught()
    self.sessionData.successfulCasts = self.sessionData.successfulCasts + 1

    if self.settings.soundAlerts then
        PlaySound("FishingBobberSplash")
    end
end

function FishingModule:StartBobberWatch()
    if not self.settings.showBobberAlert then return end

    self.bobberWatchTimer = FizzureCommon:NewTicker(0.1, function()
        self:CheckBobberState()
    end)
end

function FishingModule:StopBobberWatch()
    if self.bobberWatchTimer then
        self.bobberWatchTimer:Cancel()
        self.bobberWatchTimer = nil
    end
end

function FishingModule:CheckBobberState()
    -- This would need more complex implementation to detect bobber splashing
    -- For now, we'll rely on loot events
end

function FishingModule:CreateOneClickFishing()
    if self.oneClickButton then return end

    -- Create secure action button for one-click fishing
    self.oneClickButton = CreateFrame("Button", "FizzureOneClickFishing", UIParent, "SecureActionButtonTemplate")
    self.oneClickButton:SetSize(1, 1)
    self.oneClickButton:Hide()

    -- Set up the macro for fishing
    self.oneClickButton:SetAttribute("type", "macro")
    self.oneClickButton:SetAttribute("macrotext", "/cast Fishing")

    -- Bind to left mouse button when enabled
    self.oneClickButton:SetAttribute("*type1", "macro")
end

function FishingModule:ToggleOneClickFishing()
    self.fishingState.oneClickActive = not self.fishingState.oneClickActive

    if self.fishingState.oneClickActive then
        self:EnableOneClickFishing()
        self.oneClickBtn:SetText("One-Click: ON")
        self.oneClickBtn:SetAlpha(1)
    else
        self:DisableOneClickFishing()
        self.oneClickBtn:SetText("One-Click: OFF")
        self.oneClickBtn:SetAlpha(0.7)
    end
end

function FishingModule:EnableOneClickFishing()
    if not self.oneClickButton then
        self:CreateOneClickFishing()
    end

    -- Hook left mouse button clicks
    self.originalOnMouseDown = WorldFrame:GetScript("OnMouseDown")
    WorldFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and FishingModule.fishingState.oneClickActive then
            FishingModule:CastFishingLine()
        elseif FishingModule.originalOnMouseDown then
            FishingModule.originalOnMouseDown(self, button)
        end
    end)
end

function FishingModule:DisableOneClickFishing()
    if self.originalOnMouseDown then
        WorldFrame:SetScript("OnMouseDown", self.originalOnMouseDown)
        self.originalOnMouseDown = nil
    end
end

function FishingModule:CastFishingLine()
    -- Check if we're already fishing
    if self.fishingState.isFishing then return end

    -- Check if we have fishing skill
    local fishingSkill = self:GetFishingSkill()
    if fishingSkill == 0 then
        self.Fizzure:ShowNotification("No Fishing Skill", "You need to learn fishing first!", "error", 3)
        return
    end

    -- Check if we have a fishing pole equipped
    local mainHandLink = GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))
    if not mainHandLink then
        self.Fizzure:ShowNotification("No Fishing Pole", "Equip a fishing pole first!", "error", 3)
        return
    end

    local itemName = GetItemInfo(mainHandLink)
    if not FISHING_POLES[itemName] then
        self.Fizzure:ShowNotification("No Fishing Pole", "Equip a fishing pole first!", "error", 3)
        return
    end

    -- Cast fishing
    CastSpellByName("Fishing")
end

function FishingModule:GetFishingSkill()
    for i = 1, GetNumSkillLines() do
        local skillName, _, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if skillName == "Fishing" then
            return skillRank, skillMaxRank
        end
    end
    return 0, 0
end

function FishingModule:UpdateFishingSkill()
    local skill, maxSkill = self:GetFishingSkill()
    if self.skillLabel then
        self.skillLabel:SetText("Fishing: " .. skill .. "/" .. maxSkill)
    end
end

function FishingModule:UpdateBaitStatus()
    if not self.baitLabel then return end

    if GetTime() > self.fishingState.currentBaitExpiry then
        self.baitLabel:SetText("No Bait Applied")
        self.baitLabel:SetTextColor(1, 0.5, 0.5)
    else
        local remaining = self.fishingState.currentBaitExpiry - GetTime()
        self.baitLabel:SetText("Bait: " .. math.floor(remaining / 60) .. ":" .. string.format("%02d", remaining % 60))
        self.baitLabel:SetTextColor(0.5, 1, 0.5)
    end
end

function FishingModule:UpdateFishingFrame()
    if not self.fishingFrame or not self.fishingFrame:IsShown() then return end

    -- Update zone
    local zone = GetZoneText()
    self.zoneLabel:SetText("Zone: " .. zone)

    -- Update session stats
    local totalCatches = 0
    for _, count in pairs(self.sessionData.catches) do
        totalCatches = totalCatches + count
    end

    self.sessionLabel:SetText("Session: " .. totalCatches .. " catches")

    -- Update one-click button state
    if self.fishingState.oneClickActive then
        self.oneClickBtn:SetText("One-Click: ON")
        self.oneClickBtn:SetAlpha(1)
    else
        self.oneClickBtn:SetText("One-Click: OFF")
        self.oneClickBtn:SetAlpha(0.7)
    end
end

function FishingModule:UpdateFishingState()
    -- Auto-scan for baits periodically
    if GetTime() % 30 < 0.5 then -- Every 30 seconds
        self:ScanAvailableBaits()
    end
end

function FishingModule:HandleFishingLoot()
    -- Track items caught
    for i = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(i)
        if itemLink then
            local itemName = GetItemInfo(itemLink)
            local _, _, _, quantity = GetLootSlotInfo(i)

            if itemName then
                self.sessionData.catches[itemName] = (self.sessionData.catches[itemName] or 0) + (quantity or 1)

                -- Check if it's a rare item
                local _, _, quality = GetItemInfo(itemLink)
                if quality and quality >= 3 then -- Rare or better
                    table.insert(self.sessionData.rareItems, {
                        name = itemName,
                        link = itemLink,
                        time = GetTime() - self.sessionData.startTime
                    })

                    if self.settings.notifications.rareChatch then
                        self.Fizzure:ShowNotification("Rare Catch!",
                                "Caught: " .. itemLink, "success", 5)
                    end
                end

                -- Add to estimated value
                local vendorPrice = FizzureCommon:GetItemSellPrice(itemName) or 0
                self.sessionData.totalValue = self.sessionData.totalValue + (vendorPrice * (quantity or 1))
            end
        end
    end
end

function FishingModule:AutoLootFish()
    if not self.settings.autoLoot then return end

    for i = 1, GetNumLootItems() do
        LootSlot(i)
    end
end

function FishingModule:HandleFishingError(messageType)
    -- Handle various fishing-related error messages
    -- This would need specific error message IDs for fishing errors
end

function FishingModule:OnZoneChanged()
    local newZone = GetZoneText()
    if newZone ~= self.sessionData.currentZone then
        self.sessionData.currentZone = newZone
        -- Could reset certain tracking or notify about fishing opportunities
    end
end

function FishingModule:ToggleBaitPanel()
    if self.baitPanel:IsShown() then
        self.baitPanel:Hide()
    else
        self:ScanAvailableBaits()
        self:UpdateBaitPanel()
        self.baitPanel:Show()
    end
end

function FishingModule:ToggleCatchTracker()
    if self.catchTracker:IsShown() then
        self.catchTracker:Hide()
    else
        self:UpdateCatchTracker()
        self.catchTracker:Show()
    end
end

function FishingModule:UpdateCatchTracker()
    if not self.catchTracker or not self.catchTracker:IsShown() then return end

    -- Update session stats
    local sessionTime = GetTime() - self.sessionData.startTime
    local hours = math.floor(sessionTime / 3600)
    local minutes = math.floor((sessionTime % 3600) / 60)

    self.sessionTimeLabel:SetText("Time: " .. hours .. ":" .. string.format("%02d", minutes))
    self.totalCastsLabel:SetText("Casts: " .. self.sessionData.totalCasts)

    local successRate = self.sessionData.totalCasts > 0 and
            (self.sessionData.successfulCasts / self.sessionData.totalCasts * 100) or 0
    self.successRateLabel:SetText("Success: " .. string.format("%.1f%%", successRate))

    self.skillGainsLabel:SetText("Skill Gains: " .. self.sessionData.skillGains)
    self.totalValueLabel:SetText("Est. Value: " .. FizzureCommon:FormatMoney(self.sessionData.totalValue))

    local totalCatches = 0
    for _, count in pairs(self.sessionData.catches) do
        totalCatches = totalCatches + count
    end
    self.catchesCountLabel:SetText("Total Catches: " .. totalCatches)

    -- Update catches list
    self:UpdateCatchesList()
end

function FishingModule:UpdateCatchesList()
    local content = self.catchesScroll.content

    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    local yOffset = -10

    -- Sort catches by count
    local sortedCatches = {}
    for itemName, count in pairs(self.sessionData.catches) do
        table.insert(sortedCatches, {name = itemName, count = count})
    end
    table.sort(sortedCatches, function(a, b) return a.count > b.count end)

    for i, catch in ipairs(sortedCatches) do
        local catchFrame = CreateFrame("Frame", nil, content)
        catchFrame:SetSize(360, 20)
        catchFrame:SetPoint("TOPLEFT", 10, yOffset)

        local nameText = catchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetText(catch.name)

        local countText = catchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("RIGHT", -5, 0)
        countText:SetText("x" .. catch.count)
        countText:SetTextColor(1, 1, 0)

        yOffset = yOffset - 22
    end

    -- Update scroll height
    local totalHeight = math.abs(yOffset) + 20
    content:SetHeight(math.max(totalHeight, 300))
end

function FishingModule:MinimizeFishingFrame()
    if self.fishingFrame.minimized then
        self.fishingFrame:SetHeight(300)
        self.minimizeBtn:SetText("-")
        self.fishingFrame.minimized = false
    else
        self.fishingFrame:SetHeight(50)
        self.minimizeBtn:SetText("+")
        self.fishingFrame.minimized = true
    end
end

function FishingModule:ClearSessionData()
    self.sessionData = {
        catches = {},
        startTime = GetTime(),
        totalCasts = 0,
        successfulCasts = 0,
        skillGains = 0,
        currentZone = GetZoneText(),
        rareItems = {},
        totalValue = 0
    }

    self:UpdateCatchTracker()
    self.Fizzure:ShowNotification("Session Cleared", "Fishing session data has been reset", "info", 2)
end

function FishingModule:SaveSessionData()
    -- Save session data to settings for persistence
    self.settings.lastSession = {
        date = date("%Y-%m-%d %H:%M"),
        duration = GetTime() - self.sessionData.startTime,
        catches = self.sessionData.catches,
        totalCasts = self.sessionData.totalCasts,
        successfulCasts = self.sessionData.successfulCasts,
        skillGains = self.sessionData.skillGains,
        totalValue = self.sessionData.totalValue
    }

    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function FishingModule:CreateConfigUI(parent, x, y)
    local showFrameCheck = FizzureUI:CreateCheckBox(parent, "Show fishing frame",
            self.settings.showFishingFrame, function(checked)
                self.settings.showFishingFrame = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.fishingFrame:Show()
                else
                    self.fishingFrame:Hide()
                end
            end)
    showFrameCheck:SetPoint("TOPLEFT", x, y)

    local oneClickCheck = FizzureUI:CreateCheckBox(parent, "Enable one-click fishing",
            self.settings.oneClickFishing, function(checked)
                self.settings.oneClickFishing = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    oneClickCheck:SetPoint("TOPLEFT", x, y - 25)

    local autoLootCheck = FizzureUI:CreateCheckBox(parent, "Auto-loot catches",
            self.settings.autoLoot, function(checked)
                self.settings.autoLoot = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    autoLootCheck:SetPoint("TOPLEFT", x, y - 50)

    local soundAlertsCheck = FizzureUI:CreateCheckBox(parent, "Sound alerts",
            self.settings.soundAlerts, function(checked)
                self.settings.soundAlerts = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    soundAlertsCheck:SetPoint("TOPLEFT", x, y - 75)

    local autoApplyCheck = FizzureUI:CreateCheckBox(parent, "Auto-apply best bait",
            self.settings.autoApplyBait, function(checked)
                self.settings.autoApplyBait = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    autoApplyCheck:SetPoint("TOPLEFT", x, y - 100)

    local showFrameBtn = FizzureUI:CreateButton(parent, "Show Frame", 80, 24, function()
        self.fishingFrame:Show()
        self:UpdateFishingFrame()
    end)
    showFrameBtn:SetPoint("TOPLEFT", x, y - 130)

    local baitsBtn = FizzureUI:CreateButton(parent, "Baits", 60, 24, function()
        self:ToggleBaitPanel()
    end)
    baitsBtn:SetPoint("TOPLEFT", x + 90, y - 130)

    return y - 160
end

function FishingModule:GetQuickStatus()
    local skill, maxSkill = self:GetFishingSkill()
    local totalCatches = 0
    for _, count in pairs(self.sessionData.catches) do
        totalCatches = totalCatches + count
    end

    return string.format("Fishing: %d/%d, Catches: %d", skill, maxSkill, totalCatches)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Fishing Helper", FishingModule, "General")
end