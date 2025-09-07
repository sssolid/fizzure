-- CompanionBar.lua - Companion/Pet Bar for Summoning Non-Combat Pets for Fizzure
local CompanionBar = {}

CompanionBar.name = "Companion Bar"
CompanionBar.version = "1.0"
CompanionBar.author = "Fizzure"
CompanionBar.category = "Action Bars"

function CompanionBar:GetDefaultSettings()
    return {
        enabled = true,
        showBar = true,
        barPosition = {
            point = "BOTTOM",
            x = 200,
            y = 150
        },
        barWidth = 300,
        barHeight = 40,
        buttonSize = 36,
        buttonSpacing = 4,
        maxButtons = 6,
        showTooltips = true,
        autoAddCompanions = true,
        dismissOnCombat = false,
        savedCompanions = {},
        keybindings = {},
        barOrientation = "horizontal",
        randomCompanion = true -- Allow random companion summoning
    }
end

function CompanionBar:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showBar) == "boolean" and
            type(settings.maxButtons) == "number"
end

function CompanionBar:Initialize()
    if not self.Fizzure then
        print("|cffff0000Companion Bar Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize companion tracking
    self.companionSlots = {}
    self.availableCompanions = {}
    self.currentCompanion = nil

    -- Create the companion bar
    self:CreateCompanionBar()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Combat start
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Combat end
    self.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.eventFrame:RegisterEvent("COMPANION_UPDATE")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        CompanionBar:OnEvent(event, ...)
    end)

    -- Update timer for companion status
    self.updateTimer = FizzureCommon:NewTicker(2, function()
        self:UpdateCompanionStatus()
        self:UpdateCooldowns()
    end)

    -- Scan for companions initially
    self:ScanForCompanions()
    self:LoadSavedCompanions()

    if self.settings.showBar then
        self.companionBar:Show()
    end

    print("|cff00ff00Companion Bar|r Initialized")
    return true
end

function CompanionBar:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.companionBar then
        self.companionBar:Hide()
    end

    self:SaveCompanions()
end

function CompanionBar:OnEvent(event, ...)
    if event == "BAG_UPDATE" then
        self:ScanForCompanions()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if self.settings.dismissOnCombat and self.currentCompanion then
            self:DismissCompanion()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        self:UpdateCooldowns()
    elseif event == "COMPANION_UPDATE" then
        self:UpdateCompanionStatus()
    end
end

function CompanionBar:CreateCompanionBar()
    -- Main bar frame
    self.companionBar = CreateFrame("Frame", "FizzureCompanionBar", UIParent)
    self.companionBar:SetSize(self.settings.barWidth, self.settings.barHeight)
    self.companionBar:SetPoint(self.settings.barPosition.point, UIParent, self.settings.barPosition.point,
            self.settings.barPosition.x, self.settings.barPosition.y)

    -- Flat design background
    self.companionBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    self.companionBar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    self.companionBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Make movable
    self.companionBar:SetMovable(true)
    self.companionBar:EnableMouse(true)
    self.companionBar:RegisterForDrag("LeftButton")
    self.companionBar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    self.companionBar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CompanionBar:SaveBarPosition()
    end)

    -- Title label
    local title = self.companionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -2)
    title:SetText("Companions")
    title:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Random companion button (special first slot)
    self:CreateRandomCompanionButton()

    -- Create companion slots
    self:CreateCompanionSlots()

    -- Context menu for configuration
    self.companionBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            CompanionBar:ShowContextMenu()
        end
    end)

    self.companionBar:Hide()
end

function CompanionBar:CreateRandomCompanionButton()
    local button = CreateFrame("Button", "FizzureRandomCompanionButton", self.companionBar)
    button:SetSize(self.settings.buttonSize, self.settings.buttonSize)
    button:SetPoint("TOPLEFT", 10, -15)

    -- Flat design styling with accent color
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    button:SetBackdropColor(0.8, 0.2, 0.8, 0.3) -- Purple accent
    button:SetBackdropBorderColor(0.8, 0.2, 0.8, 1)

    -- Random companion icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(self.settings.buttonSize - 4, self.settings.buttonSize - 4)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Box_PetCarrier_01") -- Pet carrier icon
    button.icon = icon

    -- Label
    local label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    label:SetPoint("BOTTOM", 0, -12)
    label:SetText("Random")
    label:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Click handler
    button:SetScript("OnClick", function()
        self:SummonRandomCompanion()
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Random Companion")
        GameTooltip:AddLine("Summon a random companion from your collection", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.randomCompanionButton = button
end

function CompanionBar:CreateCompanionSlots()
    for i = 1, self.settings.maxButtons do
        local slot = self:CreateCompanionSlot(i)
        self.companionSlots[i] = slot
    end
end

function CompanionBar:CreateCompanionSlot(index)
    local slot = CreateFrame("Button", "FizzureCompanionSlot" .. index, self.companionBar)
    slot:SetSize(self.settings.buttonSize, self.settings.buttonSize)

    -- Position the slot (offset by random button)
    local x, y = self:GetSlotPosition(index)
    slot:SetPoint("TOPLEFT", x + self.settings.buttonSize + self.settings.buttonSpacing + 10, y)

    -- Flat design styling
    slot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    slot:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Companion icon
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetSize(self.settings.buttonSize - 4, self.settings.buttonSize - 4)
    icon:SetPoint("CENTER")
    slot.icon = icon

    -- Cooldown frame
    local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    slot.cooldown = cooldown

    -- Active indicator
    local activeRing = slot:CreateTexture(nil, "OVERLAY")
    activeRing:SetSize(self.settings.buttonSize, self.settings.buttonSize)
    activeRing:SetPoint("CENTER")
    activeRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    activeRing:SetVertexColor(0, 1, 0, 0.8)
    activeRing:Hide()
    slot.activeRing = activeRing

    -- Keybind text
    local keybind = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keybind:SetPoint("TOPLEFT", 2, -2)
    keybind:SetTextColor(0.7, 0.7, 0.7, 1)
    slot.keybind = keybind

    -- Click handlers
    slot:SetScript("OnClick", function(self, button)
        CompanionBar:OnSlotClick(index, button)
    end)

    -- Drag and drop
    slot:SetScript("OnReceiveDrag", function()
        CompanionBar:OnSlotDrop(index)
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        CompanionBar:ShowSlotTooltip(index)
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

function CompanionBar:GetSlotPosition(index)
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

function CompanionBar:ScanForCompanions()
    self.availableCompanions = {}

    -- Scan bags for companion items
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
                if itemName and self:IsCompanionItem(itemName, itemType, itemSubType) then
                    local _, itemCount = GetContainerItemInfo(bag, slot)

                    if itemCount and itemCount > 0 then
                        table.insert(self.availableCompanions, {
                            name = itemName,
                            link = itemLink,
                            bag = bag,
                            slot = slot,
                            count = itemCount
                        })
                    end
                end
            end
        end
    end

    -- Auto-add new companions if enabled
    if self.settings.autoAddCompanions then
        self:AutoAddCompanions()
    end
end

function CompanionBar:IsCompanionItem(itemName, itemType, itemSubType)
    if not itemName then return false end

    -- Check item type first
    if itemType == "Miscellaneous" and itemSubType == "Companion Pets" then
        return true
    end

    local nameLower = string.lower(itemName)

    -- Check for common companion keywords
    local companionKeywords = {
        "pet", "companion", "minipet", "baby", "whelp", "hatchling",
        "mechanical", "clockwork", "sprite", "wisp", "rabbit", "cat",
        "dog", "dragon", "whelpling", "murky", "panda", "sprite darter"
    }

    for _, keyword in ipairs(companionKeywords) do
        if string.find(nameLower, keyword) then
            return true
        end
    end

    return false
end

function CompanionBar:AutoAddCompanions()
    for _, companion in ipairs(self.availableCompanions) do
        local alreadyAdded = false

        -- Check if already in a slot
        for i = 1, self.settings.maxButtons do
            local slot = self.companionSlots[i]
            if slot and slot.itemName == companion.name then
                alreadyAdded = true
                break
            end
        end

        -- Add to first empty slot if not already added
        if not alreadyAdded then
            for i = 1, self.settings.maxButtons do
                local slot = self.companionSlots[i]
                if slot and slot.isEmpty then
                    self:SetSlotCompanion(i, companion.name, companion.link)
                    break
                end
            end
        end
    end
end

function CompanionBar:SetSlotCompanion(slotIndex, itemName, itemLink)
    local slot = self.companionSlots[slotIndex]
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

    -- Update keybind display
    self:UpdateKeybindDisplay(slotIndex)

    -- Update active status
    self:UpdateSlotActiveStatus(slotIndex)
end

function CompanionBar:ClearSlot(slotIndex)
    local slot = self.companionSlots[slotIndex]
    if not slot then return end

    slot.itemName = nil
    slot.itemLink = nil
    slot.isEmpty = true
    slot.icon:SetTexture(nil)
    slot.cooldown:Hide()
    slot.activeRing:Hide()
    slot.keybind:SetText("")
end

function CompanionBar:OnSlotClick(slotIndex, button)
    local slot = self.companionSlots[slotIndex]
    if not slot then return end

    if button == "LeftButton" then
        if slot.itemName then
            self:SummonCompanion(slot.itemName)
        end
    elseif button == "RightButton" then
        -- Remove companion from slot
        self:ClearSlot(slotIndex)
        self:SaveCompanions()
    end
end

function CompanionBar:OnSlotDrop(slotIndex)
    local cursorType, itemID, itemLink = GetCursorInfo()

    if cursorType == "item" and itemLink then
        local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)

        if itemName and self:IsCompanionItem(itemName, itemType, itemSubType) then
            self:SetSlotCompanion(slotIndex, itemName, itemLink)
            self:SaveCompanions()
            ClearCursor()
        else
            self.Fizzure:ShowNotification("Invalid Item", "Only companion pets can be added to the companion bar", "error", 3)
        end
    end
end

function CompanionBar:ShowSlotTooltip(slotIndex)
    local slot = self.companionSlots[slotIndex]
    if not slot then return end

    if slot.itemName then
        GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
        GameTooltip:SetItemByID(slot.itemName)

        -- Add status info
        if self.currentCompanion == slot.itemName then
            GameTooltip:AddLine("Currently active", 0, 1, 0)
        end

        -- Add cooldown info if applicable
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
        GameTooltip:SetText("Empty Companion Slot")
        GameTooltip:AddLine("Drag a companion pet here or right-click to configure", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

function CompanionBar:SummonCompanion(itemName)
    if not itemName then return end

    -- Dismiss current companion if it's the same one
    if self.currentCompanion == itemName then
        self:DismissCompanion()
        return
    end

    -- Use the companion item
    UseItemByName(itemName)
    self.currentCompanion = itemName

    -- Update visual indicators
    self:UpdateAllActiveStatus()

    self.Fizzure:ShowNotification("Companion Summoned", itemName .. " has been summoned", "success", 2)
end

function CompanionBar:SummonRandomCompanion()
    local availableCompanions = {}

    -- Collect available companions from slots
    for i = 1, self.settings.maxButtons do
        local slot = self.companionSlots[i]
        if slot and not slot.isEmpty and GetItemCount(slot.itemName) > 0 then
            table.insert(availableCompanions, slot.itemName)
        end
    end

    -- If no companions in slots, use all available
    if #availableCompanions == 0 then
        for _, companion in ipairs(self.availableCompanions) do
            table.insert(availableCompanions, companion.name)
        end
    end

    if #availableCompanions > 0 then
        local randomIndex = math.random(1, #availableCompanions)
        local randomCompanion = availableCompanions[randomIndex]
        self:SummonCompanion(randomCompanion)
    else
        self.Fizzure:ShowNotification("No Companions", "No companion pets available", "warning", 3)
    end
end

function CompanionBar:DismissCompanion()
    if self.currentCompanion then
        -- Use the companion item again to dismiss
        UseItemByName(self.currentCompanion)
        self.currentCompanion = nil

        -- Update visual indicators
        self:UpdateAllActiveStatus()

        self.Fizzure:ShowNotification("Companion Dismissed", "Companion has been dismissed", "info", 2)
    end
end

function CompanionBar:UpdateCompanionStatus()
    -- This is a simplified status check - in 3.3.5 there's limited API for detecting summoned companions
    -- We track based on our own summon/dismiss actions
    self:UpdateAllActiveStatus()
end

function CompanionBar:UpdateAllActiveStatus()
    for i = 1, self.settings.maxButtons do
        self:UpdateSlotActiveStatus(i)
    end
end

function CompanionBar:UpdateSlotActiveStatus(slotIndex)
    local slot = self.companionSlots[slotIndex]
    if not slot or slot.isEmpty then return end

    if self.currentCompanion == slot.itemName then
        slot.activeRing:Show()
        slot.icon:SetDesaturated(false)
    else
        slot.activeRing:Hide()
        slot.icon:SetDesaturated(false)
    end
end

function CompanionBar:UpdateCooldowns()
    for i = 1, self.settings.maxButtons do
        self:UpdateSlotCooldown(i)
    end
end

function CompanionBar:UpdateSlotCooldown(slotIndex)
    local slot = self.companionSlots[slotIndex]
    if not slot or slot.isEmpty then return end

    local start, duration = GetItemCooldown(slot.itemName)

    if start > 0 and duration > 1.5 then
        slot.cooldown:SetCooldown(start, duration)
        slot.cooldown:Show()
        slot.icon:SetDesaturated(true)
    else
        slot.cooldown:Hide()
        if self.currentCompanion ~= slot.itemName then
            slot.icon:SetDesaturated(false)
        end
    end
end

function CompanionBar:UpdateKeybindDisplay(slotIndex)
    local slot = self.companionSlots[slotIndex]
    if not slot then return end

    local keybind = self.settings.keybindings[slotIndex]
    if keybind then
        slot.keybind:SetText(keybind)
    else
        slot.keybind:SetText("")
    end
end

function CompanionBar:ShowContextMenu()
    local menu = CreateFrame("Frame", "FizzureCompanionContextMenu", UIParent)
    menu:SetSize(150, 120)
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

    -- Random companion button
    local randomBtn = FizzureUI:CreateButton(menu, "Random", 130, 20, function()
        menu:Hide()
        self:SummonRandomCompanion()
    end, true)
    randomBtn:SetPoint("TOP", 0, y)
    y = y - 25

    -- Dismiss companion button
    local dismissBtn = FizzureUI:CreateButton(menu, "Dismiss", 130, 20, function()
        menu:Hide()
        self:DismissCompanion()
    end, true)
    dismissBtn:SetPoint("TOP", 0, y)
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

function CompanionBar:ShowConfigWindow()
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

function CompanionBar:CreateConfigWindow()
    self.configWindow = FizzureUI:CreateWindow("CompanionConfig", "Companion Bar Configuration", 500, 400, nil, true)

    -- Available companions list
    local availableLabel = FizzureUI:CreateLabel(self.configWindow.content, "Available Companions:", "GameFontNormal")
    availableLabel:SetPoint("TOPLEFT", 10, -10)

    self.availableScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 280)
    self.availableScroll:SetPoint("TOPLEFT", 10, -30)

    -- Current bar setup
    local barLabel = FizzureUI:CreateLabel(self.configWindow.content, "Companion Bar Setup:", "GameFontNormal")
    barLabel:SetPoint("TOPRIGHT", -10, -10)

    self.barScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 280)
    self.barScroll:SetPoint("TOPRIGHT", -10, -30)

    -- Bottom controls
    local autoAddCheck = FizzureUI:CreateCheckBox(self.configWindow.content, "Auto-add new companions",
            self.settings.autoAddCompanions, function(checked)
                self.settings.autoAddCompanions = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("BOTTOMLEFT", 10, 60)

    local dismissCombatCheck = FizzureUI:CreateCheckBox(self.configWindow.content, "Dismiss on combat",
            self.settings.dismissOnCombat, function(checked)
                self.settings.dismissOnCombat = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    dismissCombatCheck:SetPoint("BOTTOMLEFT", 10, 35)

    local saveBtn = FizzureUI:CreateButton(self.configWindow.content, "Save & Close", 100, 24, function()
        self:SaveCompanions()
        self.configWindow:Hide()
    end, true)
    saveBtn:SetPoint("BOTTOM", 0, 10)
end

function CompanionBar:UpdateConfigWindow()
    if not self.configWindow or not self.configWindow:IsShown() then return end

    -- Update available companions list
    local content = self.availableScroll.content
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end

    local y = -5
    for _, companion in ipairs(self.availableCompanions) do
        local frame = CreateFrame("Button", nil, content)
        frame:SetSize(200, 25)
        frame:SetPoint("TOPLEFT", 5, y)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)

        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(companion.name)
        if itemIcon then
            icon:SetTexture(itemIcon)
        end

        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetText(companion.name)
        nameText:SetTextColor(0.9, 0.9, 0.9)

        frame:SetScript("OnClick", function()
            self:AddCompanionToBar(companion.name, companion.link)
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
        local slot = self.companionSlots[i]

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

            if self.currentCompanion == slot.itemName then
                nameText:SetTextColor(0, 1, 0)
            else
                nameText:SetTextColor(0.8, 0.8, 0.8)
            end

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

function CompanionBar:AddCompanionToBar(itemName, itemLink)
    -- Find first empty slot
    for i = 1, self.settings.maxButtons do
        local slot = self.companionSlots[i]
        if slot and slot.isEmpty then
            self:SetSlotCompanion(i, itemName, itemLink)
            self:UpdateConfigWindow()
            return
        end
    end

    self.Fizzure:ShowNotification("Bar Full", "All companion slots are full", "warning", 3)
end

function CompanionBar:ClearAllSlots()
    for i = 1, self.settings.maxButtons do
        self:ClearSlot(i)
    end
    self:SaveCompanions()
end

function CompanionBar:ToggleBar()
    self.settings.showBar = not self.settings.showBar
    self.Fizzure:SetModuleSettings(self.name, self.settings)

    if self.settings.showBar then
        self.companionBar:Show()
    else
        self.companionBar:Hide()
    end
end

function CompanionBar:SaveBarPosition()
    local point, _, _, x, y = self.companionBar:GetPoint()
    self.settings.barPosition = {
        point = point,
        x = x,
        y = y
    }
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function CompanionBar:SaveCompanions()
    local savedCompanions = {}

    for i = 1, self.settings.maxButtons do
        local slot = self.companionSlots[i]
        if slot and not slot.isEmpty then
            savedCompanions[i] = {
                name = slot.itemName,
                link = slot.itemLink
            }
        end
    end

    self.settings.savedCompanions = savedCompanions
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function CompanionBar:LoadSavedCompanions()
    for i, companionData in pairs(self.settings.savedCompanions) do
        if companionData and companionData.name then
            -- Check if companion is still available
            if GetItemCount(companionData.name) > 0 then
                self:SetSlotCompanion(i, companionData.name, companionData.link)
            end
        end
    end
end

function CompanionBar:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

function CompanionBar:CreateConfigUI(parent, x, y)
    local showBarCheck = FizzureUI:CreateCheckBox(parent, "Show companion bar",
            self.settings.showBar, function(checked)
                self.settings.showBar = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.companionBar:Show()
                else
                    self.companionBar:Hide()
                end
            end, true)
    showBarCheck:SetPoint("TOPLEFT", x, y)

    local autoAddCheck = FizzureUI:CreateCheckBox(parent, "Auto-add new companions",
            self.settings.autoAddCompanions, function(checked)
                self.settings.autoAddCompanions = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("TOPLEFT", x, y - 25)

    local dismissCombatCheck = FizzureUI:CreateCheckBox(parent, "Dismiss companion on combat",
            self.settings.dismissOnCombat, function(checked)
                self.settings.dismissOnCombat = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    dismissCombatCheck:SetPoint("TOPLEFT", x, y - 50)

    local configBtn = FizzureUI:CreateButton(parent, "Configure Bar", 100, 24, function()
        self:ShowConfigWindow()
    end, true)
    configBtn:SetPoint("TOPLEFT", x, y - 80)

    local randomBtn = FizzureUI:CreateButton(parent, "Random Pet", 100, 24, function()
        self:SummonRandomCompanion()
    end, true)
    randomBtn:SetPoint("TOPLEFT", x + 110, y - 80)

    return y - 110
end

function CompanionBar:GetQuickStatus()
    local equipped = 0
    local active = self.currentCompanion and 1 or 0

    for i = 1, self.settings.maxButtons do
        local slot = self.companionSlots[i]
        if slot and not slot.isEmpty then
            equipped = equipped + 1
        end
    end

    return string.format("Companions: %d equipped, %d active", equipped, active)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Companion Bar", CompanionBar, "Action Bars")
end