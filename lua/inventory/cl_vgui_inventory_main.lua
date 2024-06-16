INVENTORY_WIDTH = 4
INVENTORY_HEIGHT = 6
CELL_SIZE = 32
inventorySlots = {}

for i = 1, INVENTORY_HEIGHT do
    inventorySlots[i] = {}
    for j = 1, INVENTORY_WIDTH do
        inventorySlots[i][j] = nil 
    end
end

function AddItemToInventory(item)
    local slotX, slotY = FindEmptyInventorySlot(item.w, item.h)
    if slotX and slotY then
        for i = 0, item.h - 1 do
            for j = 0, item.w - 1 do
                inventorySlots[slotY + i][slotX + j] = item 
            end
        end
    else
        print("Инвентарь полон!")
    end
end

function FindEmptyInventorySlot(itemWidth, itemHeight)
    for y = 1, INVENTORY_HEIGHT - itemHeight + 1 do
        for x = 1, INVENTORY_WIDTH - itemWidth + 1 do
            if IsInventoryAreaEmpty(x, y, itemWidth, itemHeight) then
                return x, y
            end
        end
    end
    return nil, nil 
end

function IsInventoryAreaEmpty(startX, startY, width, height)
    for i = 0, height - 1 do
        for j = 0, width - 1 do
            if inventorySlots[startY + i] and inventorySlots[startY + i][startX + j] then
                return false
            end
        end
    end
    return true
end

local PANEL = {}

function PANEL:Init()
    self:SetTitle("Tetris Inventory")
    self:SetSize(INVENTORY_WIDTH CELL_SIZE, INVENTORY_HEIGHT CELL_SIZE)
    self:Center()
    self:MakePopup()

    AddItemToInventory({w = 1, h = 1, icon = "materials/main/integration.png"})
    AddItemToInventory({w = 3, h = 1, icon = "materials/main/integration.png"})
    AddItemToInventory({w = 1, h = 3, icon = "materials/main/integration.png"})
end

function PANEL:Paint(w, h)
    draw.RoundedBox(0, 0, 0, w, h, Color(34, 34, 34))
    surface.SetDrawColor(Color(255, 255, 255))
    for i = 1, INVENTORY_WIDTH do
        local x = i CELL_SIZE
        surface.DrawLine(x, 0, x, h) 
    end

    for i = 1, INVENTORY_HEIGHT do
        local y = i CELL_SIZE
        surface.DrawLine(0, y, w, y)
    end

    local drawnItems = {}

    for y = 1, INVENTORY_HEIGHT do
        for x = 1, INVENTORY_WIDTH do
            local item = inventorySlots[y][x]
            if item and not drawnItems[item] then
                local itemX = (x - 1) CELL_SIZE
                local itemY = (y - 1) CELL_SIZE
                local itemWidth = item.w CELL_SIZE
                local itemHeight = item.h CELL_SIZE

                if item.icon then
                    local mat = Material(item.icon)
                    surface.SetMaterial(mat)
                    surface.DrawTexturedRect(itemX + 2, itemY + 2, itemWidth - 4, itemHeight - 4)
                end

                drawnItems[item] = true 
            end
        end
    end
end

vgui.Register("VanilaUI.Inventory.Grind", PANEL, "DFrame")