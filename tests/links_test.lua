local t = require("t")
local links = require("tide.links")
local bar = require("tide.bar")
local mute = require("tide.mute")

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("a")
    f:close()
    return s
end

local function opener()
    local opened = {}
    return opened, {
        open_url = function(url)
            opened[#opened + 1] = { url = url }
        end,
        open_helper = function(spec)
            opened[#opened + 1] = { app = spec }
        end,
    }
end

t.test("every button opens a pane or a helper, and says which settings", function()
    for _, l in ipairs(links.page_list()) do
        t.eq((links.PANES[l.name] or links.APPS[l.name]) and true or false, true, l.name .. " opens nothing")
        t.eq((l.label:match(" settings$")) and true or false, true, l.label .. " doesn't name its settings")
    end
end)

t.test("a pane opens by its System Settings URL", function()
    local opened, adapter = opener()
    t.eq(links.open("mouse", adapter), true)
    t.eq(opened, { { url = "x-apple.systempreferences:com.apple.Mouse-Settings.extension" } })
end)

t.test("LinearMouse opens by its bundle ID, showing its window", function()
    local opened, adapter = opener()
    t.eq(links.open("linearmouse", adapter), true)
    t.eq(opened, { { app = { bundle = "com.lujjjh.LinearMouse", args = { "--show" } } } })
end)

t.test("Karabiner opens by its settings app's name", function()
    local opened, adapter = opener()
    t.eq(links.open("karabiner", adapter), true)
    t.eq(opened, { { app = { app = "Karabiner-Elements" } } })
end)

t.test("a name the table doesn't have opens nothing", function()
    local opened, adapter = opener()
    t.eq(links.open("https://example.com", adapter), false)
    t.eq(links.open(nil, adapter), false)
    t.eq(links.open("open_url", adapter), false)
    t.eq(opened, {})
end)

t.test("the bar's icons and the mute notice open the same panes as the window", function()
    t.eq(bar.PANES.volume, links.PANES.sound)
    t.eq(bar.PANES.battery, links.PANES.battery)
    t.eq(bar.PANES.bluetooth, links.PANES.bluetooth)
    t.eq(mute.NOTIFICATIONS_URL, links.PANES.notifications)
end)

-- tide's pages in tide's order (tide SPEC.md §16, shell/lib/settings.mjs).
local TIDE_ORDER = {
    "displays", "sound", "network", "bluetooth", "mouse", "trackpad", "keyboard", "power",
    "layouts", "workspaces", "floating",
    "appearance", "muted", "clipboard", "clocks", "idle", "startup",
    -- Then tide's own Setup checklist, which tide has no page for.
    "setup",
}

t.test("the settings window's sections are tide's pages, in tide's order, then the checklist", function()
    local html = read("hammerspoon/tide/dashboard/settings.html")
    local ids = {}
    for id in html:gmatch('<h1 id="([%w_-]+)"') do
        ids[#ids + 1] = id
    end
    t.eq(ids, TIDE_ORDER)
end)

t.test("Privacy & Security's lists open the pane at the list", function()
    local opened, adapter = opener()
    t.eq(links.open("privacy_accessibility", adapter), true)
    t.eq(links.open("privacy_input_monitoring", adapter), true)
    t.eq(opened, {
        { url = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility" },
        { url = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent" },
    })
end)

t.test("each section with buttons has a row for them", function()
    local html = read("hammerspoon/tide/dashboard/settings.html")
    for _, s in ipairs(links.SECTIONS) do
        t.eq((html:find('<h1 id="' .. s.id .. '"', 1, true)) and true or false, true, "no section " .. s.id)
        t.eq((html:find('id="' .. s.id .. '-links"', 1, true)) and true or false, true, "no row for " .. s.id .. "'s buttons")
    end
end)

t.test("each section's buttons are at its foot, as tide's advanced row", function()
    local html = read("hammerspoon/tide/dashboard/settings.html")
    for _, s in ipairs(links.SECTIONS) do
        local section = html:match('<section class="page" id="page%-' .. s.id .. '".-</section>')
        t.eq(section:find('<p class="row links" id="' .. s.id .. '%-links"></p>\n</section>$') ~= nil, true, s.id)
    end
end)

t.done("links")
