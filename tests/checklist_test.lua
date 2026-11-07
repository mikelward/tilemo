local t = require("t")
local checklist = require("tide.checklist")
local links = require("tide.links")

local function by_id(list)
    local out = {}
    for _, x in ipairs(list) do
        out[x.id] = x
    end
    return out
end

t.test("every permission and item opens a System Settings pane", function()
    for _, list in ipairs({ checklist.PERMISSIONS, checklist.ITEMS }) do
        for _, x in ipairs(list) do
            t.eq(links.PANES[x.link] ~= nil, true, x.id .. " opens nothing")
            t.eq(x.ref:match("^§%d") ~= nil, true, x.id .. " names no section")
        end
    end
end)

t.test("Accessibility is on or off as macOS says, and can't be told unasked", function()
    t.eq(checklist.permission_state("accessibility", { accessibility = true }), "on")
    t.eq(checklist.permission_state("accessibility", { accessibility = false }), "off")
    t.eq(checklist.permission_state("accessibility", {}), "unknown")
end)

t.test("Input Monitoring isn't needed with Karabiner, and can't be read without", function()
    t.eq(checklist.permission_state("input_monitoring", { karabiner = true }), "not_needed")
    t.eq(checklist.permission_state("input_monitoring", { karabiner = false }), "unknown")
end)

t.test("Screen Recording is never needed, and Automation can't be read", function()
    t.eq(checklist.permission_state("screen_recording", { accessibility = true }), "not_needed")
    t.eq(checklist.permission_state("automation", { accessibility = true, karabiner = true }), "unknown")
end)

t.test("Location Services is on or off as macOS says, off until it's asked", function()
    t.eq(checklist.permission_state("location", { location = "authorized" }), "on")
    t.eq(checklist.permission_state("location", { location = "denied" }), "off")
    t.eq(checklist.permission_state("location", { location = "undefined" }), "off", "not asked yet")
    t.eq(checklist.permission_state("location", {}), "unknown")
end)

t.test("Location Services' button asks macOS the first time, then opens the list", function()
    -- Hammerspoon is in Privacy & Security's list only once it's asked.
    t.eq(checklist.ask_first("privacy_location", { location = "undefined" }), true)
    t.eq(checklist.ask_first("privacy_location", { location = "denied" }), false)
    t.eq(checklist.ask_first("privacy_location", { location = "authorized" }), false)
    t.eq(checklist.ask_first("privacy_location", {}), false, "can't tell: the list")
    t.eq(checklist.ask_first("privacy_accessibility", { location = "undefined" }), false)
end)

t.test("the page gives each permission its state's label, and each item its tick", function()
    local page = checklist.page({ accessibility = false, karabiner = true }, { "lock", "minimize" })
    local perms = by_id(page.permissions)
    t.eq(perms.accessibility.state, "off")
    t.eq(perms.accessibility.label, "Off")
    t.eq(perms.input_monitoring.label, "Not needed")
    t.eq(perms.automation.label, "Can't tell")
    t.eq(perms.accessibility.link, "privacy_accessibility")
    local items = by_id(page.items)
    t.eq(items.lock.done, true)
    t.eq(items.minimize.done, true)
    t.eq(items.mission_control.done, false)
    t.eq(page.left, #checklist.ITEMS - 2)
    t.eq(#page.permissions, #checklist.PERMISSIONS)
    t.eq(#page.items, #checklist.ITEMS)
end)

t.test("only ticks for items that still exist count, once each, in the items' order", function()
    t.eq(checklist.progress({ "lock", "gone", "mission_control", "lock" }), { done = { "mission_control", "lock" }, left = #checklist.ITEMS - 2 })
    t.eq(checklist.progress(nil), { done = {}, left = #checklist.ITEMS })
    t.eq(checklist.progress("junk"), { done = {}, left = #checklist.ITEMS })
end)

t.test("a tick adds an item and an untick takes it out, keeping the rest", function()
    local list = checklist.ticked({ "lock" }, "tiling", true)
    t.eq(list, { "lock", "tiling" })
    t.eq(checklist.ticked(list, "lock", false), { "tiling" })
    t.eq(checklist.ticked({ "lock" }, "lock", true), { "lock" }, "ticked twice is once")
end)

t.test("a tick for an item the checklist doesn't have is refused", function()
    local list, why = checklist.ticked({ "lock" }, "accessibility", true)
    t.eq(list, nil)
    t.eq(why:find("no item accessibility", 1, true) ~= nil, true)
    t.eq((checklist.ticked({}, nil, true)), nil)
end)

t.test("tide doctor names Accessibility only when it's off", function()
    t.eq(#checklist.doctor({ accessibility = false }), 1)
    t.eq(checklist.doctor({ accessibility = false })[1]:find("Accessibility is off", 1, true) ~= nil, true)
    t.eq(checklist.doctor({ accessibility = true }), {})
    t.eq(checklist.doctor({}), {}, "unknown isn't a problem to report")
end)

t.test("tide doctor says when the menu bar is set to hide, with the fix", function()
    local lines = checklist.doctor({ accessibility = true, menu_bar_hidden = true })
    t.eq(lines, { checklist.MENU_BAR_NOTICE })
    t.eq(lines[1]:find("Never", 1, true) ~= nil, true)
    t.eq(checklist.doctor({ accessibility = true, menu_bar_hidden = false }), {})
    t.eq(#checklist.doctor({ accessibility = false, menu_bar_hidden = true }), 2, "both, not just the first")
end)

t.test("the checklist asks for the menu bar shown, from Control Center", function()
    local item
    for _, i in ipairs(checklist.ITEMS) do
        if i.id == "menu_bar" then
            item = i
        end
    end
    t.eq(item ~= nil, true)
    t.eq(item.link, "control_center")
    t.eq(item.how:find("Never", 1, true) ~= nil, true)
end)

t.done("checklist")
