local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local bar = require("tilemo.bar")
local mute = require("tilemo.mute")
local launcher = require("tilemo.launcher")

local DIR = "/home/user/.config/tide"
local SHARED = DIR .. "/" .. mute.FILE
local LOCAL = DIR .. "/" .. mute.LOCAL_FILE

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

local function encode(v)
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local x = v[k]
        local s
        if type(x) == "string" then
            s = string.format("%q", x)
        elseif type(x) == "table" then
            s = mute.encode_list(x)
        else
            s = tostring(x)
        end
        out[#out + 1] = string.format("%q: %s", k, s)
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

local function files(init)
    local fs = init or {}
    local writes = 0
    local function read(path)
        return fs[path]
    end
    local function write(path, text)
        writes = writes + 1
        fs[path] = text
        return true
    end
    return fs, read, write, function()
        return writes
    end
end

t.test("entries are bundle ids and site:<host>, the host matched exactly, ignoring case", function()
    local set, errors = mute.parse({ "com.example.chat", "site:Chat.Example.com" }, "workspaces.json")
    t.eq(errors, {})
    t.eq(mute.matches(set, "com.example.chat", nil), true)
    t.eq(mute.matches(set, "com.example.mail", nil), false)
    t.eq(mute.matches(set, "com.google.Chrome", "chat.example.com"), true)
    t.eq(mute.matches(set, "com.google.Chrome", "CHAT.example.com"), true)
    t.eq(mute.matches(set, "com.google.Chrome", "mail.example.com"), false)
    t.eq(mute.matches(set, "com.google.Chrome", "example.com"), false)
    t.eq(mute.matches(set, "com.google.Chrome", nil), false)
    t.eq(mute.matches(nil, "com.example.chat"), false)
end)

t.test("a malformed entry is an error naming the file and the entry, and the rest still count", function()
    local set, errors = mute.parse({ "com.example.chat", 42, "", "has space", "site:", "site:https://x.example.com/a",
        "site:x.example.com:8080", "site:ok.example.com" }, "workspaces.local.json")
    t.eq(set.list, { "com.example.chat", "site:ok.example.com" })
    t.eq(#errors, 6)
    t.eq(errors[1], "workspaces.local.json: muted[2] 42 is not a string")
    t.eq(errors[2], 'workspaces.local.json: muted[3] "" is empty')
    t.eq(errors[3], 'workspaces.local.json: muted[4] "has space" has a space in it')
    t.eq(errors[4], 'workspaces.local.json: muted[5] "site:" names no host')
    t.eq(errors[5]:find("more than a host", 1, true) ~= nil, true)
end)

t.test("the local file's list replaces the shared one whole, and nothing set mutes nothing", function()
    local _, read = files({
        [SHARED] = '{"muted": ["com.example.chat"], "inApps": ["x"]}',
        [LOCAL] = '{"muted": ["site:chat.example.com"]}',
    })
    local set, errors = mute.load(DIR, read, decode)
    t.eq(errors, {})
    t.eq(set.list, { "site:chat.example.com" })
    _, read = files({ [SHARED] = '{"muted": ["com.example.chat"]}', [LOCAL] = '{"other": 1}' })
    t.eq(mute.load(DIR, read, decode).list, { "com.example.chat" })
    _, read = files({})
    t.eq(mute.load(DIR, read, decode).list, {})
    _, read = files({ [LOCAL] = "not json" })
    local s, e = mute.load(DIR, read, decode)
    t.eq(s, nil, "the caller keeps the last good list")
    t.eq(e, { "workspaces.local.json: not a JSON object" })
    _, read = files({ [SHARED] = '{"muted": "com.example.chat"}' })
    t.eq(select(2, mute.load(DIR, read, decode)), { "workspaces.json: muted must be a list" })
end)

t.test("a muted value that's a JSON object is an error, not an empty list that unmutes everything", function()
    local _, read = files({
        [SHARED] = '{"muted": ["com.example.chat"]}',
        [LOCAL] = '{"muted": {"app": "com.example.chat"}}',
    })
    local set, errors = mute.load(DIR, read, decode)
    t.eq(set, nil)
    t.eq(errors, { "workspaces.local.json: muted must be a list" })
    -- Nor will muting from the switcher write over it.
    local now, err = mute.toggle(DIR, "com.example.mail", read, decode, encode, function()
        error("wrote")
    end)
    t.eq(now, nil)
    t.eq(err, "workspaces.local.json: muted must be a list")
    -- An empty array is a list: nothing muted.
    _, read = files({ [SHARED] = '{"muted": ["com.example.chat"]}', [LOCAL] = '{"muted": []}' })
    t.eq(mute.load(DIR, read, decode).list, {})
    t.eq(mute.is_list({ "a", [3] = "c" }), false)
    t.eq(mute.is_list({ "a", "b" }), true)
end)

t.test("muting writes the list in effect plus the entry to the local file, keeping its other keys", function()
    local fs, read, write = files({
        [SHARED] = '{"muted": ["com.example.chat"]}',
        [LOCAL] = '{"namePatterns": ["([A-Z]+-[0-9]+)"]}',
    })
    t.eq(mute.toggle(DIR, "site:chat.example.com", read, decode, encode, write), true)
    local v = decode(fs[LOCAL])
    t.eq(v.muted, { "com.example.chat", "site:chat.example.com" })
    t.eq(v.namePatterns, { "([A-Z]+-[0-9]+)" })
    t.eq(fs[SHARED], '{"muted": ["com.example.chat"]}', "the shared file is never written")
    -- The same again unmutes it, whatever its case.
    t.eq(mute.toggle(DIR, "site:CHAT.example.com", read, decode, encode, write), false)
    t.eq(decode(fs[LOCAL]).muted, { "com.example.chat" })
    t.eq(mute.toggle(DIR, "com.example.chat", read, decode, encode, write), false)
    t.eq(fs[LOCAL]:find('"muted": []', 1, true) ~= nil, true, "an empty list is written as one: " .. fs[LOCAL])
end)

t.test("muting writes nothing when it can't read the file or the entry is bad", function()
    local _, read, write, writes = files({ [LOCAL] = "{oops" })
    local now, err = mute.toggle(DIR, "com.example.chat", read, decode, encode, write)
    t.eq(now, nil)
    t.eq(err, "workspaces.local.json: not a JSON object")
    now, err = mute.toggle(DIR, "has space", read, decode, encode, write)
    t.eq(now, nil)
    t.eq(err:find("has a space", 1, true) ~= nil, true)
    local _, read2 = files({})
    now, err = mute.toggle(DIR, "com.example.chat", read2, decode, encode, function()
        return nil, "disk full"
    end)
    t.eq(now, nil)
    t.eq(err, "couldn't write " .. LOCAL .. ": disk full")
    t.eq(writes(), 0)
end)

t.test("a malformed entry already in the list is kept when muting something else", function()
    local fs, read, write = files({ [LOCAL] = '{"muted": ["has space", "com.example.chat"]}' })
    t.eq(mute.toggle(DIR, "com.example.mail", read, decode, encode, write), true)
    t.eq(decode(fs[LOCAL]).muted, { "has space", "com.example.chat", "com.example.mail" })
end)

t.test("a URL's host is the site: lowercased, without a port or user", function()
    t.eq(mute.host("https://Chat.Example.com/u/0/"), "chat.example.com")
    t.eq(mute.host("https://user@x.example.com:8443/a?b"), "x.example.com")
    t.eq(mute.host("about:blank"), nil)
    t.eq(mute.host(nil), nil)
end)

t.test("a switcher row mutes its window's app, or its tab's site, and says so", function()
    t.eq(mute.entry_for({ kind = "window", bundle = "com.example.chat" }), "com.example.chat")
    t.eq(mute.entry_for({ kind = "attention", bundle = "com.example.chat" }), "com.example.chat")
    t.eq(mute.entry_for({ kind = "tab", url = "https://chat.example.com/room" }), "site:chat.example.com")
    t.eq(mute.entry_for({ kind = "app", path = "/Applications/Chat.app" }), nil)
    local set = mute.parse({ "com.example.chat", "site:chat.example.com" }, "x")
    local items = launcher.items({}, {
        { title = "Room", url = "https://chat.example.com/room", browser = "Google Chrome", window = 1, tab = 1 },
        { title = "Docs", url = "https://docs.example.com/", browser = "Google Chrome", window = 1, tab = 2 },
    }, {}, {}, {
        { window = 3, title = "Chat (2)", app = "Chat", bundle = "com.example.chat", ws = "in" },
    }, {}, {
        { id = 3, title = "Chat (2)", app_name = "Chat", bundle = "com.example.chat", ws = "in" },
        { id = 4, title = "Mail", app_name = "Mail", bundle = "com.example.mail", ws = "in" },
    })
    mute.mark_rows(items, set)
    local subs = {}
    for _, item in ipairs(items) do
        subs[item.kind .. ":" .. item.title] = launcher.subtitle(item)
    end
    t.eq(subs["window:Chat (2)"], "Chat · in · muted")
    t.eq(subs["window:Mail"], "Mail · in")
    t.eq(subs["attention:Chat (2)"], "Chat · in · muted")
    t.eq(subs["tab:Room"], "Google Chrome · chat.example.com · muted")
    t.eq(subs["tab:Docs"], "Google Chrome · docs.example.com")
end)

t.test("the notice says what a mute stops, and that macOS's banners stay", function()
    t.eq(mute.notice("Chat", true):find("won't be marked for attention", 1, true) ~= nil, true)
    t.eq(mute.notice("Chat", true):find("macOS still shows its banners", 1, true) ~= nil, true)
    t.eq(mute.notice("Chat", false), "Unmuted Chat: it can be marked for attention again.")
    t.eq(mute.NOTIFICATIONS_URL, "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
end)

local function setup()
    local a = fake.new()
    a.add(1, { app = "com.example.chat", title = "Chat" })
    a.add(2, { app = "com.google.Chrome", title = "Room - Google Chrome" })
    a.add(3, { app = "com.example.mail", title = "Mail" })
    local wm = wm_mod.new(a, { workspaces = { "in" } })
    wm:sync()
    return a, wm
end

t.test("a muted app gets no mark: no chip icon, no Attention row", function()
    local _, wm = setup()
    wm:set_muted(mute.parse({ "com.example.chat" }, "x"))
    wm.attention:activated(1, "com.example.chat")
    wm.attention:title(1, "com.example.chat", "Chat (3)")
    wm.attention:dock({ { app = "com.example.chat", label = "5" } })
    wm.attention:activated(3, "com.example.mail")
    t.eq(wm:attention_windows(), { 3 })
    local chip = bar.state(wm, "A", "", {}).workspaces[1]
    t.eq(chip.wins, { 3 })
    t.eq(chip.urgent, true, "the unmuted window still marks its chip")
    wm:set_muted(mute.parse({ "com.example.chat", "com.example.mail" }, "x"))
    t.eq(wm:attention_windows(), {})
    t.eq(bar.state(wm, "A", "", {}).workspaces[1].urgent, false)
end)

t.test("muting clears the marks it now covers, and unmuting lets new ones in", function()
    local _, wm = setup()
    wm.attention:activated(1, "com.example.chat")
    wm.attention:dock({ { app = "com.example.chat", label = "1" } })
    t.eq(wm:attention_windows(), { 1 })
    wm:set_muted(mute.parse({ "com.example.chat" }, "x"))
    t.eq(wm:attention_windows(), {})
    wm:set_muted(mute.empty())
    t.eq(wm:attention_windows(), {}, "unmuting doesn't bring old marks back")
    wm.attention:activated(1, "com.example.chat")
    t.eq(wm:attention_windows(), { 1 })
end)

t.test("a muted site silences a browser window whose front tab is on it", function()
    local _, wm = setup()
    wm:set_muted(mute.parse({ "site:chat.example.com" }, "x"))
    wm.attention:activated(2, "com.google.Chrome")
    t.eq(wm:attention_windows(), { 2 }, "tilemo hasn't seen the window's tabs yet")
    wm:note_tabs({
        { win = 2, active = false, url = "https://docs.example.com/" },
        { win = 2, active = true, url = "https://chat.example.com/room/1" },
    })
    t.eq(wm:attention_windows(), {}, "learning the front tab clears its mark")
    wm.attention:title(2, "com.google.Chrome", "Room (4) - Google Chrome")
    t.eq(wm:attention_windows(), {})
    -- Another tab in front: marks come back.
    wm:note_tabs({ { win = 2, active = true, url = "https://docs.example.com/" } })
    wm.attention:activated(2, "com.google.Chrome")
    t.eq(wm:attention_windows(), { 2 })
end)

t.test("a muted window's focus theft is still handed back, just not marked", function()
    local a, wm = setup()
    wm:set_muted(mute.parse({ "com.example.chat" }, "x"))
    a.focus_ = 3
    wm:focused_window(3)
    wm.last_input = -math.huge
    a.focus_ = 1
    wm:focused_window(1)
    t.eq(a.focus_, 3)
    t.eq(wm:attention_windows(), {})
end)

t.test("an entry typed in Settings is refused if malformed or muted already, saying why", function()
    local set = mute.parse({ "com.example.chat", "site:chat.example.com" }, "workspaces.json")
    t.eq(mute.add_problem(set, "com.example.mail"), nil)
    t.eq(mute.add_problem(set, "site:mail.example.com"), nil)
    t.eq(mute.add_problem(set, "com.example.chat"), "com.example.chat is muted already")
    t.eq(mute.add_problem(set, "site:Chat.Example.com"), "chat.example.com is muted already", "a site ignoring case")
    t.eq(mute.add_problem(set, ""), "type an app's bundle id, or site: and a host")
    t.eq(mute.add_problem(set, "com.example chat"), "\"com.example chat\" has a space in it")
    t.eq(mute.add_problem(set, "site:https://x.example.com/a"), "\"site:https://x.example.com/a\" has more than a host after site: (a scheme, a path or a port)")
end)

t.done("mute")
