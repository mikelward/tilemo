-- The overview, in place of Mission Control (SPEC.md §6.9): every
-- workspace's windows as cards, grouped by workspace, on Ctrl+Up, or the
-- current workspace's alone on Ctrl+Down. Pure Lua: what the page shows,
-- from wm; overview_hs.lua shows it in an hs.webview.

local M = {}

-- The page's modules, bundled as the dashboard's are (dashboard.bundle):
-- tide's fuzzy matcher, unchanged, then the page's own script.
M.MODULES = { "tide-fuzzy.js", "overview.js" }

-- The two scopes, as the keys' `arg` gives them.
M.SCOPES = { all = true, current = true }

-- The order of workspace `n`'s windows: on each display in turn, in
-- wm:screens()' order, its tiles in the stack's order, then its floats,
-- bottom to top; then any left, such as one on a display that went away,
-- or one you minimized that's out of the stack, in the order you minimized
-- them, then by id.
local function ordered(wm, n, ids)
    local want, out, seen = {}, {}, {}
    for _, id in ipairs(ids) do
        want[id] = true
    end
    local function take(id)
        if want[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, s in ipairs(wm:screens()) do
        local part = wm.workspaces[n] and wm.workspaces[n][s.uuid]
        for _, id in ipairs(part and part.order or {}) do
            local w = wm.windows[id]
            if w and w.screen == s.uuid and not w.floating then
                take(id)
            end
        end
        for _, id in ipairs(wm.floats) do
            local w = wm.windows[id]
            if w and w.screen == s.uuid then
                take(id)
            end
        end
    end
    local rest = {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            rest[#rest + 1] = id
        end
    end
    table.sort(rest, function(p, q)
        local a, b = wm.windows[p].min_at or 0, wm.windows[q].min_at or 0
        if a ~= b then
            return a < b
        end
        return tostring(p) < tostring(q)
    end)
    for _, id in ipairs(rest) do
        out[#out + 1] = id
    end
    return out
end

-- One card's facts: the title as the window has it now, else as tide
-- last saw it, and the app's name, else its bundle ID.
local function card(wm, id)
    local w = wm.windows[id]
    local a = wm.a
    local name = w.name
    if (name or "") == "" and a.app_name and w.app then
        name = a.app_name(w.app)
    end
    return {
        id = id,
        app = (name or "") ~= "" and name or (w.app or ""),
        bundle = w.app or "",
        title = (a.title and a.title(id)) or w.title or "",
        mine = w.mine or false,
    }
end

-- The overview's groups: each workspace with a window tide manages, on
-- any display, as { name, current, windows = { { id, app, bundle, title,
-- mine } } }. The current workspace comes first, then the rest in bar
-- order (wm:listed()), then any workspace the bar doesn't list, by name.
-- With `current_only`, only the current workspace, even if it's empty.
-- A window tide doesn't manage (no workspace), or that's gone, is left
-- out; one you minimized is in, marked `mine`.
function M.groups(wm, current_only)
    local by = {}
    for id, w in pairs(wm.windows) do
        if w.ws and wm.a.state(id) then
            by[w.ws] = by[w.ws] or {}
            table.insert(by[w.ws], id)
        end
    end
    local cur = wm:current_ws()
    local names = { cur }
    if not current_only then
        local listed = {}
        for _, n in ipairs((wm:listed())) do
            listed[n] = true
            if n ~= cur then
                names[#names + 1] = n
            end
        end
        local extra = {}
        for n in pairs(by) do
            if not listed[n] and n ~= cur then
                extra[#extra + 1] = n
            end
        end
        table.sort(extra)
        for _, n in ipairs(extra) do
            names[#names + 1] = n
        end
    end
    local out = {}
    for _, n in ipairs(names) do
        local ids = by[n]
        if ids or (current_only and n == cur) then
            local windows = {}
            for i, id in ipairs(ordered(wm, n, ids or {})) do
                windows[i] = card(wm, id)
            end
            out[#out + 1] = { name = n, current = n == cur, windows = windows }
        end
    end
    return out
end

-- What the page shows, for tide.update(): the scope, the groups, the
-- focused window's id, where the selection starts, and each app's icon as
-- a data URL, by bundle ID, from `icon_of(bundle)`, nil for none.
function M.state(wm, scope, icon_of, focused)
    local groups = M.groups(wm, scope == "current")
    local icons = {}
    for _, g in ipairs(groups) do
        for _, w in ipairs(g.windows) do
            if w.bundle ~= "" and icons[w.bundle] == nil and icon_of then
                icons[w.bundle] = icon_of(w.bundle) or false
            end
        end
    end
    for b, v in pairs(icons) do
        if v == false then
            icons[b] = nil
        end
    end
    -- The window focused before the page took the focus, given by the
    -- caller: once the page is up, macOS says Hammerspoon has it.
    local f = focused
    return { scope = scope, groups = groups, focused = f and wm.windows[f] and f or nil, icons = icons }
end

return M
