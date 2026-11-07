-- The settings window's Sound page (sound.lua): what it shows of the
-- output and input in use and the devices, and what its messages do.

local t = require("t")
local sound = require("tide.sound")

t.test("each side shows its device in use, its level and the devices, sorted", function()
    local s = sound.state({
        audio = { name = "MacBook Speakers", volume = 62.6, muted = false },
        devices = { { uid = "b", name = "Studio Display" }, { uid = "a", name = "MacBook Speakers" } },
        current = "a",
    }, {
        audio = { name = "MacBook Microphone", volume = 75, muted = true },
        devices = { { uid = "m", name = "MacBook Microphone" } },
        current = "m",
    })
    t.eq(s.output, {
        name = "MacBook Speakers", volume = 63, muted = false, can_mute = true, live = true,
        devices = {
            { uid = "a", name = "MacBook Speakers", current = true },
            { uid = "b", name = "Studio Display", current = false },
        },
    })
    t.eq(s.input.volume, 75)
    t.eq(s.input.muted, true)
    t.eq(s.input.devices, { { uid = "m", name = "MacBook Microphone", current = true } })
end)

t.test("a monitor over DDC is set once the slider's let go; one with no control has no level", function()
    local s = sound.state({ audio = { name = "Monitor", volume = 30 }, devices = {}, current = "x", over_ddc = true },
        { audio = { name = "Line in" }, devices = {} })
    t.eq(s.output.live, false)
    t.eq(s.input.volume, nil)
    t.eq(s.input.can_mute, false)
end)

t.test("no devices at all shows nothing in use", function()
    local s = sound.state(nil, nil)
    t.eq(s.output.devices, {})
    t.eq(s.output.name, nil)
end)

t.test("each control does what it says, a level kept between 0 and 100", function()
    local did = {}
    local function rec(name)
        return function(v)
            did[#did + 1] = { name, v }
        end
    end
    local act = {
        set_volume = rec("volume"), set_mute = rec("mute"), use = rec("use"),
        set_input_volume = rec("input volume"), set_input_mute = rec("input mute"), use_input = rec("use input"),
    }
    for _, body in ipairs({
        { soundVolume = 140 }, { soundMute = true }, { soundOutput = "b" },
        { inputVolume = 12.4 }, { inputMute = false }, { soundInput = "m" },
    }) do
        t.eq(sound.handle(body, act), true)
    end
    t.eq(did, {
        { "volume", 100 }, { "mute", true }, { "use", "b" },
        { "input volume", 12 }, { "input mute", false }, { "use input", "m" },
    })
    t.eq(sound.handle({ writeClipboard = "{}" }, act), false, "another page's")
    t.eq(sound.handle({ soundVolume = "loud" }, act), true, "the page's, though there's no level in it")
    t.eq(#did, 6)
end)

t.done("sound")
