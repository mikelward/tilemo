-- The dim (dim.lua, SPEC.md §5.6): its strength from tide's appearance
-- files, what the window manager says is to be dimmed, and what each
-- display's layer draws.

local t = require("t")
local dim = require("tide.dim")
local json = require("json")
local fake = require("fake")
local wm_mod = require("tide.wm")

local function setup(n)
    local a = fake.new()
    for i = 1, n do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    return a, wm
end

t.test("the strength is tide's 0.12 until a file sets it, the local file's over the shared one's", function()
    t.eq({ dim.load(nil, nil, json.decode) }, { 0.12, {} })
    t.eq({ dim.load('{"dimStrength": 0.2}', nil, json.decode) }, { 0.2, {} })
    t.eq({ dim.load('{"dimStrength": 0.2}', '{"dimStrength": 0}', json.decode) }, { 0, {} })
end)

t.test("a bad strength is said, and the one before it stands", function()
    local s, errors = dim.load('{"dimStrength": 0.1}', '{"dimStrength": 2}', json.decode)
    t.eq(s, 0.1)
    t.eq(errors, { "appearance.local.json: dimStrength must be a number from 0 to 1" })
    s, errors = dim.load("{", '{"dimStrength": "a lot"}', json.decode)
    t.eq(s, 0.12)
    t.eq(errors, { "appearance.json isn't a JSON object", "appearance.local.json: dimStrength must be a number from 0 to 1" })
end)

t.test("the focused tile is the hole, and nothing is in front of it", function()
    local a, wm = setup(2)
    a.focus(1)
    wm:focused(1)
    t.eq(wm:dim_scene(), { focused = a.wins[1].frame, above = {} })
end)

t.test("a lone window, a full-screen one or none focused isn't dimmed", function()
    local a, wm = setup(1)
    a.focus(1)
    wm:focused(1)
    t.eq(wm:dim_scene(), nil, "lone")
    a.add(2, {})
    wm:sync()
    wm:retile()
    t.eq(wm:dim_scene() ~= nil, true, "two")
    a.wins[1].fullscreen = true
    t.eq(wm:dim_scene(), nil, "full screen")
    a.wins[1].fullscreen = false
    a.focus_ = nil
    t.eq(wm:dim_scene(), nil, "none focused")
end)

t.test("a window full screen on its own Space doesn't count as showing", function()
    local a, wm = setup(2)
    a.focus(1)
    wm:focused(1)
    a.wins[2].fullscreen = true
    t.eq(wm:dim_scene(), nil)
end)

t.test("with tide's own window focused, over the layer, every window is dimmed", function()
    local a, wm = setup(1)
    a.focus(1)
    wm:focused(1)
    a.own = true
    a.focus_ = nil
    local scene = wm:dim_scene()
    t.eq(scene, { above = {} })
    local els = dim.elements(scene, { x = 0, y = 0, w = 1920, h = 1080 }, 0.07, 10)
    t.eq(#els, 1, "no hole")
end)

t.test("a window you minimized or hid doesn't count as showing", function()
    local a, wm = setup(2)
    a.focus(1)
    wm:focused(1)
    a.wins[2].minimized = true
    wm:minimized(2)
    t.eq(wm:dim_scene(), nil, "minimized")
    a.wins[2].minimized = false
    wm.windows[2].mine = nil
    a.wins[2].hidden = true
    t.eq(wm:dim_scene(), nil, "hidden")
end)

t.test("a float in front of the focused tile is listed, front to back", function()
    local a, wm = setup(2)
    a.add(3, { subrole = "AXDialog", pid = 300, frame = { x = 100, y = 100, w = 300, h = 200 } })
    wm:sync()
    wm:retile()
    a.focus(1)
    a.raise(3)
    wm:focused(1)
    local scene = wm:dim_scene()
    t.eq(scene.focused, a.wins[1].frame)
    t.eq(scene.above, { a.wins[3].frame })
end)

local FULL = { x = 0, y = 0, w = 1920, h = 1080 }

t.test("the layer covers the display, with the focused window cut out, its corners rounded", function()
    local els = dim.elements({ focused = { x = 0, y = 25, w = 1056, h = 1055 }, above = {} }, FULL, 0.07, 10)
    t.eq(#els, 2)
    t.eq(els[1].frame, { x = 0, y = 0, w = 1920, h = 1080 })
    t.eq(els[1].fillColor.alpha, 0.07)
    t.eq(els[2].compositeRule, "destinationOut")
    t.eq(els[2].frame, { x = 0, y = 25, w = 1056, h = 1055 })
    t.eq(els[2].roundedRectRadii, { xRadius = 10, yRadius = 10 })
end)

t.test("a window in front of the focused one is dimmed again over the hole, once", function()
    local scene = { focused = { x = 0, y = 25, w = 1056, h = 1055 }, above = {
        { x = 100, y = 100, w = 300, h = 200 },
        { x = 1500, y = 100, w = 300, h = 200 },
    } }
    local els = dim.elements(scene, FULL, 0.07, 10)
    t.eq(#els, 3, "only the one over the hole")
    t.eq(els[3].frame, { x = 100, y = 100, w = 300, h = 200 })
    t.eq(els[3].compositeRule, "copy")
    t.eq(els[3].fillColor.alpha, 0.07)
end)

t.test("another display is dimmed all over, in its own coordinates", function()
    local scene = { focused = { x = 0, y = 25, w = 1056, h = 1055 }, above = {} }
    local els = dim.elements(scene, { x = 1920, y = 0, w = 2560, h = 1440 }, 0.07, 10)
    t.eq(#els, 1)
    t.eq(els[1].frame, { x = 0, y = 0, w = 2560, h = 1440 })
    local right = dim.elements({ focused = { x = 2000, y = 40, w = 800, h = 600 }, above = {} },
        { x = 1920, y = 0, w = 2560, h = 1440 }, 0.07, 10)
    t.eq(right[2].frame, { x = 80, y = 40, w = 800, h = 600 })
end)

t.test("nothing to dim, or a strength of none, draws no layer", function()
    t.eq(dim.elements(nil, FULL, 0.07, 10), nil)
    t.eq(dim.elements({ focused = { x = 0, y = 0, w = 10, h = 10 }, above = {} }, FULL, 0, 10), nil)
end)

t.test("corners are rounder from macOS 26", function()
    t.eq(dim.radius(15), 10)
    t.eq(dim.radius(26), 16)
end)

t.done("dim")
