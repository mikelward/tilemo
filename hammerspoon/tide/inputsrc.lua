-- The Keyboard page's input sources (SPEC.md §15), as tide's Keyboard page
-- has its layouts (tide SPEC.md §16): the keyboard layouts and input
-- methods macOS has turned on, the one in use lit, and a click to use
-- another. Adding or taking one out stays in Keyboard settings. Pure Lua:
-- hs.keycodes' lists in, the page's rows out.

local M = {}

-- The page's rows from hs.keycodes: `layouts` and `methods` (names), and
-- `current`, the one in use. Each is { name, method, current }, layouts
-- first, as the bar lists them.
function M.state(layouts, methods, current)
    local out = {}
    for _, name in ipairs(layouts or {}) do
        out[#out + 1] = { name = name, method = false, current = name == current }
    end
    for _, name in ipairs(methods or {}) do
        out[#out + 1] = { name = name, method = true, current = name == current }
    end
    return { sources = out }
end

-- Does what a message from the page asks, `{ inputSource = name }`,
-- through `use(name, method)`, for a source in `sources` (M.state's) only.
-- Returns whether it was the page's.
function M.handle(body, sources, use)
    if type(body) ~= "table" or body.inputSource == nil then
        return false
    end
    for _, s in ipairs(sources or {}) do
        if s.name == body.inputSource then
            use(s.name, s.method)
            break
        end
    end
    return true
end

-- macOS calls one function as the input source changes, whoever switched
-- it (`keycodes` is hs.keycodes): this shares it, so the bar and the
-- Keyboard page each follow. Returns on(fn), adding one to call; one that
-- fails is logged, and the rest still called.
function M.watch(keycodes, log)
    local listeners = {}
    keycodes.inputSourceChanged(function()
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then
                log("input source watcher: " .. tostring(err))
            end
        end
    end)
    return function(fn)
        listeners[#listeners + 1] = fn
    end
end

return M
