
local M = {}
M.type = "auxiliary"
M.defaultOrder = 85

M.isActive = false
M.isActing = false

local Modes = {
		Normal = 0,
		TwoWD = 1,
		Locked = 2,
		
		Unknown = 3
	}
	
local _currentMode = Modes.Normal

local _CMU = nil

local _controlParameters = {isEnabled = true}
local _initialControlParameters

local _relevantDifferential = nil

local _inputAVSmoother = newExponentialSmoothing(50)
local _outputAV1Smoother = newExponentialSmoothing(50)
local _outputAV2Smoother = newExponentialSmoothing(50)

local _outputTorque1 = 0
local _outputTorque2 = 0

local _inputAV = 0
local _outputAV1Corrected = 0
local _outputAV2Corrected = 0
local _totalAV = 0
local _totalTorque
local _avDiff = 0

local _baseBias = 0.5

local _torqueSplit = 0
local _avSplit = 0

local _torqueOffset = 0
local _avOffset = 0

local _biasA = 0.5
local _biasB = 0.5

local _targetBias = 0.5

--local _steeringCoef = 0


local function clamp(min, max, value)
	return math.min(max, math.max(min, value))
end

local function processNormalMode(dt)
	_inputAV = _inputAVSmoother:get(_relevantDifferential.inputAV * _relevantDifferential.invGearRatio)
	_outputAV1Corrected = _outputAV1Smoother:get(_relevantDifferential.outputAV1)
	_outputAV2Corrected = _outputAV2Smoother:get(_relevantDifferential.outputAV2)
	
	_outputTorque1 = _relevantDifferential.outputTorque1
	_outputTorque2 = _relevantDifferential.outputTorque2
	
	if _outputTorque1 * sign(_inputAV) < 0 then -- ignore outputs going in the opposite direction of the input
		_outputTorque1 = 0
		_outputAV1Corrected = 0
	end
	if _outputTorque2 * sign(_inputAV) < 0 then
		_outputTorque2 = 0
		_outputAV2Corrected = 0
	end
	
	_avDiff = math.abs((_outputAV2Corrected - _outputAV1Corrected) * sign(_inputAV))
	
	_totalTorque = math.abs(_outputTorque1) + math.abs(_outputTorque2)
	_totalAV = math.abs(_outputAV1Corrected) + math.abs(_outputAV2Corrected)
	
	--_steeringCoef = electrics.values.wheelspeed > _controlParameters.minSteeringSpeed and linearScale(math.abs(electrics.values.steering), 0.1, 0.3, 0, 1) or 0
	--_steeringCoef = math.min(_steeringCoef, 0.8)
	--_steeringCoef = electrics.values.wheelspeed > _controlParameters.minSteeringSpeed and math.abs(electrics.values.steering) / _controlParameters.steeringWheelLock or 0
	
	if _totalAV > _controlParameters.avThreshold and _avDiff > _controlParameters.avDiffThreshold then -- avoid unexpected behavior at low AV
		_torqueSplit = _outputTorque1 / _totalTorque * sign(_inputAV)
		_avSplit = math.abs(_outputAV1Corrected / _totalAV * sign(_inputAV))
		
		_torqueOffset = _torqueSplit - _baseBias
		_avOffset = (1 - _avSplit) - _baseBias
		
		_targetBias = (_torqueOffset + _avOffset) / 2
		--if _steeringCoef > 0 then
		--	_targetBias = (_targetBias + _steeringCoef * _controlParameters.rearOutput) / 2
		--end
		
		_targetBias = clamp(math.max(0.05, _baseBias - _controlParameters.maxBiasOffset), 
						math.min(0.95, _baseBias + _controlParameters.maxBiasOffset), 
						_targetBias + _baseBias) -- must never hit 0 or 1 or it will get stuck like that
	else
		_targetBias = _baseBias
	end
	
	_biasA = _targetBias < _biasA and _biasA - _controlParameters.changeRate * dt or
				_targetBias > _biasA and _biasA + _controlParameters.changeRate * dt or
				_biasA
				
	_biasB = 1 - _biasA
	
	_relevantDifferential.diffTorqueSplitA = _biasA
	_relevantDifferential.diffTorqueSplitB = _biasB
	
	--[[
	print("------------------------------")
	
	--print("_torqueDiff: " .. _torqueDiff)
	print("_avDiff: " .. _avDiff)
	print("_totalAV: " .. _totalAV)
	print("_totalTorque: " .. _totalTorque)
	print("_torqueSplit: " .. _torqueSplit)
	print("_avSplit: " .. _avSplit)
	print("_torqueOffset: " .. _torqueOffset)
	print("_avOffset: " .. _avOffset)
	--print("_biasOffset: " .. _biasOffset)
	print("_biasA: " .. _biasA)
	print("_biasB: " .. _biasB)
	print("_outputTorque1: " .. _outputTorque1)
	print("_outputTorque2: " .. _outputTorque2)
	print("_outputAV1Corrected: " .. _outputAV1Corrected)
	print("_outputAV2Corrected: " .. _outputAV2Corrected)
	print("electrics.values.steering: " .. electrics.values.steering)
	print("_steeringCoef: " .. _steeringCoef)
	
	print("------------------------------")
	-]]
	
end

local function updateFixedStep(dt)
	if not _controlParameters.isEnabled then
		_biasA = _baseBias
		_biasB = 1 - _biasA
		_relevantDifferential.diffTorqueSplitA = _biasA
		_relevantDifferential.diffTorqueSplitB = _biasB
		return
	end
	
	if _currentMode == Modes.Normal then
		processNormalMode(dt)
	--else
	--	_relevantDifferential.diffTorqueSplitA = _biasA
	--	_relevantDifferential.diffTorqueSplitB = _biasB
	end
	--print(_relevantDifferential.diffTorqueSplitA)
	--print(_relevantDifferential.diffTorqueSplitB)
end

local function updateGFX(dt)
  if not _controlParameters.isEnabled then
    return
  end
  
  --print(_relevantDifferential.diffTorqueSplitA)
  --print(_relevantDifferential.diffTorqueSplitB)
  --print(_relevantDifferential.mode)
end

local function setMode(output)
	--print("setMode")
	if _currentMode == Modes.Normal then
		return
	end
		--_relevantDifferential.mode = _controlParameters.baseDiffMode
	if _currentMode == Modes.TwoWD then
		output = output or 1
		_biasA = output == 1 and 1 or 0
		_biasB = 1 - _biasA
		_relevantDifferential.diffTorqueSplitA = _biasA
		_relevantDifferential.diffTorqueSplitB = _biasB
		--_relevantDifferential.mode = "open"
	elseif _currentMode == Modes.Locked then
		_biasA = clamp(_baseBias - _controlParameters.maxBiasOffset, _baseBias + _controlParameters.maxBiasOffset, 0.5)
		_biasB = 1 - _biasA
		--_relevantDifferential.mode = "locked"
		_relevantDifferential.diffTorqueSplitA = _biasA
		_relevantDifferential.diffTorqueSplitB = _biasB
	else 
		log("E", "camso_advawd.updateFixedStep", "Unknown mode: " .. _currentMode)
	end
end

local function shutdown()
	M.isActive = false
	M.isActing = false
	M.updateGFX = nil
	M.updateFixedStep = nil
end

local function reset()
	M.isActing = false
	_targetBias = _baseBias
	_biasA = _baseBias
	_biasB = 1 - _biasA
	setMode()
end

local function init(jbeamData)
	M.isActing = false
	
	_controlParameters.isEnabled = true
	_controlParameters.avThreshold = jbeamData.avThreshold or 10
	_controlParameters.avDiffThreshold = jbeamData.avDiffThreshold or 1
	_controlParameters.maxBiasOffset = jbeamData.maxBiasOffset or 0.2
	_controlParameters.rearOutput = jbeamData.rearOutput and jbeamData.rearOutput - 1 or 1
	_controlParameters.minSteeringSpeed = jbeamData.minSteeringSpeed or 8.33
	--_controlParameters.baseDiffMode = jbeamData.baseDiffMode or "lsd" -- can't get the diff type at init, this is the workaround
	--_controlParameters.mainOutput = jbeamData.mainOutput or 1
	--_controlParameters.mainOutput = clamp(0, 1, _controlParameters.mainOutput)
	_controlParameters.changeRate = jbeamData.changeRate or 1.5
	
	_controlParameters.steeringWheelLock = jbeamData.steeringWheelLock or 450
	
	_initialControlParameters = deepcopy(_controlParameters)
end

local function initSecondStage(jbeamData)
	if not _CMU then
		log("W", "camso_advawd.initSecondStage", "No _CMU present, disabling system...")
		shutdown()
		return
	end
	
	local diffName = jbeamData.differentialName
	if not diffName then
		log("E", "camso_advawd.initSecondStage", "No differentialName configured, disabling system...")
		return
	end
	
	_relevantDifferential = powertrain.getDevice(diffName)
	
	if not _relevantDifferential then
		log("E", "camso_advawd.initSecondStage", string.format("Can't find configured differential (%q), disabling system...", diffName))
		return
	end

	M.isActive = true
	
	_baseBias = _relevantDifferential.diffTorqueSplitA
	
	--print(_baseBias)
	
	--print(_relevantDifferential.diffTorqueSplitA)
	--print(_relevantDifferential.diffTorqueSplitB)
	--print(_relevantDifferential.mode)
end

local function registerCMU(cmu)
	_CMU = cmu
end

local function setParameters(parameters)	
	--_biasA = _baseBias
	--_biasB = 1 - _baseBias
  
	if parameters.mode then
		_currentMode = parameters.mode == "normal" and Modes.Normal or 
						--parameters.mode == "locked" and Modes.Locked or 
						parameters.mode == "locked" and Modes.Normal or 
						parameters.mode == "2wd" and Modes.TwoWD or
						Modes.Unknown
	else
		_currentMode = Modes.Normal
	end
	
	setMode(parameters.output)

	--print(_currentMode)
	
	--print(_relevantDifferential.diffTorqueSplitA)
	--print(_relevantDifferential.diffTorqueSplitB)
	--print(parameters.mode or "normal")
end

local function setConfig(configTable)
	_controlParameters = configTable
end

local function getConfig()
	return deepcopy(_controlParameters)
end

M.init = init
M.initSecondStage = initSecondStage

M.reset = reset

M.updateGFX = nil
M.updateFixedStep = updateFixedStep

M.registerCMU = registerCMU
M.shutdown = shutdown
M.setParameters = setParameters
M.setConfig = setConfig
M.getConfig = getConfig

return M

