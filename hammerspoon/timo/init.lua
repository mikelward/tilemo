-- timo on Hammerspoon. From ~/.hammerspoon/init.lua:
--
--   timo = require("timo")
--   timo.start({})
--
-- start() takes { layout = ..., rules = {...} }: `layout` overrides
-- timo/layout.lua's defaults whole, and `rules` are float rules that come
-- before the built-in ones (timo/rules.lua).

local keys = require("timo.keys")
local wm_mod = require("timo.wm")
local adapter_mod = require("timo.hs_adapter")

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
    self.wm = wm_mod.new(self.adapter, config)
    self.wm:sync()
    self.wm:retile()
    self.watchers = adapter_mod.watch(function()
        self.wm:schedule()
    end, function(id)
        self.wm:focused(id)
    end)
    choose_super(self, true)
    self.karabiner_timer = hs.timer.doEvery(M.KARABINER_CHECK, function()
        choose_super(self, false)
    end)
    return self
end

return M
