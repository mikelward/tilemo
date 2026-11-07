-- The Mac's light or dark on tide's schedule (theme.lua): set through System
-- Events as tide starts, at each change, on a wake, and as tide's
-- appearance files change. A switch by hand, in Control Center or the
-- settings window, holds until the next change, as tide's flip does.

local theme = require("tide.theme")
local dashboard = require("tide.dashboard")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

-- `tide` is the started tide module: its appearance_files, adapter
-- (read, javascript, after, log) and settings window, if it's open.
function M.new(tide)
    local self = {}
    local a = tide.adapter
    local held
    local plan
    -- The last good settings, which a file gone wrong leaves in effect.
    local good
    local timer
    -- What tide set last, so its own change isn't taken for one by hand.
    local setting
    local said
    local bundle

    local function now()
        return os.time() * 1000
    end

    local function dark()
        return hs.host.interfaceStyle() == "Dark"
    end

    local function say(why)
        if why ~= said then
            said = why
            if why then
                a.log("appearance: " .. why)
            end
        end
    end

    -- What tide's module says now, or nil, having logged why.
    local function work_out()
        if not bundle then
            local sources = {}
            for _, name in ipairs(theme.MODULES) do
                sources[name] = a.read(DIR .. name)
            end
            local ok, b = pcall(dashboard.bundle, sources, theme.MODULES)
            if not ok then
                say(tostring(b))
                return nil
            end
            bundle = b
        end
        local files = tide.appearance_files or {}
        local ok, out = a.javascript(theme.script(bundle, files.shared, files["local"], now(), held, hs.json.encode, good))
        local p, why = theme.read(ok, out, hs.json.decode)
        if not p then
            say(why)
            return nil
        end
        good = p.good
        say(#p.errors > 0 and table.concat(p.errors, "; ") or nil)
        if not p.held then
            held = nil
        end
        return p
    end

    local function set(want)
        setting = want
        local ok, _, err = hs.osascript.applescript(theme.applescript(want))
        if not ok then
            setting = nil
            a.log("appearance: System Events couldn't set " .. (want and "dark" or "light") .. ": "
                .. (type(err) == "table" and tostring(err.OSAScriptErrorMessageKey or hs.inspect(err)) or tostring(err)))
        end
    end

    local function shown()
        if tide.settings and tide.settings.theme_changed then
            tide.settings.theme_changed()
        end
    end

    -- Light or dark as tide's settings say now, and a look again at the
    -- next change.
    function self.apply()
        if timer then
            timer.stop()
            timer = nil
        end
        plan = work_out()
        if plan and plan.chosen and plan.dark ~= dark() then
            set(plan.dark)
        end
        timer = a.after(theme.wait(plan, now()), function()
            timer = nil
            self.apply()
        end)
        shown()
    end

    -- macOS's appearance changed: by tide, or by hand, which holds until
    -- the next change.
    function self.changed()
        local now_dark = dark()
        if setting ~= nil and now_dark == setting then
            setting = nil
            return shown()
        end
        setting = nil
        local p = work_out()
        if p and p.chosen then
            held = theme.hold(p, now_dark)
            plan = work_out()
        end
        shown()
    end

    -- The settings window's Light now or Dark now.
    function self.flip()
        local want = not dark()
        local p = work_out()
        if p and p.chosen then
            held = theme.hold(p, want)
        end
        set(want)
        plan = work_out()
        shown()
    end

    -- What the Appearance page shows: whether tide's settings choose, light
    -- or dark now, and until when (ms), if that changes.
    function self.state()
        return {
            chosen = plan ~= nil and plan.chosen,
            dark = dark(),
            next = plan and plan.chosen and plan.next or nil,
        }
    end

    -- Kept, as Hammerspoon stops one that's collected.
    self.theme_watch = hs.distributednotifications.new(function()
        a.after(0, self.changed)
    end, "AppleInterfaceThemeChangedNotification")
    self.theme_watch:start()
    self.wake_watch = hs.caffeinate.watcher.new(function(e)
        if e == hs.caffeinate.watcher.systemDidWake then
            self.apply()
        end
    end)
    self.wake_watch:start()
    self.apply()
    return self
end

return M
