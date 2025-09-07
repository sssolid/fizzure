-- SecureActions.lua - Secure Action Button Management for WoW 3.3.5
-- Handles spell casting, item usage, and keybinding registration for Fizzure modules

local SecureActions = {}
_G.FizzureSecure = SecureActions

-- Storage for secure buttons and keybindings
SecureActions.secureButtons = {}
SecureActions.moduleBindings = {}
SecureActions.bindingCounter = 1

-- Initialize secure action system
function SecureActions:Initialize()
    self.initialized = true
    print("|cff00ff00Fizzure|r SecureActions initialized")
end

-- Create a secure button for spell casting or item usage
function SecureActions:CreateSecureButton(name, macroText, keyBinding, tooltip)
    if InCombatLockdown() then
        print("|cffff0000Fizzure SecureActions:|r Cannot create secure button in combat")
        return nil
    end

    -- Generate unique name if not provided
    if not name then
        name = "FizzureSecure" .. self.bindingCounter
        self.bindingCounter = self.bindingCounter + 1
    end

    -- Create the secure button
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)  -- Hidden button
    button:Hide()

    -- Set macro attributes
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macroText)

    -- Store button reference
    self.secureButtons[name] = {
        button = button,
        macroText = macroText,
        keyBinding = keyBinding,
        tooltip = tooltip or "Fizzure Action"
    }

    -- Set up keybinding if provided
    if keyBinding then
        self:SetKeyBinding(name, keyBinding, tooltip)
    end

    return button
end

-- Remove keybinding
function SecureActions:ClearKeyBinding(key)
    SetBinding(key)
    print("|cff00ff00Fizzure SecureActions:|r Cleared binding for " .. key)
end

-- Register module bindings (for organized management)
function SecureActions:RegisterModuleBindings(moduleName, bindings)
    self.moduleBindings[moduleName] = bindings

    -- Set up the bindings
    for _, binding in ipairs(bindings) do
        if binding.key and binding.buttonName then
            self:SetKeyBinding(binding.buttonName, binding.key, binding.description)
        end
    end

    print("|cff00ff00Fizzure SecureActions:|r Registered " .. #bindings .. " bindings for " .. moduleName)
end

-- Clear all bindings for a module
function SecureActions:ClearModuleBindings(moduleName)
    local bindings = self.moduleBindings[moduleName]
    if not bindings then return end

    for _, binding in ipairs(bindings) do
        if binding.key then
            self:ClearKeyBinding(binding.key)
        end
    end

    self.moduleBindings[moduleName] = nil
    print("|cff00ff00Fizzure SecureActions:|r Cleared bindings for " .. moduleName)
end

-- Get current bindings for a module
function SecureActions:GetModuleBindings(moduleName)
    return self.moduleBindings[moduleName] or {}
end

-- Create a visible action button (for UI placement)
-- Create a visible secure action button (macro-driven)
function SecureActions:CreateVisibleActionButton(parent, text, macroText, width, height)
    if InCombatLockdown() then
        print("|cffff0000Fizzure SecureActions:|r Cannot create visible secure button in combat")
        return nil
    end

    local buttonName = "FizzureVisible" .. (self.bindingCounter or 1)
    self.bindingCounter = (self.bindingCounter or 1) + 1

    -- Secure + skinned like a UIPanelButton
    local btn = CreateFrame("Button", buttonName, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 24)
    btn:SetText(text or "Action")
    btn:RegisterForClicks("AnyUp")
    btn:Show()

    -- SECURE attributes: a macro runs as a protected action on click
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", macroText or "")

    -- Store reference for later updates
    self.secureButtons[buttonName] = { button = btn, macroText = macroText or "", visible = true }
    return btn
end


-- Smart pet feeding button that updates based on available food
function SecureActions:CreateSmartPetFeedButton(parent, text, width, height, getPetFoodFunc)
    local button = self:CreateVisibleActionButton(parent, text, "", width, height)
    if not button then return nil end

    -- Function to update the macro based on current food
    local function updateFeedMacro()
        if InCombatLockdown() then return end

        if getPetFoodFunc and type(getPetFoodFunc) == "function" then
            local bestFood = getPetFoodFunc()
            local macroText

            if bestFood then
                macroText = string.format([[
/cast [pet,exists,nodead] Feed Pet
/stopmacro [nopet]
/use [pet,exists,nodead] %s
]], bestFood.name)
            else
                macroText = [[
/cast [pet,exists,nodead] Feed Pet
/print No suitable food found for pet
]]
            end

            button:SetAttribute("macrotext", macroText)
        end
    end

    -- Initial macro update
    updateFeedMacro()

    -- Store update function for external calls
    button.updateMacro = updateFeedMacro

    return button
end

-- Utility: Save current bindings to saved variables
function SecureActions:SaveBindings()
    if not FizzureDB then FizzureDB = {} end
    if not FizzureDB.secureBindings then FizzureDB.secureBindings = {} end

    for moduleName, bindings in pairs(self.moduleBindings) do
        FizzureDB.secureBindings[moduleName] = {}
        for i, binding in ipairs(bindings) do
            FizzureDB.secureBindings[moduleName][i] = {
                key = binding.key,
                buttonName = binding.buttonName,
                description = binding.description
            }
        end
    end
end

-- Utility: Restore bindings from saved variables
function SecureActions:LoadBindings()
    if not FizzureDB or not FizzureDB.secureBindings then return end

    for moduleName, savedBindings in pairs(FizzureDB.secureBindings) do
        -- Only restore if module is still loaded
        if Fizzure and Fizzure.modules[moduleName] then
            for _, binding in ipairs(savedBindings) do
                -- Verify button still exists
                local buttonData = self.secureButtons[binding.buttonName]
                if buttonData then
                    self:SetKeyBinding(binding.buttonName, binding.key, binding.description)
                end
            end
            self.moduleBindings[moduleName] = savedBindings
        end
    end
end

-- Debug: List all secure buttons and bindings
function SecureActions:ListBindings()
    print("|cff00ff00Fizzure SecureActions - Current Bindings:|r")

    for moduleName, bindings in pairs(self.moduleBindings) do
        print("  |cffffff00" .. moduleName .. ":|r")
        for _, binding in ipairs(bindings) do
            local status = self.secureButtons[binding.buttonName] and "OK" or "MISSING"
            print("    " .. binding.key .. " -> " .. binding.buttonName .. " (" .. status .. ")")
        end
    end

    if not next(self.moduleBindings) then
        print("  No module bindings registered")
    end
end

-- Event handling for combat state changes
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Left combat
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entered combat

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Out of combat - can modify secure attributes
        SecureActions.inCombat = false

        -- Trigger any pending updates
        for buttonName, buttonData in pairs(SecureActions.secureButtons) do
            if buttonData.pendingUpdate then
                SecureActions:UpdateButtonMacro(buttonName, buttonData.pendingUpdate)
                buttonData.pendingUpdate = nil
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- In combat - cannot modify secure attributes
        SecureActions.inCombat = true
    end
end)

-- Initialize on load
SecureActions:Initialize()

-- Slash command for testing and management
SLASH_FIZZURESECURE1 = "/fzsecure"
SlashCmdList["FIZZURESECURE"] = function(msg)
    local cmd, arg1 = strsplit(" ", msg)

    if cmd == "list" then
        SecureActions:ListBindings()
    elseif cmd == "clear" and arg1 then
        SecureActions:ClearKeyBinding(arg1)
    elseif cmd == "save" then
        SecureActions:SaveBindings()
        print("Bindings saved")
    elseif cmd == "load" then
        SecureActions:LoadBindings()
        print("Bindings loaded")
    else
        print("|cff00ff00Fizzure SecureActions Commands:|r")
        print("  /fzsecure list - List all bindings")
        print("  /fzsecure clear <key> - Clear a keybinding")
        print("  /fzsecure save - Save current bindings")
        print("  /fzsecure load - Restore saved bindings")
    end
end

print("|cff00ff00Fizzure|r SecureActions Loaded")