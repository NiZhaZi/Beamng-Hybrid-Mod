-- vehicleInfo.lua - 2024.5.16 18:52 - vehicle information
-- by NZZ
-- version 0.0.1 alpha
-- final edit - 2024.5.16 20:42

local M = {}

local floor = math.floor

local location = {
    x = 0,
    y = 0,
    z = 0,
    xsymbol = 1,
    ysymbol = 1,
    zsymbol = 1,
}

local acceleration = {
    x = 0,
    y = 0,
    z = 0,
}

local battery = nil
local fuelTank = nil
local energyDensity = nil
local fuelLiquidDensity = nil
local remainingMileAge = nil
local averageConsum = {
    InitialFuel = 0,
    InitialElectricity = 0,
    fuel = 0,
    electricity = 0,
}

local mileage = nil

local function vecTonumber(vec)
    location.x = 0
    location.y = 0
    location.z = 0
    location.xsymbol = 1
    location.ysymbol = 1
    location.zsymbol = 1
    local axe = 'v'
    local symbol = 'xsymbol'
    local numType = 'int'
    local numBit = 10
    for char in string.gmatch(vec, ".") do
        if axe == 'v' then
            if tonumber(char) == 3 then
                axe = 'x'
            end
        elseif axe == 'x' then
            if tonumber(char) and numType == 'int' then
                location.x = location.x * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.x = location.x + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.xsymbol = -1
            elseif char == ',' then
                location.x = location.x * location.xsymbol
                axe = 'y'
                numType = 'int'
                numBit = 10
            end
        elseif axe == 'y' then
            if tonumber(char) and numType == 'int' then
                location.y = location.y * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.y = location.y + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.ysymbol = -1
            elseif char == ',' then
                location.y = location.y * location.ysymbol
                axe = 'z'
                numType = 'int'
                numBit = 10
            end
        elseif axe == 'z' then
            if tonumber(char) and numType == 'int' then
                location.z = location.z * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.z = location.z + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.zsymbol = -1
            elseif char == ')' then
                location.z = location.z * location.zsymbol
            end
        end
    end
end

local function updateGFX(dt)

    -- location begin
    local rot = obj:getPosition()
    local loc = tostring(rot)
    vecTonumber(loc)
    -- location end

    -- acceleration begin
    acceleration.x = electrics.values.accXSmooth
    acceleration.y = electrics.values.accYSmooth
    acceleration.z = electrics.values.accZSmooth
    -- acceleration end

    -- mileage begin
    local speed = electrics.values.airspeed -- m/s
    local dtMileage = speed * dt -- meter
    mileage = mileage + dtMileage / 1000 -- km
    -- mileage end

    -- fuel and electricity consumption begin
    local remainingFuel = (fuelTank.storedEnergy or 0) / energyDensity / fuelLiquidDensity -- L
    local remainingElectricity = (battery.storedEnergy or 0) / 3600000 -- kWh

    local fuelConsumption = averageConsum.InitialFuel - remainingFuel
    local electricityConsumption = averageConsum.InitialElectricity - remainingElectricity

    local averageFuelConsumption = fuelConsumption / mileage * 100 -- L/100km
    local averageElectricityConsumption = electricityConsumption / mileage * 100 -- kWh/100km

    averageConsum.fuel = averageFuelConsumption -- L/100km
    averageConsum.electricity = averageElectricityConsumption -- kWh/100km

    local AVF = floor(averageFuelConsumption)
    local AVE = floor(averageElectricityConsumption)

    local fuelReMiAge = remainingFuel / averageFuelConsumption * 100 -- km
    local elecReMiAge = remainingElectricity / averageElectricityConsumption * 100 -- km
    remainingMileAge = fuelReMiAge + elecReMiAge -- km
    -- fuel and electricity consumption end

    -- log("", "x", "    " .. location.x)
    -- log("", "y", "    " .. location.y)
    -- log("", "z", "    " .. location.z)
    -- log("", "", "" .. )

end

local function init()
    mileage = 0

    fuelTank = energyStorage.getStorage('mainTank')
    battery = energyStorage.getStorage('mainBattery')
    energyDensity = fuelTank.energyDensity
    fuelLiquidDensity = fuelTank.fuelLiquidDensity
    averageConsum.InitialFuel = (fuelTank.initialStoredEnergy or 0) / energyDensity / fuelLiquidDensity -- L
    averageConsum.InitialElectricity = (battery.initialStoredEnergy or 0) / 3600000 -- kWh
    averageConsum.fuel = 0
    averageConsum.electricity = 0

end

local function reset()
    mileage = 0

    averageConsum.fuel = 0
    averageConsum.electricity = 0
end

M.location = location
M.acceleration = acceleration
M.mileage = mileage
M.averageConsum = averageConsum

M.updateGFX = updateGFX
M.init = init
M.reset = reset

return M