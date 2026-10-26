-- What still works from before timo became tilemo: require("timo"), and
-- the settings timo saved.
local t = require("t")
local saved = require("tilemo.saved")

t.test('require("timo") says it is deprecated and returns tilemo', function()
    local tilemo = { start = function() end }
    local was_loaded, was_print = package.loaded.tilemo, print
    package.loaded.tilemo = tilemo
    package.loaded.timo = nil
    local said = {}
    print = function(...)
        said[#said + 1] = table.concat({ ... }, " ")
    end
    local ok, got = pcall(require, "timo")
    print = was_print
    package.loaded.tilemo, package.loaded.timo = was_loaded, nil
    t.eq(ok, true, "require")
    t.eq(got == tilemo, true, "returns tilemo")
    t.eq(#said, 1, "lines printed")
    t.eq(said[1]:find('require("tilemo")', 1, true) ~= nil, true, "names the new require")
end)

local function store(values)
    local s = { values = values }
    function s.get(k)
        return s.values[k]
    end
    function s.set(k, v)
        s.values[k] = v
    end
    return s
end

t.test("a saved value under the new key is read as it is", function()
    local s = store({ ["tilemo.state"] = { a = 1 }, ["timo.state"] = { a = 2 } })
    t.eq(saved.get(s, "tilemo.state", "timo.state"), { a = 1 })
end)

t.test("with only timo's key, its value is read and copied to the new key", function()
    local s = store({ ["timo.state"] = { a = 2 } })
    t.eq(saved.get(s, "tilemo.state", "timo.state"), { a = 2 })
    t.eq(s.values["tilemo.state"], { a = 2 })
    t.eq(s.values["timo.state"], { a = 2 }, "old key left for a downgrade")
end)

t.test("with neither key, nothing is read or written", function()
    local s = store({})
    t.eq(saved.get(s, "tilemo.state", "timo.state"), nil)
    t.eq(next(s.values), nil)
end)

t.test("the adapter and launcher read timo's old keys", function()
    -- Both are Hammerspoon-only, so their keys are checked in the source.
    for _, f in ipairs({ "hs_adapter", "launcher_hs" }) do
        local src = assert(io.open("hammerspoon/tilemo/" .. f .. ".lua")):read("a")
        t.eq(src:find("saved.get(hs.settings", 1, true) ~= nil, true, f)
    end
end)

t.test("make install puts tilemo and the timo shim in place", function()
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
        tilemo = exists("tilemo/init.lua"),
        saved = exists("tilemo/saved.lua"),
        dashboard = exists("tilemo/dashboard/bar.html"),
        shim = exists("timo/init.lua"),
    }
    os.execute("rm -rf " .. dir)
    t.eq(ok, true, "make install")
    t.eq(got, { tilemo = true, saved = true, dashboard = true, shim = true })
end)

t.done("rename")
