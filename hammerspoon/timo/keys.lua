-- tide's key map (SPEC.md §7.2), and which modifiers stand for Super.
--
-- With Karabiner's rule loaded, physical Win+key arrives as
-- Ctrl+Option+Command+key, so Option keeps its text gestures. Without it,
-- Super falls back to plain Option: every key still works, but Option's own
-- meanings (word delete, word moves, accents) go to timo (SPEC.md §7.1).

local M = {}

M.KARABINER = { "ctrl", "alt", "cmd" }
M.OPTION = { "alt" }

-- Each binding: Super plus `key`, with Shift if `shift`, calling the
-- window manager's `action` with `arg`. `repeating` keys repeat while held.
M.map = {
    { key = "j", action = "focus", arg = 1 },
    { key = "k", action = "focus", arg = -1 },
    { key = "j", shift = true, action = "move", arg = 1 },
    { key = "k", shift = true, action = "move", arg = -1 },
    { key = "return", action = "swap_master" },
    { key = "\\", action = "mfact", arg = 1, repeating = true },
    { key = "/", action = "mfact", arg = -1, repeating = true },
    { key = "=", action = "nmaster", arg = 1 },
    { key = "-", action = "nmaster", arg = -1 },
    { key = ".", action = "cycle", arg = 1 },
    { key = ",", action = "cycle", arg = -1 },
    { key = "`", action = "monocle" },
    { key = "o", action = "monocle" },
    { key = "up", action = "maximize" },
    { key = "up", shift = true, action = "fullscreen" },
    { key = "down", action = "restore" },
    { key = "f", shift = true, action = "toggle_float" },
    -- A PC keyboard's Insert arrives as the Mac's Help key.
    { key = "help", action = "toggle_float" },
    { key = "delete", action = "close" },
}

-- The modifier list for one binding.
function M.mods(super, binding)
    local out = {}
    for _, m in ipairs(super) do
        out[#out + 1] = m
    end
    if binding.shift then
        out[#out + 1] = "shift"
    end
    return out
end

-- Whether the selected Karabiner profile has timo's rule. Each profile keeps
-- its own rules, so a rule left in another profile doesn't count.
local function profile_has_rule(config)
    for _, p in ipairs(type(config) == "table" and config.profiles or {}) do
        if p.selected then
            local cm = p.complex_modifications or {}
            for _, r in ipairs(cm.rules or {}) do
                if type(r.description) == "string" and r.description:find("^timo:") then
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- Whether Karabiner is running with timo's rule loaded. `read` returns a
-- file's text or nil, `decode` turns JSON into a table or nil, and
-- `running` says whether a process name is live; all come from the adapter,
-- so this tests without a Mac.
function M.karabiner_ready(read, running, home, decode)
    local text = read(home .. "/.config/karabiner/karabiner.json")
    if not text or not profile_has_rule(decode(text)) then
        return false
    end
    -- The service's process name changed in Karabiner-Elements 15
    -- (unverified); either counts.
    return running("Karabiner-Core-Service") or running("karabiner_grabber")
end

function M.super(read, running, home, decode)
    if M.karabiner_ready(read, running, home, decode) then
        return M.KARABINER, true
    end
    return M.OPTION, false
end

-- What the fallback costs, said once when timo starts without Karabiner.
M.FALLBACK_NOTICE = "Karabiner isn't running with timo's rules, so timo's keys"
    .. " are on Option. Option+Backspace, Option+arrows and Option accents"
    .. " now belong to timo. Install conf's Karabiner rules to get them back."

return M
