local t = require("t")
local direction = require("tide.direction")

local function box(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function tiles(list)
    local out = {}
    for i, b in ipairs(list) do
        out[i] = { id = i, box = b }
    end
    return out
end

-- A 1920x1080 display, a bigger one to its right standing 360 px higher,
-- and a smaller one to its left, lower down.
local A = box(0, 0, 1920, 1080)
local B = box(1920, -360, 2560, 1440)
local C = box(-1280, 600, 1280, 1024)

local function id_of(hit)
    return hit and hit.id
end

t.test("on one display, the nearest window that way", function()
    local cols = tiles({ box(0, 0, 640, 1080), box(640, 0, 640, 1080), box(1280, 0, 640, 1080) })
    t.eq(id_of(direction.pick(cols[1].box, cols, 1)), 2)
    t.eq(id_of(direction.pick(cols[2].box, cols, -1)), 1)
    t.eq(id_of(direction.pick(cols[2].box, cols, 1)), 3)
    t.eq(direction.pick(cols[3].box, cols, 1), nil, "nothing right of the rightmost")
end)

t.test("a tie goes to the window first in tile order", function()
    local tall = tiles({ box(0, 0, 960, 1080), box(960, 0, 960, 540), box(960, 540, 960, 540) })
    t.eq(id_of(direction.pick(tall[3].box, tall, -1)), 1)
    t.eq(id_of(direction.pick(tall[1].box, tall, 1)), 2)
end)

t.test("at the edge, the window on the next display sharing the most height, then the nearest", function()
    local displays = {
        { name = "A", box = A, tiles = tiles({ box(1280, 540, 640, 540) }) },
        {
            name = "B",
            box = B,
            tiles = tiles({ box(1920, -360, 1280, 1440), box(3200, -360, 1280, 720), box(3200, 360, 1280, 720) }),
        },
    }
    -- The master and the lower stack window each share 540 px with it; the
    -- master's center is nearer.
    local hit, s = direction.find(box(1280, 540, 640, 540), "A", displays, 1)
    t.eq(s.name, "B")
    t.eq(id_of(hit), 1)
end)

t.test("sharing height beats being nearer, among the windows at the edge", function()
    local focused = box(1280, 700, 640, 300)
    local displays = {
        { name = "A", box = A, tiles = tiles({ focused }) },
        { name = "B", box = B, tiles = tiles({ box(1920, -360, 1280, 720), box(1920, 360, 1280, 720) }) },
    }
    local hit = direction.find(focused, "A", displays, 1)
    t.eq(id_of(hit), 2, "the lower window shares 300 px, the upper one none")
end)

t.test("on the next display, only the windows at the edge you come in by", function()
    -- B, bigger and standing higher, with its stack on the left, by A, and
    -- a taller master on the far side, sharing all of A's window's height.
    local focused = box(960, 0, 960, 1080)
    local displays = {
        { name = "A", box = A, tiles = tiles({ box(0, 0, 960, 1080), focused }) },
        {
            name = "B",
            box = B,
            tiles = tiles({ box(3200, -360, 1280, 1440), box(1920, -360, 1280, 720), box(1920, 360, 1280, 720) }),
        },
    }
    local hit, s = direction.find(focused, "A", displays, 1)
    t.eq(s.name, "B")
    t.eq(id_of(hit), 3, "the lower stack window, sharing 720 px, not the master sharing 1080")
    -- And back the other way, from B's lower stack window: A's lower stack
    -- window, sharing 540 px, not A's master, sharing 720.
    displays[1].tiles = tiles({ box(0, 0, 1056, 1080), box(1056, 0, 864, 540), box(1056, 540, 864, 540) })
    hit, s = direction.find(displays[2].tiles[3].box, "B", displays, -1)
    t.eq(s.name, "A")
    t.eq(id_of(hit), 3, "the window at A's right edge level with it")
end)

t.test("going left onto a smaller display lower down, its right column, not its master", function()
    -- C's master is on its left, sharing 380 px with the focused window;
    -- of its three stack windows at its right edge, the top one shares 241.
    local focused = box(0, 700, 960, 380)
    local displays = {
        { name = "A", box = A, tiles = tiles({ focused }) },
        {
            name = "C",
            box = C,
            tiles = tiles({
                box(-1280, 600, 768, 1024),
                box(-512, 600, 512, 341),
                box(-512, 941, 512, 341),
                box(-512, 1282, 512, 342),
            }),
        },
    }
    local hit, s = direction.find(focused, "A", displays, -1)
    t.eq(s.name, "C")
    t.eq(id_of(hit), 2)
end)

t.test("a pixel's difference in rounding still counts as the edge", function()
    local focused = box(0, 0, 1920, 1080)
    local displays = {
        { name = "A", box = A, tiles = tiles({ focused }) },
        -- The stack's lower window is a pixel in from the edge, and shares
        -- more height; the master, two pixels in, would share the most.
        {
            name = "D",
            box = box(1920, 0, 1920, 1080),
            tiles = tiles({ box(1922, 0, 958, 1080), box(1920, 0, 960, 300), box(1921, 300, 959, 780) }),
        },
    }
    local hit = direction.find(focused, "A", displays, 1)
    t.eq(id_of(hit), 3)
end)

t.test("with no height shared, the nearest center, on a smaller display lower down", function()
    local focused = box(0, 0, 640, 500)
    local displays = {
        { name = "A", box = A, tiles = tiles({ focused }) },
        { name = "B", box = B, tiles = tiles({ box(1920, -360, 2560, 1440) }) },
        { name = "C", box = C, tiles = tiles({ box(-1280, 600, 640, 1024), box(-640, 600, 640, 1024) }) },
    }
    local hit, s = direction.find(focused, "A", displays, -1)
    t.eq(s.name, "C")
    t.eq(id_of(hit), 2, "its right column, nearer A")
end)

t.test("the next display is the one sharing the most height with this one", function()
    local displays = {
        { name = "A", box = A, tiles = {} },
        { name = "E", box = box(1920, 1080, 1920, 1080), tiles = tiles({ box(1920, 1080, 1920, 1080) }) },
        { name = "D", box = box(1920, 0, 1920, 1080), tiles = tiles({ box(1920, 0, 1920, 1080) }) },
    }
    local _, s = direction.find(A, "A", displays, 1)
    t.eq(s.name, "D")
end)

t.test("a display that way with no windows is still where it goes", function()
    local displays = {
        { name = "A", box = A, tiles = tiles({ box(0, 0, 1920, 1080) }) },
        { name = "B", box = B, tiles = {} },
    }
    local hit, s = direction.find(box(0, 0, 1920, 1080), "A", displays, 1)
    t.eq(hit, nil)
    t.eq(s.name, "B")
end)

t.test("past the last display that way, nothing", function()
    local displays = {
        { name = "A", box = A, tiles = tiles({ box(0, 0, 1920, 1080) }) },
        { name = "B", box = B, tiles = tiles({ box(1920, -360, 2560, 1440) }) },
    }
    local hit, s = direction.find(box(1920, -360, 2560, 1440), "B", displays, 1)
    t.eq(hit, nil)
    t.eq(s, nil)
end)

t.test("the next display is the one that way, by the same rule", function()
    local displays = { { name = "A", box = A }, { name = "B", box = B }, { name = "C", box = C } }
    t.eq(direction.next_monitor(displays[1], displays, 1).name, "B")
    t.eq(direction.next_monitor(displays[1], displays, -1).name, "C")
    t.eq(direction.next_monitor(displays[2], displays, 1), nil, "none past the last")
end)

-- A float moving from a 1920x1046 work area to one half its size.
local FROM, TO = box(0, 34, 1920, 1046), box(1920, 34, 960, 523)

t.test("a float in the top left lands in the top left", function()
    t.eq(direction.place(box(96, 86, 400, 300), FROM, TO), box(1968, 60, 400, 300))
end)

t.test("a float in the bottom right lands in the bottom right", function()
    t.eq(direction.place(box(1420, 680, 500, 400), FROM, TO), box(2380, 157, 500, 400), "held inside")
    t.eq(direction.place(box(1420, 680, 500, 400), FROM, box(1920, 34, 1920, 1046)), box(3340, 680, 500, 400),
        "the same spot on a display the same size")
end)

t.test("a float too big for the next display shrinks to fit inside it", function()
    t.eq(direction.place(box(100, 100, 1200, 600), FROM, TO), box(1920, 34, 960, 523))
    t.eq(direction.place(box(800, 100, 1200, 300), FROM, TO), box(1920, 67, 960, 300), "only the side too big")
end)

t.done("direction")
