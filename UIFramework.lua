-- UIFramework.lua - Enhanced GUI system for Fizzure modules with FIXES for 3.3.5
local UIFramework = {}
_G.FizzureUI = UIFramework

-- Frame pool for performance
UIFramework.framePool = {}
UIFramework.activeFrames = {}
UIFramework.frameCounter = 1

-- Flat design color scheme
local FLAT_COLORS = {
    background = {0.12, 0.12, 0.12, 0.95},
    panel = {0.15, 0.15, 0.15, 0.9},
    border = {0.25, 0.25, 0.25, 1},
    accent = {0.2, 0.6, 1, 1},
    success = {0.2, 0.8, 0.2, 1},
    warning = {0.8, 0.6, 0.2, 1},
    error = {0.8, 0.2, 0.2, 1},
    text = {0.9, 0.9, 0.9, 1}
}

-- FIXED: Get unique frame name function
function UIFramework:GetUniqueFrameName(prefix)
    local name = (prefix or "FizzureUIFrame") .. self.frameCounter
    self.frameCounter = self.frameCounter + 1
    return name
end

-- FIXED: Base frame creation with proper naming
function UIFramework:CreateFrame(frameType, name, parent, template)
    -- FIXED: Always provide a name instead of nil
    local frameName = name or self:GetUniqueFrameName("FizzureFrame")
    local frame = CreateFrame(frameType or "Frame", frameName, parent or UIParent, template)

    -- Add common methods
    frame.Hide_ = frame.Hide
    function frame:Hide()
        self:Hide_()
        if self.OnHide then self:OnHide() end
    end

    frame.Show_ = frame.Show
    function frame:Show()
        self:Show_()
        if self.OnShow then self:OnShow() end
    end

    return frame
end

-- Create flat backdrop
local function CreateFlatBackdrop(bgAlpha, borderAlpha)
    return {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
end

-- FIXED: Window creation with proper naming and flat design
function UIFramework:CreateWindow(name, title, width, height, parent, flatDesign)
    local frameName = name or self:GetUniqueFrameName("FizzureWindow")
    local frame = self:CreateFrame("Frame", frameName, parent)
    frame:SetSize(width or 400, height or 300)
    frame:SetPoint("CENTER")

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

    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.OnPositionChanged then self:OnPositionChanged() end
    end)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Title bar
    local titleBar = self:CreateFrame("Frame", self:GetUniqueFrameName("TitleBar"), frame)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", flatDesign and 5 or 12, flatDesign and -5 or -12)
    titleBar:SetPoint("TOPRIGHT", flatDesign and -5 or -12, flatDesign and -5 or -12)

    local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", 0, 0)
    titleText:SetText(title or "")
    titleText:SetTextColor(unpack(FLAT_COLORS.text))
    frame.titleText = titleText
    frame.titleBar = titleBar

    -- Close button
    local closeBtn = CreateFrame("Button", self:GetUniqueFrameName("CloseButton"), frame, flatDesign and nil or "UIPanelCloseButton")
    if flatDesign then
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", -8, -8)
        closeBtn:SetBackdrop(CreateFlatBackdrop())
        closeBtn:SetBackdropColor(unpack(FLAT_COLORS.error))
        closeBtn:SetBackdropBorderColor(unpack(FLAT_COLORS.border))

        local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        closeText:SetAllPoints()
        closeText:SetText("×")
        closeText:SetTextColor(1, 1, 1, 1)
    else
        closeBtn:SetPoint("TOPRIGHT", -8, -8)
    end
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.closeBtn = closeBtn

    -- Content area - properly positioned below title bar
    local content = self:CreateFrame("Frame", self:GetUniqueFrameName("Content"), frame)
    content:SetPoint("TOPLEFT", flatDesign and 5 or 12, flatDesign and -35 or -44)
    content:SetPoint("BOTTOMRIGHT", flatDesign and -5 or -12, flatDesign and 5 or 12)
    frame.content = content

    return frame
end

-- FIXED: Panel creation with proper naming and flat design
function UIFramework:CreatePanel(parent, width, height, anchor, flatDesign)
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

-- FIXED: Scroll frame with proper naming and sizing
function UIFramework:CreateScrollFrame(parent, width, height, scrollBarWidth, name)
    scrollBarWidth = scrollBarWidth or 20
    local frameName = name or self:GetUniqueFrameName("ScrollFrame")

    local scrollFrame = CreateFrame("ScrollFrame", frameName, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width, height)
    scrollFrame:SetPoint("TOPLEFT")

    -- Create scroll child with proper width calculation
    local scrollChild = CreateFrame("Frame", frameName .. "Child", scrollFrame)
    scrollChild:SetSize(width - scrollBarWidth, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = FizzureCommon:Clamp(current - (delta * 30), 0, maxScroll)
        self:SetVerticalScroll(newScroll)
    end)

    function scrollFrame:UpdateScrollChildHeight()
        local maxBottom = 0
        for i = 1, scrollChild:GetNumChildren() do
            local child = select(i, scrollChild:GetChildren())
            if child and child:IsShown() then
                local _, _, _, _, bottom = child:GetPoint()
                if bottom and math.abs(bottom) > maxBottom then
                    maxBottom = math.abs(bottom)
                end
            end
        end
        scrollChild:SetHeight(math.max(maxBottom + 20, height))
    end

    scrollFrame.content = scrollChild
    return scrollFrame
end

-- FIXED: Button creation with proper text handling and naming
function UIFramework:CreateButton(parent, buttonText, width, height, onClick, flatDesign)
    local buttonName = self:GetUniqueFrameName("Button")
    local button

    if flatDesign then
        button = CreateFrame("Button", buttonName, parent)
        button:SetSize(width or 80, height or 22)

        -- Flat design styling
        button:SetBackdrop(CreateFlatBackdrop())
        button:SetBackdropColor(unpack(FLAT_COLORS.accent))
        button:SetBackdropBorderColor(unpack(FLAT_COLORS.border))

        -- FIXED: Text handling - avoid variable name collision
        local textString = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        textString:SetAllPoints()
        textString:SetText(buttonText or "Button")
        textString:SetTextColor(1, 1, 1, 1)
        button.textString = textString

        -- Hover effect
        button:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.3, 0.7, 1, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(FLAT_COLORS.accent))
        end)

        -- FIXED: SetText method
        function button:SetText(newText)
            self.textString:SetText(newText or "")
        end

        function button:GetText()
            return self.textString:GetText()
        end
    else
        button = CreateFrame("Button", buttonName, parent, "UIPanelButtonTemplate")
        button:SetSize(width or 80, height or 22)
        button:SetText(buttonText or "Button")

        -- Fix text positioning for standard buttons
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetPoint("CENTER", 0, 0)
        end
    end

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    return button
end

-- FIXED: Checkbox with proper naming and flat design
function UIFramework:CreateCheckBox(parent, labelText, checked, onChange, flatDesign)
    local container = self:CreateFrame("Frame", self:GetUniqueFrameName("CheckContainer"), parent)
    container:SetSize(200, 20)

    local checkBox
    if flatDesign then
        checkBox = CreateFrame("Button", self:GetUniqueFrameName("CheckBox"), container)
        checkBox:SetSize(16, 16)
        checkBox:SetPoint("LEFT")

        checkBox:SetBackdrop(CreateFlatBackdrop())
        checkBox:SetBackdropColor(0.2, 0.2, 0.2, 1)
        checkBox:SetBackdropBorderColor(unpack(FLAT_COLORS.border))

        -- Check mark
        local checkMark = checkBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        checkMark:SetAllPoints()
        checkMark:SetText("")
        checkMark:SetTextColor(unpack(FLAT_COLORS.success))
        checkBox.checkMark = checkMark

        checkBox.checked = checked or false

        function checkBox:SetChecked(value)
            self.checked = value
            self.checkMark:SetText(value and "✓" or "")
        end

        function checkBox:GetChecked()
            return self.checked
        end

        checkBox:SetScript("OnClick", function(self)
            self:SetChecked(not self:GetChecked())
            if onChange then
                onChange(self:GetChecked())
            end
        end)

        checkBox:SetChecked(checked)
    else
        checkBox = CreateFrame("CheckButton", self:GetUniqueFrameName("CheckButton"), container, "UICheckButtonTemplate")
        checkBox:SetPoint("LEFT")
        checkBox:SetSize(20, 20)
        checkBox:SetChecked(checked or false)

        if onChange then
            checkBox:SetScript("OnClick", function()
                onChange(checkBox:GetChecked())
            end)
        end
    end

    local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", checkBox, "RIGHT", 5, 0)
    label:SetText(labelText or "")
    label:SetTextColor(unpack(FLAT_COLORS.text))

    container.checkBox = checkBox
    container.label = label

    -- Container methods
    function container:SetChecked(value)
        self.checkBox:SetChecked(value)
    end

    function container:GetChecked()
        return self.checkBox:GetChecked()
    end

    function container:SetText(text)
        self.label:SetText(text)
        self:SetWidth(self.label:GetStringWidth() + 30)
    end

    container:SetWidth(label:GetStringWidth() + 30)
    return container
end

-- FIXED: Edit box with proper naming and flat design
function UIFramework:CreateEditBox(parent, width, height, onEnter, onTextChanged, flatDesign)
    local editBoxName = self:GetUniqueFrameName("EditBox")
    local editBox

    if flatDesign then
        editBox = CreateFrame("EditBox", editBoxName, parent)
        editBox:SetSize(width or 100, height or 20)
        editBox:SetAutoFocus(false)

        editBox:SetBackdrop(CreateFlatBackdrop())
        editBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
        editBox:SetBackdropBorderColor(unpack(FLAT_COLORS.border))

        editBox:SetFontObject("GameFontNormal")
        editBox:SetTextColor(unpack(FLAT_COLORS.text))
        editBox:SetTextInsets(5, 5, 0, 0)
    else
        editBox = CreateFrame("EditBox", editBoxName, parent, "InputBoxTemplate")
        editBox:SetSize(width or 100, height or 20)
        editBox:SetAutoFocus(false)
    end

    if onEnter then
        editBox:SetScript("OnEnterPressed", function(self)
            onEnter(self:GetText())
            self:ClearFocus()
        end)
    end

    if onTextChanged then
        editBox:SetScript("OnTextChanged", onTextChanged)
    end

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return editBox
end

-- FIXED: Slider with proper naming and flat design
function UIFramework:CreateSlider(parent, sliderName, min, max, value, step, onChange, flatDesign)
    local slider

    if flatDesign then
        slider = CreateFrame("Slider", self:GetUniqueFrameName("Slider"), parent)
        slider:SetSize(200, 20)
        slider:SetMinMaxValues(min or 0, max or 100)
        slider:SetValue(value or min or 0)
        slider:SetValueStep(step or 1)

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

        -- Labels
        if sliderName then
            local nameLabel = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            nameLabel:SetPoint("BOTTOM", slider, "TOP", 0, 5)
            nameLabel:SetText(sliderName)
            nameLabel:SetTextColor(unpack(FLAT_COLORS.text))
        end

        local lowLabel = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lowLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -5)
        lowLabel:SetText(tostring(min or 0))
        lowLabel:SetTextColor(unpack(FLAT_COLORS.text))

        local highLabel = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        highLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -5)
        highLabel:SetText(tostring(max or 100))
        highLabel:SetTextColor(unpack(FLAT_COLORS.text))
    else
        slider = CreateFrame("Slider", self:GetUniqueFrameName("Slider"), parent, "OptionsSliderTemplate")
        slider:SetMinMaxValues(min or 0, max or 100)
        slider:SetValue(value or min or 0)
        slider:SetValueStep(step or 1)
        slider:SetWidth(200)
        slider:SetHeight(20)

        if sliderName then
            _G[slider:GetName() .. "Text"]:SetText(sliderName)
        end

        _G[slider:GetName() .. "Low"]:SetText(tostring(min or 0))
        _G[slider:GetName() .. "High"]:SetText(tostring(max or 100))
    end

    if onChange then
        slider:SetScript("OnValueChanged", onChange)
    end

    return slider
end

-- FIXED: Status bar with proper naming
function UIFramework:CreateStatusBar(parent, width, height, min, max, value, flatDesign)
    local bar = CreateFrame("StatusBar", self:GetUniqueFrameName("StatusBar"), parent)
    bar:SetSize(width or 100, height or 20)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(min or 0, max or 100)
    bar:SetValue(value or 0)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    bar.bg = bg

    -- Border
    if flatDesign then
        bar:SetBackdrop(CreateFlatBackdrop())
        bar:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        bar:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    -- Text overlay
    local textOverlay = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textOverlay:SetPoint("CENTER", 0, 0)
    textOverlay:SetTextColor(unpack(FLAT_COLORS.text))
    bar.textOverlay = textOverlay

    function bar:SetText(str)
        self.textOverlay:SetText(str)
    end

    return bar
end

-- FIXED: Generic item slot with proper naming
function UIFramework:CreateItemSlot(parent, index, onRightClick, onDrop, tooltip, flatDesign)
    local slot = CreateFrame("Button", self:GetUniqueFrameName("ItemSlot"), parent)
    slot:SetSize(40, 40)

    if flatDesign then
        slot:SetBackdrop(CreateFlatBackdrop())
        slot:SetBackdropColor(0.1, 0.1, 0.1, 1)
        slot:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-White")
        slot:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    end

    -- Item texture
    local texture = slot:CreateTexture(nil, "ARTWORK")
    texture:SetSize(36, 36)
    texture:SetPoint("CENTER")
    slot.texture = texture

    -- Count text
    local countText = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -2, 2)
    countText:SetTextColor(unpack(FLAT_COLORS.text))
    slot.countText = countText

    -- Click handling
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        if button == "RightButton" and onRightClick then
            onRightClick(index, self)
        end
    end)

    -- Drag and drop
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnReceiveDrag", function(self)
        if onDrop then
            onDrop(index, self)
        end
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip and tooltip.empty or "Empty Slot")
            GameTooltip:AddLine(tooltip and tooltip.instruction or "Drag item here", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)

    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Helper methods
    function slot:SetItem(itemName, itemLink)
        self.itemName = itemName
        self.itemLink = itemLink or itemName

        if itemName then
            -- Multiple approaches to get item icon
            local itemIcon = nil

            -- Try GetItemIcon first
            if GetItemIcon then
                itemIcon = GetItemIcon(itemName)
            end

            -- Try from item info
            if not itemIcon then
                local info = {GetItemInfo(itemName)}
                if info and info[10] then
                    itemIcon = info[10]
                end
            end

            -- Try from link if available
            if not itemIcon and itemLink and itemLink ~= itemName then
                local info = {GetItemInfo(itemLink)}
                if info and info[10] then
                    itemIcon = info[10]
                end
            end

            -- Set the texture
            if itemIcon then
                self.texture:SetTexture(itemIcon)
            else
                -- Use a default food icon
                self.texture:SetTexture("Interface\\Icons\\INV_Misc_Food_01")
            end
            self.texture:Show()

            -- Update count
            local count = FizzureCommon:GetItemCount(itemName)
            if count and count > 1 then
                self.countText:SetText(count)
                self.countText:Show()
            else
                self.countText:SetText("")
                self.countText:Hide()
            end
        else
            self:ClearItem()
        end
    end

    function slot:ClearItem()
        self.itemName = nil
        self.itemLink = nil
        self.texture:SetTexture(nil)
        self.texture:Hide()
        self.countText:SetText("")
        self.countText:Hide()
    end

    slot.index = index
    return slot
end

-- Dropdown menu (unchanged - works well)
function UIFramework:CreateDropdown(parent, width, items, onSelect)
    local dropdown = CreateFrame("Frame", self:GetUniqueFrameName("Dropdown"), parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width or 120)

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for i, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text or item
            info.value = item.value or item
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, info.value)
                if onSelect then
                    onSelect(info.value)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return dropdown
end

-- FIXED: Status frame with proper naming
function UIFramework:CreateStatusFrame(name, title, width, height, flatDesign)
    local frameName = name or self:GetUniqueFrameName("StatusFrame")
    local frame = self:CreateFrame("Frame", frameName, UIParent)
    frame:SetSize(width or 200, height or 140)
    frame:SetPoint("TOPLEFT", 20, -100)

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

    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    if title then
        local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleText:SetPoint("TOP", 0, -8)
        titleText:SetText(title)
        titleText:SetTextColor(unpack(FLAT_COLORS.text))
        frame.titleText = titleText
    end

    return frame
end

-- Text label with flat design colors
function UIFramework:CreateLabel(parent, labelText, fontSize)
    local fontString = parent:CreateFontString(nil, "ARTWORK", fontSize or "GameFontNormal")
    fontString:SetText(labelText or "")
    fontString:SetTextColor(unpack(FLAT_COLORS.text))
    return fontString
end

-- Separator line with flat design
function UIFramework:CreateSeparator(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(width or parent:GetWidth() - 20, 1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(unpack(FLAT_COLORS.border))
    return line
end

-- FIXED: Notification toast with proper naming
function UIFramework:ShowToast(toastText, duration, toastType)
    duration = duration or 3

    local toast = self:CreateFrame("Frame", self:GetUniqueFrameName("Toast"), UIParent)
    toast:SetSize(300, 60)
    toast:SetPoint("TOP", 0, -100)

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

    -- Fade in
    toast:SetAlpha(0)
    toast:Show()

    local fadeIn = toast:CreateAnimationGroup()
    local alpha1 = fadeIn:CreateAnimation("Alpha")
    alpha1:SetChange(1)
    alpha1:SetDuration(0.2)
    fadeIn:Play()

    -- Auto hide
    FizzureCommon:After(duration, function()
        local fadeOut = toast:CreateAnimationGroup()
        local alpha2 = fadeOut:CreateAnimation("Alpha")
        alpha2:SetChange(-1)
        alpha2:SetDuration(0.5)
        fadeOut:Play()

        fadeOut:SetScript("OnFinished", function()
            toast:Hide()
        end)
    end)

    return toast
end

-- FIXED: Context menu with proper naming
function UIFramework:CreateContextMenu(parent, items, flatDesign)
    local menu = self:CreateFrame("Frame", self:GetUniqueFrameName("ContextMenu"), parent)

    if flatDesign then
        menu:SetBackdrop(CreateFlatBackdrop())
        menu:SetBackdropColor(unpack(FLAT_COLORS.background))
        menu:SetBackdropBorderColor(unpack(FLAT_COLORS.border))
    else
        menu:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        menu:SetBackdropColor(0, 0, 0, 0.9)
    end

    menu:SetFrameStrata("DIALOG")
    menu:Hide()

    local height = 10
    local maxWidth = 100

    for i, item in ipairs(items) do
        local menuButton = self:CreateButton(menu, item.text, 0, 20, item.func, flatDesign)
        menuButton:SetPoint("TOPLEFT", 5, -height)
        menuButton:SetPoint("RIGHT", -5, 0)

        local textWidth = menuButton:GetText() and string.len(menuButton:GetText()) * 8 + 20 or 100
        if textWidth > maxWidth then
            maxWidth = textWidth
        end

        height = height + 22
    end

    menu:SetSize(maxWidth + 10, height)

    -- Auto-hide on click outside
    menu:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self)
            if not MouseIsOver(self) then
                self:Hide()
                self:SetScript("OnUpdate", nil)
            end
        end)
    end)

    return menu
end

-- Tab system with flat design option
function UIFramework:CreateTabPanel(parent, tabs, flatDesign)
    local tabPanel = self:CreateFrame("Frame", self:GetUniqueFrameName("TabPanel"), parent)
    tabPanel:SetAllPoints()

    tabPanel.tabs = {}
    tabPanel.contents = {}
    tabPanel.selectedTab = 1

    local tabHeight = 32
    local tabWidth = math.min(120, parent:GetWidth() / #tabs)

    for i, tabInfo in ipairs(tabs) do
        -- Tab button
        local tab = self:CreateButton(tabPanel, tabInfo.name, tabWidth, tabHeight, nil, flatDesign)
        tab:SetPoint("TOPLEFT", (i - 1) * tabWidth, 0)

        -- Tab content
        local content = self:CreateFrame("Frame", self:GetUniqueFrameName("TabContent"), tabPanel)
        content:SetPoint("TOPLEFT", 0, -tabHeight - 5)
        content:SetPoint("BOTTOMRIGHT")
        content:Hide()

        tab:SetScript("OnClick", function()
            tabPanel:SelectTab(i)
        end)

        tabPanel.tabs[i] = tab
        tabPanel.contents[i] = content

        if tabInfo.onCreate then
            tabInfo.onCreate(content)
        end
    end

    function tabPanel:SelectTab(index)
        for i, content in ipairs(self.contents) do
            content:Hide()
        end

        for i, tab in ipairs(self.tabs) do
            if flatDesign then
                if i == index then
                    tab:SetBackdropColor(unpack(FLAT_COLORS.accent))
                else
                    tab:SetBackdropColor(0.2, 0.2, 0.2, 1)
                end
            else
                tab:SetAlpha(i == index and 1 or 0.7)
            end
        end

        self.contents[index]:Show()
        self.selectedTab = index
    end

    tabPanel:SelectTab(1)
    return tabPanel
end

print("|cff00ff00Fizzure|r UI Framework loaded with FIXES for WoW 3.3.5")