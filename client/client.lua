local ESX = exports['es_extended']:getSharedObject()
local isMenuOpen = false

local function OpenMultijobMenu()
    if isMenuOpen then return end
    lib.callback('multijob:getData', false, function(data)
        if not data then
            lib.notify({
                title = 'Multijob',
                description = Config.Locale.error or 'Error loading data',
                type = 'error'
            })
            return
        end
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            data = data
        })
        isMenuOpen = true
        if Config.Debug then
            print('^2[Multijob]^0 Menu opened')
        end
    end)
end

local function CloseMultijobMenu()
    if not isMenuOpen then return end
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'close'
    })
    isMenuOpen = false
    if Config.Debug then
        print('^2[Multijob]^0 Menu closed')
    end
end

RegisterNUICallback('close', function(_, cb)
    CloseMultijobMenu()
    cb('ok')
end)

RegisterNUICallback('switchSlot', function(data, cb)
    if not data or not data.slot then
        cb({success = false, message = Config.Locale.error or 'Error'})
        return
    end
    lib.callback('multijob:switchSlot', false, function(result)
        if result.success then
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'success'
            })
            lib.callback('multijob:getData', false, function(newData)
                SendNUIMessage({
                    action = 'update',
                    data = newData
                })
            end)
        else
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'error'
            })
        end
        cb(result)
    end, data.slot)
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    lib.callback('multijob:toggleDuty', false, function(result)
        if result.success then
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'success'
            })
            lib.callback('multijob:getData', false, function(newData)
                SendNUIMessage({
                    action = 'update',
                    data = newData
                })
            end)
        else
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'error'
            })
        end
        cb(result)
    end)
end)

RegisterNUICallback('removeSlot', function(data, cb)
    if not data or not data.slot then
        cb({success = false, message = Config.Locale.error or 'Error'})
        return
    end
    lib.callback('multijob:removeSlot', false, function(result)
        if result.success then
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'success'
            })
            lib.callback('multijob:getData', false, function(newData)
                SendNUIMessage({
                    action = 'update',
                    data = newData
                })
            end)
        else
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'error'
            })
        end
        cb(result)
    end, data.slot)
end)

RegisterNUICallback('addSlot', function(_, cb)
    lib.callback('multijob:addSlot', false, function(result)
        if result.success then
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'success'
            })
            lib.callback('multijob:getData', false, function(newData)
                SendNUIMessage({
                    action = 'update',
                    data = newData
                })
            end)
        else
            lib.notify({
                title = 'Multijob',
                description = result.message,
                type = 'error'
            })
        end
        cb(result)
    end)
end)

RegisterNetEvent('multijob:jobUpdated', function()
    if isMenuOpen then
        lib.callback('multijob:getData', false, function(newData)
            if newData then
                SendNUIMessage({
                    action = 'update',
                    data = newData
                })
                if Config.Debug then
                    print('^2[Multijob]^0 UI refreshed after job change')
                end
            end
        end)
    end
end)

RegisterCommand(Config.MenuCommand, function()
    OpenMultijobMenu()
end, false)

if Config.MenuKey then
    RegisterKeyMapping(Config.MenuCommand, 'Open Multijob Menu', 'keyboard', Config.MenuKey)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isMenuOpen then
        CloseMultijobMenu()
    end
end)

AddEventHandler('esx:onPlayerDeath', function()
    if isMenuOpen then
        CloseMultijobMenu()
    end
end)

exports('isOnDuty', function()
    if Config.DutySystem.useStateBags then
        return LocalPlayer.state.onDuty or false
    end
    return false
end)

exports('openMenu', function()
    OpenMultijobMenu()
end)

exports('closeMenu', function()
    CloseMultijobMenu()
end)

if Config.Debug then
    print('^2[Multijob]^0 Client script loaded successfully!')
end