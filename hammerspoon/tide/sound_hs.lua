-- The Sound page's devices (sound.lua), through hs.audiodevice. The output
-- goes through the bar's volume popover's operations when the bar is on,
-- so a monitor's volume over DDC is the one set, as the bar's keys and
-- popover set it; and macOS's own otherwise.

local sound = require("tide.sound")

local M = {}

-- `tide` is the started tide module: its bar, if it's on, and adapter.
function M.new(tide)
    local self = {}
    local log = tide.adapter.log

    local function devices(list)
        local out = {}
        for _, d in ipairs(list or {}) do
            out[#out + 1] = { uid = d:uid(), name = d:name() }
        end
        return out
    end

    -- The bar's operations for the output, or macOS's own.
    local function output_ops()
        return tide.bar and tide.bar.output_ops or nil
    end

    function self.state()
        local ops = output_ops()
        local output
        if ops then
            output = ops.reading()
        else
            local dev = hs.audiodevice.defaultOutputDevice()
            output = {
                audio = dev and { name = dev:name(), volume = dev:outputVolume(), muted = dev:outputMuted() },
                devices = devices(hs.audiodevice.allOutputDevices()),
                current = dev and dev:uid(),
            }
        end
        local dev = hs.audiodevice.defaultInputDevice()
        local input = {
            audio = dev and { name = dev:name(), volume = dev:inputVolume(), muted = dev:inputMuted() },
            devices = devices(hs.audiodevice.allInputDevices()),
            current = dev and dev:uid(),
        }
        return sound.state(output, input)
    end

    -- What the page's controls change. Each says in the log when macOS
    -- refuses.
    local function failed(what, dev)
        log("sound: " .. what .. " failed on " .. tostring(dev and dev:name()))
    end
    self.act = {
        set_volume = function(v)
            local ops = output_ops()
            if ops then
                return ops.set_volume(v)
            end
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev and dev:outputVolume() ~= nil and not dev:setOutputVolume(v) then
                failed("setOutputVolume", dev)
            end
        end,
        set_mute = function(on)
            local ops = output_ops()
            if ops then
                return ops.set_mute(on)
            end
            local dev = hs.audiodevice.defaultOutputDevice()
            if dev and not dev:setOutputMuted(on) then
                failed("setOutputMuted", dev)
            end
        end,
        use = function(uid)
            local ops = output_ops()
            if ops then
                return ops.use(uid)
            end
            local dev = hs.audiodevice.findDeviceByUID(uid)
            if not dev or not dev:setDefaultOutputDevice() then
                log("sound: couldn't switch the output to " .. tostring(dev and dev:name() or uid))
            end
        end,
        set_input_volume = function(v)
            local dev = hs.audiodevice.defaultInputDevice()
            if dev and dev:inputVolume() ~= nil and not dev:setInputVolume(v) then
                failed("setInputVolume", dev)
            end
        end,
        set_input_mute = function(on)
            local dev = hs.audiodevice.defaultInputDevice()
            if dev and not dev:setInputMuted(on) then
                failed("setInputMuted", dev)
            end
        end,
        use_input = function(uid)
            local dev = hs.audiodevice.findDeviceByUID(uid)
            if not dev or not dev:setDefaultInputDevice() then
                log("sound: couldn't switch the input to " .. tostring(dev and dev:name() or uid))
            end
        end,
    }

    -- A message from the settings page, if it's one of the Sound page's.
    function self.handle(body)
        return sound.handle(body, self.act)
    end

    return self
end

return M
