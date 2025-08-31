-- HunterModule.lua - Hunter Pet Management Module (3.3.5 FIXED VERSION)
-- Fixed core feeding functionality with comprehensive logging

local HunterModule = {}

-- Module configuration
HunterModule.name = "Hunter Pet Manager"
HunterModule.version = "3.1"
HunterModule.author = "Fizzure"

local FEED_COOLDOWN = 10  -- seconds between manual feeds (visual cooldown only)

-- Get default settings for the module
function HunterModule:GetDefaultSettings()
    return {
        enabled = true,
        checkInterval = 10, -- Only for status updates now
        showFoodStatus = true,
        lowFoodThreshold = 10,
        statusFrameMinimized = false,
        petProfiles = {},
        keybindings = {
            feedPet = "ALT-F", -- Default keybinding for feeding
            toggleStatus = "ALT-SHIFT-F",
            openProfiles = ""
        },
        notifications = {
            feeding = true,
            lowFood = true,
            noFood = true,
            manualFeedSuccess = true
        }
    }
end

-- Validate settings
function HunterModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.checkInterval) == "number" and
            settings.checkInterval > 0 and
            type(settings.showFoodStatus) == "boolean"
end

-- Initialize module
function HunterModule:Initialize()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        return false
    end

    -- Ensure core reference exists
    if not self.fizzure then
        print("|cffff0000Hunter Module Error:|r Core reference missing")
        return false
    end

    -- Ensure SecureActions is available
    if not FizzureSecure then
        print("|cffff0000Hunter Module Error:|r SecureActions not available")
        return false
    end

    -- Get settings from core
    self.settings = self.fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Get debug API wrappers
    self.debugAPI = self.fizzure:GetDebugAPI()

    -- Create update frame for status updates only (no automatic feeding)
    if not self.updateFrame then
        self.updateFrame = CreateFrame("Frame")
        self.updateFrame:SetScript("OnUpdate", function(self, elapsed)
            HunterModule:OnUpdate(elapsed)
        end)
    end

    -- Register events (FIXED: Added PET_HAPPINESS_UPDATE for feeding detection)
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(self, event, ...)
            HunterModule:OnEvent(event, ...)
        end)
    end

    self.eventFrame:RegisterEvent("UNIT_PET")
    self.eventFrame:RegisterEvent("PET_UI_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_PET_CHANGED")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")  -- Detect when Feed Pet is cast
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")  -- Detect successful casts

    -- Initialize variables
    self.lastCheck = 0
    self.currentPet = nil
    self.lastFoodCheck = 0
    self.lastManualFeed = 0  -- Track manual feeds for cooldown display
    self.availableFoods = {}

    -- Create secure action buttons for pet feeding
    self:CreateSecureButtons()

    -- Create status frame
    self:CreateStatusFrame()
    self:CreatePetProfileFrame()

    -- Show/hide status frame based on settings
    if self.settings.showFoodStatus and self.statusFrame then
        if self.settings.statusFrameMinimized then
            self:MinimizeStatusFrame()
        else
            self:MaximizeStatusFrame()
        end
        self.statusFrame:Show()
    elseif self.statusFrame then
        self.statusFrame:Hide()
    end

    -- Check for existing pet on initialization
    self:UpdateCurrentPet()
    self:ScanAvailableFoods()

    -- Debug logging
    self.fizzure:LogDebug("INFO", "Hunter Module Initialized (Manual Feed Mode)", "Hunter")

    print("|cff00ff00Hunter Module|r Initialized - Use " .. (self.settings.keybindings.feedPet or "keybinding") .. " to feed pet")
    return true
end

-- FIXED: Simple, working food scan based on original UIFramework logic
function HunterModule:ScanBagsForFood()
    local foodItems = {}

    self.fizzure:LogDebug("DEBUG", "Starting food scan", "Hunter")

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
                local _, count = GetContainerItemInfo(bag, slot)

                self.fizzure:LogDebug("DEBUG", "Found: " .. (name or "nil") .. " | Type: " .. (itemType or "nil") .. " | SubType: " .. (itemSubType or "nil"), "Hunter")

                -- Use the WORKING original logic - check if it's food (any consumable that restores health)
                if itemType and (itemType == "Consumable" or itemType == ITEM_CLASS_CONSUMABLE) then
                    if itemSubType and (itemSubType == "Food & Drink" or itemSubType == ITEM_SUBCLASS_FOOD_DRINK or
                            itemSubType == "Food" or itemSubType == "Consumable") then

                        local id = tonumber(string.match(link, "item:(%d+)"))

                        table.insert(foodItems, {
                            name = name,
                            link = link,
                            id = id,
                            count = count or 0,
                            bag = bag,
                            slot = slot
                        })

                        self.fizzure:LogDebug("INFO", "FOOD ADDED: " .. name .. " x" .. (count or 0), "Hunter")
                    end
                end
            end
        end
    end

    self.fizzure:LogDebug("INFO", "Food scan complete - " .. #foodItems .. " items found", "Hunter")
    return foodItems
end

-- FIXED: Simplified food finding that actually works
function HunterModule:FindBestFood()
    self.fizzure:LogDebug("INFO", "=== FindBestFood: Starting ===", "Hunter")

    if not self.currentPet then
        self.fizzure:LogDebug("ERROR", "FindBestFood: No current pet", "Hunter")
        return nil
    end

    -- FIRST: Check if we have preferred foods set and available
    local profile = self.settings.petProfiles[self.currentPet.name]
    if profile and profile.preferredFoods then
        self.fizzure:LogDebug("INFO", "FindBestFood: Checking preferred foods for " .. self.currentPet.name, "Hunter")

        for i = 1, 6 do
            local preferredName = profile.preferredFoods[i]
            if preferredName and preferredName ~= "" then
                local count = GetItemCount(preferredName)
                self.fizzure:LogDebug("DEBUG", "FindBestFood: Slot " .. i .. " - " .. preferredName .. " has " .. count .. " available", "Hunter")

                if count > 0 then
                    -- Found preferred food with stock - return it
                    local food = {
                        name = preferredName,
                        count = count,
                        link = nil -- Don't need link for UseItemByName
                    }
                    self.fizzure:LogDebug("INFO", "FindBestFood: SUCCESS - Using preferred food: " .. preferredName .. " x" .. count, "Hunter")
                    return food
                end
            end
        end

        self.fizzure:LogDebug("WARN", "FindBestFood: No preferred foods available, checking all bags", "Hunter")
    end

    -- FALLBACK: Scan bags for any food
    local foodItems = self:ScanBagsForFood()

    if #foodItems > 0 then
        local fallback = foodItems[1]
        self.fizzure:LogDebug("INFO", "FindBestFood: SUCCESS - Using fallback food: " .. fallback.name .. " x" .. fallback.count, "Hunter")
        return fallback
    end

    self.fizzure:LogDebug("ERROR", "FindBestFood: FAILED - No food found anywhere", "Hunter")
    return nil
end

-- Create secure action buttons for pet feeding
function HunterModule:CreateSecureButtons()
    if not FizzureSecure then
        self.fizzure:LogDebug("ERROR", "SecureActions not available for button creation", "Hunter")
        return
    end

    self.fizzure:LogDebug("INFO", "CreateSecureButtons: Secure action buttons will be created when needed", "Hunter")

    -- Set up the toggle-status keybinding (non-secure) if configured
    if self.settings.keybindings.toggleStatus and self.settings.keybindings.toggleStatus ~= "" then
        local toggleButton = CreateFrame("Button", "FizzureHunterToggleStatus", UIParent)
        toggleButton:SetSize(1, 1)
        toggleButton:Hide()
        toggleButton:SetScript("OnClick", function()
            HunterModule:ToggleStatusFrame()
        end)
        SetBindingClick(self.settings.keybindings.toggleStatus, "FizzureHunterToggleStatus")
        self.fizzure:LogDebug("INFO", "CreateSecureButtons: Toggle status keybinding set to " .. self.settings.keybindings.toggleStatus, "Hunter")
    end
end

-- Shutdown module
function HunterModule:Shutdown()
    if self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
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

    -- Clear secure action bindings
    if FizzureSecure then
        FizzureSecure:ClearModuleBindings(self.name)
    end

    self.fizzure:LogDebug("INFO", "Hunter Module Shutdown", "Hunter")
end

-- Update function (status updates only, no automatic feeding)
function HunterModule:OnUpdate(elapsed)
    if not self.settings.enabled then
        return
    end

    self.lastCheck = self.lastCheck + elapsed

    if self.lastCheck >= self.settings.checkInterval then
        self.lastCheck = 0
        self:UpdateStatusFrame()
    end

    -- Check food supply periodically
    self.lastFoodCheck = self.lastFoodCheck + elapsed
    if self.lastFoodCheck >= 30 then
        self.lastFoodCheck = 0
        self:CheckFoodSupply()
        self:ScanAvailableFoods()
        self:UpdateFeedButtonMacro()  -- Update the secure button's macro
    end
end

-- CRITICAL FIX: Update secure feed button macro with actual food name for 3.3.5
function HunterModule:UpdateFeedButtonMacro()
    if not self.feedButton then
        self.fizzure:LogDebug("DEBUG", "UpdateFeedButtonMacro: No feed button exists", "Hunter")
        return
    end

    if InCombatLockdown() then
        self.fizzure:LogDebug("WARN", "UpdateFeedButtonMacro: In combat, deferring update", "Hunter")
        self._pendingFeedMacro = true
        return
    end

    self.fizzure:LogDebug("INFO", "UpdateFeedButtonMacro: Updating macro with current best food", "Hunter")

    -- Get the current best food
    local food = self:FindBestFood()
    local macroText

    if food then
        -- Create 3.3.5 compatible macro with specific food name
        macroText = string.format([[
/cast Feed Pet
/use %s
]], food.name)

        self.fizzure:LogDebug("INFO", "UpdateFeedButtonMacro: Created macro for " .. food.name, "Hunter")
    else
        -- No food available
        macroText = "/cast Feed Pet"

        self.fizzure:LogDebug("WARN", "UpdateFeedButtonMacro: No food available, created fallback macro", "Hunter")
    end

    print(macroText)

    -- Update the secure button
    self.feedButton:SetAttribute("macrotext", macroText)
    self.fizzure:LogDebug("INFO", "UpdateFeedButtonMacro: Macro updated successfully", "Hunter")

    -- Log the actual macro for debugging
    self.fizzure:LogDebug("DEBUG", "UpdateFeedButtonMacro: Macro text set to: " .. macroText, "Hunter")
end

-- Called when manual feed is triggered (from secure button macro)
function HunterModule:OnManualFeed()
    self.fizzure:LogDebug("INFO", "=== OnManualFeed: Manual feed triggered ===", "Hunter")

    self.lastManualFeed = GetTime()

    if not self.currentPet then
        self.fizzure:LogDebug("ERROR", "OnManualFeed: No current pet active", "Hunter")
        return
    end

    local foodUsed = self:FindBestFood()
    if foodUsed then
        self.fizzure:LogDebug("INFO", "OnManualFeed: Successfully selected food: " .. foodUsed.name, "Hunter")

        if self.settings.notifications.manualFeedSuccess then
            self.fizzure:ShowNotification("Pet Fed",
                    self.currentPet.name .. " fed with " .. foodUsed.name, "success", 3)
        end

        -- Update profile last fed time
        local profile = self.settings.petProfiles[self.currentPet.name]
        if profile then
            profile.lastFed = GetTime()
            self.fizzure:SetModuleSettings(self.name, self.settings)
            self.fizzure:LogDebug("DEBUG", "OnManualFeed: Updated last fed time for " .. self.currentPet.name, "Hunter")
        end
    else
        self.fizzure:LogDebug("ERROR", "OnManualFeed: Failed to find suitable food", "Hunter")

        if self.settings.notifications.noFood then
            self.fizzure:ShowNotification("No Food", "No suitable food found for " .. self.currentPet.name, "warning", 3)
        end
    end

    self:UpdateStatusFrame()
    self.fizzure:LogDebug("INFO", "=== OnManualFeed: Process complete ===", "Hunter")
end

-- Toggle status frame visibility
function HunterModule:ToggleStatusFrame()
    if not self.statusFrame then
        self:CreateStatusFrame()
    end

    if self.statusFrame:IsShown() then
        self.statusFrame:Hide()
        self.settings.showFoodStatus = false
    else
        self.statusFrame:Show()
        self.settings.showFoodStatus = true
        if self.settings.statusFrameMinimized then
            self:MinimizeStatusFrame()
        else
            self:MaximizeStatusFrame()
        end
    end

    self.fizzure:SetModuleSettings(self.name, self.settings)
end

-- Event handler
function HunterModule:OnEvent(event, ...)
    self.fizzure:LogDebug("DEBUG", "OnEvent: Received " .. event, "Hunter")

    if event == "UNIT_PET" or event == "PLAYER_PET_CHANGED" then
        self:UpdateCurrentPet()
    elseif event == "PET_UI_UPDATE" then
        self:UpdateStatusFrame()
    elseif event == "BAG_UPDATE" then
        self.fizzure:LogDebug("DEBUG", "OnEvent: BAG_UPDATE - refreshing food data", "Hunter")
        self:CheckFoodSupply()
        self:ScanAvailableFoods()
        self:UpdateStatusFrame()
        self:UpdateFeedButtonMacro()
        if self.UpdatePetProfileFrame then
            self:UpdatePetProfileFrame()
        end
    end
end

-- Update current pet information
function HunterModule:UpdateCurrentPet()
    self.fizzure:LogDebug("DEBUG", "UpdateCurrentPet: Checking for pet", "Hunter")

    if not UnitExists("pet") then
        self.fizzure:LogDebug("INFO", "UpdateCurrentPet: No pet exists", "Hunter")
        self.currentPet = nil
        if self.UpdatePetProfileFrame then
            self:UpdatePetProfileFrame()
        end
        return
    end

    local name = UnitName("pet")
    local fam = UnitCreatureFamily("pet")
    local level = UnitLevel("pet") or 1

    if not name then
        self.fizzure:LogDebug("DEBUG", "UpdateCurrentPet: Pet name not available yet, retrying in 0.1s", "Hunter")
        -- Retry after a brief delay
        local retryTimer = CreateFrame("Frame")
        local elapsed = 0
        retryTimer:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed > 0.1 then
                self:SetScript("OnUpdate", nil)
                HunterModule:UpdateCurrentPet()
            end
        end)
        return
    end

    self.currentPet = { name = name, family = fam or "Unknown", level = level }
    self.fizzure:LogDebug("INFO", "UpdateCurrentPet: Pet updated - " .. name .. " (" .. (fam or "Unknown") .. ", Level " .. level .. ")", "Hunter")

    -- Ensure profile exists
    if not self.settings.petProfiles[name] then
        self.fizzure:LogDebug("INFO", "UpdateCurrentPet: Creating new profile for " .. name, "Hunter")

        self.settings.petProfiles[name] = {
            family = fam or "Unknown",
            preferredFoods = {},
            lastFed = 0,
        }
        self.fizzure:SetModuleSettings(self.name, self.settings)

        -- Notify user to create profile
        if self.settings.notifications.feeding then
            self.fizzure:ShowNotification("New Pet Profile",
                    "Created new profile for " .. name .. ". Configure preferred foods in the Pet Profiles window.",
                    "info", 8)
        end
    end

    if self.UpdatePetProfileFrame then
        self:UpdatePetProfileFrame()
    end
end

-- Scan for available food in bags (wrapper that uses our own function)
function HunterModule:ScanAvailableFoods()
    self.availableFoods = self:ScanBagsForFood()
    self.fizzure:LogDebug("INFO", "ScanAvailableFoods: Updated available foods - " .. #self.availableFoods .. " items", "Hunter")
end

-- Check food supply and warn if low
function HunterModule:CheckFoodSupply()
    if not self.currentPet then
        return
    end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then
        return
    end

    local totalFood = 0
    if profile.preferredFoods then
        for _, foodName in ipairs(profile.preferredFoods) do
            if foodName and foodName ~= "" then
                local count = GetItemCount(foodName)
                totalFood = totalFood + count
            end
        end
    end

    self.fizzure:LogDebug("DEBUG", "CheckFoodSupply: Total preferred food: " .. totalFood .. ", threshold: " .. self.settings.lowFoodThreshold, "Hunter")

    if totalFood <= self.settings.lowFoodThreshold and totalFood > 0 then
        if self.settings.notifications.lowFood then
            self.fizzure:ShowNotification("Low Food Warning",
                    "Running low on food for " .. self.currentPet.name .. " (" .. totalFood .. " remaining)",
                    "warning", 5)
        end
    end
end

-- Ensure the visible secure feed button exists and is attached to the frame
function HunterModule:EnsureFeedButton(maxFrame)
    if not maxFrame then
        self.fizzure:LogDebug("ERROR", "EnsureFeedButton: No maxFrame provided", "Hunter")
        return false
    end

    -- If already attached to the frame, we're good
    if maxFrame.feedBtn and maxFrame.feedBtn.GetName and maxFrame.feedBtn:GetName() then
        -- Remember for module-level references too
        self.feedButton = self.feedButton or maxFrame.feedBtn
        self.fizzure:LogDebug("DEBUG", "EnsureFeedButton: Feed button already exists on frame", "Hunter")
        return true
    end

    -- If the module already has the button, attach it to this frame now
    if self.feedButton and self.feedButton.GetName and self.feedButton:GetName() then
        maxFrame.feedBtn = self.feedButton
        self.fizzure:LogDebug("DEBUG", "EnsureFeedButton: Attached existing module feed button to frame", "Hunter")
        return true
    end

    -- Don't try to create secure UI in combat; defer until safe
    if InCombatLockdown and InCombatLockdown() then
        if not self._deferCreateFeedBtn then
            self._deferCreateFeedBtn = true
            self.fizzure:LogDebug("INFO", "EnsureFeedButton: In combat, deferring button creation", "Hunter")
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                f:UnregisterAllEvents()
                self._deferCreateFeedBtn = nil
                self:EnsureFeedButton(maxFrame)  -- try again out of combat
            end)
        end
        return false
    end

    -- FIXED: Create simple secure button for 3.3.5 compatibility
    self.fizzure:LogDebug("INFO", "EnsureFeedButton: Creating simple secure button for 3.3.5", "Hunter")

    local btn = CreateFrame("Button", "FizzureHunterFeedButton", maxFrame, "SecureActionButtonTemplate")
    btn:SetSize(120, 20)
    btn:SetPoint("TOP", 0, -85)

    -- FIXED: Proper button text handling
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText("Feed Pet")
    btn.text = btnText

    -- Style the button
    btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")

    -- Set secure attributes for 3.3.5
    btn:SetAttribute("type", "macro")

    -- Initial macro text (will be updated by UpdateFeedButtonMacro)
    local initialMacro = "/cast Feed Pet"
    btn:SetAttribute("macrotext", initialMacro)

    -- Store references
    maxFrame.feedBtn = btn
    self.feedButton = btn

    self.fizzure:LogDebug("INFO", "EnsureFeedButton: Secure button created: " .. btn:GetName(), "Hunter")

    -- Update macro immediately
    self:UpdateFeedButtonMacro()

    return true
end

-- Create enhanced status frame with minimization support
function HunterModule:CreateStatusFrame()
    if self.statusFrame then
        return
    end

    self.statusFrame = FizzureUI:CreateStatusFrame("HunterModuleStatus", "Hunter Pet Status", 200, 140)
    local frame = self.statusFrame

    -- Create minimized view
    self:CreateMinimizedView(frame)

    -- Create maximized view (existing content)
    self:CreateMaximizedView(frame)

    -- Set initial state
    if self.settings.statusFrameMinimized then
        self:MinimizeStatusFrame()
    else
        self:MaximizeStatusFrame()
    end
end

-- Create improved minimized view with better visibility
function HunterModule:CreateMinimizedView(frame)
    local miniFrame = CreateFrame("Frame", nil, frame)
    miniFrame:SetSize(160, 60)  -- Larger for better visibility
    miniFrame:SetPoint("CENTER")

    -- Enhanced backdrop with better contrast
    miniFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    miniFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)  -- Nearly black for contrast
    miniFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    frame.miniFrame = miniFrame

    -- LEFT SIDE: Food display
    local foodSection = CreateFrame("Frame", nil, miniFrame)
    -- tighten sections
    foodSection:ClearAllPoints()
    foodSection:SetPoint("LEFT", 6, 0)
    foodSection:SetSize(64, 50)

    -- Food icon (larger and more prominent)
    local foodIcon = foodSection:CreateTexture(nil, "ARTWORK")
    foodIcon:SetSize(36, 36)
    foodIcon:SetPoint("TOPLEFT", 2, -2)
    foodIcon:SetTexture("Interface\\Icons\\INV_Misc_Food_19")
    miniFrame.foodIcon = foodIcon

    -- Food count with better styling
    local foodCount = foodSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    foodCount:SetPoint("BOTTOMRIGHT", foodIcon, "BOTTOMRIGHT", 2, -2)
    foodCount:SetText("0")
    foodCount:SetTextColor(1, 1, 0.2)  -- Bright yellow
    -- Add text outline for better readability
    foodCount:SetShadowOffset(1, -1)
    foodCount:SetShadowColor(0, 0, 0, 1)
    miniFrame.foodCount = foodCount

    -- Food label
    local foodLabel = foodSection:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    foodLabel:SetPoint("BOTTOM", foodIcon, "BOTTOM", 0, -12)
    foodLabel:SetText("Food")
    foodLabel:SetTextColor(0.8, 0.8, 0.8)
    miniFrame.foodLabel = foodLabel

    -- RIGHT SIDE: Happiness display
    local happinessSection = CreateFrame("Frame", nil, miniFrame)
    happinessSection:ClearAllPoints()
    happinessSection:SetPoint("LEFT", foodSection, "RIGHT", 6, 0)
    happinessSection:SetSize(64, 50)

    -- Vertical happiness bar (much more visible)
    local miniHappiness = CreateFrame("StatusBar", nil, happinessSection)
    miniHappiness:SetSize(16, 40)  -- Tall and narrow vertical bar
    miniHappiness:SetPoint("CENTER", -10, 2)
    miniHappiness:SetOrientation("VERTICAL")
    miniHappiness:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    miniHappiness:SetMinMaxValues(1, 3)
    miniHappiness:SetValue(3)

    -- Happiness bar backdrop for contrast
    miniHappiness:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    miniHappiness:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    miniHappiness:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    miniFrame.miniHappiness = miniHappiness

    -- Happiness icon next to the bar
    local happinessIcon = happinessSection:CreateTexture(nil, "ARTWORK")
    happinessIcon:SetSize(24, 24)
    happinessIcon:SetPoint("LEFT", miniHappiness, "RIGHT", 4, 0)
    happinessIcon:SetTexture("Interface\\Icons\\Spell_Holy_Blessedlife")  -- Smiley face icon
    miniFrame.happinessIcon = happinessIcon

    -- Happiness text label
    local happinessLabel = happinessSection:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    happinessLabel:SetPoint("BOTTOM", miniHappiness, "BOTTOM", 10, -12)
    happinessLabel:SetText("Happy")
    happinessLabel:SetTextColor(0.3, 1, 0.3)
    miniFrame.happinessLabel = happinessLabel

    -- Manual feed cooldown indicator (small, unobtrusive)
    local cooldownIcon = miniFrame:CreateTexture(nil, "OVERLAY")
    cooldownIcon:SetSize(12, 12)
    cooldownIcon:SetPoint("TOPRIGHT", -4, -4)
    cooldownIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
    cooldownIcon:SetAlpha(0.7)
    miniFrame.cooldownIcon = cooldownIcon

    -- Click handlers for mini frame
    local clickFrame = CreateFrame("Button", nil, miniFrame)
    clickFrame:SetAllPoints(miniFrame)
    clickFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    clickFrame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- TODO: Feed the pet
        elseif button == "RightButton" then
            -- Show context menu
            HunterModule:ShowMiniContextMenu(clickFrame)
        end
    end)

    -- Enhanced tooltip
    miniFrame:EnableMouse(true)
    miniFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Hunter Pet Status", 1, 1, 1)

        if HunterModule.currentPet then
            GameTooltip:AddLine("Pet: " .. HunterModule.currentPet.name, 1, 1, 0.5)
            local happiness = GetPetHappiness()
            local happinessText = { "Unhappy", "Content", "Happy" }
            GameTooltip:AddLine("Happiness: " .. (happinessText[happiness] or "Unknown"),
                    happiness == 3 and 0.3 or (happiness == 2 and 1 or 1),
                    happiness == 3 and 1 or (happiness == 2 and 1 or 0.3),
                    happiness == 3 and 0.3 or (happiness == 2 and 0.3 or 0.3))
        else
            GameTooltip:AddLine("No pet active", 0.7, 0.7, 0.7)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: Pet Profiles", 0.8, 0.8, 1)
        GameTooltip:AddLine("Right-click: Options", 0.8, 0.8, 1)
        GameTooltip:Show()
    end)

    miniFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    miniFrame.clickFrame = clickFrame
end

-- Create maximized view (updated for manual feeding system)
function HunterModule:CreateMaximizedView(frame)
    local maxFrame = CreateFrame("Frame", nil, frame)
    maxFrame:SetAllPoints(frame)
    frame.maxFrame = maxFrame

    -- Pet name
    local petName = maxFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    petName:SetPoint("TOP", 0, -25)
    petName:SetText("No Pet")
    petName:SetTextColor(0.7, 0.7, 0.7)
    maxFrame.petName = petName

    -- Happiness indicator
    local happinessBar = CreateFrame("StatusBar", nil, maxFrame)
    happinessBar:SetSize(160, 12)
    happinessBar:SetPoint("TOP", 0, -45)
    happinessBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    happinessBar:SetMinMaxValues(1, 3)
    happinessBar:SetValue(3)
    maxFrame.happinessBar = happinessBar

    local happinessText = maxFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    happinessText:SetPoint("CENTER", happinessBar, "CENTER", 0, 0)
    happinessText:SetText("Happy")
    maxFrame.happinessText = happinessText

    -- Food count (with icon space reserved)
    local foodText = maxFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    foodText:SetPoint("TOP", 0, -65)
    foodText:SetText("Food: 0")
    maxFrame.foodText = foodText

    -- Ensure feed button is present and attached
    self:EnsureFeedButton(maxFrame)

    -- FIXED: Pet Profiles button positioning - positioned below feed button instead of next to it
    local configBtn = FizzureUI:CreateButton(maxFrame, "Pet Profiles", 100, 20, function()
        HunterModule:ShowPetProfileFrame()
    end)
    configBtn:SetPoint("TOP", 0, -110)  -- Position below the feed button
    maxFrame.configBtn = configBtn

    -- FIXED: Keybinding display - positioned below Pet Profiles button
    local keybindText = maxFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    keybindText:SetPoint("TOP", 0, -135)  -- Below Pet Profiles button
    keybindText:SetText("Feed Key: " .. (self.settings.keybindings.feedPet or "Not Set"))
    keybindText:SetTextColor(0.8, 0.8, 1)
    maxFrame.keybindText = keybindText

    -- Minimize button
    local minimizeBtn = CreateFrame("Button", nil, maxFrame)
    minimizeBtn:SetSize(16, 16)
    minimizeBtn:SetPoint("TOPRIGHT", -25, -5)
    minimizeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    minimizeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    minimizeBtn:SetScript("OnClick", function()
        HunterModule:MinimizeStatusFrame()
    end)
    maxFrame.minimizeBtn = minimizeBtn
end

-- Show context menu for minimized frame (updated for manual feeding)
function HunterModule:ShowMiniContextMenu(parent)
    if self.contextMenu then
        self.contextMenu:Hide()
        self.contextMenu = nil
    end

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetSize(140, 90)  -- Slightly taller for additional options
    menu:SetPoint("BOTTOM", parent, "TOP", 0, 5)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:SetFrameStrata("DIALOG")

    -- Pet Profiles button
    local profilesBtn = CreateFrame("Button", nil, menu)
    profilesBtn:SetSize(130, 25)
    profilesBtn:SetPoint("TOP", 0, -8)
    profilesBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    profilesBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    local profilesText = profilesBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profilesText:SetPoint("CENTER")
    profilesText:SetText("Pet Profiles")

    profilesBtn:SetScript("OnClick", function()
        HunterModule:ShowPetProfileFrame()
        menu:Hide()
    end)

    -- Toggle Status Window Size
    local toggleBtn = CreateFrame("Button", nil, menu)
    toggleBtn:SetSize(130, 25)
    toggleBtn:SetPoint("CENTER", 0, 0)
    toggleBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    local toggleText = toggleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    toggleText:SetPoint("CENTER")
    toggleText:SetText("Maximize Window")

    toggleBtn:SetScript("OnClick", function()
        HunterModule:MaximizeStatusFrame()
        menu:Hide()
    end)

    -- Hide Status Window
    local hideBtn = CreateFrame("Button", nil, menu)
    hideBtn:SetSize(130, 25)
    hideBtn:SetPoint("BOTTOM", 0, 8)
    hideBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    hideBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    local hideText = hideBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hideText:SetPoint("CENTER")
    hideText:SetText("Hide Status")

    hideBtn:SetScript("OnClick", function()
        HunterModule:ToggleStatusFrame()
        menu:Hide()
    end)

    -- Hide menu after 5 seconds
    menu:Show()
    local hideTimer = CreateFrame("Frame")
    local elapsed = 0
    hideTimer:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 5 then
            self:SetScript("OnUpdate", nil)
            menu:Hide()
        end
    end)

    self.contextMenu = menu
end

-- Minimize status frame
function HunterModule:MinimizeStatusFrame()
    if not self.statusFrame then
        return
    end

    self.settings.statusFrameMinimized = true
    self.fizzure:SetModuleSettings(self.name, self.settings)

    self.statusFrame.maxFrame:Hide()
    self.statusFrame.miniFrame:Show()
    self.statusFrame:SetSize(160, 60)
    if self.statusFrame.titleText then
        self.statusFrame.titleText:Hide()
    end
    self:UpdateStatusFrame()
end

-- Maximize status frame
function HunterModule:MaximizeStatusFrame()
    if not self.statusFrame then
        return
    end

    self.settings.statusFrameMinimized = false
    self.fizzure:SetModuleSettings(self.name, self.settings)

    self.statusFrame.miniFrame:Hide()
    self.statusFrame.maxFrame:Show()
    self.statusFrame:SetSize(200, 140)
    if self.statusFrame.titleText then
        self.statusFrame.titleText:Show()
    end
    self:UpdateStatusFrame()
end

-- Enhanced status frame update
function HunterModule:UpdateStatusFrame()
    if not self.statusFrame then
        return
    end

    if self.settings.statusFrameMinimized then
        self:UpdateMinimizedFrame()
    else
        self:UpdateMaximizedFrame()
    end
end

-- Update minimized frame display with new improved layout
function HunterModule:UpdateMinimizedFrame()
    local miniFrame = self.statusFrame.miniFrame
    if not miniFrame then
        return
    end

    if self.currentPet then
        -- Update food display
        local profile = self.settings.petProfiles[self.currentPet.name]
        local totalFood = 0
        local foodIcon = "Interface\\Icons\\INV_Misc_Food_19"
        local hasPreferredFood = false

        if profile and profile.preferredFoods then
            -- Try to get icon from first preferred food with count > 0
            for i = 1, 6 do
                local foodName = profile.preferredFoods[i]
                if foodName and foodName ~= "" then
                    local count = GetItemCount(foodName) or 0
                    totalFood = totalFood + count
                    if count > 0 and not hasPreferredFood then
                        local itemIcon = GetItemIcon(foodName)
                        if itemIcon then
                            foodIcon = itemIcon
                            hasPreferredFood = true
                        end
                    end
                end
            end
        end

        miniFrame.foodIcon:SetTexture(foodIcon)
        miniFrame.foodCount:SetText(totalFood)

        -- Color code food count based on availability
        if totalFood == 0 then
            miniFrame.foodCount:SetTextColor(1, 0.3, 0.3)  -- Red for no food
            miniFrame.foodLabel:SetTextColor(1, 0.3, 0.3)
        elseif totalFood <= self.settings.lowFoodThreshold then
            miniFrame.foodCount:SetTextColor(1, 1, 0.3)  -- Yellow for low food
            miniFrame.foodLabel:SetTextColor(1, 1, 0.3)
        else
            miniFrame.foodCount:SetTextColor(0.3, 1, 0.3)  -- Green for good supply
            miniFrame.foodLabel:SetTextColor(0.8, 0.8, 0.8)
        end

        -- Update happiness display
        if UnitExists("pet") then
            local happiness = GetPetHappiness()
            if happiness then
                miniFrame.miniHappiness:SetValue(happiness)

                -- Color and icon based on happiness
                local colors = { { 1, 0.3, 0.3 }, { 1, 1, 0.3 }, { 0.3, 1, 0.3 } }
                local icons = {
                    "Interface\\Icons\\Spell_Shadow_RaiseDead", -- Sad face for unhappy
                    "Interface\\Icons\\INV_Misc_QuestionMark", -- Neutral for content
                    "Interface\\Icons\\Spell_Holy_Blessedlife"      -- Happy face for happy
                }
                local labels = { "Unhappy", "Content", "Happy" }

                local color = colors[happiness] or colors[1]
                local icon = icons[happiness] or icons[1]
                local label = labels[happiness] or "Unknown"

                miniFrame.miniHappiness:SetStatusBarColor(color[1], color[2], color[3])
                miniFrame.happinessIcon:SetTexture(icon)
                miniFrame.happinessLabel:SetText(label)
                miniFrame.happinessLabel:SetTextColor(color[1], color[2], color[3])
            else
                -- Pet exists but happiness unknown
                miniFrame.miniHappiness:SetValue(1)
                miniFrame.miniHappiness:SetStatusBarColor(0.5, 0.5, 0.5)
                miniFrame.happinessIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                miniFrame.happinessLabel:SetText("Unknown")
                miniFrame.happinessLabel:SetTextColor(0.7, 0.7, 0.7)
            end
        else
            -- No pet
            miniFrame.miniHappiness:SetValue(1)
            miniFrame.miniHappiness:SetStatusBarColor(0.3, 0.3, 0.3)
            miniFrame.happinessIcon:SetTexture("Interface\\Icons\\Spell_Shadow_RaiseDead")
            miniFrame.happinessLabel:SetText("No Pet")
            miniFrame.happinessLabel:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Update cooldown indicator
        local timeSinceLastFeed = GetTime() - self.lastManualFeed
        if timeSinceLastFeed < FEED_COOLDOWN then
            miniFrame.cooldownIcon:SetAlpha(1.0)
            miniFrame.cooldownIcon:SetDesaturated(false)
        else
            miniFrame.cooldownIcon:SetAlpha(0.3)
            miniFrame.cooldownIcon:SetDesaturated(true)
        end
    else
        -- No current pet
        miniFrame.foodIcon:SetTexture("Interface\\Icons\\INV_Misc_Food_19")
        miniFrame.foodCount:SetText("N/A")
        miniFrame.foodCount:SetTextColor(0.5, 0.5, 0.5)
        miniFrame.foodLabel:SetTextColor(0.5, 0.5, 0.5)

        miniFrame.miniHappiness:SetValue(1)
        miniFrame.miniHappiness:SetStatusBarColor(0.3, 0.3, 0.3)
        miniFrame.happinessIcon:SetTexture("Interface\\Icons\\Spell_Shadow_RaiseDead")
        miniFrame.happinessLabel:SetText("No Pet")
        miniFrame.happinessLabel:SetTextColor(0.5, 0.5, 0.5)

        miniFrame.cooldownIcon:SetAlpha(0.2)
        miniFrame.cooldownIcon:SetDesaturated(true)
    end
end

-- Update maximized frame display
function HunterModule:UpdateMaximizedFrame()
    local maxFrame = self.statusFrame.maxFrame
    if not maxFrame then
        return
    end

    -- Make sure the feed button exists here too (covers reloads / timing)
    if not maxFrame.feedBtn then
        self:EnsureFeedButton(maxFrame)
    end
    if not maxFrame.feedBtn then
        -- Still not available (e.g., still in combat). Don't error; just stop.
        return
    end

    if self.currentPet then
        maxFrame.petName:SetText(self.currentPet.name)
        maxFrame.petName:SetTextColor(1, 1, 1)

        if UnitExists("pet") then
            local happiness = GetPetHappiness()
            if happiness then
                maxFrame.happinessBar:SetValue(happiness)

                local colors = {
                    { 1, 0.3, 0.3 }, -- Red (unhappy)
                    { 1, 1, 0.3 }, -- Yellow (content)
                    { 0.3, 1, 0.3 }  -- Green (happy)
                }
                local texts = { "Unhappy", "Content", "Happy" }

                local color = colors[happiness] or colors[1]
                maxFrame.happinessBar:SetStatusBarColor(color[1], color[2], color[3])
                maxFrame.happinessText:SetText(texts[happiness] or "Unknown")
            else
                maxFrame.happinessText:SetText("Unknown")
            end
        end

        -- Update food count and display food icon
        local profile = self.settings.petProfiles[self.currentPet.name]
        if profile and profile.preferredFoods then
            local totalFood = 0
            local foodIcon = "Interface\\Icons\\INV_Misc_Food_19"

            -- Get icon from first preferred food with count > 0
            for i = 1, 6 do
                local foodName = profile.preferredFoods[i]
                if foodName and foodName ~= "" then
                    local count = GetItemCount(foodName) or 0
                    totalFood = totalFood + count
                    if count > 0 and foodIcon == "Interface\\Icons\\INV_Misc_Food_19" then
                        local itemIcon = GetItemIcon(foodName)
                        if itemIcon then
                            foodIcon = itemIcon
                        end
                    end
                end
            end

            -- Update food icon texture if we have a food texture
            if not maxFrame.foodIcon then
                maxFrame.foodIcon = maxFrame:CreateTexture(nil, "ARTWORK")
                maxFrame.foodIcon:SetSize(20, 20)
                maxFrame.foodIcon:SetPoint("LEFT", maxFrame.foodText, "LEFT", -25, 0)
            end
            maxFrame.foodIcon:SetTexture(foodIcon)

            maxFrame.foodText:SetText("Food: " .. totalFood)

            if totalFood <= self.settings.lowFoodThreshold then
                maxFrame.foodText:SetTextColor(1, 0.3, 0.3)
            else
                maxFrame.foodText:SetTextColor(1, 1, 1)
            end
        else
            maxFrame.foodText:SetText("Food: Unknown")
            maxFrame.foodText:SetTextColor(0.7, 0.7, 0.7)
            if maxFrame.foodIcon then
                maxFrame.foodIcon:SetTexture("Interface\\Icons\\INV_Misc_Food_19")
            end
        end

        -- Show keybinding in separate text
        local feedKey = self.settings.keybindings.feedPet or "Not Set"
        maxFrame.keybindText:SetText("Feed Key: " .. feedKey)

        -- Enable the feed button
        if maxFrame.feedBtn then
            maxFrame.feedBtn:Enable()
        end
    else
        maxFrame.petName:SetText("No Pet")
        maxFrame.petName:SetTextColor(0.7, 0.7, 0.7)
        maxFrame.happinessBar:SetValue(1)
        maxFrame.happinessBar:SetStatusBarColor(0.5, 0.5, 0.5)
        maxFrame.happinessText:SetText("N/A")
        maxFrame.foodText:SetText("Food: N/A")
        maxFrame.foodText:SetTextColor(0.7, 0.7, 0.7)
        if maxFrame.foodIcon then
            maxFrame.foodIcon:SetTexture("Interface\\Icons\\INV_Misc_Food_19")
        end
        if maxFrame.feedBtn then
            maxFrame.feedBtn:Disable()
        end
    end
end

-- Create pet profile frame (same as original but with logging)
function HunterModule:CreatePetProfileFrame()
    if self.profileFrame then
        return
    end

    self.profileFrame = FizzureUI:CreateWindow("HunterPetProfileFrame", "Pet Food Profiles", 650, 550)
    local frame = self.profileFrame

    -- Elevate the window properly
    self.fizzure:ElevateConfigWindow(frame)

    -- Current pet section
    local currentPetLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    currentPetLabel:SetPoint("TOP", 0, -50)
    currentPetLabel:SetText("Current Pet: None")
    currentPetLabel:SetTextColor(1, 1, 0.5)
    frame.currentPetLabel = currentPetLabel

    -- LEFT SIDE: Preferred Food Slots
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetSize(250, 400)
    leftPanel:SetPoint("TOPLEFT", 20, -80)
    leftPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    leftPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local leftTitle = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    leftTitle:SetPoint("TOP", 0, -15)
    leftTitle:SetText("Preferred Foods")
    leftTitle:SetTextColor(0.8, 1, 0.8)

    local slotsHelp = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    slotsHelp:SetPoint("TOP", 0, -35)
    slotsHelp:SetText("(Drag items here or right-click foods →)")
    slotsHelp:SetTextColor(0.7, 0.7, 0.7)

    -- Create food slots in a cleaner layout
    frame.foodSlots = {}
    for i = 1, 6 do
        local slot = FizzureUI:CreateFoodSlot(frame, i, function(index)
            HunterModule:ClearFoodSlot(index)
        end)

        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local x = 60 + (col * 60)
        local y = -70 - (row * 60)
        slot:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", x, y)

        frame.foodSlots[i] = slot

        -- Enhanced drag and drop handling
        slot:SetScript("OnReceiveDrag", function(self)
            local cursorType, itemID, itemLink = GetCursorInfo()
            if cursorType == "item" and itemLink then
                local itemName = GetItemInfo(itemLink)
                if itemName then
                    -- Check if it's actually food using our own function
                    local isFood = HunterModule:IsItemFood(itemName)
                    if isFood then
                        self:SetItem(itemName, itemLink)
                        HunterModule:SetFoodSlot(i, itemName, itemLink)
                        ClearCursor()
                    else
                        HunterModule.fizzure:ShowNotification("Invalid Item", itemName .. " is not food!", "error", 3)
                    end
                end
            end
        end)
    end

    -- RIGHT SIDE: Available Foods using our scan function
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetSize(330, 400)
    rightPanel:SetPoint("TOPRIGHT", -20, -80)
    rightPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

    local rightTitle = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rightTitle:SetPoint("TOP", 0, -15)
    rightTitle:SetText("Available Food in Bags")
    rightTitle:SetTextColor(0.8, 0.8, 1)

    local bagHelp = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    bagHelp:SetPoint("TOP", 0, -35)
    bagHelp:SetText("(Right-click to add to preferred foods)")
    bagHelp:SetTextColor(0.7, 0.7, 0.7)

    -- Simple food list with manual scrolling
    local foodListFrame = CreateFrame("Frame", nil, rightPanel)
    foodListFrame:SetSize(310, 280)
    foodListFrame:SetPoint("TOP", 0, -55)
    foodListFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    foodListFrame:SetBackdropColor(0, 0, 0, 0.5)

    local scrollChild = CreateFrame("Frame", nil, foodListFrame)
    scrollChild:SetSize(300, 280)
    scrollChild:SetPoint("TOPLEFT", 5, -5)

    -- Mouse wheel scrolling
    foodListFrame:EnableMouseWheel(true)
    foodListFrame.scrollOffset = 0
    foodListFrame.itemHeight = 28
    foodListFrame.maxVisible = math.floor(260 / foodListFrame.itemHeight)

    foodListFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxItems = #(HunterModule.availableFoods or {})
        local maxScroll = math.max(0, maxItems - self.maxVisible)

        self.scrollOffset = self.scrollOffset - delta
        if self.scrollOffset < 0 then
            self.scrollOffset = 0
        end
        if self.scrollOffset > maxScroll then
            self.scrollOffset = maxScroll
        end

        HunterModule:UpdatePetProfileFrame()
    end)

    foodListFrame.content = scrollChild
    foodListFrame.items = {}

    function foodListFrame:ClearItems()
        for _, item in ipairs(self.items) do
            item:Hide()
        end
        self.items = {}
    end

    function foodListFrame:AddItem(itemFrame)
        table.insert(self.items, itemFrame)
        itemFrame:SetParent(self.content)
    end

    frame.foodList = foodListFrame

    -- BOTTOM: Controls
    local controlPanel = CreateFrame("Frame", nil, frame)
    controlPanel:SetSize(600, 60)
    controlPanel:SetPoint("BOTTOM", 0, 20)

    -- Food input section
    local inputLabel = controlPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", 20, -10)
    inputLabel:SetText("Add Food by Name:")

    local foodInput = FizzureUI:CreateEditBox(controlPanel, 200, 25, function(text)
        HunterModule:AddFoodByName(text)
    end)
    foodInput:SetPoint("TOPLEFT", 20, -30)
    frame.foodInput = foodInput

    local addBtn = FizzureUI:CreateButton(controlPanel, "Add", 60, 25, function()
        HunterModule:AddFoodByName(foodInput:GetText())
        foodInput:SetText("")
    end)
    addBtn:SetPoint("LEFT", foodInput, "RIGHT", 10, 0)

    -- Clear all button
    local clearBtn = FizzureUI:CreateButton(controlPanel, "Clear All", 80, 25, function()
        HunterModule:ClearAllFoodSlots()
    end)
    clearBtn:SetPoint("TOPLEFT", 320, -30)

    -- Refresh foods button
    local refreshBtn = FizzureUI:CreateButton(controlPanel, "Refresh", 80, 25, function()
        HunterModule:ScanAvailableFoods()
        HunterModule:UpdatePetProfileFrame()
    end)
    refreshBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
end

-- FIXED: Use simple, working food check like original
function HunterModule:IsItemFood(itemName)
    local name, _, _, _, _, itemType, itemSubType = GetItemInfo(itemName)
    if not itemType then
        self.fizzure:LogDebug("DEBUG", "IsItemFood: No item type for " .. itemName, "Hunter")
        return false
    end

    -- Use the WORKING original logic
    if itemType and (itemType == "Consumable" or itemType == ITEM_CLASS_CONSUMABLE) then
        if itemSubType and (itemSubType == "Food & Drink" or itemSubType == ITEM_SUBCLASS_FOOD_DRINK or
                itemSubType == "Food" or itemSubType == "Consumable") then
            self.fizzure:LogDebug("DEBUG", "IsItemFood: " .. itemName .. " is FOOD", "Hunter")
            return true
        end
    end

    self.fizzure:LogDebug("DEBUG", "IsItemFood: " .. itemName .. " is NOT FOOD", "Hunter")
    return false
end

-- FIXED: Set food in slot with proper UI update
function HunterModule:SetFoodSlot(index, itemName, itemLink)
    self.fizzure:LogDebug("INFO", "SetFoodSlot: Setting slot " .. index .. " to " .. itemName, "Hunter")

    if not self.currentPet then
        self.fizzure:LogDebug("ERROR", "SetFoodSlot: No current pet", "Hunter")
        return
    end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then
        self.fizzure:LogDebug("ERROR", "SetFoodSlot: No profile for " .. self.currentPet.name, "Hunter")
        return
    end

    if not profile.preferredFoods then
        profile.preferredFoods = {}
    end

    profile.preferredFoods[index] = itemName
    self.fizzure:SetModuleSettings(self.name, self.settings)

    -- FIXED: Force UI update with proper icon
    if self.profileFrame and self.profileFrame.foodSlots[index] then
        local slot = self.profileFrame.foodSlots[index]
        slot.itemName = itemName
        slot.itemLink = itemLink

        -- Get and set the icon texture
        local itemIcon = GetItemIcon(itemName)
        if itemIcon and slot.texture then
            slot.texture:SetTexture(itemIcon)
            self.fizzure:LogDebug("DEBUG", "SetFoodSlot: Set texture for " .. itemName .. " to " .. itemIcon, "Hunter")
        end
    end

    self.fizzure:LogDebug("INFO", "SetFoodSlot: Slot " .. index .. " set to " .. itemName .. " and saved", "Hunter")
    self:UpdateStatusFrame()
    self:UpdateFeedButtonMacro()
end

-- Clear food slot
function HunterModule:ClearFoodSlot(index)
    if not self.currentPet then
        return
    end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then
        return
    end

    local oldFood = profile.preferredFoods and profile.preferredFoods[index]
    if profile.preferredFoods then
        profile.preferredFoods[index] = nil
    end

    self.fizzure:SetModuleSettings(self.name, self.settings)

    local slot = self.profileFrame and self.profileFrame.foodSlots[index]
    if slot then
        slot:ClearItem()
    end

    self.fizzure:LogDebug("INFO", "ClearFoodSlot: Cleared slot " .. index .. (oldFood and (" (was: " .. oldFood .. ")") or ""), "Hunter")

    self:UpdateStatusFrame()
    self:UpdateFeedButtonMacro()
end

-- Clear all food slots
function HunterModule:ClearAllFoodSlots()
    if not self.currentPet then
        return
    end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then
        return
    end

    profile.preferredFoods = {}
    self.fizzure:SetModuleSettings(self.name, self.settings)

    -- Clear UI slots
    if self.profileFrame and self.profileFrame.foodSlots then
        for _, slot in ipairs(self.profileFrame.foodSlots) do
            slot:ClearItem()
        end
    end

    self.fizzure:ShowNotification("Cleared", "All preferred food slots cleared", "info", 2)
    self.fizzure:LogDebug("INFO", "ClearAllFoodSlots: All slots cleared", "Hunter")

    self:UpdateStatusFrame()
    self:UpdateFeedButtonMacro()
end

-- Add food by name with validation
function HunterModule:AddFoodByName(foodName)
    self.fizzure:LogDebug("INFO", "AddFoodByName: Attempting to add " .. (foodName or "nil"), "Hunter")

    if not self.currentPet or not foodName or foodName == "" then
        self.fizzure:LogDebug("ERROR", "AddFoodByName: Invalid parameters", "Hunter")
        return
    end

    -- Check if item exists and is food
    if not self:IsItemFood(foodName) then
        self.fizzure:ShowNotification("Invalid Food", foodName .. " is not a valid food item", "error", 3)
        return
    end

    local profile = self.settings.petProfiles[self.currentPet.name]
    if not profile then
        return
    end

    if not profile.preferredFoods then
        profile.preferredFoods = {}
    end

    -- Find first empty slot
    for i = 1, 6 do
        if not profile.preferredFoods[i] or profile.preferredFoods[i] == "" then
            self:SetFoodSlot(i, foodName, nil)
            self.fizzure:ShowNotification("Food Added", "Added " .. foodName .. " to slot " .. i, "success", 2)
            return
        end
    end

    self.fizzure:ShowNotification("Slots Full", "All preferred food slots are full", "warning", 3)
end

-- Show pet profile frame
function HunterModule:ShowPetProfileFrame()
    if not self.profileFrame then
        self:CreatePetProfileFrame()
    end

    self:ScanAvailableFoods()
    self:UpdatePetProfileFrame()
    self.profileFrame:Show()
end

-- Update pet profile frame display
function HunterModule:UpdatePetProfileFrame()
    if not self.profileFrame then
        return
    end

    local frame = self.profileFrame

    if self.currentPet then
        frame.currentPetLabel:SetText("Current Pet: " .. self.currentPet.name .. " (" .. self.currentPet.family .. ", Level " .. self.currentPet.level .. ")")

        -- Update food slots - show food icons properly
        local profile = self.settings.petProfiles[self.currentPet.name]
        if profile and profile.preferredFoods and frame.foodSlots then
            for i, slot in ipairs(frame.foodSlots) do
                local foodName = profile.preferredFoods[i]
                if foodName and foodName ~= "" then
                    -- Get item info for proper display
                    local itemIcon = GetItemIcon(foodName)
                    slot:SetItem(foodName, nil) -- Don't need link for display

                    -- Force texture update if icon found
                    if itemIcon and slot.texture then
                        slot.texture:SetTexture(itemIcon)
                    end

                    self.fizzure:LogDebug("DEBUG", "UpdatePetProfileFrame: Updated slot " .. i .. " with " .. foodName, "Hunter")
                else
                    slot:ClearItem()
                end
            end
        end
    else
        frame.currentPetLabel:SetText("Current Pet: None")

        -- Clear all slots when no pet
        if frame.foodSlots then
            for _, slot in ipairs(frame.foodSlots) do
                slot:ClearItem()
            end
        end
    end

    -- Update available foods list using our own scan
    if frame.foodList then
        frame.foodList:ClearItems()

        local startIndex = frame.foodList.scrollOffset + 1
        local endIndex = math.min(startIndex + frame.foodList.maxVisible - 1, #self.availableFoods)

        for i = startIndex, endIndex do
            local food = self.availableFoods[i]
            if food then
                local foodItem = CreateFrame("Button", nil, frame.foodList.content)
                foodItem:SetSize(290, frame.foodList.itemHeight)
                local yPos = -((i - startIndex) * frame.foodList.itemHeight)
                foodItem:SetPoint("TOPLEFT", 5, yPos)

                -- Food icon
                local icon = foodItem:CreateTexture(nil, "ARTWORK")
                icon:SetSize(24, 24)
                icon:SetPoint("LEFT", 5, 0)
                local itemIcon = GetItemIcon(food.name)
                if itemIcon then
                    icon:SetTexture(itemIcon)
                else
                    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_19")
                end

                -- Food name and count
                local text = foodItem:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                text:SetSize(240, 24)
                text:SetText(food.name .. " x" .. food.count)
                text:SetJustifyH("LEFT")

                -- Right-click to add to preferred foods
                foodItem:RegisterForClicks("RightButtonUp")
                foodItem:SetScript("OnClick", function()
                    HunterModule:AddFoodByName(food.name)
                    -- Refresh the frame immediately to show the change
                    FizzureCommon:After(0.1, function()
                        HunterModule:UpdatePetProfileFrame()
                    end)
                end)

                -- Highlight texture
                foodItem:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")

                frame.foodList:AddItem(foodItem)
                foodItem:Show()
            end
        end
    end
end

-- Create configuration UI for main window
function HunterModule:CreateConfigUI(parent, x, y)
    if not self.settings then
        self.settings = self.fizzure:GetModuleSettings(self.name) or self:GetDefaultSettings()
        self.fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Show status toggle
    local showStatusCheck = FizzureUI:CreateCheckBox(parent, "Show Pet Status Window", self.settings.showFoodStatus, function(checked)
        HunterModule.settings.showFoodStatus = checked
        HunterModule.fizzure:SetModuleSettings(HunterModule.name, HunterModule.settings)

        if HunterModule.statusFrame then
            if checked then
                HunterModule.statusFrame:Show()
            else
                HunterModule.statusFrame:Hide()
            end
        end
    end)
    showStatusCheck:SetPoint("TOPLEFT", x, y)

    -- Low food threshold setting
    local thresholdLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thresholdLabel:SetPoint("TOPLEFT", x, y - 30)
    thresholdLabel:SetText("Low Food Warning Threshold:")

    local thresholdInput = FizzureUI:CreateEditBox(parent, 60, 20, function(text)
        local value = tonumber(text)
        if value and value >= 0 and value <= 100 then
            HunterModule.settings.lowFoodThreshold = value
            HunterModule.fizzure:SetModuleSettings(HunterModule.name, HunterModule.settings)
            HunterModule:UpdateStatusFrame()
        else
            HunterModule.fizzure:ShowNotification("Invalid Value", "Please enter a number between 0-100", "error", 3)
        end
    end)
    thresholdInput:SetPoint("LEFT", thresholdLabel, "RIGHT", 10, 0)
    thresholdInput:SetText(tostring(self.settings.lowFoodThreshold))

    -- Keybinding configuration
    local keybindLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keybindLabel:SetPoint("TOPLEFT", x, y - 60)
    keybindLabel:SetText("Feed Pet Keybinding:")

    local keybindInput = FizzureUI:CreateEditBox(parent, 100, 20, function(text)
        if text and text ~= "" then
            -- Validate keybinding format
            if text:match("^[A-Z]*%-*[A-Z0-9]$") then
                HunterModule.settings.keybindings.feedPet = text
                HunterModule.fizzure:SetModuleSettings(HunterModule.name, HunterModule.settings)

                -- Update secure button binding
                if FizzureSecure and HunterModule.feedButton then
                    FizzureSecure:ClearModuleBindings(HunterModule.name)
                    local binding = {
                        key = text,
                        buttonName = HunterModule.feedButton:GetName(),
                        description = "Feed Pet with Preferred Food"
                    }
                    FizzureSecure:RegisterModuleBindings(HunterModule.name, { binding })
                end

                HunterModule.fizzure:ShowNotification("Keybinding Set", "Feed Pet bound to " .. text, "success", 3)
            else
                HunterModule.fizzure:ShowNotification("Invalid Keybinding", "Use format like: ALT-F, CTRL-SHIFT-G, etc.", "error", 3)
            end
        end
    end)
    keybindInput:SetPoint("LEFT", keybindLabel, "RIGHT", 10, 0)
    keybindInput:SetText(self.settings.keybindings.feedPet or "")

    -- Pet profiles button
    local profileBtn = FizzureUI:CreateButton(parent, "Manage Pet Food Profiles", 140, 25, function()
        HunterModule:ShowPetProfileFrame()
    end)
    profileBtn:SetPoint("TOPLEFT", x, y - 90)

    -- Manual feed test button with enhanced feedback
    local testFeedBtn = FizzureUI:CreateButton(parent, "Test Feed System", 140, 20, function()
        HunterModule.fizzure:LogDebug("ACTION", "Feed system test initiated by user", "Hunter")

        -- Show current state for debugging
        if HunterModule.currentPet then
            local happiness = GetPetHappiness()
            HunterModule.fizzure:LogDebug("INFO", "Test: Pet happiness is " .. (happiness or "nil"), "Hunter")

            local foodToUse = HunterModule:FindBestFood()
            if foodToUse then
                HunterModule.fizzure:LogDebug("INFO", "Test: Best food found - " .. foodToUse.name .. " x" .. foodToUse.count, "Hunter")
                HunterModule.fizzure:ShowNotification("Feed Test", "Would feed " .. foodToUse.name .. " to " .. HunterModule.currentPet.name, "info", 3)
            else
                HunterModule.fizzure:LogDebug("WARN", "Test: No suitable food found", "Hunter")
                HunterModule.fizzure:ShowNotification("Feed Test", "No suitable food found for " .. HunterModule.currentPet.name, "warning", 3)
            end
        else
            HunterModule.fizzure:LogDebug("WARN", "Test: No pet active", "Hunter")
            HunterModule.fizzure:ShowNotification("Feed Test", "No pet active", "warning", 3)
        end
    end)
    testFeedBtn:SetPoint("TOPLEFT", x, y - 120)

    -- Instructions text
    local instructionText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    instructionText:SetPoint("TOPLEFT", x, y - 150)
    instructionText:SetSize(300, 40)
    instructionText:SetText("Pet feeding is manual-only. Use the keybinding or status window button to feed your pet. Configure preferred foods in Pet Profiles.")
    instructionText:SetTextColor(0.8, 0.8, 1)
    instructionText:SetJustifyH("LEFT")

    return y - 200
end

-- Get quick status for main window
function HunterModule:GetQuickStatus()
    if not self.currentPet then
        return "No pet active"
    end

    local happiness = GetPetHappiness()
    local happinessText = { "Unhappy", "Content", "Happy" }

    local profile = self.settings.petProfiles[self.currentPet.name]
    local foodCount = 0
    if profile and profile.preferredFoods then
        for i = 1, 6 do
            local foodName = profile.preferredFoods[i]
            if foodName and foodName ~= "" then
                foodCount = foodCount + (GetItemCount(foodName) or 0)
            end
        end
    end

    local feedKey = self.settings.keybindings.feedPet or "Not Set"
    local timeSinceLastFeed = GetTime() - self.lastManualFeed
    local cooldownStatus = ""

    if timeSinceLastFeed < FEED_COOLDOWN then
        local remaining = FEED_COOLDOWN - timeSinceLastFeed
        cooldownStatus = " (CD:" .. string.format("%.1fs", remaining) .. ")"
    end

    return string.format("%s: %s, Food: %d, Key: %s%s",
            self.currentPet.name,
            happinessText[happiness] or "Unknown",
            foodCount,
            feedKey,
            cooldownStatus)
end

-- Handle debug mode toggle
function HunterModule:OnDebugToggle(enabled, level)
    if enabled then
        self.fizzure:LogDebug("INFO", "Debug mode enabled for Hunter module - Level: " .. level, "Hunter")

        if self.currentPet then
            self.fizzure:LogDebug("INFO", "Current pet: " .. self.currentPet.name, "Hunter")
            local profile = self.settings.petProfiles[self.currentPet.name]
            if profile and profile.preferredFoods then
                local foodList = {}
                for i = 1, 6 do
                    local food = profile.preferredFoods[i]
                    if food and food ~= "" then
                        table.insert(foodList, "Slot" .. i .. ":" .. food .. "(" .. (GetItemCount(food) or 0) .. ")")
                    end
                end
                if #foodList > 0 then
                    self.fizzure:LogDebug("INFO", "Preferred foods: " .. table.concat(foodList, ", "), "Hunter")
                end
            end

            -- Log secure button status
            if self.feedButton then
                self.fizzure:LogDebug("INFO", "Secure feed button available: " .. self.feedButton:GetName(), "Hunter")
            else
                self.fizzure:LogDebug("WARN", "Secure feed button not available", "Hunter")
            end

            -- Log available food count
            self.fizzure:LogDebug("INFO", "Available food items in bags: " .. #self.availableFoods, "Hunter")
        end
    end
end

-- Register module with core system
if Fizzure then
    Fizzure:RegisterClassModule("Hunter Pet Manager", HunterModule, "HUNTER")
end