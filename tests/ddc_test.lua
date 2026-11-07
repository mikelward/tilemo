local t = require("t")
local ddc = require("tide.ddc")
local bar = require("tide.bar")

local LG = "1E6D5B77-0000-0000-0B1E-0104B53C2278"
local DELL = "10ACB8A0-0000-0000-1419-0104A2435078"
local SCREENS = {
    { uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230", name = "Built-in Retina Display" },
    { uuid = LG, name = "LG HDR 4K" },
}

t.test("m1ddc comes first, then ddcctl, where Homebrew puts them", function()
    local have = {}
    local exists = function(p)
        return have[p] == true
    end
    t.eq(ddc.find(exists), nil)
    have["/usr/local/bin/ddcctl"] = true
    t.eq(ddc.find(exists), { name = "ddcctl", path = "/usr/local/bin/ddcctl" })
    have["/opt/homebrew/bin/m1ddc"] = true
    t.eq(ddc.find(exists), { name = "m1ddc", path = "/opt/homebrew/bin/m1ddc" },
        "ddcctl can't reach displays on Apple silicon")
end)

t.test("an output plays through the display named as it is, else the only external one", function()
    t.eq(ddc.screen_for("LG HDR 4K", SCREENS).uuid, LG)
    t.eq(ddc.screen_for("lg hdr 4k ", SCREENS).uuid, LG, "ignoring case and spaces")
    t.eq(ddc.screen_for("HDMI", SCREENS).uuid, LG, "the only display that isn't built in")
    local two = { SCREENS[2], { uuid = DELL, name = "DELL U2720Q" } }
    t.eq(ddc.screen_for("HDMI", two), nil, "two external displays and no name to go by")
    t.eq(ddc.screen_for("DELL U2720Q", two).uuid, DELL)
end)

t.test("m1ddc's display list gives each display's number, name and UUID", function()
    local out = "[1] LG HDR 4K (" .. LG .. ")\n[2] DELL U2720Q (" .. DELL .. ")\n"
    t.eq(ddc.parse_m1ddc_list(out), {
        { index = 1, name = "LG HDR 4K", uuid = LG },
        { index = 2, name = "DELL U2720Q", uuid = DELL },
    })
    t.eq(ddc.parse_m1ddc_list("No external display found, aborting"), {})
end)

t.test("a bare ddcctl's display lines give its numbering", function()
    local out = "D: CGDisplay " .. DELL .. " dispID(#2) (3840x2160 0°) HiDPI\n"
        .. "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) 108.79 DPI\n"
        .. "I: found 2 external displays\nUsage: ..."
    t.eq(ddc.parse_ddcctl_list(out), { { index = 1, uuid = DELL }, { index = 2, uuid = LG } })
    t.eq(ddc.parse_ddcctl_list("I: found 1 external display\nUsage:"), { { index = 1 } },
        "an older build without the lines, with one display")
    t.eq(ddc.parse_ddcctl_list("I: found 2 external displays\n"), {})
end)

t.test("a tool's display is picked by UUID, then name, then being the only one", function()
    local list = { { index = 1, name = "DELL U2720Q", uuid = DELL }, { index = 2, name = "LG HDR 4K", uuid = LG:lower() } }
    t.eq(ddc.pick(list, { uuid = LG }, "Speakers").index, 2, "UUIDs ignoring case")
    t.eq(ddc.pick(list, nil, "DELL U2720Q").index, 1)
    t.eq(ddc.pick(list, nil, "HDMI"), nil)
    t.eq(ddc.pick({ { index = 1 } }, nil, "HDMI").index, 1)
end)

t.test("ddcctl's VCP lines give the volume and mute, and its errors none", function()
    local out = "I: VCP control #98 (0x62) = current: 30, max: 100\n"
        .. "I: VCP control #141 (0x8d) = current: 2, max: 2\n"
    t.eq(ddc.parse_ddcctl_values(out), { [98] = { cur = 30, max = 100 }, [141] = { cur = 2, max = 2 } })
    t.eq(ddc.parse_ddcctl_values("E: DDC send command failed!\nE: VCP control #98 (0x62) = current: 0, max: 0\n"), {})
end)

t.test("a reading is a share of the monitor's max, and MCCS's mute", function()
    t.eq(ddc.reading(30, 100, 2), { volume = 30, muted = false, max = 100 })
    t.eq(ddc.reading(25, 50, 1), { volume = 50, muted = true, max = 50 })
    t.eq(ddc.reading(25, 50, nil), { volume = 50, max = 50 }, "a monitor that doesn't say")
    t.eq(ddc.reading(25, 0, 1), nil)
    t.eq(ddc.raw(55, 50), 28)
    t.eq(ddc.raw(120, 100), 100)
end)

-- A monitor with a fake tool: each run waits in `runs` for its answer.
local function monitor(tool)
    local runs, logs, changes = {}, {}, 0
    local m = ddc.monitor({
        find = function()
            return tool
        end,
        run = function(path, args, done)
            runs[#runs + 1] = { path = path, args = table.concat(args, " "), done = done }
            return true
        end,
        log = function(msg)
            logs[#logs + 1] = msg
        end,
        changed = function()
            changes = changes + 1
        end,
    })
    return m, runs, logs, function()
        return changes
    end
end

local M1 = { name = "m1ddc", path = "/opt/homebrew/bin/m1ddc" }
local CTL = { name = "ddcctl", path = "/usr/local/bin/ddcctl" }

t.test("with m1ddc, the monitor is found once, then read, one run at a time", function()
    local m, runs, logs, changes = monitor(M1)
    m:poll("LG HDR 4K", SCREENS)
    t.eq(#runs, 1)
    t.eq(runs[1].args, "display list")
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    t.eq(runs[2].args, "display " .. LG .. " get volume")
    m:poll("LG HDR 4K", SCREENS)
    t.eq(#runs, 2, "no second poll while one is out")
    runs[2].done(0, "40\n", "")
    t.eq(runs[3].args, "display " .. LG .. " max volume")
    runs[3].done(0, "100\n", "")
    t.eq(runs[4].args, "display " .. LG .. " get mute")
    runs[4].done(0, "2\n", "")
    t.eq(m.state, { device = "LG HDR 4K", volume = 40, muted = false, max = 100 })
    t.eq(changes(), 1)
    m:poll("LG HDR 4K", SCREENS)
    t.eq(runs[5].args, "display " .. LG .. " get volume", "the display is remembered")
    runs[5].done(0, "40\n", "")
    runs[6].done(0, "100\n", "")
    runs[7].done(0, "2\n", "")
    t.eq(changes(), 1, "the same reading isn't a change")
    t.eq(logs, {})
end)

t.test("a monitor that can't say whether it's muted still has a volume", function()
    local m, runs = monitor(M1)
    m:poll("LG HDR 4K", SCREENS)
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    runs[2].done(0, "40\n", "")
    runs[3].done(0, "100\n", "")
    runs[4].done(1, "DDC communication failure: (ipc/send) invalid destination port\n", "")
    t.eq(m.state, { device = "LG HDR 4K", volume = 40, max = 100 })
end)

t.test("a monitor that doesn't answer hides the reading, logged once", function()
    local m, runs, logs = monitor(M1)
    m:poll("LG HDR 4K", SCREENS)
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    runs[2].done(1, "DDC communication failure: (ipc/send) invalid destination port\n", "")
    runs[3].done(1, "DDC communication failure\n", "")
    runs[4].done(1, "DDC communication failure\n", "")
    t.eq(m.state, nil)
    t.eq(logs, { "bar: monitor volume unread: m1ddc get volume exited 1: DDC communication failure: (ipc/send) invalid destination port" })
    m:poll("LG HDR 4K", SCREENS)
    t.eq(runs[5].args, "display list", "a failure looks for the display again")
    runs[5].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    runs[6].done(1, "DDC communication failure: (ipc/send) invalid destination port\n", "")
    runs[7].done(1, "", "")
    runs[8].done(1, "", "")
    t.eq(#logs, 1, "the same reason isn't logged twice")
end)

t.test("no tool, or no display for the output, hides it and says why", function()
    local m, runs, logs = monitor(nil)
    m:poll("LG HDR 4K", SCREENS)
    t.eq(#runs, 0)
    t.eq(m.state, nil)
    t.eq(logs, { "bar: monitor volume unread: " .. ddc.MISSING })
    m, runs, logs = monitor(M1)
    m:poll("HDMI", { SCREENS[2], { uuid = DELL, name = "DELL U2720Q" } })
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n[2] DELL U2720Q (" .. DELL .. ")\n", "")
    t.eq(m.state, nil)
    t.eq(logs, { 'bar: monitor volume unread: m1ddc lists no display for "HDMI"' })
end)

t.test("with ddcctl, the monitor is numbered, then read in one run", function()
    local m, runs = monitor(CTL)
    m:poll("LG HDR 4K", SCREENS)
    t.eq(runs[1].args, "")
    runs[1].done(1, "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\nI: found 1 external display\n", "")
    t.eq(runs[2].args, "-d 1 -v ? -m ?")
    runs[2].done(0, "I: VCP control #98 (0x62) = current: 15, max: 50\nI: VCP control #141 (0x8d) = current: 1, max: 2\n", "")
    t.eq(m.state, { device = "LG HDR 4K", volume = 30, muted = true, max = 50 })
end)

t.test("setting the volume or mute shows at once, then tells the monitor, in order", function()
    for _, case in ipairs({
        { tool = M1, vol = "display " .. LG .. " set volume 28", mute = "display " .. LG .. " set mute off" },
        { tool = CTL, vol = "-d 1 -v 28", mute = "-d 1 -m 2" },
    }) do
        local m, runs, logs, changes = monitor(case.tool)
        t.eq(m:set_volume(50), false, "nothing read: nothing to set")
        m:poll("LG HDR 4K", SCREENS)
        if case.tool == M1 then
            runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
            runs[2].done(0, "15\n", "")
            runs[3].done(0, "50\n", "")
            runs[4].done(0, "1\n", "")
        else
            runs[1].done(1, "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\n", "")
            runs[2].done(0, "I: VCP control #98 (0x62) = current: 15, max: 50\nI: VCP control #141 (0x8d) = current: 1, max: 2\n", "")
        end
        local n = #runs
        local before = changes()
        t.eq(m:set_volume(55), true)
        t.eq(m.state.volume, 55, "at once")
        t.eq(changes(), before + 1)
        m:set_mute(false)
        t.eq(m.state.muted, false)
        t.eq(#runs, n + 1, "one run at a time")
        t.eq(runs[n + 1].args, case.vol, "55% of a max of 50")
        runs[n + 1].done(0, "", "")
        t.eq(runs[n + 2].args, case.mute)
        runs[n + 2].done(1, "DDC communication failure\n", "")
        t.eq(logs, { "bar: couldn't set the monitor's volume: " .. case.tool.name .. " exited 1: DDC communication failure" })
    end
end)

t.test("a read begun before a change can't put back the old level", function()
    local m, runs = monitor(M1)
    m:poll("LG HDR 4K", SCREENS)
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    runs[2].done(0, "40\n", "")
    runs[3].done(0, "100\n", "")
    runs[4].done(0, "2\n", "")
    m:poll("LG HDR 4K", SCREENS)
    t.eq(runs[5].args, "display " .. LG .. " get volume", "a read is out")
    m:set_volume(45)
    t.eq(m.state.volume, 45)
    runs[5].done(0, "40\n", "")
    runs[6].done(0, "100\n", "")
    runs[7].done(0, "2\n", "")
    t.eq(m.state.volume, 45, "the old reading is dropped")
    m:set_volume(m.state.volume + 5)
    t.eq(m.state.volume, 50, "a second step builds on the first")
    t.eq(runs[8].args, "display " .. LG .. " set volume 45")
    runs[8].done(0, "", "")
    t.eq(runs[9].args, "display " .. LG .. " set volume 50")
    runs[9].done(0, "", "")
    m:poll("LG HDR 4K", SCREENS)
    runs[10].done(0, "50\n", "")
    runs[11].done(0, "100\n", "")
    runs[12].done(0, "2\n", "")
    t.eq(m.state.volume, 50, "a read after the changes counts")
end)

-- Reads LG's volume as 40% with m1ddc, from the first run in `runs`.
local function read_lg(runs, from)
    runs[from].done(0, "[1] LG HDR 4K (" .. LG .. ")\n[2] DELL U2720Q (" .. DELL .. ")\n", "")
    runs[from + 1].done(0, "40\n", "")
    runs[from + 2].done(0, "100\n", "")
    runs[from + 3].done(0, "2\n", "")
end

local TWO = { SCREENS[1], SCREENS[2], { uuid = DELL, name = "DELL U2720Q" } }

t.test("switching outputs while a read is out forgets the old monitor at once", function()
    local m, runs = monitor(M1)
    m:poll("LG HDR 4K", TWO)
    read_lg(runs, 1)
    t.eq(m.state.device, "LG HDR 4K")
    m:poll("DELL U2720Q", TWO)
    t.eq(m.state, nil, "LG's reading is gone before Dell's comes")
    t.eq(m:set_volume(50), false, "so nothing can be sent to the wrong monitor")
    t.eq(runs[5].args, "display list")
    m:poll("LG HDR 4K", TWO)
    t.eq(#runs, 5, "one run at a time")
    runs[5].done(0, "[1] LG HDR 4K (" .. LG .. ")\n[2] DELL U2720Q (" .. DELL .. ")\n", "")
    t.eq(runs[6].args, "display " .. DELL .. " get volume", "Dell's read finishes")
    runs[6].done(0, "70\n", "")
    runs[7].done(0, "100\n", "")
    runs[8].done(0, "2\n", "")
    t.eq(m.state, nil, "but isn't taken for LG's")
    t.eq(runs[9].args, "display list", "LG is looked for again once Dell's read is through")
    read_lg(runs, 9)
    t.eq(m.state.volume, 40)
    m:set_volume(50)
    t.eq(runs[13].args, "display " .. LG .. " set volume 50", "and changes go to LG")
end)

t.test("a display coming or going looks for ddcctl's number again", function()
    local m, runs = monitor(CTL)
    local lines = "D: CGDisplay " .. DELL .. " dispID(#2) (3840x2160 0°) HiDPI\n"
        .. "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\n"
    m:poll("LG HDR 4K", TWO)
    runs[1].done(1, lines, "")
    t.eq(runs[2].args, "-d 2 -v ? -m ?")
    runs[2].done(0, "I: VCP control #98 (0x62) = current: 30, max: 100\n", "")
    t.eq(m.state.volume, 30)
    -- Dell unplugged: LG is ddcctl's 1 now.
    m:poll("LG HDR 4K", SCREENS)
    t.eq(m.state, nil, "the old number is forgotten at once")
    t.eq(runs[3].args, "", "and the displays listed again")
    runs[3].done(1, "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\n", "")
    t.eq(runs[4].args, "-d 1 -v ? -m ?")
end)

t.test("a change queued before a display goes is dropped, not sent by its old number", function()
    local m, runs, logs = monitor(CTL)
    local lines = "D: CGDisplay " .. DELL .. " dispID(#2) (3840x2160 0°) HiDPI\n"
        .. "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\n"
    m:poll("LG HDR 4K", TWO)
    runs[1].done(1, lines, "")
    runs[2].done(0, "I: VCP control #98 (0x62) = current: 30, max: 100\n", "")
    m:poll("LG HDR 4K", TWO)
    t.eq(runs[3].args, "-d 2 -v ? -m ?", "a read is out")
    m:set_volume(35)
    -- Dell unplugged before the read comes back.
    m:poll("LG HDR 4K", SCREENS)
    runs[3].done(0, "I: VCP control #98 (0x62) = current: 30, max: 100\n", "")
    t.eq(runs[4].args, "", "no -d 2 -v 35: the displays are listed again instead")
    t.eq(logs, { "bar: dropped a monitor volume change: the output or displays changed first" })
    runs[4].done(1, "D: CGDisplay " .. LG .. " dispID(#3) (2560x1440 0°) HiDPI\n", "")
    t.eq(runs[5].args, "-d 1 -v ? -m ?")
end)

t.test("an output that's no longer the monitor forgets it", function()
    local m, runs, _, changes = monitor(M1)
    m:poll("LG HDR 4K", SCREENS)
    runs[1].done(0, "[1] LG HDR 4K (" .. LG .. ")\n", "")
    runs[2].done(0, "40\n", "")
    runs[3].done(0, "100\n", "")
    runs[4].done(0, "2\n", "")
    m:poll(nil)
    t.eq(m.state, nil)
    t.eq(changes(), 2)
end)

t.test("the bar shows a monitor's volume, read over DDC, as any other", function()
    local read = { device = "LG HDR 4K", volume = 40, muted = true, max = 100 }
    local audio = ddc.merge({ name = "LG HDR 4K", muted = false }, read)
    t.eq(audio, { name = "LG HDR 4K", volume = 40, muted = true })
    t.eq(bar.icons({ audio = audio }).volume, { level = "mute", muted = true, text = "40%", tip = "Sound muted" })
    read.muted = nil
    t.eq(ddc.merge({ name = "LG HDR 4K", muted = false }, read).muted, false, "macOS's mute when the monitor says none")
    t.eq(ddc.merge({ name = "LG HDR 4K" }, read).muted, nil)
end)

t.test("a DDC reading counts only for the output it was read for, without a volume of its own", function()
    local read = { device = "LG HDR 4K", volume = 40, max = 100 }
    t.eq(ddc.merge({ name = "MacBook Pro Speakers", volume = 70, muted = false }, read),
        { name = "MacBook Pro Speakers", volume = 70, muted = false })
    t.eq(ddc.merge({ name = "DELL U2720Q" }, read), { name = "DELL U2720Q" }, "another monitor's reading")
    t.eq(bar.icons({ audio = ddc.merge({ name = "DELL U2720Q" }, read) }).volume.level, "fixed")
    t.eq(ddc.merge({ name = "LG HDR 4K" }, nil), { name = "LG HDR 4K" })
    t.eq(ddc.applies({ name = "LG HDR 4K" }, read), true)
    t.eq(ddc.applies(nil, read), false)
end)

t.test("brightness over DDC: each tool's runs, and what they print", function()
    local m1, ctl = { name = "m1ddc" }, { name = "ddcctl" }
    t.eq(ddc.luminance_reads(m1, "U1"), { { "display", "U1", "get", "luminance" }, { "display", "U1", "max", "luminance" } })
    t.eq(ddc.luminance_reads(ctl, 2), { { "-d", "2", "-b", "?" } })
    t.eq(ddc.luminance_set(m1, "U1", 40), { "display", "U1", "set", "luminance", "40" })
    t.eq(ddc.luminance_set(ctl, 2, 40), { "-d", "2", "-b", "40" })
    t.eq(ddc.parse_luminance(m1, { { code = 0, out = "30\n" }, { code = 0, out = "100\n" } }), { cur = 30, max = 100 })
    local l, why = ddc.parse_luminance(m1, { { code = 1, out = "", err = "no display" }, { code = 0, out = "100" } })
    t.eq(l, nil)
    t.eq(why, "m1ddc get luminance exited 1: no display")
    t.eq(ddc.parse_luminance(ctl, { { code = 0, out = "I: VCP control #16 (0x10) = current: 55, max: 100\n" } }),
        { cur = 55, max = 100 })
    t.eq(select(2, ddc.parse_luminance(ctl, { { code = 0, out = "E: DDC read failed\n" } })),
        "ddcctl read no brightness (exit 0)")
    t.eq(ddc.id(m1, { uuid = "U1", index = 1 }), "U1")
    t.eq(ddc.id(ctl, { uuid = "U1", index = 1 }), 1)
end)

t.done("ddc")
