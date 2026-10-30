local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local dashboard = require("tilemo.dashboard")

local DIR = "hammerspoon/tilemo/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

local function sources()
    local out = {}
    for _, name in ipairs(dashboard.MODULES) do
        out[name] = read(name)
    end
    return out
end

t.test("each module gets its own scope, with its imports and exports wired", function()
    local s = sources()
    s["clocks.js"] = 'const DAY = 1;\nexport function a() { return DAY; }\nexport const B = 2;\n'
    s["calendar.js"] = 'const DAY = 3;\nexport async function c() {}\n'
    local js = dashboard.bundle(s)
    t.eq(js:find('modules["./clocks.js"] = (() => {', 1, true) ~= nil, true)
    t.eq(js:find("return { a, B };", 1, true) ~= nil, true)
    t.eq(js:find("return { c };", 1, true) ~= nil, true)
    t.eq(js:find("export ", 1, true), nil)
    t.eq(js:find('const { DAY, DEFAULT_CLOCKS, WORK, abbreviation, checkZone } = modules["./clocks.js"];', 1, true) ~= nil,
        true)
end)

t.test("an import renamed with as becomes a renamed binding", function()
    local s = sources()
    s["dashboard.js"] = 'import { today as now } from "./clockview.js";\n'
    t.eq(dashboard.bundle(s):find('const { today: now } = modules["./clockview.js"];', 1, true) ~= nil, true)
end)

t.test("a missing module or an import it can't read is an error at load", function()
    local s = sources()
    s["calendar.js"] = nil
    t.eq(pcall(dashboard.bundle, s), false)
    s = sources()
    s["dashboard.js"] = 'import * as x from "./clocks.js";\n'
    local ok, err = pcall(dashboard.bundle, s)
    t.eq(ok, false)
    t.eq(tostring(err):find("dashboard.js", 1, true) ~= nil, true)
end)

t.test("the page carries tileco's stylesheet and the script", function()
    local html = dashboard.page(read("dashboard.html"), read("launcher.css"), sources())
    t.eq(html:find("TILEMO_", 1, true), nil)
    t.eq(html:find("#clock-detail", 1, true) ~= nil, true)
    t.eq(html:find("window.tilemo = {", 1, true) ~= nil, true)
end)

t.test("the page draws the bar and the clock panel", function()
    local node = io.popen("command -v node"):read("l")
    if not node then
        -- CI sets TILEMO_NEED_NODE, so this only skips on a machine without it.
        if os.getenv("TILEMO_NEED_NODE") then
            error("node is needed to check the dashboard page")
        end
        print("SKIP the page draws the bar and the clock panel: no node")
        return
    end
    local js = dashboard.bundle(sources())
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(js)
    f:close()
    local p = io.popen("TZ=Europe/Dublin node tests/dashboard_page.cjs " .. path .. " 2>&1")
    local out = p:read("a")
    local ok = p:close()
    os.remove(path)
    if not ok then
        error(out)
    end
end)

t.test("the state is the menu bar's, with the focused window's title", function()
    local a = fake.new()
    a.add(1, { title = "Notes" })
    a.add(2, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    wm:act("send", 4)
    a.focus_ = 2
    a.wins[2].title = "Chat (1)"
    local st = dashboard.state(wm, a)
    t.eq(#st.workspaces, 9)
    t.eq(st.workspaces[1], { n = 1, current = true, elsewhere = false, occupied = true, urgent = false })
    t.eq(st.workspaces[4].occupied, true)
    t.eq(st.title, "Chat (1)")
end)

t.test("a dashboard opened on one display marks that display's workspace current", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    a.focus_ = 1
    -- The keys are on A, showing 1; the dashboard opened from B's clocks.
    t.eq(wm:current_screen(), "A")
    local st = dashboard.state(wm, a, "B")
    t.eq(st.workspaces[2].current, true)
    t.eq(st.workspaces[1].current, false)
    t.eq(st.workspaces[1].elsewhere, true)
end)

t.test("the dashboard's state carries the clocks kept while a file is wrong", function()
    local a = fake.new()
    local wm = wm_mod.new(a, {})
    wm:sync()
    local good = { { zone = "Asia/Tokyo", label = "TYO" } }
    t.eq(dashboard.state(wm, a, "A", { ["local"] = "[{" }, good).goodClocks, good)
    t.eq(dashboard.state(wm, a, "A").goodClocks, nil)
end)

t.test("Super+Shift+Space asks for the dashboard", function()
    local a = fake.new()
    local wm = wm_mod.new(a, {})
    local opened = false
    wm.open_dashboard = function()
        opened = true
    end
    wm:act("dashboard")
    t.eq(opened, true)
end)

t.done("dashboard")
