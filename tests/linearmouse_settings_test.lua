-- tide's Mouse settings applied to LinearMouse's config (linearmouse.lua,
-- dashboard/linearmouse.js), with node standing in for JavaScriptCore.

local t = require("t")
local json = require("json")
local linearmouse = require("tide.linearmouse")

local function node_runner()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to set LinearMouse's scrolling")
        end
        return nil
    end
    return function(source)
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write("process.stdout.write(String(" .. source .. "));")
        f:close()
        local p = io.popen("node " .. path .. " 2>&1")
        local out = p:read("a")
        local ok = p:close()
        os.remove(path)
        return ok == true, out
    end
end

-- Plain Lua: no node needed.
t.test("what the Mouse section shows changes with the pointer as well as the problem", function()
    local base = linearmouse.shown({ problem = "", pointer = { speed = 0.35, acceleration = 1.5 } })
    t.eq(linearmouse.shown({ problem = "", pointer = { speed = 0.35, acceleration = 1.5 } }), base)
    t.eq(linearmouse.shown({ problem = "", pointer = { speed = 0.4, acceleration = 1.5 } }) ~= base, true,
        "a speed changed in LinearMouse's own window")
    t.eq(linearmouse.shown({ problem = "", pointer = { speed = 0.35 } }) ~= base, true, "one left to macOS")
    t.eq(linearmouse.shown({ problem = "LinearMouse isn't running.", pointer = { speed = 0.35, acceleration = 1.5 } }) ~= base, true)
    t.eq(linearmouse.shown({ problem = "" }), linearmouse.shown({ problem = "", pointer = {} }))
end)

t.test("macOS's natural scrolling is on while it's unset", function()
    t.eq(linearmouse.natural_from(0, "1\n"), true)
    t.eq(linearmouse.natural_from(0, "0\n"), false)
    t.eq(linearmouse.natural_from(1,
        "\n2026-11-01 defaults[1:2] \nThe domain/default pair of (kCFPreferencesAnyApplication, com.apple.swipescrolldirection) does not exist\n"), true)
    local v, why = linearmouse.natural_from(-1, "couldn't run defaults")
    t.eq(v, nil)
    t.eq(why:find("couldn't run defaults", 1, true) ~= nil, true)
    t.eq((linearmouse.natural_from(0, "maybe")), nil)
end)

t.test("a burst of plugs runs once, a second after the last", function()
    local timers, runs = {}, 0
    local function after(seconds, fn)
        local timer = { seconds = seconds, fn = fn }
        timer.stop = function()
            timer.stopped = true
        end
        timers[#timers + 1] = timer
        return timer
    end
    local poke = linearmouse.debounce(after, 1, function()
        runs = runs + 1
    end)
    poke()
    poke()
    poke()
    t.eq(#timers, 3)
    t.eq(timers[1].stopped, true)
    t.eq(timers[2].stopped, true)
    t.eq(timers[3].stopped, nil)
    t.eq(timers[3].seconds, 1)
    timers[3].fn()
    t.eq(runs, 1)
    -- A later plug starts afresh, stopping nothing that already ran.
    poke()
    t.eq(timers[3].stopped, nil)
    timers[4].fn()
    t.eq(runs, 2)
end)

local run_node = node_runner()
if not run_node then
    print("SKIP tide's Mouse settings in LinearMouse: no node")
    t.done("linearmouse_settings")
    return
end

local function read_file(path)
    local f = assert(io.open(path))
    local s = f:read("a")
    f:close()
    return s
end

local SOURCES = {}
for _, name in ipairs(linearmouse.MODULES) do
    SOURCES[name] = read_file("hammerspoon/tide/dashboard/" .. name)
end

local HOME = "/Users/me"
local DIR = HOME .. "/.config/tide"
local SUPPORT = HOME .. linearmouse.CONFIGS[1]
local CONFIG = HOME .. linearmouse.CONFIGS[2]

-- setup-macos's config: ten lines a notch for every mouse.
local SETUP = [[{
    "schemes": [
        {
            "if": {
                "device": {
                    "category": "mouse"
                }
            },
            "scrolling": {
                "distance": {
                    "vertical": 10
                }
            }
        }
    ]
}]]

-- A Mac with these files: LinearMouse installed and running unless said,
-- and natural scrolling as `natural` says (on, macOS's default).
local function machine(files, opts)
    opts = opts or {}
    local m = {
        files = files,
        notices = {},
        logs = {},
        writes = {},
        runs = 0,
        starts = 0,
        installed = opts.installed ~= false,
        running = opts.running ~= false,
        natural = opts.natural ~= false,
    }
    m.lm = linearmouse.new({
        home = HOME,
        dir = DIR,
        sources = SOURCES,
        read = function(path)
            return m.files[path]
        end,
        exists = function(path)
            return m.files[path] ~= nil
        end,
        resolve = function(path)
            return (opts.links or {})[path] or path
        end,
        write = function(path, text)
            if m.fail_write then
                return nil, "disk full"
            end
            m.writes[#m.writes + 1] = path
            m.files[path] = text
            return true
        end,
        run_js = function(source)
            m.runs = m.runs + 1
            return run_node(source)
        end,
        decode = json.decode,
        natural = function(done)
            if m.natural == "unknown" then
                done(nil, "defaults exited 1")
            else
                done(m.natural)
            end
        end,
        installed = function()
            return m.installed
        end,
        running = function()
            return m.running
        end,
        start = function(done)
            m.starts = m.starts + 1
            m.finish_start = done
        end,
        notify = function(text)
            m.notices[#m.notices + 1] = text
        end,
        log = function(text)
            m.logs[#m.logs + 1] = text
        end,
    })
    return m
end

-- What LinearMouse would do for every mouse, from the file at `path`: the
-- schemes, and the last's vertical distance and reverse.
local function scrolling(m, path)
    local config = json.decode(m.files[path or CONFIG])
    local last = config.schemes[#config.schemes]
    return { n = #config.schemes, lines = last.scrolling.distance.vertical, reverse = last.scrolling.reverse.vertical }
end

t.test("with no config, every mouse gets tide's 3x, nine lines, and its wheel not natural", function()
    local m = machine({})
    m.lm.apply("event")
    t.eq(m.writes, { CONFIG })
    -- macOS's switch is on, tide's mouse off: reversed.
    t.eq(scrolling(m), { n = 1, lines = 9, reverse = true })
    t.eq(m.lm.state.problem, "")
    t.eq(m.notices, {})
end)

t.test("setup-macos's ten lines become tide's nine, in the same scheme", function()
    local m = machine({ [CONFIG] = SETUP }, { natural = false })
    m.lm.apply("event")
    t.eq(scrolling(m), { n = 1, lines = 9, reverse = false })
end)

t.test("Application Support's config is the one changed, when there is one", function()
    local m = machine({ [SUPPORT] = SETUP, [CONFIG] = SETUP })
    m.lm.apply("event")
    t.eq(m.writes, { SUPPORT })
    t.eq(m.files[CONFIG], SETUP)
end)

t.test("a symlinked config is written where it points", function()
    local m = machine({ [CONFIG] = SETUP }, { links = { [CONFIG] = "/Users/me/conf/linearmouse.json" } })
    m.lm.apply("event")
    t.eq(m.writes, { "/Users/me/conf/linearmouse.json" })
end)

t.test("tide's scroll speed and natural scrolling, from input.local.json over input.json", function()
    local m = machine({
        [DIR .. "/input.json"] = '{"mouse": {"scrollSpeed": 2, "naturalScroll": true}}',
        [DIR .. "/input.local.json"] = '{"mouse": {"scrollSpeed": 1.5}}',
    }, { natural = false })
    m.lm.apply("event")
    -- 1.5x is 4.5 lines, rounded; natural on for the mouse while macOS's
    -- switch is off reverses it.
    t.eq(scrolling(m), { n = 1, lines = 5, reverse = true })
end)

t.test("natural scrolling as macOS has it isn't reversed; differing is", function()
    local on = machine({ [DIR .. "/input.json"] = '{"mouse": {"naturalScroll": true}}' })
    on.lm.apply("event")
    t.eq(scrolling(on).reverse, false)
    -- tide's mouse default is off, macOS's switch on: reversed.
    local off = machine({}, { natural = true })
    off.lm.apply("event")
    t.eq(scrolling(off).reverse, true)
end)

t.test("a slow scroll is one line at least", function()
    local m = machine({ [DIR .. "/input.json"] = '{"mouse": {"scrollSpeed": 0.25}}' })
    m.lm.apply("event")
    t.eq(scrolling(m).lines, 1)
end)

t.test("the rest of the config stays where it was, and a scheme of ours goes last", function()
    local config = [[{
  "$schema": "https://schema.linearmouse.app/0.10.0",
  "schemes": [
    {"if": {"device": {"category": ["mouse"]}}, "scrolling": {"distance": 4, "acceleration": {"vertical": 0}}, "pointer": {"speed": 0.2}},
    {"if": [{"device": {"vendorID": "0x46d", "productID": "0xc52b", "category": "mouse"}}], "pointer": {"speed": 0.8}, "scrolling": {"distance": {"horizontal": 12}}, "buttons": {"mappings": []}},
    {"if": {"device": {"category": "trackpad"}}, "scrolling": {}}
  ]
}]]
    local m = machine({ [CONFIG] = config })
    m.lm.apply("event")
    local c = json.decode(m.files[CONFIG])
    t.eq(c["$schema"], "https://schema.linearmouse.app/0.10.0")
    t.eq(#c.schemes, 4)
    -- Every scheme keeps its place, so the device's own pointer speed still
    -- wins over every mouse's.
    t.eq(c.schemes[1].pointer, { speed = 0.2 })
    t.eq(c.schemes[1].scrolling.distance, 4)
    t.eq(c.schemes[2].pointer, { speed = 0.8 })
    t.eq(c.schemes[3]["if"].device.category, "trackpad")
    -- Ours sets only the vertical scrolling it manages, so the device's
    -- own horizontal distance still wins over every mouse's.
    t.eq(c.schemes[2].scrolling.distance, { horizontal = 12 })
    local ours = c.schemes[4]
    t.eq(ours["if"], { device = { category = "mouse" } })
    t.eq(ours.scrolling, { distance = { vertical = 9 }, reverse = { vertical = true } })
    t.eq(ours.pointer, nil)
    -- An empty list stays a list, not an object.
    t.eq(m.files[CONFIG]:find('"mappings": []', 1, true) ~= nil, true)
    -- Applying again edits ours in place rather than adding another.
    m.lm.apply("event")
    t.eq(#json.decode(m.files[CONFIG]).schemes, 4)
end)

t.test("a mouse scheme with more conditions isn't ours: a new one goes last", function()
    local config = '{"schemes": [{"if": {"device": {"category": "mouse"}, "app": "com.example.game"}, "scrolling": {"distance": {"vertical": 1}}}]}'
    local m = machine({ [CONFIG] = config })
    m.lm.apply("event")
    local c = json.decode(m.files[CONFIG])
    t.eq(#c.schemes, 2)
    t.eq(c.schemes[1].scrolling.distance.vertical, 1)
    t.eq(c.schemes[2]["if"], { device = { category = "mouse" } })
    t.eq(c.schemes[2].scrolling.distance.vertical, 9)
end)

t.test("a config that's right already isn't written, and isn't read again", function()
    local m = machine({})
    m.lm.apply("event")
    local runs = m.runs
    m.lm.apply("check")
    t.eq(#m.writes, 1)
    t.eq(m.runs, runs)
    -- Spaced LinearMouse's way, it's still right.
    m.files[CONFIG] = (m.files[CONFIG]:gsub("\n%s*", ""))
    m.lm.apply("check")
    t.eq(#m.writes, 1)
end)

t.test("the 30 s check puts back a change made in LinearMouse's window", function()
    local m = machine({})
    m.lm.apply("event")
    m.files[CONFIG] = m.files[CONFIG]:gsub('"vertical": 9', '"vertical": 20')
    m.lm.apply("check")
    t.eq(#m.writes, 2)
    t.eq(scrolling(m).lines, 9)
end)

t.test("a config that isn't JSON is left alone, and said once", function()
    local m = machine({ [CONFIG] = "{ // a comment\n}" })
    m.lm.apply("event")
    t.eq(m.writes, {})
    t.eq(m.lm.state.problem:find("linearmouse.json isn't JSON", 1, true) ~= nil, true)
    t.eq(#m.notices, 1)
    t.eq(m.lm.doctor(), { m.lm.state.problem })
    m.files[CONFIG] = "{ // another\n}"
    m.lm.apply("check")
    t.eq(#m.notices, 1)
    -- Fixed: the problem goes.
    m.files[CONFIG] = SETUP
    m.lm.apply("check")
    t.eq(m.lm.state.problem, "")
    t.eq(m.lm.doctor(), {})
end)

t.test("a save that fails is said, and tried again at the next check", function()
    local m = machine({})
    m.fail_write = true
    m.lm.apply("event")
    t.eq(m.lm.state.problem:find("disk full", 1, true) ~= nil, true)
    t.eq(#m.notices, 1)
    m.fail_write = false
    m.lm.apply("check")
    t.eq(m.writes, { CONFIG })
    t.eq(m.lm.state.problem, "")
end)

t.test("a wrong input file keeps the last good settings, said once naming it", function()
    local m = machine({ [DIR .. "/input.local.json"] = '{"mouse": {"scrollSpeed": 2}}' })
    m.lm.apply("event")
    t.eq(scrolling(m).lines, 6)
    m.files[DIR .. "/input.local.json"] = '{"mouse": {"scrollSpeed": "fast"}}'
    m.lm.apply("folder")
    t.eq(scrolling(m).lines, 6)
    t.eq(#m.notices, 1)
    t.eq(m.notices[1]:find("input.local.json: mouse.scrollSpeed must be a number", 1, true) ~= nil, true)
    -- Doctor says so too, for as long as the file is wrong.
    t.eq(#m.lm.doctor(), 1)
    t.eq(m.lm.doctor()[1]:find("mouse.scrollSpeed must be a number", 1, true) ~= nil, true)
    m.lm.apply("check")
    t.eq(#m.lm.doctor(), 1)
    m.files[DIR .. "/input.local.json"] = '{"mouse": {"scrollSpeed": 1}}'
    m.lm.apply("folder")
    t.eq(scrolling(m).lines, 3)
    t.eq(#m.notices, 1)
    t.eq(m.lm.doctor(), {})
end)

t.test("with LinearMouse not installed, nothing is written or started", function()
    local m = machine({}, { installed = false, running = false })
    m.lm.apply("event")
    t.eq(m.writes, {})
    t.eq(m.starts, 0)
end)

t.test("an event starts LinearMouse when it isn't running; the check doesn't", function()
    local m = machine({}, { running = false })
    m.lm.apply("check")
    t.eq(m.starts, 0)
    m.lm.apply("event")
    t.eq(m.starts, 1)
    t.eq(m.lm.launching, true)
    -- Not twice while it's starting.
    m.lm.apply("event")
    t.eq(m.starts, 1)
    local told = false
    m.lm.on_started = function()
        told = true
    end
    m.finish_start(true)
    t.eq(m.lm.launching, false)
    t.eq(told, true)
    t.eq(m.notices, {})
    -- Running: nothing to start.
    m.running = true
    m.lm.apply("event")
    t.eq(m.starts, 1)
end)

t.test("a start that fails is said", function()
    local m = machine({}, { running = false })
    m.lm.apply("event")
    m.finish_start(false, "LSOpenURLsWithRole() failed")
    t.eq(m.notices, { "Couldn't start LinearMouse: LSOpenURLsWithRole() failed" })
end)

t.test("tide's folder changing starts it only when the Mouse settings did", function()
    local m = machine({}, { running = false })
    m.lm.apply("check")
    m.lm.apply("folder")
    t.eq(m.starts, 0)
    m.files[DIR .. "/input.local.json"] = '{"mouse": {"scrollSpeed": 2}}'
    m.lm.apply("folder")
    t.eq(m.starts, 1)
end)

t.test("natural scrolling that can't be read keeps the last, and is logged", function()
    local m = machine({}, { natural = false })
    m.lm.apply("event")
    -- tide's mouse off, macOS's off: not reversed.
    t.eq(scrolling(m).reverse, false)
    m.natural = "unknown"
    m.lm.apply("check")
    t.eq(scrolling(m).reverse, false)
    t.eq(m.logs[#m.logs]:find("defaults exited 1", 1, true) ~= nil, true)
end)

-- setup-macos's config since it set the pointer: 1.5 and 0.35.
local SETUP_POINTER = [[{
    "schemes": [
        {
            "if": { "device": { "category": "mouse" } },
            "scrolling": { "distance": { "vertical": 9 } },
            "pointer": { "acceleration": 1.5, "speed": 0.35 }
        }
    ]
}]]

t.test("the state says every mouse's pointer as LinearMouse has it, or nothing left to macOS", function()
    local m = machine({ [CONFIG] = SETUP_POINTER })
    m.lm.apply("check")
    t.eq(m.lm.state.pointer, { acceleration = 1.5, speed = 0.35 })
    local bare = machine({})
    bare.lm.apply("check")
    t.eq(bare.lm.state.pointer, {})
end)

t.test("setting the pointer writes it in every mouse's last scheme, keeping the scrolling", function()
    local m = machine({ [CONFIG] = SETUP_POINTER })
    m.lm.apply("check")
    local ok, why = m.lm.set_pointer("acceleration", 2)
    t.eq(ok, true, why)
    local config = json.decode(m.files[CONFIG])
    t.eq(#config.schemes, 1)
    t.eq(config.schemes[1].pointer, { acceleration = 2, speed = 0.35 })
    t.eq(config.schemes[1].scrolling.distance.vertical, 9)
    t.eq(m.lm.state.pointer, { acceleration = 2, speed = 0.35 })
    local fresh = machine({})
    t.eq((fresh.lm.set_pointer("speed", 0.5)), true)
    t.eq(json.decode(fresh.files[CONFIG]).schemes[1].pointer, { speed = 0.5 })
end)

t.test("a pointer setting out of range, or a config that isn't JSON, is refused and nothing's written", function()
    local m = machine({ [CONFIG] = SETUP_POINTER })
    local ok, why = m.lm.set_pointer("acceleration", 9)
    t.eq(ok, nil)
    t.eq(why:find("from 0 to 4", 1, true) ~= nil, true, why)
    local broken = machine({ [CONFIG] = "{" })
    ok, why = broken.lm.set_pointer("speed", 0.5)
    t.eq(ok, nil)
    t.eq(why:find("isn't JSON", 1, true) ~= nil, true, why)
    t.eq(broken.writes, {})
    local gone = machine({}, { installed = false })
    ok, why = gone.lm.set_pointer("speed", 0.5)
    t.eq(ok, nil)
    t.eq(why:find("isn't installed", 1, true) ~= nil, true, why)
end)

t.test("done hears the state once it's applied", function()
    local m = machine({})
    local got
    m.lm.apply("event", function(state)
        got = state
    end)
    t.eq(got.lines, 9)
    t.eq(got.problem, "")
end)

t.done("linearmouse_settings")
