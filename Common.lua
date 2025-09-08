-- Common.lua - Core utility functions for Fizzure framework
-- Single shared instance
_G.Common = _G.Common or {}
local Common = _G.Common

local Common = {}
_G.FizzureCommon = Common

-- Initialization (set up a C_Timer.After shim that delegates to Common:After)
function Common:Initialize()
    self.initialized = true
end

-- One-shot timer (Wrath-safe)
function Common:After(delay, func)
    delay = tonumber(delay)
    if not delay or delay < 0 then return end
    if type(func) ~= "function" then return end

    local f = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            pcall(func)
        end
    end)
    f:Show()
    return f
end

-- Retail-style shim (only if missing)
_G.C_Timer = _G.C_Timer or {}
if type(_G.C_Timer.After) ~= "function" then
    _G.C_Timer.After = function(d, fn) return Common:After(d, fn) end
end

function Common:NewTicker(interval, func, iterations)
    local f = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    local count = 0

    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= interval then
            elapsed = 0
            count = count + 1

            local ok = pcall(func, count)
            if not ok or (iterations and count >= iterations) then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end)

    f.Cancel = function(self)
        self:SetScript("OnUpdate", nil)
        self:Hide()
    end

    return f
end

-- Player Status Functions
function Common:IsInCombat()
    return UnitAffectingCombat("player") or InCombatLockdown()
end

function Common:IsResting()
    return IsResting()
end

function Common:IsDead()
    return UnitIsDeadOrGhost("player")
end

function Common:IsSwimming()
    return IsSwimming()
end

function Common:IsMounted()
    return IsMounted()
end

function Common:IsFlying()
    return IsFlying and IsFlying() or false
end

function Common:IsIndoors()
    return IsIndoors()
end

function Common:IsStealthed()
    return IsStealthed()
end

function Common:GetPlayerHealth()
    local current = UnitHealth("player")
    local max = UnitHealthMax("player")
    return current, max, (current / max) * 100
end

function Common:GetPlayerPower()
    local powerType = UnitPowerType("player")
    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    return current, max, (max > 0 and (current / max) * 100 or 0), powerType
end

-- Range and Distance Functions
function Common:IsInRange(unit, spell)
    if spell then
        return IsSpellInRange(spell, unit) == 1
    else
        return CheckInteractDistance(unit, 4) -- 28 yards
    end
end

function Common:GetUnitDistance(unit)
    -- 3.3.5 doesn't have exact distance, use interact distance checks
    if CheckInteractDistance(unit, 1) then return 5    -- Inspect
    elseif CheckInteractDistance(unit, 2) then return 10  -- Trade
    elseif CheckInteractDistance(unit, 3) then return 10  -- Duel
    elseif CheckInteractDistance(unit, 4) then return 28  -- Follow
    else return 100 end -- Out of range
end

-- Currency Functions
function Common:GetMoney()
    return GetMoney()
end

function Common:FormatMoney(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper - gold * 10000) / 100)
    local copper = copper % 100

    if gold > 0 then
        return string.format("%dg %ds %dc", gold, silver, copper)
    elseif silver > 0 then
        return string.format("%ds %dc", silver, copper)
    else
        return string.format("%dc", copper)
    end
end

function Common:GetMoneyString(copper)
    local gold = floor(copper / 10000)
    local silver = floor((copper - gold * 10000) / 100)
    local copper = copper % 100

    local str = ""
    if gold > 0 then
        str = str .. "|cffffcc00" .. gold .. "g|r "
    end
    if silver > 0 or gold > 0 then
        str = str .. "|cffc0c0c0" .. silver .. "s|r "
    end
    str = str .. "|cffcc9900" .. copper .. "c|r"

    return str:gsub("%s+$", "")
end

-- Experience Functions
function Common:GetExperience()
    local current = UnitXP("player")
    local max = UnitXPMax("player")
    local rested = GetXPExhaustion() or 0
    return current, max, rested, (current / max) * 100
end

function Common:GetLevel()
    return UnitLevel("player")
end

function Common:IsMaxLevel()
    return UnitLevel("player") >= 80 -- WotLK max level
end

-- Skill Functions
function Common:GetSkillInfo(skillName)
    for i = 1, GetNumSkillLines() do
        local name, _, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if name == skillName then
            return skillRank, skillMaxRank
        end
    end
    return 0, 0
end

function Common:HasSpell(spellName)
    return GetSpellInfo(spellName) ~= nil
end

function Common:IsSpellKnown(spellId)
    return IsSpellKnown(spellId)
end

function Common:GetSpellCooldown(spell)
    local start, duration, enabled = GetSpellCooldown(spell)
    if enabled == 1 and start > 0 and duration > 0 then
        local remaining = start + duration - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Item Functions
function FindItemInBags(itemName)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name = GetItemInfo(link)
                    if name == itemName then
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil
end

function Common:GetItemCount(item, includeBank)
    return GetItemCount(item, includeBank)
end

function Common:GetItemInfo(item)
    return GetItemInfo(item)
end

function Common:GetItemLink(bag, slot)
    return GetContainerItemLink(bag, slot)
end

function Common:GetItemQuality(item)
    local _, _, quality = GetItemInfo(item)
    return quality
end

function Common:GetItemSellPrice(item)
    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(item)
    return vendorPrice or 0
end

-- Bag Functions
function Common:GetFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local freeSlots, bagType = GetContainerNumFreeSlots(bag)
        if bagType == 0 then -- Normal bag
            free = free + freeSlots
        end
    end
    return free
end

function Common:GetTotalBagSlots()
    local total = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots then total = total + slots end
    end
    return total
end

function Common:IsBagFull()
    return self:GetFreeBagSlots() == 0
end

-- Unit Functions
function Common:UnitFullName(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

function Common:GetUnitSpeed(unit)
    unit = unit or "player"
    local speed = GetUnitSpeed(unit)
    return speed, (speed / 7) * 100 -- Convert to percentage
end

function Common:IsUnitPlayer(unit)
    return UnitIsPlayer(unit)
end

-- Zone Functions
function Common:GetZoneInfo()
    local zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    local pvpType = GetZonePVPInfo()
    local isInstance, instanceType = IsInInstance()

    return {
        zone = zone,
        subzone = subzone,
        pvpType = pvpType,
        isInstance = isInstance,
        instanceType = instanceType
    }
end

function Common:GetMapInfo()
    -- Make sure map coords are valid for the player's current zone
    SetMapToCurrentZone()

    local id = GetCurrentMapAreaID()
    local name = (GetMapInfo())  -- 1st return is the zone name
    local x, y = GetPlayerMapPosition("player")

    return {
        id   = id,
        name = name,
        x    = (x or 0) * 100,
        y    = (y or 0) * 100,
    }
end

-- Group Functions
function Common:IsInGroup()
    return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
end

function Common:IsInRaid()
    return GetNumRaidMembers() > 0
end

function Common:GetGroupSize()
    if IsInRaid() then
        return GetNumRaidMembers()
    elseif GetNumPartyMembers() > 0 then
        return GetNumPartyMembers() + 1
    else
        return 1
    end
end

-- Time Functions
function Common:GetServerTime()
    return GetTime()
end

function Common:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
    end
end

function Common:GetSessionTime()
    -- Track from addon load
    if not self.sessionStart then
        self.sessionStart = GetTime()
    end
    return GetTime() - self.sessionStart
end

-- String Functions
function Common:Trim(str)
    return str:match("^%s*(.-)%s*$")
end

function Common:Split(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)

    while delim_from do
        table.insert(result, string.sub(str, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end

    table.insert(result, string.sub(str, from))
    return result
end

function Common:ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- Table Functions
function Common:TableCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[self:TableCopy(k)] = self:TableCopy(v)
        end
        setmetatable(copy, self:TableCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function Common:TableMerge(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            self:TableMerge(t1[k], v)
        else
            t1[k] = v
        end
    end
    return t1
end

function Common:TableContains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

-- Math Functions
function Common:Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return floor(num * mult + 0.5) / mult
end

function Common:Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Event tracking
function Common:RegisterBucketEvent(event, interval, callback)
    local bucket = CreateFrame("Frame")
    local events = {}
    local elapsed = 0

    bucket:RegisterEvent(event)
    bucket:SetScript("OnEvent", function(self, event, ...)
        table.insert(events, {...})
    end)

    bucket:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= interval then
            if #events > 0 then
                callback(events)
                events = {}
            end
            elapsed = 0
        end
    end)

    return bucket
end

-- Initialize
Common:Initialize()

print("|cff00ff00Fizzure|r Common utilities loaded")