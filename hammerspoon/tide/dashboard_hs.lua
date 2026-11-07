-- The dashboard on Hammerspoon: dashboard.lua's page in a borderless
-- hs.webview over the display you're on (SPEC.md §8). Pressing its key
-- again, Esc, or clicking another window closes it; a workspace's chip
-- shows that workspace. Not runnable outside Hammerspoon.

local brand = require("tide.brand")
local dashboard = require("tide.dashboard")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the dashboard's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing or unreadable file is an error then,
-- not on the first press of the key.
local function build()
    local sources = {}
    for _, name in ipairs(dashboard.MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("dashboard.html"), read("launcher.css"), sources)
end

-- `tide` is the started tide module: its wm and adapter.
function M.new(tide)
    local self = {}
    local page = build()
    local view, before, uuid

    local function close(refocus)
        if not view then
            return
        end
        local v = view
        view = nil
        tide.wm:hold("dashboard", false)
        tide.wm:own_window("dashboard", nil)
        v:delete()
        if refocus and before then
            tide.wm:focus_unburied(before)
        end
    end

    -- Fills the page with what it shows now.
    local function push(v)
        local state = hs.json.encode(dashboard.state(tide.wm, tide.adapter, uuid, tide.clock_files, tide.good_clocks))
        v:evaluateJavaScript("tide.update(" .. state .. ")", function(_, err)
            if dashboard.js_failed(err) then
                tide.adapter.log("dashboard: " .. hs.inspect(err))
            end
        end)
    end

    local content = hs.webview.usercontent.new("tide")
    content:setCallback(function(msg)
        local body = msg.body or {}
        -- Out of the page's own callback before deleting the page.
        tide.adapter.after(0, function()
            -- A standing workspace not made yet is made by showing it.
            local n = body.show ~= nil and tide.wm:canonical(tostring(body.show))
            if n and not tide.wm:shown(n) then
                -- Showing a workspace focuses its own window, not the one before.
                -- On the display it opened on, whatever focus does as it
                -- closes.
                close(false)
                tide.wm:show(n, uuid)
            elseif n then
                -- The one already here: show() has nothing to do, so focus
                -- goes back to the window you were in.
                close(true)
            elseif body.close then
                close(true)
            elseif body.settings then
                close(false)
                tide.settings.show()
            elseif body.clockErrors then
                tide.report_clock_errors(body.clockErrors)
            elseif body.goodClocks then
                tide.keep_good_clocks(body.goodClocks)
            end
        end)
    end)

    -- On display `on`, as a bar's clocks ask, or else where the keys act,
    -- as Super+Shift+Space asks.
    function self.show(on)
        if view then
            close(true)
            return
        end
        before = tide.adapter.focused()
        uuid = on or tide.wm:current_screen()
        local s = tide.wm:screen_by_uuid(uuid)
        if not s then
            tide.adapter.log("dashboard: no display to show it on")
            return
        end
        view = hs.webview.new(s.full, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "borderless" })
        -- A title for the rules to see: tide leaves its own windows alone.
        view:windowTitle(brand.title("dashboard"))
        view:level(hs.drawing.windowLevels.modalPanel)
        view:allowTextEntry(true)
        view:navigationCallback(function(action, v)
            if action == "didFinishNavigation" then
                push(v)
            end
        end)
        view:windowCallback(function(action, _, focused)
            -- Clicking away closes it, as tileco's does.
            if action == "focusChange" and focused == false then
                close(false)
            elseif action == "closing" then
                view = nil
                tide.wm:hold("dashboard", false)
                tide.wm:own_window("dashboard", nil)
            end
        end)
        view:html(page)
        view:show()
        tide.wm:hold("dashboard", true)
        -- Focus follows mouse leaves it be (wm.own_window).
        tide.wm:own_window("dashboard", s.full)
        local w = view:hswindow()
        if w then
            w:focus()
        end
    end

    -- The clocks files changed: an open dashboard shows them now.
    function self.refresh()
        if view then
            push(view)
        end
    end

    return self
end

return M
