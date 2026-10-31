local t = require("t")
local names = require("tilemo.names")

-- JavaScript run in node, standing in for JavaScriptCore, or nil without
-- node.
local function node_runner()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TILEMO_NEED_NODE") then
            error("node is needed to run the name patterns")
        end
        return nil
    end
    return function(source)
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write("process.stdout.write(String(" .. source .. "));")
        f:close()
        local p = io.popen("node " .. path .. " 2>&1")
        local out = p:read("a")
        local ok = p:close()
        os.remove(path)
        return ok == true, out
    end
end

-- A JSON list of strings, as hs.json.decode would read it; anything else
-- passes through.
local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
local function decode(text)
    if type(text) ~= "string" or not text:match("^%[") then
        return text
    end
    local out, i = {}, 2
    while true do
        i = text:find("[\"%]]", i)
        if text:sub(i, i) == "]" then
            return out
        end
        local buf = {}
        i = i + 1
        while text:sub(i, i) ~= '"' do
            local c = text:sub(i, i)
            if c == "\\" then
                local e = text:sub(i + 1, i + 1)
                if e == "u" then
                    buf[#buf + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16))
                    i = i + 6
                else
                    buf[#buf + 1] = ESCAPES[e]
                    i = i + 2
                end
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        end
        out[#out + 1] = table.concat(buf)
        i = i + 1
    end
end

t.test("TIDE_WORKSPACE keeps an ASCII name's letters and digits, with no JavaScript", function()
    local function no_js()
        error("ASCII needs no JavaScript")
    end
    t.eq(names.sanitize("my-repo", no_js), "myrepo")
    t.eq(names.sanitize("PR-12 login", no_js), "PR12login")
    t.eq(names.sanitize("in", no_js), "in")
    t.eq(names.sanitize("a\tb\0c\27[31m!? $x", no_js), "abc31mx", "control characters and punctuation go")
    t.eq(names.sanitize("--- !!", no_js), "", "none gives an empty value")
end)

t.test("a name past ASCII that can't be run through JavaScript gives an empty value, and why", function()
    local value, err = names.sanitize("café")
    t.eq(value, "")
    t.eq(err, "no JavaScript to keep the workspace's letters and digits")
    value, err = names.sanitize("café", function()
        return false, "JavaScriptCore said no"
    end)
    t.eq(value, "", "not the ASCII it would have kept")
    t.eq(err, "couldn't keep the workspace's letters and digits: JavaScriptCore said no")
end)

t.test("with no pattern, the default is the title without its app's name, cut at a word", function()
    t.eq(names.fallback("Inbox - Google Chrome", "Google Chrome"), "Inbox")
    t.eq(names.fallback("Docs — Mozilla Firefox", "Mozilla Firefox"), "Docs")
    t.eq(names.fallback("Google Chrome", "Google Chrome"), "Google Chrome", "the app's name alone stays")
    t.eq(names.fallback("A rather long title for a page - Chrome", "Chrome"), "A rather long title")
    t.eq(names.fallback("one two three four five", ""), "one two three four")
    t.eq(names.fallback("exactly twenty chars and more", ""), "exactly twenty chars")
    t.eq(names.fallback("Supercalifragilisticexpialidocious", ""), "Supercalifragilistic", "one long word is cut")
    t.eq(names.fallback("", "Notes"), "Notes", "no title: the app's name")
    t.eq(names.fallback(nil, "Notes"), "Notes")
    t.eq(names.fallback("  spaced    out  ", ""), "spaced out")
end)

t.test("a name can't hold quotes, backslashes or control characters, as on tide", function()
    for _, bad in ipairs({ 'team "x"', "it's", "a`b", "a\\b", "a\tb", "a\127b", "a\27[0mb" }) do
        t.eq(names.unsafe(bad), true, bad)
    end
    for _, good in ipairs({ "PR-12 login", "café", "a/b", "x:y", "" }) do
        t.eq(names.unsafe(good), false, good)
    end
    t.eq(names.safe('it\'s "a`b\\c"\27'), "its abc")
end)

t.test("a default name drops what a name can't hold", function()
    t.eq(names.default_name('Say "hi" - Google Chrome', "Google Chrome"), "Say hi")
    t.eq(names.default_name("", '"Odd" App'), "Odd App")
    t.eq(names.default_name("\27]0;x\7", "App"), "]0;x")
    t.eq(names.default_name('"', "App"), "", "nothing left")
    t.eq(names.default_name("ABC-1 'x'", "App", { "(.*)" }, function()
        return true, "ABC-1 'x'"
    end), "ABC-1 x")
end)

t.test("a title is a safe JavaScript string, whatever it holds", function()
    t.eq(names.js_string('a "b" \\ c'), '"a \\"b\\" \\\\ c"')
    t.eq(names.js_string("line\nnext"), '"line\\u000anext"')
    t.eq(names.js_string("x\226\128\168y"), '"x\\u2028y"')
end)

t.test("tide's .local file's patterns take the place of the shared file's", function()
    local files = {}
    local function read(p)
        return files[p]
    end
    local function dec(x)
        return x
    end
    t.eq(names.read("/c", read, dec), {}, "no files: no patterns")
    files["/c/workspaces.json"] = { namePatterns = { "a(b)" } }
    t.eq(names.read("/c", read, dec), { "a(b)" })
    files["/c/workspaces.local.json"] = { other = true }
    t.eq(names.read("/c", read, dec), { "a(b)" }, "a .local file without the key leaves it")
    files["/c/workspaces.local.json"] = { namePatterns = { "(x)" } }
    t.eq(names.read("/c", read, dec), { "(x)" })
    files["/c/workspaces.local.json"] = { namePatterns = "(x)" }
    local list, err = names.read("/c", read, dec)
    t.eq(list, nil)
    t.eq(err, "workspaces.local.json: namePatterns must be a list of patterns")
    -- A JSON object is a table too, but not a list: an error, not no
    -- patterns.
    files["/c/workspaces.local.json"] = { namePatterns = { first = "(x)" } }
    t.eq(select(2, names.read("/c", read, dec)), "workspaces.local.json: namePatterns must be a list of patterns")
    files["/c/workspaces.local.json"] = { namePatterns = { "(x)", [5] = "(y)" } }
    t.eq(select(2, names.read("/c", read, dec)), "workspaces.local.json: namePatterns must be a list of patterns")
    files["/c/workspaces.local.json"] = { namePatterns = { "(x)", 3 } }
    t.eq(select(2, names.read("/c", read, dec)), "workspaces.local.json: namePatterns[2] must be a string")
    files["/c/workspaces.local.json"] = nil
    files["/c/workspaces.json"] = "not json"
    t.eq(select(2, names.read("/c", read, function() end)), "workspaces.json: not a JSON object")
end)

local run = node_runner()
if not run then
    print("SKIP the name patterns' JavaScript: no node")
else
    t.test("TIDE_WORKSPACE keeps letters and digits in any script, NFC-normalized", function()
        t.eq(names.sanitize("café-1", run), "café1", "accented Latin, composed")
        t.eq(names.sanitize("cafe\204\129 2", run), "caf\195\169" .. "2", "decomposed, as macOS gives it, comes out composed")
        t.eq(names.sanitize("Привет, мир", run), "Приветмир", "Cyrillic")
        t.eq(names.sanitize("日本語 メモ", run), "日本語メモ", "CJK")
        t.eq(names.sanitize("build-١٢ १", run), "build١٢१", "Arabic-Indic and Devanagari digits")
        t.eq(names.sanitize("Ⅻ ½", run), "Ⅻ½", "other numbers")
        t.eq(names.sanitize("🚀 launch ✨", run), "launch", "emoji go")
        t.eq(names.sanitize("é\t\"x\"\\\226\128\139y\226\128\168z", run), "éxyz",
            "control characters, quotes, backslashes and format characters go")
        t.eq(names.sanitize("a+b=c$ €5", run), "abc5", "symbols go")
        t.eq(names.sanitize("-\204\129-", run), "", "a mark with no letter goes")
        t.eq(names.sanitize("\225\132\128-\225\133\161", run), "\234\176\128", "jamo a dash kept apart are composed")
        t.eq(names.sanitize("¿—? 🚀", run), "", "none gives an empty value")
    end)

    t.test("the first pattern that matches gives its first capture", function()
        local ps = { "\\b([A-Z]+-[0-9]+)\\b", "github\\.com/[^/]+/([^/ ]+)" }
        t.eq(names.default_name("ABC-123: Fix login - Tracker - Google Chrome", "Google Chrome", ps, run), "ABC-123")
        t.eq(names.default_name("Pull requests · github.com/mikelward/tilemo", "Safari", ps, run), "tilemo")
        t.eq(names.default_name("Inbox - Google Chrome", "Google Chrome", ps, run), "Inbox", "no match: the fallback")
        t.eq(names.default_name("", "Notes", ps, run), "Notes")
        -- JavaScript's syntax, which Lua patterns don't have.
        t.eq(names.default_name("ticket 4521 open", "x", { "(?:bug|ticket) (\\d{4})" }, run), "4521")
        t.eq(names.default_name('a "quoted" title', "x", { '"(\\w+)"' }, run), "quoted")
        t.eq(names.default_name("x - y", "x", { "(z?)" }, run), "x - y", "an empty capture is passed over")
    end)

    t.test("a pattern that doesn't compile, or has no group, is an error naming it", function()
        local files = { ["/c/workspaces.json"] = { namePatterns = { "ok(\\d)", "(", "no group" } } }
        local function read(p)
            return files[p]
        end
        local function dec(x)
            if type(x) == "string" then
                return decode(x)
            end
            return x
        end
        local list, err = names.load("/c", read, dec, run)
        t.eq(list, nil)
        t.eq(err:find("^workspaces.json: namePatterns%[2%] ") ~= nil, true, err)
        t.eq(err:find('namePatterns[3] "no group" has no capture group', 1, true) ~= nil, true, err)
        files["/c/workspaces.json"] = { namePatterns = { "ok(\\d)" } }
        t.eq(names.load("/c", read, dec, run), { "ok(\\d)" })
    end)
end

t.test("a pattern run that fails falls back to the title, and says why", function()
    local said
    local got = names.default_name("Inbox - Mail", "Mail", { "(x)" }, function()
        return false, "no JavaScript"
    end, function(m)
        said = m
    end)
    t.eq(got, "Inbox")
    t.eq(said, "name patterns: no JavaScript")
end)

t.done("names")
