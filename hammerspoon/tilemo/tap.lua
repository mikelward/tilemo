-- Tapping Super on its own opens the launcher (SPEC.md §7.2). Without
-- Karabiner's tap rule, tilemo watches modifier changes itself. A tap is
-- Super going down and up with nothing else in between: no other key, no
-- mouse button and no scroll, so Super+T, Super+drag and Super+click never
-- open the launcher (tide SPEC.md §8). Pure Lua.

local M = {}
M.__index = M

-- A tap held longer than this is a hold, not a tap.
M.MAX = 0.5

function M.new(on_tap)
    return setmetatable({ on_tap = on_tap, armed = false, since = 0 }, M)
end

-- The modifiers changed. `super_only` says whether exactly Super is down,
-- `none` whether nothing is.
function M:flags(super_only, none, now)
    if none then
        local fire = self.armed and not self.spoiled and now - self.since <= M.MAX
        self.armed, self.spoiled = false, false
        if fire then
            self.on_tap()
        end
    elseif super_only then
        if not self.armed and not self.spoiled then
            self.armed, self.since = true, now
        end
    else
        -- Another modifier is down, before Super or with it: no tap until
        -- every modifier is let go.
        self.spoiled = true
    end
end

-- Any key, mouse button or scroll while Super is down spoils the tap.
function M:other()
    if self.armed then
        self.spoiled = true
    end
end

return M
