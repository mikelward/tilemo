-- The workspaces in the menu bar (SPEC.md §8, decided for v1): one status
-- item, drawn as text chips. Pure Lua; the adapter puts the text in the
-- menu bar and shows the number on each switch.
--
--   [3]  the workspace on the display you're on
--   (5)  showing on another display
--   2    has windows
--   4!   has a window wanting attention
--
-- Empty workspaces that aren't showing are left out.

local M = {}

-- `ws` lists, for n = 1…9, { here, elsewhere, occupied, urgent }.
function M.title(ws)
    local parts = {}
    for n = 1, #ws do
        local w = ws[n]
        if w.here or w.elsewhere or w.occupied then
            local s = tostring(n)
            if w.here then
                s = "[" .. s .. "]"
            elseif w.elsewhere then
                s = "(" .. s .. ")"
            end
            if w.urgent then
                s = s .. "!"
            end
            parts[#parts + 1] = s
        end
    end
    return table.concat(parts, " ")
end

return M
