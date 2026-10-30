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

t.done("atomic")
