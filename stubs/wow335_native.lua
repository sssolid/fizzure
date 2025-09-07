---@meta

---@param frameType string
---@param name? string
---@param parent? any
---@param template? string
---@return any
function CreateFrame(frameType, name, parent, template) end

---@param spell string|number
function CastSpellByName(spell) end

---@return number
function GetTime() end

function InCombatLockdown() end
function UnitExists(unit) end
function UnitAffectingCombat(unit) end

-- Containers (3.3.5)
---@return number texture, number itemCount, boolean locked, number quality, boolean readable, boolean lootable, number link, number isFiltered, boolean noValue, number itemID
function GetContainerItemInfo(bag, slot) end
function PickupContainerItem(bag, slot) end
function UseContainerItem(bag, slot) end
function GetItemInfo(item) end

-- Frame methods (commonly used; keep minimal)
---@class Frame
local Frame = {}
function Frame:SetPoint(...) end
function Frame:SetSize(...) end
function Frame:Show() end
function Frame:Hide() end
function Frame:SetBackdrop(...) end
function Frame:SetBackdropColor(...) end
function Frame:SetBackdropBorderColor(...) end
