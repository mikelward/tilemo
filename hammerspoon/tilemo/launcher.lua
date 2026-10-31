-- The switcher's matching and ranking (SPEC.md §9), a port of tileco's
-- src/launcher.js: apps, System Settings' panes, tilemo's commands, the
-- workspaces, every window and open tab, and the windows wanting attention,
-- in tabs Tab moves between,
-- filtered by a fuzzy match and ordered by how well they match, then by how
-- recently you used them. Also where the apps and panes are found. Pure
-- Lua; launcher_hs.lua draws it with hs.chooser.

local M = {}

local SEPARATORS = "[%s%-_%./:%(%)]"

-- How well `query` matches `text`, or nil if it doesn't. Every query
-- character must appear in order; matches at the start of a word, and runs
-- of consecutive matches, score higher, so "gc" finds "Google Calendar"
-- first.
function M.score(query, text)
    local q, t = query:lower(), (text or ""):lower()
    if q == "" then
        return 0
    end
    local score, from, last = 0, 1, -1
    for ch in q:gmatch(".") do
        if ch ~= " " then
            local i = t:find(ch, from, true)
            if not i then
                return nil
            end
            score = score + 1
            if i == 1 or t:sub(i - 1, i - 1):match(SEPARATORS) then
                score = score + 3
            end
            if i == last + 1 then
                score = score + 2
            end
            last, from = i, i + 1
        end
    end
    if t:sub(1, #q) == q then
        score = score + 5
    end
    return score
end

-- The best score over an item's title and its other searchable text, such
-- as a tab's host, which counts for less.
local function item_score(query, item)
    local title = M.score(query, item.title)
    local extra = item.extra and M.score(query, item.extra)
    if not title and not extra then
        return nil
    end
    return math.max(title or -math.huge, extra and extra - 2 or -math.huge)
end

-- The switcher's tabs (SPEC.md §9), each listing these kinds.
M.SCOPES = {
    launch = { app = true, setting = true, command = true },
    workspaces = { workspace = true },
    windows = { window = true, tab = true },
    attention = { attention = true },
}

-- The order Tab moves through them, and what each lists. Each key opens
-- the switcher on its own (SPEC.md §9).
M.SCOPE_ORDER = { "launch", "workspaces", "windows", "attention" }
M.SCOPE_NAMES = { launch = "Launch", workspaces = "Workspaces", windows = "Windows", attention = "Attention" }
M.SCOPE_LISTS = {
    launch = "apps, settings and commands",
    workspaces = "every workspace",
    windows = "every window, and Chrome and Safari tabs",
    attention = "windows wanting attention",
}
-- What an empty tab shows instead, in a row that can't be chosen.
M.SCOPE_EMPTY = {
    launch = "Nothing to launch",
    workspaces = "No workspaces",
    windows = "No windows",
    attention = "Nothing wants attention",
}

-- The scope after `scope`, or before it when `back`, round in a circle.
function M.next_scope(scope, back)
    local n = #M.SCOPE_ORDER
    for i, s in ipairs(M.SCOPE_ORDER) do
        if s == scope then
            return M.SCOPE_ORDER[(i - 1 + (back and -1 or 1)) % n + 1]
        end
    end
    return M.SCOPE_ORDER[1]
end

-- The search field's hint: the scope, what it lists, and where Tab goes.
function M.placeholder(scope)
    return string.format("%s: %s (Tab: %s)", M.SCOPE_NAMES[scope], M.SCOPE_LISTS[scope],
        M.SCOPE_NAMES[M.next_scope(scope)])
end

local KIND_ORDER = { attention = 0, workspace = 1, window = 2, tab = 3, app = 4, setting = 5, command = 6 }

local function rank_all(query, items, limit, recency)
    local q = query:match("^%s*(.-)%s*$")
    local scored = {}
    for _, item in ipairs(items) do
        local s = q == "" and 0 or item_score(q, item)
        if s then
            -- Items that come in an order of their own keep it, as the
            -- windows wanting attention do, newest first: as if used before
            -- anything else, so one key orders every kind alike.
            local seen = item.order and -item.order or recency[item.key] or 0
            scored[#scored + 1] = { item = item, score = s, seen = seen }
        end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if q == "" and a.item.kind ~= b.item.kind then
            return KIND_ORDER[a.item.kind] < KIND_ORDER[b.item.kind]
        end
        if a.seen ~= b.seen then
            return a.seen > b.seen
        end
        return a.item.title < b.item.title
    end)
    local out = {}
    for i = 1, math.min(limit, #scored) do
        out[i] = scored[i].item
    end
    return out
end

-- How many rows a tab shows at most, unless `opts.limit` says. Only Launch,
-- with every app and pane on the Mac, is capped: the other tabs list
-- tilemo's own state, and every window, tab and workspace there must stay
-- reachable however many there are.
M.LIMITS = { launch = 20 }
M.LIMIT = 20

-- Items in `scope` matching `query`, best first; ties go to the most
-- recently used (`recency` maps an item's key to when). A query that matches
-- nothing in its scope looks in every scope instead.
function M.rank(query, items, opts)
    opts = opts or {}
    local limit = opts.limit or (opts.scope and (M.LIMITS[opts.scope] or math.huge)) or M.LIMIT
    local recency = opts.recency or {}
    local in_scope = items
    if opts.scope then
        in_scope = {}
        for _, i in ipairs(items) do
            if M.SCOPES[opts.scope][i.kind] then
                in_scope[#in_scope + 1] = i
            end
        end
    end
    local found = rank_all(query, in_scope, limit, recency)
    if #found > 0 or not opts.scope or query:match("^%s*$") then
        return found
    end
    return rank_all(query, items, limit, recency)
end

-- `parts` joined with " · ", leaving out any that's nil or empty, in any
-- place: table.concat can't skip a nil.
local function join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        if p ~= nil and p ~= "" then
            out[#out + 1] = tostring(p)
        end
    end
    return table.concat(out, " · ")
end

-- The line under an item's title in the switcher.
function M.subtitle(item)
    if item.kind == "tab" then
        return join(item.browser, item.extra, item.ws)
    elseif item.kind == "window" then
        return join(item.app, item.ws)
    elseif item.kind == "setting" then
        return "System Settings"
    elseif item.kind == "attention" then
        return join(item.app, item.ws)
    elseif item.kind == "workspace" then
        return join(item.where, item.extra)
    end
    return item.kind
end

-- A tab's host, for matching by site.
local function host(url)
    return (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
end

-- A browser's tabs from TAB_SCRIPTS' output, one per line: window index,
-- tab index, the window's id, its name, the tab's address and its title,
-- separated by tabs. Returns { browser, window, tab, window_id,
-- window_name, url, title }.
function M.parse_tabs(browser, text)
    local out = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local w, t, id, wname, url, title = line:match("^(%d+)\t(%d+)\t(%d+)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if w then
            out[#out + 1] = {
                browser = browser,
                window = tonumber(w),
                tab = tonumber(t),
                window_id = tonumber(id),
                window_name = wname,
                url = url,
                title = title,
            }
        end
    end
    return out
end

-- The tilemo window a browser tab is in: of `windows`, { id, app, title,
-- ws }, the one of the browser's app (`bundle`) whose title is the tab's
-- window's name. AppleScript's window numbers aren't Accessibility's, so
-- the name is what's shared *(unverified that they always agree)*. Nil if
-- none or several match.
function M.tab_window(tab, bundle, windows)
    local found
    for _, w in ipairs(windows) do
        if w.app == bundle and w.title == tab.window_name and tab.window_name ~= "" then
            if found then
                return nil
            end
            found = w
        end
    end
    return found
end

-- Items from what the adapter found: apps { name, path }, tabs { title, url,
-- browser, window, tab, win, ws }, commands { title, action, arg, quick }, System
-- Settings' panes { name, id }, the windows wanting attention { window,
-- title, app, ws }, newest first, the workspaces { name, apps, where }, in
-- bar order, and every window { id, title, app_name, ws }, most recently
-- used first. Each gets a stable key, for remembering
-- when it was used, and an id that's unique among the items, for choosing
-- it: two tabs on the same page share a key but not an id.
function M.items(apps, tabs, commands, settings, attention, workspaces, windows)
    local out = {}
    -- Most recently used first, as listed, which they keep.
    for i, w in ipairs(windows or {}) do
        out[#out + 1] = {
            kind = "window",
            title = (w.title or "") ~= "" and w.title or (w.app_name or ""),
            extra = w.app_name,
            app = w.app_name,
            window = w.id,
            ws = w.ws,
            order = i,
            key = "window:" .. tostring(w.id),
        }
    end
    -- In bar order, which they keep, as the attention list keeps its own.
    for i, w in ipairs(workspaces or {}) do
        out[#out + 1] = {
            kind = "workspace",
            title = w.name,
            extra = w.apps,
            where = w.where,
            order = i,
            key = "workspace:" .. w.name,
        }
    end
    for _, a in ipairs(apps or {}) do
        out[#out + 1] = { kind = "app", title = a.name, path = a.path, key = "app:" .. a.path }
    end
    -- "Mouse settings", so "mouse settings" finds it as well as "mouse".
    for _, p in ipairs(settings or {}) do
        local title = p.name:lower():match(" settings$") and p.name or p.name .. " settings"
        out[#out + 1] = {
            kind = "setting",
            title = title,
            url = "x-apple.systempreferences:" .. p.id,
            key = "setting:" .. p.id,
        }
    end
    for _, t in ipairs(tabs or {}) do
        out[#out + 1] = {
            kind = "tab",
            title = t.title ~= "" and t.title or (t.url or ""),
            extra = host(t.url),
            browser = t.browser,
            window = t.window,
            window_id = t.window_id,
            tab = t.tab,
            win = t.win,
            ws = t.ws,
            key = "tab:" .. (t.url or t.title or ""),
            id = string.format("tab:%s:%s:%s", t.browser, t.window, t.tab),
        }
    end
    for i, w in ipairs(attention or {}) do
        out[#out + 1] = {
            kind = "attention",
            title = (w.title or "") ~= "" and w.title or (w.app or ""),
            extra = w.app,
            app = w.app,
            window = w.window,
            ws = w.ws,
            order = i,
            key = "attention:" .. tostring(w.window),
        }
    end
    for _, c in ipairs(commands or {}) do
        out[#out + 1] = {
            kind = "command",
            title = c.title,
            action = c.action,
            arg = c.arg,
            quick = c.quick,
            key = "command:" .. c.title,
        }
    end
    for _, item in ipairs(out) do
        item.id = item.id or item.key
    end
    return out
end

-- Where apps are: each folder, and the folders in it to `depth` levels
-- down, for vendor folders, Utilities and Chrome's web apps. An app is a
-- folder too, so the search stops at one. `~` is the home folder.
M.APP_DIRS = {
    { path = "/Applications", depth = 2 },
    { path = "/System/Applications", depth = 1 },
    { path = "/System/Library/CoreServices/Applications", depth = 0 },
    { path = "~/Applications", depth = 2 },
}

-- Apps that sit among things that aren't, listed one by one.
M.LONE_APPS = { "/System/Library/CoreServices/Finder.app" }

-- The apps, as { name, path }, in M.APP_DIRS and M.LONE_APPS. `list(dir)`
-- gives a folder's entries as { name, dir }, or nil if it can't be read.
function M.scan_apps(list, home)
    local apps = {}
    local function walk(dir, depth)
        for _, e in ipairs(list(dir) or {}) do
            local path = dir .. "/" .. e.name
            local name = e.name:match("^(.*)%.app$")
            if name then
                apps[#apps + 1] = { name = name, path = path }
            elseif e.dir and depth > 0 and e.name:sub(1, 1) ~= "." then
                walk(path, depth - 1)
            end
        end
    end
    for _, d in ipairs(M.APP_DIRS) do
        walk((d.path:gsub("^~", home)), d.depth)
    end
    for _, path in ipairs(M.LONE_APPS) do
        local dir, file = path:match("^(.*)/([^/]+)$")
        for _, e in ipairs(list(dir) or {}) do
            if e.name == file then
                apps[#apps + 1] = { name = file:match("^(.*)%.app$"), path = path }
            end
        end
    end
    return apps
end

-- System Settings' panes are app extensions that plug into it.
M.SETTINGS_DIR = "/System/Library/ExtensionKit/Extensions"
M.SETTINGS_POINT = "com.apple.Settings.extension.ui"

-- Where a pane keeps its English name, as System Settings shows it: a
-- table of every language, or the English strings alone.
local LOCALIZED = {
    { path = "Resources/InfoPlist.loctable", lang = "en" },
    { path = "Resources/en.lproj/InfoPlist.strings" },
    { path = "Resources/English.lproj/InfoPlist.strings" },
    { path = "Resources/Base.lproj/InfoPlist.strings" },
}

-- An internal name ("TrackpadExtension", "CDs & DVDs Settings Extension",
-- "PowerPreferences") without the words that only say what it is.
local function tidy(name)
    local before
    repeat
        before = name
        name = name:gsub("%s*Extension$", ""):gsub("%s*Settings$", ""):gsub("%s*Preferences$", "")
            :gsub("%s*SettingPane_macOS$", "")
    until name == before
    return name
end

local function pane_name(read, contents, info, base)
    for _, l in ipairs(LOCALIZED) do
        local t = read(contents .. "/" .. l.path)
        if t and l.lang then
            t = t[l.lang]
        end
        local name = type(t) == "table" and (t.CFBundleDisplayName or t.CFBundleName)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tidy(info.CFBundleDisplayName or info.CFBundleName or base)
end

-- The panes, as { name, id }. `read(path)` gives a plist as a table, or nil.
function M.scan_settings(list, read)
    local panes = {}
    for _, e in ipairs(list(M.SETTINGS_DIR) or {}) do
        local base = e.name:match("^(.*)%.appex$")
        local contents = M.SETTINGS_DIR .. "/" .. e.name .. "/Contents"
        local info = base and read(contents .. "/Info.plist")
        local attrs = info and info.EXAppExtensionAttributes
        if attrs and attrs.EXExtensionPointIdentifier == M.SETTINGS_POINT and info.CFBundleIdentifier then
            panes[#panes + 1] = { name = pane_name(read, contents, info, base), id = info.CFBundleIdentifier }
        end
    end
    return panes
end

-- tilemo's commands, as the launcher lists them. `action` names a window
-- manager action; `quick` names one of the adapter's quick actions
-- (tide SPEC.md §8).
M.COMMANDS = {
    { title = "Layout: tile", action = "layout", arg = "tile" },
    { title = "Layout: three columns", action = "layout", arg = "threecol" },
    { title = "Layout: two columns", action = "layout", arg = "twocol" },
    { title = "Dashboard: workspaces, clocks and calendar", action = "dashboard" },
    { title = "Settings: clocks", action = "settings" },
    { title = "Monocle", action = "monocle" },
    { title = "Float or tile the window", action = "toggle_float" },
    { title = "Maximize the window", action = "maximize" },
    { title = "Full screen", action = "fullscreen" },
    { title = "Screenshot: window", quick = "screenshot_window" },
    { title = "Screenshot: screen", quick = "screenshot_screen" },
    { title = "Screenshot: region", quick = "screenshot_region" },
    { title = "Lock", action = "lock" },
    { title = "Log out", action = "logout" },
    { title = "Sleep", quick = "sleep" },
    { title = "Restart", quick = "restart" },
    { title = "Shut down", quick = "shutdown" },
    { title = "Do Not Disturb", quick = "dnd" },
    { title = "Keep awake", quick = "keep_awake" },
    { title = "Dark style", quick = "dark" },
    { title = "Focus follows mouse on or off", quick = "toggle_ffm" },
    { title = "Reload tilemo", quick = "reload" },
    { title = "Check tilemo (doctor)", quick = "doctor" },
}
-- Workspaces are in the Workspaces tab, by name, not commands by number.

return M
