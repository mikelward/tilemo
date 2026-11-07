-- The dim (SPEC.md §5.6): every window but the focused one darkened, as
-- tide's inactive dim (tide SPEC.md §6.2). tide can't draw inside or
-- below another app's window (§2.4), so it lays one click-through layer
-- over the windows on each display, a hole cut where the focused window
-- is, and the windows in front of that one filled in again. Tiles don't
-- overlap, so the hole is the focused window and nothing else. Pure Lua:
-- dim_hs.lua draws what this says.

local M = {}

-- tide's strength when nothing sets one (tide-appearance.js's DIM_STRENGTH).
M.STRENGTH = 0.12
M.KEY = "dimStrength"
M.SHARED_FILE = "appearance.json"
M.LOCAL_FILE = "appearance.local.json"

-- The strength set, from appearance.json's and appearance.local.json's
-- texts (nil for a file that isn't there), the local one's over the shared
-- one's, as tide reads them; and what's wrong with either. A bad value is
-- left out, so the one before it stands. `decode` is hs.json.decode.
function M.load(shared, own, decode)
    local strength, errors = M.STRENGTH, {}
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        local name, text = f[1], f[2]
        if text then
            local ok, t = pcall(decode, text)
            if not ok or type(t) ~= "table" then
                errors[#errors + 1] = name .. " isn't a JSON object"
            elseif t[M.KEY] ~= nil then
                local v = t[M.KEY]
                if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then
                    errors[#errors + 1] = name .. ": " .. M.KEY .. " must be a number from 0 to 1"
                else
                    strength = v
                end
            end
        end
    end
    return strength, errors
end

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function relative(b, origin)
    return { x = b.x - origin.x, y = b.y - origin.y, w = b.w, h = b.h }
end

-- What one display's layer draws, as hs.canvas elements in the display's
-- own coordinates, or nil for no layer.
-- `scene` is wm:dim_scene(): { focused = frame, above = { frame, ... } },
-- with no focused frame when every window's to be dimmed, or nil when
-- nothing is. `full` is the display's whole frame,
-- `strength` the dim's, `radius` a window's corner radius.
function M.elements(scene, full, strength, radius)
    if not scene or not strength or strength <= 0 then
        return nil
    end
    local color = { red = 0, green = 0, blue = 0, alpha = strength }
    local corners = { xRadius = radius, yRadius = radius }
    local out = {
        { type = "rectangle", action = "fill", fillColor = color, frame = { x = 0, y = 0, w = full.w, h = full.h } },
    }
    if scene.focused and overlap(scene.focused, full) then
        -- destinationOut takes the layer away under an opaque shape, its
        -- rounded edge's antialiasing too.
        out[#out + 1] = {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
            compositeRule = "destinationOut",
            roundedRectRadii = corners,
            frame = relative(scene.focused, full),
        }
        -- A window in front of the focused one is dimmed where it covers the
        -- hole too. copy sets it to the dim exactly, so where it reaches past
        -- the hole it isn't dimmed twice.
        for _, b in ipairs(scene.above or {}) do
            if overlap(b, scene.focused) and overlap(b, full) then
                out[#out + 1] = {
                    type = "rectangle",
                    action = "fill",
                    fillColor = color,
                    compositeRule = "copy",
                    roundedRectRadii = corners,
                    frame = relative(b, full),
                }
            end
        end
    end
    return out
end

-- The corner radius of a window on macOS `major`: larger from macOS 26
-- *(unverified: it differs by kind of window)*.
function M.radius(major)
    if (major or 0) >= 26 then
        return 16
    end
    return 10
end

return M
