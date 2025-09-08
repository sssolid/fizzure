---@meta

---@meta

---@class FizzureCore
---@field modules table<string, any>
---@field RegisterModule fun(self: FizzureCore, moduleName: string, moduleData: table): boolean

-- Tell the analyzer that a global named Fizzure exists.
---@type FizzureCore
Fizzure = Fizzure

-- Also inform it that _G has a field 'Fizzure' of that type.
---@type FizzureCore
_G.Fizzure = _G.Fizzure

-- Frames
---@param frameType string
---@param name? string
---@param parent? any
---@param template? string
---@return Frame
function CreateFrame(frameType, name, parent, template) end

---@class Frame
local Frame = {}
function Frame:SetPoint(...) end
function Frame:SetSize(...) end
function Frame:Show() end
function Frame:Hide() end
function Frame:SetBackdrop(...) end
function Frame:SetBackdropColor(...) end
function Frame:SetBackdropBorderColor(...) end
function Frame:SetScript(scriptType, handler) end

-- Common globals
UIParent = UIParent or {} ---@type Frame

---@return number
function GetTime() end
function InCombatLockdown() end
function UnitExists(unit) end
function UnitAffectingCombat(unit) end

-- Spells & range (3.3.5)
---@param spell string
---@param unit string
---@return 0|1|nil
function IsSpellInRange(spell, unit) end

---@param unit string
---@param index 1|2|3|4
function CheckInteractDistance(unit, index) end

-- Sounds (numeric sound kit IDs in 3.3.5)
---@param soundKitID integer
---@param channel? "master"|"sfx"|"music"|"ambience"
function PlaySound(soundKitID, channel) end

-- Casting
---@param spell string|number
function CastSpellByName(spell) end

-- Containers (3.3.5)
---@return number texture, number itemCount, boolean locked, number quality, boolean readable, boolean lootable, string|nil link, number isFiltered, boolean noValue, number itemID
function GetContainerItemInfo(bag, slot) end
function PickupContainerItem(bag, slot) end
function UseContainerItem(bag, slot) end
function GetItemInfo(item) end

---@meta

-- ===== Spells =====
---@param spell string|number  -- name or spellID
---@return string name, string|nil rank, string icon, number castTimeMS, number minRange, number maxRange
function GetSpellInfo(spell) end

---@param spellID number
---@param isPetSpell? boolean
---@return boolean known
function IsSpellKnown(spellID, isPetSpell) end

-- ===== Items / Bags =====
---@param item string|number
---@param includeBank? boolean
---@return number count
function GetItemCount(item, includeBank) end

---@param bag number  -- 0..4 (plus specialty)
---@param slot number
---@return string|nil itemLink
function GetContainerItemLink(bag, slot) end

---@param bag number
---@return number freeSlots, number bagFamily
function GetContainerNumFreeSlots(bag) end

-- ===== Map / Zone (Wrath-era) =====
---@return string|nil pvpType, boolean|nil isFFA, string|nil faction
function GetZonePVPInfo() end

---@return number mapAreaID
function GetCurrentMapAreaID() end

---@param unit string
---@return number|nil x, number|nil y
function GetPlayerMapPosition(unit) end

-- ===== Group =====
---@return number n
function GetNumPartyMembers() end

---@return number n
function GetNumRaidMembers() end

-- ===== Skills (Professions/Skills frame) =====
---@return number num
function GetNumSkillLines() end

---@param index number
---@return string name, boolean isHeader, boolean isExpanded, number skillRank, number tempPoints, number skillModifier, number maxRank, boolean isAbandonable, number stepCost, number rankCost, number minLevel, number skillPos
function GetSkillLineInfo(index) end

---@meta

-- ==== Map (3.3.5) ====
---@return string name, string texture, number mapID, number parentMapID, number mapType
function GetMapInfo() end

---@return number mapAreaID
function GetCurrentMapAreaID() end

---@param unit string
---@return number|nil x, number|nil y  -- 0..1, nil if map not set
function GetPlayerMapPosition(unit) end

---Set the current world map to the player's zone
function SetMapToCurrentZone() end

-- ==== Containers / Bags (3.3.5) ====
---@param bag number  -- 0 backpack, 1..4 equipped bags
---@return number slots
function GetContainerNumSlots(bag) end

-- Hunter pet happiness (Wrath era still has happiness 1..3)
---@return 1|2|3|nil happiness, number|nil damagePercent
function GetPetHappiness() end

-- Returns texture path for the item (icon)
---@param item string|number  -- itemID, itemLink, or "item:..."
---@return string|nil texturePath
function GetItemIcon(item) end

-- Pick up an item onto the cursor by id/link/name (behavior varies by client)
---@param item string|number
function PickupItem(item) end

-- Optional: C_Timer shim type (so the IDE "knows" it)
---@class C_TimerClass
---@field After fun(delay:number, func:function)
C_Timer = C_Timer or {} ---@type C_TimerClass
