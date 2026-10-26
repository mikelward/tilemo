-- Restarts (SPEC.md §6.3): windows that come back with new ids, after tilemo
-- restarts or their app relaunches, go back to their places by app and
-- title.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tilemo.wm")

local function start(a, saved)
    local wm = wm_mod.new(a, { saved = saved })
    wm:sync()
    wm:reconcile()
    wm:retile()
    return wm
end

local function place(app, title, ws, pos)
    return { app = app, title = title, ws = ws, mine = false, pos = pos }
end

t.test("after a restart, windows with new ids go back by app and title", function()
    local a = fake.new()
    a.add(10, { app = "mail", pid = 200, title = "Drafts" })
    a.add(11, { app = "mail", pid = 200, title = "Inbox" })
    local wm = start(a, {
        windows = { ["1"] = place("mail", "Inbox", 3, 1), ["2"] = place("mail", "Drafts", 4, 1) },
        screens = { A = 1 },
    })
    t.eq(wm.windows[11].ws, 3, "Inbox")
    t.eq(wm.windows[10].ws, 4, "Drafts")
    t.eq(a.wins[10].minimized, true, "hidden with its workspace")
end)

t.test("the closest title wins, whichever window is found first", function()
    local a = fake.new()
    -- Found first, and like both saved titles, but more like the second.
    a.add(10, { app = "mail", pid = 200, title = "Inbox (5) - Mail" })
    a.add(11, { app = "mail", pid = 200, title = "Inbox (3) - Mail" })
    local wm = start(a, {
        windows = { ["1"] = place("mail", "Inbox (3) - Mail", 3), ["2"] = place("mail", "Inbox (9) - Mail", 4) },
        screens = { A = 1 },
    })
    t.eq(wm.windows[11].ws, 3, "the same title")
    t.eq(wm.windows[10].ws, 4, "the one left")
end)

t.test("a window only takes a place its app left", function()
    local a = fake.new()
    a.add(10, { app = "chat", pid = 201, title = "Inbox" })
    local wm = start(a, { windows = { ["1"] = place("mail", "Inbox", 3) }, screens = { A = 1 } })
    t.eq(wm.windows[10].ws, 1, "joins the workspace showing")
end)

t.test("an id reused by another app doesn't take that window's place, which stays for its app", function()
    local a = fake.new()
    a.add(7, { app = "chat", pid = 201, title = "Chat" })
    local wm = start(a, { windows = { ["7"] = place("mail", "Inbox", 3) }, screens = { A = 1 } })
    t.eq(wm.windows[7].ws, 1, "another app's window")
    a.add(8, { app = "mail", pid = 200, title = "Inbox" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[8].ws, 3, "the app it was saved for")
end)

t.test("an id reused by an app that also has a place doesn't lose the other app's place", function()
    local a = fake.new()
    a.add(7, { app = "chat", pid = 201, title = "Chat" })
    local wm = start(a, {
        windows = { ["7"] = place("mail", "Inbox", 3), ["8"] = place("chat", "Chat", 4) },
        screens = { A = 1 },
    })
    t.eq(wm.windows[7].ws, 4, "chat's place")
    a.add(9, { app = "mail", pid = 200, title = "Inbox" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[9].ws, 3, "mail's place")
end)

t.test("an app's windows come back in their old stack order", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "One" })
    a.add(2, { app = "docs", pid = 202, title = "Two" })
    a.add(3, { app = "other", pid = 203, title = "Other" })
    local wm = start(a, {})
    t.eq(wm.workspaces[1].order, { 1, 2, 3 })
    a.drop(1)
    a.drop(2)
    wm:schedule()
    a.tick()
    a.add(5, { app = "docs", pid = 202, title = "One" })
    a.add(6, { app = "docs", pid = 202, title = "Two" })
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 5, 6, 3 })
end)

t.test("a window back from a relaunch keeps its index among the windows that stayed", function()
    local a = fake.new()
    a.add(1, { app = "other", pid = 203, title = "Other" })
    a.add(2, { app = "docs", pid = 202, title = "Docs" })
    local wm = start(a, {})
    t.eq(wm.workspaces[1].order, { 1, 2 })
    a.drop(2)
    wm:schedule()
    a.tick()
    a.add(5, { app = "docs", pid = 202, title = "Docs" })
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 1, 5 }, "not master")
end)

t.test("windows back from a relaunch fit between the ones that stayed", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "One" })
    a.add(2, { app = "other", pid = 203, title = "Other" })
    a.add(3, { app = "docs", pid = 202, title = "Three" })
    local wm = start(a, {})
    a.drop(1)
    a.drop(3)
    wm:schedule()
    a.tick()
    a.add(6, { app = "docs", pid = 202, title = "Three" })
    a.add(5, { app = "docs", pid = 202, title = "One" })
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 5, 2, 6 })
end)

t.test("windows coming back one sync at a time keep their old order", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "One" })
    a.add(2, { app = "docs", pid = 202, title = "Two" })
    a.add(3, { app = "docs", pid = 202, title = "Three" })
    local wm = start(a, {})
    a.drop(1)
    a.drop(2)
    a.drop(3)
    wm:schedule()
    a.tick()
    for i, title in ipairs({ "Three", "Two", "One" }) do
        a.add(10 + i, { app = "docs", title = title })
        wm:schedule()
        a.tick()
    end
    t.eq(wm.workspaces[1].order, { 13, 12, 11 })
end)

t.test("windows found by a focus report keep their old order too", function()
    local a = fake.new()
    a.add(11, { title = "Three" })
    a.add(12, { title = "One" })
    local wm = wm_mod.new(a, { saved = {
        windows = {
            ["1"] = place("com.example.app", "One", 1, 1),
            ["2"] = place("com.example.app", "Two", 1, 2),
            ["3"] = place("com.example.app", "Three", 1, 3),
        },
        screens = { A = 1 },
    } })
    wm:focused(11)
    wm:focused(12)
    a.add(13, { title = "Two" })
    wm:focused(13)
    t.eq(wm.workspaces[1].order, { 12, 13, 11 })
end)

t.test("a relaunched app already running again at the next sync gets its places", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 10, title = "Plan" })
    local wm = start(a, {})
    a.focus_ = 1
    wm:act("send", 3)
    -- It quits and is back, as a new process, before tilemo looks again.
    a.drop(1)
    a.add(5, { app = "docs", pid = 11, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 3)
end)

t.test("a relaunched app's window focused before the next sync still gets its place", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 10, title = "Plan" })
    local wm = start(a, {})
    a.focus_ = 1
    wm:act("send", 3)
    a.drop(1)
    a.add(5, { app = "docs", pid = 11, title = "Plan" })
    wm:focused(5)
    t.eq(wm.windows[5].ws, 3)
end)

t.test("a stack you rearrange stays that way across a restart, with places pending", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 10, title = "A" })
    a.add(2, { app = "docs", pid = 10, title = "B" })
    a.add(3, { app = "docs", pid = 10, title = "C" })
    local wm = start(a, {})
    a.clock = 5
    a.drop(1)
    a.drop(2)
    a.drop(3)
    wm:schedule()
    a.tick()
    a.add(11, { app = "docs", pid = 11, title = "A" })
    a.add(12, { app = "docs", pid = 11, title = "B" })
    wm:schedule()
    a.tick()
    t.eq(wm.workspaces[1].order, { 11, 12 }, "back in order")
    -- C is still to come. You swap B into the master.
    a.focus_ = 12
    wm:act("swap_master")
    t.eq(wm.workspaces[1].order, { 12, 11 }, "swapped")
    -- The next save, as any reconcile makes.
    wm:save()
    a.clock = 20
    wm = start(a, a.saved)
    t.eq(wm.workspaces[1].order, { 12, 11 }, "after the restart")
end)

t.test("saved ids still match their own windows, in their old order", function()
    local a = fake.new()
    -- Found in a different order from their stack.
    a.add(3, { title = "c" })
    a.add(1, { title = "a" })
    a.add(2, { title = "b" })
    local wm = start(a, {
        windows = {
            ["1"] = place("com.example.app", "a", 1, 1),
            ["2"] = place("com.example.app", "b", 1, 2),
            ["3"] = place("com.example.app", "c", 1, 3),
        },
        screens = { A = 1 },
    })
    t.eq(wm.workspaces[1].order, { 1, 2, 3 })
end)

t.test("an app that quits and relaunches gets its windows back where they were", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "Plan" })
    a.add(2, { app = "docs", pid = 202, title = "Notes" })
    local wm = start(a, {})
    a.focus_ = 1
    wm:act("send", 2)
    a.focus_ = 2
    wm:act("send", 3)
    -- It quits.
    a.drop(1)
    a.drop(2)
    wm:schedule()
    a.tick()
    t.eq(#wm.gone, 2, "places kept")
    -- It relaunches, the windows in the other order, with new ids.
    a.clock = 30
    a.add(5, { app = "docs", pid = 202, title = "Notes" })
    a.add(6, { app = "docs", pid = 202, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 3, "Notes")
    t.eq(wm.windows[6].ws, 2, "Plan")
    t.eq(#wm.gone, 0, "each place taken once")
end)

t.test("a window you close while its app runs leaves no place", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "Plan" })
    a.add(2, { app = "docs", pid = 202, title = "Notes" })
    local wm = start(a, {})
    a.focus_ = 2
    wm:act("send", 3)
    a.drop(2)
    wm:schedule()
    a.tick()
    a.add(5, { app = "docs", pid = 202, title = "Notes" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 1, "joins the workspace showing")
end)

t.test("places lapse", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "Plan" })
    local wm = start(a, {})
    a.focus_ = 1
    wm:act("send", 3)
    a.drop(1)
    wm:schedule()
    a.tick()
    a.clock = wm_mod.KEEP + 1
    a.add(5, { app = "docs", pid = 202, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 1, "an app's quit place")

    a = fake.new()
    a.clock = 1000
    wm = start(a, { windows = { ["1"] = place("docs", "Plan", 3) }, screens = { A = 1 } })
    a.clock = 1000 + wm_mod.KEEP + 1
    a.add(5, { app = "docs", pid = 202, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 1, "a saved place")
end)

t.test("places not yet taken survive another restart", function()
    local a = fake.new()
    a.add(1, { app = "docs", pid = 202, title = "Plan" })
    local wm = start(a, {})
    a.focus_ = 1
    wm:act("send", 3)
    a.drop(1)
    wm:schedule()
    a.tick()
    -- tilemo restarts before the app comes back...
    local snap = a.saved
    t.eq(#snap.gone, 1, "saved")
    wm = start(a, snap)
    a.add(5, { app = "docs", pid = 202, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 3, "an app's quit place")

    -- ...and a saved window that hasn't come back by the next save is kept
    -- for it, as at login while apps are still opening theirs.
    a = fake.new()
    wm = start(a, { windows = { ["1"] = place("docs", "Plan", 3) }, screens = { A = 1 } })
    snap = a.saved
    t.eq(#snap.gone, 1, "carried over")
    wm = start(a, snap)
    a.add(5, { app = "docs", pid = 202, title = "Plan" })
    wm:schedule()
    a.tick()
    t.eq(wm.windows[5].ws, 3, "a saved place")
end)

t.test("a window's title is saved, as it is now", function()
    local a = fake.new()
    a.add(1, { title = "Chat" })
    local wm = start(a, {})
    a.wins[1].title = "Chat (2)"
    wm:poll_attention()
    wm:save()
    t.eq(a.saved.windows[1].title, "Chat (2)")
    t.eq(a.saved.windows[1].app, "com.example.app")
    t.eq(a.saved.windows[1].pos, 1)
end)

t.done("restart")
