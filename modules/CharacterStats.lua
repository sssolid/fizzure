-- CharacterStats.lua - Enhanced Character Statistics Panel for Fizzure
local CharacterStatsModule = {}

CharacterStatsModule.name = "Character Stats Panel"
CharacterStatsModule.version = "1.0"
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

    -- Create the stats panel
    self:CreateStatsPanel()

    -- Register events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("UNIT_STATS")
    self.eventFrame:RegisterEvent("UNIT_RESISTANCES")
    self.eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")

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
        self:UpdateStatsDisplay()
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
    self.statsPanel:SetSize(300, 500)
    self.statsPanel:SetFrameStrata("MEDIUM")
    self.statsPanel:SetFrameLevel(100)

    -- Background
    self.statsPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    self.statsPanel:SetBackdropColor(0, 0, 0, 0.8)

    -- Title
    local title = self.statsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Character Statistics")

    -- Create scroll frame for stats
    self.statsScroll = CreateFrame("ScrollFrame", "CharStatsScroll", self.statsPanel, "UIPanelScrollFrameTemplate")
    self.statsScroll:SetPoint("TOPLEFT", 15, -40)
    self.statsScroll:SetPoint("BOTTOMRIGHT", -30, 15)

    local statsContent = CreateFrame("Frame", "CharStatsContent", self.statsScroll)
    statsContent:SetSize(250, 1)
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

-- Helpers (3.3.5)
local function RatingAndBonus(id)
    local rt   = GetCombatRating(id) or 0
    local perc = GetCombatRatingBonus(id) or 0
    return rt, perc
end

local function HasRangedWeapon()
    -- Works for bows/guns/xbows/throwing; wands counted via HasWandEquipped()
    return IsEquippedItemType("Bows") or IsEquippedItemType("Guns") or IsEquippedItemType("Crossbows")
            or IsEquippedItemType("Thrown") or (HasWandEquipped and HasWandEquipped())
end

local function AddHeader(self, content, title, y)
    y = self:AddSection(content, title, y)
    return y + (sectionSpacing or 0)
end

-- Spell school indices in Wrath: 2=Holy,3=Fire,4=Nature,5=Frost,6=Shadow,7=Arcane
local SPELL_SCHOOLS = {2,3,4,5,6,7}
local function BestSpellCrit()
    local best = 0
    for _, school in ipairs(SPELL_SCHOOLS) do
        local c = GetSpellCritChance(school) or 0
        if c > best then best = c end
    end
    return best
end

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

    local yOffset = -10
    local sectionSpacing = -5

    -- Gear Score Section (if GearScore module is available)
    if self.settings.showGearScore then
        yOffset = self:AddSection(content, "GEAR SCORE", yOffset)
        yOffset = yOffset + sectionSpacing

        local gearScore = self:GetGearScore()
        yOffset = self:AddStatLine(content, "Gear Score", gearScore, yOffset, true)

        local avgItemLevel = self:GetAverageItemLevel()
        yOffset = self:AddStatLine(content, "Avg Item Level", avgItemLevel, yOffset)

        yOffset = yOffset - 10
    end

    -- Basic Attributes
    yOffset = self:AddSection(content, "ATTRIBUTES", yOffset)
    yOffset = yOffset + sectionSpacing

    local str = UnitStat("player", 1)
    local agi = UnitStat("player", 2)
    local sta = UnitStat("player", 3)
    local int = UnitStat("player", 4)
    local spi = UnitStat("player", 5)

    yOffset = self:AddStatLine(content, "Strength", str, yOffset)
    yOffset = self:AddStatLine(content, "Agility", agi, yOffset)
    yOffset = self:AddStatLine(content, "Stamina", sta, yOffset)
    yOffset = self:AddStatLine(content, "Intellect", int, yOffset)
    yOffset = self:AddStatLine(content, "Spirit", spi, yOffset)
    yOffset = yOffset - 10

    -- Health and Mana
    yOffset = self:AddSection(content, "VITALS", yOffset)
    yOffset = yOffset + sectionSpacing

    local health = UnitHealthMax("player")
    local mana = UnitPowerMax("player")
    local healthRegen = GetUnitHealthRegenRateFromSpirit("player")
    local manaRegen = GetUnitManaRegenRateFromSpirit("player")

    yOffset = self:AddStatLine(content, "Health", health, yOffset)
    yOffset = self:AddStatLine(content, "Mana", mana, yOffset)
    yOffset = self:AddStatLine(content, "Health Regen", string.format("%.1f", healthRegen), yOffset)
    yOffset = self:AddStatLine(content, "Mana Regen", string.format("%.1f", manaRegen), yOffset)
    yOffset = yOffset - 10

    -- Combat Stats
    yOffset = self:AddSection(content, "COMBAT", yOffset)
    yOffset = yOffset + sectionSpacing

    local armor = UnitArmor("player")
    local attackPower = UnitAttackPower("player")
    local rangedAttackPower = UnitRangedAttackPower("player")

    -- Melee stats
    local mainSpeed, offSpeed = UnitAttackSpeed("player")
    local mainDamage = UnitDamage("player")
    local rangedSpeed = UnitRangedDamage("player")

    yOffset = self:AddStatLine(content, "Armor", armor, yOffset)
    yOffset = self:AddStatLine(content, "Attack Power", attackPower, yOffset)
    yOffset = self:AddStatLine(content, "Ranged Attack Power", rangedAttackPower, yOffset)
    yOffset = self:AddStatLine(content, "Main Hand Speed", string.format("%.2f", mainSpeed), yOffset)
    if offSpeed then
        yOffset = self:AddStatLine(content, "Off Hand Speed", string.format("%.2f", offSpeed), yOffset)
    end
    yOffset = self:AddStatLine(content, "Melee Damage", string.format("%.0f", mainDamage), yOffset)
    yOffset = yOffset - 10

    -- Detailed Combat Ratings
    if self.settings.showDetailedStats then
        yOffset = AddHeader(self, content, "RATINGS", yOffset)

        -- MELEE
        do
            local critPct  = GetCritChance() or 0                      -- melee crit %
            local critRt   = GetCombatRating(CR_CRIT_MELEE) or 0
            local hitRt,  hitPct   = RatingAndBonus(CR_HIT_MELEE)      -- rating / %
            local hasteRt, hastePct= RatingAndBonus(CR_HASTE_MELEE)
            local expMain, expOff  = GetExpertise()                    -- expertise (points)
            local expRt            = GetCombatRating(CR_EXPERTISE) or 0
            local expMainPct       = (GetExpertisePercent and select(1, GetExpertisePercent())) or 0

            yOffset = self:AddStatLine(content, "Melee Crit",  string.format("%.2f%%", critPct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Crit Rating", critRt, yOffset)

            yOffset = self:AddStatLine(content, "Melee Hit",   string.format("%.2f%%", hitPct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Hit Rating", hitRt, yOffset)

            yOffset = self:AddStatLine(content, "Melee Haste", string.format("%.2f%%", hastePct), yOffset)
            yOffset = self:AddStatLine(content, "Melee Haste Rating", hasteRt, yOffset)

            if (expRt > 0) or (expMain and expMain > 0) then
                yOffset = self:AddStatLine(content, "Expertise", string.format("%d (%.2f%%)", expMain or 0, expMainPct or 0), yOffset)
                yOffset = self:AddStatLine(content, "Expertise Rating", expRt, yOffset)
            end

            -- Armor Pen applies to physical; show only if present
            local arpRt = GetCombatRating(CR_ARMOR_PENETRATION) or 0
            if arpRt > 0 then
                local arpPct = (GetArmorPenetration and GetArmorPenetration()) or 0
                yOffset = self:AddStatLine(content, "Armor Pen", string.format("%.2f%%", arpPct), yOffset)
                yOffset = self:AddStatLine(content, "Armor Pen Rating", arpRt, yOffset)
            end
        end

        -- RANGED (show only if the player actually has a ranged weapon equipped)
        if HasRangedWeapon() then
            local rCritPct  = (GetRangedCritChance and GetRangedCritChance()) or 0
            local rCritRt   = GetCombatRating(CR_CRIT_RANGED) or 0
            local rHitRt,  rHitPct   = RatingAndBonus(CR_HIT_RANGED)
            local rHasteRt, rHastePct= RatingAndBonus(CR_HASTE_RANGED)

            yOffset = AddHeader(self, content, "RANGED", yOffset)
            yOffset = self:AddStatLine(content, "Ranged Crit",  string.format("%.2f%%", rCritPct), yOffset)
            yOffset = self:AddStatLine(content, "Ranged Crit Rating", rCritRt, yOffset)

            yOffset = self:AddStatLine(content, "Ranged Hit",   string.format("%.2f%%", rHitPct), yOffset)
            yOffset = self:AddStatLine(content, "Ranged Hit Rating", rHitRt, yOffset)

            yOffset = self:AddStatLine(content, "Ranged Haste", string.format("%.2f%%", rHastePct), yOffset)
            yOffset = self:AddStatLine(content, "Ranged Haste Rating", rHasteRt, yOffset)
        end

        -- SPELL (always available; show generic “best school” crit)
        do
            local sCritBest = BestSpellCrit()                              -- %
            local sHitRt,  sHitPct   = RatingAndBonus(CR_HIT_SPELL)
            local sHasteRt, sHastePct= RatingAndBonus(CR_HASTE_SPELL)

            yOffset = AddHeader(self, content, "SPELL", yOffset)
            yOffset = self:AddStatLine(content, "Spell Crit (best school)", string.format("%.2f%%", sCritBest), yOffset)
            yOffset = self:AddStatLine(content, "Spell Hit",   string.format("%.2f%%", sHitPct), yOffset)
            yOffset = self:AddStatLine(content, "Spell Hit Rating", sHitRt, yOffset)
            yOffset = self:AddStatLine(content, "Spell Haste", string.format("%.2f%%", sHastePct), yOffset)
            yOffset = self:AddStatLine(content, "Spell Haste Rating", sHasteRt, yOffset)
        end

        yOffset = yOffset - 10
    end

    -- Defense Stats
    yOffset = self:AddSection(content, "DEFENSE", yOffset)
    yOffset = yOffset + sectionSpacing

    local defense = GetCombatRating(CR_DEFENSE_SKILL) + UnitLevel("player") * 5
    local dodgeChance = GetDodgeChance()
    local parryChance = GetParryChance()
    local blockChance = GetBlockChance()

    yOffset = self:AddStatLine(content, "Defense", defense, yOffset)
    yOffset = self:AddStatLine(content, "Dodge", string.format("%.2f%%", dodgeChance), yOffset)
    yOffset = self:AddStatLine(content, "Parry", string.format("%.2f%%", parryChance), yOffset)
    yOffset = self:AddStatLine(content, "Block", string.format("%.2f%%", blockChance), yOffset)
    yOffset = yOffset - 10

    -- Spell Stats (for casters)
    local spellPower = GetSpellBonusDamage(2) -- Fire spell power as baseline
    if spellPower > 0 then
        yOffset = self:AddSection(content, "SPELL POWER", yOffset)
        yOffset = yOffset + sectionSpacing

        yOffset = self:AddStatLine(content, "Spell Power", spellPower, yOffset)

        local spellCrit = GetSpellCritChance(2)
        yOffset = self:AddStatLine(content, "Spell Crit", string.format("%.2f%%", spellCrit), yOffset)

        local spellHaste = GetCombatRating(CR_HASTE_SPELL)
        if spellHaste > 0 then
            yOffset = self:AddStatLine(content, "Spell Haste Rating", spellHaste, yOffset)
        end

        yOffset = yOffset - 10
    end

    -- Resistances
    if self.settings.showResistances then
        yOffset = self:AddSection(content, "RESISTANCES", yOffset)
        yOffset = yOffset + sectionSpacing

        local resistances = {
            {name = "Fire", index = 2},
            {name = "Nature", index = 3},
            {name = "Frost", index = 4},
            {name = "Shadow", index = 5},
            {name = "Arcane", index = 6}
        }

        for _, resist in ipairs(resistances) do
            local value = UnitResistance("player", resist.index)
            if value > 0 then
                yOffset = self:AddStatLine(content, resist.name .. " Resist", value, yOffset)
            end
        end
    end

    -- Update scroll height
    local totalHeight = math.abs(yOffset) + 20
    self.statsContent:SetHeight(math.max(totalHeight, 400))
end

function CharacterStatsModule:AddSection(parent, title, yOffset)
    local section = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section:SetPoint("TOPLEFT", 10, yOffset)
    section:SetText(title)
    section:SetTextColor(1, 0.82, 0) -- Gold color
    return yOffset - 20
end

function CharacterStatsModule:AddStatLine(parent, label, value, yOffset, highlight)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(240, 16)
    line:SetPoint("TOPLEFT", 10, yOffset)

    local labelText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetText(label .. ":")
    labelText:SetTextColor(0.9, 0.9, 0.9)

    local valueText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("RIGHT", 0, 0)
    valueText:SetText(tostring(value))

    if highlight then
        valueText:SetTextColor(0, 1, 0) -- Green for highlighted values
    else
        valueText:SetTextColor(1, 1, 1)
    end

    return yOffset - 18
end

function CharacterStatsModule:GetGearScore()
    -- Try to get gear score from GearScore module if available
    if self.Fizzure and self.Fizzure.modules["Gear Score Calculator"] then
        local gsModule = self.Fizzure.modules["Gear Score Calculator"]
        if gsModule.playerGearScore then
            return gsModule.playerGearScore
        end
    end

    -- Calculate basic gear score if module not available
    return self:CalculateBasicGearScore()
end

function CharacterStatsModule:CalculateBasicGearScore()
    local totalScore = 0
    local slots = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "ChestSlot", "WaistSlot",
        "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot",
        "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot",
        "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
    }

    for _, slot in ipairs(slots) do
        local slotId = GetInventorySlotInfo(slot)
        local itemLink = GetInventoryItemLink("player", slotId)
        if itemLink then
            local _, _, quality, itemLevel = GetItemInfo(itemLink)
            if quality and itemLevel then
                totalScore = totalScore + (itemLevel * (quality + 1))
            end
        end
    end

    return math.floor(totalScore / 10)
end

function CharacterStatsModule:GetAverageItemLevel()
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
        local itemLink = GetInventoryItemLink("player", slotId)
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
            end)
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
            end)
    attachCheck:SetPoint("TOPLEFT", x, y - 25)

    local showGearScoreCheck = FizzureUI:CreateCheckBox(parent, "Show gear score",
            self.settings.showGearScore, function(checked)
                self.settings.showGearScore = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateStatsDisplay()
            end)
    showGearScoreCheck:SetPoint("TOPLEFT", x, y - 50)

    local showDetailedCheck = FizzureUI:CreateCheckBox(parent, "Show detailed combat stats",
            self.settings.showDetailedStats, function(checked)
                self.settings.showDetailedStats = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateStatsDisplay()
            end)
    showDetailedCheck:SetPoint("TOPLEFT", x, y - 75)

    local showResistCheck = FizzureUI:CreateCheckBox(parent, "Show resistances",
            self.settings.showResistances, function(checked)
                self.settings.showResistances = checked
                self.Fizzure:SetModuleSettings(self.name, self.settings)
                self:UpdateStatsDisplay()
            end)
    showResistCheck:SetPoint("TOPLEFT", x, y - 100)

    local toggleBtn = FizzureUI:CreateButton(parent, "Toggle Panel", 100, 24, function()
        self:TogglePanel()
    end)
    toggleBtn:SetPoint("TOPLEFT", x, y - 130)

    return y - 160
end

function CharacterStatsModule:GetQuickStatus()
    local gearScore = self:GetGearScore()
    local avgItemLevel = self:GetAverageItemLevel()
    return string.format("GS: %d, Avg iLvl: %d", gearScore, avgItemLevel)
end

-- Register module
if Fizzure then
    Fizzure:RegisterModule("Character Stats Panel", CharacterStatsModule, "UI/UX")
end