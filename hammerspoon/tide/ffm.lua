-- Focus follows mouse (SPEC.md §5.2). Focus moves the moment the pointer
-- crosses into another window, and nothing else moves it. Pure Lua: the
-- adapter says what's under the pointer, and the window manager focuses.
--
-- The rules that keep it from repeating Amethyst's bugs:
-- - Only a crossing counts. Moving inside the window the pointer was last
--   over does nothing, even after a key moved focus elsewhere, and a window
--   moving under a still pointer is recorded without focusing it.
-- - What's under the pointer comes from Accessibility's hit test, so a
--   menu, popover or anything tide doesn't manage stops the lookup and
--   focus stays put.
-- - A window's own dialog wins over the window.
-- - A tile with another app's float in front of it is left alone, and so
--   is its app's dialog it would defer to: focusing either would bury the
--   float, and macOS won't raise the float back.
-- - It pauses while a menu is open, while a button is held, while Super is
--   held, outside every
--   display's work area (the menu bar and the Dock), over tide's own
--   overlays (the tray), while tide's own
--   launcher is open, and while an app that must keep focus is in front.

local M = {}
M.__index = M

-- Apps that keep focus while they're in front: the screenshot picker and
-- password prompts, from AutoRaise's list.
M.KEEP_FOCUS = {
    ["com.apple.screencaptureui"] = true,
    ["com.apple.SecurityAgent"] = true,
}

-- Hammerspoon's own windows: its console, and tide's settings, which
-- keep a floating window level of their own, so no raise can bury them.
M.OWN_APP = "org.hammerspoon.Hammerspoon"

-- How long a focus is in flight before another may start, if macOS never
-- confirms it.
M.IN_FLIGHT = 0.3

local function inside(b, x, y)
    return b and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

function M.new(wm, adapter, opts)
    opts = opts or {}
    local keep = {}
    for k, v in pairs(M.KEEP_FOCUS) do
        keep[k] = v
    end
    for _, app in ipairs(opts.keep_focus or {}) do
        keep[app] = true
    end
    return setmetatable({
        wm = wm,
        a = adapter,
        enabled = opts.enabled ~= false,
        keep = keep,
        -- Whether Super is down now: a queued focus waits for it to go up,
        -- as a pointer move does.
        super_held = opts.super_held or function()
            return false
        end,
        last = nil,   -- the managed window the pointer was last over
        region = nil, -- its frame
        holes = {},   -- frames of floats over it
        pending = nil,
        queued = nil,
    }, M)
end

-- Paused wherever the pointer is: turned off, tide holding the keyboard
-- (the launcher, resize mode), an app in front that must keep focus, a
-- mouse button held, or a menu open. An open menu keeps focus where it is
-- until it closes, even once the pointer leaves it: focusing another window
-- would close it. A queued focus waits these out too.
function M:blocked()
    return not self.enabled or self.wm.holding_keyboard or self.keep[self.a.frontmost_app()]
        or self.a.buttons_down() or self.a.menu_open() or false
end

-- Where nothing is tide's to focus, and nothing need be asked: over
-- tide's own windows and overlays, such as the settings window and the
-- tray of windows you minimized (SPEC.md §6.7), and outside every work
-- area, which is the menu bar, tide's bar or the Dock.
function M:off_limits(x, y)
    if self.wm:own_at(x, y) then
        return true
    end
    for _, s in ipairs(self.wm:screens()) do
        if inside(s.area, x, y) then
            return false
        end
    end
    return true
end

function M:paused(x, y, super_held)
    return super_held or self:blocked() or self:off_limits(x, y)
end

-- The pointer is still where nothing new can be: in the last window, and
-- not on a float over it.
function M:within(x, y)
    if not inside(self.region, x, y) then
        return false
    end
    for _, h in ipairs(self.holes) do
        if inside(h, x, y) then
            return false
        end
    end
    return true
end

-- Record `id` as the window under the pointer, with the visible floats in
-- front of it as holes, whatever their workspace: a float dragged across a
-- display edge covers a tile on the other display too. In front means macOS's own stacking order,
-- read fresh each time: anything that raises a window, tide or an app,
-- changes it, and a copy kept here would go stale. This runs on crossings
-- and resyncs, not on every move.
function M:remember(id)
    self.last = id
    local st = id and self.a.state(id)
    self.region = st and st.frame
    self.holes = {}
    local w = id and self.wm.windows[id]
    if not w then
        return
    end
    for _, fid in ipairs(self.a.ordered()) do
        if fid == id then
            break
        end
        local f = self.wm.windows[fid]
        local fs = f and f.floating and self.wm:shown(f.ws) and self.a.state(fid)
        if fs and not fs.minimized then
            self.holes[#self.holes + 1] = fs.frame
        end
    end
end

-- The managed window at x, y, or nil when something else is on top. A
-- parked window's sliver, in a display's corner (park.lua), is nothing to
-- focus: crossing it would bring its workspace along.
function M:hit(x, y)
    local id = self.a.window_at(x, y)
    local w = id and self.wm.windows[id]
    if w and w.kind ~= "ignore" and w.ws and not (self.wm.parked and self.wm.parked[id]) then
        return id
    end
end

-- The window that should get focus when the pointer enters `id`: its app's
-- topmost float on the same workspace, if it has one, else `id` itself. A
-- window you floated defers only to its app's dialogs, the windows the
-- rules float; a dialog itself takes the focus.
function M:prefer_dialog(id)
    local w = self.wm.windows[id]
    if not w or w.kind == "float" then
        return id
    end
    for i = #self.wm.floats, 1, -1 do
        local fid = self.wm.floats[i]
        local f = self.wm.windows[fid]
        local ok = f and fid ~= id and f.pid == w.pid and f.ws == w.ws and (not w.floating or f.kind == "float")
        local fs = ok and self.a.state(fid)
        if fs and not fs.minimized and not fs.hidden then
            return fid
        end
    end
    return id
end

local function overlap(a, b)
    return a and b and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Whether tile `id` has another app's float in front of it. Focusing the
-- tile raises it, and macOS won't put the other app's window back over it
-- (SPEC.md §13), so the float would be buried. Floats of the tile's own app
-- go back over it with it, and the Hammerspoon windows tide raises to a
-- floating level (M.ELEVATED) stay over it anyway. Hammerspoon's other floats,
-- such as its Preferences, are buried like any app's.
M.ELEVATED = { ["Hammerspoon Console"] = true }

local function elevated(f)
    return f.app == M.OWN_APP and M.ELEVATED[f.title] == true
end

function M:under_float(id)
    local w = self.wm.windows[id]
    if not w or w.floating then
        return false
    end
    local st = self.a.state(id)
    local frame = st and st.frame
    for _, fid in ipairs(self.a.ordered()) do
        if fid == id then
            return false
        end
        local f = self.wm.windows[fid]
        local ok = f and f.floating and f.pid ~= w.pid and not elevated(f) and self.wm:shown(f.ws)
        local fs = ok and self.a.state(fid)
        if fs and not fs.minimized and not fs.hidden and overlap(fs.frame, frame) then
            return true
        end
    end
    return false
end

function M:focus(target)
    if self.pending then
        self.queued = target
        return
    end
    self.pending = target
    -- Each request's own timeout: an older one's mustn't settle a newer
    -- request for the same window.
    self.request = (self.request or 0) + 1
    local request = self.request
    self.wm:focus_window(target, true)
    self.a.after(M.IN_FLIGHT, function()
        if self.pending == target and self.request == request then
            self:settled(target)
        end
    end)
end

-- macOS confirmed a focus, or the wait ran out: start the queued one.
function M:settled(id)
    -- Only the window in flight settles it: a late confirmation for an
    -- earlier one, whose wait already ran out, isn't this request's.
    if not self.pending or id ~= self.pending then
        return
    end
    self.pending = nil
    local q = self.queued
    self.queued = nil
    if not q then
        return
    end
    -- A queued focus is only a crossing that waited its turn, so it gets no
    -- rules of its own: what's under the pointer now, with every pause a
    -- pointer move has, decides what follows.
    local x, y = self.a.pointer()
    if not x or self:paused(x, y, self.super_held()) then
        return
    end
    local now = self:hit(x, y)
    local target = now and self:prefer_dialog(now)
    if target and target ~= self.a.focused() and not self:under_float(now) then
        self:focus(target)
    end
end

-- The pointer moved to x, y.
function M:move(x, y, super_held)
    -- The cheap check first: most moves stay inside one window.
    if self:within(x, y) or self:paused(x, y, super_held) then
        return
    end
    local id = self:hit(x, y)
    if not id then
        -- Out of the last window onto the desktop or a gap: coming back is a
        -- crossing. A menu or popover still over that window isn't leaving it.
        -- A window queued behind a focus in flight has been left too.
        if not inside(self.region, x, y) then
            self.last, self.region, self.holes = nil, nil, {}
            self.queued = nil
            self:desktop()
        end
        return
    end
    self.desk = nil
    -- Off a desktop that took the keys and into a window: the keys come
    -- with the pointer, even into the window that kept focus, which no
    -- focus change would hand them back to.
    if self.took then
        local k = self.wm.kbd
        if k and k.uuid == self.took then
            self.wm.kbd = nil
            self.wm:changed()
        end
        self.took = nil
    end
    if id == self.last then
        self:remember(id)
        return
    end
    self:remember(id)
    local target = self:prefer_dialog(id)
    -- A tile under another app's float is left alone, and so is its own
    -- dialog: focusing the dialog activates the tile's app, which can bring
    -- the tile forward with it. With a focus in flight, the latest crossing
    -- decides what follows it, including going back to the window being
    -- focused.
    if self:under_float(id) then
        target = nil
    end
    if self.pending then
        self.queued = target ~= self.pending and target or nil
        return
    end
    if target and target ~= self.a.focused() then
        self:focus(target)
    end
end

-- The pointer is on the desktop. Onto another display's, with no window
-- under it, that display takes the keys, as Hyprland's focused monitor
-- follows the pointer: a launch opens there, and Super+Left/Right start
-- from it (SPEC.md §5.2). Asked once each time it reaches a display's
-- desktop, not at every move.
function M:desktop()
    local uuid = self.a.pointer_screen()
    if not uuid or uuid == self.desk then
        return
    end
    self.desk = uuid
    if uuid ~= self.wm:current_screen() then
        self.wm:keep_keys_on(uuid)
        self.took = uuid
    end
end

-- Windows moved under a still pointer: note what's there now, focusing
-- nothing. A window queued behind a focus in flight that's no longer under
-- the pointer is dropped: the crossing that queued it is out of date.
function M:resync()
    local x, y = self.a.pointer()
    if x then
        -- Over tide's own window, the bar or the Dock, nothing's there to
        -- read, and asking about one of tide's web pages waits on it: it
        -- counts as no window, so the one it was over is forgotten, as a
        -- lookup that found none forgets it.
        local id = not self:off_limits(x, y) and self:hit(x, y) or nil
        self:remember(id)
        if self.queued and (not id or self:prefer_dialog(id) ~= self.queued) then
            self.queued = nil
        end
    end
end

function M:toggle()
    self.enabled = not self.enabled
    return self.enabled
end

return M
