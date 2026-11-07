-- tide on Hammerspoon. From ~/.hammerspoon/init.lua:
--
--   tide = require("tide")
--   tide.start({})
--
-- start() takes { layout = ..., rules = {...}, focus_follows_mouse = true,
-- keep_focus = {...}, bar = true }: `layout` overrides tide/layout.lua's
-- defaults whole, and tide's layouts.json and layouts.local.json lay over
-- it (SPEC.md §15), `rules` are float rules that come before the ones you
-- make on the settings window's Floating page and the built-in ones
-- (tide/rules.lua, floating.lua), and `keep_focus` names more apps, by bundle ID,
-- that keep focus while they're in front. `bar = false` leaves out the bar
-- along the top and shows the workspaces in the menu bar instead.
-- `swipe = false` turns off the three-finger swipe between workspaces,
-- and `compose = false` Caps Lock as Compose.
-- `workspaces` names the standing workspaces, always listed and never
-- removed, the first being home (SPEC.md §6.1); it defaults to
-- wm.STANDING, home being "in". `home_apps` names the apps, by app name,
-- whose windows always open on home (SPEC.md §6.2); it defaults to
-- wm.HOME_APPS. A list you set also starts at login. `workspace_settings`
-- is each workspace's own, as tide's workspaceSettings: { ["in"] = {
-- askForName = true, pinnedApps = { "Gmail" } } }, whether a new window
-- there asks for a name and the apps whose windows tide's close keys
-- leave open there (SPEC.md §6.2); it defaults to home asking. tide's
-- `standing`, `inApps` and `workspaceSettings`, in workspaces.json and
-- workspaces.local.json, take the place of each where a file sets it
-- (SPEC.md §15).
-- tide.toggle_focus_follows_mouse() turns focus follows mouse off and on.
-- tide.workspace() gives the current workspace's TIDE_WORKSPACE. Scripts
-- read it from ~/Library/Caches/tide/workspace instead (SPEC.md §6.3):
-- tide never loads hs.ipc, whose port runs any Lua a local process sends.

local keys = require("tide.keys")
local mouse = require("tide.mouse")
local wm_mod = require("tide.wm")
local namealert = require("tide.namealert")
local adapter_mod = require("tide.hs_adapter")
local ffm_mod = require("tide.ffm")
local dashboard_hs = require("tide.dashboard_hs")
local overview_hs = require("tide.overview_hs")
local launcherpage = require("tide.launcherpage")
local picker_hs = require("tide.picker_hs")
local picker = require("tide.picker")
local settings_hs = require("tide.settings_hs")
local wallpaper_hs = require("tide.wallpaper_hs")
local theme_hs = require("tide.theme_hs")
local idle_hs = require("tide.idle_hs")
local dndsched_hs = require("tide.dndsched_hs")
local floating_hs = require("tide.floating_hs")
local pinned_hs = require("tide.pinned_hs")
local dashboard = require("tide.dashboard")
local shots = require("tide.shots")
local tap_mod = require("tide.tap")
local swipe_mod = require("tide.swipe")
local compose_mod = require("tide.compose")
local compose_hs = require("tide.compose_hs")
local bar = require("tide.bar")
local selfreload = require("tide.selfreload")
local bar_hs = require("tide.bar_hs")
local tray_hs = require("tide.tray_hs")
local dim_hs = require("tide.dim_hs")
local names = require("tide.names")
local mute = require("tide.mute")
local standing = require("tide.standing")
local startup = require("tide.startup")
local current = require("tide.current")
local saved = require("tide.saved")
local clipstore = require("tide.clipstore")
local clipcrypt = require("tide.clipcrypt")
local prompt_hs = require("tide.prompt_hs")
local presenter_hs = require("tide.presenter_hs")
local presenter = require("tide.presenter")
local layout = require("tide.layout")
local brand = require("tide.brand")
local links = require("tide.links")
local linearmouse = require("tide.linearmouse")
local karabiner = require("tide.karabiner")
local checklist = require("tide.checklist")
local inputsrc = require("tide.inputsrc")

local M = {}

-- How often to look for Karabiner starting or stopping, so the keys move
-- with it without a restart (SPEC.md §7.1), and for LinearMouse (§10).
M.KARABINER_CHECK = 30
-- How long after the last device plugged in, or a wake, to set the mouse
-- and check Karabiner's rules: a KVM brings several at once (SPEC.md §10).
M.PLUG_DELAY = 1
-- How often to read window titles, and clear the focused window's marks.
M.ATTENTION_POLL = 2

local function bind_all(self)
    for _, h in ipairs(self.hotkeys or {}) do
        h:delete()
    end
    self.hotkeys = {}
    local list, skipped = keys.bindings(self.super)
    -- What registered and what didn't, for the settings window's Shortcuts
    -- and tide doctor (SPEC.md §15).
    local bound, failed = {}, {}
    local function bind(mods, b)
        local fn = function()
            self.wm:act(b.action, b.arg)
        end
        -- One bad or taken key mustn't stop the rest binding.
        local ok, h = pcall(hs.hotkey.bind, mods, b.key, fn, nil, b.repeating and fn or nil)
        if ok and h then
            self.hotkeys[#self.hotkeys + 1] = h
            bound[#bound + 1] = b
        else
            local why = ok and "macOS wouldn't register it" or ("macOS wouldn't register it: " .. tostring(h))
            self.adapter.log("couldn't bind " .. table.concat(mods, "+") .. "+" .. b.key .. ": " .. why)
            failed[#failed + 1] = { keys = b.keys, does = b.does, why = why }
        end
    end
    for _, b in ipairs(list) do
        bind(b.mods, b)
    end
    for _, s in ipairs(skipped) do
        self.adapter.log("left out " .. s.chord .. ": another key has it")
        failed[#failed + 1] = s
    end
    self.shortcuts = keys.shortcuts(bound, failed)
    if self.settings then
        self.settings.refresh()
    end
end

local function resize_mode(self)
    local modal = hs.hotkey.modal.new()
    -- The float being resized keeps focus while the mode is on.
    function modal.entered()
        self.wm:hold("resize", true)
    end
    function modal.exited()
        self.wm:hold("resize", false)
    end
    for _, b in ipairs(keys.resize) do
        local fn = function()
            self.wm:act("resize_by", b.d)
        end
        modal:bind({}, b.key, fn, nil, fn)
    end
    for _, k in ipairs(keys.resize_exit) do
        modal:bind({}, k, function()
            modal:exit()
        end)
    end
    return modal
end

-- With Karabiner's rule loaded, what an out-of-date copy of it is missing
-- (keys.rule_gaps), said once each time that changes, so a key that can't
-- work is flagged rather than silently dead.
local function check_rule(self)
    local gaps = self.karabiner and keys.rule_gaps(self.adapter.read, os.getenv("HOME") or "", self.adapter.decode)
        or {}
    self.rule_gaps = gaps
    local said = table.concat(gaps, "\n")
    if said ~= (self.said_gaps or "") then
        self.said_gaps = said
        if #gaps > 0 then
            self.adapter.notify(keys.gaps_notice(gaps))
        end
    end
end

local function choose_super(self, announce)
    local super, karabiner = keys.super(self.adapter.read, self.adapter.running, os.getenv("HOME") or "",
        self.adapter.decode)
    if self.karabiner == karabiner then
        check_rule(self)
        return
    end
    self.karabiner = karabiner
    self.super = super
    bind_all(self)
    if not karabiner and announce then
        self.adapter.notify(keys.FALLBACK_NOTICE)
    end
    check_rule(self)
end

-- LinearMouse installed and running, for the mouse wheel (SPEC.md §10):
-- what's wrong, said once each time that changes, and on the settings
-- window's Mouse section. A click on the notice for it stopped starts it.
local function check_linearmouse(self)
    -- Not while tide is starting it: it isn't running yet.
    if self.linearmouse_settings and self.linearmouse_settings.launching then
        return
    end
    local kind = linearmouse.problem(function()
        return self.adapter.app_installed(linearmouse.BUNDLE)
    end, function()
        return self.adapter.bundle_running(linearmouse.BUNDLE)
    end)
    if kind == self.linearmouse then
        return
    end
    self.linearmouse = kind
    if kind then
        local start = kind == "stopped" and function()
            links.open("linearmouse", self.adapter)
        end or nil
        self.adapter.notify(linearmouse.say(kind, "notice"), start)
    end
    if self.settings then
        self.settings.refresh()
    end
end

-- conf's Karabiner rules (SPEC.md §15): brought up to date with their
-- files, a new one turned on once, and the settings window's Keyboard
-- section told when what it shows changed.
local function check_karabiner_rules(self)
    if not self.karabiner_rules then
        return
    end
    local ok, s = pcall(self.karabiner_rules.check)
    if not ok then
        self.adapter.log("Karabiner's rules: " .. tostring(s))
        return
    end
    local sig = s.problem
    for _, r in ipairs(s.rules) do
        sig = sig .. "\0" .. r.description .. (r.on and "1" or "0")
    end
    if sig ~= self.karabiner_sig then
        self.karabiner_sig = sig
        if self.settings then
            self.settings.refresh()
        end
    end
end

-- What `tide doctor` (SPEC.md §15) checks so far: Accessibility,
-- Karabiner and tide's rule, and LinearMouse. Each problem is one line, with what it costs and
-- the fix; with none, one line saying so. From Hammerspoon's console, or
-- the switcher's "Check tide".
function M.doctor()
    local lines = {}
    local hides = M.adapter and M.adapter.hides_menu_bar
    for _, line in ipairs(checklist.doctor({
        accessibility = M.adapter and M.adapter.accessibility(),
        menu_bar_hidden = M.bar ~= nil and hides ~= nil and hides(),
    })) do
        lines[#lines + 1] = line
    end
    if not M.karabiner then
        lines[#lines + 1] = keys.FALLBACK_NOTICE
    elseif #(M.rule_gaps or {}) > 0 then
        lines[#lines + 1] = keys.gaps_notice(M.rule_gaps)
    end
    local failed_keys = keys.failed_notice(M.shortcuts and M.shortcuts.failed)
    if failed_keys then
        lines[#lines + 1] = failed_keys
    end
    if M.linearmouse then
        lines[#lines + 1] = linearmouse.say(M.linearmouse, "doctor")
    end
    for _, line in ipairs(M.linearmouse_settings and M.linearmouse_settings.doctor() or {}) do
        lines[#lines + 1] = line
    end
    for _, line in ipairs(M.karabiner_rules and M.karabiner_rules.doctor() or {}) do
        lines[#lines + 1] = line
    end
    if M.presenter and #M.presenter.missing > 0 then
        lines[#lines + 1] = presenter.setup_notice(M.presenter.missing)
    end
    if #(M.workspace_errors or {}) > 0 then
        lines[#lines + 1] = "Workspaces: " .. table.concat(M.workspace_errors, "; ")
    end
    if #(M.mute_errors or {}) > 0 then
        lines[#lines + 1] = "Muted apps and sites: " .. table.concat(M.mute_errors, "; ")
    end
    if #lines == 0 then
        lines[1] = "Hammerspoon has Accessibility; Karabiner is running with " .. brand.NAME .. "'s rule, up to date, and conf's rules on;"
            .. " LinearMouse is running with tide's Mouse settings, every muted entry reads, every key registered, and Do Not Disturb's shortcuts are there."
    end
    return table.concat(lines, "\n")
end

function M.start(config)
    local self = M
    hs.window.animationDuration = 0
    -- What tilemo saved, and its folder, before anything reads them.
    saved.move_prefix(hs.settings, "tilemo.", "tide.")
    local moved, why = current.move_old(os.getenv("HOME") or "", adapter_mod.current_fs)
    self.adapter = adapter_mod.new()
    if not moved then
        self.adapter.log(why)
    end
    config = config or {}
    -- The switcher, or the dashboard launcher, switched off by default
    -- (SPEC.md §9.2): the one chosen under Keyboard in tide's settings, or
    -- else start()'s, where a bad value is an error now, not on the first
    -- key.
    -- The Appearance page's Menu bar switch, on unless turned off there.
    self.keep_menu_bar_hidden = hs.settings.get("tide.keep_menu_bar_hidden") ~= false
    self.launcher_choice = launcherpage.choose(hs.settings.get(launcherpage.SETTINGS_KEY), config.launcher,
        self.adapter.log)
    local launcher_module = launcherpage.MODULE[self.launcher_choice]
    config.saved = adapter_mod.load()
    -- The tiling area starts below the bar.
    config.top = config.bar ~= false and bar.HEIGHT or 0
    swipe_mod.check(config.swipe)
    compose_mod.check(config.compose)
    -- The layouts are tide's, from layouts.json and layouts.local.json in
    -- its settings folder, over `layout` or tide's defaults (SPEC.md §15),
    -- read before the first workspace is made and again when they change.
    local layout_base = config.layout or layout.defaults
    self.layout_base = layout_base
    -- The standing workspaces, home's apps and each workspace's settings
    -- are tide's `standing`, `inApps` and `workspaceSettings`, from
    -- workspaces.json and workspaces.local.json (SPEC.md §15), each falling
    -- back to start()'s `workspaces`, `home_apps` and `workspace_settings`,
    -- or tide's defaults, when no file sets it.
    local start_home_apps = config.home_apps
    self.workspace_base = {
        standing = wm_mod.check_standing(config.workspaces or wm_mod.STANDING),
        inApps = config.home_apps or wm_mod.HOME_APPS,
        workspaceSettings = wm_mod.check_workspace_settings(config.workspace_settings),
    }
    wm_mod.check_home_apps(self.workspace_base.inApps)
    local ws_settings, ws_errors = standing.load(dashboard.clock_dir(os.getenv), self.adapter.read, self.adapter.decode)
    config.workspaces = ws_settings and ws_settings.standing or self.workspace_base.standing
    config.home_apps = ws_settings and ws_settings.inApps or self.workspace_base.inApps
    config.workspace_settings = ws_settings and ws_settings.workspaceSettings or self.workspace_base.workspaceSettings
    local layout_errors
    config.layout, layout_errors = layout.load_settings(
        dashboard.clock_dir(os.getenv), self.adapter.read, self.adapter.decode, layout_base)
    self.wm = wm_mod.new(self.adapter, config)
    -- An app's own close and quit keys, kept from a pinned window.
    self.pinned_keys = pinned_hs.new(hs, self.wm, self.adapter.log)
    -- Hammerspoon's console floats (rules.lua) at a floating window level of
    -- its own, so no tile's raise can bury it (SPEC.md §5.1).
    local ok, err = pcall(hs.console.level, hs.drawing.windowLevels.floating)
    if not ok then
        self.adapter.log("the console's window level: " .. tostring(err))
    end
    self.wm.ffm = ffm_mod.new(self.wm, self.adapter, {
        enabled = config.focus_follows_mouse ~= false,
        keep_focus = config.keep_focus,
        super_held = function()
            return keys.super_held(self.super, hs.eventtap.checkKeyboardModifiers())
        end,
    })
    -- The float rules you made on the Floating page, from tide's settings
    -- folder (SPEC.md §15), before the first windows are decided.
    self.clock_dir = dashboard.clock_dir(os.getenv)
    self.floating = floating_hs.new(self, self.adapter.login)
    self.floating.load()
    self.wm.floated_by_hand = function(id)
        self.floating.ask(id)
    end
    self.wm.open_float_rule = function(id)
        self.floating.open(id)
    end
    self.wm:sync()
    self.wm:reconcile()
    self.wm:retile()
    self.watchers = adapter_mod.watch(function()
        self.wm:schedule()
    end, function(id)
        self.wm:focused(id)
        -- Focus may have gone to a window tide doesn't manage, which
        -- changes nothing else.
        if self.dim then
            self.dim.update()
        end
    end, function(id)
        self.wm:moved(id)
        if self.dim then
            self.dim.update()
        end
    end, function(id)
        self.wm:minimized(id)
    end, function(id)
        self.wm:unminimized(id)
    end, function(id)
        self.wm:retitled(id)
    end)
    -- Notifications and bells want attention (SPEC.md §14.2).
    self.notice_watch = adapter_mod.notifications(function(app, site)
        self.wm:notified(app, site)
    end, self.adapter.log)
    adapter_mod.bells(function(id)
        self.wm:rang(id)
    end, self.adapter.log)
    -- Quitting or reloading Hammerspoon brings back every hidden window.
    hs.shutdownCallback = function()
        self.wm:restore_all()
    end
    self.resize = resize_mode(self)
    self.wm.enter_resize_mode = function()
        self.resize:enter()
    end
    self.mouse = adapter_mod.mouse(function(flags)
        return keys.is_super(self.super, flags)
    end, {
        grab = function(kind, x, y)
            return self.wm:grab(kind, x, y)
        end,
        update = function(d, x, y)
            self.adapter.outline(mouse.update(d, x, y))
        end,
        drop = function(d, x, y)
            self.adapter.outline(nil)
            self.wm:drop(d, x, y)
        end,
        middle = function(x, y)
            self.wm:maximize_at(x, y)
        end,
        clicked = function()
            self.wm:clicked()
        end,
    })
    self.pointer = adapter_mod.pointer_moves(function(x, y, flags)
        self.wm.ffm:move(x, y, keys.super_held(self.super, flags))
        if self.bar then
            self.bar.pointer(x, y)
        end
    end)
    -- The clocks are tide's, from its settings folder, read again whenever
    -- anything there changes (SPEC.md §15). The pages say when a file is
    -- wrong; each distinct complaint is a notification once.
    self.clock_dir = dashboard.clock_dir(os.getenv)
    self.clock_files = dashboard.clock_files(self.clock_dir, self.adapter.read)
    self.startup_files = dashboard.startup_files(self.clock_dir, self.adapter.read)
    local reported
    self.report_clock_errors = function(errors)
        local text = table.concat(errors or {}, "; ")
        if text ~= "" and text ~= reported then
            reported = text
            self.adapter.notify("The clocks stay as they were: " .. text)
        end
    end
    -- And which clocks those are: the last good ones a page loaded, for a
    -- page opened while a file is wrong.
    self.keep_good_clocks = function(clocks)
        self.good_clocks = clocks
    end
    -- tide's title patterns for workspace names, from the same folder
    -- (SPEC.md §6.2, §15), checked when tide starts and whenever the
    -- folder changes. A bad list is said once, naming the file and the
    -- pattern, and the last good one stays.
    self.name_patterns = {}
    local reported_patterns
    local function load_patterns()
        local list, err = names.load(self.clock_dir, self.adapter.read, self.adapter.decode, self.adapter.javascript)
        if list then
            self.name_patterns = list
            reported_patterns = nil
        elseif err ~= reported_patterns then
            reported_patterns = err
            self.adapter.notify("Workspace name patterns stay as they were: " .. err)
        end
    end
    load_patterns()
    -- The muted apps and sites, from the same folder (SPEC.md §14.2, §15).
    -- A malformed entry is said once, naming it, and the rest still count;
    -- a file that can't be read is said once, and the last good list stays.
    self.mute_errors = {}
    local reported_mute
    local function load_muted()
        local set, errors = mute.load(self.clock_dir, self.adapter.read, self.adapter.decode)
        self.mute_errors = errors
        -- A file that can't be read keeps the last good list.
        if set then
            self.wm:set_muted(set)
        end
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported_mute then
            self.adapter.notify((set and "Some muted entries are left out: " or "What's muted stays as it was: ") .. text)
        end
        reported_mute = text
    end
    self.load_muted = load_muted
    load_muted()
    -- The standing workspaces, home's apps and each workspace's settings,
    -- read again as the folder changes. A file that's wrong is said once,
    -- naming it and the setting, and the last good settings stay.
    local reported_workspaces
    local function report_workspaces(errors)
        self.workspace_errors = errors
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported_workspaces then
            self.adapter.notify("The workspaces stay as they were: " .. text)
        end
        reported_workspaces = text
    end
    local function load_workspaces()
        local s, errors = standing.load(self.clock_dir, self.adapter.read, self.adapter.decode)
        report_workspaces(errors)
        self.workspace_files = dashboard.workspace_files(self.clock_dir, self.adapter.read)
        if not s then
            return
        end
        local ok, err = pcall(self.wm.set_workspaces, self.wm, s.standing or self.workspace_base.standing,
            s.inApps or self.workspace_base.inApps)
        if ok then
            ok, err = pcall(self.wm.set_workspace_settings, self.wm,
                s.workspaceSettings or self.workspace_base.workspaceSettings)
        end
        if not ok then
            report_workspaces({ tostring(err) })
        end
    end
    report_workspaces(ws_errors)
    self.workspace_files = dashboard.workspace_files(self.clock_dir, self.adapter.read)
    -- Start at login: tide's `commands`, from the same folder (SPEC.md
    -- §15), run once a login through runenv, as a helper key runs one,
    -- unless running already. A bad entry is said once, naming it, and the
    -- rest still run; a file that can't be read runs nothing until it's
    -- fixed.
    local reported_startup
    local function start_list()
        local list, errors = startup.load(self.clock_dir, self.adapter.read, self.adapter.decode)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported_startup then
            self.adapter.notify((list and "Some commands at login are left out: " or "Nothing runs at login until this is fixed: ") .. text)
        end
        reported_startup = text
        if not list then
            return
        end
        local login = self.adapter.login()
        if not startup.due(hs.settings.get(startup.SETTINGS_KEY), login) then
            return
        end
        hs.settings.set(startup.SETTINGS_KEY, login)
        startup.run(list, self.adapter.uid() or "", function(args, done)
            if not self.adapter.run("/usr/bin/pgrep", args, function(code)
                done(code)
            end) then
                done(-1)
            end
        end, function(command)
            self.adapter.launch({ run = command })
        end, self.adapter.log)
    end
    -- Home's apps (SPEC.md §6.2): the list you set starts once a login, in
    -- the background, before the list, which doesn't wait for them. From
    -- tide's files, an entry that's no Mac app is tide's, and is skipped.
    -- Nothing here may stop tide loading.
    local ok_home, err_home = pcall(function()
        if ws_settings and ws_settings.inApps then
            startup.home_at_login(ws_settings.inApps, hs.settings, self.adapter.login(), function(app)
                return app.bundle ~= nil and self.adapter.bundle_running(app.bundle)
            end, function(app)
                self.adapter.open_in_background(app.path)
            end, self.adapter.log, self.adapter.find_app)
        else
            startup.home_at_login(start_home_apps, hs.settings, self.adapter.login(), self.adapter.app_running,
                self.adapter.open_in_background, self.adapter.log)
        end
    end)
    if not ok_home then
        self.adapter.log("Starting home's apps failed: " .. tostring(err_home))
        self.adapter.notify("Starting home's apps failed: " .. tostring(err_home))
    end
    -- Nothing here may stop tide loading.
    local function run_startup()
        local ok, err = pcall(start_list)
        if not ok then
            self.adapter.log("Start at login failed: " .. tostring(err))
            self.adapter.notify("Start at login failed: " .. tostring(err))
        end
    end
    run_startup()
    -- Cmd+M in the switcher (launcher_hs.lua): mute `entry`, or unmute it,
    -- named `name` in the notice. After a mute, a click on the notice opens
    -- Notifications settings, since macOS's banners are its own. Returns
    -- whether it's now muted, or nil if it couldn't be saved.
    self.toggle_mute = function(entry, name)
        local now, err = mute.toggle(self.clock_dir, entry, self.adapter.read, self.adapter.decode,
            function(v)
                return hs.json.encode(v, true)
            end, self.adapter.write_file)
        if now == nil then
            self.adapter.notify("Couldn't change what's muted: " .. tostring(err))
            return nil
        end
        -- At once, rather than when the folder's watcher fires.
        load_muted()
        local open_settings = now and function()
            self.adapter.open_url(mute.NOTIFICATIONS_URL)
        end or nil
        self.adapter.notify(mute.notice(name or entry, now), open_settings, { withdrawAfter = 10 })
        if self.settings then
            self.settings.refresh()
        end
        return now
    end
    -- A layouts file that's wrong is said once, naming it, and the last
    -- good settings stay.
    local reported_layouts
    local function report_layouts(errors)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported_layouts then
            self.adapter.notify("The layouts stay as they were: " .. text)
        end
        reported_layouts = text
    end
    local function load_layouts()
        local c, errors = layout.load_settings(self.clock_dir, self.adapter.read, self.adapter.decode, layout_base, self.wm.layout)
        report_layouts(errors)
        self.wm:set_layout(c)
        self.layout_files = dashboard.layout_files(self.clock_dir, self.adapter.read)
    end
    report_layouts(layout_errors)
    self.layout_files = dashboard.layout_files(self.clock_dir, self.adapter.read)
    self.input_files = dashboard.input_files(self.clock_dir, self.adapter.read)
    -- A new copy of tide, from make install or setup, reloads it.
    local own_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")
    if own_dir then
        self.own_watch = adapter_mod.watch_folder(own_dir, selfreload.new(self.adapter.after, hs.reload, self.adapter.log))
    end
    self.clock_watch = adapter_mod.watch_folder(self.clock_dir, function()
        load_layouts()
        self.floating.load()
        load_patterns()
        load_muted()
        load_workspaces()
        run_startup()
        self.clock_files = dashboard.clock_files(self.clock_dir, self.adapter.read)
        self.startup_files = dashboard.startup_files(self.clock_dir, self.adapter.read)
        self.input_files = dashboard.input_files(self.clock_dir, self.adapter.read)
        self.appearance_files = dashboard.appearance_files(self.clock_dir, self.adapter.read)
        if self.wallpaper then
            self.wallpaper.apply()
        end
        if self.dim then
            self.dim.load()
            self.dim.update()
        end
        if self.theme then
            self.theme.apply()
        end
        self.idle_files = dashboard.idle_files(self.clock_dir, self.adapter.read)
        if self.idle then
            self.idle.reload()
        end
        self.notification_files = dashboard.notification_files(self.clock_dir, self.adapter.read)
        if self.dnd_schedule then
            self.dnd_schedule.look()
        end
        if self.set_mouse then
            self.set_mouse("folder")
        end
        -- Made after this watcher, with the picker.
        if self.load_clipboard then
            self.load_clipboard()
        end
        if self.bar then
            self.bar.update()
        end
        if self.dashboard then
            self.dashboard.refresh()
        end
        self.settings.refresh()
    end)
    -- The desktop picture from tide's wallpapers, light and dark
    -- (SPEC.md §10), and the files the settings window sets them in.
    self.appearance_files = dashboard.appearance_files(self.clock_dir, self.adapter.read)
    self.wallpaper = wallpaper_hs.new(self)
    -- The dim of every window but the focused one, at tide's strength
    -- (SPEC.md §5.6).
    self.dim = dim_hs.new(self)
    -- The input source macOS uses, switched anywhere, for the bar and the
    -- settings window's Keyboard page each to follow.
    local ok_watch, on_input_source = pcall(inputsrc.watch, hs.keycodes, self.adapter.log)
    if ok_watch then
        self.on_input_source = on_input_source
    else
        self.adapter.log("couldn't watch the input source: " .. tostring(on_input_source))
    end
    self.settings = settings_hs.new(self)
    -- Light or dark on tide's schedule, once a mode's set in its files.
    self.theme = theme_hs.new(self)
    -- tide's idle timeline, once its files set any of it.
    self.idle_files = dashboard.idle_files(self.clock_dir, self.adapter.read)
    self.idle = idle_hs.new(self)
    self.notification_files = dashboard.notification_files(self.clock_dir, self.adapter.read)
    self.wm.open_settings = function(section)
        self.settings.show(section)
    end
    -- Screenshots: macOS saves each to Screenshot's folder, and tide puts
    -- it on the clipboard too, as tide does both (SPEC.md §10). The folder
    -- is followed when Screenshot's options change.
    self.shots = shots.follow(function(dir, on_paths)
        return adapter_mod.screenshots(dir, on_paths, self.adapter.log)
    end, self.adapter.is_shot, self.adapter.copy_image)
    self.shots.folder(adapter_mod.screenshot_folder())
    self.shot_options = adapter_mod.screenshot_options(function()
        self.shots.folder(adapter_mod.screenshot_folder())
    end)
    -- The name prompt, for a window opening on "in" and for launches from
    -- it (SPEC.md §6.2). Windows found at start don't ask.
    self.prompt = prompt_hs.new(self)
    self.wm.ask_name = function(id)
        self.prompt.window(id)
    end
    self.wm.ask_launch = function(default, done)
        self.prompt.launch(default, done)
    end
    self.wm.ask_move = function(done)
        self.prompt.choose(done)
    end
    self.wm.ask_go = function(done)
        self.prompt.go(done)
    end
    self.wm.ready = true
    -- Keep awake and presenter mode (SPEC.md §10): Super+S and Super+P, the
    -- launcher and the bar, with the bar on or off.
    self.presenter = presenter_hs.new(self.adapter.run, self.adapter.log, self.adapter.notify, function()
        if self.bar then
            self.bar.refresh()
        end
    end)
    -- Do Not Disturb on tide's schedule, through presenter mode's shortcuts;
    -- one you set yourself, it leaves.
    self.dnd_schedule = dndsched_hs.new(self)
    self.presenter.on_own_dnd = function()
        self.dnd_schedule.own_changed()
    end
    self.presenter.check()
    self.wm.toggle_keep_awake = self.presenter.toggle_keep_awake
    self.wm.toggle_presenter = self.presenter.toggle_presenter
    self.launcher = require(launcher_module).new(self)
    self.wm.open_launcher = function(tab)
        self.launcher.show(tab)
    end
    -- The settings window's choice of launcher, kept on this Mac and taken
    -- at once: the one in use goes, closed if it's open, and the other
    -- takes the keys and the bar's logo. Returns true, or nil and why.
    function self.set_launcher(value)
        if not launcherpage.MODULE[value] then
            return nil, "there's no launcher " .. tostring(value)
        end
        if value ~= self.launcher_choice then
            local ok, made = pcall(function()
                return require(launcherpage.MODULE[value]).new(self)
            end)
            if not ok then
                return nil, tostring(made)
            end
            local old = self.launcher
            self.launcher = made
            self.launcher_choice = value
            if old and old.delete then
                old.delete()
            end
        end
        hs.settings.set(launcherpage.SETTINGS_KEY, value)
        return true
    end
    self.dashboard = dashboard_hs.new(self)
    self.wm.open_dashboard = function()
        self.dashboard.show()
    end
    -- Ctrl+Up and Ctrl+Down: the overview, in place of Mission Control
    -- and App Exposé (SPEC.md §6.9).
    self.overview = overview_hs.new(self)
    self.wm.open_overview = function(scope)
        self.overview.show(scope)
    end
    -- Super+V's picker, whose watcher keeps what you copy from now on.
    self.picker = picker_hs.new(self)
    -- What was copied in the last week, kept on disk, encrypted with a key
    -- in the login keychain (SPEC.md §9.1). A failure is said once, until a
    -- save works.
    self.clip_store = clipstore.new(current.dir(os.getenv("HOME") or ""), adapter_mod.current_fs,
        hs.json.encode, self.adapter.decode, clipcrypt.new(io.popen), os.time)
    local clip_save_error
    local function saved(ok, err)
        if ok then
            clip_save_error = nil
        elseif err ~= clip_save_error then
            clip_save_error = err
            self.adapter.log("clipboard history: couldn't save: " .. tostring(err))
            self.adapter.notify("Couldn't save the clipboard history: " .. tostring(err))
        end
    end
    self.save_clipboard = function()
        self.clip_store.changed(self.picker.history, saved)
    end
    self.clipboard_cleared = function()
        self.clip_store.cleared(self.picker.history, saved)
    end
    -- A copy a week old goes, whether or not anything else is copied.
    self.clip_expiry = hs.timer.doEvery(3600, function()
        if self.clip_store.expire(self.picker.history) then
            self.on_clipboard()
        end
    end)
    self.wm.open_picker = function(tab)
        self.picker.show(tab)
    end
    -- tide's Clipboard settings, from the same folder (SPEC.md §9.1, §15):
    -- the history on or off, and how many it keeps. A file that's wrong is
    -- said once, naming it, and the last good settings stay.
    local reported_clipboard
    local function load_clipboard()
        local s, errors = picker.load_settings(self.clock_dir, self.adapter.read, self.adapter.decode, self.clipboard_settings)
        self.clipboard_settings = s
        -- The first time, what was saved comes back, under this cap; after,
        -- a smaller cap trims what's saved too.
        self.clip_store.configure(self.picker.history, s, function(load_error)
            if load_error then
                self.adapter.log("clipboard history: " .. load_error)
                self.adapter.notify("The clipboard history from before couldn't be read: " .. load_error)
            end
            -- What came back shows in the settings window's count.
            self.settings.clipboard_changed()
        end, saved)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported_clipboard then
            self.adapter.notify("The clipboard settings stay as they were: " .. text)
        end
        reported_clipboard = text
        self.clipboard_files = dashboard.clipboard_files(self.clock_dir, self.adapter.read)
    end
    self.load_clipboard = load_clipboard
    -- A copy kept or forgotten: the settings window's Clipboard count.
    self.on_clipboard = function()
        self.save_clipboard()
        self.settings.clipboard_changed()
    end
    load_clipboard()
    -- Without Karabiner's tap rule, tide watches for a lone Super tap
    -- itself: the launcher, as Super+Space opens it (SPEC.md §7.2).
    self.tap = tap_mod.new(function()
        if not self.karabiner then
            self.launcher.show("launch")
        end
    end)
    self.tap_watch = adapter_mod.taps(function(flags)
        local none = not (flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn)
        self.tap:flags(not none and keys.super_alone(self.super, flags), none, hs.timer.secondsSinceEpoch())
        -- Cmd+Tab switches apps when Command goes up (SPEC.md §14.1).
        self.wm:modifiers(flags.cmd or false)
    end, function(kind, key, flags)
        self.tap:other()
        if kind == "key" then
            self.wm:key_down(key, flags.cmd or false)
        end
    end)
    -- A three-finger swipe steps through workspaces, as tide's does
    -- (SPEC.md §7.2). setup-macos turns macOS's own swipe between Spaces
    -- off, so the two don't both act.
    if config.swipe ~= false then
        self.swipe = swipe_mod.for_wm(self.wm)
        self.swipe_watch = adapter_mod.gestures(function(list, dragging)
            self.swipe:touches(list, dragging)
        end)
    end
    -- Caps Lock as Compose, as on Linux (SPEC.md §10): setup-macos makes
    -- it send F18.
    if config.compose ~= false then
        self.compose = compose_hs.new(hs, self.adapter.log)
    end
    -- The current workspace's name, for scripts, written whenever it
    -- changes (SPEC.md §6.3). A failure is said once, until a write works.
    self.workspace_file = current.new(current.dir(os.getenv("HOME") or ""), adapter_mod.current_fs,
        self.adapter.javascript)
    local file_error
    self.publish_workspace = function()
        local ok, err = self.workspace_file.write(self.wm:current_ws())
        if ok then
            file_error = nil
        elseif err ~= file_error then
            file_error = err
            self.adapter.notify("Couldn't write the workspace's name for scripts: " .. tostring(err))
        end
    end
    -- The tray of windows you minimized, in each display's corner, with the
    -- bar on or off (SPEC.md §6.7).
    self.tray = tray_hs.new(self)
    -- The workspaces, in the bar or else in the menu bar, and the name
    -- shown on each switch (SPEC.md §8).
    if config.bar ~= false then
        self.bar = bar_hs.new(self)
        self.wm.on_change = function()
            self.bar.update()
            self.tray.update()
            self.dim.update()
            self.publish_workspace()
        end
    else
        self.menubar = hs.menubar.new()
        -- tide's logo before the workspaces, tinted by macOS to suit the
        -- menu bar, and tide as its tooltip.
        local logo = self.adapter.logo(brand.TEMPLATE)
        if logo then
            self.menubar:setIcon(logo, true)
        end
        self.menubar:setTooltip(brand.NAME)
        self.wm.on_change = function()
            if self.menubar then
                self.menubar:setTitle(bar.title(self.wm:bar_state()))
            end
            self.tray.update()
            self.dim.update()
            self.publish_workspace()
        end
        self.menubar:setMenu(function()
            local items = {}
            for _, n in ipairs((self.wm:listed())) do
                items[#items + 1] = {
                    title = n,
                    fn = function()
                        self.wm:act("show", n)
                    end,
                }
            end
            return items
        end)
    end
    -- Super+Shift+M, with the bar on or off.
    self.wm.toggle_mic = function()
        bar_hs.toggle_mic(self.adapter.log)
        if self.bar then
            self.bar.refresh()
        end
    end
    self.wm.on_show = function(n, uuid)
        namealert.show(hs, n, uuid)
    end
    self.wm:changed()
    self.attention_timer = hs.timer.doEvery(M.ATTENTION_POLL, function()
        self.wm:poll_attention()
        -- A title can change without focus moving; the bar sends only what
        -- changed.
        if self.bar then
            self.bar.update()
        end
    end)
    -- conf's Karabiner rules, switched by the settings window's Keyboard
    -- section; checked before Karabiner is, so tide's own rule is up to
    -- date when it's looked at.
    local karabiner_source = self.adapter.read(karabiner.SOURCE_PATH)
    if karabiner_source then
        self.karabiner_rules = karabiner.new({
            home = os.getenv("HOME") or "",
            source = karabiner_source,
            read = self.adapter.read,
            list = self.adapter.list_dir,
            run_js = self.adapter.javascript,
            decode = self.adapter.decode,
            write = self.adapter.write_file,
            resolve = self.adapter.resolve,
            running = function()
                return self.adapter.running("Karabiner-Core-Service") or self.adapter.running("karabiner_grabber")
            end,
            get = function(k)
                return hs.settings.get(k)
            end,
            set = function(k, v)
                hs.settings.set(k, v)
            end,
            notify = self.adapter.notify,
            log = self.adapter.log,
        })
    else
        local why = "Couldn't read " .. karabiner.SOURCE_PATH .. ", so tide can't switch Karabiner's rules: install tide again"
        self.adapter.log(why)
        self.adapter.notify(why)
    end
    -- tide's Mouse settings, applied to LinearMouse (SPEC.md §10).
    local sources, missing = {}, nil
    for _, name in ipairs(linearmouse.MODULES) do
        sources[name] = self.adapter.read(linearmouse.DIR .. name)
        if not sources[name] then
            missing = missing or (linearmouse.DIR .. name)
        end
    end
    if missing then
        local why = "Couldn't read " .. missing .. ", so tide can't set LinearMouse's scrolling: install tide again"
        self.adapter.log(why)
        self.adapter.notify(why)
    else
        self.linearmouse_settings = linearmouse.new({
            home = os.getenv("HOME") or "",
            dir = self.clock_dir,
            sources = sources,
            read = self.adapter.read,
            exists = self.adapter.exists,
            resolve = self.adapter.resolve,
            write = self.adapter.write_file,
            run_js = self.adapter.javascript,
            decode = self.adapter.decode,
            natural = function(done)
                self.adapter.read_natural(function(code, out)
                    done(linearmouse.natural_from(code, out))
                end)
            end,
            installed = function()
                return self.adapter.app_installed(linearmouse.BUNDLE)
            end,
            running = function()
                return self.adapter.bundle_running(linearmouse.BUNDLE)
            end,
            start = function(done)
                self.adapter.open_bundle_in_background(linearmouse.BUNDLE, done)
            end,
            notify = self.adapter.notify,
            log = self.adapter.log,
        })
        self.linearmouse_settings.on_started = function()
            check_linearmouse(self)
        end
    end
    -- Nothing here may stop tide loading, or its checks running.
    self.set_mouse = function(why)
        if not self.linearmouse_settings then
            return
        end
        local ok, err = pcall(self.linearmouse_settings.apply, why, function(state)
            -- Only when what the Mouse section shows changed, its pointer
            -- included, so an open window isn't redrawn every 30 s.
            local shown = linearmouse.shown(state)
            if shown ~= self.mouse_said then
                self.mouse_said = shown
                if self.settings then
                    self.settings.refresh()
                end
            end
        end)
        if not ok then
            self.adapter.log("tide's Mouse settings: " .. tostring(err))
        end
    end
    self.set_mouse("event")
    check_karabiner_rules(self)
    choose_super(self, true)
    check_linearmouse(self)
    if self.bar and self.adapter.hides_menu_bar and self.adapter.hides_menu_bar() then
        self.adapter.notify(checklist.MENU_BAR_NOTICE)
    end
    self.karabiner_timer = hs.timer.doEvery(M.KARABINER_CHECK, function()
        check_karabiner_rules(self)
        choose_super(self, false)
        self.set_mouse("check")
        check_linearmouse(self)
    end)
    -- A device plugged in, a KVM switched back, a wake or an unlock: the
    -- mouse set again, LinearMouse started if it isn't running, and
    -- Karabiner's rules checked, a second after the last of a burst.
    self.plug_watch = adapter_mod.plugs_and_wakes(linearmouse.debounce(self.adapter.after, M.PLUG_DELAY, function()
        self.set_mouse("event")
        check_karabiner_rules(self)
        choose_super(self, false)
        check_linearmouse(self)
    end))
    return self
end

-- The current workspace's TIDE_WORKSPACE, as the file holds it: "" and why
-- when its letters and digits can't be found.
function M.workspace()
    return names.sanitize(M.wm:current_ws(), M.adapter.javascript)
end

function M.toggle_focus_follows_mouse()
    local on = M.wm.ffm:toggle()
    M.adapter.notify("Focus follows mouse " .. (on and "on" or "off"))
    return on
end

return M
