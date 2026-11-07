-- Who sent a notification, from its banner (SPEC.md §14.2).

local t = require("t")
local notices = require("tide.notices")
local fake = require("fake")
local wm_mod = require("tide.wm")

t.test("a banner or alert is a notification; their stack isn't", function()
    t.eq(notices.is_banner("AXNotificationCenterBanner"), true)
    t.eq(notices.is_banner("AXNotificationCenterAlert"), true)
    t.eq(notices.is_banner("AXNotificationCenterAlertStack"), false)
    t.eq(notices.is_banner("AXStandardWindow"), false)
    t.eq(notices.is_banner(nil), false)
end)

t.test("the sender is the stacking identifier's bundle ID, else the description's app name", function()
    t.eq(notices.sender("Mail, Ann, Lunch?", "bundleIdentifier=com.apple.mail,threadIdentifier=x"),
        { app = "com.apple.mail", name = "Mail" })
    t.eq(notices.sender("Mail, Ann, Lunch?", "com.apple.mail"), { app = "com.apple.mail", name = "Mail" })
    t.eq(notices.sender("Messages, Ann, hi", nil), { name = "Messages" })
    t.eq(notices.sender("", nil), nil)
    t.eq(notices.sender(nil, nil), nil)
end)

t.test("a browser's notification names its site; another app's doesn't", function()
    t.eq(notices.sender("Google Chrome, mail.google.com, New message from Ann", nil),
        { app = "com.google.Chrome", name = "Google Chrome", site = "mail.google.com" })
    t.eq(notices.sender("Google Chrome, Chat.Google.com, Ann: hi", "bundleIdentifier=com.google.Chrome").site, "chat.google.com")
    t.eq(notices.sender("Google Chrome, Download done", nil).site, nil, "no host")
    t.eq(notices.sender("Mail, ann.example.com, hi", "com.apple.mail").site, nil, "not a browser")
end)

-- A Chrome window on Mail and one on Chat, and Notes focused.
local function setup()
    local a = fake.new()
    a.add(1, { app = "com.apple.Notes", title = "Notes" })
    a.add(2, { app = "com.google.Chrome", title = "Inbox (3)" })
    a.add(3, { app = "com.google.Chrome", title = "Chat" })
    local wm = wm_mod.new(a, { workspaces = { "in" } })
    wm:sync()
    wm:focus_window(1)
    wm:focused(1)
    wm:note_tabs({
        { win = 2, active = true, url = "https://mail.google.com/" },
        { win = 3, active = true, url = "https://chat.google.com/" },
    })
    return a, wm
end

t.test("a notification marks the browser window on its site, else the app's last used", function()
    local _, wm = setup()
    wm:notified("com.google.Chrome", "chat.google.com")
    t.eq(wm:attention_windows(), { 3 })
    wm:notified("com.google.Chrome", "docs.google.com")
    t.eq(wm:attention_windows()[1] ~= nil, true, "a site with no window still marks the app")
end)

t.test("a window's title count rising marks nothing", function()
    local a, wm = setup()
    a.wins[2].title = "Inbox (4)"
    wm:poll_attention()
    t.eq(wm:attention_windows(), {})
end)

t.test("the app you're in, and the window you're in, aren't marked", function()
    local a, wm = setup()
    wm:notified("com.apple.Notes")
    wm:rang(1)
    t.eq(wm:attention_windows(), {})
    wm:focus_window(3)
    wm:focused(3)
    wm:notified("com.google.Chrome", "chat.google.com")
    t.eq(wm:attention_windows(), {}, "Chat's own window is in front")
    wm:notified("com.google.Chrome", "mail.google.com")
    t.eq(wm:attention_windows(), { 2 })
end)

t.test("a bell marks its window until you focus it", function()
    local a, wm = setup()
    wm:rang(3)
    wm:rang(99)
    t.eq(wm:attention_windows(), { 3 }, "an unknown window is ignored")
    t.eq(require("tide.bar").state(wm, "A", "", {}).workspaces[1].urgent, true)
    wm:focus_window(3)
    wm:focused(3)
    t.eq(wm:attention_windows(), {})
end)

t.test("a background browser window's notification outlasts the poll in another of its windows", function()
    local _, wm = setup()
    wm:focus_window(3)
    wm:focused(3)
    wm:notified("com.google.Chrome", "mail.google.com")
    wm:poll_attention()
    t.eq(wm:attention_windows(), { 2 })
    wm:focus_window(2)
    wm:focused(2)
    t.eq(wm:attention_windows(), {})
end)

t.done("notices")
