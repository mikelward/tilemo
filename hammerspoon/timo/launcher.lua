-- The launcher's matching and ranking (SPEC.md §9), a port of tico's
-- src/launcher.js: apps, timo's commands and open tabs, filtered by a fuzzy
-- match and ordered by how well they match, then by how recently you used
-- them. Pure Lua; launcher_hs.lua draws it with hs.chooser.

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

M.SCOPES = { launch = { app = true, command = true }, tabs = { tab = true } }

local KIND_ORDER = { tab = 1, app = 2, command = 3 }

local function rank_all(query, items, limit, recency)
    local q = query:match("^%s*(.-)%s*$")
    local scored = {}
    for _, item in ipairs(items) do
        local s = q == "" and 0 or item_score(q, item)
        if s then
            scored[#scored + 1] = { item = item, score = s, seen = recency[item.key] or 0 }
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

-- Items in `scope` matching `query`, best first; ties go to the most
-- recently used (`recency` maps an item's key to when). A query that matches
-- nothing in its scope looks in every scope instead.
function M.rank(query, items, opts)
    opts = opts or {}
    local limit = opts.limit or 20
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

-- A tab's host, for matching by site.
local function host(url)
    return (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
end

-- Items from what the adapter found: apps { name, path }, tabs { title, url,
-- browser, window, tab } and commands { title, action, arg, quick }. Each
-- gets a stable key, for remembering when it was used, and an id that's
-- unique among the items, for choosing it: two tabs on the same page share
-- a key but not an id.
function M.items(apps, tabs, commands)
    local out = {}
    for _, a in ipairs(apps or {}) do
        out[#out + 1] = { kind = "app", title = a.name, path = a.path, key = "app:" .. a.path }
    end
    for _, t in ipairs(tabs or {}) do
        out[#out + 1] = {
            kind = "tab",
            title = t.title ~= "" and t.title or (t.url or ""),
            extra = host(t.url),
            browser = t.browser,
            window = t.window,
            tab = t.tab,
            key = "tab:" .. (t.url or t.title or ""),
            id = string.format("tab:%s:%s:%s", t.browser, t.window, t.tab),
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

-- timo's commands, as the launcher lists them. `action` names a window
-- manager action; `quick` names one of the adapter's quick actions
-- (tide SPEC.md §8).
M.COMMANDS = {
    { title = "Layout: tile", action = "layout", arg = "tile" },
    { title = "Layout: three columns", action = "layout", arg = "threecol" },
    { title = "Layout: two columns", action = "layout", arg = "twocol" },
    { title = "Dashboard: workspaces, clocks and calendar", action = "dashboard" },
    { title = "Monocle", action = "monocle" },
    { title = "Float or tile the window", action = "toggle_float" },
    { title = "Maximize the window", action = "maximize" },
    { title = "Full screen", action = "fullscreen" },
    { title = "Screenshot: window", quick = "screenshot_window" },
    { title = "Screenshot: screen", quick = "screenshot_screen" },
    { title = "Screenshot: region", quick = "screenshot_region" },
    { title = "Lock", quick = "lock" },
    { title = "Log out", quick = "logout" },
    { title = "Sleep", quick = "sleep" },
    { title = "Restart", quick = "restart" },
    { title = "Shut down", quick = "shutdown" },
    { title = "Do Not Disturb", quick = "dnd" },
    { title = "Keep awake", quick = "keep_awake" },
    { title = "Dark style", quick = "dark" },
    { title = "Focus follows mouse on or off", quick = "toggle_ffm" },
    { title = "Reload timo", quick = "reload" },
}
for n = 1, 9 do
    M.COMMANDS[#M.COMMANDS + 1] = { title = "Workspace " .. n, action = "show", arg = n }
end

return M
