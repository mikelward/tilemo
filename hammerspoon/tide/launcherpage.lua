-- The dashboard launcher (SPEC.md §9.2): tileco's launcher page
-- (launcherview.js), copied unchanged, in an hs.webview in place of the
-- hs.chooser switcher. It's switched off: start()'s `launcher = "dashboard"`
-- turns it on, and the default, "chooser", keeps the switcher. The page
-- calls Chrome's extension APIs, so tide's stand-ins answer them
-- (dashboard/launcher-chrome.js), fed from the switcher's own rows
-- (launcher.items). Pure Lua; launcherpage_hs.lua shows it.

local keys = require("tide.keys")
local launcher = require("tide.launcher")

local M = {}

-- In the order they're needed, as dashboard.MODULES: tileco's page and what
-- it imports, tide's settings for the clocks, and tide's stand-ins.
-- launcher-settings.js and launcher-lists.js take the places of tileco's
-- settings.js and launcher.js (dashboard.ALIASES), answering from the feed.
M.MODULES = {
    "clocks.js", "calendar.js", "tide-clocks.js", "settings.js",
    "launcher-chrome.js", "launcher-settings.js",
    "clockview.js", "apps.js", "workspaces.js", "platform.js", "launcher.js", "launcher-lists.js",
    "unread.js", "watchers.js", "extras.js", "keepawake.js",
    "launcherview.js", "launcher-page.js",
}

-- The launcher start() runs: "chooser", the switcher, unless it says
-- "dashboard". Anything else is an error at load, naming the setting.
M.DEFAULT = "chooser"
M.MODULE = { chooser = "tide.launcher_hs", dashboard = "tide.launcherpage_hs" }

function M.front(value)
    if value == nil then
        return M.DEFAULT
    end
    if M.MODULE[value] then
        return value
    end
    error(string.format('start()\'s launcher is %s: it must be "chooser" or "dashboard"',
        type(value) == "string" and string.format("%q", value) or tostring(value)), 0)
end

-- The module that draws the launcher start()'s `value` names.
function M.module_for(value)
    return M.MODULE[M.front(value)]
end

-- The launcher chosen under Keyboard in tide's settings, kept on this Mac
-- in hs.settings: it wins over start()'s `launcher`, which is the default
-- until it's chosen there (SPEC.md §9.2, §15).
M.SETTINGS_KEY = "tide.launcher"

-- The launcher to run: `chosen`, the settings window's, if it's one there
-- is; else start()'s `value`, which is an error if it's wrong. A stored
-- value that isn't one is left out, and `log` says so.
function M.choose(chosen, value, log)
    if chosen ~= nil then
        if M.MODULE[chosen] then
            return chosen
        end
        if log then
            log("the launcher chosen in settings, " .. tostring(chosen) .. ", isn't one; using start()'s")
        end
    end
    return M.front(value)
end

-- The two choices, as the settings window's Keyboard section names them.
M.LABELS = { chooser = "tide's switcher", dashboard = "tileco's launcher" }

-- The page's scope for the switcher's tab `tab`, which a key opens it on.
-- tileco's page has no Attention scope, so the windows wanting attention
-- are among the windows, on Tabs.
M.PAGE_SCOPE = {
    launch = "launch",
    workspaces = "workspaces",
    windows = "tabs",
    attention = "tabs",
    actions = "actions",
}

function M.page_scope(tab)
    return M.PAGE_SCOPE[tab or ""] or "launch"
end

-- A row the page sends back, by the switcher's id for it: as a tab's id,
-- or a command's name after this.
M.ROW = "row:"

-- tileco's "Browser window" app is Super+G's browser (keys.APPS).
M.BROWSER = "Browser"

function M.browser_key()
    for _, a in ipairs(keys.APPS) do
        if a.does == M.BROWSER and not a.shift then
            return a
        end
    end
end

-- A window's app, as the host of the address it's listed with, so a query
-- finds a window by its app as it finds a tab by its site.
local function slug(name)
    return ((name or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- What the page shows around the rows, from window manager `wm` as seen
-- from display `uuid`, in the shape tileco's background keeps its `view`:
-- the workspaces in bar order, each one's windows, the ones made so far,
-- the urgent ones, and what each display shows, with its layout.
function M.view(wm, uuid)
    uuid = uuid or wm:current_screen()
    local bar, counts, made_list, urgent = {}, {}, {}, {}
    local _, made = wm:listed()
    for _, s in ipairs(wm:bar_state()) do
        bar[#bar + 1] = s.name
        if made[s.name] then
            made_list[#made_list + 1] = s.name
        end
        if s.urgent then
            urgent[#urgent + 1] = s.name
        end
    end
    for _, w in pairs(wm.windows) do
        if w.ws then
            counts[w.ws] = (counts[w.ws] or 0) + 1
        end
    end
    local displays = {}
    -- Every display shows the same workspace, each in its own layout.
    for _, s in ipairs(wm:screens()) do
        local ws = wm:part(wm.current, s.uuid)
        displays[s.uuid] = { workspace = wm.current, mode = ws and ws.mode }
    end
    return { bar = bar, counts = counts, made = made_list, urgent = urgent, displays = displays, focusedDisplay = uuid }
end

-- The page's feed: launcher.items' rows as the stand-ins hand them to
-- tileco's page. `opts`: `recency`, as the switcher remembers uses;
-- `view`, M.view's; `keep_awake`, whether it's on; and the clocks, as the
-- dashboard has them (`clock_files`, `good_clocks`).
--   - Windows and browser tabs are Chrome's tabs, windows most recent first,
--     each its own window for its workspace.
--   - Apps, the app scripts and System Settings' panes are tileco's app keys, most recently
--     used first; Tide Settings is tileco's own row.
--   - Tide Settings' sections are tileco's settings sections.
--   - The Actions tab's rows are its actions, in their order.
--   - The other commands are the manifest's, with no key.
function M.feed(items, opts)
    opts = opts or {}
    local recency = opts.recency or {}
    local tabs, windows, apps, actions, commands = {}, {}, {}, {}, {}
    local listed = {}
    for _, item in ipairs(items) do
        if item.kind == "window" or item.kind == "tab" then
            listed[#listed + 1] = item
        end
    end
    for i, item in ipairs(listed) do
        tabs[#tabs + 1] = {
            id = item.id,
            windowId = item.id,
            title = item.title,
            url = item.kind == "tab" and item.url or ("tide-window://" .. slug(item.app) .. "/"),
            -- tileco orders tabs by when they were last used.
            lastAccessed = #listed - i + 1,
        }
        if item.ws then
            windows[item.id] = { ws = item.ws }
        end
    end
    local found = {}
    for i, item in ipairs(items) do
        -- Apps on disk and the app scripts (launcher.with_scripts), not
        -- Tide Settings, which is tileco's own row.
        if (item.kind == "app" and (item.path or item.action == "app")) or item.kind == "setting" then
            found[#found + 1] = { item = item, i = i, seen = recency[item.key] or 0 }
        end
    end
    table.sort(found, function(a, b)
        if a.seen ~= b.seen then
            return a.seen > b.seen
        end
        return a.i < b.i
    end)
    for _, f in ipairs(found) do
        apps[#apps + 1] = { name = f.item.title, command = M.ROW .. f.item.id }
    end
    local in_order = {}
    for _, item in ipairs(items) do
        if item.kind == "action" then
            in_order[#in_order + 1] = item
        end
    end
    table.sort(in_order, function(a, b)
        return a.order < b.order
    end)
    for _, item in ipairs(in_order) do
        local detail = item.sub or ""
        if item.quick == "keep_awake" then
            detail = opts.keep_awake and "on" or "off"
        end
        actions[#actions + 1] = { kind = "action", title = item.title, detail = detail, key = "", command = M.ROW .. item.id }
    end
    -- A description ends with its key in parentheses (tileco's manifest);
    -- these have none, so "()" keeps a title's own parentheses its own.
    local browser = M.browser_key()
    if browser then
        commands[#commands + 1] = { name = "app-browser", description = "Browser window (" .. keys.keys_label(browser, {}, true) .. ")" }
    end
    for _, item in ipairs(items) do
        if item.kind == "command" and not item.query_only then
            commands[#commands + 1] = { name = M.ROW .. item.id, description = item.title .. " ()" }
        end
    end
    local sections = {}
    for _, s in ipairs(launcher.SETTINGS_SECTIONS) do
        sections[#sections + 1] = { id = s.id, name = s.name, covers = s.covers }
    end
    return {
        tabs = tabs,
        apps = apps,
        actions = actions,
        commands = commands,
        sections = sections,
        view = opts.view,
        state = { windows = windows },
        keepAwake = opts.keep_awake or false,
        clockFiles = opts.clock_files or {},
        goodClocks = opts.good_clocks,
    }
end

-- What a message from the page asks for, as { kind, value }:
--   row: run the switcher's row with id `value`;
--   workspace: show workspace `value`, made if it's new;
--   settings: the settings window, at section `value` if there's one;
--   keep_awake, browser (tileco's Browser window), reload, close;
--   clock_errors, good_clocks: as the dashboard's;
--   unknown: anything else, named.
function M.message(body)
    if type(body) ~= "table" then
        return { kind = "unknown", value = tostring(body) }
    end
    if body.close then
        return { kind = "close" }
    elseif body.typed ~= nil then
        -- Whether there's anything in the search, as it changes.
        return { kind = "typed", value = body.typed == true }
    elseif body.tabId ~= nil then
        return { kind = "row", value = tostring(body.tabId) }
    elseif type(body.command) == "string" then
        local id = body.command:sub(1, #M.ROW) == M.ROW and body.command:sub(#M.ROW + 1)
        if id and id ~= "" then
            return { kind = "row", value = id }
        elseif body.command == "keep-awake" then
            return { kind = "keep_awake" }
        elseif body.command == "app-browser" then
            return { kind = "browser" }
        end
        return { kind = "unknown", value = "command " .. body.command }
    elseif body.workspace ~= nil then
        return { kind = "workspace", value = tostring(body.workspace) }
    elseif body.settings ~= nil then
        return { kind = "settings", value = type(body.settings) == "string" and body.settings or nil }
    elseif body.reload then
        return { kind = "reload" }
    elseif body.clockErrors then
        return { kind = "clock_errors", value = body.clockErrors }
    elseif body.goodClocks then
        return { kind = "good_clocks", value = body.goodClocks }
    end
    local names = {}
    for k in pairs(body) do
        names[#names + 1] = tostring(k)
    end
    table.sort(names)
    return { kind = "unknown", value = table.concat(names, ", ") }
end

-- The launcher page's window on a display whose full frame is `full`: a
-- panel about tide's switcher's size (tide's is 560 wide), as wide as
-- tileco's launcher card (680) and its padding, up to 600 tall, centered
-- across and a third of the way down, kept on the display. Not the whole
-- display: tide's own bar already shows the workspaces, clocks and
-- status icons tileco's page would repeat above it.
M.WIDTH, M.HEIGHT = 728, 600
function M.frame(full)
    local w = math.min(M.WIDTH, full.w - 40)
    local h = math.min(M.HEIGHT, full.h - 80)
    return {
        x = math.floor(full.x + (full.w - w) / 2),
        y = math.floor(full.y + (full.h - h) / 3),
        w = w,
        h = h,
    }
end

return M
