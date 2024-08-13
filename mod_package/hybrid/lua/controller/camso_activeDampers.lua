
local M = {}
M.type = "auxiliary"
M.defaultOrder = 80

M.isActive = false
M.isActing = false

local _otherUpdate = false

local _lastG = 0

local _cmu = nil
local _isDebugEnabled = false

local _controlParameters = {isEnabled = true}
local _initialControlParameters

local _configPacket = {sourceType = "camso_activeDampers", packetType = "config", config = _controlParameters}
local _debugPacket = {sourceType = "camso_activeDampers"}

local _beamModes = {}
local _dampBeams = {}
local _currentMode = nil
local _lastMode = nil

local _beamParameters = {}

function lerp(a, b, t)
	return (1-t)*a+t*b
end

local function setDamperMode(modeName)
	local mode = _beamModes[modeName]
	if not mode then
		log("E", "activeDampers.setDamperMode", "Can't find mode: " .. modeName)
		return
	end
	
	_currentMode = mode
	
	for _, cid in ipairs(_dampBeams) do
		beam = v.data.beams[cid]
		
		_beamParameters[cid] = {}
		
		_beamParameters[cid].beamDampMin = beam.beamDamp * mode.beamDampCoefMin
		_beamParameters[cid].beamDampMax = beam.beamDamp * mode.beamDampCoefMax
		_beamParameters[cid].beamDampReboundMin = beam.beamDampRebound * mode.beamDampReboundCoefMin
		_beamParameters[cid].beamDampReboundMax = beam.beamDampRebound * mode.beamDampReboundCoefMax
		_beamParameters[cid].beamDampFastMin = beam.beamDampFast * mode.beamDampFastCoefMin
		_beamParameters[cid].beamDampFastMax = beam.beamDampFast * mode.beamDampFastCoefMax
		_beamParameters[cid].beamDampReboundFastMin = beam.beamDampReboundFast * mode.beamDampReboundFastCoefMin
		_beamParameters[cid].beamDampReboundFastMax = beam.beamDampReboundFast * mode.beamDampReboundFastCoefMax
		_beamParameters[cid].beamDampVelocitySplitMin = beam.beamDampVelocitySplit * mode.beamDampVelocitySplitCoefMin
		_beamParameters[cid].beamDampVelocitySplitMax = beam.beamDampVelocitySplit * mode.beamDampVelocitySplitCoefMax
	end
end

local function reset()
end

local function init(jbeamData)
	local dampBeamNames = jbeamData.dampBeamNames or {}
	_dampBeams = {}
	for _, b in pairs(v.data.beams) do
		if b.name then
			for _, name in pairs(dampBeamNames) do
				if b.name == name then
					table.insert(_dampBeams, b.cid)
				end
			end
		end
	end
	
	local modeData = tableFromHeaderTable(jbeamData.modes or {})
	
	_beamModes = {}
	for _, mode in pairs(modeData) do
		_beamModes[mode.name] = {
			beamDampCoefMin = mode.beamDampCoefMin or 1,
			beamDampFastCoefMin = mode.beamDampFastCoefMin or 1,
			beamDampReboundCoefMin = mode.beamDampReboundCoefMin or 1,
			beamDampReboundFastCoefMin = mode.beamDampReboundFastCoefMin or 1,
			beamDampVelocitySplitCoefMin = mode.beamDampVelocitySplitCoefMin or 1,
			beamDampCoefMax = mode.beamDampCoefMax or 1,
			beamDampFastCoefMax = mode.beamDampFastCoefMax or 1,
			beamDampReboundCoefMax = mode.beamDampReboundCoefMax or 1,
			beamDampReboundFastCoefMax = mode.beamDampReboundFastCoefMax or 1,
			beamDampVelocitySplitCoefMax = mode.beamDampVelocitySplitCoefMax or 1,
			minGForce = mode.gMin,
			maxGForce = mode.gMax
		}
	end
	
	_currentMode = _beamModes[1] or nil
	_lastMode = _currentMode
	
	_otherUpdate = jbeamData.otherUpdate or false
	
	local nameString = jbeamData.name
	local slashPos = nameString:find("/", -nameString:len())
	if slashPos then
		nameString = nameString:sub(slashPos + 1)
	end
	_debugPacket.sourceName = nameString
	
	M.isActive = true
end

local function initLastStage()
end

local function update()
	if _otherUpdate then
		_otherUpdate = false -- run only every other physics update, alternating updates between front and rear
		return
	end
	_otherUpdate = true

	local currentGForce = math.abs(sensors.gx2)
	
	if _currentMode == _lastMode and math.abs(currentGForce - _lastG) < 0.3 then -- do not update if the change is too small to matter
		return
	end
	_lastMode = _currentMode
	_lastG = currentGForce
	
	local gForceCoef = math.min(1, math.max(0, (currentGForce - _currentMode.minGForce) / (_currentMode.maxGForce - _currentMode.minGForce)))

	for _, cid in ipairs(_dampBeams) do
		local parameters = _beamParameters[cid]
		
		local beamDamp = lerp(parameters.beamDampMin, parameters.beamDampMax, gForceCoef)
		local beamDampRebound = lerp(parameters.beamDampReboundMin, parameters.beamDampReboundMax, gForceCoef)
		local beamDampFast = lerp(parameters.beamDampFastMin, parameters.beamDampFastMax, gForceCoef)
		local beamDampReboundFast = lerp(parameters.beamDampReboundFastMin, parameters.beamDampReboundFastMax, gForceCoef)
		local beamDampVelocitySplit = lerp(parameters.beamDampVelocitySplitMin, parameters.beamDampVelocitySplitMax, gForceCoef)
		
		obj:setBoundedBeamDamp(cid, beamDamp, beamDampRebound, beamDampFast, beamDampReboundFast, beamDampVelocitySplit, beamDampVelocitySplit)
		
		--[[
		print("---------------------------------------------------------")
		print("currentGForce: " .. currentGForce)
		print("gForceCoef: " .. gForceCoef)
		print("beamDamp: " .. beamDamp)
		print("beamDampRebound: " .. beamDampRebound)
		print("beamDampFast: " .. beamDampFast)
		print("beamDampReboundFast: " .. beamDampReboundFast)
		print("beamDampVelocitySplit: " .. beamDampVelocitySplit)
		print("---------------------------------------------------------")
		--]]
	end
end

local function setDebugMode(debugEnabled)
	_isDebugEnabled = debugEnabled
end

local function registerCMU(cmu)
	_cmu = cmu
end

local function shutdown()
	M.isActive = false
	M.updateGFX = nil
	M.update = nil
end

local function setParameters(parameters)
	if parameters.damperMode then
		setDamperMode(parameters.damperMode)
	end
end

local function setConfig(configTable)
	_controlParameters = configTable
end

local function getConfig()
	return deepcopy(_controlParameters)
end

local function sendConfigData()
	_configPacket.config = _controlParameters
	_cmu.sendDebugPacket(_configPacket)
end

M.init = init
M.reset = reset
M.initLastStage = initLastStage
M.update = update

M.registerCMU = registerCMU
M.setDebugMode = setDebugMode
M.shutdown = shutdown
M.setParameters = setParameters
M.setConfig = setConfig
M.getConfig = getConfig
M.sendConfigData = sendConfigData

return M

