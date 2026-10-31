-- The current workspace's name in a file, for scripts (SPEC.md §6.3): a
-- shell started without TIDE_WORKSPACE reads it to name its session. A file
-- rather than Hammerspoon's IPC port, which would run any Lua a local
-- process sends it, with tilemo's Accessibility grant.
--
-- `workspace` holds TIDE_WORKSPACE's value, and `workspace.name` the name
-- as it shows, each with a newline, in a folder only you can read. Each is
-- written whole, mode 600, by a rename over the last. Pure Lua: `fs` is
-- atomic.lua's, plus mkdir(path, mode) and chmod(path, mode), and `run_js`
-- what names.sanitize runs a name past ASCII with.

local atomic = require("tilemo.atomic")
local names = require("tilemo.names")

local M = {}

-- Under the home folder.
M.DIR = "Library/Caches/tilemo"
M.FILE = "workspace"
M.NAME_FILE = "workspace.name"

function M.dir(home)
    return home .. "/" .. M.DIR
end

-- A writer for folder `dir`: write(name) writes the files when the name
-- differs from the last written, and returns true, or nil and why not. A
-- failed write is tried again on the next call. A name whose letters and
-- digits can't be found writes an empty value, which names no session,
-- rather than leave the last workspace's, and is a failure too.
function M.new(dir, fs, run_js)
    local self = { dir = dir }
    local last
    function self.write(name)
        if name == last then
            return true
        end
        -- The folder is made, or kept, readable by you alone.
        local ok, err = fs.mkdir(dir, "700")
        if ok then
            ok, err = fs.chmod(dir, "700")
        end
        local value, bad = names.sanitize(name, run_js)
        if ok then
            ok, err = atomic.write(dir .. "/" .. M.FILE, value .. "\n", fs, "600")
        end
        if ok then
            ok, err = atomic.write(dir .. "/" .. M.NAME_FILE, name .. "\n", fs, "600")
        end
        if not ok then
            return nil, err
        end
        -- The files no longer hold `last`, so going back to it rewrites
        -- them; this name is tried again too.
        if bad then
            last = nil
            return nil, bad
        end
        last = name
        return true
    end
    return self
end

return M
