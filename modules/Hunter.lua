-- Hunter.lua - Hunter Pet Management Module with FIXED food list and drag/drop
local HunterModule = {}

HunterModule.name = "Hunter Pet Manager"
HunterModule.version = "3.3"
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

function HunterModule:EnsureSettings()
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        if self.Fizzure then
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end
    end
end

function HunterModule:Initialize()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        return false
    end

    if not self.Fizzure then
        print("|cffff0000Hunter Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    self:EnsureSettings()

    self.debugAPI = self.Fizzure:GetDebugAPI()

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
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
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
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        self:ScanAvailableFoods()
        self:UpdateStatusFrame()
        if self.profileFrame and self.profileFrame:IsShown() then
            -- Delay the update slightly to ensure bag data is ready
            FizzureCommon:After(0.1, function()
                self:UpdatePetProfileFrame()
            end)
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
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end
    end
end

-- ENHANCED and FIXED food scanning that actually works
function HunterModule:ScanAvailableFoods()
    self.availableFoods = {}

    -- Common food items by type for 3.3.5 WotLK
    local foodTypes = {
        -- Meat and Fish
        "meat", "fish", "salmon", "venison", "boar", "clefthoof", "mammoth",
        -- Bread and Cheese
        "bread", "cheese", "biscuit",
        -- Fruits and Vegetables
        "apple", "fruit", "berry", "banana",
        -- Special foods
        "conjured", "food", "ration"
    }

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local _, itemCount = GetContainerItemInfo(bag, slot)
                if itemCount and itemCount > 0 then
                    -- Get item info
                    local itemName, _, quality, itemLevel, minLevel, itemType, itemSubType = GetItemInfo(itemLink)

                    if itemName and itemType then
                        local isFood = false
                        local itemNameLower = string.lower(itemName)

                        -- Check if it's explicitly food type
                        if itemType == "Consumable" and
                                (itemSubType == "Food & Drink" or itemSubType == "Food") then
                            isFood = true
                        end

                        -- Check against common food keywords if not already identified
                        if not isFood then
                            for _, foodType in ipairs(foodTypes) do
                                if string.find(itemNameLower, foodType) then
                                    isFood = true
                                    break
                                end
                            end
                        end

                        -- Special check for items that might be food but missed
                        if not isFood and itemType == "Consumable" then
                            -- Check for food-like patterns
                            if string.find(itemNameLower, "roasted") or
                                    string.find(itemNameLower, "cooked") or
                                    string.find(itemNameLower, "smoked") or
                                    string.find(itemNameLower, "fresh") or
                                    string.find(itemNameLower, "raw") then
                                isFood = true
                            end
                        end

                        if isFood then
                            table.insert(self.availableFoods, {
                                name = itemName,
                                link = itemLink,
                                count = itemCount,
                                quality = quality or 1,
                                level = itemLevel or 1,
                                bag = bag,
                                slot = slot
                            })
                        end
                    end
                end
            end
        end
    end

    -- Sort by name for consistent display
    table.sort(self.availableFoods, function(a, b)
        return a.name < b.name
    end)

    -- Debug output
    if self.Fizzure and self.Fizzure.debug.enabled then
        self.Fizzure:LogDebug("DEBUG", "Found " .. #self.availableFoods .. " food items", "Hunter")
    end
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
            self.Fizzure:ShowNotification("Low Food Warning",
                    "Running low on food for " .. self.currentPet.name .. " (" .. totalFood .. " remaining)",
                    "warning", 5)
        end
    end
end

function HunterModule:CreateStatusFrame()
    self.statusFrame = FizzureUI:CreateStatusFrame("HunterPetStatus", "Pet Status", 200, 180)

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

    -- Happiness bar
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
        -- Immediately update status after feeding
        FizzureCommon:After(0.1, function()
            self:UpdateStatusFrame()
        end)
    end)
    self.feedButton:SetPoint("TOP", 0, -95)

    -- Profile button
    self.profileButton = FizzureUI:CreateButton(self.statusFrame, "Profiles", 80, 20, function()
        self:ToggleProfileFrame()
    end)
    self.profileButton:SetPoint("TOP", 0, -125)

    -- Keybinding info (positioned below buttons)
    self.keybindLabel = FizzureUI:CreateLabel(self.statusFrame, "Key: " .. (self.settings.keybindings.feedPet or "None"), "GameFontNormalSmall")
    self.keybindLabel:SetPoint("TOP", 0, -150)

    -- Save position on move
    self.statusFrame.OnPositionChanged = function()
        local point, _, relativePoint, x, y = self.statusFrame:GetPoint()
        self.settings.windowPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
        self.Fizzure:SetModuleSettings(self.name, self.settings)
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
                    self.Fizzure:ShowNotification("Pet Fed",
                            self.currentPet.name .. " fed with " .. foodName,
                            "success", 3)
                end

                profile.lastFed = GetTime()
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                return
            end
        end
    end

    if self.settings.notifications.noFood then
        self.Fizzure:ShowNotification("No Food",
                "No preferred food available for " .. self.currentPet.name,
                "warning", 3)
    end
end

-- COMPLETELY REWRITTEN pet profile frame with WORKING food list
function HunterModule:CreatePetProfileFrame()
    self.profileFrame = FizzureUI:CreateWindow("HunterPetProfiles", "Pet Food Profiles", 650, 500)

    -- Current pet label
    self.currentPetLabel = FizzureUI:CreateLabel(self.profileFrame.content, "Current Pet: None", "GameFontNormalLarge")
    self.currentPetLabel:SetPoint("TOP", 0, -10)

    -- LEFT SIDE - Preferred Foods Panel
    local leftPanel = CreateFrame("Frame", nil, self.profileFrame.content)
    leftPanel:SetSize(280, 350)
    leftPanel:SetPoint("TOPLEFT", 20, -50)
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    leftPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

    local leftTitle = FizzureUI:CreateLabel(leftPanel, "Preferred Foods", "GameFontNormal")
    leftTitle:SetPoint("TOP", 0, -10)

    -- Food slots in a 2x3 grid - ENHANCED with better icon handling
    self.foodSlots = {}
    for i = 1, 6 do
        local slot = CreateFrame("Button", "FizzureFoodSlot" .. i, leftPanel)
        slot:SetSize(50, 50)
        slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-White")
        slot:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

        -- Background texture for empty slots
        local emptyTexture = slot:CreateTexture(nil, "BACKGROUND")
        emptyTexture:SetSize(46, 46)
        emptyTexture:SetPoint("CENTER")
        emptyTexture:SetTexture("Interface\\Icons\\INV_Misc_Food_01")
        emptyTexture:SetAlpha(0.3)
        slot.emptyTexture = emptyTexture

        -- Item texture (will be shown when item is set)
        local itemTexture = slot:CreateTexture(nil, "ARTWORK")
        itemTexture:SetSize(46, 46)
        itemTexture:SetPoint("CENTER")
        itemTexture:Hide()
        slot.itemTexture = itemTexture

        -- Count text
        local countText = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        countText:SetPoint("BOTTOMRIGHT", -2, 2)
        slot.countText = countText

        -- Position the slot
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        slot:SetPoint("TOPLEFT", 60 + col * 70, -50 - row * 70)

        -- Click handlers
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                HunterModule:ClearFoodSlot(i)
            end
        end)

        -- Drag and drop
        slot:RegisterForDrag("LeftButton")
        slot:SetScript("OnDragStart", function(self)
            if slot.itemName then
                PickupItem(slot.itemName)
            end
        end)

        slot:SetScript("OnReceiveDrag", function(self)
            HunterModule:HandleFoodDrop(i)
        end)

        -- Tooltip
        slot:SetScript("OnEnter", function(self)
            if slot.itemName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(slot.itemName)
                GameTooltip:Show()
            else
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Empty Food Slot")
                GameTooltip:AddLine("Drag food here or right-click from list", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)

        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Helper functions for the slot
        slot.SetItem = function(self, itemName, itemLink)
            self.itemName = itemName
            self.itemLink = itemLink or itemName

            if itemName then
                -- Get item icon with multiple fallback methods
                local itemIcon = nil

                -- Method 1: Direct GetItemIcon
                if GetItemIcon then
                    itemIcon = GetItemIcon(itemName)
                end

                -- Method 2: From GetItemInfo
                if not itemIcon then
                    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemName)
                    itemIcon = icon
                end

                -- Method 3: From item link if available
                if not itemIcon and itemLink and itemLink ~= itemName then
                    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemLink)
                    itemIcon = icon
                end

                -- Set the texture
                if itemIcon then
                    self.itemTexture:SetTexture(itemIcon)
                    self.itemTexture:Show()
                    self.emptyTexture:Hide()
                else
                    -- Fallback to default food icon
                    self.itemTexture:SetTexture("Interface\\Icons\\INV_Misc_Food_01")
                    self.itemTexture:Show()
                    self.emptyTexture:Hide()
                end

                -- Update count
                local count = GetItemCount(itemName)
                if count and count > 1 then
                    self.countText:SetText(count)
                    self.countText:Show()
                else
                    self.countText:SetText("")
                    self.countText:Hide()
                end
            else
                self:ClearItem()
            end
        end

        slot.ClearItem = function(self)
            self.itemName = nil
            self.itemLink = nil
            self.itemTexture:Hide()
            self.emptyTexture:Show()
            self.countText:SetText("")
            self.countText:Hide()
        end

        slot.index = i
        self.foodSlots[i] = slot
    end

    -- RIGHT SIDE - Available Foods Panel
    local rightPanel = CreateFrame("Frame", nil, self.profileFrame.content)
    rightPanel:SetSize(300, 350)
    rightPanel:SetPoint("TOPRIGHT", -20, -50)
    rightPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

    local rightTitle = FizzureUI:CreateLabel(rightPanel, "Available Foods", "GameFontNormal")
    rightTitle:SetPoint("TOP", 0, -10)

    local rightSubtitle = FizzureUI:CreateLabel(rightPanel, "(Right-click to add)", "GameFontNormalSmall")
    rightSubtitle:SetPoint("TOP", 0, -25)

    -- Refresh button
    local refreshBtn = FizzureUI:CreateButton(rightPanel, "Refresh", 60, 20, function()
        self:ScanAvailableFoods()
        self:UpdatePetProfileFrame()
    end)
    refreshBtn:SetPoint("TOPRIGHT", -10, -10)

    -- Scroll frame for food list
    self.foodListScroll = CreateFrame("ScrollFrame", "FoodListScroll", rightPanel, "UIPanelScrollFrameTemplate")
    self.foodListScroll:SetPoint("TOPLEFT", 10, -50)
    self.foodListScroll:SetPoint("BOTTOMRIGHT", -25, 10)

    local foodListContent = CreateFrame("Frame", "FoodListContent", self.foodListScroll)
    foodListContent:SetSize(250, 1)
    self.foodListScroll:SetScrollChild(foodListContent)
    self.foodListContent = foodListContent

    -- Enable mousewheel scrolling
    self.foodListScroll:EnableMouseWheel(true)
    self.foodListScroll:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = currentScroll - (delta * 25)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- Bottom buttons
    local clearAllBtn = FizzureUI:CreateButton(self.profileFrame.content, "Clear All", 80, 24, function()
        self:ClearAllFoodSlots()
    end)
    clearAllBtn:SetPoint("BOTTOM", 0, 15)
end

-- COMPLETELY REWRITTEN update function that ACTUALLY works
function HunterModule:UpdatePetProfileFrame()
    if not self.profileFrame or not self.profileFrame:IsShown() then return end

    -- Update pet name
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
        else
            for i = 1, 6 do
                self.foodSlots[i]:ClearItem()
            end
        end
    else
        self.currentPetLabel:SetText("Current Pet: None")
        for i = 1, 6 do
            self.foodSlots[i]:ClearItem()
        end
    end

    -- FORCIBLY rescan foods to ensure we have the latest data
    self:ScanAvailableFoods()

    -- Clear existing food list items
    local content = self.foodListContent
    local children = {content:GetChildren()}
    for i = 1, #children do
        children[i]:Hide()
        children[i]:SetParent(nil)
    end

    -- Create new food list items
    local yOffset = -5
    local buttonHeight = 30

    if #self.availableFoods == 0 then
        -- Show "no food found" message
        local noFoodLabel = FizzureUI:CreateLabel(content, "No food items found in bags", "GameFontNormal")
        noFoodLabel:SetPoint("TOPLEFT", 5, yOffset)
        noFoodLabel:SetTextColor(0.7, 0.7, 0.7)
        yOffset = yOffset - 25

        local helpLabel = FizzureUI:CreateLabel(content, "Make sure you have food items in your bags", "GameFontNormalSmall")
        helpLabel:SetPoint("TOPLEFT", 5, yOffset)
        helpLabel:SetTextColor(0.5, 0.5, 0.5)
        yOffset = yOffset - 25
    else
        -- Create food item buttons
        for i, food in ipairs(self.availableFoods) do
            local foodFrame = CreateFrame("Button", "FoodButton" .. i, content)
            foodFrame:SetSize(240, buttonHeight)
            foodFrame:SetPoint("TOPLEFT", 5, yOffset)

            -- Background for hover effect
            local bg = foodFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            bg:SetAlpha(0)
            foodFrame:SetNormalTexture(bg)
            foodFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            -- Food icon with better icon retrieval
            local icon = foodFrame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("LEFT", 2, 0)

            -- Multiple attempts to get the correct icon
            local itemIcon = nil
            if GetItemIcon then
                itemIcon = GetItemIcon(food.name)
            end
            if not itemIcon then
                local _, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(food.name)
                itemIcon = iconTexture
            end
            if not itemIcon and food.link then
                local _, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(food.link)
                itemIcon = iconTexture
            end

            if itemIcon then
                icon:SetTexture(itemIcon)
            else
                icon:SetTexture("Interface\\Icons\\INV_Misc_Food_01")
            end

            -- Food name with quality color
            local nameText = foodFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            nameText:SetText(food.name)

            -- Set quality color
            local qualityColors = {
                [0] = {0.6, 0.6, 0.6},  -- Poor (gray)
                [1] = {1, 1, 1},        -- Common (white)
                [2] = {0.12, 1, 0},     -- Uncommon (green)
                [3] = {0, 0.44, 0.87},  -- Rare (blue)
                [4] = {0.64, 0.21, 0.93}, -- Epic (purple)
                [5] = {1, 0.5, 0}       -- Legendary (orange)
            }
            local color = qualityColors[food.quality] or qualityColors[1]
            nameText:SetTextColor(color[1], color[2], color[3])

            -- Food count
            local countText = foodFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            countText:SetPoint("RIGHT", -5, 0)
            countText:SetText("x" .. food.count)
            countText:SetTextColor(0.8, 0.8, 0.8)

            -- Right-click to add to preferred foods
            foodFrame:RegisterForClicks("RightButtonUp")
            foodFrame:SetScript("OnClick", function()
                self:AddFoodToProfile(food.name)
            end)

            -- Tooltip
            foodFrame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(foodFrame, "ANCHOR_RIGHT")
                if food.link then
                    GameTooltip:SetHyperlink(food.link)
                else
                    GameTooltip:SetItemByID(food.name)
                end
                GameTooltip:AddLine("Right-click to add to preferred foods", 0.7, 0.7, 1)
                GameTooltip:Show()
            end)

            foodFrame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            yOffset = yOffset - buttonHeight - 2
        end
    end

    -- Update scroll child height
    local totalHeight = math.abs(yOffset) + 20
    self.foodListContent:SetHeight(math.max(totalHeight, 300))

    -- Debug output
    if self.Fizzure and self.Fizzure.debug.enabled then
        self.Fizzure:LogDebug("DEBUG", "Updated profile frame with " .. #self.availableFoods .. " foods", "Hunter")
    end
end

function HunterModule:AddFoodToProfile(foodName)
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then return end

    if not profile.preferredFoods then
        profile.preferredFoods = {}
    end

    -- Check if food is already in the list
    for i = 1, 6 do
        if profile.preferredFoods[i] == foodName then
            self.Fizzure:ShowNotification("Already Added", foodName .. " is already in preferred foods", "info", 2)
            return
        end
    end

    -- Find first empty slot
    for i = 1, 6 do
        if not profile.preferredFoods[i] or profile.preferredFoods[i] == "" then
            profile.preferredFoods[i] = foodName
            self.Fizzure:SetModuleSettings(self.name, self.settings)

            -- Update the slot display immediately
            self.foodSlots[i]:SetItem(foodName)

            -- Update status window
            self:UpdateStatusFrame()

            self.Fizzure:ShowNotification("Food Added", foodName .. " added to preferred foods", "success", 2)
            return
        end
    end

    self.Fizzure:ShowNotification("Slots Full", "All preferred food slots are full", "warning", 2)
end

function HunterModule:ClearFoodSlot(index)
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        local removedFood = profile.preferredFoods[index]
        profile.preferredFoods[index] = nil
        self.Fizzure:SetModuleSettings(self.name, self.settings)

        -- Update the slot display immediately
        self.foodSlots[index]:ClearItem()

        -- Update status window
        self:UpdateStatusFrame()

        if removedFood then
            self.Fizzure:ShowNotification("Food Removed", removedFood .. " removed from preferred foods", "info", 2)
        end
    end
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
                    self.Fizzure:SetModuleSettings(self.name, self.settings)

                    -- Update the slot display immediately with proper icon
                    self.foodSlots[index]:SetItem(itemName, itemLink)

                    -- Update status window
                    self:UpdateStatusFrame()

                    self.Fizzure:ShowNotification("Food Added", itemName .. " added to slot " .. index, "success", 2)
                end
            end
            ClearCursor()
        end
    end
end

function HunterModule:ClearAllFoodSlots()
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile then
        profile.preferredFoods = {}
        self.Fizzure:SetModuleSettings(self.name, self.settings)

        for i = 1, 6 do
            self.foodSlots[i]:ClearItem()
        end

        self:UpdateStatusFrame()
        self.Fizzure:ShowNotification("Cleared", "All preferred foods cleared", "info", 2)
    end
end

function HunterModule:ToggleProfileFrame()
    if self.profileFrame:IsShown() then
        self.profileFrame:Hide()
    else
        -- Force rescan when opening
        self:ScanAvailableFoods()
        self:UpdatePetProfileFrame()
        self.profileFrame:Show()
    end
end

function HunterModule:CreateConfigUI(parent, x, y)
    -- Ensure settings are available
    self:EnsureSettings()

    local showStatusCheck = FizzureUI:CreateCheckBox(parent, "Show status window",
            self.settings.showFoodStatus, function(checked)
                self.settings.showFoodStatus = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

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
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end
    end)
    thresholdInput:SetPoint("LEFT", thresholdLabel, "RIGHT", 10, 0)
    thresholdInput:SetText(tostring(self.settings.lowFoodThreshold))

    local keybindLabel = FizzureUI:CreateLabel(parent, "Feed pet key:")
    keybindLabel:SetPoint("TOPLEFT", x, y - 60)

    local keybindInput = FizzureUI:CreateEditBox(parent, 100, 20, function(text)
        self.settings.keybindings.feedPet = text
        self.Fizzure:SetModuleSettings(self.name, self.settings)
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
    Fizzure:RegisterModule("Hunter Pet Manager", HunterModule, "HUNTER")
end