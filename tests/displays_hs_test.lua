-- The Displays page's brightness over DDC (displays_hs.lua), against
-- stand-in displays and a stand-in m1ddc: an external display macOS can't
-- set is read with the bar's DDC tool, shown, and set through it.

local t = require("t")

local function stub(installed, deferred)
    local s = { runs = {}, logged = {}, changes = 0, waiting = {}, lum = 30, deferred = deferred }
    s.screen = nil
    local function screen(uuid, name, brightness)
        local sc = {}
        function sc.getUUID()
            return uuid
        end
        function sc.name()
            return name
        end
        function sc.getBrightness()
            return brightness
        end
        function sc.fullFrame()
            return { x = 0, y = 0, w = 100, h = 100 }
        end
        function sc.currentMode()
            return nil
        end
        function sc.availableModes()
            return {}
        end
        return sc
    end
    s.screens = { screen("MAC", "Built-in Retina Display", 0.6), screen("0A1B-22CD", "LG HDR 4K", nil) }
    s.make_screen = screen
    _G.hs = {
        screen = {
            allScreens = function()
                return s.screens
            end,
            primaryScreen = function()
                return s.screens[1]
            end,
            watcher = {
                new = function(fn)
                    s.screen_changed = fn
                    return { start = function() end }
                end,
            },
        },
    }
    local tide = {
        adapter = {
            log = function(line)
                s.logged[#s.logged + 1] = line
            end,
            exists = function(p)
                return installed and p == "/opt/homebrew/bin/m1ddc"
            end,
            -- m1ddc answers at once, or, `deferred`, when the test says.
            run = function(_, args, done)
                local line = table.concat(args, " ")
                s.runs[#s.runs + 1] = line
                -- The monitor's luminance, as m1ddc reads and sets it.
                local function answer()
                    local set = line:match("^display 0A1B%-22CD set luminance (%d+)$")
                    if set then
                        s.lum = tonumber(set)
                    end
                    local out = ({
                        ["display list"] = "[1] LG HDR 4K (0A1B-22CD)\n",
                        ["display 0A1B-22CD get luminance"] = s.lum .. "\n",
                        ["display 0A1B-22CD max luminance"] = "100\n",
                    })[line] or ""
                    done(0, "", out)
                end
                if s.deferred then
                    s.waiting[#s.waiting + 1] = setmetatable({ line = line }, { __call = answer })
                else
                    answer()
                end
                return true
            end,
        },
    }
    -- Answers the waiting run whose line has `text` in it.
    function s.answer(text)
        for i, w in ipairs(s.waiting) do
            if w.line:find(text, 1, true) then
                table.remove(s.waiting, i)
                return w()
            end
        end
        error("no run waiting for " .. text)
    end
    package.loaded["tide.displays_hs"] = nil
    s.d = require("tide.displays_hs").new(tide, function()
        s.changes = s.changes + 1
    end)
    return s
end

local function lg(state)
    for _, d in ipairs(state.displays) do
        if d.uuid == "0A1B-22CD" then
            return d
        end
    end
end

t.test("an external display's brightness is read over DDC, and shown as such", function()
    local s = stub(true)
    t.eq(lg(s.d.state()).brightness, nil, "not read yet")
    s.d.read_ddc()
    t.eq(s.runs, { "display list", "display 0A1B-22CD get luminance", "display 0A1B-22CD max luminance" })
    t.eq(s.changes, 1)
    t.eq(lg(s.d.state()).brightness, 30)
    t.eq(lg(s.d.state()).over_ddc, true)
    t.eq(s.d.state().displays[1].over_ddc, nil, "the built-in one is macOS's")
end)

t.test("setting it runs the tool, at the monitor's scale", function()
    local s = stub(true)
    s.d.read_ddc()
    s.runs = {}
    t.eq(s.d.handle({ displayBrightness = { uuid = "0A1B-22CD", level = 55 } }), true)
    t.eq(s.runs, { "display 0A1B-22CD set luminance 55" })
    t.eq(lg(s.d.state()).brightness, 55)
end)

t.test("a display the tool doesn't list gets no slider, not another's", function()
    local s = stub(true)
    s.screens[3] = s.make_screen("AAAA-BBBB", "AirPlay Display", nil)
    s.d.read_ddc()
    t.eq(lg(s.d.state()).brightness, 30)
    for _, d in ipairs(s.d.state().displays) do
        if d.uuid == "AAAA-BBBB" then
            t.eq(d.brightness, nil, "the tool's one display is the LG, not this")
        end
    end
end)

t.test("a display coming or going during a read reads again, dropping the old answer", function()
    local s = stub(true, true)
    s.d.read_ddc()
    s.screen_changed()
    t.eq(#s.runs, 1, "one read at a time")
    -- The first read finishes; its answer is from before the change.
    while #s.waiting > 0 do
        table.remove(s.waiting, 1)()
    end
    t.eq(#s.runs, 6, "read again after the change")
    t.eq(lg(s.d.state()).brightness, 30)
end)

t.test("a read out as the slider sets it can't put the old level back", function()
    local s = stub(true)
    s.d.read_ddc()
    t.eq(lg(s.d.state()).brightness, 30)
    -- The window opens again: a read goes out, and the slider moves.
    s.deferred = true
    s.d.read_ddc()
    s.d.handle({ displayBrightness = { uuid = "0A1B-22CD", level = 55 } })
    s.answer("list")
    s.answer("get luminance") -- 30, from before the set reaches the monitor
    s.answer("max luminance")
    s.answer("set luminance 55")
    t.eq(lg(s.d.state()).brightness, 55, "the set, not the old read's 30")
    while #s.waiting > 0 do
        table.remove(s.waiting, 1)()
    end
    t.eq(lg(s.d.state()).brightness, 55, "and a fresh read agrees")
end)

t.test("sets go one at a time, in order, and only the latest of those waiting", function()
    local s = stub(true)
    s.d.read_ddc()
    s.deferred = true
    for _, level in ipairs({ 40, 50, 60 }) do
        s.d.handle({ displayBrightness = { uuid = "0A1B-22CD", level = level } })
    end
    t.eq(s.runs[#s.runs], "display 0A1B-22CD set luminance 40", "the first runs")
    s.answer("set luminance 40")
    t.eq(s.runs[#s.runs], "display 0A1B-22CD set luminance 60", "then the latest, not 50")
    s.answer("set luminance 60")
    t.eq(#s.waiting, 0)
    t.eq(s.lum, 60)
    t.eq(lg(s.d.state()).brightness, 60)
end)

t.test("without the tool, no brightness for it", function()
    local s = stub(false)
    s.d.read_ddc()
    t.eq(s.runs, {})
    t.eq(lg(s.d.state()).brightness, nil)
end)

t.done("displays_hs")
