-- The name prompt and TIDE_WORKSPACE (SPEC.md §6.2, §6.3), against the
-- window manager: what asks, and what each answer does. The prompt itself
-- is an hs.chooser (prompt_hs.lua); here a stand-in records each question.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")
local keys = require("tilemo.keys")

-- tilemo started with `n` windows, ready to ask, with every question
-- recorded: `asked` holds window ids, `launches` the launch prompts'
-- { default, done }.
local function setup(n)
    local a = fake.new()
    for i = 1, n or 0 do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    wm:retile()
    local asked, launches = {}, {}
    wm.ask_name = function(id)
        asked[#asked + 1] = id
    end
    wm.ask_launch = function(default, done)
        launches[#launches + 1] = { default = default, done = done }
    end
    wm.ready = true
    a.calls = {}
    return a, wm, asked, launches
end

local function open(a, wm, id, f)
    a.add(id, f or {})
    wm:schedule()
    a.tick()
end

local function app_key(key, shift)
    for _, b in ipairs(keys.map) do
        if b.key == key and (b.shift or false) == (shift or false) and b.action == "app" then
            return b.arg
        end
    end
end

t.test('a new window on "in" asks for a name; windows found at start don\'t', function()
    local a, wm, asked = setup(2)
    t.eq(asked, {}, "the windows already open")
    open(a, wm, 3)
    t.eq(asked, { 3 })
    t.eq(wm.windows[3].ws, "in", "it stays put until you answer")
    t.eq(wm.holding_keyboard, true, "focus follows mouse pauses")
end)

t.test('"in"\'s apps, dialogs, and windows on other workspaces don\'t ask', function()
    local a, wm, asked = setup(1)
    open(a, wm, 2, { name = "Mail" })
    open(a, wm, 3, { subrole = "AXDialog" })
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    open(a, wm, 4)
    t.eq(asked, {})
    t.eq(wm.windows[4].ws, "web")
end)

t.test("Enter makes the workspace, moves the window there and shows it, with focus", function()
    local a, wm, asked = setup(1)
    open(a, wm, 2, { title = "ABC-123" })
    a.calls = {}
    wm:answer(2, "ABC-123")
    for _, c in ipairs(a.calls) do
        t.eq(c ~= "minimize 2", true, "never hidden on the way")
    end
    t.eq(wm.windows[2].ws, "ABC-123")
    t.eq(wm.names, { "in", "ABC-123" })
    t.eq(wm.screen_ws.A, "ABC-123")
    t.eq(a.focus_, 2)
    t.eq(wm.holding_keyboard, false)
    t.eq(asked, { 2 })
end)

t.test("a name with quotes, backslashes or control characters is refused, and asked again", function()
    local a, wm, asked = setup(1)
    open(a, wm, 2, { title = "ABC-123" })
    for i, bad in ipairs({ 'team "x"', "it's", "a`b", "a\\b", "a\27]0;x\7" }) do
        wm:answer(2, bad)
        t.eq(wm.windows[2].ws, "in", bad)
        t.eq(#a.notes, i, bad)
        t.eq(a.notes[i], "A workspace's name can't have quotes, backslashes or control characters")
        t.eq(#asked, i + 1, "asked again: " .. bad)
        t.eq(wm.holding_keyboard, true, "still asking")
    end
    t.eq(wm.names, { "in" }, "nothing made")
    -- A tab or a newline is space, as ever, not a refusal.
    wm:answer(2, "ABC\t123")
    t.eq(wm.windows[2].ws, "ABC 123")
end)

t.test("a launch named with what a name can't hold is refused, and asked again without it", function()
    local a, wm, _, launches = setup(1)
    wm:act("app", app_key("g"))
    launches[1].done('PR "12"')
    t.eq(#a.launched, 0)
    t.eq(#a.notes, 1)
    t.eq(#launches, 2)
    t.eq(launches[2].default, "PR 12")
    launches[2].done("PR 12")
    t.eq(#a.launched, 1)
    t.eq(wm.screen_ws.A, "PR 12")
end)

t.test("Enter on an existing name, in any case, uses that workspace", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "Web")
    open(a, wm, 2)
    wm:answer(2, "web")
    t.eq(wm.names, { "in", "Web" })
    t.eq(wm.windows[2].ws, "Web")
    t.eq(wm.workspaces.Web.order, { 1, 2 })
    t.eq(wm.screen_ws.A, "Web")
end)

t.test("Esc closes the window, politely", function()
    local a, wm = setup(1)
    open(a, wm, 2)
    a.calls = {}
    wm:answer(2, nil)
    t.eq(a.calls, { "close 2" })
    t.eq(wm.names, { "in" })
    t.eq(wm.holding_keyboard, false)
end)

t.test('"in" itself is refused, and the window asks again', function()
    local a, wm, asked = setup(1)
    open(a, wm, 2)
    wm:answer(2, "IN")
    t.eq(#a.notes, 1)
    t.eq(asked, { 2, 2 })
    t.eq(wm.windows[2].ws, "in")
    wm:answer(2, "   ")
    t.eq(asked, { 2, 2, 2 }, "a blank name asks again too")
end)

t.test("one prompt at a time: the next window asks once the first is answered", function()
    local a, wm, asked = setup(1)
    open(a, wm, 2)
    open(a, wm, 3)
    open(a, wm, 4)
    t.eq(asked, { 2 })
    wm:answer(3, "x")
    t.eq(wm.windows[3].ws, "in", "only the window being asked about can be answered")
    -- 3 closes while it waits: it's passed over.
    a.drop(3)
    wm:schedule()
    a.tick()
    wm:answer(2, "two")
    t.eq(asked, { 2, 4 })
    t.eq(wm.holding_keyboard, true)
end)

t.test("a window gone before its answer leaves nothing behind", function()
    local a, wm = setup(1)
    open(a, wm, 2)
    a.drop(2)
    wm:schedule()
    a.tick()
    wm:answer(2, "two")
    t.eq(wm.names, { "in" })
    t.eq(wm.holding_keyboard, false)
end)

t.test("a launch from \"in\" asks first; the name's workspace shows and the launch gets its TIDE_WORKSPACE", function()
    local a, wm, _, launches = setup(1)
    a.app_names["com.google.Chrome"] = "Google Chrome"
    wm:act("app", { bundle = "com.google.Chrome" })
    t.eq(#launches, 1)
    t.eq(launches[1].default, "Google Chrome", "no title yet: the app's name")
    t.eq(#a.launched, 0, "nothing starts until you answer")
    t.eq(wm.holding_keyboard, true)
    launches[1].done("PR-12 login")
    t.eq(wm.holding_keyboard, false)
    t.eq(wm.screen_ws.A, "PR-12 login")
    t.eq(#a.launched, 1)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "PR12login" })
    -- Its window opens on the workspace showing, and doesn't ask.
    open(a, wm, 2, { app = "com.google.Chrome" })
    t.eq(wm.windows[2].ws, "PR-12 login")
end)

t.test("a launch to a name past ASCII gets what JavaScript keeps of it, or an empty value, logged", function()
    local a, wm, _, launches = setup(1)
    local scripts, logs = {}, {}
    function a.javascript(source)
        scripts[#scripts + 1] = source
        return true, "Équipe2"
    end
    function a.log(text)
        logs[#logs + 1] = text
    end
    wm:act("app", app_key("g"))
    launches[1].done("Équipe 2")
    t.eq(#scripts, 1, "the name went to JavaScript")
    t.eq(a.envs[1], { TIDE_WORKSPACE = "Équipe2" })
    function a.javascript()
        return false, "no JavaScriptCore"
    end
    wm:act("app", app_key("g"))
    t.eq(#a.launched, 2, "on a workspace other than home, it launches straight away")
    t.eq(a.envs[2], { TIDE_WORKSPACE = "" }, "not a guess")
    t.eq(logs, { "TIDE_WORKSPACE is empty: couldn't keep the workspace's letters and digits: no JavaScriptCore" })
end)

t.test("Esc cancels a launch from \"in\": nothing opens", function()
    local a, wm, _, launches = setup(1)
    wm:act("app", app_key("g"))
    launches[1].done(nil)
    t.eq(#a.launched, 0)
    t.eq(wm.names, { "in" })
    t.eq(wm.holding_keyboard, false)
end)

t.test('a launch named "in" is refused, and nothing opens', function()
    local a, wm, _, launches = setup(1)
    wm:act("app", app_key("g"))
    launches[1].done("in")
    t.eq(#a.launched, 0)
    t.eq(#a.notes, 1)
end)

t.test("an app key for one of \"in\"'s apps doesn't ask", function()
    local a, wm, _, launches = setup(1)
    wm:act("app", app_key("c", true))
    wm:act("app", app_key("y"))
    t.eq(#launches, 0)
    t.eq(#a.launched, 2)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "in" })
end)

t.test("from another workspace, a launch starts straight away with that workspace's name", function()
    local a, wm, _, launches = setup(1)
    a.focus_ = 1
    wm:act("send", "my-repo")
    wm:act("show", "my-repo")
    wm:act("app", app_key("t"))
    t.eq(#launches, 0)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "myrepo" })
end)

t.test("Super+T from \"in\" asks too, since it always opens a window", function()
    local a, wm, _, launches = setup(1)
    wm:act("app", app_key("t"))
    t.eq(#launches, 1)
    launches[1].done("shell")
    t.eq(a.fresh[1], true)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "shell" })
end)

t.test("Cmd+Return asks from any workspace, and opens a new window on the one named", function()
    local a, wm, _, launches = setup(1)
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    wm.actions.app(wm, { bundle = "com.apple.TextEdit", name = "TextEdit" }, true)
    t.eq(launches[1].default, "TextEdit")
    launches[1].done("notes")
    t.eq(wm.screen_ws.A, "notes")
    t.eq(a.fresh[1], true)
    t.eq(a.envs[1], { TIDE_WORKSPACE = "notes" })
end)

t.test("an app key with a window open brings it forward without asking", function()
    local a, wm, _, launches = setup(1)
    a.wins[1].app = "com.google.Chrome"
    wm.windows[1].app = "com.google.Chrome"
    wm:act("app", { bundle = "com.google.Chrome" })
    t.eq(#launches, 0)
    t.eq(#a.launched, 0)
end)

t.test("with no prompt to ask (before start finishes), a launch goes ahead here", function()
    local a, wm = setup(1)
    wm.ask_launch = nil
    wm:act("app", app_key("g"))
    t.eq(a.envs[1], { TIDE_WORKSPACE = "in" })
end)

t.test("a launch asked while a window's prompt is open waits its turn, and neither cancels the other", function()
    local a, wm, asked, launches = setup(1)
    open(a, wm, 2)
    t.eq(asked, { 2 })
    wm:act("app", app_key("g"))
    t.eq(#launches, 0, "the window's question is still open")
    open(a, wm, 3)
    t.eq(asked, { 2 }, "and so does a window behind it")
    wm:answer(2, nil)
    t.eq(a.calls[#a.calls], "close 2", "Esc on the window closes only it")
    t.eq(#launches, 1, "then the launch asks")
    t.eq(asked, { 2 })
    launches[1].done("web")
    t.eq(#a.launched, 1, "the launch went ahead")
    t.eq(asked, { 2, 3 }, "then the window behind it, still on home")
end)

t.test("the prompt is the home workspace's, whatever it's called", function()
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, { workspaces = { "work", "in" } })
    wm:sync()
    local asked = {}
    wm.ask_name = function(id)
        asked[#asked + 1] = id
    end
    wm.ready = true
    open(a, wm, 2)
    t.eq(asked, { 2 })
    wm:answer(2, "in")
    t.eq(wm.windows[2].ws, "in", '"in" is just a name here')
    wm:act("show", "in")
    open(a, wm, 3)
    t.eq(asked, { 2 }, "a window opening on in doesn't ask")
end)

t.test("a window asks after a launch's prompt is answered", function()
    local a, wm, asked, launches = setup(1)
    wm:act("app", app_key("g"))
    open(a, wm, 2)
    t.eq(asked, {})
    launches[1].done(nil)
    t.eq(#a.launched, 0)
    t.eq(asked, { 2 })
    t.eq(wm.holding_keyboard, true)
end)

t.test("each launch's window goes to the workspace chosen for it, though another was chosen since", function()
    local a, wm, _, launches = setup(1)
    wm:act("app", { bundle = "com.google.Chrome", name = "Chrome" })
    wm:act("app", { bundle = "com.apple.TextEdit", name = "TextEdit" })
    launches[1].done("web")
    launches[2].done("notes")
    t.eq(wm.screen_ws.A, "notes")
    -- Chrome's window arrives late, after the second answer.
    open(a, wm, 2, { app = "com.google.Chrome" })
    t.eq(wm.windows[2].ws, "web", "where its launch was for")
    t.eq(a.envs[1], { TIDE_WORKSPACE = "web" }, "and where its TIDE_WORKSPACE says")
    t.eq(wm:attention_windows(), { 2 }, "marked, since web isn't showing")
    open(a, wm, 3, { app = "com.apple.TextEdit" })
    t.eq(wm.windows[3].ws, "notes")
    -- Each launch is used once: Chrome's next window opens where you are.
    open(a, wm, 4, { app = "com.google.Chrome" })
    t.eq(wm.windows[4].ws, "notes")
end)

t.test("a launch's window goes where you launched it from, after you've moved on", function()
    local a, wm = setup(1)
    a.focus_ = 1
    wm:act("send", "web")
    wm:act("show", "web")
    wm:act("app", app_key("g"))
    t.eq(a.envs[1], { TIDE_WORKSPACE = "web" })
    wm:act("home")
    open(a, wm, 2, { app = "com.google.Chrome" })
    t.eq(wm.windows[2].ws, "web")
    -- A launch lapses after the grant's time.
    wm:act("show", "web")
    wm:act("app", app_key("g"))
    wm:act("home")
    a.clock = a.clock + wm_mod.GRANT + 1
    open(a, wm, 3)
    t.eq(wm.windows[3].ws, "in", "too late: it opens where you are")
end)

t.test("switching to an empty workspace that leaves focus on the other display updates the current workspace", function()
    local a = fake.new()
    a.screens_[2] = { uuid = "B", area = { x = 1920, y = 25, w = 1920, h = 1055 }, full = { x = 1920, y = 0, w = 1920, h = 1080 } }
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:reconcile()
    a.focus_ = 1
    local seen
    wm.on_change = function()
        seen = wm:current_ws()
    end
    wm:show("web", nil, true)
    t.eq(wm:current_ws(), "web")
    t.eq(seen, "web", "told after the keys moved, not before")
end)

t.done("prompt")
