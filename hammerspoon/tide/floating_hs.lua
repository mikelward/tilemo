-- The float rules you make, on Hammerspoon (SPEC.md §5.1, §15): reading
-- floating-macos.json and floating-macos.local.json into the window
-- manager, the settings window's edits, and the question after
-- Super+Shift+F floats a window no rule covers (floating.lua has the
-- rules themselves). Runs against `hs`, which the tests stand in for.

local floating = require("tide.floating")

local M = {}

-- Where the apps asked about this login are kept, so a reload doesn't ask
-- again.
M.SETTINGS_KEY = "tide.floating_asked"
M.ALWAYS = "Always float"
M.EDIT = "Edit rule…"

-- `tide` is the started tide module: its wm, adapter, clock_dir and
-- settings (which may come later). `get_login` tells this login, as
-- adapter.login() does, asked once, the first time it's needed.
function M.new(tide, get_login)
    local self = { rules = {}, source = nil, error = nil }
    local a = tide.adapter
    local reported
    local login, known

    -- Read the files and hand the rules to the window manager, which
    -- floats what a new rule covers. A file that's wrong is said once,
    -- naming it, and the last good rules stay.
    function self.load()
        local list, from = floating.load(tide.clock_dir, a.read, a.decode)
        if list then
            self.rules, self.source, self.error = list, from, nil
            reported = nil
            tide.wm:set_float_rules(list)
        else
            self.error = from
            if from ~= reported then
                reported = from
                a.notify("The float rules stay as they were: " .. from)
            end
        end
    end

    local function encode(v)
        return hs.json.encode(v, true)
    end

    -- One of floating.lua's edits, written to floating-macos.local.json and
    -- applied at once rather than when the folder's watcher fires. Returns
    -- true, or nil and why, having changed nothing.
    function self.edit(fn)
        local ok, why = floating.edit(tide.clock_dir, a.read, a.decode, encode, a.write_file, fn)
        if not ok then
            return nil, why
        end
        self.load()
        if tide.settings then
            tide.settings.refresh()
        end
        return true
    end

    -- The settings window's Floating section, filled in for window `id`,
    -- or for `fill`, a fill-in made before. A window with no app to name,
    -- or none at all, is a notification, since a key has nowhere else to
    -- show it.
    function self.open(id, fill)
        fill = fill or (id and tide.wm.windows[id] and tide.wm:float_prefill(id))
        if not fill then
            a.notify(id and "This window has no app to name in a float rule." or "No window is focused to make a float rule for.")
            return
        end
        tide.settings.show("floating", fill)
    end

    -- Keep the notifications until they're answered: a collected one can't
    -- call back. One left to expire stays here, at most one per app a login.
    local pending = {}

    -- Window `id` was floated by Super+Shift+F and no rule covers it: ask
    -- once per app per login whether to always float its app.
    function self.ask(id)
        local fill = tide.wm:float_prefill(id)
        if not fill then
            return
        end
        if not known then
            login, known = get_login(), true
        end
        local yes, store = floating.ask(hs.settings.get(M.SETTINGS_KEY), login, fill.app)
        hs.settings.set(M.SETTINGS_KEY, store)
        if not yes then
            return
        end
        local note
        note = hs.notify.new(function(n)
            pending[note] = nil
            local kind = n:activationType()
            local types = hs.notify.activationTypes
            if kind == types.actionButtonClicked then
                local ok, why = self.edit(function(list)
                    return floating.with(list, fill.app, "")
                end)
                if not ok then
                    a.notify("Couldn't add the float rule for " .. fill.name .. ": " .. tostring(why))
                end
            elseif kind == types.additionalActionClicked and n:additionalActivationAction() == M.EDIT
                or kind == types.contentsClicked then
                self.open(nil, fill)
            end
        end, {
            title = "tide",
            informativeText = floating.question(fill.name),
            hasActionButton = true,
            actionButtonTitle = M.ALWAYS,
            additionalActions = { M.EDIT },
            otherButtonTitle = "Not now",
            -- Long enough to answer; expiring is Not now, as on tide.
            withdrawAfter = 30,
        })
        pending[note] = true
        note:send()
    end

    return self
end

return M
