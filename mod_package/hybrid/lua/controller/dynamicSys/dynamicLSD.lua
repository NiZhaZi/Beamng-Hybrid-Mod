-- dynamicLSD.lua - 2024.1.14 15:54 - LSD control for dynamic system
-- by NZZ
-- version 0.0.5 alpha
-- final edit - 2024.9.24 19:07

local M = {}

local abs = math.abs

local AVtoRPM = 9.549296596425384

local diffs = nil
local frontDiff = nil
local rearDiff = nil
local shaftA = nil
local shaftB = nil
local AV1 = nil
local AV2 = nil

local direct1 = 0
local direct2 = 0

local maxRatio = nil
local minRatio = nil
local maxrpmDifference = nil
local stepping = nil

local frontLockMode = nil
local rearLockMode = nil

local function getRPM(diff)
	AV1 = abs(diff.outputAV1)
	AV2 = abs(diff.outputAV2)

	if AV1 ~= 0 then
		direct1 = diff.outputAV1 / AV1
	else
		direct1 = 1
	end
	if AV2 ~= 0 then
		direct2 = diff.outputAV2 / AV2
	else
		direct2 = 1
	end
	--log("W", "DAWD", "test DAWD" .. 1)
end

local function diffToShaft(diff)
	shaftA = diff.diffTorqueSplitA
	shaftB = diff.diffTorqueSplitB
	--log("W", "DAWD", "test DAWD" .. 2)
end

local function shaftToDiff(diff)
	diff.diffTorqueSplitA = shaftA
	diff.diffTorqueSplitB = shaftB
	--log("W", "DAWD", "test DAWD" .. 3)
end

local function switchLockMode(diff)
	local lockMode
	if diff == "front" then
		if frontDiff then
			if frontDiff.mode ~= "open" and frontDiff.mode ~= "locked" and frontDiff.mode ~= "dually" then
				frontLockMode = not frontLockMode
				if frontLockMode then
					lockMode = "locked"
				else
					lockMode = "unlocked"
				end
			else
				lockMode = false
			end
		else
			lockMode = false
		end
	elseif diff == "rear" then
		if rearDiff then
			if rearDiff.mode ~= "open" and rearDiff.mode ~= "locked" and rearDiff.mode ~= "dually" then
				rearLockMode = not rearLockMode
				if rearLockMode then
					lockMode = "locked"
				else
					lockMode = "unlocked"
				end
			else
				lockMode = false
			end
		else
			lockMode = false
		end
	end
	if lockMode then
		gui.message({ txt = diff .. " differential has " .. lockMode }, 5, "", "")
	else
		gui.message({ txt = "can not find " .. diff .. " differential"}, 5, "", "")
	end
end

local function updateGFX(dt)
	for _, v in ipairs(diffs) do

		if (v == frontDiff and not frontLockMode) or (v == rearDiff and not rearLockMode) then
			getRPM(v)
			diffToShaft(v)

			if abs(AV1 - AV2) * AVtoRPM >= maxrpmDifference then --1打滑
				if shaftA >= minRatio and shaftA <= maxRatio then --2未达到最大分配比例
					if AV1 > AV2 then --3主轴打滑 向副轴分配动力
						shaftA = shaftA - stepping
					elseif AV1 < AV2 then --3副轴打滑 向主轴分配动力
						shaftA = shaftA + stepping
					end
				end
			elseif abs(AV1 - AV2) * AVtoRPM < maxrpmDifference then --1不打滑
				if shaftA ~= 0.5 then --2主轴输出是否等于默认输出
					if shaftA > 0.5 then --3主轴输出大于默认输出 减少主轴输出
						shaftA = shaftA - stepping
					elseif shaftA < 0.5 then --3主轴输出小于默认输出 增加主轴输出
						shaftA = shaftA + stepping
					end
				end
			end

			if shaftA < minRatio then
				shaftA = minRatio
			end
			if shaftA > maxRatio then
				shaftA = maxRatio
			end

			shaftB = 1 - shaftA
			shaftToDiff(v)

			if direct1 ~= direct2 then
				shaftA = 0.50
				shaftB = 0.50
				shaftToDiff(v)
			end
		else
			shaftA = 0.50
			shaftB = 0.50
			shaftToDiff(v)
		end

	end	

end

local function reset()
	shaftA = 0.5
	shaftB = 0.5
	if frontDiff then
		shaftToDiff(frontDiff)
	end
	if rearDiff then
		shaftToDiff(rearDiff)
	end

	frontLockMode = false
	rearLockMode = false
end

local function init(jbeamData)
	local frontDifferentialName = jbeamData.frontDifferentialName or "frontDiff"
	local rearDifferentialName = jbeamData.rearDifferentialName or "rearDiff"
	diffs = {}
	if powertrain.getDevice(frontDifferentialName) then
		frontDiff = powertrain.getDevice(frontDifferentialName)
		table.insert(diffs, frontDiff)
	end
	if powertrain.getDevice(rearDifferentialName) then
		rearDiff = powertrain.getDevice(rearDifferentialName)
		table.insert(diffs, rearDiff)
	end
	
	maxRatio = jbeamData.maxRatio or 0.90
	minRatio = 1 - maxRatio
	maxrpmDifference = jbeamData.maxrpmDifference or 50
	stepping = jbeamData.stepping or 0.01
	
	shaftA = 0.5
	shaftB = 0.5
	if frontDiff then
		shaftToDiff(frontDiff)
	end
	if rearDiff then
		shaftToDiff(rearDiff)
	end

	frontLockMode = false
	rearLockMode = false
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

M.switchLockMode = switchLockMode

return M