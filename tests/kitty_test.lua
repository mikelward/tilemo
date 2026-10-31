-- kitty's remote control socket (SPEC.md §6.3): taken only when it and its
-- folder are yours, and the folder lets nobody else write.

local t = require("t")
local kitty = require("tilemo.kitty")

local ME, OTHER = 501, 502
local TMP = "/var/folders/xy/abc/T/"

-- hs.fs.attributes over a table of paths.
local function fs(entries)
    return function(path)
        return entries[path]
    end
end

local function private(extra)
    local e = {
        ["/var/folders/xy/abc/T"] = { mode = "directory", uid = ME, permissions = "rwx------" },
        ["/var/folders/xy/abc/T/kitty-42"] = { mode = "socket", uid = ME, permissions = "rwxr-xr-x" },
    }
    for k, v in pairs(extra or {}) do
        e[k] = v
    end
    return e
end

t.test("the socket is kitty-<pid> in $TMPDIR, with or without its trailing slash", function()
    t.eq(kitty.path(TMP, 42), "/var/folders/xy/abc/T/kitty-42")
    t.eq(kitty.path("/var/folders/xy/abc/T", 42), "/var/folders/xy/abc/T/kitty-42")
    t.eq(kitty.path(nil, 42), nil, "no $TMPDIR, no socket")
    t.eq(kitty.path("", 42), nil)
    t.eq(kitty.path(TMP, nil), nil, "no kitty process")
end)

t.test("your own socket in your own private folder is used", function()
    t.eq(kitty.socket(TMP, 42, ME, fs(private())), "unix:/var/folders/xy/abc/T/kitty-42")
end)

t.test("no socket is kitty without remote control: nothing to say", function()
    local ok, why = kitty.socket(TMP, 7, ME, fs(private()))
    t.eq(ok, nil)
    t.eq(why, nil)
end)

t.test("a socket someone else owns is refused, saying why", function()
    local ok, why = kitty.socket(TMP, 42, ME, fs(private({
        ["/var/folders/xy/abc/T/kitty-42"] = { mode = "socket", uid = OTHER, permissions = "rwxrwxrwx" },
    })))
    t.eq(ok, nil)
    t.eq(why, "/var/folders/xy/abc/T/kitty-42 belongs to someone else")
end)

t.test("a folder someone else owns, or others can write, is refused", function()
    local ok, why = kitty.socket(TMP, 42, ME, fs(private({
        ["/var/folders/xy/abc/T"] = { mode = "directory", uid = 0, permissions = "rwxrwxrwt" },
    })))
    t.eq(ok, nil)
    t.eq(why, "/var/folders/xy/abc/T isn't your own folder")
    ok, why = kitty.socket(TMP, 42, ME, fs(private({
        ["/var/folders/xy/abc/T"] = { mode = "directory", uid = ME, permissions = "rwxrwx---" },
    })))
    t.eq(ok, nil)
    t.eq(why, "/var/folders/xy/abc/T lets others write to it")
    ok, why = kitty.socket(TMP, 42, ME, fs(private({
        ["/var/folders/xy/abc/T"] = { mode = "directory", uid = ME, permissions = "rwx---rwx" },
    })))
    t.eq(why, "/var/folders/xy/abc/T lets others write to it")
end)

t.test("$TMPDIR pointing at a shared /tmp is refused", function()
    local ok, why = kitty.socket("/tmp", 42, ME, fs({
        ["/tmp"] = { mode = "directory", uid = 0, permissions = "rwxrwxrwt" },
        ["/tmp/kitty-42"] = { mode = "socket", uid = ME, permissions = "rwxr-xr-x" },
    }))
    t.eq(ok, nil)
    t.eq(why, "/tmp isn't your own folder")
end)

t.test("something that isn't a socket, or an unknown user ID, is refused", function()
    local ok, why = kitty.socket(TMP, 42, ME, fs(private({
        ["/var/folders/xy/abc/T/kitty-42"] = { mode = "file", uid = ME, permissions = "rw-------" },
    })))
    t.eq(ok, nil)
    t.eq(why, "/var/folders/xy/abc/T/kitty-42 isn't a socket")
    ok, why = kitty.socket(TMP, 42, nil, fs(private()))
    t.eq(ok, nil)
    t.eq(why, "couldn't tell your user ID, so kitty's socket isn't trusted")
end)

t.done("kitty")
