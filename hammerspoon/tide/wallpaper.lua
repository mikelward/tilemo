-- The wallpapers, light and dark, from tide's appearance.json and
-- appearance.local.json (tide SPEC.md §15, §16), as the Mac's desktop
-- picture (SPEC.md §10). Pure Lua.

local names = require("tide.names")

local M = {}

-- Each mode's setting, as tide names them.
M.KEYS = { light = "lightWallpaper", dark = "darkWallpaper" }

M.SHARED_FILE = "appearance.json"
M.LOCAL_FILE = "appearance.local.json"

-- A wallpaper that's a solid color, #rrggbb or #rgb, as tide's
-- wallpaperColor takes one (tide SPEC.md §15). macOS's desktop takes only
-- a picture, so tide draws the color into one (wallpaper_hs.lua).
function M.is_color(v)
    return type(v) == "string" and (v:match("^#%x%x%x$") or v:match("^#%x%x%x%x%x%x$")) ~= nil
end

-- A color as rrggbb, in lower case, as tide's wallpaperColor gives it.
function M.hex(v)
    if not M.is_color(v) then
        return nil
    end
    local h = v:sub(2):lower()
    if #h == 3 then
        h = h:gsub(".", "%0%0")
    end
    return h
end

-- Where the picture drawn for color `hex` is kept, in `dir`.
function M.color_file(dir, hex)
    return dir .. "/wallpaper-" .. hex .. ".png"
end

-- Why `v` can't be a wallpaper, as tide's wallpaperError says, or nil: a
-- file's path, absolute or from ~/, on one line, a color, or "" for
-- macOS's own.
local function problem(key, v)
    if type(v) == "string" and v:sub(1, 1) == "#" then
        if not M.is_color(v) then
            return key .. ' must be a color as #rrggbb or #rgb, such as "#1a1d2e"'
        end
        return nil
    end
    if type(v) ~= "string" or v:find("[\n\r]") or (v ~= "" and v:sub(1, 1) ~= "/" and v:sub(1, 2) ~= "~/") then
        return key .. ' must be a file\'s path, such as "~/Pictures/day.jpg", a color such as "#1a1d2e", or "" for the default'
    end
end

-- How each mode's picture is placed (tide SPEC.md §15): its own, else
-- wallpaperPosition's, for both, else fill.
M.POSITION_KEYS = { light = "lightWallpaperPosition", dark = "darkWallpaperPosition", both = "wallpaperPosition" }
M.POSITIONS = { "fill", "fill-top", "fill-bottom", "fit", "stretch" }

local function position_problem(key, v)
    for _, p in ipairs(M.POSITIONS) do
        if v == p then
            return nil
        end
    end
    local quoted = {}
    for i, p in ipairs(M.POSITIONS) do
        quoted[i] = '"' .. p .. '"'
    end
    return key .. " must be one of " .. table.concat(quoted, ", ")
end

-- The wallpapers set, { light, dark }, each a path or "" for none, from
-- the two files' texts (nil for a file that isn't there), the local one's
-- over the shared one's, as tide reads them; what's wrong with either; and
-- each mode's position, { light, dark }. `decode` is hs.json.decode.
function M.load(shared, own, decode)
    local out, errors = { light = "", dark = "" }, {}
    local placed = {}
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        local name, text = f[1], f[2]
        if text then
            local ok, t = pcall(decode, text)
            if not ok or type(t) ~= "table" then
                errors[#errors + 1] = name .. " isn't a JSON object"
            else
                for mode, key in pairs(M.KEYS) do
                    if t[key] ~= nil then
                        local why = problem(key, t[key])
                        if why then
                            errors[#errors + 1] = name .. ": " .. why
                        else
                            out[mode] = t[key]
                        end
                    end
                end
                for which, key in pairs(M.POSITION_KEYS) do
                    if t[key] ~= nil then
                        local why = position_problem(key, t[key])
                        if why then
                            errors[#errors + 1] = name .. ": " .. why
                        else
                            placed[which] = t[key]
                        end
                    end
                end
            end
        end
    end
    table.sort(errors)
    local positions = {
        light = placed.light or placed.both or "fill",
        dark = placed.dark or placed.both or "fill",
    }
    return out, errors, positions
end

-- How macOS places a desktop picture for `position`: NSWorkspace's
-- scaling (NSImageScaling: 3 proportionally up or down, 1 axes
-- independently) and whether it may crop. macOS centers what it crops, so
-- fill-top and fill-bottom are drawn as fill.
function M.placement(position)
    if position == "fit" then
        return { scaling = 3, clip = false }
    elseif position == "stretch" then
        return { scaling = 1, clip = false }
    end
    return { scaling = 3, clip = true }
end

-- JavaScript for JXA (hs.osascript.javascript), through its ObjC bridge,
-- since hs.screen:desktopImageURL gives macOS no placement: sets the
-- picture at file URL `url` on every display not showing it placed as
-- `placement` (M.placement's) already. Gives, as JSON, what macOS said
-- for each display it wouldn't set.
function M.desktop_script(url, placement)
    return "ObjC.import('AppKit');\n(function () {"
        .. "const URL = " .. names.js_string(url) .. ", SCALING = " .. string.format("%d", placement.scaling)
        .. ", CLIP = " .. tostring(placement.clip) .. ";"
        .. [[
  const ws = $.NSWorkspace.sharedWorkspace;
  const scalingKey = $.NSWorkspaceDesktopImageScalingKey;
  const clipKey = $.NSWorkspaceDesktopImageAllowClippingKey;
  const options = $.NSMutableDictionary.dictionary;
  options.setObjectForKey($.NSNumber.numberWithInteger(SCALING), scalingKey);
  options.setObjectForKey($.NSNumber.numberWithBool(CLIP), clipKey);
  const picture = $.NSURL.URLWithString(URL);
  const screens = $.NSScreen.screens;
  const refused = [];
  for (let i = 0; i < screens.count; i++) {
    const screen = screens.objectAtIndex(i);
    const now = ws.desktopImageURLForScreen(screen);
    const placed = ws.desktopImageOptionsForScreen(screen);
    const scaling = placed && placed.objectForKey(scalingKey);
    const clip = placed && placed.objectForKey(clipKey);
    if (now && now.absoluteString.js === URL && scaling && scaling.intValue === SCALING
        && clip && Boolean(clip.boolValue) === CLIP) {
      continue;
    }
    const error = Ref();
    if (!ws.setDesktopImageURLForScreenOptionsError(picture, screen, options, error)) {
      refused.push(error[0] ? String(error[0].localizedDescription.js) : "macOS didn't say why");
    }
  }
  return JSON.stringify(refused);
})()]]
end

-- `path` with a leading ~/ as `home`.
function M.expand(path, home)
    if path:sub(1, 2) == "~/" then
        return home .. path:sub(2)
    end
    return path
end

-- The setting for a file chosen, `path`: one under `home` from ~/, so it
-- reads the same on another machine sharing appearance.json, as tide's
-- pickedWallpaper; nil for none.
function M.setting(path, home)
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("[\n\r]") then
        return nil
    end
    if home ~= "" and path:sub(1, #home + 1) == home .. "/" then
        return "~/" .. path:sub(#home + 2)
    end
    return path
end

-- The picture to show for the mode, `dark` or light, from `walls`
-- (M.load's), as a path, or nil to leave macOS's own; for a color, nil and
-- the color as rrggbb, to be drawn.
function M.now(walls, dark, home)
    local set = walls[dark and "dark" or "light"]
    if set == nil or set == "" then
        return nil
    end
    if M.is_color(set) then
        return nil, M.hex(set)
    end
    return M.expand(set, home)
end

-- The file:// URL for `path`, as macOS takes a desktop picture's: each
-- byte but a letter, digit, slash or one of -._~ percent-encoded.
function M.file_url(path)
    return "file://" .. (path:gsub("[^%w%-%._~/]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- The folder the chooser opens in for `setting`: its file's, or `home`'s
-- Pictures for none.
function M.folder(setting, home)
    local full = setting ~= "" and M.expand(setting, home) or ""
    return full:match("^(.*)/[^/]*$") or (home .. "/Pictures")
end

return M
