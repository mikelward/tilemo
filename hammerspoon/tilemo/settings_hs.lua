-- tilemo's settings window on Hammerspoon (SPEC.md §15): the Clocks,
-- Layouts, Start at login and Clipboard pages, dashboard.lua's settings page
-- in an hs.webview. It writes tide's clocks.local.json, layouts.local.json,
-- startup.local.json and clipboard.local.json, and tilemo hands
-- the files back once they change on disk, so the page shows what the bar
-- and the next login do. Not runnable outside
-- Hammerspoon.

local dashboard = require("tilemo.dashboard")
local layout = require("tilemo.layout")
local mute = require("tilemo.mute")
local picker = require("tilemo.picker")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tilemo: can't read the settings page's " .. name .. ": " .. tostring(err))
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

-- `tilemo` is the started tilemo module: its wm, adapter, clock_dir,
-- clock_files, layout_files, startup_files, clipboard_files and picker.
function M.new(tilemo)
    local self = {}
    local page = build()
    local view
    -- The section to show once the page has loaded, or nil.
    local wanted

    local function push()
        if not view then
            return
        end
        -- An empty list must reach the page as one, not as an object.
        local json = hs.json.encode({
            clockFiles = tilemo.clock_files,
            startupFiles = tilemo.startup_files,
            layoutFiles = tilemo.layout_files,
            -- What the files lay over: start()'s layout, or tide's
            -- defaults, so the page shows and steps what's in effect.
            layoutBase = tilemo.layout_base and layout.file_form(tilemo.layout_base) or nil,
            clipboardFiles = tilemo.clipboard_files,
            clipboardCount = tilemo.picker and #tilemo.picker.history.items or 0,
            -- The settings in effect, which a file gone wrong since leaves
            -- as they were: the page shows these, not the defaults, then.
            clipboardSettings = tilemo.clipboard_settings and {
                history = tilemo.clipboard_settings.history,
                maxItems = tilemo.clipboard_settings.max_items,
            } or nil,
            muted = "__muted__",
        })
        json = json:gsub('"__muted__"', function()
            return mute.encode_list(tilemo.wm.muted.list)
        end)
        view:evaluateJavaScript("tilemo.update(" .. json .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Scroll to section `id` ("clocks", "layouts", "startup", "clipboard" or
    -- "muted").
    local function reveal(id)
        if not (view and id) then
            return
        end
        view:evaluateJavaScript("tilemo.reveal(" .. hs.json.encode({ id }):sub(2, -2) .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- A write from the page: `text` to `name` in tide's folder, said in a
    -- notice naming `what` if it fails.
    local function save(name, text, what)
        local path = tilemo.clock_dir .. "/" .. name
        local ok, err = tilemo.adapter.write_file(path, text)
        if not ok then
            tilemo.adapter.notify("Couldn't save " .. what .. " to " .. path .. ": " .. tostring(err))
            -- The page showed the change already: back to the files.
            push()
        end
        -- The folder's watcher reloads the files, and then this page.
    end

    local content = hs.webview.usercontent.new("tilemo")
    content:setCallback(function(msg)
        local body = msg.body or {}
        tilemo.adapter.after(0, function()
            if type(body.write) == "string" then
                save(dashboard.LOCAL_FILE, body.write, "the clocks")
            elseif type(body.writeLayouts) == "string" then
                save(dashboard.LAYOUTS_LOCAL_FILE, body.writeLayouts, "the layouts")
            elseif type(body.writeStartup) == "string" then
                save(dashboard.STARTUP_LOCAL_FILE, body.writeStartup, "Start at login's commands")
            elseif type(body.writeClipboard) == "string" then
                save(dashboard.CLIPBOARD_LOCAL_FILE, body.writeClipboard, "the clipboard settings")
            elseif body.clearClipboard and tilemo.picker then
                picker.clear(tilemo.picker.history)
                push()
            elseif type(body.mute) == "string" then
                -- Typed at the Muted list's foot: as Cmd+M on a row, once
                -- the mute module takes it.
                local why = mute.add_problem(tilemo.wm.muted, body.mute)
                if why and view then
                    view:evaluateJavaScript("tilemo.mutedError(" .. hs.json.encode({ why, body.mute }):sub(2, -2) .. ")")
                elseif not why and tilemo.toggle_mute(body.mute) == nil then
                    push()
                end
            elseif type(body.unmute) == "string" then
                -- The same as Cmd+M on a muted row; it refreshes this page.
                if not mute.has(tilemo.wm.muted, body.unmute) or tilemo.toggle_mute(body.unmute) == nil then
                    push()
                end
            elseif body.close and view then
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
        if not (view and tilemo.picker) then
            return
        end
        view:evaluateJavaScript("tilemo.count(" .. math.tointeger(#tilemo.picker.history.items) .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Open the window, or bring it forward, showing `section` if given.
    function self.show(section)
        if view then
            local w = view:hswindow()
            if w then
                w:focus()
            end
            reveal(section)
            return
        end
        wanted = section
        local s = tilemo.wm:screen_by_uuid(tilemo.wm:current_screen())
        if not s then
            tilemo.adapter.log("settings: no display to show it on")
            return
        end
        local w, h = 560, 560
        local frame = { x = s.area.x + (s.area.w - w) / 2, y = s.area.y + (s.area.h - h) / 2, w = w, h = h }
        view = hs.webview.new(frame, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "titled", "closable" })
        -- tilemo leaves its own windows alone, by this title.
        view:windowTitle("tilemo settings")
        view:allowTextEntry(true)
        view:navigationCallback(function(action)
            if action == "didFinishNavigation" then
                push()
                reveal(wanted)
                wanted = nil
            end
        end)
        view:windowCallback(function(action)
            if action == "closing" then
                view = nil
            end
        end)
        view:html(page)
        view:show()
        local hw = view:hswindow()
        if hw then
            hw:focus()
        end
    end

    return self
end

return M
