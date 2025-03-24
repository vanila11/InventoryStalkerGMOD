StalMod = StalMod or {}
StalMod.Inventory = StalMod.Inventory or {}
StalMod.Inventory.Items = StalMod.Inventory.Items or {}

StalMod.Inventory.INVENTORY_SIZE_X = 15
StalMod.Inventory.INVENTORY_SIZE_Y = 15

function StalMod.Inventory:New()
    local newInv = {
        items = {},
        grid = {}
    }
    setmetatable(newInv, self)
    self.__index = self

    for x = 1, StalMod.Inventory.INVENTORY_SIZE_X do
        newInv.grid[x] = {}
        for y = 1, StalMod.Inventory.INVENTORY_SIZE_Y do
            newInv.grid[x][y] = false
        end
    end

    return newInv
end

function StalMod.Inventory:GetItems()
    return self.items or {}
end

local PLAYER = FindMetaTable("Player")
function PLAYER:GetHotSlots()
    if not self.HotSlots then
        self.HotSlots = {}
        for i = 1, 5 do self.HotSlots[i] = nil end
    end
    return self.HotSlots
end
PLAYER:GetHotSlots()

StalMod.Equipment = StalMod.Equipment or {}
StalMod.Equipment.Slots = {
    PRIMARY_WEAPON = {
        name = "Основное оружие",
        types = {"PRIMARY_WEAPON"},
        maxItems = 1
    },
    SECONDARY_WEAPON = {
        name = "Пистолет",
        types = {"SECONDARY_WEAPON"},
        maxItems = 1
    },
    ARMOR = {
        name = "Броня",
        types = {"ARMOR"},
        maxItems = 1
    },
    UTILITY = {
        name = "Разное",
        types = {"UTILITY"},
        maxItems = 1
    }
}
function StalMod.Inventory:GetItemByUID(uniqueID)
    for _, item in ipairs(self.items) do
        if item.uniqueID == uniqueID then
            return item
        end
    end
    return nil
end

function StalMod.Inventory:FindEmptySpotForItem(itemId)
    local item = self.Items[itemId]
    if not item then return nil end

    local sizeX = item.SizeX or 1
    local sizeY = item.SizeY or 1

    for y = 1, self.INVENTORY_SIZE_Y - sizeY + 1 do
        for x = 1, self.INVENTORY_SIZE_X - sizeX + 1 do
            local canFit = true

            for i = 0, sizeX - 1 do
                for j = 0, sizeY - 1 do
                    if self.grid[x + i] and self.grid[x + i][y + j] then
                        canFit = false
                        break
                    end
                end
                if not canFit then break end
            end

            if canFit then
                return x, y
            end
        end
    end

    return nil
end

function StalMod.Inventory:AddItem(itemId, uniqueID, pos, skipMerge)
    local item = self.Items[itemId]
    if not item then return false end

    local x, y
    if pos then
        x = pos.x
        y = pos.y
    else
        x, y = self:FindEmptySpotForItem(itemId)
    end

    if not skipMerge and item.Stackable then
        for _, existingItem in pairs(self.items) do
            if existingItem.id == itemId and existingItem.amount < existingItem.maxStack then
                existingItem.amount = existingItem.amount + 1
                return true
            end
        end
    end

    for i = 0, item.SizeX - 1 do
        for j = 0, item.SizeY - 1 do
            local checkX = x + i
            local checkY = y + j
            if self.grid[checkX] and self.grid[checkX][checkY] then
                return false
            end
        end
    end

    for i = 0, item.SizeX - 1 do
        for j = 0, item.SizeY - 1 do
            self.grid[x + i] = self.grid[x + i] or {}
            self.grid[x + i][y + j] = uniqueID
        end
    end

    table.insert(self.items, {
        id = itemId,
        uniqueID = uniqueID,
        pos = {x = x, y = y},
        amount = 1,
        maxStack = item.MaxStack or 1,
        SizeX = item.SizeX,
        SizeY = item.SizeY
    })

    return true
end

function StalMod.Inventory:RemoveItem(uniqueID)
    local indexToRemove
    for i, itemData in ipairs(self.items) do
        if itemData.uniqueID == uniqueID then
            indexToRemove = i
            break
        end
    end
    if not indexToRemove then return false end

    local itemData = self.items[indexToRemove]
    for i = 0, (itemData.SizeX or 1) - 1 do
        for j = 0, (itemData.SizeY or 1) - 1 do
            local x = itemData.pos.x + i
            local y = itemData.pos.y + j
            if self.grid[x] then
                self.grid[x][y] = nil
            end
        end
    end

    table.remove(self.items, indexToRemove)
    return true
end

function StalMod.Inventory:CanPlaceItemAt(x, y, itemId, ignoreUniqueID)
    local item = self.Items[itemId]
    if not item then return false end

    for dx = 0, item.SizeX - 1 do
        for dy = 0, item.SizeY - 1 do
            local checkX = x + dx
            local checkY = y + dy

            if checkX > self.INVENTORY_SIZE_X or checkY > self.INVENTORY_SIZE_Y then
                return false
            end

            local cell = self.grid[checkX] and self.grid[checkX][checkY]
            if cell and cell ~= ignoreUniqueID then
                return false
            end
        end
    end
    
    return true
end

function StalMod.Inventory:RegisterItem(id, itemTable)
    local ITEM = {}
    ITEM.Id = id
    ITEM.Name = itemTable.Name or id
    ITEM.Desc = itemTable.Desc or ""
    ITEM.Weight = itemTable.Weight or 0.1
    ITEM.DefaultAmount = itemTable.DefaultAmount or 1
    ITEM.Category = itemTable.Category or "Other"
    ITEM.SizeX = itemTable.SizeX or 1
    ITEM.SizeY = itemTable.SizeY or 1
    ITEM.IconMat = itemTable.IconMat or "icons/items/error.png"
    ITEM.IconColor = itemTable.IconCoor or nil
    ITEM.EffectsDesc = itemTable.EffelctsDesc or nil
    ITEM.Stackable = itemTable.Stackable or false
    ITEM.MaxStack = itemTable.MaxStack or 1
    ITEM.Cooldown = itemTable.Cooldown or 1
    ITEM.EquipType = itemTable.EquipType or nil
    ITEM.EquipSlot = itemTable.EquipSlot or nil
    ITEM.OnEquip = itemTable.OnEquip or nil
    ITEM.OnUnEquip = itemTable.OnUnEquip or nil
    ITEM.Usable = itemTable.Usable or false
    if itemTable.EquipType then
        ITEM.EquipData = {
            slotType = itemTable.EquipType,
            requirements = itemTable.Requirements,
            conflicts = itemTable.Conflicts
        }
    end

    ITEM.DeleteOnUse = itemTable.DeleteOnUse ~= false
    ITEM.Droppable = itemTable.Droppable ~= false
    ITEM.CanStuck = itemTable.CanStuck or nil

    ITEM.IsWeapon = itemTable.IsWeapon or nil
    ITEM.IsArtifact = itemTable.IsArtifact or nil
    ITEM.IsQuest = itemTable.IsQuest or nil
    ITEM.IsMutant = itemTable.IsMutant or nil
    ITEM.IsDevice = itemTable.IsDevice or nil
    ITEM.IsArmor = itemTable.IsArmor or nil
    ITEM.IsAmmo = itemTable.IsAmmo or nil

    ITEM.Weapon = itemTable.Weapon or nil
    ITEM.ArmorModel = itemTable.ArmorModel or nil
    ITEM.Art = itemTable.Art or nil
    ITEM.ArmorTable = itemTable.ArmorTable or nil
    ITEM.HelmetTable = itemTable.HelmetTable or nil
    ITEM.Ammo = itemTable.Ammo or nil

    ITEM.BasePrice = itemTable.BasePrice or 1

    ITEM.OnPlayerUse = itemTable.OnPlayerUse or nil
    ITEM.OnPlayerGive = itemTable.OnPlayerGive or nil
    ITEM.OnArtifactEquip = itemTable.OnArtifactEquip or nil
    ITEM.OnArtifactUnEquip = itemTable.OnArtifactUnEquip or nil
    ITEM.OnArmorEquip = itemTable.OnArmorEquip or nil
    ITEM.OnArmorUnEquip = itemTable.OnArmorUnEquip or nil
    ITEM.OnHelmetEquip = itemTable.OnHelmetEquip or nil
    ITEM.OnHelmetUnEquip = itemTable.OnHelmetUnEquip or nil
    ITEM.OnQuickSlotEquip = itemTable.OnQuickSlotEquip or nil
    ITEM.OnQuickSlotUnEquip = itemTable.OnQuickSlotUnEquip or nil
    ITEM.OnPlayerDeath = itemTable.OnPlayerDeath or nil
    ITEM.OnRemoved = itemTable.OnRemoved or nil

    self.Items[id] = ITEM
end

StalMod.Inventory:RegisterItem("item_healthkit", {
    Name = "Аптечка",
    Desc = "Экстренная медицинская помощь",
    EffectsDesc = "Восстанавливает 50 HP",
    IconMat = "vgui/solutionrp/heart.png",
    Stackable = true,
    Usable = true,
    Cooldown = 3,
    MaxStack = 3,
    SizeX = 2,
    SizeY = 1,
    
    OnPlayerUse = function(ply)
        ply:SetHealth(math.min(ply:Health() + 50, ply:GetMaxHealth()))
        return true
    end
})

StalMod.Inventory:RegisterItem("item_ammo_smg1", {
    Name = "Патроны SMG",
    Desc = "Легкие патроны для SMG",
    IconMat = "vgui/solutionrp/heart.png",
    Stackable = true,
    MaxStack = 256,
    SizeX = 1,
    SizeY = 1,
})

StalMod.Inventory:RegisterItem("item_battery", {
    Name = "Бронежилет",
    Desc = "Стандартная защита торса",
    EffectsDesc = "Броня +50\nСнижает скорость передвижения на 10%",
    IconMat = "vgui/solutionrp/shield.png",
    EquipType = "ARMOR",
    EquipData = {
        slotType = "ARMOR",
        conflicts = {"UTILITY"}
    },
    SizeX = 2,
    SizeY = 2,
    IsArmor = true,
    OnEquip = function(ply, silent)
        ply:SetArmor(100)
        if not silent then
            ply:ChatPrint("Броня активирована!")
        end
    end,
    
    OnUnEquip = function(ply, silent)
        ply:SetArmor(0)
        if not silent then
            ply:ChatPrint("Броня снята.")
        end
    end
})

StalMod.Inventory:RegisterItem("weapon_ak472", {
    Name = "АК-47",
    Desc = "Штурмовая винтовка",
    EquipType = "PRIMARY_WEAPON",
    EquipData = {
        slotType = "PRIMARY_WEAPON",
        conflicts = {"SECONDARY_WEAPON"}
    },
    SizeX = 3,
    SizeY = 1,
    IsWeapon = true,
    OnEquip = function(ply)
        ply:Give("weapon_ak472")
        print("[СЕРВЕР] Оружие выдано игроку:", ply:Nick())
    end,
    OnUnEquip = function(ply)
        ply:StripWeapon("weapon_ak472")
    end
})

StalMod.Inventory:RegisterItem("weapon_pistol", {
    Name = "Пистолет",
    Desc = "Стандартный пистолет",
    EquipType = "SECONDARY_WEAPON",
    EquipData = {
        slotType = "SECONDARY_WEAPON",
        conflicts = {"PRIMARY_WEAPON"}
    },
    SizeX = 2,
    SizeY = 1,
    IsWeapon = true,
    OnEquip = function(ply)
        ply:Give("weapon_pistol")
    end,
    OnUnEquip = function(ply)
        ply:StripWeapon("weapon_pistol")
    end
})