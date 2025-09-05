-- UIFramework.lua - GUI system for Fizzure modules
local UIFramework = {}
_G.FizzureUI = UIFramework

-- Frame pool for performance
UIFramework.framePool = {}
UIFramework.activeFrames = {}

-- Base frame creation
function UIFramework:CreateFrame(frameType, name, parent, template)
    local frame = CreateFrame(frameType or "Frame", name, parent or UIParent, template)

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

-- Window creation with proper frame structure
function UIFramework:CreateWindow(name, title, width, height, parent)
    local frame = self:CreateFrame("Frame", name, parent)
    frame:SetSize(width or 400, height or 300)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
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
    local titleBar = self:CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 12, -12)
    titleBar:SetPoint("TOPRIGHT", -12, -12)

    local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", 0, 0)
    titleText:SetText(title or "")
    frame.titleText = titleText
    frame.titleBar = titleBar

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.closeBtn = closeBtn

    -- Content area - properly positioned below title bar
    local content = self:CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -44)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    frame.content = content

    return frame
end

-- Panel creation
function UIFramework:CreatePanel(parent, width, height, anchor)
    local panel = self:CreateFrame("Frame", nil, parent)
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

    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

    return panel
end

-- Status frame with proper layering
function UIFramework:CreateStatusFrame(name, title, width, height)
    local frame = self:CreateFrame("Frame", name, UIParent)
    frame:SetSize(width or 200, height or 140)
    frame:SetPoint("TOPLEFT", 20, -100)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
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
        frame.titleText = titleText
    end

    return frame
end

-- Scroll frame with corrected sizing and positioning
function UIFramework:CreateScrollFrame(parent, width, height, scrollBarWidth, name)
    scrollBarWidth = scrollBarWidth or 20
    name = name or ((parent:GetName() or "FizzureParent") .. "_Scroll")

    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width, height)
    scrollFrame:SetPoint("TOPLEFT")

    -- Create scroll child with proper width calculation
    local scrollChild = CreateFrame("Frame", name .. "Child", scrollFrame)
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

-- Button creation with proper styling
function UIFramework:CreateButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, height or 22)
    button:SetText(text or "")

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    -- Fix text positioning
    local fontString = button:GetFontString()
    if fontString then
        fontString:SetPoint("CENTER", 0, 0)
    end

    return button
end

-- Checkbox with label
function UIFramework:CreateCheckBox(parent, text, checked, onChange)
    local container = self:CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)

    local checkBox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    checkBox:SetPoint("LEFT")
    checkBox:SetSize(20, 20)
    checkBox:SetChecked(checked or false)

    local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", checkBox, "RIGHT", 5, 0)
    label:SetText(text or "")

    container.checkBox = checkBox
    container.label = label

    container.SetChecked = function(self, value)
        self.checkBox:SetChecked(value)
    end

    container.GetChecked = function(self)
        return self.checkBox:GetChecked()
    end

    container.SetText = function(self, text)
        self.label:SetText(text)
        self:SetWidth(self.label:GetStringWidth() + 30)
    end

    if onChange then
        checkBox:SetScript("OnClick", function()
            onChange(checkBox:GetChecked())
        end)
    end

    container:SetWidth(label:GetStringWidth() + 30)

    return container
end

-- Edit box with proper background
function UIFramework:CreateEditBox(parent, width, height, onEnter, onTextChanged)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width or 100, height or 20)
    editBox:SetAutoFocus(false)

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

-- Status bar with text overlay
function UIFramework:CreateStatusBar(parent, width, height, min, max, value)
    local bar = CreateFrame("StatusBar", nil, parent)
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
    bar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Text overlay
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 0)
    bar.text = text

    function bar:SetText(str)
        self.text:SetText(str)
    end

    return bar
end

-- Generic item slot for modules to use (replaces CreateFoodSlot)
function UIFramework:CreateItemSlot(parent, index, onRightClick, onDrop, tooltip)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(40, 40)
    slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-White")
    slot:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    -- Item texture
    local texture = slot:CreateTexture(nil, "ARTWORK")
    texture:SetSize(36, 36)
    texture:SetPoint("CENTER")
    slot.texture = texture

    -- Count text
    local countText = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -2, 2)
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

-- Dropdown menu
function UIFramework:CreateDropdown(parent, width, items, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
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

-- Slider
function UIFramework:CreateSlider(parent, name, min, max, value, step, onChange)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValue(value or min or 0)
    slider:SetValueStep(step or 1)
    slider:SetWidth(200)
    slider:SetHeight(20)

    if name then
        _G[slider:GetName() .. "Text"]:SetText(name)
    end

    _G[slider:GetName() .. "Low"]:SetText(tostring(min or 0))
    _G[slider:GetName() .. "High"]:SetText(tostring(max or 100))

    if onChange then
        slider:SetScript("OnValueChanged", onChange)
    end

    return slider
end

-- Tab system with proper layout
function UIFramework:CreateTabPanel(parent, tabs)
    local tabPanel = self:CreateFrame("Frame", nil, parent)
    tabPanel:SetAllPoints()

    tabPanel.tabs = {}
    tabPanel.contents = {}
    tabPanel.selectedTab = 1

    local tabHeight = 32
    local tabWidth = math.min(120, parent:GetWidth() / #tabs)

    for i, tabInfo in ipairs(tabs) do
        -- Tab button
        local tab = self:CreateButton(tabPanel, tabInfo.name, tabWidth, tabHeight)
        tab:SetPoint("TOPLEFT", (i - 1) * tabWidth, 0)

        -- Tab content
        local content = self:CreateFrame("Frame", nil, tabPanel)
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
            tab:SetAlpha(0.7)
        end

        self.contents[index]:Show()
        self.tabs[index]:SetAlpha(1)
        self.selectedTab = index
    end

    tabPanel:SelectTab(1)
    return tabPanel
end

-- Text label
function UIFramework:CreateLabel(parent, text, fontSize)
    local fontString = parent:CreateFontString(nil, "ARTWORK", fontSize or "GameFontNormal")
    fontString:SetText(text or "")
    return fontString
end

-- Separator line
function UIFramework:CreateSeparator(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(width or parent:GetWidth() - 20, 1)
    line:SetTexture(1, 1, 1, 0.2)
    return line
end

-- Notification toast
function UIFramework:ShowToast(text, duration, type)
    duration = duration or 3

    local toast = self:CreateFrame("Frame", nil, UIParent)
    toast:SetSize(300, 60)
    toast:SetPoint("TOP", 0, -100)
    toast:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })

    local colors = {
        success = {0.2, 0.8, 0.2},
        error = {0.8, 0.2, 0.2},
        warning = {0.8, 0.8, 0.2},
        info = {0.2, 0.6, 1}
    }

    local color = colors[type] or colors.info
    toast:SetBackdropColor(color[1], color[2], color[3], 0.9)

    local message = toast:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    message:SetPoint("CENTER")
    message:SetText(text)

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

-- Context menu
function UIFramework:CreateContextMenu(parent, items)
    local menu = self:CreateFrame("Frame", nil, parent)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:SetFrameStrata("DIALOG")
    menu:Hide()

    local height = 10
    local maxWidth = 100

    for i, item in ipairs(items) do
        local button = self:CreateButton(menu, item.text, 0, 20, item.func)
        button:SetPoint("TOPLEFT", 5, -height)
        button:SetPoint("RIGHT", -5, 0)

        local textWidth = button:GetFontString():GetStringWidth() + 20
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

print("|cff00ff00Fizzure|r UI Framework loaded")