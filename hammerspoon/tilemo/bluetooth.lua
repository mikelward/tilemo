-- Whether Bluetooth is on, for the bar (SPEC.md §8), as tide's bar shows it.
-- Hammerspoon has no module for it, so tilemo asks blueutil (Homebrew,
-- `brew install blueutil`, which scripts' setup-macos --wm tilemo
-- installs): `blueutil -p` prints 1 or 0. Without it, or when it fails, the
-- icon hides and the log says why, once. Pure Lua: finding, running and
-- logging come from the caller.

local M = {}

-- Where Homebrew puts it: Apple silicon's prefix, then Intel's.
-- Hammerspoon's own PATH has neither.
M.CANDIDATES = { "/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil" }
M.ARGS = { "-p" }
M.MISSING = "blueutil isn't installed (brew install blueutil, or setup-macos --wm tilemo)"

-- The first candidate `exists(path)` says is there, or nil.
function M.find(exists)
    for _, p in ipairs(M.CANDIDATES) do
        if exists(p) then
            return p
        end
    end
end

-- `blueutil -p`'s exit code and output as { on }, or nil and why.
function M.parse(code, out, err)
    local text = (out or ""):match("^%s*(.-)%s*$")
    if code ~= 0 then
        local why = (err or ""):match("^%s*(.-)%s*$")
        return nil, "blueutil -p exited " .. tostring(code) .. (why ~= "" and ": " .. why or "")
    end
    if text == "1" then
        return { on = true }
    elseif text == "0" then
        return { on = false }
    end
    return nil, string.format("blueutil -p printed %q, not 1 or 0", text)
end

-- A poller: `opts.find()` gives blueutil's path or nil; `opts.run(path,
-- args, done)` starts it without waiting, calling done(code, out, err), and
-- returns false and why if it couldn't start; `opts.log(text)`;
-- `opts.changed()` once the state differs. `state` is { on } or nil (hide).
-- One run at a time, so a slow blueutil can't pile up.
function M.poller(opts)
    local self = { state = nil }
    local busy = false
    local said

    local function say(why)
        if why ~= said then
            said = why
            opts.log("bar: Bluetooth on/off hidden: " .. why)
        end
    end

    local function set(state)
        local before = self.state
        self.state = state
        if (before and before.on) ~= (state and state.on) or (before == nil) ~= (state == nil) then
            opts.changed()
        end
    end

    function self:poll()
        if busy then
            return
        end
        local path = opts.find()
        if not path then
            set(nil)
            say(M.MISSING)
            return
        end
        busy = true
        local started, why = opts.run(path, M.ARGS, function(code, out, err)
            busy = false
            local state, problem = M.parse(code, out, err)
            if state then
                said = nil
            else
                say(problem)
            end
            set(state)
        end)
        if not started then
            busy = false
            set(nil)
            say("couldn't start blueutil: " .. tostring(why))
        end
    end

    return self
end

return M
