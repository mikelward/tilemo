-- The dim on Hammerspoon (SPEC.md §5.6; dim.lua): one hs.canvas per
-- display, over the windows and under the bar, the tray, panels, menus and
-- the Dock, that the pointer clicks through. Not runnable outside
-- Hammerspoon.

local dim = require("tide.dim")

local M = {}

-- Over normal windows (level 0) and under floating ones (3), where the
-- bar, the tray, picture-in-picture and apps' panels sit *(unverified for
-- every app's panel)*.
M.LEVEL = 1
-- Events come in bursts, a drag's moves most of all: one redraw for each.
M.DEBOUNCE = 0.03

-- `tide` is the started tide module: its wm, adapter and clock_dir.
function M.new(tide)
    local self = { canvases = {}, drawn = {} }
    local a = tide.adapter
    local strength = dim.STRENGTH
    local radius = dim.radius(hs.host.operatingSystemVersion().major)
    local reported = ""
    local pending

    -- The strength from tide's appearance files, again as they change.
    function self.load()
        local dir = tide.clock_dir
        local errors
        strength, errors = dim.load(a.read(dir .. "/" .. dim.SHARED_FILE), a.read(dir .. "/" .. dim.LOCAL_FILE),
            hs.json.decode)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported then
            a.log("dim: " .. text)
        end
        reported = text
    end

    local function drop(uuid)
        if self.canvases[uuid] then
            self.canvases[uuid]:delete()
        end
        self.canvases[uuid] = nil
        self.drawn[uuid] = nil
    end

    local function draw()
        local ok, err = pcall(function()
            local scene = tide.wm:dim_scene()
            local seen = {}
            for _, s in ipairs(tide.wm:screens()) do
                seen[s.uuid] = true
                local els = dim.elements(scene, s.full, strength, radius)
                local key = els and hs.inspect(els) .. hs.inspect(s.full)
                if not els then
                    drop(s.uuid)
                elseif key ~= self.drawn[s.uuid] then
                    local c = self.canvases[s.uuid]
                    if not c then
                        c = hs.canvas.new(s.full)
                        c:level(M.LEVEL)
                        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)
                        self.canvases[s.uuid] = c
                    else
                        c:frame(s.full)
                    end
                    c:replaceElements(els)
                    c:show()
                    self.drawn[s.uuid] = key
                end
            end
            for uuid in pairs(self.canvases) do
                if not seen[uuid] then
                    drop(uuid)
                end
            end
        end)
        if not ok then
            a.log("dim: couldn't draw: " .. tostring(err))
        end
    end

    -- Something the dim shows may have changed: focus, a window's frame, the
    -- stacking or the displays.
    function self.update()
        if pending then
            return
        end
        pending = a.after(M.DEBOUNCE, function()
            pending = nil
            draw()
        end)
    end

    -- Focus moving to another app, Hammerspoon's own windows among them,
    -- which the window watchers leave out (hs_adapter.watch).
    self.apps = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.activated then
            self.update()
        end
    end)
    self.apps:start()

    function self.stop()
        self.apps:stop()
        for uuid in pairs(self.canvases) do
            drop(uuid)
        end
    end

    self.load()
    return self
end

return M
