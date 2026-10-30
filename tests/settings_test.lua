local t = require("t")
local dashboard = require("tilemo.dashboard")

local DIR = "hammerspoon/tilemo/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

t.test("the clocks are in tide's settings folder, under XDG_CONFIG_HOME if set", function()
    local env = { HOME = "/Users/me" }
    local getenv = function(k)
        return env[k]
    end
    t.eq(dashboard.clock_dir(getenv), "/Users/me/.config/tide")
    env.XDG_CONFIG_HOME = "/Users/me/cfg"
    t.eq(dashboard.clock_dir(getenv), "/Users/me/cfg/tide")
end)

t.test("each clocks file is its text, and one that isn't there is left out", function()
    local files = { ["/c/tide/clocks.local.json"] = "[]" }
    local got = dashboard.clock_files("/c/tide", function(p)
        return files[p]
    end)
    t.eq(got, { ["local"] = "[]" })
end)

t.test("the settings page builds, and changes the clocks as tide's page does", function()
    local sources = {}
    for _, name in ipairs(dashboard.SETTINGS_MODULES) do
        sources[name] = read(name)
    end
    local html = dashboard.page(read("settings.html"), read("launcher.css"), sources, dashboard.SETTINGS_MODULES)
    t.eq(html:find("TILEMO_", 1, true), nil)
    t.eq(html:find('id="add-zone"', 1, true) ~= nil, true)
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TILEMO_NEED_NODE") then
            error("node is needed to check the settings page")
        end
        print("SKIP the settings page's changes: no node")
        return
    end
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(dashboard.bundle(sources, dashboard.SETTINGS_MODULES))
    f:close()
    local p = io.popen("TZ=Europe/Dublin node tests/settings_page.cjs " .. path .. " 2>&1")
    local out = p:read("a")
    local ok = p:close()
    os.remove(path)
    if not ok then
        error(out)
    end
end)

t.done("settings")
