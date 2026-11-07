-- The settings window's Displays page (displays.lua): each display's sizes
-- at its scale, where it is beside the main display, and what the page's
-- messages do.

local t = require("t")
local displays = require("tide.displays")

local MAIN = { x = 0, y = 0, w = 1512, h = 982 }

t.test("a display's sizes are the ones at its scale, one each, smallest first", function()
    local modes = {
        ["1512x982@2x 120Hz"] = { w = 1512, h = 982, scale = 2, freq = 120, depth = 8 },
        ["1512x982@2x 60Hz"] = { w = 1512, h = 982, scale = 2, freq = 60, depth = 8 },
        ["1147x745@2x"] = { w = 1147, h = 745, scale = 2, freq = 120, depth = 8 },
        ["1800x1169@2x"] = { w = 1800, h = 1169, scale = 2, freq = 120, depth = 8 },
        ["3024x1964@1x"] = { w = 3024, h = 1964, scale = 1, freq = 120, depth = 8 },
    }
    local sizes = displays.sizes(modes, 2)
    local seen = {}
    for _, m in ipairs(sizes) do
        seen[#seen + 1] = m.w .. "x" .. m.h .. "@" .. m.freq
    end
    t.eq(seen, { "1147x745@120", "1512x982@120", "1800x1169@120" })
end)

t.test("a display is beside the main one by the side it's past", function()
    t.eq(displays.place_of({ x = 1512, y = 0, w = 2560, h = 1440 }, MAIN), "right")
    t.eq(displays.place_of({ x = -1920, y = -200, w = 1920, h = 1080 }, MAIN), "left")
    t.eq(displays.place_of({ x = 0, y = -1440, w = 2560, h = 1440 }, MAIN), "above")
    t.eq(displays.place_of({ x = 100, y = 982, w = 1920, h = 1080 }, MAIN), "below")
    t.eq(displays.place_of({ x = 0, y = 0, w = 1512, h = 982 }, MAIN), nil, "a mirror")
end)

t.test("a place puts a display edge to edge with the main one", function()
    local f = { x = 9999, y = 9999, w = 2560, h = 1440 }
    t.eq({ displays.origin("right", f, MAIN) }, { 1512, 0 })
    t.eq({ displays.origin("left", f, MAIN) }, { -2560, 0 })
    t.eq({ displays.origin("above", f, MAIN) }, { 0, -1440 })
    t.eq({ displays.origin("below", f, MAIN) }, { 0, 982 })
    t.eq(displays.origin("nowhere", f, MAIN), nil)
end)

t.test("the page shows the main display first, each with its size, place and brightness", function()
    local s = displays.state({
        {
            uuid = "ext", name = "LG UltraFine", frame = { x = 1512, y = 0, w = 2560, h = 1440 },
            mode = { w = 2560, h = 1440, scale = 2 },
            modes = { a = { w = 2560, h = 1440, scale = 2 }, b = { w = 1920, h = 1080, scale = 2 } },
        },
        {
            uuid = "mac", name = "Built-in Retina Display", main = true, frame = MAIN,
            mode = { w = 1512, h = 982, scale = 2 }, modes = { a = { w = 1512, h = 982, scale = 2 } }, brightness = 0.734,
        },
    })
    t.eq(s.places, displays.PLACES)
    t.eq(s.displays, {
        {
            uuid = "mac", name = "Built-in Retina Display", main = true, size = { w = 1512, h = 982 },
            sizes = { { w = 1512, h = 982, current = true } }, brightness = 73,
        },
        {
            uuid = "ext", name = "LG UltraFine", main = false, size = { w = 2560, h = 1440 }, place = "right",
            sizes = { { w = 1920, h = 1080, current = false }, { w = 2560, h = 1440, current = true } },
        },
    })
end)

t.test("each control does what it says, and nothing for a message that's wrong", function()
    local did = {}
    local act = {
        set_size = function(...) did[#did + 1] = { "size", ... } end,
        place = function(...) did[#did + 1] = { "place", ... } end,
        make_main = function(...) did[#did + 1] = { "main", ... } end,
        set_brightness = function(...) did[#did + 1] = { "brightness", ... } end,
    }
    for _, body in ipairs({
        { displaySize = { uuid = "ext", w = 1920, h = 1080 } },
        { displayPlace = { uuid = "ext", place = "left" } },
        { displayMain = "ext" },
        { displayBrightness = { uuid = "mac", level = 140 } },
        { displayPlace = { uuid = "ext", place = "under the desk" } },
        { displaySize = { uuid = "ext" } },
    }) do
        t.eq(displays.handle(body, act), true)
    end
    t.eq(did, {
        { "size", "ext", 1920, 1080 }, { "place", "ext", "left" }, { "main", "ext" }, { "brightness", "mac", 100 },
    })
    t.eq(displays.handle({ soundMute = true }, act), false)
end)

t.done("displays")
