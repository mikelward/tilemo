-- The switcher on Hammerspoon: an hs.chooser over launcher.lua's ranking,
-- with tabs (SPEC.md §9). Apps come from the Applications folders and
-- System Settings' panes from its extensions (launcher.scan_apps and
-- scan_settings); the workspaces, windows and the windows wanting attention
-- from the window manager; browser tabs from Chrome, Brave and Safari through
-- AppleScript (Automation, asked for the first time), arriving after the
-- switcher opens; and commands from launcher.COMMANDS. Tab and Shift+Tab
-- move between its tabs. Not runnable outside Hammerspoon.

local launcher = require("tilemo.launcher")
local mute = require("tilemo.mute")
local saved = require("tilemo.saved")

local M = {}

M.RECENCY_KEY = "tilemo.launcher.recency"
-- Where timo kept it, before the rename.
M.OLD_RECENCY_KEY = "timo.launcher.recency"

-- A folder's entries as { name, dir }, or nil if it can't be read. `dir`
-- follows symlinks, as /Applications/Safari.app is one.
local function list_dir(dir)
    local ok, iter, obj = pcall(hs.fs.dir, dir)
    if not ok or not iter then
        return nil
    end
    local out = {}
    for name in iter, obj do
        if name ~= "." and name ~= ".." then
            out[#out + 1] = { name = name, dir = hs.fs.attributes(dir .. "/" .. name, "mode") == "directory" }
        end
    end
    return out
end

-- System Settings' panes change only with macOS, so they're read once.
local panes

-- What the launcher lists from disk: the apps, read afresh each time, and
-- System Settings' panes.
function M.scan()
    if not panes then
        panes = launcher.scan_settings(list_dir, function(path)
            local ok, t = pcall(hs.plist.read, path)
            return ok and t or nil
        end)
        if #panes == 0 then
            print("tilemo: found no System Settings panes in " .. launcher.SETTINGS_DIR)
        end
    end
    return launcher.scan_apps(list_dir, os.getenv("HOME") or ""), panes
end

local SETTINGS_BUNDLE = "com.apple.systempreferences"

-- A browser that isn't running isn't asked for its tabs, since an Apple
-- Event would launch it; one that Automation hasn't been granted for gives
-- none.

-- How long a browser has to list its tabs before it's skipped this time
-- (SPEC.md §9): a busy browser can hold an Apple Event for a long time.
M.TAB_TIMEOUT = 2

-- Ask each running browser for its tabs, without waiting: `done(tabs)` is
-- called once per browser that answers in time, with each tab's tilemo
-- window and workspace where its window's name finds them. osascript runs
-- as a task, so the switcher shows at once and a stuck browser holds up
-- nothing.
local running_tasks = {}
local function fetch_tabs(tilemo, done)
    for _, b in ipairs(launcher.BROWSERS) do
        local browser, script = b.name, launcher.tab_script(b)
        if hs.application.get(b.bundle) then
            local task, timer
            task = hs.task.new("/usr/bin/osascript", function(code, out, err)
                running_tasks[task] = nil
                if timer then
                    timer:stop()
                end
                if code ~= 0 then
                    -- Automation refused, or the browser quit: no tabs from it.
                    tilemo.adapter.log("tabs from " .. browser .. ": " .. tostring(err))
                    return
                end
                local list = launcher.parse_tabs(browser, out)
                local windows = {}
                for id, w in pairs(tilemo.wm.windows) do
                    if w.ws then
                        windows[#windows + 1] = { id = id, app = w.app, title = tilemo.adapter.title(id) or w.title, ws = w.ws }
                    end
                end
                for _, t in ipairs(list) do
                    local w = launcher.tab_window(t, b.bundle, windows)
                    if w then
                        t.win, t.ws = w.id, w.ws
                    end
                end
                done(list)
            end, { "-e", script })
            if task and task:start() then
                running_tasks[task] = true
                timer = hs.timer.doAfter(M.TAB_TIMEOUT, function()
                    if running_tasks[task] then
                        tilemo.adapter.log("tabs from " .. browser .. ": no answer in " .. M.TAB_TIMEOUT .. " s")
                        running_tasks[task] = nil
                        task:terminate()
                    end
                end)
            else
                tilemo.adapter.log("tabs from " .. browser .. ": couldn't run osascript")
            end
        end
    end
end

-- Every window on every workspace, most recently used first, for the
-- Windows tab.
local function windows(tilemo)
    local wm = tilemo.wm
    local out, seen = {}, {}
    local function add(id)
        local w = wm.windows[id]
        if w and w.ws and not seen[id] then
            seen[id] = true
            out[#out + 1] = {
                id = id,
                title = tilemo.adapter.title(id) or w.title,
                app_name = w.name or (w.app and hs.application.nameForBundleID(w.app)) or w.app,
                bundle = w.app,
                ws = w.ws,
                -- Only one you minimized: tilemo's own hide the other
                -- workspaces (SPEC.md §6.7).
                minimized = w.mine or false,
            }
        end
    end
    for _, id in ipairs(wm.history) do
        add(id)
    end
    local rest = {}
    for id in pairs(wm.windows) do
        if not seen[id] then
            rest[#rest + 1] = id
        end
    end
    table.sort(rest, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, id in ipairs(rest) do
        add(id)
    end
    return out
end

-- The tab's window may be minimized, on a workspace tilemo has hidden, so it's
-- restored too: tilemo sees a window you restored and brings its workspace
-- along with it. Where tilemo knows the window, it goes there first.

local function open_tab(tilemo, item)
    local b = launcher.browser(item.browser)
    if not b then
        tilemo.adapter.notify("Couldn't open that tab: tilemo doesn't know " .. tostring(item.browser))
        return
    end
    if item.win and tilemo.wm.windows[item.win] then
        tilemo.wm:activate(item.win)
    end
    -- The browser activating is the launch you made (SPEC.md §14.1).
    tilemo.wm:grant(b.bundle)
    local ok, _, err = hs.osascript.applescript(launcher.open_tab_script(b, item))
    if not ok then
        tilemo.adapter.notify("Couldn't open that " .. item.browser .. " tab: " .. hs.inspect(err))
    end
end

-- The windows wanting attention, newest first, as launcher.items takes them.
local function attention(tilemo)
    local out = {}
    for _, id in ipairs(tilemo.wm:attention_windows()) do
        local w = tilemo.wm.windows[id]
        out[#out + 1] = {
            window = id,
            title = tilemo.adapter.title(id) or w.title,
            app = w.app and hs.application.nameForBundleID(w.app) or w.app,
            bundle = w.app,
            ws = w.ws,
        }
    end
    return out
end

-- Every workspace, in bar order, for the Workspaces tab: its apps' names
-- (to search by too) and where it's showing (SPEC.md §9).
local function workspaces(tilemo)
    local out = {}
    local names = {}
    local function app_name(bundle)
        if names[bundle] == nil then
            names[bundle] = hs.application.nameForBundleID(bundle) or bundle
        end
        return names[bundle]
    end
    for _, s in ipairs(tilemo.wm:bar_state()) do
        local apps, seen = {}, {}
        for _, w in pairs(tilemo.wm.windows) do
            if w.ws == s.name and w.app and not seen[w.app] then
                seen[w.app] = true
                apps[#apps + 1] = app_name(w.app)
            end
        end
        table.sort(apps)
        out[#out + 1] = {
            name = s.name,
            apps = table.concat(apps, ", "),
            where = s.here and "here" or s.elsewhere and "on another display" or (#apps == 0 and "empty" or nil),
        }
    end
    return out
end

local QUICK = {}

-- macOS's own screenshot keys, as the Print keys use (SPEC.md §10).
function QUICK.screenshot_window(tilemo)
    tilemo.wm:act("screenshot", "window")
end
function QUICK.screenshot_screen(tilemo)
    tilemo.wm:act("screenshot", "screen")
end
function QUICK.screenshot_region(tilemo)
    tilemo.wm:act("screenshot", "region")
end
function QUICK.sleep()
    hs.caffeinate.systemSleep()
end
function QUICK.restart()
    hs.osascript.applescript('tell application "System Events" to restart')
end
function QUICK.shutdown()
    hs.osascript.applescript('tell application "System Events" to shut down')
end
function QUICK.dark()
    hs.osascript.applescript(
        'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode')
end
-- Keep awake, presenter mode and Do Not Disturb go through presenter_hs,
-- so each ends presenter mode as Super+S does (SPEC.md §10). macOS has no
-- public switch for Focus, so Do Not Disturb runs a shortcut, and says what
-- to make when it isn't there.
function QUICK.keep_awake(tilemo)
    tilemo.presenter.toggle_keep_awake()
end
function QUICK.presenter(tilemo)
    tilemo.presenter.toggle_presenter()
end
function QUICK.dnd(tilemo)
    tilemo.presenter.toggle_dnd()
end
-- tilemo doctor's findings, in a notification (SPEC.md §15).
function QUICK.doctor(tilemo)
    tilemo.adapter.notify(tilemo.doctor())
end
function QUICK.reload()
    hs.reload()
end

-- Mute or unmute the selected row, while the switcher's open: physical
-- Ctrl+M under setup-macos's rotation, as tide's Ctrl+M (SPEC.md §14.2).
-- It's bound only while the chooser is open (open_keys), never globally:
-- there it's taken before macOS's Cmd+M minimize can reach the chooser,
-- and everywhere else Cmd+M is left as it was.
M.MUTE_KEY = { mods = { "cmd" }, key = "m" }

-- `tilemo` is the started tilemo module: its wm and adapter.
function M.new(tilemo)
    local self = { tilemo = tilemo, recency = saved.get(hs.settings, M.RECENCY_KEY, M.OLD_RECENCY_KEY) or {} }
    local items = {}
    local before
    local chooser
    local scope = launcher.SCOPE_ORDER[1]

    local function choices(query)
        local found = launcher.rank(query or "", items, { recency = self.recency, scope = scope })
        local out = {}
        for _, item in ipairs(found) do
            out[#out + 1] = {
                text = item.title,
                subText = launcher.subtitle(item),
                id = item.id,
            }
        end
        -- An empty scope says so, in a row that can't be chosen.
        if #out == 0 and (query or ""):match("^%s*$") then
            out[1] = { text = launcher.SCOPE_EMPTY[scope], valid = false }
        end
        return out
    end

    local by_id = {}
    -- Set once the switcher is open: rebuild its rows, and mute a row.
    local refill, toggle_mute

    local function run(item, fresh)
        self.recency[item.key] = os.time()
        hs.settings.set(M.RECENCY_KEY, self.recency)
        if item.kind == "app" then
            -- By bundle ID where it has one, so an app already open comes
            -- forward with its workspace, as its app key would.
            local info = hs.application.infoForBundlePath(item.path)
            local bundle = info and info.CFBundleIdentifier
            -- One of "in"'s apps launches from "in" without asking for a
            -- workspace (SPEC.md §6.2).
            local home_app = tilemo.wm.home_apps[item.title] or false
            if bundle then
                tilemo.wm.actions.app(tilemo.wm, { bundle = bundle, name = item.title, home_app = home_app }, fresh)
            else
                tilemo.wm:before_launch({ fresh = fresh, home_app = home_app, default = item.title }, function(env)
                    -- No bundle ID to say which app's window is the launch's.
                    tilemo.wm:grant(nil)
                    tilemo.adapter.open_app(item.path, env)
                end)
            end
        elseif item.kind == "setting" then
            -- System Settings, at the pane; its window may take focus.
            tilemo.wm:grant(SETTINGS_BUNDLE)
            tilemo.adapter.open_url(item.url)
        elseif item.kind == "tab" then
            open_tab(tilemo, item)
        elseif item.kind == "window" then
            -- With its workspace, as an app key brings it.
            tilemo.wm:activate(item.window)
        elseif item.kind == "workspace" then
            -- Made, if it's a standing workspace not made yet.
            tilemo.wm:show(item.title)
        elseif item.kind == "attention" then
            -- As Super+Tab goes there: with its workspace.
            tilemo.wm:activate(item.window)
        elseif item.quick then
            if item.quick == "toggle_ffm" then
                tilemo.toggle_focus_follows_mouse()
            elseif QUICK[item.quick] then
                QUICK[item.quick](tilemo)
            end
        elseif item.action then
            tilemo.wm:act(item.action, item.arg)
        end
    end

    -- Cmd+Return, and only that: the chooser's own Cmd+1…9 picks a row with
    -- Command held too, so the modifiers alone can't tell them apart.
    local fresh = false
    -- Keys taken only while the launcher is open, and given back when it
    -- closes: Cmd+Return, Tab, Shift+Tab and Cmd+M (M.MUTE_KEY).
    local open_keys = {}

    local function set_scope(s)
        scope = s
        chooser:placeholderText(launcher.placeholder(scope))
        chooser:choices(choices(chooser:query()))
    end
    -- As Tab and Shift+Tab move, for CI's smoke test.
    self.set_scope = set_scope

    chooser = hs.chooser.new(function(choice)
        tilemo.wm:hold("launcher", false)
        for _, k in ipairs(open_keys) do
            k:delete()
        end
        open_keys = {}
        if not choice then
            -- Dismissed: back to the window you were in.
            if before then
                tilemo.wm:focus_window(before)
            end
            return
        end
        local item = by_id[choice.id]
        if item then
            -- Cmd+Return asks for a workspace and runs it there.
            run(item, fresh)
        end
    end)
    chooser:queryChangedCallback(function(query)
        chooser:choices(choices(query))
    end)

    -- Cmd+M or a right-click on a row in the Windows or Attention tab
    -- mutes or unmutes its app or site (SPEC.md §14.2), and the rows show
    -- it at once: a muted Attention row goes.
    toggle_mute = function(item)
        if not item or not mute.entry_for(item) then
            hs.alert.show("Only a window, a tab or an Attention row can be muted")
            return
        end
        local name = item.kind == "tab" and (item.extra or item.url) or item.app or item.bundle
        if tilemo.toggle_mute(mute.entry_for(item), name) ~= nil and refill then
            refill()
        end
    end
    chooser:rightClickCallback(function(index)
        toggle_mute(by_id[(chooser:selectedRowContents(index) or {}).id])
    end)

    -- Open on tab `tab` (Launch if none). A switcher key pressed while
    -- it's open closes it if it's on that key's tab, and otherwise moves to
    -- that tab (SPEC.md §9).
    function self.show(tab)
        tab = launcher.SCOPES[tab or ""] and tab or launcher.SCOPE_ORDER[1]
        if chooser:isVisible() then
            if tab == scope then
                chooser:cancel()
            else
                set_scope(tab)
            end
            return
        end
        before = tilemo.adapter.focused()
        local apps, settings = M.scan()
        local wins = windows(tilemo)
        local found_tabs = {}
        local function fill()
            items = launcher.items(apps, found_tabs, launcher.COMMANDS, settings, attention(tilemo), workspaces(tilemo), wins)
            mute.mark_rows(items, tilemo.wm.muted)
            by_id = {}
            for _, item in ipairs(items) do
                by_id[item.id] = item
            end
        end
        fill()
        refill = function()
            fill()
            chooser:choices(choices(chooser:query()))
        end
        -- The windows show at once; each browser's tabs join them when it
        -- answers, while the switcher's still open.
        local opened = {}
        self.opened = opened
        fetch_tabs(tilemo, function(list)
            if self.opened ~= opened or not chooser:isVisible() then
                return
            end
            for _, t in ipairs(list) do
                found_tabs[#found_tabs + 1] = t
            end
            -- Each browser window's front tab, for muted sites (SPEC.md
            -- §14.2).
            tilemo.wm:note_tabs(list)
            fill()
            chooser:choices(choices(chooser:query()))
        end)
        tilemo.wm:hold("launcher", true)
        fresh = false
        open_keys = {
            hs.hotkey.bind({ "cmd" }, "return", function()
                -- With no row to pick, or only an empty scope's, select()
                -- leaves the launcher open, and the next plain Return
                -- mustn't count as fresh.
                local row = chooser:selectedRowContents()
                if row and row.id then
                    fresh = true
                    chooser:select()
                end
            end),
            hs.hotkey.bind({}, "tab", function()
                set_scope(launcher.next_scope(scope))
            end),
            hs.hotkey.bind({ "shift" }, "tab", function()
                set_scope(launcher.next_scope(scope, true))
            end),
            -- Mute or unmute the row's app or site (SPEC.md §14.2).
            hs.hotkey.bind(M.MUTE_KEY.mods, M.MUTE_KEY.key, function()
                local row = chooser:selectedRowContents()
                toggle_mute(row and by_id[row.id])
            end),
        }
        chooser:query("")
        set_scope(tab)
        chooser:show()
    end

    -- The row the launcher shows `n`th, and closing it as Esc does: for
    -- CI's smoke test.
    function self.row(n)
        return chooser:selectedRowContents(n)
    end

    function self.cancel()
        chooser:cancel()
    end

    return self
end

return M
