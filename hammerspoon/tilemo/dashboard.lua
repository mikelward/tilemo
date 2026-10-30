-- The dashboard (SPEC.md §8): tileco's bar and clock panel, full screen on a
-- key, in an hs.webview. The page is tileco's own modules, copied unchanged
-- into dashboard/, tide's clocks module (tide-clocks.js, its
-- shell/lib/clocks.mjs, also unchanged), plus tilemo's settings and page
-- script. A webview can't load ES modules from files, so bundle() joins them
-- into one script, each module in its own scope. Pure Lua; dashboard_hs.lua
-- shows it.

local M = {}

-- In the order they're needed: each module only imports ones before it.
M.MODULES = { "clocks.js", "calendar.js", "tide-clocks.js", "settings.js", "clockview.js", "dashboard.js" }
-- The bar's page (bar_hs.lua) is built the same way, from the same files.
M.BAR_MODULES = { "clocks.js", "calendar.js", "tide-clocks.js", "settings.js", "clockview.js", "bar.js" }
-- And the settings page (settings_hs.lua).
M.SETTINGS_MODULES = { "clocks.js", "tide-clocks.js", "settings.js", "settings-page.js" }

-- tide's settings folder (tide SPEC.md §16.1), where the clocks are, from
-- `getenv`, as os.getenv.
function M.clock_dir(getenv)
    local base = getenv("XDG_CONFIG_HOME")
    if not base or base == "" then
        base = (getenv("HOME") or "") .. "/.config"
    end
    return base .. "/tide"
end

-- The two clocks files' texts, for the pages: `read(path)` gives a file's
-- text, or nil when there's none, which leaves it out.
function M.clock_files(dir, read)
    return { shared = read(dir .. "/clocks.json"), ["local"] = read(dir .. "/clocks.local.json") }
end

M.LOCAL_FILE = "clocks.local.json"

-- One module's source as a function that registers what it exports.
local function wrap(name, src)
    local exports = {}
    -- import { a, b as c } from "./x.js";  ->  const { a, b: c } = modules["./x.js"];
    src = src:gsub('import%s*(%b{})%s*from%s*"([^"]+)";?', function(names, from)
        return "const " .. names:gsub("%s+as%s+", ": ") .. ' = modules["' .. from .. '"];'
    end)
    if src:find("%f[%w]import%s") then
        error("tilemo: dashboard/" .. name .. " has an import bundle() can't read")
    end
    src = src:gsub("export%s+(async%s+function%s+)([%w_$]+)", function(kw, n)
        exports[#exports + 1] = n
        return kw .. n
    end)
    src = src:gsub("export%s+(function%s*%*?%s*)([%w_$]+)", function(kw, n)
        exports[#exports + 1] = n
        return kw .. n
    end)
    src = src:gsub("export%s+const%s+([%w_$]+)", function(n)
        exports[#exports + 1] = n
        return "const " .. n
    end)
    src = src:gsub("export%s+let%s+([%w_$]+)", function(n)
        exports[#exports + 1] = n
        return "let " .. n
    end)
    if src:find("%f[%w]export%f[%W]") then
        error("tilemo: dashboard/" .. name .. " has an export bundle() can't read")
    end
    return string.format('modules["./%s"] = (() => {\n%s\nreturn { %s };\n})();\n',
        name, src, table.concat(exports, ", "))
end

-- `sources` maps a module's file name to its text; `modules` lists them in
-- order, the dashboard's by default.
function M.bundle(sources, modules)
    local out = { '"use strict";\nconst modules = {};\n' }
    for _, name in ipairs(modules or M.MODULES) do
        local src = sources[name]
        if not src then
            error("tilemo: dashboard/" .. name .. " is missing")
        end
        out[#out + 1] = wrap(name, src)
    end
    return table.concat(out)
end

-- The page: the template with tileco's stylesheet and the bundled script in
-- place of its two markers.
function M.page(template, css, sources, modules)
    local script = M.bundle(sources, modules)
    local html = template:gsub("/%*TILEMO_CSS%*/", function()
        return css
    end)
    html = html:gsub("/%*TILEMO_SCRIPT%*/", function()
        return script
    end)
    return html
end

-- What the page shows, as plain data for tilemo.update(): every workspace's
-- state as seen from display `uuid`, the one the dashboard is on, the
-- focused window's title, tide's clocks files (clock_files()), and the last
-- good clocks the pages reported, kept while a file is wrong.
function M.state(wm, adapter, uuid, clock_files, good_clocks)
    local ws = {}
    for n, s in ipairs(wm:bar_state(uuid)) do
        ws[n] = {
            n = n,
            current = s.here or false,
            elsewhere = s.elsewhere or false,
            occupied = s.occupied or false,
            urgent = s.urgent or false,
        }
    end
    local f = adapter.focused()
    local title = f and wm.windows[f] and adapter.title(f) or ""
    return { workspaces = ws, title = title, clockFiles = clock_files or {}, goodClocks = good_clocks }
end

return M
