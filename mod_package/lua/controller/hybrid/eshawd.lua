--eSH-AWD version 0.0.1alpha
--Final Edit 19点11分2024年1月14日
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
    originalMode = electrics.values.hybridMode
    --log("", "", "" .. originalMode)
    if gear == -1 then
        proxyEngine:setIgnition(0)
        detN = 1
    elseif detN == 1 then
        detN = 0
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

return M