-- tide reloads itself once a new copy has been installed over it
-- (selfreload.lua): a copy is many files, so it waits for them to stop
-- coming, and leaves alone what isn't one of its files.

local t = require("t")
local selfreload = require("tide.selfreload")

-- Timers run by hand, a reload counted, and the log kept.
local function stub()
    local s = { timers = {}, reloads = 0, logged = {} }
    s.changed = selfreload.new(function(seconds, fn)
        local tm = { seconds = seconds, fn = fn }
        tm.stop = function()
            tm.stopped = true
        end
        s.timers[#s.timers + 1] = tm
        return tm
    end, function()
        s.reloads = s.reloads + 1
    end, function(line)
        s.logged[#s.logged + 1] = line
    end)
    function s.fire()
        for _, tm in ipairs(s.timers) do
            if not tm.stopped and not tm.fired then
                tm.fired = true
                tm.fn()
            end
        end
    end
    return s
end

t.test("a new copy of tide's files reloads it once, after the last file", function()
    local s = stub()
    s.changed({ "/u/.hammerspoon/tide/init.lua" })
    s.changed({ "/u/.hammerspoon/tide/wm.lua", "/u/.hammerspoon/tide/dashboard/settings.html" })
    t.eq(s.reloads, 0, "not while files are still coming")
    t.eq(s.timers[#s.timers].seconds, selfreload.QUIET)
    s.fire()
    t.eq(s.reloads, 1)
    t.eq(#s.logged, 1)
end)

t.test("Finder's .DS_Store and other hidden files don't reload it", function()
    local s = stub()
    s.changed({ "/u/.hammerspoon/tide/.DS_Store" })
    s.changed({ "/u/.hammerspoon/tide/dashboard/.settings.html.swp" })
    s.fire()
    t.eq(s.reloads, 0)
end)

t.done("selfreload")
