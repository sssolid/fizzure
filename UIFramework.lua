-- UIFramework.lua - Enhanced UI system for Fizzure modules
local UIFramework = {}
_G.FizzureUI = UIFramework

-- Framework state
UIFramework.initialized = false
UIFramework.framePool = {}
UIFramework.activeFrames = {}
UIFramework.frameCounter = 1
UIFramework.widgetTypes = {}

-- Flat design color scheme
local FLAT_COLORS = {
    background = {0.12, 0.12, 0.12, 0.95},
    panel = {0.15, 0.15, 0.15, 0.9},
    border = {0.25, 0.25, 0.25, 1},
    accent = {0.2, 0.6, 1, 1},
    success = {0.2, 0.8, 0.2, 1},
    warning = {0.8, 0.6, 0.2, 1},
    error = {0.8, 0.2, 0.2, 1},
    text = {0.9, 0.9, 0.9, 1},
    textSecondary = {0.7, 0.7, 0.7, 1},
    button = {0.18, 0.18, 0.18, 0.9},
    buttonHover = {0.22, 0.22, 0.22, 0.9},
    input = {0.08, 0.08, 0.08, 0.95}
}

-- Initialize UI Framework
function UIFramework:Initialize()
    if self.initialized then return end
    
    -- Register widget type constructors
    self:RegisterWidgetTypes()
    
    -- Create frame recycling system
    self:InitializeFramePool()
    
    self.initialized = true
    self:Log("INFO", "UI Framework initialized")
end

-- Widget type registration
function UIFramework:RegisterWidgetTypes()
    self.widgetTypes = {
        Window = self.CreateWindow,
        StatusFrame = self.CreateStatusFrame,
        Panel = self.CreatePanel,
        Button = self.CreateButton,
        Label = self.CreateLabel,
        EditBox = self.CreateEditBox,
        CheckBox = self.CreateCheckBox,
        Slider = self.CreateSlider,
        Dropdown = self.CreateDropdown,
        StatusBar = self.CreateStatusBar,
        ScrollFrame = self.CreateScrollFrame,
        ItemSlot = self.CreateItemSlot,
        Separator = self.CreateSeparator
    }
end

-- Frame pool management
function UIFramework:InitializeFramePool()
    self.framePool = {
        Frame = {},
        Button = {},
        StatusBar = {},
        ScrollFrame = {},
        EditBox = {}
    }
end

function UIFramework:GetPooledFrame(frameType)
    local pool = self.framePool[frameType]
    if pool and #pool > 0 then
        local frame = table.remove(pool)
        frame:Show()
        return frame, false -- false = reused
    end
    return nil, true -- true = needs creation
end

function UIFramework:ReturnToPool(frame, frameType)
    local pool = self.framePool[frameType]
    if pool and frame then
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(UIParent)
        table.insert(pool, frame)
    end
end

-- Enhanced frame creation with unique naming
function UIFramework:GetUniqueFrameName(prefix)
    local name = (prefix or "FizzureUIFrame") .. self.frameCounter
    self.frameCounter = self.frameCounter + 1
    return name
end

function UIFramework:CreateFrame(frameType, name, parent, template)
    local frameName = name or self:GetUniqueFrameName("FizzureFrame")
    local frame = CreateFrame(frameType or "Frame", frameName, parent or UIParent, template)
    
    -- Enhanced frame with common functionality
    frame.fizzureType = frameType
    frame.originalHide = frame.Hide
    frame.originalShow = frame.Show
    
    function frame:Hide()
        self:originalHide()
        if self.OnHide then self:OnHide() end
    end
    
    function frame:Show()
        self:originalShow()
        if self.OnShow then self:OnShow() end
    end
    
    -- Add to active frames tracking
    table.insert(self.activeFrames, frame)
    
    return frame
end

-- Create flat backdrop
local function CreateFlatBackdrop()
    return {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
end

-- Enhanced window creation
function UIFramework:CreateWindow(name, title, width, height, parent, flatDesign)
    flatDesign = flatDesign ~= false -- Default to true
    
    local frameName = name or self:GetUniqueFrameName("FizzureWindow")
    local frame = self:CreateFrame("Frame", frameName, parent)
    frame:SetSize(width or 400, height or 300)
    frame:SetPoint("CENTER")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    
    -- Backdrop
    if flatDesign then
        frame:SetBackdrop(CreateFlatBackdrop())
        frame:SetBackdropColor(unpack(FLAT_COLORS.background))
        frame:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        frame:SetBackdropColor(0, 0, 0, 0.95)
    end
    
    -- Drag handling
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.OnPositionChanged then self:OnPositionChanged() end
    end)
    
    -- Title bar
    local titleBar = self:CreateFrame("Frame", self:GetUniqueFrameName("TitleBar"), frame)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", flatDesign and 5 or 12, flatDesign and -5 or -12)
    titleBar:SetPoint("TOPRIGHT", flatDesign and -35 or -42, flatDesign and -5 or -12)
    
    local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 5, 0)
    titleText:SetText(title or "Window")
    titleText:SetTextColor(unpack(FLAT_COLORS.text))
    
    -- Close button
    local closeBtn = CreateFrame("Button", self:GetUniqueFrameName("CloseButton"), frame)
    if flatDesign then
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:SetBackdrop(CreateFlatBackdrop())
        closeBtn:SetBackdropColor(unpack(FLAT_COLORS.error))
        closeBtn:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        
        local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        closeText:SetAllPoints()
        closeText:SetText("×")
        closeText:SetTextColor(1, 1, 1, 1)
        
        -- Hover effects
        closeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(1, 0.3, 0.3, 1)
        end)
        closeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(FLAT_COLORS.error))
        end)
    else
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetSize(32, 32)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
    end
    
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Content area
    local content = self:CreateFrame("Frame", self:GetUniqueFrameName("Content"), frame)
    content:SetPoint("TOPLEFT", flatDesign and 5 or 12, flatDesign and -37 or -44)
    content:SetPoint("BOTTOMRIGHT", flatDesign and -5 or -12, flatDesign and 5 or 12)
    
    -- Store references
    frame.titleText = titleText
    frame.titleBar = titleBar
    frame.closeBtn = closeBtn
    frame.content = content
    frame.flatDesign = flatDesign
    
    -- Window management methods
    function frame:SetTitle(newTitle)
        self.titleText:SetText(newTitle or "")
    end
    
    function frame:ToggleMinimize()
        if self.minimized then
            self:SetHeight(self.normalHeight or 300)
            self.minimized = false
        else
            self.normalHeight = self:GetHeight()
            self:SetHeight(37)
            self.minimized = true
        end
    end
    
    frame:Hide()
    return frame
end

-- Enhanced status frame
function UIFramework:CreateStatusFrame(name, title, width, height, flatDesign)
    flatDesign = flatDesign ~= false
    
    local frameName = name or self:GetUniqueFrameName("FizzureStatusFrame")
    local frame = self:CreateFrame("Frame", frameName, UIParent)
    frame:SetSize(width or 200, height or 140)
    frame:SetPoint("TOPLEFT", 20, -100)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    
    if flatDesign then
        frame:SetBackdrop(CreateFlatBackdrop())
        frame:SetBackdropColor(unpack(FLAT_COLORS.background))
        frame:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        frame:SetBackdropColor(0, 0, 0, 0.9)
    end
    
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.OnPositionChanged then self:OnPositionChanged() end
    end)
    
    -- Title
    if title then
        local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleText:SetPoint("TOP", 0, -8)
        titleText:SetText(title)
        titleText:SetTextColor(unpack(FLAT_COLORS.text))
        frame.titleText = titleText
    end
    
    frame.flatDesign = flatDesign
    return frame
end

-- Enhanced panel creation
function UIFramework:CreatePanel(parent, width, height, anchor, flatDesign)
    flatDesign = flatDesign ~= false
    
    local panel = self:CreateFrame("Frame", self:GetUniqueFrameName("Panel"), parent)
    panel:SetSize(width or 200, height or 100)
    
    if anchor then
        panel:SetPoint(anchor.point or "TOPLEFT",
                anchor.relativeFrame or parent,
                anchor.relativePoint or "TOPLEFT",
                anchor.x or 0,
                anchor.y or 0)
    else
        panel:SetPoint("TOPLEFT")
    end
    
    if flatDesign then
        panel:SetBackdrop(CreateFlatBackdrop())
        panel:SetBackdropColor(unpack(FLAT_COLORS.panel))
        panel:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    end
    
    return panel
end

-- Enhanced button creation
function UIFramework:CreateButton(parent, buttonText, width, height, onClick, flatDesign)
    flatDesign = flatDesign ~= false
    
    local buttonName = self:GetUniqueFrameName("Button")
    local button
    
    if flatDesign then
        button = CreateFrame("Button", buttonName, parent)
        button:SetSize(width or 100, height or 25)
        button:SetBackdrop(CreateFlatBackdrop())
        button:SetBackdropColor(unpack(FLAT_COLORS.button))
        button:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetAllPoints()
        text:SetText(buttonText or "Button")
        text:SetTextColor(unpack(FLAT_COLORS.text))
        button.text = text
        
        -- Hover effects
        button:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(FLAT_COLORS.buttonHover))
        end)
        
        button:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(FLAT_COLORS.button))
        end)
        
        -- Click effects
        button:SetScript("OnMouseDown", function(self)
            if self:IsEnabled() then
                self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            end
        end)
        
        button:SetScript("OnMouseUp", function(self)
            if self:IsEnabled() then
                self:SetBackdropColor(unpack(FLAT_COLORS.button))
            end
        end)
        
        -- Disabled state
        button.originalEnable = button.Enable
        button.originalDisable = button.Disable
        
        function button:Enable()
            self:originalEnable()
            self.text:SetTextColor(unpack(FLAT_COLORS.text))
            self:SetBackdropColor(unpack(FLAT_COLORS.button))
        end
        
        function button:Disable()
            self:originalDisable()
            self.text:SetTextColor(unpack(FLAT_COLORS.textSecondary))
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        end
        
    else
        button = CreateFrame("Button", buttonName, parent, "UIPanelButtonTemplate")
        button:SetSize(width or 100, height or 25)
        button:SetText(buttonText or "Button")
    end
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    -- Enhanced button methods
    function button:SetText(text)
        if self.text then
            self.text:SetText(text)
        elseif self.SetText then
            self:SetText(text)
        end
    end
    
    return button
end

-- Enhanced label creation
function UIFramework:CreateLabel(parent, labelText, fontSize)
    local fontString = parent:CreateFontString(nil, "ARTWORK", fontSize or "GameFontNormal")
    fontString:SetText(labelText or "")
    fontString:SetTextColor(unpack(FLAT_COLORS.text))
    
    -- Enhanced label methods
    function fontString:SetTextColorRGB(r, g, b, a)
        self:SetTextColor(r, g, b, a or 1)
    end
    
    function fontString:SetSecondaryColor()
        self:SetTextColor(unpack(FLAT_COLORS.textSecondary))
    end
    
    function fontString:SetSuccessColor()
        self:SetTextColor(unpack(FLAT_COLORS.success))
    end
    
    function fontString:SetWarningColor()
        self:SetTextColor(unpack(FLAT_COLORS.warning))
    end
    
    function fontString:SetErrorColor()
        self:SetTextColor(unpack(FLAT_COLORS.error))
    end
    
    return fontString
end

-- Enhanced edit box
function UIFramework:CreateEditBox(parent, width, height, placeholder, flatDesign)
    flatDesign = flatDesign ~= false
    
    local editBox = CreateFrame("EditBox", self:GetUniqueFrameName("EditBox"), parent)
    editBox:SetSize(width or 150, height or 25)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    
    if flatDesign then
        editBox:SetBackdrop(CreateFlatBackdrop())
        editBox:SetBackdropColor(unpack(FLAT_COLORS.input))
        editBox:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        
        -- Focus effects
        editBox:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(unpack(FLAT_COLORS.accent))
        end)
        
        editBox:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        end)
    else
        editBox:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = true, tileSize = 16, edgeSize = 1,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        editBox:SetBackdropColor(0, 0, 0, 0.8)
        editBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
    
    editBox:SetTextInsets(8, 8, 4, 4)
    editBox:SetTextColor(unpack(FLAT_COLORS.text))
    
    -- Placeholder functionality
    if placeholder then
        editBox.placeholder = placeholder
        editBox:SetText(placeholder)
        editBox:SetTextColor(unpack(FLAT_COLORS.textSecondary))
        
        editBox:SetScript("OnEditFocusGained", function(self)
            if self:GetText() == self.placeholder then
                self:SetText("")
                self:SetTextColor(unpack(FLAT_COLORS.text))
            end
            if flatDesign then
                self:SetBackdropBorderColor(unpack(FLAT_COLORS.accent))
            end
        end)
        
        editBox:SetScript("OnEditFocusLost", function(self)
            if self:GetText() == "" then
                self:SetText(self.placeholder)
                self:SetTextColor(unpack(FLAT_COLORS.textSecondary))
            end
            if flatDesign then
                self:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
            end
        end)
    end
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    -- Enhanced methods
    function editBox:GetRealText()
        local text = self:GetText()
        return (text ~= self.placeholder) and text or ""
    end
    
    function editBox:SetRealText(text)
        self:SetText(text or "")
        if text and text ~= "" then
            self:SetTextColor(unpack(FLAT_COLORS.text))
        end
    end
    
    return editBox
end

-- Enhanced checkbox
function UIFramework:CreateCheckBox(parent, labelText, checked, onToggle, flatDesign)
    flatDesign = flatDesign ~= false
    
    local checkFrame = CreateFrame("Frame", self:GetUniqueFrameName("CheckFrame"), parent)
    checkFrame:SetSize(200, 20)
    
    local checkBox = CreateFrame("Button", self:GetUniqueFrameName("CheckBox"), checkFrame)
    checkBox:SetSize(16, 16)
    checkBox:SetPoint("LEFT")
    
    if flatDesign then
        checkBox:SetBackdrop(CreateFlatBackdrop())
        checkBox:SetBackdropColor(unpack(FLAT_COLORS.input))
        checkBox:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        
        local checkMark = checkBox:CreateTexture(nil, "OVERLAY")
        checkMark:SetSize(12, 12)
        checkMark:SetPoint("CENTER")
        checkMark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkMark:SetVertexColor(unpack(FLAT_COLORS.accent))
        checkMark:Hide()
        checkBox.checkMark = checkMark
        
        -- Hover effect
        checkBox:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(unpack(FLAT_COLORS.accent))
        end)
        
        checkBox:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        end)
    else
        checkBox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        checkBox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        checkBox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        checkBox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    
    -- Label
    local label = self:CreateLabel(checkFrame, labelText, "GameFontNormalSmall")
    label:SetPoint("LEFT", checkBox, "RIGHT", 8, 0)
    
    -- State management
    checkBox.checked = checked or false
    
    function checkBox:SetChecked(state)
        self.checked = state
        if flatDesign then
            if state then
                self.checkMark:Show()
            else
                self.checkMark:Hide()
            end
        else
            if state then
                self:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            else
                self:SetCheckedTexture(nil)
            end
        end
    end
    
    function checkBox:GetChecked()
        return self.checked
    end
    
    checkBox:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onToggle then
            onToggle(self.checked)
        end
    end)
    
    -- Set initial state
    checkBox:SetChecked(checked or false)
    
    checkFrame.checkBox = checkBox
    checkFrame.label = label
    
    return checkFrame
end

-- Enhanced slider
function UIFramework:CreateSlider(parent, sliderName, min, max, value, step, onChange, flatDesign)
    flatDesign = flatDesign ~= false
    
    local sliderFrame = CreateFrame("Frame", self:GetUniqueFrameName("SliderFrame"), parent)
    sliderFrame:SetSize(200, 50)
    
    local slider = CreateFrame("Slider", self:GetUniqueFrameName("Slider"), sliderFrame)
    slider:SetSize(180, 16)
    slider:SetPoint("CENTER", 0, -5)
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValue(value or min or 0)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    
    if flatDesign then
        -- Track
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(4)
        track:SetPoint("LEFT", 10, 0)
        track:SetPoint("RIGHT", -10, 0)
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.3, 0.3, 0.3, 1)
        
        -- Thumb
        local thumb = slider:CreateTexture(nil, "ARTWORK")
        thumb:SetSize(16, 16)
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(unpack(FLAT_COLORS.accent))
        slider:SetThumbTexture(thumb)
        
        -- Progress fill
        local progress = slider:CreateTexture(nil, "BORDER")
        progress:SetHeight(4)
        progress:SetPoint("LEFT", 10, 0)
        progress:SetTexture("Interface\\Buttons\\WHITE8X8")
        progress:SetVertexColor(unpack(FLAT_COLORS.accent))
        slider.progress = progress
        
        -- Update progress fill
        local function updateProgress()
            local pct = (slider:GetValue() - slider:GetMinMaxValues()) / 
                       (select(2, slider:GetMinMaxValues()) - slider:GetMinMaxValues())
            progress:SetWidth((slider:GetWidth() - 20) * pct)
        end
        
        slider:SetScript("OnValueChanged", function(self, val)
            updateProgress()
            if onChange then onChange(val) end
        end)
        
        updateProgress()
    else
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 }
        })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        
        if onChange then
            slider:SetScript("OnValueChanged", onChange)
        end
    end
    
    -- Labels
    if sliderName then
        local nameLabel = self:CreateLabel(sliderFrame, sliderName, "GameFontNormalSmall")
        nameLabel:SetPoint("BOTTOM", slider, "TOP", 0, 5)
    end
    
    local lowLabel = self:CreateLabel(sliderFrame, tostring(min or 0), "GameFontNormalSmall")
    lowLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -5)
    
    local highLabel = self:CreateLabel(sliderFrame, tostring(max or 100), "GameFontNormalSmall")
    highLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -5)
    
    -- Value display
    local valueLabel = self:CreateLabel(sliderFrame, tostring(math.floor(value or min or 0)), "GameFontNormalSmall")
    valueLabel:SetPoint("BOTTOM", slider, "TOP", 0, -8)
    
    slider:SetScript("OnValueChanged", function(self, val)
        valueLabel:SetText(tostring(math.floor(val)))
        if onChange then onChange(val) end
    end)
    
    sliderFrame.slider = slider
    sliderFrame.valueLabel = valueLabel
    
    return sliderFrame
end

-- Enhanced status bar
function UIFramework:CreateStatusBar(parent, width, height, min, max, value, flatDesign)
    flatDesign = flatDesign ~= false
    
    local bar = CreateFrame("StatusBar", self:GetUniqueFrameName("StatusBar"), parent)
    bar:SetSize(width or 100, height or 20)
    bar:SetMinMaxValues(min or 0, max or 100)
    bar:SetValue(value or 0)
    
    if flatDesign then
        -- Background
        bar:SetBackdrop(CreateFlatBackdrop())
        bar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        bar:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
        
        -- Status bar texture
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(unpack(FLAT_COLORS.accent))
    else
        bar:SetBackdrop({
            bgFile = "Interface\\TargetingFrame\\UI-StatusBar",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        bar:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    
    -- Text overlay
    local textOverlay = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textOverlay:SetPoint("CENTER")
    textOverlay:SetTextColor(unpack(FLAT_COLORS.text))
    bar.textOverlay = textOverlay
    
    function bar:SetText(str)
        self.textOverlay:SetText(str)
    end
    
    function bar:SetColor(r, g, b, a)
        self:SetStatusBarColor(r, g, b, a or 1)
    end
    
    return bar
end

-- Enhanced scroll frame
function UIFramework:CreateScrollFrame(parent, width, height, scrollBarWidth, name)
    scrollBarWidth = scrollBarWidth or 20
    local frameName = name or self:GetUniqueFrameName("ScrollFrame")
    
    local scrollFrame = CreateFrame("ScrollFrame", frameName, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width, height)
    scrollFrame:SetPoint("TOPLEFT")
    
    -- Create scroll child
    local scrollChild = CreateFrame("Frame", frameName .. "Child", scrollFrame)
    scrollChild:SetSize(width - scrollBarWidth, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Mouse wheel support
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 30), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)
    
    -- Auto-update scroll child height
    function scrollFrame:UpdateScrollChildHeight()
        local maxBottom = 0
        for i = 1, scrollChild:GetNumChildren() do
            local child = select(i, scrollChild:GetChildren())
            if child and child:IsShown() then
                local bottom = select(5, child:GetPoint()) or 0
                if math.abs(bottom) > maxBottom then
                    maxBottom = math.abs(bottom)
                end
            end
        end
        scrollChild:SetHeight(math.max(maxBottom + 20, height))
    end
    
    scrollFrame.content = scrollChild
    return scrollFrame
end

-- Notification system
function UIFramework:ShowToast(toastText, duration, toastType)
    duration = duration or 3
    
    local toast = self:CreateFrame("Frame", self:GetUniqueFrameName("Toast"), UIParent)
    toast:SetSize(300, 60)
    toast:SetPoint("TOP", 0, -100)
    toast:SetFrameStrata("DIALOG")
    
    toast:SetBackdrop(CreateFlatBackdrop())
    
    local colors = {
        success = FLAT_COLORS.success,
        error = FLAT_COLORS.error,
        warning = FLAT_COLORS.warning,
        info = FLAT_COLORS.accent
    }
    
    local color = colors[toastType] or colors.info
    toast:SetBackdropColor(color[1], color[2], color[3], 0.9)
    toast:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    
    local message = toast:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    message:SetPoint("CENTER")
    message:SetText(toastText)
    message:SetTextColor(1, 1, 1, 1)
    
    -- Fade in animation
    toast:SetAlpha(0)
    toast:Show()
    
    local fadeIn = toast:CreateAnimationGroup()
    local alpha1 = fadeIn:CreateAnimation("Alpha")
    alpha1:SetFromAlpha(0)
    alpha1:SetToAlpha(1)
    alpha1:SetDuration(0.2)
    fadeIn:Play()
    
    -- Auto hide with fade out
    FizzureCommon:After(duration, function()
        local fadeOut = toast:CreateAnimationGroup()
        local alpha2 = fadeOut:CreateAnimation("Alpha")
        alpha2:SetFromAlpha(1)
        alpha2:SetToAlpha(0)
        alpha2:SetDuration(0.5)
        
        fadeOut:SetScript("OnFinished", function()
            toast:Hide()
            -- Return to pool if applicable
            UIFramework:ReturnToPool(toast, "Frame")
        end)
        
        fadeOut:Play()
    end)
    
    return toast
end

-- Separator line
function UIFramework:CreateSeparator(parent, width, height, color)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(width or parent:GetWidth() - 20, height or 1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(unpack(color or FLAT_COLORS.border))
    return line
end

-- Cleanup function
function UIFramework:Cleanup()
    for _, frame in ipairs(self.activeFrames) do
        if frame and frame.Hide then
            frame:Hide()
        end
    end
    self.activeFrames = {}
    
    -- Clear pools
    for frameType, pool in pairs(self.framePool) do
        for _, frame in ipairs(pool) do
            if frame and frame.Hide then
                frame:Hide()
            end
        end
        self.framePool[frameType] = {}
    end
end

-- Logging
function UIFramework:Log(level, message)
    if _G.FizzureCommon and _G.FizzureCommon.Log then
        _G.FizzureCommon:Log(level, "[UI] " .. message)
    end
end

-- Initialize on load
UIFramework:Initialize()