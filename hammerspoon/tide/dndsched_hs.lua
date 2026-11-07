-- Do Not Disturb on tide's schedule (dndsched.lua): looked at every
-- minute, and on a wake, and turned on or off through presenter mode's
-- shortcuts (presenter_hs.lua).

local dndsched = require("tide.dndsched")
local dashboard = require("tide.dashboard")

local M = {}

M.EVERY = 60

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

-- `tide` is the started tide module: its notification_files,
-- presenter, and adapter (read, javascript, after, log).
function M.new(tide)
    local self = {}
    local a = tide.adapter
    local state
    -- The last good settings, which a file gone wrong leaves in effect.
    local good
    local timer
    local bundle
    local said

    local function say(why)
        if why ~= said and why then
            a.log("dnd schedule: " .. why)
        end
        said = why
    end

    local function work_out()
        if not bundle then
            local sources = {}
            for _, name in ipairs(dndsched.MODULES) do
                sources[name] = a.read(DIR .. name)
            end
            local ok, b = pcall(dashboard.bundle, sources, dndsched.MODULES)
            if not ok then
                say(tostring(b))
                return nil
            end
            bundle = b
        end
        local files = tide.notification_files or {}
        local ok, out = a.javascript(dndsched.script(bundle, files.shared, files["local"], os.time() * 1000, good))
        local r, why = dndsched.read(ok, out, hs.json.decode)
        if not r then
            say(why)
            return nil
        end
        good = r.good
        say(#r.errors > 0 and table.concat(r.errors, "; ") or nil)
        return r
    end

    -- Looks now, and again in a minute.
    function self.look()
        if timer then
            timer.stop()
            timer = nil
        end
        local r = work_out()
        if r then
            local set
            state, set = dndsched.step(state, r.window)
            if set ~= nil and tide.presenter and tide.presenter.set_dnd then
                tide.presenter.set_dnd(set)
            end
        end
        timer = a.after(M.EVERY, self.look)
    end

    -- Do Not Disturb turned on or off by hand: the schedule leaves it.
    function self.own_changed()
        state = dndsched.own_changed(state)
    end

    self.wake_watch = hs.caffeinate.watcher.new(function(e)
        if e == hs.caffeinate.watcher.systemDidWake then
            self.look()
        end
    end)
    self.wake_watch:start()
    self.look()
    return self
end

return M
