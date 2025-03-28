local M = {}

local manualSpoiler = nil
local spoilerOn = nil

local spoilerRunningMultiple = nil
local spoilerActiveSpeed = nil
local outStep = nil

local function setMode(mode)
	if mode == "auto" then
        manualSpoiler = false
		spoilerOn = true
	elseif mode == "on" then
		manualSpoiler = true
		spoilerOn = true
	elseif mode == "off" then
		manualSpoiler = true
		spoilerOn = false
    end
end

local function manualSpoilerMode()
	-- manualSpoiler = not manualSpoiler
	local valA = manualSpoiler
	local valB = spoilerOn
	-- manualSpoiler = not valA and valB or valA and valB
	-- spoilerOn = not valA and valB or valA and not valB

	manualSpoiler = valB
	spoilerOn = valA ~= valB

	-- manualSpoiler, spoilerOn = spoilerOn, not manualSpoiler

	if manualSpoiler then
		if spoilerOn then
			gui.message({ txt = "Spoiler On" }, 5, "", "")
		else
			gui.message({ txt = "Spoiler Off" }, 5, "", "")
		end
	else
		outStep = math.min(10, outStep)
		gui.message({ txt = "Spoiler Auto" }, 5, "", "")
	end
end

local function updateGFX(dt)
	if (manualSpoiler or (electrics.values.wheelspeed * 3.6 >= spoilerActiveSpeed)) and spoilerOn then
		outStep = math.min(15, outStep + dt * spoilerRunningMultiple)
	else
		outStep = math.max(0, outStep - dt * spoilerRunningMultiple)
	end
	electrics.values.spoiler = outStep

	-- dump(manualSpoiler)
	-- dump(spoilerOn)
end

local function reset()
	manualSpoiler = false
	spoilerOn = true

	outStep = 0
	electrics.values.spoiler = 0
end

local function init(jbeamData)
	manualSpoiler = false
	spoilerOn = true

	spoilerRunningMultiple = jbeamData.spoilerRunningMultiple or 3
	spoilerActiveSpeed = jbeamData.spoilerActiveSpeed or 60
	outStep = 0
	electrics.values.spoiler = 0
end

local function setParameters(parameters)
	setMode(parameters.mode)
end

-- public interface
M.setParameters = setParameters

M.reset = reset
M.init = init
M.updateGFX = updateGFX

M.manualSpoilerMode = manualSpoilerMode

return M
