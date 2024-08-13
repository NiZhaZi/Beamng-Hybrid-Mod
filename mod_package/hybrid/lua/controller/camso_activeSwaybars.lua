
local M = {}
M.type = "auxiliary"
M.defaultOrder = 80

M.isActive = false
M.isActing = false

local _cmu = nil
local _isDebugEnabled = false

local _controlParameters = {isEnabled = true}
local _initialControlParameters

local _configPacket = {sourceType = "adaptiveTorsionBars", packetType = "config", config = _controlParameters}
local _debugPacket = {sourceType = "adaptiveTorsionBars"}

local _torsionBarModes = {}
local _torsionBars = {}

local _otherUpdate = false
local _lastG = 0
local _currentMode = nil
local _lastMode = nil
local _tosionBarParameters = {}

function lerp(a, b, t)
	return (1-t)*a+t*b
end

local function setTorsionBarMode(modeName)
	local mode = _torsionBarModes[modeName]
	if not mode then
		log("E", "activeTorsionBars.setTorsionBarMode", "Can't find mode: " .. modeName)
		return
	end
	
	_currentMode = mode
	
	for _, cid in ipairs(_torsionBars) do
		_tosionBarParameters[cid] = {}
		_tosionBarParameters[cid].springMin = v.data.torsionbars[cid].spring * mode.springCoefMin
		_tosionBarParameters[cid].springMax = v.data.torsionbars[cid].spring * mode.springCoefMax
		_tosionBarParameters[cid].dampMin = v.data.torsionbars[cid].damp * mode.dampCoefMin
		_tosionBarParameters[cid].dampMax = v.data.torsionbars[cid].damp * mode.dampCoefMax
		--obj:setTorsionbarSpringDamp(cid, spring, damp)
	end
end

local function reset()
end

local function update()
	if _currentMode == _lastMode and not _currentMode.enabled then
		return
	end

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

	for _, cid in ipairs(_torsionBars) do
		local parameters = _tosionBarParameters[cid]
		
		local spring = lerp(parameters.springMin, parameters.springMax, gForceCoef)
		local damp = lerp(parameters.dampMin, parameters.dampMax, gForceCoef)
		
		obj:setTorsionbarSpringDamp(cid, spring, damp)
		
		--[[
		print("---------------------------------------------------------")
		print("currentGForce: " .. currentGForce)
		print("gForceCoef: " .. gForceCoef)
		print("spring: " .. spring)
		print("damp: " .. damp)
		print("---------------------------------------------------------")
		--]]
	end
end

local function init(jbeamData)
	local torsionBarNames = jbeamData.torsionBarNames or {}
	_torsionBars = {}
	for _, b in pairs(v.data.torsionbars) do
		if b.name then
			for _, name in pairs(torsionBarNames) do
				if b.name == name then
					table.insert(_torsionBars, b.cid)
				end
			end
		end
	end
	
	local modeData = tableFromHeaderTable(jbeamData.modes or {})
	
	_torsionBarModes = {}
	for _, mode in pairs(modeData) do
		_torsionBarModes[mode.name] = {
			springCoefMin = mode.springCoefMin or 1,
			springCoefMax = mode.springCoefMax or 1,
			dampCoefMin = mode.dampCoefMin or 1,
			dampCoefMax = mode.dampCoefMax or 1,
			minGForce = mode.gMin,
			maxGForce = mode.gMax,
			enabled = mode.enabled
		}
	end
	
	_currentMode = _torsionBarModes[1] or nil
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
	if parameters.torsionBarMode then
		setTorsionBarMode(parameters.torsionBarMode)
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

