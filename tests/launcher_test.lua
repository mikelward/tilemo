local t = require("t")
local launcher = require("tilemo.launcher")

t.test("every query character must appear, in order", function()
    t.eq(launcher.score("gc", "Google Calendar") ~= nil, true)
end)

t.test("a query that's out of order doesn't match", function()
    t.eq(launcher.score("zx", "Safari"), nil)
end)

t.test("word starts and the prefix score higher", function()
    local gc = launcher.score("gc", "Google Calendar")
    local mid = launcher.score("gc", "Bigcat")
    t.eq(gc > mid, true)
    t.eq(launcher.score("saf", "Safari") > launcher.score("saf", "Mesafe"), true)
end)

t.test("an empty query matches everything with score 0", function()
    t.eq(launcher.score("", "anything"), 0)
end)

t.test("two tabs on the same page can each be chosen", function()
    local items = launcher.items({}, {
        { title = "Docs", url = "https://example.com/", browser = "Google Chrome", window = 1, tab = 1 },
        { title = "Docs", url = "https://example.com/", browser = "Safari", window = 1, tab = 1 },
    })
    t.eq(items[1].key, items[2].key)
    t.eq(items[1].id ~= items[2].id, true)
end)

local function sample()
    return launcher.items(
        { { name = "Safari", path = "/Applications/Safari.app" }, { name = "Calendar", path = "/System/Applications/Calendar.app" } },
        { { title = "Google Chat", url = "https://chat.google.com/x", browser = "Google Chrome", window = 1, tab = 2 } },
        { { title = "Lock", quick = "lock" } }
    )
end

t.test("rank orders by score, best first", function()
    local found = launcher.rank("cal", sample())
    t.eq(found[1].title, "Calendar")
end)

t.test("a tab matches by its host, counted for less than a title", function()
    local found = launcher.rank("chat.google", sample())
    t.eq(found[1].kind, "tab")
end)

t.test("ties go to the most recently used", function()
    local items = launcher.items({ { name = "Notes", path = "/a/Notes.app" }, { name = "Notes", path = "/b/Notes.app" } })
    local found = launcher.rank("notes", items, { recency = { ["app:/b/Notes.app"] = 10 } })
    t.eq(found[1].path, "/b/Notes.app")
end)

t.test("an empty query lists tabs, then apps, then commands", function()
    local found = launcher.rank("", sample())
    t.eq(found[1].kind, "tab")
    t.eq(found[#found].kind, "command")
end)

t.test("a scope with no match falls back to every scope", function()
    local found = launcher.rank("google chat", sample(), { scope = "launch" })
    t.eq(found[1].kind, "tab")
    t.eq(#launcher.rank("lock", sample(), { scope = "tabs" }), 1)
end)

t.test("items have stable keys", function()
    local items = sample()
    t.eq(items[1].key, "app:/Applications/Safari.app")
    t.eq(items[3].key, "tab:https://chat.google.com/x")
    t.eq(items[4].key, "command:Lock")
end)

t.test("every command names a window manager action or a quick action", function()
    local wm = require("tilemo.wm")
    for _, c in ipairs(launcher.COMMANDS) do
        t.eq(c.quick ~= nil or type(wm.actions[c.action]) == "function", true, c.title)
    end
end)

t.done("launcher")
