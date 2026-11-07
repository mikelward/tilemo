-- What wants attention (SPEC.md §14.2), for Super+A and the bar. A
-- notification marks its app; a bell, or a window taking focus unasked
-- (SPEC.md §14.1), marks the window. A mark clears when you focus that
-- window or app. Pure Lua.

local M = {}
M.__index = M

function M.new()
    return setmetatable({ marks = {}, clock = 0 }, M)
end

local function remove(list, pred)
    for i = #list, 1, -1 do
        if pred(list[i]) then
            table.remove(list, i)
        end
    end
end

function M:mark(m)
    -- A muted app or site gets no mark (SPEC.md §14.2); `muted(m)` says
    -- which, set by the window manager.
    if self.muted and self.muted(m) then
        return
    end
    self.clock = self.clock + 1
    m.at = self.clock
    remove(self.marks, function(x)
        return x.kind == m.kind and x.app == m.app and x.id == m.id and x.site == m.site
    end)
    table.insert(self.marks, 1, m)
end

-- `app` sent a notification (SPEC.md §14.2): the app is marked, and
-- `site`, a browser notification's host or nil, says which of its windows.
function M:notified(app, site)
    self:mark({ kind = "app", app = app, site = site })
end

-- Window `id` of `app` rang the bell.
function M:rang(id, app)
    self:mark({ kind = "window", id = id, app = app })
end

-- Window `id` of `app` activated itself without a grant (SPEC.md §14.1).
function M:activated(id, app)
    self:mark({ kind = "window", id = id, app = app })
end

-- You focused window `id` of `app`, whose front tab is on `host` (or nil):
-- its marks clear, and its app's, except a browser notification's from
-- another site, which waits for a window on that site.
function M:focused(id, app, host)
    remove(self.marks, function(m)
        return m.id == id or (m.kind == "app" and m.app == app and (not m.site or m.site == host))
    end)
end

function M:gone(id)
    remove(self.marks, function(m)
        return m.id == id
    end)
end

-- Drop the marks `muted` now covers, after a mute.
function M:prune()
    remove(self.marks, function(m)
        return self.muted and self.muted(m) or false
    end)
end

-- The marks, most recent first.
function M:list()
    return self.marks
end

return M
