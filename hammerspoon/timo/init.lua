-- timo on Hammerspoon. From ~/.hammerspoon/init.lua:
--
--   timo = require("timo")
--   timo.start({})
--
-- start() takes { layout = ..., rules = {...}, focus_follows_mouse = true,
-- keep_focus = {...} }: `layout` overrides timo/layout.lua's defaults whole,
-- `rules` are float rules that come before the built-in ones
-- (timo/rules.lua), and `keep_focus` names more apps, by bundle ID, that
-- keep focus while they're in front. timo.toggle_focus_follows_mouse()
-- turns it off and on.

local keys = require("timo.keys")
local mouse = require("timo.mouse")
local wm_mod = require("timo.wm")
local adapter_mod = require("timo.hs_adapter")
local ffm_mod = require("timo.ffm")
local launcher_hs = require("timo.launcher_hs")
local tap_mod = require("timo.tap")

local M = {}

-- How often to look for Karabiner starting or stopping, so the keys move
-- with it without a restart (SPEC.md §7.1).
M.KARABINER_CHECK = 30

local function bind_all(self)
    for _, h in ipairs(self.hotkeys or {}) do
        h:delete()
    end
    self.hotkeys = {}
    for _, b in ipairs(keys.map) do
        local fn = function()
            self.wm:act(b.action, b.arg)
        end
        -- One bad or taken key mustn't stop the rest binding.
        local ok, h = pcall(hs.hotkey.bind, keys.mods(self.super, b), b.key, fn, nil, b.repeating and fn or nil)
        if ok and h then
            self.hotkeys[#self.hotkeys + 1] = h
        else
            self.adapter.log("couldn't bind " .. table.concat(keys.mods(self.super, b), "+") .. "+" .. b.key)
        end
    end
end

local function resize_mode(self)
    local modal = hs.hotkey.modal.new()
    -- The float being resized keeps focus while the mode is on.
    function modal.entered()
        self.wm.holding_keyboard = true
    end
    function modal.exited()
        self.wm.holding_keyboard = false
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
    -- Without Karabiner's tap rule, timo watches for a lone Super tap itself.
    self.tap = tap_mod.new(function()
        if not self.karabiner then
            self.launcher.show()
        end
    end)
    self.tap_watch = adapter_mod.taps(function(flags)
        local none = not (flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn)
        self.tap:flags(not none and keys.super_alone(self.super, flags), none, hs.timer.secondsSinceEpoch())
    end, function()
        self.tap:other()
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
