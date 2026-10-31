-- The window manager's view of macOS, through Hammerspoon. Everything that
-- touches `hs` lives here, so the rest tests against a fake (tests/fake.lua).
-- Not runnable outside Hammerspoon.

local atomic = require("tilemo.atomic")
local kitty = require("tilemo.kitty")
local saved = require("tilemo.saved")
local runner = require("tilemo.runner")
local shots = require("tilemo.shots")

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
-- freeze tilemo (Amethyst#342).
M.AX_TIMEOUT = 0.25

M.SETTINGS_KEY = "tilemo.state"
-- Where timo kept it, before the rename.
M.OLD_SETTINGS_KEY = "timo.state"

function M.load()
    return saved.get(hs.settings, M.SETTINGS_KEY, M.OLD_SETTINGS_KEY)
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
    -- out, so tilemo would forget its place in the layout. A window filter
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
                -- What "in"'s apps are matched by (SPEC.md §6.2).
                name = app and app:name(),
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
        hs.settings.set(M.SETTINGS_KEY, { windows = windows, screens = snap.screens, gone = snap.gone })
    end

    -- Run `path` with `args`, calling `done(code, err, out)` when it exits,
    -- each task held until then (runner.lua). presenter_hs runs its
    -- shortcuts through it too, as `a.run`.
    local run = runner.new(hs.task.new).run
    a.run = run

    -- `env` as `NAME=value` words, sorted so they come out the same each
    -- time.
    local function env_words(env)
        local out = {}
        for k, v in pairs(env or {}) do
            out[#out + 1] = k .. "=" .. v
        end
        table.sort(out)
        return out
    end

    -- kitty's remote control socket, if conf's kitty.conf turned it on:
    -- `listen_on unix:kitty`, which kitty makes `$TMPDIR/kitty-<pid>`.
    -- kitty.lua says whether it's safe to use; one that isn't is refused
    -- with a notice, and Cmd+N used instead. Your user ID is asked once,
    -- the first time a socket is there to check.
    local KITTEN = "/Applications/kitty.app/Contents/MacOS/kitten"
    local my_uid
    local function uid()
        if my_uid == nil then
            local out, ok = hs.execute("/usr/bin/id -u")
            my_uid = ok and tonumber(out and out:match("%d+")) or false
            if not my_uid then
                a.log("couldn't run id -u: " .. tostring(out))
            end
        end
        return my_uid or nil
    end
    local function kitty_socket(app)
        local pid = app and app:pid()
        local tmpdir = os.getenv("TMPDIR")
        local path = kitty.path(tmpdir, pid)
        if not (path and hs.fs.attributes(path)) then
            return nil
        end
        local socket, why = kitty.socket(tmpdir, pid, uid(), hs.fs.attributes)
        if not socket and why then
            a.notify("Not using kitty's remote control: " .. why .. ". Opened the window with Cmd+N")
        end
        return socket
    end

    -- A new window of a running app. kitty is asked for an OS window through
    -- its remote control, so the shell in it gets `env` (SPEC.md §6.3);
    -- with no socket, or if that fails, and for every other app, Cmd+N,
    -- whose window gets the environment the app started with.
    local function new_window(spec, running, env)
        local function cmd_n()
            if running:activate() then
                hs.eventtap.keyStroke({ "cmd" }, "n", 0, running)
            else
                a.notify("Couldn't open a new window of " .. spec.bundle)
            end
        end
        local socket = spec.bundle == "net.kovidgoyal.kitty" and next(env or {}) and kitty_socket(running)
        if not socket then
            cmd_n()
            return
        end
        local args = { "@", "--to", socket, "launch", "--type=os-window" }
        for _, word in ipairs(env_words(env)) do
            args[#args + 1] = "--env"
            args[#args + 1] = word
        end
        if not run(KITTEN, args, function(code, err)
            if code ~= 0 then
                a.log("kitten @ launch exited " .. code .. ": " .. (err or "") .. "; using Cmd+N")
                cmd_n()
            end
        end) then
            a.log("couldn't run " .. KITTEN .. "; using Cmd+N")
            cmd_n()
        end
    end

    -- Start an app key's app: by bundle ID, or one of tide's helpers
    -- through runenv, which gives it the login environment (tide §17,
    -- "PATH missing in keybinds"). `fresh` asks a running app for a new
    -- window, since opening it again would only bring its old windows
    -- forward. `env` (TIDE_WORKSPACE, SPEC.md §6.3) goes to a helper
    -- through env(1), and to an app through `open --env`, which reaches a
    -- new process only *(unverified on macOS 26)*. A launch that fails says
    -- so, with the first line of what it printed, rather than leaving the
    -- key doing nothing.
    function a.launch(spec, fresh, env)
        local running = spec.bundle and hs.application.get(spec.bundle)
        if fresh and running then
            new_window(spec, running, env)
            return
        end
        if spec.bundle then
            local args = { "-b", spec.bundle }
            for _, word in ipairs(env_words(env)) do
                args[#args + 1] = "--env"
                args[#args + 1] = word
            end
            if not run("/usr/bin/open", args, function(code, err)
                if code ~= 0 then
                    a.notify("Couldn't open " .. spec.bundle .. ((err or ""):match("[^\n]+") and ": " .. err:match("[^\n]+") or ""))
                end
            end) then
                a.notify("Couldn't open " .. spec.bundle)
            end
            return
        end
        local args = env_words(env)
        local runenv = (os.getenv("HOME") or "") .. "/scripts/runenv"
        args[#args + 1] = runenv
        for word in spec.run:gmatch("%S+") do
            args[#args + 1] = word
        end
        local started = run("/usr/bin/env", args, function(code, err)
            if code ~= 0 then
                a.log(spec.run .. " exited " .. code .. ": " .. (err or ""))
                local why = (err or ""):match("[^\n]+")
                a.notify(spec.run .. " failed" .. (why and ": " .. why or " (exit " .. code .. ")"))
            end
        end)
        if not started then
            a.notify("Couldn't run " .. spec.run .. " with " .. runenv)
        end
    end

    -- An app found by path, with no bundle ID, from the switcher, with
    -- `env` as a.launch gives it.
    function a.open_app(path, env)
        local args = { "-a", path }
        for _, word in ipairs(env_words(env)) do
            args[#args + 1] = "--env"
            args[#args + 1] = word
        end
        if not run("/usr/bin/open", args, function(code, err)
            if code ~= 0 then
                a.notify("Couldn't open " .. path .. ": " .. ((err or ""):match("[^\n]+") or ("exit " .. code)))
            end
        end) then
            a.notify("Couldn't open " .. path)
        end
    end

    -- An app's name, from its bundle ID, for the name prompt's default.
    function a.app_name(bundle)
        return hs.application.nameForBundleID(bundle)
    end

    -- Run JavaScript in JavaScriptCore, for the name patterns (SPEC.md
    -- §6.2). Returns ok, and the result or what went wrong.
    function a.javascript(source)
        local ok, result, err = hs.osascript.javascript(source)
        if ok then
            return true, result
        end
        return false, type(err) == "table" and (err.OSAScriptErrorMessageKey or err.NSLocalizedDescription or hs.inspect(err)) or tostring(err)
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

    -- hs.urlevent.openURL refuses a URL without "://", which a System
    -- Settings pane's lacks, so open(1) opens it.
    function a.open_url(url)
        local started = run("/usr/bin/open", { url }, function(code, err)
            if code ~= 0 then
                a.log("couldn't open " .. url .. ": " .. tostring(err))
                a.notify("Couldn't open " .. url)
            end
        end)
        if not started then
            a.log("couldn't run open for " .. url)
            a.notify("Couldn't open " .. url)
        end
    end

    function a.lock()
        hs.caffeinate.lockScreen()
    end

    function a.logout()
        local ok, _, err = hs.osascript.applescript('tell application "System Events" to log out')
        if not ok then
            a.notify("Couldn't log out: " .. hs.inspect(err))
        end
    end

    -- Write `text` to `path` whole: to a file beside it, then renamed over
    -- it, so a reader never sees half of it. Makes the folder if it's
    -- missing. Returns true, or nil and why not.
    function a.write_file(path, text)
        local dir = path:match("^(.*)/[^/]+$")
        if dir and not hs.fs.attributes(dir) then
            local _, ok = hs.execute("/bin/mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
            if not ok then
                return nil, "couldn't make " .. dir
            end
        end
        return atomic.write(path, text)
    end

    -- Put the image file at `path` on the clipboard.
    function a.copy_image(path)
        local img = hs.image.imageFromPath(path)
        if not img or not hs.pasteboard.writeObjects(img) then
            a.log("couldn't copy " .. path .. " to the clipboard")
            a.notify("Couldn't copy the screenshot to the clipboard")
        end
    end

    -- Whether `path` is a file macOS saved as a screenshot. It tags each
    -- with Spotlight's kMDItemIsScreenCapture, whatever its name. If the tag
    -- comes after the file, the folder reports the file again then.
    function a.is_shot(path)
        if hs.fs.attributes(path, "mode") ~= "file" then
            return false
        end
        for _, name in ipairs(hs.fs.xattr.list(path) or {}) do
            if name == "com.apple.metadata:kMDItemIsScreenCapture" then
                return true
            end
        end
        return false
    end

    -- Press macOS's own screenshot keys (keys.SCREENSHOT). The picker takes
    -- a moment to come up before it will hear Space.
    function a.screenshot(kind)
        local k = require("tilemo.keys").SCREENSHOT[kind]
        if not k then
            a.log("no screenshot kind " .. tostring(kind))
            return
        end
        hs.eventtap.keyStroke(k.mods, k.key, 0)
        if k["then"] then
            a.after(0.3, function()
                hs.eventtap.keyStroke({}, k["then"], 0)
            end)
        end
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
        hs.notify.new({ title = "tilemo", informativeText = text }):send()
    end

    -- This login, as when this user's loginwindow started, which a new
    -- login restarts and a Hammerspoon reload doesn't; nil, having logged
    -- why, when it can't be told.
    function a.login()
        local out, ok = hs.execute('/bin/ps -o lstart= -p "$(/usr/bin/pgrep -u "$(/usr/bin/id -u)" -x loginwindow | /usr/bin/head -n 1)"')
        local started = ok and (out or ""):match("^%s*(.-)%s*$") or ""
        if started == "" then
            a.log("couldn't tell this login from the last: " .. tostring(out))
            return nil
        end
        return started
    end

    -- This user's id, for pgrep.
    function a.uid()
        local out = hs.execute("/usr/bin/id -u")
        return (out or ""):match("%d+")
    end

    function a.now()
        return hs.timer.secondsSinceEpoch()
    end

    function a.pid_running(pid)
        return pid ~= nil and hs.application.applicationForPID(pid) ~= nil
    end

    local log = hs.logger.new("tilemo", "info")
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

-- A watcher on folder `dir`, calling `on_change()` when anything in it
-- changes. A folder that isn't there yet is made, so it can be watched.
-- What current.lua writes the workspace's name with: atomic.lua's io and
-- os, plus making a folder and setting a mode. Lua has no chmod, so that's
-- /bin/chmod, run only when the workspace changes.
local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

M.current_fs = {
    open = io.open,
    rename = os.rename,
    remove = os.remove,
    mkdir = function(path)
        if hs.fs.attributes(path, "mode") == "directory" then
            return true
        end
        return hs.fs.mkdir(path)
    end,
    chmod = function(path, mode)
        local ok, how, code = os.execute("/bin/chmod " .. mode .. " " .. shell_quote(path))
        if ok then
            return true
        end
        return nil, "chmod " .. mode .. " " .. path .. ": " .. tostring(how) .. " " .. tostring(code)
    end,
}

function M.watch_folder(dir, on_change)
    if not hs.fs.attributes(dir) then
        hs.execute("/bin/mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    end
    local watcher = hs.pathwatcher.new(dir, function()
        on_change()
    end)
    watcher:start()
    return watcher
end

-- Screenshot's folder, from its options (SPEC.md §10).
function M.screenshot_folder()
    local out, ok = hs.execute("/usr/bin/defaults read com.apple.screencapture location 2>/dev/null")
    return shots.folder(ok and out or nil, os.getenv("HOME") or "")
end

-- A watcher calling `on_change()` when Screenshot's options change, in the
-- file macOS keeps them in.
function M.screenshot_options(on_change)
    local prefs = (os.getenv("HOME") or "") .. "/Library/Preferences"
    local watcher = hs.pathwatcher.new(prefs, function(paths)
        for _, path in ipairs(paths) do
            if path:match("/com%.apple%.screencapture%.plist$") then
                on_change()
                return
            end
        end
    end)
    watcher:start()
    return watcher
end

-- A watcher on folder `dir` calling `on_paths(paths)` with what changed in
-- it, and the names of the files already there. `log(text)` hears what
-- went wrong.
function M.screenshots(dir, on_paths, log)
    local existing = {}
    if hs.fs.attributes(dir, "mode") == "directory" then
        local listed, err = pcall(function()
            for name in hs.fs.dir(dir) do
                existing[#existing + 1] = name
            end
        end)
        if not listed then
            log("couldn't list " .. dir .. ": " .. tostring(err))
        end
    end
    local watcher = hs.pathwatcher.new(dir, on_paths)
    watcher:start()
    return watcher, existing
end

-- Modifier changes, and anything that spoils a Super tap: a key, a mouse
-- button or a scroll. `on_other` gets "key" with the key's name and the
-- modifiers for a key, else "mouse". Passes every event through.
function M.taps(on_flags, on_other)
    local t = hs.eventtap.event.types
    local tap = hs.eventtap.new({
        t.flagsChanged, t.keyDown, t.leftMouseDown, t.rightMouseDown, t.otherMouseDown, t.scrollWheel,
    }, function(e)
        local kind = e:getType()
        if kind == t.flagsChanged then
            on_flags(e:getFlags())
        elseif kind == t.keyDown then
            on_other("key", hs.keycodes.map[e:getKeyCode()], e:getFlags())
        else
            on_other("mouse")
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
