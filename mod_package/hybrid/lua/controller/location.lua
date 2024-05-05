local M = {}

local location = {
    x = 0,
    y = 0,
    z = 0,
    xsymbol = 1,
    ysymbol = 1,
    zsymbol = 1,
}

local function vecTonumber(vec)
    location.x = 0
    location.y = 0
    location.z = 0
    location.xsymbol = 1
    location.ysymbol = 1
    location.zsymbol = 1
    local axe = 'v'
    local symbol = 'xsymbol'
    local numType = 'int'
    local numBit = 10
    for char in string.gmatch(vec, ".") do
        if axe == 'v' then
            if tonumber(char) == 3 then
                axe = 'x'
            end
        elseif axe == 'x' then
            if tonumber(char) and numType == 'int' then
                location.x = location.x * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.x = location.x + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.xsymbol = -1
            elseif char == ',' then
                location.x = location.x * location.xsymbol
                axe = 'y'
                numType = 'int'
                numBit = 10
            end
        elseif axe == 'y' then
            if tonumber(char) and numType == 'int' then
                location.y = location.y * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.y = location.y + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.ysymbol = -1
            elseif char == ',' then
                location.y = location.y * location.ysymbol
                axe = 'z'
                numType = 'int'
                numBit = 10
            end
        elseif axe == 'z' then
            if tonumber(char) and numType == 'int' then
                location.z = location.z * 10 + tonumber(char)
            elseif tonumber(char) and numType == 'dec' then
                location.z = location.z + tonumber(char) / numBit
                numBit = numBit * 10
            elseif char == '.' then
                numType = 'dec'
            elseif char == '-' then
                location.zsymbol = -1
            elseif char == ')' then
                location.z = location.z * location.zsymbol
            end
        end
    end
end

local function updateGFX(dt)
    local rot = obj:getPosition()
    local loc = tostring(rot)
    vecTonumber(loc)

    --local accXSmooth = electrics.values.accXSmooth
    --local accYSmooth = electrics.values.accYSmooth
    --local accZSmooth = electrics.values.accZSmooth

    --log("", "x", "    " .. location.x)
    --log("", "y", "    " .. location.y)
    --log("", "z", "    " .. location.z)
    --log("", "vec", "    " .. loc)
end

local function init()
end

M.location = location

M.updateGFX = updateGFX
M.init = init

return M