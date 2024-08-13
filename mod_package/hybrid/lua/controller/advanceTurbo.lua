local M = {}

local psiToPascal = 6894.757293178

local turbocharger = nil
local turbo = nil

local rawPressureCurve = nil
local overPressureCurve = nil

local mode = nil

local function updateGFX(dt)
    --if turbocharger ~= nil then
    --    log("W", "Supercharger", "Screw type supercharger needs at least 3 lobes")
    --end

    if mode == "raw" and rawPressureCurve then
        turbocharger.turbo.turboPressureCurve = rawPressureCurve
    elseif mode == "over" and overPressureCurve then
        turbocharger.turbo.turboPressureCurve = overPressureCurve
    end
end

local function init(jbeamData)
    --turbocharger = powertrain.getDevice("turbocharger")
    mode = "raw"

    local turbochargerModuleName = "powertrain/turbocharger"
  	turbocharger = require(turbochargerModuleName)
    turbo = turbocharger.turbo

    rawPressureCurve = {}
    if turbo.turboPressureCurve then
        rawPressureCurve = turbo.turboPressureCurve
    end

    local overPSIcount = #jbeamData.overPSI
    local tpoints = table.new(overPSIcount, 0)
    if jbeamData.overPSI then
        for i = 1, overPSIcount do
            local point = jbeamData.overPSI[i]
            tpoints[i] = {point[1], point[2]}
        end
    end
    overPressureCurve = createCurve(tpoints, true)

end


M.updateGFX = updateGFX
M.init = init

return M