-- dctIdle.lua - 2025.2.9 23:57 - switchable idle function for DCT gearboxs
-- by NZZ
-- version 0.0.1 alpha
-- final edit - 2025.2.9 23:57

local M = {}

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384

local engine = nil
local gearbox = nil
local controlLogicModule = nil

local idleAVS = nil
local idleAVT = nil
local nIdleAVS = nil
local nIdleAVT = nil

local originalAVS = nil
local originalAVT = nil

local defaultMode = nil
local mode = nil

local function setRPM(AVT, AVS)
  controlLogicModule.clutchHandling.clutchLaunchTargetAV = AVT
  controlLogicModule.clutchHandling.clutchLaunchStartAV = AVS
end

local function switchMode(sel, noti)
  local AVT
  local AVS

  if sel == 1 then
    AVT = idleAVT
    AVS = idleAVS
    setRPM(AVT, AVS)
    if noti then
      gui.message({ txt = "idle mode on" }, 5, "", "")
    end
  elseif sel == 0 then
    AVT = nIdleAVT
    AVS = nIdleAVS
    setRPM(AVT, AVS)
    if noti then
      gui.message({ txt = "idle mode off" }, 5, "", "")
    end
  else
    switchMode(-1 * mode + 1, true)
  end

  if sel == 1 or sel == 0 then
    mode = sel
  end
  
  log("D", "", mode)

end

local function init(jbeamData)
  
  engine = powertrain.getDevice("mainEngine")
  gearbox = powertrain.getDevice("gearbox")
  local gearboxType = gearbox.type

  if gearboxType == "dctGearbox" then
    -- local controlLogicModuleDirectory = "controller/vehicleController/shiftLogic/"
    local controlLogicModuleDirectory = "controller/"
    local controlLogicModulePath = controlLogicModuleDirectory .. "shiftLogic-dctGearboxAdv"
    if not FS:fileExists("lua/vehicle/" .. controlLogicModulePath .. ".lua") then
      local controlLogicModuleDirectoryLegacy = "controller/shiftLogic-" .. "dctGearboxAdv"
    end
    controlLogicModule = require(controlLogicModulePath)
  end

end

local function initSecondStage(jbeamData)
  -- log("D", "", (controlLogicModule.clutchHandling.clutchLaunchStartAV / 0.5 + engine.idleAV) * avToRPM)
  -- log("D", "", controlLogicModule.clutchHandling.clutchLaunchTargetAV / 0.5 * avToRPM)

  originalAVS = controlLogicModule.clutchHandling.clutchLaunchStartAV
  originalAVT = controlLogicModule.clutchHandling.clutchLaunchTargetAV

  -- local originalClutchLaunchTargetAV = originalAVT / 0.5
  -- local originalclutchLaunchStartAV = originalAVS / 0.5 + engine.idleAV

  if originalAVS >= 0 then
    idleAVS = ((engine.idleAV * avToRPM - 250) * rpmToAV - engine.idleAV) * 0.5
    idleAVT = (engine.idleAV * avToRPM + 250) * rpmToAV * 0.5
    nIdleAVS = originalAVS
    nIdleAVT = originalAVT
  else
    idleAVS = originalAVS
    idleAVT = originalAVT
    nIdleAVS = ((engine.idleAV * avToRPM + 250) * rpmToAV - engine.idleAV) * 0.5
    nIdleAVT = (engine.idleAV * avToRPM + 750) * rpmToAV * 0.5
  end

  defaultMode = jbeamData.defaultMode or "idle"
  if defaultMode == "idle" then
    mode = 1
    switchMode(1, false)
  else
    mode = 0
    switchMode(0, false)
  end
end

local function reset()
  if defaultMode == "idle" then
    mode = 1
    switchMode(1, false)
  else
    mode = 0
    switchMode(0, false)
  end
end

local function updateGFX(dt)
  -- log("D", "", (controlLogicModule.clutchHandling.clutchLaunchStartAV / 0.5 + engine.idleAV) * avToRPM)
  -- log("D", "", controlLogicModule.clutchHandling.clutchLaunchTargetAV / 0.5 * avToRPM)
  -- log("D", "", (originalAVS / 0.5 + engine.idleAV) * avToRPM)
  -- log("D", "", originalAVT / 0.5 * avToRPM)
end

M.init = init
M.initSecondStage = initSecondStage
M.reset = reset
M.updateGFX = updateGFX

M.switchMode = switchMode
M.setRPM = setRPM

return M
