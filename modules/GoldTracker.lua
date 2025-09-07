-- GoldTracker.lua - Gold and Experience tracking module for Fizzure
local GoldTracker = {}

GoldTracker.name = "Gold & XP Tracker"
GoldTracker.version = "1.0"
GoldTracker.author = "Fizzure"
GoldTracker.category = "Economy"

function GoldTracker:GetDefaultSettings()
    return {
        enabled = true,
        showWindow = true,
        trackVendorValue = true,
        windowPosition = nil,
        sessionData = {
            startGold = 0,
            startXP = 0,
            startTime = 0,
            goldGained = 0,
            goldLost = 0,
            xpGained = 0,
            itemsLooted = {},
            goldSources = {}
        },
        historicalData = {}
    }
end

function GoldTracker:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showWindow) == "boolean" and
            type(settings.trackVendorValue) == "boolean"
end

function GoldTracker:Initialize()
    if not self.Fizzure then
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize session
    self:StartNewSession()

    -- Create UI
    self:CreateStatusWindow()
    self:CreateDetailWindow()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
    self.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    self.eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    self.eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    self.eventFrame:RegisterEvent("LOOT_OPENED")
    self.eventFrame:RegisterEvent("MERCHANT_SHOW")

    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)

    -- Update timer
    self.updateTimer = FizzureCommon:NewTicker(1, function()
        self:UpdateDisplay()
    end)

    if self.settings.showWindow then
        self.statusWindow:Show()
    end

    return true
end

function GoldTracker:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.statusWindow then
        self.statusWindow:Hide()
    end

    if self.detailWindow then
        self.detailWindow:Hide()
    end

    -- Save session data
    self:SaveSession()
end

function GoldTracker:StartNewSession()
    local session = self.settings.sessionData
    session.startGold = GetMoney()
    session.startXP = UnitXP("player")
    session.startTime = GetTime()
    session.goldGained = 0
    session.goldLost = 0
    session.xpGained = 0
    session.itemsLooted = {}
    session.goldSources = {}

    self.lastGold = session.startGold
    self.lastXP = session.startXP
    self.lootedItems = {}
end

function GoldTracker:SaveSession()
    local session = self.settings.sessionData
    local duration = GetTime() - session.startTime

    if duration > 60 then -- Only save sessions longer than 1 minute
        local sessionRecord = {
            date = date("%Y-%m-%d %H:%M"),
            duration = duration,
            goldGained = session.goldGained,
            goldLost = session.goldLost,
            netGold = session.goldGained - session.goldLost,
            xpGained = session.xpGained,
            goldPerHour = (session.goldGained - session.goldLost) / (duration / 3600),
            xpPerHour = session.xpGained / (duration / 3600)
        }

        table.insert(self.settings.historicalData, 1, sessionRecord)

        -- Keep only last 50 sessions
        while #self.settings.historicalData > 50 do
            table.remove(self.settings.historicalData)
        end

        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
end

function GoldTracker:OnEvent(event, ...)
    if event == "PLAYER_MONEY" then
        self:OnMoneyChanged()
    elseif event == "PLAYER_XP_UPDATE" then
        self:OnXPChanged()
    elseif event == "CHAT_MSG_LOOT" then
        self:OnLoot(...)
    elseif event == "CHAT_MSG_MONEY" then
        self:OnMoneyLoot(...)
    elseif event == "LOOT_OPENED" then
        self:OnLootOpened()
    elseif event == "MERCHANT_SHOW" then
        self:CalculateVendorValue()
    end
end

function GoldTracker:OnMoneyChanged()
    local currentGold = GetMoney()
    local diff = currentGold - self.lastGold

    if diff > 0 then
        self.settings.sessionData.goldGained = self.settings.sessionData.goldGained + diff
    elseif diff < 0 then
        self.settings.sessionData.goldLost = self.settings.sessionData.goldLost + math.abs(diff)
    end

    self.lastGold = currentGold
end

function GoldTracker:OnXPChanged()
    local currentXP = UnitXP("player")
    local diff = currentXP - self.lastXP

    if diff > 0 then
        self.settings.sessionData.xpGained = self.settings.sessionData.xpGained + diff
    end

    self.lastXP = currentXP
end

function GoldTracker:OnLoot(msg)
    -- Parse loot message for item link and name
    local itemLink = string.match(msg, "(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    local itemName = string.match(msg, "|h%[(.-)%]|h")
    if itemLink and itemName then
        local count = tonumber(string.match(msg, "x(%d+)")) or 1
        local vendorPrice = FizzureCommon:GetItemSellPrice(itemName)

        if vendorPrice and vendorPrice > 0 then
            local totalValue = vendorPrice * count

            -- Track item
            if not self.lootedItems[itemName] then
                self.lootedItems[itemName] = {
                    name = itemName,
                    link = itemLink,
                    count = 0,
                    value = vendorPrice,
                    totalValue = 0
                }
            end

            self.lootedItems[itemName].count = self.lootedItems[itemName].count + count
            self.lootedItems[itemName].totalValue = self.lootedItems[itemName].totalValue + totalValue

            -- Track source
            local target = UnitName("target")
            if target then
                if not self.settings.sessionData.goldSources[target] then
                    self.settings.sessionData.goldSources[target] = {
                        gold = 0,
                        items = 0,
                        zone = GetZoneText()
                    }
                end

                self.settings.sessionData.goldSources[target].items =
                self.settings.sessionData.goldSources[target].items + totalValue
            end
        end
    end
end

function GoldTracker:OnMoneyLoot(msg)
    local copper = self:ParseMoneyString(msg)
    if copper > 0 then
        local target = UnitName("target") or "Unknown"

        if not self.settings.sessionData.goldSources[target] then
            self.settings.sessionData.goldSources[target] = {
                gold = 0,
                items = 0,
                zone = GetZoneText()
            }
        end

        self.settings.sessionData.goldSources[target].gold =
        self.settings.sessionData.goldSources[target].gold + copper
    end
end

function GoldTracker:ParseMoneyString(msg)
    local gold = tonumber(string.match(msg, "(%d+) Gold")) or 0
    local silver = tonumber(string.match(msg, "(%d+) Silver")) or 0
    local copper = tonumber(string.match(msg, "(%d+) Copper")) or 0

    return (gold * 10000) + (silver * 100) + copper
end

function GoldTracker:OnLootOpened()
    self.currentLootSource = UnitName("target") or "Unknown"
end

function GoldTracker:CalculateVendorValue()
    if not self.settings.trackVendorValue then return end

    local totalValue = 0
    for itemName, data in pairs(self.lootedItems) do
        if data.count > 0 then
            totalValue = totalValue + data.totalValue
        end
    end

    self.potentialVendorValue = totalValue
end

function GoldTracker:CreateStatusWindow()
    self.statusWindow = FizzureUI:CreateStatusFrame("GoldTrackerStatus", "Gold & XP Tracker", 200, 120)

    if self.settings.windowPosition then
        self.statusWindow:ClearAllPoints()
        self.statusWindow:SetPoint(self.settings.windowPosition.point,
                UIParent,
                self.settings.windowPosition.relativePoint,
                self.settings.windowPosition.x,
                self.settings.windowPosition.y)
    end

    -- Gold per hour
    self.goldDisplay = self.statusWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.goldDisplay:SetPoint("TOP", 0, -25)
    self.goldDisplay:SetText("Gold/Hr: 0g")

    -- XP per hour
    self.xpDisplay = self.statusWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.xpDisplay:SetPoint("TOP", 0, -45)
    self.xpDisplay:SetText("XP/Hr: 0")

    -- Session time
    self.timeDisplay = self.statusWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.timeDisplay:SetPoint("TOP", 0, -65)
    self.timeDisplay:SetText("Session: 0:00")

    -- Vendor value
    self.vendorDisplay = self.statusWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.vendorDisplay:SetPoint("TOP", 0, -80)
    self.vendorDisplay:SetText("Items: 0g")

    -- Details button
    local detailsBtn = FizzureUI:CreateButton(self.statusWindow, "Details", 60, 20, function()
        self:ToggleDetailWindow()
    end)
    detailsBtn:SetPoint("BOTTOM", 0, 10)

    -- Save position on move
    self.statusWindow.OnPositionChanged = function()
        local point, _, relativePoint, x, y = self.statusWindow:GetPoint()
        self.settings.windowPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end
end

function GoldTracker:CreateDetailWindow()
    self.detailWindow = FizzureUI:CreateWindow("GoldTrackerDetails", "Gold & XP Details", 500, 400)

    -- Tabs
    local tabs = {
        {
            name = "Current",
            onCreate = function(content) self:CreateCurrentTab(content) end
        },
        {
            name = "Sources",
            onCreate = function(content) self:CreateSourcesTab(content) end
        },
        {
            name = "History",
            onCreate = function(content) self:CreateHistoryTab(content) end
        }
    }

    self.tabPanel = FizzureUI:CreateTabPanel(self.detailWindow.content, tabs)
end

function GoldTracker:CreateCurrentTab(parent)
    local y = -10

    -- Session stats
    local sessionLabel = FizzureUI:CreateLabel(parent, "Current Session", "GameFontNormalLarge")
    sessionLabel:SetPoint("TOP", 0, y)
    y = y - 30

    self.detailGoldGained = FizzureUI:CreateLabel(parent, "Gold Gained: 0g")
    self.detailGoldGained:SetPoint("TOPLEFT", 20, y)
    y = y - 20

    self.detailGoldLost = FizzureUI:CreateLabel(parent, "Gold Lost: 0g")
    self.detailGoldLost:SetPoint("TOPLEFT", 20, y)
    y = y - 20

    self.detailNetGold = FizzureUI:CreateLabel(parent, "Net Gold: 0g")
    self.detailNetGold:SetPoint("TOPLEFT", 20, y)
    y = y - 30

    self.detailXPGained = FizzureUI:CreateLabel(parent, "XP Gained: 0")
    self.detailXPGained:SetPoint("TOPLEFT", 20, y)
    y = y - 20

    self.detailSessionTime = FizzureUI:CreateLabel(parent, "Duration: 0:00")
    self.detailSessionTime:SetPoint("TOPLEFT", 20, y)
    y = y - 30

    -- Items looted
    local itemsLabel = FizzureUI:CreateLabel(parent, "Valuable Items Looted", "GameFontNormalLarge")
    itemsLabel:SetPoint("TOP", 0, y)
    y = y - 25

    self.itemScroll = FizzureUI:CreateScrollFrame(parent, 460, 150)
    self.itemScroll:SetPoint("TOP", 0, y)
end

function GoldTracker:CreateSourcesTab(parent)
    local sourcesLabel = FizzureUI:CreateLabel(parent, "Gold Sources", "GameFontNormalLarge")
    sourcesLabel:SetPoint("TOP", 0, -10)

    self.sourcesScroll = FizzureUI:CreateScrollFrame(parent, 460, 300)
    self.sourcesScroll:SetPoint("TOP", 0, -40)
end

function GoldTracker:CreateHistoryTab(parent)
    local historyLabel = FizzureUI:CreateLabel(parent, "Session History", "GameFontNormalLarge")
    historyLabel:SetPoint("TOP", 0, -10)

    self.historyScroll = FizzureUI:CreateScrollFrame(parent, 460, 300)
    self.historyScroll:SetPoint("TOP", 0, -40)

    -- Reset button
    local resetBtn = FizzureUI:CreateButton(parent, "Clear History", 100, 20, function()
        self.settings.historicalData = {}
        self.Fizzure:SetModuleSettings(self.name, self.settings)
        self:UpdateHistoryDisplay()
    end)
    resetBtn:SetPoint("BOTTOM", 0, 10)
end

function GoldTracker:UpdateDisplay()
    if not self.statusWindow:IsShown() then return end

    local session = self.settings.sessionData
    local elapsed = GetTime() - session.startTime
    local hours = elapsed / 3600

    -- Calculate rates
    local goldPerHour = 0
    local xpPerHour = 0

    if hours > 0.01 then -- At least 36 seconds
        goldPerHour = (session.goldGained - session.goldLost) / hours
        xpPerHour = session.xpGained / hours
    end

    -- Update displays
    self.goldDisplay:SetText("Gold/Hr: " .. FizzureCommon:FormatMoney(goldPerHour))

    if goldPerHour > 0 then
        self.goldDisplay:SetTextColor(0.2, 1, 0.2)
    elseif goldPerHour < 0 then
        self.goldDisplay:SetTextColor(1, 0.2, 0.2)
    else
        self.goldDisplay:SetTextColor(1, 1, 1)
    end

    self.xpDisplay:SetText(string.format("XP/Hr: %d", xpPerHour))
    self.timeDisplay:SetText("Session: " .. FizzureCommon:FormatTime(elapsed))

    -- Vendor value
    local vendorValue = 0
    for _, data in pairs(self.lootedItems) do
        vendorValue = vendorValue + data.totalValue
    end
    self.vendorDisplay:SetText("Items: " .. FizzureCommon:FormatMoney(vendorValue))

    -- Update detail window if shown
    if self.detailWindow and self.detailWindow:IsShown() then
        self:UpdateDetailDisplay()
    end
end

function GoldTracker:UpdateDetailDisplay()
    local session = self.settings.sessionData

    -- Current tab
    if self.detailGoldGained then
        self.detailGoldGained:SetText("Gold Gained: " .. FizzureCommon:FormatMoney(session.goldGained))
        self.detailGoldLost:SetText("Gold Lost: " .. FizzureCommon:FormatMoney(session.goldLost))
        self.detailNetGold:SetText("Net Gold: " .. FizzureCommon:FormatMoney(session.goldGained - session.goldLost))
        self.detailXPGained:SetText("XP Gained: " .. session.xpGained)
        self.detailSessionTime:SetText("Duration: " .. FizzureCommon:FormatTime(GetTime() - session.startTime))
    end

    -- Update items list
    self:UpdateItemsDisplay()

    -- Update sources
    self:UpdateSourcesDisplay()

    -- Update history
    self:UpdateHistoryDisplay()
end

function GoldTracker:UpdateItemsDisplay()
    if not self.itemScroll then return end

    -- Clear existing
    local content = self.itemScroll.content
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local y = -5
    local items = {}

    for itemName, data in pairs(self.lootedItems) do
        table.insert(items, data)
    end

    table.sort(items, function(a, b) return a.totalValue > b.totalValue end)

    for i, data in ipairs(items) do
        if i > 20 then break end -- Show top 20

        local item = FizzureUI:CreateLabel(content,
                string.format("%s x%d - %s",
                        data.name,
                        data.count,
                        FizzureCommon:FormatMoney(data.totalValue)))
        item:SetPoint("TOPLEFT", 10, y)
        y = y - 20
    end

    self.itemScroll:UpdateScrollChildHeight()
end

function GoldTracker:UpdateSourcesDisplay()
    if not self.sourcesScroll then return end

    local content = self.sourcesScroll.content
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local y = -5
    local sources = {}

    for name, data in pairs(self.settings.sessionData.goldSources) do
        table.insert(sources, {
            name = name,
            total = data.gold + data.items,
            gold = data.gold,
            items = data.items,
            zone = data.zone
        })
    end

    table.sort(sources, function(a, b) return a.total > b.total end)

    for i, source in ipairs(sources) do
        if i > 30 then break end

        local text = string.format("%s (%s) - Gold: %s, Items: %s",
                source.name,
                source.zone,
                FizzureCommon:FormatMoney(source.gold),
                FizzureCommon:FormatMoney(source.items))

        local label = FizzureUI:CreateLabel(content, text, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, y)
        y = y - 18
    end

    self.sourcesScroll:UpdateScrollChildHeight()
end

function GoldTracker:UpdateHistoryDisplay()
    if not self.historyScroll then return end

    local content = self.historyScroll.content
    for i = content:GetNumChildren(), 1, -1 do
        select(i, content:GetChildren()):Hide()
    end

    local y = -5

    for i, record in ipairs(self.settings.historicalData) do
        if i > 20 then break end

        local text = string.format("%s - %s - Gold/Hr: %s, XP/Hr: %d",
                record.date,
                FizzureCommon:FormatTime(record.duration),
                FizzureCommon:FormatMoney(record.goldPerHour),
                record.xpPerHour)

        local label = FizzureUI:CreateLabel(content, text, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, y)
        y = y - 18
    end

    self.historyScroll:UpdateScrollChildHeight()
end

function GoldTracker:ToggleDetailWindow()
    if self.detailWindow:IsShown() then
        self.detailWindow:Hide()
    else
        self:UpdateDetailDisplay()
        self.detailWindow:Show()
    end
end

function GoldTracker:CreateConfigUI(parent, x, y)
    local showWindowCheck = FizzureUI:CreateCheckBox(parent, "Show tracker window",
            self.settings.showWindow, function(checked)
                self.settings.showWindow = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.statusWindow:Show()
                else
                    self.statusWindow:Hide()
                end
            end)
    showWindowCheck:SetPoint("TOPLEFT", x, y)

    local trackVendorCheck = FizzureUI:CreateCheckBox(parent, "Track item vendor values",
            self.settings.trackVendorValue, function(checked)
                self.settings.trackVendorValue = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end)
    trackVendorCheck:SetPoint("TOPLEFT", x, y - 25)

    local resetBtn = FizzureUI:CreateButton(parent, "Reset Session", 100, 20, function()
        self:StartNewSession()
        self:UpdateDisplay()
    end)
    resetBtn:SetPoint("TOPLEFT", x, y - 55)

    return y - 80
end

function GoldTracker:GetQuickStatus()
    local session = self.settings.sessionData
    local elapsed = GetTime() - session.startTime
    local hours = elapsed / 3600

    local goldPerHour = 0
    if hours > 0.01 then
        goldPerHour = (session.goldGained - session.goldLost) / hours
    end

    return string.format("Gold/Hr: %s", FizzureCommon:FormatMoney(goldPerHour))
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Gold & XP Tracker", GoldTracker, "Economy")
end