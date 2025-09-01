-- Fizzure.lua - Core modular framework with proper persistence
local addonName = "Fizzure"
local fizzure = {}
_G[addonName] = fizzure

-- Core variables
fizzure.modules = {}
fizzure.moduleCategories = {
    ["Class-Specific"] = {},
    ["General"] = {},
    ["Combat"] = {},
    ["UI/UX"] = {},
    ["Economy"] = {},
    ["Social"] = {}
}

fizzure.frames = {}
fizzure.notifications = {}
fizzure.debug = {
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
        autoSelectCategory = true
    }
}

-- Initialize core system
function fizzure:Initialize()
    -- Load saved variables
    self:LoadSettings()

    -- Create main frame
    local mainFrame = CreateFrame("Frame", "FizzureFrame")
    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:RegisterEvent("PLAYER_LOGIN")
    mainFrame:RegisterEvent("PLAYER_LOGOUT")
    mainFrame:SetScript("OnEvent", function(self, event, ...) fizzure:OnEvent(event, ...) end)

    -- Initialize UI components
    self:CreateMinimapButton()
    self:CreateMainWindow()
    self:CreateNotificationSystem()
    self:InitializeDebugSystem()

    if _G.FizzureSecure and type(_G.FizzureSecure.Initialize) == "function" then
        _G.FizzureSecure:Initialize()
    end

    print("|cff00ff00Fizzure|r Core System Loaded")
end

-- Load settings with proper defaults
function fizzure:LoadSettings()
    if not FizzureDB then
        FizzureDB = FizzureCommon:TableCopy(defaultSettings)
    else
        -- Merge with defaults to ensure all fields exist
        FizzureDB = FizzureCommon:TableMerge(FizzureCommon:TableCopy(defaultSettings), FizzureDB)
    end

    self.db = FizzureDB

    -- Apply debug settings
    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level
end

-- Save settings
function fizzure:SaveSettings()
    if self.db then
        FizzureDB = self.db
    end
end

-- Event handling
function fizzure:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Initialize enabled modules
        FizzureCommon:After(0.5, function()
            for moduleName, _ in pairs(self.db.enabledModules) do
                if self.db.enabledModules[moduleName] then
                    self:EnableModule(moduleName)
                end
            end
        end)
    elseif event == "PLAYER_LOGOUT" then
        self:SaveSettings()
    end
end

-- Module registration
function fizzure:RegisterModule(name, module, category, classRestriction)
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
    module.fizzure = self

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

function fizzure:RegisterClassModule(name, module, playerClass)
    return self:RegisterModule(name, module, "Class-Specific", playerClass)
end

function fizzure:ValidateModuleInterface(module)
    local required = {"Initialize", "Shutdown"}
    for _, method in ipairs(required) do
        if not module[method] then
            return false
        end
    end
    return true
end

-- Module management
function fizzure:EnableModule(name)
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
    self:SaveSettings()

    if module.Initialize then
        local success = module:Initialize()
        if success == false then
            self.db.enabledModules[name] = false
            self:SaveSettings()
            return false
        end
    end

    return true
end

function fizzure:DisableModule(name)
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
    self:SaveSettings()

    if module.Shutdown then
        module:Shutdown()
    end

    return true
end

function fizzure:GetModuleSettings(moduleName)
    return self.db.moduleSettings[moduleName] or {}
end

function fizzure:SetModuleSettings(moduleName, settings)
    local module = self.modules[moduleName]
    if module and module.ValidateSettings then
        if not module:ValidateSettings(settings) then
            return false
        end
    end

    self.db.moduleSettings[moduleName] = settings
    self:SaveSettings()

    -- Sync with framework settings if applicable
    self:SyncFrameworkSettings(moduleName, settings)

    return true
end

-- Sync settings between framework and modules
function fizzure:SyncFrameworkSettings(moduleName, moduleSettings)
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

-- Create minimap button
function fizzure:CreateMinimapButton()
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
            fizzure:ToggleMainWindow()
        elseif clickButton == "RightButton" then
            fizzure:ShowQuickStatus()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local angle = math.atan2(self:GetTop() - Minimap:GetTop(), self:GetLeft() - Minimap:GetLeft())
        fizzure.db.minimap.minimapPos = math.deg(angle)
        fizzure:SaveSettings()
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

-- Create main window
function fizzure:CreateMainWindow()
    local frame = FizzureUI:CreateWindow("FizzureMainWindow", "Fizzure Control Center", 700, 500)

    -- Category tabs
    frame.categoryTabs = {}
    frame.selectedCategory = "Class-Specific"

    local tabWidth = 100
    local tabIndex = 0
    for categoryName, _ in pairs(self.moduleCategories) do
        local tab = FizzureUI:CreateButton(frame, categoryName, tabWidth, 25)
        tab:SetPoint("TOPLEFT", 20 + (tabIndex * tabWidth), -45)

        tab:SetScript("OnClick", function()
            fizzure:SelectCategory(categoryName)
        end)

        frame.categoryTabs[categoryName] = tab
        tabIndex = tabIndex + 1
    end

    -- Module list
    local moduleList = FizzureUI:CreateScrollFrame(frame, 200, 350)
    moduleList:SetPoint("TOPLEFT", 20, -75)
    frame.moduleList = moduleList

    -- Details panel
    local detailsPanel = FizzureUI:CreatePanel(frame, 450, 350)
    detailsPanel:SetPoint("TOPRIGHT", -20, -75)
    frame.detailsPanel = detailsPanel

    -- Status bar
    local statusBar = FizzureUI:CreatePanel(frame, 680, 35)
    statusBar:SetPoint("BOTTOM", 0, 10)

    local statusText = FizzureUI:CreateLabel(statusBar, "Ready")
    statusText:SetPoint("LEFT", 10, 5)

    local debugBtn = FizzureUI:CreateButton(statusBar, "Debug: OFF", 80, 20, function()
        fizzure:ToggleDebug()
        debugBtn:SetText("Debug: " .. (fizzure.debug.enabled and fizzure.debug.level or "OFF"))
    end)
    debugBtn:SetPoint("RIGHT", -100, 0)

    local reloadBtn = FizzureUI:CreateButton(statusBar, "Reload UI", 80, 20, ReloadUI)
    reloadBtn:SetPoint("RIGHT", -10, 0)

    frame.statusText = statusText
    frame.debugBtn = debugBtn

    self.frames.mainWindow = frame

    function frame:UpdateModuleList()
        local content = self.moduleList.content

        -- Clear existing
        for i = content:GetNumChildren(), 1, -1 do
            select(i, content:GetChildren()):Hide()
        end

        local yOffset = -10
        local categoryModules = fizzure.moduleCategories[self.selectedCategory] or {}

        for moduleName, module in pairs(categoryModules) do
            local button = FizzureUI:CreateButton(content, moduleName, 180, 35, function()
                fizzure:ShowModuleDetails(moduleName, module)
            end)
            button:SetPoint("TOPLEFT", 10, yOffset)

            -- Status indicator
            local status = content:CreateTexture(nil, "OVERLAY")
            status:SetSize(12, 12)
            status:SetPoint("RIGHT", button, "RIGHT", -5, 0)

            if fizzure.db.enabledModules[moduleName] then
                status:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
            else
                status:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
            end

            yOffset = yOffset - 40
        end

        self.moduleList:UpdateScrollChildHeight()
        self.statusText:SetText("Ready - " .. fizzure:GetModuleCount() .. " modules loaded")
    end

    self:SelectCategory(frame.selectedCategory)
end

-- Select category
function fizzure:SelectCategory(categoryName)
    local frame = self.frames.mainWindow
    if not frame then return end

    frame.selectedCategory = categoryName

    for name, tab in pairs(frame.categoryTabs) do
        if name == categoryName then
            tab:SetAlpha(1)
        else
            tab:SetAlpha(0.7)
        end
    end

    frame:UpdateModuleList()
end

-- Show module details
function fizzure:ShowModuleDetails(moduleName, module)
    local panel = self.frames.mainWindow.detailsPanel
    if not panel then return end

    -- Clear panel
    for i = panel:GetNumChildren(), 1, -1 do
        select(i, panel:GetChildren()):Hide()
    end

    local y = -20

    local title = FizzureUI:CreateLabel(panel, moduleName, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, y)
    y = y - 30

    local info = FizzureUI:CreateLabel(panel,
            string.format("Version %s by %s", module.version or "1.0", module.author or "Unknown"))
    info:SetPoint("TOP", 0, y)
    y = y - 30

    local enableCheck = FizzureUI:CreateCheckBox(panel, "Enable Module",
            self.db.enabledModules[moduleName], function(checked)
                if checked then
                    if not fizzure:EnableModule(moduleName) then
                        enableCheck:SetChecked(false)
                    end
                else
                    if not fizzure:DisableModule(moduleName) then
                        enableCheck:SetChecked(true)
                    end
                end
                fizzure.frames.mainWindow:UpdateModuleList()
            end)
    enableCheck:SetPoint("TOPLEFT", 20, y)
    y = y - 40

    -- Module config
    if module.CreateConfigUI then
        local configLabel = FizzureUI:CreateLabel(panel, "Module Configuration:", "GameFontNormal")
        configLabel:SetPoint("TOPLEFT", 20, y)
        y = y - 25

        y = module:CreateConfigUI(panel, 20, y)
    end
end

-- Toggle main window
function fizzure:ToggleMainWindow()
    local frame = self.frames.mainWindow
    if frame:IsShown() then
        frame:Hide()
    else
        frame:UpdateModuleList()
        frame:Show()
    end
end

-- Quick status
function fizzure:ShowQuickStatus()
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

    FizzureUI:ShowToast("Fizzure Status\n" .. text, 5, "info")
end

-- Get module count
function fizzure:GetModuleCount()
    local count = 0
    for _ in pairs(self.modules) do
        count = count + 1
    end
    return count
end

-- Notification system
function fizzure:CreateNotificationSystem()
    local container = FizzureUI:CreateFrame("Frame", "FizzureNotificationContainer", UIParent)
    container:SetSize(300, 400)
    container:SetPoint("CENTER", 0, 100)
    container:SetFrameStrata("DIALOG")
    self.frames.notificationContainer = container
end

function fizzure:ShowNotification(title, message, type, duration)
    if not self.db.notifications.enabled then return end

    FizzureUI:ShowToast(title .. "\n" .. message, duration, type)

    if self.db.notifications.sound then
        PlaySound("TellMessage")
    end
end

-- Debug system
function fizzure:InitializeDebugSystem()
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

function fizzure:LogDebug(level, message, moduleName)
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

function fizzure:CreateDebugWrappers()
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

function fizzure:CreateDebugFrame()
    if self.frames.debugFrame then return end

    local frame = FizzureUI:CreateWindow("FizzureDebugFrame", "Debug Console", 500, 300)
    frame:SetPoint("TOPRIGHT", -20, -100)

    local clearBtn = FizzureUI:CreateButton(frame, "Clear", 60, 20, function()
        self.debug.logHistory = {}
        self:UpdateDebugFrame()
    end)
    clearBtn:SetPoint("TOPRIGHT", -30, -35)

    local scrollFrame = FizzureUI:CreateScrollFrame(frame.content, 480, 240)
    scrollFrame:SetPoint("TOP", 0, -20)

    frame.scrollFrame = scrollFrame
    self.frames.debugFrame = frame
end

function fizzure:UpdateDebugFrame()
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

function fizzure:ToggleDebug(level)
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

function fizzure:GetDebugAPI()
    return self.DebugAPI
end

-- Initialize on load
fizzure:Initialize()

-- Slash commands
SLASH_FIZZURE1 = "/fizz"
SLASH_FIZZURE2 = "/fizzure"
SlashCmdList["FIZZURE"] = function(msg)
    local command, arg1, arg2 = strsplit(" ", string.lower(msg))

    if command == "" or command == "show" then
        fizzure:ToggleMainWindow()
    elseif command == "enable" and arg1 then
        if fizzure:EnableModule(arg1) then
            print("|cff00ff00Fizzure:|r Enabled module: " .. arg1)
        else
            print("|cffff0000Fizzure:|r Failed to enable module: " .. arg1)
        end
    elseif command == "disable" and arg1 then
        if fizzure:DisableModule(arg1) then
            print("|cff00ff00Fizzure:|r Disabled module: " .. arg1)
        else
            print("|cffff0000Fizzure:|r Failed to disable module: " .. arg1)
        end
    elseif command == "list" then
        print("|cff00ff00Fizzure Modules:|r")
        for categoryName, modules in pairs(fizzure.moduleCategories) do
            if next(modules) then
                print("  |cffFFD700" .. categoryName .. ":|r")
                for moduleName, module in pairs(modules) do
                    local status = fizzure.db.enabledModules[moduleName] and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                    print("    " .. moduleName .. ": " .. status)
                end
            end
        end
    else
        print("|cff00ff00Fizzure Commands:|r")
        print("  /fizz - Open control center")
        print("  /fizz enable <module> - Enable module")
        print("  /fizz disable <module> - Disable module")
        print("  /fizz list - List all modules")
    end
end