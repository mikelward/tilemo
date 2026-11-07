-- A monitor's own speaker volume over DDC/CI, for the bar (SPEC.md §8).
-- macOS has no volume control for a monitor's speakers over HDMI or
-- DisplayPort, so hs.audiodevice reads none; the monitor itself answers
-- MCCS's audio speaker volume (VCP 0x62) and mute (0x8D) over DDC. tide
-- asks a Homebrew tool, found at Apple silicon's or Intel's prefix:
--
--   m1ddc (Apple silicon, `brew install m1ddc`): `display list`, then
--     `display <uuid> get volume`, `max volume`, `get mute`, and `set`;
--   ddcctl (Intel, `brew install ddcctl`): run bare, it lists the external
--     displays' UUIDs in its numbering; then `-d <n> -v ? -m ?` and
--     `-d <n> -v <value>` or `-m <1|2>`.
--
-- scripts' setup-macos --wm tide installs the one for the Mac. m1ddc
-- comes first, since ddcctl's IOFramebuffer calls don't reach displays on
-- Apple silicon. Pure Lua: finding, running and logging come from the
-- caller, and every run is asynchronous, one at a time.

local M = {}

M.TOOLS = {
    { name = "m1ddc", paths = { "/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc" } },
    { name = "ddcctl", paths = { "/opt/homebrew/bin/ddcctl", "/usr/local/bin/ddcctl" } },
}
M.MISSING = "neither m1ddc (Apple silicon) nor ddcctl (Intel) is installed "
    .. "(brew install m1ddc or ddcctl, or setup-macos --wm tide)"

-- MCCS's mute (VCP 0x8D): 1 is muted, 2 is not.
M.MUTED, M.UNMUTED = 1, 2

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function same(a, b)
    return a ~= nil and b ~= nil and trim(a):lower() == trim(b):lower() and trim(a) ~= ""
end

-- The first tool whose path `exists(path)` says is there, as { name, path },
-- or nil.
function M.find(exists)
    for _, t in ipairs(M.TOOLS) do
        for _, p in ipairs(t.paths) do
            if exists(p) then
                return { name = t.name, path = p }
            end
        end
    end
end

-- The display an audio output plays through, from `screens` ({ uuid, name
-- }, as hs.screen gives them): the one named as the device is, as macOS
-- names a monitor's speakers, else the only external one.
function M.screen_for(device, screens)
    local external = {}
    for _, s in ipairs(screens or {}) do
        if same(s.name, device) then
            return s
        end
        if not (s.name or ""):find("^Built%-in") then
            external[#external + 1] = s
        end
    end
    if #external == 1 then
        return external[1]
    end
end

-- `m1ddc display list`'s "[1] LG HDR 4K (UUID)" lines.
function M.parse_m1ddc_list(out)
    local list = {}
    for line in (out or ""):gmatch("[^\n]+") do
        local i, name, uuid = line:match("^%s*%[(%d+)%]%s*(.-)%s*%(([%x%-]+)%)%s*$")
        if i then
            list[#list + 1] = { index = tonumber(i), name = name, uuid = uuid }
        end
    end
    return list
end

-- A bare `ddcctl`'s external displays, numbered as its -d takes them, from
-- its "D: CGDisplay <uuid> dispID(...)" lines; with none (an older build),
-- its count, when that's one.
function M.parse_ddcctl_list(out)
    local list = {}
    for uuid in (out or ""):gmatch("D: CGDisplay ([%x%-]+) dispID") do
        list[#list + 1] = { index = #list + 1, uuid = uuid }
    end
    if #list == 0 and (out or ""):match("found 1 external display") then
        list[1] = { index = 1 }
    end
    return list
end

-- Whether the tool's display `d` is `screen` ({ uuid, name }), by UUID or
-- by name, with no fallback.
function M.matches(d, screen)
    return d ~= nil and screen ~= nil and (same(d.uuid, screen.uuid) or same(d.name, screen.name))
end

-- Which of a tool's displays is `screen`, playing `device`: by UUID, then by
-- name, then the only one.
function M.pick(list, screen, device)
    for _, d in ipairs(list) do
        if screen and same(d.uuid, screen.uuid) then
            return d
        end
    end
    for _, d in ipairs(list) do
        if same(d.name, device) then
            return d
        end
    end
    if #list == 1 then
        return list[1]
    end
end

-- A run's one number, as m1ddc's get and max print, or nil and why.
function M.parse_number(code, out, err, what)
    if code ~= 0 then
        local why = trim(out) ~= "" and trim(out) or trim(err)
        return nil, what .. " exited " .. tostring(code) .. (why ~= "" and ": " .. why or "")
    end
    local n = tonumber(trim(out))
    if not n then
        return nil, string.format("%s printed %q, not a number", what, trim(out))
    end
    return n
end

-- ddcctl's "I: VCP control #98 (0x62) = current: 30, max: 100" lines, by
-- control number. It exits 0 even when the monitor doesn't answer, saying
-- so on an "E:" line instead.
function M.parse_ddcctl_values(out)
    local got = {}
    for id, cur, max in (out or ""):gmatch("I: VCP control #(%d+) %([^)]*%) = current: (%d+), max: (%d+)") do
        got[tonumber(id)] = { cur = tonumber(cur), max = tonumber(max) }
    end
    return got
end

-- The bar's reading from the monitor's raw values: the volume as 0…100 of
-- its max, and whether it's muted (nil when it didn't say).
function M.reading(cur, max, mute)
    if not cur or not max or max <= 0 then
        return nil
    end
    local muted
    if mute == M.MUTED then
        muted = true
    elseif mute == M.UNMUTED then
        muted = false
    end
    return { volume = math.floor(cur * 100 / max + 0.5), muted = muted, max = max }
end

-- A volume of 0…100 in the monitor's own units.
function M.raw(volume, max)
    return math.floor(math.max(0, math.min(100, volume)) * max / 100 + 0.5)
end

-- A monitor's brightness, MCCS's luminance (VCP 0x10), for the Displays
-- page: the tool's list of displays, how it names one, the runs that read
-- the luminance and its maximum, and the run that sets it.
function M.list_args(tool)
    return tool.name == "m1ddc" and { "display", "list" } or {}
end

function M.id(tool, d)
    return tool.name == "m1ddc" and d.uuid or d.index
end

function M.luminance_reads(tool, id)
    if tool.name == "m1ddc" then
        return { { "display", id, "get", "luminance" }, { "display", id, "max", "luminance" } }
    end
    return { { "-d", tostring(id), "-b", "?" } }
end

-- The reads' results ({ code, out, err } each) as { cur, max }, or nil and
-- why.
function M.parse_luminance(tool, results)
    if tool.name == "m1ddc" then
        local cur, why = M.parse_number(results[1].code, results[1].out, results[1].err, "m1ddc get luminance")
        local max, why2 = M.parse_number(results[2].code, results[2].out, results[2].err, "m1ddc max luminance")
        if not cur or not max or max <= 0 then
            return nil, why or why2 or "m1ddc read a maximum luminance of 0"
        end
        return { cur = cur, max = max }
    end
    local b = M.parse_ddcctl_values(results[1].out)[0x10]
    if not b or b.max <= 0 then
        return nil, "ddcctl read no brightness (exit " .. tostring(results[1].code) .. ")"
    end
    return { cur = b.cur, max = b.max }
end

function M.luminance_set(tool, id, raw)
    if tool.name == "m1ddc" then
        return { "display", id, "set", "luminance", tostring(raw) }
    end
    return { "-d", tostring(id), "-b", tostring(raw) }
end

-- Whether reading `state` is the monitor volume of output reading `audio`
-- ({ volume, muted, name }, as hs.audiodevice gives them): macOS has no
-- volume for it, and the reading is of that device.
function M.applies(audio, state)
    return audio ~= nil and audio.volume == nil and state ~= nil and state.device == audio.name
end

-- Output reading `audio` with the monitor's volume and mute in place of
-- macOS's missing ones, when `state` applies to it.
function M.merge(audio, state)
    if not M.applies(audio, state) then
        return audio
    end
    local out = { name = audio.name, volume = state.volume, muted = audio.muted }
    if state.muted ~= nil then
        out.muted = state.muted
    end
    return out
end

-- The volume reader and setter. `opts.find()` gives { name, path } or nil;
-- `opts.run(path, args, done)` starts the tool without waiting, calling
-- done(code, out, err), and returns false and why if it couldn't start;
-- `opts.log(text)`; `opts.changed()` once the reading differs.
--
-- self:poll(device, screens) reads the volume of output `device` (its
-- name), or forgets it with no device. self.state is { device, volume,
-- muted, max } or nil (none read). self:set_volume(v) and self:set_mute(on)
-- change it, showing the change at once. Runs go one at a time, in order,
-- so a slow monitor can't pile them up.
function M.monitor(opts)
    local self = { state = nil }
    local queue, busy = {}, false
    local said
    local target -- { key, id } for the device and displays last picked
    -- The display self.state was read from, { key, id }: a change goes there,
    -- never to a display picked since.
    local source
    -- Bumped by every change and every switch of output or displays, so a
    -- read begun before it can't put back what it replaced.
    local generation = 0
    -- A poll asked for while another run was out, done once they're through.
    local again
    -- Bumped only by forget(): a change queued before it was for a display
    -- that may since have gone or been renumbered, so it's dropped.
    local epoch = 0

    local function say(why)
        if why ~= said then
            said = why
            opts.log("bar: monitor volume unread: " .. why)
        end
    end

    local function set(state)
        local b = self.state
        self.state = state
        local differs = (b == nil) ~= (state == nil)
            or (b and state and (b.device ~= state.device or b.volume ~= state.volume or b.muted ~= state.muted))
        if differs then
            opts.changed()
        end
    end

    -- Runs `job(next)` after every job before it; a job calls next() once
    -- it's done.
    local function pump()
        if busy or #queue == 0 then
            return
        end
        busy = true
        local job = table.remove(queue, 1)
        job(function()
            busy = false
            if #queue == 0 and again then
                local a = again
                again = nil
                self:poll(a.device, a.screens)
                return
            end
            pump()
        end)
    end

    local function enqueue(job)
        queue[#queue + 1] = job
        pump()
    end

    -- Runs `args` with the tool, calling back(code, out, err), or failing
    -- with why if it couldn't start.
    local function run(tool, args, back, fail)
        local ok, why = opts.run(tool.path, args, back)
        if not ok then
            fail("couldn't start " .. tool.name .. ": " .. tostring(why))
        end
    end

    -- Each run in `steps` ({ args, ... }) in turn, then done(results), or
    -- fail(why) if one couldn't start.
    local function sequence(tool, steps, done, fail)
        local results = {}
        local function step(i)
            if i > #steps then
                return done(results)
            end
            run(tool, steps[i], function(code, out, err)
                results[i] = { code = code, out = out, err = err }
                step(i + 1)
            end, fail)
        end
        step(1)
    end

    local function list_args(tool)
        if tool.name == "m1ddc" then
            return { "display", "list" }
        end
        return {}
    end

    local function read(tool, id, key, device, done)
        local began = generation
        -- A reading taken before the latest change is stale: the change
        -- is on its way to the monitor, and the next poll reads it back.
        local function take(state)
            if began == generation then
                source = { key = key, id = id }
                set(state)
            end
        end
        local fail = function(why)
            say(why)
            if began == generation then
                source = nil
                set(nil)
            end
            done()
        end
        if tool.name == "m1ddc" then
            local function a(...)
                return { "display", id, ... }
            end
            sequence(tool, { a("get", "volume"), a("max", "volume"), a("get", "mute") }, function(r)
                local cur, why = M.parse_number(r[1].code, r[1].out, r[1].err, "m1ddc get volume")
                local max, why2 = M.parse_number(r[2].code, r[2].out, r[2].err, "m1ddc max volume")
                -- A monitor that can't say whether it's muted still has a volume.
                local mute = M.parse_number(r[3].code, r[3].out, r[3].err, "m1ddc get mute")
                local state = M.reading(cur, max, mute)
                if not state then
                    target = nil
                    return fail(why or why2 or "m1ddc read a maximum volume of 0")
                end
                said = nil
                state.device = device
                take(state)
                done()
            end, fail)
        else
            run(tool, { "-d", tostring(id), "-v", "?", "-m", "?" }, function(code, out)
                local got = M.parse_ddcctl_values(out)
                local v, m = got[0x62], got[0x8D]
                local state = v and M.reading(v.cur, v.max, m and m.cur)
                if not state then
                    target = nil
                    return fail("ddcctl -d " .. tostring(id) .. " read no volume (exit " .. tostring(code) .. ")")
                end
                said = nil
                state.device = device
                take(state)
                done()
            end, fail)
        end
    end

    -- Forgets the reading and the display it came from, and drops any read
    -- still out, so nothing reaches a display that's no longer the one.
    local function forget()
        generation = generation + 1
        epoch = epoch + 1
        target = nil
        source = nil
        set(nil)
    end

    function self:poll(device, screens)
        if not device then
            again = nil
            forget()
            return
        end
        local tool = opts.find()
        if not tool then
            forget()
            say(M.MISSING)
            return
        end
        local screen = M.screen_for(device, screens)
        -- Every display, not just this one: ddcctl numbers them in order,
        -- so another one coming or going can renumber this one.
        local all = {}
        for _, s in ipairs(screens or {}) do
            all[#all + 1] = s.uuid or ""
        end
        table.sort(all)
        local key = table.concat({ tool.path, device, screen and screen.uuid or "", table.concat(all, ",") }, "\n")
        if (source and source.key ~= key) or (target and target.key ~= key) then
            forget()
        end
        if busy or #queue > 0 then
            again = { device = device, screens = screens }
            return
        end
        enqueue(function(done)
            if target and target.key == key then
                return read(tool, target.id, key, device, done)
            end
            local began = generation
            run(tool, list_args(tool), function(_, out)
                if began ~= generation then
                    return done()
                end
                local list = tool.name == "m1ddc" and M.parse_m1ddc_list(out) or M.parse_ddcctl_list(out)
                local d = M.pick(list, screen, device)
                if not d then
                    say(string.format("%s lists no display for %q", tool.name, device))
                    forget()
                    return done()
                end
                -- m1ddc takes a display by its listed UUID, ddcctl by number.
                local id = tool.name == "m1ddc" and d.uuid or d.index
                target = { key = key, id = id }
                read(tool, id, key, device, done)
            end, function(why)
                say(why)
                forget()
                done()
            end)
        end)
    end

    -- Sets the read monitor's volume or mute, showing it at once.
    local function change(args_for, apply)
        local s = self.state
        local tool = opts.find()
        if not s or not source or not tool then
            return false
        end
        local id = source.id
        local queued_in = epoch
        local next_state = { device = s.device, volume = s.volume, muted = s.muted, max = s.max }
        apply(next_state)
        generation = generation + 1
        set(next_state)
        enqueue(function(done)
            if queued_in ~= epoch then
                opts.log("bar: dropped a monitor volume change: the output or displays changed first")
                return done()
            end
            run(tool, args_for(tool, id, next_state), function(code, out, err)
                if code ~= 0 then
                    local why = trim(out) ~= "" and trim(out) or trim(err)
                    opts.log("bar: couldn't set the monitor's volume: " .. tool.name .. " exited " .. tostring(code)
                        .. (why ~= "" and ": " .. why or ""))
                end
                done()
            end, function(why)
                opts.log("bar: couldn't set the monitor's volume: " .. why)
                done()
            end)
        end)
        return true
    end

    function self:set_volume(volume)
        return change(function(tool, id, s)
            local raw = tostring(M.raw(s.volume, s.max))
            if tool.name == "m1ddc" then
                return { "display", id, "set", "volume", raw }
            end
            return { "-d", tostring(id), "-v", raw }
        end, function(s)
            s.volume = math.max(0, math.min(100, volume))
        end)
    end

    function self:set_mute(on)
        return change(function(tool, id)
            if tool.name == "m1ddc" then
                return { "display", id, "set", "mute", on and "on" or "off" }
            end
            return { "-d", tostring(id), "-m", tostring(on and M.MUTED or M.UNMUTED) }
        end, function(s)
            s.muted = on
        end)
    end

    return self
end

return M
