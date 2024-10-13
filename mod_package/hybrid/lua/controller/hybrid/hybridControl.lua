-- hybridContrl.lua - 2024.4.30 13:28 - hybrid control for hybrid Vehicles
-- by NZZ
-- version 0.0.44 alpha
-- final edit - 2024.10.13 21:06

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

local detN = nil
local detM = nil
local detO = nil

local defaultSVelocity = nil
local defaultCVelocity = nil
local startVelocity = nil
local connectVelocity = nil

local edriveMode = nil
local AdvanceAWD = nil
local AdAWDDiffRPM = nil
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
local lastEnergy = 1
local REEVAV = nil
local REEVSOC = nil
local highEfficentAV = nil
local reevThrottle = 0
local RMSstate = nil

local ifGearMotorDrive = false
local enhanceDrive = false

local ecrawlMode = false

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
        -- if gearbox.type == "cvtGearbox" or gearbox.type == "ectGearbox" then
        --     if gearbox.mode == "drive" then -- D gear , S gear , R gear or M gear
        --         electrics.values.motorDirection = gearbox.gearIndex
        --         motorDirection = gearbox.gearIndex
        --     elseif gearbox.mode == "reverse" then -- CVT R gear
        --         electrics.values.motorDirection = -1
        --         motorDirection = -1
        --     elseif gearbox.mode == "neutral" then -- N gear
        --         electrics.values.motorDirection = 0
        --         motorDirection = 0
        --     elseif gearbox.mode == "park" then -- P gear
        --         electrics.values.motorDirection = 0
        --         motorDirection = 0
        --     end
        -- else
        --     if gearbox.gearRatio == 0 then
        --         electrics.values.motorDirection = 0
        --         motorDirection = 0
        --     else
        --         electrics.values.motorDirection = gearbox.gearRatio / abs(gearbox.gearRatio)
        --         motorDirection = gearbox.gearRatio / abs(gearbox.gearRatio)
        --         -- log("D", "", gearbox.gearRatio)
        --     end
        -- end
    elseif not ifMotorOn or not rangeSign then
        electrics.values.motorDirection = 0
        motorDirection = 0
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
            if v.type == "motorShaft" then
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
            else
            end
        end
        ifMotorOn = true
    elseif state == "on2" then -- EV drive ratio
        for _, v in ipairs(motors) do
            if v.type == "motorShaft" then
                v:setmotorRatio(motorRatio2)
                v:setMode("disconnected")
            else
            end         
        end
        ifMotorOn = true
    elseif state == "on3" then -- EV drive ratio
        if ifMotorGearbox() then
            for _, v in ipairs(motors) do
                if v.type == "motorShaft" then
                    v:setmotorRatio(motorRatio2)
                    v:setMode("connected")
                else
                end         
            end
            ifMotorOn = true
        else
            motorMode("on2")
        end
    elseif state == "off" then
        for _, v in ipairs(motors) do
            if v.type == "motorShaft" then
                v:setmotorRatio(0)
                v:setMode("connected")
            else
            end     
        end
        ifMotorOn = false
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
        -- gearboxMode("drive")
    elseif signal == "fuel" then
        engineMode("on")
        motorMode("off")
        -- gearboxMode("powerGenerator")
    elseif signal == "electric" then
        engineMode("off")
        motorMode("on3")
        -- gearboxMode("drive")
    elseif signal == "reev" then
        engineMode("on")
        motorMode("on2")
        -- gearboxMode("powerGenerator")
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

            elseif mode == "electric" then
                trig(mode)

            elseif mode == "auto" then

            elseif mode == "reev" then
                trig(mode)
                
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
            break
        end
        guihooks.message( mode .. " mode does not available." , 5, "")
    end

    local PGMode = nil
    if mode == "reev" then
        PGMode = powerGenerator.getFunctionMode()
        PreRMode = PGMode
    end
    if mode ~= "reev" then
        REEVMode = "off"
        proxyEngine:resetTempRevLimiter()
    else
        REEVMode = "on"
    end
    if ifREEVEnable and mode == "reev" then
        powerGenerator.setMode('on')
    else
        if PreRMode then
            powerGenerator.setMode(PreRMode)
        end
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

local function reevMotorShaftUpdate(state)
    if RMSstate ~= state then
        RMSstate = state
        if state == "disconnected" then
            if ifMotorGearbox() then
                for _, v in ipairs(motors) do
                    if v.type == "motorShaft" then
                        v:setMode("disconnected")
                    end
                end
            end
        elseif state == "connected" then
            if ifMotorGearbox() then
                for _, v in ipairs(motors) do
                    if v.type == "motorShaft" then
                        v:setMode("connected")
                    end
                end
            end
        end
    end
end

local function updateGFX(dt)
    if drivetrain.shifterMode == 2 then
        --controller.mainController.setGearboxMode("realistic")
    end

    --log("", "hybrid", "hybrid" .. 3)
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

    if electrics.values.hybridMode == "electric" then
        proxyEngine:setIgnition(0)
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
        if (electrics.values.airspeed < startVelocity - 5 and not(ifLowSpeed())) and detN ~= 1 then
            engineMode("off")
            motorMode("on3")
            detN = 1
        elseif electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity and detN ~= 2 then
            detN = 2
        elseif (electrics.values.airspeed >= connectVelocity or (ifLowSpeed())) and detN ~= 3 then
            engineMode("on")
            motorMode("on1")
            detN = 3
        end
    
        if electrics.values.airspeed < startVelocity - 5 and not(ifLowSpeed()) then
            motorMode("on2")
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

    if ifMotorGearbox() then

        if ifREEVEnable and detO == 1 then
            if HybridTC or false then
                HybridTC.updateMotor(REEVMode)
            end
            detO = 0
        end

        if REEVMode == "on" and (hybridMode == "auto" or hybridMode == "reev") then
            -- local REEVAV = REEVRPM * rpmToAV * math.max(1, (input.throttle * 1.34) ^ (2.37 * REEVMutiplier))
            -- if REEVAV > proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV then
            --     REEVAV = proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV
            -- end
            if electrics.values.remainingpower < lastEnergy then
                REEVAV = REEVAV + 2 * rpmToAV
            else
                if electrics.values.remainingpower > REEVSOC then
                    REEVAV = REEVAV - 2 * rpmToAV
                    REEVAV = math.max(0, REEVAV)
                else
                    if REEVAV > highEfficentAV then
                        REEVAV = REEVAV - 2 * rpmToAV
                    else
                        REEVAV = REEVAV + 2 * rpmToAV
                    end
                end
            end
            REEVAV = math.min(proxyEngine.maxRPM * rpmToAV - REEVRPMProtect * rpmToAV, REEVAV)
            lastEnergy = electrics.values.remainingpower
            -- log("D", "lastEnergy", lastEnergy)

            proxyEngine:setTempRevLimiter(REEVAV or (REEVRPM * rpmToAV))
            if electrics.values.engineRunning == 0 and REEVAV > (proxyEngine.idleRPM * rpmToAV) then
                proxyEngine:activateStarter()
            end
            reevThrottle = 1
            reevMotorShaftUpdate("disconnected")
        else
            reevThrottle = electrics.values.throttle
            reevMotorShaftUpdate("connected")
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
            -- log("", "", "" .. v.outputAV1 * avToRPM)
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
                v.maxWantedRegenTorque = v.originalRegenTorque * cauculateRegen( v.outputAV1 * avToRPM / v.maxRPM ) * regenLevel
            end
        end

        for _, v in ipairs(subMotors) do
            if v then
                if electrics.values.throttle > 0 or ifecrawl then
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
                if electrics.values.throttle > 0 or ifecrawl then
                    v.maxWantedRegenTorque = 0
                else
                    v.maxWantedRegenTorque = v.originalRegenTorque * regenLevel
                end
            end
        end
    end

end

local function init(jbeamData)

    proxyEngine = powertrain.getDevice("mainEngine")
    gearbox = powertrain.getDevice("gearbox")
    
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
            proxyEngine.electricsThrottleName = "reevThrottle"
            break
        end
    end

    motorDirection = 0
    velocityRangeBegin = jbeamData.velocityRangeBegin or nil
    velocityRangEnd = jbeamData.velocityRangEnd or nil

    REEVMode = "off"
    REEVRPM = jbeamData.REEVRPM or 3000
    REEVAV = REEVRPM * rpmToAV
    REEVSOC = (jbeamData.REEVSOC or 80) / 100
    highEfficentAV = (jbeamData.highEfficentRPM or 3500) * rpmToAV
    REEVMutiplier = jbeamData.REEVMutiplier or 1.00
    REEVRPMProtect = jbeamData.REEVRPMProtect or 0
    ifGearMotorDrive = jbeamData.ifGearMotorDrive or false

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

        -- log("", "", "" .. subMotorNames)
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
    
    ecrawlMode = jbeamData.ecrawlMode or false

end

local function new()
end

local function onInit()
end

local function reset(jbeamData)
    motorDirection = 0
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    AdvanceAWD = jbeamData.AdvanceAWD or false
    if AdvanceAWD and #subMotors ~= 2 then
        AdvanceAWD = false
    end
    ifComfortRegen = jbeamData.ifComfortRegen or true

    startVelocity = defaultSVelocity
    connectVelocity = defaultCVelocity

    REEVMode = "off"
    REEVAV = REEVRPM * rpmToAV

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end

    enhanceDrive = false
    ifGearMotorDrive = jbeamData.ifGearMotorDrive or false
    RMSstate = nil

    for _, u in ipairs(enableModes) do
        if u == "reev" then
            ifREEVEnable = true
            proxyEngine.electricsThrottleName = "reevThrottle"
            break
        end
    end

    for _, v in ipairs(subMotors) do
        v.electricsThrottleName = "subThrottle"
    end

    for _, v in ipairs(motors) do
        v.maxWantedRegenTorque = v.originalRegenTorque
    end

    electrics.values.mainThrottle = 0
    ecrawlMode = jbeamData.ecrawlMode or false

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

M.setecrawlMode = setecrawlMode

M.reduceRegen = reduceRegen
M.enhanceRegen = enhanceRegen
M.getRegenLevel = getRegenLevel

M.changeAutoVelocity = changeAutoVelocity

M.enhanceDriveMode = enhanceDriveMode

M.init = init
M.reset = reset
M.onInit = onInit
M.onReset = onReset

M.new = new
M.updateGFX = updateGFX

rawset(_G, "hybridControl", M)
return M