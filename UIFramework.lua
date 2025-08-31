-- UIFramework.lua - Reusable UI Components for Fizzure Modules
-- Provides common UI patterns and helpers

local UIFramework = {}
_G.FizzureUI = UIFramework

-- Frame creation helpers
function UIFramework:CreateWindow(name, title, width, height, parent)
    local frame = CreateFrame("Frame", name, parent or UIParent)
    frame:SetSize(width or 400, height or 300)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Title
    if title then
        local titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        titleText:SetPoint("TOP", 0, -20)
        titleText:SetText(title)
        frame.titleText = titleText
    end

    return frame
end

function UIFramework:CreateStatusFrame(name, title, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width or 200, height or 140)
    frame:SetPoint("TOPLEFT", 20, -100)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Title bar
    if title then
        local titleBar = CreateFrame("Frame", nil, frame)
        titleBar:SetSize(width or 200, 20)
        titleBar:SetPoint("TOP", 0, 0)

        local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        titleText:SetPoint("LEFT", 8, 0)
        titleText:SetText(title)
        frame.titleText = titleText
    end

    return frame
end

-- Button helpers
function UIFramework:CreateButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, height or 22)
    button:SetText(text or "Button")

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    return button
end

function UIFramework:CreateCheckBox(parent, text, checked, onChange)
    local checkBox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkBox:SetSize(20, 20)
    checkBox:SetChecked(checked or false)

    if text then
        local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", checkBox, "RIGHT", 5, 0)
        label:SetText(text)
        checkBox.label = label
    end

    if onChange then
        checkBox:SetScript("OnClick", function()
            onChange(checkBox:GetChecked())
        end)
    end

    return checkBox
end

-- Input helpers
function UIFramework:CreateEditBox(parent, width, height, onEnter)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width or 100, height or 20)
    editBox:SetAutoFocus(false)

    if onEnter then
        editBox:SetScript("OnEnterPressed", function(self)
            onEnter(self:GetText())
            self:ClearFocus()
        end)
    end

    return editBox
end

-- List helpers
function UIFramework:CreateScrollList(parent, width, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width or 200, height or 150)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(width or 200, height or 150)
    scrollFrame:SetScrollChild(content)

    scrollFrame.content = content
    scrollFrame.items = {}

    -- Helper function to add items
    function scrollFrame:AddItem(itemFrame)
        table.insert(self.items, itemFrame)
        itemFrame:SetParent(self.content)
        self:UpdateLayout()
    end

    -- Helper function to clear items
    function scrollFrame:ClearItems()
        for _, item in ipairs(self.items) do
            item:Hide()
        end
        self.items = {}
        self:UpdateLayout()
    end

    -- Layout manager
    function scrollFrame:UpdateLayout()
        local yOffset = 0
        for i, item in ipairs(self.items) do
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 0, yOffset)
            yOffset = yOffset - (item:GetHeight() + 2)
            item:Show()
        end

        self.content:SetHeight(math.max(height or 150, -yOffset))
    end

    return scrollFrame
end

-- Food slot helper specifically for hunter module
function UIFramework:CreateFoodSlot(parent, index, onRightClick)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(40, 40)

    -- Background
    slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-White")
    slot:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    -- Item texture
    local texture = slot:CreateTexture(nil, "ARTWORK")
    texture:SetSize(32, 32)
    texture:SetPoint("CENTER")
    slot.texture = texture

    -- Click handling
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        if button == "RightButton" and onRightClick then
            onRightClick(index)
        end
    end)

    -- Drag and drop
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnReceiveDrag", function(self)
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            local itemName = GetItemInfo(itemLink)
            if itemName then
                self:SetItem(itemName, itemLink)
                ClearCursor()
            end
        end
    end)

    -- Tooltip
    slot:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:AddLine("Right-click to remove", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Empty Food Slot")
            GameTooltip:AddLine("Drag food item here", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)

    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Helper methods
    function slot:SetItem(itemName, itemLink)
        self.itemName = itemName
        self.itemLink = itemLink
        local itemTexture = GetItemIcon(itemName) or GetItemIcon(itemLink)
        self.texture:SetTexture(itemTexture)
    end

    function slot:ClearItem()
        self.itemName = nil
        self.itemLink = nil
        self.texture:SetTexture(nil)
    end

    slot.index = index
    return slot
end

-- Notification system helper
function UIFramework:ShowTooltipNotification(text, duration)
    UIErrorsFrame:AddMessage(text, 1, 1, 0, 1, duration or 3)
end

-- Debug helpers
function UIFramework:CreateDebugPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width or 300, height or 200)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width - 30, height - 10)
    scrollFrame:SetPoint("CENTER")

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(width - 30, height - 10)
    scrollFrame:SetScrollChild(content)

    panel.scrollFrame = scrollFrame
    panel.content = content
    panel.lines = {}

    function panel:AddLine(text, color)
        local line = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", 5, -#self.lines * 12)
        line:SetSize(self.content:GetWidth() - 10, 12)
        line:SetJustifyH("LEFT")
        line:SetText(text)

        if color then
            line:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
        end

        table.insert(self.lines, line)

        -- Update content height
        self.content:SetHeight(math.max(self:GetHeight() - 10, #self.lines * 12))

        -- Auto-scroll to bottom
        self.scrollFrame:SetVerticalScroll(math.max(0, self.content:GetHeight() - self.scrollFrame:GetHeight()))
    end

    function panel:Clear()
        for _, line in ipairs(self.lines) do
            line:Hide()
        end
        self.lines = {}
        self.content:SetHeight(self:GetHeight() - 10)
    end

    return panel
end

-- Utility functions
function UIFramework:GetColorForType(type)
    local colors = {
        warning = {1, 0.8, 0},
        error = {1, 0.3, 0.3},
        info = {0.3, 0.8, 1},
        success = {0.3, 1, 0.3},
        debug = {0.7, 0.7, 0.7}
    }
    return colors[type] or colors.info
end

function UIFramework:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

print("|cff00ff00Fizzure|r UI Framework Loaded")