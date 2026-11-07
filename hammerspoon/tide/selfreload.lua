-- tide reloads itself when a new copy of its files lands where it runs
-- from (SPEC.md §15): `make install`, and so setup, copies them into
-- ~/.hammerspoon/tide, and nothing else writes there. A copy is many
-- files, so the reload waits until none has come for M.QUIET seconds. A
-- hidden file, such as Finder's .DS_Store or an editor's swap file, isn't
-- one of tide's, and changes nothing.

local M = {}

M.QUIET = 1

-- Whether `path` names a hidden file, by its last part.
local function hidden(path)
    return (tostring(path):match("([^/]*)$") or ""):sub(1, 1) == "."
end

-- `after(seconds, fn)` returns a timer with stop(), as the adapter's does;
-- `reload()` reloads Hammerspoon; `log(text)` says why. Returns
-- changed(paths), for the folder's watcher to call with the paths that
-- changed.
function M.new(after, reload, log)
    local timer
    return function(paths)
        local mine = false
        for _, p in ipairs(paths or {}) do
            if not hidden(p) then
                mine = true
            end
        end
        if not mine then
            return
        end
        if timer then
            timer.stop()
        end
        timer = after(M.QUIET, function()
            timer = nil
            log("a new copy of tide is installed: reloading")
            reload()
        end)
    end
end

return M
