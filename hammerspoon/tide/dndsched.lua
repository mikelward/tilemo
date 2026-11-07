-- Do Not Disturb on a schedule, as tide's (tide SPEC.md §9, §16), from
-- tide's notifications.json and notifications.local.json: tide's own
-- module says whether a window is open, run in JavaScriptCore, and tide
-- turns Do Not Disturb on as one starts and off as it ends, through the
-- shortcuts presenter mode runs (presenter.lua). Pure Lua.

local names = require("tide.names")

local M = {}

M.SHARED_FILE = "notifications.json"
M.LOCAL_FILE = "notifications.local.json"

-- tide's modules, in the order bundled: its DND module imports its clocks
-- and appearance modules, which import its steps and palette.
M.MODULES = { "tide-clocks.js", "tide-steps.js", "tide-palette.js", "tide-appearance.js", "tide-dnd.js" }

local function literal(v)
    return v == nil and "null" or names.js_string(v)
end

-- JavaScript giving, as JSON, the window open at `now` (ms; its start, or
-- null outside one), what's wrong with either file, and the settings to
-- pass as `last` next time, after `bundle` (dashboard.bundle of
-- M.MODULES). `last` is the last good answer's `good`: with a file that's
-- wrong, it stands, as tide keeps its last good settings, so a slip in an
-- edit doesn't end a window early.
function M.script(bundle, shared, own, now, last)
    return bundle .. "\n(function(){"
        .. 'const D=modules["./tide-dnd.js"];'
        .. "const last=" .. literal(last) .. ";"
        .. "const r=D.loadNotificationSettings(" .. literal(shared) .. "," .. literal(own)
        .. ",last===null?undefined:JSON.parse(last));"
        .. "return JSON.stringify({window:D.windowStart(r.settings,new Date(" .. string.format("%d", now) .. ")),"
        .. "scheduled:r.settings.dndScheduled===true,errors:r.errors,"
        .. "good:r.errors.length>0?last:JSON.stringify(r.settings)});})()"
end

-- The script's answer as { window (ms, or false outside one), scheduled,
-- errors, good (the settings to pass as `last` next time, or nil) }, or
-- nil and why.
function M.read(ok, result, decode)
    if not ok or type(result) ~= "string" then
        return nil, "couldn't work out the schedule: " .. tostring(result)
    end
    local good, r = pcall(decode, result)
    if not good or type(r) ~= "table" then
        return nil, "couldn't work out the schedule: " .. tostring(result)
    end
    return {
        window = type(r.window) == "number" and r.window or false,
        scheduled = r.scheduled == true,
        errors = type(r.errors) == "table" and r.errors or {},
        good = type(r.good) == "string" and r.good or nil,
    }
end

-- What the schedule does as a window starts or ends, as tide's
-- scheduleStep, without reading Do Not Disturb (macOS has no public way):
-- returns the next state and true to turn it on, false off, or nil. The
-- state is { window, scheduled_on }: the window the last look was in
-- (false outside one; no state before the first look), and whether the
-- schedule turned it on, which turning it on or off yourself clears.
-- A window starting turns it on; one ending turns it off only if the
-- schedule turned it on.
function M.step(state, window)
    if state and window == state.window then
        return state, nil
    end
    if window then
        return { window = window, scheduled_on = true }, true
    end
    if not state then
        return { window = false, scheduled_on = false }, nil
    end
    if state.scheduled_on then
        return { window = false, scheduled_on = false }, false
    end
    return { window = false, scheduled_on = false }, nil
end

-- After you turn Do Not Disturb on or off yourself: the window ending
-- leaves it as you set it.
function M.own_changed(state)
    if state then
        state.scheduled_on = false
    end
    return state
end

return M
