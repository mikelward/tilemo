local t = require("t")
local json = require("json")
local standing = require("tide.standing")

local DIR = "/home/user/.config/tide"

local function load(files)
    return standing.load(DIR, function(path)
        return files[path:match("[^/]*$")]
    end, json.decode)
end

t.test("with no files, neither list is set, for start()'s to stand in", function()
    local s, errors = load({})
    t.eq(s, { from = {} })
    t.eq(errors, {})
end)

t.test("each list is the .local file's if it sets one, else the shared file's", function()
    local s = load({
        ["workspaces.json"] = '{"standing": ["in", "re"], "inApps": ["gmail"], "muted": ["x"]}',
        ["workspaces.local.json"] = '{"inApps": ["Mail", "Google Chat"]}',
    })
    t.eq(s.standing, { "in", "re" })
    t.eq(s.inApps, { "Mail", "Google Chat" })
    t.eq(s.from, { standing = "workspaces.json", inApps = "workspaces.local.json" })
end)

t.test("a list tide wouldn't take is an error at load, naming the file and the setting", function()
    local function err(text)
        local s, errors = load({ ["workspaces.local.json"] = text })
        t.eq(s, nil)
        return table.concat(errors, "; ")
    end
    t.eq(err('{"standing": []}'), "workspaces.local.json: standing must name at least one workspace, the first being home")
    t.eq(err('{"standing": ["in", "IN"]}'), 'workspaces.local.json: standing names "IN" twice')
    -- Names the window manager takes as one, spaces collapsed, are one here.
    t.eq(err('{"standing": ["a b", "a  b"]}'), 'workspaces.local.json: standing names "a  b" twice')
    t.eq(err('{"standing": ["in", "a\\"b"]}'):find("can't have quotes", 1, true) ~= nil, true)
    t.eq(err('{"standing": [" in"]}'), 'workspaces.local.json: standing: " in" has space around it')
    t.eq(err('{"standing": ["' .. string.rep("x", 33) .. '"]}'):find("at most 32 characters", 1, true) ~= nil, true)
    t.eq(err('{"standing": "in"}'), "workspaces.local.json: standing must be a list")
    t.eq(err('{"inApps": ["Mail", ""]}'), 'workspaces.local.json: inApps must list text, not "" at 2')
    t.eq(err('{"inApps": ["Mail", 3]}'), "workspaces.local.json: inApps must list text, not 3 at 2")
    t.eq(err("{"), "workspaces.local.json: not a JSON object")
end)

t.test("each file is checked whole, as tide checks it, even where the .local file's lists win", function()
    local s, errors = load({
        ["workspaces.json"] = '{"standing": []}',
        ["workspaces.local.json"] = '{"standing": ["in"], "inApps": []}',
    })
    t.eq(s, nil)
    t.eq(errors, { "workspaces.json: standing must name at least one workspace, the first being home" })
    s, errors = load({ ["workspaces.json"] = "[1]", ["workspaces.local.json"] = '{"standing": ["in"]}' })
    t.eq(s, nil)
    t.eq(errors, { "workspaces.json: not a JSON object" })
end)

t.test("home's apps compare ignoring case, with spaces and hyphens alike", function()
    t.eq(standing.app_key("Google Calendar"), standing.app_key("google-calendar"))
    t.eq(standing.app_key("YouTube Music"), "youtube-music")
    t.eq(standing.app_key("Mail"), standing.app_key("mail"))
    t.eq(standing.app_key("Mail") == standing.app_key("Gmail"), false)
end)

t.test("an entry is looked for as a Mac app by its name, and with hyphens as spaces", function()
    t.eq(standing.app_candidates("Mail"), { "Mail" })
    t.eq(standing.app_candidates("google-chat"), { "google-chat", "google chat" })
    t.eq(standing.app_candidates("https://mail.google.com"), {}, "a web address is tide's")
    t.eq(standing.app_candidates("a/b"), {})
    local paths = standing.app_paths("Gmail", "/Users/me")
    t.eq(paths[1], "/Applications/Gmail.app")
    t.eq(paths[#paths], "/Users/me/Applications/Chrome Apps.localized/Gmail.app")
end)

t.done("standing")
