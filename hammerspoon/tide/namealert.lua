-- The workspace's name, shown briefly in the middle of the screen on each
-- switch (SPEC.md §8): about macOS's own alert size, not a banner across
-- the screen. `hs` is passed in so the tests can stand in for it.

local M = {}

M.STYLE = { textSize = 28, radius = 14 }
M.SECONDS = 0.5

-- Show workspace `name` on the display `uuid`, or the main one if that's
-- gone, replacing any name still showing.
function M.show(hs, name, uuid)
    hs.alert.closeAll(0)
    hs.alert.show(name, M.STYLE, hs.screen.find(uuid) or hs.screen.mainScreen(), M.SECONDS)
end

return M
