-- Keep awake and presenter mode on Hammerspoon (SPEC.md §10), carrying out
-- what presenter.lua decides: keep awake through hs.caffeinate's
-- display-idle assertion, Do Not Disturb through the user's shortcuts and
-- /usr/bin/shortcuts. Not runnable outside Hammerspoon.

local presenter = require("tilemo.presenter")

local M = {}

-- `run` runs a command, holding its task until it exits (the adapter's
-- `run`, runner.lua); `log` writes to the console, `notify` shows a
-- notification, and `changed` is called after anything changed, for the bar.
function M.new(run, log, notify, changed)
    local self = { state = presenter.OFF }

    local function awake()
        return hs.caffeinate.get("displayIdle") and true or false
    end

    local function set_awake(on)
        -- Plugged in or not, as the bar's toggle always did.
        hs.caffeinate.set("displayIdle", on, true)
    end

    -- Do Not Disturb's shortcuts, one at a time, the latest request last.
    local driver = presenter.driver(run, function(text)
        log("presenter: " .. text)
        notify(text)
    end)

    local function apply(step)
        self.state = step.state
        if step.awake ~= nil then
            set_awake(step.awake)
        end
        if step.dnd then
            driver.request(step.dnd)
        end
        changed()
    end

    function self.presenting()
        return self.state.presenting or false
    end

    -- Super+P and the launcher's Presenter mode.
    function self.toggle_presenter()
        apply(presenter.presenter(self.state, awake()))
        hs.alert.show(presenter.presenter_sign(self.presenting()))
    end

    -- Super+S, the bar's keep-awake item and the launcher's Keep awake.
    function self.toggle_keep_awake()
        apply(presenter.keep_awake(self.state, awake()))
        hs.alert.show(presenter.awake_sign(awake()))
    end

    -- The launcher's Do Not Disturb.
    function self.toggle_dnd()
        apply(presenter.dnd(self.state))
    end

    -- Checks the shortcuts presenter mode needs, at load, for the console
    -- and `tilemo doctor` (self.missing); the first key that needs one
    -- says so in a notification.
    self.missing = {}
    function self.check()
        local started = run(presenter.SHORTCUTS, { "list" }, function(code, err, out)
            if code ~= 0 then
                log("presenter: `shortcuts list` exited " .. tostring(code) .. ": " .. tostring(err))
                return
            end
            self.missing = presenter.missing(out, { presenter.DND_ON, presenter.DND_OFF })
            if #self.missing > 0 then
                log("presenter: " .. presenter.setup_notice(self.missing))
            end
        end)
        if not started then
            log("presenter: couldn't start " .. presenter.SHORTCUTS .. "; Do Not Disturb needs macOS 12 or later")
        end
    end

    return self
end

return M
