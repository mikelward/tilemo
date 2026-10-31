-- Runs commands as hs.task does, holding each task until its callback has
-- run: Hammerspoon may stop a task that's garbage collected, which would
-- end a terminal started from a key, or a shortcut, part way. Pure, given
-- the task constructor, so it tests with fake tasks.

local M = {}

-- `new_task(path, callback, args)` makes a task, as hs.task.new does.
function M.new(new_task)
    local self = { held = {} }

    -- Runs `path` with `args`, calling `done(code, err, out)` when it exits.
    -- Returns whether it started.
    function self.run(path, args, done)
        local task
        task = new_task(path, function(code, out, err)
            self.held[task] = nil
            done(code, err, out)
        end, args)
        if task and task:start() then
            self.held[task] = true
            return true
        end
        return false
    end

    -- How many are running, for the tests.
    function self.running()
        local n = 0
        for _ in pairs(self.held) do
            n = n + 1
        end
        return n
    end

    return self
end

return M
