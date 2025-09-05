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

function HunterModule:EnsureSettings()
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        if self.fizzure then
            self.fizzure:SetModuleSettings(self.name, self.settings)
        end
    end
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
    self:EnsureSettings()

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
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemInfo = { GetItemInfo(itemLink) }
                local itemName = itemInfo[1]
                local itemType = itemInfo[6]
                local itemSubType = itemInfo[7]
                local _, itemCount = GetContainerItemInfo(bag, slot)

                if itemName and itemType and itemCount and itemCount > 0 then
                    -- Check if it's food (be more permissive with food types)
                    if itemType == "Consumable" and
                            (itemSubType == "Food & Drink" or
                                    itemSubType == "Food" or
                                    itemSubType == "Meat" or
                                    string.find(string.lower(itemName), "bread") or
                                    string.find(string.lower(itemName), "cheese") or
                                    string.find(string.lower(itemName), "fish") or
                                    string.find(string.lower(itemName), "meat")) then

                        table.insert(self.availableFoods, {
                            name = itemName,
                            link = itemLink,
                            count = itemCount,
                            bag = bag,
                            slot = slot
                        })
                    end
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

-- Completely rewritten pet profile frame that actually works
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

    -- Food slots in a 2x3 grid
    self.foodSlots = {}
    for i = 1, 6 do
        local slot = FizzureUI:CreateItemSlot(leftPanel, i,
                function(index) self:ClearFoodSlot(index) end,
                function(index) self:HandleFoodDrop(index) end,
                {
                    empty = "Empty Food Slot",
                    instruction = "Drag food here or right-click from list"
                })

        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        slot:SetPoint("TOPLEFT", 60 + col * 60, -50 - row * 60)
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

    -- Scroll frame for food list - positioned properly inside the right panel
    self.foodListScroll = CreateFrame("ScrollFrame", "FoodListScroll", rightPanel, "UIPanelScrollFrameTemplate")
    self.foodListScroll:SetPoint("TOPLEFT", 10, -45)
    self.foodListScroll:SetPoint("BOTTOMRIGHT", -25, 10)  -- Leave room for scrollbar

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
    local refreshBtn = FizzureUI:CreateButton(self.profileFrame.content, "Refresh Foods", 100, 24, function()
        self:ScanAvailableFoods()
        self:UpdatePetProfileFrame()
    end)
    refreshBtn:SetPoint("BOTTOM", -60, 15)

    local clearAllBtn = FizzureUI:CreateButton(self.profileFrame.content, "Clear All", 80, 24, function()
        self:ClearAllFoodSlots()
    end)
    clearAllBtn:SetPoint("BOTTOM", 40, 15)
end

-- Actually working update function
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

    -- Clear and rebuild food list
    local content = self.foodListContent
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    -- Scan for foods
    self:ScanAvailableFoods()

    -- Add foods to list
    local yOffset = -5
    for i, food in ipairs(self.availableFoods) do
        local foodFrame = CreateFrame("Button", "FoodButton" .. i, content)
        foodFrame:SetSize(240, 26)
        foodFrame:SetPoint("TOPLEFT", 5, yOffset)

        -- Background for hover effect
        local bg = foodFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        bg:SetAlpha(0)
        foodFrame:SetHighlightTexture(bg)

        -- Food icon
        local icon = foodFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 2, 0)

        -- Try to get the item icon
        local itemIcon = GetItemIcon(food.name)
        if not itemIcon then
            local _, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(food.name)
            itemIcon = iconTexture
        end
        if itemIcon then
            icon:SetTexture(itemIcon)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_Food_01") -- Fallback icon
        end

        -- Food name and count
        local nameText = foodFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetText(food.name)
        nameText:SetTextColor(1, 1, 1)

        local countText = foodFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        countText:SetPoint("RIGHT", -5, 0)
        countText:SetText("x" .. food.count)
        countText:SetTextColor(0.7, 0.7, 0.7)

        -- Right-click to add to preferred foods
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

        yOffset = yOffset - 28
    end

    -- Update scroll child height
    local totalHeight = math.abs(yOffset) + 10
    self.foodListContent:SetHeight(math.max(totalHeight, 300))
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

            -- Update the slot display immediately
            self.foodSlots[i]:SetItem(foodName)

            -- Update status window
            self:UpdateStatusFrame()

            return
        end
    end

    self.fizzure:ShowNotification("Slots Full", "All preferred food slots are full", "warning", 2)
end

function HunterModule:ClearFoodSlot(index)
    if not self.currentPet then return end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        profile.preferredFoods[index] = nil
        self.fizzure:SetModuleSettings(self.name, self.settings)

        -- Update the slot display immediately
        self.foodSlots[index]:ClearItem()

        -- Update status window
        self:UpdateStatusFrame()
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
                    self.fizzure:SetModuleSettings(self.name, self.settings)

                    -- Update the slot display immediately
                    self.foodSlots[index]:SetItem(itemName, itemLink)

                    -- Update status window
                    self:UpdateStatusFrame()
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
        self.fizzure:SetModuleSettings(self.name, self.settings)

        for i = 1, 6 do
            self.foodSlots[i]:ClearItem()
        end

        self:UpdateStatusFrame()
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
    -- Ensure settings are available
    self:EnsureSettings()

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