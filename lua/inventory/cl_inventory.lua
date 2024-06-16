local inventoryPanel = nil

local inventoryPanel = nil

function ToggleInventory()
    if IsValid(inventoryPanel) then
        inventoryPanel:Close()
        inventoryPanel = nil
    else
        inventoryPanel = vgui.Create("VanilaUI.Inventory.Grind")
    end
end

hook.Add("PlayerButtonDown", "Vanila.Inventory.OpenMenu", function(ply, b)
    if !ply:Alive() then return end
    if b ~= KEY_I then return end
    ToggleInventory()
end)