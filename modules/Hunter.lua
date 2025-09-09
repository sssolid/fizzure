-- Hunter.lua - Refactored Hunter Pet Management Module using new architecture
local HunterModule = {}

-- REQUIRED: Module manifest
function HunterModule:GetManifest()
    return {
        name = "Hunter Pet Manager",
        version = "3.4",
        author = "Fizzure Team",
        category = "Class-Specific",
        description = "Complete hunter pet management with food tracking and profiles",
        
        classRestriction = "HUNTER",
        minLevel = 10,
        
        hasUI = true,
        hasSettings = true,
        hasKeybindings = true
    }
end

-- REQUIRED: Default settings
function HunterModule:GetDefaultSettings()
    return {
        enabled = true,
        showStatusFrame = true,
        statusFrameMinimized = false,
        framePosition = nil,
        
        -- Pet management
        autoFeed = true,
        lowFoodThreshold = 10,
        feedOnlyWhenUnhappy = false,
        
        -- Notifications
        notifications = {
            feeding = true,
            lowFood = true,
            noFood = true,
            petSummoned = true
        },
        
        -- Keybindings
        keybindings = {
            feedPet = "ALT-F",
            toggleStatus = "ALT-SHIFT-F",
            toggleProfile = "ALT-P"
        },
        
        -- Pet profiles (stored per pet name)
        petProfiles = {}
    }
end

-- Settings validation
function HunterModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
           type(settings.autoFeed) == "boolean" and
           type(settings.lowFoodThreshold) == "number" and
           settings.lowFoodThreshold >= 0
end

-- Core initialization - NO UI CREATION HERE
function HunterModule:OnInitialize()
    -- Validate class
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        self:Log("ERROR", "Hunter module loaded on non-hunter character")
        return false
    end
    
    -- Initialize settings
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Initialize tracking variables
    self.currentPet = nil
    self.availableFoods = {}
    self.lastFoodCheck = 0
    self.lastManualFeed = 0
    self.lastAutoFeed = 0
    
    -- Create event frame
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("UNIT_PET")
    self.eventFrame:RegisterEvent("PET_UI_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.eventFrame:RegisterEvent("PLAYER_PET_CHANGED")
    self.eventFrame:RegisterEvent("PET_STABLE_UPDATE")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    
    -- Initialize pet data
    self:UpdateCurrentPet()
    self:ScanAvailableFoods()
    
    self:Log("INFO", "Hunter module core initialized")
    return true
end

-- UI creation - called after framework UI is ready
function HunterModule:OnUIReady()
    -- Create status frame
    self:CreateStatusFrame()
    
    -- Create pet profile frame
    self:CreatePetProfileFrame()
    
    -- Show status frame if enabled
    if self.settings.showStatusFrame then
        self.statusFrame:Show()
    end
    
    self:Log("INFO", "Hunter module UI ready")
    return true
end

-- Module activation
function HunterModule:OnEnable()
    -- Start update timer
    self.updateTimer = FizzureCommon:NewTicker(5, function()
        self:OnUpdate()
    end)
    
    -- Register keybindings
    self:RegisterKeybindings()
    
    -- Show status frame if configured
    if self.settings.showStatusFrame and self.statusFrame then
        self.statusFrame:Show()
    end
    
    -- Initial status update
    self:UpdateCurrentPet()
    self:UpdateStatusDisplay()
    
    self.ui.ShowNotification("Hunter Module", "Pet management activated", "success", 2)
    self:Log("INFO", "Hunter module enabled")
    
    return true
end

-- Module deactivation
function HunterModule:OnDisable()
    -- Stop timer
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Hide UI
    if self.statusFrame then
        self.statusFrame:Hide()
    end
    
    if self.profileFrame then
        self.profileFrame:Hide()
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    self.ui.ShowNotification("Hunter Module", "Pet management deactivated", "info", 2)
    self:Log("INFO", "Hunter module disabled")
    
    return true
end

-- Settings update handler
function HunterModule:OnSettingsUpdate(newSettings)
    local oldSettings = self.settings
    self.settings = newSettings
    
    -- Handle status frame visibility change
    if oldSettings.showStatusFrame ~= newSettings.showStatusFrame then
        if newSettings.showStatusFrame and self.statusFrame then
            self.statusFrame:Show()
        elseif self.statusFrame then
            self.statusFrame:Hide()
        end
    end
    
    -- Update keybindings if changed
    if oldSettings.keybindings.feedPet ~= newSettings.keybindings.feedPet or
       oldSettings.keybindings.toggleStatus ~= newSettings.keybindings.toggleStatus or
       oldSettings.keybindings.toggleProfile ~= newSettings.keybindings.toggleProfile then
        self:UnregisterKeybindings()
        self:RegisterKeybindings()
    end
    
    -- Update displays
    self:UpdateStatusDisplay()
    
    self:Log("INFO", "Settings updated")
end

-- Cleanup
function HunterModule:OnShutdown()
    -- Stop timers
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Cleanup events
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame = nil
    end
    
    -- Cleanup UI
    if self.statusFrame then
        self.statusFrame:Hide()
        self.statusFrame = nil
    end
    
    if self.profileFrame then
        self.profileFrame:Hide()
        self.profileFrame = nil
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    self:Log("INFO", "Hunter module shutdown complete")
end

-- Create status frame using UI interface
function HunterModule:CreateStatusFrame()
    self.statusFrame = self.ui.CreateStatusFrame("Pet Status", 220, 160)
    
    -- Position frame
    if self.settings.framePosition then
        self.statusFrame:ClearAllPoints()
        self.statusFrame:SetPoint(
            self.settings.framePosition.point,
            UIParent,
            self.settings.framePosition.point,
            self.settings.framePosition.x,
            self.settings.framePosition.y
        )
    end
    
    -- Save position when moved
    self.statusFrame.OnPositionChanged = function()
        local point, _, _, x, y = self.statusFrame:GetPoint()
        self.settings.framePosition = {
            point = point,
            x = x,
            y = y
        }
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Pet name label
    self.petNameLabel = self.ui.CreateLabel(self.statusFrame, "No Pet", "GameFontNormal")
    self.petNameLabel:SetPoint("TOP", 0, -25)
    
    -- Happiness bar
    self.happinessBar = FizzureUI:CreateStatusBar(self.statusFrame, 180, 16, 1, 3, 1, true)
    self.happinessBar:SetPoint("TOP", 0, -50)
    self.happinessBar:SetStatusBarColor(0.8, 0.2, 0.2)
    
    -- Food count label
    self.foodLabel = self.ui.CreateLabel(self.statusFrame, "Food: 0", "GameFontNormalSmall")
    self.foodLabel:SetPoint("TOP", 0, -75)
    
    -- Feed button
    self.feedButton = self.ui.CreateButton(self.statusFrame, "Feed Pet", function()
        self:FeedPet()
    end)
    self.feedButton:SetSize(80, 25)
    self.feedButton:SetPoint("TOP", 0, -100)
    
    -- Profile button
    local profileButton = self.ui.CreateButton(self.statusFrame, "Profile", function()
        self:ToggleProfileFrame()
    end)
    profileButton:SetSize(60, 25)
    profileButton:SetPoint("TOPLEFT", self.feedButton, "TOPRIGHT", 10, 0)
    
    -- Keybind label
    self.keybindLabel = self.ui.CreateLabel(self.statusFrame, "Key: " .. (self.settings.keybindings.feedPet or "None"), "GameFontNormalSmall")
    self.keybindLabel:SetPoint("BOTTOM", 0, 10)
    
    self.statusFrame:Hide()
end

-- Create pet profile frame
function HunterModule:CreatePetProfileFrame()
    self.profileFrame = self.ui.CreateWindow("Pet Profile", 400, 350)
    
    local content = self.profileFrame.content
    
    -- Current pet label
    self.profilePetLabel = self.ui.CreateLabel(content, "No Pet Selected", "GameFontNormalLarge")
    self.profilePetLabel:SetPoint("TOP", 0, -20)
    
    -- Food slots grid
    self.foodSlots = {}
    for i = 1, 6 do
        local slot = self:CreateFoodSlot(content, i)
        self.foodSlots[i] = slot
    end
    
    -- Available food list
    local foodListFrame = FizzureUI:CreateScrollFrame(content, 150, 200, 20, "HunterFoodList")
    foodListFrame:SetPoint("TOPLEFT", 240, -60)
    self.foodListFrame = foodListFrame
    
    -- Clear all button
    local clearButton = self.ui.CreateButton(content, "Clear All", function()
        self:ClearAllFoodSlots()
    end)
    clearButton:SetSize(80, 25)
    clearButton:SetPoint("BOTTOM", 0, 20)
    
    self.profileFrame:Hide()
end

-- Create food slot
function HunterModule:CreateFoodSlot(parent, index)
    local slot = CreateFrame("Button", "HunterFoodSlot" .. index, parent)
    slot:SetSize(50, 50)
    
    -- Background
    slot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    slot:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Item texture
    local texture = slot:CreateTexture(nil, "ARTWORK")
    texture:SetSize(46, 46)
    texture:SetPoint("CENTER")
    texture:Hide()
    slot.texture = texture
    
    -- Count text
    local countText = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.countText = countText
    
    -- Position
    local row = math.floor((index - 1) / 3)
    local col = (index - 1) % 3
    slot:SetPoint("TOPLEFT", 20 + col * 60, -60 - row * 60)
    
    -- Click handlers
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            self:ClearFoodSlot(index)
        end
    end)
    
    -- Drag and drop
    slot:SetScript("OnReceiveDrag", function()
        self:HandleFoodDrop(index)
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
            GameTooltip:AddLine("Drag food here", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Slot methods
    function slot:SetItem(itemName, itemLink)
        self.itemName = itemName
        self.itemLink = itemLink
        
        if itemName then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemName)
            if icon then
                self.texture:SetTexture(icon)
                self.texture:Show()
            end
            
            local count = FizzureCommon:GetItemCount(itemName)
            self.countText:SetText(count > 0 and count or "")
        else
            self.texture:Hide()
            self.countText:SetText("")
        end
    end
    
    function slot:ClearItem()
        self.itemName = nil
        self.itemLink = nil
        self.texture:Hide()
        self.countText:SetText("")
    end
    
    return slot
end

-- Event handling
function HunterModule:OnEvent(event, ...)
    if event == "UNIT_PET" or event == "PLAYER_PET_CHANGED" then
        self:UpdateCurrentPet()
        self:UpdateStatusDisplay()
    elseif event == "PET_UI_UPDATE" then
        self:UpdateStatusDisplay()
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        local currentTime = GetTime()
        if currentTime - self.lastFoodCheck > 2 then
            self.lastFoodCheck = currentTime
            self:ScanAvailableFoods()
            self:UpdateStatusDisplay()
        end
    elseif event == "PET_STABLE_UPDATE" then
        self:UpdateCurrentPet()
    end
end

-- Update loop
function HunterModule:OnUpdate()
    if not UnitExists("pet") then
        if self.currentPet then
            self.currentPet = nil
            self:UpdateStatusDisplay()
        end
        return
    end
    
    -- Auto-feed logic
    if self.settings.autoFeed then
        self:CheckAutoFeed()
    end
    
    -- Update display
    self:UpdateStatusDisplay()
end

-- Update current pet info
function HunterModule:UpdateCurrentPet()
    if not UnitExists("pet") then
        if self.currentPet then
            self.currentPet = nil
            if self.settings.notifications.petSummoned then
                self.ui.ShowNotification("Pet Dismissed", "Your pet has been dismissed", "info", 2)
            end
        end
        return
    end
    
    local petName = UnitName("pet")
    local petFamily = UnitCreatureFamily("pet") or "Unknown"
    local petLevel = UnitLevel("pet")
    
    if not self.currentPet or self.currentPet.name ~= petName then
        self.currentPet = {
            name = petName,
            family = petFamily,
            level = petLevel
        }
        
        -- Create profile if doesn't exist
        if not self.settings.petProfiles[petName] then
            self.settings.petProfiles[petName] = {
                family = petFamily,
                preferredFoods = {},
                lastFed = 0
            }
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end
        
        if self.settings.notifications.petSummoned then
            self.ui.ShowNotification("Pet Active", petName .. " is ready", "success", 2)
        end
        
        self:Log("INFO", "Pet updated: " .. petName .. " (" .. petFamily .. ")")
    end
end

-- Scan available foods
function HunterModule:ScanAvailableFoods()
    self.availableFoods = {}
    
    local petFoodTypes = {
        ["Beast"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit"},
        ["Bird"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit"},
        ["Boar"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Carrion Bird"] = {"Meat", "Fish"},
        ["Cat"] = {"Meat", "Fish"},
        ["Bear"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Crab"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Crocolisk"] = {"Meat", "Fish"},
        ["Gorilla"] = {"Fruit"},
        ["Raptor"] = {"Meat", "Fish"},
        ["Scorpid"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Spider"] = {"Meat", "Fish"},
        ["Tallstrider"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Turtle"] = {"Meat", "Fish", "Bread", "Cheese", "Fruit", "Fungus"},
        ["Wind Serpent"] = {"Meat", "Fish"},
        ["Wolf"] = {"Meat", "Fish"}
    }
    
    if not self.currentPet then return end
    
    local validTypes = petFoodTypes[self.currentPet.family] or {"Meat", "Fish"}
    
    -- Scan bags for food
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemName = GetItemInfo(itemLink)
                local count = select(2, GetContainerItemInfo(bag, slot)) or 0
                
                if itemName and count > 0 then
                    -- Check if item is food for this pet family
                    local tooltip = CreateFrame("GameTooltip", "HunterFoodScanTooltip", nil, "GameTooltipTemplate")
                    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                    tooltip:SetBagItem(bag, slot)
                    
                    local isFood = false
                    for i = 1, tooltip:NumLines() do
                        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
                        if line then
                            local text = line:GetText() or ""
                            for _, foodType in ipairs(validTypes) do
                                if string.find(text, foodType) then
                                    isFood = true
                                    break
                                end
                            end
                        end
                        if isFood then break end
                    end
                    
                    if isFood then
                        self.availableFoods[itemName] = count
                    end
                end
            end
        end
    end
end

-- Update status display
function HunterModule:UpdateStatusDisplay()
    if not self.statusFrame then return end
    
    if self.currentPet then
        -- Update pet name
        self.petNameLabel:SetText(self.currentPet.name)
        self.petNameLabel:SetTextColor(1, 1, 1)
        
        -- Update happiness
        if UnitExists("pet") then
            local happiness = GetPetHappiness()
            if happiness then
                self.happinessBar:SetValue(happiness)
                
                local colors = {
                    {1, 0.3, 0.3},  -- Unhappy (1)
                    {1, 1, 0.3},    -- Content (2)
                    {0.3, 1, 0.3}   -- Happy (3)
                }
                local texts = {"Unhappy", "Content", "Happy"}
                
                local color = colors[happiness] or colors[1]
                self.happinessBar:SetStatusBarColor(color[1], color[2], color[3])
                self.happinessBar:SetText(texts[happiness] or "Unknown")
            end
        end
        
        -- Update food count
        local totalFood = 0
        local profile = self.settings.petProfiles[self.currentPet.name]
        
        if profile and profile.preferredFoods then
            for i = 1, 6 do
                local foodName = profile.preferredFoods[i]
                if foodName then
                    totalFood = totalFood + (self.availableFoods[foodName] or 0)
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
        -- No pet
        self.petNameLabel:SetText("No Pet")
        self.petNameLabel:SetTextColor(0.7, 0.7, 0.7)
        self.happinessBar:SetValue(1)
        self.happinessBar:SetStatusBarColor(0.5, 0.5, 0.5)
        self.happinessBar:SetText("N/A")
        self.foodLabel:SetText("Food: N/A")
        self.foodLabel:SetTextColor(0.7, 0.7, 0.7)
        self.feedButton:Disable()
    end
end

-- Auto-feed logic
function HunterModule:CheckAutoFeed()
    if not self.currentPet or not UnitExists("pet") then return end
    
    local currentTime = GetTime()
    if currentTime - self.lastAutoFeed < 30 then return end -- Prevent spam
    
    local happiness = GetPetHappiness()
    if self.settings.feedOnlyWhenUnhappy and happiness and happiness >= 2 then
        return
    end
    
    if happiness and happiness < 3 then
        if self:FeedPet(true) then
            self.lastAutoFeed = currentTime
        end
    end
end

-- Feed pet method
function HunterModule:FeedPet(isAuto)
    if not self.currentPet or not UnitExists("pet") then return false end
    
    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile or not profile.preferredFoods then return false end
    
    -- Find first available food
    for i = 1, 6 do
        local foodName = profile.preferredFoods[i]
        if foodName and self.availableFoods[foodName] and self.availableFoods[foodName] > 0 then
            UseItemByName(foodName)
            
            local feedType = isAuto and "Auto-fed" or "Fed"
            if not isAuto or self.settings.notifications.feeding then
                self.ui.ShowNotification(feedType, "Used " .. foodName, "success", 2)
            end
            
            self:Log("INFO", feedType .. " pet with " .. foodName)
            return true
        end
    end
    
    -- No food available
    if self.settings.notifications.noFood then
        self.ui.ShowNotification("No Food", "No preferred food available", "warning", 3)
    end
    
    return false
end

-- Food slot management
function HunterModule:HandleFoodDrop(index)
    local cursorType, itemID, itemLink = GetCursorInfo()
    if cursorType == "item" and itemLink then
        local itemName = GetItemInfo(itemLink)
        if itemName and self.currentPet then
            local profile = self.settings.petProfiles[self.currentPet.name]
            if profile then
                if not profile.preferredFoods then
                    profile.preferredFoods = {}
                end
                profile.preferredFoods[index] = itemName
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                
                self.foodSlots[index]:SetItem(itemName, itemLink)
                self.ui.ShowNotification("Food Added", itemName .. " added to slot " .. index, "success", 2)
            end
            ClearCursor()
        end
    end
end

function HunterModule:ClearFoodSlot(index)
    if not self.currentPet then return end
    
    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        local removedFood = profile.preferredFoods[index]
        profile.preferredFoods[index] = nil
        self.Fizzure:SetModuleSettings(self.name, self.settings)
        
        self.foodSlots[index]:ClearItem()
        
        if removedFood then
            self.ui.ShowNotification("Food Removed", removedFood .. " removed", "info", 2)
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
        
        self.ui.ShowNotification("Cleared", "All preferred foods cleared", "info", 2)
    end
end

function HunterModule:ToggleProfileFrame()
    if not self.profileFrame then return end
    
    if self.profileFrame:IsShown() then
        self.profileFrame:Hide()
    else
        self:UpdateProfileFrame()
        self.profileFrame:Show()
    end
end

function HunterModule:UpdateProfileFrame()
    if not self.profileFrame or not self.currentPet then return end
    
    -- Update pet name
    self.profilePetLabel:SetText(self.currentPet.name .. " (" .. self.currentPet.family .. ")")
    
    -- Update food slots
    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        for i = 1, 6 do
            local foodName = profile.preferredFoods[i]
            if foodName then
                self.foodSlots[i]:SetItem(foodName)
            else
                self.foodSlots[i]:ClearItem()
            end
        end
    end
end

-- Keybinding management
function HunterModule:RegisterKeybindings()
    if not _G.FizzureSecure then return end
    
    -- Feed pet binding
    FizzureSecure:CreateSecureButton(
        "HunterFeedPetButton",
        "/script " .. self.name .. ":FeedPet()",
        self.settings.keybindings.feedPet,
        "Feed Pet"
    )
    
    -- Toggle status binding
    FizzureSecure:CreateSecureButton(
        "HunterToggleStatusButton", 
        "/script " .. self.name .. ":ToggleStatusFrame()",
        self.settings.keybindings.toggleStatus,
        "Toggle Pet Status"
    )
    
    -- Toggle profile binding
    FizzureSecure:CreateSecureButton(
        "HunterToggleProfileButton",
        "/script " .. self.name .. ":ToggleProfileFrame()",
        self.settings.keybindings.toggleProfile,
        "Toggle Pet Profile"
    )
end

function HunterModule:UnregisterKeybindings()
    if not _G.FizzureSecure then return end
    
    if self.settings.keybindings.feedPet then
        FizzureSecure:ClearKeyBinding(self.settings.keybindings.feedPet)
    end
    
    if self.settings.keybindings.toggleStatus then
        FizzureSecure:ClearKeyBinding(self.settings.keybindings.toggleStatus)
    end
    
    if self.settings.keybindings.toggleProfile then
        FizzureSecure:ClearKeyBinding(self.settings.keybindings.toggleProfile)
    end
end

function HunterModule:ToggleStatusFrame()
    if not self.statusFrame then return end
    
    if self.statusFrame:IsShown() then
        self.statusFrame:Hide()
        self.settings.showStatusFrame = false
    else
        self.statusFrame:Show()
        self.settings.showStatusFrame = true
    end
    
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

-- Utility methods
function HunterModule:Log(level, message)
    if self.Fizzure and self.Fizzure.Log then
        self.Fizzure:Log(level, "[Hunter] " .. message)
    end
end

function HunterModule:GetQuickStatus()
    if not self.currentPet then
        return "No Pet"
    end
    
    local happiness = GetPetHappiness()
    local happinessText = happiness and ({"Unhappy", "Content", "Happy"})[happiness] or "Unknown"
    
    local totalFood = 0
    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        for i = 1, 6 do
            local foodName = profile.preferredFoods[i]
            if foodName then
                totalFood = totalFood + (self.availableFoods[foodName] or 0)
            end
        end
    end
    
    return string.format("%s: %s, Food: %d", self.currentPet.name, happinessText, totalFood)
end

-- Register module with framework
if Fizzure then
    Fizzure:RegisterModule(HunterModule)
else
    -- Queue for registration if framework not ready
    if not _G.FizzureModuleQueue then
        _G.FizzureModuleQueue = {}
    end
    table.insert(_G.FizzureModuleQueue, HunterModule)
end