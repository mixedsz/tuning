-- ==========================================
-- m-tuning | server/functions.lua
-- Database helpers and player utility functions
-- ==========================================

-- Create required DB tables on resource start
function CreateDatabaseTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mtuning_data` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `plate` VARCHAR(20) NOT NULL,
            `datatype` VARCHAR(50) NOT NULL DEFAULT 'CurrentVehicleData',
            `data` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `plate_datatype` (`plate`, `datatype`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mtuning_presets` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `plate` VARCHAR(20) NOT NULL,
            `name` VARCHAR(100) NOT NULL,
            `vehicledata` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `identifier_plate` (`identifier`, `plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

-- Returns the primary identifier for a connected player
function GetMTuningIdentifier(source)
    if Config.Framework == "ESX" then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then return xPlayer.identifier end
    elseif Config.Framework == "QBCore" then
        local Player = Core.Functions.GetPlayer(source)
        if Player then return Player.PlayerData.citizenid end
    end
    -- Fallback: use license
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if string.sub(id, 1, 8) == "license:" then
            return id
        end
    end
    return nil
end

-- Returns the group/permission level of a player
function GetMTuningGroup(source)
    if Config.Framework == "ESX" then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then return xPlayer.getGroup() end
    elseif Config.Framework == "QBCore" then
        local Player = Core.Functions.GetPlayer(source)
        if Player then return Player.PlayerData.group end
    end
    return "user"
end

-- Returns true if the player has the advanced tab permission
function PlayerHasAdvancedAuth(source)
    local group = GetMTuningGroup(source)
    for _, g in ipairs(Config.AdvancedAuthorizedGroup) do
        if group == g then return true end
    end
    return false
end

-- Returns true if the player has the given item in their inventory
function PlayerHasItem(source, itemName)
    if Config.Framework == "ESX" then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then
            local item = xPlayer.getInventoryItem(itemName)
            return item ~= nil and item.count > 0
        end
    elseif Config.Framework == "QBCore" then
        local Player = Core.Functions.GetPlayer(source)
        if Player then
            local item = Player.Functions.GetItemByName(itemName)
            return item ~= nil and item.amount > 0
        end
    end
    return false
end

-- Returns true if the player's job is in Config.JobAuthorize
function PlayerHasAuthorizedJob(source)
    if Config.Framework == "ESX" then
        local xPlayer = Core.GetPlayerFromId(source)
        if xPlayer then
            for _, job in ipairs(Config.JobAuthorize) do
                if xPlayer.job.name == job then return true end
            end
        end
    elseif Config.Framework == "QBCore" then
        local Player = Core.Functions.GetPlayer(source)
        if Player then
            for _, job in ipairs(Config.JobAuthorize) do
                if Player.PlayerData.job.name == job then return true end
            end
        end
    end
    return false
end

-- ==========================================
-- Database operations
-- ==========================================

-- Upsert vehicle handling data (CurrentVehicleData / DefaultData)
function SaveVehicleData(plate, data, dataType)
    local encoded = json.encode(data)
    MySQL.query.await([[
        INSERT INTO mtuning_data (plate, datatype, data)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE data = ?, updated_at = CURRENT_TIMESTAMP
    ]], { plate, dataType, encoded, encoded })
end

-- Fetch vehicle handling data; returns decoded table or nil
function GetVehicleData(plate, dataType)
    local result = MySQL.query.await(
        'SELECT data FROM mtuning_data WHERE plate = ? AND datatype = ?',
        { plate, dataType }
    )
    if result and #result > 0 then
        return json.decode(result[1].data)
    end
    return nil
end

-- Delete all data rows for a given plate (used by CleanVehicle / DELETE_TUNER)
function DeleteVehicleData(plate)
    MySQL.query.await('DELETE FROM mtuning_data WHERE plate = ?', { plate })
end

-- Returns true if the vehicle has a CurrentVehicleData row in the DB
function VehicleHasTuning(plate)
    local result = MySQL.query.await(
        'SELECT id FROM mtuning_data WHERE plate = ? AND datatype = ?',
        { plate, 'CurrentVehicleData' }
    )
    return result ~= nil and #result > 0
end

-- Upsert a named preset for identifier+plate
function SavePreset(identifier, plate, name, vehicleData)
    local encoded = json.encode(vehicleData)
    local existing = MySQL.query.await(
        'SELECT id FROM mtuning_presets WHERE identifier = ? AND plate = ? AND name = ?',
        { identifier, plate, name }
    )
    if existing and #existing > 0 then
        MySQL.query.await(
            'UPDATE mtuning_presets SET vehicledata = ? WHERE identifier = ? AND plate = ? AND name = ?',
            { encoded, identifier, plate, name }
        )
    else
        MySQL.query.await(
            'INSERT INTO mtuning_presets (identifier, plate, name, vehicledata) VALUES (?, ?, ?, ?)',
            { identifier, plate, name, encoded }
        )
    end
end

-- Returns all presets for identifier+plate as array of { name, vehicleData }
function GetPresets(identifier, plate)
    local result = MySQL.query.await(
        'SELECT name, vehicledata FROM mtuning_presets WHERE identifier = ? AND plate = ? ORDER BY created_at ASC',
        { identifier, plate }
    )
    local presets = {}
    if result and #result > 0 then
        for _, row in ipairs(result) do
            table.insert(presets, {
                name       = row.name,
                vehicleData = json.decode(row.vehicledata)
            })
        end
    end
    return presets
end

-- Delete a single preset by identifier, plate and name
function DeletePreset(identifier, plate, name)
    MySQL.query.await(
        'DELETE FROM mtuning_presets WHERE identifier = ? AND plate = ? AND name = ?',
        { identifier, plate, name }
    )
end
