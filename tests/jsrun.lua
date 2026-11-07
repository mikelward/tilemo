-- JavaScript run in node, standing in for JavaScriptCore, as
-- hs.osascript.javascript gives its last value: ok, and the result as a
-- string: a whole script's completion value as JavaScriptCore gives it.
-- Nil without node, unless TIDE_NEED_NODE says it's needed. The
-- clock is UTC's, so a test's times read the same anywhere.
local names = require("tide.names")

return function(what)
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to run " .. what)
        end
        return nil
    end
    return function(source)
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write("process.stdout.write(String((0, eval)(" .. names.js_string(source) .. ")));")
        f:close()
        local p = io.popen("TZ=UTC node " .. path .. " 2>&1")
        local out = p:read("a")
        local ok = p:close()
        os.remove(path)
        return ok == true, out
    end
end
