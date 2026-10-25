-- A small test runner: plain Lua 5.4, no dependencies. Each test file
-- requires this, calls test(), then t.done().

package.path = "hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;" .. package.path

local t = { failures = 0, passed = 0 }

function t.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        t.passed = t.passed + 1
    else
        t.failures = t.failures + 1
        io.stderr:write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function show(v)
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(x)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end
t.show = show

function t.eq(got, want, what)
    if show(got) ~= show(want) then
        error(string.format("%s: got %s, want %s", what or "value", show(got), show(want)), 2)
    end
end

function t.done(name)
    print(string.format("%s: %d passed, %d failed", name, t.passed, t.failures))
    if t.failures > 0 then
        os.exit(1)
    end
end

return t
