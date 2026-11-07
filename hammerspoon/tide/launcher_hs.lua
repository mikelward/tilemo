-- The switcher on Hammerspoon: an hs.chooser over launcher.lua's ranking,
-- with tabs (SPEC.md §9). Apps come from the Applications folders and
-- System Settings' panes from its extensions (launcher.scan_apps and
-- scan_settings); the workspaces, windows and the windows wanting attention
-- from the window manager; browser tabs from Chrome, Brave and Safari through
-- AppleScript (Automation, asked for the first time), arriving after the
-- switcher opens; and commands from launcher.COMMANDS. Tab and Shift+Tab
-- move between its tabs. Not runnable outside Hammerspoon.

local brand = require("tide.brand")
local launcher = require("tide.launcher")
local mute = require("tide.mute")
local saved = require("tide.saved")

local M = {}

M.RECENCY_KEY = "tide.launcher.recency"
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
            print("tide: found no System Settings panes in " .. launcher.SETTINGS_DIR)
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
-- called once per browser that answers in time, with each tab's tide
-- window and workspace where its window's name finds them. osascript runs
-- as a task, so the switcher shows at once and a stuck browser holds up
-- nothing.
local running_tasks = {}
local function fetch_tabs(tide, done)
    for _, b in ipairs(launcher.BROWSERS) do
        local browser, script = b.name, launcher.tab_script(b)
        -- By bundle ID alone: hs.application.get falls back to walking
        -- every running app by name when it finds none, tens of
        -- milliseconds for each browser that isn't running.
        if #(hs.application.applicationsForBundleID(b.bundle) or {}) > 0 then
            local task, timer
            task = hs.task.new("/usr/bin/osascript", function(code, out, err)
                running_tasks[task] = nil
                if timer then
                    timer:stop()
                end
                if code ~= 0 then
                    -- Automation refused, or the browser quit: no tabs from it.
                    tide.adapter.log("tabs from " .. browser .. ": " .. tostring(err))
                    return
                end
                local list = launcher.parse_tabs(browser, out)
                local windows = {}
                for id, w in pairs(tide.wm.windows) do
                    if w.ws then
                        windows[#windows + 1] = { id = id, app = w.app, title = tide.adapter.title(id) or w.title, ws = w.ws }
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
                        tide.adapter.log("tabs from " .. browser .. ": no answer in " .. M.TAB_TIMEOUT .. " s")
                        running_tasks[task] = nil
                        task:terminate()
                    end
                end)
            else
                tide.adapter.log("tabs from " .. browser .. ": couldn't run osascript")
            end
        end
    end
end

-- Every window on every workspace, most recently used first, for the
-- Windows tab.
local function windows(tide)
    local wm = tide.wm
    local out, seen = {}, {}
    local function add(id)
        local w = wm.windows[id]
        if w and w.ws and not seen[id] then
            seen[id] = true
            out[#out + 1] = {
                id = id,
                title = tide.adapter.title(id) or w.title,
                app_name = w.name or (w.app and hs.application.nameForBundleID(w.app)) or w.app,
                bundle = w.app,
                ws = w.ws,
                -- Only one you minimized: tide's own hide the other
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

-- The tab's window may be minimized, on a workspace tide has hidden, so it's
-- restored too: tide sees a window you restored and brings its workspace
-- along with it. Where tide knows the window, it goes there first.

local function open_tab(tide, item)
    local b = launcher.browser(item.browser)
    if not b then
        tide.adapter.notify("Couldn't open that tab: tide doesn't know " .. tostring(item.browser))
        return
    end
    if item.win and tide.wm.windows[item.win] then
        tide.wm:activate(item.win)
    end
    -- The browser activating is the launch you made (SPEC.md §14.1).
    tide.wm:grant(b.bundle)
    local ok, _, err = hs.osascript.applescript(launcher.open_tab_script(b, item))
    if not ok then
        tide.adapter.notify("Couldn't open that " .. item.browser .. " tab: " .. hs.inspect(err))
    end
end

-- The windows wanting attention, newest first, as launcher.items takes them.
local function attention(tide)
    local out = {}
    for _, id in ipairs(tide.wm:attention_windows()) do
        local w = tide.wm.windows[id]
        out[#out + 1] = {
            window = id,
            title = tide.adapter.title(id) or w.title,
            app = w.app and hs.application.nameForBundleID(w.app) or w.app,
            bundle = w.app,
            ws = w.ws,
        }
    end
    return out
end

-- Every workspace, in bar order, for the Workspaces tab: its apps' names
-- (to search by too) and where it's showing (SPEC.md §9).
local function workspaces(tide)
    local out = {}
    local names = {}
    local function app_name(bundle)
        if names[bundle] == nil then
            names[bundle] = hs.application.nameForBundleID(bundle) or bundle
        end
        return names[bundle]
    end
    for _, s in ipairs(tide.wm:bar_state()) do
        local apps, seen = {}, {}
        for _, w in pairs(tide.wm.windows) do
            if w.ws == s.name and w.app and not seen[w.app] then
                seen[w.app] = true
                apps[#apps + 1] = app_name(w.app)
            end
        end
        table.sort(apps)
        out[#out + 1] = {
            name = s.name,
            apps = table.concat(apps, ", "),
            where = s.here and "here" or (#apps == 0 and "empty" or nil),
        }
    end
    return out
end

-- scripts' list of its app scripts (launcher.parse_scripts), read afresh
-- each time the switcher opens, so a pull shows at once. Without it the
-- switcher lists none, and the log says so once, until it can read it.
local scripts_unread
local function read_scripts(tide, dir)
    local path = dir .. launcher.SCRIPTS_FILE
    local f, err = io.open(path)
    if not f then
        if scripts_unread ~= tostring(err) then
            scripts_unread = tostring(err)
            tide.adapter.log("launcher: can't read " .. path .. ", so the switcher lists no app scripts: " .. tostring(err))
        end
        return {}
    end
    scripts_unread = nil
    local text = f:read("a")
    f:close()
    return launcher.parse_scripts(text)
end

-- What the switcher lists as it opens, read once: a function giving its
-- rows (launcher.items) with the browser tabs `tabs` found so far, muted
-- ones marked. Shared with the dashboard launcher (launcherpage_hs.lua).
function M.collector(tide)
    local apps, settings = M.scan()
    local wins = windows(tide)
    -- The app scripts in ~/scripts, as runenv finds them, by scripts' own
    -- list of them.
    local dir = (os.getenv("HOME") or "") .. "/scripts/"
    local commands = launcher.with_scripts(launcher.COMMANDS, read_scripts(tide, dir), function(run)
        return hs.fs.attributes(dir .. run, "mode") == "file"
    end)
    return function(tabs)
        local items = launcher.items(apps, tabs, commands, settings, attention(tide), workspaces(tide), wins)
        mute.mark_rows(items, tide.wm.muted)
        return items
    end
end

M.fetch_tabs = fetch_tabs

local QUICK = {}

-- macOS's own screenshot keys, as the Print keys use (SPEC.md §10).
function QUICK.screenshot_window(tide)
    tide.wm:act("screenshot", "window")
end
function QUICK.screenshot_screen(tide)
    tide.wm:act("screenshot", "screen")
end
function QUICK.screenshot_region(tide)
    tide.wm:act("screenshot", "region")
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
function QUICK.keep_awake(tide)
    tide.presenter.toggle_keep_awake()
end
function QUICK.presenter(tide)
    tide.presenter.toggle_presenter()
end
function QUICK.dnd(tide)
    tide.presenter.toggle_dnd()
end
-- tide doctor's findings, in a notification (SPEC.md §15).
function QUICK.doctor(tide)
    tide.adapter.notify(tide.doctor())
end
function QUICK.reload()
    hs.reload()
end

-- Run the switcher's row `item`, remembering its use in `recency` (a
-- table kept in hs.settings): `fresh` is Cmd+Return's new workspace. Shared
-- by the chooser and the dashboard launcher (launcherpage_hs.lua).
function M.run(tide, recency, item, fresh)
    recency[item.key] = os.time()
    hs.settings.set(M.RECENCY_KEY, recency)
    if item.kind == "app" and not item.path and item.action == "app" then
        -- An app script (launcher.with_scripts): as its app key runs it,
        -- with Cmd+Return's new workspace. One of home's apps by name
        -- (Gmail) launches from home, as an app on disk does, key or none.
        local spec = {}
        for k, v in pairs(item.arg) do
            spec[k] = v
        end
        spec.home_app = spec.home_app or tide.wm:home_app_named(item.title)
        tide.wm.actions.app(tide.wm, spec, fresh)
    elseif item.kind == "app" and not item.path then
        -- One of tide's own, as Tide Settings is: a window manager
        -- action.
        tide.wm:act(item.action, item.arg)
    elseif item.kind == "app" then
        -- By bundle ID where it has one, so an app already open comes
        -- forward with its workspace, as its app key would.
        local info = hs.application.infoForBundlePath(item.path)
        local bundle = info and info.CFBundleIdentifier
        -- One of "in"'s apps launches from "in" without asking for a
        -- workspace (SPEC.md §6.2).
        local home_app = tide.wm:home_app_named(item.title)
        if bundle then
            tide.wm.actions.app(tide.wm, { bundle = bundle, name = item.title, home_app = home_app }, fresh)
        else
            tide.wm:before_launch({ fresh = fresh, home_app = home_app, default = item.title }, function(env)
                -- No bundle ID to say which app's window is the launch's.
                tide.wm:grant(nil)
                tide.adapter.open_app(item.path, env)
            end)
        end
    elseif item.kind == "setting" then
        -- System Settings, at the pane; its window may take focus.
        tide.wm:grant(SETTINGS_BUNDLE)
        tide.adapter.open_url(item.url)
    elseif item.kind == "tab" then
        open_tab(tide, item)
    elseif item.kind == "window" then
        -- With its workspace, as an app key brings it.
        tide.wm:activate(item.window)
    elseif item.kind == "workspace" then
        -- Made, if it's a standing workspace not made yet.
        tide.wm:show(item.title)
    elseif item.kind == "attention" then
        -- As Super+Tab goes there: with its workspace.
        tide.wm:activate(item.window)
    elseif item.quick then
        if item.quick == "toggle_ffm" then
            tide.toggle_focus_follows_mouse()
        elseif QUICK[item.quick] then
            QUICK[item.quick](tide)
        end
    elseif item.action then
        tide.wm:act(item.action, item.arg)
    end
end

-- Mute or unmute the selected row, while the switcher's open: physical
-- Ctrl+M under setup-macos's rotation, as tide's Ctrl+M (SPEC.md §14.2).
-- It's bound only while the chooser is open (open_keys), never globally:
-- there it's taken before macOS's Cmd+M minimize can reach the chooser,
-- and everywhere else Cmd+M is left as it was.
M.MUTE_KEY = { mods = { "cmd" }, key = "m" }

-- `tide` is the started tide module: its wm and adapter.
function M.new(tide)
    local self = { tide = tide, recency = saved.get(hs.settings, M.RECENCY_KEY, M.OLD_RECENCY_KEY) or {} }
    local items = {}
    local before
    local scope = launcher.SCOPE_ORDER[1]

    -- Icons, read once each and kept: the rows are rebuilt on every
    -- keystroke. A missing one is left out (false), never waited on.
    local icons = {}
    local function icon(spec)
        local key = launcher.icon_key(spec)
        if not key then
            return nil
        end
        if icons[key] == nil then
            local ok, img
            if spec.logo then
                ok, img = true, tide.adapter.logo(brand.LOGO)
            elseif spec.bundle then
                ok, img = pcall(hs.image.imageFromAppBundle, spec.bundle)
            elseif spec.path then
                ok, img = pcall(hs.image.iconForFile, spec.path)
            else
                ok, img = pcall(hs.image.imageFromName, spec.name)
            end
            if not ok then
                tide.adapter.log("launcher: couldn't read the icon " .. key .. ": " .. tostring(img))
            end
            icons[key] = ok and img or false
        end
        return icons[key] or nil
    end

    -- tide's colors, for the system's appearance as the switcher opens.
    local look = launcher.look(true)
    local function font(size, bold)
        return { name = bold and ".AppleSystemUIFontBold" or ".AppleSystemUIFont", size = size }
    end
    -- The title, with the query's matched characters bold and in the accent.
    local function title(query, text)
        local out
        for _, run in ipairs(launcher.marks(query, text)) do
            local styled = hs.styledtext.new(run.text, {
                font = font(launcher.FONT.title, run.matched),
                color = run.matched and look.accent or look.fg,
            })
            out = out and out .. styled or styled
        end
        return out
    end
    -- The line under it, then the key that does the same, dimmer.
    local function subtitle(item)
        local sub = hs.styledtext.new(launcher.subtitle(item), { font = font(launcher.FONT.sub), color = look.sub })
        local hint = launcher.key_hint(item)
        if hint then
            sub = sub .. hs.styledtext.new("   " .. hint, { font = font(launcher.FONT.sub), color = look.hint })
        end
        return sub
    end

    local function choices(query)
        local rows = launcher.rows(scope, query, items, self.recency)
        local out = {}
        for _, row in ipairs(rows) do
            local item = row.item
            if item then
                out[#out + 1] = {
                    text = title(query, item.title),
                    subText = subtitle(item),
                    -- Plain, for CI's smoke test.
                    title = item.title,
                    id = item.id,
                    image = icon(launcher.icon(item)),
                }
            else
                -- A section's header, which can't be chosen.
                out[#out + 1] = {
                    text = hs.styledtext.new(row.header:upper(), {
                        font = font(launcher.FONT.header, true),
                        color = look.header,
                    }),
                    valid = false,
                }
            end
        end
        -- An empty scope says so, in a row that can't be chosen.
        if #out == 0 and (query or ""):match("^%s*$") then
            out[1] = { text = launcher.SCOPE_EMPTY[scope], valid = false }
        end
        return out, launcher.first_row(rows)
    end

    local chooser
    -- Show the rows for `query`, with the first real one selected, past
    -- any header. Rows already shown for the same query, scope, items and
    -- look aren't made again: showing the chooser hands its query to the
    -- query callback (HSChooser.m's showWithHints), which made every row a
    -- second time on each open.
    local shown = {}
    local function show_rows(query)
        query = query or ""
        if shown.query == query and shown.scope == scope and shown.items == items and shown.look == look then
            return
        end
        local out, first = choices(query)
        chooser:choices(out)
        if first > 1 then
            chooser:selectedRow(first)
        end
        shown = { query = query, scope = scope, items = items, look = look }
    end

    local by_id = {}
    -- Set once the switcher is open: rebuild its rows, and mute a row.
    local refill, toggle_mute

    -- Cmd+Return, and only that: the chooser's own Cmd+1…9 picks a row with
    -- Command held too, so the modifiers alone can't tell them apart.
    local fresh = false
    -- Keys taken only while the launcher is open, and given back when it
    -- closes: Cmd+Return, Tab, Shift+Tab and Cmd+M (M.MUTE_KEY).
    local open_keys = {}

    local function set_scope(s)
        scope = s
        chooser:placeholderText(launcher.placeholder(scope))
        show_rows(chooser:query())
    end
    -- As Tab and Shift+Tab move, for CI's smoke test.
    self.set_scope = set_scope

    chooser = hs.chooser.new(function(choice)
        tide.wm:hold("launcher", false)
        for _, k in ipairs(open_keys) do
            k:delete()
        end
        open_keys = {}
        if not choice then
            -- Dismissed: back to the window you were in.
            if before then
                tide.wm:focus_unburied(before)
            end
            return
        end
        local item = by_id[choice.id]
        if item then
            -- Cmd+Return asks for a workspace and runs it there.
            M.run(tide, self.recency, item, fresh)
        end
    end)
    -- hs.chooser honors a row's `valid = false` only with an invalid
    -- callback; without one, Return on a header closes the switcher and
    -- runs the completion callback. With this no-op it stays open.
    chooser:invalidCallback(function() end)
    chooser:queryChangedCallback(function(query)
        show_rows(query)
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
        if tide.toggle_mute(mute.entry_for(item), name) ~= nil and refill then
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
        -- How long each step takes, for CI's smoke test, as tileco's
        -- launcher keeps them.
        local steps, last = {}, hs.timer.secondsSinceEpoch()
        local function step(name)
            local now = hs.timer.secondsSinceEpoch()
            steps[#steps + 1] = { name = name, ms = math.floor((now - last) * 1000) }
            last = now
        end
        self.steps = steps
        before = tide.adapter.focused()
        step("focused")
        local collect = M.collector(tide)
        step("collect")
        local found_tabs = {}
        local function fill()
            items = collect(found_tabs)
            by_id = {}
            for _, item in ipairs(items) do
                by_id[item.id] = item
            end
        end
        fill()
        step("fill")
        refill = function()
            fill()
            show_rows(chooser:query())
        end
        -- The windows show at once; each browser's tabs join them when it
        -- answers, while the switcher's still open.
        local opened = {}
        self.opened = opened
        M.fetch_tabs(tide, function(list)
            if self.opened ~= opened or not chooser:isVisible() then
                return
            end
            for _, t in ipairs(list) do
                found_tabs[#found_tabs + 1] = t
            end
            -- Each browser window's front tab, for muted sites (SPEC.md
            -- §14.2).
            tide.wm:note_tabs(list)
            fill()
            show_rows(chooser:query())
        end)
        step("tabs")
        tide.wm:hold("launcher", true)
        step("hold")
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
        step("keys")
        -- tide's look, for the system's appearance now (SPEC.md §9).
        local dark = hs.host.interfaceStyle() == "Dark"
        look = launcher.look(dark)
        -- No chooser-wide fgColor or subTextColor: hs.chooser applies them
        -- over each row's styled text, which would undo a match's accent,
        -- a header's dimmer gray and the dimmer key hint.
        chooser:bgDark(dark)
        chooser:width(launcher.WIDTH)
        chooser:rows(launcher.ROWS)
        chooser:query("")
        step("look")
        set_scope(tab)
        step("rows")
        chooser:show()
        step("show")
    end

    -- The bar's logo (SPEC.md §8): closes the switcher on any tab, as a
    -- tap on tide's does, or opens it on Launch.
    function self.toggle()
        if chooser:isVisible() then
            chooser:cancel()
        else
            self.show("launch")
        end
    end

    -- Whether it's open, and on which tab: for CI's smoke test.
    function self.is_open()
        return chooser:isVisible()
    end
    function self.scope()
        return scope
    end

    -- The row the launcher shows `n`th, and closing it as Esc does: for
    -- CI's smoke test.
    function self.row(n)
        return chooser:selectedRowContents(n)
    end

    function self.cancel()
        chooser:cancel()
    end

    -- Done with, as the settings window switches launchers: its chooser
    -- goes, closed first if it's open. A browser's tabs that answer
    -- later are dropped before they touch the deleted chooser.
    function self.delete()
        self.opened = nil
        if chooser:isVisible() then
            chooser:cancel()
        end
        chooser:delete()
    end

    -- Choosing row `n` as Return does: for CI's smoke test, which checks
    -- that a header leaves the switcher open.
    function self.choose(n)
        chooser:select(n)
    end

    return self
end

return M
