--eSH-AWD version 0.0.2alpha
--Final Edit 2024年3月18日22点06分
--by NZZ

local M = {}

local abs = math.abs

local AVtoRPM = 9.549296596425384

local motorShaft = nil
local FLMotor = nil
local FRMotor = nil
local FLShaft = nil
local FRShaft = nil
local proxyEngine = nil
local gearbox = nil

local originalMode = nil
local gear = nil
local detN = nil

local function setMode(mode)
    controller.getControllerSafe("hybridControl").setMode(mode)
end

local function updateGFX()
    gear = motorShaft.motorDirection
    FLMotor.motorDirection = gear
    FRMotor.motorDirection = gear
    
    --log("", "", "" .. originalMode)
    if gear == -1 and detN == 0 then
        originalMode = electrics.values.hybridMode
        electrics.values.hybridMode = "electric"

        --proxyEngine:setIgnition(0)
        detN = 1
    elseif gear ~= -1 and detN == 1 then

        electrics.values.hybridMode = originalMode

        detN = 0

        --[[
        local mode = originalMode
        if mode == "hybrid" then
            if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                proxyEngine:activateStarter()
            end
        elseif mode == "fuel" then
            if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                proxyEngine:activateStarter()
            end
        elseif mode == "electric" then
            proxyEngine:setIgnition(0)
        elseif mode == "auto" then
            proxyEngine:setIgnition(0)
        elseif mode == "direct" then
            if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                proxyEngine:activateStarter()
            end
        end
        ]]

    end 

    local lrpm = FLShaft.outputAV1 * AVtoRPM
    local rrpm = FRShaft.outputAV1 * AVtoRPM
    if lrpm - rrpm > 50 then
        electrics.values.SHThrottleL = 0
        electrics.values.SHThrottleR = electrics.values.throttle
    elseif rrpm - lrpm > 50 then
        electrics.values.SHThrottleL = electrics.values.throttle
        electrics.values.SHThrottleR = 0
    else
        electrics.values.SHThrottleL = electrics.values.throttle
        electrics.values.SHThrottleR = electrics.values.throttle
    end
    
end

local function init(jbeamData)
    motorShaft = powertrain.getDevice("motorShaft")
    FLMotor = powertrain.getDevice(jbeamData.FLMotorName or "FLMotor")
    FRMotor = powertrain.getDevice(jbeamData.FRMotorName or "FRMotor")
    FLShaft = powertrain.getDevice(jbeamData.FLShaftName or "wheelaxleFL")
    FRShaft = powertrain.getDevice(jbeamData.FRShaftName or "wheelaxleFR")
    proxyEngine = powertrain.getDevice("mainEngine")
    gearbox = powertrain.getDevice("gearbox")

    detN = 0
end

M.updateGFX = updateGFX
M.init = init
M.reset = init

return M