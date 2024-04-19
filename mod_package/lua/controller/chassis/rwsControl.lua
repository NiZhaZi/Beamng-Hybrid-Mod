-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

--NZZ rwsControl 17点09分2024年4月19日

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

-- public interface
M.switchFWS = switchFWS

M.init = onInit
M.onInit      = onInit
M.onReset     = onInit
M.updateGFX = updateGFX

return M