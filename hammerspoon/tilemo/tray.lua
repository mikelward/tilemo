-- The tray of windows you minimized (SPEC.md §6.7): a row of app icons in
-- the bottom-right corner of each display, one per window you minimized
-- from the workspace showing there. Pure Lua; tray_hs.lua draws it.

local M = {}

-- Sizes from tide's mock, option C: 28 px icons, 5 px padding, 6 px
-- between them, 12 px in from the corner.
M.ICON = 28
M.PAD = 5
M.GAP = 6
M.MARGIN = 12

-- How many icons fit across a display `width` wide.
function M.fits(width)
    return math.max(0, (width - 2 * M.MARGIN - 2 * M.PAD + M.GAP) // (M.ICON + M.GAP))
end

-- The tray's frame for `count` icons in the bottom-right of `area`.
function M.frame(area, count)
    local w = 2 * M.PAD + count * M.ICON + (count - 1) * M.GAP
    local h = M.ICON + 2 * M.PAD
    return { x = area.x + area.w - M.MARGIN - w, y = area.y + area.h - M.MARGIN - h, w = w, h = h }
end

-- Icon `i`'s box within the tray, from its top left.
function M.icon_box(i)
    return { x = M.PAD + (i - 1) * (M.ICON + M.GAP), y = M.PAD, w = M.ICON, h = M.ICON }
end

-- What display `uuid`'s tray shows: { frame, items = { { id, app, title } } }
-- in the order you minimized them, the newest at the right, or nil when it
-- shows nothing. With more than fit, the newest that fit; the rest are in
-- the switcher's Windows tab.
function M.state(wm, uuid)
    local s = wm:screen_by_uuid(uuid)
    local n = wm.screen_ws[uuid]
    if not s or not n then
        return nil
    end
    local ids = wm:minimized_windows(n)
    local first = math.max(1, #ids - M.fits(s.area.w) + 1)
    local items = {}
    for i = first, #ids do
        local id = ids[i]
        local w = wm.windows[id]
        items[#items + 1] = { id = id, app = w.app or "", title = wm.a.title(id) or w.title or w.name or "" }
    end
    if #items == 0 then
        return nil
    end
    return { frame = M.frame(s.area, #items), items = items }
end

-- Every display's tray, by uuid, leaving out any that show nothing or hide
-- with the bar under a full-screen window (`hidden(uuid)`).
function M.all(wm, hidden)
    local out = {}
    for _, s in ipairs(wm:screens()) do
        local st = not (hidden and hidden(s.uuid)) and M.state(wm, s.uuid)
        if st then
            out[s.uuid] = st
        end
    end
    return out
end

-- The trays' frames, for focus follows mouse to pause over (SPEC.md §6.7).
function M.frames(trays)
    local out = {}
    for _, st in pairs(trays) do
        out[#out + 1] = st.frame
    end
    return out
end

-- A click on a tray's icon: Restore (SPEC.md §6.1), with its workspace.
function M.click(wm, id)
    if wm.windows[id] then
        wm:activate(id)
    end
end

-- Where the title's tip goes for icon `i` of a tray at `frame`: `w` by `h`,
-- just above the icon, right-aligned with it, and kept inside `area`.
function M.tip_frame(frame, i, w, h, area)
    local box = M.icon_box(i)
    local x = frame.x + box.x + box.w - w
    x = math.max(area.x + M.MARGIN, math.min(x, area.x + area.w - M.MARGIN - w))
    return { x = x, y = frame.y - 6 - h, w = w, h = h }
end

return M
