local t = require("t")
local atomic = require("tilemo.atomic")

-- A stand-in for io and os over a table of files, whose writes or closes
-- can fail as a full disk makes them.
local function disk(fail)
    local d = { files = {}, removed = {} }
    function d.open(path)
        local buf = {}
        return {
            write = function(self, text)
                if fail == "write" then
                    return nil, "No space left on device"
                end
                buf[#buf + 1] = text
                return self
            end,
            close = function()
                if fail == "close" then
                    return nil, "No space left on device"
                end
                d.files[path] = table.concat(buf)
                return true
            end,
        }
    end
    function d.rename(from, to)
        d.files[to], d.files[from] = d.files[from], nil
        return true
    end
    d.modes = {}
    function d.chmod(path, mode)
        if fail == "chmod" then
            return nil, "Operation not permitted"
        end
        d.modes[path] = mode
        return true
    end
    function d.remove(path)
        d.removed[#d.removed + 1] = path
        d.files[path] = nil
        return true
    end
    return d
end

t.test("a file is written whole, by way of a temporary file", function()
    local d = disk()
    d.files["/c/clocks.local.json"] = "old"
    t.eq(atomic.write("/c/clocks.local.json", "new", d), true)
    t.eq(d.files, { ["/c/clocks.local.json"] = "new" })
end)

for _, fail in ipairs({ "write", "close" }) do
    t.test("a " .. fail .. " that fails leaves the old file, and says why", function()
        local d = disk(fail)
        d.files["/c/clocks.local.json"] = "old"
        local ok, err = atomic.write("/c/clocks.local.json", "new", d)
        t.eq(ok, nil)
        t.eq(err, "No space left on device")
        t.eq(d.files, { ["/c/clocks.local.json"] = "old" })
        t.eq(d.removed, { "/c/clocks.local.json.tmp" })
    end)
end

t.test("with a mode, the file has it before it takes the path's place", function()
    local d = disk()
    local order = {}
    local chmod, rename = d.chmod, d.rename
    function d.chmod(path, mode)
        order[#order + 1] = "chmod " .. path
        return chmod(path, mode)
    end
    function d.rename(from, to)
        order[#order + 1] = "rename " .. from
        return rename(from, to)
    end
    t.eq(atomic.write("/c/w", "x", d, "600"), true)
    t.eq(order, { "chmod /c/w.tmp", "rename /c/w.tmp" })
    t.eq(d.modes["/c/w.tmp"], "600")
end)

t.test("a mode that can't be set leaves the old file, and says why", function()
    local d = disk("chmod")
    d.files["/c/w"] = "old"
    local ok, err = atomic.write("/c/w", "new", d, "600")
    t.eq(ok, nil)
    t.eq(err, "Operation not permitted")
    t.eq(d.files, { ["/c/w"] = "old" })
end)

t.done("atomic")
