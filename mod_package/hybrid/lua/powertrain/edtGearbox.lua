-- edtGearbox.lua - 2024.4.20 14:45 - DCT Gearbox with electric motor
-- by NZZ
-- version 0.2.3 beta
-- final edit - 2024.5.12 11:18

local M = {}

M.outputPorts = {[1] = true}
M.deviceCategories = {clutchlike = true, gearbox = true}
M.requiredExternalInertiaOutputs = {1}

local max = math.max
local min = math.min
local abs = math.abs
local sqrt = math.sqrt

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384

--insert0

local torqueToPower = 0.0001404345295653085
local psToWatt = 735.499

local floor = math.floor
local clamp = clamp
local sign = sign

local vehicleController = nil

local function getTorqueData(device)
  local curves = {}
  local curveCounter = 1
  local maxTorque = 0
  local maxTorqueRPM = 0
  local maxPower = 0
  local maxPowerRPM = 0
  local maxRPM = 0

  local torqueCurve = {}
  local powerCurve = {}

  for k, v in pairs(device.torqueCurve) do
    if type(k) == "number" then
      torqueCurve[k + 1] = v - device.friction - (device.dynamicFriction * k * rpmToAV)
      powerCurve[k + 1] = torqueCurve[k + 1] * k * torqueToPower
      if torqueCurve[k + 1] > maxTorque then
        maxTorque = torqueCurve[k + 1]
        maxTorqueRPM = k + 1
      end
      if powerCurve[k + 1] > maxPower then
        maxPower = powerCurve[k + 1]
        maxPowerRPM = k + 1
      end
      maxRPM = max(maxRPM, k)
    end
  end

  table.insert(curves, curveCounter, { torque = torqueCurve, power = powerCurve, name = "Electric", priority = 10 })

  table.sort(
    curves,
    function(a, b)
    local ra, rb = a.priority, b.priority
    if ra == rb then
      return a.name < b.name
    else
      return ra > rb
    end
  end
  )

  local dashes = { nil, { 10, 4 }, { 8, 3, 4, 3 }, { 6, 3, 2, 3 }, { 5, 3 } }
  for k, v in ipairs(curves) do
    v.dash = dashes[k]
    v.width = 2
  end

  return { maxRPM = maxRPM, curves = curves, maxTorque = maxTorque, maxPower = maxPower, maxTorqueRPM = maxTorqueRPM, maxPowerRPM = maxPowerRPM, finalCurveName = curveCounter, deviceName = device.name, vehicleID = obj:getId() }
end

local function sendTorqueData(device, data)
  if not data then
    data = device:getTorqueData()
  end
  guihooks.trigger("TorqueCurveChanged", data)
end

local function scaleFriction(device, friction)
  device.friction = device.friction * friction
end

local function scaleOutputTorque(device, state)
  device.outputTorqueState = 1 * state
end

local function disable(device)
  device.outputTorqueState = 0
  device.isDisabled = true
end

local function enable(device)
  device.outputTorqueState = 1
  device.isDisabled = false
end

local function lockUp(device)
  device.outputTorqueState = 0
  device.outputAVState = 0
  device.isDisabled = true
end

local function updateEnergyStorageRatios(device)
  device.energyStorageRatios = {}
  device.energyStorageRegenRatios = {}
  for _, s in pairs(device.registeredEnergyStorages) do
    local storage = energyStorage.getStorage(s)
    if storage then
      device.energyStorageRatios[storage.name] = 1 / device.storageWithEnergyCounter --ratios for using energy
      device.energyStorageRegenRatios[storage.name] = 1 / device.storageCounter --ratios for regenerating energy
    end
  end
end

local function updateEnergyUsage(device)
  if not device.energyStorage then
    return
  end

  local hasEnergy = false
  local previousStorageCount = device.storageWithEnergyCounter
  for _, s in pairs(device.registeredEnergyStorages) do
    local storage = energyStorage.getStorage(s)
    if storage then
      local previous = device.previousEnergyLevels[storage.name]
      --for regen we need to use a ratio over all storages, not just those still holding energy
      local storageRatio = device.spentEnergy > 0 and device.energyStorageRatios[storage.name] or device.energyStorageRegenRatios[storage.name]
      storage.storedEnergy = clamp(storage.storedEnergy - (device.spentEnergy * storageRatio), 0, storage.energyCapacity)
      if previous > 0 and storage.storedEnergy <= 0 then
        device.storageWithEnergyCounter = device.storageWithEnergyCounter - 1
      elseif previous <= 0 and storage.storedEnergy > 0 then
        device.storageWithEnergyCounter = device.storageWithEnergyCounter + 1
      end
      device.previousEnergyLevels[storage.name] = storage.storedEnergy
      device.previousEnergyRatios[storage.name] = storage.remainingRatio
      hasEnergy = hasEnergy or storage.storedEnergy > 0
    end
  end

  if previousStorageCount ~= device.storageWithEnergyCounter then
    device:updateEnergyStorageRatios()
  end
  device.spentEnergy = 0

  if not hasEnergy and device.hasEnergy then
    device:disable()
  elseif hasEnergy and not device.hasEnergy then
    device:enable()
  end

  device.hasEnergy = hasEnergy
end

local function setTempRevLimiter(device, revLimiterAV, maxOvershootAV)
  device.tempRevLimiterAV = revLimiterAV
  device.tempRevLimiterMaxAVOvershoot = maxOvershootAV or device.tempRevLimiterAV * 0.01
  device.invTempRevLimiterRange = 1 / device.tempRevLimiterMaxAVOvershoot
  device.isTempRevLimiterActive = true
end

local function resetTempRevLimiter(device)
  device.tempRevLimiterAV = 999999999
  --device.maxAV * 10
  device.tempRevLimiterMaxAVOvershoot = device.tempRevLimiterAV * 0.01
  device.invTempRevLimiterRange = 1 / device.tempRevLimiterMaxAVOvershoot
  device.isTempRevLimiterActive = false
end

local function registerStorage(device, storageName)
  local storage = energyStorage.getStorage(storageName)
  if storage and storage.type == "electricBattery" and storage.storedEnergy > 0 then
    device.storageWithEnergyCounter = device.storageWithEnergyCounter + 1
    device.storageCounter = device.storageCounter + 1
    table.insert(device.registeredEnergyStorages, storageName)
    device:updateEnergyStorageRatios()
    device.hasEnergy = true
    device.previousEnergyLevels[storageName] = storage.storedEnergy
  end
end

local function getSoundConfiguration(device)
  return device.soundConfiguration
end

local function setmotorRatio(device, ratio)
  device.motorRatio = ratio * 1
end

local function setmotorType(device, motorType)
  device.motorType = motorType
end

local function motorTorque(device, dt)
  local engineAV = device.inputAV
  local throttleFactor = electrics.values[device.electricsThrottleFactorName] or device.throttleFactor
  local throttle = (electrics.values[device.electricsThrottleName] or 0) * throttleFactor
  throttle = clamp(-throttle * clamp(engineAV - device.tempRevLimiterAV, 0, device.tempRevLimiterMaxAVOvershoot) * device.invTempRevLimiterRange + throttle, 0, 1)
  --smooth our actual throttle value to not have super instant torque that will just break traction
  throttle = device.throttleSmoother:getUncapped(throttle, dt)
  device.throttle = throttle

  local motorDirection = device.motorDirection
  local torqueCurve = device.torqueCurve
  local friction = device.friction
  local dynamicFriction = device.dynamicFriction
  local rpm = engineAV * avToRPM * motorDirection * device.motorRatio--/ device.gearRatios[device.gearIndex]
  local torqueRPM = floor(rpm)

  --local torqueCoef = clamp(device.torqueCoef, 0, 1) --can be used to externally reduce the available torque, for example to limit output power
  local torqueCoef = 1
  local torque = (torqueCurve[torqueRPM] or (torqueRPM < 0 and torqueCurve[0] or 0)) * 1 * torqueCoef
  torque = torque * throttle * motorDirection
  torque = min(torque, device.maxTorqueLimit) --limit output torque to a specified max, math.huge by default

  local regenThrottle = electrics.values[device.electricsRegenThrottleName] or 0
  local rawRegenTorque = (device.regenCurve[torqueRPM] or 0)
  local regenTorque = -(min(max(rawRegenTorque * regenThrottle, min(rawRegenTorque, device.minWantedRegenTorque)), device.maxWantedRegenTorque) * sign(regenThrottle) * throttleFactor * motorDirection)
  device.regenThrottle = regenThrottle
  device.instantMaxRegenTorque = rawRegenTorque

  local actualTorque = throttle > 0 and torque or regenTorque

  local maxCurrentTorque = (torqueCurve[torqueRPM] or torqueCurve[0]) - friction - (dynamicFriction * abs(device.outputRPM) * 0.1047197177)
  local instantEngineLoad = clamp(actualTorque / (maxCurrentTorque + 1e-30), -1, 1)
  device.instantEngineLoad = instantEngineLoad
  device.engineLoad = device.loadSmoother:getCapped(instantEngineLoad, dt)

  local dtT = dt * actualTorque

  local avSign = sign(engineAV)
  --local grossWork = dtT * (dtT * device.halfInvEngInertia + engineAV)
  --clutchless device has no inertia of its own now, no need for additional term
  local grossWork = dtT * engineAV
  device.grossWorkPerUpdate = device.grossWorkPerUpdate + grossWork
  device.spentEnergy = device.spentEnergy + grossWork / device.electricalEfficiencyTable[floor(abs(device.engineLoad) * 100) * 0.01]
  device.frictionLossPerUpdate = device.frictionLossPerUpdate + dt * engineAV * (friction + dynamicFriction * engineAV)

  local frictionTorque = abs(friction * avSign + dynamicFriction * engineAV)
  --friction torque is limited for stability
  frictionTorque = min(frictionTorque, abs(engineAV) * device.inertia * 2000) * avSign

  local timeSign = 1
  --log("", "", "" .. (actualTorque - frictionTorque) * timeSign)
  return (actualTorque - frictionTorque) * timeSign * device.motorRatio --/ device.gearRatios[device.gearIndex]
end

local function updateGFX(device, dt)

  --insert0

  if device.motorType == "drive" then
    if electrics.values.ignitionLevel == 2 then
      device.motorDirection = electrics.values.motorDirection or 0
    elseif electrics.values.ignitionLevel ~= 2 then
      device.motorDirection = 0
    end
  elseif device.motorType == "powerGenerator" then
    --device.motorDirection = 1
  else
    --device.motorDirection = 0
  end

  device:updateEnergyUsage()

  device.outputRPM = device.outputAV1 * avToRPM

  device.grossWorkPerUpdate = 0
  device.frictionLossPerUpdate = 0

  device.parent.outputTorque1 = device.parent.outputTorque1 + motorTorque(device, dt)

  --insert1
end

--insert1

local function updateSounds(device, dt)
  local gearWhineCoefInput = device.gearWhineCoefsInput[device.gearIndex] or 0
  local gearWhineCoefOutput = device.gearWhineCoefsOutput[device.gearIndex] or 0

  local gearWhineDynamicsCoef = 0.05
  local fixedVolumePartOutput = device.gearWhineOutputAV * device.invMaxExpectedOutputAV --normalized AV
  local powerVolumePartOutput = device.gearWhineOutputAV * device.gearWhineOutputTorque * device.invMaxExpectedPower --normalized power
  local volumeOutput = clamp(gearWhineCoefOutput + ((abs(fixedVolumePartOutput) + abs(powerVolumePartOutput)) * gearWhineDynamicsCoef), 0, 10)

  local fixedVolumePartInput = device.gearWhineInputAV * device.invMaxExpectedInputAV --normalized AV
  local powerVolumePartInput = device.gearWhineInputAV * device.gearWhineInputTorque * device.invMaxExpectedPower --normalized power
  local volumeInput = clamp(gearWhineCoefInput + ((abs(fixedVolumePartInput) + abs(powerVolumePartInput)) * gearWhineDynamicsCoef), 0, 10)

  local inputPitchCoef = device.gearRatio >= 0 and device.forwardInputPitchCoef or device.reverseInputPitchCoef
  local outputPitchCoef = device.gearRatio >= 0 and device.forwardOutputPitchCoef or device.reverseOutputPitchCoef
  local pitchInput = clamp(abs(device.gearWhineInputAV) * avToRPM * inputPitchCoef, 0, 10000000)
  local pitchOutput = clamp(abs(device.gearWhineOutputAV) * avToRPM * outputPitchCoef, 0, 10000000)

  local inputLoad = device.gearWhineInputTorque * device.invMaxExpectedInputTorque
  local outputLoad = device.gearWhineOutputTorque * device.invMaxExpectedOutputTorque
  local outputRPMSign = sign(device.gearWhineOutputAV)

  device.gearWhineOutputLoop:setVolumePitch(volumeOutput, pitchOutput, outputLoad, outputRPMSign)
  device.gearWhineInputLoop:setVolumePitch(volumeInput, pitchInput, inputLoad, outputRPMSign)

  -- print(string.format("volIn - %0.2f / volOut - %0.2f / ptchIn - %0.2f / ptchOut - %0.2f / inLoad - %0.2f / outLoad - %0.2f", volumeInput, volumeOutput, pitchInput, pitchOutput, inputLoad, outputLoad))

  -- insert0
  local soundsign
  if device.motorRatio == 0 then
    soundsign = 0
  else
    soundsign = 1
  end

  local rpm = device.soundRPMSmoother:get(abs(device.outputAV1 * avToRPM), dt) * soundsign
  local engineLoad = clamp(device.soundLoadSmoother:get(abs(device.instantEngineLoad), dt), device.soundMinLoadMix, device.soundMaxLoadMix)
  local fundamentalFreq = sounds.hzToFMODHz(rpm * device.fundamentalFrequencyRPMCoef)
  obj:setEngineSound(device.engineSoundID, rpm, engineLoad, fundamentalFreq, device.engineVolumeCoef)
  -- insert1

end

local function updateVelocity(device, dt)
  device.inputAV = device.parent.outputAV1
  device.clutchAV1 = device.outputAV1 * device.gearRatio1 * device.lockCoef
  device.clutchAV2 = device.outputAV1 * device.gearRatio2 * device.lockCoef
end

local function updateTorque(device, dt)
  local inputAV = device.inputAV
  device.clutchRatio1 = electrics.values[device.electricsClutchRatio1Name] or 0
  device.clutchRatio2 = electrics.values[device.electricsClutchRatio2Name] or 0

  if inputAV < (device.parent.idleAV or inputAV) * 0.5 then
    device.clutchRatio1 = 0
    device.clutchRatio2 = 0
  end

  local avDiff1 = inputAV - device.clutchAV1
  local avDiff2 = inputAV - device.clutchAV2
  local clutchRatio1 = device.clutchRatio1
  local clutchRatio2 = device.clutchRatio2
  local maxClutchAngle1 = device.maxClutchAngle1
  local maxClutchAngle2 = device.maxClutchAngle2

  device.clutchAngle1 = min(max(device.clutchAngle1 + avDiff1 * dt * device.clutchStiffness, -maxClutchAngle1 * clutchRatio1), maxClutchAngle1 * clutchRatio1)
  device.clutchAngle2 = min(max(device.clutchAngle2 + avDiff2 * dt * device.clutchStiffness, -maxClutchAngle2 * clutchRatio2), maxClutchAngle2 * clutchRatio2)

  local lockTorque = device.lockTorque * device.wearLockTorqueCoef * device.damageLockTorqueCoef
  device.torqueDiff1 = (min(max(device.clutchAngle1 * device.lockSpring1 + device.lockDamp1 * avDiff1 * clutchRatio1, -lockTorque), lockTorque))
  device.torqueDiff2 = (min(max(device.clutchAngle2 * device.lockSpring2 + device.lockDamp2 * avDiff2 * clutchRatio2, -lockTorque), lockTorque))

  device.torqueDiff = device.torqueDiff1 + device.torqueDiff2 --+ motorTorque(device, dt)
  --log("", "torque", device.torqueDiff)
  --log("", "RPM", device.inputAV * avToRPM)

  device.outputTorque1 = ((device.torqueDiff1 - device.friction * min(max(device.clutchAV1, -1), 1)) * device.gearRatio1 + (device.torqueDiff2 - device.friction * min(max(device.clutchAV2, -1), 1)) * device.gearRatio2) * device.lockCoef
  device.clutchRatio = max(device.clutchRatio1, device.clutchRatio2)

  device.gearWhineInputTorque = device.gearWhineInputTorqueSmoother:get(device.torqueDiff)
  device.gearWhineOutputTorque = device.gearWhineOutputTorqueSmoother:get(device.outputTorque1)
  device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(inputAV)
  device.gearWhineOutputAV = device.gearWhineOutputAVSmoother:get(device.outputAV1)
end

local function neutralUpdateVelocity(device, dt)
  device.inputAV = device.parent.outputAV1
  device.clutchAV1 = device.outputAV1 * device.gearRatio1 * device.lockCoef
  device.clutchAV2 = device.outputAV1 * device.gearRatio2 * device.lockCoef
end

local function neutralUpdateTorque(device, dt)
  device.torqueDiff = 0 --+ motorTorque(device, dt)
  device.outputTorque1 = 0
  --log("", "torque", device.torqueDiff)
  --log("", "RPM", device.inputAV * avToRPM)

  device.gearWhineInputTorque = device.gearWhineInputTorqueSmoother:get(device.torqueDiff)
  device.gearWhineOutputTorque = device.gearWhineOutputTorqueSmoother:get(device.outputTorque1)
  --device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(device.inputAV)
  device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(max(device.clutchAV1, device.clutchAV2))
  device.gearWhineOutputAV = device.gearWhineOutputAVSmoother:get(device.outputAV1)
end

local function parkUpdateVelocity(device, dt)
  device.inputAV = device.parent.outputAV1
  device.clutchAV1 = device.outputAV1 * device.gearRatio1 * device.lockCoef
  device.clutchAV2 = device.outputAV1 * device.gearRatio2 * device.lockCoef
end

local function parkUpdateTorque(device, dt)
  device.torqueDiff = 0
  local outputAV1 = device.outputAV1

  if abs(outputAV1) < 100 then
    device.parkEngaged = 1
  end

  device.parkClutchAngle = min(max(device.parkClutchAngle + outputAV1 * dt, -device.maxParkClutchAngle), device.maxParkClutchAngle)
  device.outputTorque1 = -(device.parkClutchAngle * device.parkLockSpring + device.parkLockDamp * outputAV1) * device.parkEngaged

  device.gearWhineInputTorque = device.gearWhineInputTorqueSmoother:get(device.torqueDiff)
  device.gearWhineOutputTorque = device.gearWhineOutputTorqueSmoother:get(device.outputTorque1)
  --device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(device.inputAV)
  device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(max(device.clutchAV1, device.clutchAV2))
  device.gearWhineOutputAV = device.gearWhineOutputAVSmoother:get(device.outputAV1)
end

local function selectUpdates(device)
  device.velocityUpdate = updateVelocity
  device.torqueUpdate = updateTorque

  if device.mode == "neutral" then
    device.velocityUpdate = neutralUpdateVelocity
    device.torqueUpdate = neutralUpdateTorque
  end

  if device.mode == "park" then
    device.velocityUpdate = parkUpdateVelocity
    device.torqueUpdate = parkUpdateTorque
    device.parkEngaged = 0
  end
end

local function applyDeformGroupDamage(device, damageAmount)
  device.damageLockTorqueCoef = max(device.damageLockTorqueCoef - linearScale(damageAmount, 0, 0.01, 0, 0.1), 0.2)
end

local function setPartCondition(device, subSystem, odometer, integrity, visual)
  device.wearLockTorqueCoef = linearScale(odometer, 30000000, 500000000, 1, 0.7)
  local integrityState = integrity
  if type(integrity) == "number" then
    local integrityValue = integrity
    integrityState = {
      damageLockTorqueCoef = linearScale(integrityValue, 1, 0, 1, 0.5)
    }
  end

  device.damageLockTorqueCoef = integrityState.damageLockTorqueCoef or 1
end

local function getPartCondition(device)
  local integrityState = {
    damageLockTorqueCoef = device.damageLockTorqueCoef
  }
  local integrityValueLockTorque = linearScale(device.damageLockTorqueCoef, 1, 0.5, 1, 0)
  local integrityValue = min(integrityValueLockTorque)

  return integrityValue, integrityState
end

local function validate(device)
  if not device.parent.deviceCategories.engine then
    log("E", "dctGearbox.validate", "Parent device is not an engine device...")
    log("E", "dctGearbox.validate", "Actual parent:")
    log("E", "dctGearbox.validate", powertrain.dumpsDeviceData(device.parent))
    return false
  end

  device.lockTorque = device.lockTorque or (device.parent.torqueData.maxTorque * 1.25 + device.parent.maxRPM * device.parent.inertia * math.pi / 30)

  local maxEngineTorque
  local maxEngineAV

  if device.parent and device.parent.deviceCategories.engine then
    local engine = device.parent
    local torqueData = engine:getTorqueData()
    maxEngineTorque = torqueData.maxTorque
    maxEngineAV = engine.maxAV
  else
    maxEngineTorque = 100
    maxEngineAV = 6000 * rpmToAV
  end

  device.maxExpectedInputTorque = maxEngineTorque
  device.invMaxExpectedInputTorque = 1 / maxEngineTorque
  device.invMaxExpectedOutputTorque = 0
  device.maxExpectedPower = maxEngineAV * device.maxExpectedInputTorque
  device.invMaxExpectedPower = 1 / device.maxExpectedPower
  device.maxExpectedOutputAV = maxEngineAV / device.minGearRatio
  device.invMaxExpectedOutputAV = 1 / device.maxExpectedOutputAV
  device.invMaxExpectedInputAV = 1 / maxEngineAV
  return true
end

local function setMode(device, mode)
  device.mode = mode
  selectUpdates(device)
end

local function setGearIndex1(device, index)
  --insert0
  if electrics.values.reevmode ~= "on" then
    device.gearIndex1 = min(max(index, device.minGearIndex), device.maxGearIndex)
  else
    local minG = 0
    local maxG = 0
    if device.minGearIndex ~= 0 then
      minG = device.minGearIndex / abs(device.minGearIndex)
    end
    if device.maxGearIndex ~= 0 then
      maxG = device.maxGearIndex / abs(device.maxGearIndex)
    end
    device.gearIndex1 = min(max(index, minG), maxG)
  end
  --insert1
  device.gearRatio1 = device.gearRatios[device.gearIndex1]

  powertrain.calculateTreeInertia()

  selectUpdates(device)
end

local function setGearIndex2(device, index)
  --insert0
  if electrics.values.reevmode ~= "on" then
    device.gearIndex2 = min(max(index, device.minGearIndex), device.maxGearIndex)
  else
    local minG = 0
    local maxG = 0
    if device.minGearIndex ~= 0 then
      minG = device.minGearIndex / abs(device.minGearIndex)
    end
    if device.maxGearIndex ~= 0 then
      maxG = device.maxGearIndex / abs(device.maxGearIndex)
    end
    device.gearIndex2 = min(max(index, minG), maxG)
  end
  --insert1
  device.gearIndex2 = min(max(index, device.minGearIndex), device.maxGearIndex)
  device.gearRatio2 = device.gearRatios[device.gearIndex2]

  powertrain.calculateTreeInertia()

  selectUpdates(device)
end

local function setLock(device, enabled)
  device.lockCoef = enabled and 0 or 1
end

local function calculateInertia(device)
  local outputInertia = 0
  local cumulativeGearRatio = 1
  local maxCumulativeGearRatio = 1
  if device.children and #device.children > 0 then
    local child = device.children[1]
    outputInertia = child.cumulativeInertia
    cumulativeGearRatio = child.cumulativeGearRatio
    maxCumulativeGearRatio = child.maxCumulativeGearRatio
  end

  local gearRatio1 = device.gearRatio1
  local gearRatio2 = device.gearRatio2
  local divisionSafeGearRatio1 = gearRatio1 ~= 0 and abs(gearRatio1) or (device.maxGearRatio * 2)
  local divisionSafeGearRatio2 = gearRatio2 ~= 0 and abs(gearRatio2) or (device.maxGearRatio * 2)

  device.cumulativeInertia1 = min(outputInertia / divisionSafeGearRatio1 / divisionSafeGearRatio1, device.parent.inertia * 0.5)
  device.cumulativeInertia2 = min(outputInertia / divisionSafeGearRatio2 / divisionSafeGearRatio2, device.parent.inertia * 0.5)

  device.lockSpring1 = device.lockSpringBase or (powertrain.stabilityCoef * powertrain.stabilityCoef * device.cumulativeInertia1) --Nm/rad
  device.lockSpring2 = device.lockSpringBase or (powertrain.stabilityCoef * powertrain.stabilityCoef * device.cumulativeInertia2) --Nm/rad

  device.lockDamp1 = device.lockDampRatio1 * sqrt(device.lockSpring1 * device.cumulativeInertia1)
  device.lockDamp2 = device.lockDampRatio2 * sqrt(device.lockSpring2 * device.cumulativeInertia2)

  device.maxClutchAngle1 = device.lockTorque / device.lockSpring1 --rad
  device.maxClutchAngle2 = device.lockTorque / device.lockSpring2 --rad

  device.parkLockSpring = device.parkLockSpringBase or (powertrain.stabilityCoef * powertrain.stabilityCoef * outputInertia * 0.5) --Nm/rad
  device.parkLockDamp = device.parkLockDampRatio * sqrt(device.parkLockSpring * outputInertia)
  device.maxParkClutchAngle = device.parkLockTorque / device.parkLockSpring

  device.cumulativeGearRatio = cumulativeGearRatio * (device.clutchRatio1 > device.clutchRatio2 and gearRatio1 or gearRatio2)
  device.maxCumulativeGearRatio = maxCumulativeGearRatio * device.maxGearRatio
end

local function resetSounds(device, jbeamData)
  device.gearWhineInputTorqueSmoother:reset()
  device.gearWhineOutputTorqueSmoother:reset()
  device.gearWhineInputAVSmoother:reset()
  device.gearWhineOutputAVSmoother:reset()

  device.gearWhineInputAV = 0
  device.gearWhineOutputAV = 0
  device.gearWhineInputTorque = 0
  device.gearWhineOutputTorque = 0

  -- insert0
  if not sounds.usesOldCustomSounds then
    if jbeamData.soundConfig then
      local soundConfig = v.data[jbeamData.soundConfig]
      if soundConfig then
        device.soundRPMSmoother:reset()
        device.soundLoadSmoother:reset()
        device.engineVolumeCoef = 1
        --dump(sounds)
        sounds.disableOldEngineSounds()
      else
        log("E", "electricMotor.resetSounds", "Can't find sound config: " .. jbeamData.soundConfig)
      end
    end
  else
    log("W", "electricMotor.resetSounds", "Disabling new sounds, found old custom engine sounds...")
  end
  -- insert1

end

local function initEngineSound(device, soundID, samplePath, engineNodeIDs, offLoadGain, onLoadGain, reference)
  device.soundConfiguration[reference] = device.soundConfiguration[reference] or {}
  device.soundConfiguration[reference].blendFile = samplePath
  obj:queueGameEngineLua(string.format("core_sounds.initEngineSound(%d,%d,%q,%s,%f,%f)", objectId, soundID, samplePath, serialize(engineNodeIDs), offLoadGain, onLoadGain))

  bdebug.setNodeDebugText("Powertrain", engineNodeIDs[1], device.name .. ": " .. samplePath)
end

local function setEngineSoundParameterList(device, soundID, params, reference)
  device.soundConfiguration[reference] = device.soundConfiguration[reference] or {}
  device.soundConfiguration[reference].params = tableMergeRecursive(device.soundConfiguration[reference].params or {}, params)
  device.soundConfiguration[reference].soundID = soundID
  obj:queueGameEngineLua(string.format("core_sounds.setEngineSoundParameterList(%d,%d,%s)", objectId, soundID, serialize(params)))
end

local function initSounds(device, jbeamData)
  local gearWhineOutputSample = jbeamData.gearWhineOutputEvent or "event:>Vehicle>Transmission>helical_01>twine_out"
  device.gearWhineOutputLoop = sounds.createSoundObj(gearWhineOutputSample, "AudioDefaultLoop3D", "GearWhineOut", device.transmissionNodeID or sounds.engineNode)

  local gearWhineInputSample = jbeamData.gearWhineInputEvent or "event:>Vehicle>Transmission>helical_01>twine_in"
  device.gearWhineInputLoop = sounds.createSoundObj(gearWhineInputSample, "AudioDefaultLoop3D", "GearWhineIn", device.transmissionNodeID or sounds.engineNode)

  bdebug.setNodeDebugText("Powertrain", device.transmissionNodeID or sounds.engineNode, device.name .. ": " .. gearWhineOutputSample)
  bdebug.setNodeDebugText("Powertrain", device.transmissionNodeID or sounds.engineNode, device.name .. ": " .. gearWhineInputSample)

  device.forwardInputPitchCoef = jbeamData.forwardInputPitchCoef or 1
  device.forwardOutputPitchCoef = jbeamData.forwardOutputPitchCoef or 1
  device.reverseInputPitchCoef = jbeamData.reverseInputPitchCoef or 0.7
  device.reverseOutputPitchCoef = jbeamData.reverseOutputPitchCoef or 0.7

  local inputAVSmoothing = jbeamData.gearWhineInputPitchCoefSmoothing or 50
  local outputAVSmoothing = jbeamData.gearWhineOutputPitchCoefSmoothing or 50
  local inputTorqueSmoothing = jbeamData.gearWhineInputVolumeCoefSmoothing or 10
  local outputTorqueSmoothing = jbeamData.gearWhineOutputVolumeCoefSmoothing or 10

  device.gearWhineInputTorqueSmoother = newExponentialSmoothing(inputTorqueSmoothing)
  device.gearWhineOutputTorqueSmoother = newExponentialSmoothing(outputTorqueSmoothing)
  device.gearWhineInputAVSmoother = newExponentialSmoothing(inputAVSmoothing)
  device.gearWhineOutputAVSmoother = newExponentialSmoothing(outputAVSmoothing)

  device.gearWhineInputAV = 0
  device.gearWhineOutputAV = 0
  device.gearWhineInputTorque = 0
  device.gearWhineOutputTorque = 0

  device.gearWhineOutputLoop:setParameter("c_gearboxMaxPower", device.maxExpectedPower * 0.001)
  device.gearWhineInputLoop:setParameter("c_gearboxMaxPower", device.maxExpectedPower * 0.001)

  -- insert0
  if not sounds.usesOldCustomSounds then
    if jbeamData.soundConfig then
      local soundConfig = v.data[jbeamData.soundConfig]
      if soundConfig and not sounds.usesOldCustomSounds then
        device.soundConfiguration = {}
        device.engineSoundID = powertrain.getEngineSoundID()
        local rpmInRate = soundConfig.rpmSmootherInRate or 15
        local rpmOutRate = soundConfig.rpmSmootherOutRate or 25
        device.soundRPMSmoother = newTemporalSmoothingNonLinear(rpmInRate, rpmOutRate)
        local loadInRate = soundConfig.loadSmootherInRate or 20
        local loadOutRate = soundConfig.loadSmootherOutRate or 20
        device.soundLoadSmoother = newTemporalSmoothingNonLinear(loadInRate, loadOutRate)
        device.soundMaxLoadMix = soundConfig.maxLoadMix or 1
        device.soundMinLoadMix = soundConfig.minLoadMix or 0
        local fundamentalFrequencyCylinderCount = soundConfig.fundamentalFrequencyCylinderCount or 6
        device.fundamentalFrequencyRPMCoef = fundamentalFrequencyCylinderCount / 120
        device.engineVolumeCoef = 1
        local onLoadGain = soundConfig.onLoadGain or 1
        local offLoadGain = soundConfig.offLoadGain or 1

        local sampleName = soundConfig.sampleName
        if sampleName then
          local sampleFolder = soundConfig.sampleFolder or "art/sound/blends/"
          local samplePath = sampleFolder .. sampleName .. ".sfxBlend2D.json"
          device:initEngineSound(device.engineSoundID, samplePath, {device.engineNodeID}, offLoadGain, onLoadGain, "motor")

          local main_gain = soundConfig.mainGain or 0

          local eq_a_freq = sounds.hzToFMODHz(soundConfig.lowCutFreq or 20)
          local eq_b_freq = sounds.hzToFMODHz(soundConfig.highCutFreq or 10000)
          local eq_c_freq = sounds.hzToFMODHz(soundConfig.eqLowFreq or 500)
          local eq_c_gain = soundConfig.eqLowGain or 0
          local eq_c_reso = soundConfig.eqLowWidth or 0
          local eq_d_freq = sounds.hzToFMODHz(soundConfig.eqHighFreq or 2000)
          local eq_d_gain = soundConfig.eqHighGain or 0
          local eq_d_reso = soundConfig.eqHighWidth or 0
          local eq_e_gain = soundConfig.eqFundamentalGain or 0
          local eq_e_reso = soundConfig.eqFundamentalWidth or 1

          local params = {
            main_gain = main_gain,
            eq_a_freq = eq_a_freq,
            eq_b_freq = eq_b_freq,
            eq_c_freq = eq_c_freq,
            eq_c_gain = eq_c_gain,
            eq_c_reso = eq_c_reso,
            eq_d_freq = eq_d_freq,
            eq_d_gain = eq_d_gain,
            eq_d_reso = eq_d_reso,
            eq_e_gain = eq_e_gain,
            eq_e_reso = eq_e_reso,
            onLoadGain = onLoadGain,
            offLoadGain = offLoadGain,
            muffled = 0.5
          }
          --dump(params)

          device:setEngineSoundParameterList(device.engineSoundID, params, "motor")

          device.updateSounds = updateSounds
        end
        --dump(sounds)
        sounds.disableOldEngineSounds()
      else
        log("E", "electricMotor.init", "Can't find sound config: " .. jbeamData.soundConfig)
      end
    end
  else
    log("W", "electricMotor.init", "Disabling new sounds, found old custom engine sounds...")
  end
  -- insert1

end

local function reset(device, jbeamData)

  --insert0

  device.torqueDiff = 0

  device.maxTorqueLimit = math.huge

  device.friction = jbeamData.friction or 0

  device.outputAV1 = 0
  device.inputAV = 0
  device.outputTorque1 = 0
  device.virtualMassAV = 0
  device.isBroken = false
  device.frictionTorque = 0

  device.electricsThrottleName = jbeamData.electricsThrottleName or "throttle"
  device.electricsThrottleFactorName = jbeamData.electricsThrottleFactorName or "throttleFactor"
  device.throttleFactor = 1

  device.throttle = 0
  device.requestedThrottle = 0
  device.ignitionCoef = 1
  device.dynamicFriction = jbeamData.dynamicFriction or 0

  device.inertia = jbeamData.inertia or 0.1

  device.floodLevel = 0
  device.prevFloodPercent = 0

  device.outputTorqueState = 1
  device.outputAVState = 1
  device.isDisabled = false

  device.loadSmoother:reset()
  device.throttleSmoother:reset()
  device.engineLoad = 0
  device.instantEngineLoad = 0

  device.frictionLossPerUpdate = 0
  device.spentEnergy = 0
  device.storageWithEnergyCounter = 0
  device.registeredEnergyStorages = {}
  device.previousEnergyLevels = {}
  device.previousEnergyRatios = {}
  device.energyStorageRatios = {}
  device.hasEnergy = true

  device:resetTempRevLimiter()

  device.torqueData = getTorqueData(device)
  device.maxPower = device.torqueData.maxPower
  device.maxTorque = device.torqueData.maxTorque
  device.maxPowerThrottleMap = device.torqueData.maxPower * psToWatt

  device.motorRatio = 1

  --insert1

  device.gearRatio = 0
  device.friction = jbeamData.friction or 0
  device.cumulativeGearRatio = 1
  device.maxCumulativeGearRatio = 1

  device.outputAV1 = 0
  device.inputAV = 0
  device.outputTorque1 = 0
  device.isBroken = false

  device.lockCoef = 1

  device.gearRatio1 = 0
  device.gearRatio2 = 0

  device.clutchAngle1 = 0
  device.clutchAngle2 = 0
  device.clutchRatio1 = 1
  device.clutchRatio2 = 1
  device.clutchRatio = 1 --just used as a "max" of the two actual clutches for display purposes
  device.torqueDiff1 = 0
  device.torqueDiff2 = 0
  device.torqueDiff = 0

  device.parkClutchAngle = 0

  device.damageLockTorqueCoef = 1
  device.wearLockTorqueCoef = 1

  device:setGearIndex1(1)
  device:setGearIndex2(2)

  selectUpdates(device)
end

local function new(jbeamData)
  local device = {
    --insert0

    updateGFX = updateGFX,

    --torqueDiff = 0,

    setmotorRatio = setmotorRatio,
    setmotorType = setmotorType,
    maxTorqueLimit = math.huge,

    isPropulsed = true,
    --virtualMassAV = 0,
    electricsThrottleName = jbeamData.electricsThrottleName or "throttle",
    electricsRegenThrottleName = jbeamData.electricsRegenThrottleName or "regenThrottle",
    electricsThrottleFactorName = jbeamData.electricsThrottleFactorName or "throttleFactor",
    throttleFactor = 1,
    minWantedRegenTorque = jbeamData.minimumWantedRegenTorque or 20,
    maxWantedRegenTorque = jbeamData.maximumWantedRegenTorque or 200,
    throttle = 0,
    inertia = jbeamData.inertia or 0.1,
    idleAV = 0, --we keep these for compat with logic that expects an ICE
    idleRPM = 0,
    outputTorqueState = 1,
    outputAVState = 1,
    isDisabled = false,
    ignitionCoef = 1,
    isStalled = false,
    instantEngineLoad = 0,
    engineLoad = 0,
    loadSmoother = newTemporalSmoothing(1, 1),
    throttleSmoother = newTemporalSmoothing(30, 10),
    grossWorkPerUpdate = 0,
    frictionLossPerUpdate = 0,
    spentEnergy = 0,
    storageWithEnergyCounter = 0,
    storageCounter = 0,
    registeredEnergyStorages = {},
    previousEnergyLevels = {},
    previousEnergyRatios = {},
    hasEnergy = true,
    --onBreak = onBreak,
    scaleFriction = scaleFriction,
    scaleOutputTorque = scaleOutputTorque,
    activateStarter = nop,
    deactivateStarter = nop,
    setIgnition = nop,
    cutIgnition = nop,
    setTempRevLimiter = setTempRevLimiter,
    resetTempRevLimiter = resetTempRevLimiter,
    sendTorqueData = sendTorqueData,
    getTorqueData = getTorqueData,
    lockUp = lockUp,
    disable = disable,
    enable = enable,
    updateEnergyUsage = updateEnergyUsage,
    updateEnergyStorageRatios = updateEnergyStorageRatios,
    registerStorage = registerStorage,
    initEngineSound = initEngineSound,
    setEngineSoundParameterList = setEngineSoundParameterList,
    getSoundConfiguration = getSoundConfiguration,

    --insert1
    deviceCategories = shallowcopy(M.deviceCategories),
    requiredExternalInertiaOutputs = shallowcopy(M.requiredExternalInertiaOutputs),
    outputPorts = shallowcopy(M.outputPorts),
    name = jbeamData.name,
    type = jbeamData.type,
    inputName = jbeamData.inputName,
    inputIndex = jbeamData.inputIndex,
    gearRatio = 0,
    friction = jbeamData.friction or 0,
    dynamicFriction = jbeamData.dynamicFriction or 0,
    torqueLossCoef = jbeamData.torqueLossCoef or 0,
    cumulativeGearRatio = 1,
    maxCumulativeGearRatio = 1,
    isPhysicallyDisconnected = true,
    outputAV1 = 0,
    inputAV = 0,
    outputTorque1 = 0,
    isBroken = false,
    lockCoef = 1,
    electricsClutchRatio1Name = jbeamData.electricsClutchRatio1Name or "clutchRatio1",
    electricsClutchRatio2Name = jbeamData.electricsClutchRatio2Name or "clutchRatio2",
    gearRatios = {},
    gearRatio1 = 0,
    gearRatio2 = 0,
    clutchAngle1 = 0,
    clutchAngle2 = 0,
    clutchRatio1 = 1,
    clutchRatio2 = 1,
    clutchRatio = 1, --just used as a "max" of the two actual clutches for display purposes
    torqueDiff1 = 0,
    torqueDiff2 = 0,
    torqueDiff = 0,
    damageLockTorqueCoef = 1,
    wearLockTorqueCoef = 1,
    additionalEngineInertia = jbeamData.additionalEngineInertia or 0,
    reset = reset,
    initSounds = initSounds,
    resetSounds = resetSounds,
    updateSounds = updateSounds,
    setMode = setMode,
    validate = validate,
    setLock = setLock,
    calculateInertia = calculateInertia,
    setGearIndex1 = setGearIndex1,
    setGearIndex2 = setGearIndex2,
    applyDeformGroupDamage = applyDeformGroupDamage,
    setPartCondition = setPartCondition,
    getPartCondition = getPartCondition
  }

  device.torqueLossCoef = clamp(device.torqueLossCoef, 0, 1)

  device.clutchStiffness = jbeamData.clutchStiffness or 1
  device.lockDampRatio1 = jbeamData.lockDampRatio1 or 0.15 --1 is critically damped
  device.lockDampRatio2 = jbeamData.lockDampRatio2 or 0.15 --1 is critically damped
  device.lockTorque = jbeamData.lockTorque
  device.lockSpringBase = jbeamData.lockSpring

  --gearbox park locking clutch
  device.parkClutchAngle = 0
  device.parkLockTorque = jbeamData.parkLockTorque or 1000 --Nm
  device.parkLockDampRatio = jbeamData.parkLockDampRatio or 0.4 --1 is critically damped
  device.parkLockSpringBase = jbeamData.parkLockSpring

  local forwardGears = {}
  local reverseGears = {}
  for _, v in pairs(jbeamData.gearRatios) do
    table.insert(v >= 0 and forwardGears or reverseGears, v)
  end

  device.maxGearIndex = 0
  device.minGearIndex = 0
  device.maxGearRatio = 0
  device.minGearRatio = 999999
  for i = 0, tableSize(forwardGears) - 1, 1 do
    device.gearRatios[i] = forwardGears[i + 1]
    device.maxGearIndex = max(device.maxGearIndex, i)
    device.maxGearRatio = max(device.maxGearRatio, abs(device.gearRatios[i]))
    if device.gearRatios[i] ~= 0 then
      device.minGearRatio = min(device.minGearRatio, abs(device.gearRatios[i]))
    end
  end
  local reverseGearCount = tableSize(reverseGears)
  for i = -reverseGearCount, -1, 1 do
    local index = -reverseGearCount - i - 1
    device.gearRatios[i] = reverseGears[abs(index)]
    device.minGearIndex = min(device.minGearIndex, index)
    device.maxGearRatio = max(device.maxGearRatio, abs(device.gearRatios[i]))
    if device.gearRatios[i] ~= 0 then
      device.minGearRatio = min(device.minGearRatio, abs(device.gearRatios[i]))
    end
  end
  device.gearCount = abs(device.maxGearIndex) + abs(device.minGearIndex)

  device.gearWhineCoefsOutput = {}
  local gearWhineCoefsOutput = jbeamData.gearWhineCoefsOutput or jbeamData.gearWhineCoefs
  if gearWhineCoefsOutput and type(gearWhineCoefsOutput) == "table" then
    local gearIndex = device.minGearIndex
    for _, v in pairs(gearWhineCoefsOutput) do
      device.gearWhineCoefsOutput[gearIndex] = v
      gearIndex = gearIndex + 1
    end
  else
    for i = device.minGearIndex, device.maxGearIndex, 1 do
      device.gearWhineCoefsOutput[i] = 0
    end
  end

  device.gearWhineCoefsInput = {}
  local gearWhineCoefsInput = jbeamData.gearWhineCoefsInput or jbeamData.gearWhineCoefs
  if gearWhineCoefsInput and type(gearWhineCoefsInput) == "table" then
    local gearIndex = device.minGearIndex
    for _, v in pairs(gearWhineCoefsInput) do
      device.gearWhineCoefsInput[gearIndex] = v
      gearIndex = gearIndex + 1
    end
  else
    for i = device.minGearIndex, device.maxGearIndex, 1 do
      device.gearWhineCoefsInput[i] = i < 0 and 0.3 or 0
    end
  end

  if jbeamData.gearboxNode_nodes and type(jbeamData.gearboxNode_nodes) == "table" then
    device.transmissionNodeID = jbeamData.gearboxNode_nodes[1]
  end

  if type(device.transmissionNodeID) ~= "number" then
    device.transmissionNodeID = nil
  end

  device:setGearIndex1(1)
  device:setGearIndex2(2)

  device.breakTriggerBeam = jbeamData.breakTriggerBeam
  if device.breakTriggerBeam and device.breakTriggerBeam == "" then
    --get rid of the break beam if it's just an empty string (cancellation)
    device.breakTriggerBeam = nil
  end

  device.motorType = jbeamData.motorType or "powerGenerator"

  device.motorRatio = 1

  device.motorDirection = 0

  device.torqueReactionNodes = jbeamData["torqueReactionNodes_nodes"]

  device.maxRPM = 0

  if not jbeamData.torque then
    log("E", "electricMotor.init", "Can't find torque table... Powertrain is going to break!")
  end
  local torqueTable = tableFromHeaderTable(jbeamData.torque)
  local points = {}
  for _, v in pairs(torqueTable) do
    table.insert(points, { v.rpm, v.torque })
    device.maxRPM = max(device.maxRPM, v.rpm)
  end
  device.torqueCurve = createCurve(points)
  device.maxAV = device.maxRPM * rpmToAV

  device.torqueData = getTorqueData(device)
  device.maxPower = device.torqueData.maxPower
  device.maxTorque = device.torqueData.maxTorque
  device.maxPowerThrottleMap = device.torqueData.maxPower * psToWatt

  if jbeamData.regenTorqueCurve then
    local regenTorqueTable = tableFromHeaderTable(jbeamData.regenTorqueCurve)
    points = {}
    for _, v in pairs(regenTorqueTable) do
      table.insert(points, { v.rpm, v.torque})
    end
    device.regenCurve = createCurve(points)
  else
    local regenFadeRPM = jbeamData.regenFadeRPM or 1000
    local maxRegenPower = jbeamData.maxRegenPower or device.maxPower
    local regenTorqueLimit = jbeamData.maxRegenTorque or device.maxTorque

    device.regenCurve = {[0] = 0}

    for i = 1, device.maxRPM do
      local fadeCoef = min(1, i / regenFadeRPM)
      local maxRegenTorque = min(regenTorqueLimit, maxRegenPower * 1000 / (i * rpmToAV))
      local maxOverallTorque = device.torqueCurve[i]
      local scaledMaxTorque = fadeCoef * min(maxRegenTorque, maxOverallTorque)

      table.insert(device.regenCurve, scaledMaxTorque)
    end
  end

  local maxRegenTorque = 0
  local minPeakRegenRPM = 0
  local lastTorque = 0

  for i = 0, device.maxRPM do
    local regenTorque = device.regenCurve[i]
    if regenTorque > 0 and regenTorque <= lastTorque and minPeakRegenRPM == 0 then
      minPeakRegenRPM = i -- once torque stops increasing along the curve the first time, we record that as the "lowest peak RPM"
    end
    maxRegenTorque = max(maxRegenTorque, regenTorque)
    lastTorque = regenTorque
  end

  device.maxRegenTorque = maxRegenTorque
  device.minPeakRegenRPM = minPeakRegenRPM
  device.instantMaxRegenTorque = 0
  device.minWantedRegenTorque = jbeamData.minimumWantedRegenTorque or 0
  device.maxWantedRegenTorque = jbeamData.maximumWantedRegenTorque or maxRegenTorque

  device.invEngInertia = 1 / device.inertia
  device.halfInvEngInertia = device.invEngInertia * 0.5

  local tempElectricalEfficiencyTable = nil
  if not jbeamData.electricalEfficiency or type(jbeamData.electricalEfficiency) == "number" then
    tempElectricalEfficiencyTable = { { 0, jbeamData.electricalEfficiency or 1 }, { 1, jbeamData.electricalEfficiency or 1 } }
  elseif type(jbeamData.electricalEfficiency) == "table" then
    tempElectricalEfficiencyTable = deepcopy(jbeamData.electricalEfficiency)
  end

  local copy = deepcopy(tempElectricalEfficiencyTable)
  tempElectricalEfficiencyTable = {}
  for k, v in pairs(copy) do
    if type(k) == "number" then
      table.insert(tempElectricalEfficiencyTable, { v[1] * 100, v[2] })
    end
  end

  tempElectricalEfficiencyTable = createCurve(tempElectricalEfficiencyTable)
  device.electricalEfficiencyTable = {}
  for k, v in pairs(tempElectricalEfficiencyTable) do
    device.electricalEfficiencyTable[k * 0.01] = v
  end

  device.torqueForBatteryCoef = 0

  device.requiredEnergyType = "electricEnergy"
  device.energyStorage = jbeamData.energyStorage or "mainBattery"

  if device.torqueReactionNodes and #device.torqueReactionNodes == 3 then
    local pos1 = vec3(v.data.nodes[device.torqueReactionNodes[1]].pos)
    local pos2 = vec3(v.data.nodes[device.torqueReactionNodes[2]].pos)
    local pos3 = vec3(v.data.nodes[device.torqueReactionNodes[3]].pos)
    local avgPos = (((pos1 + pos2) / 2) + pos3) / 2
    device.visualPosition = { x = avgPos.x, y = avgPos.y, z = avgPos.z }
  end

  device.engineNodeID = device.torqueReactionNodes and (device.torqueReactionNodes[1] or v.data.refNodes[0].ref) or v.data.refNodes[0].ref
  if device.engineNodeID < 0 then
    log("W", "combustionEngine.init", "Can't find suitable engine node, using ref node instead!")
    device.engineNodeID = v.data.refNodes[0].ref
  end

  device:resetTempRevLimiter()

  --insert1

  selectUpdates(device)

  return device
end

M.new = new

return M
