-- TrinketManager.lua - Trinket Bar with Cooldown Tracking for Fizzure
local TrinketManager = {}

TrinketManager.name = "Trinket Manager"
TrinketManager.version = "1.0"
TrinketManager.author = "Fizzure"
TrinketManager.category = "Action Bars"

function TrinketManager:GetDefaultSettings()
    return {
        enabled = true,
        showBar = true,
        barPosition = {
            point = "BOTTOM",
            x = 0,
            y = 150
        },
        barWidth = 400,
        barHeight = 40,
        buttonSize = 36,
        buttonSpacing = 4,
        maxButtons = 10,
        showCooldowns = true,
        showTooltips = true,
        autoAddTrinkets = true,
        savedTrinkets = {},
        keybindings = {},
        barOrientation = "horizontal" -- horizontal or vertical
    }
end

function TrinketManager:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showBar) == "boolean" and
            type(settings.maxButtons) == "number"
end

function TrinketManager:Initialize()
    if not self.Fizzure then
        print("|cffff0000Trinket Manager Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize trinket tracking
    self.trinketSlots = {}
    self.cooldownTimers = {}
    self.availableTrinkets = {}

    -- Create the trinket bar
    self:CreateTrinketBar()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        TrinketManager:OnEvent(event, ...)
    end)

    -- Update timer for cooldowns
    self.updateTimer = FizzureCommon:NewTicker(0.1, function()
        self:UpdateCooldowns()
    end)

    -- Scan for trinkets initially
    self:ScanForTrinkets()
    self:LoadSavedTrinkets()

    if self.settings.showBar then
        self.trinketBar:Show()
    end

    print("|cff00ff00Trinket Manager|r Initialized")
    return true
end

function TrinketManager:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.trinketBar then
        self.trinketBar:Hide()
    end

    self:SaveTrinkets()
end

function TrinketManager:OnEvent(event, ...)
    if event == "BAG_UPDATE" then
        self:ScanForTrinkets()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        self:UpdateCooldowns()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == 13 or slot == 14 then -- Trinket slots
            self:ScanForTrinkets()
            self:UpdateEquippedTrinkets()
        end
    end
end

function TrinketManager:CreateTrinketBar()
    -- Main bar frame
    self.trinketBar = CreateFrame("Frame", "FizzureTrinketBar", UIParent)
    self.trinketBar:SetSize(self.settings.barWidth, self.settings.barHeight)
    self.trinketBar:SetPoint(self.settings.barPosition.point, UIParent, self.settings.barPosition.point,
            self.settings.barPosition.x, self.settings.barPosition.y)

    -- Flat design background
    self.trinketBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    self.trinketBar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    self.trinketBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Make movable
    self.trinketBar:SetMovable(true)
    self.trinketBar:EnableMouse(true)
    self.trinketBar:RegisterForDrag("LeftButton")
    self.trinketBar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    self.trinketBar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrinketManager:SaveBarPosition()
    end)

    -- Title label
    local title = self.trinketBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -2)
    title:SetText("Trinkets")
    title:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Create trinket slots
    self:CreateTrinketSlots()

    -- Context menu for configuration
    self.trinketBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            TrinketManager:ShowContextMenu()
        end
    end)

    self.trinketBar:Hide()
end

function TrinketManager:CreateTrinketSlots()
    for i = 1, self.settings.maxButtons do
        local slot = self:CreateTrinketSlot(i)
        self.trinketSlots[i] = slot
    end
end

function TrinketManager:CreateTrinketSlot(index)
    local slot = CreateFrame("Button", "FizzureTrinketSlot" .. index, self.trinketBar)
    slot:SetSize(self.settings.buttonSize, self.settings.buttonSize)

    -- Position the slot
    local x, y = self:GetSlotPosition(index)
    slot:SetPoint("TOPLEFT", x, y)

    -- Flat design styling
    slot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    slot:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Item icon
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetSize(self.settings.buttonSize - 4, self.settings.buttonSize - 4)
    icon:SetPoint("CENTER")
    slot.icon = icon

    -- Cooldown frame
    local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    slot.cooldown = cooldown

    -- Stack count
    local count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.count = count

    -- Keybind text
    local keybind = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keybind:SetPoint("TOPLEFT", 2, -2)
    keybind:SetTextColor(0.7, 0.7, 0.7, 1)
    slot.keybind = keybind

    -- Make it secure for combat use
    slot:SetAttribute("type", "item")
    slot:RegisterForClicks("AnyUp")

    -- Click handlers
    slot:SetScript("OnClick", function(self, button)
        TrinketManager:OnSlotClick(index, button)
    end)

    -- Drag and drop
    slot:SetScript("OnReceiveDrag", function()
        TrinketManager:OnSlotDrop(index)
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        TrinketManager:ShowSlotTooltip(index)
    end)

    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Hover effect
    slot:SetScript("OnMouseDown", function(self)
        if self.itemName then
            self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
        end
    end)

    slot:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end)

    slot.isEmpty = true
    slot.index = index

    return slot
end

function TrinketManager:GetSlotPosition(index)
    local baseX = 10
    local baseY = -15

    if self.settings.barOrientation == "horizontal" then
        local x = baseX + (index - 1) * (self.settings.buttonSize + self.settings.buttonSpacing)
        return x, baseY
    else
        local y = baseY - (index - 1) * (self.settings.buttonSize + self.settings.buttonSpacing)
        return baseX, y
    end
end

function TrinketManager:ScanForTrinkets()
    self.availableTrinkets = {}

    -- Scan equipped trinkets
    for trinketSlot = 13, 14 do
        local itemLink = GetInventoryItemLink("player", trinketSlot)
        if itemLink then
            local itemName = GetItemInfo(itemLink)
            if itemName then
                table.insert(self.availableTrinkets, {
                    name = itemName,
                    link = itemLink,
                    location = "equipped",
                    slot = trinketSlot
                })
            end
        end
    end

    -- Scan bags for trinkets
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
                if itemType == "Armor" and itemSubType == "Trinket" then
                    local itemName = GetItemInfo(itemLink)
                    local _, itemCount = GetContainerItemInfo(bag, slot)

                    if itemName and itemCount and itemCount > 0 then
                        table.insert(self.availableTrinkets, {
                            name = itemName,
                            link = itemLink,
                            location = "bag",
                            bag = bag,
                            slot = slot,
                            count = itemCount
                        })
                    end
                end
            end
        end
    end

    -- Auto-add new trinkets if enabled
    if self.settings.autoAddTrinkets then
        self:AutoAddTrinkets()
    end
end

function TrinketManager:AutoAddTrinkets()
    for _, trinket in ipairs(self.availableTrinkets) do
        local alreadyAdded = false

        -- Check if already in a slot
        for i = 1, self.settings.maxButtons do
            local slot = self.trinketSlots[i]
            if slot and slot.itemName == trinket.name then
                alreadyAdded = true
                break
            end
        end

        -- Add to first empty slot if not already added
        if not alreadyAdded and trinket.location == "equipped" then
            for i = 1, self.settings.maxButtons do
                local slot = self.trinketSlots[i]
                if slot and slot.isEmpty then
                    self:SetSlotItem(i, trinket.name, trinket.link)
                    break
                end
            end
        end
    end
end

function TrinketManager:SetSlotItem(slotIndex, itemName, itemLink)
    local slot = self.trinketSlots[slotIndex]
    if not slot then return end

    slot.itemName = itemName
    slot.itemLink = itemLink or itemName
    slot.isEmpty = false

    -- Set icon
    local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemName)
    if itemIcon then
        slot.icon:SetTexture(itemIcon)
        slot.icon:SetDesaturated(false)
    end

    -- Update count
    local count = GetItemCount(itemName)
    if count > 1 then
        slot.count:SetText(count)
        slot.count:Show()
    else
        slot.count:Hide()
    end

    -- Set secure attribute for combat use
    slot:SetAttribute("item", itemName)

    -- Update keybind display
    self:UpdateKeybindDisplay(slotIndex)

    -- Start cooldown tracking
    self:UpdateSlotCooldown(slotIndex)
end

function TrinketManager:ClearSlot(slotIndex)
    local slot = self.trinketSlots[slotIndex]
    if not slot then return end

    slot.itemName = nil
    slot.itemLink = nil
    slot.isEmpty = true
    slot.icon:SetTexture(nil)
    slot.count:Hide()
    slot.cooldown:Hide()
    slot:SetAttribute("item", nil)
    slot.keybind:SetText("")
end

function TrinketManager:OnSlotClick(slotIndex, button)
    local slot = self.trinketSlots[slotIndex]
    if not slot then return end

    if button == "LeftButton" then
        if slot.itemName then
            -- Use the trinket
            UseItemByName(slot.itemName)
        end
    elseif button == "RightButton" then
        -- Remove item from slot
        self:ClearSlot(slotIndex)
        self:SaveTrinkets()
    end
end

function TrinketManager:OnSlotDrop(slotIndex)
    local cursorType, itemID, itemLink = GetCursorInfo()

    if cursorType == "item" and itemLink then
        local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)

        if itemType == "Armor" and itemSubType == "Trinket" then
            local itemName = GetItemInfo(itemLink)
            self:SetSlotItem(slotIndex, itemName, itemLink)
            self:SaveTrinkets()
            ClearCursor()
        else
            self.Fizzure:ShowNotification("Invalid Item", "Only trinkets can be added to the trinket bar", "error", 3)
        end
    end
end

function TrinketManager:ShowSlotTooltip(slotIndex)
    local slot = self.trinketSlots[slotIndex]
    if not slot then return end

    if slot.itemName then
        GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
        GameTooltip:SetItemByID(slot.itemName)

        -- Add cooldown info
        local start, duration = GetItemCooldown(slot.itemName)
        if start > 0 and duration > 0 then
            local remaining = start + duration - GetTime()
            if remaining > 0 then
                GameTooltip:AddLine(string.format("Cooldown: %s", self:FormatTime(remaining)), 1, 0.82, 0)
            end
        end

        GameTooltip:Show()
    else
        GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Empty Trinket Slot")
        GameTooltip:AddLine("Drag a trinket here or right-click to configure", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

function TrinketManager:UpdateCooldowns()
    for i = 1, self.settings.maxButtons do
        self:UpdateSlotCooldown(i)
    end
end

function TrinketManager:UpdateSlotCooldown(slotIndex)
    local slot = self.trinketSlots[slotIndex]
    if not slot or slot.isEmpty then return end

    local start, duration = GetItemCooldown(slot.itemName)

    if start > 0 and duration > 1.5 then
        slot.cooldown:SetCooldown(start, duration)
        slot.cooldown:Show()
        slot.icon:SetDesaturated(true)
    else
        slot.cooldown:Hide()
        slot.icon:SetDesaturated(false)
    end

    -- Update count
    local count = GetItemCount(slot.itemName)
    if count > 1 then
        slot.count:SetText(count)
        slot.count:Show()
    else
        slot.count:Hide()
    end
end

function TrinketManager:UpdateKeybindDisplay(slotIndex)
    local slot = self.trinketSlots[slotIndex]
    if not slot then return end

    local keybind = self.settings.keybindings[slotIndex]
    if keybind then
        slot.keybind:SetText(keybind)
    else
        slot.keybind:SetText("")
    end
end

function TrinketManager:UpdateEquippedTrinkets()
    -- Update any slots that have equipped trinkets
    for i = 1, self.settings.maxButtons do
        local slot = self.trinketSlots[i]
        if slot and not slot.isEmpty then
            -- Check if this trinket is still available
            local found = false
            for _, trinket in ipairs(self.availableTrinkets) do
                if trinket.name == slot.itemName then
                    found = true
                    break
                end
            end

            if not found then
                -- Trinket no longer available, clear slot
                self:ClearSlot(i)
            else
                -- Update the slot
                self:UpdateSlotCooldown(i)
            end
        end
    end
end

function TrinketManager:ShowContextMenu()
    local menu = CreateFrame("Frame", "FizzureTrinketContextMenu", UIParent)
    menu:SetSize(150, 100)
    menu:SetPoint("CURSOR")
    menu:SetFrameStrata("DIALOG")

    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local y = -10

    -- Configure button
    local configBtn = FizzureUI:CreateButton(menu, "Configure", 130, 20, function()
        menu:Hide()
        self:ShowConfigWindow()
    end, true)
    configBtn:SetPoint("TOP", 0, y)
    y = y - 25

    -- Clear all button
    local clearBtn = FizzureUI:CreateButton(menu, "Clear All", 130, 20, function()
        menu:Hide()
        self:ClearAllSlots()
    end, true)
    clearBtn:SetPoint("TOP", 0, y)
    y = y - 25

    -- Toggle bar button
    local toggleBtn = FizzureUI:CreateButton(menu, self.settings.showBar and "Hide Bar" or "Show Bar", 130, 20, function()
        menu:Hide()
        self:ToggleBar()
    end, true)
    toggleBtn:SetPoint("TOP", 0, y)

    -- Auto-hide
    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) then
            self:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

function TrinketManager:ShowConfigWindow()
    if self.configWindow then
        if self.configWindow:IsShown() then
            self.configWindow:Hide()
            return
        else
            self.configWindow:Show()
        end
    else
        self:CreateConfigWindow()
    end

    self:UpdateConfigWindow()
end

function TrinketManager:CreateConfigWindow()
    self.configWindow = FizzureUI:CreateWindow("TrinketConfig", "Trinket Manager Configuration", 500, 400, nil, true)

    -- Available trinkets list
    local availableLabel = FizzureUI:CreateLabel(self.configWindow.content, "Available Trinkets:", "GameFontNormal")
    availableLabel:SetPoint("TOPLEFT", 10, -10)

    self.availableScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 300)
    self.availableScroll:SetPoint("TOPLEFT", 10, -30)

    -- Current bar setup
    local barLabel = FizzureUI:CreateLabel(self.configWindow.content, "Trinket Bar Setup:", "GameFontNormal")
    barLabel:SetPoint("TOPRIGHT", -10, -10)

    self.barScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 300)
    self.barScroll:SetPoint("TOPRIGHT", -10, -30)

    -- Bottom controls
    local autoAddCheck = FizzureUI:CreateCheckBox(self.configWindow.content, "Auto-add equipped trinkets",
            self.settings.autoAddTrinkets, function(checked)
                self.settings.autoAddTrinkets = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("BOTTOMLEFT", 10, 40)

    local saveBtn = FizzureUI:CreateButton(self.configWindow.content, "Save & Close", 100, 24, function()
        self:SaveTrinkets()
        self.configWindow:Hide()
    end, true)
    saveBtn:SetPoint("BOTTOM", 0, 10)
end

function TrinketManager:UpdateConfigWindow()
    if not self.configWindow or not self.configWindow:IsShown() then return end

    -- Update available trinkets list
    local content = self.availableScroll.content
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end

    local y = -5
    for _, trinket in ipairs(self.availableTrinkets) do
        local frame = CreateFrame("Button", nil, content)
        frame:SetSize(200, 25)
        frame:SetPoint("TOPLEFT", 5, y)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)

        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(trinket.name)
        if itemIcon then
            icon:SetTexture(itemIcon)
        end

        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetText(trinket.name)
        nameText:SetTextColor(0.9, 0.9, 0.9)

        frame:SetScript("OnClick", function()
            self:AddTrinketToBar(trinket.name, trinket.link)
        end)

        y = y - 27
    end

    self.availableScroll.content:SetHeight(math.abs(y) + 20)

    -- Update bar setup list
    content = self.barScroll.content
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end

    y = -5
    for i = 1, self.settings.maxButtons do
        local slot = self.trinketSlots[i]

        local frame = CreateFrame("Frame", nil, content)
        frame:SetSize(200, 25)
        frame:SetPoint("TOPLEFT", 5, y)

        local slotLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotLabel:SetPoint("LEFT", 5, 0)
        slotLabel:SetText("Slot " .. i .. ":")
        slotLabel:SetTextColor(0.7, 0.7, 0.7)

        if slot and not slot.isEmpty then
            local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("LEFT", slotLabel, "RIGHT", 10, 0)
            nameText:SetText(slot.itemName)
            nameText:SetTextColor(0, 1, 0)

            local removeBtn = FizzureUI:CreateButton(frame, "X", 15, 15, function()
                self:ClearSlot(i)
                self:UpdateConfigWindow()
            end, true)
            removeBtn:SetPoint("RIGHT", -5, 0)
        else
            local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("LEFT", slotLabel, "RIGHT", 10, 0)
            emptyText:SetText("Empty")
            emptyText:SetTextColor(0.5, 0.5, 0.5)
        end

        y = y - 27
    end

    self.barScroll.content:SetHeight(math.abs(y) + 20)
end

function TrinketManager:AddTrinketToBar(itemName, itemLink)
    -- Find first empty slot
    for i = 1, self.settings.maxButtons do
        local slot = self.trinketSlots[i]
        if slot and slot.isEmpty then
            self:SetSlotItem(i, itemName, itemLink)
            self:UpdateConfigWindow()
            return
        end
    end

    self.Fizzure:ShowNotification("Bar Full", "All trinket slots are full", "warning", 3)
end

function TrinketManager:ClearAllSlots()
    for i = 1, self.settings.maxButtons do
        self:ClearSlot(i)
    end
    self:SaveTrinkets()
end

function TrinketManager:ToggleBar()
    self.settings.showBar = not self.settings.showBar
    self.Fizzure:SetModuleSettings(self.name, self.settings)

    if self.settings.showBar then
        self.trinketBar:Show()
    else
        self.trinketBar:Hide()
    end
end

function TrinketManager:SaveBarPosition()
    local point, _, _, x, y = self.trinketBar:GetPoint()
    self.settings.barPosition = {
        point = point,
        x = x,
        y = y
    }
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function TrinketManager:SaveTrinkets()
    local savedTrinkets = {}

    for i = 1, self.settings.maxButtons do
        local slot = self.trinketSlots[i]
        if slot and not slot.isEmpty then
            savedTrinkets[i] = {
                name = slot.itemName,
                link = slot.itemLink
            }
        end
    end

    self.settings.savedTrinkets = savedTrinkets
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function TrinketManager:LoadSavedTrinkets()
    for i, trinketData in pairs(self.settings.savedTrinkets) do
        if trinketData and trinketData.name then
            -- Check if trinket is still available
            if GetItemCount(trinketData.name) > 0 then
                self:SetSlotItem(i, trinketData.name, trinketData.link)
            end
        end
    end
end

function TrinketManager:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

function TrinketManager:CreateConfigUI(parent, x, y)
    local showBarCheck = FizzureUI:CreateCheckBox(parent, "Show trinket bar",
            self.settings.showBar, function(checked)
                self.settings.showBar = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.trinketBar:Show()
                else
                    self.trinketBar:Hide()
                end
            end, true)
    showBarCheck:SetPoint("TOPLEFT", x, y)

    local autoAddCheck = FizzureUI:CreateCheckBox(parent, "Auto-add equipped trinkets",
            self.settings.autoAddTrinkets, function(checked)
                self.settings.autoAddTrinkets = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("TOPLEFT", x, y - 25)

    local showTooltipsCheck = FizzureUI:CreateCheckBox(parent, "Show tooltips",
            self.settings.showTooltips, function(checked)
                self.settings.showTooltips = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    showTooltipsCheck:SetPoint("TOPLEFT", x, y - 50)

    local configBtn = FizzureUI:CreateButton(parent, "Configure Bar", 100, 24, function()
        self:ShowConfigWindow()
    end, true)
    configBtn:SetPoint("TOPLEFT", x, y - 80)

    local rescanBtn = FizzureUI:CreateButton(parent, "Rescan Trinkets", 100, 24, function()
        self:ScanForTrinkets()
        self.Fizzure:ShowNotification("Trinkets Rescanned", "Trinket inventory updated", "success", 2)
    end, true)
    rescanBtn:SetPoint("TOPLEFT", x + 110, y - 80)

    return y - 110
end

function TrinketManager:GetQuickStatus()
    local equipped = 0
    local onCooldown = 0

    for i = 1, self.settings.maxButtons do
        local slot = self.trinketSlots[i]
        if slot and not slot.isEmpty then
            equipped = equipped + 1

            local start, duration = GetItemCooldown(slot.itemName)
            if start > 0 and duration > 1.5 then
                onCooldown = onCooldown + 1
            end
        end
    end

    return string.format("Trinkets: %d equipped, %d on cooldown", equipped, onCooldown)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Trinket Manager", TrinketManager, "Action Bars")
end