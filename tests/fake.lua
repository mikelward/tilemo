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
        pointer_uuid = "A",
        timers = {},
        calls = {},    -- "focus 3", "raise 4", ...
        files = {},
        procs = {},
        notes = {},
    }

    -- Front to back. A new window opens in front, and focusing or raising
    -- one brings it to the front, as on macOS.
    a.z = {}
    local function to_front(id)
        for i, v in ipairs(a.z) do
            if v == id then
                table.remove(a.z, i)
                break
            end
        end
        table.insert(a.z, 1, id)
    end

    function a.add(id, f)
        f.role = f.role or "AXWindow"
        f.subrole = f.subrole or "AXStandardWindow"
        f.app = f.app or "com.example.app"
        f.pid = f.pid or 100
        f.frame = f.frame or { x = 100, y = 100, w = 800, h = 600 }
        a.wins[id] = f
        a.order[#a.order + 1] = id
        to_front(id)
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

    function a.ordered()
        local out = {}
        for _, id in ipairs(a.z) do
            if a.wins[id] then
                out[#out + 1] = id
            end
        end
        return out
    end

    -- What Accessibility's hit test finds: the front window whose frame
    -- holds the point, unless something unmanaged (a menu, say) is listed
    -- in `a.covers` over it.
    a.covers = {}
    function a.window_at(x, y)
        for _, b in ipairs(a.covers) do
            if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
                return nil
            end
        end
        for _, id in ipairs(a.ordered()) do
            local f = a.wins[id]
            local b = f.frame
            if not f.minimized and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
                return id
            end
        end
    end

    a.menu = false
    function a.menu_open()
        return a.menu
    end

    a.front_app = "com.example.app"
    function a.frontmost_app()
        return a.front_app
    end

    a.px, a.py = 0, 0
    function a.pointer()
        return a.px, a.py
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

    a.badges = {} -- { app, label }, as the Dock shows them
    function a.dock_badges()
        return a.badges
    end
    function a.title(id)
        return a.wins[id] and a.wins[id].title
    end

    function a.app_focused(pid)
        if a.focus_ and a.wins[a.focus_] and a.wins[a.focus_].pid == pid then
            return a.focus_
        end
    end

    function a.pointer_screen()
        return a.pointer_uuid
    end

    function a.set_frame(id, b)
        a.calls[#a.calls + 1] = "frame " .. id
        a.wins[id].frame = { x = b.x, y = b.y, w = b.w, h = b.h }
    end

    function a.focus(id)
        a.calls[#a.calls + 1] = "focus " .. id
        a.focus_ = id
        to_front(id)
    end

    function a.raise(id)
        a.calls[#a.calls + 1] = "raise " .. id
        to_front(id)
    end

    function a.minimize(id)
        a.calls[#a.calls + 1] = "minimize " .. id
        a.wins[id].minimized = true
    end

    function a.unminimize(id)
        a.calls[#a.calls + 1] = "unminimize " .. id
        a.wins[id].minimized = false
    end

    function a.save(snap)
        a.saved = snap
    end

    a.launched, a.fresh, a.envs = {}, {}, {}
    function a.launch(spec, fresh, env)
        a.launched[#a.launched + 1] = spec
        a.fresh[#a.launched] = fresh or false
        a.envs[#a.launched] = env
    end

    a.app_names = {}
    function a.app_name(bundle)
        return a.app_names[bundle]
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

    -- The clock the focus guard reads, moved on by hand.
    a.clock = 0
    function a.now()
        return a.clock
    end

    -- Whether a process is running: any of its windows is open, unless
    -- `a.pids[pid]` says otherwise.
    a.pids = {}
    function a.pid_running(pid)
        if a.pids[pid] ~= nil then
            return a.pids[pid]
        end
        for _, f in pairs(a.wins) do
            if f.pid == pid then
                return true
            end
        end
        return false
    end

    -- Lock and log out, in the order asked for.
    a.system = {}
    function a.lock()
        a.system[#a.system + 1] = "lock"
    end
    function a.logout()
        a.system[#a.system + 1] = "logout"
    end

    a.shots = {}
    function a.screenshot(kind)
        a.shots[#a.shots + 1] = kind
    end

    return a
end

return M
