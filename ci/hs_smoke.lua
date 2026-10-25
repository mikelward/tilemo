-- A smoke test that runs inside a real Hammerspoon, on CI's macOS runner.
-- The fake in tests/ can't tell whether an hs.* function timo calls exists
-- in the Hammerspoon people install, so this checks that, then starts timo
-- and opens and closes the dashboard. Hosted runners can't grant
-- Accessibility, so nothing tiles: a failure here means a missing API or a
-- Lua error, not a layout bug.
--
-- ci/hs-smoke.sh points ~/.hammerspoon/init.lua at this file, with
-- TIMO_SMOKE_OUT set to where the results go.

local out_path = TIMO_SMOKE_OUT
local failed = false

-- Each line goes out as it's made, so a hang still shows how far it got.
local function say(fmt, ...)
    local line = string.format(fmt, ...)
    local f, err = io.open(out_path, "a")
    if not f then
        print("timo smoke: can't write " .. out_path .. ": " .. tostring(err))
        return
    end
    f:write(line, "\n")
    f:close()
end

local function fail(fmt, ...)
    failed = true
    say("FAIL " .. fmt, ...)
end

local function finish()
    say(failed and "RESULT fail" or "RESULT ok")
    -- Hammerspoon's os.exit is hs._exit, which only quits the app when its
    -- second argument is true.
    hs._exit(true, true)
end

say("Hammerspoon %s, %s", hs.processInfo.version, _VERSION)

-- Every hs.x.y timo names in its source, resolved here. hs loads its
-- extensions on first touch, so walking the path is the real lookup.
local dir = hs.configdir .. "/timo"
local seen = {}
for file in hs.fs.dir(dir) do
    if file:match("%.lua$") then
        local f = assert(io.open(dir .. "/" .. file))
        for line in f:lines() do
            local code = line:gsub("%-%-.*$", "")
            for path, stop in code:gmatch("%f[%w_](hs%.[%a_][%w_%.]*)()") do
                path = path:gsub("%.$", "")
                -- An assignment sets a slot that may start out nil
                -- (hs.shutdownCallback), so only its parent must exist.
                if code:sub(stop):match("^%s*=[^=]") then
                    path = path:match("^(.*)%.[^%.]+$")
                end
                if not seen[path] then
                    seen[path] = file
                end
            end
        end
        f:close()
    end
end
local paths = {}
for path in pairs(seen) do
    paths[#paths + 1] = path
end
table.sort(paths)
for _, path in ipairs(paths) do
    local v = _G
    for key in path:gmatch("[^%.]+") do
        local ok, next_v = pcall(function()
            return v[key]
        end)
        v = ok and next_v or nil
        if v == nil then
            break
        end
    end
    if v == nil then
        fail("%s (in %s) doesn't exist", path, seen[path])
    end
end
say("checked %d hs.* names", #paths)

-- Start timo as init.lua would, then open and close the dashboard.
local ok, err = xpcall(function()
    timo = require("timo")
    timo.start({})
end, debug.traceback)
if not ok then
    fail("timo.start: %s", err)
    finish()
    return
end
say("timo started")

ok, err = xpcall(function()
    timo.dashboard.show()
end, debug.traceback)
if not ok then
    fail("dashboard: %s", err)
    finish()
    return
end
say("dashboard shown")
-- Give the page a moment to load and run, then close it. Held in a global:
-- Hammerspoon stops a timer that's garbage collected.
smoke_timer = hs.timer.doAfter(3, function()
    local closed, close_err = xpcall(function()
        timo.dashboard.show()
    end, debug.traceback)
    if not closed then
        fail("closing the dashboard: %s", close_err)
    else
        say("dashboard opened and closed")
    end
    finish()
end)
