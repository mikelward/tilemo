local t = require("t")
local launcher = require("tilemo.launcher")

t.test("every query character must appear, in order", function()
    t.eq(launcher.score("gc", "Google Calendar") ~= nil, true)
end)

t.test("a query that's out of order doesn't match", function()
    t.eq(launcher.score("zx", "Safari"), nil)
end)

t.test("word starts and the prefix score higher", function()
    local gc = launcher.score("gc", "Google Calendar")
    local mid = launcher.score("gc", "Bigcat")
    t.eq(gc > mid, true)
    t.eq(launcher.score("saf", "Safari") > launcher.score("saf", "Mesafe"), true)
end)

t.test("an empty query matches everything with score 0", function()
    t.eq(launcher.score("", "anything"), 0)
end)

t.test("two tabs on the same page can each be chosen", function()
    local items = launcher.items({}, {
        { title = "Docs", url = "https://example.com/", browser = "Google Chrome", window = 1, tab = 1 },
        { title = "Docs", url = "https://example.com/", browser = "Safari", window = 1, tab = 1 },
    })
    t.eq(items[1].key, items[2].key)
    t.eq(items[1].id ~= items[2].id, true)
end)

local function sample()
    return launcher.items(
        { { name = "Safari", path = "/Applications/Safari.app" }, { name = "Calendar", path = "/System/Applications/Calendar.app" } },
        { { title = "Google Chat", url = "https://chat.google.com/x", browser = "Google Chrome", window = 1, tab = 2 } },
        { { title = "Lock", quick = "lock" } }
    )
end

t.test("rank orders by score, best first", function()
    local found = launcher.rank("cal", sample())
    t.eq(found[1].title, "Calendar")
end)

t.test("a tab matches by its host, counted for less than a title", function()
    local found = launcher.rank("chat.google", sample())
    t.eq(found[1].kind, "tab")
end)

t.test("ties go to the most recently used", function()
    local items = launcher.items({ { name = "Notes", path = "/a/Notes.app" }, { name = "Notes", path = "/b/Notes.app" } })
    local found = launcher.rank("notes", items, { recency = { ["app:/b/Notes.app"] = 10 } })
    t.eq(found[1].path, "/b/Notes.app")
end)

t.test("an empty query lists tabs, then apps, then commands", function()
    local found = launcher.rank("", sample())
    t.eq(found[1].kind, "tab")
    t.eq(found[#found].kind, "command")
end)

t.test("a scope with no match falls back to every scope", function()
    local found = launcher.rank("google chat", sample(), { scope = "launch" })
    t.eq(found[1].kind, "tab")
    t.eq(#launcher.rank("lock", sample(), { scope = "tabs" }), 1)
end)

t.test("Tab moves through Launch, Tabs and Attention, and round again; Shift+Tab goes back", function()
    t.eq(launcher.SCOPE_ORDER[1], "launch")
    t.eq(launcher.next_scope("launch"), "tabs")
    t.eq(launcher.next_scope("tabs"), "attention")
    t.eq(launcher.next_scope("attention"), "launch")
    t.eq(launcher.next_scope("launch", true), "attention")
    t.eq(launcher.next_scope("tabs", true), "launch")
end)

t.test("the search field names the scope, what it lists, and where Tab goes", function()
    t.eq(launcher.placeholder("launch"), "Launch: apps, settings and commands (Tab: Tabs)")
    t.eq(launcher.placeholder("attention"), "Attention: windows wanting attention (Tab: Launch)")
end)

local function waiting()
    return launcher.items(
        { { name = "Mail", path = "/System/Applications/Mail.app" } },
        { { title = "Inbox", url = "https://mail.example.com/", browser = "Safari", window = 1, tab = 1 } },
        { { title = "Lock", action = "lock" } },
        nil,
        {
            { window = 7, title = "Chat (3)", app = "Slack", ws = 2 },
            { window = 4, title = "Zoom meeting", app = "zoom.us", ws = 5 },
            { window = 9, title = "", app = "Messages", ws = 1 },
        }
    )
end

t.test("the Attention scope lists the windows wanting attention, newest first, and nothing else", function()
    local found = launcher.rank("", waiting(), { scope = "attention" })
    t.eq(#found, 3)
    t.eq(found[1].window, 7)
    t.eq(found[2].window, 4)
    -- A window with no title goes by its app's name.
    t.eq(found[3].title, "Messages")
    t.eq(found[1].ws, 2)
end)

t.test("a window wanting attention matches by its title or its app", function()
    t.eq(launcher.rank("zoom", waiting(), { scope = "attention" })[1].window, 4)
    t.eq(launcher.rank("slack", waiting(), { scope = "attention" })[1].window, 7)
end)

t.test("a search of every scope orders windows wanting attention among the rest consistently", function()
    -- Two windows and an app that tie on the query, with recency that, if
    -- each kind kept its own order, would put them in a circle.
    local items = launcher.items({ { name = "Mail", path = "/A/Mail.app" } }, nil, nil, nil, {
        { window = 1, title = "Mail", app = "Mail", ws = 1 },
        { window = 2, title = "Mail", app = "Mail", ws = 2 },
    })
    local recency = { ["attention:1"] = 0, ["attention:2"] = 2, ["app:/A/Mail.app"] = 1 }
    for _, query in ipairs({ "mail", "" }) do
        local found = launcher.rank(query, items, { recency = recency })
        t.eq(#found, 3, query)
        t.eq(found[1].kind, query == "" and "attention" or "app", query)
        local windows = {}
        for _, item in ipairs(found) do
            if item.kind == "attention" then
                windows[#windows + 1] = item.window
            end
        end
        t.eq(windows, { 1, 2 }, query)
    end
end)

t.test("the Launch and Tabs scopes leave the windows wanting attention out", function()
    for _, scope in ipairs({ "launch", "tabs" }) do
        for _, item in ipairs(launcher.rank("", waiting(), { scope = scope })) do
            t.eq(item.kind ~= "attention", true, scope)
        end
    end
end)

t.test("items have stable keys", function()
    local items = sample()
    t.eq(items[1].key, "app:/Applications/Safari.app")
    t.eq(items[3].key, "tab:https://chat.google.com/x")
    t.eq(items[4].key, "command:Lock")
end)

t.test("every command names a window manager action or a quick action", function()
    local wm = require("tilemo.wm")
    for _, c in ipairs(launcher.COMMANDS) do
        t.eq(c.quick ~= nil or type(wm.actions[c.action]) == "function", true, c.title)
    end
end)

-- A disk for scan_apps and scan_settings: each path a folder (true) or a
-- file (false); a folder's entries are the paths directly under it.
local function disk(paths)
    return function(dir)
        local out, any = {}, false
        for path, is_dir in pairs(paths) do
            local parent, name = path:match("^(.*)/([^/]+)$")
            if parent == dir then
                out[#out + 1] = { name = name, dir = is_dir }
            end
            if path == dir then
                any = true
            end
        end
        return any and out or nil
    end
end

local function names(apps)
    local out = {}
    for _, a in ipairs(apps) do
        out[#out + 1] = a.path
    end
    table.sort(out)
    return out
end

t.test("apps come from vendor folders, Utilities, ~/Applications and CoreServices, and Finder", function()
    local list = disk({
        ["/Applications"] = true,
        ["/Applications/Safari.app"] = true,
        ["/Applications/Safari.app/Contents"] = true,
        ["/Applications/Vendor"] = true,
        ["/Applications/Vendor/Tool.app"] = true,
        ["/Applications/Vendor/readme.txt"] = false,
        ["/Applications/.hidden"] = true,
        ["/Applications/.hidden/Secret.app"] = true,
        ["/System/Applications"] = true,
        ["/System/Applications/Utilities"] = true,
        ["/System/Applications/Utilities/Terminal.app"] = true,
        ["/System/Library/CoreServices"] = true,
        ["/System/Library/CoreServices/Finder.app"] = true,
        ["/System/Library/CoreServices/Dock.app"] = true,
        ["/System/Library/CoreServices/Applications"] = true,
        ["/System/Library/CoreServices/Applications/Archive Utility.app"] = true,
        ["/home/me/Applications"] = true,
        ["/home/me/Applications/Chrome Apps.localized"] = true,
        ["/home/me/Applications/Chrome Apps.localized/Gmail.app"] = true,
    })
    t.eq(names(launcher.scan_apps(list, "/home/me")), {
        "/Applications/Safari.app",
        "/Applications/Vendor/Tool.app",
        "/System/Applications/Utilities/Terminal.app",
        "/System/Library/CoreServices/Applications/Archive Utility.app",
        "/System/Library/CoreServices/Finder.app",
        "/home/me/Applications/Chrome Apps.localized/Gmail.app",
    })
    local apps = launcher.scan_apps(list, "/home/me")
    local found = {}
    for _, a in ipairs(apps) do
        found[a.name] = true
    end
    t.eq(found["Archive Utility"], true)
end)

t.test("a missing app folder is skipped", function()
    t.eq(launcher.scan_apps(disk({}), "/home/me"), {})
end)

local SETTINGS = "/System/Library/ExtensionKit/Extensions"

local function plists(t_)
    return function(path)
        return t_[path]
    end
end

local function info(dir, plist)
    return SETTINGS .. "/" .. dir .. "/Contents/Info.plist", plist
end

t.test("System Settings' panes are the extensions that plug into it", function()
    local list = disk({
        [SETTINGS] = true,
        [SETTINGS .. "/Mouse.appex"] = true,
        [SETTINGS .. "/Wallpaper.appex"] = true,
        [SETTINGS .. "/Widget.appex"] = true,
        [SETTINGS .. "/Broken.appex"] = true,
    })
    local read = {}
    local function add(dir, plist)
        local p, v = info(dir, plist)
        read[p] = v
    end
    local point = { EXExtensionPointIdentifier = "com.apple.Settings.extension.ui" }
    add("Mouse.appex", { CFBundleIdentifier = "com.apple.Mouse-Settings.extension", CFBundleDisplayName = "Mouse", EXAppExtensionAttributes = point })
    add("Wallpaper.appex", { CFBundleIdentifier = "com.apple.Wallpaper-Settings.extension", CFBundleName = "Wallpaper", EXAppExtensionAttributes = point })
    add("Widget.appex", { CFBundleIdentifier = "com.apple.widget", CFBundleDisplayName = "Widget", EXAppExtensionAttributes = { EXExtensionPointIdentifier = "com.apple.widgetkit-extension" } })
    local panes = launcher.scan_settings(list, plists(read))
    table.sort(panes, function(a, b)
        return a.name < b.name
    end)
    t.eq(panes, {
        { name = "Mouse", id = "com.apple.Mouse-Settings.extension" },
        { name = "Wallpaper", id = "com.apple.Wallpaper-Settings.extension" },
    })
end)

t.test("a pane's name is its English localized one, as System Settings shows it", function()
    local list = disk({
        [SETTINGS] = true,
        [SETTINGS .. "/MouseExtension.appex"] = true,
        [SETTINGS .. "/WiFiSettings.appex"] = true,
    })
    local point = { EXExtensionPointIdentifier = "com.apple.Settings.extension.ui" }
    local base = SETTINGS .. "/MouseExtension.appex/Contents"
    local wifi = SETTINGS .. "/WiFiSettings.appex/Contents"
    local read = plists({
        [base .. "/Info.plist"] = { CFBundleIdentifier = "com.apple.Mouse-Settings.extension", CFBundleName = "MouseExtension", EXAppExtensionAttributes = point },
        [base .. "/Resources/InfoPlist.loctable"] = { de = { CFBundleDisplayName = "Maus" }, en = { CFBundleDisplayName = "Mouse" } },
        [wifi .. "/Info.plist"] = { CFBundleIdentifier = "com.apple.wifi-settings-extension", CFBundleName = "WiFiSettings", EXAppExtensionAttributes = point },
        [wifi .. "/Resources/en.lproj/InfoPlist.strings"] = { CFBundleDisplayName = "Wi-Fi" },
    })
    local panes = launcher.scan_settings(list, read)
    table.sort(panes, function(a, b)
        return a.name < b.name
    end)
    t.eq(panes[1].name, "Mouse")
    t.eq(panes[2].name, "Wi-Fi")
end)

t.test("without a localized name, an internal one loses its Extension and Settings", function()
    local list = disk({
        [SETTINGS] = true,
        [SETTINGS .. "/X.appex"] = true,
        [SETTINGS .. "/Y.appex"] = true,
        [SETTINGS .. "/Z.appex"] = true,
        [SETTINGS .. "/P.appex"] = true,
    })
    local point = { EXExtensionPointIdentifier = "com.apple.Settings.extension.ui" }
    local function plist(name, id)
        return { CFBundleIdentifier = id, CFBundleName = name, EXAppExtensionAttributes = point }
    end
    local panes = launcher.scan_settings(list, plists({
        [SETTINGS .. "/X.appex/Contents/Info.plist"] = plist("TrackpadExtension", "x"),
        [SETTINGS .. "/Y.appex/Contents/Info.plist"] = plist("CDs & DVDs Settings Extension", "y"),
        [SETTINGS .. "/Z.appex/Contents/Info.plist"] = plist("AccessibilitySettingsExtension", "z"),
        [SETTINGS .. "/P.appex/Contents/Info.plist"] = plist("PowerPreferences", "p"),
    }))
    local got = {}
    for _, p in ipairs(panes) do
        got[p.id] = p.name
    end
    t.eq(got, { x = "Trackpad", y = "CDs & DVDs", z = "Accessibility", p = "Power" })
end)

t.test("with no extensions folder there are no panes", function()
    t.eq(launcher.scan_settings(disk({}), plists({})), {})
end)

t.test("a pane is listed as its name and \"settings\", opening System Settings there", function()
    local items = launcher.items({}, {}, {}, {
        { name = "Mouse", id = "com.apple.Mouse-Settings.extension" },
        { name = "Game Center Settings", id = "com.apple.gc" },
    })
    t.eq(items[1].kind, "setting")
    t.eq(items[1].title, "Mouse settings")
    t.eq(items[1].url, "x-apple.systempreferences:com.apple.Mouse-Settings.extension")
    t.eq(items[1].key, "setting:com.apple.Mouse-Settings.extension")
    t.eq(items[2].title, "Game Center Settings")
end)

t.test("\"mouse\" and \"mouse settings\" find the Mouse pane, among apps and commands", function()
    local items = launcher.items(
        { { name = "Music", path = "/System/Applications/Music.app" }, { name = "System Settings", path = "/System/Applications/System Settings.app" } },
        {},
        launcher.COMMANDS,
        { { name = "Mouse", id = "com.apple.Mouse-Settings.extension" }, { name = "Trackpad", id = "com.apple.Trackpad-Settings.extension" } }
    )
    t.eq(launcher.rank("mouse", items, { scope = "launch" })[1].title, "Mouse settings")
    t.eq(launcher.rank("mouse settings", items, { scope = "launch" })[1].title, "Mouse settings")
end)

t.done("launcher")
