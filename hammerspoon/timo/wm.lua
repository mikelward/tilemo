-- The window manager: which window is on which workspace, tiled or
-- floating, and the actions the keys call (SPEC.md §5). It talks to macOS
-- only through an adapter (hs_adapter.lua on a Mac, a fake in the tests),
-- so all of its decisions test without Hammerspoon. The adapter's `facts`
-- is the full, slower read used to decide a new window; `state` is the
-- quick one used on every retile.
--
-- Until workspaces land (SPEC.md §6), each display shows one workspace of
-- its own, numbered in display order.

local layout = require("timo.layout")
local mouse = require("timo.mouse")
local rules = require("timo.rules")

local M = {}
M.__index = M

local function remove_value(list, v)
    for i = #list, 1, -1 do
        if list[i] == v then
            table.remove(list, i)
        end
    end
end

local set_big_on

-- How long to wait after the last window event before retiling, since one
-- window opening sends several (tico SPEC.md §5.3).
M.DEBOUNCE = 0.05
-- A float's size is capped at this share of its display (tide SPEC.md §6.4).
M.FLOAT_CAP = 0.8

function M.new(adapter, config)
    config = config or {}
    local self = setmetatable({
        a = adapter,
        layout = config.layout or layout.defaults,
        rules = rules.check(config.rules or {}, "rules"),
        windows = {},   -- id -> { id, app, ws, floating, big }
        workspaces = {}, -- number -> layout state
        screen_ws = {}, -- display uuid -> workspace number
        floats = {},    -- float ids, bottom to top
        mru = {},       -- workspace number -> ids, most recent first
        placed = {},    -- id -> the frame timo last gave it, as it landed
    }, M)
    return self
end

local function center(box)
    return box.x + box.w / 2, box.y + box.h / 2
end

local function inside(box, x, y)
    return x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h
end

-- The display whose area holds a window's center, or the first display.
function M:screen_for(frame)
    local screens = self.a.screens()
    if frame then
        local x, y = center(frame)
        for _, s in ipairs(screens) do
            if inside(s.full, x, y) then
                return s
            end
        end
    end
    return screens[1]
end

function M:screen_by_uuid(uuid)
    for _, s in ipairs(self.a.screens()) do
        if s.uuid == uuid then
            return s
        end
    end
end

-- Number each display's workspace in display order, keeping numbers already
-- given.
function M:map_screens()
    local used = {}
    local screens = self.a.screens()
    local present = {}
    for _, s in ipairs(screens) do
        present[s.uuid] = true
    end
    local lost = {}
    for uuid, n in pairs(self.screen_ws) do
        if present[uuid] then
            used[n] = true
        else
            self.screen_ws[uuid] = nil
            lost[n] = true
        end
    end
    for _, s in ipairs(screens) do
        if not self.screen_ws[s.uuid] then
            local n = 1
            while used[n] do
                n = n + 1
            end
            used[n] = true
            self.screen_ws[s.uuid] = n
        end
        local n = self.screen_ws[s.uuid]
        if not self.workspaces[n] then
            self.workspaces[n] = layout.new(n, s.area, self.layout)
            self.mru[n] = {}
        end
    end
    -- A display that went away leaves its windows on the first display that
    -- remains, where macOS puts them.
    local first = screens[1] and self.screen_ws[screens[1].uuid]
    if first and next(lost) then
        local ids = {}
        for id, w in pairs(self.windows) do
            if w.ws and lost[w.ws] then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local w = self.windows[id]
            layout.remove(self.workspaces[w.ws], id)
            remove_value(self.mru[w.ws], id)
            w.ws = first
            if not w.floating then
                layout.insert(self.workspaces[first], id, nil, self.layout)
            end
        end
    end
end

function M:ws_on_screen(s)
    return s and self.screen_ws[s.uuid]
end

-- The workspace keys act on: the focused window's, else the one on the
-- display under the pointer.
function M:current_ws()
    local w = self.windows[self.a.focused() or false]
    -- An ignored window, such as picture-in-picture, has no workspace.
    if w and w.ws then
        return w.ws
    end
    local uuid = self.a.pointer_screen()
    return self.screen_ws[uuid] or 1
end

function M:screen_of_ws(n)
    for uuid, m in pairs(self.screen_ws) do
        if m == n then
            return self:screen_by_uuid(uuid)
        end
    end
end

-- The tiled windows of workspace `n` that are on screen, in order.
function M:tiled(n)
    local ws = self.workspaces[n]
    local out = {}
    if not ws then
        return out
    end
    for _, id in ipairs(ws.order) do
        local f = self.a.state(id)
        if f and not f.minimized and not f.fullscreen and not f.hidden then
            out[#out + 1] = id
        end
    end
    return out
end

-- Place a new float centered on its parent, the app's focused window, or on
-- its display, at what it asked for capped at 80% (SPEC.md §5.1).
function M:place_float(id, f)
    local s = self:screen_for(f.frame)
    local area = s.area
    local w = math.min(f.frame.w, math.floor(area.w * M.FLOAT_CAP))
    local h = math.min(f.frame.h, math.floor(area.h * M.FLOAT_CAP))
    local over = area
    local parent = self.a.app_focused(f.pid)
    if parent and parent ~= id then
        local pf = self.a.state(parent)
        if pf then
            over = pf.frame
        end
    end
    local cx, cy = center(over)
    local x = math.floor(cx - w / 2 + 0.5)
    local y = math.floor(cy - h / 2 + 0.5)
    -- Keep it on its display.
    x = math.max(area.x, math.min(x, area.x + area.w - w))
    y = math.max(area.y, math.min(y, area.y + area.h - h))
    self.a.set_frame(id, { x = x, y = y, w = w, h = h })
end

-- Start managing a window. Returns what it was decided to be.
function M:add(id)
    if self.windows[id] then
        return self.windows[id].kind
    end
    local f = self.a.facts(id)
    if not f then
        return nil
    end
    local kind = rules.decide(f, self.rules)
    local w = { id = id, app = f.app, pid = f.pid, kind = kind }
    self.windows[id] = w
    if kind == "ignore" then
        return kind
    end
    w.ws = self:ws_on_screen(self:screen_for(f.frame)) or 1
    if kind == "float" then
        w.floating = true
        self.floats[#self.floats + 1] = id
        self:place_float(id, f)
    else
        -- "next" goes after the window you were in. macOS may already have
        -- given the new window focus, so that's the workspace's last used.
        local ws = self.workspaces[w.ws]
        local anchor = self.a.focused()
        if anchor == id or not (anchor and layout.index_of(ws.order, anchor)) then
            anchor = self.mru[w.ws][1]
        end
        layout.insert(ws, id, anchor, self.layout)
    end
    -- Known windows go to the back of the recently-used list, so a
    -- workspace always has something to focus, even straight after a
    -- restart, before any focus history exists.
    local list = self.mru[w.ws]
    if list and not layout.index_of(list, id) then
        list[#list + 1] = id
    end
    return kind
end

function M:forget(id)
    local w = self.windows[id]
    if not w then
        return
    end
    self.windows[id] = nil
    if w.ws and self.workspaces[w.ws] then
        layout.remove(self.workspaces[w.ws], id)
        remove_value(self.mru[w.ws], id)
    end
    remove_value(self.floats, id)
    self.placed[id] = nil
end

-- Match what timo knows to the windows that exist now: add new ones, forget
-- gone ones. Window events call this rather than trusting each event's
-- window, since a destroyed window can no longer say who it was.
-- Returns the workspaces that lost a window.
function M:sync()
    self:map_screens()
    local live = {}
    for _, id in ipairs(self.a.windows()) do
        live[id] = true
        self:add(id)
    end
    local lost = {}
    for id, w in pairs(self.windows) do
        if not live[id] then
            if w.ws then
                lost[w.ws] = true
            end
            self:forget(id)
        end
    end
    return lost
end

-- Lay out every display, moving only windows that aren't already where
-- they belong.
function M:retile()
    for uuid, n in pairs(self.screen_ws) do
        local s = self:screen_by_uuid(uuid)
        local ws = self.workspaces[n]
        if s and ws then
            local ids = self:tiled(n)
            local boxes = layout.arrange(ws, s.area, ids, self.layout)
            for _, id in ipairs(ids) do
                local w = self.windows[id]
                local box = boxes[id]
                if w.big == "max" then
                    box = s.area
                elseif w.big == "full" then
                    box = s.full
                end
                local f = self.a.state(id)
                local cur = f and f.frame
                if not cur or cur.x ~= box.x or cur.y ~= box.y or cur.w ~= box.w or cur.h ~= box.h then
                    self.a.set_frame(id, box)
                    -- Read it back: an app may round the size, and the move
                    -- this causes mustn't look like a drag.
                    local after = self.a.state(id)
                    cur = after and after.frame or box
                end
                self.placed[id] = cur
            end
        end
    end
    -- Windows may have moved under a still pointer; that isn't a crossing.
    if self.ffm then
        self.ffm:resync()
    end
end

-- Coalesce a burst of events into one sync and retile.
function M:schedule()
    if self.timer then
        self.timer:stop()
    end
    self.timer = self.a.after(M.DEBOUNCE, function()
        self.timer = nil
        local lost = self:sync()
        self:retile()
        for n in pairs(lost) do
            self:refocus(n)
        end
    end)
end

-- The mouse (SPEC.md §5.3) --------------------------------------------------

local function same(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- The managed window under a point: the frontmost visible window there,
-- or nil if that one is ignored or unknown, such as picture-in-picture
-- over a tile.
function M:window_at(x, y)
    for _, id in ipairs(self.a.ordered()) do
        local st = self.a.state(id)
        if st and not st.minimized and not st.hidden and inside(st.frame, x, y) then
            local w = self.windows[id]
            if w and w.kind ~= "ignore" and w.ws then
                return id
            end
            return nil
        end
    end
end

-- A tile the user moved or resized to `box`, by its own edges or with
-- Super+drag. A resize sets the split; a move puts the window in the tile
-- nearest where its center landed, swapping with that tile's window, or on
-- the workspace of the display it landed on.
function M:request(id, box)
    local w = self.windows[id]
    if not w or not w.ws or w.floating then
        return
    end
    local old = self.placed[id]
    local cx, cy = center(box)
    local s = self:screen_for(box)
    local n = self:ws_on_screen(s)
    -- Another display first: macOS may resize a window it moves onto a
    -- smaller display, and that's still a move.
    if n and n ~= w.ws then
        layout.remove(self.workspaces[w.ws], id)
        remove_value(self.mru[w.ws], id)
        w.ws = n
        layout.insert(self.workspaces[n], id, nil, self.layout)
    elseif old and (old.w ~= box.w or old.h ~= box.h) then
        local ws = self.workspaces[w.ws]
        local ids = self:tiled(w.ws)
        local i = layout.index_of(ids, id)
        if s and i and #ids == 1 then
            -- A lone window: the drag sets its width on this workspace.
            ws.single_width = mouse.single_width_for(s.area, old, box) or ws.single_width
        else
            local f = s and i and mouse.mfact_for(ws.mode, ws.opts[ws.mode] or {}, i, #ids, s.area, old, box)
            if f then
                ws.opts[ws.mode].mfact = layout.geometry.clamp(f, 0.1, 0.9)
            end
        end
    elseif n then
        local ws = self.workspaces[n]
        local ids = self:tiled(n)
        local boxes = layout.arrange(ws, s.area, ids, self.layout)
        for _, other in ipairs(ids) do
            if other ~= id and inside(boxes[other], cx, cy) then
                local a, b = layout.index_of(ws.order, id), layout.index_of(ws.order, other)
                ws.order[a], ws.order[b] = ws.order[b], ws.order[a]
                break
            end
        end
    end
    self:retile()
end

-- macOS says a window moved or changed size. Ignore the moves timo made;
-- treat the rest as a request, once the button is up.
function M:moved(id)
    local w = self.windows[id]
    if w and w.floating and self.ffm then
        -- A float that moved changes what's under the pointer.
        self.ffm:resync()
    end
    if not w or not w.ws or w.floating then
        return
    end
    local st = self.a.state(id)
    if not st or same(st.frame, self.placed[id]) then
        return
    end
    if self.a.buttons_down() then
        self.a.after(0.1, function()
            self:moved(id)
        end)
        return
    end
    self:request(id, st.frame)
end

-- A Super+drag or Super+right-drag starting at x, y. Returns the drag, or
-- nil if there's no window there.
function M:grab(kind, x, y)
    local id = self:window_at(x, y)
    local st = id and self.a.state(id)
    if not st then
        return nil
    end
    local d = mouse.grab(kind, st.frame, x, y)
    d.id = id
    return d
end

-- The drag ended with the pointer at x, y.
function M:drop(d, x, y)
    local box = mouse.update(d, x, y)
    local w = self.windows[d.id]
    if not w then
        return
    end
    if w.floating then
        self.a.set_frame(d.id, box)
        -- Dropped on another display, it joins the workspace there, so
        -- tiling it again later tiles it where it is.
        local n = self:ws_on_screen(self:screen_for(box))
        if n and n ~= w.ws then
            remove_value(self.mru[w.ws], d.id)
            w.ws = n
            table.insert(self.mru[n], 1, d.id)
        end
        if self.ffm then
            self.ffm:resync()
        end
    else
        self:request(d.id, box)
    end
end

-- Super+middle-click: maximize the window under the pointer, or put it back.
function M:maximize_at(x, y)
    local id = self:window_at(x, y)
    if id then
        self:focus_window(id)
        set_big_on(self, id, "max")
    end
end

-- Raise the workspace's floats over its tiles, keeping their order, so a
-- dialog never ends up behind the window that opened it (SPEC.md §5.1).
-- The focused window's own floats go last, on top.
function M:raise_floats(n, pid)
    local mine = {}
    for _, id in ipairs(self.floats) do
        local w = self.windows[id]
        if w and w.ws == n then
            if pid and w.pid == pid then
                mine[#mine + 1] = id
            else
                self.a.raise(id)
            end
        end
    end
    for _, id in ipairs(mine) do
        self.a.raise(id)
    end
    -- The stacking changed under a still pointer.
    if self.ffm then
        self.ffm:resync()
    end
end

function M:focus_window(id)
    local w = self.windows[id]
    if not w then
        return
    end
    self.a.focus(id)
    if not w.floating then
        self:raise_floats(w.ws, w.pid)
    elseif w.kind ~= "float" then
        -- A window you floated keeps its app's dialogs over it.
        local raised = false
        for _, fid in ipairs(self.floats) do
            local f = self.windows[fid]
            if fid ~= id and f and f.kind == "float" and f.pid == w.pid and f.ws == w.ws then
                self.a.raise(fid)
                raised = true
            end
        end
        if raised and self.ffm then
            self.ffm:resync()
        end
    end
end

-- Called when macOS reports a window gained focus, by timo or by a click
-- or app switch. A window too new to have been synced is added now, so its
-- focus isn't lost.
function M:focused(id)
    if not self.windows[id] then
        self:map_screens()
        self:add(id)
    end
    if self.ffm then
        self.ffm:settled(id)
    end
    local w = self.windows[id]
    if not w or not w.ws then
        return
    end
    -- However the tile got focus, its floats go back over it. A focused
    -- float comes to the front, so it moves to the top of wm.floats, which
    -- raise_floats replays bottom to top, and what's under the pointer is
    -- re-read.
    if w.floating then
        remove_value(self.floats, id)
        self.floats[#self.floats + 1] = id
        if self.ffm then
            self.ffm:resync()
        end
    else
        self:raise_floats(w.ws, w.pid)
    end
    local list = self.mru[w.ws]
    remove_value(list, id)
    table.insert(list, 1, id)
    -- Maximize lasts until another window on the workspace is focused
    -- (tide SPEC.md §6.3).
    local changed = false
    for oid, o in pairs(self.windows) do
        if oid ~= id and o.ws == w.ws and o.big == "max" then
            o.big = nil
            changed = true
        end
    end
    if changed then
        self:retile()
    end
end

-- After a close, something keeps focus: the window under the pointer, as
-- tide's focus_on_close, else the last used window left on that workspace,
-- else any tile you can see there. The fallback means a window that reached
-- the workspace without a focus event, such as one moved off a display that
-- went away, still counts.
function M:refocus(n)
    if self.a.focused() then
        return
    end
    if self.ffm and self.ffm.enabled then
        local x, y = self.a.pointer()
        local id = x and self.ffm:hit(x, y)
        if id and self.windows[id].ws == n then
            self:focus_window(id)
            return
        end
    end
    for _, id in ipairs(self.mru[n] or {}) do
        -- Only a window you can see: focusing a minimized one doesn't
        -- bring it back.
        local w = self.windows[id]
        local st = w and w.ws == n and self.a.state(id)
        if st and not st.minimized and not st.hidden and not st.fullscreen then
            self:focus_window(id)
            return
        end
    end
    local id = self:tiled(n)[1]
    if id then
        self:focus_window(id)
    end
end

-- Actions, called by the keys -----------------------------------------------

function M:focused_tile()
    local id = self.a.focused()
    local w = self.windows[id or false]
    if w and w.ws and not w.floating then
        return id, w
    end
end

M.actions = {}
local A = M.actions

function A.focus(self, delta)
    local n = self:current_ws()
    local ids = self:tiled(n)
    local id = self:focused_tile()
    local target = layout.neighbor(ids, id, delta)
    -- Focusing raises the target, monocle's full-size tile included, and
    -- then its floats go back over it.
    if target then
        self:focus_window(target)
    end
end

function A.move(self, delta)
    local id, w = self:focused_tile()
    if id then
        layout.move(self.workspaces[w.ws], self:tiled(w.ws), id, delta)
        self:retile()
    end
end

function A.swap_master(self)
    local id, w = self:focused_tile()
    if id then
        layout.swap_master(self.workspaces[w.ws], self:tiled(w.ws), id)
        self:retile()
    end
end

function A.mfact(self, sign)
    layout.mfact(self.workspaces[self:current_ws()], sign * self.layout.mfact_step)
    self:retile()
end

function A.nmaster(self, delta)
    layout.nmaster(self.workspaces[self:current_ws()], delta)
    self:retile()
end

function A.cycle(self, delta)
    layout.cycle(self.workspaces[self:current_ws()], delta, self.layout)
    self:retile()
end

function A.monocle(self)
    layout.toggle_monocle(self.workspaces[self:current_ws()])
    self:retile()
end

function set_big_on(self, id, kind)
    local w = self.windows[id]
    if not w or not w.ws or w.floating then
        return
    end
    w.big = (w.big ~= kind) and kind or nil
    self:retile()
    if w.big then
        self.a.raise(id)
        -- The tile is already focused, so no focus event will put its
        -- floats back over it.
        self:raise_floats(w.ws, w.pid)
    end
end

local function set_big(self, kind)
    local id = self:focused_tile()
    if id then
        set_big_on(self, id, kind)
    end
end

function A.maximize(self)
    set_big(self, "max")
end

function A.fullscreen(self)
    set_big(self, "full")
end

function A.restore(self)
    local id, w = self:focused_tile()
    if id and w.big then
        w.big = nil
        self:retile()
    end
end

function A.toggle_float(self)
    local id = self.a.focused()
    local w = self.windows[id or false]
    if not w or not w.ws then
        return
    end
    if w.floating then
        w.floating = false
        remove_value(self.floats, id)
        layout.insert(self.workspaces[w.ws], id, nil, self.layout)
    else
        w.floating = true
        w.big = nil
        layout.remove(self.workspaces[w.ws], id)
        self.floats[#self.floats + 1] = id
        self:place_float(id, self.a.facts(id))
    end
    self:retile()
end

-- The window's going away is seen by the next sync, which refocuses.
function A.close(self)
    local id = self.a.focused()
    if id then
        self.a.close(id)
    end
end

-- Resize mode (Super+Shift+R): grow or shrink the focused float by dx, dy,
-- keeping it on its display.
function A.resize_by(self, d)
    local id = self.a.focused()
    local w = self.windows[id or false]
    local st = w and w.floating and self.a.state(id)
    if not st then
        return
    end
    local f = st.frame
    self.a.set_frame(id, {
        x = f.x,
        y = f.y,
        w = math.max(mouse.MIN, f.w + d[1]),
        h = math.max(mouse.MIN, f.h + d[2]),
    })
end

-- Super+Shift+R: the keys for resize mode are Hammerspoon's to bind
-- (init.lua), so this only enters it.
function A.resize_mode(self)
    if self.enter_resize_mode then
        self.enter_resize_mode()
    end
end

function M:act(name, arg)
    local f = A[name]
    if not f then
        error("timo: no action " .. tostring(name))
    end
    f(self, arg)
end

return M
