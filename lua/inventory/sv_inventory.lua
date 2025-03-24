local HOTSLOT_COUNT = 5

hook.Add("PlayerInitialSpawn", "InitPlayerEquipment", function(ply)
    ply.Equipment = {}
    for slotType, _ in pairs(StalMod.Equipment.Slots) do
        ply.Equipment[slotType] = nil
    end
end)

local function UpdateClientHotSlots(ply)
    local hotSlotsData = {}
    for i = 1, HOTSLOT_COUNT do
        hotSlotsData[i] = ply.HotSlots and ply.HotSlots[i] or nil
    end

    net.Start("StalMod_UpdateHotSlots")
        net.WriteTable(hotSlotsData)
    net.Send(ply)
end

function NotifyClientInventoryUpdate(ply)
    if not ply.Inventory then return end

    local validItems = {}
    for _, itemData in ipairs(ply.Inventory.items) do
        if StalMod.Inventory.Items[itemData.id] then
            itemData.amount = itemData.amount or 1
            table.insert(validItems, itemData)
        end
    end

    net.Start("StalMod_UpdateInventory")
    net.WriteUInt(#validItems, 16)
    for _, itemData in ipairs(validItems) do
        net.WriteString(itemData.id)
        net.WriteString(itemData.uniqueID)
        net.WriteInt(itemData.pos.x, 8)
        net.WriteInt(itemData.pos.y, 8)
        net.WriteInt(itemData.amount or 1, 16)
    end
    net.Send(ply)

    UpdateClientHotSlots(ply)
end

function DropItemFromInventory(ply, uniqueID)
    if not ply.Inventory then return end

    local itemData
    for _, data in ipairs(ply.Inventory.items) do
        if data.uniqueID == uniqueID then
            itemData = data
            break
        end
    end

    local item = StalMod.Inventory.Items[itemData.id]
    if not item then
        return
    end

    local ent = ents.Create(itemData.id)
    if IsValid(ent) then
        ent:SetPos(ply:EyePos() + ply:GetForward() * 50)
        ent:Spawn()
    else
        print("[ОШИБКА] Не удалось создать сущность: " .. itemData.id)
        return
    end

    if item.Stackable then
        if itemData.amount > 1 then
            itemData.amount = itemData.amount - 1
        else
            ply.Inventory:RemoveItem(uniqueID)
        end
    else
        ply.Inventory:RemoveItem(uniqueID)
    end

    NotifyClientInventoryUpdate(ply)
end

function StalMod.Inventory:UpdateInventoryGrid(oldPos, newPos, uniqueID)
    for i = 0, (self.Items[self.items[uniqueID].SizeX or 1]) - 1 do
        for j = 0, (self.Items[self.items[uniqueID].SizeY or 1]) - 1 do
            local x = oldPos.x + i
            local y = oldPos.y + j
            if self.grid[x] and self.grid[x][y] == uniqueID then
                self.grid[x][y] = nil
            end
        end
    end

    for i = 0, (self.Items[self.items[uniqueID].SizeX or 1]) - 1 do
        for j = 0, (self.Items[self.items[uniqueID].SizeY or 1]) - 1 do
            local x = newPos.x + i
            local y = newPos.y + j
            self.grid[x] = self.grid[x] or {}
            self.grid[x][y] = uniqueID
        end
    end
end

function StalMod.Inventory:SplitStack(uniqueID, splitAmount, ply)
    for i, itemData in ipairs(self.items) do
        if itemData.uniqueID == uniqueID then
            local item = self.Items[itemData.id]

            if splitAmount <= 0 or splitAmount >= itemData.amount then
                return false, "Некорректное количество (должно быть от 1 до " .. (itemData.amount - 1) .. ")"
            end

            local x, y = self:FindEmptySpotForItem(itemData.id)
            if not x or not y then
                return false, "Недостаточно места в инвентаре"
            end

            local newUniqueID = ply:SteamID64() .. "_" .. os.time() .. "_" .. math.random(10000, 99999)

            local newItem = {
                id = itemData.id,
                uniqueID = newUniqueID,
                pos = {x = x, y = y},
                amount = splitAmount,
                maxStack = itemData.maxStack,
                SizeX = itemData.SizeX,
                SizeY = itemData.SizeY
            }
            table.insert(self.items, newItem)

            itemData.amount = itemData.amount - splitAmount

            if itemData.amount <= 0 then
                self:RemoveItem(uniqueID)
            end

            SaveInventoryToDatabase(ply)
            return true
        end
    end

    NotifyClientInventoryUpdate(ply)

    for slotIndex, slotData in pairs(ply.HotSlots or {}) do
        if slotData.uniqueID == uniqueID then
            slotData.amount = itemData.amount - splitAmount
        end
    end
    UpdateClientHotSlots(ply)
    return false, "Предмет не найден"
end

function StalMod.Inventory:TryMergeStacks(sourceUID, targetUID)
    local sourceStack, targetStack

    for _, item in ipairs(self.items) do
        if item.uniqueID == sourceUID then sourceStack = item end
        if item.uniqueID == targetUID then targetStack = item end
        if sourceStack and targetStack then break end
    end

    if not sourceStack or not targetStack then return false end
    if sourceStack.id ~= targetStack.id then return false end
    if sourceStack.uniqueID == targetStack.uniqueID then return false end
    
    local itemInfo = self.Items[sourceStack.id]
    local maxStack = itemInfo.MaxStack or 1

    local availableSpace = maxStack - targetStack.amount
    if availableSpace <= 0 then return false end

    local transferAmount = math.min(sourceStack.amount, availableSpace)

    targetStack.amount = targetStack.amount + transferAmount
    sourceStack.amount = sourceStack.amount - transferAmount

    if sourceStack.amount <= 0 then
        self:RemoveItem(sourceUID)
    end

    return true
end

local function IsValidItem(class)
    return StalMod.Inventory.Items[class] ~= nil
end

function PickupItem(ply, ent)
    local itemId = ent:GetClass()
    if not IsValidItem(itemId) then return end
    if not ply.Inventory then ply.Inventory = StalMod.Inventory:New() end

    local item = StalMod.Inventory.Items[itemId]
    if item.Stackable then
        for _, existingItem in ipairs(ply.Inventory.items) do
            if existingItem.id == itemId and existingItem.amount < existingItem.maxStack then
                existingItem.amount = existingItem.amount + 1
                ent:Remove()
                NotifyClientInventoryUpdate(ply)
                return
            end
        end
    end

    local uniqueID = ply:SteamID64() .. "_" .. os.time() .. "_" .. math.random(10000, 99999)
    local x, y = ply.Inventory:FindEmptySpotForItem(itemId)
    if x and y and ply.Inventory:AddItem(itemId, uniqueID, {x = x, y = y}) then
        ent:Remove()
        NotifyClientInventoryUpdate(ply)
    end
end

local function TryPickupItem(ply)
    local trace = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * 100,
        filter = ply
    })

    if trace.Hit and IsValid(trace.Entity) and trace.Entity:GetClass() ~= "worldspawn" then
        PickupItem(ply, trace.Entity)
    end
end

hook.Add("PlayerButtonDown", "StalMod_ItemPickup", function(ply, button)
    if button == KEY_F then
        TryPickupItem(ply)
    end
end)

function StalMod.Equipment.UnEquipItem(ply, slotType, silent)
    local eqItem = ply.Equipment[slotType]
    if not eqItem then return false end

    local success = ply.Inventory:AddItem(eqItem.itemID, eqItem.uniqueID)
    if not success then
        if not silent then ply:ChatPrint("Недостаточно места!") end
        return false
    end

    local itemInfo = StalMod.Inventory.Items[eqItem.itemID]
    if itemInfo.OnUnEquip then
        itemInfo.OnUnEquip(ply, silent)
    end

    ply.Equipment[slotType] = nil

    if not silent then
        net.Start("StalMod_FullEquipmentUpdate")
            net.WriteTable(ply.Equipment)
        net.Send(ply)
        SaveInventoryToDatabase(ply)
        NotifyClientInventoryUpdate(ply)
    end

    return true
end

function StalMod.Equipment.CanEquip(ply, itemID, slotType)
    local item = StalMod.Inventory.Items[itemID]
    if not item or not item.EquipData then return false end

    if item.EquipData.slotType ~= slotType then
        print("[СЕРВЕР] Предмет не подходит для слота:", slotType)
        return false
    end

    if item.EquipData.conflicts then
        for _, conflictType in pairs(item.EquipData.conflicts) do
            if ply.Equipment[conflictType] then
                print("[СЕРВЕР] Конфликт с экипировкой:", conflictType)
                return false
            end
        end
    end

    return true
end

function StalMod.Equipment.EquipItem(ply, uniqueID, slotType, silent)
    local item = ply.Inventory:GetItemByUID(uniqueID)
    if not item then
        if not silent then ply:ChatPrint("Предмет не найден!") end
        return false
    end

    local slotInfo = StalMod.Equipment.Slots[slotType]
    if not slotInfo then
        if not silent then ply:ChatPrint("Неверный слот!") end
        return false
    end

    local itemInfo = StalMod.Inventory.Items[item.id]
    if not table.HasValue(slotInfo.types, itemInfo.EquipData.slotType) then
        if not silent then ply:ChatPrint("Предмет не подходит для слота!") end
        return false
    end

    if ply.Equipment[slotType] then
        if not StalMod.Equipment.UnEquipItem(ply, slotType, true) then
            if not silent then ply:ChatPrint("Не удалось освободить слот!") end
            return false
        end
    end

    ply.Equipment[slotType] = {
        uniqueID = uniqueID,
        itemID = item.id
    }

    local itemInfo = StalMod.Inventory.Items[item.id]
    if itemInfo.OnEquip then
        itemInfo.OnEquip(ply, silent)
    end

    ply.Inventory:RemoveItem(uniqueID)

    if not silent then
        net.Start("StalMod_FullEquipmentUpdate")
            net.WriteTable(ply.Equipment)
        net.Send(ply)
        NotifyClientInventoryUpdate(ply)
        SaveInventoryToDatabase(ply)
    end

    return true
end