-- Fizzure.lua - Enhanced Core Modular System (COMPLETE VERSION)
-- World of Warcraft 3.3.5 Modular Management Addon

local addonName = "Fizzure"
local fizzure = {}
_G[addonName] = fizzure

-- Core system variables
fizzure.modules = {}
fizzure.moduleCategories = {
    ["Class-Specific"] = {},
    ["General"] = {},
    ["Combat"] = {},
    ["UI/UX"] = {},
    ["Economy"] = {},
    ["Social"] = {}
}

-- Ensure saved variables table exists now (before modules register)
_G.FizzureDB = _G.FizzureDB or {}
fizzure.db = _G.FizzureDB

-- Ensure required subtables exist immediately (so RegisterModule can use them)
fizzure.db.enabledModules = fizzure.db.enabledModules or {}
fizzure.db.moduleSettings = fizzure.db.moduleSettings or {}
fizzure.db.notifications  = fizzure.db.notifications  or { enabled = true, sound = true, position = { "CENTER", 0, 100 } }
fizzure.db.minimap        = fizzure.db.minimap        or { show = true, minimapPos = 225 }
fizzure.db.debug          = fizzure.db.debug          or { enabled = false, level = "DRY_RUN", showDebugFrame = true, logToChat = false }
fizzure.db.ui             = fizzure.db.ui             or { categorizeModules = true, compactView = false, autoSelectCategory = true }

fizzure.frames = {}
fizzure.notifications = {}
fizzure.debug = {
    enabled = false,
    level = "DRY_RUN", -- OFF, LOG, DRY_RUN, VERBOSE
    logHistory = {},
    maxLogHistory = 100
}

-- Default core settings
local defaultCoreSettings = {
    enabledModules = {},
    moduleSettings = {}, -- Per-module settings storage
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

-- --- BEGIN: fail-safe Common/C_Timer shim ---
if not _G.FizzureCommon then _G.FizzureCommon = {} end
if type(_G.FizzureCommon.After) ~= "function" then
    function _G.FizzureCommon:After(delay, func)
        if type(delay) ~= "number" or delay < 0 then return end
        if type(func) ~= "function" then return end
        local f = CreateFrame("Frame", nil, UIParent)
        local elapsed = 0
        f:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                pcall(func)
                self:Hide()
            end
        end)
        return f
    end
end
if not _G.C_Timer then _G.C_Timer = {} end
if type(_G.C_Timer.After) ~= "function" then
    _G.C_Timer.After = function(delay, func)
        return _G.FizzureCommon:After(delay, func)
    end
end
-- --- END: fail-safe Common/C_Timer shim ---


-- Initialize core system
function fizzure:Initialize()
    -- Initialize database
    if FizzureDB then
        for k, v in pairs(defaultCoreSettings) do
            if FizzureDB[k] == nil then
                FizzureDB[k] = v
            end
        end
        self.db = FizzureDB
    else
        FizzureDB = defaultCoreSettings
        self.db = FizzureDB
    end

    -- Create main frame
    local mainFrame = CreateFrame("Frame", "FizzureFrame")
    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:RegisterEvent("PLAYER_LOGIN")
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

-- Event handling
function fizzure:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            self:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Initialize modules after login
        for moduleName, module in pairs(self.modules) do
            if self.db.enabledModules[moduleName] then
                self:EnableModule(moduleName)
            end
        end
    end
end

-- Enhanced module registration with validation
function fizzure:RegisterModule(name, module, category, classRestriction)
    -- Validate module interface
    if not self:ValidateModuleInterface(module) then
        print("|cffff0000Fizzure Error:|r Invalid module interface for " .. name)
        return false
    end

    -- Check class restriction
    if classRestriction then
        local _, playerClass = UnitClass("player")
        if playerClass ~= classRestriction then
            self:LogDebug("INFO", "Module " .. name .. " skipped - class restriction (" .. classRestriction .. ")", "Core")
            return false
        end
    end

    -- Set metadata
    module.name = name
    module.category = category or "General"
    module.classRestriction = classRestriction
    module.fizzure = self

    -- Store in appropriate category
    local cat = module.category
    if not self.moduleCategories[cat] then
        self.moduleCategories[cat] = {}
    end

    self.moduleCategories[cat][name] = module
    self.modules[name] = module

    -- Initialize module settings
    if module.GetDefaultSettings then
        if not self.db.moduleSettings[name] then
            self.db.moduleSettings[name] = module:GetDefaultSettings()
        else
            -- Merge with defaults for new settings
            local defaults = module:GetDefaultSettings()
            for k, v in pairs(defaults) do
                if self.db.moduleSettings[name][k] == nil then
                    self.db.moduleSettings[name][k] = v
                end
            end
        end
    else
        if not self.db.moduleSettings[name] then
            self.db.moduleSettings[name] = {}
        end
    end

    -- Notify other modules
    for otherName, otherModule in pairs(self.modules) do
        if otherModule.OnModuleLoaded then
            otherModule:OnModuleLoaded(name, module)
        end
    end

    print("|cff00ff00Fizzure|r Module registered: " .. name .. " [" .. cat .. "]")
    self:LogDebug("INFO", "Module registered: " .. name .. " in category " .. cat, "Core")
    return true
end

-- Register class-specific modules with helper
function fizzure:RegisterClassModule(name, module, playerClass)
    return self:RegisterModule(name, module, "Class-Specific", playerClass)
end

-- Validate module interface
function fizzure:ValidateModuleInterface(module)
    local required = {"Initialize", "Shutdown"}
    for _, method in ipairs(required) do
        if not module[method] then
            self:LogDebug("ERROR", "Module missing required method: " .. method, "Core")
            return false
        end
    end
    return true
end

-- Enhanced module management
function fizzure:EnableModule(name)
    local module = self.modules[name]
    if not module then
        self:LogDebug("ERROR", "Attempted to enable unknown module: " .. name, "Core")
        return false
    end

    -- Check dependencies
    if module.dependencies then
        for _, dep in ipairs(module.dependencies) do
            if not self.db.enabledModules[dep] then
                self:LogDebug("ERROR", "Module " .. name .. " requires " .. dep .. " to be enabled first", "Core")
                return false
            end
        end
    end

    -- Check conflicts
    if module.conflicts then
        for _, conflict in ipairs(module.conflicts) do
            if self.db.enabledModules[conflict] then
                self:LogDebug("ERROR", "Module " .. name .. " conflicts with enabled module " .. conflict, "Core")
                return false
            end
        end
    end

    -- Validate settings
    if module.ValidateSettings and not module:ValidateSettings(self.db.moduleSettings[name] or {}) then
        self:LogDebug("ERROR", "Invalid settings for module " .. name, "Core")
        return false
    end

    self.db.enabledModules[name] = true

    if module.Initialize then
        local success = module:Initialize()
        if success == false then
            self.db.enabledModules[name] = false
            self:LogDebug("ERROR", "Module " .. name .. " failed to initialize", "Core")
            return false
        end
    end

    self:LogDebug("INFO", "Module enabled: " .. name, "Core")
    return true
end

-- Disable module
function fizzure:DisableModule(name)
    local module = self.modules[name]
    if not module then return false end

    -- Check if other modules depend on this one
    for otherName, otherModule in pairs(self.modules) do
        if self.db.enabledModules[otherName] and otherModule.dependencies then
            for _, dep in ipairs(otherModule.dependencies) do
                if dep == name then
                    self:LogDebug("ERROR", "Cannot disable " .. name .. " - " .. otherName .. " depends on it", "Core")
                    return false
                end
            end
        end
    end

    self.db.enabledModules[name] = false

    if module.Shutdown then
        module:Shutdown()
    end

    -- Notify other modules
    for otherName, otherModule in pairs(self.modules) do
        if otherModule.OnModuleUnloaded then
            otherModule:OnModuleUnloaded(name)
        end
    end

    self:LogDebug("INFO", "Module disabled: " .. name, "Core")
    return true
end

-- Get module settings
function fizzure:GetModuleSettings(moduleName)
    return self.db.moduleSettings[moduleName] or {}
end

-- Set module settings
function fizzure:SetModuleSettings(moduleName, settings)
    local module = self.modules[moduleName]
    if module and module.ValidateSettings then
        if not module:ValidateSettings(settings) then
            self:LogDebug("ERROR", "Invalid settings provided for " .. moduleName, "Core")
            return false
        end
    end

    self.db.moduleSettings[moduleName] = settings
    self:LogDebug("INFO", "Settings updated for module: " .. moduleName, "Core")
    return true
end

-- Create minimap button
function fizzure:CreateMinimapButton()
    local button = CreateFrame("Button", "FizzureMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    -- Button texture
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    button:SetPushedTexture("Interface\\Icons\\INV_Misc_Gear_02")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Position on minimap
    local function updatePosition()
        local angle = math.rad(self.db.minimap.minimapPos or 225)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    updatePosition()

    -- Click handler
    button:SetScript("OnClick", function(self, clickButton)
        if clickButton == "LeftButton" then
            fizzure:ToggleMainWindow()
        elseif clickButton == "RightButton" then
            fizzure:ShowQuickStatus()
        end
    end)

    -- Drag handler
    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local angle = math.atan2(self:GetTop() - Minimap:GetTop(), self:GetLeft() - Minimap:GetLeft())
        fizzure.db.minimap.minimapPos = math.deg(angle)
        updatePosition()
    end)

    -- Tooltip
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

-- Enhanced main window with categories
function fizzure:CreateMainWindow()
    local frame = CreateFrame("Frame", "FizzureMainWindow", UIParent)
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetSize(680, 30)
    titleBar:SetPoint("TOP", 0, -10)

    local title = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", 10, 0)
    title:SetText("Fizzure - Module Control Center")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Category tabs
    frame.categoryTabs = {}
    frame.selectedCategory = "Class-Specific"

    local tabWidth = 100
    local tabIndex = 0
    for categoryName, _ in pairs(self.moduleCategories) do
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(tabWidth, 25)
        tab:SetPoint("TOPLEFT", 20 + (tabIndex * tabWidth), -45)

        -- Tab appearance
        tab:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        tab:SetBackdropColor(0.2, 0.2, 0.2, 0.8)

        local tabText = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        tabText:SetPoint("CENTER")
        tabText:SetText(categoryName)
        tab.text = tabText

        tab:SetScript("OnClick", function()
            fizzure:SelectCategory(categoryName)
        end)

        frame.categoryTabs[categoryName] = tab
        tabIndex = tabIndex + 1
    end

    -- Module list (left panel)
    local moduleList = CreateFrame("ScrollFrame", "AMModuleList", frame, "UIPanelScrollFrameTemplate")
    moduleList:SetSize(200, 350)
    moduleList:SetPoint("TOPLEFT", 20, -75)

    local moduleListContent = CreateFrame("Frame", nil, moduleList)
    moduleListContent:SetSize(200, 350)
    moduleList:SetScrollChild(moduleListContent)

    -- Module details (right panel)
    local detailsPanel = CreateFrame("Frame", "AMDetailsPanel", frame)
    detailsPanel:SetSize(450, 350)
    detailsPanel:SetPoint("TOPRIGHT", -20, -75)
    detailsPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    detailsPanel:SetBackdropColor(0, 0, 0, 0.8)

    -- Enhanced status bar
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetSize(680, 35)
    statusBar:SetPoint("BOTTOM", 0, 10)
    statusBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    statusBar:SetBackdropColor(0, 0, 0, 0.5)

    local statusText = statusBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusText:SetPoint("LEFT", 10, 5)
    statusText:SetText("Ready")

    -- Module count by category
    local categoryStats = statusBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    categoryStats:SetPoint("LEFT", 10, -8)
    categoryStats:SetText("")

    -- Debug toggle button
    local debugBtn = CreateFrame("Button", nil, statusBar, "UIPanelButtonTemplate")
    debugBtn:SetSize(80, 20)
    debugBtn:SetPoint("RIGHT", -100, 0)
    debugBtn:SetText("Debug: OFF")
    debugBtn:SetScript("OnClick", function()
        fizzure:ToggleDebug()
        debugBtn:SetText("Debug: " .. (fizzure.debug.enabled and fizzure.debug.level or "OFF"))
    end)

    -- Reload UI button
    local reloadBtn = CreateFrame("Button", nil, statusBar, "UIPanelButtonTemplate")
    reloadBtn:SetSize(80, 20)
    reloadBtn:SetPoint("RIGHT", -10, 0)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)

    -- Store references
    frame.moduleList = moduleListContent
    frame.detailsPanel = detailsPanel
    frame.statusText = statusText
    frame.categoryStats = categoryStats
    frame.debugBtn = debugBtn

    self.frames.mainWindow = frame

    -- Enhanced update function
    function frame:UpdateModuleList()
        -- Clear existing buttons
        if self.moduleButtons then
            for i = 1, #self.moduleButtons do
                self.moduleButtons[i]:Hide()
            end
        end

        self.moduleButtons = {}
        local yOffset = -10

        -- Get modules for selected category
        local categoryModules = fizzure.moduleCategories[fizzure.frames.mainWindow.selectedCategory] or {}

        for moduleName, module in pairs(categoryModules) do
            local button = CreateFrame("Button", nil, self.moduleList)
            button:SetSize(180, 35)
            button:SetPoint("TOPLEFT", 10, yOffset)

            -- Button background
            button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
            button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
            button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")

            -- Module name
            local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            text:SetPoint("LEFT", 10, 5)
            text:SetText(moduleName)

            -- Version/Author info
            local info = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            info:SetPoint("LEFT", 10, -5)
            info:SetText("v" .. (module.version or "1.0") .. " by " .. (module.author or "Unknown"))
            info:SetTextColor(0.7, 0.7, 0.7)

            -- Status indicators
            local statusIcon = button:CreateTexture(nil, "OVERLAY")
            statusIcon:SetSize(12, 12)
            statusIcon:SetPoint("RIGHT", -25, 0)

            if fizzure.db.enabledModules[moduleName] then
                statusIcon:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
            else
                statusIcon:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
            end

            -- Class restriction indicator
            if module.classRestriction then
                local classIcon = button:CreateTexture(nil, "OVERLAY")
                classIcon:SetSize(16, 16)
                classIcon:SetPoint("RIGHT", -5, 0)
                classIcon:SetTexture("Interface\\Icons\\ClassIcon_" .. module.classRestriction)
            end

            -- Click handler
            button:SetScript("OnClick", function()
                fizzure:ShowModuleDetails(moduleName, module)
            end)

            table.insert(self.moduleButtons, button)
            yOffset = yOffset - 40
        end

        -- Update scroll content height
        self.moduleList:SetHeight(math.max(350, #self.moduleButtons * 40))

        -- Update status
        fizzure.frames.mainWindow.statusText:SetText("Ready - " .. fizzure:GetModuleCount() .. " modules loaded")
        fizzure.frames.mainWindow.categoryStats:SetText(fizzure:GetCategoryStats())
    end

    -- Initialize with first category
    self:SelectCategory(frame.selectedCategory)
end

-- Select category tab
function fizzure:SelectCategory(categoryName)
    local frame = self.frames.mainWindow
    if not frame then return end

    frame.selectedCategory = categoryName

    -- Update tab appearance
    for name, tab in pairs(frame.categoryTabs) do
        if name == categoryName then
            tab:SetBackdropColor(0.3, 0.3, 0.8, 0.8)
            tab.text:SetTextColor(1, 1, 1)
        else
            tab:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
            tab.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end

    frame:UpdateModuleList()
end

-- Get module count
function fizzure:GetModuleCount()
    local count = 0
    for _ in pairs(self.modules) do
        count = count + 1
    end
    return count
end

-- Get category statistics
function fizzure:GetCategoryStats()
    local stats = {}
    for categoryName, modules in pairs(self.moduleCategories) do
        local count = 0
        local enabled = 0
        for name, _ in pairs(modules) do
            count = count + 1
            if self.db.enabledModules[name] then
                enabled = enabled + 1
            end
        end
        if count > 0 then
            table.insert(stats, categoryName .. ": " .. enabled .. "/" .. count)
        end
    end
    return table.concat(stats, " | ")
end

-- Enhanced module details with proper scrolling & autosizing
function fizzure:ShowModuleDetails(moduleName, module)
    local panel = self.frames.mainWindow and self.frames.mainWindow.detailsPanel
    if not panel then return end

    -- Clear old scroll/content
    if panel.scroll then panel.scroll:Hide() panel.scroll = nil end
    if panel.content then panel.content:Hide() panel.content = nil end

    -- ScrollFrame
    local scroll = CreateFrame("ScrollFrame", "Fizzure_DetailScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8) -- leave room for the scrollbar
    panel.scroll = scroll

    -- Content (scroll child)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT")
    content:SetSize(1, 1) -- will be sized after building
    scroll:SetScrollChild(content)
    panel.content = content

    -- Keep content width aligned to the visible scroll region
    local function syncContentWidth()
        local w = scroll:GetWidth() or 0
        if w > 0 then content:SetWidth(w - 18) end
    end
    scroll:SetScript("OnShow", syncContentWidth)
    scroll:SetScript("OnSizeChanged", syncContentWidth)
    syncContentWidth()

    -- Enable mouse wheel
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local step = 28
        local range = self:GetVerticalScrollRange() or 0
        local new = current - delta * step
        if new < 0 then new = 0 elseif new > range then new = range end
        self:SetVerticalScroll(new)
    end)

    -- Helper to size content height from its children
    local function sizeContentFromChildren()
        local minBottom = 0
        local maxTop = 0
        -- include content itself as a fallback baseline
        maxTop = content:GetTop() or 0
        minBottom = content:GetBottom() or 0

        local kids = { content:GetChildren() }
        for _, child in ipairs(kids) do
            if child:IsShown() then
                local top = child:GetTop() or 0
                local bottom = child:GetBottom() or 0
                if top > maxTop then maxTop = top end
                if bottom < minBottom then minBottom = bottom end
            end
        end

        -- Height we need to encompass all children (+ padding)
        local needed = (maxTop - minBottom) + 16
        local minVisible = math.max(0, (panel:GetHeight() or 350) - 16)
        content:SetHeight(math.max(minVisible, needed))
        scroll:UpdateScrollChildRect()
    end

    ----------------------------------------------------------------
    -- Build the details UI into `content`
    ----------------------------------------------------------------
    local y = -20

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, y)
    title:SetText(moduleName)
    y = y - 25

    if module.category or module.classRestriction then
        local info = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        info:SetPoint("TOP", 0, y)
        info:SetText(("Category: %s%s"):format(
                module.category or "General",
                module.classRestriction and (" | Class: " .. module.classRestriction) or ""
        ))
        info:SetTextColor(0.8, 0.8, 1)
        y = y - 20
    end

    local ver = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ver:SetPoint("TOP", 0, y)
    ver:SetText("Version " .. (module.version or "1.0") .. " by " .. (module.author or "Unknown"))
    ver:SetTextColor(0.7, 0.7, 0.7)
    y = y - 25

    if module.dependencies and #module.dependencies > 0 then
        local dep = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        dep:SetPoint("TOPLEFT", 20, y)
        dep:SetText("Dependencies: " .. table.concat(module.dependencies, ", "))
        dep:SetTextColor(1, 1, 0.3)
        y = y - 20
    end

    if module.conflicts and #module.conflicts > 0 then
        local conf = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        conf:SetPoint("TOPLEFT", 20, y)
        conf:SetText("Conflicts: " .. table.concat(module.conflicts, ", "))
        conf:SetTextColor(1, 0.3, 0.3)
        y = y - 25
    end

    -- Enable/Disable
    local enableCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 20, y)
    enableCheck:SetSize(20, 20)
    enableCheck:SetChecked(self.db.enabledModules[moduleName])

    local enableLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 5, 0)
    enableLabel:SetText("Enable Module")
    y = y - 30

    enableCheck:SetScript("OnClick", function()
        local enabled = enableCheck:GetChecked()
        local ok
        if enabled then
            ok = fizzure:EnableModule(moduleName)
            if not ok then
                enableCheck:SetChecked(false)
                fizzure:ShowNotification("Module Error", "Failed to enable " .. moduleName, "error", 3)
            else
                fizzure:ShowNotification("Module Enabled", moduleName .. " is now active", "success", 3)
            end
        else
            ok = fizzure:DisableModule(moduleName)
            if not ok then
                enableCheck:SetChecked(true)
                fizzure:ShowNotification("Module Error", "Cannot disable " .. moduleName, "error", 3)
            else
                fizzure:ShowNotification("Module Disabled", moduleName .. " is now inactive", "info", 3)
            end
        end
        if ok and fizzure.frames.mainWindow and fizzure.frames.mainWindow.UpdateModuleList then
            fizzure.frames.mainWindow:UpdateModuleList()
        end
        fizzure:ShowModuleDetails(moduleName, module) -- repaint
    end)

    -- Debug controls
    local debugHdr = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    debugHdr:SetPoint("TOPLEFT", 20, y)
    debugHdr:SetText("Debug Controls")
    debugHdr:SetTextColor(1, 1, 0)
    y = y - 22

    local dbg = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    dbg:SetPoint("TOPLEFT", 20, y)
    dbg:SetSize(20, 20)
    dbg:SetChecked(fizzure.debug.enabled)

    local dbgLbl = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dbgLbl:SetPoint("LEFT", dbg, "RIGHT", 5, 0)
    dbgLbl:SetText("Enable Debug for " .. moduleName)
    y = y - 28

    dbg:SetScript("OnClick", function()
        if dbg:GetChecked() then
            if not fizzure.debug.enabled then fizzure:ToggleDebug("DRY_RUN") end
        else
            if fizzure.debug.enabled then fizzure:ToggleDebug() end
        end
        if fizzure.frames.mainWindow and fizzure.frames.mainWindow.debugBtn then
            fizzure.frames.mainWindow.debugBtn:SetText("Debug: " .. (fizzure.debug.enabled and fizzure.debug.level or "OFF"))
        end
    end)

    -- Module-specific configuration
    if module and module.CreateConfigUI then
        local cfgHdr = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cfgHdr:SetPoint("TOPLEFT", 20, y)
        cfgHdr:SetText("Module Configuration:")
        cfgHdr:SetTextColor(0.3, 1, 0.3)
        y = y - 22

        -- IMPORTANT: Create all config controls with `content` as the parent
        -- and anchor them relative to previous controls, not absolute screen points.
        -- If your builder returns a new y, use it; otherwise leave as is.
        local returnedY = module:CreateConfigUI(content, 20, y)
        if type(returnedY) == "number" then y = returnedY end
    else
        local noCfg = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        noCfg:SetPoint("TOPLEFT", 20, y)
        noCfg:SetText("No configuration options available")
        noCfg:SetTextColor(0.7, 0.7, 0.7)
        y = y - 16
    end

    -- Finalize sizing & scroll range
    sizeContentFromChildren()
    content:Show()
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

-- Quick status window
function fizzure:ShowQuickStatus()
    local popup = CreateFrame("Frame", "AMQuickStatus", UIParent)
    popup:SetSize(250, 150)
    popup:SetPoint("CENTER")
    popup:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    popup:SetBackdropColor(0, 0, 0, 0.9)

    local title = popup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Quick Status")

    local yOffset = -45
    for moduleName, module in pairs(self.modules) do
        if self.db.enabledModules[moduleName] and module.GetQuickStatus then
            local status = popup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            status:SetPoint("TOPLEFT", 15, yOffset)
            status:SetText(moduleName .. ": " .. module:GetQuickStatus())
            yOffset = yOffset - 20
        end
    end

    popup:Show()

    local elapsed = 0
    notification:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= (duration or 5) then
            self:SetScript("OnUpdate", nil)
            popup:Hide()
        end
    end)
end

-- Notification system
function fizzure:CreateNotificationSystem()
    local container = CreateFrame("Frame", "AMNotificationContainer", UIParent)
    container:SetSize(300, 400)
    container:SetPoint("CENTER", 0, 100)
    container:SetFrameStrata("DIALOG")
    container.notifications = {}
    self.frames.notificationContainer = container
end

function fizzure:ShowNotification(title, message, type, duration)
    if not self.db.notifications.enabled then return end

    local container = self.frames.notificationContainer
    if not container then return end

    local notification = CreateFrame("Frame", nil, container)
    notification:SetSize(280, 80)
    notification:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })

    -- Color based on type
    local colors = {
        warning = {1, 0.8, 0, 0.9},
        error = {1, 0.3, 0.3, 0.9},
        info = {0.3, 0.8, 1, 0.9},
        success = {0.3, 1, 0.3, 0.9}
    }
    local color = colors[type] or colors.info
    notification:SetBackdropColor(color[1], color[2], color[3], color[4])

    -- Title
    local titleText = notification:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -10)
    titleText:SetText(title)
    titleText:SetTextColor(1, 1, 1)

    -- Message
    local messageText = notification:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    messageText:SetPoint("TOP", 0, -30)
    messageText:SetSize(260, 40)
    messageText:SetText(message)
    messageText:SetTextColor(1, 1, 1)
    messageText:SetJustifyH("CENTER")

    -- Position notification
    local numNotifications = #container.notifications
    notification:SetPoint("TOP", 0, -(numNotifications * 90))

    table.insert(container.notifications, notification)

    -- Play sound
    if self.db.notifications.sound then
        PlaySound("TellMessage")
    end

    -- Auto-remove after duration - FIXED: Proper cleanup
    local function removeNotification()
        if notification and notification:GetParent() then
            notification:Hide()
            notification:SetParent(nil)

            -- Remove from notifications list
            for i = #container.notifications, 1, -1 do
                if container.notifications[i] == notification then
                    table.remove(container.notifications, i)
                    break
                end
            end

            -- Reposition remaining notifications
            for i, notif in ipairs(container.notifications) do
                notif:ClearAllPoints()
                notif:SetPoint("TOP", container, "TOP", 0, -((i-1) * 90))
            end
        end
    end

    notification:Show()

    local elapsed = 0
    notification:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= (duration or 5) then
            self:SetScript("OnUpdate", nil)
            removeNotification()
        end
    end)
end

-- Elevate module config windows
function fizzure:ElevateConfigWindow(frame)
    -- Parent to UIParent so it does NOT inherit any transparency from the control center
    frame:SetParent(UIParent)

    -- Always float above the control center
    frame:SetToplevel(true)
    frame:SetFrameStrata("DIALOG")  -- higher than MEDIUM; you could also use "FULLSCREEN_DIALOG" if desired
    -- Ensure a higher frame level than the control center, even if strata collides
    local base = (self.frames.mainWindow and self.frames.mainWindow:GetFrameLevel() or 10)
    frame:SetFrameLevel(math.max(base + 50, frame:GetFrameLevel()))

    -- Solid, opaque backdrop (no transparency)
    if not frame.SetBackdrop then
        -- 3.3.5 has SetBackdrop on frames with BackdropTemplate via XML.
        -- If your frame was created without a template, you can still call SetBackdrop in 3.3.5.
    end
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)    -- fully opaque
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Safety niceties
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if not frame._dragBound then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
        frame._dragBound = true
    end
    frame:SetClampedToScreen(true)
    frame:SetAlpha(1)            -- ensure no residual alpha
    frame:Raise()                -- in case of level ties within the same strata
end


-- Debug System Implementation
function fizzure:InitializeDebugSystem()
    -- Merge debug settings with core db
    if not self.db.debug then
        self.db.debug = defaultCoreSettings.debug
    else
        for k, v in pairs(defaultCoreSettings.debug) do
            if self.db.debug[k] == nil then
                self.db.debug[k] = v
            end
        end
    end

    -- Initialize debug state
    self.debug.enabled = self.db.debug.enabled
    self.debug.level = self.db.debug.level

    -- Create debug frame if enabled
    if self.db.debug.showDebugFrame then
        self:CreateDebugFrame()
    end

    -- Create debug API wrappers
    self:CreateDebugWrappers()

    if self.debug.enabled then
        self:LogDebug("DEBUG", "Debug system initialized - Level: " .. self.debug.level)
    end
end

-- Debug logging function
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
        local colorCode = {
            DEBUG = "|cff888888",
            INFO = "|cff00ffff",
            WARN = "|cffffff00",
            ACTION = "|cff00ff00",
            ERROR = "|cffff0000"
        }

        local logEntry = {
            time = timestamp,
            level = level,
            module = moduleName or "Core",
            message = message
        }

        -- Store in history
        table.insert(self.debug.logHistory, logEntry)
        if #self.debug.logHistory > self.debug.maxLogHistory then
            table.remove(self.debug.logHistory, 1)
        end

        -- Display in debug frame
        if self.frames.debugFrame and self.frames.debugFrame:IsShown() then
            self:UpdateDebugFrame()
        end

        -- Optional chat output
        if self.db.debug.logToChat then
            local chatMessage = string.format("%s%s [%s] %s: %s|r",
                    colorCode[level], timestamp, level, prefix, message)
            print(chatMessage)
        end
    end
end

-- Create debug API wrappers
function fizzure:CreateDebugWrappers()
    -- Store original functions
    if not self.debug.originalFunctions then
        self.debug.originalFunctions = {}
    end

    -- Create wrapper namespace
    self.DebugAPI = {}

    -- UseItemByName wrapper
    self.DebugAPI.UseItemByName = function(itemName)
        if self.debug.enabled and (self.debug.level == "DRY_RUN" or self.debug.level == "VERBOSE") then
            self:LogDebug("ACTION", "DRY RUN: Would use item '" .. (itemName or "nil") .. "'")
            return true -- Pretend success
        else
            self:LogDebug("ACTION", "Using item: " .. (itemName or "nil"))
            return UseItemByName(itemName)
        end
    end

    -- GetItemCount wrapper (read-only, always execute)
    self.DebugAPI.GetItemCount = function(itemName)
        local count = GetItemCount(itemName)
        if self.debug.enabled and self.debug.level == "VERBOSE" then
            self:LogDebug("DEBUG", "Item count for '" .. (itemName or "nil") .. "': " .. count)
        end
        return count
    end

    -- Pet happiness wrapper (read-only, always execute)
    self.DebugAPI.GetPetHappiness = function()
        local happiness, damage, loyalty = GetPetHappiness()
        if self.debug.enabled and self.debug.level == "VERBOSE" then
            self:LogDebug("DEBUG", "Pet happiness: " .. (happiness or "nil"))
        end
        return happiness, damage, loyalty
    end

    -- Unit existence wrapper (read-only, always execute)
    self.DebugAPI.UnitExists = function(unit)
        local exists = UnitExists(unit)
        if self.debug.enabled and self.debug.level == "VERBOSE" then
            self:LogDebug("DEBUG", "Unit '" .. (unit or "nil") .. "' exists: " .. tostring(exists))
        end
        return exists
    end

    -- Notification wrapper
    self.DebugAPI.ShowNotification = function(title, message, type, duration)
        if self.debug.enabled and (self.debug.level == "DRY_RUN" or self.debug.level == "VERBOSE") then
            self:LogDebug("ACTION", "DRY RUN: Would show notification - " .. title .. ": " .. message)
            return
        else
            self:LogDebug("INFO", "Showing notification: " .. title)
            return self:ShowNotification(title, message, type, duration)
        end
    end
end

-- Create debug frame
function fizzure:CreateDebugFrame()
    if self.frames.debugFrame then return end

    local frame = CreateFrame("Frame", "FizzureDebugFrame", UIParent)
    frame:SetSize(500, 300)
    frame:SetPoint("TOPRIGHT", -20, -100)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    -- Title with debug indicator
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Fizzure Debug Console")
    title:SetTextColor(1, 1, 0)

    -- Debug level indicator
    local levelText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    levelText:SetPoint("TOP", 0, -35)
    levelText:SetText("Debug Level: " .. (self.debug.level or "OFF"))
    levelText:SetTextColor(0, 1, 0)
    frame.levelText = levelText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 20)
    clearBtn:SetPoint("TOPRIGHT", -30, -35)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        self.debug.logHistory = {}
        self:UpdateDebugFrame()
    end)

    -- Log display (scrollable)
    local scrollFrame = CreateFrame("ScrollFrame", "Fizzure_LogDisplay", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(460, 220)
    scrollFrame:SetPoint("TOP", 0, -60)

    local logContent = CreateFrame("Frame", nil, scrollFrame)
    logContent:SetSize(460, 220)
    scrollFrame:SetScrollChild(logContent)

    frame.scrollFrame = scrollFrame
    frame.logContent = logContent
    frame.logEntries = {}

    self.frames.debugFrame = frame

    if self.debug.enabled then
        self:UpdateDebugFrame()
    end
end

-- Update debug frame content
function fizzure:UpdateDebugFrame()
    local frame = self.frames.debugFrame
    if not frame then return end

    -- Clear existing log entries
    if frame.logEntries then
        for _, entry in ipairs(frame.logEntries) do
            entry:Hide()
        end
    end
    frame.logEntries = {}

    -- Update level text
    frame.levelText:SetText("Debug Level: " .. (self.debug.level or "OFF"))

    -- Add log entries
    local yOffset = -5
    for i = math.max(1, #self.debug.logHistory - 20), #self.debug.logHistory do
        local logEntry = self.debug.logHistory[i]
        if logEntry then
            local entryFrame = CreateFrame("Frame", nil, frame.logContent)
            entryFrame:SetSize(450, 15)
            entryFrame:SetPoint("TOPLEFT", 5, yOffset)

            local text = entryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            text:SetPoint("LEFT", 0, 0)
            text:SetSize(450, 15)
            text:SetJustifyH("LEFT")

            local colorCode = {
                DEBUG = "|cff888888",
                INFO = "|cff00ffff",
                WARN = "|cffffff00",
                ACTION = "|cff00ff00",
                ERROR = "|cffff0000"
            }

            local message = string.format("%s[%s] %s [%s]: %s|r",
                    colorCode[logEntry.level],
                    logEntry.time,
                    logEntry.level,
                    logEntry.module,
                    logEntry.message
            )

            text:SetText(message)

            table.insert(frame.logEntries, entryFrame)
            yOffset = yOffset - 15
        end
    end

    -- Update scroll range
    local contentHeight = math.max(220, #frame.logEntries * 15)
    frame.logContent:SetHeight(contentHeight)
end

-- Toggle debug mode
function fizzure:ToggleDebug(level)
    if level then
        self.debug.level = level
        self.db.debug.level = level
    end

    self.debug.enabled = not self.debug.enabled
    self.db.debug.enabled = self.debug.enabled

    if self.debug.enabled then
        self:LogDebug("INFO", "Debug mode ENABLED - Level: " .. self.debug.level)

        -- Show debug frame if configured
        if self.db.debug.showDebugFrame and not self.frames.debugFrame then
            self:CreateDebugFrame()
        end

        if self.frames.debugFrame then
            self.frames.debugFrame:Show()
            self:UpdateDebugFrame()
        end

        -- Visual indicator on minimap button
        if self.frames.minimapButton then
            self.frames.minimapButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_02")
        end

        -- Notify all modules
        for moduleName, module in pairs(self.modules) do
            if module.OnDebugToggle then
                module:OnDebugToggle(true, self.debug.level)
            end
        end
    else
        self:LogDebug("INFO", "Debug mode DISABLED")

        -- Hide debug frame
        if self.frames.debugFrame then
            self.frames.debugFrame:Hide()
        end

        -- Restore minimap button
        if self.frames.minimapButton then
            self.frames.minimapButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
        end

        -- Notify all modules
        for moduleName, module in pairs(self.modules) do
            if module.OnDebugToggle then
                module:OnDebugToggle(false, "OFF")
            end
        end
    end
end

-- Debug helper for modules
function fizzure:IsDebugEnabled(level)
    if not self.debug.enabled then return false end

    if level == "VERBOSE" then
        return self.debug.level == "VERBOSE"
    elseif level == "DRY_RUN" then
        return self.debug.level == "DRY_RUN" or self.debug.level == "VERBOSE"
    elseif level == "LOG" then
        return true -- All debug levels include logging
    end

    return self.debug.enabled
end

-- Get debug API wrappers for modules
function fizzure:GetDebugAPI()
    return self.DebugAPI
end

-- Core initialization
fizzure:Initialize()

-- Enhanced slash commands with module management
SLASH_FIZZURE1 = "/fizz"
SLASH_FIZZURE2 = "/fizzure"
SlashCmdList["FIZZURE"] = function(msg)
    local command, arg1, arg2, arg3 = strsplit(" ", string.lower(msg))

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
                    local classInfo = module.classRestriction and (" [" .. module.classRestriction .. "]") or ""
                    print("    " .. moduleName .. classInfo .. ": " .. status)
                end
            end
        end
    elseif command == "debug" then
        if arg1 == "on" or arg1 == "enable" then
            if not fizzure.debug.enabled then
                fizzure:ToggleDebug(arg2 or "DRY_RUN")
            end
            print("|cff00ff00Fizzure:|r Debug enabled - Level: " .. fizzure.debug.level)
        elseif arg1 == "off" or arg1 == "disable" then
            if fizzure.debug.enabled then
                fizzure:ToggleDebug()
            end
            print("|cff00ff00Fizzure:|r Debug disabled")
        elseif arg1 == "level" and arg2 then
            local validLevels = {log = "LOG", dryrun = "DRY_RUN", verbose = "VERBOSE"}
            local newLevel = validLevels[arg2]
            if newLevel then
                fizzure.debug.level = newLevel
                fizzure.db.debug.level = newLevel
                print("|cff00ff00Fizzure:|r Debug level set to: " .. newLevel)
            else
                print("|cffff0000Fizzure:|r Invalid debug level. Use: log, dryrun, verbose")
            end
        elseif arg1 == "console" or arg1 == "show" then
            if fizzure.frames.debugFrame then
                fizzure.frames.debugFrame:Show()
                fizzure:UpdateDebugFrame()
            else
                fizzure:CreateDebugFrame()
                fizzure.frames.debugFrame:Show()
            end
        elseif arg1 == "clear" then
            fizzure.debug.logHistory = {}
            if fizzure.frames.debugFrame then
                fizzure:UpdateDebugFrame()
            end
            print("|cff00ff00Fizzure:|r Debug log cleared")
        else
            print("|cff00ff00Fizzure Debug Commands:|r")
            print("  /fizz debug on/off - Enable/disable debug mode")
            print("  /fizz debug level <log|dryrun|verbose> - Set debug level")
            print("  /fizz debug console - Show debug console")
            print("  /fizz debug clear - Clear debug log")
        end
    elseif command == "status" then
        print("|cff00ff00Fizzure Status:|r")
        print("  Debug Mode: " .. (fizzure.debug.enabled and ("ON - " .. fizzure.debug.level) or "OFF"))
        print("  " .. fizzure:GetCategoryStats())
    else
        print("|cff00ff00Fizzure Commands:|r")
        print("  /fizz [show] - Open main window")
        print("  /fizz enable/disable <module> - Enable/disable module")
        print("  /fizz list - List all modules")
        print("  /fizz debug <command> - Debug controls")
        print("  /fizz status - Show system status")
    end
end