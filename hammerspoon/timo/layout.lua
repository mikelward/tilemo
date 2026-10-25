-- Per-workspace layout state (SPEC.md §5): the window order, the mode and
-- each mode's mfact and master count. Pure Lua, so it tests without
-- Hammerspoon. The geometry itself is tide's, unchanged (geometry.lua).

local geometry = require("timo.geometry")

local M = { geometry = geometry }

-- tide's defaults (tide hypr/tide/layout.lua), so a workspace looks the same
-- on every desktop.
M.defaults = {
    ultrawide_aspect = 2.1,
    default_mode = { normal = "tile", ultrawide = "threecol" },
    single = {
        { min_aspect = 2.1, width = 0.8 },
        { min_aspect = 3.2, width = 0.6 },
    },
    modes = {
        tile = { mfact = 0.55, nmaster = 1 },
        threecol = { mfact = 0.5, nmaster = 1 },
        twocol = { mfact = 0.72, nmaster = 2 },
        monocle = {},
    },
    cycle = { "tile", "threecol", "twocol" },
    -- "end" of the stack, "top" of it, "next" after the focused window, or
    -- "master".
    new_window = "end",
    mfact_step = 0.025,
}

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = copy(v)
    end
    return out
end
M.copy = copy

local function index_of(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
end
M.index_of = index_of

-- A new workspace, in the default mode for its area's shape.
function M.new(id, area, config)
    config = config or M.defaults
    local aspect = area and area.h > 0 and area.w / area.h or 0
    local mode = aspect >= config.ultrawide_aspect and config.default_mode.ultrawide
        or config.default_mode.normal
    return { id = id, mode = mode, opts = copy(config.modes), order = {} }
end

-- Put `wid` into the order where config.new_window says. `focused` is the
-- window that had focus, for "next".
function M.insert(ws, wid, focused, config)
    config = config or M.defaults
    if index_of(ws.order, wid) then
        return
    end
    local where = config.new_window
    local nmaster = (ws.opts[ws.mode] or {}).nmaster or 1
    local pos = #ws.order + 1
    if where == "master" then
        pos = 1
    elseif where == "top" then
        pos = math.min(nmaster + 1, #ws.order + 1)
    elseif where == "next" then
        local i = focused and index_of(ws.order, focused)
        if i then
            pos = i + 1
        end
    end
    table.insert(ws.order, pos, wid)
end

function M.remove(ws, wid)
    local i = index_of(ws.order, wid)
    if i then
        table.remove(ws.order, i)
    end
end

-- The window `delta` places from `wid` in `ids`, wrapping round. `ids` is
-- the order filtered to what's visible.
function M.neighbor(ids, wid, delta)
    local n = #ids
    if n == 0 then
        return nil
    end
    local i = index_of(ids, wid)
    if not i then
        return ids[1]
    end
    return ids[(i - 1 + delta) % n + 1]
end

local function swap(list, a, b)
    local i, j = index_of(list, a), index_of(list, b)
    if i and j then
        list[i], list[j] = list[j], list[i]
    end
end

-- Swap `wid` with its neighbor `delta` places along `ids`.
function M.move(ws, ids, wid, delta)
    local other = M.neighbor(ids, wid, delta)
    if other and other ~= wid then
        swap(ws.order, wid, other)
    end
end

-- dwm's zoom: the master swaps with the next window; any other window
-- swaps with the master.
function M.swap_master(ws, ids, wid)
    if #ids < 2 or not index_of(ids, wid) then
        return
    end
    local other = ids[1] == wid and ids[2] or ids[1]
    swap(ws.order, wid, other)
end

function M.mfact(ws, delta)
    local o = ws.opts[ws.mode]
    if o and o.mfact then
        o.mfact = geometry.clamp(o.mfact + delta, 0.1, 0.9)
    end
end

function M.nmaster(ws, delta)
    local o = ws.opts[ws.mode]
    if o and o.nmaster then
        o.nmaster = math.max(1, o.nmaster + delta)
    end
end

-- Step through config.cycle; from monocle, step from the mode before it.
function M.cycle(ws, delta, config)
    config = config or M.defaults
    local list = config.cycle
    local from = ws.mode == "monocle" and (ws.prev_mode or list[1]) or ws.mode
    local i = index_of(list, from) or 1
    ws.prev_mode = nil
    ws.mode = list[(i - 1 + delta) % #list + 1]
end

function M.toggle_monocle(ws)
    if ws.mode == "monocle" then
        ws.mode = ws.prev_mode or M.defaults.default_mode.normal
        ws.prev_mode = nil
    else
        ws.prev_mode = ws.mode
        ws.mode = "monocle"
    end
end

-- Boxes for `ids` (the tiled, visible windows in order) in `area`, keyed by
-- window id.
function M.arrange(ws, area, ids, config)
    config = config or M.defaults
    -- A width you dragged a lone window to on this workspace beats the
    -- single-window rule.
    local single = config.single
    if ws.single_width then
        single = { { min_aspect = 0, width = ws.single_width } }
    end
    local boxes = geometry.arrange(ws.mode, area, #ids, ws.opts[ws.mode], single)
    local out = {}
    for i, wid in ipairs(ids) do
        out[wid] = boxes[i]
    end
    return out
end

return M
