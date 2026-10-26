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
-- tilemo.toggle_focus_follows_mouse() turns focus follows mouse off and on.

local keys = require("tilemo.keys")
local mouse = require("tilemo.mouse")
local wm_mod = require("tilemo.wm")
local adapter_mod = require("tilemo.hs_adapter")
local ffm_mod = require("tilemo.ffm")
local dashboard_hs = require("tilemo.dashboard_hs")
local launcher_hs = require("tilemo.launcher_hs")
local tap_mod = require("tilemo.tap")
local bar = require("tilemo.bar")
local bar_hs = require("tilemo.bar_hs")

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
    -- The workspaces, in the bar or else in the menu bar, and the number
    -- shown on each switch (SPEC.md §8).
    if config.bar ~= false then
        self.bar = bar_hs.new(self)
        self.wm.on_change = function()
            self.bar.update()
        end
    else
        self.menubar = hs.menubar.new()
        self.wm.on_change = function()
            if self.menubar then
                self.menubar:setTitle(bar.title(self.wm:bar_state()))
            end
        end
        self.menubar:setMenu(function()
            local items = {}
            for n = 1, wm_mod.WORKSPACES do
                items[#items + 1] = {
                    title = "Workspace " .. n,
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
        hs.alert.show(tostring(n), { textSize = 96, radius = 24 }, hs.screen.find(uuid) or hs.screen.mainScreen(), 0.5)
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

function M.toggle_focus_follows_mouse()
    local on = M.wm.ffm:toggle()
    M.adapter.notify("Focus follows mouse " .. (on and "on" or "off"))
    return on
end

return M
