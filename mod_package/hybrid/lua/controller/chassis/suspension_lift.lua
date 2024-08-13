--NZZ Chassis Height Adjust 18点30分2024年4月19日

local M = {}

local floor = math.floor
local ceil = math.ceil

local lift0 = nil
local liftLevel = nil
local DropLevel = nil

local function onInit(jbeamData)
    lift0 = 0
    electrics.values['lift0'] = lift0

    liftLevel = jbeamData.liftLevel or 0.10
    DropLevel = jbeamData.DropLevel or -0.10
end

local function adjustChassis(para)

    if para > 0 then
        if lift0 < liftLevel then
            lift0 = lift0 + para
        end
    elseif para < 0 then
        if lift0 > DropLevel then
            lift0 = lift0 + para
        end
    end

    local level = floor(lift0 / para)
    guihooks.message("Chassis Height is now on level " .. level, 5, "")

    if lift0 > liftLevel then
        lift0 = liftLevel
    end
    if lift0 < DropLevel then
        lift0 = DropLevel
    end

    electrics.values['lift0'] = lift0

end

local function resetChassis()

    electrics.values['lift0'] = 0
    guihooks.message("Chassis Height is now on level " .. 0, 5, "")

end

local function updateGFX(dt)

end

-- public interface

M.adjustChassis = adjustChassis
M.resetChassis = resetChassis

M.init      = onInit
M.reset     = onInit
M.updateGFX = updateGFX

return M