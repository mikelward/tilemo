-- The name prompt (SPEC.md §6.2, §7.2): an hs.chooser listing the existing
-- workspaces, with a default name typed in. Typing filters the list or
-- gives a new name; Enter answers with the row picked, or with what's
-- typed; Esc answers nil. Not runnable outside Hammerspoon; what it
-- decides is wm.lua's and names.lua's.

local names = require("tilemo.names")

local M = {}

-- How often the default follows a window's title until you type.
M.TITLE_POLL = 0.5

-- `tilemo` is the started tilemo module: its wm, adapter and patterns.
function M.new(tilemo)
    local self = {}
    local chooser, done, typed, setting, poll, exclude

    -- Every workspace listed, the standing ones made or not, filtered by
    -- what's typed, ignoring case; what's typed, if it names none, first.
    local function rows(query)
        local wm = tilemo.wm
        local name = wm.clean_name(query or "")
        local want = name and wm.fold(name) or ""
        local out = {}
        local exact = false
        for _, n in ipairs((wm:listed())) do
            local f = wm.fold(n)
            if n ~= exclude and (want == "" or f:find(want, 1, true)) then
                out[#out + 1] = { text = n, name = n }
                exact = exact or f == want
            end
        end
        if name and not exact then
            table.insert(out, 1, { text = name, subText = "New workspace", name = name })
        end
        return out
    end

    local function set_query(text)
        setting = true
        chooser:query(text)
        setting = false
        chooser:choices(rows(text))
    end

    local function finish(name)
        if poll then
            poll:stop()
            poll = nil
        end
        local cb = done
        done = nil
        if cb then
            cb(name)
        end
    end

    chooser = hs.chooser.new(function(choice)
        finish(choice and choice.name or nil)
    end)
    chooser:queryChangedCallback(function(query)
        if not setting then
            typed = true
        end
        chooser:choices(rows(query))
    end)

    -- Open the prompt, with `default` typed in, and `on_done(name or nil)`
    -- once it's answered. `follow()`, if given, gives the default again,
    -- for a title that arrives after its window. The home workspace isn't
    -- offered when `no_home` says so. wm.lua asks one question at a time,
    -- so the prompt is never open already: canceling an open one would
    -- answer it as Esc.
    local function open(placeholder, default, on_done, follow, no_home)
        if done then
            tilemo.adapter.log("name prompt: asked again while open; the earlier question was dropped")
            if poll then
                poll:stop()
                poll = nil
            end
        end
        done = on_done
        typed = false
        exclude = no_home and tilemo.wm.home or nil
        chooser:placeholderText(placeholder)
        -- hs.chooser has no way to select its text, so typing adds to the
        -- default rather than replacing it *(unverified)*; Cmd+A or
        -- Backspace clears it.
        set_query(default or "")
        if follow then
            local last = default
            poll = hs.timer.doEvery(M.TITLE_POLL, function()
                if typed then
                    return
                end
                local now = follow()
                if now and now ~= last then
                    last = now
                    set_query(now)
                end
            end)
        end
        chooser:show()
    end

    local function default_for(id)
        local w = tilemo.wm.windows[id]
        local title = tilemo.adapter.title(id) or (w and w.title) or ""
        local app = w and (w.name or (w.app and tilemo.adapter.app_name(w.app))) or ""
        return names.default_name(title, app, tilemo.name_patterns, tilemo.adapter.javascript, tilemo.adapter.log)
    end

    -- A window opening on home: its answer goes to wm:answer.
    function self.window(id)
        open("Workspace for this window", default_for(id), function(name)
            tilemo.wm:answer(id, name)
        end, function()
            return default_for(id)
        end, true)
    end

    -- A launch from home, or Cmd+Return: `on_done(name or nil)`.
    function self.launch(default, on_done)
        open("Workspace to open it on", default, on_done, nil, true)
    end

    -- For CI's smoke test: the rows shown, and Esc.
    function self.rows()
        return rows(chooser:query())
    end

    function self.cancel()
        chooser:cancel()
    end

    return self
end

return M
