-- tilemo's settings window on Hammerspoon (SPEC.md §15): the Clocks page,
-- dashboard.lua's settings page in an hs.webview. It writes tide's
-- clocks.local.json, and tilemo hands the files back once they change on
-- disk, so the page shows what the bar does. Not runnable outside
-- Hammerspoon.

local dashboard = require("tilemo.dashboard")
local mute = require("tilemo.mute")

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

-- `tilemo` is the started tilemo module: its wm, adapter, clock_dir and
-- clock_files.
function M.new(tilemo)
    local self = {}
    local page = build()
    local view

    local function push()
        if not view then
            return
        end
        -- An empty list must reach the page as one, not as an object.
        local json = hs.json.encode({ clockFiles = tilemo.clock_files, muted = "__muted__" })
        json = json:gsub('"__muted__"', function()
            return mute.encode_list(tilemo.wm.muted.list)
        end)
        view:evaluateJavaScript("tilemo.update(" .. json .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    local content = hs.webview.usercontent.new("tilemo")
    content:setCallback(function(msg)
        local body = msg.body or {}
        tilemo.adapter.after(0, function()
            if type(body.write) == "string" then
                local path = tilemo.clock_dir .. "/" .. dashboard.LOCAL_FILE
                local ok, err = tilemo.adapter.write_file(path, body.write)
                if not ok then
                    tilemo.adapter.notify("Couldn't save the clocks to " .. path .. ": " .. tostring(err))
                    -- The page showed the change already: back to the files.
                    push()
                end
                -- The folder's watcher reloads the files, and then this page.
            elseif type(body.unmute) == "string" then
                -- The same as Cmd+I on a muted row; it refreshes this page.
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

    function self.show()
        if view then
            local w = view:hswindow()
            if w then
                w:focus()
            end
            return
        end
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
