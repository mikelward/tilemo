-- Which windows tile, float or are left alone (SPEC.md §5.1). Each new
-- window is decided once, from facts the adapter reads through
-- Accessibility, and the first rule that matches wins; a tile whose title
-- changes as it opens is decided again (wm.retitled).

local M = {}

-- Hammerspoon's own windows, by title: they float. Its others are tide's
-- (the bar, the launcher, the settings window), which tide places itself.
M.HAMMERSPOON = "org.hammerspoon.Hammerspoon"
M.HAMMERSPOON_OWN = { "^Hammerspoon Console$", "^Hammerspoon Preferences$" }

-- Whether a window of Hammerspoon's, titled `title`, is one of tide's.
function M.tides(title)
    for _, p in ipairs(M.HAMMERSPOON_OWN) do
        if (title or ""):match(p) then
            return false
        end
    end
    return true
end

-- Rules that ship with tide, after the user's own. `app` is a bundle ID and
-- `title` a Lua pattern; either may be left out to match anything.
M.defaults = {
    -- Picture-in-picture stays on every workspace, untiled (SPEC.md §5.5).
    { title = "^Picture in Picture$", action = "ignore" },
    { title = "^Picture%-in%-Picture$", action = "ignore" },
    -- Hammerspoon's console and preferences float; the rest of its windows
    -- are tide's own (the launcher, the dashboard), placed by tide, so
    -- they're left alone. The window filters don't watch Hammerspoon now
    -- (hs_adapter), so these only decide a window found some other way.
    { app = M.HAMMERSPOON, title = M.HAMMERSPOON_OWN[1], action = "float" },
    { app = M.HAMMERSPOON, title = M.HAMMERSPOON_OWN[2], action = "float" },
    { app = M.HAMMERSPOON, action = "ignore" },
    -- System Settings is a fixed width, though its height can change, so a
    -- tile would leave a gap beside it.
    { app = "com.apple.systempreferences", action = "float" },
    -- Bitwarden's extension asks you to sign in, fill or use a passkey in a
    -- popup window of the browser, showing its own page, titled
    -- "Bitwarden". The vault's own tab, and the desktop app, are titled
    -- otherwise or are another app.
    { app = "com.google.Chrome", title = "^Bitwarden$", action = "float" },
    { app = "com.brave.Browser", title = "^Bitwarden$", action = "float" },
    -- Notification Center's banners, alerts and widgets are macOS's own,
    -- over every window: floated, one would be moved to the middle of the
    -- display, and focus follows mouse would focus it.
    { app = "com.apple.notificationcenterui", action = "ignore" },
}

M.actions = { tile = true, float = true, ignore = true }

local FLOATING_SUBROLES = {
    AXDialog = true,
    AXSystemDialog = true,
    AXFloatingWindow = true,
}

-- Lua reports a malformed pattern only when a match reaches the bad part,
-- so `^Save[` passes a trial match against "" and fails on a title that
-- starts "Save". This walks the whole pattern as lstrlib.c reads it, and
-- gives why it's malformed, or nil.
local MAXCAPTURES = 32

-- The end of the set that starts at `i` (just after its "["), or nil.
local function set_end(p, i)
    if p:sub(i, i) == "^" then
        i = i + 1
    end
    -- A "]" first is one of the set's characters.
    repeat
        if i > #p then
            return nil
        end
        local c = p:sub(i, i)
        i = i + 1
        if c == "%" then
            if i > #p then
                return nil
            end
            i = i + 1
        end
    until p:sub(i, i) == "]"
    return i
end

function M.pattern_problem(p)
    if type(p) ~= "string" then
        return "isn't text"
    end
    local open = {} -- the captures still open, by number
    local n = 0     -- captures begun
    local i = 1
    if p:sub(1, 1) == "^" then
        i = 2
    end
    while i <= #p do
        local c = p:sub(i, i)
        local single = true
        if c == "(" then
            n = n + 1
            if n > MAXCAPTURES then
                return "has more than " .. MAXCAPTURES .. " captures"
            end
            open[#open + 1] = n
            i = i + 1
            single = false
        elseif c == ")" then
            if #open == 0 then
                return "has a ) with no ( before it"
            end
            open[#open] = nil
            i = i + 1
            single = false
        elseif c == "$" and i == #p then
            i = i + 1
            single = false
        elseif c == "%" then
            local d = p:sub(i + 1, i + 1)
            if d == "" then
                return "ends with %"
            elseif d == "b" then
                if #p < i + 3 then
                    return "has a %b without two characters after it"
                end
                i = i + 4
                single = false
            elseif d == "f" then
                if p:sub(i + 2, i + 2) ~= "[" then
                    return "has a %f without a [set] after it"
                end
                local e = set_end(p, i + 3)
                if not e then
                    return "has a [ with no ] to end it"
                end
                i = e + 1
                single = false
            elseif d:match("%d") then
                local k = tonumber(d)
                local closed = k >= 1 and k <= n
                for _, o in ipairs(open) do
                    closed = closed and o ~= k
                end
                if not closed then
                    return "has %" .. d .. ", which names no capture closed before it"
                end
                i = i + 2
                single = false
            else
                i = i + 2
            end
        elseif c == "[" then
            local e = set_end(p, i + 1)
            if not e then
                return "has a [ with no ] to end it"
            end
            i = e + 1
        else
            i = i + 1
        end
        -- A repeat after a single character class is part of it.
        if single and p:sub(i, i):match("^[%*%+%-%?]$") then
            i = i + 1
        end
    end
    if #open > 0 then
        return "has a ( with no ) to end it"
    end
end

-- Rules that failed to match are said once each, through M.report, which
-- the window manager points at its log.
M.report = function() end
local reported = {}

local function matches(rule, facts)
    if rule.app and rule.app ~= facts.app then
        return false
    end
    if rule.title then
        -- One bad pattern, from a hand-edited file say, mustn't stop every
        -- window being decided: it matches nothing, and the log names it.
        local ok, hit = pcall(string.find, facts.title or "", rule.title)
        if not ok then
            if not reported[rule.title] then
                reported[rule.title] = true
                M.report(string.format("the float rule for %s, title %q, is skipped: %s",
                    tostring(rule.app or "any app"), rule.title, tostring(hit)))
            end
            return false
        end
        if not hit then
            return false
        end
    end
    return true
end

-- A rule list is checked when settings load, so a typo is an error naming
-- the rule, not a window that tiles by surprise (tide AGENTS.md).
function M.check(rules, what)
    what = what or "rules"
    for i, r in ipairs(rules or {}) do
        if type(r) ~= "table" then
            error(string.format("%s[%d] is not a table", what, i), 2)
        end
        for k in pairs(r) do
            if k ~= "app" and k ~= "title" and k ~= "action" then
                error(string.format("%s[%d].%s is not an option", what, i, tostring(k)), 2)
            end
        end
        if not M.actions[r.action] then
            error(string.format("%s[%d].action must be tile, float or ignore", what, i), 2)
        end
        if r.title then
            local why = M.pattern_problem(r.title)
            if why then
                error(string.format("%s[%d].title is not a valid pattern: it %s", what, i, why), 2)
            end
        end
    end
    return rules
end

-- The first rule in `list` that matches `facts`, and its place, or nil.
function M.first(list, facts)
    for i, r in ipairs(list or {}) do
        if matches(r, facts) then
            return r, i
        end
    end
end

-- Why a window that no rule names floats or is left alone: the step of
-- M.decide's that says so, as a short phrase, or nil for one that tiles.
M.STEPS = {
    accessory = "it's part of its app's interface: no close button, from an app out of the Dock",
    fixed = "its size can't be changed",
    modal = "it's modal",
    subrole = "macOS reports it as a dialog or panel",
    other = "it isn't a standard window",
}

-- The step after the rules (3 to 8 below): the action, and its M.STEPS key.
function M.step(facts)
    -- 3. A window with no close button from an app that stays out of the
    -- Dock is part of that app's interface, not a window: Control Center's
    -- and menu bar apps' panels, Spotlight, the input source switcher
    -- (AeroSpace's isWindowHeuristic).
    if facts.accessory and facts.closable == false then
        return "ignore", "accessory"
    end
    -- 4. A standard window whose size can't be changed floats: a fixed-size
    -- dialog that reports itself standard. Other subroles go on to the
    -- checks below, so a fixed-size popup, such as Chrome's find bar or a
    -- tooltip (AXUnknown), is left alone rather than floated, centered and
    -- focused.
    if facts.size_settable == false and facts.subrole == "AXStandardWindow" then
        return "float", "fixed"
    end
    -- 5. A modal window floats.
    if facts.modal then
        return "float", "modal"
    end
    -- 6. Dialogs and panels float.
    if FLOATING_SUBROLES[facts.subrole] then
        return "float", "subrole"
    end
    -- 7. Standard windows tile. Late on purpose: some dialogs report
    -- themselves as standard windows, and the checks above catch them.
    if facts.subrole == "AXStandardWindow" then
        return "tile"
    end
    -- 8. Anything else, such as AXUnknown, is left alone: extension popups
    -- and other odd windows mustn't take a tile.
    return "ignore", "other"
end

-- "tile", "float" or "ignore", for a window described by `facts`:
-- role, subrole, app, title, size_settable, modal, and accessory and
-- closable (whether its app stays out of the Dock, and whether the window
-- has a close button; nil when unknown).
function M.decide(facts, user)
    -- 1. Not a window: sheets, popovers and menus are left alone.
    if facts.role ~= "AXWindow" then
        return "ignore"
    end
    -- 2. Rules, the user's first, so a misbehaving app can always be fixed.
    local r = M.first(user, facts) or M.first(M.defaults, facts)
    if r then
        return r.action
    end
    return (M.step(facts))
end

return M
