-- tide's settings window on Hammerspoon (SPEC.md §15): a section for each
-- of tide's pages, dashboard.lua's settings page in an hs.webview. It writes
-- tide's clocks.local.json, layouts.local.json, workspaces.local.json,
-- startup.local.json, clipboard.local.json and input.local.json, and tide hands the files back once they change on
-- disk, so the page shows what the bar and the next login do. What tide
-- can't change itself, a section's buttons open (links.lua). Not runnable
-- outside Hammerspoon.

local brand = require("tide.brand")
local dashboard = require("tide.dashboard")
local layout = require("tide.layout")
local mute = require("tide.mute")
local standing = require("tide.standing")
local picker = require("tide.picker")
local floating = require("tide.floating")
local links = require("tide.links")
local launcher = require("tide.launcher")
local launcherpage = require("tide.launcherpage")
local linearmouse = require("tide.linearmouse")
local checklist = require("tide.checklist")
local sound_hs = require("tide.sound_hs")
local displays_hs = require("tide.displays_hs")
local bluetooth_hs = require("tide.bluetooth_hs")
local netpower_hs = require("tide.netpower_hs")
local inputsrc = require("tide.inputsrc")

local M = {}

-- Where the Appearance page's Menu bar switch is kept: true (or unset) keeps
-- the hidden menu bar from sliding over tide's bar (bar_hs.lua).
M.MENU_BAR_KEY = "tide.keep_menu_bar_hidden"

-- `list` as a JSON array, each item by `encode`, so an empty one is [].
function M.list(list, encode)
    local out = {}
    for i, v in ipairs(list or {}) do
        out[i] = encode(v)
    end
    return "[" .. table.concat(out, ",") .. "]"
end

-- A Floating fill-in (floating.prefill) as JSON, its `about` rows a list.
function M.encode_fill(fill)
    local about = fill.about
    local copy = {}
    for k, v in pairs(fill) do
        copy[k] = v
    end
    copy.about = "__about__"
    return (hs.json.encode(copy):gsub('"__about__"', function()
        return M.list(about, hs.json.encode)
    end))
end

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the settings page's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing or unreadable file is an error then.
local function build()
    local sources = {}
    for _, name in ipairs(dashboard.SETTINGS_MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("settings.html"), read("launcher.css"), sources, dashboard.SETTINGS_MODULES)
end

-- What the Mouse section says is wrong, "" when nothing is: LinearMouse
-- missing or stopped, and what stops tide setting its scrolling.
function M.mouse_problem(tide)
    local out = {}
    local say = linearmouse.say(tide.linearmouse, "section")
    if say then
        out[#out + 1] = say
    end
    local applied = tide.linearmouse_settings and tide.linearmouse_settings.state.problem or ""
    if applied ~= "" then
        out[#out + 1] = applied
    end
    return table.concat(out, " ")
end

-- The Setup checklist (checklist.page) as JSON, for update()'s `setup` and
-- tide.setup(): the permissions as macOS says now, and this Mac's ticks.
function M.encode_setup(tide)
    local facts = { karabiner = tide.karabiner and true or false }
    -- An adapter without the call (a test's) can't tell.
    if tide.adapter.accessibility then
        facts.accessibility = tide.adapter.accessibility()
    end
    facts.location = M.location_status(tide.adapter.log)
    local page = checklist.page(facts, hs.settings.get(checklist.SETTINGS_KEY))
    return '{"permissions":' .. M.list(page.permissions, hs.json.encode)
        .. ',"items":' .. M.list(page.items, hs.json.encode)
        .. ',"left":' .. math.tointeger(page.left) .. "}"
end

-- One of the Floating section's messages, { floatAdd = { app, title } },
-- { floatMove = { index, app, title, step } } or { floatRemove = { index,
-- app, title } }, through `floats` (floating_hs.new). Returns true, or nil
-- and why.
function M.float_edit(floats, body)
    if not floats then
        return nil, "the float rules aren't loaded"
    end
    local str = function(v)
        return type(v) == "string" and v or ""
    end
    local int = function(v)
        return math.tointeger(v) or 0
    end
    if body.floatAdd then
        local m = body.floatAdd
        return floats.edit(function(list)
            return floating.with(list, str(m.app), str(m.title))
        end)
    elseif body.floatMove then
        local m = body.floatMove
        return floats.edit(function(list)
            return floating.moved(list, int(m.index), str(m.app), str(m.title), int(m.step) < 0 and -1 or 1)
        end)
    end
    local m = body.floatRemove
    return floats.edit(function(list)
        return floating.without(list, int(m.index), str(m.app), str(m.title))
    end)
end

-- Location Services for Hammerspoon, as hs.location.authorizationStatus()
-- says, or nil, logged, if it can't be read.
function M.location_status(log)
    local ok, status = pcall(function()
        return hs.location.authorizationStatus()
    end)
    if ok then
        return status
    end
    log("settings: couldn't read Location Services: " .. tostring(status))
    return nil
end

-- Has macOS ask for Location Services: it asks as Hammerspoon first
-- looks for where it is, and adds it to Privacy & Security's list. Looking
-- stops a minute later, answered or not, as only the asking was wanted.
local function ask_location(tide)
    local ok, err = pcall(hs.location.start)
    if not ok then
        tide.adapter.log("settings: couldn't ask for Location Services: " .. tostring(err))
        return
    end
    tide.adapter.after(60, function()
        local stopped, why = pcall(hs.location.stop)
        if not stopped then
            tide.adapter.log("settings: couldn't stop looking for where the Mac is: " .. tostring(why))
        end
    end)
end

-- The Switcher row's choice, `value`: tide switches at once. Returns
-- true, or nil and why, which the log keeps with what was asked.
function M.switch_launcher(tide, value)
    local ok, why
    if tide.set_launcher then
        ok, why = tide.set_launcher(value)
    else
        why = "this tide can't switch launchers"
    end
    if ok then
        return true
    end
    why = tostring(why)
    tide.adapter.log("settings: couldn't switch the launcher to " .. tostring(value) .. ": " .. why)
    return nil, why
end

-- The window's height, in points, on a display tall enough for it.
M.HEIGHT = 710

-- `tide` is the started tide module: its wm, adapter, shortcuts,
-- clock_dir, clock_files, layout_files, workspace_files, workspace_base,
-- startup_files, clipboard_files, input_files and picker.
function M.new(tide)
    local self = {}
    local page = build()
    local view
    -- The section to show once the page has loaded, or nil.
    local wanted

    -- The Sound page's devices (sound_hs.lua). A device that goes as it's
    -- read is logged, and the page shows none, rather than the rest of the
    -- window going undrawn.
    local sound = sound_hs.new(tide)
    local function sound_state()
        local ok, s = pcall(sound.state)
        if ok then
            return s
        end
        tide.adapter.log("settings: couldn't read the sound devices: " .. tostring(s))
        return {}
    end

    -- The Displays page's displays (displays_hs.lua), read the same way,
    -- and drawn again as one comes, goes or changes.
    local screens = displays_hs.new(tide, function()
        self.displays_changed()
    end)
    local function displays_state()
        local ok, s = pcall(screens.state)
        if ok then
            return s
        end
        tide.adapter.log("settings: couldn't read the displays: " .. tostring(s))
        return {}
    end

    -- The Bluetooth page's adapter and paired devices (bluetooth_hs.lua),
    -- read through blueutil while the window's open, and drawn again as
    -- what it says changes.
    local bt = bluetooth_hs.new(tide, function()
        self.bluetooth_changed()
    end)

    -- The Network and Power pages' Wi-Fi and battery (netpower_hs.lua),
    -- read the same way.
    local np = netpower_hs.new(tide, function()
        self.netpower_changed()
    end)
    local function netpower_state()
        local ok, s = pcall(np.state)
        if ok then
            return s
        end
        tide.adapter.log("settings: couldn't read Wi-Fi and the battery: " .. tostring(s))
        return {}
    end

    -- The Keyboard page's input sources (inputsrc.lua), from hs.keycodes.
    local function sources_state()
        local ok, s = pcall(function()
            return inputsrc.state(hs.keycodes.layouts(), hs.keycodes.methods(),
                hs.keycodes.currentMethod() or hs.keycodes.currentLayout())
        end)
        if ok then
            return s
        end
        tide.adapter.log("settings: couldn't read the input sources: " .. tostring(s))
        return { sources = {} }
    end

    local function push()
        if not view then
            return
        end
        -- An empty list must reach the page as one, not as an object.
        local json = hs.json.encode({
            -- The Sound page's devices, volumes and mutes.
            sound = sound_state(),
            -- The Displays page's displays.
            displays = displays_state(),
            -- The Network and Power pages'.
            netpower = netpower_state(),
            -- The Keyboard page's input sources.
            inputSources = sources_state(),
            -- The Bluetooth page's, as last read.
            bluetooth = bt.state(),
            -- Light or dark now, and until when, on tide's schedule.
            theme = tide.theme and tide.theme.state() or nil,
            clockFiles = tide.clock_files,
            startupFiles = tide.startup_files,
            layoutFiles = tide.layout_files,
            -- What the files lay over: start()'s layout, or tide's
            -- defaults, so the page shows and steps what's in effect.
            layoutBase = tide.layout_base and layout.file_form(tide.layout_base) or nil,
            clipboardFiles = tide.clipboard_files,
            -- tide's Appearance files, for the wallpapers, light and dark.
            appearanceFiles = tide.appearance_files,
            -- tide's idle files, for the Idle page's timings.
            idleFiles = tide.idle_files,
            -- tide's notifications files, for Do Not Disturb's schedule.
            notificationFiles = tide.notification_files,
            -- tide's workspaces files, and what they lay over: start()'s
            -- lists, or tide's defaults.
            workspaceFiles = tide.workspace_files,
            workspaceBase = tide.workspace_base and {
                standing = "__ws_standing__",
                inApps = "__ws_in_apps__",
                workspaceSettings = tide.workspace_base.workspaceSettings and "__ws_settings__" or nil,
            } or nil,
            clipboardCount = tide.picker and #tide.picker.history.items or 0,
            -- The settings in effect, which a file gone wrong since leaves
            -- as they were: the page shows these, not the defaults, then.
            clipboardSettings = tide.clipboard_settings and {
                history = tide.clipboard_settings.history,
                maxItems = tide.clipboard_settings.max_items,
                maxAgeDays = tide.clipboard_settings.max_age_days,
            } or nil,
            muted = "__muted__",
            -- The sidebar's groups and pages, as tide's settings panel has
            -- them.
            sidebar = launcher.settings_sidebar(),
            -- Each section's buttons, and what's wrong with LinearMouse, if
            -- anything, for the Mouse section.
            links = links.page_list(),
            inputFiles = tide.input_files,
            mouse = {
                problem = M.mouse_problem(tide),
                -- The Mac's own Speed and Acceleration, as LinearMouse
                -- has them for every mouse.
                pointer = tide.linearmouse_settings and tide.linearmouse_settings.state.pointer or nil,
            },
            -- conf's Karabiner rules, each on or off, and what's wrong, if
            -- anything (karabiner.lua).
            -- The launcher the switcher's keys open, and the choices.
            launcher = tide.launcher_choice and {
                value = tide.launcher_choice,
                choices = {
                    { value = "chooser", label = launcherpage.LABELS.chooser },
                    { value = "dashboard", label = launcherpage.LABELS.dashboard },
                },
            } or nil,
            -- The Appearance page's Menu bar switch (bar_hs.lua).
            menuBar = { hidden = tide.keep_menu_bar_hidden ~= false },
            keyboard = {
                rules = "__karabiner_rules__",
                problem = tide.karabiner_rules and tide.karabiner_rules.state.problem or "",
            },
            -- tide's key bindings as they registered, and the keys that
            -- didn't (keys.shortcuts), for the Keyboard section's Shortcuts.
            shortcuts = {
                binds = "__shortcut_binds__",
                failed = "__shortcut_failed__",
            },
            -- The Setup checklist: each permission's state, and the ticks.
            setup = "__setup__",
            floating = tide.floating and {
                rules = "__float_rules__",
                source = tide.floating.source,
                error = tide.floating.error,
                now = "__float_now__",
            } or nil,
        })
        json = json:gsub('"__muted__"', function()
            return mute.encode_list(tide.wm.muted.list)
        end)
        -- Lists that may be empty, which must reach the page as lists.
        json = json:gsub('"__float_rules__"', function()
            return M.list(tide.floating.rules, function(r)
                return hs.json.encode({ app = r.app, title = r.title or "" })
            end)
        end)
        json = json:gsub('"__ws_standing__"', function()
            return mute.encode_list(tide.workspace_base.standing)
        end)
        json = json:gsub('"__ws_in_apps__"', function()
            return mute.encode_list(tide.workspace_base.inApps)
        end)
        json = json:gsub('"__ws_settings__"', function()
            return standing.encode_settings(tide.workspace_base.workspaceSettings, mute.quote)
        end)
        json = json:gsub('"__karabiner_rules__"', function()
            return M.list(tide.karabiner_rules and tide.karabiner_rules.state.rules or {}, function(r)
                return hs.json.encode({ description = r.description, label = r.label, on = r.on == true })
            end)
        end)
        local shortcuts = tide.shortcuts or { binds = {}, failed = {} }
        json = json:gsub('"__shortcut_binds__"', function()
            return M.list(shortcuts.binds, hs.json.encode)
        end)
        json = json:gsub('"__shortcut_failed__"', function()
            return M.list(shortcuts.failed, hs.json.encode)
        end)
        json = json:gsub('"__setup__"', function()
            return M.encode_setup(tide)
        end)
        json = json:gsub('"__float_now__"', function()
            return M.list(tide.wm:floating_now(), M.encode_fill)
        end)
        view:evaluateJavaScript("tide.update(" .. json .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Scroll to section `id`, as settings.html names them: "clocks",
    -- "layouts", "workspaces", "startup", "clipboard", "muted", "floating",
    -- and the rest.
    local function reveal(id)
        if not (view and id) then
            return
        end
        view:evaluateJavaScript("tide.reveal(" .. hs.json.encode({ id }):sub(2, -2) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- A write from the page: `text` to `name` in tide's folder, said in a
    -- notice naming `what` if it fails.
    local function save(name, text, what)
        local path = tide.clock_dir .. "/" .. name
        local ok, err = tide.adapter.write_file(path, text)
        if not ok then
            tide.adapter.notify("Couldn't save " .. what .. " to " .. path .. ": " .. tostring(err))
            -- The page showed the change already: back to the files.
            push()
        end
        -- The folder's watcher reloads the files, and then this page.
    end

    -- The Sound page alone, as the bar sees a device, a volume or a mute
    -- change, so it follows the volume keys while it's open.
    function self.sound_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.sound(" .. hs.json.encode(sound_state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- The Displays page alone.
    function self.displays_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.displays(" .. hs.json.encode(displays_state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Appearance's light or dark alone, as it changes.
    function self.theme_changed()
        if not view or not tide.theme then
            return
        end
        view:evaluateJavaScript("tide.theme(" .. hs.json.encode(tide.theme.state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- The Keyboard page's input sources alone.
    function self.sources_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.inputSources(" .. hs.json.encode(sources_state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Switched anywhere, from the menu bar or a shortcut as well as the
    -- page, the Keyboard page follows.
    if tide.on_input_source then
        tide.on_input_source(self.sources_changed)
    end

    -- The Network and Power pages alone, as the bar sees them change.
    function self.netpower_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.netpower(" .. hs.json.encode(netpower_state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- The Bluetooth page alone.
    function self.bluetooth_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.bluetooth(" .. hs.json.encode(bt.state()) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- The checklist alone, so coming back to the window doesn't redraw the
    -- rest of it.
    local function setup_changed()
        if not view then
            return
        end
        view:evaluateJavaScript("tide.setup(" .. M.encode_setup(tide) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    local content = hs.webview.usercontent.new("tide")
    content:setCallback(function(msg)
        local body = msg.body or {}
        tide.adapter.after(0, function()
            if type(body.write) == "string" then
                save(dashboard.LOCAL_FILE, body.write, "the clocks")
            elseif type(body.writeLayouts) == "string" then
                save(dashboard.LAYOUTS_LOCAL_FILE, body.writeLayouts, "the layouts")
            elseif type(body.writeStartup) == "string" then
                save(dashboard.STARTUP_LOCAL_FILE, body.writeStartup, "Start at login's commands")
            elseif type(body.writeInput) == "string" then
                save(dashboard.INPUT_LOCAL_FILE, body.writeInput, "the Mouse settings")
            elseif type(body.writeWorkspaces) == "string" then
                save(dashboard.WORKSPACES_LOCAL_FILE, body.writeWorkspaces, "the workspaces")
            elseif type(body.writeClipboard) == "string" then
                save(dashboard.CLIPBOARD_LOCAL_FILE, body.writeClipboard, "the clipboard settings")
            elseif sound.handle(body) then
                -- The page shows what macOS says now, not what it asked.
                self.sound_changed()
            elseif screens.handle(body) then
                self.displays_changed()
            elseif inputsrc.handle(body, sources_state().sources, function(name, method)
                local ok = method and hs.keycodes.setMethod(name) or (not method and hs.keycodes.setLayout(name))
                if not ok then
                    tide.adapter.log("settings: macOS didn't switch to " .. name)
                end
            end) then
                self.sources_changed()
            elseif np.handle(body) then
                -- Drawn once it's had time to change.
            elseif bt.handle(body) then
                -- Drawn as blueutil answers.
            elseif body.themeFlip == true and tide.theme then
                -- Drawn as macOS's appearance changes.
                tide.theme.flip()
            elseif type(body.writeNotifications) == "string" then
                save(dashboard.NOTIFICATIONS_LOCAL_FILE, body.writeNotifications, "Do Not Disturb's schedule")
            elseif type(body.writeIdle) == "string" then
                save(dashboard.IDLE_LOCAL_FILE, body.writeIdle, "the idle timings")
            elseif type(body.writeAppearance) == "string" then
                save(dashboard.APPEARANCE_LOCAL_FILE, body.writeAppearance, "the wallpapers")
            elseif type(body.pickWallpaper) == "string" and tide.wallpaper then
                -- macOS's file dialog, over this window; the file chosen
                -- goes back to the page, which sets it as a typed one.
                local key = body.pickWallpaper
                local value = tide.wallpaper.pick(key)
                if value and view then
                    view:evaluateJavaScript("tide.setWallpaper(" .. hs.json.encode({ key, value }):sub(2, -2) .. ")")
                end
            elseif body.clearClipboard and tide.picker then
                picker.clear(tide.picker.history)
                tide.clipboard_cleared()
                push()
            elseif type(body.mute) == "string" then
                -- Typed at the Muted list's foot: as Cmd+M on a row, once
                -- the mute module takes it.
                local why = mute.add_problem(tide.wm.muted, body.mute)
                if why and view then
                    view:evaluateJavaScript("tide.mutedError(" .. hs.json.encode({ why, body.mute }):sub(2, -2) .. ")")
                elseif not why and tide.toggle_mute(body.mute) == nil then
                    push()
                end
            elseif type(body.unmute) == "string" then
                -- The same as Cmd+M on a muted row; it refreshes this page.
                if not mute.has(tide.wm.muted, body.unmute) or tide.toggle_mute(body.unmute) == nil then
                    push()
                end
            elseif type(body.floatAdd) == "table" or type(body.floatMove) == "table"
                or type(body.floatRemove) == "table" then
                -- The Floating section's edits, which tide makes, since the
                -- page can't check a Lua pattern (floating.lua).
                local ok, why = M.float_edit(tide.floating, body)
                if view then
                    if ok then
                        view:evaluateJavaScript("tide.floatingDone(" .. (body.floatAdd and "true" or "false") .. ")")
                    else
                        view:evaluateJavaScript("tide.floatingError(" .. hs.json.encode({ tostring(why) }):sub(2, -2) .. ")")
                    end
                end
            elseif type(body.mousePointer) == "table" and type(body.mousePointer.key) == "string" then
                -- The Mac's Speed and Acceleration rows: written straight to
                -- LinearMouse's config, which says why when it can't be.
                local ok, why
                if tide.linearmouse_settings then
                    ok, why = tide.linearmouse_settings.set_pointer(body.mousePointer.key, body.mousePointer.value)
                else
                    why = "the Mouse settings aren't running"
                end
                if not ok then
                    tide.adapter.log("settings: " .. tostring(why))
                    tide.adapter.notify(tostring(why))
                end
                push()
            elseif type(body.keepMenuBarHidden) == "boolean" then
                -- The Menu bar switch: kept in hs.settings, as tide's own,
                -- and followed at once by the bar.
                tide.keep_menu_bar_hidden = body.keepMenuBarHidden
                hs.settings.set(M.MENU_BAR_KEY, body.keepMenuBarHidden)
                push()
            elseif type(body.launcher) == "string" then
                -- The Switcher row: tide switches at once, and the page
                -- shows the one in use.
                local ok, why = M.switch_launcher(tide, body.launcher)
                if not ok then
                    tide.adapter.notify("Couldn't switch the launcher: " .. why)
                end
                push()
            elseif type(body.karabinerRule) == "table" and type(body.karabinerRule.description) == "string" then
                -- A Keyboard switch: tide edits karabiner.json, and the
                -- page shows the rules as they are after.
                local why
                if not tide.karabiner_rules then
                    why = "tide can't switch Karabiner's rules on this Mac"
                else
                    local ok, err = tide.karabiner_rules.set(body.karabinerRule.description, body.karabinerRule.on == true)
                    why = not ok and tostring(err) or nil
                end
                push()
                if why and view then
                    view:evaluateJavaScript("tide.keyboardError(" .. hs.json.encode({ why }):sub(2, -2) .. ")")
                end
            elseif type(body.setupTick) == "table" then
                -- A checklist item ticked or not: this Mac's own, kept in
                -- hs.settings, as tileco keeps its ticks in storage.local.
                local list, why = checklist.ticked(hs.settings.get(checklist.SETTINGS_KEY),
                    body.setupTick.id, body.setupTick.on == true)
                if list then
                    hs.settings.set(checklist.SETTINGS_KEY, list)
                else
                    tide.adapter.log("settings: " .. why)
                end
                setup_changed()
            elseif body.setupRefresh then
                -- Back in the window, perhaps from Privacy & Security: the
                -- permissions as they are now.
                setup_changed()
            elseif type(body.open) == "string" then
                -- A section's button: what its name stands for, and nothing
                -- the page can name otherwise.
                if checklist.ask_first(body.open, { location = M.location_status(tide.adapter.log) }) then
                    ask_location(tide)
                elseif not links.open(body.open, tide.adapter) then
                    tide.adapter.log("settings: no button named " .. body.open)
                end
            elseif body.close and view then
                tide.wm:own_window("settings", nil)
                view:delete()
                view = nil
            end
        end)
    end)

    -- The files changed: show them as they are now.
    self.refresh = push

    -- The clipboard history changed: its count, alone, so a copy made while
    -- you're editing another section doesn't redraw it.
    function self.clipboard_changed()
        if not (view and tide.picker) then
            return
        end
        view:evaluateJavaScript("tide.count(" .. math.tointeger(#tide.picker.history.items) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Fill in the Floating section's fields (floating.prefill).
    local function fill_in(fill)
        if not (view and fill) then
            return
        end
        view:evaluateJavaScript("tide.floatingFill(" .. M.encode_fill(fill) .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end
    local wanted_fill

    -- Open the window, or bring it forward, showing `section` if given,
    -- with the Floating section filled in by `fill` if given.
    function self.show(section, fill)
        if view then
            local w = view:hswindow()
            if w then
                w:focus()
            end
            -- Floating now may have changed since it drew.
            push()
            reveal(section)
            fill_in(fill)
            return
        end
        wanted = section
        wanted_fill = fill
        local s = tide.wm:screen_by_uuid(tide.wm:current_screen())
        if not s then
            tide.adapter.log("settings: no display to show it on")
            return
        end
        -- Wide enough for the sidebar beside a page, and tall enough for
        -- every page and heading in it, as tide's card is: 703 points of
        -- them, at tide's 32 a page. A shorter display's sidebar scrolls.
        local w, h = 760, math.min(M.HEIGHT, s.area.h)
        local frame = { x = s.area.x + (s.area.w - w) / 2, y = s.area.y + (s.area.h - h) / 2, w = w, h = h }
        view = hs.webview.new(frame, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "titled", "closable" })
        -- tide leaves it untiled, so a floating level keeps it over the
        -- tiles, as a float is (SPEC.md §5.1).
        view:level(hs.drawing.windowLevels.floating)
        -- tide leaves its own windows alone, by this title.
        view:windowTitle(brand.title("settings"))
        view:allowTextEntry(true)
        view:navigationCallback(function(action)
            if action == "didFinishNavigation" then
                -- Read once there's a page to draw them on.
                bt.watch(true)
                np.watch(true)
                screens.read_ddc()
                push()
                reveal(wanted)
                fill_in(wanted_fill)
                wanted, wanted_fill = nil, nil
            end
        end)
        view:windowCallback(function(action)
            if action == "closing" then
                tide.wm:own_window("settings", nil)
                view = nil
                bt.watch(false)
                np.watch(false)
            end
        end)
        -- Focus follows mouse leaves it be, wherever it's dragged: asking
        -- Accessibility about a page waits on it (wm.own_window).
        tide.wm:own_window("settings", function()
            local f = view and view:frame()
            return f and { x = f.x, y = f.y, w = f.w, h = f.h }
        end)
        view:html(page)
        view:show()
        local hw = view:hswindow()
        if hw then
            hw:focus()
        end
    end

    -- What the page answers to `js`, done(result, err), after anything
    -- pushed before it: for CI's smoke test.
    function self.evaluate(js, done)
        if not view then
            done(nil, "the settings window isn't open")
            return
        end
        view:evaluateJavaScript(js, done)
    end

    return self
end

return M
