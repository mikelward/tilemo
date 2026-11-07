-- Caps Lock as Compose, as on Linux (SPEC.md §10): Compose, then a few
-- keys, types a character, such as ' and e for é, from the same table
-- Linux's Compose key reads (compose.tsv). setup-macos makes Caps Lock send
-- F18, which tide takes as Compose. Pure Lua.

local M = {}
M.__index = M

-- compose.tsv's text: lines of KEYS, a tab, and what they type. A line
-- with no tab is a comment; "#" can't mark one, since # starts sequences.
function M.parse(text)
    local table_ = { full = {}, prefix = {} }
    for line in text:gmatch("[^\n]+") do
        local keys, out = line:match("^([^\t]+)\t(.+)$")
        if keys then
            table_.full[keys] = out
            for i = 1, #keys - 1 do
                table_.prefix[keys:sub(1, i)] = true
            end
        end
    end
    return table_
end

-- start()'s `compose`: true or nil for on, false for off.
function M.check(v)
    if v ~= nil and type(v) ~= "boolean" then
        error("compose must be true or false, not " .. tostring(v), 3)
    end
end

function M.new(table_)
    return setmetatable({ table = table_, typed = nil }, M)
end

-- Compose was pressed: what follows is a sequence.
function M:start()
    self.typed = ""
end

function M:active()
    return self.typed ~= nil
end

-- A key typed while composing, as the character it would type. Gives
-- "more" while it's the start of a sequence, "done" and the character once
-- it's a whole one, or "none" once it can't be, as Linux drops a sequence
-- it doesn't know. Either of the last two ends composing.
function M:key(char)
    if not self.typed then
        return "none"
    end
    local typed = self.typed .. char
    local out = self.table.full[typed]
    if out then
        self.typed = nil
        return "done", out
    end
    if self.table.prefix[typed] then
        self.typed = typed
        return "more"
    end
    self.typed = nil
    return "none"
end

-- Esc, a click, or a key that types nothing: give up.
function M:cancel()
    self.typed = nil
end

return M
