-- Fizzure.lua - Core modular framework with FIXED UI issues and clean flat design
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

-- Register a module
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

    -- Set module name reference
    moduleData.name = moduleName

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

    self.db.enabledModules[name] = true
    self:SaveSettings()

    if module.Enable then
        local success, err = pcall(module.Enable, module)
        if not success then
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

-- FIXED: Create minimap button (SINGLE BUTTON ONLY - prevent duplicates)
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

    -- Calculate tab width based on available space
    local availableWidth = 780  -- Leave some margin
    local categoryCount = 0
    for _ in pairs(self.moduleCategories) do categoryCount = categoryCount + 1 end

    local maxTabWidth = 120
    local minTabWidth = 80
    local tabWidth = math.max(minTabWidth, math.min(maxTabWidth, availableWidth / categoryCount))

    local tabIndex = 0
    for categoryName, _ in pairs(self.moduleCategories) do
        local tab = FizzureUI:CreateButton(tabContainer, categoryName, tabWidth, 25, nil, true)
        local xPos = tabIndex * (tabWidth + 2)

        -- FIXED: Handle category overflow by wrapping or scrolling
        if xPos + tabWidth > availableWidth then
            -- If we overflow, reduce tab width further
            tabWidth = math.max(60, (availableWidth - 10) / categoryCount)
            tab:SetWidth(tabWidth)
            xPos = tabIndex * (tabWidth + 2)
        end

        tab:SetPoint("LEFT", xPos, 0)

        tab:SetScript("OnClick", function()
            Fizzure:SelectCategory(categoryName)
        end)

        frame.categoryTabs[categoryName] = tab
        tabIndex = tabIndex + 1
    end

    -- Main content area with FIXED positioning
    local contentArea = CreateFrame("Frame", self:GetUniqueFrameName("ContentArea"), frame.content)
    contentArea:SetPoint("TOPLEFT", 0, -40)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 35)

    -- Left panel - Module list with FIXED width
    local moduleListPanel = FizzureUI:CreatePanel(contentArea, 250, 1, nil, true)
    moduleListPanel:SetPoint("TOPLEFT", 10, 0)
    moduleListPanel:SetPoint("BOTTOMLEFT", 10, 0)

    local moduleLabel = FizzureUI:CreateLabel(moduleListPanel, "Modules", "GameFontNormalLarge")
    moduleLabel:SetPoint("TOP", 0, -10)

    local moduleList = FizzureUI:CreateScrollFrame(moduleListPanel, 230, 1, 20, self:GetUniqueFrameName("ModuleScroll"))
    moduleList:SetPoint("TOPLEFT", 10, -30)
    moduleList:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.moduleList = moduleList

    -- Right panel - Module details with FIXED clearing
    local detailsPanel = FizzureUI:CreatePanel(contentArea, 1, 1, nil, true)
    detailsPanel:SetPoint("TOPLEFT", moduleListPanel, "TOPRIGHT", 10, 0)
    detailsPanel:SetPoint("BOTTOMRIGHT", -10, 0)

    local detailsLabel = FizzureUI:CreateLabel(detailsPanel, "Module Details", "GameFontNormalLarge")
    detailsLabel:SetPoint("TOP", 0, -10)
    frame.detailsLabel = detailsLabel

    -- FIXED: Details content area with proper naming
    local detailsContent = CreateFrame("ScrollFrame", self:GetUniqueFrameName("DetailsScroll"), detailsPanel, "UIPanelScrollFrameTemplate")
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

    -- FIXED: Status bar with proper positioning
    local statusBar = CreateFrame("Frame", self:GetUniqueFrameName("StatusBar"), frame.content)
    statusBar:SetHeight(30)
    statusBar:SetPoint("BOTTOMLEFT", 5, 5)
    statusBar:SetPoint("BOTTOMRIGHT", -5, 5)
    statusBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    statusBar:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    statusBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local statusText = FizzureUI:CreateLabel(statusBar, "Ready", "GameFontNormal")
    statusText:SetPoint("LEFT", 10, 0)
    frame.statusText = statusText

    -- Update module list function
    function frame:UpdateModuleList()
        Fizzure:PopulateModuleList()
    end

    self.frames.mainWindow = frame
    frame:Hide()
end

-- FIXED: Show module details with proper clearing and error handling
function Fizzure:ShowModuleDetails(moduleName, module)
    local frame = self.frames.mainWindow
    local panel = frame.detailsContent
    if not panel then return end

    -- FIXED: ALWAYS clear existing detail widgets FIRST
    if frame.currentDetailWidgets then
        for _, widget in ipairs(frame.currentDetailWidgets) do
            if widget and widget.Hide then
                widget:Hide()
            end
            if widget and widget.SetParent then
                widget:SetParent(nil)
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

    -- FIXED: Enable checkbox with proper scope
    local enableCheckContainer = FizzureUI:CreateCheckBox(panel, "Enable Module",
            self.db.enabledModules[moduleName], function(checked)
                if checked then
                    if not Fizzure:EnableModule(moduleName) then
                        enableCheckContainer:SetChecked(false)
                        Fizzure:ShowNotification("Enable Failed", "Could not enable " .. moduleName, "error", 3)
                    else
                        Fizzure:ShowNotification("Module Enabled", moduleName .. " has been enabled", "success", 2)
                        Fizzure:ShowModuleDetails(moduleName, module)
                    end
                else
                    if not Fizzure:DisableModule(moduleName) then
                        enableCheckContainer:SetChecked(true)
                        Fizzure:ShowNotification("Disable Failed", "Could not disable " .. moduleName, "error", 3)
                    else
                        Fizzure:ShowNotification("Module Disabled", moduleName .. " has been disabled", "info", 2)
                        Fizzure:ShowModuleDetails(moduleName, module)
                    end
                end
                frame:UpdateModuleList()
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

        -- FIXED: Safely call CreateConfigUI with error handling
        local success, newY = pcall(function()
            return module:CreateConfigUI(panel, 20, y)
        end)

        if success and newY then
            y = newY
        else
            local errorLabel = FizzureUI:CreateLabel(panel, "Configuration error: " .. tostring(newY or "Unknown error"), "GameFontNormalSmall")
            errorLabel:SetPoint("TOPLEFT", 20, y)
            errorLabel:SetTextColor(1, 0.5, 0.5)
            table.insert(frame.currentDetailWidgets, errorLabel)
            y = y - 20
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

    -- Update tab appearance
    for name, tab in pairs(frame.categoryTabs) do
        if name == categoryName then
            tab:SetBackdropColor(0.2, 0.6, 1, 1)
        else
            tab:SetBackdropColor(0.2, 0.2, 0.2, 1)
        end
    end

    -- Update module list
    self:PopulateModuleList()
end

-- Populate module list for selected category
function Fizzure:PopulateModuleList()
    local frame = self.frames.mainWindow
    if not frame or not frame.moduleList then return end

    local content = frame.moduleList.content
    local category = frame.selectedCategory or "Class-Specific"

    -- Clear existing list
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
            child:SetParent(nil)
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
        PlaySound("TellMessage")
    end
end

-- Debug system
function Fizzure:InitializeDebugSystem()
    if not self.db.debug then
        self.db.debug = defaultSettings.debug
    end

    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level

    if self.db.debug.showDebugFrame then
        self:CreateDebugFrame()
    end
end

function Fizzure:CreateDebugFrame()
    -- Debug frame implementation
    local frame = FizzureUI:CreateWindow(self:GetUniqueFrameName("DebugFrame"), "Fizzure Debug", 500, 300, nil, true)
    frame:SetPoint("TOPLEFT", 50, -50)

    self.frames.debugFrame = frame
    frame:Hide()
end

-- Get module count
function Fizzure:GetModuleCount()
    local count = 0
    for _ in pairs(self.modules) do
        count = count + 1
    end
    return count
end

-- Initialize on load
Fizzure:Initialize()

-- Slash commands
SLASH_FIZZURE1 = "/fizz"
SLASH_FIZZURE2 = "/fizzure"
SlashCmdList["FIZZURE"] = function(msg)
    local command, arg1, arg2 = strsplit(" ", string.lower(msg))

    if command == "" or command == "show" then
        Fizzure:ToggleMainWindow()
    elseif command == "enable" and arg1 then
        if Fizzure:EnableModule(arg1) then
            print("|cff00ff00Fizzure:|r Enabled module: " .. arg1)
        else
            print("|cffff0000Fizzure:|r Failed to enable module: " .. arg1)
        end
    elseif command == "disable" and arg1 then
        if Fizzure:DisableModule(arg1) then
            print("|cff00ff00Fizzure:|r Disabled module: " .. arg1)
        else
            print("|cffff0000Fizzure:|r Failed to disable module: " .. arg1)
        end
    elseif command == "list" then
        print("|cff00ff00Fizzure Modules:|r")
        for categoryName, modules in pairs(Fizzure.moduleCategories) do
            if next(modules) then
                print("  |cffFFD700" .. categoryName .. ":|r")
                for moduleName, module in pairs(modules) do
                    local status = Fizzure.db.enabledModules[moduleName] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                    print("    " .. moduleName .. ": " .. status)
                end
            end
        end
    elseif command == "save" then
        Fizzure:SaveSettings()
        print("|cff00ff00Fizzure:|r Settings saved manually")
    else
        print("|cff00ff00Fizzure Commands:|r")
        print("  /fizz - Open control center")
        print("  /fizz enable <module> - Enable module")
        print("  /fizz disable <module> - Disable module")
        print("  /fizz list - List all modules")
        print("  /fizz save - Manually save settings")
    end
end