--hybridContrl version 0.0.7alpha
--Final Edit 2024年2月22日23点46分
--by NZZ

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
local mode = nil
local isCrawl = 0
local ifMotorOn = nil
local motorRatio1 = nil
local motorRatio2 = nil
local directRPM1 = nil
local directRPM2 = nil

local detN = nil
local detM = nil

local startVelocity = nil
local connectVelocity = nil

local edriveMode = nil
local regenLevel = 5
local ifComfortRegen = nil
local comfortRegenBegine = nil
local comfortRegenEnd = nil

local enableModes = {}

local function reduceRegen()
    --[[
    for _, v in ipairs(motors) do
        if v.maxWantedRegenTorque > 0 then
            v.maxWantedRegenTorque = v.maxWantedRegenTorque - v.originalRegenTorque * 0.2
            gui.message({ txt = "Energy Recovery Reduced" }, 5, "", "")
        elseif v.maxWantedRegenTorque == 0 then
            gui.message({ txt = "Energy Recovery Min" }, 5, "", "")
        elseif v.maxWantedRegenTorque < 0 then
            v.maxWantedRegenTorque = 0
            gui.message({ txt = "Energy Recovery Min" }, 5, "", "")
        end
    end
    --[[
    for _, v in ipairs(mainMotors) do
        if v.maxWantedRegenTorque > 0 then
            v.maxWantedRegenTorque = v.maxWantedRegenTorque - v.originalRegenTorque * 0.2
            gui.message({ txt = "Energy Recovery Reduced" }, 5, "", "")
        elseif v.maxWantedRegenTorque == 0 then
            gui.message({ txt = "Energy Recovery Min" }, 5, "", "")
        elseif v.maxWantedRegenTorque < 0 then
            v.maxWantedRegenTorque = 0
            gui.message({ txt = "Energy Recovery Min" }, 5, "", "")
        end
    end]]

    if regenLevel > 0 then
        regenLevel = regenLevel - 1
    end

end

local function enhanceRegen()
    --[[
    for _, v in ipairs(motors) do
        if v.maxWantedRegenTorque < v.originalRegenTorque then
            v.maxWantedRegenTorque = v.maxWantedRegenTorque + v.originalRegenTorque * 0.2
            gui.message({ txt = "Energy Recovery Enhanced" }, 5, "", "")
        elseif v.maxWantedRegenTorque == v.originalRegenTorque then
            gui.message({ txt = "Energy Recovery Max" }, 5, "", "")
        elseif v.maxWantedRegenTorque > v.originalRegenTorque then
            v.maxWantedRegenTorque = v.originalRegenTorque
            gui.message({ txt = "Energy Recovery Max" }, 5, "", "")
        end
    end
    --[[
    for _, v in ipairs(mainMotors) do
        if v.maxWantedRegenTorque < v.originalRegenTorque then
            v.maxWantedRegenTorque = v.maxWantedRegenTorque + v.originalRegenTorque * 0.2
            gui.message({ txt = "Energy Recovery Enhanced" }, 5, "", "")
        elseif v.maxWantedRegenTorque == v.originalRegenTorque then
            gui.message({ txt = "Energy Recovery Max" }, 5, "", "")
        elseif v.maxWantedRegenTorque > v.originalRegenTorque then
            v.maxWantedRegenTorque = v.originalRegenTorque
            gui.message({ txt = "Energy Recovery Max" }, 5, "", "")
        end
    end]]

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

local function setMode(mode)
    for _, u in ipairs(enableModes) do
        if mode == u then
            electrics.values.hybridMode = mode

            if mode == "hybrid" then
                gui.message({ txt = "Switch to hybrid mode" }, 5, "", "")
                if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                    proxyEngine:activateStarter()
                end
                for _, v in ipairs(motors) do
                    v:setmotorRatio(motorRatio1)
                    v:setMode("connected")
                    ifMotorOn = true
                end
            elseif mode == "fuel" then
                gui.message({ txt = "Switch to fuel mode" }, 5, "", "")
                if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                    proxyEngine:activateStarter()
                end
                for _, v in ipairs(motors) do
                    v:setmotorRatio(0)
                    v:setMode("connected")
                    ifMotorOn = false  
                end
            elseif mode == "electric" then
                gui.message({ txt = "Switch to electric mode" }, 5, "", "")
                proxyEngine:setIgnition(0)
                for _, v in ipairs(motors) do
                    v:setmotorRatio(motorRatio2)
                    v:setMode("disconnected")
                    ifMotorOn = true         
                end
            elseif mode == "auto" then
                gui.message({ txt = "Switch to auto mode" }, 5, "", "")
                proxyEngine:setIgnition(0)
                for _, v in ipairs(motors) do
                    v:setmotorRatio(motorRatio2)
                    v:setMode("disconnected")
                    ifMotorOn = true
                end
            elseif mode == "direct" then
                gui.message({ txt = "Switch to direct mode" }, 5, "", "")
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
    edriveMode = mode
end

local function updateGFX(dt)
    --log("", "hybrid", "hybrid" .. 3)
    getGear()

    if electrics.values.hybridMode == "electric" then
        proxyEngine:setIgnition(0)
    end

    --auto mode
    if electrics.values.hybridMode == "auto" then
        if electrics.values.airspeed < startVelocity - 5 and detN ~= 1 then
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio2)
                v:setMode("disconnected")
                proxyEngine:setIgnition(0)
            end
            detN = 1
        elseif electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity and detN ~= 2 then
            detN = 2
        elseif electrics.values.airspeed >= connectVelocity and detN ~= 3 then
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
                if electrics.values.ignitionLevel == 2 and electrics.values.engineRunning == 0 then
                    proxyEngine:activateStarter()
                end
            end
            detN = 3
        end
    
        if electrics.values.airspeed < startVelocity - 5 then
            if electrics.values.engineRunning == 1 then  
                proxyEngine:setIgnition(0)
            end
        elseif electrics.values.airspeed >= startVelocity and electrics.values.airspeed < connectVelocity then
            if electrics.values.engineRunning == 0 then
                proxyEngine:activateStarter()
            end
        end
    end

    if electrics.values.hybridMode ~= "auto" then
        detN = 0
    end
    --auto mode

    --direct mode
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

        --[[if proxyEngine.outputRPM < directRPM1 then 
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio2)
                v:setMode("disconnected")
            end
            for _, v in ipairs(directMotors) do
                v:setmotorRatio(0)
                v:setMode("disconnected")
            end
        elseif proxyEngine.outputRPM >= directRPM1 and proxyEngine.outputRPM < directRPM2 then
            for _, v in ipairs(motors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
            end
            for _, v in ipairs(directMotors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("disconnected")
            end
        elseif proxyEngine.outputRPM >= directRPM2 then 
            for _, v in ipairs(directMotors) do
                v:setmotorRatio(motorRatio1)
                v:setMode("connected")
            end
        end]]
    end

    if electrics.values.hybridMode ~= "direct" then
        detM = 0
        for _, v in ipairs(directMotors) do
            v:setmotorRatio(0)
        end
    end
    --direct mode

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
        if abs(mianRPM - subRPM) >= ondemandMaxRPM then
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

    enableModes = jbeamData.enableModes or {"hybrid", "fuel", "electric", "auto"}
    --auto      自动选择
    --reev      增程模式
    --electric  电机直驱
    --fuel      燃油直驱
    --hybrid    混合驱动
    --direct    直接驱动
    
    motorRatio1 = jbeamData.motorRatio1 or 1
    motorRatio2 = jbeamData.motorRatio2 or 1
    startVelocity = jbeamData.startVelocity or 10
    connectVelocity = jbeamData.connectVelocity or 11
    directRPM1 = jbeamData.directRPM1 or 1000
    directRPM2 = jbeamData.directRPM2 or 3000

    edriveMode = jbeamData.defaultEAWDMode or "partTime"
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

local function onReset(jbeamData)
    edriveMode = jbeamData.defaultEAWDMode or "partTime"
    ifComfortRegen = jbeamData.ifComfortRegen or true

    if jbeamData.defaultMode then
        setMode(jbeamData.defaultMode)
    else
        setMode("hybrid")
    end
end

M.setMode = setMode
M.setPartTimeDriveMode = setPartTimeDriveMode

M.reduceRegen = reduceRegen
M.enhanceRegen = enhanceRegen

M.init = init
M.onInit = onInit
M.onReset = onReset

M.new = new
M.updateGFX = updateGFX


return M