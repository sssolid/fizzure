-- Fizzure.lua - Core modular framework with ALL ISSUES FIXED for WoW 3.3.5
local addonName = "Fizzure"
local Fizzure = {}
_G[addonName] = Fizzure

-- Core variables
Fizzure.modules = {}
Fizzure.moduleCategories = {
    ["Class-Specific"] = {},
    ["General"] = {},
    ["Combat"] = {},
    ["UI/UX"] = {},
    ["Economy"] = {},
    ["Social"] = {},
    ["Action Bars"] = {}
}

Fizzure.frames = {}
Fizzure.notifications = {}
Fizzure.debug = {
    enabled = false,
    level = "DRY_RUN",
    logHistory = {},
    maxLogHistory = 100
}

-- Counter for unique frame names
Fizzure.frameCounter = 1

-- Default settings
local defaultSettings = {
    enabledModules = {},
    moduleSettings = {},
    notifications = {
        enabled = true,
        sound = true,
        position = { "CENTER", 0, 100 }
    },
    minimap = {
        show = true,
        minimapPos = 225
    },
    debug = {
        enabled = false,
        level = "DRY_RUN",
        showDebugFrame = true,
        logToChat = false
    },
    ui = {
        categorizeModules = true,
        compactView = false,
        autoSelectCategory = true,
        flatDesign = true
    }
}

-- FIXED: Debug logging function (defined early)
function Fizzure:LogDebug(level, message, module)
    if not self.debug.enabled then return end

    local timestamp = date("%H:%M:%S")
    local logEntry = string.format("[%s] %s: %s - %s", timestamp, level, module or "Core", message)

    table.insert(self.debug.logHistory, logEntry)

    -- Keep log history within limits
    if #self.debug.logHistory > self.debug.maxLogHistory then
        table.remove(self.debug.logHistory, 1)
    end

    if self.db and self.db.debug and self.db.debug.logToChat then
        print("|cff888888Fizzure Debug:|r " .. logEntry)
    end

    -- Update debug window if open
    if self.frames.debugFrame and self.frames.debugFrame:IsShown() then
        self:RefreshDebugLog()
    end
end

-- Initialize core system
function Fizzure:Initialize()
    -- Load saved variables
    self:LoadSettings()

    -- Create main frame
    local mainFrame = CreateFrame("Frame", "FizzureMainFrame", UIParent)
    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:RegisterEvent("PLAYER_LOGIN")
    mainFrame:RegisterEvent("PLAYER_LOGOUT")
    mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mainFrame:SetScript("OnEvent", function(self, event, ...) Fizzure:OnEvent(event, ...) end)

    -- Initialize UI components
    self:CreateMinimapButton()
    self:CreateMainWindow()
    self:CreateNotificationSystem()
    self:InitializeDebugSystem()

    -- Periodic save timer (every 30 seconds)
    self.saveTimer = FizzureCommon:NewTicker(30, function()
        self:SaveSettings()
    end)

    if _G.FizzureSecure and type(_G.FizzureSecure.Initialize) == "function" then
        _G.FizzureSecure:Initialize()
    end

    -- After loading settings inside Fizzure:Initialize()
    for name, module in pairs(self.modules) do
        if self.db.enabledModules[name] and not module._initialized and type(module.Initialize) == "function" then
            pcall(module.Initialize, module)
            module._initialized = true
        end
    end

    print("|cff00ff00Fizzure|r Core System Loaded")
end

-- Get unique frame name
function Fizzure:GetUniqueFrameName(prefix)
    local name = (prefix or "FizzureFrame") .. self.frameCounter
    self.frameCounter = self.frameCounter + 1
    return name
end

-- Load settings with proper defaults and persistence
function Fizzure:LoadSettings()
    if not FizzureDB then
        FizzureDB = FizzureCommon:TableCopy(defaultSettings)
        print("|cff00ff00Fizzure:|r Created new database")
    else
        -- Merge with defaults to ensure all fields exist
        FizzureDB = FizzureCommon:TableMerge(FizzureCommon:TableCopy(defaultSettings), FizzureDB)
        print("|cff00ff00Fizzure:|r Loaded existing database")
    end

    self.db = FizzureDB

    -- Apply settings to debug system
    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level
end

-- Save settings to disk
function Fizzure:SaveSettings()
    if not FizzureDB then return end

    -- Force update any pending changes
    for key, value in pairs(self.db) do
        FizzureDB[key] = value
    end
end

-- Event handler
function Fizzure:OnEvent(event, addonName)
    if event == "ADDON_LOADED" and addonName == "Fizzure" then
        self:LoadModules()
    elseif event == "PLAYER_LOGIN" then
        self:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        self:SaveSettings()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Additional setup after entering world
        for moduleName, module in pairs(self.modules) do
            if self.db.enabledModules[moduleName] and module.OnWorldEnter then
                local success, err = pcall(module.OnWorldEnter, module)
                if not success then
                    print("|cffff0000Fizzure:|r Error in " .. moduleName .. ".OnWorldEnter: " .. tostring(err))
                end
            end
        end
    end
end

-- Load and register modules
function Fizzure:LoadModules()
    -- Modules are auto-loaded by the TOC, just need to initialize them
    for moduleName, module in pairs(self.modules) do
        if module.Initialize then
            local success, err = pcall(module.Initialize, module)
            if not success then
                print("|cffff0000Fizzure:|r Failed to initialize " .. moduleName .. ": " .. tostring(err))
            end
        end
    end
end

-- FIXED: Register a module with proper Fizzure reference
function Fizzure:RegisterModule(moduleName, moduleData)
    if not moduleName or not moduleData then
        print("|cffff0000Fizzure:|r Invalid module registration")
        return false
    end

    -- Set default category if not specified
    local category = moduleData.category or "General"
    if not self.moduleCategories[category] then
        self.moduleCategories[category] = {}
    end

    -- Register the module
    self.modules[moduleName] = moduleData
    self.moduleCategories[category][moduleName] = moduleData

    -- CRITICAL FIX: Set module name and Fizzure reference
    moduleData.name = moduleName
    moduleData.Fizzure = self

    print("|cff00ff00Fizzure:|r Registered module: " .. moduleName .. " (" .. category .. ")")
    return true
end

-- Enable a module
function Fizzure:EnableModule(name)
    local module = self.modules[name]
    if not module then return false end

    -- Check dependencies
    if module.dependencies then
        for _, dep in pairs(module.dependencies) do
            if not self.db.enabledModules[dep] then
                print("|cffff0000Fizzure:|r Cannot enable " .. name .. " - missing dependency: " .. dep)
                return false
            end
        end
    end

    -- Mark enabled in DB
    self.db.enabledModules[name] = true
    self:SaveSettings()

    -- >>> ADD THIS: initialize the module exactly once <<<
    if not module._initialized and type(module.Initialize) == "function" then
        local ok, err = pcall(module.Initialize, module)
        if not ok then
            print("|cffff0000Fizzure:|r Failed to initialize " .. name .. ": " .. tostring(err))
            self.db.enabledModules[name] = false
            self:SaveSettings()
            return false
        end
        module._initialized = true
    end
    -- <<< end added block

    -- Optional: per-enable hook if the module provides it
    if type(module.Enable) == "function" then
        local ok, err = pcall(module.Enable, module)
        if not ok then
            print("|cffff0000Fizzure:|r Failed to enable " .. name .. ": " .. tostring(err))
            self.db.enabledModules[name] = false
            self:SaveSettings()
            return false
        end
    end

    return true
end

-- Disable a module
function Fizzure:DisableModule(name)
    local module = self.modules[name]
    if not module then return false end

    -- Check if other modules depend on this one
    for moduleName, moduleData in pairs(self.modules) do
        if moduleData.dependencies then
            for _, dep in pairs(moduleData.dependencies) do
                if dep == name and self.db.enabledModules[moduleName] then
                    print("|cffff0000Fizzure:|r Cannot disable " .. name .. " - " .. moduleName .. " depends on it")
                    return false
                end
            end
        end
    end

    self.db.enabledModules[name] = false
    self:SaveSettings()

    if module.Shutdown then
        local success, err = pcall(module.Shutdown, module)
        if not success then
            print("|cffff0000Fizzure:|r Error shutting down " .. name .. ": " .. tostring(err))
        end
    end

    return true
end

-- Get module settings
function Fizzure.GetModuleSettings(name)
    return (FizzureDB and FizzureDB.moduleSettings and FizzureDB.moduleSettings[name]) or {}
end

-- Set module settings
function Fizzure:SetModuleSettings(moduleName, settings)
    local module = self.modules[moduleName]
    if module and module.ValidateSettings then
        if not module:ValidateSettings(settings) then
            return false
        end
    end

    self.db.moduleSettings[moduleName] = settings
    self:SaveSettings()
    self:SyncFrameworkSettings(moduleName, settings)
    return true
end

-- Sync settings between framework and modules
function Fizzure:SyncFrameworkSettings(moduleName, moduleSettings)
    -- Check for common settings that should be synced
    if moduleSettings.notifications then
        for key, value in pairs(moduleSettings.notifications) do
            if self.db.notifications[key] ~= nil then
                self.db.notifications[key] = value
            end
        end
    end

    if moduleSettings.debug then
        for key, value in pairs(moduleSettings.debug) do
            if self.db.debug[key] ~= nil then
                self.db.debug[key] = value
                self.debug[key] = value
            end
        end
    end

    self:SaveSettings()
end

-- FIXED: Create minimap button (prevent duplicates)
function Fizzure:CreateMinimapButton()
    -- Check if button already exists and remove it
    if self.frames.minimapButton then
        self.frames.minimapButton:Hide()
        self.frames.minimapButton:SetParent(nil)
        self.frames.minimapButton = nil
    end

    -- Remove any existing buttons by name to prevent duplicates
    local existingButton = _G["FizzureMinimapButton"]
    if existingButton then
        existingButton:Hide()
        existingButton:SetParent(nil)
    end

    local button = CreateFrame("Button", "FizzureMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    button:SetPushedTexture("Interface\\Icons\\INV_Misc_Gear_02")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function updatePosition()
        local angle = math.rad(self.db.minimap.minimapPos or 225)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    updatePosition()

    button:SetScript("OnClick", function(self, clickButton)
        if clickButton == "LeftButton" then
            Fizzure:ToggleMainWindow()
        elseif clickButton == "RightButton" then
            Fizzure:ShowQuickStatus()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local angle = math.atan2(self:GetTop() - Minimap:GetTop(), self:GetLeft() - Minimap:GetLeft())
        Fizzure.db.minimap.minimapPos = math.deg(angle)
        Fizzure:SaveSettings()
        updatePosition()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Fizzure", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open Manager", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Quick Status", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    self.frames.minimapButton = button
end

-- FIXED: Create main window with proper layout and category overflow handling
function Fizzure:CreateMainWindow()
    local frame = FizzureUI:CreateWindow("FizzureControlCenter", "Fizzure Control Center", 800, 600, nil, true)

    -- Store reference to current detail widgets for proper clearing
    frame.currentDetailWidgets = {}

    -- Category tabs with FIXED overflow handling
    frame.categoryTabs = {}
    frame.selectedCategory = "Class-Specific"

    local tabContainer = CreateFrame("Frame", self:GetUniqueFrameName("TabContainer"), frame.content)
    tabContainer:SetHeight(30)
    tabContainer:SetPoint("TOPLEFT", 0, -5)
    tabContainer:SetPoint("TOPRIGHT", 0, -5)

    -- FIXED: Calculate tab width based on available space with proper overflow handling
    local availableWidth = 780 -- Leave some margin
    local categoryList = {}
    for categoryName, _ in pairs(self.moduleCategories) do
        table.insert(categoryList, categoryName)
    end
    table.sort(categoryList) -- Consistent ordering
    local categoryCount = #categoryList

    local maxTabWidth = 110
    local minTabWidth = 70
    local tabWidth = math.max(minTabWidth, math.min(maxTabWidth, math.floor(availableWidth / categoryCount) - 2))

    for i, categoryName in ipairs(categoryList) do
        local tab = FizzureUI:CreateButton(tabContainer, categoryName, tabWidth, 25, nil, true)
        local xPos = (i - 1) * (tabWidth + 2)

        -- FIXED: Ensure no overflow by clamping position
        if xPos + tabWidth > availableWidth then
            -- Reduce all tab widths if needed
            tabWidth = math.floor((availableWidth - 10) / categoryCount)
            for j = 1, i - 1 do
                if frame.categoryTabs[categoryList[j]] then
                    frame.categoryTabs[categoryList[j]]:SetWidth(tabWidth)
                    frame.categoryTabs[categoryList[j]]:SetPoint("LEFT", (j - 1) * (tabWidth + 2), 0)
                end
            end
            xPos = (i - 1) * (tabWidth + 2)
        end

        tab:SetPoint("LEFT", xPos, 0)

        tab:SetScript("OnClick", function()
            Fizzure:SelectCategory(categoryName)
        end)

        frame.categoryTabs[categoryName] = tab
    end

    -- Main content area with proper positioning
    local contentArea = CreateFrame("Frame", self:GetUniqueFrameName("ContentArea"), frame.content)
    contentArea:SetPoint("TOPLEFT", 0, -40)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 35)

    -- Left panel - Module list
    local moduleListPanel = FizzureUI:CreatePanel(contentArea, 250, 1, nil, true)
    moduleListPanel:SetPoint("TOPLEFT", 10, 0)
    moduleListPanel:SetPoint("BOTTOMLEFT", 10, 0)

    local moduleLabel = FizzureUI:CreateLabel(moduleListPanel, "Modules", "GameFontNormalLarge")
    moduleLabel:SetPoint("TOP", 0, -10)

    local moduleList = FizzureUI:CreateScrollFrame(moduleListPanel, 230, 1, 20, self:GetUniqueFrameName("ModuleScroll"))
    moduleList:SetPoint("TOPLEFT", 10, -30)
    moduleList:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.moduleList = moduleList

    -- Right panel - Module details
    local detailsPanel = FizzureUI:CreatePanel(contentArea, 1, 1, nil, true)
    detailsPanel:SetPoint("TOPLEFT", moduleListPanel, "TOPRIGHT", 10, 0)
    detailsPanel:SetPoint("BOTTOMRIGHT", -10, 0)

    local detailsLabel = FizzureUI:CreateLabel(detailsPanel, "Module Details", "GameFontNormalLarge")
    detailsLabel:SetPoint("TOP", 0, -10)
    frame.detailsLabel = detailsLabel

    -- Details content area
    local detailsContent = CreateFrame("ScrollFrame", self:GetUniqueFrameName("DetailsScroll"), detailsPanel,
        "UIPanelScrollFrameTemplate")
    detailsContent:SetPoint("TOPLEFT", 10, -30)
    detailsContent:SetPoint("BOTTOMRIGHT", -30, 10)

    local detailsScrollChild = CreateFrame("Frame", self:GetUniqueFrameName("DetailsChild"), detailsContent)
    detailsScrollChild:SetSize(400, 1)
    detailsContent:SetScrollChild(detailsScrollChild)

    detailsContent:EnableMouseWheel(true)
    detailsContent:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 30), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)

    frame.detailsContent = detailsScrollChild
    frame.detailsScrollFrame = detailsContent

    -- FIXED: Status bar with DEBUG and Reload UI buttons
    local statusBar = CreateFrame("Frame", self:GetUniqueFrameName("StatusBar"), frame.content)
    statusBar:SetHeight(30)
    statusBar:SetPoint("BOTTOMLEFT", 5, 5)
    statusBar:SetPoint("BOTTOMRIGHT", -5, 5)
    statusBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    statusBar:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    statusBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local statusText = FizzureUI:CreateLabel(statusBar, "Ready", "GameFontNormal")
    statusText:SetPoint("LEFT", 10, 0)
    frame.statusText = statusText

    -- FIXED: Add DEBUG button back
    local debugButton = FizzureUI:CreateButton(statusBar, "DEBUG", 60, 20, function()
        Fizzure:ToggleDebugMode()
    end, true)
    debugButton:SetPoint("RIGHT", -80, 0)

    -- FIXED: Add Reload UI button back
    local reloadButton = FizzureUI:CreateButton(statusBar, "Reload UI", 70, 20, function()
        ReloadUI()
    end, true)
    reloadButton:SetPoint("RIGHT", -10, 0)

    -- Update module list function
    function frame:UpdateModuleList()
        Fizzure:PopulateModuleList()
    end

    self.frames.mainWindow = frame
    frame:Hide()
end

-- FIXED: Show module details with WORKING error display system
function Fizzure:ShowModuleDetails(moduleName, module)
    local frame = self.frames.mainWindow
    local panel = frame.detailsContent
    if not panel then return end

    -- HARD CLEAR of existing content in the details scroll child
    do
        -- Frames (children)
        local children = { panel:GetChildren() }
        for _, child in ipairs(children) do
            if child then
                if child.Hide then child:Hide() end
                if child.SetParent then child:SetParent(nil) end
            end
        end
        -- Regions (e.g., FontStrings, Textures) that modules might have created directly
        local regions = { panel:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.Hide then region:Hide() end
        end
    end

    -- FIXED: SAFELY clear existing detail widgets FIRST
    if frame.currentDetailWidgets then
        for _, widget in ipairs(frame.currentDetailWidgets) do
            if widget then
                -- Only call Hide if the method exists
                if widget.Hide then
                    widget:Hide()
                end
                -- Only call SetParent if it's a frame (not a font string)
                if widget.SetParent and widget.GetObjectType and widget:GetObjectType() ~= "FontString" then
                    widget:SetParent(nil)
                end
            end
        end
    end
    frame.currentDetailWidgets = {}

    local y = -10

    -- Module title
    local title = FizzureUI:CreateLabel(panel, moduleName, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, y)
    table.insert(frame.currentDetailWidgets, title)
    y = y - 30

    -- Module info
    local info = FizzureUI:CreateLabel(panel,
        string.format("Version %s by %s", module.version or "1.0", module.author or "Unknown"))
    info:SetPoint("TOP", 0, y)
    table.insert(frame.currentDetailWidgets, info)
    y = y - 30

    -- Declare first so the upvalue exists for the callback
    local enableCheckContainer

    -- Enable checkbox
    enableCheckContainer = FizzureUI:CreateCheckBox(panel, "Enable Module",
        not not self.db.enabledModules[moduleName],
        function(checked)
            if checked then
                if not Fizzure:EnableModule(moduleName) then
                    enableCheckContainer:SetChecked(false)
                    Fizzure:ShowNotification("Enable Failed", "Could not enable " .. moduleName, "error", 3)
                else
                    Fizzure:ShowNotification("Module Enabled", moduleName .. " has been enabled", "success", 2)
                    Fizzure:ShowModuleDetails(moduleName, module)
                    if frame and frame.UpdateModuleList then frame:UpdateModuleList() end
                end
            else
                if not Fizzure:DisableModule(moduleName) then
                    enableCheckContainer:SetChecked(true)
                    Fizzure:ShowNotification("Disable Failed", "Could not disable " .. moduleName, "error", 3)
                else
                    Fizzure:ShowNotification("Module Disabled", moduleName .. " has been disabled", "info", 2)
                    Fizzure:ShowModuleDetails(moduleName, module)
                    if frame and frame.UpdateModuleList then frame:UpdateModuleList() end
                end
            end
        end)
    enableCheckContainer:SetPoint("TOPLEFT", 20, y)
    table.insert(frame.currentDetailWidgets, enableCheckContainer)
    y = y - 40

    -- Module configuration section
    if module.CreateConfigUI then
        local configLabel = FizzureUI:CreateLabel(panel, "Module Configuration:", "GameFontNormal")
        configLabel:SetPoint("TOPLEFT", 20, y)
        table.insert(frame.currentDetailWidgets, configLabel)
        y = y - 25

        if not self.db.enabledModules[moduleName] then
            local disabledLabel = FizzureUI:CreateLabel(panel, "(Enable module to configure)", "GameFontNormalSmall")
            disabledLabel:SetPoint("TOPLEFT", 20, y)
            disabledLabel:SetTextColor(0.7, 0.7, 0.7)
            table.insert(frame.currentDetailWidgets, disabledLabel)
            y = y - 25
        end

        -- FIXED: Call CreateConfigUI with PROPER error display
        local success, newY = pcall(function()
            return module:CreateConfigUI(panel, 20, y)
        end)

        if success and newY then
            y = newY
        else
            -- FIXED: Create FULL error display in chat AND show button
            local fullError = tostring(newY or "Unknown error")
            print("|cffff0000=== FULL MODULE ERROR ===|r")
            print("|cffff0000Module:|r " .. moduleName)
            print("|cffff0000Error:|r " .. fullError)
            print("|cffff0000=========================|r")

            -- Create error button for details pane
            local errorButton = FizzureUI:CreateButton(panel, "ERROR: " .. moduleName .. " (See Chat)", 400, 20,
                function()
                    print("|cffff0000=== FULL MODULE ERROR ===|r")
                    print("|cffff0000Module:|r " .. moduleName)
                    print("|cffff0000Error:|r " .. fullError)
                    print("|cffff0000=========================|r")
                end, true)
            errorButton:SetPoint("TOPLEFT", 20, y)
            errorButton:SetBackdropColor(0.8, 0.2, 0.2, 0.8)
            table.insert(frame.currentDetailWidgets, errorButton)
            y = y - 30
        end
    end

    -- Update scroll area
    local totalHeight = math.abs(y) + 50
    panel:SetHeight(math.max(totalHeight, 300))
    if frame.detailsScrollFrame.UpdateScrollChildHeight then
        frame.detailsScrollFrame:UpdateScrollChildHeight()
    end
end

-- Select category
function Fizzure:SelectCategory(categoryName)
    local frame = self.frames.mainWindow
    if not frame then return end

    frame.selectedCategory = categoryName

    for name, tab in pairs(frame.categoryTabs) do
        if name == categoryName then
            -- selected
            tab:SetBackdropColor(0.2, 0.6, 1, 1)
            if tab.UpdateOriginalColor then
                tab:UpdateOriginalColor({0.2, 0.6, 1, 1}, {0.3, 0.3, 0.35, 1})
            end
        else
            -- not selected
            tab:SetBackdropColor(0.2, 0.2, 0.2, 1)
            if tab.UpdateOriginalColor then
                tab:UpdateOriginalColor({0.2, 0.2, 0.2, 1}, {0.3, 0.3, 0.35, 1})
            end
        end
    end

    self:PopulateModuleList()
end

-- FIXED: Populate module list for selected category with proper clearing
function Fizzure:PopulateModuleList()
    local frame = self.frames.mainWindow
    if not frame or not frame.moduleList then return end

    local content = frame.moduleList.content
    local category = frame.selectedCategory or "Class-Specific"

    -- FIXED: Clear existing list properly
    local children = { content:GetChildren() }
    for _, child in ipairs(children) do
        if child then
            child:Hide()
            -- Only call SetParent on frames, not font strings
            if child.SetParent and child.GetObjectType and child:GetObjectType() ~= "FontString" then
                child:SetParent(nil)
            end
        end
    end

    local y = -5
    local modules = self.moduleCategories[category] or {}

    for moduleName, module in pairs(modules) do
        local button = FizzureUI:CreateButton(content, moduleName, 200, 22, nil, true)
        button:SetPoint("TOPLEFT", 10, y)

        -- Color based on enabled state
        if self.db.enabledModules[moduleName] then
            button:SetBackdropColor(0.2, 0.8, 0.2, 0.8)
        else
            button:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        end

        -- FIXED: Proper button highlighting that gets cleared
        button:SetScript("OnEnter", function(self)
            self.originalColor = { self:GetBackdropColor() }
            self:SetBackdropColor(0.3, 0.7, 1, 1)
        end)

        button:SetScript("OnLeave", function(self)
            if self.originalColor then
                self:SetBackdropColor(unpack(self.originalColor))
            else
                -- Fallback to determine color based on enabled state
                if Fizzure.db.enabledModules[moduleName] then
                    self:SetBackdropColor(0.2, 0.8, 0.2, 0.8)
                else
                    self:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
                end
            end
        end)

        button:SetScript("OnClick", function()
            Fizzure:ShowModuleDetails(moduleName, module)
        end)

        y = y - 25
    end

    -- Update scroll height
    content:SetHeight(math.max(math.abs(y), 100))
end

-- Toggle main window
function Fizzure:ToggleMainWindow()
    local frame = self.frames.mainWindow
    if frame:IsShown() then
        frame:Hide()
    else
        frame:UpdateModuleList()
        frame:Show()
    end
end

-- FIXED: Toggle debug mode and show debug window
function Fizzure:ToggleDebugMode()
    self.debug.enabled = not self.debug.enabled
    self.db.debug.enabled = self.debug.enabled
    self:SaveSettings()

    local status = self.debug.enabled and "enabled" or "disabled"
    print("|cff00ff00Fizzure:|r Debug mode " .. status)

    if self.frames.mainWindow and self.frames.mainWindow.statusText then
        self.frames.mainWindow.statusText:SetText("Debug " .. status)
    end

    -- Show/hide debug window
    if self.debug.enabled then
        self:ShowDebugWindow()
    else
        self:HideDebugWindow()
    end
end

-- Quick status
function Fizzure:ShowQuickStatus()
    local text = ""
    local enabledCount = 0

    for moduleName, module in pairs(self.modules) do
        if self.db.enabledModules[moduleName] then
            enabledCount = enabledCount + 1
            if module.GetQuickStatus then
                text = text .. moduleName .. ": " .. module:GetQuickStatus() .. "\n"
            end
        end
    end

    if text == "" then
        text = "No modules with status enabled"
    end

    FizzureUI:ShowToast("Fizzure Status (" .. enabledCount .. " modules)\n" .. text, 5, "info")
end

-- Player login handler
function Fizzure:OnPlayerLogin()
    -- Enable modules marked as enabled
    for moduleName, _ in pairs(self.db.enabledModules) do
        if self.db.enabledModules[moduleName] then
            self:EnableModule(moduleName)
        end
    end
end

-- Notification system
function Fizzure:CreateNotificationSystem()
    local container = FizzureUI:CreateFrame("Frame", self:GetUniqueFrameName("NotificationContainer"), UIParent)
    container:SetSize(300, 400)
    container:SetPoint("CENTER", 0, 100)
    container:SetFrameStrata("DIALOG")
    self.frames.notificationContainer = container
end

function Fizzure:ShowNotification(title, message, type, duration)
    if not self.db.notifications.enabled then return end

    FizzureUI:ShowToast(title .. "\n" .. message, duration, type)

    if self.db.notifications.sound then
        PlaySound(3081, "master")
    end
end

-- FIXED: Debug system initialization (no early LogDebug call)
function Fizzure:InitializeDebugSystem()
    if not self.db.debug then
        self.db.debug = defaultSettings.debug
    end

    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level

    -- Initialize log history if not exists
    if not self.debug.logHistory then
        self.debug.logHistory = {}
    end

    -- Now it's safe to log
    self:LogDebug("INFO", "Debug system initialized", "Core")

    if self.db.debug.showDebugFrame and self.debug.enabled then
        self:ShowDebugWindow()
    end
end

-- Debug window functions
function Fizzure:ShowDebugWindow()
    if not self.frames.debugFrame then
        self:CreateDebugWindow()
    end
    self.frames.debugFrame:Show()
end

function Fizzure:HideDebugWindow()
    if self.frames.debugFrame then
        self.frames.debugFrame:Hide()
    end
end

function Fizzure:CreateDebugWindow()
    local frame = FizzureUI:CreateWindow(self:GetUniqueFrameName("DebugFrame"), "Fizzure Debug Console", 600, 400, nil,
        true)
    frame:SetPoint("TOPLEFT", 50, -50)

    -- Debug log display
    local logScrollFrame = FizzureUI:CreateScrollFrame(frame.content, 580, 300, 20, self:GetUniqueFrameName("DebugLog"))
    logScrollFrame:SetPoint("TOPLEFT", 10, -10)

    local logText = FizzureUI:CreateLabel(logScrollFrame.content, "", "GameFontNormalSmall")
    logText:SetPoint("TOPLEFT", 5, -5)
    logText:SetWidth(550)
    logText:SetJustifyH("LEFT")

    frame.logText = logText
    frame.logScrollFrame = logScrollFrame

    -- Control buttons
    local clearButton = FizzureUI:CreateButton(frame.content, "Clear Log", 80, 25, function()
        Fizzure:ClearDebugLog()
    end, true)
    clearButton:SetPoint("BOTTOMLEFT", 10, 10)

    local refreshButton = FizzureUI:CreateButton(frame.content, "Refresh", 80, 25, function()
        Fizzure:RefreshDebugLog()
    end, true)
    refreshButton:SetPoint("BOTTOMLEFT", 100, 10)

    self.frames.debugFrame = frame
    self:RefreshDebugLog()
end

function Fizzure:RefreshDebugLog()
    if not self.frames.debugFrame or not self.frames.debugFrame.logText then return end

    local logContent = table.concat(self.debug.logHistory, "\n")
    self.frames.debugFrame.logText:SetText(logContent)

    -- Scroll to bottom
    local scrollFrame = self.frames.debugFrame.logScrollFrame
    if scrollFrame then
        scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
    end
end

function Fizzure:ClearDebugLog()
    self.debug.logHistory = {}
    self:RefreshDebugLog()
    self:LogDebug("INFO", "Debug log cleared", "Debug")
end

-- Initialize the addon
Fizzure:Initialize()
