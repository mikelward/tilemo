-- The Bluetooth page's adapter and paired devices (bluetooth.lua), through
-- blueutil, the bar's (bluetooth.lua's poller), run without waiting, one
-- read at a time: as the window opens, every few seconds while it's open,
-- so a device that connects by itself shows, and after each change.

local bluetooth = require("tide.bluetooth")

local M = {}

-- Seconds between reads while the window's open.
M.EVERY = 5

-- `tide` is the started tide module: its adapter (run, exists, after,
-- log) and bar, if it's on. `changed()` is called as what the page shows
-- changes, for it to redraw.
function M.new(tide, changed)
    local self = {}
    local a = tide.adapter
    local reading = {}
    -- An address being connected or disconnected, or the power switched.
    local busy = {}
    local switching = false
    -- Why the last change failed, until the next one.
    local failed
    local reading_now, again = false, false
    local watching, timer = false, nil
    local said
    local drawn

    local function find()
        return bluetooth.find(a.exists)
    end

    function self.state()
        return bluetooth.page_state({
            on = reading.on,
            devices = reading.devices,
            busy = busy,
            switching = switching,
            problem = reading.problem or failed,
        })
    end

    -- Redraws when what the page shows differs; a problem's logged once,
    -- until it changes or clears.
    local function show()
        local problem = reading.problem
        if problem ~= said then
            said = problem
            if problem then
                a.log("settings: Bluetooth: " .. problem)
            end
        end
        local now = hs.json.encode(self.state())
        if now ~= drawn then
            drawn = now
            changed()
        end
    end

    local function start(path, args, done)
        local started = a.run(path, args, done)
        if not started then
            return false, "couldn't start blueutil " .. table.concat(args, " ")
        end
        return true
    end

    local function schedule()
        if watching and not timer then
            timer = a.after(M.EVERY, function()
                timer = nil
                self.refresh()
            end)
        end
    end

    local function finish(r)
        reading = r
        reading_now = false
        show()
        if again then
            again = false
            self.refresh()
        else
            schedule()
        end
    end

    -- Reads whether it's on, then, while it is, the paired devices.
    function self.refresh()
        if reading_now then
            again = true
            return
        end
        local path = find()
        if not path then
            return finish({ problem = bluetooth.MISSING })
        end
        reading_now = true
        local ok, why = start(path, bluetooth.ARGS, function(code, err, out)
            local power, problem = bluetooth.parse(code, out, err)
            if not power then
                return finish({ problem = problem })
            end
            if not power.on then
                return finish({ on = false })
            end
            local listed, not_listed = start(path, bluetooth.PAIRED_ARGS, function(code2, err2, out2)
                local devices, problem2 = bluetooth.parse_paired(code2, out2, err2, hs.json.decode)
                finish({ on = true, devices = devices, problem = problem2 })
            end)
            if not listed then
                finish({ on = true, problem = not_listed })
            end
        end)
        if not ok then
            finish({ problem = why })
        end
    end

    -- Read every few seconds while `open`, from now; stop when it isn't.
    function self.watch(open)
        watching = open
        if open then
            self.refresh()
        elseif timer then
            timer.stop()
            timer = nil
        end
    end

    -- A device's name, as last read, or its address.
    local function named(address)
        for _, d in ipairs(reading.devices or {}) do
            if d.address == address then
                return d.name
            end
        end
        return address
    end

    -- Runs blueutil with `args`, then reads again, and has the bar read
    -- too, so its icon follows. A failure is logged with blueutil's why, and
    -- the page says `what` failed until the next change.
    local function change(args, what, done)
        failed = nil
        local path = find()
        if not path then
            reading = { problem = bluetooth.MISSING }
            done()
            return show()
        end
        local ok, why = start(path, args, function(code, err)
            if code ~= 0 then
                local text = (err or ""):match("^%s*(.-)%s*$")
                a.log("settings: blueutil " .. table.concat(args, " ") .. " exited " .. tostring(code)
                    .. (text ~= "" and ": " .. text or ""))
                failed = "Couldn't " .. what .. ": " .. (text ~= "" and text or ("blueutil exited " .. tostring(code)))
            end
            done()
            self.refresh()
            if tide.bar and tide.bar.bluetooth then
                tide.bar.bluetooth:poll()
            end
        end)
        if not ok then
            a.log("settings: " .. why)
            failed = "Couldn't " .. what .. ": " .. why
            done()
        end
        show()
    end

    self.act = {
        set_power = function(on)
            if switching then
                return
            end
            switching = true
            change({ "--power", on and "1" or "0" }, "turn Bluetooth " .. (on and "on" or "off"), function()
                switching = false
            end)
        end,
        connect = function(address)
            if busy[address] then
                return
            end
            busy[address] = "connecting"
            change({ "--connect", address }, "connect " .. named(address), function()
                busy[address] = nil
            end)
        end,
        disconnect = function(address)
            if busy[address] then
                return
            end
            busy[address] = "disconnecting"
            change({ "--disconnect", address }, "disconnect " .. named(address), function()
                busy[address] = nil
            end)
        end,
    }

    -- A message from the settings page, if it's one of the Bluetooth page's.
    function self.handle(body)
        return bluetooth.handle(body, self.act)
    end

    return self
end

return M
