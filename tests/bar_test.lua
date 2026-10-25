local t = require("t")
local bar = require("timo.bar")

local function ws(spec)
    local out = {}
    for n = 1, 9 do
        out[n] = spec[n] or {}
    end
    return out
end

t.test("the menu bar shows this display's workspace, others showing, and occupied ones", function()
    t.eq(bar.title(ws({ { here = true }, { occupied = true }, { elsewhere = true }, nil, { occupied = true, urgent = true } })),
        "[1] 2 (3) 5!")
end)

t.test("empty workspaces that aren't showing are left out", function()
    t.eq(bar.title(ws({ nil, { here = true } })), "[2]")
end)

t.done("bar")
