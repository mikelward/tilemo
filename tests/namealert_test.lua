-- The workspace's name on a switch (namealert.lua, SPEC.md §8): shown at
-- about macOS's own alert size on the display switched, replacing any name
-- still showing.

local t = require("t")
local namealert = require("tide.namealert")

-- A stand-in hs that records the alerts shown and closed.
local function stub(screens)
    local s = { shown = {}, closed = 0 }
    s.hs = {
        alert = {
            closeAll = function()
                s.closed = s.closed + 1
                s.shown = {}
            end,
            show = function(text, style, screen, seconds)
                s.shown[#s.shown + 1] = { text = text, style = style, screen = screen, seconds = seconds }
            end,
        },
        screen = {
            find = function(uuid)
                return screens[uuid]
            end,
            mainScreen = function()
                return "main"
            end,
        },
    }
    return s
end

t.test("the name shows at alert size, not across the screen", function()
    local s = stub({ left = "left" })
    namealert.show(s.hs, "docs", "left")
    t.eq(#s.shown, 1)
    t.eq(s.shown[1].text, "docs")
    -- macOS's alerts and Hammerspoon's default are about 27 pt; it was 96.
    t.eq(s.shown[1].style.textSize <= 32, true, "text size " .. tostring(s.shown[1].style.textSize))
    t.eq(s.shown[1].style.radius <= s.shown[1].style.textSize, true, "radius in proportion")
    t.eq(s.shown[1].seconds, 0.5)
end)

t.test("it shows on the display switched, or the main one if that's gone", function()
    local s = stub({ left = "left" })
    namealert.show(s.hs, "docs", "left")
    t.eq(s.shown[1].screen, "left")
    namealert.show(s.hs, "web", "gone")
    t.eq(s.shown[1].screen, "main")
end)

t.test("a new switch replaces the name still showing", function()
    local s = stub({})
    namealert.show(s.hs, "docs", nil)
    namealert.show(s.hs, "web", nil)
    t.eq(#s.shown, 1)
    t.eq(s.shown[1].text, "web")
end)

t.done("namealert")
