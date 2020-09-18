--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==
local version = "Motion lights QA v1.2.090920.3"

if dofile and not hc3_emulator then
    require("fibaro")
    -- hc3_emulator = {startWeb = false, speed = 1}
    require("test_lighting")
    dofile("fibaroapiHC3.lua")
    return
end

__TAG = "QA_MOTION_LIGHTS_" .. (plugin.mainDeviceId or "")
local debugMode = false

local jT = nil
local homeTable = fibaro.getGlobalVariable("HomeTable")
if homeTable then
    jT = json.decode(homeTable)
end

lighting = lighting or {}

local function tableToString(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. tableToString(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

function dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

local function log(dev, ...)
    if debugMode or dev.debugMode then
        dev = dev or {name = "[MAIN]"}
        print(os.date("%H:%M | %B %d, %Y"), dev.name, ...)
    end
end

local function errorlog(str)
    -- fibaro.debug("<font color='red'>" .. str .. "</font>")
    print("ERROR:", str)
end

local function isEmpty(s)
    return s == nil or s == ""
end

function idIsInList(id, list)
    for i = 1, #list do
        if (id == list[i]) then
            return true
        end
    end
    return false
end

--==--==--==--==--==--==--==--==

function split(text, delimiter)
    local list = {}
    local pos = 1
    if string.find("", delimiter, 1) then
        table.insert(list, text)
        return list
    end
    while 1 do
        local first, last = string.find(text, delimiter, pos)
        if first then
            table.insert(list, string.sub(text, pos, first - 1))
            pos = last + 1
        else
            table.insert(list, string.sub(text, pos))
            break
        end
    end
    return list
end

function getPowerExclusionState(dev)
    if dev.exclusion ~= nil then
        for i, n in ipairs(dev.exclusion) do
            local value = fibaro.getValue(n, "value")
            -- print(n, value)
            if value ~= nil then
                if type(value) == "boolean" then
                    if (value) then
                        value = 1
                    else
                        value = 0
                    end
                end
                if (tonumber(value) > 0) then
                    return true
                end
            else
                print("device:", n, "nil")
            end
        end
    end
    return false
end

function getLux(dev)
    local totalLux = 0
    local averigeLux = 0
    if #dev.luxs > 0 then
        for i = 1, #dev.luxs do
            local value = fibaro.getValue(dev.luxs[i], "value")
            if value ~= nil then
                totalLux = totalLux + tonumber(value)
            end
        end
        averigeLux = math.floor(totalLux / #dev.luxs)
    else
        averigeLux = 9999
    end
    return averigeLux
end

function getLastBreach(dev)
    local breach = 0
    if dev.sensors ~= nil then
        for i, n in ipairs(dev.sensors) do
            local nBreach = 0
            if type(n) == "string" then
                -- nBreach = tonumber(fibaro.getGlobalModificationTime(n))
                local value, modified = fibaro.getGlobalVariable(n)
                nBreach = tonumber(modified)
            else
                --nBreach = tonumber(fibaro.getValue(n, "lastBreached"))
                state, nBreach = fibaro.get(n, "value")
                if state ~= nil then
                    if (state) then
                        state = 1
                    else
                        state = 0
                    end
                    if (tonumber(state) > 0) then
                        if dev.door_ignore and fibaro.getType(n) == "com.fibaro.doorSensor" then
                            -- ignore
                        else
                            nBreach = os.time()
                        end
                    else
                        nBreach = tonumber(nBreach)
                    end
                else
                    fibaro.Warning("DEVICE " .. tostring(n) .. " DEAD!")
                    nBreach = 0
                end
            end
            if (nBreach > breach) then
                breach = nBreach
            end
        end
    end
    return breach
end

function getSensorState(dev)
    if dev.sensors ~= nil then
        -- fibaro.debug("====" .. dev.name .. "===")
        for i, n in ipairs(dev.sensors) do
            if type(n) == "string" then
                local state = fibaro.getGlobalVariable(n) -- self:getVariable(name)
                if tonumber(state) > 0 then
                    return 1
                end
            else
                -- print(n);
                local state, lastModification = fibaro.get(n, "value")
                if state then
                    state = 1
                else
                    state = 0
                end
                -- print(state, lastModification)
                if state == nil then
                    print(n, "not found!")
                end
                if
                    dev.door_ignore and fibaro.getType(n) == "com.fibaro.doorSensor" and tonumber(state) == 1 and
                        os.time() - lastModification > 60 * 1
                 then
                    state = 0
                end

                -- print(state)
                if state ~= nil and tonumber(state) > 0 then
                    return 1
                end
            end
        end
    end
    return 0
end

local DimmerDeviceType = {
    "com.fibaro.multilevelSwitch",
    "com.fibaro.FGD212",
    "com.fibaro.FGWD111"
}

local RGBWDeviceType = {
    "com.fibaro.colorController",
    "com.fibaro.philipsHueLight",
    "com.fibaro.FGRGBW442CC",
    "com.fibaro.FGRGBW441M"
}

local cacheTypes = {}

function getDeviceType(deviceId)
    local deviceType = cacheTypes[tostring(deviceId)]
    if deviceType == nil then
        deviceType = fibaro.getType(deviceId)
        cacheTypes[tostring(deviceId)] = deviceType
    end
    if (idIsInList(deviceType, RGBWDeviceType)) then
        return "com.fibaro.colorController"
    elseif (idIsInList(deviceType, DimmerDeviceType)) then
        return "com.fibaro.multilevelSwitch"
    else
        return "com.fibaro.binarySwitch"
    end
end

function setPowerState(dev, value)
    local function hex2rgb(hex)
        local hex = hex:gsub("#", "")
        return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
    end
    if dev.powers == nil then
        dev.powers = {}
    end
    for i, id in ipairs(dev.powers) do
        local lightType = getDeviceType(id)
        if (lightType == "com.fibaro.multilevelSwitch") then
            if type(value) == "string" then
                fibaro.call(id, value)
            else
                fibaro.call(id, "setValue", value)
            end
        elseif lightType == "com.fibaro.binarySwitch" then
            if value > 0 then
                fibaro.call(id, "turnOn")
            else
                fibaro.call(id, "turnOff")
            end
        elseif (lightType == "com.fibaro.colorController") then
            if type(value) == "string" then
                fibaro.call(id, "turnOn")
                local color = split(value, ",")
                local r, g, b, w = unpack(color)
                fibaro.call(id, "setColor", r, g, b, w)
                if #color == 5 then
                    fibaro.call(id, "setBrightness", color[5])
                end
            else
                if value > 0 then
                    fibaro.call(id, "turnOn")
                    fibaro.call(id, "setBrightness", value)
                else
                    fibaro.call(id, "turnOff")
                end
            end
        else
            -- unknown
            if value > 0 then
                fibaro.call(id, "turnOn")
            else
                fibaro.call(id, "turnOff")
            end
        end
    end
end

function getPowerState(dev)
    function getState(power_states)
        for i, state in ipairs(power_states) do
            if (state ~= power_states[1]) then
                return false
            end
        end
        return power_states[1] or false
    end

    function getOnState(power_states)
        for i, state in ipairs(power_states) do
            if (state > 0) then
                return state
            end
        end
        return 0
    end

    local lastDeviceLastModification = 0
    local power_states = {}
    if dev.powers ~= nil then
        for i, id in ipairs(dev.powers) do
            local deviceState, lastModification = fibaro.get(id, "value")
            if deviceState ~= nil then
                if deviceState then
                    if type(deviceState) == "boolean" then
                        deviceState = 1
                    end
                else
                    deviceState = 0
                end
                if lastModification > lastDeviceLastModification then
                    lastDeviceLastModification = lastModification
                end
                deviceState = tonumber(deviceState)
                if deviceState > 0 then
                    local lightType = getDeviceType(id)
                    if lightType == "com.fibaro.binarySwitch" then
                        deviceState = 99
                    end
                end
                table.insert(power_states, deviceState)
            end
        end
        local result = getState(power_states)
        if not result then
            -- log(dev, "Warning: powers are different")
            result = getOnState(power_states)
        end
        return result, lastDeviceLastModification
    else
        return 0, lastDeviceLastModification
    end
end

function checkLux(dev)
    if dev.minLux == nil then
        return true
    end
    if dev.luxs == nil then
        return true
    end
    local lux = getLux(dev)
    -- log(dev, "lux: " .. lux .. " | " .. dev.minLux)
    return lux < dev.minLux, {lux = lux, minLux = dev.minLux, maxLux = dev.maxLux}
end

function between(timestr)
    local dayMap = {["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7}
    local smap = {
        ["Sunset"] = "sunsetHour",
        ["Sunrise"] = "sunriseHour",
        ["Evening"] = "sunsetHour", -- SunsetTwilight
        ["Morning"] = "sunriseHour"
    }

    local function trim(s)
        return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    end

    local function offset(s, o, p)
        if (not (o and p)) or o == "" then
            return s
        end
        local h, m = s:match("(%d+):(%d+)")
        local t = 60 * h + m + (o == "+" and p or -tonumber(p))
        return string.format("%02d:%02d", math.floor(t / 60), t % 60)
    end

    local function sec2hmStr(hms)
        local h, m, s = math.floor(hms / 3600), math.floor((hms % 3600) / 60), hms % 60
        return string.format("%02d:%02d", h, m)
    end

    local function isnull(name, val, action)
        if (val == nil) then
            if (_ENV[name] ~= nil) then
                local result = _ENV[name]()
                if type(result) == "boolean" and result then
                    val = os.date("%H:%M", os.time())
                elseif result then
                    val = result
                else
                    val = ""
                end
            end
        end
        return val
    end

    local function betw(interv)
        local dt, start, stop = os.date("*t"), interv:match("^([%S%a0-9%.%:]+) ?(.*)")
        if not start then
            return false
        end
        stop = stop == "" and start or stop
        local d1, h1, m1 = start:match("^([%S%a%.]-)%.?(%d+):(%d+)$")
        local d2, h2, m2 = stop:match("^([%S%a]-)%.?(%d+):(%d+)$")

        d1 = d1 == "" and (dt.wday == 1 and 7 or dt.wday - 1) or dayMap[d1]
        d2 = d2 == "" and d1 or dayMap[d2]
        local d = dt.wday == 1 and 7 or dt.wday - 1
        if not (d >= d1 and d <= d2) then
            return false
        end
        m1, m2, t = h1 * 60 + m1, h2 * 60 + m2, dt.hour * 60 + dt.min
        if (m1 <= m2) then
            return m1 <= t and t <= m2 -- 01:00-02:00
        else
            return m1 <= t or t <= m2 -- 23:00-21:00
        end
    end
    timestr =
        timestr:gsub(
        "$(%w+)([%+%-]?)(%d*)",
        function(s, o, p)
            return offset(isnull(s, smap[s] and fibaro.getValue(1, smap[s]) or fibaro.getGlobalVariable(s), o, p))
        end
    )
    for _, interv in ipairs(split(timestr, ",")) do
        if betw(trim(string.gsub(interv, "%.%.", " "))) then
            return true
        end
    end
    return false
end

function checkDevice(dev)
    local function trim(s)
        return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    end

    function tableClone(t)
        local t2 = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                t2[k] = tableClone(v)
            else
                t2[k] = v
            end
        end
        return t2
    end

    if dev.times == nil then
        return true, dev
    end

    if type(dev.times) == "string" then
        if between(dev.times) then
            return true, dev
        end
    elseif type(dev.times) == "table" then
        for k, v in pairs(dev.times) do
            local period = type(k) == "string" and k or v
            if type(period) == "function" then
                period = "00:00..24:00"
            end
            if between(period) then
                if type(v) == "table" then
                    -- override
                    local override = tableClone(dev)
                    for k0, v0 in pairs(v) do
                        override[k0] = v0
                    end
                    for _, v in ipairs(v) do
                        if type(v) == "boolean" then
                            return v, override
                        elseif type(v) == "function" then
                            return v(), override
                        end
                    end
                    return true, override
                else
                    local override = tableClone(dev)
                    if type(v) == "boolean" then
                        return v, override
                    elseif type(v) == "function" then
                        return v(), override
                    end
                    override.level = type(v) == "number" and v or 99
                    return true, override
                end
            end
        end
    end

    return false, dev
end

function getGlobalOverride(dev)
    if dev.override then
        local value = fibaro.getGlobalVariable(dev.override)
        if value then
            return value
        end
    end
    return "AUTO"
end

function checkMotion(dev)
    dev.power_state = dev.power_state or 0
    dev.sensor_state = dev.sensor_state or 0
    local gOverride = getGlobalOverride(dev)
    local sensor_state = getSensorState(dev)
    if sensor_state > 0 then -- is breached!
        if (dev.sensor_state == 0) then
            log(dev, "Sensor breached")
            dev.sensor_state = 1

            local power_state, power_state_modification = getPowerState(dev)
            --  update state for manual devices...
            if dev.manual then
                dev.power_state = power_state
                return
            end
            if power_state == 0 then -- device is off now
                if (dev.power_state == 0) then -- is turned off by me
                    local isLighting, params = checkDevice(dev)
                    if isLighting then
                        local isLux, debugInfo = checkLux(params)
                        --log(dev, "is Lux: " .. tostring(isLux))
                        if isLux then
                            local exclusion = getPowerExclusionState(dev)
                            if not exclusion then
                                if (gOverride ~= "OFF") then
                                    local level = params.level or 99
                                    log(dev, "[on" .. " : " .. level .. "]")
                                    dev.power_state = 1
                                    setPowerState(dev, level)
                                else
                                    log(dev, "[lighting `on` ignored by global override]")
                                end
                            else
                                log(dev, "[lighting `on` ignored by exclusions devices]")
                            end
                        else
                            log(dev, "[is not dark for lighting]", debugInfo.lux .. "/" .. debugInfo.minLux)
                        end
                    else
                        log(dev, "[is not time for lighting]")
                    end
                end
            else
                local isLighting, params = checkDevice(dev)
                local level = params.level or 99
                if dev.power_state == 0 or dev.power_state == dev.levelOff or dev.power_state < level then -- device turned on and not by me
                    log(dev, "[was [on] manualy]")
                    setPowerState(dev, level)
                    log(dev, "[set run level to " .. level .. "]")
                end
            end
        else
            -- motions is still here but, we should re-check other conditions time to time
            local power_state, power_state_modification = getPowerState(dev)
            -- only if device if off
            if power_state == 0 then
                if ((os.time() - power_state_modification) > 60 * 1) then -- let chance get away
                    -- log(dev, power_state, power_state_modification)
                    local isLighting, params = checkDevice(dev)
                    if isLighting then
                        local isLux = checkLux(params)
                        if isLux then
                            -- do reCheck
                            dev.sensor_state = 0
                        end
                    end
                end
            else
                if dev.power_state == 0 then
                else
                    local isLighting, params = checkDevice(dev)
                    if not isLighting then
                        log(dev, "[off by time]")
                        dev.power_state = 0
                        setPowerState(dev, 0)
                    end
                    local isLux, debugInfo = checkLux(params)
                    if not isLux then
                        if debugInfo.lux >= (debugInfo.maxLux or 1) then
                            log(dev, "[off by lux]")
                            dev.power_state = 0
                            setPowerState(dev, 0)
                        end
                    end
                end
            end
        end
        -- check lost?
        if dev.check_lost then
            -- is lost>
            if ((os.time() - getLastBreach(dev)) > 60 * 60) then -- is lost?
                log(dev, "[off by lost]")
                dev.power_state = params.levelOff or 0
                setPowerState(dev, params.levelOff or 0)
            end
        end
    else
        if (dev.sensor_state == 1) then -- safe
            log(dev, "Sensor safe")
            dev.sensor_state = 0
        end

        local override = getGlobalOverride(dev)
        if override == "OFF" then
            return
        end

        local power_state, power_state_modification = getPowerState(dev)
        if power_state > 0 then -- if device is on now
            local _, params = checkDevice(dev)

            local exclusion = getPowerExclusionState(dev)
            if exclusion then
                log(dev, "[off by exclusion]")
                dev.power_state = 0
                setPowerState(dev, 0)
            end

            if dev.power_state > 0 then -- it's me
                local timeout = params.timeout or 60
                if timeout > 0 then
                    if getSensorState(dev) > 0 then -- is breached!
                        -- nothing todo
                    else
                        if power_state == (params.levelOff or 0) then
                            -- standby mode
                        else
                            if ((os.time() - getLastBreach(dev)) >= timeout) then -- is timeout?
                                log(dev, "[off by timeout]")
                                dev.power_state = params.levelOff or 0
                                setPowerState(dev, params.levelOff or 0)
                            end
                        end
                    end
                else
                    -- todo?!
                end
            else -- is turned on not by me
                params.timeout = params.timeout or 60
                local timeout = params.timeout_manual or params.timeout
                if timeout > 0 then
                    if (os.time() - power_state_modification >= timeout) then
                        -- double check!
                        if ((os.time() - getLastBreach(dev)) >= timeout) then
                            if power_state == (params.levelOff or 0) then
                                -- standby mode
                            else
                                log(dev, "[off by timeout (was [on] manually)]")
                                dev.power_state = params.levelOff or 0
                                setPowerState(dev, params.levelOff or 0)
                            end
                        end
                    end
                else
                    -- todo?!
                end
            end
        else
            if dev.power_state > 0 then
                log(dev, "[was [off] manualy]")
                dev.power_state = 0
            end
        end
    end
end

function QuickApp:recodeTable(tbl)
    if jT and tbl then
        for i = 1, #tbl do
            local item = tbl[i]
            if type(item) ~= "number" then
                local id = jT[item]
                if id then
                    tbl[i] = id
                else
                    local isGlobal = fibaro.getGlobalVariable(item)
                    if isGlobal == nil then
                        error("Uknown device: " .. tostring(item))
                    end
                end
            end
        end
    end
    return tbl
end

function QuickApp:startup()
    local rules = 0
    for k, dev in pairs(lighting) do
        dev.sensors = self:recodeTable(dev.sensors)
        dev.luxs = self:recodeTable(dev.luxs)
        dev.exclusion = self:recodeTable(dev.exclusion)
        dev.powers = self:recodeTable(dev.powers)

        local status, res =
            xpcall(
            function()
                checkMotion(dev)
            end,
            function(err)
                return err
            end
        )
        if not status then
            errorlog(dev.name .. " ERR: " .. res)
            return
        end

        log(dev.name, noError)
        rules = rules + 1
    end
    print(os.date("%H:%M | %B %d, %Y"), "loaded " .. tostring(rules) .. " lighting rules")

    self:updateProperty("log", "started...")
    print(os.date("%H:%M | %B %d, %Y"), "started...")

    -- while true do
    --     for k, dev in pairs(lighting) do
    --         checkMotion(dev)
    --     end
    --     fibaro.sleep(1000)
    -- end

    self.looper =
        setInterval(
        function()
            for k, dev in pairs(lighting) do
                checkMotion(dev)
            end
        end,
        1000
    )
end

function QuickApp:setLighting(lighting)
    if self.looper then
        clearInterval(self.looper)
        fibaro.sleep(1000)
    end
    self:debug("Lighting realoading...")
    lighting = lighting
    self:startup()
end

function QuickApp:onInit()
    self:debug("starting " .. version .. "...")
    -- self:updateProperty("deviceIcon", 1041)
    self:run()
end

function QuickApp:run()
    self:startup()
end
