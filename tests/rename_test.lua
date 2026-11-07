-- What still works from before timo and tilemo became tide: require("timo")
-- and require("tilemo"), the settings they saved, and tilemo's folder.
local t = require("t")
local saved = require("tide.saved")
local current = require("tide.current")

t.test('require("timo") says it is deprecated and returns tide', function()
    local tide = { start = function() end }
    local was_loaded, was_print = package.loaded.tide, print
    package.loaded.tide = tide
    package.loaded.timo = nil
    local said = {}
    print = function(...)
        said[#said + 1] = table.concat({ ... }, " ")
    end
    local ok, got = pcall(require, "timo")
    print = was_print
    package.loaded.tide, package.loaded.timo = was_loaded, nil
    t.eq(ok, true, "require")
    t.eq(got == tide, true, "returns tide")
    t.eq(#said, 1, "lines printed")
    t.eq(said[1]:find('require("tide")', 1, true) ~= nil, true, "names the new require")
end)

t.test('require("tilemo") says it is deprecated and returns tide', function()
    local tide = { start = function() end }
    local was_loaded, was_print = package.loaded.tide, print
    package.loaded.tide = tide
    package.loaded.tilemo = nil
    local said = {}
    print = function(...)
        said[#said + 1] = table.concat({ ... }, " ")
    end
    local ok, got = pcall(require, "tilemo")
    print = was_print
    package.loaded.tide, package.loaded.tilemo = was_loaded, nil
    t.eq(ok, true, "require")
    t.eq(got == tide, true, "returns tide")
    t.eq(#said, 1, "lines printed")
    t.eq(said[1]:find('require("tide")', 1, true) ~= nil, true, "names the new require")
end)

local function store(values)
    local s = { values = values }
    function s.getKeys()
        local keys = {}
        for k in pairs(s.values) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        return keys
    end
    function s.get(k)
        return s.values[k]
    end
    function s.set(k, v)
        s.values[k] = v
    end
    return s
end

t.test("what's saved keeps every field of the snapshot, with window ids as strings", function()
    local form = saved.form({
        windows = { [7] = { ws = "web", screen = "B" } },
        gone = { { app = "a" } },
        names = { "in", "web" },
        current = "web",
    })
    t.eq(form, {
        windows = { ["7"] = { ws = "web", screen = "B" } },
        gone = { { app = "a" } },
        names = { "in", "web" },
        current = "web",
    })
end)

t.test("a saved value under the new key is read as it is", function()
    local s = store({ ["tide.state"] = { a = 1 }, ["timo.state"] = { a = 2 } })
    t.eq(saved.get(s, "tide.state", "timo.state"), { a = 1 })
end)

t.test("with only timo's key, its value is read and copied to the new key", function()
    local s = store({ ["timo.state"] = { a = 2 } })
    t.eq(saved.get(s, "tide.state", "timo.state"), { a = 2 })
    t.eq(s.values["tide.state"], { a = 2 })
    t.eq(s.values["timo.state"], { a = 2 }, "old key left for a downgrade")
end)

t.test("with neither key, nothing is read or written", function()
    local s = store({})
    t.eq(saved.get(s, "tide.state", "timo.state"), nil)
    t.eq(next(s.values), nil)
end)

t.test("what tilemo saved is copied to tide's keys, which win where tide saved its own", function()
    local s = store({
        ["tilemo.state"] = { a = 1 },
        ["tilemo.launcher.recency"] = { x = 2 },
        ["tilemo.setup_done"] = { "keys" },
        ["tide.setup_done"] = { "mine" },
        ["other.key"] = 3,
    })
    t.eq(saved.move_prefix(s, "tilemo.", "tide."), 2, "copied")
    t.eq(s.values["tide.state"], { a = 1 })
    t.eq(s.values["tide.launcher.recency"], { x = 2 })
    t.eq(s.values["tide.setup_done"], { "mine" }, "tide's own kept")
    t.eq(s.values["tilemo.state"], { a = 1 }, "old key left for a downgrade")
    t.eq(s.values["tide.key"], nil, "other prefixes untouched")
end)

-- A file system with folders and links, for tilemo's Caches folder.
local function caches(kinds, fail)
    local fs = { kinds = kinds, calls = {} }
    function fs.kind(path)
        return fs.kinds[path]
    end
    function fs.rename(from, to)
        fs.calls[#fs.calls + 1] = "rename " .. from .. " " .. to
        if fail == "rename" then
            return nil, "Permission denied"
        end
        fs.kinds[to], fs.kinds[from] = fs.kinds[from], nil
        return true
    end
    function fs.symlink(target, path)
        fs.calls[#fs.calls + 1] = "link " .. path .. " -> " .. target
        if fail == "symlink" then
            return nil, "File exists"
        end
        fs.kinds[path] = "link"
        return true
    end
    return fs
end

local OLD, NEW = "/h/Library/Caches/tilemo", "/h/Library/Caches/tide"

t.test("tilemo's Caches folder moves to tide's, with a link left at the old path", function()
    local fs = caches({ [OLD] = "directory" })
    t.eq(current.move_old("/h", fs), true)
    t.eq(fs.calls, { "rename " .. OLD .. " " .. NEW, "link " .. OLD .. " -> " .. NEW })
end)

t.test("with tide's folder there and no old one, only the link is made", function()
    local fs = caches({ [NEW] = "directory" })
    t.eq(current.move_old("/h", fs), true)
    t.eq(fs.calls, { "link " .. OLD .. " -> " .. NEW })
end)

t.test("a link already there, both folders, or neither: nothing is touched", function()
    for _, kinds in ipairs({
        { [OLD] = "link", [NEW] = "directory" },
        { [OLD] = "directory", [NEW] = "directory" },
        {},
    }) do
        local fs = caches(kinds)
        t.eq(current.move_old("/h", fs), true)
        t.eq(fs.calls, {})
    end
end)

t.test("a move that fails says why and makes no link", function()
    local fs = caches({ [OLD] = "directory" }, "rename")
    local ok, why = current.move_old("/h", fs)
    t.eq(ok, nil)
    t.eq(why:find("couldn't move", 1, true) ~= nil, true, why)
    t.eq(#fs.calls, 1)
end)

t.test("the adapter and launcher read timo's old keys", function()
    -- Both are Hammerspoon-only, so their keys are checked in the source.
    for _, f in ipairs({ "hs_adapter", "launcher_hs" }) do
        local src = assert(io.open("hammerspoon/tide/" .. f .. ".lua")):read("a")
        t.eq(src:find("saved.get(hs.settings", 1, true) ~= nil, true, f)
    end
end)

t.test("make install puts tide and the tilemo and timo shims in place", function()
    local dir = os.tmpname()
    os.remove(dir)
    local make = os.getenv("MAKE") or "make"
    local ok = os.execute(make .. " -s install HAMMERSPOON_DIR=" .. dir .. " >/dev/null")
    local function exists(p)
        local f = io.open(dir .. "/" .. p)
        if f then
            f:close()
        end
        return f ~= nil
    end
    local got = {
        tide = exists("tide/init.lua"),
        saved = exists("tide/saved.lua"),
        dashboard = exists("tide/dashboard/bar.html"),
        shim = exists("timo/init.lua"),
        tilemo = exists("tilemo/init.lua"),
    }
    os.execute("rm -rf " .. dir)
    t.eq(ok, true, "make install")
    t.eq(got, { tide = true, saved = true, dashboard = true, shim = true, tilemo = true })
end)

t.done("rename")
