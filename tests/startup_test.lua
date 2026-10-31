local t = require("t")
local startup = require("tilemo.startup")

local DIR = "/home/user/.config/tide"

-- A small JSON reader for the tests: objects, lists, strings without
-- escapes, numbers, true, false and null. Nil for anything else.
local function decode(text)
    local i = 1
    local value
    local function ws()
        i = text:find("%S", i) or #text + 1
    end
    local function fail()
        error("bad json", 0)
    end
    function value()
        ws()
        local c = text:sub(i, i)
        if c == "{" then
            local out = {}
            i = i + 1
            ws()
            if text:sub(i, i) == "}" then
                i = i + 1
                return out
            end
            while true do
                ws()
                local k = value()
                if type(k) ~= "string" then fail() end
                ws()
                if text:sub(i, i) ~= ":" then fail() end
                i = i + 1
                out[k] = value()
                ws()
                local d = text:sub(i, i)
                i = i + 1
                if d == "}" then return out end
                if d ~= "," then fail() end
            end
        elseif c == "[" then
            local out = {}
            i = i + 1
            ws()
            if text:sub(i, i) == "]" then
                i = i + 1
                return out
            end
            while true do
                out[#out + 1] = value()
                ws()
                local d = text:sub(i, i)
                i = i + 1
                if d == "]" then return out end
                if d ~= "," then fail() end
            end
        elseif c == '"' then
            local j = text:find('"', i + 1, true) or fail()
            local s = text:sub(i + 1, j - 1)
            i = j + 1
            return s
        end
        for word, v in pairs({ ["true"] = true, ["false"] = false, ["null"] = "null" }) do
            if text:sub(i, i + #word - 1) == word then
                i = i + #word
                return v
            end
        end
        local num = text:match("^-?%d+%.?%d*", i) or fail()
        i = i + #num
        return tonumber(num)
    end
    local ok, v = pcall(value)
    if not ok then
        return nil
    end
    ws()
    return i > #text and v or nil
end

local function reader(files)
    return function(path)
        return files[path]
    end
end

local function load(shared, loc)
    return startup.load(DIR, reader({ [DIR .. "/startup.json"] = shared, [DIR .. "/startup.local.json"] = loc }), decode)
end

t.test("none by default, and the local list replaces the shared one whole", function()
    t.eq({ load(nil, nil) }, { {}, {} })
    t.eq(load('{"commands": ["google-calendar"]}', nil), { "google-calendar" })
    t.eq(load('{"commands": ["a"]}', '{"commands": ["b", "c"]}'), { "b", "c" })
    t.eq(load('{"commands": ["a"]}', '{}'), { "a" }, "a local file without a list keeps the shared one")
    t.eq(load('{"commands": ["a"]}', '{"commands": []}'), {}, "an empty local list runs nothing")
end)

t.test("a bad entry is an error naming the file and entry, and the rest still run", function()
    local list, errors = load(nil, '{"commands": ["google-calendar", "echo $HOME", 7, "google-calendar", "google-chat"]}')
    t.eq(list, { "google-calendar", "google-chat" })
    t.eq(#errors, 3)
    t.eq(errors[1]:match("^startup%.local%.json: commands%[2%] \"echo %$HOME\" has a quote, backslash or %$") ~= nil, true, errors[1])
    t.eq(errors[2], "startup.local.json: commands[3] 7 is not a string")
    t.eq(errors[3], 'startup.local.json: commands[4] "google-calendar" is listed already')
end)

t.test("a file that isn't an object, or a list that isn't one, runs nothing", function()
    t.eq({ load(nil, "{") }, { nil, { "startup.local.json: not a JSON object" } })
    t.eq({ load('["a"]', nil) }, { nil, { "startup.json: not a JSON object" } })
    t.eq({ load('{"commands": ["a"]}', " [] ") }, { nil, { "startup.local.json: not a JSON object" } },
        "an empty list is no object either, and doesn't fall through to the shared file")
    t.eq({ load('{"commands": "a"}', nil) }, { nil, { "startup.json: commands must be a list" } })
end)

t.test("a command is words with no shell; quotes, backslashes and $ are refused", function()
    t.eq(startup.words("  chrome  --app=https://chat.google.com "), { "chrome", "--app=https://chat.google.com" })
    t.eq(startup.problem("chrome --app=https://x.example/?a=1&b=2"), nil)
    t.eq(startup.problem("a\\b") ~= nil, true)
    t.eq(startup.problem("sh -c 'x'") ~= nil, true)
    t.eq(startup.problem("   "), "names no program")
    t.eq(startup.problem("a\nb"), "has a control character in it")
    t.eq(startup.problem("/opt/helpers/ --x"), "names a directory, not a program")
end)

t.test("the list runs once a login, and not when the login can't be told", function()
    t.eq(startup.due(nil, "Sat Oct 31 09:00:00 2026"), true)
    t.eq(startup.due("Sat Oct 31 09:00:00 2026", "Sat Oct 31 09:00:00 2026"), false, "a reload in the same login")
    t.eq(startup.due("Fri Oct 30 09:00:00 2026", "Sat Oct 31 09:00:00 2026"), true, "the next login")
    t.eq(startup.due(nil, nil), false)
    t.eq(startup.due(nil, ""), false)
end)

t.test("pgrep matches the program's whole basename, as macOS's pgrep -x reads argv[0], escaped", function()
    t.eq(startup.pgrep_args(501, "/opt/google-calendar.sh+x --new"), { "-u", "501", "-x", "--", "google-calendar\\.sh\\+x" })
    t.eq(startup.pgrep_args(501, "a-very-long-helper-name"), { "-u", "501", "-x", "--", "a-very-long-helper-name" }, "not cut at 15")
    t.eq(startup.pgrep_args(501, "a.b+c"), { "-u", "501", "-x", "--", "a\\.b\\+c" })
end)

t.test("each runs unless running; a pgrep that can't tell starts it, saying so", function()
    local launched, logged = {}, {}
    local codes = { a = 1, b = 0, c = 2 }
    startup.run({ "a --x", "b", "c" }, 501, function(args, done)
        done(codes[args[5]])
    end, function(command)
        launched[#launched + 1] = command
    end, function(text)
        logged[#logged + 1] = text
    end)
    t.eq(launched, { "a --x", "c" })
    t.eq(logged, { "b is running already, so not starting it again", "pgrep couldn't say whether c is running (exit 2), so starting it" })
end)

t.test("a list of directories loads none, and pgrep_args never throws", function()
    local list, errors = load(nil, '{"commands": ["/opt/helpers/", "google-chat"]}')
    t.eq(list, { "google-chat" })
    t.eq(errors, { 'startup.local.json: commands[1] "/opt/helpers/" names a directory, not a program' })
    t.eq(startup.pgrep_args(501, "/"), { "-u", "501", "-x", "--", "" })
end)

t.test("one command that throws doesn't stop the rest", function()
    local launched, logged = {}, {}
    startup.run({ "a", "b" }, 501, function(args, done)
        if args[5] == "a" then
            error("no pgrep task")
        end
        done(1)
    end, function(command)
        launched[#launched + 1] = command
    end, function(text)
        logged[#logged + 1] = text
    end)
    t.eq(launched, { "b" })
    t.eq(#logged, 1)
    t.eq(logged[1]:match("^couldn't start a: ") ~= nil, true, logged[1])
end)

t.test("each starts only after the one before it, in the list's order", function()
    local pending, events = {}, {}
    startup.run({ "first", "second", "third" }, 501, function(args, done)
        events[#events + 1] = "check " .. args[5]
        pending[#pending + 1] = done
    end, function(command)
        events[#events + 1] = "launch " .. command
    end, function() end)
    t.eq(events, { "check first" }, "the second waits for the first's check")
    pending[1](1)
    t.eq(events, { "check first", "launch first", "check second" })
    pending[2](0)
    t.eq(events, { "check first", "launch first", "check second", "check third" }, "a skipped one moves on")
    pending[3](1)
    t.eq(events[#events], "launch third")
end)

t.test("home starts only the apps you set, not tilemo's default list of alternatives", function()
    t.eq(startup.home_starts(nil), {})
    t.eq(startup.home_starts({ "Gmail", "Google Calendar" }), { "Gmail", "Google Calendar" })
end)

-- hs.settings, in memory.
local function settings()
    local kept = {}
    return {
        get = function(k)
            return kept[k]
        end,
        set = function(k, v)
            kept[k] = v
        end,
        kept = kept,
    }
end

t.test("home's apps start in order at login, in the background, skipping one that's running", function()
    local opened, logged = {}, {}
    local s = settings()
    local started = startup.home_at_login({ "Gmail", "Google Chat", "Google Calendar" }, s, "Sat Oct 31 09:00:00 2026",
        function(name)
            return name == "Google Chat"
        end, function(name)
            opened[#opened + 1] = name
        end, function(text)
            logged[#logged + 1] = text
        end)
    t.eq(started, true)
    t.eq(opened, { "Gmail", "Google Calendar" })
    t.eq(logged, { "Google Chat is running already, so not starting it again" })
    t.eq(s.kept[startup.HOME_SETTINGS_KEY], "Sat Oct 31 09:00:00 2026")
    t.eq(s.kept[startup.SETTINGS_KEY], nil, "apart from the list's login")
end)

t.test("home's apps start once a login, not at every reload", function()
    local opened = {}
    local s = settings()
    local function at(login)
        return startup.home_at_login({ "Gmail" }, s, login, function()
            return false
        end, function(name)
            opened[#opened + 1] = name
        end, function() end)
    end
    t.eq(at("login 1"), true)
    t.eq(at("login 1"), false, "a reload in the same login")
    t.eq(at(nil), false, "a login that can't be told")
    t.eq(at("login 2"), true)
    t.eq(opened, { "Gmail", "Gmail" })
end)

t.test("with tilemo's default home_apps, nothing starts and the login isn't spent", function()
    local s = settings()
    t.eq(startup.home_at_login(nil, s, "login 1", function()
        error("not asked")
    end, function()
        error("not opened")
    end, function() end), false)
    t.eq(s.kept[startup.HOME_SETTINGS_KEY], nil)
end)

t.test("one of home's apps that fails to start is logged, and the rest still start", function()
    local opened, logged = {}, {}
    startup.start_home({ "Broken", "Gmail" }, function(name)
        if name == "Broken" then
            error("no such app")
        end
        return false
    end, function(name)
        opened[#opened + 1] = name
    end, function(text)
        logged[#logged + 1] = text
    end)
    t.eq(opened, { "Gmail" })
    t.eq(#logged, 1)
    t.eq(logged[1]:match("^couldn't start Broken: ") ~= nil, true, logged[1])
end)

t.done("startup_test")
