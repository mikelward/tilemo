-- The launcher on Hammerspoon: an hs.chooser over launcher.lua's ranking
-- (SPEC.md §9). Apps come from the Applications folders and System
-- Settings' panes from its extensions (launcher.scan_apps and
-- scan_settings), tabs from Chrome and Safari through AppleScript
-- (Automation, asked for the first time), the windows wanting attention
-- from the window manager, and commands from launcher.COMMANDS. Tab and
-- Shift+Tab move between its scopes. Not runnable outside Hammerspoon.

local launcher = require("tilemo.launcher")
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

-- Each browser's tabs, as { title, url, browser, window, tab }. A browser
-- that isn't running, or that Automation hasn't been granted for, gives
-- none.
local TAB_SCRIPTS = {
    ["Google Chrome"] = [[
        set out to ""
        tell application "Google Chrome"
            repeat with w from 1 to count windows
                repeat with t from 1 to count tabs of window w
                    set out to out & w & tab & t & tab & (URL of tab t of window w) & tab & (title of tab t of window w) & linefeed
                end repeat
            end repeat
        end tell
        return out]],
    Safari = [[
        set out to ""
        tell application "Safari"
            repeat with w from 1 to count windows
                repeat with t from 1 to count tabs of window w
                    set out to out & w & tab & t & tab & (URL of tab t of window w) & tab & (name of tab t of window w) & linefeed
                end repeat
            end repeat
        end tell
        return out]],
}

local function tabs()
    local out = {}
    for browser, script in pairs(TAB_SCRIPTS) do
        if hs.application.get(browser) then
            local ok, text = hs.osascript.applescript(script)
            if ok and type(text) == "string" then
                for line in text:gmatch("[^\n]+") do
                    local w, t, url, title = line:match("^(%d+)\t(%d+)\t([^\t]*)\t(.*)$")
                    if w then
                        out[#out + 1] = { browser = browser, window = tonumber(w), tab = tonumber(t), url = url, title = title }
                    end
                end
            end
        end
    end
    return out
end

-- The tab's window may be minimized, on a workspace tilemo has hidden, so it's
-- restored too: tilemo sees a window you restored and brings its workspace
-- along with it.
local BROWSER_BUNDLES = { ["Google Chrome"] = "com.google.Chrome", Safari = "com.apple.Safari" }

local function open_tab(tilemo, item)
    -- The browser activating is the launch you made (SPEC.md §14.1).
    tilemo.wm:grant(BROWSER_BUNDLES[item.browser])
    local set, restore
    if item.browser == "Safari" then
        set = ("set current tab of window %d to tab %d of window %d"):format(item.window, item.tab, item.window)
        restore = ("set miniaturized of window %d to false"):format(item.window)
    else
        set = ("set active tab index of window %d to %d"):format(item.window, item.tab)
        restore = ("set minimized of window %d to false"):format(item.window)
    end
    local ok, _, err = hs.osascript.applescript(([[
        tell application "%s"
            %s
            %s
            set index of window %d to 1
            activate
        end tell]]):format(item.browser, set, restore, item.window))
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
function QUICK.keep_awake()
    local on = not hs.caffeinate.get("displayIdle")
    hs.caffeinate.set("displayIdle", on, true)
    hs.alert.show(on and "Keeping awake" or "Not keeping awake")
end
function QUICK.dnd()
    -- macOS has no public switch for Focus; a Shortcuts shortcut named
    -- "Toggle Do Not Disturb" is the usual stand-in (unverified on macOS 26).
    hs.task.new("/usr/bin/shortcuts", nil, { "run", "Toggle Do Not Disturb" }):start()
end
function QUICK.reload()
    hs.reload()
end

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
    -- closes: Cmd+Return, Tab and Shift+Tab.
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
        items = launcher.items(apps, tabs(), launcher.COMMANDS, settings, attention(tilemo), workspaces(tilemo))
        by_id = {}
        for _, item in ipairs(items) do
            by_id[item.id] = item
        end
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
