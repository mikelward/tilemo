-- Keep awake and presenter mode (SPEC.md §10): Super+S, Super+P, the
-- launcher and the bar's keep-awake item. Pure, so it tests in plain Lua;
-- presenter_hs.lua carries out what it decides.
--
-- Presenter mode is Do Not Disturb and keep awake together, as on tide
-- (tide §10). Keep awake is Hammerspoon's display-idle assertion, which
-- tilemo can read, so turning presenter mode off puts it back as it was.
-- Do Not Disturb is a Focus, which has no public API: tilemo turns it on
-- and off through two shortcuts the user makes in Shortcuts, and can't read
-- it, so turning presenter mode off turns it off.

local M = {}

-- The shortcuts presenter mode runs, through /usr/bin/shortcuts.
M.DND_ON = "Do Not Disturb On"
M.DND_OFF = "Do Not Disturb Off"
-- The one the launcher's Do Not Disturb runs (SPEC.md §9).
M.DND_TOGGLE = "Toggle Do Not Disturb"

-- The state is { presenting, awake_before }: whether presenter mode is on,
-- and whether keep awake was on before it came on.
M.OFF = { presenting = false }

-- What to do, as { state, awake, dnd }: the next state, keep awake's new
-- setting (nil to leave it), and the shortcut to run (nil for none).

-- Super+P: on, remembering keep awake; or off, putting keep awake back.
function M.presenter(state, awake_now)
    if state and state.presenting then
        return { state = M.OFF, awake = state.awake_before or false, dnd = M.DND_OFF }
    end
    return { state = { presenting = true, awake_before = awake_now or false }, awake = true, dnd = M.DND_ON }
end

-- Super+S, the bar's item, the launcher's Keep awake. While presenting it
-- reads on, so it goes off, ending presenter mode; Do Not Disturb stays on.
function M.keep_awake(state, awake_now)
    if state and state.presenting then
        return { state = M.OFF, awake = false }
    end
    return { state = state or M.OFF, awake = not awake_now }
end

-- The launcher's Do Not Disturb, which toggles it. While presenting it
-- turns it off, ending presenter mode; keep awake stays on.
function M.dnd(state)
    if state and state.presenting then
        return { state = M.OFF, dnd = M.DND_OFF }
    end
    return { state = state or M.OFF, dnd = M.DND_TOGGLE }
end

-- The on-screen sign after a key, as tide's OSD (tide §9).
function M.awake_sign(on)
    return on and "Keeping awake" or "Not keeping awake"
end

function M.presenter_sign(presenting)
    return presenting and "Presenting" or "Presenter mode off"
end

-- Which of `names` `shortcuts list`'s output lacks: one shortcut per line.
function M.missing(list_output, names)
    local have = {}
    for line in (list_output or ""):gmatch("[^\n]+") do
        have[line:gsub("%s+$", "")] = true
    end
    local out = {}
    for _, name in ipairs(names) do
        if not have[name] then
            out[#out + 1] = name
        end
    end
    return out
end

-- What each shortcut's one Set Focus action does to Do Not Disturb.
M.SETTING = {
    [M.DND_ON] = "turn it on until turned off",
    [M.DND_OFF] = "turn it off",
    [M.DND_TOGGLE] = "toggle it",
}

-- What to make, said when a key first needs a shortcut that isn't there.
-- Keep awake works either way.
function M.setup_notice(missing)
    local each = {}
    for i, name in ipairs(missing) do
        each[i] = "\"" .. name .. "\" (" .. (M.SETTING[name] or "set it") .. ")"
    end
    return "Do Not Disturb has no public switch, so tilemo runs shortcuts for it. In the Shortcuts app,"
        .. " make " .. table.concat(each, " and ") .. ", each one Set Focus action on Do Not Disturb."
        .. " Keep awake works without them."
end

-- What to say when a shortcut that's there fails, with what it printed.
function M.failed_notice(name, code, err)
    local why = (err or ""):gsub("%s+$", "")
    return "The \"" .. name .. "\" shortcut failed (exit " .. tostring(code) .. ")"
        .. (why ~= "" and (": " .. why) or "") .. ", so Do Not Disturb didn't change."
end

M.SHORTCUTS = "/usr/bin/shortcuts"

-- What waits to run when `new` is asked for while `wanted` waits: the last
-- request wins, except that a toggle composes with what's waiting. Two
-- toggles cancel out, and a toggle after an on or off that hasn't run yet
-- flips it.
function M.queued(wanted, new)
    if new ~= M.DND_TOGGLE or wanted == nil then
        return new
    end
    if wanted == M.DND_TOGGLE then
        return nil
    end
    if wanted == M.DND_ON then
        return M.DND_OFF
    end
    if wanted == M.DND_OFF then
        return M.DND_ON
    end
    return new
end

-- Runs Do Not Disturb's shortcuts one at a time, in request order, keeping
-- only the latest waiting request (M.queued), so a quick second Super+P
-- can't race the first and leave the wrong one last. `run(path, args,
-- done(code, err, out))` runs a command, as runner.lua does, and returns
-- whether it started; `report(text)` logs and notifies. Each shortcut is
-- looked for in `shortcuts list` before its first run, and a missing one
-- is said once.
function M.driver(run, report)
    local self = { busy = false, wanted = nil }
    local found, said = {}, {}
    local pump

    local function finish()
        self.busy = false
        pump()
    end

    local function unstartable()
        report("tilemo couldn't start " .. M.SHORTCUTS .. ", so Do Not Disturb didn't change."
            .. " It needs macOS 12 or later.")
        finish()
    end

    local function run_shortcut(name)
        local started = run(M.SHORTCUTS, { "run", name }, function(code, err)
            if code ~= 0 then
                report(M.failed_notice(name, code, err))
            end
            finish()
        end)
        if not started then
            unstartable()
        end
    end

    pump = function()
        if self.busy or self.wanted == nil then
            return
        end
        local name = self.wanted
        self.wanted = nil
        self.busy = true
        if found[name] then
            run_shortcut(name)
            return
        end
        local started = run(M.SHORTCUTS, { "list" }, function(code, err, out)
            if code ~= 0 then
                report("tilemo couldn't list your shortcuts (exit " .. tostring(code) .. ")"
                    .. ((err or "") ~= "" and (": " .. err:gsub("%s+$", "")) or "")
                    .. ", so Do Not Disturb didn't change.")
                finish()
                return
            end
            if #M.missing(out, { name }) == 0 then
                found[name] = true
                run_shortcut(name)
                return
            end
            if not said[name] then
                said[name] = true
                report(M.setup_notice({ name }))
            end
            finish()
        end)
        if not started then
            unstartable()
        end
    end

    function self.request(name)
        self.wanted = M.queued(self.wanted, name)
        pump()
    end

    return self
end

return M
