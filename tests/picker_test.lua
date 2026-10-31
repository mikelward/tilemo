local t = require("t")
local picker = require("tilemo.picker")

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("a")
    f:close()
    return s
end

t.test("two tabs, Clipboard first, and Tab goes round them", function()
    t.eq(picker.TABS, { "clipboard", "characters" })
    t.eq(picker.next_tab("clipboard"), "characters")
    t.eq(picker.next_tab("characters"), "clipboard")
    t.eq(picker.next_tab("clipboard", true), "characters")
    t.eq(pcall(picker.next_tab, "apps"), false)
end)

t.test("a copy marked concealed or transient is never kept", function()
    t.eq(picker.keep({ "public.utf8-plain-text" }), true)
    t.eq(picker.keep({ "public.utf8-plain-text", "org.nspasteboard.ConcealedType" }), false)
    t.eq(picker.keep({ "org.nspasteboard.TransientType", "public.utf8-plain-text" }), false)
    t.eq(picker.keep(nil), false, "types that can't be read")
end)

t.test("the history keeps the newest first, moves a repeat up, and keeps 200", function()
    local h = picker.history()
    t.eq(picker.add(h, "one"), true)
    picker.add(h, "two")
    picker.add(h, "one")
    t.eq(h.items, { "one", "two" })
    t.eq(picker.add(h, "  \n"), false, "blank")
    t.eq(picker.add(h, nil), false, "no text")
    t.eq(picker.add(h, string.rep("x", picker.MAX_BYTES + 1)), false, "too big")
    for i = 1, 250 do
        picker.add(h, "copy " .. i)
    end
    t.eq(#h.items, picker.MAX_ITEMS)
    t.eq(h.items[1], "copy 250")
    t.eq(h.items[picker.MAX_ITEMS], "copy 51")
end)

t.test("a query finds text past what the row shows", function()
    local h = picker.history()
    picker.add(h, string.rep("x", 150) .. " needle")
    picker.add(h, "short")
    local rows = picker.history_rows(h, "needle")
    t.eq(#rows, 1)
    t.eq(rows[1].text, string.rep("x", 150) .. " needle")
    t.eq(rows[1].preview:find("needle", 1, true), nil, "the row still shows the start")
end)

t.test("Shift+Delete forgets one entry", function()
    local h = picker.history()
    picker.add(h, "a")
    picker.add(h, "b")
    t.eq(picker.forget(h, "a"), true)
    t.eq(h.items, { "b" })
    t.eq(picker.forget(h, "zzz"), false)
end)

t.test("a row shows one line of the copy, and says if it's a link", function()
    t.eq(picker.preview("  make\n  test  "), "make test")
    t.eq(picker.preview("ééééé", 3), "ééé…")
    t.eq(picker.kind("https://example.com/docs"), "Link")
    t.eq(picker.kind("see https://example.com"), "Text")
end)

t.test("the Clipboard tab lists newest first, and a query ranks by score", function()
    local h = picker.history()
    picker.add(h, "make mocks")
    picker.add(h, "git commit --amend")
    picker.add(h, "make test")
    local function texts(rows)
        local out = {}
        for i, r in ipairs(rows) do
            out[i] = r.text
        end
        return out
    end
    t.eq(texts(picker.history_rows(h, "")), { "make test", "git commit --amend", "make mocks" })
    t.eq(texts(picker.history_rows(h, "mock")), { "make mocks" })
    t.eq(texts(picker.history_rows(h, "make")), { "make test", "make mocks" }, "equal scores stay newest first")
end)

local list = picker.parse_chars(table.concat({
    "# a comment",
    "á\tlatin small letter a with acute\tLatin-1",
    "é\tlatin small letter e with acute\tLatin-1",
    "É\tlatin capital letter e with acute\tLatin-1",
    "→\trightwards arrow\tArrows",
    "↑\tupwards arrow\tArrows",
    "🤷\tperson shrugging\tPeople & Body",
    "⬆️\tup arrow\tSymbols",
}, "\n"))

local function chars(rows)
    local out = {}
    for i, c in ipairs(rows) do
        out[i] = c.char
    end
    return out
end

t.test("each typed word must start a word of the name, in any order", function()
    t.eq(chars(picker.character_rows(list, "e acute")), { "é", "É" })
    t.eq(chars(picker.character_rows(list, "acute e")), { "é", "É" })
    t.eq(chars(picker.character_rows(list, "shrug")), { "🤷" })
    t.eq(chars(picker.character_rows(list, "rugging")), {})
end)

t.test("whole words rank before prefixes, then the list's order", function()
    t.eq(chars(picker.character_rows(list, "arrow")), { "→", "↑", "⬆️" })
    t.eq(chars(picker.character_rows(list, "up")), { "⬆️", "↑" })
end)

t.test("no query lists from the top, and every list is capped", function()
    t.eq(#picker.character_rows(list, ""), #list)
    local many = {}
    for i = 1, 300 do
        many[i] = "x\tthing " .. i .. "\tG"
    end
    local big = picker.parse_chars(table.concat(many, "\n"))
    t.eq(#picker.character_rows(big, ""), picker.CHARACTER_LIMIT)
    t.eq(#picker.character_rows(big, "thing"), picker.CHARACTER_LIMIT)
end)

t.test("a row whose character starts with # isn't a comment; a malformed line is said", function()
    local c, errors = picker.parse_chars("# header\n#\u{FE0F}\u{20E3}\tkeycap: #\tSymbols\nbroken\n")
    t.eq(#c, 1)
    t.eq(c[1].name, "keycap: #")
    t.eq(errors, { 3 })
end)

t.test("a single code point is shown as U+XXXX", function()
    t.eq(picker.code_point("é"), "U+00E9")
    t.eq(picker.code_point("🤷"), "U+1F937")
    t.eq(picker.code_point("⬆️"), "U+2B06")
    t.eq(picker.code_point("🇯🇵"), nil)
    t.eq(picker.character_sub({ char = "é", group = "Latin-1" }), "Latin-1 · U+00E9")
end)

t.test("an empty tab says why", function()
    t.eq(picker.empty_text("clipboard", ""), "Nothing copied since tilemo started")
    t.eq(picker.empty_text("characters", "zzz"), "Nothing matches")
    t.eq(picker.empty_text("characters", "", "can't read chars.tsv"), "can't read chars.tsv")
end)

t.test("the shipped list, tide's, parses whole and finds the spec's examples", function()
    local all, errors = picker.parse_chars(read("hammerspoon/tilemo/chars.tsv"))
    t.eq(errors, {})
    t.eq(#all > 3000, true)
    t.eq(chars(picker.character_rows(all, "e acute")), { "é", "É" })
    t.eq(picker.character_rows(all, "shrug")[1].char, "🤷")
    local found = {}
    for _, c in ipairs(picker.character_rows(all, "keycap")) do
        found[c.char] = true
    end
    t.eq(found["#\u{FE0F}\u{20E3}"], true, "keycap #")
end)

t.done("picker")
