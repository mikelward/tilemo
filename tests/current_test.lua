-- The workspace's name in a file, for scripts (SPEC.md §6.3).

local t = require("t")
local current = require("tilemo.current")

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
    t.eq(current.dir("/home/user"), "/home/user/Library/Caches/tilemo")
end)

t.test("the name goes to the file as TIDE_WORKSPACE has it, and as it shows, private", function()
    local d = disk()
    local w = current.new("/c/tilemo", d)
    t.eq(w.write("PR-12 login"), true)
    t.eq(d.files["/c/tilemo/workspace"], "PR12login\n")
    t.eq(d.files["/c/tilemo/workspace.name"], "PR-12 login\n")
    t.eq(d.modes["/c/tilemo"], "700", "the folder is yours alone")
    t.eq(d.modes["/c/tilemo/workspace"], "600")
    t.eq(d.modes["/c/tilemo/workspace.name"], "600")
    -- Each written whole: to a temporary file, given its mode, then renamed.
    t.eq(d.calls, {
        "mkdir /c/tilemo",
        "chmod 700 /c/tilemo",
        "chmod 600 /c/tilemo/workspace.tmp",
        "rename /c/tilemo/workspace.tmp /c/tilemo/workspace",
        "chmod 600 /c/tilemo/workspace.name.tmp",
        "rename /c/tilemo/workspace.name.tmp /c/tilemo/workspace.name",
    })
end)

t.test("a name past ASCII goes to the file as JavaScript keeps it", function()
    local d = disk()
    local w = current.new("/c/tilemo", d, function()
        return true, "Équipe2"
    end)
    t.eq(w.write("Équipe 2"), true)
    t.eq(d.files["/c/tilemo/workspace"], "Équipe2\n")
    t.eq(d.files["/c/tilemo/workspace.name"], "Équipe 2\n")
end)

t.test("a name whose letters can't be found writes an empty value, not the last one, and says why", function()
    local d = disk()
    local js_ok = true
    local w = current.new("/c/tilemo", d, function()
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
    t.eq(d.files["/c/tilemo/workspace"], "\n")
    t.eq(d.files["/c/tilemo/workspace.name"], "Équipe\n")
    js_ok = true
    d.calls = {}
    w.write("Équipe")
    t.eq(#d.calls > 0, true, "tried again")
end)

t.test("going back to the last name after a failed one rewrites the files", function()
    local d = disk()
    local js_ok = true
    local w = current.new("/c/tilemo", d, function()
        if js_ok then
            return true, "Équipe"
        end
        return false, "no JavaScriptCore"
    end)
    t.eq(w.write("web"), true)
    js_ok = false
    w.write("Équipe")
    t.eq(w.write("web"), true)
    t.eq(d.files["/c/tilemo/workspace"], "web\n", "not the empty value the failure left")
    t.eq(d.files["/c/tilemo/workspace.name"], "web\n")
end)

t.test("only a change is written", function()
    local d = disk()
    local w = current.new("/c/tilemo", d)
    w.write("in")
    d.calls = {}
    t.eq(w.write("in"), true)
    t.eq(d.calls, {})
    w.write("web")
    t.eq(d.files["/c/tilemo/workspace"], "web\n")
end)

t.test("a write that fails says why, and is tried again next time", function()
    local d = disk("mkdir")
    local w = current.new("/c/tilemo", d)
    local ok, err = w.write("in")
    t.eq(ok, nil)
    t.eq(err, "Permission denied")
    t.eq(d.files["/c/tilemo/workspace"], nil)
    d.calls = {}
    w.write("in")
    t.eq(d.calls[1], "mkdir /c/tilemo", "tried again")
end)

t.done("current")
