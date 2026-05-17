-- ==========================================
-- m-tuning | client/main.lua
-- ==========================================

Core           = nil
createCallback = nil
local currentVeh  = nil
local isDriftMode = false
local isSportMode = false

-- Factory (unmodified) handling values cached the moment we enter a vehicle,
-- before applyVehicleData runs. Every mode / save calculation is based on
-- these values so nothing can ever compound or stack.
local vehicleFactory = {}   -- [veh entity] = flat handling table

-- ==========================================
-- Framework initialisation
-- ==========================================
CreateThread(function()
    Core, _ = GetCore()
    if Config.Framework == 'ESX' then
        createCallback = Core.TriggerServerCallback
    else
        createCallback = Core.Functions.TriggerCallback
    end
end)

-- ==========================================
-- Internal helpers
-- ==========================================

local function IsInVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    return veh ~= 0 and DoesEntityExist(veh), veh
end

-- Returns the factory handling table for the current vehicle.
-- If we somehow don't have it cached yet, read live (safe fallback).
local function GetFactory()
    if currentVeh and vehicleFactory[currentVeh] then
        return vehicleFactory[currentVeh]
    end
    if currentVeh and DoesEntityExist(currentVeh) then
        return GetVehData(currentVeh)
    end
    return {}
end

-- Shallow-copy a table so we can modify it without touching the original
local function ShallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Send the current vehicle's handling snapshot to the NUI
local function SendVehicleDataToNUI()
    if not currentVeh or not DoesEntityExist(currentVeh) then return end
    SendNUIMessage({ message = 'GET_VEHICLE_DATA', vehicleData = GetVehData(currentVeh) })
end

-- Fetch custom presets from server and push to NUI
local function SendPresetsToNUI()
    if not currentVeh or not DoesEntityExist(currentVeh) then return end
    local plate = GetVehicleNumberPlateText(currentVeh)
    createCallback('m-tuning:getPresets', function(presets)
        SendNUIMessage({ message = 'GET_CURRENT_DATA', GetCurrentData = presets or {} })
    end, plate)
end

-- Build GTA5-compatible handling XML from a vehicleData table
local function GenerateHandlingXML(d)
    if not d then return '' end
    return string.format([[<Item type="CHandlingData">
  <handlingName>CUSTOM_TUNING</handlingName>
  <fMass value="%.6f"/>
  <fInitialDragCoeff value="%.6f"/>
  <fDownforceModifier value="%.6f"/>
  <fInitialDriveForce value="%.6f"/>
  <fDriveInertia value="%.6f"/>
  <fInitialDriveMaxFlatVel value="%.6f"/>
  <nInitialDriveGears value="%d"/>
  <fClutchChangeRateScaleUpShift value="%.6f"/>
  <fClutchChangeRateScaleDownShift value="%.6f"/>
  <fDriveBiasFront value="%.6f"/>
  <fBrakeForce value="%.6f"/>
  <fBrakeBiasFront value="%.6f"/>
  <fHandBrakeForce value="%.6f"/>
  <fTractionCurveMax value="%.6f"/>
  <fTractionCurveMin value="%.6f"/>
  <fTractionCurveLateral value="%.6f"/>
  <fTractionBiasFront value="%.6f"/>
  <fTractionLossMult value="%.6f"/>
  <fLowSpeedTractionLossMult value="%.6f"/>
  <fSteeringLock value="%.6f"/>
  <fSuspensionForce value="%.6f"/>
  <fSuspensionCompDamp value="%.6f"/>
  <fSuspensionReboundDamp value="%.6f"/>
  <fSuspensionUpperLimit value="%.6f"/>
  <fSuspensionLowerLimit value="%.6f"/>
  <fSuspensionRaise value="%.6f"/>
  <fSuspensionBiasFront value="%.6f"/>
  <fAntiRollBarForce value="%.6f"/>
  <fAntiRollBarBiasFront value="%.6f"/>
  <fRollCentreHeightFront value="%.6f"/>
  <fRollCentreHeightRear value="%.6f"/>
</Item>]],
        tonumber(d.fmassValue)                       or 0.0,
        tonumber(d.airResistanceValue)               or 0.0,
        tonumber(d.downForceValue)                   or 0.0,
        tonumber(d.powerValue)                       or 0.0,
        tonumber(d.driveInertiaValue)                or 0.0,
        tonumber(d.topSpeedValue)                    or 0.0,
        math.floor(tonumber(d.ofGearsValue)          or 4),
        tonumber(d.shiftUpValue)                     or 0.0,
        tonumber(d.shiftDownValue)                   or 0.0,
        tonumber(d.powerBiasValue)                   or 0.0,
        tonumber(d.brakeStrengthValue)               or 0.0,
        tonumber(d.brakeBiasValue)                   or 0.0,
        tonumber(d.handBrakeStrength)                or 0.0,
        tonumber(d.tireGripMaxValue)                 or 0.0,
        tonumber(d.tireGripMinValue)                 or 0.0,
        tonumber(d.tractionCurveValue)               or 0.0,
        tonumber(d.tireGripBiasValue)                or 0.0,
        tonumber(d.offRoadTractionValue)             or 0.0,
        tonumber(d.lowSpeedBurnoutValue)             or 0.0,
        tonumber(d.maxSteerAngleValue)               or 0.0,
        tonumber(d.springStrengthValue)              or 0.0,
        tonumber(d.springCompDampenStrengthValue)    or 0.0,
        tonumber(d.springReboundDampenStrengthValue) or 0.0,
        tonumber(d.suspensionUpperLimitValue)        or 0.0,
        tonumber(d.suspensionLowerLimitValue)        or 0.0,
        tonumber(d.suspensionRaiseValue)             or 0.0,
        tonumber(d.strengthBiasValue)                or 0.0,
        tonumber(d.antirollStrengthValue)            or 0.0,
        tonumber(d.antirollStrengthBiasValue)        or 0.0,
        tonumber(d.rollCentreFrontValue)             or 0.0,
        tonumber(d.rollBackFrontValue)               or 0.0
    )
end

-- ==========================================
-- Open tuning tablet
-- ==========================================
local function OpenTablet()
    while not createCallback do Wait(100) end
    local inVeh, veh = IsInVehicle()
    if not inVeh then ClientNotification(Locales.Default['ARE_NOT_VEHICLE'], 'error') return end

    local function DoOpen()
        currentVeh = veh
        local vehName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
        createCallback('m-tuning:getGroup', function(group, authActive)
            SendNUIMessage({ message = 'GET_GROUP', Auth = group, AuthActive = authActive })
        end)
        SendNUIMessage({ message = 'OPEN_TABLET', vehName = vehName, Locales = Locales.Default })
        SetNuiFocus(true, true)
        isDriftMode = false
        isSportMode = false
    end

    if Config.ItemControl then
        createCallback('m-tuning:hasItem', function(hasItem)
            if not hasItem then ClientNotification(Locales.Default['NO_HAVE_TABLET'], 'error') return end
            DoOpen()
        end)
    else
        DoOpen()
    end
end

-- ==========================================
-- Open police checker tablet
-- ==========================================
local function OpenTunerChecker()
    while not createCallback do Wait(100) end
    local inVeh, veh = IsInVehicle()
    if not inVeh then ClientNotification(Locales.Default['ARE_NOT_VEHICLE'], 'error') return end

    createCallback('m-tuning:checkJob', function(authorized)
        if not authorized then ClientNotification(Locales.Default['ARE_NOT_POLICE'], 'error') return end

        local function DoOpenChecker()
            currentVeh = veh
            SendNUIMessage({ message = 'OPEN_POLICE_TABLET', Locales = Locales.Default })
            SetNuiFocus(true, true)
        end

        if Config.ItemControl then
            createCallback('m-tuning:hasCheckerItem', function(hasItem)
                if not hasItem then ClientNotification(Locales.Default['NO_HAVE_TABLET'], 'error') return end
                DoOpenChecker()
            end)
        else
            DoOpenChecker()
        end
    end)
end

-- ==========================================
-- Commands
-- ==========================================
RegisterCommand(Config.OpenCommand,  function() OpenTablet()      end, false)
RegisterCommand(Config.TunerChecker, function() OpenTunerChecker() end, false)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback('CLOSE_TABLET', function(_, cb)
    SetNuiFocus(false, false)
    isDriftMode = false
    isSportMode = false
    cb('ok')
end)

-- -------------------------------------------------------
-- SAVE_DATA  (basic tuning page — 5 sliders)
-- All calculations are based on vehicleFactory so they
-- never compound no matter how many times the user saves.
-- -------------------------------------------------------
RegisterNUICallback('SAVE_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end

    local f          = GetFactory()
    local boostVal   = tonumber(data.boost)        or 0.0
    local accelVal   = tonumber(data.acceleration) or (tonumber(f.driveInertiaValue) or 0.5)
    local gearVal    = tonumber(data.gearchange)   or (tonumber(f.shiftUpValue)      or 1.0)
    local brakeVal   = tonumber(data.breaking)     or (tonumber(f.brakeBiasValue)    or 0.5)
    local driveVal   = tonumber(data.drivetrain)   or (tonumber(f.powerBiasValue)    or 0.5)

    local stockPower = tonumber(f.powerValue)    or 0.28
    local stockSpeed = tonumber(f.topSpeedValue) or 1.4

    -- Map boost slider 0→0.5 to engine force 1×→6× factory value.
    -- At max boost a stock car (0.28) becomes 1.68 — very noticeably fast.
    local newPower    = stockPower * (1.0 + (boostVal / 0.5) * 5.0)
    -- Top speed scales 1×→3× factory. Always from factory, never compounds.
    local newTopSpeed = stockSpeed * (1.0 + (boostVal / 0.5) * 2.0)

    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fInitialDriveForce',              newPower)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fInitialDriveMaxFlatVel',         newTopSpeed)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fDriveInertia',                   accelVal)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fClutchChangeRateScaleUpShift',   gearVal)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fClutchChangeRateScaleDownShift', gearVal)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fBrakeBiasFront',                 brakeVal)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fDriveBiasFront',                 driveVal)

    -- Also boost traction so the extra power doesn't just spin the wheels
    local stockGripMax = tonumber(f.tireGripMaxValue) or 2.5
    local stockGripMin = tonumber(f.tireGripMinValue) or 2.0
    local gripScale    = 1.0 + (boostVal / 0.5) * 0.5  -- up to 1.5× grip at max boost
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fTractionCurveMax', stockGripMax * gripScale)
    SetVehicleHandlingFloat(currentVeh, 'CHandlingData', 'fTractionCurveMin', stockGripMin * gripScale)

    local plate    = GetVehicleNumberPlateText(currentVeh)
    local snapshot = GetVehData(currentVeh)
    TriggerServerEvent('m-tuning:CreateTableData', plate, { vehicleData = snapshot }, 'CurrentVehicleData')
    ClientNotification(Locales.Default['ADVANCED_MODE_NOTIFY'], 'success')
    cb('ok')
end)

-- Push current vehicle handling snapshot to the NUI
RegisterNUICallback('GET_ADVANCED_DATA', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    SendVehicleDataToNUI()
    cb('ok')
end)

-- Save a named advanced preset and apply it to the vehicle immediately
RegisterNUICallback('SAVE_ADVANCED_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    if not data.vehicleData or not data.DataName or data.DataName == '' then cb('ok') return end

    local plate = GetVehicleNumberPlateText(currentVeh)
    TriggerServerEvent('m-tuning:savePreset', plate, data.vehicleData, data.DataName)
    setAdvancedData(currentVeh, { vehicleData = data.vehicleData }, false, false)
    ClientNotification(Locales.Default['ADVANCED_MODE_NOTIFY'], 'success')
    cb('ok')
end)

RegisterNUICallback('GET_CUSTOMS_DATA', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    SendPresetsToNUI()
    cb('ok')
end)

RegisterNUICallback('DELETE_PRESET', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    if not data.vehicleData or not data.vehicleData.name then cb('ok') return end
    TriggerServerEvent('m-tuning:deletePreset', GetVehicleNumberPlateText(currentVeh), data.vehicleData.name)
    ClientNotification(Locales.Default['DELETE_PRESET'], 'success')
    cb('ok')
end)

-- Reset handling to the cached factory values for this vehicle
RegisterNUICallback('DEFAULT_BACK', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    local plate = GetVehicleNumberPlateText(currentVeh)
    local f     = GetFactory()
    setAdvancedData(currentVeh, { vehicleData = f }, false, false)
    TriggerServerEvent('m-tuning:CreateTableData', plate, { vehicleData = f }, 'CurrentVehicleData')
    isDriftMode = false
    isSportMode = false
    ClientNotification(Locales.Default['DEFAULT_BACKE'], 'success')
    cb('ok')
end)

-- -------------------------------------------------------
-- CHANGE_MODE  (preset page built-in modes)
-- HTML sends 'DriftMode' / 'SportMode' / 'NormalMode'
-- All calculations are based on vehicleFactory — no stacking.
-- -------------------------------------------------------
RegisterNUICallback('CHANGE_MODE', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end

    local modeLower = string.lower(data.mode or '')
    local f         = GetFactory()
    local plate     = GetVehicleNumberPlateText(currentVeh)

    local stockPower    = tonumber(f.powerValue)           or 0.28
    local stockSpeed    = tonumber(f.topSpeedValue)        or 1.4
    local stockInertia  = tonumber(f.driveInertiaValue)    or 0.5
    local stockShiftUp  = tonumber(f.shiftUpValue)         or 1.0
    local stockShiftDn  = tonumber(f.shiftDownValue)       or 1.0
    local stockGripMax  = tonumber(f.tireGripMaxValue)     or 2.5
    local stockGripMin  = tonumber(f.tireGripMinValue)     or 2.0
    local stockOffRoad  = tonumber(f.offRoadTractionValue) or 1.0
    local stockHBrake   = tonumber(f.handBrakeStrength)    or 0.5

    if modeLower == 'driftmode' then
        isDriftMode = true
        isSportMode = false

        local d = ShallowCopy(f)
        d.powerValue           = stockPower * 1.8   -- enough grunt to drift
        d.topSpeedValue        = stockSpeed * 2.2   -- faster than stock but not stupid
        d.powerBiasValue       = 0.01               -- pure RWD
        d.tireGripMaxValue     = stockGripMax * 0.50  -- slide easily
        d.tireGripMinValue     = stockGripMin * 0.50
        d.offRoadTractionValue = stockOffRoad * 2.0
        d.lowSpeedBurnoutValue = 2.5
        d.handBrakeStrength    = stockHBrake  * 2.5
        d.shiftUpValue         = math.min(stockShiftUp * 3.0, 10.0)
        d.shiftDownValue       = math.min(stockShiftDn * 3.0, 10.0)
        setAdvancedData(currentVeh, { vehicleData = d }, false, false)
        ClientNotification(Locales.Default['DRIFT_MODE_NOTIFY'], 'success')

    elseif modeLower == 'sportmode' then
        isDriftMode = false
        isSportMode = true

        local d = ShallowCopy(f)
        d.powerValue        = stockPower * 4.0          -- 4× factory power
        d.topSpeedValue     = stockSpeed * 3.5          -- 3.5× factory top speed
        d.driveInertiaValue = math.min(stockInertia * 2.0, 3.0)
        d.shiftUpValue      = math.min(stockShiftUp * 5.0, 10.0)
        d.shiftDownValue    = math.min(stockShiftDn * 5.0, 10.0)
        d.tireGripMaxValue  = math.min(stockGripMax * 1.5, 10.0)  -- more grip to use the power
        d.tireGripMinValue  = math.min(stockGripMin * 1.5, 10.0)
        setAdvancedData(currentVeh, { vehicleData = d }, false, false)
        -- Engine multipliers stack on top of the handling floats for instant feel
        SetVehicleEnginePowerMultiplier(currentVeh,  Config.SportModeSettings['PowerMultiplier'])
        SetVehicleEngineTorqueMultiplier(currentVeh, Config.SportModeSettings['TorqueMultiplier'])
        ClientNotification(Locales.Default['SPORT_MODE_NOTIFY'], 'success')

    elseif modeLower == 'normalmode' then
        isDriftMode = false
        isSportMode = false
        -- Restore exact factory values — no DB lookup needed
        setAdvancedData(currentVeh, { vehicleData = f }, false, false)
        TriggerServerEvent('m-tuning:CreateTableData', plate, { vehicleData = f }, 'CurrentVehicleData')
        ClientNotification(Locales.Default['NORMAL_MODE_NOTIFY'], 'success')
    end

    ClientNotification(Locales.Default['CHANGED_MODE'], 'success')
    cb('ok')
end)

-- Police checker: ask server if vehicle has saved tuning data
RegisterNUICallback('GET_VEHICLE_STATUS', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    createCallback('m-tuning:getVehicleStatus', function(isTuned)
        SendNUIMessage({
            message           = 'SET_VEHICLE_STATUS',
            vehiclestatusPage = isTuned and 'tunedVehicle' or 'tuneClear'
        })
    end, GetVehicleNumberPlateText(currentVeh))
    cb('ok')
end)

-- Generate handling XML and, when called from InsertXML, apply the preset too
RegisterNUICallback('GET_XML_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end

    local vehData
    if data and data.vehicleData then
        -- InsertXML sends { vehicleData = selectedData } where
        -- selectedData = { name, vehicleData = {flat handling} }
        vehData = data.vehicleData.vehicleData or data.vehicleData
        -- Apply the preset — data.vehicleData has shape { name, vehicleData={flat} }
        -- which is exactly what setAdvancedData(veh, x, false, false) expects
        setAdvancedData(currentVeh, data.vehicleData, false, false)
        ClientNotification(Locales.Default['ADVANCED_MODE_NOTIFY'], 'success')
    else
        vehData = GetVehData(currentVeh)
    end

    SendNUIMessage({ message = 'GET_XML_DATA', XMLData = GenerateHandlingXML(vehData) })
    cb('ok')
end)

-- ==========================================
-- Server → client events
-- ==========================================

-- Apply saved tuning when entering a vehicle.
-- CurrentVehicleData is stored as { vehicleData = {flat} } by setAdvancedData.
RegisterNetEvent('m-tuning:applyVehicleData', true)
AddEventHandler('m-tuning:applyVehicleData', function(plate, data)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then return end
    if GetVehicleNumberPlateText(veh) ~= plate then return end
    local flatData = (data and data.vehicleData) and data.vehicleData or data
    DefaultAdvancedData(veh, plate, flatData)
end)

-- ==========================================
-- Vehicle entry monitor
-- Cache factory values BEFORE requesting saved tuning so
-- GetFactory() always returns the original unmodified data.
-- ==========================================
CreateThread(function()
    local lastVeh = 0
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and veh ~= lastVeh then
            lastVeh    = veh
            currentVeh = veh
            -- Read factory values NOW, before applyVehicleData arrives from server
            vehicleFactory[veh] = GetVehData(veh)
            TriggerServerEvent('m-tuning:requestVehicleData', GetVehicleNumberPlateText(veh))

        elseif veh == 0 and lastVeh ~= 0 then
            vehicleFactory[lastVeh] = nil   -- free memory when leaving vehicle
            lastVeh     = 0
            currentVeh  = nil
            isDriftMode = false
            isSportMode = false
        end
    end
end)

-- ==========================================
-- Drift mode speed enforcer — reverts to factory if over the limit
-- ==========================================
if Config.DriftModeLimit then
    CreateThread(function()
        while true do
            Wait(750)
            if isDriftMode and currentVeh and DoesEntityExist(currentVeh) then
                local speed = GetEntitySpeed(currentVeh)
                local displaySpeed = Config.MPH and (speed * 2.236936) or (speed * 3.6)
                if displaySpeed > Config.MaxDriftSpeed then
                    isDriftMode = false
                    ClientNotification(Locales.Default['NORMAL_MODE_NOTIFY'], 'error')
                    local f = GetFactory()
                    setAdvancedData(currentVeh, { vehicleData = f }, false, false)
                end
            end
        end
    end)
end
