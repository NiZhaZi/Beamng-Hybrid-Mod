-- powerGenerator.lua - 2024.4.29 17:27 - powerGenerator control for hybrid Transmissions
-- by NZZ
-- version 0.0.9 alpha
-- final edit - 2024.10.21 23:58

local M = {}

local abs = math.abs

local AVtoRPM = 9.549296596425384

local powerGenerator = nil
local proxyEngine = nil

local powerGeneratorMode = nil -- "on" or "off"
local functionMode = nil -- "on", "off" or "auto"

local defaultSOC = nil
local SOC = nil
local lowValue = nil
local highValue = nil
local enhancedDrive = nil

local function getEnhancedDrive()
    return enhancedDrive
end

local function setSOC(sigh)
    if sigh == "+" and SOC < 100 then
        SOC = SOC + 5
    elseif sigh == "-" and SOC > 0 then
        SOC = SOC - 5
    elseif SOC ~= 100 or SOC ~= 0 then
        SOC = defaultSOC
    end
    if sigh == "+" or sigh == "-" then
        guihooks.message("SOC set to " .. SOC .. "%" , 5, "")
    else
        guihooks.message("SOC Reset to " .. SOC .. "%" , 5, "")
    end
end

local function setMode(mode)
    functionMode = mode
end

local function changeMode(mode)
    setMode(mode)
    guihooks.message("Power Generator " .. mode , 5, "")
end

local function getFunctionMode()
    return functionMode
end

local function updateGFX(dt)

    lowValue = SOC
    highValue = math.min(SOC + 5, 100)

    if functionMode == "on" then
        powerGeneratorMode = "on"
    elseif functionMode == "off" then
        powerGeneratorMode = "off"
    elseif functionMode == "auto" then
        if electrics.values.evfuel then
            if electrics.values.evfuel <= lowValue and powerGeneratorMode ~= "on" then
                powerGeneratorMode = "on"
            elseif electrics.values.evfuel >= highValue and powerGeneratorMode ~= "off" then
                powerGeneratorMode = "off"
            end
        end
    end

    if powerGeneratorMode == "on" then
        powerGenerator.motorType = "powerGenerator"
        electrics.values.powerGeneratorMode = "on"
    elseif powerGeneratorMode == "off" then
        if enhancedDrive then
            powerGenerator.motorType = "drive"
        end
        electrics.values.powerGeneratorMode = "off"
    end

    --log("", "", "" .. powerGenerator.inputAV)
end

local function reset(jbeamData)
    functionMode = jbeamData.defaultMode or "auto"
    SOC = defaultSOC

    enhancedDrive = jbeamData.enhancedDrive or false
end

local function init(jbeamData)
    local powerGeneratorName = jbeamData.powerGeneratorName
    powerGenerator = powertrain.getDevice(powerGeneratorName)
    local proxyEngineName = jbeamData.proxyEngineName or "mainEngine"
    proxyEngine = powertrain.getDevice(proxyEngineName)

    functionMode = jbeamData.defaultMode or "off"

    defaultSOC = jbeamData.SOC or 80
    defaultSOC = math.min(defaultSOC, 100)
    SOC = defaultSOC

    enhancedDrive = jbeamData.enhancedDrive or false

end

M.enhancedDrive = enhancedDrive
M.getEnhancedDrive = getEnhancedDrive

M.setSOC = setSOC
M.setMode = setMode
M.changeMode = changeMode
M.getFunctionMode = getFunctionMode

M.updateGFX = updateGFX
M.reset = reset
M.init = init

rawset(_G, "powerGenerator", M)
return M