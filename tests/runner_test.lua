local t = require("t")
local runner = require("tilemo.runner")

-- Fake tasks, as hs.task.new makes them: each one keeps its callback for
-- the test to call, as the process exiting would.
local function fake(start_ok)
    local made = {}
    return made, function(path, callback, args)
        local task = { path = path, args = args, callback = callback }
        function task.start()
            return start_ok
        end
        made[#made + 1] = task
        return task
    end
end

t.test("a task is held until its callback runs, then let go", function()
    local made, new = fake(true)
    local r = runner.new(new)
    local got
    t.eq(r.run("/usr/bin/shortcuts", { "list" }, function(code, err, out)
        got = { code, err, out }
    end), true)
    t.eq(r.running(), 1, "held while it runs")
    t.eq(r.held[made[1]], true, "the task itself is referenced")
    made[1].callback(0, "Do Not Disturb On\n", "")
    t.eq(got, { 0, "", "Do Not Disturb On\n" })
    t.eq(r.running(), 0, "let go once it's done")
end)

t.test("each of several tasks is held until its own callback", function()
    local made, new = fake(true)
    local r = runner.new(new)
    r.run("a", {}, function() end)
    r.run("b", {}, function() end)
    made[2].callback(0, "", "")
    t.eq(r.running(), 1)
    t.eq(r.held[made[1]], true, "the first still held")
    made[1].callback(1, "", "boom")
    t.eq(r.running(), 0)
end)

t.test("a task that won't start isn't held, and says so", function()
    local _, new = fake(false)
    local r = runner.new(new)
    t.eq(r.run("x", {}, function() end), false)
    t.eq(r.running(), 0)
end)

t.done("runner")
