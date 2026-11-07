-- Caps Lock as Compose on Hammerspoon (SPEC.md §10): F18, which
-- setup-macos makes Caps Lock send, starts a sequence; the keys after it
-- are held back from the app in front while compose.lua reads them, and
-- the character is typed once the sequence is whole. Esc, a click, or a
-- key with Command or Control gives up. What it decides is compose.lua's.
-- Not runnable outside Hammerspoon.

local compose = require("tide.compose")

local M = {}

-- compose.tsv sits beside this file, installed or not.
local function here()
    local src = debug.getinfo(1, "S").source
    return (src:match("^@(.*)/[^/]*$") or ".")
end

-- `log` says what went wrong, with context.
function M.new(hs, log)
    local path = here() .. "/compose.tsv"
    local f, err = io.open(path, "rb")
    if not f then
        log("compose: couldn't read " .. path .. ": " .. tostring(err))
        return nil
    end
    local c = compose.new(compose.parse(f:read("a")))
    f:close()

    local t = hs.eventtap.event.types
    local tap
    local function stop()
        c:cancel()
        if tap then
            tap:stop()
        end
    end
    tap = hs.eventtap.new({ t.keyDown, t.leftMouseDown, t.rightMouseDown, t.otherMouseDown }, function(e)
        if not c:active() then
            tap:stop()
            return false
        end
        if e:getType() ~= t.keyDown then
            stop()
            return false
        end
        local flags = e:getFlags()
        local key = hs.keycodes.map[e:getKeyCode()]
        if key == "escape" or flags.cmd or flags.ctrl then
            stop()
            return key == "escape"
        end
        -- Shift, and the keyboard's layout, already applied.
        local char = e:getCharacters()
        if not char or char == "" or #char > 1 then
            stop()
            return true
        end
        local status, out = c:key(char)
        if status ~= "more" then
            tap:stop()
        end
        if status == "done" then
            -- Typed once this key's event is done with, so the two can't
            -- cross.
            hs.timer.doAfter(0, function()
                hs.eventtap.keyStrokes(out)
            end)
        end
        return true
    end)

    local hotkey = hs.hotkey.bind({}, "f18", function()
        c:start()
        tap:start()
    end)
    return {
        stop = function()
            stop()
            hotkey:delete()
        end,
    }
end

return M
