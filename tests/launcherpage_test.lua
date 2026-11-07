local t = require("t")
local fake = require("fake")
local json = require("json")
local wm_mod = require("tide.wm")
local dashboard = require("tide.dashboard")
local launcher = require("tide.launcher")
local launcherpage = require("tide.launcherpage")

local DIR = "hammerspoon/tide/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

local function sources()
    local out = {}
    for _, name in ipairs(launcherpage.MODULES) do
        out[name] = read(name)
    end
    return out
end

t.test("start() keeps the chooser switcher unless it asks for the dashboard launcher", function()
    t.eq(launcherpage.front(nil), "chooser")
    t.eq(launcherpage.module_for(nil), "tide.launcher_hs")
    t.eq(launcherpage.module_for("chooser"), "tide.launcher_hs")
    t.eq(launcherpage.module_for("dashboard"), "tide.launcherpage_hs")
end)

t.test("any other launcher is an error at load, naming the setting", function()
    for _, bad in ipairs({ "spotlight", true, 1 }) do
        local ok, err = pcall(launcherpage.module_for, bad)
        t.eq(ok, false, tostring(bad))
        t.eq(tostring(err):find("launcher", 1, true) ~= nil, true, tostring(err))
        t.eq(tostring(err):find('"chooser" or "dashboard"', 1, true) ~= nil, true, tostring(err))
    end
end)

t.test("each switcher key opens the page on its scope", function()
    t.eq(launcherpage.page_scope("launch"), "launch")
    t.eq(launcherpage.page_scope("workspaces"), "workspaces")
    t.eq(launcherpage.page_scope("windows"), "tabs")
    t.eq(launcherpage.page_scope("attention"), "tabs")
    t.eq(launcherpage.page_scope("actions"), "actions")
    t.eq(launcherpage.page_scope(nil), "launch")
end)

-- The switcher's rows for a small desktop: two apps and a pane, a browser
-- tab, two windows, most recent first, and tide's commands.
local function rows()
    return launcher.items(
        { { name = "Safari", path = "/Applications/Safari.app" }, { name = "Notes", path = "/System/Applications/Notes.app" } },
        { { title = "Docs", url = "https://docs.example.com/a", browser = "Safari", window = 1, tab = 1, ws = "re" } },
        launcher.COMMANDS,
        { { name = "Mouse", id = "com.apple.Mouse-Settings.extension" } },
        {},
        { { name = "in" }, { name = "re" } },
        {
            { id = 2, title = "notes.txt", app_name = "TextEdit", bundle = "com.apple.TextEdit", ws = "in" },
            { id = 1, title = "", app_name = "Google Chrome", bundle = "com.google.Chrome", ws = "re" },
        }
    )
end

local function feed(opts)
    return launcherpage.feed(rows(), opts)
end

t.test("windows and browser tabs are the page's tabs, windows most recent first", function()
    local f = feed()
    t.eq(#f.tabs, 3)
    t.eq(f.tabs[1].id, "window:2")
    t.eq(f.tabs[1].title, "notes.txt")
    t.eq(f.tabs[1].url, "tide-window://textedit/")
    t.eq(f.tabs[2].title, "Google Chrome", "a window with no title goes by its app")
    t.eq(f.tabs[2].url, "tide-window://google-chrome/")
    t.eq(f.tabs[3].url, "https://docs.example.com/a")
    t.eq(f.tabs[1].lastAccessed > f.tabs[2].lastAccessed, true)
    t.eq(f.tabs[2].lastAccessed > f.tabs[3].lastAccessed, true)
    t.eq(f.state.windows["window:2"], { ws = "in" })
    t.eq(f.state.windows[f.tabs[3].id], { ws = "re" })
end)

t.test("apps and panes are the page's apps, most recently used first", function()
    local f = feed({ recency = { ["app:/System/Applications/Notes.app"] = 10 } })
    local names = {}
    for i, a in ipairs(f.apps) do
        names[i] = a.name
    end
    -- Tide Settings is the page's own row.
    t.eq(names, { "Notes", "Safari", "Mouse settings" })
    t.eq(f.apps[1].command, "row:app:/System/Applications/Notes.app")
end)

t.test("the app scripts are the page's apps too", function()
    local scripts = launcher.parse_scripts("google-meet|Google Meet|camera-web|com.google.Chrome\n")
    local commands = launcher.with_scripts(launcher.COMMANDS, scripts, function(run)
        return run == "google-meet"
    end)
    local f = launcherpage.feed(launcher.items({}, {}, commands, {}))
    t.eq(f.apps, { { name = "Google Meet", command = "row:command:script:google-meet" } }, "not Tide Settings")
end)

t.test("the Actions tab's rows are the page's actions, in order, with keep awake on or off", function()
    local f = feed({ keep_awake = true })
    t.eq(f.actions[1], { kind = "action", title = "Lock", detail = "", key = "", command = "row:command:Lock" })
    local by = {}
    for i, a in ipairs(f.actions) do
        by[a.title] = i
    end
    t.eq(by["Log out"], 2)
    t.eq(f.actions[by["Keep awake"]].detail, "on")
    t.eq(feed().actions[by["Keep awake"]].detail, "off")
end)

t.test("the other commands are the manifest's, with Super+G for the browser and no Tide Settings rows", function()
    local f = feed()
    t.eq(f.commands[1], { name = "app-browser", description = "Browser window (Super+G)" })
    local titles = {}
    for _, c in ipairs(f.commands) do
        titles[#titles + 1] = c.description
        t.eq(c.description:find("Tide Settings", 1, true), nil, c.description)
    end
    t.eq(titles[2], "Layout: tile ()")
    t.eq(#f.sections, #launcher.SETTINGS_SECTIONS)
    t.eq(f.sections[1], { id = "displays", name = "Displays", covers = launcher.SETTINGS_SECTIONS[1].covers })
end)

t.test("the view is the bar's workspaces as seen from the display it's on", function()
    local a = fake.new()
    a.add(1, {})
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    wm:act("send", "web")
    local v = launcherpage.view(wm, "A")
    t.eq(v.bar[1], "in")
    t.eq(v.bar[#v.bar], "web")
    t.eq(v.counts, { ["in"] = 1, web = 1 })
    t.eq(v.made, { "in", "web" })
    t.eq(v.focusedDisplay, "A")
    t.eq(v.displays.A.workspace, "in")
    t.eq(v.displays.A.mode, wm:part("in", "A").mode)
end)

t.test("each message from the page says what to do", function()
    local m = launcherpage.message
    t.eq(m({ tabId = "window:2", windowId = "window:2" }), { kind = "row", value = "window:2" })
    t.eq(m({ command = "row:command:Lock" }), { kind = "row", value = "command:Lock" })
    t.eq(m({ command = "keep-awake" }), { kind = "keep_awake" })
    t.eq(m({ command = "app-browser" }), { kind = "browser" })
    t.eq(m({ command = "tile" }), { kind = "unknown", value = "command tile" })
    t.eq(m({ workspace = "web" }), { kind = "workspace", value = "web" })
    t.eq(m({ settings = "clocks" }), { kind = "settings", value = "clocks" })
    t.eq(m({ settings = true }), { kind = "settings" })
    t.eq(m({ close = true }), { kind = "close" })
    t.eq(m({ reload = true }), { kind = "reload" })
    t.eq(m({ clockErrors = { "x" } }), { kind = "clock_errors", value = { "x" } })
    t.eq(m({ dim = true }), { kind = "unknown", value = "dim" })
end)

t.test("the page bundles tileco's launcher with tide's stand-ins in place of its settings and launcher", function()
    local js = dashboard.bundle(sources(), launcherpage.MODULES)
    t.eq(js:find('modules["./settings.js"] = modules["./launcher-settings.js"];', 1, true) ~= nil, true)
    t.eq(js:find('modules["./launcher.js"] = modules["./launcher-lists.js"];', 1, true) ~= nil, true)
    local html = dashboard.page(read("launcherpage.html"), read("launcher.css"), sources(), launcherpage.MODULES)
    t.eq(html:find("/*TIDE_", 1, true), nil)
    t.eq(html:find('data-scope="actions"', 1, true) ~= nil, true)
end)

t.test("the page lists, searches and chooses tide's rows", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to check the dashboard launcher's page")
        end
        print("SKIP the page lists, searches and chooses tide's rows: no node")
        return
    end
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local f = feed({ recency = { ["app:/System/Applications/Notes.app"] = 10 }, view = launcherpage.view(wm, "A") })
    local js_path, feed_path = os.tmpname(), os.tmpname()
    local out = assert(io.open(js_path, "w"))
    out:write(dashboard.bundle(sources(), launcherpage.MODULES))
    out:close()
    out = assert(io.open(feed_path, "w"))
    out:write(json.encode(f))
    out:close()
    local p = io.popen("TZ=Europe/Dublin node tests/launcherpage_page.cjs " .. js_path .. " " .. feed_path .. " 2>&1")
    local said = p:read("a")
    local ok = p:close()
    os.remove(js_path)
    os.remove(feed_path)
    if not ok then
        error(said)
    end
end)

t.test("the launcher chosen in settings wins over start()'s, which is the default until then", function()
    t.eq(launcherpage.choose(nil, nil), "chooser")
    t.eq(launcherpage.choose(nil, "dashboard"), "dashboard")
    t.eq(launcherpage.choose("dashboard", "chooser"), "dashboard")
    t.eq(launcherpage.choose("chooser", "dashboard"), "chooser")
end)

t.test("a stored launcher that isn't one is left out, and said", function()
    local said = {}
    t.eq(launcherpage.choose("raycast", "dashboard", function(text)
        said[#said + 1] = text
    end), "dashboard")
    t.eq(#said, 1)
    t.eq(said[1]:find("raycast", 1, true) ~= nil, true, said[1])
    -- start()'s own value is still checked.
    t.eq(pcall(launcherpage.choose, "raycast", "spotlight"), false)
end)

t.test("each launcher has its name for the settings window", function()
    for value in pairs(launcherpage.MODULE) do
        t.eq(type(launcherpage.LABELS[value]), "string", value)
    end
end)

t.test("the page says whether there's anything in the search", function()
    t.eq(launcherpage.message({ typed = true }), { kind = "typed", value = true })
    t.eq(launcherpage.message({ typed = false }), { kind = "typed", value = false })
end)

t.test("the launcher page is a panel about tide's switcher's size, not the whole display", function()
    t.eq(launcherpage.frame({ x = 0, y = 0, w = 1512, h = 982 }), { x = 392, y = 127, w = 728, h = 600 })
    t.eq(launcherpage.frame({ x = 1512, y = -200, w = 1920, h = 1080 }), { x = 2108, y = -40, w = 728, h = 600 },
        "on its own display, wherever that is")
    t.eq(launcherpage.frame({ x = 0, y = 0, w = 640, h = 480 }), { x = 20, y = 26, w = 600, h = 400 },
        "kept on a small display")
end)

t.done("launcherpage")
