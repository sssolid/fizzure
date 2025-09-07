-- Tests.lua - Enhanced Testing Framework Integration (COMPLETE VERSION)
-- Updated to work with the enhanced Fizzure architecture and new Hunter module

local FizzureTests = {}

-- Only load tests in development environment
if not WoWUnit then
    print("|cffff8000FizzureTests:|r WoWUnit not available - tests disabled")
    return
end

-- Create test suite
local Tests = WoWUnit('Fizzure_Tests', 'ADDON_LOADED')

-- Enhanced test data setup
local mockPetData = {
    ["TestWolf"] = {name = "TestWolf", family = "Wolf", happiness = 2, level = 25},
    ["TestBear"] = {name = "TestBear", family = "Bear", happiness = 1, level = 40},
    ["TestCat"] = {name = "TestCat", family = "Cat", happiness = 3, level = 15}
}

local mockFoodItems = {
    ["Roasted Clefthoof"] = 15,
    ["Smoked Salmon"] = 8,
    ["Raw Boar Meat"] = 25,
    ["Red Apple"] = 12,
    ["Fresh Bread"] = 20,
    ["Conjured Mana Biscuit"] = 0,
    ["Mammoth Meal"] = 5 -- High level food
}

-- Setup function - runs before each test
function Tests:Setup()
    -- Ensure Fizzure core is loaded
    WoWUnit.Exists(Fizzure, "Fizzure core should be loaded")

    -- Reset module state
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if hunterModule then
        hunterModule.currentPet = nil
        hunterModule.settings = hunterModule:GetDefaultSettings()

        -- Clear any existing profiles
        hunterModule.settings.petProfiles = {}
    end

    -- Reset mock data
    if MockEnv then
        MockEnv.mockData.currentPet = nil
        for petName, data in pairs(mockPetData) do
            MockEnv.mockData.pets[petName] = {
                family = data.family,
                happiness = data.happiness,
                level = data.level
            }
        end
        MockEnv.mockData.inventory = {}
        for item, count in pairs(mockFoodItems) do
            MockEnv.mockData.inventory[item] = count
        end
    end
end

-- Test core system functionality
function Tests:TestCoreSystemLoaded()
    WoWUnit.Exists(Fizzure, "Fizzure core should exist")
    WoWUnit.Exists(Fizzure.modules, "Module registry should exist")
    WoWUnit.Exists(Fizzure.moduleCategories, "Module categories should exist")
    WoWUnit.AreEqual("table", type(Fizzure.db), "Database should be initialized")
    WoWUnit.Exists(Fizzure.RegisterModule, "Module registration function should exist")
end

-- Test enhanced module registration
function Tests:TestModuleRegistration()
    WoWUnit.Exists(Fizzure.modules["Hunter Pet Manager"], "Hunter module should be registered")

    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    WoWUnit.AreEqual("Hunter Pet Manager", hunterModule.name, "Module name should be set")
    WoWUnit.AreEqual("Class-Specific", hunterModule.category, "Module should be in Class-Specific category")
    WoWUnit.AreEqual("HUNTER", hunterModule.classRestriction, "Module should have Hunter class restriction")

    -- Test module is in correct category
    local classSpecificModules = Fizzure.moduleCategories["Class-Specific"]
    WoWUnit.Exists(classSpecificModules["Hunter Pet Manager"], "Hunter module should be in Class-Specific category")
end

-- Test module settings system
function Tests:TestModuleSettings()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Test default settings
    local defaultSettings = hunterModule:GetDefaultSettings()
    WoWUnit.Exists(defaultSettings, "Module should provide default settings")
    WoWUnit.AreEqual("boolean", type(defaultSettings.enabled), "Settings should include enabled flag")
    WoWUnit.AreEqual("boolean", type(defaultSettings.autoFeed), "Settings should include autoFeed setting")

    -- Test settings validation
    WoWUnit.AreEqual(true, hunterModule:ValidateSettings(defaultSettings), "Default settings should be valid")

    local invalidSettings = {enabled = "not_boolean", autoFeed = true, checkInterval = 3}
    WoWUnit.AreEqual(false, hunterModule:ValidateSettings(invalidSettings), "Invalid settings should fail validation")
end

-- Test pet detection with enhanced data
function Tests:TestEnhancedPetDetection()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Enable mocking if available
    if MockEnv then
        MockEnv:EnableMocking()
        MockEnv:SummonPet("TestWolf")
    else
        -- Mock WoW API functions directly
        WoWUnit.Replace('UnitExists', function(unit)
            return unit == "pet"
        end)

        WoWUnit.Replace('UnitName', function(unit)
            return unit == "pet" and mockPetData.TestWolf.name or nil
        end)

        WoWUnit.Replace('UnitCreatureFamily', function(unit)
            return unit == "pet" and mockPetData.TestWolf.family or nil
        end)

        WoWUnit.Replace('UnitLevel', function(unit)
            return unit == "pet" and mockPetData.TestWolf.level or 1
        end)
    end

    -- Test the function
    hunterModule:UpdateCurrentPet()

    -- Verify results
    WoWUnit.Exists(hunterModule.currentPet, "Current pet should be set")
    WoWUnit.AreEqual(mockPetData.TestWolf.name, hunterModule.currentPet.name, "Pet name should match")
    WoWUnit.AreEqual(mockPetData.TestWolf.family, hunterModule.currentPet.family, "Pet family should match")
    WoWUnit.AreEqual(mockPetData.TestWolf.level, hunterModule.currentPet.level, "Pet level should match")
    WoWUnit.Exists(hunterModule.settings.petProfiles[mockPetData.TestWolf.name], "Pet profile should be created")

    -- Clean up
    if MockEnv and MockEnv.isActive then
        MockEnv:DisableMocking()
    end
end

-- Test food compatibility with level checking
function Tests:TestFoodCompatibilityWithLevels()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Set up mock pet
    hunterModule.currentPet = mockPetData.TestWolf

    -- Test compatible foods
    local compatibleFoods = hunterModule:GetCompatibleFoods()
    WoWUnit.Exists(compatibleFoods, "Should return food list")
    WoWUnit.AreEqual("table", type(compatibleFoods), "Should return table")

    -- Wolf should be able to eat meat and fish
    local hasCompatibleFood = false
    for _, food in ipairs(compatibleFoods) do
        if food == "Roasted Clefthoof" or food == "Smoked Salmon" or food == "Raw Boar Meat" then
            hasCompatibleFood = true
            break
        end
    end
    WoWUnit.AreEqual(true, hasCompatibleFood, "Wolf should have compatible meat/fish options")

    -- Test level-appropriate food checking
    WoWUnit.AreEqual(true, hunterModule:IsFoodAppropriateLevel("Raw Boar Meat"), "Low level food should be appropriate")
    WoWUnit.AreEqual(true, hunterModule:IsFoodAppropriateLevel("Roasted Clefthoof"), "Similar level food should be appropriate")

    -- Test with high level food for low level pet
    hunterModule.currentPet.level = 10
    WoWUnit.AreEqual(false, hunterModule:IsFoodAppropriateLevel("Mammoth Meal"), "Too high level food should not be appropriate")
end

-- Test enhanced auto-feeding logic
function Tests:TestEnhancedAutoFeeding()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    local fedPet = false
    local usedItem = nil

    -- Set up test state
    hunterModule.currentPet = mockPetData.TestWolf
    hunterModule.settings.petProfiles[mockPetData.TestWolf.name] = {
        family = mockPetData.TestWolf.family,
        preferredFood = {"Roasted Clefthoof", "Smoked Salmon"},
        lastFed = 0
    }
    hunterModule.settings.autoFeed = true

    -- Mock functions
    WoWUnit.Replace('GetPetHappiness', function()
        return 2, 100, 6 -- Content, full damage, max loyalty
    end)

    WoWUnit.Replace('GetItemCount', function(itemName)
        return mockFoodItems[itemName] or 0
    end)

    WoWUnit.Replace('UseItemByName', function(itemName)
        fedPet = true
        usedItem = itemName
        return true
    end)

    WoWUnit.Replace('UnitExists', function(unit)
        return unit == "pet"
    end)

    -- Test feeding
    hunterModule:CheckPet()

    -- Verify results
    WoWUnit.AreEqual(true, fedPet, "Should have fed the pet")
    WoWUnit.AreEqual("Roasted Clefthoof", usedItem, "Should use preferred food first")
end

-- Test low food warning system
function Tests:TestLowFoodWarning()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    local notificationReceived = false
    local notificationMessage = ""

    -- Set up test state
    hunterModule.currentPet = mockPetData.TestBear
    hunterModule.settings.petProfiles[mockPetData.TestBear.name] = {
        family = mockPetData.TestBear.family,
        preferredFood = {"Smoked Salmon"}, -- Only 8 remaining
        lastFed = 0
    }
    hunterModule.settings.lowFoodThreshold = 10

    -- Mock functions
    WoWUnit.Replace('GetItemCount', function(itemName)
        return mockFoodItems[itemName] or 0
    end)

    -- Mock core notification system
    if Fizzure.ShowNotification then
        WoWUnit.Replace(Fizzure, 'ShowNotification', function(title, message, type, duration)
            notificationReceived = true
            notificationMessage = message
        end)
    end

    -- Test warning
    hunterModule:CheckFoodSupply()

    -- Verify warning was triggered
    WoWUnit.AreEqual(true, notificationReceived, "Should receive low food notification")
    WoWUnit.AreEqual(true, notificationMessage:find("8 remaining") ~= nil, "Should mention remaining count")
end

-- Test debug system integration
function Tests:TestDebugSystemIntegration()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Test debug API access
    WoWUnit.Exists(hunterModule.debugAPI, "Hunter module should have debug API access")
    WoWUnit.Exists(hunterModule.debugAPI.UseItemByName, "Debug API should have UseItemByName wrapper")
    WoWUnit.Exists(hunterModule.debugAPI.GetItemCount, "Debug API should have GetItemCount wrapper")

    -- Test debug mode callback
    WoWUnit.Exists(hunterModule.OnDebugToggle, "Hunter module should implement OnDebugToggle")

    -- Test debug mode toggle
    local debugCallbackReceived = false
    local originalCallback = hunterModule.OnDebugToggle
    hunterModule.OnDebugToggle = function(self, enabled, level)
        debugCallbackReceived = true
        originalCallback(self, enabled, level)
    end

    -- Toggle debug mode
    if Fizzure.debug and not Fizzure.debug.enabled then
        Fizzure:ToggleDebug("VERBOSE")
        WoWUnit.AreEqual(true, debugCallbackReceived, "Debug toggle should trigger module callback")
        Fizzure:ToggleDebug() -- Turn off
    end

    -- Restore original callback
    hunterModule.OnDebugToggle = originalCallback
end

-- Test performance with multiple operations
function Tests:TestPerformance()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    local startTime = GetTime()

    -- Mock required functions for performance test
    WoWUnit.Replace('UnitExists', function(unit) return unit == "pet" end)
    WoWUnit.Replace('GetPetHappiness', function() return 1, 100, 6 end)
    WoWUnit.Replace('GetItemCount', function() return 100 end)
    WoWUnit.Replace('UseItemByName', function() return true end)

    hunterModule.currentPet = mockPetData.TestWolf
    hunterModule.settings.autoFeed = true

    -- Run update cycle 100 times
    for i = 1, 100 do
        hunterModule:OnUpdate(0.1) -- Simulate 0.1 second updates
    end

    local endTime = GetTime()
    local totalTime = endTime - startTime

    -- Should complete quickly (less than 1 second for 100 operations)
    WoWUnit.AreEqual(true, totalTime < 1.0, "Update cycle should be performant")

    print("|cff00ff00Test Performance:|r 100 operations in " .. string.format("%.3f", totalTime) .. " seconds")
end

-- Test module enable/disable functionality
function Tests:TestModuleEnableDisable()
    WoWUnit.Exists(Fizzure.EnableModule, "Core should have EnableModule function")
    WoWUnit.Exists(Fizzure.DisableModule, "Core should have DisableModule function")

    local moduleName = "Hunter Pet Manager"
    local hunterModule = Fizzure.modules[moduleName]
    if not hunterModule then return end

    -- Test enable
    local enableResult = Fizzure:EnableModule(moduleName)
    WoWUnit.AreEqual(true, enableResult, "Module should enable successfully")
    WoWUnit.AreEqual(true, Fizzure.db.enabledModules[moduleName], "Module should be marked as enabled in database")

    -- Test disable
    local disableResult = Fizzure:DisableModule(moduleName)
    WoWUnit.AreEqual(true, disableResult, "Module should disable successfully")
    WoWUnit.AreEqual(false, Fizzure.db.enabledModules[moduleName], "Module should be marked as disabled in database")
end

-- Test category system
function Tests:TestCategorySystem()
    WoWUnit.Exists(Fizzure.moduleCategories, "Category system should exist")
    WoWUnit.Exists(Fizzure.moduleCategories["Class-Specific"], "Class-Specific category should exist")

    local classSpecific = Fizzure.moduleCategories["Class-Specific"]
    local hunterModule = classSpecific["Hunter Pet Manager"]
    WoWUnit.Exists(hunterModule, "Hunter module should be in Class-Specific category")

    -- Test category statistics
    local stats = Fizzure:GetCategoryStats()
    WoWUnit.AreEqual("string", type(stats), "Category stats should return string")
    WoWUnit.AreEqual(true, stats:find("Class-Specific") ~= nil, "Stats should include Class-Specific category")
end

-- Test MockEnvironment integration
function Tests:TestMockEnvironmentIntegration()
    if not MockEnv then
        print("|cffff8000Test Warning:|r MockEnvironment not available - skipping mock integration tests")
        return
    end

    WoWUnit.Exists(MockEnv, "MockEnvironment should be available")
    WoWUnit.Exists(MockEnv.EnableMocking, "MockEnv should have EnableMocking function")
    WoWUnit.Exists(MockEnv.RunTestScenario, "MockEnv should have RunTestScenario function")

    -- Test scenario integration
    MockEnv:EnableMocking()

    local scenarioResult = MockEnv:RunTestScenario("hungry_pet")
    -- Scenario should run without errors

    -- Test that hunter module responds to mock data
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if hunterModule then
        hunterModule:UpdateCurrentPet()
        WoWUnit.Exists(hunterModule.currentPet, "Hunter module should detect mock pet")
        if hunterModule.currentPet then
            WoWUnit.AreEqual("TestWolf", hunterModule.currentPet.name, "Should detect correct mock pet")
        end
    end

    MockEnv:DisableMocking()
end

-- Test error handling and edge cases
function Tests:TestErrorHandling()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Test feeding with no pet
    hunterModule.currentPet = nil
    local result = hunterModule:FeedPet() -- Should not crash
    -- Function should handle gracefully

    -- Test with invalid food data
    local originalCurrentPet = hunterModule.currentPet
    hunterModule.currentPet = {name = "InvalidPet", family = "InvalidFamily", level = 50}

    local compatibleFoods = hunterModule:GetCompatibleFoods()
    WoWUnit.AreEqual("table", type(compatibleFoods), "Should return table even for invalid pet family")
    WoWUnit.AreEqual(0, #compatibleFoods, "Should return empty table for invalid pet family")

    -- Test level checking with invalid data
    local levelCheck = hunterModule:IsFoodAppropriateLevel("NonexistentFood")
    WoWUnit.AreEqual(false, levelCheck, "Should return false for nonexistent food")

    -- Restore state
    hunterModule.currentPet = originalCurrentPet
end

-- Test quick status functionality
function Tests:TestQuickStatus()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Test with no pet
    hunterModule.currentPet = nil
    local status = hunterModule:GetQuickStatus()
    WoWUnit.AreEqual("string", type(status), "Should return string status")
    WoWUnit.AreEqual(true, status:find("No pet") ~= nil, "Should indicate no pet")

    -- Test with pet
    hunterModule.currentPet = mockPetData.TestWolf
    hunterModule.settings.petProfiles[mockPetData.TestWolf.name] = {
        family = mockPetData.TestWolf.family,
        preferredFood = {"Roasted Clefthoof"},
        lastFed = 0
    }

    WoWUnit.Replace('GetPetHappiness', function() return 3, 100, 6 end)
    WoWUnit.Replace('GetItemCount', function() return 10 end)

    status = hunterModule:GetQuickStatus()
    WoWUnit.AreEqual(true, status:find("TestWolf") ~= nil, "Should include pet name")
    WoWUnit.AreEqual(true, status:find("Happy") ~= nil, "Should include happiness status")
    WoWUnit.AreEqual(true, status:find("Food:") ~= nil, "Should include food count")
end

-- Test cleanup and resource management
function Tests:TestCleanup()
    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Test shutdown functionality
    WoWUnit.Exists(hunterModule.Shutdown, "Hunter module should have Shutdown method")

    -- Store original state
    local originalUpdateFrame = hunterModule.updateFrame
    local originalEventFrame = hunterModule.eventFrame
    local originalStatusFrame = hunterModule.statusFrame

    -- Test shutdown
    hunterModule:Shutdown()

    -- Verify cleanup (frames should be cleaned up)
    if originalUpdateFrame then
        -- Update frame should have OnUpdate cleared
        WoWUnit.AreEqual(nil, originalUpdateFrame:GetScript("OnUpdate"), "Update frame script should be cleared")
    end

    if originalEventFrame then
        -- Event frame should be unregistered (we can't easily test this without more complex mocking)
    end

    if originalStatusFrame then
        WoWUnit.AreEqual(false, originalStatusFrame:IsShown(), "Status frame should be hidden")
    end
end

-- Run comprehensive integration test
function Tests:TestFullIntegration()
    print("|cff00ff00Running Full Integration Test...|r")

    -- Enable MockEnvironment if available
    if MockEnv then
        MockEnv:EnableMocking()
        MockEnv:RunTestScenario("hungry_pet")
    end

    local hunterModule = Fizzure.modules["Hunter Pet Manager"]
    if not hunterModule then return end

    -- Enable debug mode
    if Fizzure.debug and not Fizzure.debug.enabled then
        Fizzure:ToggleDebug("VERBOSE")
    end

    -- Enable the module
    Fizzure:EnableModule("Hunter Pet Manager")
    WoWUnit.AreEqual(true, Fizzure.db.enabledModules["Hunter Pet Manager"], "Module should be enabled")

    -- Simulate some activity
    if hunterModule.currentPet then
        -- Test feeding cycle
        for i = 1, 5 do
            hunterModule:CheckPet()
            hunterModule:UpdateStatusFrame()
        end

        -- Test food supply check
        hunterModule:CheckFoodSupply()

        -- Test compatibility check
        hunterModule:CheckFoodCompatibility()
    end

    -- Test quick status
    local status = hunterModule:GetQuickStatus()
    WoWUnit.AreEqual("string", type(status), "Quick status should return string")

    -- Clean up
    if MockEnv and MockEnv.isActive then
        MockEnv:DisableMocking()
    end

    if Fizzure.debug.enabled then
        Fizzure:ToggleDebug()
    end

    print("|cff00ff00Full Integration Test Complete|r")
end

-- Summary function to run all tests
function Tests:RunAllTests()
    print("|cff00ff00=== Fizzure Test Suite Starting ===|r")

    local testMethods = {
        "TestCoreSystemLoaded",
        "TestModuleRegistration",
        "TestModuleSettings",
        "TestEnhancedPetDetection",
        "TestFoodCompatibilityWithLevels",
        "TestEnhancedAutoFeeding",
        "TestLowFoodWarning",
        "TestDebugSystemIntegration",
        "TestPerformance",
        "TestModuleEnableDisable",
        "TestCategorySystem",
        "TestMockEnvironmentIntegration",
        "TestErrorHandling",
        "TestQuickStatus",
        "TestCleanup",
        "TestFullIntegration"
    }

    local passed = 0
    local total = #testMethods

    for _, testName in ipairs(testMethods) do
        local success, err = pcall(function() self[testName](self) end)
        if success then
            passed = passed + 1
            print("|cff00ff00✓|r " .. testName)
        else
            print("|cffff0000✗|r " .. testName .. " - " .. tostring(err))
        end
    end

    print("|cff00ff00=== Test Results: " .. passed .. "/" .. total .. " passed ===|r")

    if passed == total then
        print("|cff00ff00All tests passed! Fizzure is ready for use.|r")
    else
        print("|cffff8000Some tests failed. Check the output above for details.|r")
    end
end

print("|cff00ff00Fizzure Enhanced Tests|r Loaded. Commands:")
print("  /wowunit Fizzure_Tests - Run individual tests")
print("  /script FizzureTests.RunAllTests() - Run complete test suite")