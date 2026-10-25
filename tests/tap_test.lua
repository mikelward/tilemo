local t = require("t")
local tap = require("timo.tap")

local function watcher()
    local fired = 0
    local w = tap.new(function()
        fired = fired + 1
    end)
    return w, function()
        return fired
    end
end

t.test("Super down and up alone is a tap", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:flags(false, true, 0.1)
    t.eq(fired(), 1)
end)

t.test("a key in between isn't a tap", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:other()
    w:flags(false, true, 0.1)
    t.eq(fired(), 0)
end)

t.test("a click or scroll in between isn't a tap", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:other() -- Super+click
    w:flags(false, true, 0.2)
    t.eq(fired(), 0)
end)

t.test("another modifier joining in isn't a tap", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:flags(false, false, 0.05) -- Super+Shift
    w:flags(true, false, 0.1) -- Shift let go
    w:flags(false, true, 0.15)
    t.eq(fired(), 0)
end)

t.test("holding Super isn't a tap", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:flags(false, true, 2)
    t.eq(fired(), 0)
end)

t.test("a spoiled tap doesn't spoil the next", function()
    local w, fired = watcher()
    w:flags(true, false, 0)
    w:other()
    w:flags(false, true, 0.1)
    w:flags(true, false, 1)
    w:flags(false, true, 1.1)
    t.eq(fired(), 1)
end)

t.test("keys pressed without Super don't arm anything", function()
    local w, fired = watcher()
    w:other()
    w:flags(false, true, 0)
    t.eq(fired(), 0)
end)

t.test("Super left over from a combination isn't a tap", function()
    local w, fired = watcher()
    w:flags(false, false, 0) -- Ctrl
    w:flags(false, false, 0.05) -- Ctrl+Super
    w:flags(true, false, 0.1) -- Ctrl let go
    w:flags(false, true, 0.15)
    t.eq(fired(), 0)
    w:flags(true, false, 1)
    w:flags(false, true, 1.1)
    t.eq(fired(), 1)
end)

t.done("tap")
