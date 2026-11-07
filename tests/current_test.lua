-- The workspace's name in a file, for scripts (SPEC.md §6.3).

local t = require("t")
local current = require("tide.current")

-- A stand-in for the file system: files, modes, and every call in order.
local function disk(fail)
    local d = { files = {}, modes = {}, dirs = {}, calls = {} }
    function d.open(path)
        local buf = {}
        return {
            write = function(self, text)
                buf[#buf + 1] = text
                return self
            end,
            close = function()
                d.files[path] = table.concat(buf)
                return true
            end,
        }
    end
    function d.rename(from, to)
        d.calls[#d.calls + 1] = "rename " .. from .. " " .. to
        d.files[to], d.files[from] = d.files[from], nil
        d.modes[to], d.modes[from] = d.modes[from], nil
        return true
    end
    function d.remove(path)
        d.files[path] = nil
        return true
    end
    function d.mkdir(path, mode)
        d.calls[#d.calls + 1] = "mkdir " .. path
        if fail == "mkdir" then
            return nil, "Permission denied"
        end
        d.dirs[path] = d.dirs[path] or mode
        return true
    end
    function d.chmod(path, mode)
        d.calls[#d.calls + 1] = "chmod " .. mode .. " " .. path
        d.modes[path] = mode
        return true
    end
    return d
end

t.test("the file lives in the user's caches, not anywhere shared", function()
    t.eq(current.dir("/home/user"), "/home/user/Library/Caches/tide")
end)

t.test("the name goes to the file as TIDE_WORKSPACE has it, and as it shows, private", function()
    local d = disk()
    local w = current.new("/c/tide", d)
    t.eq(w.write("PR-12 login"), true)
    t.eq(d.files["/c/tide/workspace"], "PR12login\n")
    t.eq(d.files["/c/tide/workspace.name"], "PR-12 login\n")
    t.eq(d.modes["/c/tide"], "700", "the folder is yours alone")
    t.eq(d.modes["/c/tide/workspace"], "600")
    t.eq(d.modes["/c/tide/workspace.name"], "600")
    -- Each written whole: to a temporary file, given its mode, then renamed.
    t.eq(d.calls, {
        "mkdir /c/tide",
        "chmod 700 /c/tide",
        "chmod 600 /c/tide/workspace.tmp",
        "rename /c/tide/workspace.tmp /c/tide/workspace",
        "chmod 600 /c/tide/workspace.name.tmp",
        "rename /c/tide/workspace.name.tmp /c/tide/workspace.name",
    })
end)

t.test("a name past ASCII goes to the file as JavaScript keeps it", function()
    local d = disk()
    local w = current.new("/c/tide", d, function()
        return true, "Équipe2"
    end)
    t.eq(w.write("Équipe 2"), true)
    t.eq(d.files["/c/tide/workspace"], "Équipe2\n")
    t.eq(d.files["/c/tide/workspace.name"], "Équipe 2\n")
end)

t.test("a name whose letters can't be found writes an empty value, not the last one, and says why", function()
    local d = disk()
    local js_ok = true
    local w = current.new("/c/tide", d, function()
        if js_ok then
            return true, "web"
        end
        return false, "no JavaScriptCore"
    end)
    w.write("wéb")
    js_ok = false
    local ok, err = w.write("Équipe")
    t.eq(ok, nil)
    t.eq(err, "couldn't keep the workspace's letters and digits: no JavaScriptCore")
    t.eq(d.files["/c/tide/workspace"], "\n")
    t.eq(d.files["/c/tide/workspace.name"], "Équipe\n")
    js_ok = true
    d.calls = {}
    w.write("Équipe")
    t.eq(#d.calls > 0, true, "tried again")
end)

t.test("going back to the last name after a failed one rewrites the files", function()
    local d = disk()
    local js_ok = true
    local w = current.new("/c/tide", d, function()
        if js_ok then
            return true, "Équipe"
        end
        return false, "no JavaScriptCore"
    end)
    t.eq(w.write("web"), true)
    js_ok = false
    w.write("Équipe")
    t.eq(w.write("web"), true)
    t.eq(d.files["/c/tide/workspace"], "web\n", "not the empty value the failure left")
    t.eq(d.files["/c/tide/workspace.name"], "web\n")
end)

t.test("only a change is written", function()
    local d = disk()
    local w = current.new("/c/tide", d)
    w.write("in")
    d.calls = {}
    t.eq(w.write("in"), true)
    t.eq(d.calls, {})
    w.write("web")
    t.eq(d.files["/c/tide/workspace"], "web\n")
end)

t.test("a write that fails says why, and is tried again next time", function()
    local d = disk("mkdir")
    local w = current.new("/c/tide", d)
    local ok, err = w.write("in")
    t.eq(ok, nil)
    t.eq(err, "Permission denied")
    t.eq(d.files["/c/tide/workspace"], nil)
    d.calls = {}
    w.write("in")
    t.eq(d.calls[1], "mkdir /c/tide", "tried again")
end)

t.done("current")
