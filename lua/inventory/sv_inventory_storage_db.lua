local function InitializeDatabase()
    if not sql.TableExists("gmod_storage") then
        sql.Query([[
            CREATE TABLE gmod_storage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                playerID TEXT NOT NULL UNIQUE,
                sizeX INTEGER DEFAULT 10,
                sizeY INTEGER DEFAULT 10
            )
        ]])
    end

    if not sql.TableExists("gmod_storage_items") then
        sql.Query([[
            CREATE TABLE gmod_storage_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                storageID INTEGER,
                itemID TEXT NOT NULL,
                uniqueID TEXT NOT NULL,
                posX INTEGER,
                posY INTEGER,
                amount INTEGER DEFAULT 1,
                FOREIGN KEY(storageID) REFERENCES gmod_storage(id)
            )
        ]])
    end
end

hook.Add("PlayerInitialSpawn", "InitPlayerStorage", function(ply)
    local steamID = ply:SteamID64()
    local storage = sql.QueryRow("SELECT * FROM gmod_storage WHERE playerID = " .. sql.SQLStr(steamID))
    
    if not storage then
        sql.Query(string.format(
            "INSERT INTO gmod_storage (playerID, sizeX, sizeY) VALUES (%s, 10, 10)",
            sql.SQLStr(steamID)
        ))
    end
end)

hook.Add("PlayerInitialSpawn", "InitPlayerStorage", function(ply)
    local steamID = ply:SteamID64()
    local storage = sql.QueryRow("SELECT * FROM gmod_storage WHERE playerID = " .. sql.SQLStr(steamID))

    if not storage then
        sql.Query(string.format(
            "INSERT INTO gmod_storage (playerID, sizeX, sizeY) VALUES (%s, 10, 10)",
            sql.SQLStr(steamID)
        ))
    end
end)

function StalMod.Storage:GetPlayerStorage(ply)
    local storage = {
        grid = {},
        items = {},
        sizeX = 10,
        sizeY = 10
    }

    local storageData = sql.QueryRow("SELECT * FROM gmod_storage WHERE playerID = " .. sql.SQLStr(ply:SteamID64()))
    if storageData then
        storage.sizeX = tonumber(storageData.sizeX)
        storage.sizeY = tonumber(storageData.sizeY)

        local items = sql.Query("SELECT * FROM gmod_storage_items WHERE storageID = " .. storageData.id)
        if items then
            for _, item in ipairs(items) do
                table.insert(storage.items, {
                    id = item.itemID,
                    uniqueID = item.uniqueID,
                    pos = {x = item.posX, y = item.posY},
                    amount = item.amount
                })
            end
        end
    end

    for x = 1, storage.sizeX do
        storage.grid[x] = {}
        for y = 1, storage.sizeY do
            storage.grid[x][y] = false
        end
    end

    for _, item in ipairs(storage.items) do
        local itemInfo = StalMod.Inventory.Items[item.id]
        for dx = 0, (itemInfo.SizeX or 1)-1 do
            for dy = 0, (itemInfo.SizeY or 1)-1 do
                storage.grid[item.pos.x + dx][item.pos.y + dy] = item.uniqueID
            end
        end
    end

    return storage
end