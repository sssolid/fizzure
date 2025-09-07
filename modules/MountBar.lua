-- MountBar.lua - Mount Bar for Quick Mount Access for Fizzure
local MountBar = {}

MountBar.name = "Mount Bar"
MountBar.version = "1.0"
MountBar.author = "Fizzure"
MountBar.category = "Action Bars"

-- Mount types and speeds for 3.3.5
local MOUNT_TYPES = {
    ["ground"] = {
        speed60 = {"Horse", "Wolf", "Ram", "Saber", "Skeletal Horse", "Mechanostrider"},
        speed100 = {"Swift", "Epic"}
    },
    ["flying"] = {
        speed60 = {"Flying Carpet", "Gryphon", "Wind Rider", "Nether Ray"},
        speed100 = {"Swift Flying", "Epic Flying"}
    }
}

function MountBar:GetDefaultSettings()
    return {
        enabled = true,
        showBar = true,
        barPosition = {
            point = "BOTTOM",
            x = -200,
            y = 150
        },
        barWidth = 350,
        barHeight = 40,
        buttonSize = 36,
        buttonSpacing = 4,
        maxButtons = 8,
        showTooltips = true,
        autoAddMounts = true,
        smartMounting = true, -- Use flying mounts in flying areas, ground otherwise
        savedMounts = {},
        keybindings = {},
        barOrientation = "horizontal",
        favoriteMount = nil -- Primary mount for smart mounting
    }
end

function MountBar:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showBar) == "boolean" and
            type(settings.maxButtons) == "number"
end

function MountBar:Initialize()
    if not self.Fizzure then
        print("|cffff0000Mount Bar Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize mount tracking
    self.mountSlots = {}
    self.availableMounts = {}
    self.currentZoneInfo = nil

    -- Create the mount bar
    self:CreateMountBar()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        MountBar:OnEvent(event, ...)
    end)

    -- Update timer for cooldowns and zone detection
    self.updateTimer = FizzureCommon:NewTicker(1, function()
        self:UpdateCooldowns()
        self:UpdateZoneInfo()
    end)

    -- Scan for mounts initially
    self:ScanForMounts()
    self:LoadSavedMounts()
    self:UpdateZoneInfo()

    if self.settings.showBar then
        self.mountBar:Show()
    end

    print("|cff00ff00Mount Bar|r Initialized")
    return true
end

function MountBar:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.mountBar then
        self.mountBar:Hide()
    end

    self:SaveMounts()
end

function MountBar:OnEvent(event, ...)
    if event == "BAG_UPDATE" then
        self:ScanForMounts()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        self:UpdateZoneInfo()
        self:UpdateMountAvailability()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        self:UpdateCooldowns()
    end
end

function MountBar:CreateMountBar()
    -- Main bar frame
    self.mountBar = CreateFrame("Frame", "FizzureMountBar", UIParent)
    self.mountBar:SetSize(self.settings.barWidth, self.settings.barHeight)
    self.mountBar:SetPoint(self.settings.barPosition.point, UIParent, self.settings.barPosition.point,
            self.settings.barPosition.x, self.settings.barPosition.y)

    -- Flat design background
    self.mountBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    self.mountBar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    self.mountBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Make movable
    self.mountBar:SetMovable(true)
    self.mountBar:EnableMouse(true)
    self.mountBar:RegisterForDrag("LeftButton")
    self.mountBar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    self.mountBar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MountBar:SaveBarPosition()
    end)

    -- Title label
    local title = self.mountBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -2)
    title:SetText("Mounts")
    title:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Smart mount button (special first slot)
    self:CreateSmartMountButton()

    -- Create mount slots
    self:CreateMountSlots()

    -- Context menu for configuration
    self.mountBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MountBar:ShowContextMenu()
        end
    end)

    self.mountBar:Hide()
end

function MountBar:CreateSmartMountButton()
    local button = CreateFrame("Button", "FizzureSmartMountButton", self.mountBar)
    button:SetSize(self.settings.buttonSize, self.settings.buttonSize)
    button:SetPoint("TOPLEFT", 10, -15)

    -- Flat design styling with accent color
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    button:SetBackdropColor(0.2, 0.6, 1, 0.3) -- Blue accent
    button:SetBackdropBorderColor(0.2, 0.6, 1, 1)

    -- Smart mount icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(self.settings.buttonSize - 4, self.settings.buttonSize - 4)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse") -- Default mount icon
    button.icon = icon

    -- Label
    local label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    label:SetPoint("BOTTOM", 0, -12)
    label:SetText("Smart")
    label:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Click handler
    button:SetScript("OnClick", function()
        self:SmartMount()
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Smart Mount")
        GameTooltip:AddLine("Automatically selects the best mount for your current zone", 0.7, 0.7, 0.7)
        if MountBar.settings.favoriteMount then
            GameTooltip:AddLine("Favorite: " .. MountBar.settings.favoriteMount, 0, 1, 0)
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.smartMountButton = button
end

function MountBar:CreateMountSlots()
    for i = 1, self.settings.maxButtons do
        local slot = self:CreateMountSlot(i)
        self.mountSlots[i] = slot
    end
end

function MountBar:CreateMountSlot(index)
    local slot = CreateFrame("Button", "FizzureMountSlot" .. index, self.mountBar)
    slot:SetSize(self.settings.buttonSize, self.settings.buttonSize)

    -- Position the slot (offset by smart mount button)
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

    -- Mount icon
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetSize(self.settings.buttonSize - 4, self.settings.buttonSize - 4)
    icon:SetPoint("CENTER")
    slot.icon = icon

    -- Cooldown frame
    local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    slot.cooldown = cooldown

    -- Mount type indicator
    local typeIcon = slot:CreateTexture(nil, "OVERLAY")
    typeIcon:SetSize(12, 12)
    typeIcon:SetPoint("TOPRIGHT", -2, -2)
    slot.typeIcon = typeIcon

    -- Keybind text
    local keybind = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keybind:SetPoint("TOPLEFT", 2, -2)
    keybind:SetTextColor(0.7, 0.7, 0.7, 1)
    slot.keybind = keybind

    -- Click handlers
    slot:SetScript("OnClick", function(self, button)
        MountBar:OnSlotClick(index, button)
    end)

    -- Drag and drop
    slot:SetScript("OnReceiveDrag", function()
        MountBar:OnSlotDrop(index)
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        MountBar:ShowSlotTooltip(index)
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

function MountBar:GetSlotPosition(index)
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

function MountBar:ScanForMounts()
    self.availableMounts = {}

    -- Scan bags for mount items
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemName, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
                if itemName and self:IsMountItem(itemName, itemType, itemSubType) then
                    local _, itemCount = GetContainerItemInfo(bag, slot)

                    if itemCount and itemCount > 0 then
                        local mountInfo = self:GetMountInfo(itemName)
                        table.insert(self.availableMounts, {
                            name = itemName,
                            link = itemLink,
                            bag = bag,
                            slot = slot,
                            count = itemCount,
                            mountType = mountInfo.type,
                            speed = mountInfo.speed
                        })
                    end
                end
            end
        end
    end

    -- Auto-add new mounts if enabled
    if self.settings.autoAddMounts then
        self:AutoAddMounts()
    end
end

function MountBar:IsMountItem(itemName, itemType, itemSubType)
    if not itemName then return false end

    local nameLower = string.lower(itemName)

    -- Check for common mount keywords
    local mountKeywords = {
        "horse", "wolf", "ram", "saber", "kodo", "raptor", "strider", "mechanostrider",
        "gryphon", "wyvern", "bat", "carpet", "drake", "proto", "warhorse",
        "charger", "steed", "mount", "riding", "swift", "skeletal", "spectral"
    }

    for _, keyword in ipairs(mountKeywords) do
        if string.find(nameLower, keyword) then
            return true
        end
    end

    return false
end

function MountBar:GetMountInfo(itemName)
    local nameLower = string.lower(itemName)
    local info = {
        type = "ground",
        speed = 60
    }

    -- Determine mount type
    if string.find(nameLower, "flying") or string.find(nameLower, "gryphon") or
            string.find(nameLower, "wyvern") or string.find(nameLower, "drake") or
            string.find(nameLower, "proto") or string.find(nameLower, "carpet") then
        info.type = "flying"
    end

    -- Determine speed
    if string.find(nameLower, "swift") or string.find(nameLower, "epic") then
        info.speed = 100
    end

    return info
end

function MountBar:AutoAddMounts()
    for _, mount in ipairs(self.availableMounts) do
        local alreadyAdded = false

        -- Check if already in a slot
        for i = 1, self.settings.maxButtons do
            local slot = self.mountSlots[i]
            if slot and slot.itemName == mount.name then
                alreadyAdded = true
                break
            end
        end

        -- Add to first empty slot if not already added
        if not alreadyAdded then
            for i = 1, self.settings.maxButtons do
                local slot = self.mountSlots[i]
                if slot and slot.isEmpty then
                    self:SetSlotMount(i, mount.name, mount.link)
                    break
                end
            end
        end
    end
end

function MountBar:SetSlotMount(slotIndex, itemName, itemLink)
    local slot = self.mountSlots[slotIndex]
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

    -- Set mount type indicator
    local mountInfo = self:GetMountInfo(itemName)
    if mountInfo.type == "flying" then
        slot.typeIcon:SetTexture("Interface\\Icons\\Ability_Mount_Drake_Azure")
        slot.typeIcon:SetTexCoord(0, 1, 0, 1)
        slot.typeIcon:Show()
    else
        slot.typeIcon:Hide()
    end

    -- Update keybind display
    self:UpdateKeybindDisplay(slotIndex)

    -- Update availability
    self:UpdateSlotAvailability(slotIndex)
end

function MountBar:ClearSlot(slotIndex)
    local slot = self.mountSlots[slotIndex]
    if not slot then return end

    slot.itemName = nil
    slot.itemLink = nil
    slot.isEmpty = true
    slot.icon:SetTexture(nil)
    slot.typeIcon:Hide()
    slot.cooldown:Hide()
    slot.keybind:SetText("")
end

function MountBar:OnSlotClick(slotIndex, button)
    local slot = self.mountSlots[slotIndex]
    if not slot then return end

    if button == "LeftButton" then
        if slot.itemName then
            self:UseMount(slot.itemName)
        end
    elseif button == "RightButton" then
        -- Remove mount from slot or set as favorite
        if IsShiftKeyDown() then
            self:SetFavoriteMount(slot.itemName)
        else
            self:ClearSlot(slotIndex)
            self:SaveMounts()
        end
    end
end

function MountBar:OnSlotDrop(slotIndex)
    local cursorType, itemID, itemLink = GetCursorInfo()

    if cursorType == "item" and itemLink then
        local itemName = GetItemInfo(itemLink)

        if itemName and self:IsMountItem(itemName) then
            self:SetSlotMount(slotIndex, itemName, itemLink)
            self:SaveMounts()
            ClearCursor()
        else
            self.Fizzure:ShowNotification("Invalid Item", "Only mounts can be added to the mount bar", "error", 3)
        end
    end
end

function MountBar:ShowSlotTooltip(slotIndex)
    local slot = self.mountSlots[slotIndex]
    if not slot then return end

    if slot.itemName then
        GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
        GameTooltip:SetItemByID(slot.itemName)

        -- Add mount info
        local mountInfo = self:GetMountInfo(slot.itemName)
        GameTooltip:AddLine(string.format("Type: %s, Speed: %d%%",
                mountInfo.type == "flying" and "Flying" or "Ground", mountInfo.speed), 0.7, 0.7, 0.7)

        -- Add cooldown info if applicable
        local start, duration = GetItemCooldown(slot.itemName)
        if start > 0 and duration > 0 then
            local remaining = start + duration - GetTime()
            if remaining > 0 then
                GameTooltip:AddLine(string.format("Cooldown: %s", self:FormatTime(remaining)), 1, 0.82, 0)
            end
        end

        -- Add availability info
        if not self:IsMountAvailable(slot.itemName) then
            GameTooltip:AddLine("Not available in this zone", 1, 0.2, 0.2)
        end

        GameTooltip:AddLine("Shift+Right-click to set as favorite", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    else
        GameTooltip:SetOwner(slot, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Empty Mount Slot")
        GameTooltip:AddLine("Drag a mount here or right-click to configure", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

function MountBar:UseMount(itemName)
    if not self:IsMountAvailable(itemName) then
        self.Fizzure:ShowNotification("Mount Unavailable", "This mount cannot be used in the current zone", "error", 3)
        return
    end

    -- Dismount if mounted
    if IsMounted() then
        Dismount()
        return
    end

    -- Use the mount
    UseItemByName(itemName)
end

function MountBar:SmartMount()
    if IsMounted() then
        Dismount()
        return
    end

    local bestMount = self:GetBestAvailableMount()
    if bestMount then
        self:UseMount(bestMount)
    else
        self.Fizzure:ShowNotification("No Mounts", "No suitable mounts available", "warning", 3)
    end
end

function MountBar:GetBestAvailableMount()
    -- Use favorite mount if available
    if self.settings.favoriteMount and self:IsMountAvailable(self.settings.favoriteMount) then
        return self.settings.favoriteMount
    end

    -- Find best available mount based on zone
    local bestMount = nil
    local bestSpeed = 0
    local preferFlying = self:CanFly()

    -- Check mounted mounts first
    for i = 1, self.settings.maxButtons do
        local slot = self.mountSlots[i]
        if slot and not slot.isEmpty and self:IsMountAvailable(slot.itemName) then
            local mountInfo = self:GetMountInfo(slot.itemName)

            -- Prefer flying mounts in flying zones
            local score = mountInfo.speed
            if preferFlying and mountInfo.type == "flying" then
                score = score + 50
            elseif not preferFlying and mountInfo.type == "ground" then
                score = score + 10
            end

            if score > bestSpeed then
                bestSpeed = score
                bestMount = slot.itemName
            end
        end
    end

    -- If no mounted mounts, check all available
    if not bestMount then
        for _, mount in ipairs(self.availableMounts) do
            if self:IsMountAvailable(mount.name) then
                local score = mount.speed
                if preferFlying and mount.mountType == "flying" then
                    score = score + 50
                elseif not preferFlying and mount.mountType == "ground" then
                    score = score + 10
                end

                if score > bestSpeed then
                    bestSpeed = score
                    bestMount = mount.name
                end
            end
        end
    end

    return bestMount
end

function MountBar:UpdateZoneInfo()
    local zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    local isInstance, instanceType = IsInInstance()

    self.currentZoneInfo = {
        zone = zone,
        subzone = subzone,
        isInstance = isInstance,
        instanceType = instanceType,
        canFly = self:CanFly()
    }
end

function MountBar:CanFly()
    -- Basic flying zone detection for 3.3.5
    local zone = GetRealZoneText()
    if not zone then return false end

    local flyingZones = {
        "Outland", "Hellfire Peninsula", "Zangarmarsh", "Nagrand", "Blade's Edge Mountains",
        "Netherstorm", "Shadowmoon Valley", "Terokkar Forest", "Borean Tundra", "Dragonblight",
        "Grizzly Hills", "Howling Fjord", "Icecrown", "Sholazar Basin", "The Storm Peaks",
        "Wintergrasp", "Zul'Drak", "Crystalsong Forest"
    }

    for _, flyingZone in ipairs(flyingZones) do
        if string.find(zone, flyingZone) then
            return true
        end
    end

    return false
end

function MountBar:IsMountAvailable(itemName)
    if not itemName or GetItemCount(itemName) == 0 then
        return false
    end

    -- Check if in instance where mounts aren't allowed
    if self.currentZoneInfo and self.currentZoneInfo.isInstance then
        return false
    end

    local mountInfo = self:GetMountInfo(itemName)

    -- Flying mounts require flying zones
    if mountInfo.type == "flying" and not self:CanFly() then
        return false
    end

    return true
end

function MountBar:UpdateMountAvailability()
    for i = 1, self.settings.maxButtons do
        self:UpdateSlotAvailability(i)
    end
end

function MountBar:UpdateSlotAvailability(slotIndex)
    local slot = self.mountSlots[slotIndex]
    if not slot or slot.isEmpty then return end

    if self:IsMountAvailable(slot.itemName) then
        slot.icon:SetDesaturated(false)
        slot:SetAlpha(1)
    else
        slot.icon:SetDesaturated(true)
        slot:SetAlpha(0.5)
    end
end

function MountBar:UpdateCooldowns()
    for i = 1, self.settings.maxButtons do
        self:UpdateSlotCooldown(i)
    end
end

function MountBar:UpdateSlotCooldown(slotIndex)
    local slot = self.mountSlots[slotIndex]
    if not slot or slot.isEmpty then return end

    local start, duration = GetItemCooldown(slot.itemName)

    if start > 0 and duration > 1.5 then
        slot.cooldown:SetCooldown(start, duration)
        slot.cooldown:Show()
    else
        slot.cooldown:Hide()
    end
end

function MountBar:UpdateKeybindDisplay(slotIndex)
    local slot = self.mountSlots[slotIndex]
    if not slot then return end

    local keybind = self.settings.keybindings[slotIndex]
    if keybind then
        slot.keybind:SetText(keybind)
    else
        slot.keybind:SetText("")
    end
end

function MountBar:SetFavoriteMount(itemName)
    self.settings.favoriteMount = itemName
    self.Fizzure:SetModuleSettings(self.name, self.settings)
    self.Fizzure:ShowNotification("Favorite Set", itemName .. " set as favorite mount", "success", 3)

    -- Update smart mount button icon
    local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemName)
    if itemIcon then
        self.smartMountButton.icon:SetTexture(itemIcon)
    end
end

function MountBar:ShowContextMenu()
    local menu = CreateFrame("Frame", "FizzureMountContextMenu", UIParent)
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

    -- Clear all button
    local clearBtn = FizzureUI:CreateButton(menu, "Clear All", 130, 20, function()
        menu:Hide()
        self:ClearAllSlots()
    end, true)
    clearBtn:SetPoint("TOP", 0, y)
    y = y - 25

    -- Smart mount button
    local smartBtn = FizzureUI:CreateButton(menu, "Smart Mount", 130, 20, function()
        menu:Hide()
        self:SmartMount()
    end, true)
    smartBtn:SetPoint("TOP", 0, y)
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

function MountBar:ShowConfigWindow()
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

function MountBar:CreateConfigWindow()
    self.configWindow = FizzureUI:CreateWindow("MountConfig", "Mount Bar Configuration", 500, 400, nil, true)

    -- Available mounts list
    local availableLabel = FizzureUI:CreateLabel(self.configWindow.content, "Available Mounts:", "GameFontNormal")
    availableLabel:SetPoint("TOPLEFT", 10, -10)

    self.availableScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 280)
    self.availableScroll:SetPoint("TOPLEFT", 10, -30)

    -- Current bar setup
    local barLabel = FizzureUI:CreateLabel(self.configWindow.content, "Mount Bar Setup:", "GameFontNormal")
    barLabel:SetPoint("TOPRIGHT", -10, -10)

    self.barScroll = FizzureUI:CreateScrollFrame(self.configWindow.content, 220, 280)
    self.barScroll:SetPoint("TOPRIGHT", -10, -30)

    -- Bottom controls
    local autoAddCheck = FizzureUI:CreateCheckBox(self.configWindow.content, "Auto-add new mounts",
            self.settings.autoAddMounts, function(checked)
                self.settings.autoAddMounts = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("BOTTOMLEFT", 10, 60)

    local smartCheck = FizzureUI:CreateCheckBox(self.configWindow.content, "Smart mounting",
            self.settings.smartMounting, function(checked)
                self.settings.smartMounting = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    smartCheck:SetPoint("BOTTOMLEFT", 10, 35)

    local saveBtn = FizzureUI:CreateButton(self.configWindow.content, "Save & Close", 100, 24, function()
        self:SaveMounts()
        self.configWindow:Hide()
    end, true)
    saveBtn:SetPoint("BOTTOM", 0, 10)
end

function MountBar:UpdateConfigWindow()
    if not self.configWindow or not self.configWindow:IsShown() then return end

    -- Update available mounts list
    local content = self.availableScroll.content
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then child:Hide() end
    end

    local y = -5
    for _, mount in ipairs(self.availableMounts) do
        local frame = CreateFrame("Button", nil, content)
        frame:SetSize(200, 25)
        frame:SetPoint("TOPLEFT", 5, y)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)

        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(mount.name)
        if itemIcon then
            icon:SetTexture(itemIcon)
        end

        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetText(mount.name)
        nameText:SetTextColor(0.9, 0.9, 0.9)

        local typeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeText:SetPoint("RIGHT", -5, 0)
        typeText:SetText(mount.mountType == "flying" and "F" or "G")
        typeText:SetTextColor(mount.mountType == "flying" and 0.5 or 1, mount.mountType == "flying" and 0.8 or 0.8, 1)

        frame:SetScript("OnClick", function()
            self:AddMountToBar(mount.name, mount.link)
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
        local slot = self.mountSlots[i]

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
            removeBtn:SetPoint("RIGHT", -25, 0)

            local favBtn = FizzureUI:CreateButton(frame, "★", 15, 15, function()
                self:SetFavoriteMount(slot.itemName)
                self:UpdateConfigWindow()
            end, true)
            favBtn:SetPoint("RIGHT", -5, 0)

            if self.settings.favoriteMount == slot.itemName then
                favBtn:SetBackdropColor(1, 0.8, 0, 1)
            end
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

function MountBar:AddMountToBar(itemName, itemLink)
    -- Find first empty slot
    for i = 1, self.settings.maxButtons do
        local slot = self.mountSlots[i]
        if slot and slot.isEmpty then
            self:SetSlotMount(i, itemName, itemLink)
            self:UpdateConfigWindow()
            return
        end
    end

    self.Fizzure:ShowNotification("Bar Full", "All mount slots are full", "warning", 3)
end

function MountBar:ClearAllSlots()
    for i = 1, self.settings.maxButtons do
        self:ClearSlot(i)
    end
    self:SaveMounts()
end

function MountBar:ToggleBar()
    self.settings.showBar = not self.settings.showBar
    self.Fizzure:SetModuleSettings(self.name, self.settings)

    if self.settings.showBar then
        self.mountBar:Show()
    else
        self.mountBar:Hide()
    end
end

function MountBar:SaveBarPosition()
    local point, _, _, x, y = self.mountBar:GetPoint()
    self.settings.barPosition = {
        point = point,
        x = x,
        y = y
    }
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function MountBar:SaveMounts()
    local savedMounts = {}

    for i = 1, self.settings.maxButtons do
        local slot = self.mountSlots[i]
        if slot and not slot.isEmpty then
            savedMounts[i] = {
                name = slot.itemName,
                link = slot.itemLink
            }
        end
    end

    self.settings.savedMounts = savedMounts
    self.Fizzure:SetModuleSettings(self.name, self.settings)
end

function MountBar:LoadSavedMounts()
    for i, mountData in pairs(self.settings.savedMounts) do
        if mountData and mountData.name then
            -- Check if mount is still available
            if GetItemCount(mountData.name) > 0 then
                self:SetSlotMount(i, mountData.name, mountData.link)
            end
        end
    end
end

function MountBar:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

function MountBar:CreateConfigUI(parent, x, y)
    local showBarCheck = FizzureUI:CreateCheckBox(parent, "Show mount bar",
            self.settings.showBar, function(checked)
                self.settings.showBar = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    self.mountBar:Show()
                else
                    self.mountBar:Hide()
                end
            end, true)
    showBarCheck:SetPoint("TOPLEFT", x, y)

    local autoAddCheck = FizzureUI:CreateCheckBox(parent, "Auto-add new mounts",
            self.settings.autoAddMounts, function(checked)
                self.settings.autoAddMounts = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    autoAddCheck:SetPoint("TOPLEFT", x, y - 25)

    local smartCheck = FizzureUI:CreateCheckBox(parent, "Smart mounting",
            self.settings.smartMounting, function(checked)
                self.settings.smartMounting = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    smartCheck:SetPoint("TOPLEFT", x, y - 50)

    local configBtn = FizzureUI:CreateButton(parent, "Configure Bar", 100, 24, function()
        self:ShowConfigWindow()
    end, true)
    configBtn:SetPoint("TOPLEFT", x, y - 80)

    local rescanBtn = FizzureUI:CreateButton(parent, "Rescan Mounts", 100, 24, function()
        self:ScanForMounts()
        self.Fizzure:ShowNotification("Mounts Rescanned", "Mount inventory updated", "success", 2)
    end, true)
    rescanBtn:SetPoint("TOPLEFT", x + 110, y - 80)

    return y - 110
end

function MountBar:GetQuickStatus()
    local mounted = 0
    local flyingMounts = 0

    for i = 1, self.settings.maxButtons do
        local slot = self.mountSlots[i]
        if slot and not slot.isEmpty then
            mounted = mounted + 1
            local mountInfo = self:GetMountInfo(slot.itemName)
            if mountInfo.type == "flying" then
                flyingMounts = flyingMounts + 1
            end
        end
    end

    return string.format("Mounts: %d equipped (%d flying)", mounted, flyingMounts)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Mount Bar", MountBar, "Action Bars")
end