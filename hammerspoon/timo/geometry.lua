-- Window geometry for the tide layouts (SPEC.md §6), kept free of any
-- Hyprland API so it can be tested with plain Lua.
--
-- Every function takes the work area as a box {x, y, w, h} and returns one
-- box per tiled window, in window order: masters first, then the stack.
-- Boxes are on whole pixels and neighbors share an edge, so the tiles cover
-- the area exactly with no gaps and no overlap.

local M = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end
M.clamp = clamp

-- Cut [start, start + len) into pieces weighted by `weights`, on integer
-- edges. Rounding each edge rather than each size keeps the pieces
-- contiguous and their total exactly `len`.
local function spans(start, len, weights)
    local total = 0
    for _, wt in ipairs(weights) do
        total = total + wt
    end
    local out = {}
    local acc = 0
    local prev = math.floor(start + 0.5)
    for i, wt in ipairs(weights) do
        acc = acc + wt
        local edge = math.floor(start + len * acc / total + 0.5)
        out[i] = { pos = prev, size = edge - prev }
        prev = edge
    end
    return out
end

local function equal(n)
    local w = {}
    for i = 1, n do
        w[i] = 1
    end
    return w
end

-- Boxes for columns across `area`, weighted by `weights`.
function M.columns(area, weights)
    local boxes = {}
    local ys = spans(area.y, area.h, { 1 })[1]
    for i, s in ipairs(spans(area.x, area.w, weights)) do
        boxes[i] = { x = s.pos, y = ys.pos, w = s.size, h = ys.size }
    end
    return boxes
end

-- `n` equal rows down `area`.
function M.rows(area, n)
    local boxes = {}
    local xs = spans(area.x, area.w, { 1 })[1]
    for i, s in ipairs(spans(area.y, area.h, equal(n))) do
        boxes[i] = { x = xs.pos, y = s.pos, w = xs.size, h = s.size }
    end
    return boxes
end

local function append(dst, src)
    for _, b in ipairs(src) do
        dst[#dst + 1] = b
    end
    return dst
end

-- The width fraction for a lone window. `rules` is a list of
-- {min_aspect = a, width = f}; the rule with the largest min_aspect that the
-- area's aspect ratio reaches wins, and nothing matching means full width.
function M.single_width(area, rules)
    local aspect = area.h > 0 and area.w / area.h or 0
    local best, width = -1, 1.0
    for _, r in ipairs(rules or {}) do
        if aspect >= r.min_aspect and r.min_aspect > best then
            best, width = r.min_aspect, r.width
        end
    end
    return clamp(width, 0.1, 1.0)
end

-- A lone window, centered at `single_width` of the area.
function M.single(area, rules)
    local f = M.single_width(area, rules)
    if f >= 1.0 then
        return M.columns(area, { 1 })
    end
    local side = (1 - f) / 2
    return { M.columns(area, { side, f, side })[2] }
end

-- Master column on the left, stack on the right (dwm "tile").
function M.tile(area, n, o)
    if n <= 0 then
        return {}
    end
    local m = clamp(o.nmaster or 1, 0, n)
    if m == 0 or m == n then
        return M.rows(area, n)
    end
    local cols = M.columns(area, { o.mfact, 1 - o.mfact })
    return append(M.rows(cols[1], m), M.rows(cols[2], n - m))
end

-- Master centered with a stack either side. With a single stack window
-- there is nothing to balance, so it is master + one column. Stack windows
-- alternate right, left, right... so adding one never moves the others to
-- the other side.
function M.threecol(area, n, o)
    if n <= 0 then
        return {}
    end
    local m = clamp(o.nmaster or 1, 1, n)
    local s = n - m
    if s == 0 then
        return M.rows(area, n)
    end
    if s == 1 then
        local cols = M.columns(area, { o.mfact, 1 - o.mfact })
        return append(M.rows(cols[1], m), { cols[2] })
    end
    local side = (1 - o.mfact) / 2
    local cols = M.columns(area, { side, o.mfact, side })
    local nright = math.ceil(s / 2)
    local right = M.rows(cols[3], nright)
    local left = M.rows(cols[1], s - nright)
    local boxes = M.rows(cols[2], m)
    local r, l = 0, 0
    for k = 1, s do
        if k % 2 == 1 then
            r = r + 1
            boxes[#boxes + 1] = right[r]
        else
            l = l + 1
            boxes[#boxes + 1] = left[l]
        end
    end
    return boxes
end

-- Masters as full-height columns side by side, the rest stacked on the
-- right. With no stack the masters share the whole width.
function M.twocol(area, n, o)
    if n <= 0 then
        return {}
    end
    local m = clamp(o.nmaster or 2, 1, n)
    if m == n then
        return M.columns(area, equal(n))
    end
    local weights = {}
    for i = 1, m do
        weights[i] = o.mfact / m
    end
    weights[m + 1] = 1 - o.mfact
    local cols = M.columns(area, weights)
    local boxes = {}
    for i = 1, m do
        boxes[i] = cols[i]
    end
    return append(boxes, M.rows(cols[m + 1], n - m))
end

-- Every window fills the area; the focused one is on top.
function M.monocle(area, n)
    local boxes = {}
    for i = 1, n do
        boxes[i] = M.columns(area, { 1 })[1]
    end
    return boxes
end

M.modes = { "tile", "threecol", "twocol", "monocle" }

-- Boxes for `n` windows in `mode`. A lone window follows the single-window
-- rule in every mode.
function M.arrange(mode, area, n, o, single_rules)
    if n == 1 then
        return M.single(area, single_rules)
    end
    local f = M[mode]
    if type(f) ~= "function" then
        error("unknown layout mode: " .. tostring(mode))
    end
    return f(area, n, o or {})
end

return M
