-- A three-finger swipe across the trackpad steps through workspaces, as
-- tide's does (conf `hyprland.lua`, SPEC.md §7.2). The fingers move left
-- for the next workspace and right for the previous one, as macOS's own
-- swipe between Spaces goes. One swipe steps once, however far it goes.
-- Pure Lua: the adapter feeds it each gesture event's touches.

local M = {}
M.__index = M

M.FINGERS = 3
-- How far the fingers must move together, as a share of the trackpad's
-- width, before it counts as a swipe.
M.DISTANCE = 0.15
-- And how much more sideways than up or down.
M.SLOPE = 2

-- start()'s `swipe`: true or nil for on, false for off.
function M.check(v)
    if v ~= nil and type(v) ~= "boolean" then
        error("swipe must be true or false, not " .. tostring(v), 3)
    end
end

function M.new(on_swipe)
    return setmetatable({ on_swipe = on_swipe }, M)
end

local function mean(touches, start)
    local x, y, n = 0, 0, 0
    for id, p in pairs(touches) do
        if not start or start.at[id] then
            x, y, n = x + p.x, y + p.y, n + 1
        end
    end
    return x / n, y / n, n
end

-- A swipe that steps `wm`'s workspaces, as Super+PgUp and PgDn do.
function M.for_wm(wm)
    return M.new(function(d)
        wm:act("step", d)
    end)
end

-- The fingers on the trackpad now: an array of { id = ..., x = ..., y = ... }
-- in the trackpad's own 0 to 1 coordinates, y going up. `dragging` says
-- a mouse button is down, as Accessibility's three-finger drag holds one:
-- that's a drag, not a swipe, until every finger lifts.
function M:touches(list, dragging)
    local now = {}
    local count = 0
    for _, p in ipairs(list) do
        now[p.id] = p
        count = count + 1
    end
    if count == 0 then
        -- Every finger is up: the next swipe can start.
        self.start, self.done = nil, false
        return
    end
    if dragging then
        self.start, self.done = nil, true
        return
    end
    if count ~= M.FINGERS or self.done then
        -- A finger more or fewer: not this swipe. Wait for every finger to
        -- lift before another can start, so a finger lifting at the end of
        -- a swipe can't start a second one.
        if self.start then
            self.start, self.done = nil, true
        end
        return
    end
    if not self.start then
        local x, y = mean(now)
        self.start = { at = now, x = x, y = y }
        return
    end
    local x, y, n = mean(now, self.start)
    if n ~= M.FINGERS then
        -- The same number of fingers, but not the same ones.
        self.start, self.done = nil, true
        return
    end
    local dx, dy = x - self.start.x, y - self.start.y
    if math.abs(dx) >= M.DISTANCE and math.abs(dx) >= M.SLOPE * math.abs(dy) then
        self.start, self.done = nil, true
        self.on_swipe(dx < 0 and 1 or -1)
    end
end

return M
