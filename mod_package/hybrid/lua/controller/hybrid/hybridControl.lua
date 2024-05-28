-- hybridContrl.lua - 2024.4.30 13:28 - hybrid control for hybrid Vehicles
-- by NZZ
-- version 0.0.19 alpha
-- final edit - 2024.5.28 16:37

local M = {}

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local abs = math.abs

local proxyEngine = nil
local gearbox = nil
local mainMotors = nil
local subMotors = nil
local motors = nil
local directMotors = nil 

local ondemandMaxRPM = nil
local controlLogicModule = nil
local hybridMode = nil
local isCrawl = 0
local ifMotorOn = nil
local motorRatio1 = nil
local motorRatio2 = nil
local directRPM1 = nil
local directRPM2 = nil

local detN = nil
local detM = nil
local detO = nil

local startVelocity = nil
local connectVelocity = nil

local edriveMode = nil
local regenLevel = 5
local ifComfortRegen = nil
local comfortRegenBegine = nil
local comfortRegenEnd = nil
local lowSpeed = nil

local enableModes = {}
local ifREEVEnable = false
local REEVMode = nil -- control engine start and TC
local PreRMode = nil
local REEVRPM = nil
local REEVMutiplier = nil
local REEVRPMProtect = nil
local reevThrottle = 0

local function reduceRegen()

    guihooks.message("Energy Recovery Level is " .. regenLevel , 5, "")

    if regenLevel > 0 then
        regenLevel = regenLevel - 1
    end

end

local function enhanceRegen()

    guihooks.message("Energy Recovery Level is " .. regenLevel , 5, "")

    if regenLevel < 5 then
        regenLevel = regenLevel + 1
    end

end

local function getGear()
    if ifMotorOn == true then
        if gearbox.mode then
            electrics.values.gearName = gearbox.mode
            if gearbox.mode == "drive" then -- D gear , S gear , R gear or M gear
                electrics.values.motorDirection = gearbox.gearIndex
            elseif gearbox.mode == "reverse" then -- CVT R gear
                electrics.values.motorDirection = -1
            elseif gearbox.mode == "neutral" then -- N gear
                electrics.values.motorDirection = 0
            elseif gearbox.mode == "park" then -- P gear
                electrics.values.motorDirection = 0
            end
        else
            electrics.values.motorDirection = gearbox.gearIndex
        end
    elseif ifMotorOn == false then
        electrics.values.motorDirection = 0
    end

end

local function engineMode(state)
    if state == "on" then
        if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
            proxyEngine:activateStarter()
        end
    elseif state == "off" then
        if electrics.values.engineRunning == 1 then
            proxyEngine:setIgnition(0)
        end
    end
end

local function motorMode(state)
    if state == "on1" then -- hybrid drive ratio
        for _, v in ipairs(motors) do
            v:setmotorRatio(motorRatio1)
            v:setMode("connected")
            ifMotorOn = true
        end
    elseif state == "on2" then -- EV drive ratio
        for _, v in ipairs(motors) do
            v:setmotorRatio(motorRatio2)
            v:setMode("disconnected")
            ifMotorOn = true         
        end
    elseif state == "off" then
        for _, v in ipairs(motors) do
            v:setmotorRatio(0)
            v:setMode("connected")
            ifMotorOn = false  
        end
    end
end

local function trig(signal)
    if signal == "hybrid" then
        engineMode("on")
        motorMode("on1")
    elseif signal == "fuel" then
        engineMode("on")
        motorMode("off")
    elseif signal == "electric" then
        engineMode("off")
        motorMode("on2")
    end
end

local function setMode(mode)
    detO = 1
    for _, u in ipairs(enableModes) do
        if mode == u then
            hybridMode = mode
            electrics.values.hybridMode = mode
            guihooks.message("Switch to " .. mode .. " mode" , 5, "")

            if mode == "hybrid" then
                trig(mode)

            elseif mode == "fuel" then
                trig(mode)

            elseif mode == "electric" then
                trig(mode)

            elseif mode == "auto" then

            elseif mode == "reev" then
                engineMode("on")
                motorMode("on2")
                
            elseif mode == "direct" then
                --gui.message({ txt = "Switch to direct mode" }, 5, "", "")
                if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                    proxyEngine:activateStarter()
                end
                for _, v in ipairs(motors) do
                    v:setmotorRatio(motorRatio2)
                    v:setMode("disconnected")
                    ifMotorOn = true
                end
                for _, v in ipairs(directMotors) do
                    v:setmotorRatio(0)
                    v:setMode("disconnected")
                end
            end

        end
    end

    local PGMode = controller.getControllerSafe('powerGenerator').getFunctionMode()
    if mode ~= "reev" and REEVMode ~= "on" then
        PreRMode = PGMode
        REEVMode = "off"
        proxyEngine:resetTempRevLimiter()
    else
        REEVMode = "on"
    end
    if ifREEVEnable and mode == "reev" then
        controller.getControllerSafe('powerGenerator').setMode('on')
    else
        controller.getControllerSafe('powerGenerator').setMode(PreRMode)
    end

end

local function rollingMode(direct)
    local modeCount = #enableModes
    local modeNum = 0
    for _, u in ipairs(enableModes) do
        if electrics.values.hybridMode == u then
            modeNum = modeNum + 1
            break
        else
            modeNum = modeNum + 1
        end
    end
    if direct > 0 then
        if modeNum + 1 > modeCount then
            modeNum = 0
        end
        setMode(enableModes[modeNum + 1])
    elseif direct < 0 then
        if modeNum - 1 < 1 then
            modeNum = #enableModes + 1
        end
        setMode(enableModes[modeNum - 1])
    else
    end
end

local function cauculateRegen(percentage)
    if percentage > comfortRegenBegine then
        return 1
    elseif percentage <= comfortRegenBegine and percentage > comfortRegenEnd then
        return percentage
    else
        return comfortRegenEnd
    end
end

local function setPartTimeDriveMode(mode)
    if mode == "partTime" then
        gui.message({ txt = "EV part-time drive on" }, 5, "", "")
    elseif mode == "fullTime" then
        gui.message({ txt = "EV full-time drive on" }, 5, "", "")
    else
        gui.message({ txt = "subMotors off" }, 5, "", "")
    end
    edriveMode = mode or "off"
end

local function ifLowSpeed()
    if input.throttle > 0.8 and electrics.values.airspeed <= lowSpeed then
        return true
    else
        return false
    end
    return false
end

local function updateGFX(dt)
    if drivetrain.shifterMode == 2 then
        --controller.mainController.setGearboxMode("realistic")
    end

    --log("", "hybrid", "hybrid" .. 3)
    getGear()

    if electrics.values.hybridMode == "electric" then
        proxyEngine:setIgnition(0)
    end

    --auto mode begin
    local powerGeneratorOff = true
    if electrics.values.powerGeneratorMode == "on" then
        powerGeneratorOff = false
    end

    if electrics.values.hybridMode == "auto" then
        if (electrics.values.airspeed < startVelocity - 5 and not(ifLowSpeed())) and detN ~= 1 then
            engineMode("off")
            motorMode("on2")
            detN = 1
        elseif electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity and detN ~= 2 then
            detN = 2
        elseif (electrics.values.airspeed >= connectVelocity or (ifLowSpeed())) and detN ~= 3 then
            engineMode("on")
            motorMode("on1")
            detN = 3
        end
    
        if electrics.values.airspeed < startVelocity - 5 and not(ifLowSpeed()) then
            if electrics.values.engineRunning == 1 and powerGeneratorOff then  
                engineMode("off")
            elseif not powerGeneratorOff then
                engineMode("on")
            end
            
            if powerGeneratorOff then
                REEVMode = "off"
            elseif ifREEVEnable then
                REEVMode = "on"
            end
        elseif (electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity) or ifLowSpeed() then
            REEVMode = "off"
            engineMode("on")
        end
    end

    if electrics.values.hybridMode ~= "auto" then
        detN = 0
    end

    --auto mode end

    --direct mode begin
    if electrics.values.hybridMode == "direct" then

        if proxyEngine.outputRPM < directRPM1 and electrics.values.airspeed < 0.5 then
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio2)
                v:setMode("disconnected")
            end
            for _, v in ipairs(directMotors) do
                v:setmotorRatio(0)
                v:setMode("disconnected")
            end
        elseif proxyEngine.outputRPM >= directRPM2 then 
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
            end
            for _, v in ipairs(directMotors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
            end
        end

    end

    if electrics.values.hybridMode ~= "direct" then
        detM = 0
        for _, v in ipairs(directMotors) do
            v:setmotorRatio(0)
        end
    end
    --direct mode end

    --reev mode begin
    if ifREEVEnable and detO == 1 then
        if controller.getControllerSafe('tractionControl') or false then
            controller.getControllerSafe('tractionControl').updateMotor(REEVMode)
        end
        detO = 0
    end

    if REEVMode == "on" and (hybridMode == "auto" or hybridMode == "reev") then
        local REEVAV = REEVRPM * rpmToAV * math.max(1, (input.throttle * 1.34) ^ (2.37 * REEVMutiplier))
        if REEVAV > proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV then
            REEVAV = proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV
        end
        proxyEngine:setTempRevLimiter(REEVAV)
        reevThrottle = 1
    else
        reevThrottle = electrics.values.throttle
    end

    electrics.values.reevThrottle = reevThrottle
    electrics.values.reevmode = REEVMode

    --reev mode end

    --ev part time drive
    local mianRPM = 0
    local subRPM = 0
    for _, v in ipairs(mainMotors) do
        if v then
            mianRPM = mianRPM + v.outputAV1 * avToRPM
        end
    end
    mianRPM = mianRPM / #mainMotors
    for _, v in ipairs(subMotors) do
        if v then
            subRPM = subRPM + v.outputAV1 * avToRPM
        end
    end
    subRPM = subRPM / #subMotors

    if edriveMode == "partTime" then
        if (abs(mianRPM - subRPM) >= ondemandMaxRPM) or ifLowSpeed() then
            electrics.values.subThrottle = electrics.values.throttle
        else
            electrics.values.subThrottle = 0
        end
    elseif edriveMode == "fullTime" then
        electrics.values.subThrottle = electrics.values.throttle
    else
        electrics.values.subThrottle = 0
    end



    --comfortable regen
    if ifComfortRegen then
        local comfortRegen
        for _, v in ipairs(mainMotors) do
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 then
                    v.maxWantedRegenTorque = 0
                else
                    v.maxWantedRegenTorque = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
                    --log("", "hybrid", "hybrid" .. v.maxWantedRegenTorque)
                end
            end
        end
    else
        for _, v in ipairs(mainMotors) do
            if v then
                v.maxWantedRegenTorque = v.originalRegenTorque * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 then
                    v.maxWantedRegenTorque = 0
                else
                    v.maxWantedRegenTorque = v.originalRegenTorque * regenLevel
                end
            end
        end
    end

end

local function init(jbeamData)

    enableModes = jbeamData.enableModes or {"hybrid", "fuel", "electric", "auto", "reev"}
    -- auto      自动选择
    -- reev      增程模式
    -- electric  电机直驱
    -- fuel      燃油直驱
    -- hybrid    混合驱动
    -- direct    直接驱动
    for _, u in ipairs(enableModes) do
        if u == "reev" then
            ifREEVEnable = true
            break
        end
    end

    REEVMode = "off"
    REEVRPM = jbeamData.REEVRPM or 3000
    REEVMutiplier = jbeamData.REEVMutiplier or 1.00
    REEVRPMProtect = jbeamData.REEVRPMProtect or 0

    detO = 0
    
    motorRatio1 = jbeamData.motorRatio1 or 1
    motorRatio2 = jbeamData.motorRatio2 or 1
    startVelocity = (jbeamData.startVelocity or 36) * 0.2778
    connectVelocity = (jbeamData.connectVelocity or (startVelocity + 5)) * 0.2778
    directRPM1 = jbeamData.directRPM1 or 1000
    directRPM2 = jbeamData.directRPM2 or 3000

    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    lowSpeed = (jbeamData.lowSpeed or 0.08) * 0.2778
    ifComfortRegen = jbeamData.ifComfortRegen or true
    comfortRegenBegine = jbeamData.comfortRegenBegine or 0.75
    comfortRegenEnd = jbeamData.comfortRegenEnd or 0.15

    proxyEngine = powertrain.getDevice("mainEngine")
    gearbox = powertrain.getDevice("gearbox")

    mainMotors = {}
    local mainMotorNames = jbeamData.mainMotorNames or {"mainMotor"}
    if mainMotorNames then
        for _, v in ipairs(mainMotorNames) do
            local mainMotor = powertrain.getDevice(v)
            if mainMotor then
                table.insert(mainMotors, mainMotor)
                mainMotor.originalRegenTorque = mainMotor.maxWantedRegenTorque
            end
        end
    end

    subMotors = {}
    local subMotorNames = jbeamData.subMotorNames or {"subMotor"}
    if subMotorNames then
        for _, v in ipairs(subMotorNames) do
            local subMotor = powertrain.getDevice(v)
            if subMotor then
                table.insert(subMotors, subMotor)
                subMotor.originalRegenTorque = subMotor.maxWantedRegenTorque
            end
        end
    end

    ondemandMaxRPM = jbeamData.ondemandMaxRPM or 50
    
    motors = {}
    local motorNames = jbeamData.motorNames
    if motorNames then
        for _, v in ipairs(motorNames) do
            local motor = powertrain.getDevice(v)
            if motor then
                table.insert(motors, motor)
                motor.originalRegenTorque = motor.maxWantedRegenTorque
            end
        end
    end

    if #mainMotors == 0 and #subMotors == 0 then
        mainMotors = motors
    end

    directMotors = {}
    local directmotorNames = jbeamData.directMotorNames
    if directmotorNames then
        for _, v in ipairs(directmotorNames) do
            local directMotor = powertrain.getDevice(v)
            if directMotor then
                table.insert(directMotors, directMotor)
                directMotor.originalRegenTorque = directMotor.maxWantedRegenTorque
            end
        end
    end

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
    
end

local function new()
end

local function onInit()
end

local function reset(jbeamData)
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifComfortRegen = jbeamData.ifComfortRegen or true

    REEVMode = "off"

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
end

local function onReset(jbeamData)
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifComfortRegen = jbeamData.ifComfortRegen or true

    REEVMode = "off"

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
end

M.setMode = setMode
M.setPartTimeDriveMode = setPartTimeDriveMode
M.rollingMode = rollingMode

M.reduceRegen = reduceRegen
M.enhanceRegen = enhanceRegen

M.init = init
M.reset = reset
M.onInit = onInit
M.onReset = onReset

M.new = new
M.updateGFX = updateGFX


return M