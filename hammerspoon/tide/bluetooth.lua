-- Whether Bluetooth is on, for the bar (SPEC.md §8), as tide's bar shows it.
-- Hammerspoon has no module for it, so tide asks blueutil (Homebrew,
-- `brew install blueutil`, which scripts' setup-macos --wm tide
-- installs): `blueutil -p` prints 1 or 0. Without it, or when it fails, the
-- icon hides and the log says why, once. Pure Lua: finding, running and
-- logging come from the caller.

local M = {}

-- Where Homebrew puts it: Apple silicon's prefix, then Intel's.
-- Hammerspoon's own PATH has neither.
M.CANDIDATES = { "/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil" }
M.ARGS = { "-p" }
M.MISSING = "blueutil isn't installed (brew install blueutil, or setup-macos --wm tide)"

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

-- The settings window's Bluetooth page (SPEC.md §15), as tide's Bluetooth
-- popover (tide SPEC.md §7.4): Bluetooth on or off, then the paired
-- devices, connected first, each connected or disconnected with a click.
-- Pairing a new one is Bluetooth settings' job. bluetooth_hs.lua runs
-- blueutil for these.
M.PAIRED_ARGS = { "--paired", "--format", "json" }

-- A device's address as blueutil prints it, `xx-xx-xx-xx-xx-xx`, or nil.
-- The page can send only one of these, so nothing else reaches
-- blueutil's arguments: not a name, which it would search for, nor an
-- option.
function M.address(a)
    if type(a) ~= "string" then
        return nil
    end
    local hex = "%x%x"
    local dashes = "^" .. hex .. string.rep("%-" .. hex, 5) .. "$"
    local colons = "^" .. hex .. string.rep(":" .. hex, 5) .. "$"
    if a:match(dashes) or a:match(colons) then
        return a
    end
    return nil
end

-- `blueutil --paired --format json`'s exit code and output as a list of
-- { address, name, connected }, or nil and why. `decode` is hs.json's. A
-- device with no name is called by its address, as tide's are.
function M.parse_paired(code, out, err, decode)
    if code ~= 0 then
        local why = (err or ""):match("^%s*(.-)%s*$")
        return nil, "blueutil --paired exited " .. tostring(code) .. (why ~= "" and ": " .. why or "")
    end
    local ok, list = pcall(decode, out or "")
    if not ok or type(list) ~= "table" then
        return nil, "blueutil --paired printed something that isn't a JSON list"
    end
    local devices = {}
    for _, d in ipairs(list) do
        local address = type(d) == "table" and M.address(d.address)
        if address then
            local name = type(d.name) == "string" and d.name ~= "" and d.name or address
            devices[#devices + 1] = { address = address, name = name, connected = d.connected == true }
        end
    end
    return devices
end

local STATUS = { connecting = "Connecting…", disconnecting = "Disconnecting…" }

-- What the page shows, from blueutil's readings: `on` (nil when it can't
-- be read), the paired `devices`, `busy` (each address being connected or
-- disconnected, as "connecting" or "disconnecting"), whether the power's
-- being `switching`, and the `problem`, if any. The devices are listed
-- only while it's on, connected first, then by name, as tide's popover
-- has them, each with its status line.
function M.page_state(r)
    r = r or {}
    local busy = r.busy or {}
    local devices = {}
    if r.on == true then
        for _, d in ipairs(r.devices or {}) do
            local doing = busy[d.address]
            devices[#devices + 1] = {
                address = d.address,
                name = d.name,
                connected = d.connected,
                busy = doing ~= nil,
                status = STATUS[doing] or (d.connected and "Connected" or ""),
            }
        end
    end
    table.sort(devices, function(a, b)
        if a.connected ~= b.connected then
            return a.connected
        end
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then
            return x < y
        end
        return a.address < b.address
    end)
    return {
        on = r.on,
        switching = r.switching == true,
        devices = devices,
        problem = r.problem,
    }
end

-- Does what a message from the page asks, through `act`: set_power(on),
-- connect(address) and disconnect(address). A message naming anything but
-- an address is the page's, and does nothing. Returns whether it was one
-- of the Bluetooth page's.
function M.handle(body, act)
    if type(body) ~= "table" then
        return false
    end
    if body.bluetoothPower ~= nil then
        act.set_power(body.bluetoothPower == true)
    elseif body.bluetoothConnect ~= nil then
        local a = M.address(body.bluetoothConnect)
        if a then
            act.connect(a)
        end
    elseif body.bluetoothDisconnect ~= nil then
        local a = M.address(body.bluetoothDisconnect)
        if a then
            act.disconnect(a)
        end
    else
        return false
    end
    return true
end

return M
