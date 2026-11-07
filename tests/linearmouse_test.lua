local t = require("t")
local linearmouse = require("tide.linearmouse")

local function yes()
    return true
end
local function no()
    return false
end

t.test("LinearMouse installed and running is no problem", function()
    t.eq(linearmouse.problem(yes, yes), nil)
end)

t.test("LinearMouse not installed is missing, whatever's running", function()
    t.eq(linearmouse.problem(no, yes), "missing")
    t.eq(linearmouse.problem(no, no), "missing")
end)

t.test("LinearMouse installed but not running is stopped", function()
    t.eq(linearmouse.problem(yes, no), "stopped")
end)

t.test("each problem says what stops working", function()
    for _, kind in ipairs({ "missing", "stopped" }) do
        for _, where in ipairs({ "notice", "doctor", "section" }) do
            local text = linearmouse.say(kind, where)
            t.eq((text:find("wheel notch scrolls a line or so", 1, true)) and true or false, true, kind .. " " .. where .. ": " .. text)
        end
    end
end)

t.test("missing says setup-macos installs it", function()
    t.eq((linearmouse.say("missing", "notice"):find("setup-macos installs it", 1, true)) and true or false, true)
end)

t.test("stopped says how to start it, for where it's said", function()
    t.eq((linearmouse.say("stopped", "notice"):find("Click to start it", 1, true)) and true or false, true)
    t.eq((linearmouse.say("stopped", "doctor"):find("LinearMouse settings, under Mouse", 1, true)) and true or false, true)
    -- The section has the button beside it, so it only says what's wrong.
    t.eq(linearmouse.say("stopped", "section"),
        "LinearMouse isn't running, so a mouse wheel notch scrolls a line or so, faster as you spin it.")
end)

t.test("no problem says nothing", function()
    t.eq(linearmouse.say(nil, "section"), nil)
end)

t.test("the Mouse section says LinearMouse's problem and what stops its scrolling being set", function()
    local settings_hs = require("tide.settings_hs")
    t.eq(settings_hs.mouse_problem({}), "")
    t.eq(settings_hs.mouse_problem({ linearmouse = "stopped" }), linearmouse.say("stopped", "section"))
    local applied = { state = { problem = "Can't set LinearMouse's scrolling: linearmouse.json isn't JSON." } }
    t.eq(settings_hs.mouse_problem({ linearmouse_settings = applied }), applied.state.problem)
    t.eq(settings_hs.mouse_problem({ linearmouse = "stopped", linearmouse_settings = applied }),
        linearmouse.say("stopped", "section") .. " " .. applied.state.problem)
end)

t.done("linearmouse")
