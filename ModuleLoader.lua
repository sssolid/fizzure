-- ModuleLoader.lua - Module registration helper for delayed loading
-- This handles modules that load before the core framework is ready

local ModuleLoader = {}
_G.FizzureModuleLoader = ModuleLoader

-- Module queue for modules that register before framework is ready
ModuleLoader.queuedModules = {}
ModuleLoader.frameworkReady = false

-- Register a module (called by modules or framework)
function ModuleLoader:RegisterModule(moduleTable)
    if not moduleTable then
        self:Log("ERROR", "Attempted to register nil module")
        return false
    end
    
    -- If framework is ready, register directly
    if self.frameworkReady and _G.Fizzure then
        return _G.Fizzure:RegisterModule(moduleTable)
    end
    
    -- Otherwise, queue for later registration
    table.insert(self.queuedModules, moduleTable)
    self:Log("INFO", "Queued module for registration: " .. (moduleTable.name or "Unknown"))
    return true
end

-- Called by framework when it's ready to accept modules
function ModuleLoader:OnFrameworkReady()
    if self.frameworkReady then
        return -- Already processed
    end
    
    self.frameworkReady = true
    
    if not _G.Fizzure then
        self:Log("ERROR", "Framework ready signal received but Fizzure not available")
        return
    end
    
    self:Log("INFO", "Framework ready, processing " .. #self.queuedModules .. " queued modules")
    
    -- Register all queued modules
    local successCount = 0
    local failCount = 0
    
    for _, moduleTable in ipairs(self.queuedModules) do
        local success = _G.Fizzure:RegisterModule(moduleTable)
        if success then
            successCount = successCount + 1
        else
            failCount = failCount + 1
            self:Log("ERROR", "Failed to register queued module: " .. (moduleTable.name or "Unknown"))
        end
    end
    
    -- Clear the queue
    self.queuedModules = {}
    
    self:Log("INFO", string.format("Module registration complete: %d successful, %d failed", 
        successCount, failCount))
end

-- Get status information
function ModuleLoader:GetStatus()
    return {
        frameworkReady = self.frameworkReady,
        queuedModules = #self.queuedModules,
        moduleNames = self:GetQueuedModuleNames()
    }
end

function ModuleLoader:GetQueuedModuleNames()
    local names = {}
    for _, module in ipairs(self.queuedModules) do
        local name = "Unknown"
        if module.GetManifest then
            local manifest = module:GetManifest()
            name = manifest and manifest.name or "Unknown"
        elseif module.name then
            name = module.name
        end
        table.insert(names, name)
    end
    return names
end

-- Logging
function ModuleLoader:Log(level, message)
    if _G.FizzureCommon and _G.FizzureCommon.Log then
        _G.FizzureCommon:Log(level, "[ModuleLoader] " .. message)
    else
        -- Fallback logging when common utilities not available
        print("|cff00ff00FizzureLoader|r [" .. (level or "INFO") .. "] " .. tostring(message))
    end
end

-- Initialize compatibility global
if not _G.FizzureModuleQueue then
    _G.FizzureModuleQueue = ModuleLoader.queuedModules
end

-- Create compatibility function for old-style registration
_G.RegisterFizzureModule = function(moduleTable)
    return ModuleLoader:RegisterModule(moduleTable)
end

print("|cff00ff00Fizzure|r Module Loader initialized")