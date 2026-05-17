-- ==========================================
-- m-tuning | server/main.lua
-- Server-side core: DB init, callbacks, events
-- ==========================================

Core = nil

-- Initialise framework object on the server side
CreateThread(function()
    Core, _ = GetCore()
end)

-- Create DB tables when the resource starts
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(1500)
    CreateDatabaseTables()
    print('[m-tuning] Database tables ready.')
end)

-- ==========================================
-- Register framework callbacks
-- We wait for Core to be available before registering so ESX/QBCore
-- exports have had time to initialise.
-- ==========================================
CreateThread(function()
    while not Core do Wait(500) end

    if Config.Framework == 'ESX' then

        -- Fetch stored handling data for a vehicle
        Core.RegisterServerCallback('m-tuning:sqlDta', function(source, cb, plate, dataType)
            if not plate or not dataType then cb(nil) return end
            local data = GetVehicleData(plate, dataType)
            cb(data)
        end)

        -- Fetch all presets for the calling player's current vehicle
        Core.RegisterServerCallback('m-tuning:getPresets', function(source, cb, plate)
            if not plate then cb({}) return end
            local identifier = GetMTuningIdentifier(source)
            if not identifier then cb({}) return end
            cb(GetPresets(identifier, plate))
        end)

        -- Check whether the player owns the tuner tablet item
        Core.RegisterServerCallback('m-tuning:hasItem', function(source, cb)
            if not Config.ItemControl then cb(true) return end
            cb(PlayerHasItem(source, Config.TabletItemName))
        end)

        -- Check whether the player owns the checker tablet item
        Core.RegisterServerCallback('m-tuning:hasCheckerItem', function(source, cb)
            if not Config.ItemControl then cb(true) return end
            cb(PlayerHasItem(source, Config.CheckerItemName))
        end)

        -- Check whether the player's job is authorised for the checker
        Core.RegisterServerCallback('m-tuning:checkJob', function(source, cb)
            cb(PlayerHasAuthorizedJob(source))
        end)

        -- Return player group and whether advanced tab is accessible
        Core.RegisterServerCallback('m-tuning:getGroup', function(source, cb)
            local group     = GetMTuningGroup(source)
            local authActive = Config.AdvancedAuthorize and PlayerHasAdvancedAuth(source) or not Config.AdvancedAuthorize
            cb(group, authActive)
        end)

        -- Return whether the given vehicle plate has saved tuning data
        Core.RegisterServerCallback('m-tuning:getVehicleStatus', function(source, cb, plate)
            if not plate then cb(false) return end
            cb(VehicleHasTuning(plate))
        end)

    elseif Config.Framework == 'QBCore' then

        Core.Functions.CreateCallback('m-tuning:sqlDta', function(source, cb, plate, dataType)
            if not plate or not dataType then cb(nil) return end
            local data = GetVehicleData(plate, dataType)
            cb(data)
        end)

        Core.Functions.CreateCallback('m-tuning:getPresets', function(source, cb, plate)
            if not plate then cb({}) return end
            local identifier = GetMTuningIdentifier(source)
            if not identifier then cb({}) return end
            cb(GetPresets(identifier, plate))
        end)

        Core.Functions.CreateCallback('m-tuning:hasItem', function(source, cb)
            if not Config.ItemControl then cb(true) return end
            cb(PlayerHasItem(source, Config.TabletItemName))
        end)

        Core.Functions.CreateCallback('m-tuning:hasCheckerItem', function(source, cb)
            if not Config.ItemControl then cb(true) return end
            cb(PlayerHasItem(source, Config.CheckerItemName))
        end)

        Core.Functions.CreateCallback('m-tuning:checkJob', function(source, cb)
            cb(PlayerHasAuthorizedJob(source))
        end)

        Core.Functions.CreateCallback('m-tuning:getGroup', function(source, cb)
            local group      = GetMTuningGroup(source)
            local authActive = Config.AdvancedAuthorize and PlayerHasAdvancedAuth(source) or not Config.AdvancedAuthorize
            cb(group, authActive)
        end)

        Core.Functions.CreateCallback('m-tuning:getVehicleStatus', function(source, cb, plate)
            if not plate then cb(false) return end
            cb(VehicleHasTuning(plate))
        end)

    end
end)

-- ==========================================
-- Network events
-- ==========================================

-- Save or update the vehicle's active handling snapshot in the DB
RegisterNetEvent('m-tuning:CreateTableData', true)
AddEventHandler('m-tuning:CreateTableData', function(plate, data, dataType)
    if not plate or not data or not dataType then return end
    if type(plate) ~= 'string' or #plate > 20 then return end
    if type(dataType) ~= 'string' then return end
    SaveVehicleData(plate, data, dataType)
end)

-- Save a named preset for the calling player's vehicle
RegisterNetEvent('m-tuning:savePreset', true)
AddEventHandler('m-tuning:savePreset', function(plate, vehicleData, presetName)
    local source = source
    if not plate or not vehicleData or not presetName then return end
    if type(presetName) ~= 'string' or #presetName > 100 then return end
    local identifier = GetMTuningIdentifier(source)
    if not identifier then return end
    SavePreset(identifier, plate, presetName, vehicleData)
end)

-- Delete a named preset for the calling player's vehicle
RegisterNetEvent('m-tuning:deletePreset', true)
AddEventHandler('m-tuning:deletePreset', function(plate, presetName)
    local source = source
    if not plate or not presetName then return end
    local identifier = GetMTuningIdentifier(source)
    if not identifier then return end
    DeletePreset(identifier, plate, presetName)
end)

-- Erase all tuning data for a vehicle (used by police DELETE TUNER button)
RegisterNetEvent('m-tuning:cleanVehicleData', true)
AddEventHandler('m-tuning:cleanVehicleData', function(plate)
    local source = source
    if not plate then return end
    -- Only authorised jobs may clean a vehicle
    if not PlayerHasAuthorizedJob(source) then
        print('[m-tuning] Unauthorised cleanVehicleData attempt from source ' .. source)
        return
    end
    DeleteVehicleData(plate)
end)

-- A client entering a vehicle requests its saved handling data
RegisterNetEvent('m-tuning:requestVehicleData', true)
AddEventHandler('m-tuning:requestVehicleData', function(plate)
    local source = source
    if not plate then return end

    local data = GetVehicleData(plate, 'CurrentVehicleData')
    if not data then
        data = GetVehicleData(plate, 'DefaultData')
    end

    if data then
        TriggerClientEvent('m-tuning:applyVehicleData', source, plate, data)
    end
end)
