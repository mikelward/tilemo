-- The volume popover (SPEC.md §8), as tide's (tide §7.4): under the bar's
-- speaker, a slider and mute for the output in use, the outputs to pick
-- from, and a link to Sound settings. This is the part with no
-- Hammerspoon in it: what the page shows, where it goes, and what its
-- messages do. volume_hs.lua draws it.

local M = {}

M.WIDTH = 300
-- The header, slider row, a row per output and the settings row, in px,
-- as volume.html draws them.
M.ROW = 30
M.CHROME = 112
-- No taller than this, the rows scroll past it.
M.MAX_HEIGHT = 480

-- What the page shows. `audio` is the bar's reading of the output in use
-- ({ name, volume, muted } with the monitor's DDC reading merged in, as
-- bar_hs.lua reads it; volume nil with no control), `outputs` each output
-- device's { uid, name }, and `current` the uid in use. `live` is whether
-- the slider sets the volume as it moves; a DDC monitor's is set once it's
-- let go, since each change is a slow run of its tool.
function M.state(audio, outputs, current, over_ddc)
    local list = {}
    for _, o in ipairs(outputs or {}) do
        if type(o.uid) == "string" then
            list[#list + 1] = { uid = o.uid, name = o.name or o.uid, current = o.uid == current }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.uid < b.uid
    end)
    local out = { outputs = list, live = not over_ddc }
    if audio then
        out.name = audio.name
        if audio.volume ~= nil then
            out.volume = math.max(0, math.min(100, math.floor(audio.volume + 0.5)))
        end
        out.muted = audio.muted == true
        out.can_mute = audio.muted ~= nil
    end
    return out
end

-- The popover's height for `n` outputs.
function M.height(n)
    return math.min(M.MAX_HEIGHT, M.CHROME + M.ROW * n)
end

-- Where the popover goes: just under bar `frame`, its right edge under the
-- speaker's (`right`, in the bar's own px), kept on the bar's display.
function M.frame(frame, right, n)
    local w, h = M.WIDTH, M.height(n)
    local x = frame.x + (tonumber(right) or frame.w) - w
    x = math.max(frame.x, math.min(x, frame.x + frame.w - w))
    return { x = x, y = frame.y + frame.h, w = w, h = h }
end

-- Does what a message from the page asks, through `act`: set_volume(v),
-- set_mute(on), use(uid) for an output, settings(), close().
function M.handle(body, act)
    if type(body) ~= "table" then
        return
    end
    if body.volume ~= nil then
        local v = tonumber(body.volume)
        if v then
            act.set_volume(math.max(0, math.min(100, math.floor(v + 0.5))))
        end
    elseif body.mute ~= nil then
        act.set_mute(body.mute == true)
    elseif type(body.output) == "string" then
        act.use(body.output)
    elseif body.settings then
        act.settings()
    elseif body.close then
        act.close()
    end
end

return M
