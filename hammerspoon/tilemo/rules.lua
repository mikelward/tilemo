-- Which windows tile, float or are left alone (SPEC.md §5.1). Each new
-- window is decided once, from facts the adapter reads through
-- Accessibility, and the first rule that matches wins.

local M = {}

-- Rules that ship with tilemo, after the user's own. `app` is a bundle ID and
-- `title` a Lua pattern; either may be left out to match anything.
M.defaults = {
    -- Picture-in-picture stays on every workspace, untiled (SPEC.md §5.5).
    { title = "^Picture in Picture$", action = "ignore" },
    { title = "^Picture%-in%-Picture$", action = "ignore" },
    -- Hammerspoon's console and preferences float; the rest of its windows
    -- are tilemo's own (the launcher, the dashboard), placed by tilemo, so
    -- they're left alone.
    { app = "org.hammerspoon.Hammerspoon", title = "^Hammerspoon Console$", action = "float" },
    { app = "org.hammerspoon.Hammerspoon", title = "^Hammerspoon Preferences$", action = "float" },
    { app = "org.hammerspoon.Hammerspoon", action = "ignore" },
    -- System Settings is a fixed width, though its height can change, so a
    -- tile would leave a gap beside it.
    { app = "com.apple.systempreferences", action = "float" },
}

M.actions = { tile = true, float = true, ignore = true }

local function matches(rule, facts)
    if rule.app and rule.app ~= facts.app then
        return false
    end
    if rule.title and not (facts.title or ""):find(rule.title) then
        return false
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
            local ok, err = pcall(string.find, "", r.title)
            if not ok then
                error(string.format("%s[%d].title is not a valid pattern: %s", what, i, err), 2)
            end
        end
    end
    return rules
end

local FLOATING_SUBROLES = {
    AXDialog = true,
    AXSystemDialog = true,
    AXFloatingWindow = true,
}

-- "tile", "float" or "ignore", for a window described by `facts`:
-- role, subrole, app, title, size_settable, modal.
function M.decide(facts, user)
    -- 1. Not a window: sheets, popovers and menus are left alone.
    if facts.role ~= "AXWindow" then
        return "ignore"
    end
    -- 2. Rules, the user's first, so a misbehaving app can always be fixed.
    for _, list in ipairs({ user or {}, M.defaults }) do
        for _, r in ipairs(list) do
            if matches(r, facts) then
                return r.action
            end
        end
    end
    -- 3. A window whose size can't be changed floats.
    if facts.size_settable == false then
        return "float"
    end
    -- 4. A modal window floats.
    if facts.modal then
        return "float"
    end
    -- 5. Dialogs and panels float.
    if FLOATING_SUBROLES[facts.subrole] then
        return "float"
    end
    -- 6. Standard windows tile. Late on purpose: some dialogs report
    -- themselves as standard windows, and the checks above catch them.
    if facts.subrole == "AXStandardWindow" then
        return "tile"
    end
    -- 7. Anything else, such as AXUnknown, is left alone: extension popups
    -- and other odd windows mustn't take a tile.
    return "ignore"
end

return M
