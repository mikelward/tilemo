-- A fake adapter: windows and displays in tables, timers run by hand.

local M = {}

function M.new()
    local a = {
        wins = {},     -- id -> facts, plus state fields
        order = {},    -- ids in creation order
        screens_ = {
            { uuid = "A", area = { x = 0, y = 25, w = 1920, h = 1055 }, full = { x = 0, y = 0, w = 1920, h = 1080 } },
        },
        focus_ = nil,
        pointer = "A",
        timers = {},
        calls = {},    -- "focus 3", "raise 4", ...
        files = {},
        procs = {},
        notes = {},
    }

    function a.add(id, f)
        f.role = f.role or "AXWindow"
        f.subrole = f.subrole or "AXStandardWindow"
        f.app = f.app or "com.example.app"
        f.pid = f.pid or 100
        f.frame = f.frame or { x = 100, y = 100, w = 800, h = 600 }
        a.wins[id] = f
        a.order[#a.order + 1] = id
        return id
    end

    function a.drop(id)
        a.wins[id] = nil
        for i, v in ipairs(a.order) do
            if v == id then
                table.remove(a.order, i)
                break
            end
        end
        if a.focus_ == id then
            a.focus_ = nil
        end
    end

    function a.windows()
        local out = {}
        for _, id in ipairs(a.order) do
            out[#out + 1] = id
        end
        return out
    end

    function a.state(id)
        local f = a.wins[id]
        if not f then
            return nil
        end
        return { frame = f.frame, minimized = f.minimized or false, fullscreen = f.fullscreen or false, hidden = f.hidden or false }
    end

    function a.facts(id)
        return a.wins[id]
    end

    -- Front to back: the last focused first, then creation order.
    function a.ordered()
        local out = {}
        if a.focus_ and a.wins[a.focus_] then
            out[1] = a.focus_
        end
        for i = #a.order, 1, -1 do
            local id = a.order[i]
            if id ~= a.focus_ then
                out[#out + 1] = id
            end
        end
        return out
    end

    a.buttons = false
    function a.buttons_down()
        return a.buttons
    end

    function a.screens()
        return a.screens_
    end

    function a.focused()
        return a.focus_
    end

    function a.app_focused(pid)
        if a.focus_ and a.wins[a.focus_] and a.wins[a.focus_].pid == pid then
            return a.focus_
        end
    end

    function a.pointer_screen()
        return a.pointer
    end

    function a.set_frame(id, b)
        a.calls[#a.calls + 1] = "frame " .. id
        a.wins[id].frame = { x = b.x, y = b.y, w = b.w, h = b.h }
    end

    function a.focus(id)
        a.calls[#a.calls + 1] = "focus " .. id
        a.focus_ = id
    end

    function a.raise(id)
        a.calls[#a.calls + 1] = "raise " .. id
    end

    function a.close(id)
        a.calls[#a.calls + 1] = "close " .. id
    end

    function a.after(_, fn)
        local timer = { fn = fn }
        function timer.stop()
            timer.stopped = true
        end
        a.timers[#a.timers + 1] = timer
        return timer
    end

    -- Run every timer that's due, as the clock moving on would.
    function a.tick()
        local due = a.timers
        a.timers = {}
        for _, timer in ipairs(due) do
            if not timer.stopped then
                timer.fn()
            end
        end
    end

    function a.read(path)
        return a.files[path]
    end

    function a.running(name)
        return a.procs[name] or false
    end

    function a.notify(text)
        a.notes[#a.notes + 1] = text
    end

    function a.log() end

    return a
end

return M
