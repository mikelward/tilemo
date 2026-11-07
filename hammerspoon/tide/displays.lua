-- The settings window's Displays page (SPEC.md §15), as tide's (tide SPEC.md
-- §16): for each display, its name, the size it looks like (macOS's scaled
-- resolution) and the others it offers at its scale, where it goes beside
-- the main display, whether it's the main one, and its brightness where
-- macOS can set it. This is the part with no Hammerspoon in it:
-- displays_hs.lua reads and sets them.

local M = {}

-- Where a display goes beside the main one, as tide's Place steps through
-- its positions.
M.PLACES = {
    { place = "right", label = "To the right" },
    { place = "left", label = "To the left" },
    { place = "above", label = "Above" },
    { place = "below", label = "Below" },
}

local function placed(place)
    for _, p in ipairs(M.PLACES) do
        if p.place == place then
            return true
        end
    end
    return false
end

-- The sizes a display offers at `scale`, from its modes (hs.screen's
-- availableModes: { w, h, scale, freq, depth } each), smallest first: one
-- per width and height, the mode with the highest refresh rate, then
-- depth, for each.
function M.sizes(modes, scale)
    local by = {}
    for _, m in pairs(modes or {}) do
        if type(m) == "table" and m.scale == scale and tonumber(m.w) and tonumber(m.h) then
            local key = m.w .. "x" .. m.h
            local have = by[key]
            local better = not have or (m.freq or 0) > (have.freq or 0)
                or ((m.freq or 0) == (have.freq or 0) and (m.depth or 0) > (have.depth or 0))
            if better then
                by[key] = m
            end
        end
    end
    local out = {}
    for _, m in pairs(by) do
        out[#out + 1] = m
    end
    table.sort(out, function(a, b)
        if a.w * a.h ~= b.w * b.h then
            return a.w * a.h < b.w * b.h
        end
        return a.w < b.w
    end)
    return out
end

-- Which side of the main display's `main` frame `frame` is beyond, or nil
-- when they overlap, as the main display itself, or a mirror, does.
function M.place_of(frame, main)
    if frame.x >= main.x + main.w then
        return "right"
    elseif frame.x + frame.w <= main.x then
        return "left"
    elseif frame.y + frame.h <= main.y then
        return "above"
    elseif frame.y >= main.y + main.h then
        return "below"
    end
end

-- The origin that puts a display of `frame`'s size `place` of the main
-- display's `main` frame, edge to edge, with their top or left edges lined
-- up, as macOS's arrangement snaps one. Nil for a place there's none of.
function M.origin(place, frame, main)
    if place == "right" then
        return main.x + main.w, main.y
    elseif place == "left" then
        return main.x - frame.w, main.y
    elseif place == "above" then
        return main.x, main.y - frame.h
    elseif place == "below" then
        return main.x, main.y + main.h
    end
end

-- What the page shows, from each display's reading: { uuid, name, main,
-- frame (its full frame), mode (currentMode's { w, h, scale }), modes
-- (availableModes), brightness (0 to 1, or nil where macOS can't set it) }.
-- The main display first, then left to right.
function M.state(readings)
    local main
    for _, r in ipairs(readings or {}) do
        if r.main then
            main = r
        end
    end
    local out = {}
    for _, r in ipairs(readings or {}) do
        local d = { uuid = r.uuid, name = r.name or "Display", main = r.main == true, sizes = {} }
        if r.mode then
            d.size = { w = r.mode.w, h = r.mode.h }
            for _, m in ipairs(M.sizes(r.modes, r.mode.scale)) do
                d.sizes[#d.sizes + 1] = { w = m.w, h = m.h, current = m.w == r.mode.w and m.h == r.mode.h }
            end
        end
        if main and not r.main and r.frame and main.frame then
            d.place = M.place_of(r.frame, main.frame)
        end
        if type(r.brightness) == "number" then
            d.brightness = math.max(0, math.min(100, math.floor(r.brightness * 100 + 0.5)))
            -- Set once the slider's let go, as a monitor's volume over DDC.
            d.over_ddc = r.over_ddc == true or nil
        end
        d.x = r.frame and r.frame.x or 0
        out[#out + 1] = d
    end
    table.sort(out, function(a, b)
        if a.main ~= b.main then
            return a.main
        end
        return a.x < b.x
    end)
    for _, d in ipairs(out) do
        d.x = nil
    end
    return { displays = out, places = M.PLACES }
end

-- Does what a message from the page asks, through `act`: set_size(uuid,
-- w, h), place(uuid, place), make_main(uuid) and set_brightness(uuid,
-- level, 0 to 100). Returns whether it was one of the Displays page's.
function M.handle(body, act)
    if type(body) ~= "table" then
        return false
    end
    local function uuid(t)
        return type(t) == "table" and type(t.uuid) == "string" and t.uuid or nil
    end
    if body.displaySize ~= nil then
        local t = body.displaySize
        local w, h = tonumber(type(t) == "table" and t.w), tonumber(type(t) == "table" and t.h)
        if uuid(t) and w and h then
            act.set_size(t.uuid, w, h)
        end
    elseif body.displayPlace ~= nil then
        local t = body.displayPlace
        if uuid(t) and placed(t.place) then
            act.place(t.uuid, t.place)
        end
    elseif body.displayMain ~= nil then
        if type(body.displayMain) == "string" then
            act.make_main(body.displayMain)
        end
    elseif body.displayBrightness ~= nil then
        local t = body.displayBrightness
        local level = tonumber(type(t) == "table" and t.level)
        if uuid(t) and level then
            act.set_brightness(t.uuid, math.max(0, math.min(100, math.floor(level + 0.5))))
        end
    else
        return false
    end
    return true
end

return M
