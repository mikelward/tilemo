-- The tray on Hammerspoon (SPEC.md §6.7): tray.lua's state as an hs.canvas
-- per display, floating over the windows in the bottom-right corner, with a
-- second canvas for the hovered icon's title. Not runnable outside
-- Hammerspoon.

local tray = require("tilemo.tray")
local bar = require("tilemo.bar")

local M = {}

local TIP_SIZE = 12
-- A long title is cut, with an ellipsis, at this width.
local TIP_MAX = 420

-- The bar's colors, light or dark as macOS is (launcher.css).
local function colors()
    if hs.host.interfaceStyle() == "Dark" then
        return { bg = { white = 0.11, alpha = 0.94 }, fg = { white = 0.9 }, tip = { white = 0.2, alpha = 0.97 }, blank = { white = 0.3 } }
    end
    return { bg = { white = 0.96, alpha = 0.94 }, fg = { white = 0.1 }, tip = { white = 1, alpha = 0.98 }, blank = { white = 0.8 } }
end

local function floating(c)
    c:level(hs.canvas.windowLevels.floating)
    c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)
    -- A click mustn't make Hammerspoon the front app, which would take focus
    -- from the window you were in (unverified that this is enough).
    c:clickActivating(false)
    return c
end

-- `tilemo` is the started tilemo module: its wm and adapter.
function M.new(tilemo)
    -- Per display: its canvas, the state it shows, and what was last drawn.
    local self = { canvases = {}, shown = {}, keys = {} }
    local log = tilemo.adapter.log
    local wm = tilemo.wm
    local tip

    local images = {}
    local function image_of(app)
        local img = images[app]
        if img == nil then
            local ok, v = pcall(hs.image.imageFromAppBundle, app)
            if not ok then
                log("tray: couldn't read the icon of " .. tostring(app) .. ": " .. tostring(v))
            end
            img = ok and v or false
            images[app] = img
        end
        return img or nil
    end

    local function hide_tip()
        if tip then
            tip:delete()
            tip = nil
        end
    end

    local function show_tip(st, i)
        hide_tip()
        local item = st.items[i]
        local s = wm:screen_by_uuid(st.uuid)
        if not item or item.title == "" or not s then
            return
        end
        local size = hs.drawing.getTextDrawingSize(item.title, { size = TIP_SIZE })
        local w = math.min(TIP_MAX, math.ceil(size.w)) + 18
        local h = math.ceil(size.h) + 10
        local c = colors()
        tip = floating(hs.canvas.new(tray.tip_frame(st.frame, i, w, h, s.area)))
        tip:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = c.tip,
            roundedRectRadii = { xRadius = 7, yRadius = 7 },
        }, {
            type = "text",
            text = item.title,
            textSize = TIP_SIZE,
            textColor = c.fg,
            textLineBreak = "truncateTail",
            frame = { x = 9, y = 5, w = w - 18, h = h - 10 },
        })
        tip:show()
    end

    local function on_mouse(uuid, msg, id)
        local st = self.shown[uuid]
        local i = st and tonumber(tostring(id or ""):match("^icon(%d+)$"))
        if not i then
            return
        end
        if msg == "mouseEnter" then
            show_tip(st, i)
        elseif msg == "mouseExit" then
            hide_tip()
        elseif msg == "mouseUp" then
            hide_tip()
            local item = st.items[i]
            -- Out of the canvas's own callback before changing the screen.
            tilemo.adapter.after(0, function()
                tray.click(wm, item.id)
            end)
        end
    end

    local function draw(uuid, st)
        local c = self.canvases[uuid]
        if not c then
            c = floating(hs.canvas.new(st.frame))
            c:mouseCallback(function(_, msg, id)
                on_mouse(uuid, msg, id)
            end)
            self.canvases[uuid] = c
        else
            c:frame(st.frame)
        end
        local col = colors()
        local elements = {
            {
                type = "rectangle",
                action = "fill",
                fillColor = col.bg,
                roundedRectRadii = { xRadius = 12, yRadius = 12 },
            },
        }
        for i, item in ipairs(st.items) do
            local box = tray.icon_box(i)
            local img = item.app ~= "" and image_of(item.app)
            local e = {
                id = "icon" .. i,
                frame = box,
                trackMouseEnterExit = true,
                trackMouseUp = true,
            }
            if img then
                e.type = "image"
                e.image = img
                e.imageScaling = "scaleProportionally"
            else
                -- An app with no icon is a blank square, as on the bar.
                e.type = "rectangle"
                e.action = "fill"
                e.fillColor = col.blank
                e.roundedRectRadii = { xRadius = 6, yRadius = 6 }
            end
            elements[#elements + 1] = e
        end
        c:replaceElements(elements)
        c:show()
    end

    -- Redraw what changed: called on every wm change, like the bar.
    function self.update()
        local trays = tray.all(wm, function(uuid)
            return bar.hidden(wm, uuid)
        end)
        wm.overlays = tray.frames(trays)
        for uuid, st in pairs(trays) do
            st.uuid = uuid
            local key = hs.json.encode({ st.frame, st.items })
            if key ~= self.keys[uuid] then
                self.keys[uuid] = key
                draw(uuid, st)
            end
            self.shown[uuid] = st
        end
        for uuid, c in pairs(self.canvases) do
            if not trays[uuid] then
                c:delete()
                self.canvases[uuid] = nil
                self.shown[uuid] = nil
                self.keys[uuid] = nil
                hide_tip()
            end
        end
    end

    -- The trays' frames, for the smoke test.
    function self.frames()
        local out = {}
        for uuid, c in pairs(self.canvases) do
            local f = c:frame()
            out[uuid] = { x = f.x, y = f.y, w = f.w, h = f.h }
        end
        return out
    end

    return self
end

return M
