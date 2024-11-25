-- motorLimit.lua - 2024.11.25 20:35 - motor torque limit for EVs
-- by NZZ
-- version 0.0.1 alpha
-- final edit - 2024.11.25 20:35

local M = { }

local mainMotors = nil
local subMotors = nil
local motors = nil

local mainOutputLevel = nil
local subOutputLevel = nil

local function setMainMotorsTorqueLimit(num)
    num = math.floor(num)
    mainOutputLevel = math.max(math.min(mainOutputLevel + num, 5), 2)
    for _, v in ipairs(mainMotors) do
        v.maxTorqueLimit = v.maxTorque * mainOutputLevel / 5
    end
    gui.message({ txt = "Main motors output is limited to level " .. tostring(mainOutputLevel - 1) }, 5, "", "")
end

local function setSubMotorsTorqueLimit(num)
    num = math.floor(num)
    subOutputLevel = math.max(math.min(subOutputLevel + num, 5), 2)
    for _, v in ipairs(subMotors) do
        v.maxTorqueLimit = v.maxTorque * subOutputLevel / 5
    end
    gui.message({ txt = "Sub motors output is limited to level " .. tostring(subOutputLevel - 1) }, 5, "", "")
end

local function updateGFX()
    
end

local function init()
    mainOutputLevel = 5
    subOutputLevel = 5
    motors = evdrive:getMotors()
    mainMotors = evdrive:getMainMotors()
    subMotors = evdrive:getSubMotors()
end

local function reset()
    mainOutputLevel = 5
    subOutputLevel = 5
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

M.setMainMotorsTorqueLimit = setMainMotorsTorqueLimit
M.setSubMotorsTorqueLimit = setSubMotorsTorqueLimit

return M