-- evdrive.lua - 2024.5.5 16:54 - advance control for EVs
-- by NZZ
-- version 0.0.5 alpha
-- final edit - 2024.5.20 21:19

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
local ifAdvanceBrake = nil
local ifSportBrake = nil
local ifAssistSteering = nil
local assistSteeringSpeed = nil

local ondemandMaxRPM = nil

local function onInit(jbeamData)
    battery =  jbeamData.energyStorage or "mainBattery"
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifAdvanceBrake = jbeamData.ifAdvanceBrake or true
    ifSportBrake = jbeamData.ifSportBrake or false
    ifAssistSteering = jbeamData.ifAssistSteering or true
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

local function switchAdvanceBrake()
    ifAdvanceBrake = not ifAdvanceBrake
end

local function switchSportBrake()
    ifSportBrake = not ifSportBrake
end

local function switchAWD(mode)
    edriveMode = mode
end

local function switchBrakeMode(type)
    if type == "advance" then
        switchAdvanceBrake()
        if ifAdvanceBrake then
            gui.message({ txt = "advance brake on" }, 5, "", "")
        else
            gui.message({ txt = "one-pedal brake on" }, 5, "", "")
            ifSportBrake = false
        end
    elseif type == "sport" then
        if ifAdvanceBrake then
            switchSportBrake()
            if ifSportBrake then
                gui.message({ txt = "sport brake on" }, 5, "", "")
            else
                gui.message({ txt = "sport brake off" }, 5, "", "")
            end
        else
            gui.message({ txt = "switch to advance brake firest" }, 5, "", "")
        end
    end
end

local function switchAWDMode(mode)
    switchAWD(mode)
    if edriveMode == "fullTime" then
        gui.message({ txt = "full-time AWD mode on" }, 5, "", "")
    elseif edriveMode == "partTime" then
        gui.message({ txt = "on-demand AWD mode on" }, 5, "", "")
    else
        gui.message({ txt = "AWD mode off" }, 5, "", "")
    end
end

local function updateGFX(dt)
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

    if edriveMode == "partTime" then
        if abs(mianRPM - subRPM) >= ondemandMaxRPM then
            electrics.values.subThrottle = electrics.values.throttle
        else
            electrics.values.subThrottle = 0
        end
    elseif edriveMode == "fullTime" then
        electrics.values.subThrottle = electrics.values.throttle
    else
        electrics.values.subThrottle = 0
    end
    -- ev part time drive end


    -- advance brake begin
    if ifAdvanceBrake then
        for _, v in ipairs(motors) do
            if ifSportBrake then
                if v then
                    v.maxWantedRegenTorque = v.originalRegenTorque * input.brake
                end
                electrics.values.brake = input.brake
            else
                if v then
                    v.maxWantedRegenTorque = v.originalRegenTorque * input.brake * 2
                    if v.maxWantedRegenTorque > v.originalRegenTorque then
                        v.maxWantedRegenTorque = v.originalRegenTorque
                    end
                end
                if input.brake > 0.5 then
                    electrics.values.brake = (input.brake - 0.5) * 2
                end
            end
        end
    else
        for _, v in ipairs(motors) do
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque
            end
        end
        electrics.values.brake = input.brake
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

local function reset(jbeamData)
    switchAWD("partTime")
    ifAdvanceBrake = jbeamData.ifAdvanceBrake or true
    ifSportBrake = jbeamData.ifSportBrake or false
end

-- public interface

M.switchBrakeMode = switchBrakeMode
M.switchAWDMode = switchAWDMode

M.init = onInit
M.reset = reset
M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX

return M