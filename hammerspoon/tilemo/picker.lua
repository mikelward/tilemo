-- tide's picker on Super+C (tide SPEC.md §8.4, SPEC.md §7.2): a Clipboard
-- tab of what you've copied and a Characters tab of emoji and symbols found
-- by name. The history, its rows and the character search, in plain Lua;
-- picker_hs.lua watches the pasteboard and draws it with hs.chooser.

local launcher = require("tilemo.launcher")

local M = {}

M.TABS = { "clipboard", "characters" }
M.TAB_NAMES = { clipboard = "Clipboard", characters = "Characters" }
M.PLACEHOLDERS = {
    clipboard = "Clipboard: what you've copied (Tab: Characters)",
    characters = "Characters: by name, as arrow, e acute, shrug (Tab: Clipboard)",
}

-- The newest this many copies are kept, as tide keeps (SPEC.md §7.2).
M.MAX_ITEMS = 200
-- At most this many character rows, so one letter doesn't fill the chooser
-- with thousands.
M.CHARACTER_LIMIT = 200
-- A copy longer than this isn't kept: the history is in memory.
M.MAX_BYTES = 1000000

-- The pasteboard types an app sets on a copy that clipboard managers should
-- leave alone (nspasteboard.org's convention): concealed for a password,
-- as Bitwarden's desktop app sets through arboard 3.6.1, and transient for
-- one that's only passing through.
M.SKIP_TYPES = {
    ["org.nspasteboard.ConcealedType"] = true,
    ["org.nspasteboard.TransientType"] = true,
}

local function check_tab(tab)
    for _, t in ipairs(M.TABS) do
        if t == tab then
            return
        end
    end
    error("tilemo: not a picker tab: " .. tostring(tab), 3)
end

-- The tab after `tab`, or before it when `back`, round in a circle.
function M.next_tab(tab, back)
    check_tab(tab)
    return tab == "clipboard" and "characters" or "clipboard"
end

-- Whether to keep a copy whose pasteboard types are `types` (a list of
-- UTIs, or nil when they couldn't be read). Unread types aren't kept, in
-- case it's a password.
function M.keep(types)
    if type(types) ~= "table" then
        return false
    end
    for _, t in ipairs(types) do
        if M.SKIP_TYPES[t] then
            return false
        end
    end
    return true
end

-- A new, empty history.
function M.history()
    return { items = {} }
end

-- Adds `text` as the newest entry of `history`: a repeat moves to the top
-- rather than being kept twice, and the oldest go past MAX_ITEMS. Empty or
-- blank text, or text over MAX_BYTES, isn't kept. Returns whether it was.
function M.add(history, text)
    if type(text) ~= "string" or not text:find("%S") or #text > M.MAX_BYTES then
        return false
    end
    for i, item in ipairs(history.items) do
        if item == text then
            table.remove(history.items, i)
            break
        end
    end
    table.insert(history.items, 1, text)
    while #history.items > M.MAX_ITEMS do
        table.remove(history.items)
    end
    return true
end

-- Forgets the entry `text`.
function M.forget(history, text)
    for i, item in ipairs(history.items) do
        if item == text then
            table.remove(history.items, i)
            return true
        end
    end
    return false
end

-- One line for a copy: its whitespace folded, cut to `width` characters.
function M.preview(text, width)
    width = width or 100
    local line = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if utf8.len(line) and utf8.len(line) > width then
        line = line:sub(1, utf8.offset(line, width + 1) - 1) .. "…"
    end
    return line
end

-- What kind of copy `text` is, for its row's second line.
function M.kind(text)
    if text:match("^%s*[%a][%w+.%-]*://%S+%s*$") then
        return "Link"
    end
    return "Text"
end

-- The Clipboard tab's rows, newest first, or best match first for a query
-- (launcher.score, the switcher's), newest first among equals. The query
-- is matched against the whole copy, its whitespace folded, not just the
-- line shown. Each row is { text, preview, sub }.
function M.history_rows(history, query)
    local q = query or ""
    local rows = {}
    for order, text in ipairs(history.items) do
        local preview = M.preview(text)
        local score = launcher.score(q, (text:gsub("%s+", " ")))
        if score then
            rows[#rows + 1] = { text = text, preview = preview, sub = M.kind(text), score = score, order = order }
        end
    end
    if q:find("%S") then
        table.sort(rows, function(a, b)
            if a.score ~= b.score then
                return a.score > b.score
            end
            return a.order < b.order
        end)
    end
    return rows
end

-- A name's words, lowercase: what a typed word has to start.
function M.words(text)
    local out = {}
    for w in (text or ""):lower():gmatch("[%a%d]+") do
        out[#out + 1] = w
    end
    return out
end

-- The character list, tide's shell/chars/chars.tsv: CHARACTER, NAME and
-- GROUP per line, tab-separated, after `#` comments. A comment has no tab,
-- so the keycap #️⃣, whose character starts with `#`, is still a row.
-- Returns the list and the malformed lines it left out, by number.
function M.parse_chars(text)
    local chars, errors = {}, {}
    local n = 0
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line ~= "" and not (line:sub(1, 1) == "#" and not line:find("\t", 1, true)) then
            local char, name, group = line:match("^([^\t]+)\t([^\t]+)\t([^\t]*)$")
            if char then
                chars[#chars + 1] = { char = char, name = name, group = group, words = M.words(name), order = #chars + 1 }
            else
                errors[#errors + 1] = n
            end
        end
    end
    return chars, errors
end

-- How `c` matches the query's words: each must start a word of the name,
-- in any order. Returns how many are whole words, or nil.
local function match_char(c, query_words)
    local exact = 0
    for _, q in ipairs(query_words) do
        local found, whole = false, false
        for _, w in ipairs(c.words) do
            if w == q then
                found, whole = true, true
                break
            elseif w:sub(1, #q) == q then
                found = true
            end
        end
        if not found then
            return nil
        end
        if whole then
            exact = exact + 1
        end
    end
    return exact
end

-- The Characters tab's rows: whole-word matches first, then the list's
-- order, at most `limit`. With no query, the list from the top.
function M.character_rows(chars, query, limit)
    limit = limit or M.CHARACTER_LIMIT
    local q = M.words(query)
    local found = {}
    for _, c in ipairs(chars) do
        if #q == 0 then
            found[#found + 1] = { c = c, exact = 0 }
        else
            local exact = match_char(c, q)
            if exact then
                found[#found + 1] = { c = c, exact = exact }
            end
        end
        if #q == 0 and #found >= limit then
            break
        end
    end
    table.sort(found, function(a, b)
        if a.exact ~= b.exact then
            return a.exact > b.exact
        end
        return a.c.order < b.c.order
    end)
    local out = {}
    for i = 1, math.min(limit, #found) do
        out[i] = found[i].c
    end
    return out
end

-- "U+00E9" for a character that is one code point, ignoring the emoji
-- variation selector; nil for a sequence.
function M.code_point(char)
    local cps = {}
    for _, cp in utf8.codes(char) do
        if cp ~= 0xFE0F then
            cps[#cps + 1] = cp
        end
    end
    if #cps ~= 1 then
        return nil
    end
    return string.format("U+%04X", cps[1])
end

-- A character row's second line: its group, and its code point if it has
-- one.
function M.character_sub(c)
    local cp = M.code_point(c.char)
    return cp and (c.group .. " · " .. cp) or c.group
end

-- What an empty tab says.
function M.empty_text(tab, query, err)
    check_tab(tab)
    if err then
        return err
    end
    if (query or ""):find("%S") then
        return "Nothing matches"
    end
    return tab == "clipboard" and "Nothing copied since tilemo started" or "No characters"
end

return M
