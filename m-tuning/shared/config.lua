Config = {}

Config.Framework = "ESX" -- QBCore, ESX
Config.Database = "oxmysql" --oxmysql, ghmattimysql , mysql-asnyc


Config.ItemControl = true              -- If true you can only open menus with items, if false only with commands
Config.TabletItemName = "tunertablet2"   -- Tuner Tablet Item Name
Config.CheckerItemName = "tunerchecker" -- Tuner Checker Tablet Item Name
Config.OpenCommand = "tablet"           -- Tuner Tablet Command
Config.TunerChecker = "tunercheck"      -- Tuner Checker Tablet Command

Config.DriftModeLimit = true
Config.MPH = true                                     -- true = MPH , false = KMH
Config.MaxDriftSpeed = 50                             -- If it is higher than the number you enter here, it cannot drift

Config.JobAuthorize = { 'sasp', 'sherrif', 'police' } -- Professions that can use the tuner checker tablet
Config.AdvancedAuthorize = true                       -- If true, the advanced page is not visible to users, only to the following authorized usersif true, the advanced page is not visible to users, only to the following authorized users
Config.AdvancedAuthorizedGroup = { 'god', 'admin' }   -- Authorizations with access to advanced page
Config.SportModeSettings = {                          -- Sport Mode Handling Settings
    ["fInitialDriveMaxFlatVel"] = 3.0,                -- Doğrudan daha yüksek bir değer belirleyebilirsin
    ["fDriveInertia"] = 3.0,
    ["fClutchChangeRateScaleUpShift"] = 10,
    ["fClutchChangeRateScaleDownShift"] = 10,
    ['PowerMultiplier'] = 25.0,
    ['TorqueMultiplier'] = 25.0
}

ClientNotification = function(message, type) -- You can change notification event here
    if Config.Framework == "ESX" then
        TriggerEvent("esx:showNotification", message)
    elseif Config.Framework == "QBCore" then
        TriggerEvent('QBCore:Notify', message, type, 1500)
    end
end
