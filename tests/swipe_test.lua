local t = require("t")
local swipe = require("tide.swipe")
local fake = require("fake")
local wm_mod = require("tide.wm")

local function watcher()
    local steps = {}
    local w = swipe.new(function(d)
        steps[#steps + 1] = d
    end)
    return w, steps
end

-- Three fingers at x, each 0.1 apart, at height y.
local function three(x, y, ids)
    ids = ids or { 1, 2, 3 }
    return {
        { id = ids[1], x = x, y = y or 0.5 },
        { id = ids[2], x = x + 0.1, y = y or 0.5 },
        { id = ids[3], x = x + 0.2, y = y or 0.5 },
    }
end

t.test("three fingers moving left step to the next workspace", function()
    local w, steps = watcher()
    w:touches(three(0.6))
    w:touches(three(0.5))
    w:touches(three(0.4))
    t.eq(steps, { 1 })
end)

t.test("three fingers moving right step to the previous one", function()
    local w, steps = watcher()
    w:touches(three(0.2))
    w:touches(three(0.4))
    t.eq(steps, { -1 })
end)

t.test("one swipe steps once, however far it goes", function()
    local w, steps = watcher()
    w:touches(three(0.7))
    w:touches(three(0.5))
    w:touches(three(0.3))
    w:touches(three(0.1))
    t.eq(steps, { 1 })
end)

t.test("lifting every finger lets the next swipe step again", function()
    local w, steps = watcher()
    w:touches(three(0.6))
    w:touches(three(0.4))
    w:touches({})
    w:touches(three(0.6))
    w:touches(three(0.4))
    t.eq(steps, { 1, 1 })
end)

t.test("fingers lifting one by one after a swipe start nothing", function()
    local w, steps = watcher()
    w:touches(three(0.6))
    w:touches(three(0.4))
    local last = three(0.4)
    w:touches({ last[1], last[2] })
    w:touches({ last[1] })
    w:touches({})
    t.eq(steps, { 1 })
end)

t.test("a short move isn't a swipe", function()
    local w, steps = watcher()
    w:touches(three(0.5))
    w:touches(three(0.45))
    w:touches({})
    t.eq(steps, {})
end)

t.test("a mostly vertical move isn't a swipe", function()
    local w, steps = watcher()
    w:touches(three(0.5, 0.2))
    w:touches(three(0.35, 0.6))
    t.eq(steps, {})
end)

t.test("two or four fingers aren't a swipe", function()
    local w, steps = watcher()
    local function two(x)
        local p = three(x)
        return { p[1], p[2] }
    end
    w:touches(two(0.6))
    w:touches(two(0.3))
    w:touches({})
    local function four(x)
        local p = three(x)
        p[4] = { id = 4, x = x + 0.3, y = 0.5 }
        return p
    end
    w:touches(four(0.6))
    w:touches(four(0.3))
    t.eq(steps, {})
end)

t.test("a fourth finger joining calls the swipe off until every finger lifts", function()
    local w, steps = watcher()
    w:touches(three(0.6))
    local p = three(0.55)
    p[4] = { id = 4, x = 0.9, y = 0.5 }
    w:touches(p)
    w:touches(three(0.3))
    t.eq(steps, {})
    w:touches({})
    w:touches(three(0.6))
    w:touches(three(0.4))
    t.eq(steps, { 1 })
end)

t.test("three fingers that aren't the same three call it off", function()
    local w, steps = watcher()
    w:touches(three(0.6))
    w:touches(three(0.3, nil, { 1, 2, 4 }))
    t.eq(steps, {})
end)

t.test("a three-finger drag isn't a swipe", function()
    local w, steps = watcher()
    w:touches(three(0.6), true)
    w:touches(three(0.4), true)
    -- The button comes up before the fingers do.
    w:touches(three(0.2))
    t.eq(steps, {})
    w:touches({})
    w:touches(three(0.6))
    w:touches(three(0.4))
    t.eq(steps, { 1 })
end)

t.test("a swipe shows the next workspace with windows, and back", function()
    local a = fake.new()
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, { workspaces = { "in" } })
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 2
    wm:act("send", "web")
    wm:show("in")
    local w = swipe.for_wm(wm)
    w:touches(three(0.6))
    w:touches(three(0.4))
    w:touches({})
    t.eq(wm.current, "web")
    w:touches(three(0.2))
    w:touches(three(0.4))
    t.eq(wm.current, "in")
end)

t.test("the swipe setting is true or false", function()
    swipe.check(nil)
    swipe.check(true)
    swipe.check(false)
    local ok, err = pcall(swipe.check, "yes")
    t.eq(ok, false)
    t.eq(tostring(err):find("swipe must be true or false", 1, true) ~= nil, true)
end)

t.done("swipe")
