-- floating_hs.lua against the fake adapter and a stand-in hs: the files
-- loaded into the window manager, the settings window's edits, and the
-- "Always float" question after Super+Shift+F.

local t = require("t")
local fake = require("fake")
local json = require("json")
local wm_mod = require("tide.wm")
local floating = require("tide.floating")

local DIR = "/home/user/.config/tide"
local LOCAL = DIR .. "/" .. floating.LOCAL_FILE

local ACTION, OTHER, CONTENTS = "action", "other", "contents"

-- A stand-in hs: notifications kept to be answered by hand, and a settings
-- store.
local function stub()
    local s = { notes = {}, settings = {} }
    _G.hs = {
        json = { encode = json.encode },
        settings = {
            get = function(k)
                return s.settings[k]
            end,
            set = function(k, v)
                s.settings[k] = v
            end,
        },
        notify = {
            activationTypes = { actionButtonClicked = ACTION, additionalActionClicked = OTHER, contentsClicked = CONTENTS },
            new = function(fn, attrs)
                local n = { attrs = attrs, fn = fn }
                function n:send()
                    s.notes[#s.notes + 1] = n
                end
                function n:activationType()
                    return n.kind
                end
                function n:additionalActivationAction()
                    return n.extra
                end
                function n.answer(kind, extra)
                    n.kind, n.extra = kind, extra
                    fn(n)
                end
                return n
            end,
        },
    }
    return s
end

local function setup()
    local s = stub()
    package.loaded["tide.floating_hs"] = nil
    local floating_hs = require("tide.floating_hs")
    local a = fake.new()
    a.add(1, { app = "com.example.alpha", name = "Alpha", title = "Big (1).txt" })
    a.add(2, { app = "com.example.beta", name = "Beta", title = "Beta" })
    function a.write_file(p, text)
        a.files[p] = text
        return true
    end
    a.decode = json.decode
    local logins = 0
    local tide = { adapter = a, clock_dir = DIR }
    tide.wm = wm_mod.new(a, {})
    tide.settings = {
        shown = {},
        refreshed = 0,
        show = function(section, fill)
            tide.settings.shown[#tide.settings.shown + 1] = { section = section, fill = fill }
        end,
        refresh = function()
            tide.settings.refreshed = tide.settings.refreshed + 1
        end,
    }
    tide.floating = floating_hs.new(tide, function()
        logins = logins + 1
        return "login 1"
    end)
    tide.floating.load()
    tide.wm.floated_by_hand = function(id)
        tide.floating.ask(id)
    end
    tide.wm:sync()
    tide.wm:retile()
    return s, a, tide, function()
        return logins
    end
end

t.test("floating a window by the key asks once whether to always float its app", function()
    local s, a, tide, logins = setup()
    a.focus_ = 1
    tide.wm:act("toggle_float")
    t.eq(#s.notes, 1)
    local n = s.notes[1].attrs
    t.eq(n.title, "tide")
    t.eq(n.informativeText, "Always float Alpha?")
    t.eq(n.actionButtonTitle, "Always float")
    t.eq(n.additionalActions, { "Edit rule…" })
    -- Tiled and floated again, or reloaded in the same login: not again.
    tide.wm:act("toggle_float")
    tide.wm:act("toggle_float")
    t.eq(#s.notes, 1)
    t.eq(logins(), 1, "the login is told once")
    a.focus_ = 2
    tide.wm:act("toggle_float")
    t.eq(#s.notes, 2, "another app is asked about")
end)

t.test("a reload in the same login doesn't ask again; a new login does", function()
    local s, a, tide = setup()
    a.focus_ = 1
    tide.wm:act("toggle_float")
    local kept = s.settings
    local s2, a2, tide2 = setup()
    s2.settings[next(kept)] = kept[next(kept)]
    a2.focus_ = 1
    tide2.wm:act("toggle_float")
    t.eq(#s2.notes, 0)
    s2.settings[next(kept)].login = "an earlier login"
    tide2.wm:act("toggle_float")
    tide2.wm:act("toggle_float")
    t.eq(#s2.notes, 1)
    t.eq(a.files[LOCAL], nil, "asking writes nothing")
end)

t.test("Always float adds the app's rule at once", function()
    local s, a, tide = setup()
    a.focus_ = 1
    tide.wm:act("toggle_float")
    t.eq(#tide.wm:floating_now(), 1)
    s.notes[1].answer(ACTION)
    t.eq(json.decode(a.files[LOCAL]).rules, { { app = "com.example.alpha" } })
    t.eq(tide.wm.float_rules, { { app = "com.example.alpha", action = "float" } })
    t.eq(#tide.wm:floating_now(), 0, "a rule covers it now")
    t.eq(tide.settings.refreshed, 1)
end)

t.test("Edit rule… and a click on the notification open the page filled in", function()
    local s, a, tide = setup()
    a.focus_ = 1
    tide.wm:act("toggle_float")
    s.notes[1].answer(OTHER, "Edit rule…")
    local shown = tide.settings.shown[1]
    t.eq(shown.section, "floating")
    t.eq(shown.fill.app, "com.example.alpha")
    t.eq(shown.fill.title, "^Big %(1%)%.txt$")
    s.notes[1].answer(CONTENTS)
    t.eq(#tide.settings.shown, 2)
    t.eq(a.files[LOCAL], nil, "neither adds a rule")
end)

t.test("the key with no window, or one with no app, says so", function()
    local _, a, tide = setup()
    tide.floating.open(nil)
    a.add(3, { title = "x" })
    a.wins[3].app = nil
    tide.wm:sync()
    tide.floating.open(3)
    t.eq(a.notes, { "No window is focused to make a float rule for.", "This window has no app to name in a float rule." })
    tide.floating.open(1)
    t.eq(tide.settings.shown[1].fill.app, "com.example.alpha")
end)

t.test("a file that's wrong is said once, and the last good rules stay", function()
    local _, a, tide = setup()
    a.files[LOCAL] = '{"rules": [{"app": "com.example.beta"}]}'
    tide.floating.load()
    t.eq(tide.wm.windows[2].floating, true, "the new rule floated it")
    a.files[LOCAL] = '{"rules": [{"app": "x", "title": "("}]}'
    tide.floating.load()
    tide.floating.load()
    t.eq(#a.notes, 1)
    t.eq(a.notes[1]:find("The float rules stay as they were: " .. floating.LOCAL_FILE .. ": rules[1]", 1, true), 1)
    t.eq(tide.wm.float_rules, { { app = "com.example.beta", action = "float" } })
    t.eq(tide.floating.error ~= nil, true)
end)

t.test("the settings window's messages add, move and remove rules", function()
    local _, a, tide = setup()
    _G.hs.webview = nil
    package.loaded["tide.settings_hs"] = nil
    local settings_hs = require("tide.settings_hs")
    local edit = function(body)
        return settings_hs.float_edit(tide.floating, body)
    end
    t.eq(edit({ floatAdd = { app = "com.example.alpha", title = "^Big" } }), true)
    t.eq(edit({ floatAdd = { app = "com.example.beta", title = "" } }), true)
    t.eq(edit({ floatMove = { index = 2, app = "com.example.beta", title = "", step = -1 } }), true)
    t.eq(json.decode(a.files[LOCAL]).rules, { { app = "com.example.beta" }, { app = "com.example.alpha", title = "^Big" } })
    local ok, why = edit({ floatRemove = { index = 1, app = "com.example.alpha", title = "^Big" } })
    t.eq(ok, nil)
    t.eq(why:find("changed", 1, true) ~= nil, true)
    t.eq(edit({ floatRemove = { index = 2, app = "com.example.alpha", title = "^Big" } }), true)
    t.eq(json.decode(a.files[LOCAL]).rules, { { app = "com.example.beta" } })
    ok, why = edit({ floatAdd = { app = "x", title = "%" } })
    t.eq(ok, nil)
    t.eq(why:find("isn't a Lua pattern", 1, true) ~= nil, true, why)
end)

t.test("showing an open settings window again redraws Floating now", function()
    local _, _, tide = setup()
    local pushed = 0
    local view = {}
    for _, m in ipairs({ "windowStyle", "windowTitle", "allowTextEntry", "html", "show", "delete" }) do
        view[m] = function() end
    end
    -- It floats over the tiles at a window level of its own.
    function view.level(_, l)
        view.level_ = l
    end
    _G.hs.drawing = { windowLevels = { floating = 3 } }
    -- The Displays page watches the displays.
    _G.hs.screen = {
        watcher = { new = function() return { start = function() end } end },
        allScreens = function() return {} end,
        primaryScreen = function() end,
    }
    function view.navigationCallback(_, fn)
        view.nav = fn
    end
    function view.windowCallback() end
    function view.hswindow()
        return nil
    end
    function view.evaluateJavaScript(_, js)
        if js:find("tide.update(", 1, true) == 1 then
            pushed = pushed + 1
        end
    end
    _G.hs.inspect = tostring
    _G.hs.webview = {
        new = function()
            return view
        end,
        usercontent = {
            new = function()
                return { setCallback = function() end }
            end,
        },
    }
    tide.wm.screen_by_uuid = function()
        return { area = { x = 0, y = 0, w = 1000, h = 800 } }
    end
    tide.wm.current_screen = function()
        return "s"
    end
    -- The Bluetooth page reads through blueutil, which isn't here.
    tide.adapter.exists = function()
        return false
    end
    package.loaded["tide.settings_hs"] = nil
    local settings = require("tide.settings_hs").new(tide)
    settings.show("floating")
    view.nav("didFinishNavigation")
    t.eq(pushed, 1)
    t.eq(view.level_, 3, "at the floating level")
    settings.show("floating")
    t.eq(pushed, 2, "no fill, but Floating now is redrawn")
end)

t.done("floating_hs")
