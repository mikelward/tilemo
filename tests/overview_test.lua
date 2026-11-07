local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local overview = require("tide.overview")
local dashboard = require("tide.dashboard")

-- Windows 1-3 on "in", then 4 sent to "re" and 5 to "web", with "web"
-- showing at the end.
local function setup()
    local a = fake.new()
    a.add(1, { title = "Notes", name = "Notes", app = "com.apple.Notes" })
    a.add(2, { title = "Inbox", name = "Mail", app = "com.apple.mail" })
    a.add(3, { title = "~", name = "kitty", app = "net.kovidgoyal.kitty" })
    a.add(4, { title = "Chat", name = "Google Chat", app = "com.google.Chrome.app.chat" })
    a.add(5, { title = "Docs", name = "Chrome", app = "com.google.Chrome" })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 4
    wm:act("send", "re")
    a.focus_ = 5
    wm:act("send", "web")
    return a, wm
end

local function names(groups)
    local out = {}
    for i, g in ipairs(groups) do
        out[i] = g.name
    end
    return out
end

local function ids(group)
    local out = {}
    for i, w in ipairs(group.windows) do
        out[i] = w.id
    end
    return out
end

t.test("each workspace with windows is a group, the current one first, then the rest in bar order", function()
    local _, wm = setup()
    wm:show("web")
    local groups = overview.groups(wm)
    -- The bar lists "in", "re", "oc", "me", then "web"; "oc" and "me" have
    -- no windows, so no group.
    t.eq(names(groups), { "web", "in", "re" })
    t.eq(groups[1].current, true)
    t.eq(groups[2].current, false)
    t.eq(ids(groups[2]), { 1, 2, 3 })
    t.eq(groups[3].windows, { { id = 4, app = "Google Chat", bundle = "com.google.Chrome.app.chat", title = "Chat", mine = false } })
end)

t.test("a group's windows go in tile order on each display, then its floats", function()
    local a, wm = setup()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    wm:show("in")
    a.focus_ = 1
    -- A dialog on A, a float on "in".
    a.add(6, { subrole = "AXDialog", title = "Save", frame = { x = 0, y = 0, w = 400, h = 200 } })
    wm:sync()
    wm:retile()
    t.eq(wm.windows[6].floating, true)
    -- Window 2 to the second display, and window 1 moved down the stack.
    a.focus_ = 2
    wm:act("move_side", 1)
    t.eq(wm.windows[2].screen, "B")
    a.focus_ = 1
    wm:act("move", 1)
    t.eq(wm:part("in", "A").order, { 3, 1 })
    t.eq(ids(overview.groups(wm)[1]), { 3, 1, 6, 2 })
end)

t.test("a window you minimized is in its group, marked; one tide doesn't manage isn't", function()
    local a, wm = setup()
    a.add(7, { title = "Picture in Picture", frame = { x = 5, y = 5, w = 300, h = 200 } })
    wm:sync()
    wm:retile()
    a.focus_ = 2
    wm:act("minimize")
    local g = overview.groups(wm)[1]
    t.eq(g.name, "in")
    t.eq(ids(g), { 1, 2, 3 })
    t.eq(g.windows[2].mine, true)
    t.eq(g.windows[1].mine, false)
end)

t.test("the title is the window's now, and an app with no name shows its bundle's", function()
    local a, wm = setup()
    a.wins[1].title = "Notes — shopping"
    a.wins[3].name = nil
    wm.windows[3].name = nil
    a.app_names["net.kovidgoyal.kitty"] = "kitty"
    local w = overview.groups(wm)[1].windows
    t.eq(w[1].title, "Notes — shopping")
    t.eq(w[3].app, "kitty")
    a.app_names["net.kovidgoyal.kitty"] = nil
    t.eq(overview.groups(wm)[1].windows[3].app, "net.kovidgoyal.kitty")
end)

t.test("current_only is the current workspace alone, even empty", function()
    local _, wm = setup()
    wm:show("re")
    local groups = overview.groups(wm, true)
    t.eq(names(groups), { "re" })
    t.eq(ids(groups[1]), { 4 })
    wm:show("oc")
    groups = overview.groups(wm, true)
    t.eq(names(groups), { "oc" })
    t.eq(groups[1].windows, {})
    t.eq(names(overview.groups(wm)), { "in", "re", "web" }, "an empty current workspace has no group of every workspace")
end)

t.test("the state carries each app's icon once, by bundle, and the focused window", function()
    local a, wm = setup()
    a.add(8, { title = "Second note", name = "Notes", app = "com.apple.Notes" })
    wm:sync()
    wm:retile()
    a.focus_ = 1
    local asked = {}
    local st = overview.state(wm, "all", function(bundle)
        asked[#asked + 1] = bundle
        if bundle ~= "com.apple.mail" then
            return "data:" .. bundle
        end
    end, 1)
    t.eq(st.scope, "all")
    t.eq(st.focused, 1)
    t.eq(st.icons["com.apple.Notes"], "data:com.apple.Notes")
    t.eq(st.icons["com.apple.mail"], nil, "no icon, none sent")
    local notes = 0
    for _, b in ipairs(asked) do
        if b == "com.apple.Notes" then
            notes = notes + 1
        end
    end
    t.eq(notes, 1, "asked once")
    t.eq(#overview.state(wm, "current").groups, 1)
end)

t.test("Ctrl+Up and Ctrl+Down ask for the overview, of every workspace or this one", function()
    local _, wm = setup()
    local asked = {}
    wm.open_overview = function(scope)
        asked[#asked + 1] = scope
    end
    wm:act("overview", "all")
    wm:act("overview", "current")
    t.eq(asked, { "all", "current" })
    wm_mod.actions.overview({}, "all") -- before the overview exists: nothing, no error
end)

-- The page --------------------------------------------------------------

local DIR = "hammerspoon/tide/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

local function sources()
    local out = {}
    for _, name in ipairs(overview.MODULES) do
        out[name] = read(name)
    end
    return out
end

t.test("the page carries tileco's stylesheet and the script", function()
    local html = dashboard.page(read("overview.html"), read("launcher.css"), sources(), overview.MODULES)
    t.eq(html:find("TIDE_", 1, true), nil)
    t.eq(html:find("window.tide = {", 1, true) ~= nil, true)
    t.eq(html:find('modules["./fuzzy.mjs"]', 1, true) ~= nil, true, "tide's matcher, by tide's name too")
end)

t.test("the page draws the groups, filters, and sends choices back", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to check the overview page")
        end
        print("SKIP the overview page: no node")
        return
    end
    local js = dashboard.bundle(sources(), overview.MODULES)
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(js)
    f:close()
    local p = io.popen("node tests/overview_page.cjs " .. path .. " 2>&1")
    local out = p:read("a")
    local ok = p:close()
    os.remove(path)
    if not ok then
        error(out)
    end
end)

t.done("overview")
