-- The focus guard (SPEC.md §14.1): nothing takes the keyboard unless you
-- asked for it.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")

-- Window 1 of app "a" focused long enough ago that nothing you did still
-- counts, and window 2 of app "b" beside it.
local function setup()
    local a = fake.new()
    a.add(1, { app = "a", pid = 1 })
    a.add(2, { app = "b", pid = 2 })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    wm:focus_window(1)
    wm:focused(1)
    a.clock = 100
    a.calls = {}
    return a, wm
end

-- macOS gives window `id` focus, as an app activating itself does.
local function steal(a, wm, id)
    a.focus_ = id
    wm:focused(id)
end

local function marked(wm, id)
    for _, m in ipairs(wm.attention:list()) do
        if m.id == id then
            return true
        end
    end
    return false
end

t.test("an app activating itself is handed focus back and marked", function()
    local a, wm = setup()
    steal(a, wm, 2)
    t.eq(a.focused(), 1, "focus")
    t.eq(a.calls[1], "focus 1")
    t.eq(marked(wm, 2), true, "marked")
    t.eq(wm.history[1], 1, "last used")
    t.eq(wm:bar_state()[1].urgent, true, "the bar shows it")
end)

t.test("focus handed back is tilemo's own, so it stays", function()
    local a, wm = setup()
    steal(a, wm, 2)
    wm:focused(1)
    t.eq(a.focused(), 1)
    t.eq(wm.history[1], 1)
end)

t.test("a new window of the app you're in keeps focus", function()
    local a, wm = setup()
    a.add(3, { app = "a", pid = 1 })
    wm:sync()
    steal(a, wm, 3)
    t.eq(a.focused(), 3)
    t.eq(marked(wm, 3), false)
end)

t.test("a focus tilemo asked for is kept", function()
    local a, wm = setup()
    wm:focus_window(2)
    wm:focused(2)
    t.eq(a.focused(), 2)
    t.eq(marked(wm, 2), false)
end)

t.test("a click just before is yours; one long before isn't", function()
    local a, wm = setup()
    wm:clicked()
    a.clock = a.clock + 0.5
    steal(a, wm, 2)
    t.eq(a.focused(), 2, "just after a click")

    a, wm = setup()
    wm:clicked()
    a.clock = a.clock + 3
    steal(a, wm, 2)
    t.eq(a.focused(), 1, "seconds after a click")
end)

t.test("Cmd+Tab is yours: while Command is down, and as it goes up", function()
    local a, wm = setup()
    wm:modifiers(true)
    a.clock = a.clock + 5
    steal(a, wm, 2)
    t.eq(a.focused(), 2, "Command held")

    a, wm = setup()
    wm:modifiers(true)
    a.clock = a.clock + 5
    wm:modifiers(false)
    steal(a, wm, 2)
    t.eq(a.focused(), 2, "Command let go")

    a, wm = setup()
    wm:modifiers(true)
    wm:modifiers(false)
    a.clock = a.clock + 5
    steal(a, wm, 2)
    t.eq(a.focused(), 1, "long after")
end)

t.test("typing isn't a choice of app: one activating as you type is refused", function()
    local a, wm = setup()
    wm:key_down("x", false)
    steal(a, wm, 2)
    t.eq(a.focused(), 1)
end)

t.test("an app key's launch may take focus once, within the grant", function()
    local a, wm = setup()
    wm:act("app", { bundle = "c" })
    t.eq(#a.launched, 1)
    a.clock = a.clock + 5
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    steal(a, wm, 3)
    t.eq(a.focused(), 3, "the launch's window")

    -- Used once: its next window, from the background, is refused.
    a.add(4, { app = "c", pid = 3 })
    wm:sync()
    wm:focus_window(1)
    wm:focused(1)
    a.clock = a.clock + 5
    steal(a, wm, 4)
    t.eq(a.focused(), 1, "used once")
end)

t.test("a launch's grant runs out, and ends when you type, click or move focus", function()
    local function launched()
        local a, wm = setup()
        wm:act("app", { bundle = "c" })
        a.add(3, { app = "c", pid = 3 })
        wm:sync()
        return a, wm
    end
    local a, wm = launched()
    a.clock = a.clock + wm_mod.GRANT + 1
    steal(a, wm, 3)
    t.eq(a.focused(), 1, "ran out")

    a, wm = launched()
    a.clock = a.clock + 1
    wm:key_down("x", false)
    a.clock = a.clock + 1
    steal(a, wm, 3)
    t.eq(a.focused(), 1, "typed")

    a, wm = launched()
    a.clock = a.clock + 1
    wm:clicked()
    a.clock = a.clock + 2
    steal(a, wm, 3)
    t.eq(a.focused(), 1, "clicked")

    a, wm = launched()
    a.clock = a.clock + 1
    wm:focus_window(2)
    wm:focused(2)
    a.clock = a.clock + 2
    steal(a, wm, 3)
    t.eq(a.focused(), 2, "moved focus")
end)

t.test("handing focus back doesn't end a launch's grant", function()
    local a, wm = setup()
    wm:act("app", { bundle = "c" })
    a.clock = a.clock + 2
    steal(a, wm, 2)
    t.eq(a.focused(), 1, "b refused")
    wm:focused(1)
    a.clock = a.clock + 2
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    steal(a, wm, 3)
    t.eq(a.focused(), 3, "c's launch")
end)

t.test("focus you moved ends a launch's grant, even after a hand-back since", function()
    local a, wm = setup()
    wm:act("app", { bundle = "c" })
    a.add(3, { app = "c", pid = 3 })
    a.add(4, { app = "d", pid = 4 })
    wm:sync()
    a.clock = a.clock + 1
    -- Focus follows mouse moves you to window 2.
    wm:focus_window(2)
    wm:focused(2)
    a.clock = a.clock + 2
    steal(a, wm, 4)
    t.eq(a.focused(), 2, "d refused")
    wm:focused(2)
    a.clock = a.clock + 2
    steal(a, wm, 3)
    t.eq(a.focused(), 2, "c's grant stays ended")
end)

t.test("an app left with the focus it took back may open its own dialog", function()
    local a, wm = setup()
    steal(a, wm, 2)
    a.clock = a.clock + 0.2
    steal(a, wm, 2)
    t.eq(a.focused(), 2)
    a.clock = a.clock + 5
    a.add(3, { app = "b", pid = 2 })
    wm:sync()
    steal(a, wm, 3)
    t.eq(a.focused(), 3, "its dialog")
    t.eq(marked(wm, 2), true, "still marked")
end)

t.test("Return may launch an app outside tilemo: its first window keeps focus, not another's", function()
    local a, wm = setup()
    wm:key_down("return", false)
    a.clock = a.clock + 4
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    steal(a, wm, 3)
    t.eq(a.focused(), 3, "a new app's first window")

    a, wm = setup()
    wm:key_down("return", false)
    a.clock = a.clock + 4
    steal(a, wm, 2)
    t.eq(a.focused(), 1, "an app already open")
end)

t.test("an app launched outside tilemo that opens several windows may take focus", function()
    local a, wm = setup()
    wm:key_down("return", false)
    a.clock = a.clock + 4
    -- It restores two windows before either is focused.
    a.add(3, { app = "c", pid = 3 })
    a.add(4, { app = "c", pid = 3 })
    wm:sync()
    steal(a, wm, 4)
    t.eq(a.focused(), 4)
end)

t.test("when the window you were in goes away, focus moving on isn't theft", function()
    local a, wm = setup()
    a.wins[1].minimized = true
    steal(a, wm, 2)
    t.eq(a.focused(), 2, "minimized")
    t.eq(marked(wm, 2), false)

    a, wm = setup()
    a.drop(1)
    steal(a, wm, 2)
    t.eq(a.focused(), 2, "closed")
end)

t.test("while the launcher holds the keyboard, a thief is only marked", function()
    local a, wm = setup()
    wm:hold("launcher", true)
    steal(a, wm, 2)
    t.eq(a.calls, {}, "no hand-back")
    t.eq(marked(wm, 2), true)
end)

t.test("an app that takes focus straight back keeps it, marked", function()
    local a, wm = setup()
    steal(a, wm, 2)
    t.eq(a.focused(), 1)
    a.clock = a.clock + 0.2
    a.calls = {}
    steal(a, wm, 2)
    t.eq(a.calls, {}, "not fought over")
    t.eq(a.focused(), 2)
    wm:poll_attention()
    t.eq(marked(wm, 2), true, "the poll leaves its mark")
end)

t.test("Super+Tab goes to the window that tried, and clears its mark", function()
    local a, wm = setup()
    steal(a, wm, 2)
    wm:act("attention")
    wm:focused(2)
    t.eq(a.focused(), 2)
    t.eq(marked(wm, 2), false)
end)

t.done("guard")
