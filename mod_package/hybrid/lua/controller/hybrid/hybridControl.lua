-- hybridContrl.lua - 2024.4.30 13:28 - hybrid control for hybrid Vehicles
-- by NZZ
-- version 0.0.52 alpha
-- final edit - 2025.3.21 18:55

local M = {}

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local abs = math.abs
local sign = sign

local proxyEngine = nil
local gearbox = nil
local mainMotors = nil
local subMotors = nil
local motors = nil
local directMotors = nil 

local motorDirection = 0
local velocityRangeBegin = nil
local velocityRangEnd = nil

local ondemandMaxRPM = nil
local AWDMultiplier = nil
local controlLogicModule = nil
local hybridMode = nil
local isCrawl = 0
local ifMotorOn = nil
local motorRatio1 = nil
local motorRatio2 = nil
local directRPM1 = nil
local directRPM2 = nil

local autoModeStage = nil
local detM = nil
local detO = nil

local defaultSVelocity = nil
local defaultCVelocity = nil
local startVelocity = nil
local connectVelocity = nil

local edriveMode = nil
local AdvanceAWD = nil
local AdAWDDiffRPM = nil
local regenLevel = 3
local ifComfortRegen = nil
local comfortRegenBegine = nil
local comfortRegenEnd = nil
local lowSpeed = nil

local brakeMode = nil

local enableModes = {}
local ifREEVEnable = false
local REEVMode = nil -- control engine start and TC
local PreRMode = nil
local REEVRPM = nil
local REEVMutiplier = nil
local REEVRPMProtect = nil
local lastEnergy = 1
local REEVAV = nil
local highEfficentAV = nil
local reevThrottle = 0

local electricReverse = nil

local ifGearMotorDrive = false
local enhanceDrive = false

local ecrawlMode = false

local tcsMultiper = nil

local function ifMotorGearbox()
    if (gearbox.type == "eatGearbox" or gearbox.type == "ectGearbox" or gearbox.type == "edtGearbox" or gearbox.type == "emtGearbox" or gearbox.type == "estGearbox") then
        return true
    else
        return false
    end
end

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

local function selectBrakeMode(mode)
    if mode then
        brakeMode = mode
    else
        if mode == "onePedal" then
            mode = "CRBS"
        elseif mode == "CRBS" then
            mode = "sport"
        elseif mode == "sport" then
            mode = "onePedal"
        end
    end
end

local function switchBrakeMode(mode)
    selectBrakeMode(mode)
    gui.message({ txt = mode .. " mode on" }, 5, "", "")
end

local function getRegenLevel()
    return regenLevel
end

local function getGear()
    local rangeSign
    if velocityRangeBegin and velocityRangEnd then
        rangeSign = false
        if electrics.values.airspeed >= velocityRangeBegin * 0.2778 and electrics.values.airspeed <= velocityRangEnd * 0.2778 then
            rangeSign = true
        end
    elseif velocityRangeBegin and not velocityRangEnd then
        rangeSign = false
        if electrics.values.airspeed >= velocityRangeBegin * 0.2778 then
            rangeSign = true
        end
    elseif not velocityRangeBegin and velocityRangEnd then
        rangeSign = false
        if electrics.values.airspeed <= velocityRangEnd * 0.2778 then
            rangeSign = true
        end
    else
        rangeSign = true
    end

    if ifMotorOn and rangeSign then
        local directFlag = 0
        if gearbox.mode then
            electrics.values.gearName = gearbox.mode
            if gearbox.mode == "drive" then -- D gear , S gear , R gear or M gear
                directFlag = gearbox.gearIndex
            elseif gearbox.mode == "reverse" then -- CVT R gear
                directFlag = -1
            elseif gearbox.mode == "neutral" then -- N gear
                directFlag = 0
            elseif gearbox.mode == "park" then -- P gear
                directFlag = 0
            end
        else
            directFlag = gearbox.gearIndex
        end
        directFlag = math.max(-1, math.min(1, directFlag))
        if directFlag > 0 then
            directFlag = 1
        elseif directFlag < 0 then
            directFlag = -1
        else
            directFlag = 0
        end
        electrics.values.motorDirection = directFlag
        motorDirection = directFlag
    elseif not ifMotorOn or not rangeSign then
        electrics.values.motorDirection = 0
        motorDirection = 0
    end

    return motorDirection

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
    local motorAction = {
        on1 = {motorRatio = motorRatio1, mode = "connected"},
        on2 = {motorRatio = motorRatio2, mode = "disconnected"},
        on3 = {motorRatio = motorRatio2, mode = "connected", condition = ifMotorGearbox() and powerGenerator:getEnhancedDrive()},
        off = {motorRatio = 0, mode = "connected"}
    }

    local action = motorAction[state]
    if action then
        -- If it's "on3", check the condition before proceeding
        if state == "on3" and not action.condition then
            motorMode("on2")  -- Fall back to "on2" if condition is not met
            return
        end

        -- Apply the action to motors
        for _, v in ipairs(motors) do
            if v.type == "motorShaft" then
                v:setmotorRatio(action.motorRatio)
                v:setMode(action.mode)
            end
        end

        if state == "off" then
            ifMotorOn = false
        else
            ifMotorOn = true
        end
    end
end


local function enhanceDriveMode()
    if ifGearMotorDrive then
        enhanceDrive = not enhanceDrive
        if enhanceDrive then
            guihooks.message("Enhance Drive on", 5, "")
        else
            guihooks.message("Enhance Drive off", 5, "")
        end
    end
end

local function changeAutoVelocity(num)
    if num then
        startVelocity = startVelocity + num * 0.2778
        connectVelocity = connectVelocity + num * 0.2778
        if startVelocity <= 0 then
            startVelocity = 0
            connectVelocity = defaultCVelocity - defaultSVelocity
        end
    else
        startVelocity = defaultSVelocity
        connectVelocity = defaultCVelocity
    end
    guihooks.message("Engine Intervention Velocity is " .. math.floor(startVelocity * 3.6) .. " km/h" , 5, "")
end

local function gearboxMode(state)
    if ifGearMotorDrive then
        if state == "drive" then
            if enhanceDrive then
                gearbox:setmotorType(state)
            end
        else
            gearbox:setmotorType(state)
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

    elseif signal == "reev" then
        engineMode("on")
        motorMode("on2")

    end
end

local function setMode(mode)
    detO = 1
    for _, u in ipairs(enableModes) do
        if mode == u then
            hybridMode = mode
            electrics.values.hybridMode = mode
            guihooks.message("Switch to " .. mode .. " mode." , 5, "")

            if mode == "hybrid" then
                trig(mode)

            elseif mode == "fuel" then
                trig(mode)

            end
            break
        end
        guihooks.message( mode .. " mode does not available." , 5, "")
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

local function setecrawlMode(m)
    if type(m) == "bool" then
        ecrawlMode = m
    else
        ecrawlMode = not ecrawlMode
    end
    local state
    if ecrawlMode then
        state = "On"
    else
        state = "Off"
    end
    gui.message({ txt = "E-Crawl " .. state }, 5, "", "")
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

    getGear()
    local tempIgn
    if electrics.values.ignitionLevel == 2 then
        tempIgn = 1
    else
        tempIgn = 0
    end
    for _, v in ipairs(motors) do
        if v.type == "electricMotor" then
            v.motorDirection = motorDirection * tempIgn or 0
        end     
    end

    

    if enhanceDrive then
        electrics.values.gearDirection = 1
    else
        electrics.values.gearDirection = 0
    end

    --auto mode begin
    local powerGeneratorOff = true
    if electrics.values.powerGeneratorMode == "on" then
        powerGeneratorOff = false
    end

    if electrics.values.hybridMode == "auto" then
        if (electrics.values.airspeed < startVelocity - 5 and not ifLowSpeed()) and autoModeStage ~= 1 then
            if powerGeneratorOff then
                engineMode("off")
                motorMode("on3")
            else
                engineMode("on")
                motorMode("on2")
            end
            autoModeStage = 1
        elseif electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity and not ifLowSpeed() and autoModeStage ~= 2 then
            autoModeStage = 2
        elseif (electrics.values.airspeed >= connectVelocity or ifLowSpeed()) and autoModeStage ~= 3 then
            engineMode("on")
            motorMode("on1")
            autoModeStage = 3
        end

        if autoModeStage == 1 and not powerGeneratorOff then
            REEVMode = "on"
        else
            REEVMode = "off"
        end
    end
    
    if electrics.values.hybridMode ~= "auto" then
        autoModeStage = 0
    end

    electrics.values.autoModeStage = autoModeStage

    --auto mode end

    if electrics.values.hybridMode == "electric" then
        if powerGeneratorOff then
            engineMode("off")
            motorMode("on3")
            REEVMode = "off"
        else
            engineMode("on")
            motorMode("on2")
            REEVMode = "on"
        end
    end

    if electrics.values.hybridMode ~= "electric" and electrics.values.hybridMode ~= "auto" then
        REEVMode = "off"
    end

    --reev mode begin

    if ifMotorGearbox() then

        if ifREEVEnable and detO == 1 then
            if HybridTC or false then
                HybridTC.updateMotor(REEVMode)
            end
            detO = 0
        end

        if REEVMode == "on" then
            if electrics.values.remainingpower < lastEnergy then
                REEVAV = REEVAV + 2 * rpmToAV
            else
                REEVAV = REEVAV - 2 * rpmToAV
                REEVAV = math.max(highEfficentAV, REEVAV)
            end

            REEVAV = math.min(proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV, REEVAV)
            lastEnergy = electrics.values.remainingpower

            proxyEngine:setTempRevLimiter(REEVAV or (REEVRPM * rpmToAV))
            if electrics.values.engineRunning == 0 and REEVAV > (proxyEngine.idleRPM * rpmToAV) then
                proxyEngine:activateStarter()
            end
            reevThrottle = 1
        else
            reevThrottle = electrics.values.throttle

            if electrics.values.tcs == 0 then
                local wheelspeed = electrics.values.wheelspeed * 3.6
                local airspeed = electrics.values.airspeed * 3.6
                if wheelspeed > 1 and airspeed > 0.5 and wheelspeed > airspeed * 1.5 then
                    reevThrottle = math.max(0, reevThrottle * tcsMultiper)
                    tcsMultiper = math.max(0.01, tcsMultiper - 0.02)
                    electrics.values.tcsActive2 = 1
                else
                    tcsMultiper = math.min(1.00, tcsMultiper + 0.01)
                    electrics.values.tcsActive2 = 0
                end
            else
                electrics.values.tcsActive2 = 0
            end
        end

        electrics.values.reevmode = REEVMode

    else
        reevThrottle = electrics.values.throttle
    end

    electrics.values.reevThrottle = reevThrottle

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
        if (abs(mianRPM - subRPM * AWDMultiplier) >= ondemandMaxRPM) or ifLowSpeed() then
            electrics.values.subThrottle = electrics.values.throttle
        else
            electrics.values.subThrottle = 0
        end
    elseif edriveMode == "fullTime" then
        electrics.values.subThrottle = electrics.values.throttle
    else
        electrics.values.subThrottle = 0
    end

    if AdvanceAWD then
        local rpm1 = nil
        local rpm2 = nil
        for _, v in ipairs(subMotors) do
            if v.outputAV1 then
                if rpm1 == nil then
                    rpm1 = v.outputAV1 * avToRPM
                else
                    rpm2 = v.outputAV1 * avToRPM
                end
            end
        end
        
        if math.abs(rpm1) - math.abs(rpm2) >= AdAWDDiffRPM then
            electrics.values.subThrottle1 = 0
            electrics.values.subThrottle2 = electrics.values.subThrottle
        elseif math.abs(rpm2) - math.abs(rpm1) >= AdAWDDiffRPM then
            electrics.values.subThrottle1 = electrics.values.subThrottle
            electrics.values.subThrottle2 = 0
        else
            electrics.values.subThrottle1 = electrics.values.subThrottle
            electrics.values.subThrottle2 = electrics.values.subThrottle
        end  
    end


    -- ecrawl
    local ifecrawl = false
    if ecrawlMode and ifMotorOn and electrics.values.ignitionLevel == 2 and input.throttle == 0 then
        if electrics.values.wheelspeed < (5 / 3.6)  then
            electrics.values.mainThrottle = electrics.values.mainThrottle + 0.01
            electrics.values.mainThrottle = math.min(electrics.values.mainThrottle, 0.2)
        elseif electrics.values.wheelspeed > (6 / 3.6) then
            electrics.values.mainThrottle = electrics.values.mainThrottle - 0.05
            if electrics.values.wheelspeed < (10 / 3.6) then
                electrics.values.mainThrottle = math.max(electrics.values.mainThrottle, 0.01)
            end
        end
        ifecrawl = true
    else
        electrics.values.mainThrottle = electrics.values.throttle
    end

    --comfortable regen
    if ifComfortRegen then
        local comfortRegen
        for _, v in ipairs(mainMotors) do
            if v then
                v.wantedRegenTorque1 = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 or ifecrawl then
                    v.wantedRegenTorque1 = 0
                else
                    v.wantedRegenTorque1 = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
                end
            end
        end
    else
        for _, v in ipairs(mainMotors) do
            if v then
                v.wantedRegenTorque1 = v.originalRegenTorque * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 or ifecrawl then
                    v.wantedRegenTorque1 = 0
                else
                    v.wantedRegenTorque1 = v.originalRegenTorque * regenLevel
                end
            end
        end
    end

    for _, v in ipairs(motors) do
        if brakeMode == "sport" then
            if v then
                v.maxWantedRegenTorque = v.wantedRegenTorque1 * input.brake
            end
        elseif brakeMode == "CRBS" then
            if v then
                v.maxWantedRegenTorque = v.wantedRegenTorque1 * input.brake * 2
                if v.maxWantedRegenTorque > v.wantedRegenTorque1 then
                    v.maxWantedRegenTorque = v.wantedRegenTorque1
                end
            end
            if input.brake > 0.5 then
                electrics.values.brake = (input.brake - 0.5) * 2
            end
        elseif brakeMode == "onePedal" then
            if v then
                v.maxWantedRegenTorque = v.wantedRegenTorque1
            end
        end
    end

    --electric Reverse
    if electricReverse then
        if hybridMode == "hybrid" and getGear() == -1 then
            motorMode("on3")
            electrics.values.reevThrottle = 0
            electrics.values.electricReverse = 1
        elseif hybridMode == "hybrid" and getGear() ~= -1 then
            motorMode("on1")
            electrics.values.electricReverse = 0
        end
    end

end

local function init(jbeamData)

    proxyEngine = powertrain.getDevice("mainEngine")
    gearbox = powertrain.getDevice("gearbox")
    
    local _modes = {jbeamData.autoMode, jbeamData.hybridMode, jbeamData.electricMode, jbeamData.fuelMode}
    for _, v in ipairs(_modes) do 
        if v then
            table.insert(enableModes, v)
        end
    end

    if next(enableModes) == nil then
        enableModes = {"hybrid"}
    end
    -- enableModes = jbeamData.enableModes or {"hybrid", "fuel", "electric", "auto"}
    -- auto      自动选择
    -- electric  电机直驱
    -- fuel      燃油直驱
    -- hybrid    混合驱动
    if ifMotorGearbox() then
        ifREEVEnable = true
        proxyEngine.electricsThrottleName = "reevThrottle"
    end

    brakeMode = jbeamData.defaultBrakeMode or "onePedal"

    motorDirection = 0
    velocityRangeBegin = jbeamData.velocityRangeBegin or nil
    velocityRangEnd = jbeamData.velocityRangEnd or nil

    REEVMode = "off"
    REEVRPM = jbeamData.REEVRPM or 3000
    REEVAV = REEVRPM * rpmToAV
    highEfficentAV = (jbeamData.highEfficentRPM or 3500) * rpmToAV
    REEVMutiplier = jbeamData.REEVMutiplier or 1.00
    REEVRPMProtect = jbeamData.REEVRPMProtect or 0
    ifGearMotorDrive = jbeamData.ifGearMotorDrive or false

    tcsMultiper = 1

    detO = 0
    
    motorRatio1 = jbeamData.motorRatio1 or 1
    motorRatio2 = jbeamData.motorRatio2 or 1
    startVelocity = (jbeamData.startVelocity or 36) * 0.2778
    connectVelocity = (jbeamData.connectVelocity or (startVelocity + 5)) * 0.2778
    defaultSVelocity = startVelocity
    defaultCVelocity = connectVelocity
    directRPM1 = jbeamData.directRPM1 or 1000
    directRPM2 = jbeamData.directRPM2 or 3000

    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    AdvanceAWD = jbeamData.AdvanceAWD or false
    AdAWDDiffRPM = jbeamData.AdAWDDiffRPM or 250
    lowSpeed = (jbeamData.lowSpeed or 0.08) * 0.2778
    ifComfortRegen = jbeamData.ifComfortRegen or true
    comfortRegenBegine = jbeamData.comfortRegenBegine or 0.75
    comfortRegenEnd = jbeamData.comfortRegenEnd or 0.15

    ifGearMotorDrive = ifGearMotorDrive and ifMotorGearbox()
    if enhanceDrive then
        electrics.values.gearDirection = 1
    else
        electrics.values.gearDirection = 0
    end

    mainMotors = {}
    local mainMotorNames = jbeamData.mainMotorNames or {"mainMotor"}
    if mainMotorNames then
        for _, v in ipairs(mainMotorNames) do
            local mainMotor = powertrain.getDevice(v)
            if mainMotor then
                table.insert(mainMotors, mainMotor)
                mainMotor.originalRegenTorque = mainMotor.maxWantedRegenTorque
                mainMotor.wantedRegenTorque1 = 0
                mainMotor.electricsThrottleName = "mainThrottle"
            end
        end
    end
    electrics.values.mainThrottle = 0

    subMotors = {}
    local subMotorNames = jbeamData.subMotorNames or {"subMotor"}
    if subMotorNames then
        for _, v in ipairs(subMotorNames) do
            local subMotor = powertrain.getDevice(v)
            if subMotor then
                table.insert(subMotors, subMotor)
                subMotor.originalRegenTorque = subMotor.maxWantedRegenTorque
                subMotor.wantedRegenTorque1 = 0
            end
        end

        local num = 1
        for _, v in ipairs(subMotors) do
            if AdvanceAWD and #subMotors == 2 then
                local numStr = tostring(num)
                v.electricsThrottleName = "subThrottle" .. numStr
                num = num + 1
            else
                AdvanceAWD = false
                v.electricsThrottleName = "subThrottle"
            end
        end
    end

    ondemandMaxRPM = jbeamData.ondemandMaxRPM or 50
    AWDMultiplier = jbeamData.AWDMultiplier or 1
    
    motors = {}
    local motorNames = jbeamData.motorNames
    if motorNames then
        for _, v in ipairs(motorNames) do
            local motor = powertrain.getDevice(v)
            if motor then
                table.insert(motors, motor)
                motor.originalRegenTorque = motor.maxWantedRegenTorque
                motor.wantedRegenTorque1 = 0
                motor.maxWantedRegenTorque = 0
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
                directMotor.wantedRegenTorque1 = 0
                directMotor.maxWantedRegenTorque = 0
            end
        end
    end

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
    
    ecrawlMode = jbeamData.ecrawlMode or false

    electricReverse = jbeamData.electricReverse == nil and true or jbeamData.electricReverse
    electrics.values.electricReverse = 0

end

local function new()
end

local function onInit()
end

local function reset(jbeamData)

    brakeMode = jbeamData.defaultBrakeMode or "onePedal"

    motorDirection = 0
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    AdvanceAWD = jbeamData.AdvanceAWD or false
    if AdvanceAWD and #subMotors ~= 2 then
        AdvanceAWD = false
    end
    ifComfortRegen = jbeamData.ifComfortRegen and true

    startVelocity = defaultSVelocity
    connectVelocity = defaultCVelocity

    REEVMode = "off"
    REEVAV = REEVRPM * rpmToAV

    tcsMultiper = 1

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end

    enhanceDrive = false
    ifGearMotorDrive = jbeamData.ifGearMotorDrive or false

    if ifMotorGearbox() then
        ifREEVEnable = true
        proxyEngine.electricsThrottleName = "reevThrottle"
    end

    for _, v in ipairs(subMotors) do
        v.electricsThrottleName = "subThrottle"
    end

    for _, v in ipairs(motors) do
        v.maxWantedRegenTorque = v.originalRegenTorque
    end

    electrics.values.mainThrottle = 0
    ecrawlMode = jbeamData.ecrawlMode or false

    electrics.values.electricReverse = 0

end

local function onReset(jbeamData)
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifComfortRegen = jbeamData.ifComfortRegen and true

    REEVMode = "off"

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
end

local function setParameters(parameters)
    if parameters.awd then-- partTime fullTime off
        edriveMode = parameters.awd
    end
    if parameters.regen then
        regenLevel = math.max(0, math.min(5, parameters.regen))
    end
end

M.setMode = setMode
M.setPartTimeDriveMode = setPartTimeDriveMode
M.rollingMode = rollingMode

M.setecrawlMode = setecrawlMode

M.switchBrakeMode = switchBrakeMode
M.reduceRegen = reduceRegen
M.enhanceRegen = enhanceRegen
M.getRegenLevel = getRegenLevel

M.changeAutoVelocity = changeAutoVelocity

M.enhanceDriveMode = enhanceDriveMode

M.init = init
M.reset = reset
M.onInit = onInit
M.onReset = onReset
M.setParameters = setParameters

M.new = new
M.updateGFX = updateGFX

rawset(_G, "hybridControl", M)
return M