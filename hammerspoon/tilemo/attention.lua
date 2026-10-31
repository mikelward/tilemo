-- What wants attention (SPEC.md §14.2), for Super+Tab and the menu bar.
-- A Dock badge appearing or rising marks the app; a window title gaining
-- an unread count, such as "Chat (3)", or a window taking focus unasked
-- (SPEC.md §14.1), marks the window. A mark clears when you focus that
-- window or app. Pure Lua.

local M = {}
M.__index = M

function M.new()
    return setmetatable({ marks = {}, badges = {}, counts = {}, clock = 0 }, M)
end

-- The unread count in a title: "Chat (3)", "(3) Inbox", or none.
function M.count(title)
    local n = (title or ""):match("%((%d+)%)")
    return n and tonumber(n) or 0
end

-- A badge's count: a number, or 1 for a non-numeric badge such as "•".
local function badge_count(label)
    if not label or label == "" then
        return 0
    end
    return tonumber(label) or 1
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
        return x.kind == m.kind and x.app == m.app and x.id == m.id
    end)
    table.insert(self.marks, 1, m)
end

-- An app's Dock badge now reads `label`.
function M:badge(app, label)
    local n = badge_count(label)
    if n > (self.badges[app] or 0) then
        self:mark({ kind = "app", app = app })
    end
    self.badges[app] = n
end

-- One reading of every Dock badge, as { app, label } pairs. An app missing
-- from it has no badge now, maybe because it quit, so its next badge counts
-- as new.
function M:dock(list)
    local seen = {}
    for _, b in ipairs(list) do
        seen[b.app] = true
        self:badge(b.app, b.label)
    end
    for app in pairs(self.badges) do
        if not seen[app] then
            self.badges[app] = nil
        end
    end
end

-- A window's title now reads `title`.
function M:title(id, app, title)
    local n = M.count(title)
    if n > (self.counts[id] or 0) then
        self:mark({ kind = "window", id = id, app = app })
    end
    self.counts[id] = n
end

-- Window `id` of `app` activated itself without a grant (SPEC.md §14.1).
function M:activated(id, app)
    self:mark({ kind = "window", id = id, app = app })
end

-- You focused window `id` of `app`: its marks, and its app's, clear.
function M:focused(id, app)
    remove(self.marks, function(m)
        return m.id == id or (m.kind == "app" and m.app == app)
    end)
end

function M:gone(id)
    self.counts[id] = nil
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
