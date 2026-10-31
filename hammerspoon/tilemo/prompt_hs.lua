-- The name prompt (SPEC.md §6.2, §7.2): an hs.chooser listing the existing
-- workspaces, with a default name typed in and selected. Typing replaces
-- it, filtering the list or giving a new name; Enter answers with the row
-- picked, or with what's typed; Esc answers nil. What it decides is
-- wm.lua's and names.lua's; tests/prompt_hs_test.lua runs it against a
-- stand-in hs.chooser.

local names = require("tilemo.names")

local M = {}

-- How often the default follows a window's title until you type.
M.TITLE_POLL = 0.5

-- `tilemo` is the started tilemo module: its wm, adapter and patterns.
function M.new(tilemo)
    local self = {}
    local chooser, done, typed, setting, poll, exclude
    -- Home and End, taken only while the prompt is open.
    local open_keys = {}

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

    -- Selects the whole text. hs.chooser has no call for that, but show()
    -- makes its text field first responder, which in AppKit selects the
    -- field's text, and does so again while it's open. show() also runs
    -- the query callback, which mustn't count as typing.
    local function select_all()
        setting = true
        chooser:show()
        setting = false
    end

    local function release_keys()
        for _, k in ipairs(open_keys) do
            k:delete()
        end
        open_keys = {}
    end

    -- Home and End move to the start and end of the text, keeping it, as
    -- in tide's prompt. A macOS text field's own Home and End only scroll,
    -- so they send Cmd+Left and Cmd+Right instead. Either stops the default
    -- following the title, which would select it again; Left and Right
    -- the field handles itself, unseen here.
    local function bind_keys()
        release_keys()
        for key, arrow in pairs({ home = "left", ["end"] = "right" }) do
            open_keys[#open_keys + 1] = hs.hotkey.bind({}, key, function()
                typed = true
                hs.eventtap.keyStroke({ "cmd" }, arrow, 0)
            end)
        end
    end

    local function finish(name)
        if poll then
            poll:stop()
            poll = nil
        end
        release_keys()
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
                    select_all()
                end
            end)
        end
        bind_keys()
        select_all()
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

    -- Super+Shift+Return: any workspace, home included, which takes only
    -- its own apps' windows.
    function self.choose(on_done)
        open("Move the window to", "", on_done, nil, false)
    end

    -- Super+Return: any workspace to go to, home included, since nothing
    -- moves there.
    function self.go(on_done)
        open("Go to the workspace", "", on_done, nil, false)
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
