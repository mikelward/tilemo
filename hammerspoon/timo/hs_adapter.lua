-- The window manager's view of macOS, through Hammerspoon. Everything that
-- touches `hs` lives here, so the rest tests against a fake (tests/fake.lua).
-- Not runnable outside Hammerspoon.

local M = {}

local function box(r)
    return { x = math.floor(r.x + 0.5), y = math.floor(r.y + 0.5), w = math.floor(r.w + 0.5), h = math.floor(r.h + 0.5) }
end

-- Roles Accessibility's hit test may land on that mean "not a window":
-- focus follows mouse stops on them (SPEC.md §5.2).
local NOT_A_WINDOW = {
    AXMenu = true,
    AXMenuItem = true,
    AXMenuBar = true,
    AXMenuBarItem = true,
    AXPopover = true,
    AXDockItem = true,
    AXHelpTag = true,
}

-- Every Accessibility call gives up after this long, so a hung app can't
-- freeze timo (Amethyst#342).
M.AX_TIMEOUT = 0.25

M.SETTINGS_KEY = "timo.state"

function M.load()
    return hs.settings.get(M.SETTINGS_KEY)
end

function M.new()
    local a = {}
    local cache = {}
    local system = hs.axuielement.systemWideElement()
    -- On the system-wide element this sets the timeout for every call.
    system:setTimeout(M.AX_TIMEOUT)

    local function win(id)
        local w = cache[id]
        if not w then
            w = hs.window.get(id)
            cache[id] = w
        end
        return w
    end

    -- Reads on a window that's going away can fail; a failed read is
    -- treated as no window.
    local function try(fn, ...)
        local ok, v = pcall(fn, ...)
        if ok then
            return v
        end
    end

    -- Every Space, not just the current one: a window in native full screen
    -- sits on a Space of its own, and hs.window.allWindows() would leave it
    -- out, so timo would forget its place in the layout. A window filter
    -- with no current-Space setting covers them all.
    local every = hs.window.filter.new(false)
    every:setDefaultFilter({ allowRoles = "*" })

    function a.windows()
        cache = {}
        local ids = {}
        for _, w in ipairs(every:getWindows()) do
            local id = try(w.id, w)
            if id then
                cache[id] = w
                ids[#ids + 1] = id
            end
        end
        return ids
    end

    function a.state(id)
        local w = win(id)
        if not w then
            return nil
        end
        return try(function()
            local app = w:application()
            return {
                frame = box(w:frame()),
                minimized = w:isMinimized(),
                fullscreen = w:isFullScreen(),
                hidden = app and app:isHidden() or false,
            }
        end)
    end

    function a.facts(id)
        local w = win(id)
        if not w then
            return nil
        end
        return try(function()
            local app = w:application()
            local el = hs.axuielement.windowElement(w)
            local settable = el and el:isAttributeSettable("AXSize")
            return {
                role = w:role(),
                subrole = w:subrole(),
                app = app and app:bundleID(),
                pid = w:pid(),
                title = w:title(),
                -- nil when Accessibility didn't say, which rules.lua reads
                -- as settable.
                size_settable = settable,
                modal = el and el:attributeValue("AXModal") or false,
                frame = box(w:frame()),
                minimized = w:isMinimized(),
                fullscreen = w:isFullScreen(),
            }
        end)
    end

    -- Visible windows, front to back.
    function a.ordered()
        local ids = {}
        for _, w in ipairs(hs.window.orderedWindows()) do
            local id = try(w.id, w)
            if id then
                cache[id] = cache[id] or w
                ids[#ids + 1] = id
            end
        end
        return ids
    end

    -- The window Accessibility finds at x, y, or nil when what's there is a
    -- menu, a popover, the Dock or anything else that isn't a window.
    function a.window_at(x, y)
        return try(function()
            local el = hs.axuielement.systemElementAtPosition(x, y)
            if not el then
                return nil
            end
            local seen = 0
            while el and seen < 50 do
                local role = el:attributeValue("AXRole")
                if NOT_A_WINDOW[role] then
                    return nil
                end
                if role == "AXWindow" then
                    local w = el:asHSWindow()
                    return w and w:id()
                end
                el = el:attributeValue("AXParent")
                seen = seen + 1
            end
        end)
    end

    -- Whether any app has a menu open: an on-screen window at the pop-up
    -- menu level (101, kCGPopUpMenuWindowLevel) *(unverified for every
    -- kind of menu)*. `true` lists every level: by default the list stops
    -- below the Dock, and menus sit above it.
    function a.menu_open()
        for _, info in ipairs(hs.window.list(true) or {}) do
            if info.kCGWindowLayer == 101 then
                return true
            end
        end
        return false
    end

    function a.frontmost_app()
        local app = hs.application.frontmostApplication()
        return app and app:bundleID()
    end

    function a.pointer()
        local p = hs.mouse.absolutePosition()
        return p.x, p.y
    end

    function a.buttons_down()
        for _, down in pairs(hs.eventtap.checkMouseButtons()) do
            if down then
                return true
            end
        end
        return false
    end

    -- The outline shown during a Super+drag, or nil to hide it.
    local outline
    function a.outline(b)
        if not b then
            if outline then
                outline:delete()
                outline = nil
            end
            return
        end
        if not outline then
            outline = hs.canvas.new(b)
            outline:level(hs.canvas.windowLevels.overlay)
            outline[1] = {
                type = "rectangle",
                action = "stroke",
                strokeWidth = 3,
                strokeColor = { white = 1, alpha = 0.8 },
            }
            outline:show()
        else
            outline:frame(b)
        end
    end

    function a.title(id)
        local w = win(id)
        return w and try(w.title, w)
    end

    -- Each Dock item's badge, as { app = bundle ID, label }. Read through
    -- Accessibility's AXStatusLabel, which some apps don't set
    -- (SPEC.md §2.5).
    function a.dock_badges()
        local out = {}
        local dock = hs.application.get("com.apple.dock")
        local el = dock and hs.axuielement.applicationElement(dock)
        local list = el and try(function()
            return el:attributeValue("AXChildren")[1]
        end)
        for _, item in ipairs(list and try(list.attributeValue, list, "AXChildren") or {}) do
            local name = try(item.attributeValue, item, "AXTitle")
            local label = try(item.attributeValue, item, "AXStatusLabel")
            local app = name and hs.application.get(name)
            local bundle = app and app:bundleID()
            if bundle then
                out[#out + 1] = { app = bundle, label = label }
            end
        end
        return out
    end

    function a.screens()
        local out = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            out[#out + 1] = { uuid = s:getUUID(), area = box(s:frame()), full = box(s:fullFrame()) }
        end
        -- Left to right, then top to bottom, so numbering is stable.
        table.sort(out, function(p, q)
            if p.full.x ~= q.full.x then
                return p.full.x < q.full.x
            end
            return p.full.y < q.full.y
        end)
        return out
    end

    function a.focused()
        local w = hs.window.focusedWindow()
        return w and try(w.id, w)
    end

    function a.app_focused(pid)
        local app = pid and hs.application.applicationForPID(pid)
        local w = app and app:focusedWindow()
        return w and try(w.id, w)
    end

    function a.pointer_screen()
        local s = hs.mouse.getCurrentScreen()
        return s and s:getUUID()
    end

    function a.set_frame(id, b)
        local w = win(id)
        if w then
            try(w.setFrame, w, hs.geometry.rect(b.x, b.y, b.w, b.h), 0)
        end
    end

    function a.focus(id)
        local w = win(id)
        if w then
            try(w.focus, w)
        end
    end

    function a.raise(id)
        local w = win(id)
        if w then
            try(w.raise, w)
        end
    end

    function a.minimize(id)
        local w = win(id)
        if w then
            try(w.minimize, w)
        end
    end

    function a.unminimize(id)
        local w = win(id)
        if w then
            try(w.unminimize, w)
        end
    end

    -- Where every window is, for the next start (SPEC.md §6.3). The
    -- settings store wants string keys.
    function a.save(snap)
        local windows = {}
        for id, v in pairs(snap.windows) do
            windows[tostring(id)] = v
        end
        hs.settings.set(M.SETTINGS_KEY, { windows = windows, screens = snap.screens })
    end

    -- Start an app key's app: by bundle ID, or one of tide's helpers
    -- through runenv, which gives it the login environment (tide §17,
    -- "PATH missing in keybinds"). `fresh` asks a running app for a new
    -- window with Cmd+N, the near-universal shortcut, since opening it
    -- again would only bring its old windows forward.
    function a.launch(spec, fresh)
        local running = spec.bundle and hs.application.get(spec.bundle)
        if fresh and running then
            if running:activate() then
                hs.eventtap.keyStroke({ "cmd" }, "n", 0, running)
            else
                a.notify("Couldn't open a new window of " .. spec.bundle)
            end
            return
        end
        if spec.bundle then
            if not hs.application.launchOrFocusByBundleID(spec.bundle) then
                a.notify("Couldn't open " .. spec.bundle)
            end
            return
        end
        local args = {}
        for word in spec.run:gmatch("%S+") do
            args[#args + 1] = word
        end
        local runenv = (os.getenv("HOME") or "") .. "/scripts/runenv"
        local task = hs.task.new(runenv, function(code, _, err)
            if code ~= 0 then
                a.log(spec.run .. " exited " .. code .. ": " .. (err or ""))
            end
        end, args)
        if not task or not task:start() then
            a.notify("Couldn't run " .. spec.run)
        end
    end

    function a.close(id)
        local w = win(id)
        if w then
            try(w.close, w)
        end
    end

    -- Hammerspoon stops a timer that's garbage collected, so each one is
    -- held here until it fires or is stopped.
    local pending = {}
    function a.after(seconds, fn)
        local t
        t = hs.timer.doAfter(seconds, function()
            pending[t] = nil
            fn()
        end)
        pending[t] = true
        return {
            stop = function()
                pending[t] = nil
                t:stop()
            end,
        }
    end

    function a.read(path)
        local f = io.open(path, "r")
        if not f then
            return nil
        end
        local text = f:read("a")
        f:close()
        return text
    end

    -- A file that isn't valid JSON, such as karabiner.json caught mid-write,
    -- reads as nil, and the caller treats it as not set up.
    function a.decode(text)
        local ok, value = pcall(hs.json.decode, text)
        if not ok then
            a.log("couldn't read JSON: " .. tostring(value))
            return nil
        end
        return value
    end

    function a.running(name)
        local _, ok = hs.execute("/usr/bin/pgrep -xq " .. name)
        return ok == true
    end

    function a.notify(text)
        hs.notify.new({ title = "timo", informativeText = text }):send()
    end

    local log = hs.logger.new("timo", "info")
    function a.log(text)
        log.i(text)
    end

    return a
end

-- Call `on_change` on any window coming, going, hiding or changing state,
-- `on_focus(id)` when one gains focus, `on_moved(id)` when one moves or
-- changes size, and `on_min(id)` / `on_unmin(id)` when one is minimized or
-- comes back. Returns what to keep alive.
function M.watch(on_change, on_focus, on_moved, on_min, on_unmin)
    local wf = hs.window.filter.new(false)
    wf:setDefaultFilter({ allowRoles = "*" })
    wf:subscribe({
        hs.window.filter.windowCreated,
        hs.window.filter.windowDestroyed,
        hs.window.filter.windowHidden,
        hs.window.filter.windowUnhidden,
        hs.window.filter.windowFullscreened,
        hs.window.filter.windowUnfullscreened,
    }, function()
        on_change()
    end)
    local function with_id(fn)
        return function(w)
            local ok, id = pcall(w.id, w)
            if ok and id then
                fn(id)
            end
        end
    end
    wf:subscribe(hs.window.filter.windowFocused, with_id(on_focus))
    wf:subscribe(hs.window.filter.windowMoved, with_id(on_moved))
    wf:subscribe(hs.window.filter.windowMinimized, with_id(on_min))
    wf:subscribe(hs.window.filter.windowUnminimized, with_id(on_unmin))
    local sw = hs.screen.watcher.new(on_change)
    sw:start()
    return { wf, sw }
end

-- Modifier changes, and anything that spoils a Super tap: a key, a mouse
-- button or a scroll. Passes every event through.
function M.taps(on_flags, on_other)
    local t = hs.eventtap.event.types
    local tap = hs.eventtap.new({
        t.flagsChanged, t.keyDown, t.leftMouseDown, t.rightMouseDown, t.otherMouseDown, t.scrollWheel,
    }, function(e)
        if e:getType() == t.flagsChanged then
            on_flags(e:getFlags())
        else
            on_other()
        end
        return false
    end)
    tap:start()
    return tap
end

-- Pointer moves, for focus follows mouse. Drags are separate events, so a
-- drag never reaches it. Passes every event through.
function M.pointer_moves(fn)
    local tap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(e)
        local p = e:location()
        fn(p.x, p.y, e:getFlags())
        return false
    end)
    tap:start()
    return tap
end

-- Super+drag, Super+right-drag and Super+middle-click (SPEC.md §5.3).
-- `is_super(flags)` says whether exactly Super is held. The handlers get the
-- pointer's position; a press with Super held is swallowed, so the app under
-- it never sees it, and anything else passes straight through.
function M.mouse(is_super, h)
    local t = hs.eventtap.event.types
    local drag
    local tap = hs.eventtap.new({
        t.leftMouseDown, t.leftMouseDragged, t.leftMouseUp,
        t.rightMouseDown, t.rightMouseDragged, t.rightMouseUp,
        t.otherMouseDown,
    }, function(e)
        local kind = e:getType()
        local p = e:location()
        if kind == t.leftMouseDown or kind == t.rightMouseDown then
            h.clicked()
            if not is_super(e:getFlags()) then
                return false
            end
            drag = h.grab(kind == t.leftMouseDown and "move" or "resize", p.x, p.y)
            return drag ~= nil
        elseif kind == t.leftMouseDragged or kind == t.rightMouseDragged then
            if drag then
                h.update(drag, p.x, p.y)
                return true
            end
        elseif kind == t.leftMouseUp or kind == t.rightMouseUp then
            if drag then
                local d = drag
                drag = nil
                h.drop(d, p.x, p.y)
                return true
            end
        elseif kind == t.otherMouseDown then
            -- Button 2 is the middle one.
            if e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) == 2 and is_super(e:getFlags()) then
                h.middle(p.x, p.y)
                return true
            end
        end
        return false
    end)
    tap:start()
    return tap
end

return M
