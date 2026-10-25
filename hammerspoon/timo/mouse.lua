-- Super+drag and Super+right-drag (SPEC.md §5.3): where the window would go
-- for a given pointer position. Pure Lua; the adapter draws the outline and
-- timo moves the real window only when the button comes up, since moving
-- another app's window on every mouse event lags.

local M = {}

-- The smallest a resize can make a window.
M.MIN = 100

-- Start a drag. `kind` is "move" or "resize"; a resize moves the edges
-- nearest where the pointer went down.
function M.grab(kind, frame, x, y)
    return {
        kind = kind,
        x = x,
        y = y,
        frame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
        h = x < frame.x + frame.w / 2 and -1 or 1,
        v = y < frame.y + frame.h / 2 and -1 or 1,
    }
end

-- Where the window goes with the pointer at x, y.
function M.update(drag, x, y)
    local f = drag.frame
    local dx, dy = x - drag.x, y - drag.y
    if drag.kind == "move" then
        return { x = f.x + dx, y = f.y + dy, w = f.w, h = f.h }
    end
    local b = { x = f.x, y = f.y, w = f.w, h = f.h }
    if drag.h < 0 then
        local w = math.max(M.MIN, f.w - dx)
        b.x, b.w = f.x + f.w - w, w
    else
        b.w = math.max(M.MIN, f.w + dx)
    end
    if drag.v < 0 then
        local h = math.max(M.MIN, f.h - dy)
        b.y, b.h = f.y + f.h - h, h
    else
        b.h = math.max(M.MIN, f.h + dy)
    end
    return b
end

-- The split (mfact) that puts a resized tile's edge where it was dragged.
-- `i` is the tile's place in the visible order, `n` how many tiles, `area`
-- the work area, `old` the tile's box before and `new` after. Returns nil
-- when the drag didn't move an edge the split controls.
-- The width, as a fraction of the area, that a drag gives a lone window,
-- which stays centered: the edge you moved sets how far it reaches from the
-- center, and the other edge follows. Nil when no edge moved.
function M.single_width_for(area, old, new)
    local W = area.w
    if W <= 0 then
        return nil
    end
    local cx = area.x + W / 2
    local f
    if new.x + new.w ~= old.x + old.w then
        f = 2 * (new.x + new.w - cx) / W
    elseif new.x ~= old.x then
        f = 2 * (cx - new.x) / W
    else
        return nil
    end
    return math.max(0.1, math.min(1.0, f))
end

function M.mfact_for(mode, opts, i, n, area, old, new)
    local W = area.w
    if W <= 0 or n < 2 then
        return nil
    end
    local function frac(v)
        return (v - area.x) / W
    end
    local left_moved = new.x ~= old.x
    local right_moved = new.x + new.w ~= old.x + old.w
    local m = opts.nmaster or 1
    if mode == "tile" or (mode == "threecol" and n - m == 1) then
        if m >= n then
            return nil
        end
        if i <= m and right_moved then
            return frac(new.x + new.w)
        elseif i > m and left_moved then
            return frac(new.x)
        end
    elseif mode == "threecol" then
        -- With no stack the masters are full-width rows and mfact isn't
        -- used, so a drag sets nothing.
        if m >= n then
            return nil
        end
        -- The master stays centered, so the split comes from how far the
        -- dragged edge is from the area's center, not from the width.
        local cx = area.x + W / 2
        local right = new.x + new.w
        if i <= m then
            if right_moved then
                return 2 * (right - cx) / W
            elseif left_moved then
                return 2 * (cx - new.x) / W
            end
        elseif new.x + new.w / 2 > cx then
            -- A right-hand stack window: its inner edge is its left.
            if left_moved then
                return 2 * (new.x - cx) / W
            end
        elseif right_moved then
            return 2 * (cx - right) / W
        end
    elseif mode == "twocol" then
        if m >= n then
            return nil
        end
        -- Master i spans the boundaries at (i - 1) and i times mfact / m.
        if i <= m and right_moved then
            return frac(new.x + new.w) * m / i
        elseif i <= m and i > 1 and left_moved then
            return frac(new.x) * m / (i - 1)
        elseif i > m and left_moved then
            return frac(new.x)
        end
    end
    return nil
end

return M
