--motorControl version 0.0.8alpha
--Final Edit 2024年3月3日22点21分
--by NZZ

local M = {}

local max = math.max
local min = math.min
local abs = math.abs
local floor = math.floor
local fsign = fsign

local constants = {rpmToAV = 0.104719755, avToRPM = 9.549296596425384}

local nsmotors = nil
local motors = nil

M.smoothedValues = nil

M.throttle = 0
M.brake = 0
M.regen = 0

local battery = nil

local regenHandling = {
    smoother = nil,
    smootherRateGain = 0,
    unavailableGears = {P = true, N = true},
    onePedalRegenCoef = 0.5,
    onePedalFrictionBrakeCoef = 1,
    numStrengthLevels = 3,
    strengthLevel = 0,
    regenTorqueToCoef = {},
    regenCoefToTorque = {},
    currentAvgFadeCoef = 0,
    instantMaxRegenTorque = 0,
    desiredOnePedalTorque = 0,
    currentRegenTorque = 0,
    regenFlag = nil
}
  
local brakeHandling = {
    smoother = nil,
    smoothStopTimeToLatch = 0.25,
    smoothStopLatchTime = 0,
    smoothStopReleaseAmount = 0.85,
    maxFrictionBrakeTorque = 0,
    frictionTorqueToCoef = {},
    frictionCoefToTorque = {}
}

local automaticHandling = {
    availableModes = {"P", "R", "N", "D", "S", "1", "2", "M"},
    hShifterModeLookup = {[-1] = "R", [0] = "N", "P", "D", "S", "2", "1", "M1"},
    forwardModes = {["D"] = true, ["S"] = true, ["1"] = true, ["2"] = true, ["M"] = true},
    availableModeLookup = {},
    existingModeLookup = {},
    modeIndexLookup = {},
    modes = {},
    mode = nil,
    modeIndex = 0,
    maxAllowedGearIndex = 0,
    minAllowedGearIndex = 0,
    autoDownShiftInM = true,
    defaultForwardMode = "D",
    throttleCoefWhileShifting = 1
}

local function updateRegen(dt)
    local avgRegenFadeCoef = 0
    local maxRegenTorque = 0
    local currentRegenTorque = 0
  
    electrics.values.regenFromBrake = 0
    electrics.values.regenFromOnePedal = 0
  
    for _, motor in ipairs(motors) do
      local motorRPM = abs(motor.outputAV1 * constants.avToRPM)
      local regenFadeCoef = 1 - min(1, motorRPM / motor.minPeakRegenRPM)
  
      avgRegenFadeCoef = avgRegenFadeCoef + regenFadeCoef / #motors
      maxRegenTorque = maxRegenTorque + motor.maxRegenTorque * motor.cumulativeGearRatio
      currentRegenTorque = currentRegenTorque + M.regen * motor.instantMaxRegenTorque * motor.cumulativeGearRatio
    end
  
    regenHandling.currentAvgFadeCoef = avgRegenFadeCoef
    regenHandling.instantMaxRegenTorque = maxRegenTorque
    regenHandling.currentRegenTorque = currentRegenTorque
    regenHandling.smootherRateGain = 1 + max(0, min(1, M.throttle * 2)) -- scale smoother rate with throttle input to release regen/brakes faster during sudden acceleration
    
  
    if regenHandling.unavailableGears[automaticHandling.mode] then
      M.regen = 0
      regenHandling.smoother:reset()
      regenHandling.strengthLevel = 0
      regenHandling.desiredOnePedalTorque = 0
    else
      regenHandling.strengthLevel = min(regenHandling.numStrengthLevels, electrics.values.regenStrength or 0)
  
      local onePedalDrivingCoef = regenHandling.strengthLevel / regenHandling.numStrengthLevels
      local onePedalRegenCoef = 0
  
      if onePedalDrivingCoef > 0 then
        local maxOffset = regenHandling.throttleNeutralPoint
        local throttleOffset = maxOffset * max(0.25, min(1, electrics.values.wheelspeed / 2.5))
        local positiveThrottle = max(0, (M.throttle - throttleOffset) / (1 - throttleOffset))
        local negativeThrottle = max(0, min(1, (throttleOffset - M.throttle) / throttleOffset))
  
        onePedalRegenCoef = onePedalDrivingCoef * regenHandling.onePedalRegenCoef * negativeThrottle
  
        M.throttle = positiveThrottle
      end
  
      -- when applying throttle while completely stopped, the smoother should be reset and regen should cancel immediately
      -- (otherwise there might be a slight perceived delay to the throttle response)

      --if M.smoothedValues.avgAV < 0.5 and M.throttle > 1e-2 then
      --  onePedalRegenCoef = 0
      --  regenHandling.smoother:reset()
      --end
  
      onePedalRegenCoef = regenHandling.smoother:get(onePedalRegenCoef, dt * regenHandling.smootherRateGain)
      regenHandling.desiredOnePedalTorque = regenHandling.regenCoefToTorque[floor(onePedalRegenCoef * 1000)] or (onePedalDrivingCoef * regenHandling.instantMaxRegenTorque)
  
      local frictionBrakeTorqueDemand = brakeHandling.frictionCoefToTorque[floor(M.brake * 1000)] or (M.brake * brakeHandling.maxFrictionBrakeTorque)
      local equivalentRegenCoefForBrakeDemand = regenHandling.regenTorqueToCoef[floor(frictionBrakeTorqueDemand)] or 1
      local brakePedalRegenCoef = (M.isArcadeSwitched or M.throttle > 0) and 0 or equivalentRegenCoefForBrakeDemand
      local finalRegenCoef = min(brakePedalRegenCoef + onePedalRegenCoef, 1)
      local emergencyBrakeCoef = M.brake >= 1 and 0.5 or 1
      local escCoef = electrics.values.escActive and 0 or 1
      local steeringCoef = abs(sensors.gx2) > 5 and 0.8 or 1
  
      M.regen = finalRegenCoef * escCoef * steeringCoef * emergencyBrakeCoef
      electrics.values.regenFromBrake = brakePedalRegenCoef
      electrics.values.regenFromOnePedal = onePedalRegenCoef
    end
  
    electrics.values.maxRegenStrength = regenHandling.numStrengthLevels
    electrics.values.regenThrottle = M.regen
end

local function updateBrakes(dt)
  if not regenHandling.unavailableGears[automaticHandling.mode] then
    local frictionBrakeTorqueDemand = brakeHandling.frictionCoefToTorque[floor(M.brake * 1000)] or (M.brake * brakeHandling.maxFrictionBrakeTorque)
    local actualBrakePedalRegenTorque = max(0, regenHandling.currentRegenTorque - regenHandling.desiredOnePedalTorque)
    local frictionBrakeDemandAfterRegen = max(0, frictionBrakeTorqueDemand - actualBrakePedalRegenTorque)
    local adjustedBrakeCoef = frictionBrakeDemandAfterRegen / brakeHandling.maxFrictionBrakeTorque
    local regenFadeCompensationBrakeCoef = 0

    -- When 1-pedal driving is at the strongest setting, blend friction brakes to bring the car to a stop and hold it there
    if regenHandling.strengthLevel == regenHandling.numStrengthLevels and M.regen > 1e-5 then
      local maxOnePedalRegenTorque = regenHandling.instantMaxRegenTorque * regenHandling.onePedalRegenCoef
      local brakeCoefForMaxRegen = brakeHandling.frictionTorqueToCoef[floor(maxOnePedalRegenTorque)] or 0
      local smoothStopCoef = 1

      if brakeHandling.smoothStopLatchTime < brakeHandling.smoothStopTimeToLatch then
        -- to achieve a smooth, comfortable stop, the brakes are gently released as the vehicle passes below 1 m/s
        -- however, once the vehicle stops completely, the brakes are latched "full on" to prevent the vehicle moving accidentally
        local smoothStopProgress = 1 - min(1, electrics.values.wheelspeed / 2) -- increases from [0..1] as vehicle slows from 2 to 0 m/s

        smoothStopCoef = 1 - smoothStopProgress * brakeHandling.smoothStopReleaseAmount -- decreases from [1..x] to gradually release brakes

        local desiredSpeedSign = electrics.values.gear == "R" and -1 or 1

        --if M.smoothedAvgAVInput * desiredSpeedSign < -0.5 then -- if vehicle starts rolling back, immediately latch (don't want to use smoothed value for this)
        --  brakeHandling.smoothStopLatchTime = brakeHandling.smoothStopTimeToLatch
        --elseif abs(M.smoothedValues.avgAV) < 0.05 then -- determine if vehicle is stopped
        --  brakeHandling.smoothStopLatchTime = brakeHandling.smoothStopLatchTime + dt
        --end
      end

      regenFadeCompensationBrakeCoef = regenHandling.currentAvgFadeCoef * brakeCoefForMaxRegen * regenHandling.onePedalFrictionBrakeCoef * smoothStopCoef
    else
      brakeHandling.smoothStopLatchTime = 0
      brakeHandling.smoother:reset()
    end

    if M.throttle > 0.25 then
      -- to prevent brakes from "sticking" during sudden acceleration from a stop, smoother is immediately reset if throttle exceeds 25%
      brakeHandling.smoother:reset()
    end

    regenFadeCompensationBrakeCoef = brakeHandling.smoother:get(regenFadeCompensationBrakeCoef, dt * regenHandling.smootherRateGain)

    if regenFadeCompensationBrakeCoef < 0.01 then
      -- so brake lights don't linger and pads don't drag a tiny bit as the smoother levels off
      regenFadeCompensationBrakeCoef = 0
    end

    adjustedBrakeCoef = max(adjustedBrakeCoef, regenFadeCompensationBrakeCoef)
    M.brake = adjustedBrakeCoef
  end
end

local function activeRegen(dt)
    if electrics.values.ifregen == 1 then
      updateRegen(dt)
      updateBrakes(dt)
      electrics.values.regenThrottle = 1
    elseif electrics.values.ifregen == 0 then
      electrics.values.regenThrottle = 0
    else
        electrics.values.ifregen = 1
    end
end

local function updateGFX(dt)
  activeRegen(dt)
  for _, v in ipairs(nsmotors) do
    v.motorDirection = electrics.values.motorDirection or 0
  end

  local storage = energyStorage.getStorage(battery)
  electrics.values.remainingpower = storage.remainingRatio
  electrics.values.evfuel = electrics.values.remainingpower * 100
  --log("", "hybrid", "hybrid" .. electrics.values.evfuel)

end

local function onReset()
    
end

local function init(jbeamData)
  battery =  jbeamData.energyStorage or "mainBattery"

  nsmotors = {}
  local nsmotorNames = jbeamData.nsmotorNames or {"mainMotor"}
  if nsmotorNames then
    for _, v in ipairs(nsmotorNames) do
      local nsmotor = powertrain.getDevice(v)
      if nsmotor then
        table.insert(nsmotors, nsmotor)
      end
    end
  end
  
  motors = {}
  local motorNames = jbeamData.motorNames
  if motorNames then
    for _, v in ipairs(motorNames) do
      local motor = powertrain.getDevice(v)
      if motor then
        table.insert(motors, motor)
      end
    end
  end

  -- determine maximum available friction brake torque
  local totalMaxBrakeTorque = 0
  for _, wd in pairs(wheels.wheels) do
    totalMaxBrakeTorque = totalMaxBrakeTorque + wd.brakeTorque * (wd.brakeInputSplit + (1 - wd.brakeInputSplit) * wd.brakeSplitCoef)
  end

  -- create two complimentary curves to map between a "brake input" coefficient and the resulting actual brake torque
  local tempFrictionCoefToTorqueMap = {}
  local tempFrictionTorqueToCoefMap = {}
  for i = 0, 100 do
    local brakeCoef = i / 100
    local totalBrakeTorque = 0
    for _, wd in pairs(wheels.wheels) do
      totalBrakeTorque = totalBrakeTorque + wd.brakeTorque * (min(brakeCoef, wd.brakeInputSplit) + max(brakeCoef - wd.brakeInputSplit, 0) * wd.brakeSplitCoef)
    end
    table.insert(tempFrictionCoefToTorqueMap, {i * 10, totalBrakeTorque})
    table.insert(tempFrictionTorqueToCoefMap, {totalBrakeTorque, brakeCoef})
  end

  local regenSmoothingRate = jbeamData.regenSmoothingRate or 20
  local regenSmoothingAccel = jbeamData.regenSmoothingAccel or 5

  brakeHandling.smoother = newTemporalSigmoidSmoothing(regenSmoothingRate * 2, regenSmoothingAccel * 2, regenSmoothingAccel, regenSmoothingRate)
  brakeHandling.smoothStopReleaseAmount = jbeamData.onePedalSmoothStopBrakeReleaseAmount or 0.85
  brakeHandling.maxFrictionBrakeTorque = totalMaxBrakeTorque
  brakeHandling.frictionCoefToTorque = createCurve(tempFrictionCoefToTorqueMap)
  brakeHandling.frictionTorqueToCoef = createCurve(tempFrictionTorqueToCoefMap)

  local tempRegenCoefToTorqueMap = {}
  local tempRegenTorqueToCoefMap = {}
  for i = 0, 100 do
    local regenCoef = i / 100
    local totalRegenTorque = 0
    for _, motor in pairs(motors) do
      totalRegenTorque = totalRegenTorque + regenCoef * motor.maxRegenTorque * motor.cumulativeGearRatio
    end
    table.insert(tempRegenCoefToTorqueMap, {i * 10, totalRegenTorque})
    table.insert(tempRegenTorqueToCoefMap, {totalRegenTorque, regenCoef})
  end

  regenHandling.smoother = newTemporalSigmoidSmoothing(regenSmoothingRate, regenSmoothingAccel, regenSmoothingAccel, regenSmoothingRate)
  regenHandling.onePedalRegenCoef = jbeamData.onePedalRegenCoef or 0.5
  regenHandling.onePedalFrictionBrakeCoef = jbeamData.onePedalFrictionBrakeCoef or 1
  regenHandling.numStrengthLevels = jbeamData.regenStrengthLevels or 3
  regenHandling.strengthLevel = electrics.values.regenStrength or jbeamData.defaultRegenStrength or regenHandling.numStrengthLevels
  regenHandling.throttleNeutralPoint = jbeamData.regenThrottleNeutralPoint or 0.15
  regenHandling.regenCoefToTorque = createCurve(tempRegenCoefToTorqueMap)
  regenHandling.regenTorqueToCoef = createCurve(tempRegenTorqueToCoefMap)
  regenHandling.regenFlag = jbeamData.regenFlag or 1

  electrics.values.regenStrength = regenHandling.strengthLevel * regenHandling.regenFlag
end

M.init = init
M.onReset = onReset
M.onInit = init
M.updateGFX = updateGFX

M.smoothedAvgAVInput = 1

return M