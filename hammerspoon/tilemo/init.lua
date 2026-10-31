-- tilemo on Hammerspoon. From ~/.hammerspoon/init.lua:
--
--   tilemo = require("tilemo")
--   tilemo.start({})
--
-- start() takes { layout = ..., rules = {...}, focus_follows_mouse = true,
-- keep_focus = {...}, bar = true }: `layout` overrides tilemo/layout.lua's
-- defaults whole, `rules` are float rules that come before the built-in
-- ones (tilemo/rules.lua), and `keep_focus` names more apps, by bundle ID,
-- that keep focus while they're in front. `bar = false` leaves out the bar
-- along the top and shows the workspaces in the menu bar instead.
-- `workspaces` names the standing workspaces, always listed and never
-- removed, the first being home (SPEC.md §6.1); it defaults to
-- wm.STANDING, home being "in". `home_apps` names the apps, by app name,
-- whose windows always open on home (SPEC.md §6.2); it defaults to
-- wm.HOME_APPS.
-- tilemo.toggle_focus_follows_mouse() turns focus follows mouse off and on.
-- tilemo.workspace() gives the current workspace's TIDE_WORKSPACE. Scripts
-- read it from ~/Library/Caches/tilemo/workspace instead (SPEC.md §6.3):
-- tilemo never loads hs.ipc, whose port runs any Lua a local process sends.

local keys = require("tilemo.keys")
local mouse = require("tilemo.mouse")
local wm_mod = require("tilemo.wm")
local adapter_mod = require("tilemo.hs_adapter")
local ffm_mod = require("tilemo.ffm")
local dashboard_hs = require("tilemo.dashboard_hs")
local launcher_hs = require("tilemo.launcher_hs")
local settings_hs = require("tilemo.settings_hs")
local dashboard = require("tilemo.dashboard")
local shots = require("tilemo.shots")
local tap_mod = require("tilemo.tap")
local bar = require("tilemo.bar")
local bar_hs = require("tilemo.bar_hs")
local names = require("tilemo.names")
local current = require("tilemo.current")
local prompt_hs = require("tilemo.prompt_hs")

local M = {}

-- How often to look for Karabiner starting or stopping, so the keys move
-- with it without a restart (SPEC.md §7.1).
M.KARABINER_CHECK = 30
-- How often to read Dock badges and window titles for attention.
M.ATTENTION_POLL = 2

local function bind_all(self)
    for _, h in ipairs(self.hotkeys or {}) do
        h:delete()
    end
    self.hotkeys = {}
    local function bind(mods, b)
        local fn = function()
            self.wm:act(b.action, b.arg)
        end
        -- One bad or taken key mustn't stop the rest binding.
        local ok, h = pcall(hs.hotkey.bind, mods, b.key, fn, nil, b.repeating and fn or nil)
        if ok and h then
            self.hotkeys[#self.hotkeys + 1] = h
        else
            self.adapter.log("couldn't bind " .. table.concat(mods, "+") .. "+" .. b.key)
        end
    end
    local list, skipped = keys.bindings(self.super)
    for _, b in ipairs(list) do
        bind(b.mods, b)
    end
    for _, chord in ipairs(skipped) do
        self.adapter.log("left out " .. chord .. ": another key has it")
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

local function choose_super(self, announce)
    local super, karabiner = keys.super(self.adapter.read, self.adapter.running, os.getenv("HOME") or "",
        self.adapter.decode)
    if self.karabiner == karabiner then
        return
    end
    self.karabiner = karabiner
    self.super = super
    bind_all(self)
    if not karabiner and announce then
        self.adapter.notify(keys.FALLBACK_NOTICE)
    end
end

function M.start(config)
    local self = M
    hs.window.animationDuration = 0
    self.adapter = adapter_mod.new()
    config = config or {}
    config.saved = adapter_mod.load()
    -- The tiling area starts below the bar.
    config.top = config.bar ~= false and bar.HEIGHT or 0
    self.wm = wm_mod.new(self.adapter, config)
    self.wm.ffm = ffm_mod.new(self.wm, self.adapter, {
        enabled = config.focus_follows_mouse ~= false,
        keep_focus = config.keep_focus,
        super_held = function()
            return keys.super_held(self.super, hs.eventtap.checkKeyboardModifiers())
        end,
    })
    self.wm:sync()
    self.wm:reconcile()
    self.wm:retile()
    self.watchers = adapter_mod.watch(function()
        self.wm:schedule()
    end, function(id)
        self.wm:focused(id)
    end, function(id)
        self.wm:moved(id)
    end, function(id)
        self.wm:minimized(id)
    end, function(id)
        self.wm:unminimized(id)
    end)
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
    end)
    -- The clocks are tide's, from its settings folder, read again whenever
    -- anything there changes (SPEC.md §15). The pages say when a file is
    -- wrong; each distinct complaint is a notification once.
    self.clock_dir = dashboard.clock_dir(os.getenv)
    self.clock_files = dashboard.clock_files(self.clock_dir, self.adapter.read)
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
    -- (SPEC.md §6.2, §15), checked when tilemo starts and whenever the
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
    self.clock_watch = adapter_mod.watch_folder(self.clock_dir, function()
        load_patterns()
        self.clock_files = dashboard.clock_files(self.clock_dir, self.adapter.read)
        if self.bar then
            self.bar.update()
        end
        if self.dashboard then
            self.dashboard.refresh()
        end
        self.settings.refresh()
    end)
    self.settings = settings_hs.new(self)
    self.wm.open_settings = function()
        self.settings.show()
    end
    -- Screenshots: macOS saves each to Screenshot's folder, and tilemo puts
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
    self.wm.ready = true
    self.launcher = launcher_hs.new(self)
    self.wm.open_launcher = function()
        self.launcher.show()
    end
    self.dashboard = dashboard_hs.new(self)
    self.wm.open_dashboard = function()
        self.dashboard.show()
    end
    -- Without Karabiner's tap rule, tilemo watches for a lone Super tap itself.
    self.tap = tap_mod.new(function()
        if not self.karabiner then
            self.launcher.show()
        end
    end)
    self.tap_watch = adapter_mod.taps(function(flags)
        local none = not (flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn)
        self.tap:flags(not none and keys.super_alone(self.super, flags), none, hs.timer.secondsSinceEpoch())
        -- Cmd+Tab switches apps when Command goes up (SPEC.md §14.1).
        self.wm:modifiers(flags.cmd or false)
        -- Letting Super go ends a round of Super+Tab.
        if not keys.is_super(self.super, flags) then
            self.wm:end_round()
        end
    end, function(kind, key, flags)
        self.tap:other()
        if kind == "key" then
            self.wm:key_down(key, flags.cmd or false)
        end
    end)
    -- The current workspace's name, for scripts, written whenever it
    -- changes (SPEC.md §6.3). A failure is said once, until a write works.
    self.workspace_file = current.new(current.dir(os.getenv("HOME") or ""), adapter_mod.current_fs)
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
    -- The workspaces, in the bar or else in the menu bar, and the name
    -- shown on each switch (SPEC.md §8).
    if config.bar ~= false then
        self.bar = bar_hs.new(self)
        self.wm.on_change = function()
            self.bar.update()
            self.publish_workspace()
        end
    else
        self.menubar = hs.menubar.new()
        self.wm.on_change = function()
            if self.menubar then
                self.menubar:setTitle(bar.title(self.wm:bar_state()))
            end
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
        hs.alert.closeAll(0)
        hs.alert.show(n, { textSize = 96, radius = 24 }, hs.screen.find(uuid) or hs.screen.mainScreen(), 0.5)
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
    choose_super(self, true)
    self.karabiner_timer = hs.timer.doEvery(M.KARABINER_CHECK, function()
        choose_super(self, false)
    end)
    return self
end

-- The current workspace's TIDE_WORKSPACE, as the file holds it.
function M.workspace()
    return names.sanitize(M.wm:current_ws())
end

function M.toggle_focus_follows_mouse()
    local on = M.wm.ffm:toggle()
    M.adapter.notify("Focus follows mouse " .. (on and "on" or "off"))
    return on
end

return M
