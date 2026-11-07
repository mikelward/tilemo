-- What the desktop calls itself on screen: tide, as on Linux, with tide's
-- wave logo. The code keeps the name tide, in its modules, its
-- hs.settings keys, start()'s options, its files and its message
-- handlers, so a user's init.lua and saved state keep working; nothing
-- shown is built from those.

local M = {}

M.NAME = "tide"

-- The logo, rendered from tide's shell/icons/tide-symbolic.svg by
-- `make icons` (icons/render.cjs). The template is black on clear, for the
-- menu bar, where macOS tints it to match light and dark; the other is in
-- tide's accent blue, for notifications and the switcher's rows.
M.ICON_DIR = "icons"
M.LOGO = "tide.png"
M.TEMPLATE = "tide-template.png"
-- The size each is drawn at, in points; the files have 4x the pixels.
M.TEMPLATE_SIZE = { w = 16, h = 16 }
M.LOGO_SIZE = { w = 64, h = 64 }

-- The path of `name` in the icons folder beside the module at `dir`.
function M.icon_path(dir, name)
    return dir .. "/" .. M.ICON_DIR .. "/" .. name
end

-- A window's title: tide, then what the window is, if anything.
function M.title(what)
    if what == nil or what == "" then
        return M.NAME
    end
    return M.NAME .. " " .. what
end

-- hs.notify's attributes for a notice saying `text`, titled tide and
-- showing the logo (`image`, an hs.image, or nil if it couldn't be read),
-- with `extra`'s attributes over them.
function M.notice(text, image, extra)
    local out = { title = M.NAME, informativeText = text, contentImage = image }
    for k, v in pairs(extra or {}) do
        out[k] = v
    end
    return out
end

return M
