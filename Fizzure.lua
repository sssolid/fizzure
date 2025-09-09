-- Fizzure.lua - Refactored Core Framework with Lifecycle Management
local addonName = "Fizzure"
local Fizzure = {}
_G[addonName] = Fizzure

-- Core variables
Fizzure.modules = {}
Fizzure.moduleManifests = {}
Fizzure.dependencyGraph = {}
Fizzure.initializationOrder = {}
Fizzure.moduleStates = {}
Fizzure.frames = {}
Fizzure.ui = {}

-- Module states
local MODULE_STATES = {
    REGISTERED = "REGISTERED",
    VALIDATED = "VALIDATED", 
    INITIALIZED = "INITIALIZED",
    UI_READY = "UI_READY",
    ENABLED = "ENABLED",
    DISABLED = "DISABLED",
    FAILED = "FAILED"
}

-- Framework phases
local FRAMEWORK_PHASES = {
    LOADING = "LOADING",
    REGISTRATION = "REGISTRATION",
    VALIDATION = "VALIDATION",
    CORE_INIT = "CORE_INIT",
    UI_CREATION = "UI_CREATION",
    MODULE_ENABLE = "MODULE_ENABLE",
    RUNTIME = "RUNTIME"
}

Fizzure.currentPhase = FRAMEWORK_PHASES.LOADING
Fizzure.debug = {
    enabled = false,
    level = "INFO",
    logHistory = {},
    maxLogHistory = 100
}

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
        level = "INFO"
    },
    ui = {
        flatDesign = true,
        autoSelectCategory = true
    }
}

-- Initialize core framework
function Fizzure:Initialize()
    self.currentPhase = FRAMEWORK_PHASES.LOADING
    
    -- Load settings
    self:LoadSettings()
    
    -- Initialize debug system
    self:InitializeDebugSystem()
    
    -- Create main event frame
    local mainFrame = CreateFrame("Frame", "FizzureMainFrame", UIParent)
    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:RegisterEvent("PLAYER_LOGIN") 
    mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mainFrame:RegisterEvent("PLAYER_LOGOUT")
    mainFrame:SetScript("OnEvent", function(self, event, ...) 
        Fizzure:OnEvent(event, ...)
    end)
    
    self.mainFrame = mainFrame
    
    -- Initialize lifecycle manager
    self:InitializeLifecycleManager()
    
    self:Log("INFO", "Core framework initialized")
end

-- Lifecycle Management
function Fizzure:InitializeLifecycleManager()
    self.lifecycle = {
        registeredModules = {},
        failedModules = {},
        enabledModules = {},
        dependencyGraph = {}
    }
end

-- Module Registration (called during TOC load)
function Fizzure:RegisterModule(moduleTable)
    if not moduleTable or not moduleTable.GetManifest then
        self:Log("ERROR", "Invalid module registration - missing GetManifest")
        return false
    end
    
    local manifest = moduleTable:GetManifest()
    if not self:ValidateManifest(manifest) then
        self:Log("ERROR", "Invalid manifest for module: " .. tostring(manifest.name))
        return false
    end
    
    local moduleName = manifest.name
    
    -- Store module and manifest
    self.modules[moduleName] = moduleTable
    self.moduleManifests[moduleName] = manifest
    self.moduleStates[moduleName] = MODULE_STATES.REGISTERED
    
    -- Set framework reference
    moduleTable.Fizzure = self
    moduleTable.name = moduleName
    
    -- Add to dependency graph
    self:AddToDependencyGraph(moduleName, manifest.dependencies or {})
    
    self:Log("INFO", "Registered module: " .. moduleName)
    return true
end

-- Validate module manifest
function Fizzure:ValidateManifest(manifest)
    if not manifest or type(manifest) ~= "table" then
        return false
    end
    
    local required = {"name", "version", "author"}
    for _, field in ipairs(required) do
        if not manifest[field] or manifest[field] == "" then
            return false
        end
    end
    
    -- Validate dependencies
    if manifest.dependencies then
        if type(manifest.dependencies) ~= "table" then
            return false
        end
    end
    
    return true
end

-- Dependency management
function Fizzure:AddToDependencyGraph(moduleName, dependencies)
    self.dependencyGraph[moduleName] = dependencies or {}
end

function Fizzure:ResolveDependencyOrder()
    local order = {}
    local visited = {}
    local visiting = {}
    
    local function visit(moduleName)
        if visiting[moduleName] then
            self:Log("ERROR", "Circular dependency detected involving: " .. moduleName)
            return false
        end
        
        if visited[moduleName] then
            return true
        end
        
        visiting[moduleName] = true
        
        local dependencies = self.dependencyGraph[moduleName] or {}
        for _, dep in ipairs(dependencies) do
            if not self.modules[dep] then
                self:Log("ERROR", "Missing dependency '" .. dep .. "' for module '" .. moduleName .. "'")
                return false
            end
            
            if not visit(dep) then
                return false
            end
        end
        
        visiting[moduleName] = nil
        visited[moduleName] = true
        table.insert(order, moduleName)
        
        return true
    end
    
    -- Visit all modules
    for moduleName in pairs(self.modules) do
        if not visited[moduleName] then
            if not visit(moduleName) then
                return {}
            end
        end
    end
    
    self.initializationOrder = order
    return order
end

-- Event handling
function Fizzure:OnEvent(event, addonName)
    if event == "ADDON_LOADED" and addonName == "Fizzure" then
        self:OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        self:OnPlayerLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:OnPlayerEnteringWorld()
    elseif event == "PLAYER_LOGOUT" then
        self:SaveSettings()
    end
end

function Fizzure:OnAddonLoaded()
    self.currentPhase = FRAMEWORK_PHASES.VALIDATION
    
    -- Validate all registered modules
    for moduleName, module in pairs(self.modules) do
        if not self:ValidateModule(module) then
            self.moduleStates[moduleName] = MODULE_STATES.FAILED
            self:Log("ERROR", "Module validation failed: " .. moduleName)
        else
            self.moduleStates[moduleName] = MODULE_STATES.VALIDATED
        end
    end
    
    -- Resolve dependency order
    local order = self:ResolveDependencyOrder()
    if #order == 0 then
        self:Log("ERROR", "Dependency resolution failed")
        return
    end
    
    self.currentPhase = FRAMEWORK_PHASES.CORE_INIT
    
    -- Initialize modules in dependency order
    for _, moduleName in ipairs(order) do
        if self.moduleStates[moduleName] == MODULE_STATES.VALIDATED then
            self:InitializeModule(moduleName)
        end
    end
end

function Fizzure:OnPlayerLogin()
    self.currentPhase = FRAMEWORK_PHASES.UI_CREATION
    
    -- Initialize UI system
    self:InitializeUISystem()
    
    -- Create UI for all initialized modules
    for _, moduleName in ipairs(self.initializationOrder) do
        if self.moduleStates[moduleName] == MODULE_STATES.INITIALIZED then
            self:CreateModuleUI(moduleName)
        end
    end
end

function Fizzure:OnPlayerEnteringWorld()
    self.currentPhase = FRAMEWORK_PHASES.MODULE_ENABLE
    
    -- Enable modules based on saved settings
    for _, moduleName in ipairs(self.initializationOrder) do
        if self.moduleStates[moduleName] == MODULE_STATES.UI_READY then
            if self.db.enabledModules[moduleName] then
                self:EnableModule(moduleName)
            end
        end
    end
    
    self.currentPhase = FRAMEWORK_PHASES.RUNTIME
    self:Log("INFO", "Framework fully operational")
end

-- Module lifecycle methods
function Fizzure:ValidateModule(module)
    local required = {"GetManifest"}
    for _, method in ipairs(required) do
        if not module[method] or type(module[method]) ~= "function" then
            return false
        end
    end
    return true
end

function Fizzure:InitializeModule(moduleName)
    local module = self.modules[moduleName]
    if not module then return false end
    
    self:Log("INFO", "Initializing module: " .. moduleName)
    
    -- Load module settings
    module.settings = self:GetModuleSettings(moduleName)
    
    -- Call module initialization
    if module.OnInitialize then
        local success, err = pcall(module.OnInitialize, module)
        if not success then
            self:Log("ERROR", "Module initialization failed for " .. moduleName .. ": " .. tostring(err))
            self.moduleStates[moduleName] = MODULE_STATES.FAILED
            return false
        end
    end
    
    self.moduleStates[moduleName] = MODULE_STATES.INITIALIZED
    return true
end

function Fizzure:CreateModuleUI(moduleName)
    local module = self.modules[moduleName]
    if not module then return false end
    
    -- Provide UI creation interface
    module.ui = self:CreateModuleUIInterface(moduleName)
    
    -- Call module UI setup
    if module.OnUIReady then
        local success, err = pcall(module.OnUIReady, module)
        if not success then
            self:Log("ERROR", "Module UI creation failed for " .. moduleName .. ": " .. tostring(err))
            return false
        end
    end
    
    self.moduleStates[moduleName] = MODULE_STATES.UI_READY
    return true
end

function Fizzure:EnableModule(moduleName)
    local module = self.modules[moduleName]
    if not module or self.moduleStates[moduleName] ~= MODULE_STATES.UI_READY then
        return false
    end
    
    self.db.enabledModules[moduleName] = true
    
    if module.OnEnable then
        local success, err = pcall(module.OnEnable, module)
        if not success then
            self:Log("ERROR", "Module enable failed for " .. moduleName .. ": " .. tostring(err))
            self.db.enabledModules[moduleName] = false
            return false
        end
    end
    
    self.moduleStates[moduleName] = MODULE_STATES.ENABLED
    self:SaveSettings()
    return true
end

function Fizzure:DisableModule(moduleName)
    local module = self.modules[moduleName]
    if not module or self.moduleStates[moduleName] ~= MODULE_STATES.ENABLED then
        return false
    end
    
    self.db.enabledModules[moduleName] = false
    
    if module.OnDisable then
        local success, err = pcall(module.OnDisable, module)
        if not success then
            self:Log("ERROR", "Module disable failed for " .. moduleName .. ": " .. tostring(err))
        end
    end
    
    self.moduleStates[moduleName] = MODULE_STATES.UI_READY
    self:SaveSettings()
    return true
end

-- UI Interface for modules
function Fizzure:CreateModuleUIInterface(moduleName)
    return {
        CreateWindow = function(title, width, height)
            return FizzureUI:CreateWindow(
                "Fizzure" .. moduleName .. "Window",
                title or moduleName,
                width or 400,
                height or 300,
                UIParent,
                self.db.ui.flatDesign
            )
        end,
        
        CreateStatusFrame = function(title, width, height)
            return FizzureUI:CreateStatusFrame(
                "Fizzure" .. moduleName .. "Status",
                title or moduleName,
                width or 200,
                height or 150,
                self.db.ui.flatDesign
            )
        end,
        
        CreateButton = function(parent, text, onClick)
            return FizzureUI:CreateButton(
                parent,
                text,
                nil, nil,
                onClick,
                self.db.ui.flatDesign
            )
        end,
        
        CreateLabel = function(parent, text, fontSize)
            return FizzureUI:CreateLabel(parent, text, fontSize)
        end,
        
        ShowNotification = function(title, message, type, duration)
            return self:ShowNotification(title, message, type, duration)
        end
    }
end

-- UI System Initialization
function Fizzure:InitializeUISystem()
    -- Create main window
    self:CreateMainWindow()
    
    -- Create minimap button
    self:CreateMinimapButton()
    
    -- Initialize notification system
    self:CreateNotificationSystem()
end

function Fizzure:CreateMainWindow()
    local frame = FizzureUI:CreateWindow("FizzureMainWindow", "Fizzure Control Center", 700, 500, UIParent, self.db.ui.flatDesign)
    
    -- Create module list
    local moduleList = FizzureUI:CreateScrollFrame(frame.content, 200, 400, 20, "FizzureModuleList")
    moduleList:SetPoint("TOPLEFT", 10, -10)
    
    -- Create details panel  
    local detailsPanel = FizzureUI:CreatePanel(frame.content, 450, 400, {
        point = "TOPLEFT",
        relativeFrame = moduleList,
        relativePoint = "TOPRIGHT",
        x = 10,
        y = 0
    }, self.db.ui.flatDesign)
    
    frame.moduleList = moduleList
    frame.detailsPanel = detailsPanel
    frame.currentDetailWidgets = {}
    
    self.frames.mainWindow = frame
    frame:Hide()
    
    -- Populate with modules
    self:PopulateModuleList()
end

function Fizzure:PopulateModuleList()
    local frame = self.frames.mainWindow
    if not frame or not frame.moduleList then return end
    
    local content = frame.moduleList.content
    local yPos = -10
    
    -- Clear existing buttons
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end
    
    -- Create module buttons
    for _, moduleName in ipairs(self.initializationOrder) do
        local module = self.modules[moduleName]
        local manifest = self.moduleManifests[moduleName]
        local state = self.moduleStates[moduleName]
        
        local btn = FizzureUI:CreateButton(content, moduleName, 180, 30, function()
            self:ShowModuleDetails(moduleName)
        end, self.db.ui.flatDesign)
        
        btn:SetPoint("TOP", 0, yPos)
        
        -- Color code by state
        if state == MODULE_STATES.ENABLED then
            btn:SetBackdropBorderColor(0, 1, 0, 1)
        elseif state == MODULE_STATES.FAILED then
            btn:SetBackdropBorderColor(1, 0, 0, 1)
        else
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
        
        yPos = yPos - 35
    end
    
    frame.moduleList:UpdateScrollChildHeight()
end

function Fizzure:ShowModuleDetails(moduleName)
    local frame = self.frames.mainWindow
    if not frame or not frame.detailsPanel then return end
    
    -- Clear existing widgets
    for _, widget in ipairs(frame.currentDetailWidgets) do
        if widget and widget.Hide then widget:Hide() end
    end
    frame.currentDetailWidgets = {}
    
    local module = self.modules[moduleName]
    local manifest = self.moduleManifests[moduleName]
    local state = self.moduleStates[moduleName]
    
    local panel = frame.detailsPanel
    local yPos = -20
    
    -- Title
    local title = FizzureUI:CreateLabel(panel, moduleName, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, yPos)
    table.insert(frame.currentDetailWidgets, title)
    yPos = yPos - 30
    
    -- Info
    local info = FizzureUI:CreateLabel(panel, 
        string.format("v%s by %s", manifest.version, manifest.author))
    info:SetPoint("TOP", 0, yPos)
    table.insert(frame.currentDetailWidgets, info)
    yPos = yPos - 25
    
    -- State
    local stateLabel = FizzureUI:CreateLabel(panel, "State: " .. state)
    stateLabel:SetPoint("TOP", 0, yPos)
    table.insert(frame.currentDetailWidgets, stateLabel)
    yPos = yPos - 30
    
    -- Enable/Disable button
    if state == MODULE_STATES.UI_READY or state == MODULE_STATES.ENABLED then
        local isEnabled = state == MODULE_STATES.ENABLED
        local toggleBtn = FizzureUI:CreateButton(panel, 
            isEnabled and "Disable" or "Enable", 
            100, 25,
            function()
                if isEnabled then
                    self:DisableModule(moduleName)
                else
                    self:EnableModule(moduleName)
                end
                self:ShowModuleDetails(moduleName) -- Refresh
            end,
            self.db.ui.flatDesign)
        
        toggleBtn:SetPoint("TOP", 0, yPos)
        table.insert(frame.currentDetailWidgets, toggleBtn)
    end
end

-- Settings management
function Fizzure:LoadSettings()
    if not FizzureDB then
        FizzureDB = FizzureCommon:TableCopy(defaultSettings)
    else
        FizzureDB = FizzureCommon:TableMerge(
            FizzureCommon:TableCopy(defaultSettings), 
            FizzureDB
        )
    end
    self.db = FizzureDB
end

function Fizzure:SaveSettings()
    if not self.db then return end
    for key, value in pairs(self.db) do
        FizzureDB[key] = value
    end
end

function Fizzure:GetModuleSettings(moduleName)
    return self.db.moduleSettings[moduleName] or {}
end

function Fizzure:SetModuleSettings(moduleName, settings)
    self.db.moduleSettings[moduleName] = settings
    
    local module = self.modules[moduleName]
    if module and module.OnSettingsUpdate then
        local success, err = pcall(module.OnSettingsUpdate, module, settings)
        if not success then
            self:Log("ERROR", "Settings update failed for " .. moduleName .. ": " .. tostring(err))
        end
    end
    
    self:SaveSettings()
end

-- Debug and logging
function Fizzure:InitializeDebugSystem()
    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level
end

function Fizzure:Log(level, message)
    local levels = {DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4}
    local currentLevel = levels[self.debug.level] or 2
    local messageLevel = levels[level] or 2
    
    if messageLevel >= currentLevel then
        local timestamp = date("%H:%M:%S")
        local logEntry = string.format("[%s] %s: %s", timestamp, level, message)
        
        if self.debug.enabled then
            print("|cff00ff00Fizzure|r " .. logEntry)
        end
        
        table.insert(self.debug.logHistory, logEntry)
        if #self.debug.logHistory > self.debug.maxLogHistory then
            table.remove(self.debug.logHistory, 1)
        end
    end
end

-- Notification system
function Fizzure:CreateNotificationSystem()
    self.notifications = {}
end

function Fizzure:ShowNotification(title, message, type, duration)
    if not self.db.notifications.enabled then return end
    
    return FizzureUI:ShowToast(
        string.format("%s: %s", title, message),
        duration or 3,
        type or "info"
    )
end

-- Minimap button
function Fizzure:CreateMinimapButton()
    if not self.db.minimap.show then return end
    
    local button = CreateFrame("Button", "FizzureMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52, -52)
    
    button:SetNormalTexture("Interface\\AddOns\\Fizzure\\textures\\minimap-button")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    button:SetScript("OnClick", function()
        self:ToggleMainWindow()
    end)
    
    self.minimapButton = button
end

function Fizzure:ToggleMainWindow()
    local frame = self.frames.mainWindow
    if not frame then return end
    
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Public API
function Fizzure:GetModuleState(moduleName)
    return self.moduleStates[moduleName]
end

function Fizzure:GetModuleList()
    return self.initializationOrder
end

-- Initialize framework
Fizzure:Initialize()

-- Slash commands
SLASH_FIZZURE1 = "/fizz"
SLASH_FIZZURE2 = "/fizzure"
SlashCmdList["FIZZURE"] = function(msg)
    local command = string.lower(msg or "")
    
    if command == "" or command == "show" then
        Fizzure:ToggleMainWindow()
    elseif command == "debug" then
        Fizzure.debug.enabled = not Fizzure.debug.enabled
        print("|cff00ff00Fizzure:|r Debug " .. (Fizzure.debug.enabled and "enabled" or "disabled"))
    else
        print("|cff00ff00Fizzure Commands:|r")
        print("  /fizz - Toggle control center")
        print("  /fizz debug - Toggle debug mode")
    end
end