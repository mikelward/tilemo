local t = require("t")
local compose = require("tide.compose")

local TABLE = compose.parse(table.concat({
    "# A comment: no tab.",
    "'e\té",
    "oo\t°",
    "#b\t♭",
    "(1)\t①",
    "(10)\t⑩",
    "//\t\\",
}, "\n"))

local function typed(keys)
    local c = compose.new(TABLE)
    c:start()
    local status, out
    for k in keys:gmatch(".") do
        status, out = c:key(k)
    end
    return status, out, c:active()
end

t.test("two keys after Compose type their character", function()
    t.eq({ typed("'e") }, { "done", "é", false })
    t.eq({ typed("oo") }, { "done", "°", false })
end)

t.test("a sequence can start with #, which isn't a comment there", function()
    t.eq({ typed("#b") }, { "done", "♭", false })
end)

t.test("the start of a sequence waits for more", function()
    t.eq({ typed("(1") }, { "more", nil, true })
    t.eq({ typed("(1)") }, { "done", "①", false })
    t.eq({ typed("(10)") }, { "done", "⑩", false })
end)

t.test("a sequence it doesn't know types nothing and ends", function()
    t.eq({ typed("'q") }, { "none", nil, false })
end)

t.test("keys without Compose first aren't composed", function()
    local c = compose.new(TABLE)
    t.eq(c:key("'"), "none")
    t.eq(c:active(), false)
end)

t.test("cancel ends a sequence part way", function()
    local c = compose.new(TABLE)
    c:start()
    c:key("'")
    c:cancel()
    t.eq(c:active(), false)
    t.eq(c:key("e"), "none")
end)

t.test("Linux's table, as shipped, types the usual ones", function()
    local f = assert(io.open("hammerspoon/tide/compose.tsv", "rb"))
    local shipped = compose.parse(f:read("a"))
    f:close()
    t.eq(shipped.full["'e"], "é")
    t.eq(shipped.full["ss"], "ß")
    t.eq(shipped.full["=e"], "€")
    t.eq(shipped.full["//"], "\\")
    t.eq(shipped.full["#b"], "♭")
    t.eq(shipped.full["# Linux's Compose sequences (tide SPEC.md §10): the keys after Compose,"], nil)
end)

t.test("the compose setting is true or false", function()
    compose.check(nil)
    compose.check(false)
    local ok, err = pcall(compose.check, 1)
    t.eq(ok, false)
    t.eq(tostring(err):find("compose must be true or false", 1, true) ~= nil, true)
end)

t.done("compose")
