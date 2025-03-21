-- emtGearbox.lua - 2024.3.18 13:31 - MT Gearbox with electric motor
-- by NZZ
-- version 0.2.8 beta
-- final edit - 2025.3.21 18:54

local M = {}

M.outputPorts = {[1] = true}
M.deviceCategories = {gearbox = true}
M.requiredExternalInertiaOutputs = {1}

local max = math.max
local min = math.min
local abs = math.abs
local clamp = clamp

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
  local rpm = engineAV * avToRPM * motorDirection * device.motorRatio --/ device.gearRatios[device.gearIndex]
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
  device.motorTorque = (actualTorque - frictionTorque) * timeSign * device.motorRatio
  return (actualTorque - frictionTorque) * timeSign * device.motorRatio --/ device.gearRatios[device.gearIndex]
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

local function engineCoup()
  if electrics.values.hybridMode then
    if (electrics.values.hybridMode == "hybrid" or electrics.values.hybridMode == "fuel") and electrics.values.electricReverse == 0 then
      return 1
    elseif (electrics.values.hybridMode == "electric" or electrics.values.autoModeStage == 1) and electrics.values.powerGeneratorMode == "on" then
      return 1
    elseif electrics.values.autoModeStage == 2 or electrics.values.autoModeStage == 3 then
      return 1
    else
      return 0
    end
  else
    return 1
  end
end

local function updateVelocity(device, dt)
  device.inputAV = device.outputAV1 * device.gearRatio * device.lockCoef
  device.parent[device.parentOutputAVName] = device.inputAV * engineCoup()
end

local function updateTorque(device, dt)
  local inputTorque = device.parent[device.parentOutputTorqueName] + motorTorque(device, dt)
  device.inputTorque = inputTorque
  local inputAV = device.inputAV
  local friction = (device.friction * clamp(inputAV, -1, 1) + device.dynamicFriction * inputAV + device.torqueLossCoef * inputTorque) * device.wearFrictionCoef * device.damageFrictionCoef
  local outputTorque = (inputTorque - friction) * device.gearRatio * device.lockCoef
  device.outputTorque1 = outputTorque

  device.gearWhineInputTorque = device.gearWhineInputTorqueSmoother:get(inputTorque)
  device.gearWhineOutputTorque = device.gearWhineOutputTorqueSmoother:get(outputTorque)
  device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(inputAV)
  device.gearWhineOutputAV = device.gearWhineOutputAVSmoother:get(device.outputAV1)
end

local function neutralUpdateVelocity(device, dt)
  device.inputAV = device.virtualMassAV
  device.parent[device.parentOutputAVName] = device.inputAV
end

local function neutralUpdateTorque(device, dt)
  device:updateGrinding(dt)

  local inputAV = device.inputAV
  local friction = (device.neutralFriction * clamp(inputAV, -1, 1) + device.neutralDynamicFriction * inputAV) * device.wearFrictionCoef * device.damageFrictionCoef
  device.inputTorque = device.parent[device.parentOutputTorqueName]
  local outputTorque = device.inputTorque + motorTorque(device, dt) - friction + device.grindingTorque * device.grindingTorqueSign
  device.virtualMassAV = device.virtualMassAV + outputTorque * device.invCumulativeInertia * dt
  device.outputTorque1 = -device.grindingTorque * device.grindingTorqueReactionSign

  device.gearWhineInputTorque = device.gearWhineInputTorqueSmoother:get(device.parent[device.parentOutputTorqueName])
  device.gearWhineOutputTorque = device.gearWhineOutputTorqueSmoother:get(0)
  device.gearWhineInputAV = device.gearWhineInputAVSmoother:get(inputAV)
  device.gearWhineOutputAV = device.gearWhineOutputAVSmoother:get(device.outputAV1)
end

local function selectUpdates(device)
  device.velocityUpdate = updateVelocity
  device.torqueUpdate = updateTorque

  if device.isBroken or device.gearRatio == 0 then
    device.velocityUpdate = neutralUpdateVelocity
    device.torqueUpdate = neutralUpdateTorque
    --make sure the virtual mass has the right AV
    device.virtualMassAV = device.inputAV
  end
end

local function updateGrinding(device, dt)
  if device.isGrindingShift then
    local gearIndex = device.grindingShiftTargetIndex
    local avDifference = (device.outputAV1 * device.gearRatios[gearIndex]) - device.inputAV
    device.grindingTorque = linearScale(avDifference, 1, 1000, device.maxGrindingTorque, device.maxGrindingTorque * 0.1)
    device.grindingTorqueSign = sign(avDifference)
    device.grindingTorqueReactionSign = sign(avDifference) * sign(device.gearRatios[gearIndex])
    local synchroWear = abs(avDifference * device.grindingTorque * device.synchroWearCoef[gearIndex] * dt)
    device.synchroWear[gearIndex] = clamp(device.synchroWear[gearIndex] + synchroWear, 0, 1)

    --when we reach 100% synchro wear, disable this specific gear by setting its gear ratio to 0
    if device.synchroWear[gearIndex] >= 1 then
      device.gearRatios[gearIndex] = 0
      --set the av diff to 0 as well, so that in the next step it goes "into" gear rather than keep grinding (there's nothing left to grind)
      avDifference = 0
    end

    --if we reached a small enough AV difference, go into gear
    if abs(avDifference) < 20 then
      device.gearIndex = gearIndex
      device.gearRatio = device.gearRatios[device.gearIndex]
      device:setGearGrinding(false)
      local maxExpectedOutputTorque = device.maxExpectedInputTorque * device.gearRatio
      device.invMaxExpectedOutputTorque = 1 / maxExpectedOutputTorque

      if device.gearRatio ~= 0 then
        powertrain.calculateTreeInertia()
      end

      selectUpdates(device)
    end
    device.gearGrindLoop:setVolumePitch(1, abs(avDifference) * avToRPM, 1, 1)

    local wornGearIndex = gearIndex
    --we always want to display the UI message the first time damage happens
    local isFirstDamage = device.synchroWear[wornGearIndex] > 0 and device.previouslyReportedSynchroWear[wornGearIndex] <= 0
    --we also want to display it for every further %
    local isSignificantlyMoreDamage = (device.synchroWear[wornGearIndex] - device.previouslyReportedSynchroWear[wornGearIndex]) >= 0.01
    local hasReachedMaximumDamage = device.synchroWear[wornGearIndex] >= 1 and (device.synchroWear[wornGearIndex] - device.previouslyReportedSynchroWear[wornGearIndex]) > 0
    local doDisplayDamageMessage = isFirstDamage or isSignificantlyMoreDamage or hasReachedMaximumDamage
    if doDisplayDamageMessage then
      guihooks.message({txt = string.format("Synchronizer damage (Gear %g): %d%%", wornGearIndex, clamp(device.synchroWear[wornGearIndex] * 100, 1, 100)), context = {}}, 5, "vehicle.damage.synchros")
      device.previouslyReportedSynchroWear[wornGearIndex] = device.synchroWear[wornGearIndex]
    end

    if device.synchroWear[gearIndex] > 0 and not damageTracker.getDamage("gearbox", "synchroWear") then
      damageTracker.setDamageTemporary("gearbox", "synchroWear", true, false, 2)
    end
  end
end

local function setGearGrinding(device, active, targetGearIndex, maxGrindingTorque)
  if active then
    --expose the current grinding to the outside world
    device.isGrindingShift = active
    --save our target gear index for when grinding finished
    device.grindingShiftTargetIndex = targetGearIndex
    --activate the synchro/grinding torque
    device.grindingTorque = 0
    device.maxGrindingTorque = maxGrindingTorque
    if device.gearGrindLoop then
      --start the grinding sound, but keep it silent for now (params are then set from the update logic of the grinding)
      device.gearGrindLoop:setVolumePitch(0, 0, 0, 0)
      obj:playSFX(device.gearGrindLoop.obj)
    end
  else
    device.isGrindingShift = false
    device.grindingShiftTargetIndex = nil
    device.grindingTorque = 0
    device.maxGrindingTorque = 0
    device.grindingTorqueSign = 0
    device.grindingTorqueReactionSign = 0
    if device.gearGrindLoop then
      device.gearGrindLoop:setVolumePitch(0, 0, 0, 0)
      obj:stopSFX(device.gearGrindLoop.obj)
    end
  end
end

local function updateGFX(device, dt)
  --local gearIndex = device.grindingShiftTargetIndex or device.gearIndex
  --local avDifference = (device.outputAV1 * device.gearRatios[gearIndex]) - device.inputAV
  --guihooks.graph({"RPM difference", avDifference * avToRPM, 7000, "", false}, {"Input RPM", device.inputAV * avToRPM, 7000, "", false}, {"Output RPM", device.outputAV1 * device.gearRatios[gearIndex] * avToRPM, 7000, "", false})
  -- local gearPopoutMinDamage = 0.75
  -- if device.synchroWear[device.gearIndex] >= gearPopoutMinDamage then
  --   device.gearPopOutTimer = device.gearPopOutTimer - dt
  --   if device.gearPopOutTimer <= 0 then
  --     local gearPopOutChance = linearScale(device.synchroWear[device.gearIndex], 0.75, 1, 0.99, 0.95) --1% chance at 75% damage, 5% chance at 100% damage
  --     if math.random() > gearPopOutChance then
  --       device:setGearIndex(0)
  --       guihooks.message({txt = string.format("Gear popped out, too much transmission damage"), context = {}}, 5, "vehicle.damage.synchros")
  --     end
  --     device.gearPopOutTimer = device.gearPopOutTimer + 1 --1s delay until the next check
  --   end
  -- end

  --insert0

  if device.mode == "disconnected" then
    device.torqueDiff = 0
  else
    device.torqueDiff = device[device.outputTorqueName]
  end

  if device.motorType == "drive" then
    device.electricsThrottleName = "throttle"
    if electrics.values.ignitionLevel == 2 then
      -- device.motorDirection = electrics.values.gearDirection or 0
      device.motorDirection = 1 * math.abs(electrics.values.motorDirection or 0)
    elseif electrics.values.ignitionLevel ~= 2 then
      device.motorDirection = 0
    end
  elseif device.motorType == "powerGenerator" then
    device.electricsThrottleName = "powerGenerator"
    if electrics.values.powerGeneratorMode == "on" then
      device.motorDirection = 1
    elseif electrics.values.powerGeneratorMode == "off" then
      device.motorDirection = 0
    end
  else
    device.electricsThrottleName = 0
  end

  device:updateEnergyUsage()

  device.outputRPM = device.outputAV1 * avToRPM

  device.grossWorkPerUpdate = 0
  device.frictionLossPerUpdate = 0

  --insert1
end

local function setGearIndex(device, index, availableSyncTime)
  local oldIndex = device.gearIndex
  local newDesiredIndex = clamp(index, device.minGearIndex, device.maxGearIndex)
  local isSuccessfulShift = true
  local isGrindingShift = false
  local maxGrindingTorque = 0
  --assume lots of time when no time is provided, this helps staying backwards compatible
  local ignoreSynchroHandling = not availableSyncTime
  availableSyncTime = availableSyncTime or math.huge

  local avDifference = (device.outputAV1 * device.gearRatios[newDesiredIndex]) - device.inputAV
  --only use this logic if are changing away from neutral and indeed changing into a different gear
  if newDesiredIndex ~= 0 and newDesiredIndex ~= oldIndex then
    local absAVDifference = abs(avDifference)
    --print(string.format("AV difference: %.2f", avDifference))
    local synchroWearCoef = linearScale(device.synchroWear[newDesiredIndex], 0.1, 1, 1, 0.4)

    --check if our AV difference is below a certain threshold where we allow shifting without clutch usage
    if absAVDifference <= device.shiftAllowedNonClutchAVDifference[newDesiredIndex] * synchroWearCoef or ignoreSynchroHandling then
      --shift succeeded without using the clutch
      --print(string.format("AV difference is minimal, shift succeeded without clutch usage. Allowed AV difference: %.2f", device.shiftAllowedNonClutchAVDifference[newDesiredIndex]))
    else
      --check if the current AV difference _can_ be synced away, this threshold is very low with non-synchromesh transmissions
      if absAVDifference > device.shiftMaxSynchroAVCapability[newDesiredIndex] * synchroWearCoef then
        --print(string.format("AV difference too high to sync. Max: %.2f, actual: %.2f", device.shiftMaxSynchroAVCapability[newDesiredIndex], avDifference))
        isSuccessfulShift = false
        isGrindingShift = true
        maxGrindingTorque = 50
      else
        --check if the clutch is pressed enough to allow for shifting, ideally this would be solved via a torque check instead, but that's difficult with the current way the clutch works
        local clutchPressedEnough = device.parent.clutchRatio and (1 - device.parent.clutchRatio) >= device.shiftRequiredClutchInput[newDesiredIndex]
        if not clutchPressedEnough then
          --print(string.format("Not enough clutch input. Required: %.2f, actual: ", device.shiftRequiredClutchInput[newDesiredIndex], (1 - device.parent.clutchRatio)))
          isSuccessfulShift = false
          isGrindingShift = true
          maxGrindingTorque = 50
        else
          local maxSyncSpeed = device.shiftMaxSynchroRate[newDesiredIndex] * synchroWearCoef
          --check if our actual hardware shiftime was long enough to hypotheitcally complete synchro use. Only act if it's _not_ enough.
          --We need to do it in this "backwards" way so that we don't introduce additional lag upon shifting
          --since the first time we are notified about "user shifted into gear" is when the gearstick already finished moving.
          if availableSyncTime * maxSyncSpeed < absAVDifference then
            --print(string.format("Available sync time too small. Required: %.4fs, actual: %.4fs", absAVDifference / maxSyncSpeed, availableSyncTime))
            --print(string.format("Hypothetical sync rate required for this shift: %.2f rad/s", (absAVDifference / availableSyncTime)))
            isSuccessfulShift = false
            isGrindingShift = true
            maxGrindingTorque = 50
          else
            --print(string.format("Good shift, perfection: %.1f%%", (absAVDifference / maxSyncSpeed) / availableSyncTime * 100))
          end
        end
      end
    end
  elseif newDesiredIndex == 0 then
    --if we are shifting into neutral, stop any possible grinding logic
    device:setGearGrinding(false)
  end

  if isSuccessfulShift then
    device.gearIndex = newDesiredIndex
    device.gearRatio = device.gearRatios[device.gearIndex]
    --safe guard in case there somehow was still grinding active
    device:setGearGrinding(false)
  end

  if isGrindingShift then
    --we have a grinding shift, enable the grinding logic
    device:setGearGrinding(true, newDesiredIndex, maxGrindingTorque)
  end

  --update our powertrain stats for the possibly new gear
  local maxExpectedOutputTorque = device.maxExpectedInputTorque * device.gearRatio
  device.invMaxExpectedOutputTorque = 1 / maxExpectedOutputTorque

  if device.gearRatio ~= 0 then
    powertrain.calculateTreeInertia()
  end

  selectUpdates(device)
end

local function onBreak(device)
  device.isBroken = true
  selectUpdates(device)
end

local function setLock(device, enabled)
  device.lockCoef = enabled and 0 or 1
  if device.parent and device.parent.setLock then
    device.parent:setLock(enabled)
  end
end

local function applyDeformGroupDamage(device, damageAmount)
  device.damageFrictionCoef = device.damageFrictionCoef + linearScale(damageAmount, 0, 0.01, 0, 0.1)
end

local function setPartCondition(device, subSystem, odometer, integrity, visual)
  device.wearFrictionCoef = linearScale(odometer, 30000000, 1000000000, 1, 2)
  local integrityState = integrity
  if type(integrity) == "number" then
    local integrityValue = integrity
    integrityState = {
      damageFrictionCoef = linearScale(integrityValue, 1, 0, 1, 50),
      synchroWear = {},
      isBroken = false
    }
    for gearIndex, _ in pairs(device.gearRatios) do
      integrityState.synchroWear[gearIndex] = 0
    end
  end

  device.damageFrictionCoef = integrityState.damageFrictionCoef or 1
  device.synchroWear = integrityState.synchroWear

  if integrityState.isBroken then
    device:onBreak()
  end
end

local function getPartCondition(device)
  local integrityState = {
    damageFrictionCoef = device.damageFrictionCoef,
    synchroWear = device.synchroWear,
    isBroken = device.isBroken
  }
  local integrityValue = linearScale(device.damageFrictionCoef, 1, 50, 1, 0)
  if device.isBroken then
    integrityValue = 0
  end
  return integrityValue, integrityState
end

local function validate(device)
  if device.parent and not device.parent.deviceCategories.clutch and not device.parent.isFake then
    log("E", "manualGearbox.validate", "Parent device is not a clutch device...")
    log("E", "manualGearbox.validate", "Actual parent:")
    log("E", "manualGearbox.validate", powertrain.dumpsDeviceData(device.parent))
    return false
  end

  if not device.transmissionNodeID then
    local engine = device.parent and device.parent.parent or nil
    local engineNodeID = engine and engine.engineNodeID or nil
    device.transmissionNodeID = engineNodeID or sounds.engineNode
  end

  if type(device.transmissionNodeID) ~= "number" then
    device.transmissionNodeID = nil
  end

  local maxEngineTorque
  local maxEngineAV

  if device.parent.parent and device.parent.parent.deviceCategories.engine then
    local engine = device.parent.parent
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

  local gearRatio = device.gearRatio ~= 0 and abs(device.gearRatio) or (device.maxGearRatio * 2)
  device.cumulativeInertia = outputInertia / gearRatio / gearRatio
  device.invCumulativeInertia = 1 / device.cumulativeInertia

  device.cumulativeGearRatio = cumulativeGearRatio * device.gearRatio
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
  device.gearGrindSoundFile = jbeamData.gearGrindSoundFile or "event:>Vehicle>Transmission>grind>transmissionGrind_01"
  local gearGrindSample = jbeamData.gearGrindEvent or "event:>Vehicle>Transmission>grind>transmissionGrindTest"
  device.gearGrindLoop = sounds.createSoundObj(gearGrindSample, "AudioDefaultLoop3D", "GearGrind", device.transmissionNodeID or sounds.engineNode)

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

  device.gearWhineFixedCoefOutput = jbeamData.gearWhineFixedCoefOutput or 0.7
  device.gearWhinePowerCoefOutput = 1 - device.gearWhineFixedCoefOutput
  device.gearWhineFixedCoefInput = jbeamData.gearWhineFixedCoefInput or 0.4
  device.gearWhinePowerCoefInput = 1 - device.gearWhineFixedCoefInput

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
  device.motorTorque = 0

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

  device.gearRatio = jbeamData.gearRatio or 1
  device.friction = jbeamData.friction or 0
  device.cumulativeInertia = 1
  device.cumulativeGearRatio = 1
  device.maxCumulativeGearRatio = 1
  device.grindingTorque = 0
  device.maxGrindingTorque = 0
  device.grindingTorqueSign = 0
  device.grindingTorqueReactionSign = 0

  device.outputAV1 = 0
  device.inputAV = 0
  device.outputTorque1 = 0
  device.virtualMassAV = 0
  device.isBroken = false

  device.lockCoef = 1
  device.misShiftPenaltyTimer = 0

  device.gearIndex = 1
  device.isShiftGrinding = false
  device.gearPopOutTimer = 0

  for k, v in pairs(device.initialGearRatios) do
    device.gearRatios[k] = v
    device.synchroWear[k] = 0
    device.previouslyReportedSynchroWear[k] = 0
  end

  device.wearFrictionCoef = 1
  device.damageFrictionCoef = 1

  damageTracker.setDamage("gearbox", "synchroWear", false)

  device:setGearIndex(0)

  selectUpdates(device)
end

local function new(jbeamData)
  local device = {

    --insert0
    motorTorque = 0,

    visualType = "manualGearbox",

    torqueDiff = 0,

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
    type = "emtGearbox",
    inputName = jbeamData.inputName,
    inputIndex = jbeamData.inputIndex,
    gearRatio = jbeamData.gearRatio or 1,
    friction = jbeamData.friction or 0,
    dynamicFriction = jbeamData.dynamicFriction or 0,
    torqueLossCoef = jbeamData.torqueLossCoef or 0,
    wearFrictionCoef = 1,
    damageFrictionCoef = 1,
    cumulativeInertia = 1,
    cumulativeGearRatio = 1,
    maxCumulativeGearRatio = 1,
    isPhysicallyDisconnected = true,
    outputAV1 = 0,
    inputAV = 0,
    outputTorque1 = 0,
    virtualMassAV = 0,
    isBroken = false,
    lockCoef = 1,
    misShiftPenaltyTimer = 0,
    grindingTorque = 0,
    maxGrindingTorque = 0,
    grindingTorqueSign = 0,
    grindingTorqueReactionSign = 0,
    isShiftGrinding = false,
    gearPopOutTimer = 0,
    gearIndex = 1,
    gearRatios = {},
    gearDamageThreshold = jbeamData.gearDamageThreshold or 3000,
    maxExpectedInputAV = 0,
    maxExpectedOutputAV = 0,
    maxExpectedInputTorque = 0,
    invMaxExpectedOutputTorque = 0,
    invMaxExpectedInputTorque = 0,
    invMaxExpectedPower = 0,
    reset = reset,
    updateGFX = updateGFX,
    initSounds = initSounds,
    resetSounds = resetSounds,
    updateSounds = updateSounds,
    onBreak = onBreak,
    validate = validate,
    setLock = setLock,
    calculateInertia = calculateInertia,
    updateGrinding = updateGrinding,
    setGearIndex = setGearIndex,
    setGearGrinding = setGearGrinding,
    applyDeformGroupDamage = applyDeformGroupDamage,
    setPartCondition = setPartCondition,
    getPartCondition = getPartCondition
  }

  device.torqueLossCoef = clamp(device.torqueLossCoef, 0, 1)
  device.neutralFriction = jbeamData.neutralFriction or device.friction
  device.neutralDynamicFriction = jbeamData.neutralDynamicFriction or device.dynamicFriction

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

  device.initialGearRatios = shallowcopy(device.gearRatios)

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

  local synchroSettings = tableFromHeaderTable(jbeamData.synchronizerSettings or {})
  local synchroSettingLookup = {}
  for _, settings in pairs(synchroSettings) do
    if settings.gearIndex then
      synchroSettingLookup[settings.gearIndex] = settings
    end
  end
  device.synchroWear = {}
  device.previouslyReportedSynchroWear = {}
  device.shiftAllowedNonClutchAVDifference = {}
  device.shiftRequiredClutchInput = {}
  device.shiftMaxSynchroAVCapability = {}
  device.shiftMaxSynchroRate = {}
  device.synchroWearCoef = {}
  for i, _ in pairs(device.gearRatios) do
    local gearSettings = synchroSettingLookup[i] or {}
    device.synchroWear[i] = 0
    device.previouslyReportedSynchroWear[i] = 0
    device.shiftAllowedNonClutchAVDifference[i] = (gearSettings.maxClutchRPMDifference or 50) * rpmToAV
    device.shiftRequiredClutchInput[i] = gearSettings.requiredClutchInput or 0.8
    device.shiftMaxSynchroAVCapability[i] = (gearSettings.maxSynchroRPMDifference or math.huge) * rpmToAV
    device.shiftMaxSynchroRate[i] = gearSettings.maxSynchroRate or 5000
    device.synchroWearCoef[i] = gearSettings.synchroWearCoef or 0.000005
  end

  --if no synchro settings are provided, use a default of a non-synchro reverse gear
  if not jbeamData.synchronizerSettings then
    for i, _ in pairs(device.gearRatios) do
      if i >= 0 then
        device.shiftMaxSynchroAVCapability[i] = math.huge
      else
        device.shiftMaxSynchroAVCapability[i] = 100
      end
    end
  end

  if jbeamData.gearboxNode_nodes and type(jbeamData.gearboxNode_nodes) == "table" then
    device.transmissionNodeID = jbeamData.gearboxNode_nodes[1]
  end

  if type(device.transmissionNodeID) ~= "number" then
    device.transmissionNodeID = nil
  end

  device:setGearIndex(0)

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

  --print("experimental gearbox device")

  return device
end

M.new = new

return M
