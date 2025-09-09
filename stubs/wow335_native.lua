---@meta

-- ========= Fizzure core typing =========
---@class FizzureCore
---@field modules table<string, any>
---@field RegisterModule fun(self: FizzureCore, name: string, module: table, class?: string): boolean
---@field EnableModule fun(self: FizzureCore, name: string): boolean
---@field DisableModule fun(self: FizzureCore, name: string): boolean
---@field GetModuleSettings fun(self: FizzureCore, name: string): table
---@field SetModuleSettings fun(self: FizzureCore, name: string, settings: table): boolean
---@field ShowNotification fun(self: FizzureCore, title:string, msg:string, level?:string, duration?:number)

---@type FizzureCore
Fizzure = Fizzure
---@type FizzureCore
_G.Fizzure = _G.Fizzure

-- ========= Frames / regions (minimal but covers your usage) =========
---@class Frame
local Frame = {}
function Frame:SetPoint(...) end
function Frame:ClearAllPoints() end
function Frame:SetSize(...) end
function Frame:SetAlpha(...) end
function Frame:Show() end
function Frame:Hide() end
function Frame:SetScript(...) end
function Frame:SetBackdrop(...) end
function Frame:SetBackdropColor(...) end
function Frame:SetBackdropBorderColor(...) end
function Frame:RegisterForClicks(...) end
function Frame:SetChecked(...) end      -- for CheckButton
function Frame:GetChecked(...) return false end
function Frame:SetText(...) end         -- for EditBox-like
function Frame:SetTextColor(...) end    -- for FontString/Text
function Frame:SetTextInsets(...) end   -- for EditBox
function Frame:SetAutoFocus(...) end
function Frame:SetFont(...) end
function Frame:SetNormalTexture(...) end
function Frame:SetHighlightTexture(...) end
function Frame:SetPushedTexture(...) end
function Frame:SetAllPoints(...) end
function Frame:GetChildren() end        -- returns varargs at runtime
function Frame:GetRegions() end

---@class FontString : Frame
local FontString = {}

---@class Animation : Frame
local Animation = {}
function Animation:SetChange(...) end
function Animation:SetDuration(...) end

---@class AnimationGroup : Frame
local AnimationGroup = {}
---@return Animation
function AnimationGroup:CreateAnimation(...) end
function AnimationGroup:Play(...) end

---@param frameType string
---@param name? string
---@param parent? any
---@param template? string
---@return Frame
function CreateFrame(frameType, name, parent, template) end

---@return FontString
function Frame:CreateFontString(...) end

---@return AnimationGroup
function Frame:CreateAnimationGroup(...) end

UIParent = UIParent or {} ---@type Frame

-- ========= Game API (3.3.5) =========
---@return number
function GetTime() end

function InCombatLockdown() end
function UnitExists(unit) end
---@param unit string
---@return string className, string classTag
function UnitClass(unit) end
function UnitAffectingCombat(unit) end

-- Spells / range
---@param spell string|number
---@return string name, string|nil rank, string icon, number castTimeMS, number minRange, number maxRange
function GetSpellInfo(spell) end

---@param spellID number
---@param isPetSpell? boolean
---@return boolean
function IsSpellKnown(spellID, isPetSpell) end

---@param spell string
---@param unit string
---@return 0|1|nil
function IsSpellInRange(spell, unit) end

---@param unit string
---@param index 1|2|3|4
---@return boolean
function CheckInteractDistance(unit, index) end

---@param spell string|number
function CastSpellByName(spell) end

-- Containers / items
---@param bag number
---@return number slots
function GetContainerNumSlots(bag) end

---@param bag number
---@param slot number
---@return number texture, number itemCount, boolean locked, number quality, boolean readable, boolean lootable, string|nil link, number isFiltered, boolean noValue, number itemID
function GetContainerItemInfo(bag, slot) end

---@param bag number
---@param slot number
---@return string|nil itemLink
function GetContainerItemLink(bag, slot) end

function PickupContainerItem(bag, slot) end
function UseContainerItem(bag, slot) end

---@param item string|number
---@param includeBank? boolean
---@return number count
function GetItemCount(item, includeBank) end

---@param item string|number
---@return string|nil texturePath
function GetItemIcon(item) end

---@param item string|number
function GetItemInfo(item) end

-- Map / zones (Wrath)
---@return number mapAreaID
function GetCurrentMapAreaID() end

---@return string name, string texture, number mapID, number parentMapID, number mapType
function GetMapInfo() end

---@param unit string
---@return number|nil x, number|nil y
function GetPlayerMapPosition(unit) end

function SetMapToCurrentZone() end

-- Groups
---@return number
function GetNumPartyMembers() end
---@return number
function GetNumRaidMembers() end

-- Skills
---@return number
function GetNumSkillLines() end
---@param index number
---@return string name, boolean isHeader, boolean isExpanded, number skillRank, number tempPoints, number skillModifier, number maxRank, boolean isAbandonable, number stepCost, number rankCost, number minLevel, number skillPos
function GetSkillLineInfo(index) end

-- Pet
---@return 1|2|3|nil happiness, number|nil damagePercent
function GetPetHappiness() end

-- Sound (numeric IDs on 3.3.5)
---@param soundKitID integer
---@param channel? "master"|"sfx"|"music"|"ambience"
function PlaySound(soundKitID, channel) end

-- Timer (type only; your runtime shim provides the function)
---@class C_TimerClass
---@field After fun(delay:number, func:function)
C_Timer = C_Timer or {} ---@type C_TimerClass
