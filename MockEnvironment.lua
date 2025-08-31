-- MockEnvironment.lua - Enhanced Testing Helper for Fizzure Development (COMPLETE VERSION)
-- This addon creates controllable test scenarios and works with the enhanced architecture

local MockEnv = {}
MockEnv.originalFunctions = {}
MockEnv.isActive = false
MockEnv.mockData = {
    pets = {
        ["TestWolf"] = {family = "Wolf", happiness = 2, level = 20},
        ["TestBear"] = {family = "Bear", happiness = 1, level = 35},
        ["TestCat"] = {family = "Cat", happiness = 3, level = 15},
        ["TestSpider"] = {family = "Spider", happiness = 2, level = 45},
        ["TestRaptor"] = {family = "Raptor", happiness = 1, level = 60}
    },
    inventory = {
        -- High level foods
        ["Roasted Clefthoof"] = 25,
        ["Smoked Talbuk Venison"] = 15,
        ["Poached Sunscale Salmon"] = 10,
        ["Mammoth Meal"] = 5,

        -- Mid level foods
        ["Smoked Salmon"] = 8,
        ["Goldenbark Apple"] = 12,
        ["Alterac Swiss"] = 6,
        ["Homemade Cherry Pie"] = 20,

        -- Low level foods
        ["Raw Boar Meat"] = 30,
        ["Red Apple"] = 15,
        ["Fresh Bread"] = 25,
        ["Raw Longjaw Mud Snapper"] = 40,

        -- Special cases
        ["Conjured Mana Biscuit"] = 15,
        ["Goldenbark Apple"] = 0, -- No fruit for testing
        ["Tundra Berries"] = 3    -- Low stock for testing
    },
    currentPet = nil,
    playerLevel = 70 -- For testing level-appropriate food
}

-- Enhanced mock WoW API functions for testing
function MockEnv:EnableMocking()
    if self.isActive then
        print("|cffff8000MockEnvironment:|r Already active")
        return
    end

    -- Store original functions
    self.originalFunctions.UnitExists = UnitExists
    self.originalFunctions.UnitName = UnitName
    self.originalFunctions.UnitCreatureFamily = UnitCreatureFamily
    self.originalFunctions.UnitLevel = UnitLevel
    self.originalFunctions.GetPetHappiness = GetPetHappiness
    self.originalFunctions.GetItemCount = GetItemCount
    self.originalFunctions.UseItemByName = UseItemByName
    self.originalFunctions.GetItemIcon = GetItemIcon
    self.originalFunctions.GetItemInfo = GetItemInfo

    -- Replace with mock functions
    UnitExists = function(unit)
        if unit == "pet" then
            return self.mockData.currentPet ~= nil
        elseif unit == "player" then
            return true
        end
        return self.originalFunctions.UnitExists(unit)
    end

    UnitName = function(unit)
        if unit == "pet" and self.mockData.currentPet then
            return self.mockData.currentPet
        elseif unit == "player" then
            return "TestPlayer"
        end
        return self.originalFunctions.UnitName(unit)
    end

    UnitCreatureFamily = function(unit)
        if unit == "pet" and self.mockData.currentPet then
            local petData = self.mockData.pets[self.mockData.currentPet]
            return petData and petData.family
        end
        return self.originalFunctions.UnitCreatureFamily(unit)
    end

    UnitLevel = function(unit)
        if unit == "pet" and self.mockData.currentPet then
            local petData = self.mockData.pets[self.mockData.currentPet]
            return petData and petData.level or 1
        elseif unit == "player" then
            return self.mockData.playerLevel
        end
        return self.originalFunctions.UnitLevel(unit)
    end

    GetPetHappiness = function()
        if self.mockData.currentPet then
            local petData = self.mockData.pets[self.mockData.currentPet]
            local happiness = petData and petData.happiness or 1
            local damage = 100 -- Mock damage percentage
            local loyalty = 6   -- Mock loyalty level
            return happiness, damage, loyalty
        end
        return self.originalFunctions.GetPetHappiness()
    end

    GetItemCount = function(itemName)
        return self.mockData.inventory[itemName] or 0
    end

    UseItemByName = function(itemName)
        if self.mockData.inventory[itemName] and self.mockData.inventory[itemName] > 0 then
            self.mockData.inventory[itemName] = self.mockData.inventory[itemName] - 1
            print("|cff00ff00MockEnv:|r Used " .. itemName .. " (" .. self.mockData.inventory[itemName] .. " remaining)")

            -- Simulate pet happiness increase
            if self.mockData.currentPet then
                local petData = self.mockData.pets[self.mockData.currentPet]
                if petData and petData.happiness < 3 then
                    petData.happiness = math.min(3, petData.happiness + 1)
                    print("|cff00ff00MockEnv:|r " .. self.mockData.currentPet .. " happiness increased to " .. petData.happiness)

                    -- Trigger pet UI update for the hunter module
                    if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
                        local module = Fizzure.modules["Hunter Pet Manager"]
                        if module.OnEvent then
                            module:OnEvent("PET_UI_UPDATE")
                        end
                    end
                end
            end
            return true
        else
            print("|cffff0000MockEnv:|r Cannot use " .. itemName .. " - not available")
            return false
        end
    end

    -- Mock item info functions for better testing
    GetItemIcon = function(itemName)
        -- Return mock icons based on food type
        local iconMap = {
            ["Roasted Clefthoof"] = "Interface\\Icons\\INV_Misc_Food_59",
            ["Smoked Salmon"] = "Interface\\Icons\\INV_Misc_Food_15",
            ["Red Apple"] = "Interface\\Icons\\INV_Misc_Food_12",
            ["Fresh Bread"] = "Interface\\Icons\\INV_Misc_Food_23",
            ["Conjured Mana Biscuit"] = "Interface\\Icons\\INV_Misc_Food_32"
        }
        return iconMap[itemName] or "Interface\\Icons\\INV_Misc_Food_01"
    end

    GetItemInfo = function(itemLink)
        -- Parse item name from link or use directly if it's just a name
        local itemName = itemLink
        if type(itemLink) == "string" and itemLink:match("|h%[(.+)%]|h") then
            itemName = itemLink:match("|h%[(.+)%]|h")
        end

        -- Return mock item info
        return itemName, nil, 1, 1, 1, nil, nil, nil, nil, GetItemIcon(itemName), nil, nil, nil
    end

    self.isActive = true
    print("|cffff8000MockEnvironment:|r API mocking enabled")

    -- Log current mock state if Fizzure debug is enabled
    if Fizzure and Fizzure.debug and Fizzure.debug.enabled then
        Fizzure:LogDebug("INFO", "MockEnvironment activated", "MockEnv")
    end
end

-- Restore original functions
function MockEnv:DisableMocking()
    if not self.isActive then
        print("|cffff8000MockEnvironment:|r Not currently active")
        return
    end

    for funcName, originalFunc in pairs(self.originalFunctions) do
        _G[funcName] = originalFunc
    end

    self.isActive = false

    -- Trigger pet detection if Hunter module is loaded
    if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
        local module = Fizzure.modules["Hunter Pet Manager"]
        if module.UpdateCurrentPet then
            module:UpdateCurrentPet()
        end
    end

    print("|cffff8000MockEnvironment:|r API mocking disabled")

    -- Log to Fizzure debug if available
    if Fizzure and Fizzure.debug and Fizzure.debug.enabled then
        Fizzure:LogDebug("INFO", "MockEnvironment deactivated", "MockEnv")
    end
end

-- Enhanced test scenario functions
function MockEnv:SummonPet(petName)
    if not self.mockData.pets[petName] then
        print("|cffff0000MockEnv:|r Unknown pet: " .. petName)
        self:ListAvailablePets()
        return false
    end

    self.mockData.currentPet = petName
    local petData = self.mockData.pets[petName]
    print("|cffff8000MockEnv:|r Summoned " .. petName .. " (Level " .. petData.level .. " " .. petData.family .. ")")

    -- Trigger pet events if Fizzure is loaded
    if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
        local module = Fizzure.modules["Hunter Pet Manager"]
        if module.OnEvent then
            module:OnEvent("UNIT_PET")
            module:OnEvent("PLAYER_PET_CHANGED")
        end
    end

    return true
end

function MockEnv:DismissPet()
    if not self.mockData.currentPet then
        print("|cffff8000MockEnv:|r No pet currently summoned")
        return
    end

    local petName = self.mockData.currentPet
    self.mockData.currentPet = nil
    print("|cffff8000MockEnv:|r " .. petName .. " dismissed")

    -- Trigger pet events
    if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
        local module = Fizzure.modules["Hunter Pet Manager"]
        if module.OnEvent then
            module:OnEvent("UNIT_PET")
            module:OnEvent("PLAYER_PET_CHANGED")
        end
    end
end

function MockEnv:SetPetHappiness(happiness)
    if not self.mockData.currentPet then
        print("|cffff0000MockEnv:|r No pet summoned")
        return false
    end

    local happinessLevel = tonumber(happiness)
    if not happinessLevel or happinessLevel < 1 or happinessLevel > 3 then
        print("|cffff0000MockEnv:|r Invalid happiness level. Use 1 (Unhappy), 2 (Content), or 3 (Happy)")
        return false
    end

    local petData = self.mockData.pets[self.mockData.currentPet]
    if petData then
        petData.happiness = happinessLevel
        local happinessText = {"Unhappy", "Content", "Happy"}
        print("|cffff8000MockEnv:|r Set " .. self.mockData.currentPet .. " happiness to " .. happinessText[happinessLevel])

        -- Trigger UI update
        if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
            local module = Fizzure.modules["Hunter Pet Manager"]
            if module.OnEvent then
                module:OnEvent("PET_UI_UPDATE")
            end
        end
        return true
    end
    return false
end

function MockEnv:SetPetLevel(level)
    if not self.mockData.currentPet then
        print("|cffff0000MockEnv:|r No pet summoned")
        return false
    end

    local petLevel = tonumber(level)
    if not petLevel or petLevel < 1 or petLevel > 80 then
        print("|cffff0000MockEnv:|r Invalid level. Use 1-80")
        return false
    end

    local petData = self.mockData.pets[self.mockData.currentPet]
    if petData then
        petData.level = petLevel
        print("|cffff8000MockEnv:|r Set " .. self.mockData.currentPet .. " level to " .. petLevel)

        -- Trigger update
        if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
            local module = Fizzure.modules["Hunter Pet Manager"]
            if module.UpdateCurrentPet then
                module:UpdateCurrentPet()
            end
        end
        return true
    end
    return false
end

function MockEnv:SetFoodCount(foodName, count)
    local foodCount = tonumber(count) or 0
    self.mockData.inventory[foodName] = foodCount
    print("|cffff8000MockEnv:|r Set " .. foodName .. " count to " .. foodCount)

    -- Trigger bag update
    if Fizzure and Fizzure.modules["Hunter Pet Manager"] then
        local module = Fizzure.modules["Hunter Pet Manager"]
        if module.OnEvent then
            module:OnEvent("BAG_UPDATE")
        end
    end
end

function MockEnv:ListAvailablePets()
    print("|cffff8000MockEnv Available Pets:|r")
    for petName, petData in pairs(self.mockData.pets) do
        local status = petName == self.mockData.currentPet and " |cff00ff00(ACTIVE)|r" or ""
        print("  " .. petName .. " - Level " .. petData.level .. " " .. petData.family .. status)
    end
end

function MockEnv:ListInventory()
    print("|cffff8000MockEnv Inventory:|r")
    for itemName, count in pairs(self.mockData.inventory) do
        if count > 0 then
            print("  " .. itemName .. ": " .. count)
        end
    end
end

function MockEnv:ShowStatus()
    print("|cffff8000MockEnvironment Status:|r")
    print("  Mocking Active: " .. (self.isActive and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    print("  Current Pet: " .. (self.mockData.currentPet or "None"))

    if self.mockData.currentPet then
        local petData = self.mockData.pets[self.mockData.currentPet]
        if petData then
            local happinessText = {"Unhappy", "Content", "Happy"}
            print("    Family: " .. petData.family)
            print("    Level: " .. petData.level)
            print("    Happiness: " .. happinessText[petData.happiness])
        end
    end

    local itemCount = 0
    for _, count in pairs(self.mockData.inventory) do
        if count > 0 then itemCount = itemCount + 1 end
    end
    print("  Food Items Available: " .. itemCount)

    -- Show Fizzure integration status
    if Fizzure then
        local hunterModule = Fizzure.modules["Hunter Pet Manager"]
        local moduleStatus = hunterModule and "LOADED" or "NOT LOADED"
        print("  Hunter Module: " .. moduleStatus)
        if hunterModule and Fizzure.db.enabledModules["Hunter Pet Manager"] then
            print("    Status: |cff00ff00ENABLED|r")
        elseif hunterModule then
            print("    Status: |cffff0000DISABLED|r")
        end
    else
        print("  Fizzure Core: |cffff0000NOT LOADED|r")
    end
end

-- Enhanced test scenarios
function MockEnv:RunTestScenario(scenarioName)
    if not self.isActive then
        print("|cffff0000MockEnv:|r Mocking must be enabled first. Use /mock on")
        return
    end

    if scenarioName == "hungry_pet" then
        self:SummonPet("TestWolf")
        self:SetPetHappiness(1) -- Unhappy
        self:SetFoodCount("Roasted Clefthoof", 10)
        self:SetFoodCount("Smoked Salmon", 5)
        print("|cff00ff00Scenario:|r Hungry pet with appropriate food available")

    elseif scenarioName == "no_food" then
        self:SummonPet("TestCat")
        self:SetPetHappiness(2) -- Content
        self:SetFoodCount("Roasted Clefthoof", 0)
        self:SetFoodCount("Smoked Salmon", 0)
        self:SetFoodCount("Raw Boar Meat", 0)
        print("|cff00ff00Scenario:|r Pet needs feeding but no compatible food available")

    elseif scenarioName == "low_food" then
        self:SummonPet("TestBear")
        self:SetPetHappiness(3) -- Happy
        self:SetFoodCount("Roasted Clefthoof", 3) -- Below threshold
        self:SetFoodCount("Fresh Bread", 2)
        print("|cff00ff00Scenario:|r Low food warning test")

    elseif scenarioName == "wrong_food" then
        self:SummonPet("TestCat") -- Can only eat meat/fish
        self:SetPetHappiness(2)
        self:SetFoodCount("Red Apple", 10) -- Fruit - incompatible
        self:SetFoodCount("Fresh Bread", 15) -- Bread - incompatible
        self:SetFoodCount("Roasted Clefthoof", 0) -- No compatible food
        print("|cff00ff00Scenario:|r Wrong food type available")

    elseif scenarioName == "level_mismatch" then
        self:SummonPet("TestWolf")
        self:SetPetLevel(10) -- Low level pet
        self:SetPetHappiness(1) -- Unhappy
        self:SetFoodCount("Mammoth Meal", 5) -- Level 75 food - too high
        self:SetFoodCount("Raw Boar Meat", 10) -- Level 1 food - appropriate
        print("|cff00ff00Scenario:|r Food level compatibility test")

    elseif scenarioName == "high_level_pet" then
        self:SummonPet("TestRaptor")
        self:SetPetLevel(70) -- High level pet
        self:SetPetHappiness(1) -- Unhappy
        self:SetFoodCount("Raw Boar Meat", 20) -- Low level food - still usable
        self:SetFoodCount("Mammoth Meal", 3) -- High level food - preferred
        print("|cff00ff00Scenario:|r High level pet with mixed food levels")

    elseif scenarioName == "rapid_feeding" then
        self:SummonPet("TestSpider")
        self:SetPetHappiness(1) -- Unhappy
        self:SetFoodCount("Smoked Salmon", 1) -- Only one food item
        print("|cff00ff00Scenario:|r Rapid feeding test - will run out of food quickly")

    elseif scenarioName == "multiple_pets" then
        print("|cff00ff00Scenario:|r Multiple pet switching test")
        self:SummonPet("TestWolf")
        self:SetPetHappiness(2)
        FizzureCommon:After(3, function()
            MockEnv:SummonPet("TestBear")
            MockEnv:SetPetHappiness(1)
        end)

        FizzureCommon:After(6, function()
            MockEnv:SummonPet("TestCat")
            MockEnv:SetPetHappiness(3)
        end)

    else
        print("|cffff0000MockEnv:|r Unknown scenario. Available scenarios:")
        print("  hungry_pet - Basic hungry pet with food")
        print("  no_food - Pet needs food but none available")
        print("  low_food - Test low food warnings")
        print("  wrong_food - Incompatible food types")
        print("  level_mismatch - Food level vs pet level")
        print("  high_level_pet - High level pet scenarios")
        print("  rapid_feeding - Quick food consumption test")
        print("  multiple_pets - Pet switching test")
    end
end

-- Performance testing
function MockEnv:RunPerformanceTest(iterations)
    if not self.isActive then
        print("|cffff0000MockEnv:|r Mocking must be enabled first")
        return
    end

    iterations = tonumber(iterations) or 100
    print("|cffff8000MockEnv:|r Running performance test with " .. iterations .. " iterations...")

    self:SummonPet("TestWolf")
    self:SetPetHappiness(1)
    self:SetFoodCount("Roasted Clefthoof", iterations + 10)

    local startTime = GetTime()
    local hunterModule = Fizzure and Fizzure.modules["Hunter Pet Manager"]

    if hunterModule then
        for i = 1, iterations do
            hunterModule:FeedPet()
        end
    end

    local endTime = GetTime()
    local totalTime = endTime - startTime

    print("|cffff8000MockEnv:|r Performance test completed:")
    print("  " .. iterations .. " feed operations in " .. string.format("%.3f", totalTime) .. " seconds")
    print("  Average: " .. string.format("%.3f", (totalTime / iterations) * 1000) .. " ms per operation")
end

-- Integration with Fizzure debug system
function MockEnv:SetDebugMode(enabled)
    if not Fizzure then
        print("|cffff0000MockEnv:|r Fizzure not loaded")
        return
    end

    if enabled and not Fizzure.debug.enabled then
        Fizzure:ToggleDebug("VERBOSE")
        print("|cffff8000MockEnv:|r Enabled Fizzure debug mode")
    elseif not enabled and Fizzure.debug.enabled then
        Fizzure:ToggleDebug()
        print("|cffff8000MockEnv:|r Disabled Fizzure debug mode")
    end
end

-- Enhanced slash commands for easy testing
SLASH_MOCKENV1 = "/mockenv"
SLASH_MOCKENV2 = "/mock"
SlashCmdList["MOCKENV"] = function(msg)
    local command, arg1, arg2, arg3 = strsplit(" ", msg)
    command = string.lower(command or "")

    if command == "on" or command == "enable" then
        MockEnv:EnableMocking()
    elseif command == "off" or command == "disable" then
        MockEnv:DisableMocking()
    elseif command == "summon" and arg1 then
        MockEnv:SummonPet(arg1)
    elseif command == "dismiss" then
        MockEnv:DismissPet()
    elseif command == "happiness" and arg1 then
        MockEnv:SetPetHappiness(arg1)
    elseif command == "level" and arg1 then
        MockEnv:SetPetLevel(arg1)
    elseif command == "food" and arg1 and arg2 then
        MockEnv:SetFoodCount(arg1, arg2)
    elseif command == "status" then
        MockEnv:ShowStatus()
    elseif command == "pets" then
        MockEnv:ListAvailablePets()
    elseif command == "inventory" then
        MockEnv:ListInventory()
    elseif command == "scenario" and arg1 then
        MockEnv:RunTestScenario(arg1)
    elseif command == "perf" then
        MockEnv:RunPerformanceTest(arg1)
    elseif command == "debug" then
        MockEnv:SetDebugMode(arg1 == "on" or arg1 == "enable")
    elseif command == "reset" then
        MockEnv:DisableMocking()
        MockEnv.mockData.currentPet = nil
        -- Reset inventory to defaults
        MockEnv.mockData.inventory = {
            ["Roasted Clefthoof"] = 25,
            ["Smoked Talbuk Venison"] = 15,
            ["Poached Sunscale Salmon"] = 10,
            ["Smoked Salmon"] = 8,
            ["Raw Boar Meat"] = 30,
            ["Red Apple"] = 15,
            ["Fresh Bread"] = 25,
            ["Conjured Mana Biscuit"] = 15
        }
        print("|cffff8000MockEnv:|r Reset to defaults")
    else
        print("|cffff8000MockEnvironment Commands:|r")
        print("  /mock on/off - Enable/disable API mocking")
        print("  /mock summon <petname> - Summon pet (TestWolf, TestBear, TestCat, TestSpider, TestRaptor)")
        print("  /mock dismiss - Dismiss current pet")
        print("  /mock happiness <1-3> - Set pet happiness (1=Unhappy, 2=Content, 3=Happy)")
        print("  /mock level <1-80> - Set pet level")
        print("  /mock food <itemname> <count> - Set food count")
        print("  /mock status - Show current mock state")
        print("  /mock pets - List available pets")
        print("  /mock inventory - Show mock inventory")
        print("  /mock scenario <name> - Run test scenario")
        print("  /mock perf [iterations] - Run performance test")
        print("  /mock debug on/off - Toggle Fizzure debug mode")
        print("  /mock reset - Reset to default state")
        print("")
        print("|cffFFD700Available Scenarios:|r hungry_pet, no_food, low_food, wrong_food,")
        print("level_mismatch, high_level_pet, rapid_feeding, multiple_pets")
    end
end

print("|cffff8000MockEnvironment|r Enhanced Version Loaded. Type /mock for commands.")