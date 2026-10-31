-- kitty's remote control socket, for TIDE_WORKSPACE in a new kitty window
-- (SPEC.md §6.3). conf's kitty.conf has `listen_on unix:kitty` on a Mac,
-- which kitty puts in its temporary folder, $TMPDIR, as `kitty-<pid>`.
-- That folder is yours alone, but a socket is only taken when it and its
-- folder are both owned by you and the folder lets nobody else write:
-- remote control runs anything as you, and tilemo sends the workspace's
-- name, so a socket someone else made is refused. Pure Lua: `attributes`
-- is hs.fs.attributes's shape (mode, uid, permissions).

local M = {}

-- Where kitty with process ID `pid` listens, given $TMPDIR as `tmpdir`.
function M.path(tmpdir, pid)
    if not (tmpdir and tmpdir ~= "" and pid) then
        return nil
    end
    return (tmpdir:gsub("/+$", "")) .. "/kitty-" .. pid
end

-- Whether a `permissions` string ("rwxr-xr-x") lets group or others write.
local function others_write(permissions)
    permissions = permissions or ""
    return permissions:sub(5, 5) == "w" or permissions:sub(8, 8) == "w"
end

-- The socket to give `kitten @ --to`, as "unix:<path>"; or nil, with why
-- not when there's one that isn't safe to use (nil alone when there's no
-- socket, which is kitty without remote control). `uid` is yours.
function M.socket(tmpdir, pid, uid, attributes)
    local path = M.path(tmpdir, pid)
    if not path then
        return nil
    end
    local sock = attributes(path)
    if not sock then
        return nil
    end
    if sock.mode ~= "socket" then
        return nil, path .. " isn't a socket"
    end
    local dir = path:match("^(.*)/[^/]*$")
    local folder = attributes(dir)
    if not uid then
        return nil, "couldn't tell your user ID, so kitty's socket isn't trusted"
    end
    if not folder or folder.mode ~= "directory" or folder.uid ~= uid then
        return nil, dir .. " isn't your own folder"
    end
    if others_write(folder.permissions) then
        return nil, dir .. " lets others write to it"
    end
    if sock.uid ~= uid then
        return nil, path .. " belongs to someone else"
    end
    return "unix:" .. path
end

return M
