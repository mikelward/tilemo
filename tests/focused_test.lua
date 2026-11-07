-- The focused window, as the adapter reads it for the attention poll, the
-- bar and the keys, against stand-in apps. While Hammerspoon has the focus,
-- with a launcher or Tide Settings open, it isn't asked: asking
-- Accessibility about Hammerspoon from its own thread waits out the whole
-- timeout, every time.

local t = require("t")

local ME = 42

-- An app of `pid` whose focused window is `id`; `asked` counts the asks.
local function app(s, pid, id)
    return {
        pid = function()
            return pid
        end,
        focusedWindow = function()
            s.asked = s.asked + 1
            return id and { id = function() return id end } or nil
        end,
    }
end

-- The adapter, with `front` the frontmost app's pid and focused window.
local function stub(front_pid, front_id)
    local s = { asked = 0 }
    local apps = {
        [front_pid] = app(s, front_pid, front_id),
        [ME] = app(s, ME, 900),
        [7] = app(s, 7, 70),
    }
    _G.hs = {
        processInfo = { processID = ME },
        axuielement = {
            systemWideElement = function()
                return { setTimeout = function() end }
            end,
        },
        window = {
            filter = {
                new = function()
                    return { setDefaultFilter = function() end }
                end,
            },
            focusedWindow = function()
                s.asked = s.asked + 1
                return { id = function() return front_id end }
            end,
        },
        application = {
            frontmostApplication = function()
                return apps[front_pid]
            end,
            applicationForPID = function(pid)
                return apps[pid]
            end,
        },
        logger = { new = function() return { i = function() end } end },
        task = { new = function() end },
    }
    package.loaded["tide.hs_adapter"] = nil
    s.adapter = require("tide.hs_adapter").new()
    return s
end

t.test("another app's focused window is asked for, once", function()
    local s = stub(7, 70)
    t.eq(s.adapter.focused(), 70)
    t.eq(s.asked, 1)
end)

t.test("with Hammerspoon in front, nothing is focused, and Accessibility isn't asked", function()
    local s = stub(ME, 900)
    t.eq(s.adapter.focused(), nil)
    t.eq(s.asked, 0)
end)

t.test("an app's focused window is read for it, but not Hammerspoon's", function()
    local s = stub(7, 70)
    t.eq(s.adapter.app_focused(7), 70)
    t.eq(s.adapter.app_focused(ME), nil)
    t.eq(s.asked, 1)
end)

t.done("focused")
