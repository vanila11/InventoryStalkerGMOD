util.AddNetworkString("StalMod_UpdateInventory")
util.AddNetworkString("StalMod_ItemCooldown")
util.AddNetworkString("StalMod_FullEquipmentUpdate")

util.AddNetworkString("StalMod_DropItem")
net.Receive("StalMod_DropItem", function(len, ply)
    local uniqueID = net.ReadString()
    print("[СЕРВЕР] Получен запрос на выкидывание предмета с UniqueID:", uniqueID)
    DropItemFromInventory(ply, uniqueID)
end)

util.AddNetworkString("StalMod_MoveItem")
net.Receive("StalMod_MoveItem", function(len, ply)
    local uniqueID = net.ReadString()
    local newX = net.ReadUInt(8)
    local newY = net.ReadUInt(8)
    local shouldMerge = net.ReadBool()

    if not ply.Inventory then return end

    local itemData
    for _, data in ipairs(ply.Inventory.items) do
        if data and data.uniqueID == uniqueID then
            itemData = data
            break
        end
    end
    if not itemData then return end

    local item = StalMod.Inventory.Items[itemData.id]
    if not item then return end

    if not ply.Inventory:CanPlaceItemAt(newX, newY, itemData.id, uniqueID) then
        return
    end

    for i = 0, itemData.SizeX - 1 do
        for j = 0, itemData.SizeY - 1 do
            ply.Inventory.grid[itemData.pos.x + i][itemData.pos.y + j] = nil
        end
    end

    for i = 0, item.SizeX - 1 do
        for j = 0, item.SizeY - 1 do
            ply.Inventory.grid[newX + i] = ply.Inventory.grid[newX + i] or {}
            ply.Inventory.grid[newX + i][newY + j] = uniqueID
        end
    end

    itemData.pos.x = newX
    itemData.pos.y = newY

    if shouldMerge then
        net.Start("StalMod_ItemMoved")
        net.WriteString(uniqueID)
        net.WriteBool(true)
        net.Send(ply)
    end

    SaveInventoryToDatabase(ply)
    NotifyClientInventoryUpdate(ply)
end)

util.AddNetworkString("StalMod_UseItem")
net.Receive("StalMod_UseItem", function(len, ply)
    local uniqueID = net.ReadString()
    local foundItem = false
    for k, itemData in pairs(ply.Inventory.items) do
        if itemData.uniqueID == uniqueID then
            local item = StalMod.Inventory.Items[itemData.id]
            if item.OnPlayerUse and item.OnPlayerUse(ply) then
                if itemData.slotIndex then
                    if item.Cooldown then
                        local cooldown = item.Cooldown
                        net.Start("StalMod_ItemCooldown")
                            net.WriteUInt(itemData.slotIndex, 8)
                            net.WriteFloat(CurTime() + cooldown)
                        net.Send(ply)
                    end 
                end

                if item.Stackable then
                    itemData.amount = itemData.amount - 1
                    if itemData.amount < 1 then
                        table.remove(ply.Inventory.items, k)
                    end
                end
                foundItem = true
                break
            end
        end
    end
    if foundItem then
        NotifyClientInventoryUpdate(ply)
    end
end)

util.AddNetworkString("StalMod_SplitStack")
net.Receive("StalMod_SplitStack", function(len, ply)
    local uniqueID = net.ReadString()
    local splitAmount = net.ReadUInt(16)

    local itemData
    for _, data in ipairs(ply.Inventory.items) do
        if data.uniqueID == uniqueID then
            itemData = data
            break
        end
    end

    if not itemData then
        ply:ChatPrint("Ошибка: стак не найден.")
        return
    end

    if itemData.amount <= 1 then
        ply:ChatPrint("Невозможно разделить стак из одного предмета.")
        return
    end

    local success, err = ply.Inventory:SplitStack(uniqueID, splitAmount, ply)
    if success then
        SaveInventoryToDatabase(ply)
        NotifyClientInventoryUpdate(ply)
    else
        ply:ChatPrint("Ошибка: " .. (err or "неизвестная ошибка"))
    end

    NotifyClientInventoryUpdate(ply)
end)

util.AddNetworkString("StalMod_ItemMoved")
net.Receive("StalMod_ItemMoved", function(len, ply)
    local movedUID = net.ReadString()
    local shouldMerge = net.ReadBool()

    local movedItem
    for _, item in ipairs(ply.Inventory.items) do
        if item.uniqueID == movedUID then
            movedItem = item
            break
        end
    end

    if not movedItem then
        print("[ОШИБКА] Предмет с UniqueID " .. movedUID .. " не найден в инвентаре.")
        return
    end

    if shouldMerge then
        for _, targetItem in ipairs(ply.Inventory.items) do
            if targetItem.id == movedItem.id 
            and targetItem.uniqueID ~= movedItem.uniqueID
            and ply.Inventory:TryMergeStacks(movedItem.uniqueID, targetItem.uniqueID) then
                break
            end
        end
    end

    NotifyClientInventoryUpdate(ply)
end)

util.AddNetworkString("StalMod_UpdateHotSlots")
function UpdateClientHotSlots(ply)
    net.Start("StalMod_UpdateHotSlots")
        net.WriteTable(ply.HotSlots or {})
    net.Send(ply)
end

util.AddNetworkString("StalMod_MergeStacks")
net.Receive("StalMod_MergeStacks", function(len, ply)
    local sourceUID = net.ReadString()
    local targetUID = net.ReadString()
    
    if ply.Inventory:TryMergeStacks(sourceUID, targetUID) then
        ply:ChatPrint("Стаки успешно объединены!")
    else
        ply:ChatPrint("Невозможно объединить стаки!")
    end

    NotifyClientInventoryUpdate(ply)
end)

util.AddNetworkString("StalMod_AssignHotSlot")
net.Receive("StalMod_AssignHotSlot", function(len, ply)
    local slotIndex = net.ReadUInt(8)
    local uniqueID = net.ReadString()

    for i, slot in pairs(ply.HotSlots or {}) do
        if slot.uniqueID == uniqueID then
            ply:ChatPrint("Этот предмет уже назначен в слот F" .. i)
            return
        end
    end

    local itemData
    for _, item in ipairs(ply.Inventory.items) do
        if item.uniqueID == uniqueID then
            itemData = item
            break
        end
    end

    if itemData then
        ply.HotSlots = ply.HotSlots or {}
        ply.HotSlots[slotIndex] = {
            id = itemData.id,
            uniqueID = uniqueID,
            amount = itemData.amount
        }

        UpdateClientHotSlots(ply)
        SaveInventoryToDatabase(ply)
        ply:ChatPrint("Предмет назначен на F" .. slotIndex)
    end
end)

local itemCooldowns = {}
util.AddNetworkString("StalMod_UseHotSlot")
net.Receive("StalMod_UseHotSlot", function(len, ply)
    local slotIndex = net.ReadUInt(8)
    local slotData = ply.HotSlots and ply.HotSlots[slotIndex]

    if not slotData then return end

    local itemData
    for _, item in ipairs(ply.Inventory.items) do
        if item.uniqueID == slotData.uniqueID then
            itemData = item
            break
        end
    end

    if itemData then
        local itemInfo = StalMod.Inventory.Items[itemData.id]
        if itemInfo and itemInfo.OnPlayerUse and itemInfo.OnPlayerUse(ply) then
            if itemInfo.Stackable then
                itemData.amount = itemData.amount - 1
                if itemData.amount <= 0 then
                    ply.Inventory:RemoveItem(itemData.uniqueID)
                    ply.HotSlots[slotIndex] = nil
                end
            end
            NotifyClientInventoryUpdate(ply)
            UpdateClientHotSlots(ply)
        end
    else
        ply.HotSlots[slotIndex] = nil
        UpdateClientHotSlots(ply)
    end

    if itemData then
        local itemInfo = StalMod.Inventory.Items[itemData.id]
        itemCooldowns[ply:SteamID()] = itemCooldowns[ply:SteamID()] or {}
        itemCooldowns[ply:SteamID()][slotIndex] = CurTime() + itemInfo.Cooldown
    end

    net.Start("StalMod_ItemCooldown")
        net.WriteUInt(slotIndex, 8)
        net.WriteFloat(itemCooldowns[ply:SteamID()][slotIndex])
    net.Send(ply)
end)

util.AddNetworkString("StalMod_UnassignHotSlot")
net.Receive("StalMod_UnassignHotSlot", function(len, ply)
    local slotIndex = net.ReadUInt(8)
    
    if ply.HotSlots and ply.HotSlots[slotIndex] then
        ply.HotSlots[slotIndex] = nil
        UpdateClientHotSlots(ply)
        SaveInventoryToDatabase(ply)
        ply:ChatPrint("Предмет снят с F"..slotIndex)
    end
end)

util.AddNetworkString("StalMod_EquipItem")
net.Receive("StalMod_EquipItem", function(len, ply)
    local uniqueID = net.ReadString()
    local slotType = net.ReadString()
    local itemData
    for _, item in ipairs(ply.Inventory.items) do
        if item.uniqueID == uniqueID then
            itemData = item
            break
        end
    end
    if not itemData then return end
    local itemInfo = StalMod.Inventory.Items[itemData.id]
    local slotInfo = StalMod.Equipment.Slots[slotType]
    if itemInfo.EquipData and slotInfo then
        if StalMod.Equipment.CanEquip(ply, itemData.id, slotType) then
            StalMod.Equipment.EquipItem(ply, uniqueID, slotType)
        else
            print("[SERVER] Ошибка!")
        end
    end
end)

util.AddNetworkString("StalMod_RequestEquipment")
net.Receive("StalMod_RequestEquipment", function(len, ply)
    if not ply.Equipment then return end
    net.Start("StalMod_FullEquipmentUpdate")
        net.WriteTable(ply.Equipment)
    net.Send(ply)
end)

util.AddNetworkString("StalMod_UnEquipItem")
net.Receive("StalMod_UnEquipItem", function(len, ply)
    local slotType = net.ReadString()
    StalMod.Equipment.UnEquipItem(ply, slotType)
end)

hook.Add("PlayerSpawn", "ApplyEquipmentEffects", function(ply)
    timer.Simple(0.5, function()
        if IsValid(ply) and ply.Equipment then
            for slotType, itemData in pairs(ply.Equipment) do
                local itemInfo = StalMod.Inventory.Items[itemData.itemID]
                if itemInfo and itemInfo.OnEquip then
                    itemInfo.OnEquip(ply, true)
                end
            end
        end
    end)
end)