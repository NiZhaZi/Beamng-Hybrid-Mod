-- evdrive.lua - 2024.5.5 16:54 - advance control for EVs
-- by NZZ
-- version 0.0.7 alpha
-- final edit - 2024.11.25 20:35

local M = {}

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local abs = math.abs

local battery = nil
local mainMotors = nil
local subMotors = nil
local leftMotors = nil
local rightMotors = nil
local motors = nil

local edriveMode = nil
local regenLevel = 5
local brakeMode = nil
local ifAssistSteering = nil
local assistSteeringSpeed = nil

local ondemandMaxRPM = nil

local function onInit(jbeamData)
    battery =  jbeamData.energyStorage or "mainBattery"
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    brakeMode = jbeamData.brakeMode or "onePedal" -- "onePedal" "CRBS" "sport"
    ifAssistSteering = jbeamData.ifAssistSteering or false
    assistSteeringSpeed = jbeamData.assistSteeringSpeed or 75

    motors = {}

    mainMotors = {}
    local mainMotorNames = jbeamData.mainMotorNames or {"mainMotor"}
    if mainMotorNames then
        for _, v in ipairs(mainMotorNames) do
            local mainMotor = powertrain.getDevice(v)
            if mainMotor then
                table.insert(mainMotors, mainMotor)
                table.insert(motors, mainMotor)
                mainMotor.originalRegenTorque = mainMotor.maxWantedRegenTorque
                mainMotor.electricsThrottleName = "mainThrottle"
            end
        end
    end

    subMotors = {}
    local subMotorNames = jbeamData.subMotorNames or {"subMotor"}
    if subMotorNames then
        for _, v in ipairs(subMotorNames) do
            local subMotor = powertrain.getDevice(v)
            if subMotor then
                table.insert(subMotors, subMotor)
                table.insert(motors, subMotor)
                subMotor.originalRegenTorque = subMotor.maxWantedRegenTorque
                subMotor.electricsThrottleName = "subThrottle"
            end
        end
    end

    if ifAssistSteering then

        leftMotors = {}
        local leftMotorNames = jbeamData.leftMotorNames
        if leftMotorNames then
            for _, v in ipairs(leftMotorNames) do
                local leftMotor = powertrain.getDevice(v)
                if leftMotor then
                    table.insert(leftMotors, leftMotor)
                end
            end
        end

        rightMotors = {}
        local rightMotorNames = jbeamData.rightMotorNames
        if rightMotorNames then
            for _, v in ipairs(rightMotorNames) do
                local rightMotor = powertrain.getDevice(v)
                if rightMotor then
                    table.insert(rightMotors, rightMotor)
                end
            end
        end

    end

    ondemandMaxRPM = jbeamData.ondemandMaxRPM or 50
end

local function ifLowSpeed()
    if input.throttle > 0.8 and electrics.values.airspeed <= 5 * 3.6 then
        return true
    else
        return false
    end
    return false
end

local function selectBrakeMode(mode)
    if mode then
        brakeMode = mode
    else
        if mode == "onePedal" then
            mode = "CRBS"
        elseif mode == "CRBS" then
            mode = "sport"
        elseif mode == "sport" then
            mode = "onePedal"
        end
    end
end

local function switchAWD(mode)
    edriveMode = mode
end

local function switchBrakeMode(mode)
    selectBrakeMode(mode)
    gui.message({ txt = mode .. " mode on" }, 5, "", "")
end

local function switchAWDMode(mode)
    switchAWD(mode)
    if edriveMode == "fullTime" then
        gui.message({ txt = "Full-time AWD mode on" }, 5, "", "")
    elseif edriveMode == "partTime" then
        gui.message({ txt = "On-demand AWD mode on" }, 5, "", "")
    elseif edriveMode == "subDrive" then
        gui.message({ txt = "Main Motors off" }, 5, "", "")
    else
        gui.message({ txt = "Sub Motors off" }, 5, "", "")
    end
end

local function updateGFX(dt)
    -- log("D", "", electrics.values.ignitionLevel)
    -- battery begin
    local storage = energyStorage.getStorage(battery)
    electrics.values.remainingpower = storage.remainingRatio
    electrics.values.evfuel = electrics.values.remainingpower * 100
    -- battery end

    -- ev part time drive begin
    local mianRPM = 0
    local subRPM = 0
    for _, v in ipairs(mainMotors) do
        if v then
            mianRPM = mianRPM + v.outputAV1 * avToRPM
        end
    end
    mianRPM = mianRPM / #mainMotors
    for _, v in ipairs(subMotors) do
        if v then
            subRPM = subRPM + v.outputAV1 * avToRPM
        end
    end
    subRPM = subRPM / #subMotors


    electrics.values.mainThrottle = electrics.values.throttle
    electrics.values.subThrottle = electrics.values.throttle
    if edriveMode == "partTime" then
        if abs(mianRPM - subRPM) >= ondemandMaxRPM or ifLowSpeed() then
            electrics.values.subThrottle = electrics.values.throttle
        else
            electrics.values.subThrottle = 0
        end
    elseif edriveMode == "fullTime" then
        electrics.values.subThrottle = electrics.values.throttle
    elseif edriveMode == "subDrive" then
        electrics.values.mainThrottle = 0
    else
        electrics.values.subThrottle = 0    
    end
    -- local direction = electrics.values.subThrottle
    -- ev part time drive end

    -- advance brake begin
    for _, v in ipairs(motors) do
        if brakeMode == "sport" then
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * input.brake
            end
        elseif brakeMode == "CRBS" then
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * input.brake * 2
                if v.maxWantedRegenTorque > v.originalRegenTorque then
                    v.maxWantedRegenTorque = v.originalRegenTorque
                end
            end
            if input.brake > 0.5 then
                electrics.values.brake = (input.brake - 0.5) * 2
            end
        elseif brakeMode == "onePedal" then
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque
            end
        end
    end

    local ign
    if electrics.values.ignitionLevel == 2 then
        ign = 1
    else
        ign = 0
    end
    electrics.values.brakewithign = input.brake * ign
    -- advance brake end

    -- assist steering begin
    local speed = electrics.values.wheelspeed / 0.2778
    local steering = input.steering
    local direction = fsign(steering)

    if ifAssistSteering and speed > assistSteeringSpeed and math.abs(steering) > 0.2 then
        -- log("", "", direction)
        if direction == 1 then
            for _, v in ipairs(rightMotors) do
                v.maxWantedRegenTorque = v.originalRegenTorque
            end
            electrics.values.throttle_L = electrics.values.throttle
            electrics.values.throttle_R = 0
        elseif direction == -1 then
            for _, v in ipairs(leftMotors) do
                v.maxWantedRegenTorque = v.originalRegenTorque
            end
            electrics.values.throttle_L = 0
            electrics.values.throttle_R = electrics.values.throttle
        end
        -- log("", "throttle_L ", electrics.values.throttle_L)
        -- log("", "throttle_R ", electrics.values.throttle_R)
    else
        electrics.values.throttle_L = electrics.values.throttle
        electrics.values.throttle_R = electrics.values.throttle
    end
    -- assist steering end

end

local function getMainMotors()
    return mainMotors
end

local function getSubMotors()
    return subMotors
end

local function getMotors()
    return motors
end

-- public interface

M.switchBrakeMode = switchBrakeMode
M.switchAWDMode = switchAWDMode

M.init = onInit
M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX

M.getMainMotors = getMainMotors
M.getSubMotors = getSubMotors
M.getMotors = getMotors

rawset(_G, "evdrive", M)
return M