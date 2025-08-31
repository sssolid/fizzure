-- Common.lua
local Common = {}
_G.FizzureCommon = Common

-- Lightweight replacement for C_Timer.After on 3.3.5.
-- Also shims C_Timer.After so existing calls keep working.
function Common:After(delay, func)
    if type(delay) ~= "number" or delay < 0 then return end
    if type(func) ~= "function" then return end

    local f = CreateFrame("Frame", nil, UIParent)
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            pcall(func)  -- don’t kill other timers on error
            self:Hide()
        end
    end)
    return f
end

function Common:Initialize()
    self.initialized = true
    if not _G.C_Timer then _G.C_Timer = {} end
    if type(_G.C_Timer.After) ~= "function" then
        _G.C_Timer.After = function(delay, func)
            return Common:After(delay, func)
        end
    end
end

Common:Initialize()
