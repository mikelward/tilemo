local t = require("t")
local launcher = require("tide.launcher")

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

t.test("a match is scored from its best start, not the first matching letter", function()
    -- Greedy from the S of System, "settings" missed the run in Settings.
    t.eq(launcher.score("settings", "System Settings"), launcher.score("settings", "Appearance settings"))
end)

t.test("System Settings comes first for \"settings\", ahead of its panes", function()
    local panes = {}
    for _, n in ipairs({ "Appearance", "Battery", "General", "Keyboard", "Privacy & Security" }) do
        panes[#panes + 1] = { name = n, id = n }
    end
    local items = launcher.items({ { name = "System Settings", path = "/System/Applications/System Settings.app" } }, {}, {}, panes, {}, {}, {})
    local first = launcher.rank("settings", items, { scope = "launch" })[1]
    t.eq(first.title, "System Settings", "an app before panes that match as well")
end)

t.test("equal matches sort the same way whatever their recency, commands included", function()
    -- An app, a pane and a command that "settings" matches equally, used in
    -- an order that made the old pairwise rule go round in a circle.
    local items = {
        { kind = "app", title = "System Settings", key = "a" },
        { kind = "setting", title = "Mouse settings", key = "p" },
        { kind = "command", title = "Tide Settings: Clocks", key = "c" },
    }
    local recency = { a = 1, p = 3, c = 2 }
    local order = {}
    for _, r in ipairs(launcher.rank("settings", items, { scope = "launch", recency = recency })) do
        order[#order + 1] = r.title
    end
    t.eq(order[#order], "Mouse settings", "the pane last, after both")
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

t.test("Tab moves through Launch, Workspaces, Windows, Attention and Actions, and round again; Shift+Tab goes back", function()
    t.eq(launcher.SCOPE_ORDER, { "launch", "workspaces", "windows", "attention", "actions" })
    t.eq(launcher.next_scope("launch"), "workspaces")
    t.eq(launcher.next_scope("workspaces"), "windows")
    t.eq(launcher.next_scope("windows"), "attention")
    t.eq(launcher.next_scope("attention"), "actions")
    t.eq(launcher.next_scope("actions"), "launch")
    t.eq(launcher.next_scope("launch", true), "actions")
    t.eq(launcher.next_scope("workspaces", true), "launch")
end)

t.test("the search field names the scope, what it lists, where Tab goes, and the tab's own keys", function()
    t.eq(launcher.placeholder("launch"),
        "Launch: apps, settings and commands (Tab: Workspaces, Cmd+Return: new workspace)")
    t.eq(launcher.placeholder("workspaces"), "Workspaces: every workspace (Tab: Windows)")
    t.eq(launcher.placeholder("windows"),
        "Windows: every window, and Chrome and Safari tabs (Tab: Attention, Cmd+M: mute)")
    t.eq(launcher.placeholder("attention"), "Attention: windows wanting attention (Tab: Actions, Cmd+M: mute)")
    t.eq(launcher.placeholder("actions"), "Actions: session, power, toggles and screenshots (Tab: Launch)")
end)

t.test("the hint offers Cmd+Return only on Launch and Cmd+M only where a row can be muted", function()
    for _, scope in ipairs(launcher.SCOPE_ORDER) do
        local hint = launcher.placeholder(scope)
        t.eq(hint:find("Cmd+Return", 1, true) ~= nil, scope == "launch", scope)
        t.eq(hint:find("Cmd+M:", 1, true) ~= nil, scope == "windows" or scope == "attention", scope)
    end
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
    local wm = require("tide.wm")
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
        { id = 3, title = "", app_name = "kitty", ws = "tide" },
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
    t.eq(found[2].ws, "tide")
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

t.test("a tab finds its tide window by its browser and its window's name, if just one has it", function()
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

t.test("each settings section has its own row, found by its name or what it covers, opening the window there", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {})
    local function first(q)
        return launcher.rank(q, items, { scope = "launch" })[1]
    end
    t.eq(first("start at login").title, "Tide Settings: Start at login")
    t.eq(first("start at login").arg, "startup")
    t.eq(first("clocks").arg, "clocks")
    t.eq(first("muted").arg, "muted")
    t.eq(first("floating").arg, "floating")
    t.eq(first("layouts").arg, "layouts")
    t.eq(first("clipboard history").arg, "clipboard")
    t.eq(first("left-handed").arg, "mouse", "by what it covers")
    t.eq(first("time zones").arg, "clocks", "by what it covers")
    t.eq(launcher.subtitle(first("clocks")), "Tide Settings")
    -- One row per section of the settings window, in its order.
    local sections = {}
    for _, c in ipairs(launcher.COMMANDS) do
        if c.action == "settings" and c.arg then
            sections[#sections + 1] = c.arg
        end
    end
    local want = {}
    for _, sec in ipairs(launcher.SETTINGS_SECTIONS) do
        want[#want + 1] = sec.id
    end
    t.eq(sections, want)
end)

t.test("each settings section is one the settings window has", function()
    local f = assert(io.open("hammerspoon/tide/dashboard/settings.html"))
    local html = f:read("a")
    f:close()
    -- Each page's markup, from its section to the next.
    local pages = {}
    for id, body in html:gmatch('<section class="page" id="page%-([%w-]+)"[^>]*>(.-)</section>') do
        pages[id] = body
    end
    for _, sec in ipairs(launcher.SETTINGS_SECTIONS) do
        local page = pages[sec.page or sec.id]
        t.eq(page ~= nil, true, "a page for " .. sec.id)
        t.eq((page or ""):find('id="' .. sec.id .. '"', 1, true) ~= nil, true, sec.id .. " on its page")
    end
end)

t.test("the settings sidebar groups the pages under tide's headings", function()
    local sidebar = launcher.settings_sidebar()
    local shown = {}
    for _, row in ipairs(sidebar.rows) do
        shown[#shown + 1] = row.heading and row.heading:upper() or row.label
    end
    t.eq(shown, {
        "HARDWARE", "Displays", "Sound", "Network", "Bluetooth", "Mouse", "Trackpad", "Keyboard", "Power",
        "WINDOWS", "Layouts", "Workspaces", "Floating",
        "GENERAL", "Appearance", "Notifications", "Clipboard", "Clocks", "Idle", "Start at login", "Setup checklist",
    })
    t.eq(sidebar.parts, { shortcuts = "keyboard" })
end)

t.test("the sidebar's pages are the window's, in its order", function()
    -- A page left out of every group, or a group's pages apart, would show
    -- in the sidebar out of the window's order, or not at all.
    local window = {}
    for _, sec in ipairs(launcher.SETTINGS_SECTIONS) do
        if not sec.page then
            window[#window + 1] = sec.id
        end
    end
    local sidebar = {}
    for _, row in ipairs(launcher.settings_sidebar().rows) do
        if row.page then
            sidebar[#sidebar + 1] = row.page
        end
    end
    t.eq(sidebar, window)
end)

t.test("a settings section keeps the use remembered under its old title", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {})
    local keys = {}
    for _, item in ipairs(items) do
        keys[item.key] = item.arg
    end
    t.eq(keys["command:Settings: clocks"], "clocks")
    t.eq(keys["command:Settings: start at login"], "startup")
    -- Network had Bluetooth with it.
    t.eq(keys["command:Tide Settings: Network and Bluetooth"], "network")
end)

t.test("Network and Bluetooth are each found as their own page", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {})
    t.eq(launcher.rank("wi-fi", items, { scope = "launch" })[1].title, "Tide Settings: Network")
    t.eq(launcher.rank("bluetooth", items, { scope = "launch" })[1].title, "Tide Settings: Bluetooth")
end)

t.test("Tide Settings is an app on Launch, with nothing typed, opening tide's settings window", function()
    local items = launcher.items({ { name = "Safari", path = "/Applications/Safari.app" } }, {}, launcher.COMMANDS, {})
    local found = launcher.rank("", items, { scope = "launch" })
    local row
    for _, item in ipairs(found) do
        if item.title == "Tide Settings" then
            row = item
        end
        t.eq(item.sub ~= "Tide Settings", true, "no section row without a query: " .. item.title)
    end
    t.eq(row.kind, "app")
    t.eq(row.action, "settings")
    t.eq(row.arg, nil)
    t.eq(row.path, nil, "launcher_hs runs it as a window manager action")
    t.eq(launcher.rank("tide settings", items, { scope = "launch" })[1].title, "Tide Settings")
end)

t.test("the Actions tab lists every session, power and toggle action, with nothing typed, in order", function()
    local items = launcher.items({ { name = "Safari", path = "/Applications/Safari.app" } }, {}, launcher.COMMANDS, {})
    local titles = {}
    for _, item in ipairs(launcher.rank("", items, { scope = "actions" })) do
        t.eq(item.kind, "action", item.title)
        titles[#titles + 1] = item.title
    end
    t.eq(titles[1], "Lock")
    t.eq(titles[2], "Log out")
    local has = {}
    for _, title in ipairs(titles) do
        has[title] = true
    end
    for _, want in ipairs({ "Sleep", "Restart", "Shut down", "Reload tide", "Keep awake", "Do Not Disturb", "Dark style",
        "Presenter mode: Do Not Disturb and keep awake", "Screenshot: region" }) do
        t.eq(has[want], true, want)
    end
end)

t.test("Launch with nothing typed lists no actions, but a query there still finds one", function()
    local items = launcher.items({ { name = "Safari", path = "/Applications/Safari.app" } }, {}, launcher.COMMANDS, {})
    for _, item in ipairs(launcher.rank("", items, { scope = "launch" })) do
        t.eq(item.kind ~= "action", true, item.title)
    end
    t.eq(launcher.rank("shut down", items, { scope = "launch" })[1].title, "Shut down")
    t.eq(launcher.rank("restart", items, { scope = "actions" })[1].title, "Restart")
end)

t.test("the switcher's mute key is Cmd+M, physical Ctrl+M as tide's", function()
    _G.hs = _G.hs or {}
    local hs_launcher = require("tide.launcher_hs")
    t.eq(hs_launcher.MUTE_KEY.key, "m")
    t.eq(table.concat(hs_launcher.MUTE_KEY.mods, "+"), "cmd")
end)

local function joined(runs)
    local out = {}
    for _, r in ipairs(runs) do
        out[#out + 1] = r.matched and "[" .. r.text .. "]" or r.text
    end
    return table.concat(out)
end

t.test("a query's matched characters are marked where the score found them", function()
    t.eq(joined(launcher.marks("gc", "Google Calendar")), "[G]oogle [C]alendar")
    t.eq(joined(launcher.marks("saf", "Safari")), "[Saf]ari")
end)

t.test("no marks for an empty query or a title that doesn't match", function()
    t.eq(joined(launcher.marks("", "Safari")), "Safari")
    t.eq(joined(launcher.marks("zx", "Safari")), "Safari")
    -- Matched by a tab's host, not its title.
    t.eq(joined(launcher.marks("chat.google", "Inbox")), "Inbox")
end)

t.test("marks never split a multibyte character", function()
    local runs = launcher.marks("ce", "Café Ce")
    t.eq(joined(runs), "[C]af\xc3\xa9 C[e]")
    for _, r in ipairs(runs) do
        t.eq(utf8.len(r.text) ~= nil, true, r.text)
    end
end)

local function command(title)
    for _, item in ipairs(launcher.items({}, {}, launcher.COMMANDS, {})) do
        if item.title == title then
            return item
        end
    end
    error("no command " .. title)
end

t.test("a row's key hint is the key that does the same", function()
    t.eq(launcher.key_hint(command("Lock")), "Super+L")
    t.eq(launcher.key_hint(command("Log out")), "Super+Shift+E")
    t.eq(launcher.key_hint(command("Keep awake")), "Super+S")
    t.eq(launcher.key_hint(command("Float or tile the window")), "Super+Shift+F")
    t.eq(launcher.key_hint(command("Screenshot: region")), "Shift+Print")
    t.eq(launcher.key_hint(command("Screenshot: window")), "Alt+Print")
end)

t.test("rows with no key of their own have no hint", function()
    t.eq(launcher.key_hint(command("Sleep")), nil)
    t.eq(launcher.key_hint(command("Layout: tile")), nil)
    t.eq(launcher.key_hint(command("Tide Settings")), nil)
    t.eq(launcher.key_hint({ kind = "app", title = "Safari", path = "/Applications/Safari.app" }), nil)
end)

t.test("every row's icon says where it comes from", function()
    local items = launcher.items(
        { { name = "Safari", path = "/Applications/Safari.app" } },
        { { title = "Docs", url = "https://example.com/", browser = "Google Chrome", window = 1, tab = 1 } },
        launcher.COMMANDS,
        { { name = "Mouse", id = "com.apple.Mouse-Settings.extension" } },
        { { title = "Chat", app = "Chrome", bundle = "com.google.Chrome", window = 7 } },
        { { name = "in", apps = "Chrome" } },
        { { id = 3, title = "Notes", app_name = "Notes", bundle = "com.apple.Notes" } }
    )
    local by = {}
    for _, item in ipairs(items) do
        by[item.title] = item
    end
    t.eq(launcher.icon(by["Safari"]).path, "/Applications/Safari.app")
    t.eq(launcher.icon(by["Docs"]).bundle, "com.google.Chrome")
    t.eq(launcher.icon(by["Mouse settings"]).bundle, "com.apple.systempreferences")
    t.eq(launcher.icon(by["Chat"]).bundle, "com.google.Chrome")
    t.eq(launcher.icon(by["Notes"]).bundle, "com.apple.Notes")
    t.eq(launcher.icon(by["in"]).name, "NSMultipleDocuments")
    t.eq(launcher.icon(by["Tide Settings"]).logo, true)
    t.eq(launcher.icon(by["Tide Settings: Mouse"]).logo, true)
    t.eq(launcher.icon(by["Lock"]).name, "NSLockLockedTemplate")
    t.eq(launcher.icon(by["Screenshot: screen"]).bundle, "com.apple.screenshot.launcher")
    t.eq(launcher.icon(by["Keep awake"]).logo, true)
    for _, item in ipairs(items) do
        t.eq(launcher.icon_key(launcher.icon(item)) ~= nil, true, item.title)
    end
end)

local function headers(rows)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = r.header and "# " .. r.header or r.item.title
    end
    return table.concat(out, " | ")
end

t.test("Launch with nothing typed: Recent, then each kind under its own header", function()
    local items = launcher.items(
        { { name = "Safari", path = "/a/Safari.app" }, { name = "Notes", path = "/a/Notes.app" } },
        {},
        { { title = "Tide Settings", as = "app", action = "settings", logo = true }, { title = "Monocle", action = "monocle" } },
        { { name = "Mouse", id = "m" } }
    )
    local recency = { ["app:/a/Notes.app"] = 5, ["command:Monocle"] = 9 }
    local found = launcher.rank("", items, { scope = "launch", recency = recency })
    local rows = launcher.sections("launch", "", found, recency)
    t.eq(headers(rows), "# Recent | Monocle | Notes | # Apps | Safari | Tide Settings | # System Settings | Mouse settings")
    t.eq(launcher.first_row(rows), 2)
end)

t.test("Recent comes from every Launch row, not just the first M.LIMITS.launch", function()
    local apps = {}
    for i = 1, 30 do
        apps[i] = { name = string.format("App%02d", i), path = "/a/" .. i .. ".app" }
    end
    local items = launcher.items(apps, {}, { { title = "Monocle", action = "monocle" } })
    local recency = { ["command:Monocle"] = 9 }
    local rows = launcher.rows("launch", "", items, recency)
    t.eq(rows[1].header, "Recent")
    t.eq(rows[2].item.title, "Monocle")
    -- The rest are still capped.
    local n = 0
    for _, r in ipairs(rows) do
        if r.item then
            n = n + 1
        end
    end
    t.eq(n, 1 + launcher.LIMITS.launch)
end)

t.test("Launch never shows more than M.RECENT under Recent", function()
    local apps, recency = {}, {}
    for i = 1, 8 do
        apps[i] = { name = "App" .. i, path = "/a/" .. i .. ".app" }
        recency["app:/a/" .. i .. ".app"] = i
    end
    local items = launcher.items(apps)
    local rows = launcher.sections("launch", "", launcher.rank("", items, { scope = "launch", recency = recency }), recency)
    t.eq(headers(rows), "# Recent | App8 | App7 | App6 | App5 | App4 | # Apps | App3 | App2 | App1")
end)

t.test("Actions with nothing typed are grouped: Session, tide, Toggles, Screenshots", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {})
    local rows = launcher.sections("actions", "", launcher.rank("", items, { scope = "actions" }))
    local seen = {}
    for _, r in ipairs(rows) do
        if r.header then
            seen[#seen + 1] = r.header
        end
    end
    t.eq(table.concat(seen, ", "), "Session, tide, Toggles, Screenshots")
    t.eq(rows[1].header, "Session")
    t.eq(rows[2].item.title, "Lock")
    t.eq(launcher.first_row(rows), 2)
end)

t.test("a typed query, and the other tabs, get no headers", function()
    local items = launcher.items({ { name = "Safari", path = "/a/Safari.app" } }, {}, launcher.COMMANDS, {})
    local rows = launcher.sections("launch", "saf", launcher.rank("saf", items, { scope = "launch" }), {})
    t.eq(rows[1].item.title, "Safari")
    t.eq(launcher.first_row(rows), 1)
    local acts = launcher.sections("actions", "lock", launcher.rank("lock", items, { scope = "actions" }))
    t.eq(acts[1].item.title, "Lock")
    t.eq(launcher.first_row(launcher.sections("windows", "", {})), 1)
end)

t.test("tide's look has a dark and a light palette", function()
    t.eq(launcher.look(true).accent.hex, "#78aeed")
    t.eq(launcher.look(false).accent.hex, "#1c71d8")
    t.eq(launcher.look(true).fg.white > launcher.look(false).fg.white, true)
end)

local SCRIPTS = launcher.parse_scripts(table.concat({
    "# SCRIPT|NAME|ICON|MAC",
    "gmail|Gmail|mail-unread-symbolic|com.google.Chrome",
    "google-chat|Google Chat|chat-symbolic|com.google.Chrome",
    "google-meet|Google Meet|camera-web|com.google.Chrome",
    "irc|IRC|io.github.Hexchat|-",
    "bluetooth-connect|Connect the headphones|audio-headphones|linux",
    "",
}, "\n"))

t.test("scripts' list of app scripts skips comments, blanks, Linux-only and bad lines", function()
    t.eq(SCRIPTS, {
        { run = "gmail", name = "Gmail", bundle = "com.google.Chrome" },
        { run = "google-chat", name = "Google Chat", bundle = "com.google.Chrome" },
        { run = "google-meet", name = "Google Meet", bundle = "com.google.Chrome" },
        { run = "irc", name = "IRC" },
    })
    t.eq(launcher.parse_scripts("notepad|Notepad|x\nhome|Home|user-home|com.apple.finder|extra\n"), {}, "not four fields")
    t.eq(launcher.parse_scripts(nil), {})
end)

t.test("the app scripts in ~/scripts are apps, found by name and run as their keys run them", function()
    local have = { ["google-meet"] = true, ["google-chat"] = true, gmail = true, ["some-tool"] = true }
    local commands = launcher.with_scripts(launcher.COMMANDS, SCRIPTS, function(run)
        return have[run] == true
    end)
    t.eq(#commands, #launcher.COMMANDS + 3, "only the listed scripts that are there")
    local items = launcher.items({}, {}, commands, {})
    local function first(q)
        return launcher.rank(q, items, { scope = "launch" })[1]
    end
    local meet = first("meet")
    t.eq(meet.title, "Google Meet")
    t.eq(meet.kind, "app", "listed among the apps")
    t.eq(meet.action, "app")
    t.eq(meet.arg, { run = "google-meet" })
    t.eq(launcher.icon(meet), { bundle = "com.google.Chrome" }, "the list's Mac app's icon")
    t.eq(first("google-meet").title, "Google Meet", "by the script's own name too")
    t.eq(first("gmail").title, "Gmail")
    local chat = first("google chat")
    t.eq(chat.arg.home_app, true, "Google Chat runs as its key does, from the home workspace")
    local irc = launcher.items({}, {}, launcher.with_scripts({}, SCRIPTS, function(run)
        return run == "irc"
    end), {})[1]
    t.eq(launcher.icon(irc), nil, "- shows no app's icon")
end)

t.done("launcher")
