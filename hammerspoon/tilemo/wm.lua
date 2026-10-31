-- The window manager: which window is on which workspace, tiled or
-- floating, and the actions the keys call (SPEC.md §5). It talks to macOS
-- only through an adapter (hs_adapter.lua on a Mac, a fake in the tests),
-- so all of its decisions test without Hammerspoon. The adapter's `facts`
-- is the full, slower read used to decide a new window; `state` is the
-- quick one used on every retile.
--
-- Workspaces (SPEC.md §6.1) are tileco's model with tide's names: the
-- home workspace ("in" by default) first and always there, then the
-- standing ones, then the rest in the order they were made, shared by
-- every display, each display showing one. An empty workspace that isn't
-- standing goes once no display shows it. A window on a workspace that
-- isn't showing is minimized. Every operation changes only which workspace
-- each display shows and which workspace each window is on; then
-- reconcile() makes the screen match, restoring first so the screen never
-- goes empty.

local attention = require("tilemo.attention")
local mute = require("tilemo.mute")
local bar = require("tilemo.bar")
local layout = require("tilemo.layout")
local mouse = require("tilemo.mouse")
local names = require("tilemo.names")
local rules = require("tilemo.rules")

local M = {}
M.__index = M

local function remove_value(list, v)
    for i = #list, 1, -1 do
        if list[i] == v then
            table.remove(list, i)
        end
    end
end

local set_big_on

-- The standing workspaces (SPEC.md §6.1): always listed, never removed.
-- The first is the home workspace, "in" by default, made at start and
-- never renamed, where the apps below always open, by app name (SPEC.md
-- §6.2); the rest are made the first time you show one or send a window
-- to it. Which names stand for mail, chat, calendar and music is a guess,
-- to confirm.
M.STANDING = { "in", "re", "oc", "me" }
M.HOME_APPS = { "Mail", "Gmail", "Messages", "Google Chat", "Calendar", "Google Calendar", "Music", "YouTube Music" }
-- How long tilemo waits for macOS to report a minimize or restore it asked for.
M.EXPECT = 2

-- How long to wait after the last window event before retiling, since one
-- window opening sends several (tileco SPEC.md §5.3).
M.DEBOUNCE = 0.05
-- A float's size is capped at this share of its display (tide SPEC.md §6.4).
M.FLOAT_CAP = 0.8
-- The focus guard (SPEC.md §14.1): how long a launch you made may give its
-- window focus, and how soon after something you did (a click, a key with
-- Command, a focus tilemo asked for) an activation still counts as yours.
M.GRANT = 10
M.GRACE = 1
-- How long the place of a window whose app quit, or that the last run saved
-- and hasn't come back, is kept for a window of that app to take
-- (SPEC.md §6.3), and how many such places are kept at most.
M.KEEP = 600
M.KEEP_MAX = 50

-- `name` folded for comparing ignoring case: ASCII, Latin-1, Latin
-- Extended-A, Greek and Cyrillic capitals go to their small letters, as
-- Unicode's simple case folding does for them; other characters are kept.
-- Lua's own lower() is byte by byte, so it misses everything past ASCII.
function M.fold(name)
    local ok, out = pcall(function()
        local cps = {}
        for _, c in utf8.codes(name) do
            if (c >= 0x41 and c <= 0x5A) or (c >= 0xC0 and c <= 0xDE and c ~= 0xD7)
                or (c >= 0x391 and c <= 0x3AB and c ~= 0x3A2) or (c >= 0x410 and c <= 0x42F) then
                c = c + 32
            elseif c >= 0x400 and c <= 0x40F then
                c = c + 80
            elseif (c >= 0x100 and c <= 0x137 and c ~= 0x130) or (c >= 0x14A and c <= 0x177)
                or (c >= 0x460 and c <= 0x481) or (c >= 0x48A and c <= 0x4BF) then
                -- Capital and small alternate, capital first.
                if c % 2 == 0 then
                    c = c + 1
                end
            elseif (c >= 0x139 and c <= 0x148) or (c >= 0x179 and c <= 0x17E) then
                -- Here the capital is odd.
                if c % 2 == 1 then
                    c = c + 1
                end
            elseif c == 0x178 then
                c = 0xFF
            end
            cps[#cps + 1] = utf8.char(c)
        end
        return table.concat(cps)
    end)
    -- Not valid UTF-8: compare it byte by byte.
    return ok and out or name:lower()
end

-- `workspaces`, the standing workspaces' names, is checked when tilemo
-- starts: a list of at least one name, the first being home, none named
-- twice. Anything else is an error naming the setting.
function M.check_standing(list)
    if type(list) ~= "table" then
        error("workspaces must be a list of names", 3)
    end
    for k in pairs(list) do
        if math.type(k) ~= "integer" or k < 1 or k > #list then
            error("workspaces must be a list of names, not " .. tostring(k), 3)
        end
    end
    if #list == 0 then
        error("workspaces must name at least one workspace, the home one", 3)
    end
    local out, seen = {}, {}
    for i, name in ipairs(list) do
        local n = M.clean_name(name)
        if not n then
            error(string.format("workspaces[%d] must be a name", i), 3)
        end
        if names.unsafe(n) then
            error(string.format("workspaces[%d]: %q can't have quotes, backslashes or control characters", i, n), 3)
        end
        local f = M.fold(n)
        if seen[f] then
            error(string.format("workspaces[%d]: %q is already workspaces[%d]", i, n, seen[f]), 3)
        end
        seen[f] = i
        out[#out + 1] = n
    end
    return out
end

-- `home_apps` is checked when tilemo starts, so a typo is an error naming the
-- setting rather than a window opening in the wrong place.
function M.check_home_apps(list)
    if type(list) ~= "table" then
        error("home_apps must be a list of app names", 3)
    end
    local set = {}
    for i, name in ipairs(list) do
        if type(name) ~= "string" or name == "" then
            error(string.format("home_apps[%d] must be an app's name", i), 3)
        end
        set[name] = true
    end
    for k in pairs(list) do
        if math.type(k) ~= "integer" or k < 1 or k > #list then
            error("home_apps must be a list of app names, not " .. tostring(k), 3)
        end
    end
    return set
end

-- A saved state from before named workspaces names each workspace by its
-- number (SPEC.md §6.5). It's read once: each number with windows becomes
-- the workspace named by it, "1" to "9" in that order after the standing
-- ones; an empty number is dropped, and a display showing one shows `home`.
-- Each window from it is marked `numbered`, so one of home's apps goes home
-- when it comes back, which needs its app's name, not saved then. Returns
-- the state as names, and whether it was numbered.
function M.migrate(saved, home)
    saved = saved or {}
    if saved.names then
        return saved, false
    end
    local numbered = false
    local used = {}
    -- The settings store may give a number back as a float.
    local function name_of(ws)
        if type(ws) == "number" then
            numbered = true
            return tostring(math.tointeger(ws) or ws)
        end
        return ws
    end
    local windows = {}
    for k, v in pairs(saved.windows or {}) do
        local c = {}
        for f, x in pairs(v) do
            c[f] = x
        end
        c.ws = name_of(v.ws)
        windows[k] = c
    end
    local gone = {}
    for i, g in ipairs(saved.gone or {}) do
        local c = {}
        for f, x in pairs(g) do
            c[f] = x
        end
        c.ws = name_of(g.ws)
        gone[i] = c
    end
    local screens = {}
    for uuid, n in pairs(saved.screens or {}) do
        screens[uuid] = name_of(n)
    end
    if not numbered then
        return { windows = windows, gone = gone, screens = screens }, false
    end
    for _, list in ipairs({ windows, gone }) do
        for _, v in pairs(list) do
            if v.ws then
                v.numbered = true
                used[v.ws] = true
            end
        end
    end
    local names = { home }
    for n = 1, 9 do
        if used[tostring(n)] then
            names[#names + 1] = tostring(n)
        end
    end
    for uuid, name in pairs(screens) do
        if not used[name] then
            screens[uuid] = home
        end
    end
    return { windows = windows, gone = gone, screens = screens, names = names }, true
end

function M.new(adapter, config)
    config = config or {}
    local standing = M.check_standing(config.workspaces or M.STANDING)
    local saved, migrated = M.migrate(config.saved, standing[1])
    local self = setmetatable({
        a = adapter,
        layout = config.layout or layout.defaults,
        -- The height tilemo's bar takes from the top of each display, or 0
        -- with the bar off (bar.lua).
        top = config.top or 0,
        rules = rules.check(config.rules or {}, "rules"),
        home_apps = M.check_home_apps(config.home_apps or M.HOME_APPS),
        standing = standing,
        -- The home workspace: the first standing one, "in" by default.
        home = standing[1],
        windows = {},   -- id -> { id, app, name, ws, floating, big }
        -- The workspaces that exist, in bar order: home, the standing
        -- ones made so far in their order, then the rest in the order they
        -- were made.
        names = {},
        workspaces = {}, -- name -> layout state
        screen_ws = {}, -- display uuid -> workspace name
        floats = {},    -- float ids, bottom to top
        mru = {},       -- workspace name -> ids, most recent first
        placed = {},    -- id -> the frame tilemo last gave it, as it landed
        -- id -> the minimizes and restores tilemo asked for that macOS hasn't
        -- reported yet, oldest first, each { kind = "min" or "unmin",
        -- token = n }. One entry per request: switching back and forth
        -- quickly can leave several of either kind outstanding.
        expect = {},
        tokens = 0,
        attention = attention.new(),
        history = {},   -- ids, most recently focused first, across workspaces
        -- The focus guard's inputs: when you last typed or clicked, when you
        -- last did something that switches apps, whether Command is down,
        -- the launch grant, the focuses tilemo asked for within M.GRACE, and
        -- the last window refused.
        last_input = -math.huge,
        last_switch = -math.huge,
        cmd_down = false,
        granted = nil,  -- { app (nil: any), at, first_only }
        asked = {},     -- { id, app, at }, oldest first
        last_steal = nil, -- { id, at }
    }, M)
    -- What the last run saved (snapshot()). Window ids may come back as
    -- strings from the settings store. A saved window that doesn't come back
    -- by id is matched by app and title until M.KEEP after this start.
    self.started = adapter.now()
    -- Home first, then the rest as saved.
    self.names[1] = self.home
    for _, name in ipairs(saved.names or {}) do
        if type(name) == "string" and not self:find(name) then
            self:add_name(name)
        end
    end
    -- Numbered workspaces left empty once their windows are back go after
    -- the first sync (SPEC.md §6.5).
    self.migrated = migrated
    -- The name prompt (SPEC.md §6.2): the questions waiting, oldest first,
    -- and the one being asked (ask_next). Windows found at start don't
    -- ask: init.lua sets `ready` once the first sync is done.
    self.ready = false
    self.asking = {}
    self.prompting = nil
    self.saved = {}
    for k, v in pairs(saved.windows or {}) do
        self.saved[tonumber(k) or k] = v
    end
    self.saved_screens = saved.screens or {}
    -- Places of windows whose app quit, each { app, title, ws, mine, pos,
    -- at }, oldest first, for the app's windows to take when it relaunches.
    self.gone = {}
    for _, g in ipairs(saved.gone or {}) do
        self.gone[#self.gone + 1] = g
    end
    -- id -> the place sync() paired a new window with.
    self.paired = {}
    -- The muted apps and sites (SPEC.md §14.2), and each browser window's
    -- front tab's host, as the switcher last saw it.
    self.muted = mute.empty()
    self.tab_hosts = {}
    self.attention.muted = function(m)
        return self:is_muted(m.app, m.id)
    end
    return self
end

-- Whether a mark for window `id` of `app` is muted: its app is in the
-- list, or it's a browser window whose front tab is on a muted site.
function M:is_muted(app, id)
    return mute.matches(self.muted, app, id and self.tab_hosts[id])
end

-- The muted list changed: marks it now covers go, and the bar shows it.
function M:set_muted(set)
    self.muted = set or mute.empty()
    self.attention:prune()
    self:changed()
end

-- The browser windows' front tabs, from the switcher's tab list: `tabs`
-- as launcher.parse_tabs gives them, with `win` the tilemo window and
-- `active` the front tab. Marks they now cover go.
function M:note_tabs(tabs)
    local changed = false
    for _, t in ipairs(tabs) do
        if t.active and t.win then
            local h = mute.host(t.url)
            if self.tab_hosts[t.win] ~= h then
                self.tab_hosts[t.win] = h
                changed = true
            end
        end
    end
    if changed then
        self.attention:prune()
        self:changed()
    end
end

local function center(box)
    return box.x + box.w / 2, box.y + box.h / 2
end

local function inside(box, x, y)
    return x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h
end

-- The displays, each one's tiling area below tilemo's bar when it's on.
function M:screens()
    local out = {}
    for i, s in ipairs(self.a.screens()) do
        out[i] = self.top > 0 and { uuid = s.uuid, area = bar.below(s.area, self.top), full = s.full } or s
    end
    return out
end

-- The display whose area holds a window's center, or the first display.
function M:screen_for(frame)
    local screens = self:screens()
    if frame then
        local x, y = center(frame)
        for _, s in ipairs(screens) do
            if inside(s.full, x, y) then
                return s
            end
        end
    end
    return screens[1]
end

function M:screen_by_uuid(uuid)
    for _, s in ipairs(self:screens()) do
        if s.uuid == uuid then
            return s
        end
    end
end

-- A workspace name as typed: one line, runs of space made one, trimmed.
-- Nil if nothing's left.
function M.clean_name(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:gsub("%s+", " "):match("^ ?(.-) ?$")
    return name ~= "" and name or nil
end

-- The workspace called `name` that exists, as it was made: names are
-- compared ignoring case (SPEC.md §6.1).
function M:find(name)
    name = M.clean_name(name)
    if not name then
        return nil
    end
    local want = M.fold(name)
    for _, n in ipairs(self.names) do
        if M.fold(n) == want then
            return n
        end
    end
end

-- The standing workspace called `name`, as the setting spells it, whether
-- it exists yet or not.
function M:standing_name(name)
    name = M.clean_name(name)
    if not name then
        return nil
    end
    local want = M.fold(name)
    for _, n in ipairs(self.standing) do
        if M.fold(n) == want then
            return n
        end
    end
end

-- The name a workspace called `name` has or would have: an existing one's,
-- a standing one's as the setting spells it, or the name as typed.
function M:canonical(name)
    return self:find(name) or self:standing_name(name) or M.clean_name(name)
end

-- Add `name` to the workspaces that exist, in bar order: a standing one
-- among the standing ones, in the setting's order, and any other at the
-- end.
function M:add_name(name)
    local s = self:standing_name(name)
    if not s then
        self.names[#self.names + 1] = name
        return name
    end
    local rank = {}
    for i, n in ipairs(self.standing) do
        rank[n] = i
    end
    local at = #self.names + 1
    for i, n in ipairs(self.names) do
        if not rank[n] or rank[n] > rank[s] then
            at = i
            break
        end
    end
    table.insert(self.names, at, s)
    return s
end

-- Every workspace the bar and the switcher list, in bar order: home, every
-- standing one, made yet or not, then the rest in the order they were
-- made. `made[name]` says which exist.
function M:listed()
    local out, made = {}, {}
    for _, n in ipairs(self.names) do
        made[n] = true
    end
    for _, n in ipairs(self.standing) do
        out[#out + 1] = n
    end
    for _, n in ipairs(self.names) do
        if not self:standing_name(n) then
            out[#out + 1] = n
        end
    end
    return out, made
end

-- Whether window `w` is one of home's apps, by its app's name.
function M:is_home_app(w)
    return w ~= nil and w.name ~= nil and self.home_apps[w.name] == true
end

-- Give each display a workspace, keeping the ones already given. The first
-- display shows home; a display with nothing of its own gets a new empty
-- workspace, named by the lowest number from 2 that's free, the number it
-- had before names (a guess: SPEC.md doesn't say what a second display
-- shows before anything is named for it).
function M:map_screens()
    local used = {}
    local screens = self:screens()
    local present = {}
    for _, s in ipairs(screens) do
        present[s.uuid] = true
    end
    -- A display that went away leaves its workspace hidden; Next and
    -- Previous, the bar and the menu show it on a display that's left.
    for uuid, n in pairs(self.screen_ws) do
        if present[uuid] and self:find(n) then
            used[n] = true
        else
            self.screen_ws[uuid] = nil
        end
    end
    -- A display tilemo saw last run shows what it showed then.
    for _, s in ipairs(screens) do
        local n = self:find(self.saved_screens[s.uuid])
        if not self.screen_ws[s.uuid] and n and not used[n] then
            used[n] = true
            self.screen_ws[s.uuid] = n
        end
    end
    for _, s in ipairs(screens) do
        if not self.screen_ws[s.uuid] then
            local n = self.home
            local i = 1
            while used[n] or (n ~= self.home and self:find(n)) do
                i = i + 1
                n = tostring(i)
            end
            used[n] = true
            self.screen_ws[s.uuid] = n
        end
        self:ensure_ws(self.screen_ws[s.uuid], s.area)
    end
    -- Every workspace has its layout state, in the default for the first
    -- display if none shows it.
    for _, n in ipairs(self.names) do
        self:ensure_ws(n, screens[1] and screens[1].area)
    end
end

-- Workspace `name`, made in its place in bar order (add_name), in the
-- default layout for `area`, if it's new. Returns its name as it was made.
function M:ensure_ws(name, area)
    local n = self:find(name)
    if not n then
        n = M.clean_name(name)
        if not n then
            return nil
        end
        n = self:add_name(n)
    end
    if not self.workspaces[n] then
        self.workspaces[n] = layout.new(n, area, self.layout)
        self.mru[n] = self.mru[n] or {}
    end
    return n
end

-- Whether any window is on workspace `n`, minimized by you or not.
function M:occupied(n)
    for _, w in pairs(self.windows) do
        if w.ws == n then
            return true
        end
    end
    return false
end

-- Note workspace `n` as the one used most recently.
function M:used_ws(n)
    self.ws_history = self.ws_history or {}
    remove_value(self.ws_history, n)
    table.insert(self.ws_history, 1, n)
end

-- The most recently used workspace that still exists, or is standing, and
-- that `skip(name)` doesn't rule out.
function M:last_used(skip)
    for _, n in ipairs(self.ws_history or {}) do
        if (self:find(n) or self:standing_name(n)) and not skip(n) then
            return n
        end
    end
end

-- Remove every empty workspace no display shows, other than the standing
-- ones, home included (SPEC.md §6.1).
function M:prune()
    for i = #self.names, 1, -1 do
        local n = self.names[i]
        if not self:standing_name(n) and not self:shown(n) and not self:occupied(n) then
            table.remove(self.names, i)
            self.workspaces[n] = nil
            self.mru[n] = nil
            remove_value(self.ws_history or {}, n)
        end
    end
end

-- After the first sync from a numbered state: a number left with no
-- windows, since its windows went home, is dropped, and a display showing
-- it shows home if no other display does (SPEC.md §6.5).
function M:finish_migration()
    if not self.migrated then
        return
    end
    self.migrated = false
    for uuid, n in pairs(self.screen_ws) do
        if not self:standing_name(n) and not self:occupied(n) and not self:shown(self.home) then
            self.screen_ws[uuid] = self.home
        end
    end
    self:prune()
end

-- Where `n` is in bar order, among the workspaces listed.
function M:index_of_ws(n)
    for i, m in ipairs((self:listed())) do
        if m == n then
            return i
        end
    end
end

-- The display showing workspace `n`, if one is.
function M:shown(n)
    for uuid, m in pairs(self.screen_ws) do
        if m == n then
            return uuid
        end
    end
end

function M:ws_on_screen(s)
    return s and self.screen_ws[s.uuid]
end

-- The workspace keys act on: the focused window's, else the one on the
-- display under the pointer.
function M:current_ws()
    local kbd = self:kbd_screen()
    if kbd then
        return self.screen_ws[kbd] or self.home
    end
    local w = self.windows[self.a.focused() or false]
    -- An ignored window, such as picture-in-picture, has no workspace.
    if w and w.ws then
        return w.ws
    end
    local uuid = self.a.pointer_screen()
    return self.screen_ws[uuid] or self.home
end

function M:screen_of_ws(n)
    for uuid, m in pairs(self.screen_ws) do
        if m == n then
            return self:screen_by_uuid(uuid)
        end
    end
end

-- The tiled windows of workspace `n` that are on screen, in order.
function M:tiled(n)
    local ws = self.workspaces[n]
    local out = {}
    if not ws then
        return out
    end
    for _, id in ipairs(ws.order) do
        local f = self.a.state(id)
        if f and not f.minimized and not f.fullscreen and not f.hidden then
            out[#out + 1] = id
        end
    end
    return out
end

-- Place a new float centered on its parent, the app's focused window, or on
-- its display, at what it asked for capped at 80% (SPEC.md §5.1).
function M:place_float(id, f)
    local s = self:screen_for(f.frame)
    local area = s.area
    local w = math.min(f.frame.w, math.floor(area.w * M.FLOAT_CAP))
    local h = math.min(f.frame.h, math.floor(area.h * M.FLOAT_CAP))
    local over = area
    local parent = self.a.app_focused(f.pid)
    if parent and parent ~= id then
        local pf = self.a.state(parent)
        if pf then
            over = pf.frame
        end
    end
    local cx, cy = center(over)
    local x = math.floor(cx - w / 2 + 0.5)
    local y = math.floor(cy - h / 2 + 0.5)
    -- Keep it on its display.
    x = math.max(area.x, math.min(x, area.x + area.w - w))
    y = math.max(area.y, math.min(y, area.y + area.h - h))
    self.a.set_frame(id, { x = x, y = y, w = w, h = h })
end

-- The workspace of a new float's parent: its app's focused window, as
-- place_float centers it on, if tilemo manages it.
function M:parent_ws(id, f)
    local parent = self.a.app_focused(f.pid)
    local p = parent and parent ~= id and self.windows[parent]
    return p and p.ws
end

-- Launches tilemo made, oldest first, each { app, ws, at }: the window a
-- launch opens goes to the workspace it was for (`ws`), whatever's showing
-- when it arrives. `app` is the bundle ID, or nil for a helper script,
-- whose window may be any app's. Each is used once, within M.GRANT.
function M:launch_to(app, ws)
    self.launches = self.launches or {}
    self.launches[#self.launches + 1] = { app = app, ws = ws, at = self.a.now() }
end

-- The workspace the oldest launch that window `w` may be from was for, if
-- any; `take` uses that launch up.
function M:launched_to(w, take)
    local now = self.a.now()
    local list = self.launches or {}
    for i = #list, 1, -1 do
        if now - list[i].at > M.GRANT then
            table.remove(list, i)
        end
    end
    for i, l in ipairs(list) do
        if l.app == nil or l.app == w.app then
            if take then
                table.remove(list, i)
            end
            return l.ws
        end
    end
end

-- Start managing a window. Returns what it was decided to be.
function M:add(id)
    if self.windows[id] then
        return self.windows[id].kind
    end
    local f = self.a.facts(id)
    if not f then
        return nil
    end
    local kind = rules.decide(f, self.rules)
    -- `seen`: when tilemo found it, so the focus guard can tell a window a
    -- launch opened from one that was already there.
    local w = { id = id, app = f.app, name = f.name, pid = f.pid, kind = kind, seen = self.a.now(), title = f.title }
    self.windows[id] = w
    if kind == "ignore" then
        return kind
    end
    local saved = self.paired[id] or self:match(id, f, function(sid)
        return self.a.state(sid) ~= nil
    end)
    self.paired[id] = nil
    if saved and saved.ws then
        -- tilemo restarted, or the app relaunched: the window goes back where
        -- it was. One of home's apps from a numbered state goes home.
        w.ws = (saved.numbered and self:is_home_app(w)) and self.home or saved.ws
        w.mine = saved.mine
        -- Its old index, and which save it's from: only indexes from the
        -- same save say which window went before which.
        w.saved_pos = saved.pos
        w.saved_at = saved.at or self.started
        w.ws = self:ensure_ws(w.ws, self:screen_for(f.frame).area)
    elseif kind == "float" and self:parent_ws(id, f) then
        -- A dialog goes where its parent is (SPEC.md §6.2), even for one of
        -- home's apps whose window you moved elsewhere.
        w.ws = self:parent_ws(id, f)
        w.mine = f.minimized or false
    elseif self:is_home_app(w) then
        -- Home's apps always open there (SPEC.md §6.2).
        w.ws = self.home
        w.mine = f.minimized or false
    elseif self:launched_to(w) then
        -- A launch tilemo made goes to the workspace it was for, even if
        -- you've moved on since, marked if that isn't showing (SPEC.md
        -- §6.1, §14.2).
        w.ws = self:ensure_ws(self:launched_to(w, true), self:screen_for(f.frame).area)
        w.mine = f.minimized or false
        if not self:shown(w.ws) then
            self.attention:activated(id, w.app)
        end
    else
        w.ws = self:ws_on_screen(self:screen_for(f.frame)) or self.home
        -- Minimized before tilemo knew it: you did that.
        w.mine = f.minimized or false
    end
    -- Any other app's new window on "in" asks for a name first. Dialogs and
    -- other floats go where their parent is, and a window coming back to
    -- its place doesn't ask.
    if self.ready and kind == "tile" and w.ws == self.home and not (saved and saved.ws) and not self:is_home_app(w) then
        self.asking[#self.asking + 1] = { window = id }
    end
    if kind == "float" then
        w.floating = true
        self.floats[#self.floats + 1] = id
        self:place_float(id, f)
    elseif saved and saved.ws and saved.pos then
        self:insert_back(id, w)
    else
        -- "next" goes after the window you were in. macOS may already have
        -- given the new window focus, so that's the workspace's last used.
        local ws = self.workspaces[w.ws]
        local anchor = self.a.focused()
        if anchor == id or not (anchor and layout.index_of(ws.order, anchor)) then
            anchor = self.mru[w.ws][1]
        end
        layout.insert(ws, id, anchor, self.layout)
    end
    -- Known windows go to the back of the recently-used list, so a
    -- workspace always has something to focus, even straight after a
    -- restart, before any focus history exists.
    local list = self.mru[w.ws]
    if list and not layout.index_of(list, id) then
        list[#list + 1] = id
    end
    return kind
end

-- How alike two titles are: the same title most, then by how much they
-- start and end alike.
local SAME_TITLE = 1e9
local function likeness(a, b)
    a, b = a or "", b or ""
    if a == b then
        return SAME_TITLE
    end
    local n = math.min(#a, #b)
    local p = 0
    while p < n and a:byte(p + 1) == b:byte(p + 1) do
        p = p + 1
    end
    local s = 0
    while s < n - p and a:byte(#a - s) == b:byte(#b - s) do
        s = s + 1
    end
    return p + s
end

-- The places a new window of `app` might take: saved ones whose window
-- hasn't come back (`live(id)` says whether one is still there), and those
-- of windows whose app quit, while they last.
function M:places(app, live)
    local now = self.a.now()
    local out = {}
    if now - self.started <= M.KEEP then
        for sid, s in pairs(self.saved) do
            if s.app == app and s.ws and not self.windows[sid] and not live(sid) then
                out[#out + 1] = { place = s, sid = sid }
            end
        end
    end
    for _, g in ipairs(self.gone) do
        if g.app == app and g.ws and now - (g.at or 0) <= M.KEEP then
            out[#out + 1] = { place = g }
        end
    end
    return out
end

-- Take a place, so no other window gets it.
function M:claim(c)
    if c.sid ~= nil then
        self.saved[c.sid] = nil
    else
        remove_value(self.gone, c.place)
    end
    return c.place
end

-- Where window `id` was (SPEC.md §6.3): its own saved place, if it's the
-- same app's, else the closest by title of its app's places.
-- The place saved under window `id`, if it's its app's. If the id is
-- another app's now, the window saved under it is gone, and its place
-- stays for that app.
function M:own_place(id, f)
    local s = self.saved[id]
    if not s then
        return nil
    end
    self.saved[id] = nil
    if s.app == nil or s.app == f.app then
        return s
    end
    s.at = self.started
    table.insert(self.gone, s)
end

function M:match(id, f, live)
    local s = self:own_place(id, f)
    if s then
        return s
    end
    local best, score
    for _, c in ipairs(self:places(f.app, live)) do
        local l = likeness(f.title, c.place.title)
        if not best or l > score then
            best, score = c, l
        end
    end
    return best and self:claim(best)
end

-- Pair the windows a sync found new with their places, closest titles
-- first, so the first window found can't take a place another fits
-- better.
function M:pair(ids, live)
    local pairs_ = {}
    local facts = {}
    for _, id in ipairs(ids) do
        local f = self.a.facts(id)
        if f and rules.decide(f, self.rules) ~= "ignore" then
            local s = self:own_place(id, f)
            if s then
                self.paired[id] = s
            else
                facts[id] = f
            end
        end
    end
    -- After every reused id has given up its place, so those count too.
    for id, f in pairs(facts) do
        for _, c in ipairs(self:places(f.app, live)) do
            pairs_[#pairs_ + 1] = { id = id, c = c, score = likeness(f.title, c.place.title) }
        end
    end
    table.sort(pairs_, function(p, q)
        return p.score > q.score
    end)
    local taken = {}
    for _, p in ipairs(pairs_) do
        if not self.paired[p.id] and not taken[p.c.place] then
            taken[p.c.place] = true
            self.paired[p.id] = self:claim(p.c)
        end
    end
end

-- Put a window coming back at its old index, or the end if the stack is
-- shorter now, but always after the windows from the same save that were
-- before it and before those that were after it, however they arrived.
-- Windows not from that save stay where they are.
function M:insert_back(id, w)
    local order = self.workspaces[w.ws].order
    local lo, hi = 1, #order + 1
    for i, other in ipairs(order) do
        local o = self.windows[other]
        if o and o.saved_pos and o.saved_at == w.saved_at then
            if o.saved_pos < w.saved_pos then
                lo = math.max(lo, i + 1)
            elseif o.saved_pos > w.saved_pos then
                hi = math.min(hi, i)
            end
        end
    end
    local at = math.min(w.saved_pos, #order + 1)
    at = math.max(lo, math.min(at, hi))
    table.insert(order, at, id)
end

-- Stop managing window `id`. `pos` is its place in its stack, if read
-- already, and `at` the time to save its place under.
function M:forget(id, pos, at)
    local w = self.windows[id]
    if not w then
        return
    end
    -- Its process quit: keep its place for when the app comes back, which
    -- may be running again already.
    if w.ws and w.app and not self.a.pid_running(w.pid) then
        table.insert(self.gone, {
            app = w.app,
            title = w.title,
            ws = w.ws,
            mine = w.mine or false,
            pos = pos or (self.workspaces[w.ws] and layout.index_of(self.workspaces[w.ws].order, id)),
            at = at or self.a.now(),
        })
        while #self.gone > M.KEEP_MAX do
            table.remove(self.gone, 1)
        end
    end
    self.windows[id] = nil
    if w.ws and self.workspaces[w.ws] then
        layout.remove(self.workspaces[w.ws], id)
        remove_value(self.mru[w.ws], id)
    end
    remove_value(self.floats, id)
    self.placed[id] = nil
    remove_value(self.history, id)
    self.attention:gone(id)
    self.tab_hosts[id] = nil
end

-- Match what tilemo knows to the windows that exist now: add new ones, forget
-- gone ones. Window events call this rather than trusting each event's
-- window, since a destroyed window can no longer say who it was.
-- Returns the workspaces that lost a window.
-- Forget the windows not in `live`, keeping the places of those whose
-- process quit. Every gone window's place in its stack is read before any
-- leaves it, and they share one time, so their indexes order them.
-- Returns the workspaces that lost a window.
function M:collect_gone(live)
    local lost = {}
    local gone, pos = {}, {}
    for id, w in pairs(self.windows) do
        if not live[id] then
            gone[#gone + 1] = id
            pos[id] = w.ws and self.workspaces[w.ws] and layout.index_of(self.workspaces[w.ws].order, id)
        end
    end
    local now = self.a.now()
    for _, id in ipairs(gone) do
        local w = self.windows[id]
        if w.ws then
            lost[w.ws] = true
        end
        self:forget(id, pos[id], now)
    end
    return lost
end

function M:sync()
    self:map_screens()
    local live = {}
    local ids = self.a.windows()
    local new = {}
    for _, id in ipairs(ids) do
        live[id] = true
        if not self.windows[id] then
            new[#new + 1] = id
        end
    end
    -- Windows that went go first, so their places are there for windows
    -- coming back in the same sync, such as a relaunched app's.
    local lost = self:collect_gone(live)
    self:pair(new, function(sid)
        return live[sid] == true
    end)
    -- Windows coming back go first, lowest old index first, so each lands
    -- at its index; the rest follow in the order macOS lists them.
    local first, rest = {}, {}
    for _, id in ipairs(ids) do
        local p = self.paired[id]
        if p and p.pos then
            first[#first + 1] = id
        else
            rest[#rest + 1] = id
        end
    end
    local seq = {}
    for i, id in ipairs(first) do
        seq[id] = i
    end
    table.sort(first, function(p, q)
        local a, b = self.paired[p].pos, self.paired[q].pos
        if a ~= b then
            return a < b
        end
        return seq[p] < seq[q]
    end)
    for _, list in ipairs({ first, rest }) do
        for _, id in ipairs(list) do
            self:add(id)
        end
    end
    self:finish_migration()
    return lost
end

-- Make the screen match the state (SPEC.md §6.1): a window shows if its
-- workspace is showing on some display and you haven't minimized it.
-- Restores go first, in tile order, then the rest are minimized.
function M:reconcile()
    local restore, hide = {}, {}
    for id, w in pairs(self.windows) do
        if w.ws then
            local st = self.a.state(id)
            if st then
                local want = self:shown(w.ws) ~= nil and not w.mine
                if want and st.minimized and self:last_asked(id) ~= "unmin" then
                    restore[#restore + 1] = id
                elseif not want and not st.minimized and self:last_asked(id) ~= "min" then
                    hide[#hide + 1] = id
                end
            end
        end
    end
    local function rank(id)
        local w = self.windows[id]
        return layout.index_of(self.workspaces[w.ws].order, id) or 1000
    end
    table.sort(restore, function(p, q)
        return rank(p) < rank(q)
    end)
    -- An expectation lapses if macOS never reports the change, so a later
    -- minimize of yours isn't mistaken for tilemo's.
    local function expect(id, kind)
        -- Each request gets its own token, so an older request's timeout
        -- can't clear a newer one's expectation.
        self.tokens = self.tokens + 1
        local token = self.tokens
        self.expect[id] = self.expect[id] or {}
        table.insert(self.expect[id], { kind = kind, token = token })
        -- A request that lapsed may have held back a later one in reconcile,
        -- so look again rather than leave the screen out of step.
        self.a.after(M.EXPECT, function()
            if self:settle_request(id, function(r)
                return r.token == token
            end) and not self.timer then
                self:schedule()
            end
        end)
    end
    for _, id in ipairs(restore) do
        expect(id, "unmin")
        self.a.unminimize(id)
    end
    table.sort(hide)
    for _, id in ipairs(hide) do
        expect(id, "min")
        self.a.minimize(id)
    end
    self:prune()
    self:save()
end

-- What a restart needs to put every window back: each window's workspace,
-- flag and place in its stack, with its app and title to match it by if
-- it comes back with a new id, and the places still kept for windows that
-- haven't come back.
function M:snapshot()
    local out = { windows = {}, screens = {}, gone = {}, names = nil }
    local now = self.a.now()
    -- A window's index is where it is now, so a stack you rearranged stays
    -- that way. (Windows still to come back after a restart partway through
    -- may land out of order: see TODO.md.)
    for id, w in pairs(self.windows) do
        if w.ws then
            out.windows[id] = {
                ws = w.ws,
                mine = w.mine or false,
                app = w.app,
                title = w.title,
                pos = not w.floating and layout.index_of(self.workspaces[w.ws].order, id) or nil,
            }
        end
    end
    if now - self.started <= M.KEEP then
        for sid, s in pairs(self.saved) do
            if s.ws and s.app and not self.windows[sid] then
                out.gone[#out.gone + 1] = {
                    app = s.app, title = s.title, ws = s.ws, mine = s.mine, pos = s.pos, at = s.at or self.started,
                    numbered = s.numbered,
                }
            end
        end
    end
    for _, g in ipairs(self.gone) do
        if now - (g.at or 0) <= M.KEEP then
            out.gone[#out.gone + 1] = g
        end
    end
    for uuid, n in pairs(self.screen_ws) do
        out.screens[uuid] = n
    end
    out.names = {}
    for i, n in ipairs(self.names) do
        out.names[i] = n
    end
    return out
end

function M:save()
    if self.a.save then
        self.a.save(self:snapshot())
    end
end

-- The newest of tilemo's outstanding requests for `id`, if any: a restore
-- asked after a hide supersedes it, though both reports are still due.
function M:last_asked(id)
    local e = self.expect[id]
    return e and e[#e].kind
end

-- Drop the oldest outstanding request for `id` that `match` picks, and say
-- whether there was one.
function M:settle_request(id, match)
    local e = self.expect[id]
    for i, r in ipairs(e or {}) do
        if match(r) then
            table.remove(e, i)
            if #e == 0 then
                self.expect[id] = nil
            end
            return true
        end
    end
    return false
end

-- Take macOS's report of `kind` as the answer to tilemo's oldest request of
-- that kind, if there is one, and say whether there was.
function M:acknowledge(id, kind)
    return self:settle_request(id, function(r)
        return r.kind == kind
    end)
end

-- macOS says a window was minimized. If tilemo didn't ask, you did.
function M:minimized(id)
    if self:acknowledge(id, "min") then
        -- Its workspace may have come back meanwhile.
        self:schedule()
        return
    end
    local w = self.windows[id]
    -- One already yours keeps its place in the tray.
    if w and w.ws and not w.mine then
        self:mark_mine(id)
        self:save()
    end
    self:schedule()
end

-- Window `id` is one you minimized: it goes into its display's tray, after
-- the ones before it (SPEC.md §6.7).
function M:mark_mine(id)
    local w = self.windows[id]
    self.min_seq = (self.min_seq or 0) + 1
    w.mine = true
    w.min_at = self.min_seq
end

-- The windows you minimized on workspace `n`, in the order you minimized
-- them; ones minimized before tilemo saw them first, by id.
function M:minimized_windows(n)
    local out = {}
    for id, w in pairs(self.windows) do
        if n and w.ws == n and w.mine and self.a.state(id) then
            out[#out + 1] = id
        end
    end
    table.sort(out, function(p, q)
        local a, b = self.windows[p].min_at or 0, self.windows[q].min_at or 0
        if a ~= b then
            return a < b
        end
        return tostring(p) < tostring(q)
    end)
    return out
end

-- macOS says a window came back. If tilemo didn't ask, you restored it from
-- the Dock or Cmd+Tab: clear the flag, and bring its workspace along.
function M:unminimized(id)
    if self:acknowledge(id, "unmin") then
        -- A restore can finish after show() laid out and focused without it.
        if self.focus_after == id then
            self.focus_after = nil
            self:focus_window(id)
        end
        self:schedule()
        return
    end
    local w = self.windows[id]
    if w and w.ws then
        w.mine = false
        if not self:shown(w.ws) then
            self:activate(id)
            return
        end
    end
    self:schedule()
end

-- When tilemo quits, nothing stays stranded in the Dock (SPEC.md §6.3).
function M:restore_all()
    for id, w in pairs(self.windows) do
        local st = w.ws and not w.mine and self.a.state(id)
        if st and st.minimized then
            self.a.unminimize(id)
        end
    end
end

-- The display a switch left keys on, while focus hasn't moved since: a
-- switch to an empty workspace, or a Send that empties this one, leaves
-- focus on a window on the other display.
function M:kbd_screen()
    local k = self.kbd
    if k and k.focused == self.a.focused() and self:screen_by_uuid(k.uuid) then
        return k.uuid
    end
    self.kbd = nil
end

-- Keep keys on display `uuid` until focus moves.
function M:keep_keys_on(uuid)
    self.kbd = { uuid = uuid, focused = self.a.focused() }
    -- The current workspace changed with it, for the bar and the file
    -- scripts read.
    self:changed()
end

-- The display keys act on: the focused window's, else the pointer's. After
-- showing an empty workspace, it's that display until focus moves.
function M:current_screen()
    local kbd = self:kbd_screen()
    if kbd then
        return kbd
    end
    local w = self.windows[self.a.focused() or false]
    if w and w.ws then
        local uuid = self:shown(w.ws)
        if uuid then
            return uuid
        end
    end
    return self.a.pointer_screen() or (self:screens()[1] or {}).uuid
end

-- Show workspace `name` on display `uuid`. If another display shows it,
-- the two swap, as on tide. A name with no workspace does nothing, unless
-- `make` says to make it, as the name prompt does (SPEC.md §6.2).
function M:show(name, uuid, make)
    uuid = uuid or self:current_screen()
    local s = self:screen_by_uuid(uuid)
    local n = self:find(name)
    -- A standing workspace is made the first time it's shown.
    if not n and (make or self:standing_name(name)) then
        n = self:ensure_ws(self:canonical(name), s and s.area)
    end
    if not s or not n then
        return
    end
    local cur = self.screen_ws[uuid]
    if cur == n then
        return
    end
    local other = self:shown(n)
    if other then
        self.screen_ws[other] = cur
    end
    self.screen_ws[uuid] = n
    -- The one left, then the one shown, most recent first, for Super+Tab
    -- and Super+End.
    if cur then
        self:used_ws(cur)
    end
    self:used_ws(n)
    self:reconcile()
    self:retile()
    -- With nothing there to focus, focus stays put, perhaps on a window the
    -- swap carried to the other display: keys still mean this one.
    if not self:refocus_ws(n) then
        self:keep_keys_on(uuid)
    end
    -- The display it was shown on: focus may have stayed on the other one.
    if self.on_show then
        self.on_show(n, uuid)
    end
end

-- Focus workspace n's last used window, if it has one, and say whether it
-- did. If that window is still being restored, it's focused when the
-- restore lands; a later switch replaces the wait.
function M:refocus_ws(n)
    self.focus_after = nil
    self.kbd = nil
    for _, id in ipairs(self.mru[n] or {}) do
        local w = self.windows[id]
        local st = w and w.ws == n and not w.mine and self.a.state(id)
        -- An app you hid with Cmd+H stays hidden: pass over its windows.
        if st and not st.hidden then
            if st.minimized then
                self.focus_after = id
            else
                self:focus_window(id)
            end
            return true
        end
    end
    return false
end

-- Move window `id` to the end of workspace `name`'s stack, making the
-- workspace, at the end of the list, if the name is new. Only home's apps
-- may be sent home (SPEC.md §6.2); another app's window is refused, with
-- a notice. Says whether the window moved. `defer` leaves the screen to
-- the caller's next reconcile, for a Send followed by a Show, so the window
-- isn't minimized and restored between the two.
function M:send(id, name, defer)
    local w = self.windows[id or false]
    local n = self:canonical(name)
    if not w or not w.ws or not n or w.ws == n then
        return false
    end
    if n == self.home and not self:is_home_app(w) then
        if self.a.notify then
            self.a.notify("Only the home workspace's apps go on " .. self.home)
        end
        return false
    end
    local from = w.ws
    layout.remove(self.workspaces[from], id)
    remove_value(self.mru[from], id)
    local s = self:screen_by_uuid(self:current_screen())
    n = self:ensure_ws(n, s and s.area)
    w.ws = n
    w.big = nil
    if not w.floating then
        -- A window you send joins the end of the stack there, whatever
        -- new_window says: that's for windows that open.
        layout.insert(self.workspaces[n], id, nil, { new_window = "end" })
    end
    table.insert(self.mru[n], 1, id)
    if not defer then
        self:reconcile()
        self:retile()
    end
    return true
end

-- Bring a window forward, with its workspace if that isn't showing: app
-- keys, Super+Tab, Cmd+Tab, a Dock click, a notification. A hidden
-- workspace comes to display `uuid` if given, else where the keys act.
function M:activate(id, uuid)
    local w = self.windows[id]
    if not w or not w.ws then
        return
    end
    w.mine = false
    if not self:shown(w.ws) then
        local list = self.mru[w.ws]
        remove_value(list, id)
        table.insert(list, 1, id)
        self:show(w.ws, uuid)
    else
        self:reconcile()
        self:retile()
    end
    self:focus_window(id)
end

-- A workspace's floats go to the display showing it, keeping their place
-- relative to the display they were on, so a dialog stays with its parent
-- when workspaces swap displays.
function M:follow_floats()
    for _, id in ipairs(self.floats) do
        local w = self.windows[id]
        local uuid = w and w.ws and self:shown(w.ws)
        local st = uuid and self.a.state(id)
        if st and not st.minimized then
            local to = self:screen_by_uuid(uuid)
            local from = self:screen_for(st.frame)
            if to and from and from.uuid ~= to.uuid then
                local f = st.frame
                local a = to.area
                local x = a.x + (f.x - from.area.x)
                local y = a.y + (f.y - from.area.y)
                x = math.max(a.x, math.min(x, a.x + a.w - f.w))
                y = math.max(a.y, math.min(y, a.y + a.h - f.h))
                self.a.set_frame(id, { x = x, y = y, w = f.w, h = f.h })
            end
        end
    end
end

-- Lay out every display, moving only windows that aren't already where
-- they belong.
function M:retile()
    self:follow_floats()
    for uuid, n in pairs(self.screen_ws) do
        local s = self:screen_by_uuid(uuid)
        local ws = self.workspaces[n]
        if s and ws then
            local ids = self:tiled(n)
            local boxes = layout.arrange(ws, s.area, ids, self.layout)
            for _, id in ipairs(ids) do
                local w = self.windows[id]
                local box = boxes[id]
                if w.big == "max" then
                    box = s.area
                elseif w.big == "full" then
                    box = s.full
                end
                local f = self.a.state(id)
                local cur = f and f.frame
                if not cur or cur.x ~= box.x or cur.y ~= box.y or cur.w ~= box.w or cur.h ~= box.h then
                    self.a.set_frame(id, box)
                    -- Read it back: an app may round the size, and the move
                    -- this causes mustn't look like a drag.
                    local after = self.a.state(id)
                    cur = after and after.frame or box
                end
                self.placed[id] = cur
            end
        end
    end
    -- Windows may have moved under a still pointer; that isn't a crossing.
    if self.ffm then
        self.ffm:resync()
    end
    self:changed()
end

-- Something the menu bar shows may have changed.
function M:changed()
    if self.on_change then
        self.on_change()
    end
end

-- What the bar shows (bar.lua): for each workspace, whether it's on
-- display `uuid` or another, has windows, or wants attention. With no
-- display named, "here" is where the keys act, as for the menu bar item
-- and Super+Shift+Space; a bar or a dashboard on a given display names it.
function M:bar_state(uuid)
    local here = self.screen_ws[uuid or self:current_screen()]
    local out, by = {}, {}
    for i, n in ipairs((self:listed())) do
        out[i] = { name = n, here = n == here, elsewhere = n ~= here and self:shown(n) ~= nil }
        by[n] = out[i]
    end
    for _, w in pairs(self.windows) do
        if w.ws and by[w.ws] then
            by[w.ws].occupied = true
        end
    end
    for _, m in ipairs(self.attention:list()) do
        local ids = m.id and { m.id } or self:app_windows(m.app)
        local w = ids[1] and self.windows[ids[1]]
        if w and w.ws and by[w.ws] then
            by[w.ws].urgent = true
        end
    end
    return out
end

-- Coalesce a burst of events into one sync and retile.
function M:schedule()
    if self.timer then
        self.timer:stop()
    end
    self.timer = self.a.after(M.DEBOUNCE, function()
        self.timer = nil
        local lost = self:sync()
        self:reconcile()
        self:retile()
        for n in pairs(lost) do
            self:refocus(n)
        end
        self:ask_next()
    end)
end

-- The name prompt (SPEC.md §6.2) ---------------------------------------------

-- Every question for the prompt waits its turn in `asking`, oldest first:
-- { window = id } for a window opening on home, { launch = opts, go = fn }
-- for a launch. There's one prompt, so asking a second question while one
-- is open would replace it, and the replaced one would read as Esc,
-- closing a window or canceling a launch.

-- Ask the next question waiting, if nothing is being asked already.
-- `ask_name(id)` and `ask_launch(default, done)`, from init.lua, open the
-- prompt. It holds the keyboard, so focus follows mouse pauses.
function M:ask_next()
    if self.prompting then
        return
    end
    while #self.asking > 0 do
        local q = table.remove(self.asking, 1)
        if q.window then
            local w = self.windows[q.window]
            if w and w.ws == self.home and self.ask_name then
                self.prompting = q
                self:hold("prompt", true)
                self.ask_name(q.window)
                return
            end
        elseif q.move then
            if self.windows[q.move] and self.ask_move then
                self.prompting = q
                self:hold("prompt", true)
                self.ask_move(function(name)
                    self:move_answer(q, name)
                end)
                return
            end
        elseif self.ask_launch then
            self.prompting = q
            self:hold("prompt", true)
            self.ask_launch(q.launch.default or "", function(name)
                self:launch_answer(q, name)
            end)
            return
        end
    end
end

-- Done with question `q`: let the keyboard go, and ask the next.
function M:asked_done(q)
    if self.prompting == q then
        self.prompting = nil
        self:hold("prompt", false)
    end
end

-- A name typed at the prompt for question `q` that holds what a name
-- can't (names.UNSAFE) is refused, said so, and asked again, with those
-- characters dropped where the question has a default of its own to show.
-- True if refused.
function M:refuse_unsafe(q, name)
    if not (name and names.unsafe(M.clean_name(name) or "")) then
        return false
    end
    self:asked_done(q)
    if self.a.notify then
        self.a.notify(names.UNSAFE_MESSAGE)
    end
    if q.launch then
        q.launch.default = M.clean_name(names.safe(name)) or ""
    end
    table.insert(self.asking, 1, q)
    self:ask_next()
    return true
end

-- The prompt's answer for window `id`: a name moves it there, making the
-- workspace if it's new, and shows it, on the display home was on, with
-- focus; nil (Esc) closes the window, politely. Home itself is refused,
-- and asked again, as is a name with what a name can't hold.
function M:answer(id, name)
    local q = self.prompting
    if not (q and q.window == id) then
        return
    end
    if self:refuse_unsafe(q, name) then
        return
    end
    self:asked_done(q)
    local w = self.windows[id]
    if w and w.ws == self.home then
        if name == nil then
            self.a.close(id)
        else
            local n = self:canonical(name)
            if n == self.home or not n then
                if n then
                    self.a.notify(self.home .. " is for its own apps: give this window another name")
                end
                table.insert(self.asking, 1, q)
            else
                local uuid = self:shown(self.home)
                if self:send(id, n, true) then
                    self:show(self.windows[id].ws, uuid)
                    -- Already showing there, show() had nothing to do.
                    self:reconcile()
                    self:retile()
                    self:focus_window(id)
                end
            end
        end
    end
    self:ask_next()
end

-- The prompt's answer for launch question `q`: a name shows that
-- workspace, making it if it's new, then launches with its
-- TIDE_WORKSPACE; nil (Esc) launches nothing.
function M:launch_answer(q, name)
    if self.prompting ~= q or self:refuse_unsafe(q, name) then
        return
    end
    self:asked_done(q)
    local n = name and self:canonical(name)
    if n == self.home and not q.launch.home_app then
        self.a.notify(self.home .. " is for its own apps: nothing was opened")
    elseif n then
        self:show(n, nil, true)
        n = self:find(n) or n
        self:launch_to(q.launch.app, n)
        q.go(self:env(n))
    end
    self:ask_next()
end

-- The prompt's answer for Super+Return's question `q`: a name sends the
-- window there, as A.send does; nil (Esc) leaves it.
function M:move_answer(q, name)
    if self.prompting ~= q or self:refuse_unsafe(q, name) then
        return
    end
    self:asked_done(q)
    if name and self.windows[q.move] then
        self:send_keeping_focus(q.move, name)
    end
    self:ask_next()
end

-- TIDE_WORKSPACE for a process tilemo starts on workspace `n` (SPEC.md §6.3):
-- empty, and logged, when the name's letters and digits can't be found.
function M:env(n)
    local value, err = names.sanitize(n, self.a.javascript)
    if err then
        self.a.log("TIDE_WORKSPACE is empty: " .. err)
    end
    return { TIDE_WORKSPACE = value }
end

-- Before a launch tilemo makes (the switcher's Launch tab, an app key,
-- Cmd+Return), the workspace it's for (SPEC.md §6.2, §9): from home, or
-- for Cmd+Return (`opts.fresh`) from anywhere, it asks for a name first,
-- with `opts.default` typed in, unless the app is one of home's
-- (`opts.home_app`, and never for Cmd+Return). `opts.app` is the bundle
-- ID, if known, which the launch's window is matched by (launch_to). The question waits its turn
-- behind any other. A name shows that workspace, making it if it's new,
-- then `go(env)` launches with its TIDE_WORKSPACE; Esc launches nothing.
-- Elsewhere it launches straight away, on the workspace you're on.
function M:before_launch(opts, go)
    local cur = self:current_ws()
    local ask = opts.fresh or (cur == self.home and not opts.home_app)
    if not ask or not self.ask_launch then
        self:launch_to(opts.app, cur)
        go(self:env(cur))
        return
    end
    self.asking[#self.asking + 1] = { launch = opts, go = go }
    self:ask_next()
end

-- The mouse (SPEC.md §5.3) --------------------------------------------------

local function same(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- The managed window under a point: the frontmost visible window there,
-- or nil if that one is ignored or unknown, such as picture-in-picture
-- over a tile.
function M:window_at(x, y)
    for _, id in ipairs(self.a.ordered()) do
        local st = self.a.state(id)
        if st and not st.minimized and not st.hidden and inside(st.frame, x, y) then
            local w = self.windows[id]
            if w and w.kind ~= "ignore" and w.ws then
                return id
            end
            return nil
        end
    end
end

-- A tile the user moved or resized to `box`, by its own edges or with
-- Super+drag. A resize sets the split; a move puts the window in the tile
-- nearest where its center landed, swapping with that tile's window, or on
-- the workspace of the display it landed on.
function M:request(id, box)
    local w = self.windows[id]
    if not w or not w.ws or w.floating then
        return
    end
    local old = self.placed[id]
    local cx, cy = center(box)
    local s = self:screen_for(box)
    local n = self:ws_on_screen(s)
    -- Another display first: macOS may resize a window it moves onto a
    -- smaller display, and that's still a move.
    if n and n ~= w.ws then
        layout.remove(self.workspaces[w.ws], id)
        remove_value(self.mru[w.ws], id)
        w.ws = n
        layout.insert(self.workspaces[n], id, nil, self.layout)
        -- Focused already, so no focus event will put it in n's history.
        table.insert(self.mru[n], 1, id)
        self:save()
    elseif old and (old.w ~= box.w or old.h ~= box.h) then
        local ws = self.workspaces[w.ws]
        local ids = self:tiled(w.ws)
        local i = layout.index_of(ids, id)
        if s and i and #ids == 1 then
            -- A lone window: the drag sets its width on this workspace.
            ws.single_width = mouse.single_width_for(s.area, old, box) or ws.single_width
        else
            local f = s and i and mouse.mfact_for(ws.mode, ws.opts[ws.mode] or {}, i, #ids, s.area, old, box)
            if f then
                ws.opts[ws.mode].mfact = layout.geometry.clamp(f, 0.1, 0.9)
            end
        end
    elseif n then
        local ws = self.workspaces[n]
        local ids = self:tiled(n)
        local boxes = layout.arrange(ws, s.area, ids, self.layout)
        for _, other in ipairs(ids) do
            if other ~= id and inside(boxes[other], cx, cy) then
                local a, b = layout.index_of(ws.order, id), layout.index_of(ws.order, other)
                ws.order[a], ws.order[b] = ws.order[b], ws.order[a]
                break
            end
        end
    end
    self:retile()
end

-- macOS says a window moved or changed size. Ignore the moves tilemo made;
-- treat the rest as a request, once the button is up.
-- A float you moved to another display joins the workspace showing there,
-- so following workspaces between displays doesn't pull it back.
function M:float_landed(id)
    local w = self.windows[id]
    local st = w and w.floating and self.a.state(id)
    if not st then
        return
    end
    local n = self:ws_on_screen(self:screen_for(st.frame))
    if n and n ~= w.ws then
        remove_value(self.mru[w.ws], id)
        w.ws = n
        table.insert(self.mru[n], 1, id)
        self:save()
    end
end

function M:moved(id)
    local w = self.windows[id]
    if w and w.floating then
        if not self.a.buttons_down() then
            self:float_landed(id)
        end
        -- A float that moved changes what's under the pointer.
        if self.ffm then
            self.ffm:resync()
        end
    end
    if not w or not w.ws or w.floating then
        return
    end
    local st = self.a.state(id)
    if not st or same(st.frame, self.placed[id]) then
        return
    end
    if self.a.buttons_down() then
        self.a.after(0.1, function()
            self:moved(id)
        end)
        return
    end
    self:request(id, st.frame)
end

-- A Super+drag or Super+right-drag starting at x, y. Returns the drag, or
-- nil if there's no window there.
function M:grab(kind, x, y)
    local id = self:window_at(x, y)
    local st = id and self.a.state(id)
    if not st then
        return nil
    end
    local d = mouse.grab(kind, st.frame, x, y)
    d.id = id
    return d
end

-- The drag ended with the pointer at x, y.
function M:drop(d, x, y)
    local box = mouse.update(d, x, y)
    local w = self.windows[d.id]
    if not w then
        return
    end
    if w.floating then
        self.a.set_frame(d.id, box)
        -- Dropped on another display, it joins the workspace there.
        self:float_landed(d.id)
        if self.ffm then
            self.ffm:resync()
        end
    else
        self:request(d.id, box)
    end
end

-- Super+middle-click: maximize the window under the pointer, or put it back.
function M:maximize_at(x, y)
    local id = self:window_at(x, y)
    if id then
        self:focus_window(id)
        set_big_on(self, id, "max")
    end
end

-- Raise the workspace's floats over its tiles, keeping their order, so a
-- dialog never ends up behind the window that opened it (SPEC.md §5.1).
-- The focused window's own floats go last, on top.
function M:raise_floats(n, pid)
    local mine = {}
    for _, id in ipairs(self.floats) do
        local w = self.windows[id]
        if w and w.ws == n then
            if pid and w.pid == pid then
                mine[#mine + 1] = id
            else
                self.a.raise(id)
            end
        end
    end
    for _, id in ipairs(mine) do
        self.a.raise(id)
    end
    -- The stacking changed under a still pointer.
    if self.ffm then
        self.ffm:resync()
    end
end

-- Hold the keyboard for `owner` (the launcher, the dashboard, resize mode)
-- or let it go. Focus follows mouse pauses while anyone holds it, so one
-- overlay closing can't release another's hold.
function M:hold(owner, on)
    self.holds = self.holds or {}
    self.holds[owner] = on or nil
    self.holding_keyboard = next(self.holds) ~= nil
end

function M:focus_window(id)
    local w = self.windows[id]
    if not w then
        return
    end
    -- Focusing something else is a newer choice than a slow restore.
    if self.focus_after ~= id then
        self.focus_after = nil
    end
    -- The focus report this causes is tilemo's, not an app helping itself,
    -- and moving focus ends a launch's grant. Every ask within M.GRACE is
    -- kept, not just the last: focus follows mouse starts its next focus
    -- as soon as macOS confirms one, or once its wait runs out, which can be
    -- before tilemo has heard the report for the one before.
    local now = self.a.now()
    local asked = {}
    for _, q in ipairs(self.asked) do
        if q.id ~= id and now - q.at <= M.GRACE then
            asked[#asked + 1] = q
        end
    end
    asked[#asked + 1] = { id = id, app = w.app, at = now }
    self.asked = asked
    self.granted = nil
    self.a.focus(id)
    if not w.floating then
        self:raise_floats(w.ws, w.pid)
    elseif w.kind ~= "float" then
        -- A window you floated keeps its app's dialogs over it.
        local raised = false
        for _, fid in ipairs(self.floats) do
            local f = self.windows[fid]
            if fid ~= id and f and f.kind == "float" and f.pid == w.pid and f.ws == w.ws then
                self.a.raise(fid)
                raised = true
            end
        end
        if raised and self.ffm then
            self.ffm:resync()
        end
    end
end

-- A click: whatever it picks is newer than a restore still on its way,
-- and than a switch that kept keys on its display. (A focus report alone
-- can't say this: macOS moves focus itself as tilemo minimizes, and a click
-- on the window that already has focus reports nothing.)
function M:clicked()
    self.focus_after = nil
    self.kbd = nil
    -- A click is yours, and so is what it starts: a Dock icon, a link, a
    -- notification.
    local now = self.a.now()
    self.last_input = now
    self.last_switch = now
    self:grant(nil, true)
end

-- The focus guard (SPEC.md §14.1) -------------------------------------------

-- A launch you made: a window of `app` (of any app, when tilemo can't tell
-- which, as for a helper script) may take focus within M.GRANT, once, if
-- you haven't typed, clicked or moved focus since. `first_only` limits it
-- to an app with no window open before the grant, for a launch guessed
-- from the click or Return that may have started it outside tilemo (the
-- Dock, Spotlight, Finder); every window that launch opens counts.
function M:grant(app, first_only)
    self.granted = { app = app, at = self.a.now(), first_only = first_only or false }
end

-- A key went down. Typing ends a launch's grant. A key with Command held
-- (Cmd+Tab, tilemo's own keys) or Return (Spotlight, a file in Finder) is a
-- choice, so what it activates is yours.
function M:key_down(key, cmd)
    local now = self.a.now()
    self.last_input = now
    if cmd or key == "return" or key == "padenter" then
        self.last_switch = now
        self:grant(nil, true)
    end
end

-- Command went down or up. Cmd+Tab activates the app when you let go.
function M:modifiers(cmd)
    if cmd or self.cmd_down then
        self.last_switch = self.a.now()
    end
    self.cmd_down = cmd or false
end

-- Whether `app` had a window open before time `t`: if so, a window of
-- its now isn't from a launch at `t`, however many the launch opened.
function M:open_before(app, t)
    for _, o in pairs(self.windows) do
        if o.app == app and o.seen < t then
            return true
        end
    end
    return false
end

-- Whether window `id` may keep the focus macOS just gave it: yes for
-- anything you asked for, no for an app activating itself.
function M:may_focus(id, w)
    local prev = self.history[1]
    local p = prev and self.windows[prev]
    -- The window you were in, or another of its app's: a dialog, a second
    -- window.
    if not p or prev == id or p.app == w.app then
        return true
    end
    -- The window you were in went away (closed, minimized, hidden, its
    -- workspace switched away), so macOS moving focus on isn't theft.
    local st = self.a.state(prev)
    if not st or st.minimized or st.hidden or p.mine or not (p.ws and self:shown(p.ws)) then
        return true
    end
    local now = self.a.now()
    for _, q in ipairs(self.asked) do
        if now - q.at <= M.GRACE and (q.id == id or q.app == w.app) then
            return true
        end
    end
    if self.cmd_down or now - self.last_switch <= M.GRACE then
        return true
    end
    local g = self.granted
    if g and now - g.at <= M.GRANT and self.last_input <= g.at
        and (g.app == nil or g.app == w.app)
        and not (g.first_only and self:open_before(w.app, g.at)) then
        -- Used once.
        self.granted = nil
        return true
    end
    return false
end

-- Window `id` took focus unasked: mark it, and hand focus back to the
-- window you were in. While the launcher, dashboard or resize mode holds
-- the keyboard, it's only marked: those overlays keep their own focus.
function M:refuse(id, w)
    self.attention:activated(id, w.app)
    self:changed()
    local now = self.a.now()
    local last = self.last_steal
    self.last_steal = { id = id, at = now }
    -- One that takes focus straight back is left with it, marked, rather
    -- than fought over.
    if last and last.id == id and now - last.at <= M.GRACE then
        self.a.log("letting " .. tostring(w.app) .. " keep the focus it took back")
        -- It's the window you're in now, so its own dialogs may follow.
        remove_value(self.history, id)
        table.insert(self.history, 1, id)
        return
    end
    if self.holding_keyboard then
        return
    end
    self.a.log("handing focus back from " .. tostring(w.app))
    -- Not a focus you moved, so it doesn't end a launch's grant.
    local g = self.granted
    self:focus_window(self.history[1])
    self.granted = g
end

-- Called when macOS reports a window gained focus, by tilemo or by a click
-- or app switch. A window too new to have been synced is added now, so its
-- focus isn't lost.
function M:focused(id)
    self:focused_window(id)
    self:ask_next()
end

function M:focused_window(id)
    if not self.windows[id] then
        self:map_screens()
        -- A relaunched app focuses its first window before the next sync:
        -- the old process's places must be there for it to take.
        local live = {}
        for _, lid in ipairs(self.a.windows()) do
            live[lid] = true
        end
        if next(self:collect_gone(live)) then
            self:schedule()
        end
        self:add(id)
    end
    if self.ffm then
        self.ffm:settled(id)
    end
    local w = self.windows[id]
    if not w or not w.ws then
        return
    end
    if not self:may_focus(id, w) then
        self:refuse(id, w)
        return
    end
    if self.last_steal and self.last_steal.id == id then
        self.last_steal = nil
    end
    remove_value(self.history, id)
    table.insert(self.history, 1, id)
    self.attention:focused(id, w.app)
    self:changed()
    -- However the tile got focus, its floats go back over it. A focused
    -- float comes to the front, so it moves to the top of wm.floats, which
    -- raise_floats replays bottom to top, and what's under the pointer is
    -- re-read.
    if w.floating then
        remove_value(self.floats, id)
        self.floats[#self.floats + 1] = id
        if self.ffm then
            self.ffm:resync()
        end
    else
        self:raise_floats(w.ws, w.pid)
    end
    local list = self.mru[w.ws]
    remove_value(list, id)
    table.insert(list, 1, id)
    -- Maximize lasts until another window on the workspace is focused
    -- (tide SPEC.md §6.3).
    local changed = false
    for oid, o in pairs(self.windows) do
        if oid ~= id and o.ws == w.ws and o.big == "max" then
            o.big = nil
            changed = true
        end
    end
    if changed then
        self:retile()
    end
end

-- After a close, something keeps focus: the window under the pointer, as
-- tide's focus_on_close, else the last used window left on that workspace,
-- else any tile you can see there. The fallback means a window that reached
-- the workspace without a focus event, such as one moved off a display that
-- went away, still counts.
function M:refocus(n)
    if self.a.focused() then
        return
    end
    if self.ffm and self.ffm.enabled then
        local x, y = self.a.pointer()
        local id = x and self.ffm:hit(x, y)
        if id and self.windows[id].ws == n then
            self:focus_window(id)
            return
        end
    end
    for _, id in ipairs(self.mru[n] or {}) do
        -- Only a window you can see: focusing a minimized one doesn't
        -- bring it back.
        local w = self.windows[id]
        local st = w and w.ws == n and self.a.state(id)
        if st and not st.minimized and not st.hidden and not st.fullscreen then
            self:focus_window(id)
            return
        end
    end
    local id = self:tiled(n)[1]
    if id then
        self:focus_window(id)
    end
end

-- Actions, called by the keys -----------------------------------------------

function M:focused_tile()
    local id = self.a.focused()
    local w = self.windows[id or false]
    if w and w.ws and not w.floating then
        return id, w
    end
end

M.actions = {}
local A = M.actions

function A.focus(self, delta)
    local n = self:current_ws()
    local ids = self:tiled(n)
    local id = self:focused_tile()
    local target = layout.neighbor(ids, id, delta)
    -- Focusing raises the target, monocle's full-size tile included, and
    -- then its floats go back over it.
    if target then
        self:focus_window(target)
    end
end

function A.move(self, delta)
    local id, w = self:focused_tile()
    if id then
        layout.move(self.workspaces[w.ws], self:tiled(w.ws), id, delta)
        self:retile()
    end
end

function A.swap_master(self)
    local id, w = self:focused_tile()
    if id then
        layout.swap_master(self.workspaces[w.ws], self:tiled(w.ws), id)
        self:retile()
    end
end

function A.mfact(self, sign)
    layout.mfact(self.workspaces[self:current_ws()], sign * self.layout.mfact_step)
    self:retile()
end

function A.nmaster(self, delta)
    layout.nmaster(self.workspaces[self:current_ws()], delta)
    self:retile()
end

function A.cycle(self, delta)
    layout.cycle(self.workspaces[self:current_ws()], delta, self.layout)
    self:retile()
end

function A.monocle(self)
    layout.toggle_monocle(self.workspaces[self:current_ws()])
    self:retile()
end

function set_big_on(self, id, kind)
    local w = self.windows[id]
    if not w or not w.ws or w.floating then
        return
    end
    w.big = (w.big ~= kind) and kind or nil
    self:retile()
    if w.big then
        self.a.raise(id)
        -- The tile is already focused, so no focus event will put its
        -- floats back over it.
        self:raise_floats(w.ws, w.pid)
    end
end

local function set_big(self, kind)
    local id = self:focused_tile()
    if id then
        set_big_on(self, id, kind)
    end
end

function A.maximize(self)
    set_big(self, "max")
end

function A.fullscreen(self)
    set_big(self, "full")
end

function A.restore(self)
    local id, w = self:focused_tile()
    if id and w.big then
        w.big = nil
        self:retile()
    end
end

function A.toggle_float(self)
    local id = self.a.focused()
    local w = self.windows[id or false]
    if not w or not w.ws then
        return
    end
    if w.floating then
        w.floating = false
        remove_value(self.floats, id)
        layout.insert(self.workspaces[w.ws], id, nil, self.layout)
    else
        w.floating = true
        w.big = nil
        layout.remove(self.workspaces[w.ws], id)
        self.floats[#self.floats + 1] = id
        self:place_float(id, self.a.facts(id))
    end
    self:retile()
end

-- Super+Z: minimize the focused window to its display's tray (SPEC.md
-- §6.7). Focus goes to the workspace's last used window still showing.
function A.minimize(self)
    local id = self.a.focused()
    local w = self.windows[id or false]
    if not (w and w.ws) or w.mine then
        return
    end
    self:mark_mine(id)
    self:reconcile()
    self:retile()
    self:refocus_ws(w.ws)
    self:changed()
end

-- The window's going away is seen by the next sync, which refocuses.
function A.close(self)
    local id = self.a.focused()
    if id then
        self.a.close(id)
    end
end

-- Resize mode (Super+Shift+R): grow or shrink the focused float by dx, dy,
-- keeping it on its display.
function A.resize_by(self, d)
    local id = self.a.focused()
    local w = self.windows[id or false]
    local st = w and w.floating and self.a.state(id)
    if not st then
        return
    end
    local f = st.frame
    self.a.set_frame(id, {
        x = f.x,
        y = f.y,
        w = math.max(mouse.MIN, f.w + d[1]),
        h = math.max(mouse.MIN, f.h + d[2]),
    })
end

-- Super+Shift+R: the keys for resize mode are Hammerspoon's to bind
-- (init.lua), so this only enters it.
function A.resize_mode(self)
    if self.enter_resize_mode then
        self.enter_resize_mode()
    end
end

-- Workspaces ----------------------------------------------------------------

function A.show(self, n)
    self:show(n)
end

function A.send(self, n)
    self:send_keeping_focus(self.a.focused(), n)
end

-- Send window `id` away, with focus staying on the workspace you're on, as
-- on tide; with nothing left there, so do the keys.
function M:send_keeping_focus(id, n)
    local w = self.windows[id or false]
    local from = w and w.ws
    local uuid = from and self:shown(from)
    self:send(id, n)
    -- Focus stays on the workspace you're on, as on tide; with nothing left
    -- there, so do the keys.
    if from and self.windows[id] and self.windows[id].ws ~= from then
        if not self:refocus_ws(from) and uuid then
            self:keep_keys_on(uuid)
        end
    end
end

-- The workspace `d` steps from `cur` in bar order, stopping at the first
-- and last.
function M:step_from(cur, d)
    local list = self:listed()
    local i = self:index_of_ws(cur) or 1
    return list[math.max(1, math.min(#list, i + d))]
end

-- Super+Left/Right and PgUp/PgDn: the previous or next workspace in bar
-- order, stopping at the first and last.
function A.step(self, d)
    self:show(self:step_from(self.screen_ws[self:current_screen()] or self.home, d))
end

-- Super+Home: the home workspace (SPEC.md §6.1).
function A.home(self)
    self:show(self.home)
end

-- Super+Tab (SPEC.md §7.2): from any other workspace, home; from home, the
-- workspace you used last. Pressed again, it flips back.
function A.flip(self)
    local cur = self.screen_ws[self:current_screen()] or self.home
    if cur ~= self.home then
        self:show(self.home)
        return
    end
    local n = self:last_used(function(m)
        return m == self.home
    end)
    if n then
        self:show(n)
    end
end

-- Super+End (SPEC.md §7.2): the workspace you used last, other than home
-- and the one you're on. From home that's where Super+Tab goes; from
-- another, the one before it.
function A.last(self)
    local cur = self.screen_ws[self:current_screen()] or self.home
    local n = self:last_used(function(m)
        return m == self.home or m == cur
    end)
    if n then
        self:show(n)
    end
end

-- Super+Return (SPEC.md §7.2): move the focused window to a workspace by
-- name, with the prompt listing them all. This is Send: focus stays put.
-- Esc leaves the window where it is.
function A.move_to(self)
    local id = self.a.focused()
    local w = self.windows[id or false]
    if not w or not w.ws or not self.ask_move then
        return
    end
    self.asking[#self.asking + 1] = { move = id }
    self:ask_next()
end

-- Super+Shift+Left/Right: carry the focused window there, and follow it.
function A.carry(self, d)
    local id = self.a.focused()
    -- The display it's carried from, noted before the window moves.
    local uuid = self:current_screen()
    local cur = self.screen_ws[uuid] or self.home
    local n = self:step_from(cur, d)
    if id and n ~= cur and self:send(id, n) then
        self:show(n, uuid)
        self:focus_window(id)
    end
end

-- Apps and the launcher ----------------------------------------------------

-- An app's managed windows, most recently used first: by focus across
-- workspaces, then by each workspace's own order for windows not focused
-- since tilemo started.
function M:app_windows(bundle)
    local out, seen = {}, {}
    for _, id in ipairs(self.history) do
        local w = self.windows[id]
        if w and w.app == bundle and w.ws then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, n in ipairs(self.names) do
        for _, id in ipairs(self.mru[n] or {}) do
            local w = self.windows[id]
            if w and w.app == bundle and w.ws and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    for id, w in pairs(self.windows) do
        if w.app == bundle and w.ws and not seen[id] then
            out[#out + 1] = id
        end
    end
    return out
end

-- An app key: bring the app's window forward, with its workspace, or
-- launch it. `fresh` opens a new window instead (Cmd+Return in the
-- launcher), even if the app is running. A spec marked `new` opens a new
-- window every time, on this workspace, as tide's terminal key does. A
-- launch asks for a workspace first where before_launch says, and starts
-- with that workspace's TIDE_WORKSPACE.
function A.app(self, spec, fresh)
    local default = spec.name or (spec.bundle and self.a.app_name and self.a.app_name(spec.bundle)) or spec.run
    if fresh or spec.new then
        self:before_launch({ fresh = fresh, home_app = spec.home_app, default = default, app = spec.bundle }, function(env)
            self:grant(spec.bundle)
            self.a.launch(spec, true, env)
        end)
        return
    end
    local ids = spec.bundle and self:app_windows(spec.bundle) or {}
    if ids[1] then
        self:activate(ids[1])
    else
        self:before_launch({ home_app = spec.home_app, default = default, app = spec.bundle }, function(env)
            self:grant(spec.bundle)
            self.a.launch(spec, false, env)
        end)
    end
end

-- The windows wanting attention, newest first, for the switcher's
-- Attention tab (Super+A). Only marks with a window to go to: a badged app may have quit.
-- An app's badge and its window's title can name the same window; it comes
-- once, where its newest mark puts it.
function M:attention_windows()
    local list, seen = {}, {}
    for _, m in ipairs(self.attention:list()) do
        local target = m.id or self:app_windows(m.app)[1]
        if target and self.windows[target] and not seen[target] then
            seen[target] = true
            list[#list + 1] = target
        end
    end
    return list
end

-- Read Dock badges and window titles for new marks. What's focused now
-- can't want attention: a count can rise while you're looking at it, and
-- focus events alone wouldn't clear that.
function M:poll_attention()
    local att = self.attention
    att:dock(self.a.dock_badges())
    for id, w in pairs(self.windows) do
        if w.ws then
            local title = self.a.title(id)
            -- Kept for matching the window after a restart.
            w.title = title or w.title
            att:title(id, w.app, title)
        end
    end
    local f = self.a.focused()
    local w = f and self.windows[f]
    -- A window left with the focus it took keeps its mark until you pick it.
    if w and not (self.last_steal and self.last_steal.id == f) then
        att:focused(f, w.app)
    end
    self:changed()
end

-- The switcher, on tab `tab` (SPEC.md §9): Super+Space on Launch, the
-- Super tap on Workspaces, Super+A on Attention.
function A.launcher(self, tab)
    if self.open_launcher then
        self.open_launcher(tab)
    end
end

-- Super+C: the picker, on tab `tab`: what you've copied, and characters by
-- name (SPEC.md §7.2).
function A.picker(self, tab)
    if self.open_picker then
        self.open_picker(tab)
    end
end

-- Super+Shift+M: mute or unmute the microphone (SPEC.md §7.2).
function A.mic_mute(self)
    if self.toggle_mic then
        self.toggle_mic()
    end
end

-- Super+S: keep awake on or off; Super+P: presenter mode, Do Not Disturb
-- and keep awake together (SPEC.md §10).
function A.keep_awake(self)
    if self.toggle_keep_awake then
        self.toggle_keep_awake()
    end
end

function A.presenter(self)
    if self.toggle_presenter then
        self.toggle_presenter()
    end
end

-- Super+L and Super+Shift+E, and the launcher's Lock and Log out.
function A.lock(self)
    self.a.lock()
end

function A.logout(self)
    self.a.logout()
end

-- The Print keys and the launcher's screenshot actions (SPEC.md §10).
function A.screenshot(self, kind)
    self.a.screenshot(kind)
end

-- tilemo's settings window, from the launcher and the dashboard (SPEC.md
-- §15).
function A.settings(self)
    if self.open_settings then
        self.open_settings()
    end
end

-- Super+Shift+Space: the dashboard, or closes it (SPEC.md §8).
function A.dashboard(self)
    if self.open_dashboard then
        self.open_dashboard()
    end
end

function A.layout(self, mode)
    local ws = self.workspaces[self:current_ws()]
    if ws then
        ws.prev_mode = nil
        ws.mode = mode
        self:retile()
    end
end

function M:act(name, arg)
    local f = A[name]
    if not f then
        error("tilemo: no action " .. tostring(name))
    end
    f(self, arg)
end

return M
