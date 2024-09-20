-- suspension_lift.lua - 2024.4.19 18:30 - suspension lift control
-- by NZZ
-- version 0.0.6 alpha
-- final edit - 2024.9.20 11:57

local M = {}

local floor = math.floor
local ceil = math.ceil

local lift0 = nil
local liftLevel = nil
local dropLevel = nil

local highSpeed = nil

local autoLevel = nil
local otSign = nil
local mode = nil

local function getSign(num)
    if type(num) == "number" then
        if num == 0 or num == -0 then
            return 0
        elseif num > 0 then
            return 1
        else
            return -1
        end
    else
        error("typeError")
    end
end

local function onInit(jbeamData)
    
    lift0 = 0
    electrics.values['lift0'] = lift0

    highSpeed = jbeamData.liftVelocity or 80
    mode = jbeamData.defaultMode or "auto"
    autoLevel = 0

    liftLevel = jbeamData.liftLevel or 0.10
    dropLevel = jbeamData.dropLevel or -0.10
end

local function adjustChassis(para)

    if mode == "manual" then

        lift0 = math.max(math.min(lift0 + para, liftLevel), dropLevel)
        if math.abs(lift0) < 0.0001 then
            lift0 = 0
        end

        local level = getSign(lift0) * math.abs(lift0 / para)
        if level == -0 then
            level = 0
        end
        guihooks.message("Chassis Height is now on level " .. level .. ".", 5, "")

        electrics.values['lift0'] = lift0
    else
        guihooks.message("Chassis Height can not be adjusted manually now.", 5, "")
    end

end

local function resetChassis()

    if mode == "manual" then
        lift0 = 0
        electrics.values['lift0'] = lift0
        guihooks.message("Chassis Height is now on level " .. 0 .. ".", 5, "")
    else
        guihooks.message("Chassis Height can not be adjusted manually now.", 5, "")
    end

end

local function updateGFX(dt)

    local finalLevel = autoLevel
    if mode ~= "outTrouble" and autoLevel == 0 and electrics.values.wheelspeed >= highSpeed / 3.6 then
        finalLevel = dropLevel
    end
    if mode == "auto" then
        electrics.values['lift0'] = finalLevel
        lift0 = finalLevel
    elseif mode == "outTrouble" then
        if electrics.values['lift0'] == liftLevel then
            otSign = -1
        elseif electrics.values['lift0'] == dropLevel then
            otSign = 1
        end
        finalLevel = math.min(math.max(electrics.values['lift0'] + otSign * dt, dropLevel), liftLevel)
        electrics.values['lift0'] = finalLevel
        lift0 = finalLevel
    end 
    
end

local function setParameters(parameters)
    if mode == "auto" then
        autoLevel = parameters.lift
    end
end

local function switchMode(Mode)
    if Mode == "auto" or Mode == "manual" or Mode == "outTrouble" then
        mode = Mode
    else
        if mode == "auto" then
            mode = "manual"
        elseif mode == "manual" then
            mode = "auto"
        else
            mode = "auto"
        end
    end
    if Mode == "outTrouble" then
        otSign = -1
    end
    guihooks.message("Chassis Adjust Mode is now " .. mode .. " mode." , 5, "")
end

-- public interface
M.switchMode = switchMode

M.adjustChassis = adjustChassis
M.resetChassis = resetChassis

M.setParameters = setParameters

M.init      = onInit
M.reset     = onInit
M.updateGFX = updateGFX

return M