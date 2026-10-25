-- The window manager's view of macOS, through Hammerspoon. Everything that
-- touches `hs` lives here, so the rest tests against a fake (tests/fake.lua).
-- Not runnable outside Hammerspoon.

local M = {}

local function box(r)
    return { x = math.floor(r.x + 0.5), y = math.floor(r.y + 0.5), w = math.floor(r.w + 0.5), h = math.floor(r.h + 0.5) }
end

function M.new()
    local a = {}
    local cache = {}

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

    function a.close(id)
        local w = win(id)
        if w then
            try(w.close, w)
        end
    end

    function a.after(seconds, fn)
        return hs.timer.doAfter(seconds, fn)
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
-- `on_focus(id)` when one gains focus, and `on_moved(id)` when one moves or
-- changes size. Returns what to keep alive.
function M.watch(on_change, on_focus, on_moved)
    local wf = hs.window.filter.new(false)
    wf:setDefaultFilter({ allowRoles = "*" })
    wf:subscribe({
        hs.window.filter.windowCreated,
        hs.window.filter.windowDestroyed,
        hs.window.filter.windowMinimized,
        hs.window.filter.windowUnminimized,
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
    local sw = hs.screen.watcher.new(on_change)
    sw:start()
    return { wf, sw }
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
