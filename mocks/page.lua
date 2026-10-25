-- Writes the bar's page, as timo builds it, to stdout, for mocks/render.cjs.

local dashboard = require("timo.dashboard")

local DIR = "hammerspoon/timo/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("mocks: can't read " .. DIR .. name .. ": " .. tostring(err))
    end
    local s = f:read("a")
    f:close()
    return s
end

local sources = {}
for _, name in ipairs(dashboard.BAR_MODULES) do
    sources[name] = read(name)
end
io.write(dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES))
