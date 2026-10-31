local t = require("t")
local layout = require("tilemo.layout")

local HD = { x = 0, y = 25, w = 1920, h = 1055 }
local UW = { x = 0, y = 25, w = 3440, h = 1415 }

t.test("a workspace starts in tile, or threecol on an ultrawide", function()
    t.eq(layout.new(1, HD).mode, "tile")
    t.eq(layout.new(1, UW).mode, "threecol")
end)

t.test("new windows join the end of the stack by default", function()
    local ws = layout.new(1, HD)
    layout.insert(ws, 1)
    layout.insert(ws, 2)
    layout.insert(ws, 3)
    t.eq(ws.order, { 1, 2, 3 })
end)

t.test("new_window places a window at the top, after the focused one, or as master", function()
    local function with(where, focused)
        local cfg = layout.copy(layout.defaults)
        cfg.new_window = where
        local ws = layout.new(1, HD, cfg)
        ws.order = { 1, 2, 3 }
        layout.insert(ws, 9, focused, cfg)
        return ws.order
    end
    t.eq(with("top"), { 1, 9, 2, 3 }, "top")
    t.eq(with("next", 2), { 1, 2, 9, 3 }, "next")
    t.eq(with("master"), { 9, 1, 2, 3 }, "master")
end)

t.test("inserting a window twice keeps one copy", function()
    local ws = layout.new(1, HD)
    layout.insert(ws, 1)
    layout.insert(ws, 1)
    t.eq(ws.order, { 1 })
end)

t.test("neighbor wraps both ways", function()
    t.eq(layout.neighbor({ 1, 2, 3 }, 3, 1), 1)
    t.eq(layout.neighbor({ 1, 2, 3 }, 1, -1), 3)
    t.eq(layout.neighbor({ 1, 2, 3 }, 7, 1), 1, "unknown window starts at the master")
    t.eq(layout.neighbor({}, 1, 1), nil)
end)

t.test("move swaps with the neighbor in the visible order", function()
    local ws = layout.new(1, HD)
    ws.order = { 1, 2, 3, 4 }
    -- 3 is minimized, so moving 2 down passes it.
    layout.move(ws, { 1, 2, 4 }, 2, 1)
    t.eq(ws.order, { 1, 4, 3, 2 })
end)

t.test("swap_master: others swap with the master, and the master with the one before it", function()
    local ws = layout.new(1, HD)
    ws.order = { 1, 2, 3 }
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 3, 2, 1 })
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 1, 2, 3 }, "back with 1, the master before it, not 2")
    layout.swap_master(ws, ws.order, 1)
    t.eq(ws.order, { 3, 2, 1 }, "and again")
    -- With the master before gone, the next, as dwm's zoom.
    ws.prev_master = 9
    layout.swap_master(ws, ws.order, 3)
    t.eq(ws.order, { 2, 3, 1 })
end)

t.test("mfact stays between 0.1 and 0.9", function()
    local ws = layout.new(1, HD)
    for _ = 1, 40 do
        layout.mfact(ws, 0.025)
    end
    t.eq(ws.opts.tile.mfact, 0.9)
end)

t.test("nmaster never drops below one", function()
    local ws = layout.new(1, HD)
    layout.nmaster(ws, -5)
    t.eq(ws.opts.tile.nmaster, 1)
end)

t.test("cycle steps through tile, threecol and twocol", function()
    local ws = layout.new(1, HD)
    layout.cycle(ws, 1)
    t.eq(ws.mode, "threecol")
    layout.cycle(ws, 1)
    t.eq(ws.mode, "twocol")
    layout.cycle(ws, 1)
    t.eq(ws.mode, "tile")
    layout.cycle(ws, -1)
    t.eq(ws.mode, "twocol")
end)

t.test("monocle toggles back to the mode before it", function()
    local ws = layout.new(1, UW)
    layout.toggle_monocle(ws)
    t.eq(ws.mode, "monocle")
    layout.toggle_monocle(ws)
    t.eq(ws.mode, "threecol")
end)

t.test("arrange keys tide's boxes by window", function()
    local ws = layout.new(1, HD)
    local boxes = layout.arrange(ws, HD, { 7, 8 })
    t.eq(boxes[7], { x = 0, y = 25, w = 1056, h = 1055 })
    t.eq(boxes[8], { x = 1056, y = 25, w = 864, h = 1055 })
end)

t.test("a lone window on an ultrawide is centered at 80%", function()
    local ws = layout.new(1, UW)
    local b = layout.arrange(ws, UW, { 7 })[7]
    t.eq(b.w, 2752)
    t.eq(b.x, 344)
end)

-- tide's layouts files, as hs.json would decode them.
local DECODED = {
    ['{"modes": {"tile": {"mfact": 0.6}}}'] = { modes = { tile = { mfact = 0.6 } } },
    ['{"newWindow": "top", "ultrawideAspect": 2.4}'] = { newWindow = "top", ultrawideAspect = 2.4 },
    ['{"modes": {"tile": {"nmaster": 2}}, "defaultMode": {"ultrawide": "tile"}}'] =
        { modes = { tile = { nmaster = 2 } }, defaultMode = { ultrawide = "tile" } },
    ['{"single": [{"minAspect": 2.5, "width": 0.7}]}'] = { single = { { minAspect = 2.5, width = 0.7 } } },
    ['{"modes": {"tile": {"mfact": 2}}}'] = { modes = { tile = { mfact = 2 } } },
    ['{"modes": {"twocol": {"nmaster": 0}}}'] = { modes = { twocol = { nmaster = 0 } } },
    ['{"newWindow": "left"}'] = { newWindow = "left" },
    ['{"defaultMode": {"normal": "grid"}}'] = { defaultMode = { normal = "grid" } },
    ['{"gaps": 4}'] = { gaps = 4 },
    ['{"single": {"width": 0.5}}'] = { single = { width = 0.5 } },
    ["[]"] = {},
}
local function decode(text)
    return DECODED[text]
end
local function files(shared, localf)
    local by = { ["/c/tide/layouts.json"] = shared, ["/c/tide/layouts.local.json"] = localf }
    return function(path)
        return by[path]
    end
end

t.test("with no layouts files, the settings are tide's defaults", function()
    local c, errors = layout.load_settings("/c/tide", files(nil, nil), decode)
    t.eq(c, layout.defaults)
    t.eq(errors, {})
end)

t.test("tide's layouts files set tilemo's layout, the local file's over the shared one's", function()
    local c = layout.load_settings("/c/tide",
        files('{"modes": {"tile": {"mfact": 0.6}}}', '{"modes": {"tile": {"nmaster": 2}}, "defaultMode": {"ultrawide": "tile"}}'),
        decode)
    t.eq(c.modes.tile, { mfact = 0.6, nmaster = 2 }, "objects merge key by key")
    t.eq(c.modes.threecol, layout.defaults.modes.threecol)
    t.eq(c.default_mode, { normal = "tile", ultrawide = "tile" })
    c = layout.load_settings("/c/tide", files('{"newWindow": "top", "ultrawideAspect": 2.4}', nil), decode)
    t.eq(c.new_window, "top")
    t.eq(c.ultrawide_aspect, 2.4)
    t.eq(c.cycle, layout.defaults.cycle, "what the files can't set stays")
    c = layout.load_settings("/c/tide", files(nil, '{"single": [{"minAspect": 2.5, "width": 0.7}]}'), decode)
    t.eq(c.single, { { min_aspect = 2.5, width = 0.7 } }, "a list is set whole")
end)

t.test("the files lay over start()'s layout, which stays tilemo's own base", function()
    local base = layout.copy(layout.defaults)
    base.mfact_step = 0.05
    local c = layout.load_settings("/c/tide", files('{"modes": {"tile": {"mfact": 0.6}}}', nil), decode, base)
    t.eq(c.mfact_step, 0.05)
    t.eq(c.modes.tile.mfact, 0.6)
    t.eq(base.modes.tile.mfact, 0.55, "the base isn't changed")
end)

t.test("a layouts file that's wrong keeps the last good settings, naming the file and why", function()
    local last = layout.copy(layout.defaults)
    last.new_window = "next"
    for text, why in pairs({
        ['{"modes": {"tile": {"mfact": 2}}}'] = "modes.tile.mfact must be a number from 0.1 to 0.9",
        ['{"modes": {"twocol": {"nmaster": 0}}}'] = "modes.twocol.nmaster must be a whole number from 1 to 100",
        ['{"newWindow": "left"}'] = "newWindow must be one of end, top, next, master",
        ['{"defaultMode": {"normal": "grid"}}'] = "defaultMode.normal must be one of",
        ['{"gaps": 4}'] = 'unknown setting "gaps"',
        ['{"single": {"width": 0.5}}'] = "single must be a list of {minAspect, width}",
        ["[]"] = "expected an object of settings",
        ["{"] = "doesn't parse",
    }) do
        local c, errors = layout.load_settings("/c/tide", files('{"modes": {"tile": {"mfact": 0.6}}}', text), decode, nil, last)
        t.eq(c, last, text)
        t.eq(#errors, 1, text)
        t.eq(errors[1]:find("layouts.local.json: ", 1, true) == 1, true, errors[1])
        t.eq(errors[1]:find(why, 1, true) ~= nil, true, errors[1])
    end
    local c = layout.load_settings("/c/tide", files(nil, "{"), decode)
    t.eq(c, layout.defaults, "with nothing good yet, the defaults")
end)

t.test("new settings keep a workspace's mode and reset what the keys set", function()
    local ws = layout.new(1, HD)
    layout.cycle(ws, 1)
    layout.mfact(ws, 0.1)
    local mode = ws.mode
    local c = layout.copy(layout.defaults)
    c.modes.threecol.mfact = 0.4
    layout.reconfigure(ws, c)
    t.eq(ws.mode, mode)
    t.eq(ws.opts.threecol.mfact, 0.4)
    t.eq(ws.opts.tile.mfact, 0.55)
end)

t.test("the settings page gets the layout in tide's files' names", function()
    local f = layout.file_form(layout.defaults)
    t.eq(f.ultrawideAspect, 2.1)
    t.eq(f.defaultMode, { normal = "tile", ultrawide = "threecol" })
    t.eq(f.modes, { tile = { mfact = 0.55, nmaster = 1 }, threecol = { mfact = 0.5, nmaster = 1 }, twocol = { mfact = 0.72, nmaster = 2 } })
    t.eq(f.single, { { minAspect = 2.1, width = 0.8 }, { minAspect = 3.2, width = 0.6 } })
    t.eq(f.newWindow, "end")
end)

t.done("layout")
