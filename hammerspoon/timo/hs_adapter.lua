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
-- and `on_focus(id)` when one gains focus. Returns what to keep alive.
function M.watch(on_change, on_focus)
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
    wf:subscribe(hs.window.filter.windowFocused, function(w)
        local ok, id = pcall(w.id, w)
        if ok and id then
            on_focus(id)
        end
    end)
    local sw = hs.screen.watcher.new(on_change)
    sw:start()
    return { wf, sw }
end

return M
