-- 4wsAdvance.lua - 2024.4.19 17:09 - advance rear wheel steering
-- by NZZ
-- version 0.0.2 alpha
-- final edit - 2024.5.6 22:51

local M = {}

local switchVelocity = nil
local switchFlag = 1

local judge = nil
local direction = nil

local function switch()
    if switchFlag == 1 then
        switchFlag = 0
    elseif switchFlag == 0 then
        switchFlag = 1
    else
        switchFlag = 1
    end
end

local function onInit()
    electrics.values.fws = 1
    electrics.values['4wsAdvance'] = 0
    switchVelocity = (v.data.variables["$switchVelocity"].val or 7) * 0.2778
end

local function judgeUpdateSteer()
    if electrics.values.airspeed <= switchVelocity then
        if electrics.values['steering_input'] < 0.01 then
            direction = 1
        else
        end
    else
        if electrics.values['steering_input'] < 0.01 then
            direction = 2
        else
        end
    end
end

local function updateGFX(dt)
    if not electrics.values['steering_input'] then return end
    --local steer = -electrics.values['steering_input']
    if not v.data.variables["$switchVelocity"] then return end
    
    local steer
    local formedSteer

    judgeUpdateSteer()

    if direction == 1 then
        formedSteer = -electrics.values['steering_input']
    else
        formedSteer = electrics.values['steering_input']
    end

    steer = formedSteer

    local absSteer = math.abs(steer)

    --local rws = (math.sin(absSteer * 1) * math.cos((absSteer * 3.3))) * 1.21
    local rws = math.sin(absSteer * 1.57) * -1
    rws = rws * fsign(steer) --Use the sign of the steering input to know the sign of rws output

    if electrics.values.fws == 1 then
        electrics.values['4wsAdvance'] = rws
    elseif electrics.values.fws == 0 then
        electrics.values['4wsAdvance'] = 0
    end

    --log("W", "4ws", "test 4ws" .. electrics.values['4wsAdvance'])

end

-- public interface
M.switch = switch

M.onInit      = onInit
M.onReset     = onInit

M.init      = onInit
M.reset     = onInit

M.updateGFX = updateGFX

return M