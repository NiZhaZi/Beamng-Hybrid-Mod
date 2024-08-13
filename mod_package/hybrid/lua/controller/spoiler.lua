-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.type = "auxilliary"
M.relevantDevice = nil

local abs = math.abs
local max = math.max

local idleFrontPosition = 0
local idleRearPosition = 0
local mediumSpeedFrontPosition = 0
local mediumSpeedRearPosition = 0
local highSpeedFrontPosition = 0
local highSpeedRearPosition = 0
local highSpeedCorneringFrontPosition = 0
local highSpeedCorneringRearPosition = 0
local brakingFrontPosition = 0
local brakingRearPosition = 0

local transitionTimeIdle = 0.3
local transitionTimeBraking = 0.15

local lastEngineRunning = 0
local lastAirBrakeActive = false
local lastMediumSpeedPositionActive
local lastHighSpeedPositionActive
local lasthighSpeedCorneringPositionActive

local frontPositionSmoother = newTemporalSmoothing(1, 1)
local rearPositionSmoother = newTemporalSmoothing(1, 1)
local highSpeedCorneringInputSmoother = newTemporalSmoothing(1, 1000)

local speedThresholdMedium = 20
local speedThresholdHigh = 55
local brakeThresholdHigh = 0.4
local speedThresholdAirBrake = 5

local targetFrontPosition
local targetRearPosition
local currentFrontPosition
local currentRearPosition
local positionTransitionTimer

local sensorHub

local function updateGFX(dt)
  targetFrontPosition = idleFrontPosition
  targetRearPosition = idleRearPosition
  currentFrontPosition = electrics.values.spoilerF
  currentRearPosition = electrics.values.spoilerR
  local speed = electrics.values.wheelspeed

  local mediumSpeedPositionActive = speed > speedThresholdMedium
  if mediumSpeedPositionActive ~= lastMediumSpeedPositionActive then
    positionTransitionTimer = transitionTimeIdle
  end
  if mediumSpeedPositionActive then
    targetFrontPosition = mediumSpeedFrontPosition
    targetRearPosition = mediumSpeedRearPosition
  end

  local highSpeedPositionActive = speed > speedThresholdHigh
  if highSpeedPositionActive ~= lastHighSpeedPositionActive then
    positionTransitionTimer = transitionTimeBraking
  end
  if highSpeedPositionActive then
    targetFrontPosition = highSpeedFrontPosition
    targetRearPosition = highSpeedRearPosition
  end

  local speedHighEnough = speed > speedThresholdHigh
  local accHighEnough = abs(sensors.gx2) > 3
  local yawHighEnough = sensorHub and abs(sensorHub.yawAV) > 0.2
  local steeringHighEnough = abs(electrics.values.steering_input or 0) > 0.1
  local highSpeedCorneringInput = speedHighEnough and (accHighEnough or yawHighEnough or steeringHighEnough)

  local highSpeedCorneringPositionActive = highSpeedCorneringInputSmoother:getUncapped(highSpeedCorneringInput and 1 or 0, dt) > 0
  if highSpeedCorneringPositionActive ~= lasthighSpeedCorneringPositionActive then
    positionTransitionTimer = transitionTimeBraking
  end
  if highSpeedCorneringPositionActive then
    targetFrontPosition = highSpeedCorneringFrontPosition
    targetRearPosition = highSpeedCorneringRearPosition
  end

  local yawControlOverrideAirBrake = electrics.values.yawControlRequestReduceOversteer or 0
  local activateAirBrake = (electrics.values.brake > brakeThresholdHigh or yawControlOverrideAirBrake > 0) and speed >= speedThresholdAirBrake
  if activateAirBrake ~= lastAirBrakeActive then
    positionTransitionTimer = transitionTimeBraking
  end
  if activateAirBrake then
    targetFrontPosition = brakingFrontPosition
    targetRearPosition = brakingRearPosition
  end

  if electrics.values.engineRunning ~= lastEngineRunning then
    positionTransitionTimer = transitionTimeIdle
  end
  if electrics.values.engineRunning < 1 then
    targetFrontPosition = 0
    targetRearPosition = 0
  end

  local frontRate = abs(currentFrontPosition - targetFrontPosition) / positionTransitionTimer
  local rearRate = abs(currentRearPosition - targetRearPosition) / positionTransitionTimer

  currentFrontPosition = frontPositionSmoother:getWithRateUncapped(targetFrontPosition, dt, frontRate)
  currentRearPosition = rearPositionSmoother:getWithRateUncapped(targetRearPosition, dt, rearRate)

  positionTransitionTimer = max(positionTransitionTimer - dt, 0)

  electrics.values.spoilerF = currentFrontPosition
  electrics.values.spoilerR = currentRearPosition

  lastEngineRunning = electrics.values.engineRunning
  lastAirBrakeActive = activateAirBrake
  lastMediumSpeedPositionActive = mediumSpeedPositionActive
  lastHighSpeedPositionActive = highSpeedPositionActive
  lasthighSpeedCorneringPositionActive = highSpeedCorneringPositionActive
end

local function reset(jbeamData)
  idleFrontPosition = 0
  idleRearPosition = 0
  brakingFrontPosition = 0
  brakingRearPosition = 0
  electrics.values.spoilerF = idleFrontPosition
  electrics.values.spoilerR = idleRearPosition
  frontPositionSmoother:set(idleFrontPosition)
  rearPositionSmoother:set(idleRearPosition)
  highSpeedCorneringInputSmoother:reset()
end

local function init(jbeamData)
  idleFrontPosition = 0
  idleRearPosition = 0
  brakingFrontPosition = 0
  brakingRearPosition = 0
  electrics.values.spoilerF = idleFrontPosition
  electrics.values.spoilerR = idleRearPosition
  frontPositionSmoother:set(idleFrontPosition)
  rearPositionSmoother:set(idleRearPosition)
end

local function initLastStage(jbeamData)
  local CMU = controller.getController("CMU")
  if CMU then
    sensorHub = CMU.sensorHub
  end
end

local function setParameters(parameters)

  if parameters.speedThresholdMedium then
    speedThresholdMedium = parameters.speedThresholdMedium
  end
  if parameters.speedThresholdHigh then
    speedThresholdHigh = parameters.speedThresholdHigh
  end
  if parameters.speedThresholdAirBrake then
    speedThresholdAirBrake = parameters.speedThresholdAirBrake
  end

  if parameters.idleFrontPosition then
    idleFrontPosition = parameters.idleFrontPosition
  end
  if parameters.idleRearPosition then
    idleRearPosition = parameters.idleRearPosition
  end

  if parameters.mediumSpeedFrontPosition then
    mediumSpeedFrontPosition = parameters.mediumSpeedFrontPosition
  end
  if parameters.mediumSpeedRearPosition then
    mediumSpeedRearPosition = parameters.mediumSpeedRearPosition
  end

  if parameters.highSpeedFrontPosition then
    highSpeedFrontPosition = parameters.highSpeedFrontPosition
  end
  if parameters.highSpeedRearPosition then
    highSpeedRearPosition = parameters.highSpeedRearPosition
  end

  if parameters.highSpeedCorneringFrontPosition then
    highSpeedCorneringFrontPosition = parameters.highSpeedCorneringFrontPosition
  end
  if parameters.highSpeedCorneringRearPosition then
    highSpeedCorneringRearPosition = parameters.highSpeedCorneringRearPosition
  end

  if parameters.brakingFrontPosition then
    brakingFrontPosition = parameters.brakingFrontPosition
  end
  if parameters.brakingRearPosition then
    brakingRearPosition = parameters.brakingRearPosition
  end

  positionTransitionTimer = transitionTimeIdle
end

M.init = init
M.initLastStage = initLastStage
M.reset = reset
M.updateGFX = updateGFX

M.setParameters = setParameters

return M
