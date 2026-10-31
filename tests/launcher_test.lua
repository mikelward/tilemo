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
    t.eq(#launcher.rank("lock", sample(), { scope = "windows" }), 1)
end)

t.test("Tab moves through Launch, Workspaces, Windows and Attention, and round again; Shift+Tab goes back", function()
    t.eq(launcher.SCOPE_ORDER, { "launch", "workspaces", "windows", "attention" })
    t.eq(launcher.next_scope("launch"), "workspaces")
    t.eq(launcher.next_scope("workspaces"), "windows")
    t.eq(launcher.next_scope("windows"), "attention")
    t.eq(launcher.next_scope("attention"), "launch")
    t.eq(launcher.next_scope("launch", true), "attention")
    t.eq(launcher.next_scope("workspaces", true), "launch")
end)

t.test("the search field names the scope, what it lists, and where Tab goes", function()
    t.eq(launcher.placeholder("launch"), "Launch: apps, settings and commands (Tab: Workspaces)")
    t.eq(launcher.placeholder("attention"), "Attention: windows wanting attention (Tab: Launch)")
end)

t.test("the Workspaces tab lists every workspace in bar order, by name or by an app on it", function()
    local items = launcher.items({ { name = "Safari", path = "/Applications/Safari.app" } }, {}, {}, {}, {}, {
        { name = "in", apps = "Mail", where = "here" },
        { name = "re", apps = "", where = "empty" },
        { name = "web", apps = "Google Chrome, Safari" },
    })
    local found = launcher.rank("", items, { scope = "workspaces" })
    local names = {}
    for i, item in ipairs(found) do
        names[i] = item.title
        t.eq(item.kind, "workspace")
    end
    t.eq(names, { "in", "re", "web" })
    t.eq(launcher.rank("chrome", items, { scope = "workspaces" })[1].title, "web")
    t.eq(launcher.rank("re", items, { scope = "workspaces" })[1].title, "re")
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

t.test("the Launch and Windows tabs leave the windows wanting attention out", function()
    for _, scope in ipairs({ "launch", "windows" }) do
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

t.test("no command shows a workspace by number, now that they have names", function()
    for _, c in ipairs(launcher.COMMANDS) do
        t.eq(c.action ~= "show", true, c.title)
    end
end)

t.test("every command names a window manager action or a quick action", function()
    local wm = require("tilemo.wm")
    for _, c in ipairs(launcher.COMMANDS) do
        t.eq(c.quick ~= nil or type(wm.actions[c.action]) == "function", true, c.title)
    end
end)

t.test("a row's subtitle leaves out what's missing, wherever it is", function()
    t.eq(launcher.subtitle({ kind = "workspace", extra = "Mail, Safari" }), "Mail, Safari", "no where: a hidden workspace")
    t.eq(launcher.subtitle({ kind = "workspace", where = "here", extra = "" }), "here")
    t.eq(launcher.subtitle({ kind = "workspace", where = "empty", extra = "" }), "empty")
    t.eq(launcher.subtitle({ kind = "workspace" }), "")
    t.eq(launcher.subtitle({ kind = "attention", app = "Slack", ws = "web" }), "Slack · web")
    t.eq(launcher.subtitle({ kind = "attention", ws = "web" }), "web")
    t.eq(launcher.subtitle({ kind = "tab", browser = "Safari" }), "Safari")
    t.eq(launcher.subtitle({ kind = "setting" }), "System Settings")
    t.eq(launcher.subtitle({ kind = "command" }), "command")
end)

-- The Windows tab (SPEC.md §9) ----------------------------------------------

local function wins()
    return {
        { id = 7, title = "Inbox - Mail", app_name = "Mail", ws = "in" },
        { id = 3, title = "", app_name = "kitty", ws = "tilemo" },
        { id = 9, title = "Design doc - Google Chrome", app_name = "Google Chrome", ws = "web" },
    }
end

t.test("the Windows tab lists every window, most recently used first, and the browsers' tabs", function()
    local items = launcher.items({}, {
        { title = "Pull requests", url = "https://github.com/x", browser = "Google Chrome", window = 1, tab = 2, win = 9, ws = "web" },
    }, {}, {}, {}, {}, wins())
    local found = launcher.rank("", items, { scope = "windows" })
    t.eq(found[1].window, 7)
    t.eq(found[2].title, "kitty", "no title: the app's name")
    t.eq(found[2].ws, "tilemo")
    t.eq(found[3].window, 9)
    t.eq(found[4].kind, "tab")
    t.eq(found[4].ws, "web", "a tab carries its window's workspace")
    t.eq(launcher.rank("github", items, { scope = "windows" })[1].kind, "tab")
    t.eq(launcher.rank("kitty", items, { scope = "windows" })[1].window, 3, "by app too")
    -- From Launch, text that matches nothing there finds a window.
    t.eq(launcher.rank("inbox", items, { scope = "launch" })[1].window, 7)
end)

t.test("the Windows tab shows every window and every tab, however many", function()
    local windows, tabs = {}, {}
    for i = 1, 30 do
        windows[i] = { id = i, title = "Window " .. i, app_name = "App", ws = "in" }
        tabs[i] = { title = "Tab " .. i, url = "https://example.com/" .. i, browser = "Safari", window = 1, tab = i }
    end
    local items = launcher.items({}, tabs, {}, {}, {}, {}, windows)
    local found = launcher.rank("", items, { scope = "windows" })
    t.eq(#found, 60)
    t.eq(found[60].kind, "tab", "the last tab too")
    t.eq(#launcher.rank("tab", items, { scope = "windows" }), 30)
    -- Launch keeps its cap: it lists every app and pane on the Mac.
    local apps = {}
    for i = 1, 30 do
        apps[i] = { name = "App " .. i, path = "/Applications/App " .. i .. ".app" }
    end
    t.eq(#launcher.rank("", launcher.items(apps), { scope = "launch" }), launcher.LIMITS.launch)
end)

t.test("each browser's tab list is read line by line, with its window's name", function()
    local text = "1\t1\t1\t4021\tDocs - Google Chrome\thttps://docs.example.com/\tDocs\n"
        .. "1\t2\t0\t4021\tDocs - Google Chrome\thttps://x.example.com/a\tA title\twith a tab\n"
        .. "garbage\n"
        .. "2\t1\t1\t77\t\t\t\n"
    local list = launcher.parse_tabs("Google Chrome", text)
    t.eq(#list, 3)
    t.eq(list[1], {
        browser = "Google Chrome", window = 1, tab = 1, active = true, window_id = 4021, window_name = "Docs - Google Chrome",
        url = "https://docs.example.com/", title = "Docs",
    })
    t.eq(list[3].window_id, 77)
    t.eq(list[2].title, "A title\twith a tab", "the title is the rest of the line")
    t.eq(list[3].window, 2)
    t.eq(list[2].active, false, "only the front tab is active")
    t.eq(launcher.parse_tabs("Safari", nil), {})
end)

t.test("a tab finds its tilemo window by its browser and its window's name, if just one has it", function()
    local windows = {
        { id = 1, app = "com.google.Chrome", title = "Docs - Google Chrome", ws = "web" },
        { id = 2, app = "com.google.Chrome", title = "Mail - Google Chrome", ws = "in" },
        { id = 3, app = "com.apple.Safari", title = "Docs - Google Chrome", ws = "x" },
    }
    local tab = { window_name = "Docs - Google Chrome" }
    t.eq(launcher.tab_window(tab, "com.google.Chrome", windows).id, 1)
    t.eq(launcher.tab_window({ window_name = "Nope" }, "com.google.Chrome", windows), nil)
    t.eq(launcher.tab_window({ window_name = "" }, "com.google.Chrome", windows), nil)
    windows[2].title = "Docs - Google Chrome"
    t.eq(launcher.tab_window(tab, "com.google.Chrome", windows), nil, "two alike: neither")
end)

t.test("Brave's tabs are asked for as Chrome's are, by its own name", function()
    local names = {}
    for _, b in ipairs(launcher.BROWSERS) do
        names[#names + 1] = b.name .. "=" .. b.bundle
    end
    t.eq(names, { "Google Chrome=com.google.Chrome", "Brave Browser=com.brave.Browser", "Safari=com.apple.Safari" })
    local brave = launcher.browser("Brave Browser")
    local script = launcher.tab_script(brave)
    t.eq(script:find('tell application "Brave Browser"', 1, true) ~= nil, true)
    t.eq(script, (launcher.tab_script(launcher.browser("Google Chrome")):gsub("Google Chrome", "Brave Browser")), "Chrome's, renamed")
    t.eq(script:find("active tab index of window w", 1, true) ~= nil, true)
    t.eq(script:find("(title of tab t of window w)", 1, true) ~= nil, true)
    t.eq(launcher.browser("Firefox"), nil, "no AppleScript tabs")
end)

t.test("Safari's tabs are its current tab and its tabs' names", function()
    local script = launcher.tab_script(launcher.browser("Safari"))
    t.eq(script:find('tell application "Safari"', 1, true) ~= nil, true)
    t.eq(script:find("index of current tab of window w", 1, true) ~= nil, true)
    t.eq(script:find("(name of tab t of window w)", 1, true) ~= nil, true)
end)

t.test("a chosen tab is brought forward in its window by id, in its browser's words", function()
    local item = { window = 2, window_id = 4021, tab = 3 }
    local brave = launcher.open_tab_script(launcher.browser("Brave Browser"), item)
    t.eq(brave:find('tell application "Brave Browser"', 1, true) ~= nil, true)
    t.eq(brave:find("set active tab index of window id 4021 to 3", 1, true) ~= nil, true)
    t.eq(brave:find("set minimized of window id 4021 to false", 1, true) ~= nil, true)
    t.eq(brave:find("set index of window id 4021 to 1", 1, true) ~= nil, true)
    local safari = launcher.open_tab_script(launcher.browser("Safari"), item)
    t.eq(safari:find("set current tab of window id 4021 to tab 3 of window id 4021", 1, true) ~= nil, true)
    t.eq(safari:find("set miniaturized of window id 4021 to false", 1, true) ~= nil, true)
    local old = launcher.open_tab_script(launcher.browser("Google Chrome"), { window = 2, tab = 1 })
    t.eq(old:find("set active tab index of window 2 to 1", 1, true) ~= nil, true, "no id: by number")
end)

t.test("Brave's tabs parse as Chrome's do and find Brave's windows", function()
    local list = launcher.parse_tabs("Brave Browser", "1\t1\t1\t77\tDocs - Brave\thttps://docs.example.com/\tDocs\n")
    t.eq(list[1].browser, "Brave Browser")
    local windows = { { id = 5, app = "com.brave.Browser", title = "Docs - Brave", ws = "web" } }
    t.eq(launcher.tab_window(list[1], launcher.browser("Brave Browser").bundle, windows).id, 5)
end)

t.test("a window's and a tab's subtitles name their workspace", function()
    t.eq(launcher.subtitle({ kind = "window", app = "Mail", ws = "in" }), "Mail · in")
    t.eq(launcher.subtitle({ kind = "window", ws = "in" }), "in")
    t.eq(launcher.subtitle({ kind = "tab", browser = "Safari", extra = "github.com", ws = "web" }), "Safari · github.com · web")
    t.eq(launcher.subtitle({ kind = "tab", browser = "Safari", ws = "web" }), "Safari · web", "no host")
    -- about:blank has no host: the item's extra is nil, and its row still
    -- draws.
    local items = launcher.items({}, {
        { title = "", url = "about:blank", browser = "Google Chrome", window = 1, tab = 1, window_id = 9 },
    })
    t.eq(items[1].extra, nil)
    t.eq(items[1].window_id, 9, "the window's id travels with the tab")
    t.eq(launcher.subtitle(items[1]), "Google Chrome")
end)

t.test("every tab says what it is when it's empty", function()
    for _, scope in ipairs(launcher.SCOPE_ORDER) do
        t.eq(type(launcher.SCOPE_EMPTY[scope]), "string", scope)
        t.eq(launcher.placeholder(scope):find(launcher.SCOPE_NAMES[scope], 1, true), 1, scope)
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

t.test("each settings section has its own row, found by its name, opening the window there", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {})
    local function first(q)
        return launcher.rank(q, items, { scope = "launch" })[1]
    end
    t.eq(first("start at login").title, "Settings: start at login")
    t.eq(first("start at login").arg, "startup")
    t.eq(first("clocks").arg, "clocks")
    t.eq(first("muted").arg, "muted")
    local sections = {}
    for _, c in ipairs(launcher.COMMANDS) do
        if c.action == "settings" then
            sections[#sections + 1] = c.arg
        end
    end
    t.eq(sections, { "clocks", "startup", "clipboard", "muted" })
    t.eq(first("clipboard history").arg, "clipboard")
end)

t.test("the switcher's mute key is Cmd+M, physical Ctrl+M as tide's", function()
    _G.hs = _G.hs or {}
    local hs_launcher = require("tilemo.launcher_hs")
    t.eq(hs_launcher.MUTE_KEY.key, "m")
    t.eq(table.concat(hs_launcher.MUTE_KEY.mods, "+"), "cmd")
end)

t.done("launcher")
