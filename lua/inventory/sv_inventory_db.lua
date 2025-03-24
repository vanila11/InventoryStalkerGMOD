local function InitializeDatabase()
    if not sql.TableExists("gmod_inventory") then
        sql.Query([[
            CREATE TABLE gmod_inventory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uniqueID TEXT,
                playerID TEXT,
                itemID TEXT,
                posX INTEGER,
                posY INTEGER,
                amount INTEGER DEFAULT 1,
                maxStack INTEGER DEFAULT 1
            )
        ]])
    end

    if not sql.TableExists("gmod_equipment") then
        sql.Query([[
            CREATE TABLE gmod_equipment (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                playerID TEXT NOT NULL,
                slotType TEXT NOT NULL,
                uniqueID TEXT NOT NULL,
                itemID TEXT NOT NULL
            )
        ]])
    end
end

function SaveInventoryToDatabase(ply)
    if not ply.Inventory then
        return 
    end

    local deleteQuery = "DELETE FROM gmod_inventory WHERE playerID = " .. sql.SQLStr(ply:SteamID64())
    sql.Query(deleteQuery)

    for _, itemData in ipairs(ply.Inventory.items) do
        local query = string.format(
            "INSERT INTO gmod_inventory (uniqueID, playerID, itemID, posX, posY, amount, maxStack) VALUES (%s, %s, %s, %d, %d, %d, %d)",
            sql.SQLStr(itemData.uniqueID),
            sql.SQLStr(ply:SteamID64()),
            sql.SQLStr(itemData.id),
            itemData.pos.x,
            itemData.pos.y,
            itemData.amount,
            itemData.maxStack
        )
        sql.Query(query)
    end

    sql.Query("DELETE FROM gmod_equipment WHERE playerID = " .. sql.SQLStr(ply:SteamID64()))

    if ply.Equipment then
        for slotType, itemData in pairs(ply.Equipment) do
            local query = string.format(
                "INSERT INTO gmod_equipment (playerID, slotType, uniqueID, itemID) VALUES (%s, %s, %s, %s)",
                sql.SQLStr(ply:SteamID64()),
                sql.SQLStr(slotType),
                sql.SQLStr(itemData.uniqueID),
                sql.SQLStr(itemData.itemID)
            )
            sql.Query(query)
        end
    end
end

function LoadInventoryFromDatabase(ply)
    if not ply.Inventory then
        ply.Inventory = StalMod.Inventory:New()
    end

    local result = sql.Query("SELECT * FROM gmod_inventory WHERE playerID = " .. sql.SQLStr(ply:SteamID64()))
    if result then
        for _, row in ipairs(result) do
            local posX = tonumber(row.posX)
            local posY = tonumber(row.posY)
            ply.Inventory:AddItem(row.itemID, row.uniqueID, {x = posX, y = posY}, true)
            local item = ply.Inventory.items[#ply.Inventory.items]
            item.amount = tonumber(row.amount) or 1
            item.maxStack = tonumber(row.maxStack) or 1
        end
    end

    ply.Equipment = {}
    
    local eqData = sql.Query("SELECT * FROM gmod_equipment WHERE playerID = " .. sql.SQLStr(ply:SteamID64()))
    if eqData then
        for _, row in ipairs(eqData) do
            if StalMod.Inventory.Items[row.itemID] then
                ply.Inventory:AddItem(row.itemID, row.uniqueID, {x = 0, y = 0}, true)

                StalMod.Equipment.EquipItem(ply, row.uniqueID, row.slotType, true)

                local itemInfo = StalMod.Inventory.Items[row.itemID]
                if itemInfo.OnEquip then
                    itemInfo.OnEquip(ply, true)
                end
            else
                print("[ОШИБКА] Удален битый предмет экипировки: ", row.itemID)
                sql.Query("DELETE FROM gmod_equipment WHERE id = " .. row.id)
            end
        end
    end

    NotifyClientInventoryUpdate(ply)
    net.Start("StalMod_FullEquipmentUpdate")
        net.WriteTable(ply.Equipment or {})
    net.Send(ply)
end

InitializeDatabase()

hook.Add("PlayerInitialSpawn", "LoadInventoryOnJoin", function(ply)
    timer.Simple(1, function()
        LoadInventoryFromDatabase(ply)
    end)
end)

hook.Add("PlayerDisconnected", "SaveInventoryOnLeave", function(ply)
    SaveInventoryToDatabase(ply)
end)