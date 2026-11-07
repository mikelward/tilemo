-- The Displays page's displays (displays.lua), through hs.screen: each one's
-- modes, where it is, whether it's the main one, and its brightness.

local displays = require("tide.displays")
local ddc = require("tide.ddc")

local M = {}

-- `tide` is the started tide module: its adapter. `changed()` is
-- called as a display comes, goes or changes, for the page to redraw.
function M.new(tide, changed)
    local self = {}
    local log = tide.adapter.log
    local a = tide.adapter
    -- An external display's brightness over DDC, by UUID: { id, cur, max },
    -- read with the bar's DDC tool (ddc.lua) for a display macOS can't set.
    local over = {}
    -- The displays' generation, bumped as they come and go, so a read begun
    -- before can't put back what it found.
    local generation = 0

    -- Every run of the DDC tool goes through one queue, one job at a time,
    -- so reads and sets reach the monitor in the order asked: a read can't
    -- answer with a level from before a set, nor one set overtake another.
    local queue, busy = {}, false
    local function pump()
        if busy then
            return
        end
        local job = table.remove(queue, 1)
        if not job then
            return
        end
        busy = true
        job.run(function()
            busy = false
            pump()
        end)
    end
    local function enqueue(job)
        queue[#queue + 1] = job
        pump()
    end
    local said

    local function frame(s)
        local f = s:fullFrame()
        return { x = f.x, y = f.y, w = f.w, h = f.h }
    end

    local function find(uuid)
        for _, s in ipairs(hs.screen.allScreens() or {}) do
            if s:getUUID() == uuid then
                return s
            end
        end
    end

    function self.state()
        local primary = hs.screen.primaryScreen()
        local main = primary and primary:getUUID()
        local readings = {}
        for _, s in ipairs(hs.screen.allScreens() or {}) do
            local brightness = s:getBrightness()
            local d = over[s:getUUID()]
            local over_ddc = type(brightness) ~= "number" and d ~= nil
            if over_ddc then
                brightness = d.cur / d.max
            end
            readings[#readings + 1] = {
                uuid = s:getUUID(),
                name = s:name(),
                main = s:getUUID() == main,
                frame = frame(s),
                mode = s:currentMode(),
                modes = s:availableModes(),
                brightness = type(brightness) == "number" and brightness or nil,
                over_ddc = over_ddc,
            }
        end
        return displays.state(readings)
    end

    local function say(why)
        if why ~= said then
            said = why
            if why then
                log("displays: brightness over DDC: " .. why)
            end
        end
    end

    -- Runs each of `steps` in turn with the tool, then done(results), or
    -- fail(why) when one can't start.
    local function sequence(tool, steps, done, fail)
        local results = {}
        local function step(i)
            if i > #steps then
                return done(results)
            end
            if not a.run(tool.path, steps[i], function(code, err, out)
                results[i] = { code = code, out = out, err = err }
                step(i + 1)
            end) then
                fail("couldn't start " .. tool.name)
            end
        end
        step(1)
    end

    -- Reads the brightness over DDC of each display macOS can't set, one
    -- run at a time, then redraws, and done(). Without the bar's DDC tool
    -- there's none.
    local function read_now(done)
        local began = generation
        local tool = ddc.find(a.exists)
        local externals = {}
        for _, s in ipairs(hs.screen.allScreens() or {}) do
            if type(s:getBrightness()) ~= "number" then
                externals[#externals + 1] = { uuid = s:getUUID(), name = s:name() }
            end
        end
        if not tool or #externals == 0 then
            over = {}
            return done()
        end
        local function finish(why)
            say(why)
            changed()
            done()
        end
        sequence(tool, { ddc.list_args(tool) }, function(r)
            local list = tool.name == "m1ddc" and ddc.parse_m1ddc_list(r[1].out) or ddc.parse_ddcctl_list(r[1].out)
            local found, i = {}, 0
            local function next_screen()
                i = i + 1
                local s = externals[i]
                if not s then
                    if began == generation then
                        over = found
                    end
                    return finish(nil)
                end
                -- With more than one display to match, the tool's lone one
                -- is this only if it says so, not by default.
                local d = ddc.pick(list, s, s.name)
                if d and #externals > 1 and not ddc.matches(d, s) then
                    d = nil
                end
                if not d then
                    return next_screen()
                end
                local id = ddc.id(tool, d)
                sequence(tool, ddc.luminance_reads(tool, id), function(results)
                    local l, why = ddc.parse_luminance(tool, results)
                    if l then
                        found[s.uuid] = { id = id, cur = l.cur, max = l.max }
                    else
                        say(why)
                    end
                    next_screen()
                end, finish)
            end
            next_screen()
        end, finish)
    end

    -- A read, queued; one waiting is enough, as it reads what's there when
    -- it runs.
    function self.read_ddc()
        for _, job in ipairs(queue) do
            if job.kind == "read" then
                return
            end
        end
        enqueue({ kind = "read", run = read_now })
    end

    local function missing(uuid)
        log("displays: no display " .. tostring(uuid) .. " now")
    end

    self.act = {
        -- Only a size macOS lists for the display, at the scale it's at.
        set_size = function(uuid, w, h)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            local mode = s:currentMode()
            for _, m in ipairs(displays.sizes(s:availableModes(), mode and mode.scale)) do
                if m.w == w and m.h == h then
                    if not s:setMode(m.w, m.h, m.scale, m.freq, m.depth) then
                        log("displays: macOS didn't set " .. tostring(s:name()) .. " to " .. w .. "x" .. h)
                    end
                    return
                end
            end
            log("displays: " .. tostring(s:name()) .. " has no " .. w .. "x" .. h .. " at its scale")
        end,
        place = function(uuid, place)
            local s, main = find(uuid), hs.screen.primaryScreen()
            if not s or not main then
                return missing(uuid)
            end
            if s:getUUID() == main:getUUID() then
                return
            end
            local x, y = displays.origin(place, frame(s), frame(main))
            if x and not s:setOrigin(x, y) then
                log("displays: macOS didn't move " .. tostring(s:name()) .. " " .. place)
            end
        end,
        make_main = function(uuid)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            if not s:setPrimary() then
                log("displays: macOS didn't make " .. tostring(s:name()) .. " the main display")
            end
        end,
        set_brightness = function(uuid, level)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            if type(s:getBrightness()) ~= "number" and over[uuid] then
                -- A set waiting for this display takes the newer level, so
                -- only the last asked for is sent after the one running.
                for _, job in ipairs(queue) do
                    if job.kind == "set" and job.uuid == uuid then
                        job.level = level
                        return
                    end
                end
                local job = { kind = "set", uuid = uuid, level = level }
                function job.run(done)
                    local d = over[uuid]
                    local tool = d and ddc.find(a.exists)
                    if not tool then
                        return done()
                    end
                    local raw = ddc.raw(job.level, d.max)
                    if not a.run(tool.path, ddc.luminance_set(tool, d.id, raw), function(code, err, out)
                        if code ~= 0 then
                            log("displays: " .. tool.name .. " couldn't set " .. tostring(s:name()) .. "'s brightness: "
                                .. tostring((out ~= "" and out) or err))
                        elseif over[uuid] then
                            over[uuid].cur = raw
                        end
                        changed()
                        done()
                    end) then
                        log("displays: couldn't start " .. tool.name)
                        done()
                    end
                end
                enqueue(job)
                return
            end
            if not s:setBrightness(level / 100) then
                log("displays: macOS didn't set " .. tostring(s:name()) .. "'s brightness")
            end
        end,
    }

    -- A message from the settings page, if it's one of the Displays page's.
    function self.handle(body)
        return displays.handle(body, self.act)
    end

    -- Kept, as Hammerspoon stops one that's collected.
    self.watch = hs.screen.watcher.new(function()
        -- What was read may now name the wrong display: forget it, and
        -- read again.
        generation = generation + 1
        over = {}
        changed()
        self.read_ddc()
    end)
    self.watch:start()

    return self
end

return M
