-- dynamicAWD.lua - 2024.3.12 12:38 - center differential control for dynamic system
-- by NZZ
-- version 0.0.8 alpha
-- final edit - 2024.3.12 12:38

local M = {}

local abs = math.abs
local floor = math.floor

local AVtoRPM = 9.549296596425384

local mainShaft = nil
local subShaft = nil
local mainAV = nil
local subAV = nil

local direct1 = 0
local direct2 = 0
local maxSim = nil

local dynamicDiff = nil

local mainOutputNum = nil

local defaultMainOutput = nil
local defaultSubOutput = nil
local minMainOutput = nil
local maxMainOutput = nil
local minSubOutput = nil
local maxSubOutput = nil

local variableOutputRatio = nil
local forceOutputRatio = nil
local forceOutputMode = nil
local mainForceNum = nil
local rearMaxRatio = nil
local rearMinRatio = nil

local maxrpmDifference = nil
local stepping = nil

local function getRPM()
	if mainOutputNum == 1 then
		mainAV = abs(dynamicDiff.outputAV1)
		subAV = abs(dynamicDiff.outputAV2)

		if mainAV ~= 0 then
			direct1 = dynamicDiff.outputAV1 / mainAV
		else
			direct1 = 1
		end
		if subAV ~= 0 then
			direct2 = dynamicDiff.outputAV2 / subAV
		else
			direct2 = 1
		end
	elseif mainOutputNum == 2 then
		mainAV = abs(dynamicDiff.outputAV2)
		subAV = abs(dynamicDiff.outputAV1)

		if mainAV ~= 0 then
			direct1 = dynamicDiff.outputAV2 / mainAV
		else
			direct1 = 1
		end
		if subAV ~= 0 then
			direct2 = dynamicDiff.outputAV1 / subAV
		else
			direct2 = 1
		end
	end
	--log("W", "DAWD", "test DAWD" .. 1)
end

local function diffToShaft()
	if mainOutputNum == 1 then
		mainShaft = dynamicDiff.diffTorqueSplitA
		subShaft = dynamicDiff.diffTorqueSplitB
	elseif mainOutputNum == 2 then
		mainShaft = dynamicDiff.diffTorqueSplitB
		subShaft = dynamicDiff.diffTorqueSplitA
	end
	--log("W", "DAWD", "test DAWD" .. 2)
end

local function shaftToDiff()
	if mainOutputNum == 1 then
		dynamicDiff.diffTorqueSplitA = mainShaft
		dynamicDiff.diffTorqueSplitB = subShaft
	elseif mainOutputNum == 2 then
		dynamicDiff.diffTorqueSplitB = mainShaft
		dynamicDiff.diffTorqueSplitA = subShaft
	end
	--log("W", "DAWD", "test DAWD" .. 3)
end

local function switchForceOutputMode()
	if forceOutputMode == "off" then
		forceOutputMode = "on"
		gui.message({ txt = "Force Output Mode On" }, 5, "", "")
	elseif forceOutputMode == "on" then
		forceOutputMode = "off"
		gui.message({ txt = "Force Output Mode Off" }, 5, "", "")
	end
end

local function increaseMainOurtput()
	if variableOutputRatio < rearMaxRatio then
		variableOutputRatio = variableOutputRatio + 0.1
		--gui.message({ txt = "Rear output increased" }, 5, "", "")
	else
		--gui.message({ txt = "Rear output max" }, 5, "", "")
	end

	if variableOutputRatio > rearMaxRatio then
		variableOutputRatio = rearMaxRatio
	end

	if floor(variableOutputRatio * 100) % 10 > 0 then
		variableOutputRatio = variableOutputRatio + (10 - (variableOutputRatio * 100 % 10)) / 100
	end

	local variable = floor(variableOutputRatio * 100)
	gui.message( "Rear output increased to " ..  variable .. "%" , 5, "")

	if forceOutputMode == "off" then
		forceOutputMode = "on"
		--gui.message({ txt = "Force Output Mode On" }, 5, "", "")
	end
end

local function decreaseMainOurtput()
	if variableOutputRatio > rearMinRatio then
		variableOutputRatio = variableOutputRatio - 0.1
		--gui.message({ txt = "Rear output decreased" }, 5, "", "")
	else
		--gui.message({ txt = "Rear output min" }, 5, "", "")
	end

	if variableOutputRatio < rearMinRatio then
		variableOutputRatio = rearMinRatio
	end

	if floor(variableOutputRatio * 100) % 10 > 0 then
		variableOutputRatio = variableOutputRatio + (10 - (variableOutputRatio * 100 % 10)) / 100
	end

	local variable = floor(variableOutputRatio * 100)
	gui.message( "Rear output decreased to " ..  variable .. "%" , 5, "")

	if forceOutputMode == "off" then
		forceOutputMode = "on"
		--gui.message({ txt = "Force Output Mode On" }, 5, "", "")
	end
end

local function resetVariableOutputRatio()
	variableOutputRatio = forceOutputRatio
	gui.message({ txt = "Force Output Mode Reset" }, 5, "", "")
end

local function updateGFX(dt)
	getRPM()
	diffToShaft()

	if forceOutputMode == "off" then
		if abs(mainAV - subAV) * AVtoRPM >= maxrpmDifference then --1打滑
			if mainShaft >= minMainOutput and mainShaft <= maxMainOutput then --2未达到最大分配比例
				if mainAV > subAV then --3主轴打滑 向副轴分配动力
					mainShaft = mainShaft - stepping
				elseif mainAV < subAV then --3副轴打滑 向主轴分配动力
					mainShaft = mainShaft + stepping
				end
			end
		elseif abs(mainAV - subAV) * AVtoRPM < maxrpmDifference then --1不打滑
			if mainShaft ~= defaultMainOutput then --2主轴输出是否等于默认输出
				if mainShaft > defaultMainOutput then --3主轴输出大于默认输出 减少主轴输出
					mainShaft = mainShaft - stepping
				elseif mainShaft < defaultMainOutput then --3主轴输出小于默认输出 增加主轴输出
					mainShaft = mainShaft + stepping
				end
			end
		end

		--log("W", "DAWD", "test DAWD difference   " .. abs(mainAV - subAV) * AVtoRPM)
		--log("W", "DAWD", "test DAWD mian shaft" .. mainShaft)

		--过冲保护
		if mainShaft < minMainOutput then
			mainShaft = minMainOutput
		end
		if mainShaft > maxMainOutput then
			mainShaft = maxMainOutput
		end

		--反转保护
		if abs(dynamicDiff.outputAV1) > 0.01 and abs(dynamicDiff.outputAV2) > 0.01 then
			if direct1 ~= direct2 then
				mainShaft = maxSim
			end
		end
	elseif forceOutputMode == "on" then
		if mainForceNum == 1 then
			mainShaft = variableOutputRatio
		elseif mainForceNum == 2 then
			mainShaft = 1 - variableOutputRatio
		end
	end

	subShaft = 1 - mainShaft
	shaftToDiff()

	--log("I", "forceOutputMode", "   " .. dynamicDiff.diffTorqueSplitA)

end

local function reset(jbeamData)
	mainShaft = defaultMainOutput
	subShaft = 1 - mainShaft
	shaftToDiff()

	forceOutputMode = jbeamData.forceOutputMode or "off"
	variableOutputRatio = forceOutputRatio

end

local function init(jbeamData)
	local diffName = jbeamData.diffName
	dynamicDiff = powertrain.getDevice(diffName)

	maxrpmDifference = jbeamData.maxrpmDifference or 50
	stepping = jbeamData.stepping or 0.01
	
	mainOutputNum = jbeamData.mainOutputNum or 1

	defaultMainOutput = jbeamData.defaultMainOutput or 1.00
	defaultSubOutput = 1 - defaultMainOutput

	minMainOutput = jbeamData.minMainOutput or 0.50
	maxMainOutput = jbeamData.maxMainOutput or 1.00

	if mainOutputNum == 1 then
		rearMaxRatio = maxMainOutput
		rearMinRatio = minMainOutput
	elseif mainOutputNum == 2 then
		rearMaxRatio = 1 - minMainOutput
		rearMinRatio = 1 - maxMainOutput
	end

	if maxMainOutput < defaultMainOutput then
		maxMainOutput = defaultMainOutput
	end
	if minMainOutput > defaultMainOutput then
		minMainOutput = defaultMainOutput
	end

	minSubOutput = 1 - maxMainOutput
	maxSubOutput = 1 - minMainOutput

	mainShaft = defaultMainOutput
	subShaft = 1 - mainShaft
	shaftToDiff()

	if minMainOutput > 0.5 then
		maxSim = minMainOutput
	else
		maxSim = 0.5
	end

	if jbeamData.forceOutputNum == mainOutputNum then
		mainForceNum = 1
	else
		mainForceNum = 2
	end

	forceOutputRatio = jbeamData.forceOutputRatio
	variableOutputRatio = forceOutputRatio
	forceOutputMode = jbeamData.forceOutputMode or "off"
end

M.switchForceOutputMode = switchForceOutputMode
M.increaseMainOurtput = increaseMainOurtput
M.decreaseMainOurtput = decreaseMainOurtput
M.resetVariableOutputRatio = resetVariableOutputRatio

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M