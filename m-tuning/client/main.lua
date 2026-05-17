-- ==========================================
-- m-tuning | client/main.lua
-- Client-side core: commands, NUI callbacks, vehicle monitoring
-- ==========================================

Core           = nil
createCallback = nil
local currentVeh  = nil
local isDriftMode = false
local isSportMode = false

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

-- Send the current vehicle's handling snapshot to the NUI
local function SendVehicleDataToNUI()
    if not currentVeh or not DoesEntityExist(currentVeh) then return end
    local vehData = GetVehData(currentVeh)
    SendNUIMessage({ message = 'GET_VEHICLE_DATA', vehicleData = vehData })
end

-- Fetch presets from server and forward to NUI
local function SendPresetsToNUI()
    if not currentVeh or not DoesEntityExist(currentVeh) then return end
    local plate = GetVehicleNumberPlateText(currentVeh)
    createCallback('m-tuning:getPresets', function(presets)
        SendNUIMessage({
            message       = 'GET_CURRENT_DATA',
            GetCurrentData = presets or {}
        })
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
-- Open tablet (tuning)
-- ==========================================
local function OpenTablet()
    while not createCallback do Wait(100) end

    local inVeh, veh = IsInVehicle()
    if not inVeh then
        ClientNotification(Locales.Default['ARE_NOT_VEHICLE'], 'error')
        return
    end

    local function DoOpen()
        currentVeh = veh
        local vehName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))

        -- Fetch group/auth and open NUI
        createCallback('m-tuning:getGroup', function(group, authActive)
            SendNUIMessage({
                message    = 'GET_GROUP',
                Auth       = group,
                AuthActive = authActive
            })
        end)

        SendNUIMessage({
            message = 'OPEN_TABLET',
            vehName = vehName,
            Locales = Locales.Default
        })
        SetNuiFocus(true, true)
        isDriftMode = false
        isSportMode = false
    end

    if Config.ItemControl then
        createCallback('m-tuning:hasItem', function(hasItem)
            if not hasItem then
                ClientNotification(Locales.Default['NO_HAVE_TABLET'], 'error')
                return
            end
            DoOpen()
        end)
    else
        DoOpen()
    end
end

-- ==========================================
-- Open checker tablet (police)
-- ==========================================
local function OpenTunerChecker()
    while not createCallback do Wait(100) end

    local inVeh, veh = IsInVehicle()
    if not inVeh then
        ClientNotification(Locales.Default['ARE_NOT_VEHICLE'], 'error')
        return
    end

    createCallback('m-tuning:checkJob', function(authorized)
        if not authorized then
            ClientNotification(Locales.Default['ARE_NOT_POLICE'], 'error')
            return
        end

        local function DoOpenChecker()
            currentVeh = veh
            SendNUIMessage({
                message = 'OPEN_POLICE_TABLET',
                Locales = Locales.Default
            })
            SetNuiFocus(true, true)
        end

        if Config.ItemControl then
            createCallback('m-tuning:hasCheckerItem', function(hasItem)
                if not hasItem then
                    ClientNotification(Locales.Default['NO_HAVE_TABLET'], 'error')
                    return
                end
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
RegisterCommand(Config.OpenCommand, function()
    OpenTablet()
end, false)

RegisterCommand(Config.TunerChecker, function()
    OpenTunerChecker()
end, false)

-- ==========================================
-- NUI Callbacks
-- ==========================================

RegisterNUICallback('CLOSE_TABLET', function(_, cb)
    SetNuiFocus(false, false)
    isDriftMode = false
    isSportMode = false
    cb('ok')
end)

-- Basic tuning page sliders: boost, acceleration, gear change, brake bias, drivetrain
RegisterNUICallback('SAVE_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    setVehData(currentVeh, data)
    -- Snapshot full vehicle state after the 5 basic sliders are applied and persist it
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

-- Save a named advanced preset (also applies it immediately)
RegisterNUICallback('SAVE_ADVANCED_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    if not data.vehicleData or not data.DataName or data.DataName == '' then cb('ok') return end

    local plate = GetVehicleNumberPlateText(currentVeh)
    -- Save flat vehicleData to preset DB row (InsertXML will re-wrap when applying)
    TriggerServerEvent('m-tuning:savePreset', plate, data.vehicleData, data.DataName)
    -- setAdvancedData expects { vehicleData = {flat handling} } as its data arg
    setAdvancedData(currentVeh, { vehicleData = data.vehicleData }, false, false)
    ClientNotification(Locales.Default['ADVANCED_MODE_NOTIFY'], 'success')
    cb('ok')
end)

-- Fetch presets and push them to the NUI
RegisterNUICallback('GET_CUSTOMS_DATA', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    SendPresetsToNUI()
    cb('ok')
end)

-- Delete a preset by name, then refresh the presets list
RegisterNUICallback('DELETE_PRESET', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    if not data.vehicleData or not data.vehicleData.name then cb('ok') return end

    local plate = GetVehicleNumberPlateText(currentVeh)
    TriggerServerEvent('m-tuning:deletePreset', plate, data.vehicleData.name)
    ClientNotification(Locales.Default['DELETE_PRESET'], 'success')
    cb('ok')
end)

-- Reset vehicle handling to saved default (or factory if no DB record)
RegisterNUICallback('DEFAULT_BACK', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    local plate = GetVehicleNumberPlateText(currentVeh)
    DefaultAdvancedData(currentVeh, plate, nil)
    isDriftMode = false
    isSportMode = false
    ClientNotification(Locales.Default['DEFAULT_BACKE'], 'success')
    cb('ok')
end)

-- Change driving mode: driftMode | sportMode | normalMode
RegisterNUICallback('CHANGE_MODE', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    local mode = data.mode

    if mode == 'driftMode' then
        isDriftMode = true
        isSportMode = false

        -- Drift: full rear-wheel bias, reduced traction, looser steering
        local d = GetVehData(currentVeh)
        d.powerBiasValue       = 0.01
        d.tireGripMaxValue     = d.tireGripMaxValue     * 0.65
        d.tireGripMinValue     = d.tireGripMinValue     * 0.65
        d.offRoadTractionValue = d.offRoadTractionValue * 1.5
        d.lowSpeedBurnoutValue = 1.5
        d.handBrakeStrength    = d.handBrakeStrength    * 1.5
        -- setAdvancedData expects { vehicleData = {flat handling} }
        setAdvancedData(currentVeh, { vehicleData = d }, false, false)
        ClientNotification(Locales.Default['DRIFT_MODE_NOTIFY'], 'success')

    elseif mode == 'sportMode' then
        isDriftMode = false
        isSportMode = true

        -- Sport: boost drive force directly via handling floats (persists through engine events)
        -- then also apply the engine multipliers on top for immediate feel
        local d = GetVehData(currentVeh)
        d.powerValue    = d.powerValue    * (Config.SportModeSettings['PowerMultiplier']  / 10.0)
        d.topSpeedValue = d.topSpeedValue + Config.SportModeSettings['fInitialDriveMaxFlatVel']
        d.driveInertiaValue = Config.SportModeSettings['fDriveInertia']
        d.shiftUpValue   = Config.SportModeSettings['fClutchChangeRateScaleUpShift']
        d.shiftDownValue = Config.SportModeSettings['fClutchChangeRateScaleDownShift']
        setAdvancedData(currentVeh, { vehicleData = d }, false, false)
        -- Multipliers stack on top of the handling floats for extra punch
        SetVehicleEnginePowerMultiplier(currentVeh, Config.SportModeSettings['PowerMultiplier'])
        SetVehicleEngineTorqueMultiplier(currentVeh, Config.SportModeSettings['TorqueMultiplier'])
        ClientNotification(Locales.Default['SPORT_MODE_NOTIFY'], 'success')

    elseif mode == 'normalMode' then
        isDriftMode = false
        isSportMode = false
        DefaultAdvancedData(currentVeh, GetVehicleNumberPlateText(currentVeh), nil)
        ClientNotification(Locales.Default['NORMAL_MODE_NOTIFY'], 'success')
    end

    ClientNotification(Locales.Default['CHANGED_MODE'], 'success')
    cb('ok')
end)

-- Police checker: ask server if this vehicle has tuning data
RegisterNUICallback('GET_VEHICLE_STATUS', function(_, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end
    local plate = GetVehicleNumberPlateText(currentVeh)
    createCallback('m-tuning:getVehicleStatus', function(isTuned)
        SendNUIMessage({
            message           = 'SET_VEHICLE_STATUS',
            vehiclestatusPage = isTuned and 'tunedVehicle' or 'tuneClear'
        })
    end, plate)
    cb('ok')
end)

-- Generate and push XML handling string to the NUI.
-- When called with vehicleData (from InsertXML / preset page), ALSO apply that
-- preset's handling to the vehicle — this is what makes presets actually work.
RegisterNUICallback('GET_XML_DATA', function(data, cb)
    if not currentVeh or not DoesEntityExist(currentVeh) then cb('ok') return end

    local vehData
    if data and data.vehicleData then
        -- data.vehicleData = selectedData = { name, vehicleData = {flat handling} }
        -- flat handling lives one level deeper
        vehData = data.vehicleData.vehicleData or data.vehicleData

        -- Apply the preset to the vehicle right now
        -- setAdvancedData(veh, { vehicleData={flat} }, false, false) is the correct call
        -- data.vehicleData already has the right shape: { name, vehicleData={flat} }
        setAdvancedData(currentVeh, data.vehicleData, false, false)
        ClientNotification(Locales.Default['ADVANCED_MODE_NOTIFY'], 'success')
    else
        vehData = GetVehData(currentVeh)
    end

    SendNUIMessage({
        message = 'GET_XML_DATA',
        XMLData = GenerateHandlingXML(vehData)
    })
    cb('ok')
end)

-- ==========================================
-- Server -> client events
-- ==========================================

-- Restore saved handling when entering a vehicle (triggered by server).
-- CurrentVehicleData is stored as { vehicleData = {flat handling} } by setAdvancedData,
-- so we must unwrap the inner flat table before passing to DefaultAdvancedData.
RegisterNetEvent('m-tuning:applyVehicleData', true)
AddEventHandler('m-tuning:applyVehicleData', function(plate, data)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then return end
    if GetVehicleNumberPlateText(veh) ~= plate then return end
    -- Unwrap wrapper if present; DefaultAdvancedData expects a flat handling table
    local flatData = (data and data.vehicleData) and data.vehicleData or data
    DefaultAdvancedData(veh, plate, flatData)
end)

-- ==========================================
-- Vehicle entry monitor — applies saved tuning on enter
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
            local plate = GetVehicleNumberPlateText(veh)
            TriggerServerEvent('m-tuning:requestVehicleData', plate)

        elseif veh == 0 and lastVeh ~= 0 then
            lastVeh    = 0
            currentVeh = nil
            isDriftMode = false
            isSportMode = false
        end
    end
end)

-- ==========================================
-- Drift mode speed enforcer
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
                    DefaultAdvancedData(currentVeh, GetVehicleNumberPlateText(currentVeh), nil)
                end
            end
        end
    end)
end
