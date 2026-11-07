-- The window manager's view of macOS, through Hammerspoon. Everything that
-- touches `hs` lives here, so the rest tests against a fake (tests/fake.lua).
-- Not runnable outside Hammerspoon.

local atomic = require("tide.atomic")
local bar = require("tide.bar")
local brand = require("tide.brand")
local kitty = require("tide.kitty")
local notices = require("tide.notices")
local rules = require("tide.rules")
local saved = require("tide.saved")
local runner = require("tide.runner")
local shots = require("tide.shots")
local standing = require("tide.standing")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")

-- Hammerspoon's window filters never look at Hammerspoon's own windows, the
-- bar, the launchers and the settings window among them: watching them,
-- the filter asks Accessibility about each from Hammerspoon's own thread,
-- which can't answer it, so each question waits out AX_TIMEOUT, a dozen a
-- window, while nothing else runs (CI's Mac: 3 s as the launcher shows).
-- tide leaves them alone anyway. Its console and preferences go
-- untracked with them, so they stay where macOS puts them.
local function ignore_own_windows()
    hs.window.filter.ignoreAlways = hs.window.filter.ignoreAlways or {}
    hs.window.filter.ignoreAlways["Hammerspoon"] = true
end

-- The displays as last read, until Hammerspoon is next idle or they
-- change (a.screens).
local displays = {}
local function forget_displays()
    displays.list = nil
    if displays.forget then
        displays.forget:stop()
        displays.forget = nil
    end
end

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
-- freeze tide (Amethyst#342).
M.AX_TIMEOUT = 0.25

-- kCGDockWindowLevel: a.ordered() lists the windows below it.
M.DOCK_LEVEL = 20

M.SETTINGS_KEY = "tide.state"
-- Where timo kept it, before the rename.
M.OLD_SETTINGS_KEY = "timo.state"

function M.load()
    return saved.get(hs.settings, M.SETTINGS_KEY, M.OLD_SETTINGS_KEY)
end

function M.new()
    local a = {}
    local cache = {}
    -- Windows on screen that no filter watches, id -> frame (a.ordered).
    local strangers = {}
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
    -- out, so tide would forget its place in the layout. A window filter
    -- with no current-Space setting covers them all.
    ignore_own_windows()
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
        -- A window the last a.ordered() found that nothing watches: on
        -- screen, where the window server said.
        local stranger = not cache[id] and strangers[id]
        if stranger then
            return { frame = stranger, minimized = false, fullscreen = false, hidden = false }
        end
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
            -- Whether the window has a close button: nil when there's no
            -- element to ask.
            local closable
            if el then
                closable = el:attributeValue("AXCloseButton") ~= nil
            end
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
                -- An app out of the Dock (kind 0): Notification Center,
                -- Spotlight, a menu bar app. With no close button, its
                -- window is left alone (rules.lua).
                accessory = app and app:kind() == 0 or false,
                closable = closable,
                frame = box(w:frame()),
                minimized = w:isMinimized(),
                fullscreen = w:isFullScreen(),
            }
        end)
    end

    -- What macOS says of window `id`, for the Floating page's "More about
    -- this window" (floating.about): read only when the page asks, as the
    -- app's path isn't needed to decide a window. Nil for a window gone.
    function a.about(id)
        local w = win(id)
        if not w then
            return nil
        end
        return try(function()
            local app = w:application()
            local el = hs.axuielement.windowElement(w)
            return {
                role = w:role(),
                subrole = w:subrole(),
                modal = el and el:attributeValue("AXModal"),
                size_settable = el and el:isAttributeSettable("AXSize"),
                standard = w:isStandard(),
                name = app and app:name(),
                path = app and app:path(),
            }
        end)
    end

    -- Visible windows, front to back, from the window server's on-screen
    -- list (hs.window.list), below the Dock's level, so the Dock, the menu
    -- bar, menus and other overlays aren't in it. Not
    -- hs.window.orderedWindows(): it lists only apps with a Dock icon (its
    -- visibleWindows() skips app:kind() 0), so a menu bar app's window,
    -- which tiles unless a rule floats it, never counted as in front, and
    -- focus follows mouse buried it under the tile the pointer crossed
    -- (SPEC.md §5.1). Of the windows no filter watches, only Hammerspoon's
    -- console and Preferences stay in, as strangers, by their bounds: they
    -- cover what's behind them (wm.window_at). They're named by title, as
    -- the rules name them, not looked up through Accessibility, which can't
    -- answer about Hammerspoon from its own thread. Everything else of
    -- Hammerspoon's is tide's own drawing (the dim, the bar, the drag
    -- outline, the switcher), click-through or reported by wm.own_window,
    -- and a new overlay stays out without anyone naming it.
    function a.ordered()
        local list = try(hs.window.list, true)
        if not list then
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
        local ids = {}
        strangers = {}
        for _, info in ipairs(list) do
            local id = info.kCGWindowNumber
            local layer = info.kCGWindowLayer or 0
            local b = info.kCGWindowBounds
            if id and layer >= 0 and layer < M.DOCK_LEVEL then
                if cache[id] then
                    ids[#ids + 1] = id
                elseif info.kCGWindowOwnerPID == hs.processInfo.processID and not rules.tides(info.kCGWindowName)
                    and b and (info.kCGWindowAlpha or 1) > 0 and (b.Width or 0) > 0 and (b.Height or 0) > 0 then
                    strangers[id] = box({ x = b.X or 0, y = b.Y or 0, w = b.Width, h = b.Height })
                    ids[#ids + 1] = id
                end
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

    -- Whether the menu bar is set to hide always ("Automatically hide and
    -- show the menu bar": Always; scripts' setup-macos sets Never). Read
    -- once, and again after the displays change, as they do when the
    -- setting does: the menu bar's strip comes or goes *(unverified on a
    -- Mac that the screen watcher fires for it)*. Never set, defaults
    -- fails, and that's no: kept as nil, it ran defaults, a process
    -- Hammerspoon waits on, at every display read.
    local menu_bar_hidden
    local function hides_menu_bar()
        if menu_bar_hidden == nil or displays.menu_bar_stale then
            displays.menu_bar_stale = false
            local out, ok = hs.execute("/usr/bin/defaults read -g _HIHideMenuBar 2>/dev/null")
            menu_bar_hidden = (ok and (out or ""):match("^%s*1") ~= nil) or false
        end
        return menu_bar_hidden
    end

    -- The displays, read once until Hammerspoon is next idle: each read
    -- of every display's ID and frames takes 20 ms or more, even on CI's
    -- Mac, and one change redraws the bar and the tray, which asked eight
    -- times. A display that changes meanwhile is read afresh as macOS says
    -- so (M.watch). Each caller gets its own copy.
    local function copy(list)
        local out = {}
        for i, s in ipairs(list) do
            out[i] = {
                uuid = s.uuid,
                area = { x = s.area.x, y = s.area.y, w = s.area.w, h = s.area.h },
                full = { x = s.full.x, y = s.full.y, w = s.full.w, h = s.full.h },
                notch = s.notch,
                menu_bar = s.menu_bar,
            }
        end
        return out
    end
    a.hides_menu_bar = hides_menu_bar

    function a.screens()
        if displays.list then
            return copy(displays.list)
        end
        local out = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            local area, full = box(s:frame()), box(s:fullFrame())
            local notch, menu_bar = bar.top_room(area, full, hides_menu_bar())
            out[#out + 1] = { uuid = s:getUUID(), area = area, full = full, notch = notch, menu_bar = menu_bar }
        end
        -- Left to right, then top to bottom, so numbering is stable.
        table.sort(out, function(p, q)
            if p.full.x ~= q.full.x then
                return p.full.x < q.full.x
            end
            return p.full.y < q.full.y
        end)
        displays.list = out
        if not displays.forget then
            displays.forget = hs.timer.doAfter(0, forget_displays)
        end
        return copy(out)
    end

    -- Nothing, while Hammerspoon has the focus: one of tide's own
    -- windows, or the console, none of which the window manager knows
    -- (M.watch). Asking Accessibility about Hammerspoon from its own thread
    -- waits out M.AX_TIMEOUT, and the attention poll and the bar ask over
    -- and over, which held Esc in the launcher for seconds.
    local me = hs.processInfo.processID
    local function focused_in(app)
        if not app or app:pid() == me then
            return nil
        end
        local w = try(app.focusedWindow, app)
        return w and try(w.id, w)
    end

    function a.focused()
        return focused_in(hs.application.frontmostApplication())
    end

    function a.app_focused(pid)
        return focused_in(pid and hs.application.applicationForPID(pid))
    end

    -- Give the focus to Hammerspoon itself, with no window of its own in
    -- front, so typing reaches no app's window (wm's unfocus_parked)
    -- *(unverified on a Mac that activating it opens no console)*.
    function a.focus_none()
        local app = hs.application.applicationForPID(me)
        if app then
            app:activate()
        end
    end

    -- Whether Hammerspoon has the focus, which focused() can't say.
    function a.own_front()
        local app = hs.application.frontmostApplication()
        return app ~= nil and app:pid() == me
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

    -- Where every window is, for the next start (SPEC.md §6.5).
    function a.save(snap)
        hs.settings.set(M.SETTINGS_KEY, saved.form(snap))
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

    -- The Mac app an `inApps` entry from tide's files names, as
    -- { path, bundle }, or nil when there's none (SPEC.md §6.2). A Mac's
    -- disk ignores case, as a rule, so `gmail` finds Gmail.app.
    function a.find_app(entry)
        for _, path in ipairs(standing.app_paths(entry, os.getenv("HOME") or "")) do
            if hs.fs.attributes(path, "mode") == "directory" then
                local info = hs.application.infoForBundlePath(path)
                return { path = path, bundle = info and info.CFBundleIdentifier }
            end
        end
    end

    -- One of home's apps by name, at login (SPEC.md §6.2): in the
    -- background (`open -g`), so it doesn't take focus. One that won't open,
    -- such as a name with no app, says so, with what open printed.
    function a.open_in_background(name)
        if not run("/usr/bin/open", { "-g", "-a", name }, function(code, err)
            if code ~= 0 then
                a.notify("Couldn't open " .. name .. " on home: " .. ((err or ""):match("[^\n]+") or ("exit " .. code)))
            end
        end) then
            a.notify("Couldn't open " .. name .. " on home")
        end
    end

    -- An app by bundle ID, in the background (`open -g`), without its
    -- window: `done(ok, why)` once open has.
    function a.open_bundle_in_background(bundle, done)
        if not run("/usr/bin/open", { "-g", "-b", bundle }, function(code, err)
            done(code == 0, code ~= 0 and (((err or ""):match("[^\n]+")) or ("exit " .. code)) or nil)
        end) then
            done(false, "couldn't run open")
        end
    end

    -- macOS's natural-scrolling switch, read fresh each time, as
    -- `done(code, out)` with what defaults printed, either stream:
    -- hs.mouse.scrollDirection() takes the switch as off while it's unset,
    -- where macOS takes it as on.
    function a.read_natural(done)
        if not run("/usr/bin/defaults", { "read", "-g", "com.apple.swipescrolldirection" }, function(code, err, out)
            done(code, (out or "") .. (err or ""))
        end) then
            done(-1, "couldn't run defaults")
        end
    end

    -- Whether a file is at `path`, through any symlink, as Foundation's
    -- fileExists says.
    function a.exists(path)
        return hs.fs.attributes(path) ~= nil
    end

    -- Whether an app of that exact name is running.
    function a.app_running(name)
        return hs.application.get(name) ~= nil
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

    -- Whether Hammerspoon has Accessibility, without asking for it: false
    -- shows no prompt (the setup checklist, tide doctor).
    function a.accessibility()
        return hs.accessibilityState(false)
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

    -- Open a helper's own window (links.APPS): `spec.bundle` by bundle ID,
    -- or `spec.app` by name, with `spec.args` for it as it starts.
    function a.open_helper(spec)
        local args = spec.bundle and { "-b", spec.bundle } or { "-a", spec.app }
        if spec.args and #spec.args > 0 then
            args[#args + 1] = "--args"
            for _, v in ipairs(spec.args) do
                args[#args + 1] = v
            end
        end
        local what = spec.bundle or spec.app
        local started = run("/usr/bin/open", args, function(code, err)
            if code ~= 0 then
                a.log("couldn't open " .. what .. ": " .. tostring(err))
                a.notify("Couldn't open " .. what .. ": " .. ((err or ""):match("[^\n]+") or ("exit " .. code)))
            end
        end)
        if not started then
            a.log("couldn't run open for " .. what)
            a.notify("Couldn't open " .. what)
        end
    end

    -- Whether an app with this bundle ID is installed, as Launch Services
    -- finds it, and whether one is running. On CI's Mac, with no such app,
    -- the path came back as something other than nil, so it must be one
    -- that's there.
    function a.app_installed(bundle)
        local path = hs.application.pathForBundleID(bundle)
        return type(path) == "string" and path ~= "" and hs.fs.attributes(path) ~= nil
    end

    function a.bundle_running(bundle)
        return #(hs.application.applicationsForBundleID(bundle) or {}) > 0
    end

    -- The file names in `dir`, or nil if it can't be read.
    function a.list_dir(dir)
        local ok, iter, obj = pcall(hs.fs.dir, dir)
        if not ok or not iter then
            return nil
        end
        local out = {}
        for name in iter, obj do
            if name ~= "." and name ~= ".." then
                out[#out + 1] = name
            end
        end
        return out
    end

    -- The file `path` names, through any symlinks, so a write replaces it
    -- rather than the link; `path` itself when it isn't there.
    function a.resolve(path)
        return hs.fs.pathToAbsolute(path) or path
    end

    function a.lock()
        hs.caffeinate.lockScreen()
    end

    -- Asks System Events to log out, restart or shut down, as
    -- hs.caffeinate's do, but saying so when it can't: AppleScript returns a
    -- failure, such as Automation access to System Events being denied,
    -- rather than raising it, and hs.caffeinate drops it.
    local function system_events(verb)
        local ok, _, err = hs.osascript.applescript('tell application "System Events" to ' .. verb)
        if not ok then
            a.log("couldn't " .. verb .. ": " .. hs.inspect(err))
            a.notify("Couldn't " .. verb .. ": " .. hs.inspect(err))
        end
        return ok
    end

    function a.logout()
        return system_events("log out")
    end

    function a.restart()
        return system_events("restart")
    end

    function a.shutdown()
        return system_events("shut down")
    end

    function a.sleep()
        hs.caffeinate.systemSleep()
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
        local k = require("tide.keys").SCREENSHOT[kind]
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

    -- tide's logo as an hs.image, `name` one of brand.lua's, read once and
    -- sized in points; nil, having logged why, if it can't be read, so a
    -- notice or the menu bar goes without it rather than failing.
    local logos = {}
    function a.logo(name)
        if logos[name] == nil then
            local path = brand.icon_path(DIR, name)
            local img = hs.image.imageFromPath(path)
            if img then
                img:size(name == brand.TEMPLATE and brand.TEMPLATE_SIZE or brand.LOGO_SIZE)
                img:template(name == brand.TEMPLATE)
            else
                a.log("couldn't read the logo at " .. path)
            end
            logos[name] = img or false
        end
        return logos[name] or nil
    end

    -- A notification saying `text`, titled tide, with the logo; `fn` and
    -- `extra` are hs.notify.new's callback and more attributes.
    function a.notify(text, fn, extra)
        hs.notify.new(fn, brand.notice(text, a.logo(brand.LOGO), extra)):send()
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

    local log = hs.logger.new(brand.NAME, "info")
    function a.log(text)
        log.i(text)
    end

    return a
end

-- Call `on_change` on any window coming, going, hiding or changing state,
-- `on_focus(id)` when one gains focus, `on_moved(id)` when one moves or
-- changes size, `on_min(id)` / `on_unmin(id)` when one is minimized or
-- comes back, and `on_title(id)` when its title changes (Hammerspoon waits
-- 0.5 s after the last change to say so). Returns what to keep alive.
-- tide's own windows, which the rules leave alone, are left out: each
-- time the launcher showed or hid, its window's coming and going made the
-- window manager sync and retile every window, and its focus made it list
-- them all again, while Esc waited.
function M.watch(on_change, on_focus, on_moved, on_min, on_unmin, on_title)
    ignore_own_windows()
    local me = hs.processInfo.processID
    local function tides(w)
        local ok, pid = pcall(w.pid, w)
        if not ok or pid ~= me then
            return false
        end
        local got, title = pcall(w.title, w)
        return rules.tides(got and title or "")
    end
    local wf = hs.window.filter.new(false)
    wf:setDefaultFilter({ allowRoles = "*" })
    wf:subscribe({
        hs.window.filter.windowCreated,
        hs.window.filter.windowDestroyed,
        hs.window.filter.windowHidden,
        hs.window.filter.windowUnhidden,
        hs.window.filter.windowFullscreened,
        hs.window.filter.windowUnfullscreened,
    }, function(w)
        if not (w and tides(w)) then
            on_change()
        end
    end)
    local function with_id(fn)
        return function(w)
            if tides(w) then
                return
            end
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
    wf:subscribe(hs.window.filter.windowTitleChanged, with_id(on_title))
    local sw = hs.screen.watcher.new(function(...)
        forget_displays()
        displays.menu_bar_stale = true
        on_change(...)
    end)
    sw:start()
    return { wf, sw }
end

-- Notification Center's banners (SPEC.md §14.2): `on_notice(app, site)`
-- for each new one, with `app` the sender's bundle ID and `site` a browser
-- notification's host or nil. Watched through Accessibility, which says
-- when its window or a banner in it appears *(unverified on macOS 26:
-- which of these notifications fire)*. A banner hidden by a Focus never
-- shows, so it marks nothing. `log` hears what went wrong. Returns what to
-- keep alive, started again when Notification Center restarts.
local NC = "com.apple.notificationcenterui"

local function app_bundle(name)
    for _, app in ipairs(hs.application.runningApplications()) do
        local ok, n = pcall(app.name, app)
        if ok and n == name then
            local got, bundle = pcall(app.bundleID, app)
            return got and bundle or nil
        end
    end
    return nil
end

function M.notifications(on_notice, log)
    local keep = { seen = {} }
    local function attr(el, name)
        local ok, v = pcall(el.attributeValue, el, name)
        return ok and v or nil
    end
    -- Every banner showing, each new one reported once: a banner is told
    -- apart by its text, kept while it shows.
    local function scan(root)
        local showing = {}
        local function walk(el, depth)
            if depth > 6 then
                return
            end
            if notices.is_banner(attr(el, "AXSubrole")) then
                local desc = attr(el, "AXDescription")
                local stacking = attr(el, "AXStackingIdentifier")
                local key = tostring(stacking) .. "\0" .. tostring(desc)
                showing[key] = true
                if not keep.seen[key] then
                    local who = notices.sender(desc, stacking)
                    local app = who and (who.app or (who.name and app_bundle(who.name)))
                    if app then
                        on_notice(app, who.site)
                    elseif who then
                        log("a notification from " .. tostring(who.name) .. ", which isn't running, marks nothing")
                    end
                end
                return
            end
            for _, child in ipairs(attr(el, "AXChildren") or {}) do
                walk(child, depth + 1)
            end
        end
        walk(root, 0)
        keep.seen = showing
    end
    local function attach()
        local app = hs.application.get(NC)
        if not app then
            return
        end
        local el = hs.axuielement.applicationElement(app)
        local ok, ob = pcall(hs.axuielement.observer.new, app:pid())
        if not (ok and ob and el) then
            log("couldn't watch Notification Center's banners: " .. tostring(ob))
            return
        end
        ob:callback(function()
            local fine, err = pcall(scan, el)
            if not fine then
                log("couldn't read a notification banner: " .. tostring(err))
            end
        end)
        for _, note in ipairs({ "AXWindowCreated", "AXCreated", "AXLayoutChanged" }) do
            local added, err = pcall(ob.addWatcher, ob, el, note)
            if not added then
                log("couldn't watch Notification Center for " .. note .. ": " .. tostring(err))
            end
        end
        ob:start()
        keep.observer = ob
    end
    attach()
    keep.apps = hs.application.watcher.new(function(_, event, app)
        local ok, bundle = pcall(app.bundleID, app)
        if ok and bundle == NC and event == hs.application.watcher.launched then
            if keep.observer then
                keep.observer:stop()
            end
            keep.observer = nil
            attach()
        end
    end)
    keep.apps:start()
    return keep
end

-- `hammerspoon://tide-bell?window=<id>`: window `id` (its CGWindowID, as
-- hs.window:id()) rang the bell. conf's kitty runs this on a bell, as
-- tide's kitty activates its window (SPEC.md §14.2). Any program of yours
-- can open it, and all it can do is mark a window.
function M.bells(on_bell, log)
    hs.urlevent.bind("tide-bell", function(_, params)
        local id = tonumber(params and params.window)
        if id then
            on_bell(id)
        else
            log("a bell named no window: " .. hs.inspect(params))
        end
    end)
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
    kind = function(path)
        local mode = hs.fs.symlinkAttributes(path, "mode")
        if mode == "link" then
            return "link"
        end
        return mode == "directory" and "directory" or (mode and "file" or nil)
    end,
    symlink = function(target, path)
        return hs.fs.link(target, path, true)
    end,
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
    -- The paths that changed, for a watcher that cares which.
    local watcher = hs.pathwatcher.new(dir, function(paths)
        on_change(paths)
    end)
    watcher:start()
    return watcher
end

-- `fn()` when a USB device is plugged in, and on a wake or an unlock
-- (SPEC.md §10): the watchers, to keep.
function M.plugs_and_wakes(fn)
    local usb = hs.usb.watcher.new(function(e)
        if e and e.eventType == "added" then
            fn()
        end
    end)
    usb:start()
    local w = hs.caffeinate.watcher
    local wakes = { [w.systemDidWake] = true, [w.screensDidWake] = true, [w.screensDidUnlock] = true }
    local caffeinate = w.new(function(e)
        if wakes[e] then
            fn()
        end
    end)
    caffeinate:start()
    return { usb = usb, caffeinate = caffeinate }
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

-- The fingers on the trackpad, from each gesture event, for the swipe
-- between workspaces (swipe.lua): `fn` gets an array of { id, x, y }, in
-- the trackpad's own 0 to 1 coordinates, leaving out the fingers lifting,
-- and whether a mouse button is down. Passes every event through, so apps still see pinches and scrolls.
-- `getTouches()`' fields on macOS 26 are unverified on a Mac.
function M.gestures(fn)
    local tap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, function(e)
        local list = {}
        for _, touch in ipairs(e:getTouches() or {}) do
            local phase = touch.phase
            local p = touch.normalizedPosition
            if p and touch.touching ~= false and phase ~= "ended" and phase ~= "cancelled" then
                list[#list + 1] = { id = touch.identity, x = p.x, y = p.y }
            end
        end
        local dragging = false
        for _, down in pairs(hs.eventtap.checkMouseButtons()) do
            dragging = dragging or down
        end
        fn(list, dragging)
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
