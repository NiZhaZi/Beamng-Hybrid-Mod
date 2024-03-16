-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local abs = math.abs

local mainMotors = nil
local subMotors = nil

local edriveMode = nil
local regenLevel = 5
local ifComfortRegen = nil
local comfortRegenBegine = nil
local comfortRegenEnd = nil

local ondemandMaxRPM = nil

local function onInit(jbeamData)
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifComfortRegen = jbeamData.ifComfortRegen or true
    comfortRegenBegine = jbeamData.comfortRegenBegine or 0.75
    comfortRegenEnd = jbeamData.comfortRegenEnd or 0.15

    mainMotors = {}
    local mainMotorNames = jbeamData.mainMotorNames or {"mainMotor"}
    if mainMotorNames then
        for _, v in ipairs(mainMotorNames) do
            local mainMotor = powertrain.getDevice(v)
            if mainMotor then
                table.insert(mainMotors, mainMotor)
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
                subMotor.originalRegenTorque = subMotor.maxWantedRegenTorque
            end
        end
    end

    ondemandMaxRPM = jbeamData.ondemandMaxRPM or 50
end

local function cauculateRegen(percentage)
    if percentage > comfortRegenBegine then
        return 1
    elseif percentage <= comfortRegenBegine and percentage > comfortRegenEnd then
        return percentage
    else
        return comfortRegenEnd
    end
end

local function updateGFX(dt)
    --ev part time drive
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



    --comfortable regen
    if ifComfortRegen then
        local comfortRegen
        for _, v in ipairs(mainMotors) do
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 then
                    v.maxWantedRegenTorque = 0
                else
                    v.maxWantedRegenTorque = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
                    --log("", "hybrid", "hybrid" .. v.maxWantedRegenTorque)
                end
            end
        end
    else
        for _, v in ipairs(mainMotors) do
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 then
                    v.maxWantedRegenTorque = 0
                else
                    v.maxWantedRegenTorque = v.originalRegenTorque * regenLevel
                end
            end
        end
    end
end

-- public interface

M.init = onInit
M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX

return M