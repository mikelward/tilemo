-- The window manager: which window is on which workspace, tiled or
-- floating, and the actions the keys call (SPEC.md §5). It talks to macOS
-- only through an adapter (hs_adapter.lua on a Mac, a fake in the tests),
-- so all of its decisions test without Hammerspoon. The adapter's `facts`
-- is the full, slower read used to decide a new window; `state` is the
-- quick one used on every retile.
--
-- Workspaces (SPEC.md §6.1) are tileco's model with tide's names: the
-- home workspace ("in" by default) first and always there, then the
-- standing ones, then the rest in the order they were made. One workspace
-- shows at a time, on every display, and each display has its own part of
-- it: its own stack, layout, mfact and masters (`workspaces[n][uuid]`). A
-- window belongs to a workspace and to a display within it (`w.screen`).
-- An empty workspace that isn't standing goes once it isn't showing. A
-- window on a workspace that isn't showing is parked off screen (park.lua),
-- or minimized with `hide = "minimize"`. Every operation
-- changes only which workspace shows and where each window is; then
-- reconcile() makes the screen match, restoring first so the screen never
-- goes empty.

local attention = require("tide.attention")
local mute = require("tide.mute")
local bar = require("tide.bar")
local direction = require("tide.direction")
local layout = require("tide.layout")
local mouse = require("tide.mouse")
local names = require("tide.names")
local standing_mod = require("tide.standing")
local rules = require("tide.rules")
local floating = require("tide.floating")
local park = require("tide.park")

local M = {}

-- Whether two layout settings are the same, value by value.
local function layout_equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not layout_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end
M.__index = M

local function remove_value(list, v)
    for i = #list, 1, -1 do
        if list[i] == v then
            table.remove(list, i)
        end
    end
end

local set_big_on

local function same_box(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function copy_box(b)
    return { x = b.x, y = b.y, w = b.w, h = b.h }
end

-- Take window `w` out of its part's stack, if it's in one.
local function unplace(self, w, id)
    local p = self:part_of(w)
    if p then
        layout.remove(p, id)
    end
end

-- The standing workspaces (SPEC.md §6.1): always listed, never removed.
-- The first is the home workspace, "in" by default, made at start and
-- never renamed, where the apps below always open, by app name (SPEC.md
-- §6.2); the rest are made the first time you show one or send a window
-- to it. Which names stand for mail, chat, calendar and music is a guess,
-- to confirm.
M.STANDING = { "in", "re", "oc", "me" }
M.HOME_APPS = { "Mail", "Gmail", "Messages", "Google Chat", "Calendar", "Google Calendar", "Music", "YouTube Music" }
-- How long tide waits for macOS to report a minimize or restore it asked for.
M.EXPECT = 2

-- How long to wait after the last window event before retiling, since one
-- window opening sends several (tileco SPEC.md §5.3).
M.DEBOUNCE = 0.05
-- A float's size is capped at this share of its display (tide SPEC.md §6.4).
M.FLOAT_CAP = 0.8
-- The focus guard (SPEC.md §14.1): how long a launch you made may give its
-- window focus, and how soon after something you did (a click, a key with
-- Command, a focus tide asked for) an activation still counts as yours.
-- 5 s, for a launch and a click alike: long enough for a slow app's
-- window (a cold launch, System Settings showing About This Mac), short
-- enough that one long after isn't taken for what you asked.
M.GRANT = 5
M.GRACE = 1
-- How long after tide first sees a window a new title still decides it
-- again: a browser's popup can open before its page has named it.
M.SETTLE = 3
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

-- `workspaces`, the standing workspaces' names, is checked when tide
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
            error(string.format("workspaces[%d]: %q can't have quotes, backslashes, @ or control characters", i, n), 3)
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

-- How a workspace that isn't showing hides its windows (SPEC.md §6):
-- "park" moves them off screen, all but a sliver in a corner of their
-- display, and "minimize" minimizes them. `hide` is checked when tide
-- starts, so a typo is an error naming the setting. Nil is "park".
M.HIDE = { park = true, minimize = true }
function M.check_hide(value)
    if value == nil then
        return "park"
    end
    if not M.HIDE[value] then
        error(string.format('hide must be "park" or "minimize", not %s',
            type(value) == "string" and string.format("%q", value) or tostring(value)), 3)
    end
    return value
end

-- `home_apps` is checked when tide starts, so a typo is an error naming the
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
        set[standing_mod.app_key(name)] = true
    end
    for k in pairs(list) do
        if math.type(k) ~= "integer" or k < 1 or k > #list then
            error("home_apps must be a list of app names, not " .. tostring(k), 3)
        end
    end
    return set
end

-- `workspace_settings` is checked when tide starts, as tide checks
-- workspaceSettings, so a typo is an error naming the setting. Nil is
-- tide's default: home asks for a name and nothing is pinned.
function M.check_workspace_settings(value)
    if value == nil then
        return nil
    end
    local why = standing_mod.settings_problem(value, "workspace_settings")
    if why then
        error(why, 3)
    end
    return value
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
    local current = saved.current and name_of(saved.current)
    if not numbered then
        return { windows = windows, gone = gone, screens = screens, current = current }, false
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
    if current and not used[current] then
        current = home
    end
    return { windows = windows, gone = gone, screens = screens, current = current, names = names }, true
end

function M.new(adapter, config)
    config = config or {}
    local standing = M.check_standing(config.workspaces or M.STANDING)
    local saved, migrated = M.migrate(config.saved, standing[1])
    local self = setmetatable({
        a = adapter,
        layout = config.layout or layout.defaults,
        -- The height tide's bar takes from the top of each display, or 0
        -- with the bar off (bar.lua).
        top = config.top or 0,
        -- Where each display's bar window really ends, by uuid, when macOS
        -- moved it lower than tide put it (bar.place).
        bar_floor = {},
        -- start()'s rules, then the ones you made on the Floating page
        -- (floating.lua), together as `rules`, tried before tide's own.
        start_rules = rules.check(config.rules or {}, "rules"),
        float_rules = {},
        home_apps = M.check_home_apps(config.home_apps or M.HOME_APPS),
        -- Each workspace's own settings (SPEC.md §6.2): tide's
        -- workspaceSettings, or nil for its default, home asking.
        workspace_settings = M.check_workspace_settings(config.workspace_settings),
        -- How hidden workspaces hide: "park" or "minimize" (M.check_hide).
        hide = M.check_hide(config.hide),
        -- id -> true for a window tide parked off screen (park.lua): not
        -- minimized, but not on screen either. A move lands at once, so,
        -- unlike a minimize, a park needs no expectation. `w.park_frame` is
        -- where it was before, which a float goes back to.
        parked = {},
        -- id -> true for a native full-screen window tide minimized in
        -- park mode: full screen is a Space of its own, which can't be
        -- parked, so it hides as minimize mode does.
        hid_full = {},
        standing = standing,
        -- The home workspace: the first standing one, "in" by default.
        home = standing[1],
        -- id -> { id, app, name, ws, screen, floating, big }; `screen` is
        -- the display's uuid, and `from`, `from_pos` where a display that
        -- went away had it, for when that display comes back.
        windows = {},
        -- The workspaces that exist, in bar order: home, the standing
        -- ones made so far in their order, then the rest in the order they
        -- were made.
        names = {},
        workspaces = {}, -- name -> display uuid -> layout state (M:part)
        current = nil,  -- the workspace showing, on every display
        floats = {},    -- float ids, bottom to top
        mru = {},       -- workspace name -> ids, most recent first
        placed = {},    -- id -> the frame tide last gave it, as it landed
        -- id -> the minimizes and restores tide asked for that macOS hasn't
        -- reported yet, oldest first, each { kind = "min" or "unmin",
        -- token = n }. One entry per request: switching back and forth
        -- quickly can leave several of either kind outstanding.
        expect = {},
        tokens = 0,
        attention = attention.new(),
        history = {},   -- ids, most recently focused first, across workspaces
        -- The focus guard's inputs: when you last typed or clicked, when you
        -- last did something that switches apps, whether Command is down,
        -- the launch grant, the focuses tide asked for within M.GRACE, and
        -- the last window refused.
        last_input = -math.huge,
        last_switch = -math.huge,
        cmd_down = false,
        granted = nil,  -- { app (nil: any), at, first_only }
        asked = {},     -- { id, app, at }, oldest first
        last_steal = nil, -- { id, at }
    }, M)
    self.rules = floating.combined(self.start_rules, self.float_rules)
    rules.report = function(msg)
        if adapter.log then
            adapter.log(msg)
        end
    end
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
    -- What showed last run: `current`, or, from a state saved when each
    -- display showed its own, what some display showed (map_screens).
    self.saved_current = saved.current
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
        return self:is_muted(m.app, m.id, m.site)
    end
    return self
end

-- Whether a mark for window `id` of `app` is muted: its app is in the
-- list, or it's a browser window whose front tab is on a muted site, or a
-- notification from muted site `site`.
function M:is_muted(app, id, site)
    return mute.matches(self.muted, app, (id and self.tab_hosts[id]) or site)
end

-- The muted list changed: marks it now covers go, and the bar shows it.
function M:set_muted(set)
    self.muted = set or mute.empty()
    self.attention:prune()
    self:changed()
end

-- The browser windows' front tabs, from the switcher's tab list: `tabs`
-- as launcher.parse_tabs gives them, with `win` the tide window and
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

-- The displays, each one's tiling area below tide's bar when it's on.
function M:screens()
    local out = {}
    for i, s in ipairs(self.a.screens()) do
        if self.top > 0 then
            local _, area = bar.place(s, self.top, self.bar_floor[s.uuid])
            out[i] = { uuid = s.uuid, area = area, full = s.full, notch = s.notch }
        else
            out[i] = s
        end
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

-- Every display's full frame, for park.lua.
function M:fulls()
    local out = {}
    for i, s in ipairs(self:screens()) do
        out[i] = s.full
    end
    return out
end

-- Whether window `id`, whose quick state is `st`, is on screen: neither
-- minimized nor parked off screen. A hidden app's window (Cmd+H) still
-- counts; visible() leaves it out too.
function M:shows(id, st)
    if not st then
        return false
    end
    return not st.minimized and not self.parked[id]
end

-- Whether window `id` can be seen: on screen (shows), and its app not
-- hidden.
function M:visible(id, st)
    return self:shows(id, st) and not st.hidden
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

-- Whether the app called `name` is one of home's apps: ignoring case, and
-- with spaces and hyphens alike, so tide's `google-chat` is Google Chat
-- (standing.app_key).
function M:home_app_named(name)
    return name ~= nil and self.home_apps[standing_mod.app_key(name)] == true
end

-- Whether window `w` is one of home's apps, by its app's name.
function M:is_home_app(w)
    return w ~= nil and self:home_app_named(w.name)
end

-- Workspace `name`'s own settings, { askForName, pinnedApps } (SPEC.md
-- §6.2): tide's workspaceSettings, matched ignoring case.
function M:ws_setting(name)
    return standing_mod.setting(self.workspace_settings, self.home, name)
end

-- Whether a new window on workspace `name`, or a launch from it, asks for a
-- workspace's name.
function M:asks_for_name(name)
    return name ~= nil and self:ws_setting(name).askForName
end

-- The workspace window `w` is pinned on, or nil: the one it's on, when its
-- app is one of that workspace's pinnedApps, matched by app name as home's
-- apps are (standing.app_key). tide's close actions leave it open.
function M:pinned_on(w)
    if not (w and w.ws and w.name) then
        return nil
    end
    local key = standing_mod.app_key(w.name)
    for _, entry in ipairs(self:ws_setting(w.ws).pinnedApps) do
        if standing_mod.app_key(entry) == key then
            return w.ws
        end
    end
    return nil
end

-- What a close refused for a window pinned on `ws` says, as tide's does.
function M.pinned_notice(ws)
    return "Pinned window: it's pinned on " .. ws .. ", so it stays open."
end

-- If window `id` is pinned where it is, say so and return true: a close
-- action leaves it open.
function M:keeps_pinned(id)
    local ws = self:pinned_on(self.windows[id])
    if not ws then
        return false
    end
    self.a.log("left " .. tostring(self.windows[id].name) .. " open: it's pinned on " .. ws)
    if self.a.notify then
        self.a.notify(M.pinned_notice(ws))
    end
    return true
end

-- The workspace the focused window is pinned on, or nil.
function M:pinned_focus()
    local id = self.a.focused()
    return id and self:pinned_on(self.windows[id]) or nil
end

-- Tell `on_pinned_focus(ws)` when the focused window becomes pinned, or
-- stops being: init.lua holds an app's own close and quit keys while it is
-- (pinned_hs.lua).
function M:check_pinned_focus()
    -- With nothing pinned anywhere, as by default, there's nothing to ask
    -- macOS.
    local any = false
    for _, v in pairs(self.workspace_settings or {}) do
        any = any or (type(v.pinnedApps) == "table" and #v.pinnedApps > 0)
    end
    local ws = any and self:pinned_focus() or nil
    if ws ~= self.pinned_focus_ws then
        self.pinned_focus_ws = ws
        if self.on_pinned_focus then
            self.on_pinned_focus(ws)
        end
    end
end

-- An app's own close or quit key, held while a pinned window was focused:
-- true if the window's still pinned, and the key kept from it, said so;
-- false if not, for the caller to pass the key on.
function M:pinned_key()
    local id = self.a.focused()
    if id and self:keeps_pinned(id) then
        return true
    end
    self:check_pinned_focus()
    return false
end

-- New workspace settings, from tide's files as they change (SPEC.md §15),
-- checked as start()'s are; nil for tide's default.
function M:set_workspace_settings(value)
    self.workspace_settings = M.check_workspace_settings(value)
    self:check_pinned_focus()
end

-- New standing workspaces and home's apps, from tide's files as they change
-- (SPEC.md §15), checked as start()'s are. The first standing one is home
-- from now on: it's made if it isn't yet, and goes first. The rest keep
-- their windows and places; a workspace no longer standing is an ordinary
-- one, removed once it's empty and hidden. Windows stay where they are:
-- home's apps say where a window opens, not where it must stay.
function M:set_workspaces(list, home_apps)
    local new = M.check_standing(list)
    local apps = M.check_home_apps(home_apps)
    local same = #new == #self.standing
    for i, n in ipairs(new) do
        same = same and M.fold(self.standing[i]) == M.fold(n)
    end
    for k in pairs(apps) do
        same = same and self.home_apps[k] == true
    end
    for k in pairs(self.home_apps) do
        same = same and apps[k] == true
    end
    if same then
        return false
    end
    local old = self.names
    -- An existing workspace keeps the case it was made with.
    local function existing(n)
        local want = M.fold(n)
        for _, m in ipairs(old) do
            if M.fold(m) == want then
                return m
            end
        end
    end
    -- Standing names take an existing workspace's spelling too, since the
    -- bar and Next and Previous compare names exactly.
    for i, n in ipairs(new) do
        new[i] = existing(n) or n
    end
    self.standing = new
    self.home_apps = apps
    self.home = existing(new[1]) or new[1]
    self.names = { self.home }
    local taken = { [M.fold(self.home)] = true }
    for i = 2, #new do
        local m = existing(new[i])
        if m then
            self.names[#self.names + 1] = m
            taken[M.fold(m)] = true
        end
    end
    for _, m in ipairs(old) do
        if not taken[M.fold(m)] then
            self.names[#self.names + 1] = m
            taken[M.fold(m)] = true
        end
    end
    self:ensure_ws(self.home)
    self:prune()
    self:changed()
    return true
end

-- Make sure a workspace shows, and put every window on a display that's
-- there (SPEC.md §6.4). At start it's the one that showed last run, else
-- home. A display that went away hands its windows to the first display
-- left, in the same workspace, each at the end of that display's stack;
-- each remembers where it was, and goes back there, in its old order,
-- when that display comes back, unless you've moved it since.
function M:map_screens()
    local screens = self:screens()
    if not (self.current and self:find(self.current)) then
        local n = self:find(self.saved_current)
        for _, s in ipairs(screens) do
            n = n or self:find(self.saved_screens[s.uuid])
        end
        self.current = n or self.home
        -- Only at start: later, a workspace that's gone isn't brought back.
        self.saved_current, self.saved_screens = nil, {}
    end
    self:ensure_ws(self.current)
    -- Every workspace has its parts, made as they're needed (M:part).
    for _, n in ipairs(self.names) do
        self:ensure_ws(n)
    end
    local first = screens[1]
    if not first then
        return
    end
    local present = {}
    for _, s in ipairs(screens) do
        present[s.uuid] = true
    end
    local back, away = {}, {}
    for id, w in pairs(self.windows) do
        if w.ws then
            if w.from and present[w.from] and not w.floating then
                back[#back + 1] = id
            elseif not present[w.screen] then
                away[#away + 1] = id
            end
        end
    end
    -- Those coming back go first, so their old places are free. Lowest old
    -- index first, so each lands at its index.
    table.sort(back, function(p, q)
        local a, b = self.windows[p].from_pos or math.huge, self.windows[q].from_pos or math.huge
        if a ~= b then
            return a < b
        end
        return tostring(p) < tostring(q)
    end)
    for _, id in ipairs(back) do
        local w = self.windows[id]
        unplace(self, w, id)
        w.screen = w.from
        local order = self:part_of(w).order
        table.insert(order, math.min(w.from_pos or #order + 1, #order + 1), id)
        w.from, w.from_pos = nil, nil
    end
    -- Those leaving, in their old order, so they keep it on the display
    -- they go to.
    local pos = {}
    for _, id in ipairs(away) do
        local p = self:part_of(self.windows[id])
        pos[id] = p and layout.index_of(p.order, id)
    end
    table.sort(away, function(p, q)
        local a, b = pos[p] or math.huge, pos[q] or math.huge
        if a ~= b then
            return a < b
        end
        return tostring(p) < tostring(q)
    end)
    for _, id in ipairs(away) do
        local w = self.windows[id]
        unplace(self, w, id)
        -- A float is where macOS put it, and stays: only tiles go back.
        if not w.floating and w.screen then
            w.from = w.from or w.screen
            w.from_pos = w.from_pos or pos[id]
        end
        w.screen = first.uuid
        if not w.floating then
            local order = self:part_of(w).order
            order[#order + 1] = id
        end
    end
end

-- Workspace `name`, made in its place in bar order (add_name), if it's
-- new. Returns its name as it was made.
function M:ensure_ws(name)
    local n = self:find(name)
    if not n then
        n = M.clean_name(name)
        if not n then
            return nil
        end
        n = self:add_name(n)
    end
    if not self.workspaces[n] then
        self.workspaces[n] = {}
        self.mru[n] = self.mru[n] or {}
    end
    return n
end

-- Workspace `n`'s part on display `uuid`: its own stack, layout, mfact and
-- masters there (SPEC.md §6.1), made in the default layout for that
-- display's shape the first time it's needed. A display that went away
-- keeps its parts, for when it comes back.
function M:part(n, uuid)
    local parts = n and self.workspaces[n]
    if not parts or not uuid then
        return nil
    end
    local p = parts[uuid]
    if not p then
        local s = self:screen_by_uuid(uuid)
        p = layout.new(n, s and s.area, self.layout)
        parts[uuid] = p
    end
    return p
end

-- The part window `w` is in, if it's on a workspace.
function M:part_of(w)
    return w and self:part(w.ws, w.screen)
end

-- The display a window's frame is on, by uuid.
function M:screen_of_frame(frame)
    local s = self:screen_for(frame)
    return s and s.uuid
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

-- Remove every empty workspace that isn't showing, other than the standing
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
-- windows, since its windows went home, is dropped, and if it was showing,
-- home shows (SPEC.md §6.5).
function M:finish_migration()
    if not self.migrated then
        return
    end
    self.migrated = false
    local n = self.current
    if n and not self:standing_name(n) and not self:occupied(n) then
        self.current = self.home
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

-- Whether workspace `n` is the one showing, on every display.
function M:shown(n)
    return n ~= nil and n == self.current
end

-- The workspace showing, which the keys act on.
function M:current_ws()
    return self.current or self.home
end

-- The tiled windows of workspace `n` on display `uuid` that are on screen,
-- in that display's order.
function M:tiled(n, uuid)
    local ws = self:part(n, uuid)
    local out = {}
    if not ws then
        return out
    end
    for _, id in ipairs(ws.order) do
        local f = self.a.state(id)
        if self:visible(id, f) and not f.fullscreen then
            out[#out + 1] = id
        end
    end
    return out
end

-- Place a new float centered on its parent, the app's focused window, at
-- what it asked for capped at 80% (SPEC.md §5.1). One with no parent, such
-- as System Settings, centers on the pointer when that's on its display,
-- else on the display: opening under the pointer, it isn't buried by the
-- tile beside it, which focus follows mouse would raise at the pointer's
-- next move.
function M:place_float(id, f)
    local s = self:screen_for(f.frame)
    local area = s.area
    local w = math.min(f.frame.w, math.floor(area.w * M.FLOAT_CAP))
    local h = math.min(f.frame.h, math.floor(area.h * M.FLOAT_CAP))
    local cx, cy = center(area)
    -- One with no parent centers on its display, as on tide, not under the
    -- pointer: a slow app's window arrives after the pointer has moved on,
    -- and lands where it was. Focus follows mouse leaves it on top anyway
    -- (M:buries).
    local parent = self.a.app_focused(f.pid)
    local pf = parent and parent ~= id and self.a.state(parent)
    if pf then
        cx, cy = center(pf.frame)
    end
    local x = math.floor(cx - w / 2 + 0.5)
    local y = math.floor(cy - h / 2 + 0.5)
    -- Keep it on its display.
    x = math.max(area.x, math.min(x, area.x + area.w - w))
    y = math.max(area.y, math.min(y, area.y + area.h - h))
    self.a.set_frame(id, { x = x, y = y, w = w, h = h })
end

-- The workspace of a new float's parent: its app's focused window, as
-- place_float centers it on, if tide manages it.
function M:parent_ws(id, f)
    local parent = self.a.app_focused(f.pid)
    local p = parent and parent ~= id and self.windows[parent]
    return p and p.ws
end

-- Launches tide made, oldest first, each { app, ws, at }: the window a
-- launch opens goes to the workspace it was for (`ws`), whatever's showing
-- when it arrives. `app` is the bundle ID, or nil for a helper script,
-- whose window may be any app's. Each is used once, within M.GRANT.
-- A launch you made, of `app` (a bundle ID, or nil for any) for workspace
-- `ws`: its window goes to that workspace, on the display keys act on as
-- you launch it, wherever macOS opens it (SPEC.md §6.1). `screen` is that
-- display, read as the key was pressed, before a prompt or a switch moved
-- focus; nil reads it now.
function M:launch_to(app, ws, screen)
    self.launches = self.launches or {}
    self.launches[#self.launches + 1] = { app = app, ws = ws, at = self.a.now(), screen = screen or self:current_screen() }
end

-- The workspace the oldest launch that window `w` may be from was for, if
-- any; `take` uses that launch up.
-- A tile from launch `l` goes to the display keys acted on as it was made:
-- macOS opens it where the app last had a window, not where you are.
function M:launched_on(w, l, kind)
    if kind ~= "float" and l.screen and self:screen_by_uuid(l.screen) then
        w.screen = l.screen
        w.launched_on = l.screen
    end
end

-- The launch window `w` is from, if any: { ws, screen }. `take` uses it up.
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
            return l
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
    -- `seen`: when tide found it, so the focus guard can tell a window a
    -- launch opened from one that was already there.
    -- `opened`: the frame it opened at, which a tile no longer has, so one
    -- decided again (M:retitled) floats at the size it asked for.
    local w = {
        id = id, app = f.app, name = f.name, pid = f.pid, kind = kind, seen = self.a.now(), title = f.title,
        opened = f.frame,
    }
    self.windows[id] = w
    if kind == "ignore" then
        return kind
    end
    local saved = self.paired[id] or self:match(id, f, function(sid)
        return self.a.state(sid) ~= nil
    end)
    self.paired[id] = nil
    local launched = false
    if saved and saved.ws then
        -- tide restarted, or the app relaunched: the window goes back where
        -- it was. One of home's apps from a numbered state goes home.
        w.ws = (saved.numbered and self:is_home_app(w)) and self.home or saved.ws
        w.mine = saved.mine
        -- Where it was before a park, if the last run left it parked.
        w.park_frame = type(saved.frame) == "table" and saved.frame.w and copy_box(saved.frame) or nil
        -- Its old index, and which save it's from: only indexes from the
        -- same save say which window went before which.
        w.saved_pos = saved.pos
        w.saved_at = saved.at or self.started
        w.ws = self:ensure_ws(w.ws)
        -- Its display, if that's here; one that went away while the
        -- window was there, which it goes back to when it's here again.
        if saved.from and self:screen_by_uuid(saved.from) then
            w.screen, w.saved_pos = saved.from, saved.from_pos
        else
            local was = saved.from or saved.screen
            if saved.screen and self:screen_by_uuid(saved.screen) then
                w.screen = saved.screen
            else
                w.screen = self:screen_of_frame(f.frame)
                -- Its index was in another display's stack. A state saved
                -- before displays were kept names none.
                if saved.screen then
                    w.saved_pos = nil
                end
            end
            if was and was ~= w.screen and kind ~= "float" then
                w.from, w.from_pos = was, saved.from_pos or saved.pos
            end
        end
    elseif kind == "float" and self:parent_ws(id, f) then
        -- A dialog goes where its parent is (SPEC.md §6.2), even for one of
        -- home's apps whose window you moved elsewhere.
        w.ws = self:parent_ws(id, f)
        w.mine = f.minimized or false
    elseif self:is_home_app(w) then
        -- Home's apps always open there (SPEC.md §6.2), on the display a
        -- launch of one was made from.
        w.ws = self.home
        w.mine = f.minimized or false
        local l = self:launched_to(w, true)
        if l then
            self:launched_on(w, l, kind)
        end
    elseif self:launched_to(w) then
        -- A launch tide made goes to the workspace it was for, even if
        -- you've moved on since, marked if that isn't showing (SPEC.md
        -- §6.1, §14.2). Its workspace was named, so it doesn't ask again.
        local l = self:launched_to(w, true)
        w.ws = self:ensure_ws(l.ws)
        self:launched_on(w, l, kind)
        launched = true
        w.mine = f.minimized or false
        if not self:shown(w.ws) then
            self.attention:activated(id, w.app)
        end
    else
        w.ws = self.current or self.home
        -- Minimized before tide knew it: you did that.
        w.mine = f.minimized or false
    end
    -- Every window is on the display it opened on, in its workspace,
    -- unless it's going back to one.
    w.screen = w.screen or self:screen_of_frame(f.frame)
    -- Any other app's new window on a workspace whose askForName is on,
    -- home by default, asks for a name first. Dialogs and other floats go
    -- where their parent is, and a window coming back to its place, or
    -- launched to the workspace you named, doesn't ask.
    if self.ready and kind == "tile" and self:asks_for_name(w.ws) and not (saved and saved.ws) and not launched
        and not self:is_home_app(w) then
        self.asking[#self.asking + 1] = { window = id, ws = w.ws }
    end
    if kind == "float" then
        w.floating = true
        self.floats[#self.floats + 1] = id
        -- One the last run left parked stays off screen, for reconcile to
        -- keep parked or bring back to where it was.
        if not (self.hide == "park" and w.park_frame and park.hidden(f.frame, self:fulls())) then
            self:place_float(id, f)
        end
    elseif saved and saved.ws and w.saved_pos then
        self:insert_back(id, w)
    else
        -- "next" goes after the window you were in. macOS may already have
        -- given the new window focus, so that's the workspace's last used
        -- on this display.
        local ws = self:part_of(w)
        local anchor = self.a.focused()
        if anchor == id or not (anchor and layout.index_of(ws.order, anchor)) then
            anchor = nil
            for _, m in ipairs(self.mru[w.ws]) do
                if layout.index_of(ws.order, m) then
                    anchor = m
                    break
                end
            end
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
    local order = self:part_of(w).order
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
            screen = w.screen,
            from = w.from,
            from_pos = w.from_pos,
            mine = w.mine or false,
            pos = pos or (self:part_of(w) and layout.index_of(self:part_of(w).order, id)),
            at = at or self.a.now(),
        })
        while #self.gone > M.KEEP_MAX do
            table.remove(self.gone, 1)
        end
    end
    self.windows[id] = nil
    if w.ws and self.workspaces[w.ws] then
        unplace(self, w, id)
        remove_value(self.mru[w.ws], id)
    end
    remove_value(self.floats, id)
    self.placed[id] = nil
    self.parked[id] = nil
    self.hid_full[id] = nil
    remove_value(self.history, id)
    self.attention:gone(id)
    self.tab_hosts[id] = nil
end

-- Match what tide knows to the windows that exist now: add new ones, forget
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
            local part = w.ws and self.workspaces[w.ws] and self:part_of(w)
            pos[id] = part and layout.index_of(part.order, id)
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
-- What shows comes back first, laid out, and only then does the rest
-- hide, so the screen never goes empty in between. A workspace that isn't
-- showing hides by parking its windows off screen (M:park_window), or,
-- with `hide = "minimize"`, by minimizing them, as do the windows you
-- minimized and, since full screen is a Space of its own, a native
-- full-screen window. Coming back from a park, a float takes its own frame
-- again and a tile takes its tile at the next retile.
function M:reconcile()
    local parking = self.hide == "park"
    local fulls = parking and self:fulls() or nil
    local restore, hide, unpark, to_park = {}, {}, {}, {}
    for id, w in pairs(self.windows) do
        if w.ws then
            local st = self.a.state(id)
            if st then
                local want = self:shown(w.ws) and not w.mine
                if want then
                    if st.minimized and self:last_asked(id) ~= "unmin" then
                        restore[#restore + 1] = id
                    end
                    -- Parked, or still where a park left it, as after a
                    -- restart.
                    if parking and (self.parked[id] or (not st.minimized and park.hidden(st.frame, fulls))) then
                        unpark[#unpark + 1] = id
                    end
                elseif not parking or w.mine or st.fullscreen or self.hid_full[id] then
                    if not st.minimized and self:last_asked(id) ~= "min" then
                        hide[#hide + 1] = id
                        if parking and not w.mine then
                            self.hid_full[id] = true
                        end
                    end
                else
                    -- One tide minimized under the old scheme, from a
                    -- saved state or before an upgrade, comes back to be
                    -- parked.
                    if st.minimized and self:last_asked(id) ~= "unmin" then
                        restore[#restore + 1] = id
                    end
                    if not self.parked[id] or not park.hidden(st.frame, fulls) then
                        to_park[#to_park + 1] = id
                    end
                end
            end
        end
    end
    local function rank(id)
        local w = self.windows[id]
        local p = self:part_of(w)
        return p and layout.index_of(p.order, id) or 1000
    end
    table.sort(restore, function(p, q)
        return rank(p) < rank(q)
    end)
    -- An expectation lapses if macOS never reports the change, so a later
    -- minimize of yours isn't mistaken for tide's.
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
        self.hid_full[id] = nil
        expect(id, "unmin")
        self.a.unminimize(id)
    end
    if parking then
        table.sort(unpark, function(p, q)
            return rank(p) < rank(q)
        end)
        for _, id in ipairs(unpark) do
            self:unpark_window(id)
        end
        -- The workspace coming in is laid out before the one leaving goes.
        if #unpark > 0 and #to_park > 0 then
            self:retile()
        end
        table.sort(to_park, function(p, q)
            return tostring(p) < tostring(q)
        end)
        for _, id in ipairs(to_park) do
            self:park_window(id, fulls)
        end
    end
    table.sort(hide)
    for _, id in ipairs(hide) do
        expect(id, "min")
        self.a.minimize(id)
    end
    self:prune()
    self:save()
end

-- Park window `id` off screen (park.lua): all but a sliver of it past a
-- corner of its display, the first corner whose side has no other display.
-- Where it was is kept, unless it's already off screen, as after a
-- restart, when the saved one stands.
function M:park_window(id, fulls)
    local w = self.windows[id]
    local st = self.a.state(id)
    if not (w and st and st.frame) then
        return
    end
    fulls = fulls or self:fulls()
    -- Already parked, it moves to a new spot but keeps where it was: a
    -- display plugged in where it sat can show its old spot, which isn't
    -- where you left it.
    local again = self.parked[id]
    local away = again or park.hidden(st.frame, fulls)
    -- A float's display is where it is, read before it leaves; one already
    -- off screen keeps the display it had.
    local uuid = (not away and self:screen_of(id)) or w.screen
    if w.floating and uuid then
        w.screen = uuid
    end
    if not away then
        w.park_frame = copy_box(st.frame)
    end
    self.parked[id] = true
    local s = self:screen_by_uuid(uuid) or self:screens()[1]
    if not s then
        return
    end
    local spot = park.spot(s.full, fulls, st.frame)
    if not same_box(st.frame, spot) then
        self.a.set_frame(id, spot)
    end
end

-- Where window `id` goes back to from a park: the frame it had before, if
-- that's still on a display, else nil.
function M:unpark_frame(id, fulls)
    local w = self.windows[id]
    local f = w and w.park_frame
    if f and not park.hidden(f, fulls or self:fulls()) then
        return f
    end
end

-- Bring window `id` back from a park. A tile takes its tile at the next
-- retile; a float, and a hidden app's tile (Cmd+H), which a retile passes
-- over, go back to where they were now.
function M:unpark_window(id)
    local w = self.windows[id]
    self.parked[id] = nil
    if not w then
        return
    end
    local st = self.a.state(id)
    local f = self:unpark_frame(id)
    if w.floating and not w.place_pending then
        if f then
            self.a.set_frame(id, f)
        else
            local facts = self.a.facts(id)
            local s = self:screen_by_uuid(w.screen) or self:screens()[1]
            if facts and s then
                local placed = {}
                for k, v in pairs(facts) do
                    placed[k] = v
                end
                local size = (st and st.frame) or facts.frame
                placed.frame = { x = s.area.x, y = s.area.y, w = size.w, h = size.h }
                self:place_float(id, placed)
            end
        end
    elseif st and st.hidden and f then
        self.a.set_frame(id, f)
    end
    w.park_frame = nil
end

-- What a restart needs to put every window back: each window's workspace,
-- display, flag and place in that display's stack, and the display it
-- goes back to, with its app and title to match it by if it comes back
-- with a new id; the places still kept for windows that haven't come
-- back; and the workspace showing.
function M:snapshot()
    local out = { windows = {}, gone = {}, names = nil, current = nil }
    local now = self.a.now()
    -- A window's index is where it is now, so a stack you rearranged stays
    -- that way. (Windows still to come back after a restart partway through
    -- may land out of order: see TODO.md.)
    for id, w in pairs(self.windows) do
        if w.ws then
            out.windows[id] = {
                ws = w.ws,
                screen = w.screen,
                from = w.from,
                from_pos = w.from_pos,
                mine = w.mine or false,
                app = w.app,
                title = w.title,
                pos = not w.floating and self:part_of(w) and layout.index_of(self:part_of(w).order, id) or nil,
                -- Where a parked window was, for a float to go back to if
                -- tide restarts without bringing it back first.
                frame = self.parked[id] and w.park_frame or nil,
            }
        end
    end
    if now - self.started <= M.KEEP then
        for sid, s in pairs(self.saved) do
            if s.ws and s.app and not self.windows[sid] then
                out.gone[#out.gone + 1] = {
                    app = s.app, title = s.title, ws = s.ws, mine = s.mine, pos = s.pos, at = s.at or self.started,
                    numbered = s.numbered, screen = s.screen, from = s.from, from_pos = s.from_pos,
                }
            end
        end
    end
    for _, g in ipairs(self.gone) do
        if now - (g.at or 0) <= M.KEEP then
            out.gone[#out.gone + 1] = g
        end
    end
    out.current = self.current
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

-- The newest of tide's outstanding requests for `id`, if any: a restore
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

-- Take macOS's report of `kind` as the answer to tide's oldest request of
-- that kind, if there is one, and say whether there was.
function M:acknowledge(id, kind)
    return self:settle_request(id, function(r)
        return r.kind == kind
    end)
end

-- macOS says a window was minimized. If tide didn't ask, you did.
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

-- The windows you minimized on workspace `n`, on display `uuid` if given,
-- in the order you minimized them; ones minimized before tide saw them
-- first, by id.
function M:minimized_windows(n, uuid)
    local out = {}
    for id, w in pairs(self.windows) do
        if n and w.ws == n and w.mine and (uuid == nil or w.screen == uuid) and self.a.state(id) then
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

-- macOS says a window came back. If tide didn't ask, you restored it from
-- the Dock or Cmd+Tab: clear the flag, and bring its workspace along.
function M:unminimized(id)
    if self:acknowledge(id, "unmin") then
        -- A restore can finish after show() laid out and focused without it.
        if self.focus_after == id then
            self.focus_after = nil
            self:focus_unburied(id)
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

-- When tide quits, nothing stays stranded in the Dock or off screen
-- (SPEC.md §6.3): what it minimized comes back, and what it parked goes
-- back onto its display's tiling area, where it was if that's still on a
-- display.
function M:restore_all()
    local fulls = self:fulls()
    for id, w in pairs(self.windows) do
        local st = w.ws and self.a.state(id)
        if st and st.minimized and not w.mine then
            self.a.unminimize(id)
        end
        if st and self.parked[id] then
            self.parked[id] = nil
            local f = self:unpark_frame(id, fulls)
            if not f then
                local s = self:screen_by_uuid(w.screen) or self:screens()[1]
                local area = s and s.area
                f = area and {
                    x = area.x, y = area.y, w = math.min(st.frame.w, area.w), h = math.min(st.frame.h, area.h),
                }
            end
            if f then
                self.a.set_frame(id, f)
            end
            w.park_frame = nil
        end
    end
end

-- The display a switch left keys on, while focus hasn't moved since: a
-- switch to a workspace with nothing on this display, or a Send that
-- empties this display's part, leaves focus where it was, or on a window
-- on another display.
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
    -- The bar's title goes by the display keys act on.
    self:changed()
end

-- The display keys act on: the focused window's, else the pointer's. After
-- a switch leaves nothing to focus there, it's that display until focus
-- moves.
function M:current_screen()
    local kbd = self:kbd_screen()
    if kbd then
        return kbd
    end
    local id = self.a.focused()
    local uuid = self:screen_of(id)
    if uuid and self:shown(self.windows[id].ws) then
        return uuid
    end
    return self.a.pointer_screen() or (self:screens()[1] or {}).uuid
end

-- The display window `id` is on, if tide manages it: a tile's is its
-- part's; a float's is where it is.
function M:screen_of(id)
    local w = self.windows[id or false]
    if not (w and w.ws) then
        return nil
    end
    -- A parked float is off screen: its display is the one it left. So is
    -- one just unparked whose placement is still to come (place_pending):
    -- its frame is still where the park left it.
    if w.floating and not self.parked[id] then
        local st = self.a.state(id)
        if st and st.frame and not park.hidden(st.frame, self:fulls()) then
            return self:screen_of_frame(st.frame)
        end
        return w.screen
    end
    return w.screen
end

-- Show workspace `name`, on every display at once, each display its own
-- part of it (SPEC.md §6.1). `uuid` is the display the keys stay on if
-- there's nothing to focus, the one they act on unless given. A name with
-- no workspace does nothing, unless `make` says to make it, as the name
-- prompt does (SPEC.md §6.2).
function M:show(name, uuid, make)
    uuid = uuid or self:current_screen()
    local s = self:screen_by_uuid(uuid)
    local n = self:find(name)
    -- A standing workspace is made the first time it's shown.
    if not n and (make or self:standing_name(name)) then
        n = self:ensure_ws(self:canonical(name))
    end
    if not s or not n then
        return
    end
    local cur = self.current
    if cur == n then
        return
    end
    self.current = n
    -- The one left, then the one shown, most recent first, for Super+Tab
    -- and Super+End.
    if cur then
        self:used_ws(cur)
    end
    self:used_ws(n)
    self:reconcile()
    self:retile()
    -- With nothing to focus, focus stays put: keys still mean this display.
    if not self:refocus_ws(n) then
        self:unfocus_parked()
        self:keep_keys_on(uuid)
    end
    -- The display keys act on, where the sign goes.
    if self.on_show then
        self.on_show(n, uuid)
    end
end

-- With the focused window parked and nothing to focus in its place, focus
-- goes to Hammerspoon, which has no window to type into, so keys don't
-- reach a window you can't see. Minimizing left this to macOS, which
-- moved focus on itself.
function M:unfocus_parked()
    local f = self.a.focused()
    if f and self.parked[f] then
        self.a.focus_none()
    end
end

-- Focus workspace n's last used window, on display `uuid` if given, if it
-- has one, and say whether it did. If that window is still being restored,
-- it's focused when the restore lands; a later switch replaces the wait.
-- A tile with another app's float in front of it is passed over while
-- another will do (SPEC.md §5.1).
function M:refocus_ws(n, uuid)
    self.focus_after = nil
    self.kbd = nil
    local spare
    for _, id in ipairs(self.mru[n] or {}) do
        local w = self.windows[id]
        local st = w and w.ws == n and not w.mine and (uuid == nil or self:screen_of(id) == uuid)
            and self.a.state(id)
        -- An app you hid with Cmd+H stays hidden: pass over its windows,
        -- and over any still parked.
        if st and not st.hidden and not self.parked[id] then
            if st.minimized then
                -- What's in front of it is known once it's back.
                self.focus_after = id
                return true
            elseif self:buries(id) then
                spare = spare or id
            else
                self:focus_window(id)
                return true
            end
        end
    end
    if spare then
        self:focus_window(spare)
        return true
    end
    return false
end

-- Move window `id` to the end of workspace `name`'s stack on its display,
-- making the
-- workspace, at the end of the list, if the name is new. Any window may
-- be sent home (SPEC.md §6.2). Says whether the window moved. `defer` leaves the screen to
-- the caller's next reconcile, for a Send followed by a Show, so the window
-- isn't minimized and restored between the two.
function M:send(id, name, defer)
    local w = self.windows[id or false]
    local n = self:canonical(name)
    if not w or not w.ws or not n or w.ws == n then
        return false
    end
    local from = w.ws
    unplace(self, w, id)
    remove_value(self.mru[from], id)
    n = self:ensure_ws(n)
    w.screen = self:screen_of(id) or w.screen
    w.ws = n
    w.big = nil
    -- Moved by you: it stays on this display when another comes back.
    w.from, w.from_pos = nil, nil
    if not w.floating then
        -- A window you send joins the end of the stack there, whatever
        -- new_window says: that's for windows that open.
        layout.insert(self:part_of(w), id, nil, { new_window = "end" })
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
    self:choose(id)
end

-- A float waiting to be placed (M:set_float_rules) is placed as a new
-- float is, once it shows, at the size it asked for, on its display.
-- Every display shows the same workspace, so the others stay where they
-- are.
function M:follow_floats()
    for _, id in ipairs(self.floats) do
        local w = self.windows[id]
        local st = w and w.place_pending and self:shown(w.ws) and self.a.state(id)
        local to = self:shows(id, st) and (self:screen_by_uuid(self:screen_of(id)) or self:screens()[1])
        local f = to and self.a.facts(id)
        if f then
            local size = w.place_pending
            w.place_pending = nil
            local placed = {}
            for k, v in pairs(f) do
                placed[k] = v
            end
            placed.frame = { x = to.area.x, y = to.area.y, w = size.w, h = size.h }
            self:place_float(id, placed)
        end
    end
end

-- New layout settings, from tide's layouts files (SPEC.md §15): every
-- workspace's part on every display keeps its mode and takes the new mfact and master count, as on
-- tide, and the displays are laid out again at once. Unchanged settings
-- change nothing, so a reload doesn't undo what the keys set.
function M:set_layout(config)
    if layout_equal(self.layout, config) then
        return
    end
    self.layout = config
    for _, parts in pairs(self.workspaces) do
        for _, ws in pairs(parts) do
            layout.reconfigure(ws, config)
        end
    end
    self:retile()
end

-- Lay out every display, moving only windows that aren't already where
-- they belong.
-- Where display `s` lays out its part of the workspace showing: its tiles
-- in order, and each one's box, a big window's being the display's.
function M:arranged(s)
    local n = self.current
    local ws = self:part(n, s.uuid)
    if not ws then
        return {}, {}
    end
    local ids = self:tiled(n, s.uuid)
    local boxes = layout.arrange(ws, s.area, ids, self.layout)
    for _, id in ipairs(ids) do
        local big = self.windows[id].big
        if big == "max" then
            boxes[id] = s.area
        elseif big == "full" then
            boxes[id] = s.full
        end
    end
    return ids, boxes
end

-- Put every tile where its layout says; `skip`, the tile being resized by
-- hand, stays where the pointer has it, its placed frame the drag's start.
function M:retile(skip)
    self:follow_floats()
    for _, s in ipairs(self:screens()) do
        local ids, boxes = self:arranged(s)
        for _, id in ipairs(ids) do
            local box = boxes[id]
            if id == skip then
                goto continue
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
            ::continue::
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
    -- A window moved on or off a workspace that pins it.
    self:check_pinned_focus()
end

-- What the bar shows (bar.lua): for each workspace, whether it's the one
-- showing, has windows, or wants attention. Every display shows the same
-- one, so every bar, the menu bar item and the dashboard say the same.
function M:bar_state()
    local out, by = {}, {}
    for i, n in ipairs((self:listed())) do
        out[i] = { name = n, here = self:shown(n) }
        by[n] = out[i]
    end
    for _, w in pairs(self.windows) do
        if w.ws and by[w.ws] then
            by[w.ws].occupied = true
        end
    end
    for _, m in ipairs(self.attention:list()) do
        local target = self:mark_target(m)
        local w = target and self.windows[target]
        if w and w.ws and by[w.ws] then
            by[w.ws].urgent = true
        end
    end
    return out
end

-- What the dim needs (dim.lua, SPEC.md §5.6): the focused window's frame
-- and the frames of the windows in front of it, front to back, or nil when
-- nothing's to be dimmed: no window of the workspace showing has focus, it's
-- full screen, or it's the only window showing, which tide never dims
-- (tide SPEC.md §6.2). While one of tide's own windows has the focus (the
-- settings window, a launcher), they sit over the layer, and every window
-- under it is dimmed: { above = {} }, with no focused frame.
function M:dim_scene()
    if self.a.own_front() then
        return { above = {} }
    end
    local id = self.a.focused()
    local w = id and self.windows[id]
    if not w or not self:shown(w.ws) then
        return nil
    end
    local st = self.a.state(id)
    if not self:visible(id, st) or st.fullscreen then
        return nil
    end
    local others = {}
    for oid, o in pairs(self.windows) do
        if oid ~= id and o.ws == w.ws and not o.mine then
            local ost = self.a.state(oid)
            -- One full screen is on a Space of its own, not showing here.
            if self:visible(oid, ost) and not ost.fullscreen then
                others[oid] = ost.frame
            end
        end
    end
    if not next(others) then
        return nil
    end
    local above = {}
    for _, oid in ipairs(self.a.ordered()) do
        if oid == id then
            break
        end
        if others[oid] then
            above[#above + 1] = others[oid]
        end
    end
    return { focused = st.frame, above = above }
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
-- { window = id, ws = name } for a window opening on workspace `ws`, one
-- that asks, { launch = opts, go = fn }
-- for a launch, { move = id } for Super+Shift+Return, { go_to = true } for
-- Super+Return. There's one prompt, so asking a second question while one
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
            if w and w.ws == q.ws and self.ask_name then
                self.prompting = q
                self:hold("prompt", true)
                self.ask_name(q.window)
                return
            end
        elseif q.go_to then
            if self.ask_go then
                self.prompting = q
                self:hold("prompt", true)
                self.ask_go(function(name)
                    self:go_answer(q, name)
                end)
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
-- workspace if it's new, and shows it, on the display it was on, with
-- focus; nil (Esc) closes the window, politely, unless it's pinned there,
-- which says so. The workspace it's on keeps it there. A blank name, or
-- one with what a name can't hold, asks again.
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
    if w and w.ws == q.ws then
        local n = name and self:canonical(name)
        if name == nil and not self:keeps_pinned(id) then
            self.a.close(id)
        elseif name ~= nil and not n then
            table.insert(self.asking, 1, q)
        else
            if name == nil or M.fold(n) == M.fold(w.ws) then
                -- It stays, shown and focused, as a move would leave it.
                self:show(w.ws, self:screen_of(id))
                self:reconcile()
                self:retile()
                self:focus_window(id)
            else
                local uuid = self:screen_of(id)
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
    if n then
        self:show(n, nil, true)
        n = self:find(n) or n
        self:launch_to(q.launch.app, n, q.launch.screen)
        q.go(self:env(n))
    end
    self:ask_next()
end

-- The prompt's answer for Super+Return's question `q`: a name shows that
-- workspace, making it if it's new, moving no window; nil (Esc) stays.
-- Home is a name like any other here, as everywhere. A new
-- one left empty goes once you leave it, as any empty workspace does.
function M:go_answer(q, name)
    if self.prompting ~= q or self:refuse_unsafe(q, name) then
        return
    end
    self:asked_done(q)
    local n = name and self:canonical(name)
    if n then
        self:show(n, nil, true)
    end
    self:ask_next()
end

-- The prompt's answer for Super+Shift+Return's question `q`: a name moves
-- the window there and follows it, as tide's does: that workspace shows on
-- the display the window was on, with the window focused. Nil (Esc) leaves
-- it, and you where you are.
function M:move_answer(q, name)
    if self.prompting ~= q or self:refuse_unsafe(q, name) then
        return
    end
    self:asked_done(q)
    local id = q.move
    local w = self.windows[id]
    if name and w then
        -- The display it moves from, noted before it moves.
        local uuid = self:screen_of(id) or self:current_screen()
        -- Reconciled once, after the show, so the window never hides on
        -- the way, as for a new window's answer.
        if self:send(id, name, true) then
            self:show(self.windows[id].ws, uuid)
            -- Already showing there, show() had nothing to do.
            self:reconcile()
            self:retile()
            self:focus_window(id)
        end
    end
    self:ask_next()
end

-- TIDE_WORKSPACE for a process tide starts on workspace `n` (SPEC.md §6.3):
-- empty, and logged, when the name's letters and digits can't be found.
function M:env(n)
    local value, err = names.sanitize(n, self.a.javascript)
    if err then
        self.a.log("TIDE_WORKSPACE is empty: " .. err)
    end
    return { TIDE_WORKSPACE = value }
end

-- Before a launch tide makes (the switcher's Launch tab, an app key,
-- Cmd+Return), the workspace it's for (SPEC.md §6.2, §9): from a
-- workspace whose askForName is on (home by default), or for Cmd+Return
-- (`opts.fresh`) from anywhere, it asks for a name first,
-- with `opts.default` typed in, unless the app is one of home's
-- (`opts.home_app`, and never for Cmd+Return). `opts.app` is the bundle
-- ID, if known, which the launch's window is matched by (launch_to). The question waits its turn
-- behind any other. A name shows that workspace, making it if it's new,
-- then `go(env)` launches with its TIDE_WORKSPACE; Esc launches nothing.
-- Elsewhere it launches straight away, on the workspace you're on.
function M:before_launch(opts, go)
    -- The display you launched from, before the prompt takes focus and a
    -- switch to the workspace named focuses one of its windows.
    opts.screen = opts.screen or self:current_screen()
    local cur = self:current_ws()
    local ask = opts.fresh or (self:asks_for_name(cur) and not opts.home_app)
    if not ask or not self.ask_launch then
        self:launch_to(opts.app, cur, opts.screen)
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
-- or nil if that one is ignored or unknown, such as picture-in-picture or
-- Hammerspoon's console over a tile, or one of tide's own windows.
function M:window_at(x, y)
    if self:own_at(x, y) then
        return nil
    end
    for _, id in ipairs(self.a.ordered()) do
        local st = self.a.state(id)
        -- A parked window's sliver isn't one to pick.
        if self:visible(id, st) and inside(st.frame, x, y) then
            local w = self.windows[id]
            if w and w.kind ~= "ignore" and w.ws then
                return id
            end
            return nil
        end
    end
end

-- The split a resize of tile `id` from `from` (its placed frame unless
-- given) to `box` sets, on its part: true when it changed it. A lone
-- tile's sets its width.
function M:resize_split(id, box, from)
    local w = self.windows[id]
    local old = from or self.placed[id]
    local s = self:screen_for(box)
    local ws = self:part_of(w)
    local ids = self:tiled(w.ws, w.screen)
    local i = layout.index_of(ids, id)
    if s and i and #ids == 1 then
        -- A lone window stays centered: the other edge follows.
        local width = mouse.single_width_for(s.area, old, box)
        if not width or width == ws.single_width then
            return false
        end
        ws.single_width = width
        return true
    end
    local f = s and i and mouse.mfact_for(ws.mode, ws.opts[ws.mode] or {}, i, #ids, s.area, old, box)
    if not f then
        return false
    end
    f = layout.geometry.clamp(f, 0.1, 0.9)
    local opts = ws.opts[ws.mode]
    if opts.mfact == f then
        return false
    end
    opts.mfact = f
    return true
end

-- Whether putting tile `id` where its layout now says would move an edge
-- being dragged (from `old` to `box`) away from the pointer, as clamping
-- the split, or a corner drag's height, can. If not, it's placed too, so a centered tile (a lone
-- window, threecol's middle master) narrows on both sides as you drag.
function M:fights_drag(id, old, box)
    local s = self:screen_for(box)
    if not s then
        return true
    end
    local _, boxes = self:arranged(s)
    local b = boxes and boxes[id]
    if not b then
        return true
    end
    -- Every edge the drag moved must stay where the pointer put it.
    local function off(a1, a2)
        return math.abs(a1 - a2) > 2
    end
    if box.x ~= old.x and off(b.x, box.x) then
        return true
    end
    if box.x + box.w ~= old.x + old.w and off(b.x + b.w, box.x + box.w) then
        return true
    end
    if box.y ~= old.y and off(b.y, box.y) then
        return true
    end
    if box.y + box.h ~= old.y + old.h and off(b.y + b.h, box.y + box.h) then
        return true
    end
    return false
end

-- A tile the user moved or resized to `box`, by its own edges or with
-- Super+drag. A resize sets the split; a move puts the window in the tile
-- nearest where its center landed, swapping with that tile's window, or on
-- the display it landed on, in the same workspace (SPEC.md §6.1).
function M:request(id, box)
    local w = self.windows[id]
    if not w or not w.ws or w.floating then
        return
    end
    local old = self.placed[id]
    local cx, cy = center(box)
    local s = self:screen_for(box)
    -- Another display first: macOS may resize a window it moves onto a
    -- smaller display, and that's still a move. A launched window that
    -- hasn't been placed yet is only where macOS opened it, or where the app
    -- put it next, not somewhere you moved it.
    if s and s.uuid ~= w.screen and (old or not w.launched_on) then
        self:to_screen(id, s.uuid)
        layout.insert(self:part_of(w), id, nil, self.layout)
        -- Focused already, so no focus event will put it first in its
        -- workspace's history.
        remove_value(self.mru[w.ws], id)
        table.insert(self.mru[w.ws], 1, id)
        self:save()
    elseif old and (old.w ~= box.w or old.h ~= box.h) then
        self:resize_split(id, box)
    elseif s then
        local ws = self:part_of(w)
        local ids = self:tiled(w.ws, w.screen)
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

-- macOS says a window moved or changed size. Ignore the moves tide made;
-- treat the rest as a request, once the button is up.
-- A float you moved to another display is on that display now, in the
-- workspace showing.
function M:float_landed(id)
    local w = self.windows[id]
    local st = w and w.floating and self.a.state(id)
    if not st then
        return
    end
    local uuid = self:screen_of_frame(st.frame)
    local n = self.current
    if n and (n ~= w.ws or uuid ~= w.screen) then
        remove_value(self.mru[w.ws], id)
        w.ws = n
        w.screen = uuid
        table.insert(self.mru[n], 1, id)
        self:save()
    end
end

-- Take window `id` out of its part and put it on display `uuid`, in the
-- same workspace, with nothing to go back to: you moved it. The caller
-- puts it in that display's order.
function M:to_screen(id, uuid)
    local w = self.windows[id]
    unplace(self, w, id)
    w.screen = uuid
    w.big = nil
    w.from, w.from_pos = nil, nil
end

function M:moved(id)
    -- tide's own park, which no request or landing should read.
    if self.parked[id] then
        return
    end
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
    if not st then
        return
    end
    local down = self.a.buttons_down()
    local s = self:screen_for(st.frame)
    local here = s and s.uuid == w.screen
    local live = self.live_resize
    if live and live.id ~= id then
        live = nil
    end
    -- A resize by the tile's own edge moves its neighbors as it goes. Each
    -- step is worked out afresh from where the drag started and the split
    -- as the drag found it, so an edge taken back puts the split back, and
    -- one taken out again moves it again. Over another display, where macOS
    -- may resize a window it moves, it's a move, which the drop takes.
    if not live and down and here then
        local start = self.placed[id]
        if start and (start.w ~= st.frame.w or start.h ~= st.frame.h) then
            local part = self:part_of(w)
            -- The edge you took hold of: a centered tile's other edge moves
            -- too, by tide's hand, and mustn't take over the split.
            local edge
            if st.frame.x + st.frame.w ~= start.x + start.w then
                edge = "right"
            elseif st.frame.x ~= start.x then
                edge = "left"
            end
            live = {
                id = id, start = start, part = part, mode = part.mode, edge = edge,
                mfact = (part.opts[part.mode] or {}).mfact, single_width = part.single_width,
            }
            self.live_resize = live
        end
    end
    if live and not live.edge then
        -- A corner drag may change only the height at first: the edge you
        -- hold is the first side to move.
        local st0 = live.start
        if st.frame.x + st.frame.w ~= st0.x + st0.w then
            live.edge = "right"
        elseif st.frame.x ~= st0.x then
            live.edge = "left"
        end
    end
    if live then
        local part, opts = live.part, live.part.opts[live.mode]
        local mfact, width = opts.mfact, part.single_width
        opts.mfact, part.single_width = live.mfact, live.single_width
        if here then
            -- Only the edge you hold moves the split: the other is the start's.
            local box, st0 = st.frame, live.start
            if live.edge == "right" then
                box = { x = st0.x, y = box.y, w = box.x + box.w - st0.x, h = box.h }
            elseif live.edge == "left" then
                box = { x = box.x, y = box.y, w = st0.x + st0.w - box.x, h = box.h }
            end
            self:resize_split(id, box, live.start)
        end
        if not down then
            self.live_resize = nil
            if not here then
                -- Dropped on another display: a move, with the split as it was.
                self:request(id, st.frame)
                return
            end
            self:retile()
            return
        end
        if opts.mfact ~= mfact or part.single_width ~= width then
            -- The edges you moved are the ones that differ from where tide
            -- last put the tile, which mid-drag may not be where it started.
            self:retile(self:fights_drag(id, self.placed[id], st.frame) and id or nil)
        end
        self.a.after(0.1, function()
            self:moved(id)
        end)
        return
    end
    if same(st.frame, self.placed[id]) then
        return
    end
    if down then
        -- A move waits for the drop, which may swap it.
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

-- tide's own windows, by owner: the settings window, tileco's launcher,
-- the dashboard. They're web pages, and asking Accessibility what's under
-- the pointer over one waits on the page, a quarter of a second each
-- question, so focus follows mouse leaves them be. `frame` is the
-- window's box, or a function giving it; nil says it has gone, and its box
-- counts for M.OWN_GRACE more seconds, while macOS takes it off the
-- screen.
M.OWN_GRACE = 0.5

function M:own_window(owner, frame)
    self.own = self.own or {}
    local o = self.own[owner] or {}
    self.own[owner] = o
    if frame then
        o.frame, o.gone_at = frame, nil
    elseif o.frame then
        o.last = type(o.frame) == "function" and o.frame() or o.frame
        o.frame, o.gone_at = nil, self.a.now()
    end
end

local function own_box(o, now)
    if o.frame then
        if type(o.frame) == "function" then
            return o.frame()
        end
        return o.frame
    end
    if o.gone_at and now - o.gone_at < M.OWN_GRACE then
        return o.last
    end
end

-- Whether x, y is over one of tide's own windows, or its overlays (the
-- tray).
function M:own_at(x, y)
    for _, box in ipairs(self.overlays or {}) do
        if inside(box, x, y) then
            return true
        end
    end
    local now = self.a.now()
    for _, o in pairs(self.own or {}) do
        local box = own_box(o, now)
        if box and inside(box, x, y) then
            return true
        end
    end
    return false
end

-- Hold the keyboard for `owner` (the launcher, the dashboard, resize mode)
-- or let it go. Focus follows mouse pauses while anyone holds it, so one
-- overlay closing can't release another's hold.
function M:hold(owner, on)
    self.holds = self.holds or {}
    self.holds[owner] = on or nil
    self.holding_keyboard = next(self.holds) ~= nil
end

-- `by_pointer`: focus follows mouse moved it, which doesn't end a grant
-- (M:grant): what you clicked or chose may still be on its way, and a slow
-- app's window mustn't lose its focus to the pointer passing over a tile.
function M:focus_window(id, by_pointer)
    local w = self.windows[id]
    if not w then
        return
    end
    -- Focusing something else is a newer choice than a slow restore.
    if self.focus_after ~= id then
        self.focus_after = nil
    end
    -- The focus report this causes is tide's, not an app helping itself,
    -- and moving focus ends a launch's grant. Every ask within M.GRACE is
    -- kept, not just the last: focus follows mouse starts its next focus
    -- as soon as macOS confirms one, or once its wait runs out, which can be
    -- before tide has heard the report for the one before.
    local now = self.a.now()
    local asked = {}
    for _, q in ipairs(self.asked) do
        if q.id ~= id and now - q.at <= M.GRACE then
            asked[#asked + 1] = q
        end
    end
    asked[#asked + 1] = { id = id, app = w.app, at = now }
    self.asked = asked
    if not by_pointer then
        self.granted = nil
    end
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

-- Focus window `id` because you picked it, with a key or an app key: the
-- keys go where it is, even when it had focus already, so a display a
-- switch or Super+Left/Right left them on lets go (kbd_screen keeps them
-- only while focus hasn't moved).
function M:choose(id)
    self.kbd = nil
    self:focus_window(id)
end

-- A click: whatever it picks is newer than a restore still on its way,
-- and than a switch that kept keys on its display. (A focus report alone
-- can't say this: macOS moves focus itself as tide minimizes, and a click
-- on the window that already has focus reports nothing.)
function M:clicked()
    self.focus_after = nil
    self.kbd = nil
    -- A click is yours, and so is what it starts: a Dock icon, a link, a
    -- notification.
    local now = self.a.now()
    self.last_input = now
    self.last_switch = now
    -- A menu item you chose is yours whatever it opens, even a window of an
    -- app that has one already: About This Mac is System Settings'.
    self:grant(nil, not self.a.menu_open())
end

-- The focus guard (SPEC.md §14.1) -------------------------------------------

-- A launch you made: a window of `app` (of any app, when tide can't tell
-- which, as for a helper script) may take focus within M.GRANT, once, if
-- you haven't typed, clicked or moved focus since. `first_only` limits it
-- to an app with no window open before the grant, for a launch guessed
-- from the click or Return that may have started it outside tide (the
-- Dock, Spotlight, Finder); every window that launch opens counts.
function M:grant(app, first_only)
    self.granted = { app = app, at = self.a.now(), first_only = first_only or false }
end

-- A key went down. Typing ends a launch's grant. A key with Command held
-- (Cmd+Tab, tide's own keys) or Return (Spotlight, a file in Finder) is a
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
    if not self:visible(prev, st) or p.mine or not (p.ws and self:shown(p.ws)) then
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
    -- Never to the thief itself.
    self:focus_unburied(self.history[1], id)
    self.granted = g
end

-- Called when macOS reports a window gained focus, by tide or by a click
-- or app switch. A window too new to have been synced is added now, so its
-- focus isn't lost.
function M:focused(id)
    self:focused_window(id)
    self:check_pinned_focus()
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
    self.attention:focused(id, w.app, self.tab_hosts[id])
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
    -- (tide SPEC.md §6.3), on the same display: each display lays out its
    -- own part.
    local changed = false
    local on = self:screen_of(id)
    for oid, o in pairs(self.windows) do
        if oid ~= id and o.ws == w.ws and o.big == "max" and o.screen == on then
            o.big = nil
            changed = true
        end
    end
    if changed then
        self:retile()
    end
    -- A parked window that took focus, from Cmd+Tab, a click on its sliver
    -- or its app coming to the front, brings its workspace along, as one
    -- restored from the Dock does (M:unminimized).
    -- Only while it still has the focus: a late report of a focus from
    -- before a switch, its window parked since, mustn't pull you back.
    if self.parked[id] and not self:shown(w.ws) and self.a.focused() == id then
        self:activate(id)
    end
end

-- Take tile `id` out of its workspace's layout and float it, placed as a
-- new float is. The caller retiles.
function M:float_tile(id, f)
    local w = self.windows[id]
    w.floating = true
    w.big = nil
    unplace(self, w, id)
    self.floats[#self.floats + 1] = id
    if f and self.parked[id] then
        -- Parked, it's placed once its workspace shows (follow_floats), at
        -- this size: the tile's frame from before the park is stale.
        w.park_frame = nil
        w.place_pending = { w = f.frame.w, h = f.frame.h }
    elseif f then
        self:place_float(id, f)
    end
end

-- New float rules from the Floating page's files (SPEC.md §15). A new rule
-- floats the windows open now that it covers, on every workspace, as tide's
-- does (tide §16): each tiled window the new rules float and the old ones
-- didn't. One the old rules floated was tiled by hand, and stays; full
-- screen and maximized ones are left as they are; nothing is tiled.
-- Returns the ids floated.
function M:set_float_rules(list)
    local old = self.rules
    self.float_rules = list or {}
    self.rules = floating.combined(self.start_rules, self.float_rules)
    local ws = {}
    for id, w in pairs(self.windows) do
        if w.ws then
            ws[#ws + 1] = { id = id, facts = self.a.facts(id), tiled = not w.floating, big = w.big ~= nil }
        end
    end
    table.sort(ws, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    local ids = floating.sweep(ws, old, self.rules)
    for _, id in ipairs(ids) do
        local w = self.windows[id]
        w.kind = "float"
        for i = #self.asking, 1, -1 do
            if self.asking[i].window == id then
                table.remove(self.asking, i)
            end
        end
        -- Placed as a new float is, at the size it opened at, by the next
        -- retile that finds it showing (M:follow_floats): at once if it
        -- shows now, else once its workspace shows or it's restored.
        local f = self.a.facts(id)
        local size = w.opened or (f and f.frame)
        w.place_pending = size and { w = size.w, h = size.h } or nil
        self:float_tile(id, nil)
    end
    if #ids > 0 then
        self:reconcile()
        self:retile()
        self:changed()
    end
    return ids
end

-- Whether a rule, or the steps that float dialogs, floats window `id`
-- without your asking.
function M:covered(id)
    local f = self.a.facts(id)
    return f ~= nil and rules.decide(f, self.rules) == "float"
end

-- The Floating page's "Floating now": the floating windows no rule covers,
-- one per app, each the page's fill-in for it (floating.prefill), ordered
-- by app name.
function M:floating_now()
    local out, seen = {}, {}
    local ids = {}
    for id, w in pairs(self.windows) do
        if w.ws and w.floating then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, id in ipairs(ids) do
        local f = self.a.facts(id)
        if f and f.app and f.app ~= "" and not seen[f.app] and rules.decide(f, self.rules) ~= "float" then
            seen[f.app] = true
            out[#out + 1] = self:float_prefill(id, f)
        end
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- The Floating page's fill-in for window `id` (floating.prefill), or nil
-- when it has no app to name.
function M:float_prefill(id, f)
    f = f or self.a.facts(id)
    local info = self.a.about and self.a.about(id) or nil
    return floating.prefill(f, info, self.start_rules, self.float_rules)
end

-- Window `id`'s title changed. One tide tiled by its rules, in its first
-- M.SETTLE, is decided again with the new title, as if it had opened with
-- it: a browser's popup, such as Bitwarden's sign-in, autofill and passkey
-- prompts, can open before its page names it. Only a tile that should
-- float moves; one you placed with Super+Shift+F stays yours.
function M:retitled(id)
    local w = self.windows[id]
    if not (w and w.ws) or w.floating or w.chosen or self.a.now() - w.seen > M.SETTLE then
        return
    end
    local f = self.a.facts(id)
    if not f then
        return
    end
    w.title = f.title
    if rules.decide(f, self.rules) ~= "float" then
        return
    end
    w.kind = "float"
    -- A float doesn't ask for a name (M:add); one already asking keeps its
    -- prompt.
    for i = #self.asking, 1, -1 do
        if self.asking[i].window == id then
            table.remove(self.asking, i)
        end
    end
    local placed = {}
    for k, v in pairs(f) do
        placed[k] = v
    end
    placed.frame = w.opened or f.frame
    self:float_tile(id, placed)
    -- As a float named at once would, it goes where its parent is (M:add),
    -- which may not be where it opened as a tile, and shows if that does.
    local n = self:parent_ws(id, f)
    if n and n ~= w.ws then
        remove_value(self.mru[w.ws], id)
        w.ws = n
        local list = self.mru[n]
        list[#list + 1] = id
    end
    self:reconcile()
    self:retile()
    self:changed()
end

-- After a close, something keeps focus: the window under the pointer, as
-- tide's focus_on_close, else the last used window left on that workspace,
-- else any tile you can see there. The fallback means a window that reached
-- the workspace without a focus event, such as one moved off a display that
-- went away, still counts. A tile with another app's float in front of it
-- is passed over while another will do: focusing it would bury the float
-- (SPEC.md §5.1).
function M:refocus(n)
    -- One of tide's own windows having it counts: a close behind the
    -- launcher or Tide Settings leaves them be.
    if self.a.focused() or self.a.own_front() then
        return
    end
    local spare
    local function take(id)
        if self:buries(id) then
            spare = spare or id
            return false
        end
        self:focus_window(id)
        return true
    end
    if self.ffm and self.ffm.enabled then
        local x, y = self.a.pointer()
        local id = x and self.ffm:hit(x, y)
        if id and self.windows[id].ws == n and take(id) then
            return
        end
    end
    for _, id in ipairs(self.mru[n] or {}) do
        -- Only a window you can see: focusing a minimized one doesn't
        -- bring it back.
        local w = self.windows[id]
        local st = w and w.ws == n and self.a.state(id)
        if self:visible(id, st) and not st.fullscreen and take(id) then
            return
        end
    end
    local screens = self:screens()
    table.insert(screens, 1, { uuid = self:current_screen() })
    for _, s in ipairs(screens) do
        local id = self:tiled(n, s.uuid)[1]
        if id and take(id) then
            return
        end
    end
    if spare then
        self:focus_window(spare)
    end
end

-- Whether focusing window `id` would bury another app's float: it's a
-- tile with one in front of it, and macOS won't raise the float back over
-- the app just focused (SPEC.md §5.1). Only a focus you didn't choose asks:
-- a key or a click on the tile still focuses it.
function M:buries(id)
    return self.ffm ~= nil and id ~= nil and self.ffm:under_float(id)
end

-- The last used window you can see on workspace `n`, other than `except`
-- and `avoid`, that focusing wouldn't bury another app's float under, if
-- there is one.
function M:unburied_on(n, except, avoid)
    for _, id in ipairs(self.mru[n] or {}) do
        local w = self.windows[id]
        local st = id ~= except and id ~= avoid and w and w.ws == n and not w.mine and self.a.state(id)
        if self:visible(id, st) and not st.fullscreen and not self:buries(id) then
            return id
        end
    end
end

-- Focus window `id`, which tide picked for you, not you: back to the
-- window you were in, or one that was being restored. If that's a tile
-- with another app's float in front of it, the last used window on its
-- workspace that isn't goes instead, so the float stays on top; with none,
-- `id` does after all. `avoid` is never the one instead: a window that
-- just took focus unasked, which focusing would count as asked for.
function M:focus_unburied(id, avoid)
    local w = self.windows[id or false]
    local alt = w and self:buries(id) and self:unburied_on(w.ws, id, avoid)
    self:focus_window(alt or id)
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

-- The part the keys act on: the workspace showing, on the display keys
-- act on (current_screen), which is the focused window's unless a switch
-- or Super+Left/Right left the keys on another display, and never a
-- hidden workspace's, though focus may have stayed on one of its windows.
function M:current_part()
    local uuid = self:current_screen()
    local n = self:current_ws()
    return self:part(n, uuid), n, uuid
end

function A.focus(self, delta)
    local _, n, uuid = self:current_part()
    local ids = self:tiled(n, uuid)
    local id = self:focused_tile()
    local target = layout.neighbor(ids, id, delta)
    -- Focusing raises the target, monocle's full-size tile included, and
    -- then its floats go back over it.
    if target then
        self:choose(target)
    end
end

function A.move(self, delta)
    local id, w = self:focused_tile()
    if id then
        layout.move(self:part_of(w), self:tiled(w.ws, w.screen), id, delta)
        self:retile()
    end
end

function A.swap_master(self)
    local id, w = self:focused_tile()
    if id then
        layout.swap_master(self:part_of(w), self:tiled(w.ws, w.screen), id)
        self:retile()
    end
end

function A.mfact(self, sign)
    layout.mfact((self:current_part()), sign * self.layout.mfact_step)
    self:retile()
end

function A.nmaster(self, delta)
    layout.nmaster((self:current_part()), delta)
    self:retile()
end

function A.cycle(self, delta)
    layout.cycle((self:current_part()), delta, self.layout)
    self:retile()
end

function A.monocle(self)
    layout.toggle_monocle((self:current_part()))
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
    -- Yours now: a late title doesn't decide it again (M:retitled).
    w.chosen = true
    if w.floating then
        w.floating = false
        w.place_pending = nil
        remove_value(self.floats, id)
        w.screen = self:screen_of_frame((self.a.state(id) or {}).frame) or w.screen
        w.from, w.from_pos = nil, nil
        layout.insert(self:part_of(w), id, nil, self.layout)
    else
        self:float_tile(id, self.a.facts(id))
        -- Floated by the key, with no rule covering it: tide asks whether
        -- to always float its app (floating_hs.lua).
        if self.floated_by_hand and not self:covered(id) then
            self.floated_by_hand(id)
        end
    end
    self:retile()
end

-- Super+Shift+I: the settings window's Floating section, filled in for
-- the focused window (SPEC.md §15).
function A.float_rule(self)
    if self.open_float_rule then
        self.open_float_rule(self.a.focused())
    end
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

-- The window's going away is seen by the next sync, which refocuses. One
-- pinned on its workspace stays open, and a notification says so.
function A.close(self)
    local id = self.a.focused()
    if id and not self:keeps_pinned(id) then
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
    local uuid = from and self:screen_of(id)
    self:send(id, n)
    -- Focus stays on the workspace you're on, on this display, as on tide;
    -- with nothing left there, so do the keys.
    if from and self.windows[id] and self.windows[id].ws ~= from then
        if not self:refocus_ws(from, uuid) then
            self:unfocus_parked()
            if uuid then
                self:keep_keys_on(uuid)
            end
        end
    end
end

-- The workspace `d` steps from `cur` in bar order: with `wrap`, from the
-- last round to the first and back, as the keys do; without, stopping at
-- the first and last, as the bar's scroll does.
function M:step_from(cur, d, wrap)
    local list = self:listed()
    local i = self:index_of_ws(cur) or 1
    if wrap then
        return list[(i - 1 + d) % #list + 1]
    end
    return list[math.max(1, math.min(#list, i + d))]
end

-- Whether workspace `n` has a window you haven't minimized: what
-- Super+PgUp and PgDn stop at.
function M:has_windows(n)
    for _, w in pairs(self.windows) do
        if w.ws == n and not w.mine then
            return true
        end
    end
    return false
end

-- Super+PgUp/PgDn: the previous or next workspace in bar order that has a
-- window, wrapping from the last to home and back, as on tide, so an empty
-- one is never a stop; with none, it stays.
function A.step(self, d)
    local list = self:listed()
    local i = self:index_of_ws(self:current_ws()) or 1
    for k = 1, #list - 1 do
        local n = list[(i - 1 + d * k) % #list + 1]
        if self:has_windows(n) then
            self:show(n)
            return
        end
    end
end

-- The Nth workspace in bar order, or the last for 0, or nil past the last.
function M:nth_listed(i)
    local list = self:listed()
    return list[i == 0 and #list or i]
end

-- Super+1…9 (SPEC.md §7.2): the Nth workspace in bar order, home first, so
-- Super+1 is home. Past the last workspace, nothing. Super+0 is the last.
function A.nth(self, i)
    local n = self:nth_listed(i)
    if n then
        self:show(n)
    end
end

-- Super+Shift+1…9: send the focused window to the Nth workspace in bar
-- order, with focus staying here, as Super+Shift+N did. Past the last,
-- nothing. Super+Shift+0 sends it to the last.
function A.send_nth(self, i)
    local n = self:nth_listed(i)
    if n then
        self:send_keeping_focus(self.a.focused(), n)
    end
end

-- Super+Home: the home workspace (SPEC.md §6.1).
function A.home(self)
    self:show(self.home)
end

-- Super+Tab (SPEC.md §7.2): from any other workspace, home; from home, the
-- workspace you used last. Pressed again, it flips back.
function A.flip(self)
    local cur = self:current_ws()
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
    local cur = self:current_ws()
    local n = self:last_used(function(m)
        return m == self.home or m == cur
    end)
    if n then
        self:show(n)
    end
end

-- Super+Return (SPEC.md §7.2): go to a workspace by name, with the prompt
-- listing them all. It needs no window, so it works on an empty workspace.
-- A second press while it's asked, or waiting to be, asks nothing more.
function A.go_to(self)
    if not self.ask_go then
        return
    end
    if self.prompting and self.prompting.go_to then
        return
    end
    for _, q in ipairs(self.asking) do
        if q.go_to then
            return
        end
    end
    self.asking[#self.asking + 1] = { go_to = true }
    self:ask_next()
end

-- Super+Shift+Return (SPEC.md §7.2): move the focused window to a
-- workspace by name, with the prompt listing them all, and follow it there,
-- as Super+Shift+PgDn does. Esc leaves the window where it is. With no
-- window there's nothing to move, so it does nothing, and the log says why.
function A.move_to(self)
    local id = self.a.focused()
    local w = self.windows[id or false]
    if not w or not w.ws then
        self.a.log("Super+Shift+Return: no window focused, so no window to move")
        return
    end
    if not self.ask_move then
        return
    end
    self.asking[#self.asking + 1] = { move = id }
    self:ask_next()
end

-- Super+Shift+PgUp/PgDn: move the focused window to the previous or next
-- workspace, and follow it.
function A.move_ws(self, d)
    local id = self.a.focused()
    -- The display it moves from, noted before the window moves.
    local uuid = self:current_screen()
    local cur = self:current_ws()
    local n = self:step_from(cur, d, true)
    if id and n ~= cur and self:send(id, n) then
        self:show(n, uuid)
        self:choose(id)
    end
end

-- Left and right (SPEC.md §7.2) ------------------------------------------

-- What's on side `d` of where the keys are, by direction.lua's rule: the
-- tile picked, if any, and its display, if there's one that way. On the
-- next display only the tiles at the edge you come in by are picked from. "Where
-- the keys are" is the focused window's box on the display keys act on,
-- or that whole display with no window of its own focused.
function M:beside(d)
    local uuid = self:current_screen()
    local here = self:screen_by_uuid(uuid)
    if not here then
        return nil
    end
    local focused = self.a.focused()
    local displays = {}
    local box
    for _, s in ipairs(self:screens()) do
        local ids, boxes = self:arranged(s)
        local tiles = {}
        for _, id in ipairs(ids) do
            tiles[#tiles + 1] = { id = id, box = boxes[id] }
            if id == focused and s.uuid == uuid then
                box = boxes[id]
            end
        end
        -- direction.lua is tide's, so a display is a monitor to it: its
        -- `name` and `box`. It reads only a tile's box, so `id` can stand
        -- where tide keeps `address`.
        displays[#displays + 1] = { name = s.uuid, uuid = s.uuid, box = s.full, tiles = tiles }
    end
    -- A float is where it is, if that's on this display.
    local w = self.windows[focused or false]
    if not box and w and w.ws and w.floating then
        local st = self.a.state(focused)
        local on = self:shows(focused, st) and self:screen_for(st.frame)
        if on and on.uuid == uuid then
            box = st.frame
        end
    end
    return direction.find(box or here.area, uuid, displays, d)
end

-- Whether key list `p` sorts before `q`, first entry first.
local function less(p, q)
    for i = 1, #p do
        if p[i] ~= q[i] then
            return p[i] < q[i]
        end
    end
    return false
end

-- Where window `id`, coming onto display `s` going `d`, goes in workspace
-- `n`'s order: the tile it goes before, or nil for the end. Tile order
-- isn't left to right (threecol's third tile is on the left), so each slot
-- is laid out, and the one putting the window nearest the edge it came in
-- by wins: the left edge moving right, the right moving left; then the one
-- sharing the most height with `from`, where it was; then the nearest
-- center; then the earliest slot.
function M:entry_slot(n, s, id, d, from)
    local ws = self:part(n, s.uuid)
    local ids = {}
    for _, other in ipairs(self:tiled(n, s.uuid)) do
        if other ~= id then
            ids[#ids + 1] = other
        end
    end
    local best, best_key
    for k = 1, #ids + 1 do
        local trial = { table.unpack(ids) }
        table.insert(trial, k, id)
        local b = layout.arrange(ws, s.area, trial, self.layout)[id]
        local edge = d > 0 and b.x - s.area.x or s.area.x + s.area.w - (b.x + b.w)
        local cx, cy = b.x + b.w / 2, b.y + b.h / 2
        local fx, fy = cx, cy
        if from then
            fx, fy = from.x + from.w / 2, from.y + from.h / 2
        end
        local key = { edge, from and -direction.overlap(from, b) or 0, (cx - fx) ^ 2 + (cy - fy) ^ 2 }
        if not best_key or less(key, best_key) then
            best, best_key = k, key
        end
    end
    return ids[best]
end

-- Super+Left/Right: select the window left or right of the focused one,
-- at a display's edge the nearest on the next display that way. A display
-- there with no tiles takes the keys, as an empty workspace's does.
function A.select(self, d)
    local hit, s = self:beside(d)
    if hit then
        self:choose(hit.id)
    elseif s then
        self:keep_keys_on(s.uuid)
    end
end

-- A float moving `d`: onto the next display that way, by direction.lua's
-- rule, at the same relative spot in its work area and its size, shrunk
-- only to fit (direction.place). It stays floating and in its workspace,
-- joining that display's part, with focus. Past the last display, nothing.
function M:move_float_side(id, w, d)
    local st = self.a.state(id)
    if not self:shows(id, st) or not self:shown(w.ws) then
        return
    end
    local here = self:screen_for(st.frame)
    local displays, cur = {}, nil
    for _, s in ipairs(self:screens()) do
        -- A display is a monitor to direction.lua: its `name` and `box`.
        displays[#displays + 1] = { name = s.uuid, box = s.full, screen = s }
        if s.uuid == here.uuid then
            cur = displays[#displays]
        end
    end
    local next_one = cur and direction.next_monitor(cur, displays, d)
    if not next_one then
        return
    end
    local s = next_one.screen
    self.a.set_frame(id, direction.place(st.frame, here.area, s.area))
    w.screen = s.uuid
    remove_value(self.mru[w.ws], id)
    table.insert(self.mru[w.ws], 1, id)
    self:save()
    self:choose(id)
    -- A float that moved changes what's under the pointer.
    if self.ffm then
        self.ffm:resync()
    end
end

-- Super+Shift+Left/Right: move the focused tile the same way, swapping it
-- with the tile there on this display, or onto the next display at the
-- edge, staying in the same workspace, as a window you drag there does
-- (SPEC.md §6.1), in the slot whose tile lands nearest the
-- edge it came in by (M:entry_slot). A float goes straight to the next
-- display (M:move_float_side).
function A.move_side(self, d)
    local fid = self.a.focused()
    local fw = self.windows[fid or false]
    if fw and fw.ws and fw.floating then
        self:move_float_side(fid, fw, d)
        return
    end
    local id, w = self:focused_tile()
    if not id then
        return
    end
    local hit, s = self:beside(d)
    if not s then
        return
    end
    local from_box = self.placed[id] or (self.a.state(id) or {}).frame
    local n = w.ws
    if s.uuid == w.screen then
        local order = self:part_of(w).order
        local i, j = layout.index_of(order, id), hit and layout.index_of(order, hit.id)
        if i and j then
            order[i], order[j] = order[j], order[i]
        end
        self:retile()
        return
    end
    -- Onto the next display, in the same workspace.
    local before = self:entry_slot(n, self:screen_by_uuid(s.uuid), id, d, from_box)
    self:to_screen(id, s.uuid)
    local ws = self:part_of(w)
    local i = before and layout.index_of(ws.order, before)
    table.insert(ws.order, i or #ws.order + 1, id)
    remove_value(self.mru[n], id)
    table.insert(self.mru[n], 1, id)
    self:reconcile()
    self:retile()
    self:choose(id)
end

-- Apps and the launcher ----------------------------------------------------

-- An app's managed windows, most recently used first: by focus across
-- workspaces, then by each workspace's own order for windows not focused
-- since tide started.
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

-- The window a mark points at: its own, or for an app's, the app's last
-- used window, preferring one whose front tab is on the notification's
-- site (SPEC.md §14.2). Nil when the app has no window left.
function M:mark_target(m)
    if m.id then
        return m.id
    end
    local ids = self:app_windows(m.app)
    if m.site then
        for _, id in ipairs(ids) do
            if self.tab_hosts[id] == m.site then
                return id
            end
        end
    end
    return ids[1]
end

-- The windows wanting attention, newest first, for the switcher's
-- Attention tab (Super+A). Only marks with a window to go to: a notifying
-- app may have quit. An app's notification and its window's bell can name
-- the same window; it comes once, where its newest mark puts it.
function M:attention_windows()
    local list, seen = {}, {}
    for _, m in ipairs(self.attention:list()) do
        local target = self:mark_target(m)
        if target and self.windows[target] and not seen[target] then
            seen[target] = true
            list[#list + 1] = target
        end
    end
    return list
end

-- `app` sent a notification, from browser site `site` or nil (SPEC.md
-- §14.2). The app you're in needs no mark: you're looking at it.
function M:notified(app, site)
    local f = self.a.focused()
    local w = f and self.windows[f]
    if w and w.app == app and (not site or self.tab_hosts[f] == site) then
        return
    end
    self.attention:notified(app, site)
    self:changed()
end

-- Window `id` rang the bell (SPEC.md §14.2); the focused one needs no mark.
function M:rang(id)
    local w = self.windows[id]
    if not w or id == self.a.focused() then
        return
    end
    self.attention:rang(id, w.app)
    self:changed()
end

-- Read window titles, and clear what's focused now: a window left with the
-- focus it took keeps its mark until you pick it, but focus events alone
-- wouldn't clear a mark made while you were looking at it.
function M:poll_attention()
    for id, w in pairs(self.windows) do
        if w.ws then
            -- Kept for matching the window after a restart.
            w.title = self.a.title(id) or w.title
        end
    end
    local f = self.a.focused()
    local w = f and self.windows[f]
    if w and not (self.last_steal and self.last_steal.id == f) then
        self.attention:focused(f, w.app, self.tab_hosts[f])
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

-- Super+V: the picker, on tab `tab`: what you've copied, and characters by
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

-- tide's settings window, from the launcher and the dashboard (SPEC.md
-- §15).
function A.settings(self, section)
    if self.open_settings then
        self.open_settings(section)
    end
end

-- Super+Shift+Space: the dashboard, or closes it (SPEC.md §8).
function A.dashboard(self)
    if self.open_dashboard then
        self.open_dashboard()
    end
end

-- Ctrl+Up and Ctrl+Down: the overview, in place of Mission Control and
-- App Exposé, of every workspace ("all") or the current one ("current"),
-- or closes it (SPEC.md §6.9).
function A.overview(self, scope)
    if self.open_overview then
        self.open_overview(scope)
    end
end

function A.layout(self, mode)
    local ws = self:current_part()
    if ws then
        ws.prev_mode = nil
        ws.mode = mode
        self:retile()
    end
end

function M:act(name, arg)
    local f = A[name]
    if not f then
        error("tide: no action " .. tostring(name))
    end
    f(self, arg)
end

return M
