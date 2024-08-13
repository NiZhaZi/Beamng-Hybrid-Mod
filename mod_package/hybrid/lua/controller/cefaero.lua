local M = {}

local dragNodeOrigin = nil
local dragNodeX = nil
local dragNodeY = nil
local dragNodeZ = nil

local dragForceY = 0
local dragForceX = 0
local dragForceZ = 0

local currentVelocity = {0,0,0}

local overrideDrag = false
local overrideDensity = false

local airDensity = 1.225
local vehicleArea = 1
local dragModX = 1.25
local dragModZ = 1.5

local windVector = vec3(0,0,0)

local forwardVector = vec3(0,-1,0)
local upVector = vec3(0, 0, 1)
local leftVector = forwardVector:cross(upVector)

local WORLD_UP_VECTOR = vec3(0,0,1)

local windSpeeds = {0, 0, 0}

local downforceNodesFront = {}
local downforceNodesRear = {}
local downforceFactorFront = 0
local downforceFactorRear = 0

local downforceModelEnabled = false

local forcedDownforceFront = 0
local forcedDownforceRear = 0

local constantForceFront = 0
local constantForceRear = 0

local function getVehicleVelocity()

	if not (dragNodeOrigin and dragNodeX and dragNodeY and dragNodeZ) then
		--print("DRAG MODEL: Drag Nodes not set!")
		return
	end

	local velX = -obj:getNodeVelocity(dragNodeOrigin, dragNodeX)
	local velY = -obj:getNodeVelocity(dragNodeOrigin, dragNodeY)
	local velZ = -obj:getNodeVelocity(dragNodeOrigin, dragNodeZ)
	--local retArray = [velx, velY, velZ]
	return {velX, velY, velZ}
end

local function setDragForce(_forceX, _forceY, _forceZ)
	dragForceY = _forceY
	dragForceX = _forceX
	dragForceZ = _forceZ
end

local function calculateDragForce(_affectedArea, _airDensity, _velocity)
	return _affectedArea * 0.5 * _airDensity * _velocity * _velocity * sign(_velocity)
end

local function calculateDownforce(_factor, _velocity)
	return 0.5 * _factor * airDensity * _velocity * _velocity * sign(_velocity)
end

local function setVehicleArea(_area)
	vehicleArea = _area
end
local function getVehicleArea()
	return vehicleArea
end
local function setAirDensity(_density)
	airDensity = _density
end
local function getAirDensity()
	return airDensity
end
local function setDownforceFactorFront(_factor)
	downforceFactorFront = _factor
end
local function setDownforceFactorRear(_factor)
	downforceFactorRear = _factor
end
local function getDownforceModelEnabled()
	return downforceModelEnabled
end
local function setDownforceModelEnabled(_isEnabled)
	downforceModelEnabled = _isEnabled
end

local function update()

	if not overrideDensity then 
			airDensity = obj:getAirDensity() 
		end
	if not overrideDrag then
		
		currentVelocity = getVehicleVelocity()
		
		forwardVector = -obj:getDirectionVector()
		upVector = obj:getDirectionVectorUp()
		leftVector = forwardVector:cross(upVector)
		
		windVector = obj:getFlow()
		
		windSpeeds[1] = leftVector:dot(windVector)
		windSpeeds[2] = forwardVector:dot(windVector)
		windSpeeds[3] = upVector:dot(windVector)
		
		setDragForce(calculateDragForce(vehicleArea * dragModX, airDensity, currentVelocity[1] + windSpeeds[1]), 
			calculateDragForce(vehicleArea, airDensity, currentVelocity[2] + windSpeeds[2]), 
			calculateDragForce(vehicleArea * dragModZ, airDensity, currentVelocity[3] + windSpeeds[3]))
	end

	obj:applyForce(dragNodeOrigin, dragNodeY, dragForceY)
	obj:applyForce(dragNodeOrigin, dragNodeX, dragForceX)
	obj:applyForce(dragNodeOrigin, dragNodeZ, dragForceZ)
	
	if not downforceModelEnabled then
		for _, frontNodes in pairs(downforceNodesFront) do
			obj:applyForce(frontNodes.ref, frontNodes.up, forcedDownforceFront)
		end
		for _, rearNodes in pairs(downforceNodesRear) do
			obj:applyForce(rearNodes.ref, rearNodes.up, forcedDownforceRear)
		end
		return
	end
	
	for _, frontNodes in pairs(downforceNodesFront) do
		obj:applyForce(frontNodes.ref, frontNodes.up,
			-calculateDownforce(downforceFactorFront, currentVelocity[2] + windSpeeds[2]) * math.abs(WORLD_UP_VECTOR:dot(upVector)) - constantForceFront)
	end
	for _, rearNodes in pairs(downforceNodesRear) do
		obj:applyForce(rearNodes.ref, rearNodes.up,
			-calculateDownforce(downforceFactorRear, currentVelocity[2] + windSpeeds[2]) * math.abs(WORLD_UP_VECTOR:dot(upVector)) - constantForceRear)
	end
end

local function getDragForce()
	return {dragForceX,	dragForceY,	dragForceZ}
end
local function setOverrideDrag(_overrideDrag)
	overrideDrag = _overrideDrag
	if overrideDrag then setDragForce(0,0,0) end
end
local function setOverrideDensity(_overrideDensity)
	overrideDensity = _overrideDensity
end

local function getFactorForDownforceAtKMH(_downforce, _velocity, _airDensity)
	if _airDensity == 0 then
		_airDensity = airDensity
	end
	_velocity = _velocity / 3.6
	return _downforce / (0.5 * airDensity * _velocity * _velocity * sign(_velocity))
end

local function setForcedDownforce(_front, _rear)
	forcedDownforceFront = _front
	forcedDownforceRear = _rear
end
local function disableAeroCalcs(_disable)
	if _disable == true then
		setOverrideDensity(true)
		setOverrideDrag(true)
		setDownforceModelEnabled(false)
	else
		setOverrideDensity(false)
		setOverrideDrag(false)
		setDownforceModelEnabled(true)
	end
end

local function reset()
	setDragForce(0,0,0)
	currentVelocity = {0,0,0}
	
	windSpeeds = {0, 0, 0}
	--setVehicleWind(0,0,0)
	
	setForcedDownforce(0,0)
	
	disableAeroCalcs(false)
	
	forwardVector = vec3(0,-1,0)
	upVector = vec3(0, 0, 1)
	leftVector = forwardVector:cross(upVector)
end

local function init()
	print("INITIALIZING AERO MODEL V3")

	--local dragForceY = 0
	--local dragForceX = 0
	--local dragForceZ = 0
	setDragForce(0,0,0)
	currentVelocity = {0,0,0}
	
	windSpeeds = {0, 0, 0}
	--setVehicleWind(0,0,0)
	
	setForcedDownforce(0,0)
	
	disableAeroCalcs(false)
	
	forwardVector = vec3(0,-1,0)
	upVector = vec3(0, 0, 1)
	leftVector = forwardVector:cross(upVector)

	if v.data.dragModel == nil then
		M.update = nop
		M.updateGFX = nop
		return
	end
	local dragNodes = v.data.dragModel
	
	if (#dragNodes.dragNodes_nodes < 4) then
		print("DRAG MODEL: Not enough drag nodes [4 Required]")
		M.update = nop
		M.updateGFX = nop
		return
	end
	
	M.update = update
	
	-- 1: Origin; 2: -Y; 3: X; 4: Z
	dragNodeOrigin = dragNodes.dragNodes_nodes[1]
	dragNodeY = dragNodes.dragNodes_nodes[2]
	dragNodeX = dragNodes.dragNodes_nodes[3]
	dragNodeZ = dragNodes.dragNodes_nodes[4]
	
	dragModX = dragNodes.dragModX or 1.25
	dragModZ = dragNodes.dragModZ or 1.5
	
	vehicleArea = dragNodes.vehicleArea or 1
	if vehicleArea < 0 then
		guihooks.message("WARNING: NEGATIVE VEHICLE AREA")
	end
	
	downforceNodesFront = {}
	downforceNodesRear = {}
	
	if v.data.downforceModel == nil or v.data.downforceNodeGroups and next(v.data.downforceNodeGroups) == nil then
		downforceModelEnabled = false
		return
	end
	downforceModelEnabled = true

	--getFactorForDownforceAtKMH(_downforce, _velocity, _airDensity)
	local dfFrontN = v.data.downforceModel.downforceTargetFront or 0
	local dfRearN = v.data.downforceModel.downforceTargetRear or 0
	local targetSpeedKMH = v.data.downforceModel.targetSpeedKMH or 200
	local targetAirDensity = v.data.downforceModel.targetAirDensity or 1.2041

	constantForceFront = v.data.downforceModel.constantForceFront * 9.80665 or 0
	constantForceRear = v.data.downforceModel.constantForceRear * 9.80665 or 0

	--downforceFactorFront = v.data.downforceModel.downforceFrontFactor or 0
	--downforceFactorRear = v.data.downforceModel.downforceRearFactor or 0

	downforceFactorFront = getFactorForDownforceAtKMH(dfFrontN, targetSpeedKMH, targetAirDensity)
	downforceFactorRear = getFactorForDownforceAtKMH(dfRearN, targetSpeedKMH, targetAirDensity)
	
	for _, dfactors in pairs(v.data.downforceNodeGroups) do
		if dfactors.isFront == true then
			table.insert(downforceNodesFront, dfactors)
		else
			table.insert(downforceNodesRear, dfactors)
		end
	end
	
	v.downforceNodesFront = downforceNodesFront
	v.downforceNodesRear = downforceNodesRear
end


-- public interface
M.reset = reset
M.init = init
M.update = nop
M.updateGFX = nop

v.setDragForce = setDragForce
v.getDragForce = getDragForce
v.getVehicleVelocity = getVehicleVelocity
v.setOverrideDrag = setOverrideDrag
v.setOverrideDensity = setOverrideDensity
v.setVehicleArea = setVehicleArea
v.getVehicleArea = getVehicleArea
v.setAirDensity = setAirDensity
v.getAirDensity = getAirDensity
v.setOverrideDensity = setOverrideDensity
v.setDownforceFactorFront = setDownforceFactorFront
v.setDownforceFactorRear = setDownforceFactorRear
v.getFactorForDownforceAtKMH = getFactorForDownforceAtKMH
v.getDownforceModelEnabled = getDownforceModelEnabled
v.setDownforceModelEnabled = setDownforceModelEnabled
v.setForcedDownforce = setForcedDownforce
v.disableAeroCalcs = disableAeroCalcs

return M
