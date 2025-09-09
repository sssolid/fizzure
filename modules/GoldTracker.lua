-- GoldTracker.lua - Refactored Gold Tracking Module
local GoldTrackerModule = {}

-- REQUIRED: Module manifest
function GoldTrackerModule:GetManifest()
    return {
        name = "Gold Tracker",
        version = "2.1",
        author = "Fizzure Team",
        category = "Economy",
        description = "Track gold earnings, spending, and session statistics",
        
        minLevel = 1,
        
        hasUI = true,
        hasSettings = true,
        hasKeybindings = true
    }
end

-- REQUIRED: Default settings
function GoldTrackerModule:GetDefaultSettings()
    return {
        enabled = true,
        showStatusFrame = true,
        statusFrameMinimized = false,
        framePosition = nil,
        
        -- Tracking options
        trackSession = true,
        trackHourly = true,
        trackDaily = true,
        showNetChange = true,
        
        -- Display options
        showCopper = false,
        useShortFormat = false,
        updateInterval = 5,
        
        -- Notifications
        notifications = {
            enabled = true,
            goldGain = true,
            goldLoss = true,
            milestones = true,
            thresholds = {1000000, 5000000, 10000000} -- 100g, 500g, 1000g in copper
        },
        
        -- History settings
        maxHistoryDays = 30,
        autoCleanHistory = true,
        
        -- Keybindings
        keybindings = {
            toggleStatus = "ALT-G",
            showDetails = "ALT-SHIFT-G",
            reset = "ALT-CTRL-G"
        }
    }
end

-- Settings validation
function GoldTrackerModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
           type(settings.trackSession) == "boolean" and
           type(settings.updateInterval) == "number" and
           settings.updateInterval > 0
end

-- Core initialization
function GoldTrackerModule:OnInitialize()
    -- Initialize settings
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Initialize tracking data
    self.currentGold = GetMoney()
    self.sessionStart = GetTime()
    self.sessionStartGold = self.currentGold
    self.lastUpdate = 0
    self.goldHistory = {}
    
    -- Load persistent data
    self:LoadPersistentData()
    
    -- Create event frame
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
    self.eventFrame:RegisterEvent("MERCHANT_SHOW")
    self.eventFrame:RegisterEvent("MERCHANT_CLOSED")
    self.eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
    self.eventFrame:RegisterEvent("TRADE_MONEY_CHANGED")
    self.eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    
    -- Initialize statistics
    self:InitializeStatistics()
    
    self:Log("INFO", "Gold Tracker initialized with " .. FizzureCommon:FormatMoney(self.currentGold, true))
    return true
end

-- UI creation
function GoldTrackerModule:OnUIReady()
    -- Create status frame
    self:CreateStatusFrame()
    
    -- Create details window
    self:CreateDetailsWindow()
    
    -- Show status frame if enabled
    if self.settings.showStatusFrame then
        self.statusFrame:Show()
    end
    
    self:Log("INFO", "Gold Tracker UI ready")
    return true
end

-- Module activation
function GoldTrackerModule:OnEnable()
    -- Start update timer
    self.updateTimer = FizzureCommon:NewTicker(self.settings.updateInterval, function()
        self:OnUpdate()
    end)
    
    -- Register keybindings
    self:RegisterKeybindings()
    
    -- Show status frame if configured
    if self.settings.showStatusFrame and self.statusFrame then
        self.statusFrame:Show()
    end
    
    -- Initial update
    self:UpdateGoldTracking()
    self:UpdateDisplay()
    
    self.ui.ShowNotification("Gold Tracker", "Money tracking activated", "success", 2)
    self:Log("INFO", "Gold Tracker enabled")
    
    return true
end

-- Module deactivation
function GoldTrackerModule:OnDisable()
    -- Stop timer
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Hide UI
    if self.statusFrame then
        self.statusFrame:Hide()
    end
    
    if self.detailsWindow then
        self.detailsWindow:Hide()
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    -- Save data before disabling
    self:SavePersistentData()
    
    self.ui.ShowNotification("Gold Tracker", "Money tracking deactivated", "info", 2)
    self:Log("INFO", "Gold Tracker disabled")
    
    return true
end

-- Settings update handler
function GoldTrackerModule:OnSettingsUpdate(newSettings)
    local oldSettings = self.settings
    self.settings = newSettings
    
    -- Handle status frame visibility
    if oldSettings.showStatusFrame ~= newSettings.showStatusFrame then
        if newSettings.showStatusFrame and self.statusFrame then
            self.statusFrame:Show()
        elseif self.statusFrame then
            self.statusFrame:Hide()
        end
    end
    
    -- Update timer interval
    if oldSettings.updateInterval ~= newSettings.updateInterval then
        if self.updateTimer then
            self.updateTimer:Cancel()
            self.updateTimer = FizzureCommon:NewTicker(newSettings.updateInterval, function()
                self:OnUpdate()
            end)
        end
    end
    
    -- Update keybindings
    if not self:CompareKeybindings(oldSettings.keybindings, newSettings.keybindings) then
        self:UnregisterKeybindings()
        self:RegisterKeybindings()
    end
    
    -- Update display
    self:UpdateDisplay()
    
    self:Log("INFO", "Settings updated")
end

-- Cleanup
function GoldTrackerModule:OnShutdown()
    -- Save data
    self:SavePersistentData()
    
    -- Stop timer
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
    
    -- Cleanup events
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame = nil
    end
    
    -- Cleanup UI
    if self.statusFrame then
        self.statusFrame:Hide()
        self.statusFrame = nil
    end
    
    if self.detailsWindow then
        self.detailsWindow:Hide()
        self.detailsWindow = nil
    end
    
    -- Unregister keybindings
    self:UnregisterKeybindings()
    
    self:Log("INFO", "Gold Tracker shutdown complete")
end

-- Create status frame
function GoldTrackerModule:CreateStatusFrame()
    self.statusFrame = self.ui.CreateStatusFrame("Gold Tracker", 180, 120)
    
    -- Position frame
    if self.settings.framePosition then
        self.statusFrame:ClearAllPoints()
        self.statusFrame:SetPoint(
            self.settings.framePosition.point,
            UIParent,
            self.settings.framePosition.point,
            self.settings.framePosition.x,
            self.settings.framePosition.y
        )
    end
    
    -- Save position when moved
    self.statusFrame.OnPositionChanged = function()
        local point, _, _, x, y = self.statusFrame:GetPoint()
        self.settings.framePosition = {
            point = point,
            x = x,
            y = y
        }
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
    
    -- Current gold label
    self.currentGoldLabel = self.ui.CreateLabel(self.statusFrame, "0g", "GameFontNormal")
    self.currentGoldLabel:SetPoint("TOP", 0, -25)
    
    -- Session change label
    self.sessionLabel = self.ui.CreateLabel(self.statusFrame, "Session: +0g", "GameFontNormalSmall")
    self.sessionLabel:SetPoint("TOP", 0, -45)
    
    -- Rate label
    self.rateLabel = self.ui.CreateLabel(self.statusFrame, "0g/hour", "GameFontNormalSmall")
    self.rateLabel:SetPoint("TOP", 0, -60)
    
    -- Details button
    local detailsButton = self.ui.CreateButton(self.statusFrame, "Details", function()
        self:ToggleDetailsWindow()
    end)
    detailsButton:SetSize(60, 20)
    detailsButton:SetPoint("BOTTOM", 0, 15)
    
    -- Toggle button
    local toggleButton = self.ui.CreateButton(self.statusFrame, "⌄", function()
        self:ToggleMinimize()
    end)
    toggleButton:SetSize(16, 16)
    toggleButton:SetPoint("TOPRIGHT", -5, -5)
    self.toggleButton = toggleButton
    
    self.statusFrame:Hide()
end

-- Create details window
function GoldTrackerModule:CreateDetailsWindow()
    self.detailsWindow = self.ui.CreateWindow("Gold Tracker Details", 450, 350)
    
    local content = self.detailsWindow.content
    
    -- Statistics panel
    local statsPanel = FizzureUI:CreatePanel(content, 200, 280, {
        point = "TOPLEFT",
        x = 10,
        y = -10
    }, true)
    
    -- History panel
    local historyPanel = FizzureUI:CreatePanel(content, 200, 280, {
        point = "TOPLEFT",
        relativeFrame = statsPanel,
        relativePoint = "TOPRIGHT",
        x = 20,
        y = 0
    }, true)
    
    -- Statistics content
    local statsTitle = self.ui.CreateLabel(statsPanel, "Statistics", "GameFontNormalLarge")
    statsTitle:SetPoint("TOP", 0, -15)
    
    self.statsLabels = {}
    local statNames = {"Current", "Session Start", "Session Change", "Hourly Rate", "Daily Rate", "Best Session", "Worst Session"}
    
    for i, name in ipairs(statNames) do
        local label = self.ui.CreateLabel(statsPanel, name .. ": 0g", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, -30 - (i * 20))
        self.statsLabels[name] = label
    end
    
    -- History content
    local historyTitle = self.ui.CreateLabel(historyPanel, "Recent History", "GameFontNormalLarge")
    historyTitle:SetPoint("TOP", 0, -15)
    
    local historyScroll = FizzureUI:CreateScrollFrame(historyPanel, 180, 200, 20, "GoldHistoryScroll")
    historyScroll:SetPoint("TOPLEFT", 10, -40)
    self.historyScroll = historyScroll
    
    -- Control buttons
    local resetButton = self.ui.CreateButton(content, "Reset Session", function()
        self:ResetSession()
    end)
    resetButton:SetSize(100, 25)
    resetButton:SetPoint("BOTTOM", -55, 15)
    
    local exportButton = self.ui.CreateButton(content, "Export Data", function()
        self:ExportData()
    end)
    exportButton:SetSize(100, 25)
    exportButton:SetPoint("BOTTOM", 55, 15)
    
    self.detailsWindow:Hide()
end

-- Event handling
function GoldTrackerModule:OnEvent(event, ...)
    if event == "PLAYER_MONEY" then
        self:UpdateGoldTracking()
    elseif event == "MERCHANT_SHOW" then
        self.inMerchant = true
    elseif event == "MERCHANT_CLOSED" then
        self.inMerchant = false
    elseif event == "MAIL_INBOX_UPDATE" then
        -- Delay update to catch mail money
        FizzureCommon:After(1, function()
            self:UpdateGoldTracking()
        end)
    elseif event == "TRADE_MONEY_CHANGED" then
        self.inTrade = true
    elseif event == "AUCTION_HOUSE_SHOW" then
        self.inAuction = true
    end
end

-- Update loop
function GoldTrackerModule:OnUpdate()
    self:UpdateDisplay()
    
    -- Auto-save history periodically
    if GetTime() - (self.lastHistorySave or 0) > 300 then -- Every 5 minutes
        self:SavePersistentData()
        self.lastHistorySave = GetTime()
    end
end

-- Core tracking logic
function GoldTrackerModule:UpdateGoldTracking()
    local newGold = GetMoney()
    local oldGold = self.currentGold
    local change = newGold - oldGold
    
    if change ~= 0 then
        self.currentGold = newGold
        
        -- Record the change
        self:RecordGoldChange(change)
        
        -- Check for notifications
        self:CheckNotifications(change, newGold)
        
        -- Update statistics
        self:UpdateStatistics(change)
        
        self:Log("DEBUG", string.format("Gold changed: %s (Total: %s)", 
            FizzureCommon:FormatMoney(change, true),
            FizzureCommon:FormatMoney(newGold, true)))
    end
end

-- Record gold change
function GoldTrackerModule:RecordGoldChange(change)
    local now = GetTime()
    local entry = {
        timestamp = now,
        change = change,
        total = self.currentGold,
        source = self:DetermineSource()
    }
    
    table.insert(self.goldHistory, entry)
    
    -- Limit history size
    while #self.goldHistory > 1000 do
        table.remove(self.goldHistory, 1)
    end
end

-- Determine source of gold change
function GoldTrackerModule:DetermineSource()
    if self.inMerchant then
        return "Merchant"
    elseif self.inTrade then
        return "Trade"
    elseif self.inAuction then
        return "Auction"
    else
        return "Other"
    end
end

-- Check for notifications
function GoldTrackerModule:CheckNotifications(change, newGold)
    if not self.settings.notifications.enabled then return end
    
    local absChange = math.abs(change)
    
    -- Milestone notifications
    if self.settings.notifications.milestones then
        for _, threshold in ipairs(self.settings.notifications.thresholds) do
            if self.currentGold - change < threshold and newGold >= threshold then
                self.ui.ShowNotification("Milestone Reached!", 
                    "You now have " .. FizzureCommon:FormatMoney(newGold, true), 
                    "success", 5)
                break
            end
        end
    end
    
    -- Large change notifications
    if change > 0 and self.settings.notifications.goldGain and absChange >= 10000 then -- 1g or more
        self.ui.ShowNotification("Gold Gained", 
            "+" .. FizzureCommon:FormatMoney(change, true), 
            "success", 3)
    elseif change < 0 and self.settings.notifications.goldLoss and absChange >= 50000 then -- 5g or more
        self.ui.ShowNotification("Gold Lost", 
            "-" .. FizzureCommon:FormatMoney(absChange, true), 
            "warning", 3)
    end
end

-- Update display
function GoldTrackerModule:UpdateDisplay()
    if not self.statusFrame then return end
    
    -- Current gold
    local goldText = self.settings.useShortFormat and 
        self:FormatGoldShort(self.currentGold) or
        FizzureCommon:FormatMoney(self.currentGold, true)
    self.currentGoldLabel:SetText(goldText)
    
    -- Session change
    local sessionChange = self.currentGold - self.sessionStartGold
    local sessionText = "Session: " .. (sessionChange >= 0 and "+" or "") .. 
        FizzureCommon:FormatMoney(sessionChange, true)
    self.sessionLabel:SetText(sessionText)
    
    if sessionChange > 0 then
        self.sessionLabel:SetSuccessColor()
    elseif sessionChange < 0 then
        self.sessionLabel:SetErrorColor()
    else
        self.sessionLabel:SetTextColor(unpack({0.9, 0.9, 0.9, 1}))
    end
    
    -- Rate calculation
    local sessionTime = GetTime() - self.sessionStart
    if sessionTime > 0 then
        local hourlyRate = (sessionChange / sessionTime) * 3600
        local rateText = FizzureCommon:FormatMoney(hourlyRate, true) .. "/hour"
        self.rateLabel:SetText(rateText)
    end
    
    -- Update details window if open
    if self.detailsWindow and self.detailsWindow:IsShown() then
        self:UpdateDetailsDisplay()
    end
end

-- Update details display
function GoldTrackerModule:UpdateDetailsDisplay()
    if not self.statsLabels then return end
    
    local sessionChange = self.currentGold - self.sessionStartGold
    local sessionTime = GetTime() - self.sessionStart
    local hourlyRate = sessionTime > 0 and (sessionChange / sessionTime) * 3600 or 0
    local dailyRate = hourlyRate * 24
    
    self.statsLabels["Current"]:SetText("Current: " .. FizzureCommon:FormatMoney(self.currentGold, true))
    self.statsLabels["Session Start"]:SetText("Session Start: " .. FizzureCommon:FormatMoney(self.sessionStartGold, true))
    self.statsLabels["Session Change"]:SetText("Session Change: " .. 
        (sessionChange >= 0 and "+" or "") .. FizzureCommon:FormatMoney(sessionChange, true))
    self.statsLabels["Hourly Rate"]:SetText("Hourly Rate: " .. FizzureCommon:FormatMoney(hourlyRate, true))
    self.statsLabels["Daily Rate"]:SetText("Daily Rate: " .. FizzureCommon:FormatMoney(dailyRate, true))
    
    -- Update history list
    self:UpdateHistoryDisplay()
end

-- Update history display
function GoldTrackerModule:UpdateHistoryDisplay()
    if not self.historyScroll then return end
    
    local content = self.historyScroll.content
    
    -- Clear existing items
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end
    
    -- Show recent history (last 20 entries)
    local startIndex = math.max(1, #self.goldHistory - 19)
    local yPos = -5
    
    for i = #self.goldHistory, startIndex, -1 do
        local entry = self.goldHistory[i]
        local timeStr = date("%H:%M:%S", entry.timestamp)
        local changeStr = (entry.change >= 0 and "+" or "") .. FizzureCommon:FormatMoney(entry.change, true)
        local text = timeStr .. " " .. changeStr .. " (" .. entry.source .. ")"
        
        local label = self.ui.CreateLabel(content, text, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 5, yPos)
        
        if entry.change > 0 then
            label:SetSuccessColor()
        elseif entry.change < 0 then
            label:SetErrorColor()
        end
        
        yPos = yPos - 15
    end
    
    self.historyScroll:UpdateScrollChildHeight()
end

-- Initialize statistics
function GoldTrackerModule:InitializeStatistics()
    self.statistics = {
        bestSession = 0,
        worstSession = 0,
        totalEarned = 0,
        totalSpent = 0,
        avgHourlyRate = 0
    }
end

-- Update statistics
function GoldTrackerModule:UpdateStatistics(change)
    if change > 0 then
        self.statistics.totalEarned = self.statistics.totalEarned + change
    else
        self.statistics.totalSpent = self.statistics.totalSpent + math.abs(change)
    end
    
    local sessionChange = self.currentGold - self.sessionStartGold
    if sessionChange > self.statistics.bestSession then
        self.statistics.bestSession = sessionChange
    end
    if sessionChange < self.statistics.worstSession then
        self.statistics.worstSession = sessionChange
    end
end

-- Utility methods
function GoldTrackerModule:FormatGoldShort(copper)
    local gold = math.floor(copper / 10000)
    if gold >= 1000000 then
        return string.format("%.1fM", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.1fK", gold / 1000)
    else
        return tostring(gold) .. "g"
    end
end

function GoldTrackerModule:CompareKeybindings(old, new)
    for key, value in pairs(old) do
        if new[key] ~= value then
            return false
        end
    end
    return true
end

function GoldTrackerModule:ResetSession()
    self.sessionStart = GetTime()
    self.sessionStartGold = self.currentGold
    self.goldHistory = {}
    self:UpdateDisplay()
    self.ui.ShowNotification("Session Reset", "Gold tracking session reset", "info", 2)
end

function GoldTrackerModule:ToggleMinimize()
    if self.settings.statusFrameMinimized then
        self.statusFrame:SetHeight(120)
        self.toggleButton:SetText("⌄")
        self.settings.statusFrameMinimized = false
    else
        self.statusFrame:SetHeight(40)
        self.toggleButton:SetText("⌃")
        self.settings.statusFrameMinimized = true
    end
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function GoldTrackerModule:ToggleDetailsWindow()
    if not self.detailsWindow then return end
    
    if self.detailsWindow:IsShown() then
        self.detailsWindow:Hide()
    else
        self:UpdateDetailsDisplay()
        self.detailsWindow:Show()
    end
end

function GoldTrackerModule:ExportData()
    -- Simple data export functionality
    local data = {
        currentGold = self.currentGold,
        sessionStart = self.sessionStart,
        sessionStartGold = self.sessionStartGold,
        history = self.goldHistory,
        statistics = self.statistics
    }
    
    self.ui.ShowNotification("Export", "Gold data exported to saved variables", "info", 3)
    -- In a real implementation, this could export to a file or show in a window
end

-- Data persistence
function GoldTrackerModule:LoadPersistentData()
    -- This would load from saved variables in a real implementation
    -- For now, just initialize empty data
    if not self.goldHistory then
        self.goldHistory = {}
    end
end

function GoldTrackerModule:SavePersistentData()
    -- This would save to saved variables in a real implementation
    self:Log("DEBUG", "Persistent data saved")
end

-- Keybinding management
function GoldTrackerModule:RegisterKeybindings()
    if not _G.FizzureSecure then return end
    
    -- Toggle status binding
    FizzureSecure:CreateSecureButton(
        "GoldTrackerToggleButton",
        "/script " .. self.name .. ":ToggleStatusFrame()",
        self.settings.keybindings.toggleStatus,
        "Toggle Gold Status"
    )
    
    -- Show details binding
    FizzureSecure:CreateSecureButton(
        "GoldTrackerDetailsButton",
        "/script " .. self.name .. ":ToggleDetailsWindow()",
        self.settings.keybindings.showDetails,
        "Show Gold Details"
    )
    
    -- Reset binding
    FizzureSecure:CreateSecureButton(
        "GoldTrackerResetButton",
        "/script " .. self.name .. ":ResetSession()",
        self.settings.keybindings.reset,
        "Reset Gold Session"
    )
end

function GoldTrackerModule:UnregisterKeybindings()
    if not _G.FizzureSecure then return end
    
    for _, key in pairs(self.settings.keybindings) do
        if key then
            FizzureSecure:ClearKeyBinding(key)
        end
    end
end

function GoldTrackerModule:ToggleStatusFrame()
    if not self.statusFrame then return end
    
    if self.statusFrame:IsShown() then
        self.statusFrame:Hide()
        self.settings.showStatusFrame = false
    else
        self.statusFrame:Show()
        self.settings.showStatusFrame = true
    end
    
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

-- Utility methods
function GoldTrackerModule:Log(level, message)
    if self.Fizzure and self.Fizzure.Log then
        self.Fizzure:Log(level, "[GoldTracker] " .. message)
    end
end

function GoldTrackerModule:GetQuickStatus()
    local sessionChange = self.currentGold - self.sessionStartGold
    return string.format("Gold: %s (Session: %s%s)",
        FizzureCommon:FormatMoney(self.currentGold, true),
        sessionChange >= 0 and "+" or "",
        FizzureCommon:FormatMoney(sessionChange, true))
end

-- Register module with framework
if Fizzure then
    Fizzure:RegisterModule(GoldTrackerModule)
else
    -- Queue for registration if framework not ready
    if not _G.FizzureModuleQueue then
        _G.FizzureModuleQueue = {}
    end
    table.insert(_G.FizzureModuleQueue, GoldTrackerModule)
end