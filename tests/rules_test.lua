local t = require("t")
local rules = require("tide.rules")

local function std(extra)
    local f = { role = "AXWindow", subrole = "AXStandardWindow", app = "com.example.app", title = "Doc" }
    for k, v in pairs(extra or {}) do
        f[k] = v
    end
    return f
end

t.test("an ordinary window tiles", function()
    t.eq(rules.decide(std()), "tile")
end)

t.test("anything that isn't an AXWindow is left alone", function()
    t.eq(rules.decide(std({ role = "AXSheet" })), "ignore")
    t.eq(rules.decide(std({ role = "AXPopover" })), "ignore")
end)

t.test("a fixed-size standard window floats", function()
    t.eq(rules.decide(std({ size_settable = false })), "float")
end)

-- Chrome's find bar, tooltips and hover cards are windows of their own,
-- AXUnknown and a fixed size: floated, each would be moved to the middle of
-- Chrome's window, and focus follows mouse would focus it.
t.test("a fixed-size popup that isn't a standard window is left alone", function()
    t.eq(rules.decide(std({ app = "com.google.Chrome", subrole = "AXUnknown", size_settable = false })), "ignore")
    local f = std({ size_settable = false })
    f.subrole = nil
    t.eq(rules.decide(f), "ignore", "no subrole")
    t.eq(rules.decide(std({ subrole = "AXDialog", size_settable = false })), "float", "a fixed-size dialog still floats")
end)

-- Its sign-in, autofill and passkey prompts open as a popup window of the
-- browser, showing the extension's own page, titled "Bitwarden".
t.test("Bitwarden's pop-outs in Chrome and Brave float, and nothing else of theirs", function()
    t.eq(rules.decide(std({ app = "com.google.Chrome", title = "Bitwarden" })), "float")
    t.eq(rules.decide(std({ app = "com.brave.Browser", title = "Bitwarden" })), "float")
    t.eq(rules.decide(std({ app = "com.google.Chrome", title = "Vaults | Bitwarden Web vault" })), "tile",
        "the web vault's tab")
    t.eq(rules.decide(std({ app = "com.bitwarden.desktop", title = "Bitwarden" })), "tile", "the desktop app")
end)

t.test("Notification Center's windows are left alone, whatever they report", function()
    for _, f in ipairs({
        std({ app = "com.apple.notificationcenterui", title = "Notification Center", size_settable = false }),
        std({ app = "com.apple.notificationcenterui", subrole = "AXSystemDialog" }),
        std({ app = "com.apple.notificationcenterui" }),
    }) do
        t.eq(rules.decide(f), "ignore", f.subrole)
    end
end)

-- AeroSpace's isWindowHeuristic: Control Center's and a menu bar app's
-- panels, Spotlight, the input source switcher.
t.test("a window with no close button from an app outside the Dock is left alone", function()
    t.eq(rules.decide(std({ app = "com.apple.controlcenter", accessory = true, closable = false })), "ignore")
    t.eq(rules.decide(std({ subrole = "AXDialog", accessory = true, closable = false })), "ignore", "a panel")
    t.eq(rules.decide(std({ accessory = true, closable = true })), "tile", "a menu bar app's own window")
    t.eq(rules.decide(std({ accessory = false, closable = false })), "tile", "an app in the Dock")
    t.eq(rules.decide(std({ accessory = true })), "tile", "close button unknown")
    t.eq(rules.decide(std({ accessory = true, closable = false }), { { app = "com.example.app", action = "float" } }),
        "float", "a user rule still wins")
end)

t.test("an unknown settable size counts as settable", function()
    t.eq(rules.decide(std({ size_settable = nil })), "tile")
end)

t.test("a modal standard window floats", function()
    t.eq(rules.decide(std({ modal = true })), "float")
end)

t.test("dialogs and panels float", function()
    for _, sr in ipairs({ "AXDialog", "AXSystemDialog", "AXFloatingWindow" }) do
        t.eq(rules.decide(std({ subrole = sr })), "float", sr)
    end
end)

t.test("user rules come first, by app and title", function()
    local user = { { app = "com.example.app", title = "^Prefs", action = "float" } }
    t.eq(rules.decide(std({ title = "Prefs" }), user), "float")
    t.eq(rules.decide(std(), user), "tile")
    t.eq(rules.decide(std({ subrole = "AXDialog" }), { { app = "com.example.app", action = "tile" } }), "tile",
        "a rule can tile a dialog")
end)

t.test("picture-in-picture is left alone", function()
    t.eq(rules.decide(std({ title = "Picture in Picture" })), "ignore")
end)

t.test("a bad rule is an error that names it", function()
    local ok, err = pcall(rules.check, { { app = "x", action = "flaot" } }, "rules")
    t.eq(ok, false)
    t.eq(err:find("rules%[1%]%.action") ~= nil, true, err)
    ok, err = pcall(rules.check, { { titel = "x", action = "float" } }, "rules")
    t.eq(err:find("titel is not an option") ~= nil, true, err)
    ok, err = pcall(rules.check, { { title = "[", action = "float" } }, "rules")
    t.eq(err:find("not a valid pattern") ~= nil, true, err)
end)

t.test("a window with no known subrole is left alone", function()
    t.eq(rules.decide(std({ subrole = "AXUnknown" })), "ignore")
    local f = std()
    f.subrole = nil
    t.eq(rules.decide(f), "ignore")
end)

t.test("Hammerspoon's console floats, and tide's own windows are left alone", function()
    local hs = { role = "AXWindow", subrole = "AXStandardWindow", app = "org.hammerspoon.Hammerspoon" }
    hs.title = "Hammerspoon Console"
    t.eq(rules.decide(hs), "float")
    hs.title = "tide dashboard"
    t.eq(rules.decide(hs), "ignore")
    hs.title = ""
    t.eq(rules.decide(hs), "ignore")
end)

-- Its window is a fixed width, though its height can change, so a tile
-- would leave a gap beside it.
t.test("System Settings floats, though its size is settable", function()
    t.eq(rules.decide(std({ app = "com.apple.systempreferences", title = "Mouse", size_settable = true })), "float")
end)

t.test("a user rule can still tile System Settings", function()
    local user = { { app = "com.apple.systempreferences", action = "tile" } }
    t.eq(rules.decide(std({ app = "com.apple.systempreferences" }), user), "tile")
end)


-- Lua says a pattern is malformed only when a match reaches the bad part,
-- so a trial match against "" passes "^Save[" (Codex on #76).
t.test("a title pattern is checked whole, not by one trial match", function()
    for p, why in pairs({
        ["^Save["] = "has a [ with no ] to end it",
        ["Save%"] = "ends with %",
        ["%"] = "ends with %",
        ["a%b("] = "has a %b without two characters after it",
        ["a%fx"] = "has a %f without a [set] after it",
        ["a%f[x"] = "has a [ with no ] to end it",
        ["a(b"] = "has a ( with no ) to end it",
        ["a)b"] = "has a ) with no ( before it",
        ["(a%1)"] = "has %1, which names no capture closed before it",
        ["a%0"] = "has %0, which names no capture closed before it",
        ["[%"] = "has a [ with no ] to end it",
    }) do
        t.eq(rules.pattern_problem(p), why, p)
        local ok = pcall(rules.check, { { title = p, action = "float" } })
        t.eq(ok, false, "start()'s rules refuse " .. p)
    end
    for _, p in ipairs({ "^Save", "^Save As%.%.%.$", "[]]", "[^]a]", "%b()", "%f[%w]x", "(a)%1", "()", "a$b",
        "x^", "a-*", "[a-z]+", "%%", "%[", "" }) do
        t.eq(rules.pattern_problem(p), nil, p)
    end
end)

-- The check's one promise, tried on many patterns: what it passes, Lua can
-- match against any title without an error.
t.test("no pattern the check passes errors when matched", function()
    local alphabet = { "a", "b", "^", "$", "(", ")", "%", "[", "]", "f", "1", "-", "*", "+", "?", ".", " " }
    local titles = { "", "a", "ab", "aab", "ba", "a b", "(a)", "[a]", "%", "ab1", "a-b*c" }
    math.randomseed(76)
    for _ = 1, 20000 do
        local parts = {}
        for i = 1, math.random(1, 8) do
            parts[i] = alphabet[math.random(#alphabet)]
        end
        local p = table.concat(parts)
        if not rules.pattern_problem(p) then
            for _, title in ipairs({ p, table.unpack(titles) }) do
                local ok, err = pcall(string.find, title, p)
                if not ok then
                    error(string.format("%q passed, but matching %q: %s", p, title, err))
                end
            end
        end
    end
end)

t.test("a bad pattern that reaches decide is skipped and logged, and the window decided", function()
    local said = {}
    rules.report = function(msg)
        said[#said + 1] = msg
    end
    local bad = { { app = "com.example.app", title = "^Doc[", action = "float" } }
    t.eq(rules.decide(std({ title = "Doc" }), bad), "tile")
    t.eq(rules.decide(std({ title = "Doc" }), bad), "tile")
    t.eq(#said, 1, "said once")
    t.eq(said[1]:find('com.example.app, title "^Doc["', 1, true) ~= nil, true, said[1])
    rules.report = function() end
end)

t.done("rules")
