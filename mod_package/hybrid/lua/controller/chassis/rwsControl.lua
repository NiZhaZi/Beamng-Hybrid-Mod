-- rwsControl.lua - 2024.4.19 17:09 - rear wheel steering control
-- by NZZ
-- version 0.0.2 alpha
-- final edit - 2024.11.2 21:18

local M = {}

local fws = nil

local function switchFWS()
    if electrics.values.fws == 1 then
        electrics.values.fws = 0
        gui.message({ txt = "Rear Wheel Steering Off" }, 5, "", "")
    elseif electrics.values.fws == 0 then
        electrics.values.fws = 1
        gui.message({ txt = "Rear Wheel Steering On" }, 5, "", "")
    end
end

local function onInit()
    --local fwsName = "4wsAdvance"
  	--fws = require(fwsName)
end

local function updateGFX(dt)
    
end

local function setParameters(parameters)
    local Val
    if parameters.val < 0.5 then
        Val = 0
    else
        Val = 1
    end
    electrics.values.fws = Val
end

-- public interface
M.switchFWS = switchFWS

M.init = onInit
M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX
M.setParameters = setParameters

return M