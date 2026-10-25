-- A smoke test that runs inside a real Hammerspoon, on CI's macOS runner.
-- The fake in tests/ can't tell whether an hs.* function timo calls exists
-- in the Hammerspoon people install, so this checks that, then starts timo,
-- checks its bar is up, opens and closes the dashboard, and tiles a few
-- windows below the bar. GitHub's macOS runners come with Accessibility
-- granted, so the tiling is real.
--
-- ci/hs-smoke.sh points ~/.hammerspoon/init.lua at this file, with
-- TIMO_SMOKE_OUT set to where the results go.

local bar = require("timo.bar")
local layout = require("timo.layout")

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

-- Open TextEdit windows and check timo tiles them where its layout says
-- (SPEC.md §5). TextEdit, because `open` can give it several windows
-- without asking for Automation, which a runner can't grant.
local APP = "com.apple.TextEdit"
local WANT = 3
local SLACK = 2
local TILE_WAIT = 20

local function app_windows(wm)
    local out = {}
    for id, w in pairs(wm.windows) do
        if w.app == APP and not w.floating then
            out[#out + 1] = id
        end
    end
    return out
end

-- Where each tiled window is against where timo's layout puts it, or nil
-- and why not yet.
local function tiling_misses(wm)
    if #app_windows(wm) < WANT then
        return nil, string.format("%d of %d TextEdit windows tiled", #app_windows(wm), WANT)
    end
    local misses, checked = {}, 0
    for uuid, n in pairs(wm.screen_ws) do
        local s = wm:screen_by_uuid(uuid)
        local ws = wm.workspaces[n]
        local ids = wm:tiled(n)
        local boxes = s and ws and layout.arrange(ws, s.area, ids, wm.layout) or {}
        for _, id in ipairs(ids) do
            local want = boxes[id]
            local st = wm.a.state(id)
            local got = st and st.frame
            if want and got then
                if wm.windows[id].app == APP then
                    checked = checked + 1
                end
                local off = math.max(math.abs(got.x - want.x), math.abs(got.y - want.y),
                    math.abs(got.w - want.w), math.abs(got.h - want.h))
                if off > SLACK then
                    misses[#misses + 1] = string.format("window %s at %d,%d %dx%d, want %d,%d %dx%d", tostring(id),
                        got.x, got.y, got.w, got.h, want.x, want.y, want.w, want.h)
                end
            end
        end
    end
    if checked < WANT then
        return nil, string.format("%d of %d TextEdit windows on a shown workspace", checked, WANT)
    end
    return misses
end

-- The bar: a strip along the top of each display, its page loaded, and the
-- tiling area starting below it.
local function check_bar()
    if not timo.bar then
        fail("bar: timo started without its bar")
        return
    end
    local frames = timo.bar.frames()
    local n = 0
    for _, s in ipairs(timo.adapter.screens()) do
        local want = bar.strip(s.area, bar.HEIGHT)
        local got = frames[s.uuid]
        local v = timo.bar.views[s.uuid]
        if not got then
            fail("bar: none on display %s", s.uuid)
        else
            local off = math.max(math.abs(got.x - want.x), math.abs(got.y - want.y),
                math.abs(got.w - want.w), math.abs(got.h - want.h))
            if off > SLACK then
                fail("bar: at %d,%d %dx%d, want %d,%d %dx%d", got.x, got.y, got.w, got.h,
                    want.x, want.y, want.w, want.h)
            end
            if not (v and v.ready) then
                fail("bar: its page on display %s didn't load (got as far as %s)", s.uuid, v and v.nav or "nothing")
            end
            n = n + 1
        end
        local tiling = timo.wm:screen_by_uuid(s.uuid).area
        if tiling.y ~= want.y + want.h then
            fail("bar: tiling starts at y=%d, want %d", tiling.y, want.y + want.h)
        end
    end
    -- Which status items this Mac has; the network one is always drawn.
    local items = {}
    for k in pairs(timo.bar.icons) do
        items[#items + 1] = k
    end
    table.sort(items)
    if not timo.bar.icons.network then
        fail("bar: no network status item")
    end
    -- Anything a page reported: a script error or a failed load.
    for _, e in ipairs(timo.bar.errors) do
        fail("bar: %s", e)
    end
    say("bar up on %d display(s), with %s", n, table.concat(items, ", "))
end

-- Wait for every bar page to load, up to a deadline, then check the bar
-- and call `next`.
local BAR_WAIT = 15

local function wait_for_bar(next)
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_bar_poll = hs.timer.doEvery(0.5, function()
        local ready = timo.bar ~= nil
        for _, v in pairs(timo.bar and timo.bar.views or {}) do
            ready = ready and v.ready
        end
        if ready or hs.timer.secondsSinceEpoch() - started > BAR_WAIT then
            smoke_bar_poll:stop()
            check_bar()
            next()
        end
    end)
end

local function check_tiling()
    if not hs.accessibilityState() then
        fail("tiling: Hammerspoon doesn't have Accessibility on this runner")
        finish()
        return
    end
    local dir = os.getenv("TMPDIR") or "/tmp"
    local files = {}
    for i = 1, WANT do
        local path = string.format("%s/timo-smoke-%d.txt", dir, i)
        local f, err = io.open(path, "w")
        if not f then
            fail("tiling: can't write %s: %s", path, tostring(err))
            finish()
            return
        end
        f:close()
        files[#files + 1] = "'" .. path .. "'"
    end
    local output, opened = hs.execute("open -a TextEdit " .. table.concat(files, " ") .. " 2>&1")
    if not opened then
        fail("tiling: couldn't open TextEdit: %s", output)
        finish()
        return
    end
    -- TextEdit and timo's watchers take a moment; wait for them, up to a
    -- deadline, rather than a fixed time.
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_poll = hs.timer.doEvery(0.5, function()
        local misses, why = tiling_misses(timo.wm)
        local done = misses and #misses == 0
        if done or hs.timer.secondsSinceEpoch() - started > TILE_WAIT then
            smoke_poll:stop()
            if done then
                say("%d TextEdit windows tiled", WANT)
            elseif not misses then
                fail("tiling: %s after %ds", why, TILE_WAIT)
            else
                for _, m in ipairs(misses) do
                    fail("tiling: %s", m)
                end
            end
            finish()
        end
    end)
end

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
        finish()
        return
    end
    say("dashboard opened and closed")
    wait_for_bar(check_tiling)
end)
