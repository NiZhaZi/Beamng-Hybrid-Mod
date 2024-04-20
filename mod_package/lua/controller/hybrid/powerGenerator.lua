--powerGenerator Control version 0.0.2alpha
--Final Edit 12点55分2024年4月20日
--by NZZ

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
    guihooks.message("Power Generator " .. mode , 5, "")
end

local function updateGFX(dt)

    lowValue = SOC
    highValue = SOC + 5

    if functionMode == "on" then
        powerGeneratorMode = "on"
    elseif functionMode == "off" then
        powerGeneratorMode = "off"
    elseif functionMode == "auto" then
        if electrics.values.evfuel <= lowValue and powerGeneratorMode == "off" then
            powerGeneratorMode = "on"
        elseif electrics.values.evfuel >= highValue and powerGeneratorMode == "on" then
            powerGeneratorMode = "off"
        end
    end

    if powerGeneratorMode == "on" then
        powerGenerator.motorDirection = 1
        if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 and electrics.values.hybridMode ~= "electric" then
            proxyEngine:activateStarter()
        end
        electrics.values.powerGeneratorMode = "on"
    elseif powerGeneratorMode == "off" then
        powerGenerator.motorDirection = 0
        electrics.values.powerGeneratorMode = "off"
    end

    --log("", "", "" .. powerGenerator.inputAV)
end

local function reset(jbeamData)
    functionMode = jbeamData.defaultMode or "off"
    SOC = defaultSOC
end

local function init(jbeamData)
    local powerGeneratorName = jbeamData.powerGeneratorName
    powerGenerator = powertrain.getDevice(powerGeneratorName)
    local proxyEngineName = jbeamData.proxyEngineName or "mainEngine"
    proxyEngine = powertrain.getDevice(proxyEngineName)

    functionMode = jbeamData.defaultMode or "off"

    defaultSOC = jbeamData.SOC or 80
    SOC = defaultSOC

end

M.setSOC = setSOC
M.setMode = setMode

M.updateGFX = updateGFX
M.reset = reset
M.init = init

return M