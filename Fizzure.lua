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
    local mainFrame = CreateFrame("Frame", "FizzureFrame")
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

    -- Apply debug settings
    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level
end

-- Save settings with forced persistence
function Fizzure:SaveSettings()
    if self.db then
        FizzureDB = self.db
        -- Force save by marking as dirty
        if FizzureDB then
            FizzureDB._saveTime = GetTime()
        end
    end
end

-- Event handling
function Fizzure:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Initialize enabled modules after a short delay to ensure all addons are loaded
        FizzureCommon:After(1.0, function()
            for moduleName, enabled in pairs(self.db.enabledModules) do
                if enabled then
                    local success = self:EnableModule(moduleName)
                    if not success then
                        self.db.enabledModules[moduleName] = false
                        print("|cffff8000Fizzure:|r Failed to load module: " .. moduleName)
                    else
                        print("|cff00ff00Fizzure:|r Loaded module: " .. moduleName)
                    end
                end
            end
            self:SaveSettings()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure settings are saved when entering world
        self:SaveSettings()
    elseif event == "PLAYER_LOGOUT" then
        -- Cancel save timer and do final save
        if self.saveTimer then
            self.saveTimer:Cancel()
        end
        self:SaveSettings()
        print("|cff00ff00Fizzure:|r Settings saved on logout")
    end
end

-- Module registration
function Fizzure:RegisterModule(name, module, category, classRestriction)
    if not self:ValidateModuleInterface(module) then
        print("|cffff0000Fizzure Error:|r Invalid module interface for " .. name)
        return false
    end

    if classRestriction then
        local _, playerClass = UnitClass("player")
        if playerClass ~= classRestriction then
            self:LogDebug("INFO", "Module " .. name .. " skipped - class restriction (" .. classRestriction .. ")", "Core")
            return false
        end
    end

    module.name = name
    module.category = category or "General"
    module.classRestriction = classRestriction
    module.Fizzure = self

    local cat = module.category
    if not self.moduleCategories[cat] then
        self.moduleCategories[cat] = {}
    end

    self.moduleCategories[cat][name] = module
    self.modules[name] = module

    -- Initialize module settings with defaults
    if module.GetDefaultSettings then
        if not self.db.moduleSettings[name] then
            self.db.moduleSettings[name] = module:GetDefaultSettings()
        else
            -- Merge defaults for new settings
            local defaults = module:GetDefaultSettings()
            self.db.moduleSettings[name] = FizzureCommon:TableMerge(defaults, self.db.moduleSettings[name])
        end
    else
        if not self.db.moduleSettings[name] then
            self.db.moduleSettings[name] = {}
        end
    end

    -- Save after registration
    self:SaveSettings()

    print("|cff00ff00Fizzure|r Module registered: " .. name .. " [" .. cat .. "]")
    return true
end

function Fizzure:RegisterClassModule(name, module, playerClass)
    return self:RegisterModule(name, module, "Class-Specific", playerClass)
end

function Fizzure:ValidateModuleInterface(module)
    local required = {"Initialize", "Shutdown"}
    for _, method in ipairs(required) do
        if not module[method] then
            return false
        end
    end
    return true
end

-- Module management
function Fizzure:EnableModule(name)
    local module = self.modules[name]
    if not module then
        return false
    end

    if module.dependencies then
        for _, dep in ipairs(module.dependencies) do
            if not self.db.enabledModules[dep] then
                return false
            end
        end
    end

    if module.conflicts then
        for _, conflict in ipairs(module.conflicts) do
            if self.db.enabledModules[conflict] then
                return false
            end
        end
    end

    if module.ValidateSettings and not module:ValidateSettings(self.db.moduleSettings[name] or {}) then
        return false
    end

    self.db.enabledModules[name] = true
    self:SaveSettings() -- Force save immediately

    if module.Initialize then
        local success = module:Initialize()
        if success == false then
            self.db.enabledModules[name] = false
            self:SaveSettings() -- Save the failure state too
            return false
        end
    end

    return true
end

function Fizzure:DisableModule(name)
    local module = self.modules[name]
    if not module then return false end

    for otherName, otherModule in pairs(self.modules) do
        if self.db.enabledModules[otherName] and otherModule.dependencies then
            for _, dep in ipairs(otherModule.dependencies) do
                if dep == name then
                    return false
                end
            end
        end
    end

    self.db.enabledModules[name] = false
    self:SaveSettings() -- Force save immediately

    if module.Shutdown then
        module:Shutdown()
    end

    return true
end

function Fizzure.GetModuleSettings(name)
    return (FizzureDB and FizzureDB.modules and FizzureDB.modules[name] and FizzureDB.modules[name].settings) or nil
end

function Fizzure:SetModuleSettings(moduleName, settings)
    local module = self.modules[moduleName]
    if module and module.ValidateSettings then
        if not module:ValidateSettings(settings) then
            return false
        end
    end

    self.db.moduleSettings[moduleName] = settings

    -- Force immediate save for persistence
    self:SaveSettings()

    -- Sync with framework settings if applicable
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

-- Create minimap button (SINGLE BUTTON ONLY)
function Fizzure:CreateMinimapButton()
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

-- Create main window with FIXED layout and clean flat design
function Fizzure:CreateMainWindow()
    local frame = FizzureUI:CreateWindow("FizzureMainWindow", "Fizzure Control Center", 700, 500, nil, true) -- true for flat design

    -- Store reference to current detail widgets for proper clearing
    frame.currentDetailWidgets = {}

    -- Category tabs at the very top
    frame.categoryTabs = {}
    frame.selectedCategory = "Class-Specific"

    local tabContainer = CreateFrame("Frame", nil, frame.content)
    tabContainer:SetHeight(30)
    tabContainer:SetPoint("TOPLEFT", 0, -5)
    tabContainer:SetPoint("TOPRIGHT", 0, -5)

    local tabWidth = 100
    local tabIndex = 0
    for categoryName, _ in pairs(self.moduleCategories) do
        local tab = FizzureUI:CreateButton(tabContainer, categoryName, tabWidth, 25, nil, true) -- true for flat design
        tab:SetPoint("LEFT", tabIndex * (tabWidth + 5), 0)

        tab:SetScript("OnClick", function()
            Fizzure:SelectCategory(categoryName)
        end)

        frame.categoryTabs[categoryName] = tab
        tabIndex = tabIndex + 1
    end

    -- Main content area - FIXED positioning between tabs and status bar
    local contentArea = CreateFrame("Frame", nil, frame.content)
    contentArea:SetPoint("TOPLEFT", 0, -40)  -- Below tabs
    contentArea:SetPoint("BOTTOMRIGHT", 0, 35) -- Above status bar

    -- Left panel - Module list
    local moduleListPanel = FizzureUI:CreatePanel(contentArea, 240, 1, nil, true) -- true for flat design
    moduleListPanel:SetPoint("TOPLEFT", 10, 0)
    moduleListPanel:SetPoint("BOTTOMLEFT", 10, 0)

    local moduleLabel = FizzureUI:CreateLabel(moduleListPanel, "Modules", "GameFontNormalLarge")
    moduleLabel:SetPoint("TOP", 0, -10)

    local moduleList = FizzureUI:CreateScrollFrame(moduleListPanel, 220, 1, 20)
    moduleList:SetPoint("TOPLEFT", 10, -30)
    moduleList:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.moduleList = moduleList

    -- Right panel - Module details
    local detailsPanel = FizzureUI:CreatePanel(contentArea, 1, 1, nil, true) -- true for flat design
    detailsPanel:SetPoint("TOPLEFT", moduleListPanel, "TOPRIGHT", 10, 0)
    detailsPanel:SetPoint("BOTTOMRIGHT", -10, 0)

    local detailsLabel = FizzureUI:CreateLabel(detailsPanel, "Module Details", "GameFontNormalLarge")
    detailsLabel:SetPoint("TOP", 0, -10)
    frame.detailsLabel = detailsLabel

    -- This is the actual content area for module details
    local detailsContent = CreateFrame("ScrollFrame", "MainWindow_UIPanelScrollFrameTemplate", detailsPanel, "UIPanelScrollFrameTemplate")
    detailsContent:SetPoint("TOPLEFT", 10, -30)
    detailsContent:SetPoint("BOTTOMRIGHT", -30, 10) -- Leave room for scrollbar

    local detailsScrollChild = CreateFrame("Frame", nil, detailsContent)
    detailsScrollChild:SetSize(400, 1)
    detailsContent:SetScrollChild(detailsScrollChild)

    -- Enable mousewheel on details
    detailsContent:EnableMouseWheel(true)
    detailsContent:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 30), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)

    frame.detailsContent = detailsScrollChild
    frame.detailsScrollFrame = detailsContent

    -- Status bar - FIXED at bottom with proper positioning and flat design
    local statusBar = CreateFrame("Frame", nil, frame.content)
    statusBar:SetHeight(30)
    statusBar:SetPoint("BOTTOMLEFT", 5, 5)
    statusBar:SetPoint("BOTTOMRIGHT", -5, 5)
    -- Flat design backdrop
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

    local debugBtn = FizzureUI:CreateButton(statusBar, "Debug: OFF", 80, 20, function()
        Fizzure:ToggleDebug()
        debugBtn:SetText("Debug: " .. (Fizzure.debug.enabled and Fizzure.debug.level or "OFF"))
    end, true) -- true for flat design
    debugBtn:SetPoint("RIGHT", -90, 0)

    local reloadBtn = FizzureUI:CreateButton(statusBar, "Reload UI", 80, 20, ReloadUI, true) -- true for flat design
    reloadBtn:SetPoint("RIGHT", -5, 0)

    frame.statusText = statusText
    frame.debugBtn = debugBtn
    frame.statusBar = statusBar

    self.frames.mainWindow = frame

    function frame:UpdateModuleList()
        local content = self.moduleList.content

        -- Clear existing items
        for i = 1, content:GetNumChildren() do
            local child = select(i, content:GetChildren())
            if child then
                child:Hide()
            end
        end

        local yOffset = -10
        local categoryModules = Fizzure.moduleCategories[self.selectedCategory] or {}

        for moduleName, module in pairs(categoryModules) do
            local button = FizzureUI:CreateButton(content, moduleName, 200, 30, function()
                Fizzure:ShowModuleDetails(moduleName, module)
            end, true) -- true for flat design
            button:SetPoint("TOPLEFT", 5, yOffset)

            -- Status indicator
            local status = content:CreateTexture(nil, "OVERLAY")
            status:SetSize(12, 12)
            status:SetPoint("RIGHT", button, "RIGHT", -10, 0)

            if Fizzure.db.enabledModules[moduleName] then
                status:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
            else
                status:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
            end

            yOffset = yOffset - 35
        end

        self.moduleList:UpdateScrollChildHeight()
        self.statusText:SetText("Ready - " .. Fizzure:GetModuleCount() .. " modules loaded")
    end

    self:SelectCategory(frame.selectedCategory)
end

-- Select category
function Fizzure:SelectCategory(categoryName)
    local frame = self.frames.mainWindow
    if not frame then return end

    frame.selectedCategory = categoryName

    -- Update tab appearance
    for name, tab in pairs(frame.categoryTabs) do
        if name == categoryName then
            tab:SetAlpha(1)
        else
            tab:SetAlpha(0.7)
        end
    end

    frame:UpdateModuleList()
end

-- COMPLETELY FIXED module details display with proper clearing and immediate config display
function Fizzure:ShowModuleDetails(moduleName, module)
    local frame = self.frames.mainWindow
    local panel = frame.detailsContent
    if not panel then return end

    -- ALWAYS clear existing detail widgets FIRST
    for i = 1, panel:GetNumChildren() do
        local child = select(i, panel:GetChildren())
        if child then
            child:Hide()
            child:SetParent(nil)
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

    -- Enable checkbox - FIXED variable scope issue
    local enableCheck = FizzureUI:CreateCheckBox(panel, "Enable Module",
            self.db.enabledModules[moduleName], function(checked)
                if checked then
                    if not Fizzure:EnableModule(moduleName) then
                        enableCheck:SetChecked(false)
                        Fizzure:ShowNotification("Enable Failed", "Could not enable " .. moduleName, "error", 3)
                    else
                        Fizzure:ShowNotification("Module Enabled", moduleName .. " has been enabled", "success", 2)
                        -- Refresh the details view to show config options
                        Fizzure:ShowModuleDetails(moduleName, module)
                    end
                else
                    if not Fizzure:DisableModule(moduleName) then
                        enableCheck:SetChecked(true)
                        Fizzure:ShowNotification("Disable Failed", "Could not disable " .. moduleName, "error", 3)
                    else
                        Fizzure:ShowNotification("Module Disabled", moduleName .. " has been disabled", "info", 2)
                        -- Refresh the details view to hide config options
                        Fizzure:ShowModuleDetails(moduleName, module)
                    end
                end
                Fizzure.frames.mainWindow:UpdateModuleList()
            end)
    enableCheck:SetPoint("TOPLEFT", 20, y)
    table.insert(frame.currentDetailWidgets, enableCheck)
    y = y - 40

    -- ALWAYS show module config if available, just disable if module not enabled
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

        -- Safely call CreateConfigUI with error handling
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

        -- Disable config controls if module is not enabled
        if not self.db.enabledModules[moduleName] then
            for i = 1, panel:GetNumChildren() do
                local child = select(i, panel:GetChildren())
                if child and child.SetEnabled then
                    child:SetEnabled(false)
                elseif child and child.SetAlpha then
                    child:SetAlpha(0.5)
                end
            end
        end
    end

    -- Update scroll area
    local totalHeight = math.abs(y) + 50
    panel:SetHeight(math.max(totalHeight, 300))
    if frame.detailsScrollFrame.UpdateScrollChildHeight then
        frame.detailsScrollFrame:UpdateScrollChildHeight()
    end
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

-- Get module count
function Fizzure:GetModuleCount()
    local count = 0
    for _ in pairs(self.modules) do
        count = count + 1
    end
    return count
end

-- Notification system
function Fizzure:CreateNotificationSystem()
    local container = FizzureUI:CreateFrame("Frame", "FizzureNotificationContainer", UIParent)
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

    self:CreateDebugWrappers()
end

function Fizzure:LogDebug(level, message, moduleName)
    if not self.debug.enabled then return end

    local levels = { DEBUG = 1, INFO = 2, WARN = 3, ACTION = 4, ERROR = 5 }
    local minLevel = 1

    if self.debug.level == "LOG" then minLevel = 2
    elseif self.debug.level == "DRY_RUN" then minLevel = 3
    elseif self.debug.level == "VERBOSE" then minLevel = 1 end

    if levels[level] >= minLevel then
        local timestamp = date("%H:%M:%S")
        local prefix = moduleName and ("[" .. moduleName .. "]") or "[Core]"

        local logEntry = {
            time = timestamp,
            level = level,
            module = moduleName or "Core",
            message = message
        }

        table.insert(self.debug.logHistory, logEntry)
        if #self.debug.logHistory > self.debug.maxLogHistory then
            table.remove(self.debug.logHistory, 1)
        end

        if self.frames.debugFrame and self.frames.debugFrame:IsShown() then
            self:UpdateDebugFrame()
        end

        if self.db.debug.logToChat then
            print(string.format("[%s] %s %s: %s", timestamp, level, prefix, message))
        end
    end
end

function Fizzure:CreateDebugWrappers()
    self.DebugAPI = {}

    self.DebugAPI.UseItemByName = function(itemName)
        if self.debug.enabled and (self.debug.level == "DRY_RUN" or self.debug.level == "VERBOSE") then
            self:LogDebug("ACTION", "DRY RUN: Would use item '" .. (itemName or "nil") .. "'")
            return true
        else
            self:LogDebug("ACTION", "Using item: " .. (itemName or "nil"))
            return UseItemByName(itemName)
        end
    end

    self.DebugAPI.GetItemCount = function(itemName)
        local count = GetItemCount(itemName)
        if self.debug.enabled and self.debug.level == "VERBOSE" then
            self:LogDebug("DEBUG", "Item count for '" .. (itemName or "nil") .. "': " .. count)
        end
        return count
    end

    self.DebugAPI.ShowNotification = function(title, message, type, duration)
        if self.debug.enabled and (self.debug.level == "DRY_RUN" or self.debug.level == "VERBOSE") then
            self:LogDebug("ACTION", "DRY RUN: Would show notification - " .. title .. ": " .. message)
            return
        else
            return self:ShowNotification(title, message, type, duration)
        end
    end
end

function Fizzure:CreateDebugFrame()
    if self.frames.debugFrame then return end

    local frame = FizzureUI:CreateWindow("FizzureDebugFrame", "Debug Console", 500, 300, nil, true) -- true for flat design
    frame:SetPoint("TOPRIGHT", -20, -100)

    local clearBtn = FizzureUI:CreateButton(frame.content, "Clear", 60, 20, function()
        self.debug.logHistory = {}
        self:UpdateDebugFrame()
    end, true) -- true for flat design
    clearBtn:SetPoint("TOPRIGHT", -30, -10)

    local scrollFrame = FizzureUI:CreateScrollFrame(frame.content, 480, 240)
    scrollFrame:SetPoint("TOPLEFT", 0, -40)

    frame.scrollFrame = scrollFrame
    self.frames.debugFrame = frame
end

function Fizzure:UpdateDebugFrame()
    local frame = self.frames.debugFrame
    if not frame then return end

    local content = frame.scrollFrame.content

    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local y = -5
    for i = math.max(1, #self.debug.logHistory - 20), #self.debug.logHistory do
        local entry = self.debug.logHistory[i]
        if entry then
            local text = string.format("[%s] %s [%s]: %s",
                    entry.time, entry.level, entry.module, entry.message)

            local label = FizzureUI:CreateLabel(content, text, "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 5, y)
            y = y - 15
        end
    end

    frame.scrollFrame:UpdateScrollChildHeight()
end

function Fizzure:ToggleDebug(level)
    if level then
        self.debug.level = level
        self.db.debug.level = level
    end

    self.debug.enabled = not self.debug.enabled
    self.db.debug.enabled = self.debug.enabled
    self:SaveSettings()

    if self.debug.enabled then
        if self.frames.debugFrame then
            self.frames.debugFrame:Show()
        end
    else
        if self.frames.debugFrame then
            self.frames.debugFrame:Hide()
        end
    end

    for moduleName, module in pairs(self.modules) do
        if module.OnDebugToggle then
            module:OnDebugToggle(self.debug.enabled, self.debug.level)
        end
    end
end

function Fizzure:GetDebugAPI()
    return self.DebugAPI
end

-- Initialize on load
Fizzure:Initialize()

-- Slash commands
SLASH_FIZZURE1 = "/fizz"
SLASH_FIZZURE2 = "/Fizzure"
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