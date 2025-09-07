-- CharacterStats.lua - Enhanced Character Statistics Panel with Inspect Support
local CharacterStatsModule = {}

CharacterStatsModule.name = "Character Stats Panel"
CharacterStatsModule.version = "1.1"
CharacterStatsModule.author = "Fizzure"
CharacterStatsModule.category = "UI/UX"

function CharacterStatsModule:GetDefaultSettings()
    return {
        enabled = true,
        showPanel = true,
        attachToCharacterFrame = true,
        showGearScore = true,
        showDetailedStats = true,
        showResistances = true,
        showOtherPlayers = true,
        inspectOnTarget = true,
        updateFrequency = 1.0,
        panelPosition = {
            point = "TOPLEFT",
            relativeTo = "CharacterFrame",
            relativePoint = "TOPRIGHT",
            x = 5,
            y = 0
        }
    }
end

function CharacterStatsModule:ValidateSettings(settings)
    return type(settings.enabled) == "boolean" and
            type(settings.showPanel) == "boolean" and
            type(settings.attachToCharacterFrame) == "boolean"
end

function CharacterStatsModule:Initialize()
    if not self.Fizzure then
        print("|cffff0000CharacterStats Module Error:|r Core reference missing")
        return false
    end

    self.settings = self.Fizzure:GetModuleSettings(self.name)
    if not self.settings or not next(self.settings) then
        self.settings = self:GetDefaultSettings()
        self.Fizzure:SetModuleSettings(self.name, self.settings)
    end

    -- Initialize inspect cache
    self.inspectCache = {}
    self.currentInspectTarget = "player"

    -- Create the stats panel
    self:CreateStatsPanel()
    self:CreateInspectSelector()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("UNIT_STATS")
    self.eventFrame:RegisterEvent("UNIT_RESISTANCES")
    self.eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

    self.eventFrame:SetScript("OnEvent", function(self, event, ...)
        CharacterStatsModule:OnEvent(event, ...)
    end)

    -- Update timer
    self.updateTimer = FizzureCommon:NewTicker(self.settings.updateFrequency, function()
        self:UpdateStatsDisplay()
    end)

    -- Hook character frame events
    self:HookCharacterFrame()

    print("|cff00ff00Character Stats Module|r Initialized")
    return true
end

function CharacterStatsModule:Shutdown()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end

    if self.statsPanel then
        self.statsPanel:Hide()
    end

    self:UnhookCharacterFrame()
end

function CharacterStatsModule:OnEvent(event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" or
            event == "UNIT_STATS" or
            event == "UNIT_RESISTANCES" or
            event == "COMBAT_RATING_UPDATE" or
            event == "CHARACTER_POINTS_CHANGED" then
        if self.currentInspectTarget == "player" then
            self:UpdateStatsDisplay()
        end
    elseif event == "INSPECT_READY" then
        local guid = ...
        if guid then
            self:CacheInspectData(guid)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if self.settings.inspectOnTarget and UnitExists("target") and UnitIsPlayer("target") then
            self:InspectTarget()
        end
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_InspectUI" then
            self:UpdateStatsDisplay()
        end
    end
end

function CharacterStatsModule:CreateStatsPanel()
    -- Create the main panel frame
    self.statsPanel = CreateFrame("Frame", "FizzureCharacterStatsPanel", UIParent)
    self.statsPanel:SetSize(320, 520)
    self.statsPanel:SetFrameStrata("MEDIUM")
    self.statsPanel:SetFrameLevel(100)

    -- Flat design background
    self.statsPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    self.statsPanel:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    self.statsPanel:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    -- Title
    local title = self.statsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Character Statistics")
    title:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Player selector dropdown area
    local selectorFrame = CreateFrame("Frame", nil, self.statsPanel)
    selectorFrame:SetSize(300, 30)
    selectorFrame:SetPoint("TOP", 0, -40)
    self.selectorFrame = selectorFrame

    -- Create scroll frame for stats
    self.statsScroll = CreateFrame("ScrollFrame", "CharStatsScroll", self.statsPanel, "UIPanelScrollFrameTemplate")
    self.statsScroll:SetPoint("TOPLEFT", 15, -75)
    self.statsScroll:SetPoint("BOTTOMRIGHT", -30, 15)

    local statsContent = CreateFrame("Frame", "CharStatsContent", self.statsScroll)
    statsContent:SetSize(270, 1)
    self.statsScroll:SetScrollChild(statsContent)
    self.statsContent = statsContent

    -- Enable mousewheel
    self.statsScroll:EnableMouseWheel(true)
    self.statsScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 20), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)

    -- Position the panel
    self:PositionPanel()

    -- Hide initially
    self.statsPanel:Hide()
end

function CharacterStatsModule:CreateInspectSelector()
    -- Player selection label
    local label = FizzureUI:CreateLabel(self.selectorFrame, "Viewing:", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0)

    -- Player selection buttons
    local playerBtn = FizzureUI:CreateButton(self.selectorFrame, "You", 60, 24, function()
        self:ViewPlayer("player")
    end, true)
    playerBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
    self.playerBtn = playerBtn

    local targetBtn = FizzureUI:CreateButton(self.selectorFrame, "Target", 60, 24, function()
        if UnitExists("target") and UnitIsPlayer("target") then
            self:ViewPlayer("target")
        else
            self.Fizzure:ShowNotification("No Target", "Target a player to view their stats", "warning", 3)
        end
    end, true)
    targetBtn:SetPoint("LEFT", playerBtn, "RIGHT", 5, 0)
    self.targetBtn = targetBtn

    -- Refresh button
    local refreshBtn = FizzureUI:CreateButton(self.selectorFrame, "Refresh", 60, 24, function()
        self:RefreshCurrentView()
    end, true)
    refreshBtn:SetPoint("RIGHT", -10, 0)
    self.refreshBtn = refreshBtn

    -- Current viewing label
    self.viewingLabel = FizzureUI:CreateLabel(self.selectorFrame, "You", "GameFontNormalLarge")
    self.viewingLabel:SetPoint("CENTER", 0, -10)
    self.viewingLabel:SetTextColor(0.2, 0.6, 1, 1)
end

function CharacterStatsModule:ViewPlayer(unit)
    self.currentInspectTarget = unit

    if unit == "player" then
        self.viewingLabel:SetText("You")
        self.playerBtn:SetAlpha(1)
        self.targetBtn:SetAlpha(0.7)
    else
        local name = UnitName(unit)
        if name then
            self.viewingLabel:SetText(name)
            self.playerBtn:SetAlpha(0.7)
            self.targetBtn:SetAlpha(1)

            -- Inspect the target if not cached
            local guid = UnitGUID(unit)
            if guid and not self.inspectCache[guid] then
                NotifyInspect(unit)
            end
        end
    end

    self:UpdateStatsDisplay()
end

function CharacterStatsModule:InspectTarget()
    if UnitExists("target") and UnitIsPlayer("target") then
        self:ViewPlayer("target")
    end
end

function CharacterStatsModule:RefreshCurrentView()
    if self.currentInspectTarget ~= "player" then
        local guid = UnitGUID(self.currentInspectTarget)
        if guid then
            self.inspectCache[guid] = nil
            NotifyInspect(self.currentInspectTarget)
        end
    end
    self:UpdateStatsDisplay()
end

function CharacterStatsModule:CacheInspectData(guid)
    local unit = self:GetUnitFromGUID(guid)
    if not unit then return end

    -- Cache basic inspect data
    self.inspectCache[guid] = {
        timestamp = GetTime(),
        name = UnitName(unit),
        level = UnitLevel(unit),
        class = UnitClass(unit),
        gear = self:GetInspectGear(unit)
    }

    -- Update display if viewing this unit
    if UnitGUID(self.currentInspectTarget) == guid then
        self:UpdateStatsDisplay()
    end
end

function CharacterStatsModule:GetInspectGear(unit)
    local gear = {}

    for slot = 1, 19 do
        local itemLink = GetInventoryItemLink(unit, slot)
        if itemLink then
            gear[slot] = itemLink
        end
    end

    return gear
end

function CharacterStatsModule:GetUnitFromGUID(guid)
    if UnitGUID("target") == guid then return "target" end
    if UnitGUID("player") == guid then return "player" end

    -- Check party/raid members
    for i = 1, 40 do
        local unit = GetNumRaidMembers() > 0 and "raid" .. i or "party" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

function CharacterStatsModule:PositionPanel()
    if self.settings.attachToCharacterFrame then
        self.statsPanel:SetPoint(
                self.settings.panelPosition.point,
                self.settings.panelPosition.relativeTo,
                self.settings.panelPosition.relativePoint,
                self.settings.panelPosition.x,
                self.settings.panelPosition.y
        )
    else
        self.statsPanel:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
    end
end

function CharacterStatsModule:HookCharacterFrame()
    -- Hook character frame show/hide
    if CharacterFrame then
        self.originalCharacterFrameShow = CharacterFrame:GetScript("OnShow")
        CharacterFrame:SetScript("OnShow", function(...)
            if self.originalCharacterFrameShow then
                self.originalCharacterFrameShow(...)
            end
            if self.settings.showPanel and self.settings.attachToCharacterFrame then
                self.statsPanel:Show()
                self:UpdateStatsDisplay()
            end
        end)

        self.originalCharacterFrameHide = CharacterFrame:GetScript("OnHide")
        CharacterFrame:SetScript("OnHide", function(...)
            if self.originalCharacterFrameHide then
                self.originalCharacterFrameHide(...)
            end
            if self.settings.attachToCharacterFrame then
                self.statsPanel:Hide()
            end
        end)
    end
end

function CharacterStatsModule:UnhookCharacterFrame()
    if CharacterFrame and self.originalCharacterFrameShow then
        CharacterFrame:SetScript("OnShow", self.originalCharacterFrameShow)
        CharacterFrame:SetScript("OnHide", self.originalCharacterFrameHide)
    end
end

-- Get stats for unit (player or inspected)
function CharacterStatsModule:GetUnitStats(unit)
    local stats = {}

    if unit == "player" or UnitIsUnit(unit, "player") then
        -- Player stats - direct API access
        stats.strength = UnitStat("player", 1)
        stats.agility = UnitStat("player", 2)
        stats.stamina = UnitStat("player", 3)
        stats.intellect = UnitStat("player", 4)
        stats.spirit = UnitStat("player", 5)
        stats.health = UnitHealthMax("player")
        stats.mana = UnitPowerMax("player")
        stats.armor = UnitArmor("player")
        stats.attackPower = UnitAttackPower("player")
        stats.rangedAttackPower = UnitRangedAttackPower("player")
        stats.level = UnitLevel("player")
    else
        -- Inspected unit - limited info available
        local guid = UnitGUID(unit)
        local cached = guid and self.inspectCache[guid]

        if cached then
            stats.level = cached.level
            stats.class = cached.class
            stats.name = cached.name
            -- Calculate estimated stats from gear
            stats = self:EstimateStatsFromGear(stats, cached.gear)
        else
            -- Fallback to basic unit info
            stats.level = UnitLevel(unit) or 0
            stats.health = UnitHealthMax(unit) or 0
            stats.mana = UnitPowerMax(unit) or 0
            stats.name = UnitName(unit)
            stats.class = UnitClass(unit)
        end
    end

    return stats
end

function CharacterStatsModule:EstimateStatsFromGear(stats, gear)
    if not gear then return stats end

    local totalStats = {
        stamina = 0,
        intellect = 0,
        spirit = 0,
        strength = 0,
        agility = 0,
        armor = 0
    }

    -- Basic estimation based on item level and type
    for slot, itemLink in pairs(gear) do
        if itemLink then
            local _, _, quality, itemLevel = GetItemInfo(itemLink)
            if quality and itemLevel then
                -- Very rough estimation based on item level
                local statBudget = itemLevel * (quality + 1) * 0.5

                -- Distribute stats based on slot type
                if slot == 1 or slot == 5 or slot == 7 then -- Head, Chest, Legs
                    totalStats.stamina = totalStats.stamina + (statBudget * 0.4)
                    totalStats.armor = totalStats.armor + (itemLevel * 2)
                elseif slot >= 11 and slot <= 12 then -- Rings
                    totalStats.intellect = totalStats.intellect + (statBudget * 0.3)
                    totalStats.spirit = totalStats.spirit + (statBudget * 0.2)
                end
            end
        end
    end

    -- Apply estimations
    stats.estimatedStamina = math.floor(totalStats.stamina)
    stats.estimatedIntellect = math.floor(totalStats.intellect)
    stats.estimatedSpirit = math.floor(totalStats.spirit)
    stats.estimatedArmor = math.floor(totalStats.armor)

    return stats
end

-- Updated stats display function
function CharacterStatsModule:UpdateStatsDisplay()
    if not self.statsPanel or not self.statsPanel:IsShown() then return end

    -- Clear existing content
    local content = self.statsContent
    for i = 1, content:GetNumChildren() do
        local child = select(i, content:GetChildren())
        if child then
            child:Hide()
        end
    end

    local unit = self.currentInspectTarget
    local stats = self:GetUnitStats(unit)

    local yOffset = -10
    local sectionSpacing = -5

    -- Basic info section
    yOffset = self:AddSection(content, "CHARACTER INFO", yOffset)
    yOffset = yOffset + sectionSpacing

    if stats.name then
        yOffset = self:AddStatLine(content, "Name", stats.name, yOffset)
    end
    if stats.level then
        yOffset = self:AddStatLine(content, "Level", stats.level, yOffset)
    end
    if stats.class then
        yOffset = self:AddStatLine(content, "Class", stats.class, yOffset)
    end
    yOffset = yOffset - 10

    -- Gear Score Section (if available)
    if self.settings.showGearScore then
        local gearScore = self:GetGearScore(unit)
        if gearScore > 0 then
            yOffset = self:AddSection(content, "GEAR SCORE", yOffset)
            yOffset = yOffset + sectionSpacing
            yOffset = self:AddStatLine(content, "Gear Score", self:FormatGearScore(gearScore), yOffset, true)

            local avgItemLevel = self:GetAverageItemLevel(unit)
            if avgItemLevel > 0 then
                yOffset = self:AddStatLine(content, "Avg Item Level", avgItemLevel, yOffset)
            end
            yOffset = yOffset - 10
        end
    end

    -- Basic Attributes
    if unit == "player" or UnitIsUnit(unit, "player") then
        yOffset = self:AddSection(content, "ATTRIBUTES", yOffset)
        yOffset = yOffset + sectionSpacing

        yOffset = self:AddStatLine(content, "Strength", stats.strength or 0, yOffset)
        yOffset = self:AddStatLine(content, "Agility", stats.agility or 0, yOffset)
        yOffset = self:AddStatLine(content, "Stamina", stats.stamina or 0, yOffset)
        yOffset = self:AddStatLine(content, "Intellect", stats.intellect or 0, yOffset)
        yOffset = self:AddStatLine(content, "Spirit", stats.spirit or 0, yOffset)
        yOffset = yOffset - 10

        -- Health and Mana
        yOffset = self:AddSection(content, "VITALS", yOffset)
        yOffset = yOffset + sectionSpacing

        yOffset = self:AddStatLine(content, "Health", stats.health or 0, yOffset)
        yOffset = self:AddStatLine(content, "Mana", stats.mana or 0, yOffset)

        local healthRegen = GetUnitHealthRegenRateFromSpirit("player")
        local manaRegen = GetUnitManaRegenRateFromSpirit("player")
        yOffset = self:AddStatLine(content, "Health Regen", string.format("%.1f", healthRegen), yOffset)
        yOffset = self:AddStatLine(content, "Mana Regen", string.format("%.1f", manaRegen), yOffset)
        yOffset = yOffset - 10

        -- Combat Stats (player only)
        yOffset = self:AddSection(content, "COMBAT", yOffset)
        yOffset = yOffset + sectionSpacing

        yOffset = self:AddStatLine(content, "Armor", stats.armor or 0, yOffset)
        yOffset = self:AddStatLine(content, "Attack Power", stats.attackPower or 0, yOffset)
        yOffset = self:AddStatLine(content, "Ranged Attack Power", stats.rangedAttackPower or 0, yOffset)

        local mainSpeed, offSpeed = UnitAttackSpeed("player")
        local mainDamage = UnitDamage("player")
        yOffset = self:AddStatLine(content, "Main Hand Speed", string.format("%.2f", mainSpeed), yOffset)
        if offSpeed then
            yOffset = self:AddStatLine(content, "Off Hand Speed", string.format("%.2f", offSpeed), yOffset)
        end
        yOffset = self:AddStatLine(content, "Melee Damage", string.format("%.0f", mainDamage), yOffset)
        yOffset = yOffset - 10

        -- Detailed Combat Ratings (player only)
        if self.settings.showDetailedStats then
            yOffset = self:AddSection(content, "RATINGS", yOffset)
            yOffset = yOffset + sectionSpacing

            local critPct = GetCritChance() or 0
            local critRt = GetCombatRating(CR_CRIT_MELEE) or 0
            yOffset = self:AddStatLine(content, "Melee Crit", string.format("%.2f%%", critPct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Crit Rating", critRt, yOffset)

            local hitRt = GetCombatRating(CR_HIT_MELEE) or 0
            local hitPct = GetCombatRatingBonus(CR_HIT_MELEE) or 0
            yOffset = self:AddStatLine(content, "Melee Hit", string.format("%.2f%%", hitPct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Hit Rating", hitRt, yOffset)

            local hasteRt = GetCombatRating(CR_HASTE_MELEE) or 0
            local hastePct = GetCombatRatingBonus(CR_HASTE_MELEE) or 0
            yOffset = self:AddStatLine(content, "Melee Haste", string.format("%.2f%%", hastePct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Haste Rating", hasteRt, yOffset)
            yOffset = yOffset - 10
        end
    else
        -- Inspected player - show estimated/available stats
        yOffset = self:AddSection(content, "ESTIMATED STATS", yOffset)
        yOffset = yOffset + sectionSpacing

        if stats.health and stats.health > 0 then
            yOffset = self:AddStatLine(content, "Health", stats.health, yOffset)
        end
        if stats.mana and stats.mana > 0 then
            yOffset = self:AddStatLine(content, "Mana", stats.mana, yOffset)
        end

        if stats.estimatedStamina then
            yOffset = self:AddStatLine(content, "Est. Stamina (from gear)", stats.estimatedStamina, yOffset)
        end
        if stats.estimatedIntellect then
            yOffset = self:AddStatLine(content, "Est. Intellect (from gear)", stats.estimatedIntellect, yOffset)
        end
        if stats.estimatedArmor then
            yOffset = self:AddStatLine(content, "Est. Armor (from gear)", stats.estimatedArmor, yOffset)
        end

        yOffset = yOffset - 10

        -- Add note about limitations
        local noteLabel = FizzureUI:CreateLabel(content, "Note: Inspected stats are estimated", "GameFontNormalSmall")
        noteLabel:SetPoint("TOPLEFT", 10, yOffset)
        noteLabel:SetTextColor(0.7, 0.7, 0.7)
        yOffset = yOffset - 20
    end

    -- Update scroll height
    local totalHeight = math.abs(yOffset) + 40
    self.statsContent:SetHeight(math.max(totalHeight, 400))
end

function CharacterStatsModule:AddSection(parent, title, yOffset)
    local section = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section:SetPoint("TOPLEFT", 10, yOffset)
    section:SetText(title)
    section:SetTextColor(0.2, 0.6, 1, 1) -- Flat design accent color
    return yOffset - 20
end

function CharacterStatsModule:AddStatLine(parent, label, value, yOffset, highlight)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(250, 16)
    line:SetPoint("TOPLEFT", 10, yOffset)

    local labelText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetText(label .. ":")
    labelText:SetTextColor(0.9, 0.9, 0.9)

    local valueText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("RIGHT", 0, 0)
    valueText:SetText(tostring(value))

    if highlight then
        valueText:SetTextColor(0.2, 0.8, 0.2) -- Green for highlighted values
    else
        valueText:SetTextColor(1, 1, 1)
    end

    return yOffset - 18
end

function CharacterStatsModule:GetGearScore(unit)
    -- Try to get gear score from GearScore module if available
    if self.Fizzure and self.Fizzure.modules["Gear Score Calculator"] then
        local gsModule = self.Fizzure.modules["Gear Score Calculator"]

        if unit == "player" or UnitIsUnit(unit, "player") then
            return gsModule.playerGearScore or 0
        else
            local guid = UnitGUID(unit)
            if guid and gsModule.gearScoreCache[guid] then
                return gsModule.gearScoreCache[guid].score or 0
            end
        end
    end

    -- Calculate basic gear score if module not available
    return self:CalculateBasicGearScore(unit)
end

function CharacterStatsModule:CalculateBasicGearScore(unit)
    local totalScore = 0
    local slots = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "ChestSlot", "WaistSlot",
        "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot",
        "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot",
        "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
    }

    for _, slot in ipairs(slots) do
        local slotId = GetInventorySlotInfo(slot)
        local itemLink = GetInventoryItemLink(unit, slotId)
        if itemLink then
            local _, _, quality, itemLevel = GetItemInfo(itemLink)
            if quality and itemLevel then
                totalScore = totalScore + (itemLevel * (quality + 1))
            end
        end
    end

    return math.floor(totalScore / 10)
end

function CharacterStatsModule:GetAverageItemLevel(unit)
    local totalLevel = 0
    local itemCount = 0
    local slots = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "ChestSlot", "WaistSlot",
        "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot",
        "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot",
        "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
    }

    for _, slot in ipairs(slots) do
        local slotId = GetInventorySlotInfo(slot)
        local itemLink = GetInventoryItemLink(unit, slotId)
        if itemLink then
            local _, _, _, itemLevel = GetItemInfo(itemLink)
            if itemLevel then
                totalLevel = totalLevel + itemLevel
                itemCount = itemCount + 1
            end
        end
    end

    return itemCount > 0 and math.floor(totalLevel / itemCount) or 0
end

function CharacterStatsModule:FormatGearScore(score)
    if score >= 6000 then
        return string.format("|cffffff00%d|r", score) -- Gold
    elseif score >= 5000 then
        return string.format("|cffff8000%d|r", score) -- Orange
    elseif score >= 4000 then
        return string.format("|cffa335ee%d|r", score) -- Purple
    elseif score >= 3000 then
        return string.format("|cff0070dd%d|r", score) -- Blue
    elseif score >= 2000 then
        return string.format("|cff1eff00%d|r", score) -- Green
    elseif score >= 1000 then
        return string.format("|cffffffff%d|r", score) -- White
    else
        return string.format("|cff9d9d9d%d|r", score) -- Gray
    end
end

function CharacterStatsModule:TogglePanel()
    if self.statsPanel:IsShown() then
        self.statsPanel:Hide()
    else
        self.statsPanel:Show()
        self:UpdateStatsDisplay()
    end
end

function CharacterStatsModule:CreateConfigUI(parent, x, y)
    local showPanelCheck = FizzureUI:CreateCheckBox(parent, "Show stats panel",
            self.settings.showPanel, function(checked)
                self.settings.showPanel = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                if checked then
                    if CharacterFrame:IsShown() and self.settings.attachToCharacterFrame then
                        self.statsPanel:Show()
                        self:UpdateStatsDisplay()
                    end
                else
                    self.statsPanel:Hide()
                end
            end, true)
    showPanelCheck:SetPoint("TOPLEFT", x, y)

    local attachCheck = FizzureUI:CreateCheckBox(parent, "Attach to character frame",
            self.settings.attachToCharacterFrame, function(checked)
                self.settings.attachToCharacterFrame = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)

                self:PositionPanel()

                if checked then
                    self:HookCharacterFrame()
                else
                    self:UnhookCharacterFrame()
                end
            end, true)
    attachCheck:SetPoint("TOPLEFT", x, y - 25)

    local showOtherCheck = FizzureUI:CreateCheckBox(parent, "Show other players' stats",
            self.settings.showOtherPlayers, function(checked)
                self.settings.showOtherPlayers = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    showOtherCheck:SetPoint("TOPLEFT", x, y - 50)

    local inspectTargetCheck = FizzureUI:CreateCheckBox(parent, "Auto-inspect target",
            self.settings.inspectOnTarget, function(checked)
                self.settings.inspectOnTarget = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
            end, true)
    inspectTargetCheck:SetPoint("TOPLEFT", x, y - 75)

    local showGearScoreCheck = FizzureUI:CreateCheckBox(parent, "Show gear score",
            self.settings.showGearScore, function(checked)
                self.settings.showGearScore = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateStatsDisplay()
            end, true)
    showGearScoreCheck:SetPoint("TOPLEFT", x, y - 100)

    local showDetailedCheck = FizzureUI:CreateCheckBox(parent, "Show detailed combat stats",
            self.settings.showDetailedStats, function(checked)
                self.settings.showDetailedStats = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateStatsDisplay()
            end, true)
    showDetailedCheck:SetPoint("TOPLEFT", x, y - 125)

    local toggleBtn = FizzureUI:CreateButton(parent, "Toggle Panel", 100, 24, function()
        self:TogglePanel()
    end, true)
    toggleBtn:SetPoint("TOPLEFT", x, y - 155)

    return y - 185
end

function CharacterStatsModule:GetQuickStatus()
    local unit = self.currentInspectTarget
    local stats = self:GetUnitStats(unit)
    local gearScore = self:GetGearScore(unit)
    local avgItemLevel = self:GetAverageItemLevel(unit)

    if unit == "player" then
        return string.format("GS: %d, Avg iLvl: %d", gearScore, avgItemLevel)
    else
        local name = stats.name or "Unknown"
        return string.format("%s - GS: %d, iLvl: %d", name, gearScore, avgItemLevel)
    end
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Character Stats Panel", CharacterStatsModule, "UI/UX")
end