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

t.test("TIDE_WORKSPACE keeps only ASCII letters and digits", function()
    t.eq(names.sanitize("my-repo"), "myrepo")
    t.eq(names.sanitize("PR-12 login"), "PR12login")
    t.eq(names.sanitize("in"), "in")
    t.eq(names.sanitize("日本語"), "", "none gives an empty value")
    t.eq(names.sanitize("café"), "caf")
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
