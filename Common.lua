-- Common.lua - Enhanced utility functions for Fizzure framework
local Common = {}
_G.FizzureCommon = Common

-- Initialize flag
Common.initialized = false

function Common:Initialize()
    if self.initialized then return end
    
    -- Create compatibility shims for 3.3.5
    self:CreateCompatibilityShims()
    
    -- Initialize internal tracking
    self.sessionStart = GetTime()
    self.moduleUtilities = {}
    
    self.initialized = true
    self:Log("INFO", "Common utilities initialized")
end

-- Compatibility shims for 3.3.5
function Common:CreateCompatibilityShims()
    -- C_Timer compatibility
    if not _G.C_Timer then _G.C_Timer = {} end
    if not _G.C_Timer.After then
        _G.C_Timer.After = function(delay, func)
            return self:After(delay, func)
        end
    end
    if not _G.C_Timer.NewTicker then
        _G.C_Timer.NewTicker = function(interval, func, iterations)
            return self:NewTicker(interval, func, iterations)
        end
    end
    
    -- UnitPowerMax compatibility
    if not UnitPowerMax then
        UnitPowerMax = function(unit, powerType)
            return UnitManaMax(unit)
        end
    end
    
    -- UnitPower compatibility
    if not UnitPower then
        UnitPower = function(unit, powerType)
            return UnitMana(unit)
        end
    end
end

-- Enhanced Timer Functions
function Common:After(delay, func)
    if type(delay) ~= "number" or delay < 0 then
        self:Log("WARN", "Invalid delay for After timer: " .. tostring(delay))
        return
    end
    if type(func) ~= "function" then
        self:Log("WARN", "Invalid function for After timer")
        return
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            local success, err = pcall(func)
            if not success then
                Common:Log("ERROR", "Timer callback error: " .. tostring(err))
            end
            self:Hide()
        end
    end)
    
    -- Return cancellation function
    return {
        Cancel = function()
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
        end
    }
end

function Common:NewTicker(interval, func, iterations)
    if type(interval) ~= "number" or interval <= 0 then
        self:Log("WARN", "Invalid interval for NewTicker: " .. tostring(interval))
        return
    end
    if type(func) ~= "function" then
        self:Log("WARN", "Invalid function for NewTicker")
        return
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    local count = 0
    local cancelled = false

    frame:SetScript("OnUpdate", function(self, dt)
        if cancelled then return end
        
        elapsed = elapsed + dt
        if elapsed >= interval then
            elapsed = 0
            count = count + 1

            local success, err = pcall(func, count)
            if not success then
                Common:Log("ERROR", "Ticker callback error: " .. tostring(err))
                cancelled = true
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end
            
            if iterations and count >= iterations then
                cancelled = true
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end)

    return {
        Cancel = function()
            cancelled = true
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
        end,
        
        IsCancelled = function()
            return cancelled
        end
    }
end

-- Delayed execution with retry capability
function Common:DelayedCall(delay, func, maxRetries, retryDelay)
    maxRetries = maxRetries or 0
    retryDelay = retryDelay or 1
    
    local attempts = 0
    
    local function tryCall()
        attempts = attempts + 1
        local success, err = pcall(func)
        
        if not success then
            self:Log("WARN", "DelayedCall attempt " .. attempts .. " failed: " .. tostring(err))
            
            if attempts <= maxRetries then
                self:After(retryDelay, tryCall)
            else
                self:Log("ERROR", "DelayedCall failed after " .. attempts .. " attempts")
            end
        end
    end
    
    return self:After(delay, tryCall)
end

-- Enhanced Player Status Functions
function Common:GetPlayerStatus()
    return {
        inCombat = UnitAffectingCombat("player") or InCombatLockdown(),
        isResting = IsResting(),
        isDead = UnitIsDeadOrGhost("player"),
        isSwimming = IsSwimming(),
        isMounted = IsMounted(),
        isFlying = IsFlying and IsFlying() or false,
        isIndoors = IsIndoors(),
        isStealthed = IsStealthed(),
        level = UnitLevel("player"),
        class = select(2, UnitClass("player")),
        race = select(2, UnitRace("player"))
    }
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

-- Enhanced Item Functions
function Common:GetItemCount(item, includeBank)
    return GetItemCount(item, includeBank) or 0
end

function Common:GetItemInfo(item)
    if not item then return end
    
    local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, 
          equipSlot, texture, vendorPrice = GetItemInfo(item)
    
    return {
        name = name,
        link = link,
        quality = quality,
        itemLevel = iLevel,
        requiredLevel = reqLevel,
        class = class,
        subclass = subclass,
        maxStack = maxStack,
        equipSlot = equipSlot,
        texture = texture,
        vendorPrice = vendorPrice
    }
end

function Common:FindItemInBags(itemName)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local name = GetItemInfo(itemLink)
                if name == itemName then
                    local texture, count = GetContainerItemInfo(bag, slot)
                    return bag, slot, count, itemLink
                end
            end
        end
    end
    return nil
end

-- Enhanced Bag Functions
function Common:GetBagInfo()
    local totalSlots = 0
    local freeSlots = 0
    local usedSlots = 0
    
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        totalSlots = totalSlots + slots
        
        local free, bagType = GetContainerNumFreeSlots(bag)
        if bagType == 0 then -- Normal bag
            freeSlots = freeSlots + free
        end
    end
    
    usedSlots = totalSlots - freeSlots
    
    return {
        total = totalSlots,
        free = freeSlots,
        used = usedSlots,
        percentFull = totalSlots > 0 and (usedSlots / totalSlots) * 100 or 0
    }
end

function Common:ScanBags(filterFunc)
    local items = {}
    
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
                local itemName = GetItemInfo(itemLink)
                
                local itemData = {
                    bag = bag,
                    slot = slot,
                    name = itemName,
                    link = itemLink,
                    count = count,
                    quality = quality,
                    texture = texture,
                    locked = locked
                }
                
                if not filterFunc or filterFunc(itemData) then
                    table.insert(items, itemData)
                end
            end
        end
    end
    
    return items
end

-- Enhanced Unit Functions
function Common:GetUnitInfo(unit)
    if not UnitExists(unit) then return nil end
    
    return {
        name = UnitName(unit),
        level = UnitLevel(unit),
        class = UnitClass(unit),
        race = UnitRace(unit),
        health = UnitHealth(unit),
        healthMax = UnitHealthMax(unit),
        healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100,
        isDead = UnitIsDeadOrGhost(unit),
        isPlayer = UnitIsPlayer(unit),
        isConnected = UnitIsConnected(unit),
        reaction = UnitReaction(unit, "player")
    }
end

function Common:GetDistance(unit)
    -- 3.3.5 doesn't have exact distance, use interact distance checks
    if not UnitExists(unit) then return nil end
    
    if CheckInteractDistance(unit, 1) then return 5    -- Inspect
    elseif CheckInteractDistance(unit, 2) then return 10  -- Trade
    elseif CheckInteractDistance(unit, 3) then return 10  -- Duel
    elseif CheckInteractDistance(unit, 4) then return 28  -- Follow
    else return 100 end -- Out of range
end

-- Enhanced Currency Functions
function Common:GetMoney()
    return GetMoney()
end

function Common:FormatMoney(copper, colored)
    if not copper or copper == 0 then
        return colored and "|cffcc99000c|r" or "0c"
    end
    
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper - gold * 10000) / 100)
    copper = copper % 100

    local parts = {}
    
    if gold > 0 then
        table.insert(parts, colored and ("|cffffcc00" .. gold .. "g|r") or (gold .. "g"))
    end
    if silver > 0 or gold > 0 then
        table.insert(parts, colored and ("|cffc0c0c0" .. silver .. "s|r") or (silver .. "s"))
    end
    table.insert(parts, colored and ("|cffcc9900" .. copper .. "c|r") or (copper .. "c"))

    return table.concat(parts, " ")
end

-- Enhanced String Functions
function Common:Trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end

function Common:Split(str, delimiter)
    if not str then return {} end
    if not delimiter then delimiter = "%s" end
    
    local result = {}
    local pattern = "(.-)" .. delimiter
    local lastEnd = 1
    local s, e, cap = str:find(pattern, 1)
    
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(result, cap)
        end
        lastEnd = e + 1
        s, e, cap = str:find(pattern, lastEnd)
    end
    
    if lastEnd <= #str then
        cap = str:sub(lastEnd)
        table.insert(result, cap)
    end
    
    return result
end

function Common:StartsWith(str, prefix)
    return str and prefix and str:sub(1, #prefix) == prefix
end

function Common:EndsWith(str, suffix)
    return str and suffix and str:sub(-#suffix) == suffix
end

function Common:Contains(str, substring)
    return str and substring and str:find(substring, 1, true) ~= nil
end

function Common:Capitalize(str)
    if not str or str == "" then return str end
    return str:sub(1, 1):upper() .. str:sub(2):lower()
end

-- Enhanced Table Functions
function Common:TableCopy(orig, deep)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            if deep and type(v) == 'table' then
                copy[k] = self:TableCopy(v, true)
            else
                copy[k] = v
            end
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end

function Common:TableMerge(t1, t2)
    if not t1 then return self:TableCopy(t2) end
    if not t2 then return self:TableCopy(t1) end
    
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            self:TableMerge(t1[k], v)
        else
            t1[k] = v
        end
    end
    return t1
end

function Common:TableContains(tbl, element)
    if not tbl then return false end
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

function Common:TableSize(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Common:TableKeys(tbl)
    if not tbl then return {} end
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

function Common:TableValues(tbl)
    if not tbl then return {} end
    local values = {}
    for _, v in pairs(tbl) do
        table.insert(values, v)
    end
    return values
end

function Common:TableFilter(tbl, predicate)
    if not tbl then return {} end
    local filtered = {}
    for k, v in pairs(tbl) do
        if predicate(v, k) then
            filtered[k] = v
        end
    end
    return filtered
end

function Common:TableMap(tbl, transformer)
    if not tbl then return {} end
    local mapped = {}
    for k, v in pairs(tbl) do
        mapped[k] = transformer(v, k)
    end
    return mapped
end

-- Enhanced Math Functions
function Common:Round(num, decimals)
    if not num then return 0 end
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(num * mult + 0.5) / mult
end

function Common:Clamp(value, min, max)
    if not value then return min or 0 end
    if min and value < min then return min end
    if max and value > max then return max end
    return value
end

function Common:Lerp(a, b, t)
    return a + (b - a) * t
end

function Common:Map(value, inMin, inMax, outMin, outMax)
    return outMin + (outMax - outMin) * ((value - inMin) / (inMax - inMin))
end

-- Color Functions
function Common:ColorText(text, r, g, b)
    if not text then return "" end
    if type(r) == "table" then
        g, b = r[2], r[3]
        r = r[1]
    end
    r = math.floor((r or 1) * 255)
    g = math.floor((g or 1) * 255)  
    b = math.floor((b or 1) * 255)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
end

function Common:HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)) / 255,
           tonumber("0x" .. hex:sub(3, 4)) / 255,
           tonumber("0x" .. hex:sub(5, 6)) / 255
end

function Common:RGBToHex(r, g, b)
    return string.format("%02x%02x%02x", 
        math.floor(r * 255), 
        math.floor(g * 255), 
        math.floor(b * 255))
end

-- Zone and Location Functions
function Common:GetZoneInfo()
    local zone = GetRealZoneText() or "Unknown"
    local subzone = GetSubZoneText() or ""
    local pvpType = GetZonePVPInfo()
    local isInstance, instanceType = IsInInstance()
    
    return {
        zone = zone,
        subzone = subzone,
        pvpType = pvpType,
        isInstance = isInstance,
        instanceType = instanceType,
        isDungeon = instanceType == "party",
        isRaid = instanceType == "raid",
        isPvP = instanceType == "pvp",
        isArena = instanceType == "arena"
    }
end

function Common:GetMapInfo()
    local mapId = GetCurrentMapAreaID()
    local mapName = GetMapNameByID and GetMapNameByID(mapId) or "Unknown"
    local x, y = GetPlayerMapPosition("player")
    
    return {
        id = mapId,
        name = mapName,
        x = x * 100,
        y = y * 100,
        continent = GetCurrentMapContinent()
    }
end

-- Group Functions
function Common:GetGroupInfo()
    local isInRaid = GetNumRaidMembers() > 0
    local isInParty = GetNumPartyMembers() > 0
    
    return {
        isInGroup = isInParty or isInRaid,
        isInRaid = isInRaid,
        isInParty = isInParty,
        size = isInRaid and GetNumRaidMembers() or (isInParty and GetNumPartyMembers() + 1 or 1),
        isLeader = isInRaid and IsRaidLeader() or (isInParty and IsPartyLeader() or true)
    }
end

-- Time Functions
function Common:GetSessionTime()
    return GetTime() - (self.sessionStart or GetTime())
end

function Common:FormatTime(seconds, showSeconds)
    if not seconds then return "0s" end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return showSeconds and string.format("%dh %dm %ds", hours, minutes, secs) 
                            or string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return showSeconds and string.format("%dm %ds", minutes, secs)
                            or string.format("%dm", minutes)
    else
        return string.format("%ds", secs)
    end
end

function Common:GetServerTime()
    local serverHour, serverMinute = GetGameTime()
    return serverHour * 3600 + serverMinute * 60
end

-- Event Management
function Common:RegisterBucketEvent(events, interval, callback)
    if type(events) == "string" then
        events = {events}
    end
    
    local bucket = CreateFrame("Frame")
    local eventQueue = {}
    local elapsed = 0

    for _, event in ipairs(events) do
        bucket:RegisterEvent(event)
    end
    
    bucket:SetScript("OnEvent", function(self, event, ...)
        table.insert(eventQueue, {event = event, args = {...}, time = GetTime()})
    end)

    bucket:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= interval and #eventQueue > 0 then
            local success, err = pcall(callback, eventQueue)
            if not success then
                Common:Log("ERROR", "Bucket event callback error: " .. tostring(err))
            end
            eventQueue = {}
            elapsed = 0
        end
    end)

    bucket.Stop = function()
        bucket:UnregisterAllEvents()
        bucket:SetScript("OnEvent", nil)
        bucket:SetScript("OnUpdate", nil)
    end

    return bucket
end

-- Debug and Logging
function Common:Log(level, message)
    if _G.Fizzure and _G.Fizzure.Log then
        _G.Fizzure:Log(level, message)
    else
        -- Fallback logging
        print("|cff00ff00FizzureCommon|r [" .. (level or "INFO") .. "] " .. tostring(message))
    end
end

-- Module Utilities
function Common:RegisterModuleUtility(name, func)
    if not name or not func then return false end
    self.moduleUtilities[name] = func
    return true
end

function Common:GetModuleUtility(name)
    return self.moduleUtilities[name]
end

-- Validation Functions
function Common:ValidateNumber(value, min, max, default)
    if type(value) ~= "number" then return default end
    if min and value < min then return min end
    if max and value > max then return max end
    return value
end

function Common:ValidateString(value, maxLength, default)
    if type(value) ~= "string" then return default or "" end
    if maxLength and #value > maxLength then
        return value:sub(1, maxLength)
    end
    return value
end

function Common:ValidateTable(value, default)
    return type(value) == "table" and value or (default or {})
end

-- Performance measurement
function Common:BenchmarkFunction(func, iterations)
    iterations = iterations or 1
    local startTime = GetTime()
    
    for i = 1, iterations do
        func()
    end
    
    local endTime = GetTime()
    local totalTime = endTime - startTime
    
    return {
        totalTime = totalTime,
        averageTime = totalTime / iterations,
        iterations = iterations
    }
end

-- Initialize on load
Common:Initialize()