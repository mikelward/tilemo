-- The overview on Hammerspoon (SPEC.md §6.9): overview.lua's page in a
-- full-screen borderless hs.webview over the display you're on, as the
-- dashboard is (dashboard_hs.lua). Ctrl+Up shows every workspace's windows,
-- Ctrl+Down the current workspace's. The same key again, Esc, a click on
-- empty space or on another window closes it; the other key switches it to
-- that scope. Not runnable outside Hammerspoon.

local brand = require("tide.brand")
local dashboard = require("tide.dashboard")
local overview = require("tide.overview")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

-- An icon's size: a card's 32 px at 2x.
M.ICON = { w = 64, h = 64 }

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the overview's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing or unreadable file is an error then,
-- not on the first press of the key.
local function build()
    local sources = {}
    for _, name in ipairs(overview.MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("overview.html"), read("launcher.css"), sources, overview.MODULES)
end

-- `tide` is the started tide module: its wm and adapter.
function M.new(tide)
    local self = {}
    local page = build()
    local log = tide.adapter.log
    local view, before, uuid, scope

    -- Each app's icon as a PNG data URL, from its bundle, which needs no
    -- Screen Recording. Made once per bundle ID; an app with no icon is
    -- kept as false, so it isn't asked again.
    local icons = {}
    local function icon_of(bundle)
        local url = icons[bundle]
        if url == nil then
            local ok, v = pcall(function()
                local img = hs.image.imageFromAppBundle(bundle)
                return img and img:setSize(M.ICON):encodeAsURLString(false, "PNG")
            end)
            if not ok then
                log("overview: couldn't read the icon of " .. tostring(bundle) .. ": " .. tostring(v))
            end
            url = ok and v or false
            icons[bundle] = url
        end
        return url or nil
    end

    local function close(refocus)
        if not view then
            return
        end
        local v = view
        view = nil
        tide.wm:hold("overview", false)
        tide.wm:own_window("overview", nil)
        v:delete()
        if refocus and before then
            tide.wm:focus_unburied(before)
        end
    end

    -- Fills the page with what it shows now.
    local function push(v)
        local state = hs.json.encode(overview.state(tide.wm, scope, icon_of, before))
        v:evaluateJavaScript("tide.update(" .. state .. ")", function(_, err)
            if dashboard.js_failed(err) then
                log("overview: " .. hs.inspect(err))
            end
        end)
    end

    local content = hs.webview.usercontent.new("tide")
    content:setCallback(function(msg)
        local body = msg.body or {}
        -- Out of the page's own callback before deleting the page.
        tide.adapter.after(0, function()
            local wm = tide.wm
            local id = body.activate
            local n = body.show ~= nil and wm:canonical(tostring(body.show))
            if id ~= nil then
                -- JSON gives the id back as a number, which is how wm keys
                -- windows (hs.window:id()).
                id = tonumber(id) or id
                if wm.windows[id] then
                    -- Activate brings its workspace along, to this display,
                    -- and restores a window you minimized (SPEC.md §6.1).
                    close(false)
                    wm:activate(id, uuid)
                else
                    log("overview: window " .. tostring(id) .. " has gone")
                    close(true)
                end
            elseif n and not wm:shown(n) then
                -- As the dashboard's chips: showing a workspace focuses its
                -- own window, on the display the overview opened on.
                close(false)
                wm:show(n, uuid)
            elseif n or body.close then
                close(true)
            end
        end)
    end)

    -- `which` is "all" (Ctrl+Up) or "current" (Ctrl+Down).
    function self.show(which)
        if not overview.SCOPES[which] then
            log("overview: no scope " .. tostring(which))
            return
        end
        if view then
            if which == scope then
                close(true)
            else
                scope = which
                push(view)
            end
            return
        end
        scope = which
        before = tide.adapter.focused()
        uuid = tide.wm:current_screen()
        local s = tide.wm:screen_by_uuid(uuid)
        if not s then
            log("overview: no display to show it on")
            return
        end
        view = hs.webview.new(s.full, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "borderless" })
        -- A title for the rules to see: tide leaves its own windows alone.
        view:windowTitle(brand.title("overview"))
        view:level(hs.drawing.windowLevels.modalPanel)
        view:allowTextEntry(true)
        view:navigationCallback(function(action, v)
            if action == "didFinishNavigation" then
                push(v)
            end
        end)
        view:windowCallback(function(action, _, focused)
            if action == "focusChange" and focused == false then
                close(false)
            elseif action == "closing" then
                view = nil
                tide.wm:hold("overview", false)
                tide.wm:own_window("overview", nil)
            end
        end)
        view:html(page)
        view:show()
        -- Focus follows mouse pauses while it's open, as for the dashboard
        -- (SPEC.md §5.2).
        tide.wm:hold("overview", true)
        tide.wm:own_window("overview", s.full)
        local w = view:hswindow()
        if w then
            w:focus()
        end
    end

    return self
end

return M
