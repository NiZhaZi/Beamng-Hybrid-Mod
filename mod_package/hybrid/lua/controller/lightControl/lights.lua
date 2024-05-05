local M = {}

local lightSign = nil

local light1 = nil
local light2 = nil

local t1 = nil
local t2 = nil
local range1 = nil

local timerange = nil

local function updateGFX(dt)

    if timerange < 4 then
        t1 = t1 + dt
        if t1 >= 0.1 then
            light1 = 1
            t1 = 0
            timerange = timerange + 1
        else
            light1 = 0
        end
    else
        light1 = 0
        t2 = t2 + dt
        if t2 >= 0.5 then
            timerange = 0
            t2 = 0
        end
    end

    local igi
    if electrics.values.ignitionLevel == 2 then
        igi = 1
    else
        igi = 0
    end

    electrics.values.saftylight = light1 * igi * lightSign
    electrics.values.fog = lightSign

    --log("", "light", "light" .. timerange)

end

local function setsign()
    if lightSign == 0 then
        lightSign = 1
    else
        lightSign = 0
    end
end 

local function init()
    lightSign = 0

    light1 = 0
    light2 = 0
    t1 = 0
    t2 = 0
    range1 = 0
    timerange = 0
end

M.setsign = setsign

M.updateGFX = updateGFX
M.init = init
M.reset = init

return M