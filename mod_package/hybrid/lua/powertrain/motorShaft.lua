-- motorShaft.lua - 2024.3.8 14:45 - Shaft with electric motor
-- by NZZ
-- version 0.0.10 alpha
-- final edit - 2024.9.24 14:42

local M = {}

M.outputPorts = {[1] = true}
M.deviceCategories = {clutchlike = true, shaft = true}

local max = math.max
local min = math.min
local sqrt = math.sqrt
local abs = math.abs
local floor = math.floor
local clamp = clamp
local sign = sign

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local torqueToPower = 0.0001404345295653085
local psToWatt = 735.499

--insert0

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

local function updateGFX(device, dt)

  if device.mode == "disconnected" then
    device.torqueDiff = 0
  else
    device.torqueDiff = device[device.outputTorqueName]
  end

  if device.motorType == "drive" then
    if electrics.values.ignitionLevel == 2 then
      device.motorDirection = electrics.values.motorDirection or 0
    elseif electrics.values.ignitionLevel ~= 2 then
      device.motorDirection = 0
    end
  elseif device.motorType == "powerGenerator" then
    device.motorDirection = 1
  else
    device.motorDirection = 0
  end

  device:updateEnergyUsage()

  device.outputRPM = device.outputAV1 * avToRPM

  device.grossWorkPerUpdate = 0
  device.frictionLossPerUpdate = 0

end
--insert1
local function setmotorRatio(device, ratio)
  device.motorRatio = ratio * 1
end

local function setmotorType(device, motorType)
  device.motorType = motorType
end


local function motorTorque(device, dt)
  local engineAV = device.outputAV1
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
  local rpm = engineAV * avToRPM * motorDirection * device.motorRatio
  local torqueRPM = floor(rpm)

  --local torqueCoef = clamp(device.torqueCoef, 0, 1) --can be used to externally reduce the available torque, for example to limit output power
  local torqueCoef = 1
  local torque = (torqueCurve[torqueRPM] or (torqueRPM < 0 and torqueCurve[0] or 0)) * device.outputTorqueState * torqueCoef
  torque = torque * throttle * motorDirection
  torque = min(torque, device.maxTorqueLimit) --limit output torque to a specified max, math.huge by default

  local regenThrottle = electrics.values[device.electricsRegenThrottleName] or 0
  local rawRegenTorque = (device.regenCurve[torqueRPM] or 0)
  local regenTorque = -(min(max(rawRegenTorque * regenThrottle, min(rawRegenTorque, device.minWantedRegenTorque)), device.maxWantedRegenTorque) * sign(regenThrottle) * throttleFactor * motorDirection)
  device.regenThrottle = regenThrottle
  device.instantMaxRegenTorque = rawRegenTorque

  local actualTorque = throttle > 0 and torque or regenTorque

  -- device.consoleNum0 = 
  device.motorOutputRPM = torqueRPM
  device.motorOutputTorque = torque
  device.motorRegenTorque = regenTorque

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
  device.motorTorque = (actualTorque - frictionTorque) * timeSign
  return (actualTorque - frictionTorque) * device.motorRatio * timeSign
end

local function updateSounds(device, dt)
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
end

local function updateVelocity(device, dt)
  device.inputAV = device[device.outputAVName] * device.gearRatio
  device.parent[device.parentOutputAVName] = device.inputAV
end

local function updateTorque(device, dt)
  device[device.outputTorqueName] = (device.parent[device.parentOutputTorqueName] - (device.friction * clamp(device.inputAV, -1, 1) + device.dynamicFriction * device.inputAV) * device.wearFrictionCoef * device.damageFrictionCoef) * device.gearRatio

  device[device.outputTorqueName] = device[device.outputTorqueName] + motorTorque(device, dt)

end

local function disconnectedUpdateVelocity(device, dt)
  --use the speed of the virtual mass, not the drivetrain on other side if the shaft is broken or disconnected, otherwise, pass through
  device.inputAV = device.virtualMassAV * device.gearRatio
  device.parent[device.parentOutputAVName] = device.inputAV
end

local function disconnectedUpdateTorque(device, dt)
  local outputTorque = (device.parent[device.parentOutputTorqueName] - (device.friction * clamp(device.inputAV, -1, 1) + device.dynamicFriction * device.inputAV) * device.wearFrictionCoef * device.damageFrictionCoef) * device.gearRatio
  --accelerate a virtual mass with the output torque if the shaft is disconnected or broken
  device.virtualMassAV = device.virtualMassAV + outputTorque * device.invCumulativeInertia * dt
  device[device.outputTorqueName] = 0 --set to 0 to stop children receiving torque

  device[device.outputTorqueName] = device[device.outputTorqueName] + motorTorque(device, dt)
end

local function wheelShaftUpdateVelocity(device, dt)
  device[device.outputAVName] = device.wheel.angularVelocity * device.wheelDirection
  device.inputAV = device[device.outputAVName] * device.gearRatio
  device.parent[device.parentOutputAVName] = device.inputAV
end

local function wheelShaftUpdateTorque(device)
  local outputTorque = device.parent[device.parentOutputTorqueName] * device.gearRatio
  local wheel = device.wheel
  wheel.propulsionTorque = outputTorque * device.wheelDirection
  wheel.frictionTorque = (device.friction + device.dynamicFriction * device.inputAV) * device.wearFrictionCoef * device.damageFrictionCoef
  device[device.outputTorqueName] = outputTorque
  local trIdx = wheel.torsionReactorIdx
  powertrain.torqueReactionCoefs[trIdx] = powertrain.torqueReactionCoefs[trIdx] + abs(outputTorque)
end

local function wheelShaftDisconnectedUpdateVelocity(device, dt)
  device[device.outputAVName] = device.wheel.angularVelocity * device.wheelDirection
  device.inputAV = device.virtualMassAV * device.gearRatio
  device.parent[device.parentOutputAVName] = device.inputAV
end

local function wheelShaftDisconnectedUpdateTorque(device, dt)
  local outputTorque = (device.parent[device.parentOutputTorqueName] - (device.friction * clamp(device.inputAV, -1, 1) + device.dynamicFriction * device.inputAV) * device.wearFrictionCoef * device.damageFrictionCoef) * device.gearRatio
  --accelerate a virtual mass with the output torque if the shaft is disconnected or broken
  device.virtualMassAV = device.virtualMassAV + outputTorque * device.invCumulativeInertia * dt
  device[device.outputTorqueName] = 0 --set to 0 to stop children receiving torque
  device.wheel.propulsionTorque = 0
  device.wheel.frictionTorque = device.friction
end

local function selectUpdates(device)
  device.velocityUpdate = updateVelocity
  device.torqueUpdate = updateTorque

  if device.connectedWheel then
    device.velocityUpdate = wheelShaftUpdateVelocity
    device.torqueUpdate = wheelShaftUpdateTorque
  end

  if device.isBroken or device.mode == "disconnected" then
    device.velocityUpdate = disconnectedUpdateVelocity
    device.torqueUpdate = disconnectedUpdateTorque
    if device.connectedWheel then
      device.velocityUpdate = wheelShaftDisconnectedUpdateVelocity
      device.torqueUpdate = wheelShaftDisconnectedUpdateTorque
    end
    --make sure the virtual mass has the right AV
    device.virtualMassAV = device.inputAV
  end
end

local function applyDeformGroupDamage(device, damageAmount)
  device.damageFrictionCoef = device.damageFrictionCoef + linearScale(damageAmount, 0, 0.01, 0, 0.1)
end

local function setPartCondition(device, subSystem, odometer, integrity, visual)
  device.wearFrictionCoef = linearScale(odometer, 30000000, 1000000000, 1, 1.5)
  local integrityState = integrity
  if type(integrity) == "number" then
    local integrityValue = integrity
    integrityState = {damageFrictionCoef = linearScale(integrityValue, 1, 0, 1, 50), isBroken = false}
  end

  device.damageFrictionCoef = integrityState.damageFrictionCoef or 1

  if integrityState.isBroken then
    device:onBreak()
  end
end

local function getPartCondition(device)
  local integrityState = {damageFrictionCoef = device.damageFrictionCoef, isBroken = device.isBroken}
  local integrityValue = linearScale(device.damageFrictionCoef, 1, 50, 1, 0)
  if device.isBroken then
    integrityValue = 0
  end
  return integrityValue, integrityState
end

local function validate(device)
  if device.isPhysicallyDisconnected then
    device.mode = "disconnected"
    selectUpdates(device)
  end

  if (not device.connectedWheel) and (not device.children or #device.children <= 0) then
    --print(device.name)
    local parentDiff = device.parent
    while parentDiff.parent and not parentDiff.deviceCategories.differential do
      parentDiff = parentDiff.parent
      --print(parentDiff and parentDiff.name or "nil")
    end

    if parentDiff and parentDiff.deviceCategories.differential and parentDiff.defaultVirtualInertia then
      --print("Found parent diff, using its default virtual inertia: "..parentDiff.defaultVirtualInertia)
      device.virtualInertia = parentDiff.defaultVirtualInertia
    end
  end

  if device.connectedWheel and device.parent then
    --print(device.connectedWheel)
    --print(device.name)
    local torsionReactor = device.parent
    while torsionReactor.parent and torsionReactor.type ~= "torsionReactor" do
      torsionReactor = torsionReactor.parent
      --print(torsionReactor and torsionReactor.name or "nil")
    end

    if torsionReactor and torsionReactor.type == "torsionReactor" and torsionReactor.torqueReactionNodes then
      local wheel = powertrain.wheels[device.connectedWheel]
      local reactionNodes = torsionReactor.torqueReactionNodes
      wheel.obj:setEngineAxisCoupleNodes(reactionNodes[1], reactionNodes[2], reactionNodes[3])
      device.torsionReactor = torsionReactor
      wheel.torsionReactor = torsionReactor
    end
  end

  return true
end

local function updateSimpleControlButtons(device)
  if #device.availableModes > 1 and device.uiSimpleModeControl then
    local modeIconLookup
    if device.connectedWheel then
      modeIconLookup = {connected = "powertrain_wheel_connected", disconnected = "powertrain_wheel_disconnected"}
    else
      modeIconLookup = {connected = "powertrain_shaft_connected", disconnected = "powertrain_shaft_disconnected"}
    end
    extensions.ui_simplePowertrainControl.setButton("powertrain_device_mode_shortcut_" .. device.name, device.uiName, modeIconLookup[device.mode], nil, nil, string.format("powertrain.toggleDeviceMode(%q)", device.name))
  end
end

local function setMode(device, mode)
  local isValidMode = false
  for _, availableMode in ipairs(device.availableModes) do
    if mode == availableMode then
      isValidMode = true
    end
  end
  if not isValidMode then
    return
  end
  device.mode = mode
  --prevent mode changes to physically disconnected devices, they lock up if in any other mode than "disconnected"
  if device.isPhysicallyDisconnected then
    device.mode = "disconnected"
  end
  selectUpdates(device)
  device:updateSimpleControlButtons()
end

local function onBreak(device)
  device.isBroken = true
  --obj:breakBeam(device.breakTriggerBeam)
  selectUpdates(device)
end

--insert0
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

--insert1

local function calculateInertia(device)
  local outputInertia
  local cumulativeGearRatio = 1
  local maxCumulativeGearRatio = 1
  if device.children and #device.children > 0 then
    local child = device.children[1]
    outputInertia = child.cumulativeInertia
    cumulativeGearRatio = child.cumulativeGearRatio
    maxCumulativeGearRatio = child.maxCumulativeGearRatio
  elseif device.connectedWheel then
    local axisInertia = 0
    local wheel = powertrain.wheels[device.connectedWheel]
    local hubNode1 = vec3(v.data.nodes[wheel.node1].pos)
    local hubNode2 = vec3(v.data.nodes[wheel.node2].pos)

    for _, nid in pairs(wheel.nodes) do
      local n = v.data.nodes[nid]
      local distanceToAxis = vec3(n.pos):distanceToLine(hubNode1, hubNode2)
      axisInertia = axisInertia + (n.nodeWeight * (distanceToAxis * distanceToAxis))
    end

    --print(device.connectedWheel .. " Hub-Axis Inertia: " .. axisInertia .. " kgm^2")
    outputInertia = axisInertia
  else
    --Nothing connected to this shaft :(
    outputInertia = device.virtualInertia --some default inertia
  end

  device.cumulativeInertia = outputInertia / device.gearRatio / device.gearRatio
  device.invCumulativeInertia = device.cumulativeInertia > 0 and 1 / device.cumulativeInertia or 0
  device.cumulativeGearRatio = cumulativeGearRatio * device.gearRatio
  device.maxCumulativeGearRatio = maxCumulativeGearRatio * device.gearRatio
end

--insert0

local function getSoundConfiguration(device)
  return device.soundConfiguration
end

--insert1

local function reset(device, jbeamData)
  device.gearRatio = jbeamData.gearRatio or 1
  device.friction = jbeamData.friction or 0
  device.cumulativeInertia = 1
  device.invCumulativeInertia = 1
  device.cumulativeGearRatio = 1
  device.maxCumulativeGearRatio = 1

  device.inputAV = 0
  device.visualShaftAngle = 0
  device.virtualMassAV = 0

  device.isBroken = false
  device.wearFrictionCoef = 1
  device.damageFrictionCoef = 1

  device[device.outputTorqueName] = 0
  device[device.outputAVName] = 0

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

  device.motorRatio = 0
  --insert1

  selectUpdates(device)

  return device
end

--insert0

local function resetSounds(device, jbeamData)
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
end

--insert1

local function new(jbeamData)
  local device = {
    deviceCategories = shallowcopy(M.deviceCategories),
    requiredExternalInertiaOutputs = shallowcopy(M.requiredExternalInertiaOutputs),
    outputPorts = shallowcopy(M.outputPorts),
    name = jbeamData.name,
    type = jbeamData.type,
    inputName = jbeamData.inputName,
    inputIndex = jbeamData.inputIndex,
    gearRatio = jbeamData.gearRatio or 1,
    friction = jbeamData.friction or 0,
    dynamicFriction = jbeamData.dynamicFriction or 0,
    wearFrictionCoef = 1,
    damageFrictionCoef = 1,
    cumulativeInertia = 1,
    invCumulativeInertia = 1,
    virtualInertia = 2,
    cumulativeGearRatio = 1,
    maxCumulativeGearRatio = 1,
    isPhysicallyDisconnected = true,
    electricsName = jbeamData.electricsName,
    visualShaftAVName = jbeamData.visualShaftAVName,
    inputAV = 0,
    visualShaftAngle = 0,
    virtualMassAV = 0,
    isBroken = false,
    torsionReactor = nil,
    nodeCid = jbeamData.node,
    reset = reset,
    onBreak = onBreak,
    setMode = setMode,
    validate = validate,
    calculateInertia = calculateInertia,
    applyDeformGroupDamage = applyDeformGroupDamage,
    setPartCondition = setPartCondition,
    getPartCondition = getPartCondition,
    updateSimpleControlButtons = updateSimpleControlButtons,

    --insert0
    motorOutputRPM = 0,
    motorTorque = 0,
    motorOutputTorque = 0,
    motorRegenTorque = 0,
    consoleNum0 = 0,

    visualType = "electricMotor",
    outputAV1 = 0,
    torqueDiff = 0,

    setmotorRatio = setmotorRatio,
    setmotorType = setmotorType,
    maxTorqueLimit = math.huge,

    initSounds = initSounds,
    resetSounds = resetSounds,
    updateSounds = nop,

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
    updateGFX = updateGFX,
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
    getSoundConfiguration = getSoundConfiguration
    --insert1
  }

  if jbeamData.connectedWheel and powertrain.wheels[jbeamData.connectedWheel] then
    device.connectedWheel = jbeamData.connectedWheel
    device.wheel = powertrain.wheels[device.connectedWheel]
    device.wheelDirection = powertrain.wheels[device.connectedWheel].wheelDir

    device.cumulativeInertia = 1

    local pos = v.data.nodes[device.wheel.node1].pos
    device.visualPosition = pos
    device.visualType = "wheel"
  end

  local outputPortIndex = 1
  if jbeamData.outputPortOverride then
    device.outputPorts = {}
    for _, v in pairs(jbeamData.outputPortOverride) do
      device.outputPorts[v] = true
      outputPortIndex = v
    end
  end

  device.outputTorqueName = "outputTorque" .. tostring(outputPortIndex)
  device.outputAVName = "outputAV" .. tostring(outputPortIndex)
  device[device.outputTorqueName] = 0
  device[device.outputAVName] = 0

  if jbeamData.canDisconnect then
    device.availableModes = {"connected", "disconnected"}
    device.mode = jbeamData.isDisconnected and "disconnected" or "connected"
  else
    device.availableModes = {"connected"}
    device.mode = "connected"
  end

  device.breakTriggerBeam = jbeamData.breakTriggerBeam
  if device.breakTriggerBeam and device.breakTriggerBeam == "" then
    --get rid of the break beam if it's just an empty string (cancellation)
    device.breakTriggerBeam = nil
  end

  --insert0
  device.motorType = jbeamData.motorType or "drive"

  device.motorRatio = 0

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
  device.energyStorage = jbeamData.energyStorage

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

  --dump(jbeamData)

  --device.torqueData = getTorqueData(device)
  --device.maxPower = device.torqueData.maxPower
  --device.maxTorque = device.torqueData.maxTorque
  --device.maxPowerThrottleMap = device.torqueData.maxPower * psToWatt
  --insert1

  selectUpdates(device)

  return device
end

M.new = new

return M
