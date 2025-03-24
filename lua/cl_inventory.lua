local inventoryPanel
local inventoryGridSizeX, inventoryGridSizeY = 15, 15
local cellSize = 52
local inventoryColor = Color(50, 50, 50, 200)
local gridLineColor = Color(255, 255, 255, 50)
local itemColor = Color(100, 100, 255, 200)
local hoveredItem = nil
local tooltipWidth = 200
local tooltipPadding = 8
local draggingItem = nil
local dragOffsetX, dragOffsetY = 0, 0
local lastRightClickTime = 0
local rightClickCooldown = 0.5
local dragStartTime = 0
local dragDelay = 0
local HOTSLOT_COUNT = 5
local HOTSLOT_SIZE = 64
local HOTSLOT_MARGIN = 10
local HOTKEYS = {KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5}
local hotSlotCooldowns = {}
local TOOLTIP_OFFSET = -100
local TOOLTIP_MAX_WIDTH = 300
local HOTSLOT_HOVER_COLOR = Color(255, 255, 255, 50)
local HOTSLOT_DEFAULT_COLOR = Color(200, 200, 200, 150)
local EQUIPMENT_SLOTS = {
    {
        Type = "PRIMARY_WEAPON",
        Name = "Основное оружие",
        Pos = {x = 275, y = 50},
        Size = {w = 100, h = 305},
        Color = Color(80, 80, 80)
    },
    {
        Type = "SECONDARY_WEAPON",
        Name = "Пистолет",
        Pos = {x = 10, y = 60},
        Size = {w = 100, h = 35},
        Color = Color(70, 70, 70)
    },
    {
        Type = "ARMOR",
        Name = "Броня",
        Pos = {x = 10, y = 110},
        Size = {w = 110, h = 110},
        Color = Color(60, 90, 120)
    }
}

local function WrapText(text, font, maxWidth)
    surface.SetFont(font)
    local words = string.Explode(" ", text)
    local wrappedText = ""
    local line = ""

    for _, word in ipairs(words) do
        local testLine = line .. (line == "" and "" or " ") .. word
        local testWidth = surface.GetTextSize(testLine)

        if testWidth > maxWidth then
            wrappedText = wrappedText .. (wrappedText == "" and "" or "\n") .. line
            line = word
        else
            line = testLine
        end
    end

    wrappedText = wrappedText .. (wrappedText == "" and "" or "\n") .. line
    return wrappedText
end

local function AdjustTooltipPosition(x, y, w, h)
    local scrW, scrH = ScrW(), ScrH()

    if x + w > scrW then
        x = x - w - TOOLTIP_OFFSET * 2
    end

    if y + h > scrH then
        y = y - h - TOOLTIP_OFFSET
    end

    return x, y
end

local hotSlots = {}
for i = 1, HOTSLOT_COUNT do
    hotSlots[i] = {
        item = nil,
        posX = ScrW()/2 - (HOTSLOT_SIZE * HOTSLOT_COUNT + HOTSLOT_MARGIN * (HOTSLOT_COUNT-1))/2 + (i-1)*(HOTSLOT_SIZE + HOTSLOT_MARGIN),
        posY = ScrH() - 100
    }
end

net.Receive("StalMod_UpdateHotSlots", function()
    local slots = net.ReadTable()
    for i = 1, 5 do
        hotSlots[i].item = slots[i]
    end
end)

function AssignToHotSlot(slotIndex, itemData)
    if not hotSlots[slotIndex] then return end

    local item = StalMod.Inventory.Items[itemData.id]
    if not item or not item.Usable then
        LocalPlayer():ChatPrint("Этот предмет нельзя назначить в слот")
        return
    end

    for i, slot in ipairs(hotSlots) do
        if slot.item and slot.item.id == itemData.id then
            LocalPlayer():ChatPrint("Этот тип предмета уже в слоте F"..i)
            return
        end
    end

    if hotSlots[slotIndex].item then
        LocalPlayer():ChatPrint("Слот F"..slotIndex.." занят")
        return
    end

    net.Start("StalMod_AssignHotSlot")
        net.WriteUInt(slotIndex, 8)
        net.WriteString(itemData.uniqueID)
    net.SendToServer()
end

local lastHotSlotUse = 0
function UseHotSlot(slotIndex)
    if hotSlotCooldowns[slotIndex] and hotSlotCooldowns[slotIndex] > CurTime() then
        LocalPlayer():ChatPrint("Этот слот в кулдауне!")
        return
    end

    if CurTime() - lastHotSlotUse < 0.5 then return end
    lastHotSlotUse = CurTime()

    net.Start("StalMod_UseHotSlot")
        net.WriteUInt(slotIndex, 8)
    net.SendToServer()
end

local function OpenContextMenu(itemData)
    local menu = DermaMenu()
    menu:AddOption("Использовать", function()
        net.Start("StalMod_UseItem")
        net.WriteString(itemData.uniqueID)
        net.SendToServer()
    end):SetIcon("icon16/bullet_go.png")

    if StalMod.Inventory.Items[itemData.id].Stackable and itemData.amount > 1 then
        menu:AddOption("Разделить стак", function()
            Derma_StringRequest(
                "Разделение стака",
                "Введите количество (1-" .. (itemData.amount - 1) .. "):",
                "",
                function(text)
                    local amount = tonumber(text)
                    if amount and amount > 0 and amount < itemData.amount then
                        net.Start("StalMod_SplitStack")
                        net.WriteString(itemData.uniqueID)
                        net.WriteUInt(amount, 16)
                        net.SendToServer()
                    else
                        LocalPlayer():ChatPrint("Некорректное количество!")
                    end
                end
            )
        end):SetIcon("icon16/arrow_divide.png")
    end

    local itemInfo = StalMod.Inventory.Items[itemData.id]
    if itemInfo and itemInfo.Usable then
        local selector = menu:AddSubMenu("Снарядить")
        for i = 1, HOTSLOT_COUNT do
            selector:AddOption("Слот " .. i, function()
                AssignToHotSlot(i, itemData)
            end)
        end
    end

    if itemInfo and itemInfo.EquipData then
        menu:AddOption("Экипировать", function()
            net.Start("StalMod_EquipItem")
                net.WriteString(itemData.uniqueID)
                net.WriteString(itemInfo.EquipData.slotType)
            net.SendToServer()
        end):SetIcon("icon16/star.png")
    end

    menu:AddOption("Выкинуть", function()
        net.Start("StalMod_DropItem")
        net.WriteString(itemData.uniqueID)
        net.SendToServer()
    end):SetIcon("icon16/delete.png")

    menu:Open()
end

local function DrawInventoryGrid(panel)
    for i = 0, inventoryGridSizeX do
        local x = i * cellSize
        surface.SetDrawColor(gridLineColor)
        surface.DrawLine(x, 0, x, inventoryGridSizeY * cellSize)
    end

    for i = 0, inventoryGridSizeY do
        local y = i * cellSize
        surface.SetDrawColor(gridLineColor)
        surface.DrawLine(0, y, inventoryGridSizeX * cellSize, y)
    end
end

local function IsMouseInsideBounds(mouseX, mouseY, ix, iy, itemData)
    local item = StalMod.Inventory.Items[itemData.id]

    if not item then
        return false
    end

    local sizeX = item.SizeX or 1
    local sizeY = item.SizeY or 1

    local startX = (ix - 1) * cellSize
    local endX = startX + sizeX * cellSize
    local startY = (iy - 1) * cellSize
    local endY = startY + sizeY * cellSize

    return mouseX >= startX 
        and mouseX <= endX 
        and mouseY >= startY 
        and mouseY <= endY
end

local function UpdateInventoryGrid(oldPos, newPos, uniqueID, inv)
    local itemData = inv.Items[uniqueID]

    if not itemData then
        return
    end

    local sizeX, sizeY = itemData.SizeX, itemData.SizeY

    for j = 0, sizeY - 1 do
        for i = 0, sizeX - 1 do
            local x = oldPos.x + i
            local y = oldPos.y + j
            if inv.grid[x] and inv.grid[x][y] == uniqueID then
                inv.grid[x][y] = nil
            end
        end
    end

    for j = 0, sizeY - 1 do
        for i = 0, sizeX - 1 do
            local x = newPos.x + i
            local y = newPos.y + j
            inv.grid[x] = inv.grid[x] or {}
            inv.grid[x][y] = uniqueID
        end
    end

    itemData.pos.x = newPos.x
    itemData.pos.y = newPos.y
end

local function StartDragging(itemData, mouseX, mouseY)
    draggingItem = itemData
    dragOffsetX = mouseX - (itemData.pos.x - 1) * cellSize
    dragOffsetY = mouseY - (itemData.pos.y - 1) * cellSize
    dragStartTime = CurTime()
end

net.Receive("StalMod_UpdateInventory", function()
    local itemCount = net.ReadUInt(16)
    local items = {}

    for i = 1, itemCount do
        local id = net.ReadString()
        local uniqueID = net.ReadString()
        local posX = net.ReadInt(8)
        local posY = net.ReadInt(8)
        local amount = net.ReadInt(16)

        table.insert(items, {
            id = id,
            uniqueID = uniqueID,
            pos = {x = posX, y = posY},
            amount = amount
        })
    end

    if not LocalPlayer().Inventory then
        LocalPlayer().Inventory = StalMod.Inventory:New()
    end

    LocalPlayer().Inventory.items = items

    for _, itemData in ipairs(items) do
        UpdateInventoryGrid({x = 0, y = 0}, itemData.pos, itemData.uniqueID, LocalPlayer().Inventory)
    end
end)

net.Receive("StalMod_FullEquipmentUpdate", function()
    local ply = LocalPlayer()
    local equipmentData = net.ReadTable()

    plyEquipment = {}

    for slotType, itemData in pairs(equipmentData) do
        plyEquipment[slotType] = {
            itemID = itemData.itemID,
            uniqueID = itemData.uniqueID
        }
    end
end)

local function IsMouseInRect(x, y, w, h)
    local mx, my = gui.MousePos()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function DrawInventory(inventory, panel)
    surface.SetDrawColor(inventoryColor)
    surface.DrawRect(0, 0, inventoryGridSizeX * cellSize, inventoryGridSizeY * cellSize)

    DrawInventoryGrid(panel)

    local mouseX, mouseY = panel:ScreenToLocal(gui.MouseX(), gui.MouseY())
    local isDragging = draggingItem and input.IsMouseDown(MOUSE_LEFT)

    hoveredItem = nil
    for _, itemData in pairs(inventory:GetItems()) do
        if itemData then
            local item = StalMod.Inventory.Items[itemData.id]
            local IconMat = Material(item.IconMat)

            if not item then
                continue
            end
            local x, y = itemData.pos.x, itemData.pos.y

            if not isDragging or draggingItem.uniqueID ~= itemData.uniqueID then
                surface.SetDrawColor(Color(255, 255, 255))
                surface.SetMaterial(IconMat)
                surface.DrawTexturedRect((x - 1) * cellSize, (y - 1) * cellSize, item.SizeX * cellSize, item.SizeY * cellSize)
                surface.DrawOutlinedRect((x - 1) * cellSize, (y - 1) * cellSize, item.SizeX * cellSize, item.SizeY * cellSize, 0.9)

                if item.Stackable and itemData.amount > 1 then
                    draw.SimpleText(itemData.amount, "DermaDefaultBold", 
                        (x - 1) * cellSize + 5, 
                        (y - 1) * cellSize + 5, 
                        color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            end

            local isMouseInside = IsMouseInsideBounds(mouseX, mouseY, itemData.pos.x, itemData.pos.y, itemData)
            if isMouseInside then
                hoveredItem = {data = itemData, item = item, x = (itemData.pos.x - 1) * cellSize, y = (itemData.pos.y - 1) * cellSize}
            end
        end
    end

    if hoveredItem and not draggingItem then
        local mouseX, mouseY = panel:ScreenToLocal(gui.MouseX(), gui.MouseY())
        local text = Format("%s\n%s", hoveredItem.item.Name, hoveredItem.item.Desc)

        if hoveredItem.item.EffectsDesc then
            text = text .. "\n\nЭффекты:\n" .. hoveredItem.item.EffectsDesc
        end

        surface.SetFont("DermaDefaultBold")
        local tw, th = surface.GetTextSize(text)
        local padding = 8

        local panelW, panelH = panel:GetWide(), panel:GetTall()

        local tx = mouseX + 20
        local ty = mouseY + 20

        if tx + tw + padding > panelW then
            tx = mouseX - tw - padding - 20
        end

        if ty + th + padding > panelH then
            ty = mouseY - th - padding - 20
        end

        surface.SetDrawColor(Color(30, 30, 40, 240))
        surface.DrawRect(tx, ty, tw + padding*2, th + padding*2)
        draw.DrawText(text, "DermaDefaultBold", tx + padding, ty + padding, color_white, TEXT_ALIGN_LEFT)
        surface.SetDrawColor(Color(255, 255, 255, 50))
        surface.DrawOutlinedRect(tx, ty, tw + padding*2, th + padding*2)
    end

    if draggingItem and not input.IsMouseDown(MOUSE_LEFT) then
        for i, slot in ipairs(hotSlots) do
            if IsMouseInRect(slot.posX, slot.posY, HOTSLOT_SIZE, HOTSLOT_SIZE) then
                AssignToHotSlot(i, draggingItem)
                break
            end
        end
    end

    if not isDragging then
        for _, itemData in pairs(inventory:GetItems()) do
            if itemData then
                local item = StalMod.Inventory.Items[itemData.id]
                local isMouseInside = IsMouseInsideBounds(mouseX, mouseY, itemData.pos.x, itemData.pos.y, itemData)

                if input.IsMouseDown(MOUSE_LEFT) and hoveredItem and not draggingItem then
                    StartDragging(hoveredItem.data, mouseX, mouseY)
                end

                if input.IsMouseDown(MOUSE_RIGHT) and (CurTime() - lastRightClickTime > rightClickCooldown) then
                    if hoveredItem then
                        OpenContextMenu(hoveredItem.data)
                    end
                    lastRightClickTime = CurTime()
                end
            end
        end
    end

    if draggingItem and input.IsMouseDown(MOUSE_LEFT) then
        local item = StalMod.Inventory.Items[draggingItem.id]
        local IconMat = Material(item.IconMat)
        surface.SetDrawColor(Color(255, 255, 255, 0))
        surface.SetMaterial(IconMat)
        surface.DrawTexturedRect(mouseX - dragOffsetX, mouseY - dragOffsetY, item.SizeX * cellSize, item.SizeY * cellSize)
    end

    if draggingItem and not input.IsMouseDown(MOUSE_LEFT) then
        if dragStartTime > 0 and (CurTime() - dragStartTime >= dragDelay) then
            local item = StalMod.Inventory.Items[draggingItem.id]
            local newX = math.Clamp(math.floor((mouseX - dragOffsetX) / cellSize) + 1, 1, inventoryGridSizeX - (item.SizeX or 1) + 1)
            local newY = math.Clamp(math.floor((mouseY - dragOffsetY) / cellSize) + 1, 1, inventoryGridSizeY - (item.SizeY or 1) + 1)

            local targetStack
            for _, itemData in pairs(inventory:GetItems()) do
                if itemData and itemData.id == draggingItem.id 
                and itemData.uniqueID ~= draggingItem.uniqueID
                and IsMouseInsideBounds(mouseX, mouseY, itemData.pos.x, itemData.pos.y, itemData) then
                    targetStack = itemData
                    break
                end
            end

            if targetStack then
                net.Start("StalMod_MergeStacks")
                net.WriteString(draggingItem.uniqueID)
                net.WriteString(targetStack.uniqueID)
                net.SendToServer()
            else
                net.Start("StalMod_MoveItem")
                net.WriteString(draggingItem.uniqueID)
                net.WriteUInt(newX, 8)
                net.WriteUInt(newY, 8)
                net.SendToServer()
            end

            draggingItem = nil
            dragOffsetX, dragOffsetY = 0, 0
            dragStartTime = 0
        else
            draggingItem = nil
            dragOffsetX, dragOffsetY = 0, 0
            dragStartTime = 0
        end
    end
end

function EquipmentDrawSlot(slotType, panel, w, h, name)
    if not panel or not IsValid(panel) then return end

    local itemData = plyEquipment and plyEquipment[slotType]
    if itemData then
        local itemInfo = StalMod.Inventory.Items[itemData.itemID]
        if itemInfo then
            local mat = Material(itemInfo.IconMat or "error")
            if not mat:IsError() then
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255)
                surface.DrawTexturedRect(5, 5, w - 10, h - 10)
            else
                surface.SetDrawColor(100, 100, 255, 200)
                surface.DrawRect(5, 5, w - 10, h - 10)
                draw.SimpleText(itemInfo.Name or "?", "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(
                itemInfo.Name,
                "DermaDefaultBold",
                w / 2,
                h - 15,
                color_white,
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_BOTTOM
            )
        else
            draw.SimpleText("Ошибка", "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    else
        draw.SimpleText(name, "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

function EquipmentCreateSlots(parentFrame)
    if not IsValid(parentFrame) then return end
    local weaponPanel = vgui.Create("DPanel", parentFrame)
    weaponPanel:SetSize(100, 305)
    weaponPanel:SetPos(275, 50)
    weaponPanel.slotType = "PRIMARY_WEAPON"
    weaponPanel.Paint = function(self, w, h)
        EquipmentDrawSlot("PRIMARY_WEAPON", self, w, h, "Оружие")
    end
    weaponPanel.Think = function(self)
        if IsMouseInRect(1440, 215, 90, 295) then
            if input.IsMouseDown(MOUSE_RIGHT) and (CurTime() - lastRightClickTime > rightClickCooldown) then
                local menu = DermaMenu()
                menu:AddOption("Снять", function()
                    net.Start("StalMod_UnEquipItem")
                        net.WriteString(self.slotType)
                    net.SendToServer()
                end)
                menu:Open(gui.MouseX(), gui.MouseY())
                lastRightClickTime = CurTime()
            end
        end
    end

    local armorPanel = vgui.Create("DPanel", parentFrame)
    armorPanel:SetSize(150, 150)
    armorPanel:SetPos(120, 50)
    armorPanel.slotType = "ARMOR"
    armorPanel.Paint = function(self, w, h)
        EquipmentDrawSlot("ARMOR", self, w, h, "Броня")
    end
    armorPanel.Think = function(self)
        if IsMouseInRect(1275, 210, 155, 152) then
            if input.IsMouseDown(MOUSE_RIGHT) and (CurTime() - lastRightClickTime > rightClickCooldown) then
                local menu = DermaMenu()
                menu:AddOption("Снять", function()
                    net.Start("StalMod_UnEquipItem")
                        net.WriteString(self.slotType)
                    net.SendToServer()
                end)
                menu:Open(gui.MouseX(), gui.MouseY())
                lastRightClickTime = CurTime()
            end
        end
    end

    local pistolPanel = vgui.Create("DPanel", parentFrame)
    pistolPanel:SetSize(100, 305)
    pistolPanel:SetPos(15, 50)
    pistolPanel.slotType = "SECONDARY_WEAPON"
    pistolPanel.Paint = function(self, w, h)
        EquipmentDrawSlot("SECONDARY_WEAPON", self, w, h, "Пистолет")
    end
    pistolPanel.Think = function(self)
        if IsMouseInRect(1440, 215, 90, 295) then
            if input.IsMouseDown(MOUSE_RIGHT) and (CurTime() - lastRightClickTime > rightClickCooldown) then
                local menu = DermaMenu()
                menu:AddOption("Снять", function()
                    net.Start("StalMod_UnEquipItem")
                        net.WriteString(self.slotType)
                    net.SendToServer()
                end)
                menu:Open(gui.MouseX(), gui.MouseY())
                lastRightClickTime = CurTime()
            end
        end
    end

    local otherPanel = vgui.Create("DPanel", parentFrame)
    otherPanel:SetSize(150, 150)
    otherPanel:SetPos(120, 205)
    otherPanel.slotType = "UTILITY"
    otherPanel.Paint = function(self, w, h)
        EquipmentDrawSlot("UTILITY", self, w, h, "Разное")
    end
    otherPanel.Think = function(self)
        if IsMouseInRect(1440, 215, 90, 295) then
            if input.IsMouseDown(MOUSE_RIGHT) and (CurTime() - lastRightClickTime > rightClickCooldown) then
                local menu = DermaMenu()
                menu:AddOption("Снять", function()
                    net.Start("StalMod_UnEquipItem")
                        net.WriteString(self.slotType)
                    net.SendToServer()
                end)
                menu:Open(gui.MouseX(), gui.MouseY())
                lastRightClickTime = CurTime()
            end
        end
    end
end

local PANEL = {}

function PANEL:Init()
    self:SetSize(ScaleX(1920), ScaleY(1920))
    self:SetPos(0, 0)
    self:MakePopup()
end

function PANEL:Paint(w, h)
    local mouseX, mouseY = gui.MouseX(), gui.MouseY()
    if draggingItem then
        local item = StalMod.Inventory.Items[draggingItem.id]
        local IconMat = Material(item.IconMat)
        surface.SetDrawColor(Color(255, 255, 255, 100))
        surface.SetMaterial(IconMat)
        surface.DrawTexturedRect(mouseX - dragOffsetX, mouseY - dragOffsetY, item.SizeX * cellSize, item.SizeY * cellSize)
        surface.DrawOutlinedRect(mouseX - dragOffsetX, mouseY - dragOffsetY, item.SizeX * cellSize, item.SizeY * cellSize, 1)
    end
end

vgui.Register("ItemsPanel", PANEL, "EditablePanel")

local function CreateInventoryPanel(inventory)
    if IsValid(frame) then
        frame:Remove()
    end
    frame = vgui.Create("DFrame")
    frame:SetTitle("Инвентарь")
    frame:SetSize(inventoryGridSizeX * cellSize + 420, inventoryGridSizeY * cellSize + 35)
    frame:Center()
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)

    frame.Create = CurTime() + 0.5
    frame.Think = function(self)
        if input.IsKeyDown(KEY_ESCAPE) or not LocalPlayer():Alive() then
            self:Remove()
        end
        if self.Create <= CurTime() and input.IsKeyDown(KEY_I) then
            self:Remove()
        end
    end
    
    local invPanel = vgui.Create("DPanel", frame)
    invPanel:SetSize(inventoryGridSizeX * cellSize, inventoryGridSizeY * cellSize)
    invPanel:SetPos(10, 30)
    invPanel.Paint = function() DrawInventory(inventory, invPanel) end

    local equipPanel = vgui.Create("EditablePanel", frame)
    if not IsValid(equipPanel) then 
        ErrorNoHalt("[ОШИБКА] Не удалось создать панель экипировки!")
        return frame 
    end

    equipPanel:SetSize(390, 400)
    equipPanel:SetPos(inventoryGridSizeX * cellSize + 20, 30)
    equipPanel.Paint = function(self, w, h)
        surface.SetDrawColor(50, 50, 50, 200)
        surface.DrawRect(0, 0, w, h)
    end

    if IsValid(equipPanel) then
        EquipmentCreateSlots(equipPanel)
        equipPanel:InvalidateLayout()
    end

    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:Dock(FILL)
    contentPanel:SetMouseInputEnabled(false)
    contentPanel.Paint = function(self, w, h) draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 0)) end
    local itemsPanel = vgui.Create("ItemsPanel", contentPanel)

    net.Start("StalMod_RequestEquipment")
    net.SendToServer()
end

local function ShowInventoryUI(inventory)
    if not inventory then
        return
    end

    if not IsValid(inventoryPanel) then
        inventoryPanel = CreateInventoryPanel(inventory)
    else
        inventoryPanel:SetVisible(not inventoryPanel:IsVisible())
    end
end

hook.Add("PlayerButtonDown", "ToggleInventoryOnI", function(ply, button)
    if button == KEY_I then
        ShowInventoryUI(LocalPlayer().Inventory)
    end
end)

net.Receive("StalMod_ItemCooldown", function()
    local slotIndex = net.ReadUInt(8)
    local endTime = net.ReadFloat()
    hotSlotCooldowns[slotIndex] = endTime
end)

function DrawHotSlots()
    for i, slot in ipairs(hotSlots) do
        local isHovered = IsMouseInRect(slot.posX, slot.posY, HOTSLOT_SIZE, HOTSLOT_SIZE)

        surface.SetDrawColor(isHovered and HOTSLOT_HOVER_COLOR or HOTSLOT_DEFAULT_COLOR)
        surface.DrawRect(slot.posX, slot.posY, HOTSLOT_SIZE, HOTSLOT_SIZE)

        if slot.item then
            local itemInfo = StalMod.Inventory.Items[slot.item.id]
            if itemInfo then
                local mat = Material(itemInfo.IconMat or "error")
                if mat:IsError() then
                    surface.SetDrawColor(100, 100, 255, 200)
                    surface.DrawRect(slot.posX + 8, slot.posY + 8, HOTSLOT_SIZE - 16, HOTSLOT_SIZE - 16)
                    draw.SimpleText(itemInfo.Name or "?", "DermaDefault", 
                        slot.posX + HOTSLOT_SIZE/2, 
                        slot.posY + HOTSLOT_SIZE/2, 
                        color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    surface.SetDrawColor(255, 255, 255)
                    surface.SetMaterial(mat)
                    surface.DrawTexturedRect(slot.posX + 8, slot.posY + 8, HOTSLOT_SIZE - 16, HOTSLOT_SIZE - 16)
                end
            end

            if hotSlotCooldowns[i] then
                local remaining = hotSlotCooldowns[i] - CurTime()
                if remaining > 0 then
                    surface.SetDrawColor(50, 50, 50, 150)
                    surface.DrawRect(slot.posX, slot.posY, HOTSLOT_SIZE, HOTSLOT_SIZE)

                    draw.SimpleText(math.ceil(remaining), "DermaDefaultBold", slot.posX + HOTSLOT_SIZE/2, slot.posY + HOTSLOT_SIZE/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    hotSlotCooldowns[i] = nil
                end
            end
        end

        draw.SimpleText("F"..i, "DermaDefaultBold", slot.posX + 5, slot.posY + 5, color_white)
    end
end

hook.Add("HUDPaint", "DrawHotSlots", DrawHotSlots)

local function OpenHotSlotMenu(slotIndex, x, y)
    local menu = DermaMenu()
    menu:AddOption("Снять предмет", function()
        net.Start("StalMod_UnassignHotSlot")
            net.WriteUInt(slotIndex, 8)
        net.SendToServer()
    end)
    menu:Open(x, y)
end

hook.Add("HUDPaint", "HotSlotClicks", function()
    if not IsValid(LocalPlayer()) then return end
    
    for i, slot in ipairs(hotSlots) do
        if IsMouseInRect(slot.posX, slot.posY, HOTSLOT_SIZE, HOTSLOT_SIZE) then
            if input.IsMouseDown(MOUSE_RIGHT) then
                OpenHotSlotMenu(i, gui.MouseX(), gui.MouseY())
            end
        end
    end
end)

hook.Add("PlayerButtonDown", "HotkeyHandler", function(ply, btn)
    if not IsFirstTimePredicted() then return end

    for i, key in ipairs(HOTKEYS) do
        if btn == key then
            UseHotSlot(i)
            return
        end
    end
end)