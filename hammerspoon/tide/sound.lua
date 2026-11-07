-- The settings window's Sound page (SPEC.md §15), as tide's (tide SPEC.md
-- §16): the output in use, its volume and mute, and the outputs to pick
-- from; then the input in use, its, and the inputs. This is the part with
-- no Hammerspoon in it: what the page shows, and what its messages do.
-- sound_hs.lua reads and sets the devices.

local volume = require("tide.volume")

local M = {}

-- One side as the page shows it, from volume.state's reading: the device
-- in use's { name, volume, muted, can_mute }, whether the slider sets the
-- volume as it moves (`live`), and every device's { uid, name, current }.
local function side(audio, devices, current, over_ddc)
    local s = volume.state(audio, devices, current, over_ddc)
    return {
        name = s.name,
        volume = s.volume,
        muted = s.muted,
        can_mute = s.can_mute,
        live = s.live,
        devices = s.outputs,
    }
end

-- What the page shows: each side's device in use, read as `{ name, volume,
-- muted }` (volume nil with no control), each device's `{ uid, name }`, and
-- the uid in use. An output over DDC is set once the slider's let go.
function M.state(output, input)
    output, input = output or {}, input or {}
    return {
        output = side(output.audio, output.devices, output.current, output.over_ddc),
        input = side(input.audio, input.devices, input.current, false),
    }
end

-- Does what a message from the page asks, through `act`: set_volume(v),
-- set_mute(on) and use(uid) for the output, set_input_volume(v),
-- set_input_mute(on) and use_input(uid) for the input. Returns whether it
-- was one of the Sound page's.
function M.handle(body, act)
    if type(body) ~= "table" then
        return false
    end
    local function level(v)
        v = tonumber(v)
        return v and math.max(0, math.min(100, math.floor(v + 0.5)))
    end
    if body.soundVolume ~= nil then
        local v = level(body.soundVolume)
        if v then
            act.set_volume(v)
        end
    elseif body.soundMute ~= nil then
        act.set_mute(body.soundMute == true)
    elseif type(body.soundOutput) == "string" then
        act.use(body.soundOutput)
    elseif body.inputVolume ~= nil then
        local v = level(body.inputVolume)
        if v then
            act.set_input_volume(v)
        end
    elseif body.inputMute ~= nil then
        act.set_input_mute(body.inputMute == true)
    elseif type(body.soundInput) == "string" then
        act.use_input(body.soundInput)
    else
        return false
    end
    return true
end

return M
