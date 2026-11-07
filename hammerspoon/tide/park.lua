-- Where a hidden workspace's window goes: parked off screen, as AeroSpace
-- does (SPEC.md §6). macOS won't let a window go wholly off screen, so a
-- parked window keeps a 1 pt sliver inside a corner of its display, and
-- the rest of it reaches out past that corner. Pure geometry: boxes are
-- { x, y, w, h }, in the global coordinates macOS gives every display,
-- y growing downward.

local M = {}

-- How much of a parked window stays inside its display, in points.
M.SLIVER = 1

-- The corners tried, in order, each as where the window's top-left goes
-- for display `d` and a window `w` by `h`: the window reaches outward
-- from the corner, keeping one sliver-sized square inside. Bottom-right
-- first, as AeroSpace parks.
local CORNERS = {
    { name = "bottom-right", at = function(d, w, h)
        return d.x + d.w - M.SLIVER, d.y + d.h - M.SLIVER
    end },
    { name = "bottom-left", at = function(d, w, h)
        return d.x + M.SLIVER - w, d.y + d.h - M.SLIVER
    end },
    { name = "top-right", at = function(d, w, h)
        return d.x + d.w - M.SLIVER, d.y + M.SLIVER - h
    end },
    { name = "top-left", at = function(d, w, h)
        return d.x + M.SLIVER - w, d.y + M.SLIVER - h
    end },
}
M.CORNERS = {}
for i, c in ipairs(CORNERS) do
    M.CORNERS[i] = c.name
end

-- How far two boxes overlap, as a width and a height (0 when apart).
local function overlap(a, b)
    local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    return math.max(0, w), math.max(0, h)
end

local function same_box(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Where to park a window of `size` ({ w, h }, or any box) whose display's
-- full frame is `full`, with `fulls` every display's full frame, that one
-- included: a box the window's size, at the first corner, in CORNERS'
-- order, where it overlaps no other display, so it can't show on a
-- display beside or below. If every corner touches another display, the
-- bottom-right one. Returns the box and the corner's name.
function M.spot(full, fulls, size)
    local w, h = size.w, size.h
    for _, c in ipairs(CORNERS) do
        local x, y = c.at(full, w, h)
        local box = { x = x, y = y, w = w, h = h }
        local clear = true
        for _, other in ipairs(fulls or {}) do
            if not same_box(other, full) then
                local ow, oh = overlap(box, other)
                if ow > 0 and oh > 0 then
                    clear = false
                    break
                end
            end
        end
        if clear then
            return box, c.name
        end
    end
    local x, y = CORNERS[1].at(full, w, h)
    return { x = x, y = y, w = w, h = h }, CORNERS[1].name
end

-- Whether `frame` is parked, or as good as: no display in `fulls` shows
-- more of it than a sliver. A window macOS reports where a park left it,
-- after a restart, reads as parked.
function M.hidden(frame, fulls)
    if not frame then
        return false
    end
    for _, d in ipairs(fulls or {}) do
        local ow, oh = overlap(frame, d)
        if ow > M.SLIVER and oh > M.SLIVER then
            return false
        end
    end
    return true
end

return M
