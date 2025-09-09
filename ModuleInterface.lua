-- ModuleInterface.lua - Standardized interface for Fizzure modules
-- This shows the contract that all modules must implement

local SampleModule = {}

-- REQUIRED: GetManifest - Returns module metadata
function SampleModule:GetManifest()
    return {
        name = "Sample Module",
        version = "1.0",
        author = "Fizzure Team",
        category = "General",
        description = "Sample module showing proper interface",
        
        -- Optional dependencies (will be initialized before this module)
        dependencies = {
            -- "Other Module Name"
        },
        
        -- Optional class restriction
        classRestriction = nil, -- or "HUNTER", "MAGE", etc.
        
        -- Optional minimum level requirement
        minLevel = 1,
        
        -- Module capabilities
        hasUI = true,
        hasSettings = true,
        hasKeybindings = true
    }
end

-- REQUIRED: GetDefaultSettings - Return default settings table
function SampleModule:GetDefaultSettings()
    return {
        enabled = true,
        showFrame = true,
        framePosition = nil,
        
        -- Sample settings structure
        notifications = {
            enabled = true,
            sound = true
        },
        
        keybindings = {
            toggle = "ALT-S"
        },
        
        -- Module-specific settings
        threshold = 10,
        autoMode = false
    }
end

-- OPTIONAL: ValidateSettings - Validate settings before applying
function SampleModule:ValidateSettings(settings)
    if type(settings.enabled) ~= "boolean" then
        return false
    end
    
    if settings.threshold and (type(settings.threshold) ~= "number" or settings.threshold < 0) then
        return false
    end
    
    return true
end

-- OPTIONAL: OnInitialize - Core module initialization (NO UI CREATION HERE)
function SampleModule:OnInitialize()
    -- Get settings from framework
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Initialize module state
    self.isActive = false
    self.lastUpdate = 0
    self.cache = {}
    
    -- Create event frame for WoW events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    
    -- Create update timer if needed
    self.updateTimer = FizzureCommon:NewTicker(1, function()
        self:OnUpdate()
    end)
    
    self:Log("INFO", "Module initialized")
    return true
end

-- OPTIONAL: OnUIReady - UI creation and setup (called after framework UI is ready)
function SampleModule:OnUIReady()
    -- Create main window using framework UI interface
    self.mainWindow = self.ui.CreateWindow("Sample Module", 400, 300)
    
    -- Create status frame
    self.statusFrame = self.ui.CreateStatusFrame("Sample Status", 200, 150)
    
    -- Create UI elements using framework interface
    local content = self.mainWindow.content
    
    -- Status label
    self.statusLabel = self.ui.CreateLabel(content, "Status: Ready")
    self.statusLabel:SetPoint("TOP", 0, -20)
    
    -- Action button
    self.actionButton = self.ui.CreateButton(content, "Toggle Action", function()
        self:ToggleAction()
    end)
    self.actionButton:SetPoint("TOP", 0, -60)
    
    -- Settings button
    local settingsButton = self.ui.CreateButton(content, "Settings", function()
        self:ShowSettings()
    end)
    settingsButton:SetPoint("TOP", 0, -100)
    
    -- Position frame if saved position exists
    if self.settings.framePosition then
        self.mainWindow:ClearAllPoints()
        self.mainWindow:SetPoint(
            self.settings.framePosition.point,
            UIParent,
            self.settings.framePosition.point,
            self.settings.framePosition.x,
            self.settings.framePosition.y
        )
    end
    
    -- Save position when window moves
    self.mainWindow.OnPositionChanged = function()
        local point, _, _, x, y = self.mainWindow:GetPoint()
        self.settings.framePosition = {
            point = point,
            x = x,
            y = y
        }
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Show frame if setting is enabled
    if self.settings.showFrame then
        self.mainWindow:Show()
    end
    
    self:Log("INFO", "UI created")
    return true
end

-- OPTIONAL: OnEnable - Called when module is enabled at runtime
function SampleModule:OnEnable()
    self.isActive = true
    
    -- Start any timers or processes
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = FizzureCommon:NewTicker(1, function()
            self:OnUpdate()
        end)
    end
    
    -- Show UI if configured
    if self.settings.showFrame and self.mainWindow then
        self.mainWindow:Show()
    end
    
    -- Register secure actions/keybindings
    self:RegisterKeybindings()
    
    self:Log("INFO", "Module enabled")
    self.ui.ShowNotification("Module Enabled", self.name .. " is now active", "success", 2)
    
    return true
end

-- OPTIONAL: OnDisable - Called when module is disabled at runtime
function SampleModule:OnDisable()
    self.isActive = false
    
    -- Stop timers
    if self.updateTimer then
        self.updateTimer:Cancel()
    end
    
    -- Hide UI
    if self.mainWindow then
        self.mainWindow:Hide()
    end
    
    if self.statusFrame then
        self.statusFrame:Hide()
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    self:Log("INFO", "Module disabled")
    self.ui.ShowNotification("Module Disabled", self.name .. " is now inactive", "info", 2)
    
    return true
end

-- OPTIONAL: OnSettingsUpdate - Called when settings are changed
function SampleModule:OnSettingsUpdate(newSettings)
    local oldSettings = self.settings
    self.settings = newSettings
    
    -- React to setting changes
    if oldSettings.showFrame ~= newSettings.showFrame then
        if newSettings.showFrame and self.mainWindow then
            self.mainWindow:Show()
        elseif self.mainWindow then
            self.mainWindow:Hide()
        end
    end
    
    -- Update keybindings if changed
    if oldSettings.keybindings.toggle ~= newSettings.keybindings.toggle then
        self:UnregisterKeybindings()
        if self.isActive then
            self:RegisterKeybindings()
        end
    end
    
    self:Log("INFO", "Settings updated")
end

-- OPTIONAL: OnShutdown - Cleanup when addon unloads
function SampleModule:OnShutdown()
    -- Clean up event frames
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame = nil
    end
    
    -- Cancel timers
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Cleanup UI
    if self.mainWindow then
        self.mainWindow:Hide()
        self.mainWindow = nil
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    self:Log("INFO", "Module shutdown complete")
end

-- Module-specific methods
function SampleModule:OnEvent(event, ...)
    if not self.isActive then return end
    
    if event == "PLAYER_TARGET_CHANGED" then
        self:OnTargetChanged()
    elseif event == "BAG_UPDATE" then
        self:OnBagUpdate()
    end
end

function SampleModule:OnUpdate()
    if not self.isActive then return end
    
    local currentTime = GetTime()
    if currentTime - self.lastUpdate < 1 then return end
    
    self.lastUpdate = currentTime
    
    -- Update status display
    if self.statusLabel then
        self.statusLabel:SetText("Status: Active (" .. math.floor(currentTime) .. ")")
    end
end

function SampleModule:OnTargetChanged()
    local target = UnitName("target")
    if target then
        self:Log("DEBUG", "Target changed to: " .. target)
    end
end

function SampleModule:OnBagUpdate()
    -- Handle bag changes
    self:Log("DEBUG", "Bag contents updated")
end

function SampleModule:ToggleAction()
    self.isActive = not self.isActive
    
    local status = self.isActive and "Active" or "Inactive"
    if self.statusLabel then
        self.statusLabel:SetText("Status: " .. status)
    end
    
    self.ui.ShowNotification("Action Toggled", "Module is now " .. string.lower(status), "info", 2)
end

function SampleModule:ShowSettings()
    -- Create simple settings interface
    local settingsFrame = self.ui.CreateWindow("Settings - " .. self.name, 300, 250)
    
    local content = settingsFrame.content
    local yPos = -20
    
    -- Enable/disable notifications checkbox
    local notifyCheck = FizzureUI:CreateCheckBox(content, "Enable Notifications", 
        self.settings.notifications.enabled, function(checked)
            self.settings.notifications.enabled = checked
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end)
    notifyCheck:SetPoint("TOP", 0, yPos)
    yPos = yPos - 30
    
    -- Show frame checkbox  
    local frameCheck = FizzureUI:CreateCheckBox(content, "Show Main Frame",
        self.settings.showFrame, function(checked)
            self.settings.showFrame = checked
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end)
    frameCheck:SetPoint("TOP", 0, yPos)
    yPos = yPos - 30
    
    -- Threshold slider
    local thresholdSlider = FizzureUI:CreateSlider(content, "Threshold", 
        1, 100, self.settings.threshold, 1, function(value)
            self.settings.threshold = math.floor(value)
            self.Fizzure:SetModuleSettings(self.name, self.settings)
        end, true)
    thresholdSlider:SetPoint("TOP", 0, yPos)
    
    settingsFrame:Show()
end

function SampleModule:RegisterKeybindings()
    if not _G.FizzureSecure then return end
    
    local macroText = "/script " .. self.name .. ":ToggleAction()"
    FizzureSecure:CreateSecureButton(
        self.name .. "ToggleButton",
        macroText,
        self.settings.keybindings.toggle,
        "Toggle " .. self.name
    )
end

function SampleModule:UnregisterKeybindings()
    if not _G.FizzureSecure then return end
    
    if self.settings.keybindings.toggle then
        FizzureSecure:ClearKeyBinding(self.settings.keybindings.toggle)
    end
end

-- Utility methods that modules can use
function SampleModule:Log(level, message)
    if self.Fizzure and self.Fizzure.Log then
        self.Fizzure:Log(level, "[" .. (self.name or "Module") .. "] " .. message)
    end
end

function SampleModule:GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

function SampleModule:IsPlayerLevel(minLevel)
    return UnitLevel("player") >= minLevel
end

function SampleModule:IsModuleEnabled()
    return self.isActive
end

-- Register module with framework
-- This should be called at the end of each module file
if Fizzure then
    Fizzure:RegisterModule(SampleModule)
else
    -- Queue for later registration if framework not loaded yet
    if not _G.FizzureModuleQueue then
        _G.FizzureModuleQueue = {}
    end
    table.insert(_G.FizzureModuleQueue, SampleModule)
end