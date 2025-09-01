-- Hunter.lua - Hunter Pet Management Module
local HunterModule = {}

HunterModule.name = "Hunter Pet Manager"
HunterModule.version = "3.2"
HunterModule.author = "Fizzure"
HunterModule.category = "Class-Specific"
HunterModule.classRestriction = "HUNTER"

function HunterModule:GetDefaultSettings()
    return {
        enabled = true,
        showFoodStatus = true,
        lowFoodThreshold = 10,
        statusFrameMinimized = false,
        windowPosition = nil,
        petProfiles = {},
        keybindings = {
            feedPet = "ALT-F",
            toggleStatus = "ALT-SHIFT-F"
        },
        notifications = {
            feeding = true,
            lowFood = true,
            noFood = true
        }
    }
end

function HunterModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showFoodStatus) == "boolean" and
            type(settings.lowFoodThreshold) == "number"
end

function HunterModule:Initialize()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        return false
    end

    if not self.fizzure then
        print("|cffff0000Hunter Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.fizzure:SetModuleSettings(self.name, self.settings)
    end

    self.debugAPI = self.fizzure:GetDebugAPI()

    -- Initialize tracking variables
    self.currentPet = nil
    self.availableFoods = {}
    self.lastFoodCheck = 0
    self.lastManualFeed = 0

    -- Create UI elements
    self:CreateStatusFrame()
    self:CreatePetProfileFrame()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("UNIT_PET")
    self.eventFrame:RegisterEvent("PET_UI_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_PET_CHANGED")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        HunterModule:OnEvent(event, ...)
    end)

    -- Update timer
    self.updateTimer = FizzureCommon:NewTicker(10, function()
        self:UpdateCurrentPet()
        self:CheckFoodSupply()
        self:UpdateStatusFrame()
    end)

    -- Initialize pet data
    self:UpdateCurrentPet()
    self:ScanAvailableFoods()

    if self.settings.showFoodStatus then
        self.statusFrame:Show()
    end

    print("|cff00ff00Hunter Module|r Initialized")
    return true
end

function HunterModule:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.statusFrame then
        self.statusFrame:Hide()
    end

    if self.profileFrame then
        self.profileFrame:Hide()
    end
end

function HunterModule:OnEvent(event, ...)
    if event == "UNIT_PET" or event == "PLAYER_PET_CHANGED" then
        self:UpdateCurrentPet()
    elseif event == "PET_UI_UPDATE" then
        self:UpdateStatusFrame()
    elseif event == "BAG_UPDATE" then
        self:ScanAvailableFoods()
        self:UpdateStatusFrame()
        if self.profileFrame and self.profileFrame:IsShown() then
            self:UpdatePetProfileFrame()
        end
    end
end

function HunterModule:UpdateCurrentPet()
    if not UnitExists("pet") then
        self.currentPet = nil
        return
    end

    local name = UnitName("pet")
    local family = UnitCreatureFamily("pet")
    local level = UnitLevel("pet") or 1

    if name then
        self.currentPet = {
            name = name,
            family = family or "Unknown",
            level = level
        }

        -- Ensure profile exists
        if not self.settings.petProfiles[name] then
            self.settings.petProfiles[name] = {
                family = family or "Unknown",
                preferredFoods = {},
                lastFed = 0
            }
            self.fizzure:SetModuleSettings(self.name, self.settings)
        end
    end
end

function HunterModule:ScanAvailableFoods()
    self.availableFoods = {}

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
                local _, count = GetContainerItemInfo(bag, slot)

                if itemType == "Consumable" and
                        (itemSubType == "Food & Drink" or itemSubType == "Food" or itemSubType == "Meat") then
                    table.insert(self.availableFoods, {
                        name = name,
                        link = link,
                        count = count or 0,
                        bag = bag,
                        slot = slot
                    })
                end
            end
        end
    end

    table.sort(self.availableFoods, function(a, b) return a.name < b.name end)
end

function HunterModule:CheckFoodSupply()
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile or not profile.preferredFoods then return end

    local totalFood = 0
    for i = 1, 6 do
        local foodName = profile.preferredFoods[i]
        if foodName and foodName ~= "" then
            totalFood = totalFood + FizzureCommon:GetItemCount(foodName)
        end
    end

    if totalFood > 0 and totalFood <= self.settings.lowFoodThreshold then
        if self.settings.notifications.lowFood then
            self.fizzure:ShowNotification("Low Food Warning",
                    "Running low on food for " .. self.currentPet.name .. " (" .. totalFood .. " remaining)",
                    "warning", 5)
        end
    end
end

function HunterModule:CreateStatusFrame()
    self.statusFrame = FizzureUI:CreateStatusFrame("HunterPetStatus", "Pet Status", 200, 160)

    if self.settings.windowPosition then
        self.statusFrame:ClearAllPoints()
        self.statusFrame:SetPoint(self.settings.windowPosition.point,
                UIParent,
                self.settings.windowPosition.relativePoint,
                self.settings.windowPosition.x,
                self.settings.windowPosition.y)
    end

    -- Pet name
    self.petNameLabel = FizzureUI:CreateLabel(self.statusFrame, "No Pet")
    self.petNameLabel:SetPoint("TOP", 0, -25)

    -- Happiness bar with proper text overlay
    self.happinessBar = FizzureUI:CreateStatusBar(self.statusFrame, 160, 16, 1, 3, 3)
    self.happinessBar:SetPoint("TOP", 0, -45)
    self.happinessBar:SetStatusBarColor(0.3, 1, 0.3)
    self.happinessBar:SetText("Happy")

    -- Food count
    self.foodLabel = FizzureUI:CreateLabel(self.statusFrame, "Food: 0")
    self.foodLabel:SetPoint("TOP", 0, -70)

    -- Feed button
    self.feedButton = FizzureUI:CreateButton(self.statusFrame, "Feed Pet", 120, 24, function()
        self:FeedPet()
    end)
    self.feedButton:SetPoint("TOP", 0, -95)

    -- Keybinding info
    self.keybindLabel = FizzureUI:CreateLabel(self.statusFrame, "Key: " .. (self.settings.keybindings.feedPet or "None"), "GameFontNormalSmall")
    self.keybindLabel:SetPoint("TOP", 0, -125)

    -- Profile button
    self.profileButton = FizzureUI:CreateButton(self.statusFrame, "Profiles", 80, 20, function()
        self:ToggleProfileFrame()
    end)
    self.profileButton:SetPoint("BOTTOM", 0, 10)

    -- Save position on move
    self.statusFrame.OnPositionChanged = function()
        local point, _, relativePoint, x, y = self.statusFrame:GetPoint()
        self.settings.windowPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
        self.fizzure:SetModuleSettings(self.name, self.settings)
    end
end

function HunterModule:UpdateStatusFrame()
    if not self.statusFrame or not self.statusFrame:IsShown() then return end

    if self.currentPet then
        self.petNameLabel:SetText(self.currentPet.name)
        self.petNameLabel:SetTextColor(1, 1, 1)

        -- Update happiness
        if UnitExists("pet") then
            local happiness = GetPetHappiness()
            if happiness then
                self.happinessBar:SetValue(happiness)

                local colors = {
                    {1, 0.3, 0.3},  -- Unhappy
                    {1, 1, 0.3},    -- Content
                    {0.3, 1, 0.3}   -- Happy
                }
                local texts = {"Unhappy", "Content", "Happy"}

                local color = colors[happiness] or colors[1]
                self.happinessBar:SetStatusBarColor(color[1], color[2], color[3])
                self.happinessBar:SetText(texts[happiness] or "Unknown")
            end
        end

        -- Update food count
        local profile = self.settings.petProfiles[self.currentPet.name]
        local totalFood = 0

        if profile and profile.preferredFoods then
            for i = 1, 6 do
                local foodName = profile.preferredFoods[i]
                if foodName and foodName ~= "" then
                    totalFood = totalFood + FizzureCommon:GetItemCount(foodName)
                end
            end
        end

        self.foodLabel:SetText("Food: " .. totalFood)
        if totalFood <= self.settings.lowFoodThreshold then
            self.foodLabel:SetTextColor(1, 0.3, 0.3)
        else
            self.foodLabel:SetTextColor(1, 1, 1)
        end

        self.feedButton:Enable()
    else
        self.petNameLabel:SetText("No Pet")
        self.petNameLabel:SetTextColor(0.7, 0.7, 0.7)
        self.happinessBar:SetValue(1)
        self.happinessBar:SetStatusBarColor(0.5, 0.5, 0.5)
        self.happinessBar:SetText("N/A")
        self.foodLabel:SetText("Food: N/A")
        self.foodLabel:SetTextColor(0.7, 0.7, 0.7)
        self.feedButton:Disable()
    end

    -- Update keybind display
    self.keybindLabel:SetText("Key: " .. (self.settings.keybindings.feedPet or "None"))
end

function HunterModule:FeedPet()
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile or not profile.preferredFoods then return end

    -- Find first available food
    for i = 1, 6 do
        local foodName = profile.preferredFoods[i]
        if foodName and foodName ~= "" then
            local count = FizzureCommon:GetItemCount(foodName)
            if count > 0 then
                CastSpellByName("Feed Pet")
                UseItemByName(foodName)

                if self.settings.notifications.feeding then
                    self.fizzure:ShowNotification("Pet Fed",
                            self.currentPet.name .. " fed with " .. foodName,
                            "success", 3)
                end

                profile.lastFed = GetTime()
                self.fizzure:SetModuleSettings(self.name, self.settings)
                return
            end
        end
    end

    if self.settings.notifications.noFood then
        self.fizzure:ShowNotification("No Food",
                "No preferred food available for " .. self.currentPet.name,
                "warning", 3)
    end
end

function HunterModule:CreatePetProfileFrame()
    self.profileFrame = FizzureUI:CreateWindow("HunterPetProfiles", "Pet Food Profiles", 600, 450)

    -- Current pet label
    self.currentPetLabel = FizzureUI:CreateLabel(self.profileFrame.content, "Current Pet: None", "GameFontNormalLarge")
    self.currentPetLabel:SetPoint("TOP", 0, -10)

    -- Left panel - Preferred foods
    local leftPanel = FizzureUI:CreatePanel(self.profileFrame.content, 250, 300)
    leftPanel:SetPoint("TOPLEFT", 20, -50)

    local leftTitle = FizzureUI:CreateLabel(leftPanel, "Preferred Foods", "GameFontNormal")
    leftTitle:SetPoint("TOP", 0, -10)

    -- Food slots
    self.foodSlots = {}
    for i = 1, 6 do
        local slot = FizzureUI:CreateFoodSlot(leftPanel, i,
                function(index) self:ClearFoodSlot(index) end,
                function(index) self:HandleFoodDrop(index) end)

        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        slot:SetPoint("TOPLEFT", 40 + col * 50, -40 - row * 50)

        self.foodSlots[i] = slot
    end

    -- Right panel - Available foods
    local rightPanel = FizzureUI:CreatePanel(self.profileFrame.content, 280, 300)
    rightPanel:SetPoint("TOPRIGHT", -20, -50)

    local rightTitle = FizzureUI:CreateLabel(rightPanel, "Available Foods (Right-click to add)", "GameFontNormal")
    rightTitle:SetPoint("TOP", 0, -10)

    self.foodListScroll = FizzureUI:CreateScrollFrame(rightPanel, 260, 250)
    self.foodListScroll:SetPoint("TOP", 0, -35)

    -- Bottom controls
    local clearAllBtn = FizzureUI:CreateButton(self.profileFrame.content, "Clear All", 80, 24, function()
        self:ClearAllFoodSlots()
    end)
    clearAllBtn:SetPoint("BOTTOM", -50, 20)

    local refreshBtn = FizzureUI:CreateButton(self.profileFrame.content, "Refresh", 80, 24, function()
        self:ScanAvailableFoods()
        self:UpdatePetProfileFrame()
    end)
    refreshBtn:SetPoint("BOTTOM", 50, 20)
end

function HunterModule:UpdatePetProfileFrame()
    if not self.profileFrame or not self.profileFrame:IsShown() then return end

    -- Update current pet label
    if self.currentPet then
        self.currentPetLabel:SetText("Current Pet: " .. self.currentPet.name .. " (" .. self.currentPet.family .. ")")

        -- Update food slots
        local profile = self.settings.petProfiles[self.currentPet.name]
        if profile and profile.preferredFoods then
            for i = 1, 6 do
                local foodName = profile.preferredFoods[i]
                if foodName and foodName ~= "" then
                    self.foodSlots[i]:SetItem(foodName)
                else
                    self.foodSlots[i]:ClearItem()
                end
            end
        end
    else
        self.currentPetLabel:SetText("Current Pet: None")
        for i = 1, 6 do
            self.foodSlots[i]:ClearItem()
        end
    end

    -- Update available foods list
    local content = self.foodListScroll.content

    -- Clear existing items
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local y = -5
    for _, food in ipairs(self.availableFoods) do
        local foodFrame = CreateFrame("Button", nil, content)
        foodFrame:SetSize(240, 24)
        foodFrame:SetPoint("TOPLEFT", 5, y)

        -- Icon
        local icon = foodFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexture(GetItemIcon(food.name))

        -- Name and count
        local text = foodFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        text:SetText(food.name .. " x" .. food.count)

        -- Highlight
        foodFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        -- Right-click to add
        foodFrame:RegisterForClicks("RightButtonUp")
        foodFrame:SetScript("OnClick", function()
            self:AddFoodToProfile(food.name)
        end)

        -- Tooltip
        foodFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(foodFrame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(food.link)
            GameTooltip:AddLine("Right-click to add to preferred foods", 0.7, 0.7, 1)
            GameTooltip:Show()
        end)

        foodFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        y = y - 26
    end

    self.foodListScroll:UpdateScrollChildHeight()
end

function HunterModule:AddFoodToProfile(foodName)
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then return end

    if not profile.preferredFoods then
        profile.preferredFoods = {}
    end

    -- Find first empty slot
    for i = 1, 6 do
        if not profile.preferredFoods[i] or profile.preferredFoods[i] == "" then
            profile.preferredFoods[i] = foodName
            self.fizzure:SetModuleSettings(self.name, self.settings)
            self:UpdatePetProfileFrame()
            return
        end
    end

    self.fizzure:ShowNotification("Slots Full", "All preferred food slots are full", "warning", 2)
end

function HunterModule:HandleFoodDrop(index)
    local cursorType, itemID, itemLink = GetCursorInfo()
    if cursorType == "item" and itemLink then
        local itemName = GetItemInfo(itemLink)
        if itemName then
            if self.currentPet then
                local profile = self.settings.petProfiles[self.currentPet.name]
                if profile then
                    if not profile.preferredFoods then
                        profile.preferredFoods = {}
                    end
                    profile.preferredFoods[index] = itemName
                    self.fizzure:SetModuleSettings(self.name, self.settings)
                    self.foodSlots[index]:SetItem(itemName, itemLink)
                end
            end
            ClearCursor()
        end
    end
end

function HunterModule:ClearFoodSlot(index)
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        profile.preferredFoods[index] = nil
        self.fizzure:SetModuleSettings(self.name, self.settings)
        self.foodSlots[index]:ClearItem()
    end
end

function HunterModule:ClearAllFoodSlots()
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile then
        profile.preferredFoods = {}
        self.fizzure:SetModuleSettings(self.name, self.settings)

        for i = 1, 6 do
            self.foodSlots[i]:ClearItem()
        end
    end
end

function HunterModule:ToggleProfileFrame()
    if self.profileFrame:IsShown() then
        self.profileFrame:Hide()
    else
        self:UpdatePetProfileFrame()
        self.profileFrame:Show()
    end
end

function HunterModule:CreateConfigUI(parent, x, y)
    local showStatusCheck = FizzureUI:CreateCheckBox(parent, "Show status window",
            self.settings.showFoodStatus, function(checked)
                self.settings.showFoodStatus = checked
                self.fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.statusFrame:Show()
                else
                    self.statusFrame:Hide()
                end
            end)
    showStatusCheck:SetPoint("TOPLEFT", x, y)

    local thresholdLabel = FizzureUI:CreateLabel(parent, "Low food threshold:")
    thresholdLabel:SetPoint("TOPLEFT", x, y - 30)

    local thresholdInput = FizzureUI:CreateEditBox(parent, 60, 20, function(text)
        local value = tonumber(text)
        if value and value >= 0 and value <= 100 then
            self.settings.lowFoodThreshold = value
            self.fizzure:SetModuleSettings(self.name, self.settings)
        end
    end)
    thresholdInput:SetPoint("LEFT", thresholdLabel, "RIGHT", 10, 0)
    thresholdInput:SetText(tostring(self.settings.lowFoodThreshold))

    local keybindLabel = FizzureUI:CreateLabel(parent, "Feed pet key:")
    keybindLabel:SetPoint("TOPLEFT", x, y - 60)

    local keybindInput = FizzureUI:CreateEditBox(parent, 100, 20, function(text)
        self.settings.keybindings.feedPet = text
        self.fizzure:SetModuleSettings(self.name, self.settings)
        self:UpdateStatusFrame()
    end)
    keybindInput:SetPoint("LEFT", keybindLabel, "RIGHT", 10, 0)
    keybindInput:SetText(self.settings.keybindings.feedPet or "")

    local profileBtn = FizzureUI:CreateButton(parent, "Pet Profiles", 100, 24, function()
        self:ToggleProfileFrame()
    end)
    profileBtn:SetPoint("TOPLEFT", x, y - 90)

    return y - 120
end

function HunterModule:GetQuickStatus()
    if not self.currentPet then
        return "No pet active"
    end

    local happiness = GetPetHappiness()
    local happinessText = {"Unhappy", "Content", "Happy"}

    local profile = self.settings.petProfiles[self.currentPet.name]
    local foodCount = 0

    if profile and profile.preferredFoods then
        for i = 1, 6 do
            local foodName = profile.preferredFoods[i]
            if foodName and foodName ~= "" then
                foodCount = foodCount + FizzureCommon:GetItemCount(foodName)
            end
        end
    end

    return string.format("%s: %s, Food: %d",
            self.currentPet.name,
            happinessText[happiness] or "Unknown",
            foodCount)
end

-- Register module
if Fizzure then
    Fizzure:RegisterClassModule("Hunter Pet Manager", HunterModule, "HUNTER")
end