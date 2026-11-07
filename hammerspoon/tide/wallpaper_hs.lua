-- The desktop picture from tide's wallpapers, light and dark (SPEC.md §10;
-- wallpaper.lua): set on every display for the mode macOS is in, again as
-- the mode changes, a display comes, or the settings do. With none set
-- for the mode, macOS's own picture stays. And the settings window's file
-- chooser for one.

local wallpaper = require("tide.wallpaper")

local M = {}

-- `tide` is the started tide module: its clock_dir (tide's settings
-- folder) and adapter.
function M.new(tide)
    local self = {}
    local home = os.getenv("HOME") or ""
    local reported = ""

    -- The wallpapers set, and each mode's position (wallpaper.load's).
    local function walls()
        local dir = tide.clock_dir
        local read = tide.adapter.read
        local w, errors, positions = wallpaper.load(read(dir .. "/" .. wallpaper.SHARED_FILE),
            read(dir .. "/" .. wallpaper.LOCAL_FILE), hs.json.decode)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported then
            tide.adapter.log("wallpaper: " .. text)
        end
        reported = text
        return w, positions
    end

    local function dark()
        return hs.host.interfaceStyle() == "Dark"
    end

    -- Where a color's picture is drawn: a folder of tide's own, kept
    -- across restarts, since macOS shows the file itself.
    local colors = home .. "/Library/Application Support/tide"

    -- The picture for color `hex`, drawn once: a small square of it, which
    -- macOS stretches to fill each display. Nil, logged, if it can't be:
    -- tried again at each change, but said once for each color.
    local said = {}
    local function drawn(hex)
        local path = wallpaper.color_file(colors, hex)
        if hs.fs.attributes(path, "mode") == "file" then
            return path
        end
        hs.fs.mkdir(colors)
        local ok, saved = pcall(function()
            local c = hs.canvas.new({ x = 0, y = 0, w = 64, h = 64 })
            c:appendElements({ type = "rectangle", action = "fill", fillColor = { hex = "#" .. hex, alpha = 1 } })
            local image = c:imageFromCanvas()
            c:delete()
            return image and image:saveToFile(path)
        end)
        if not ok or not saved then
            if not said[hex] then
                said[hex] = true
                tide.adapter.log("wallpaper: couldn't draw #" .. hex .. " to " .. path .. ": " .. tostring(saved)
                    .. "; the desktop picture stays as it is")
            end
            return nil
        end
        return path
    end

    -- Set the mode's picture, placed as its position says, on every display
    -- that doesn't show it so yet. A color's square is filled.
    function self.apply()
        local w, positions = walls()
        local is_dark = dark()
        local path, hex = wallpaper.now(w, is_dark, home)
        local placement = wallpaper.placement(positions[is_dark and "dark" or "light"])
        if hex then
            path = drawn(hex)
            placement = wallpaper.placement("fill")
        end
        if not path then
            return
        end
        if hs.fs.attributes(path, "mode") ~= "file" then
            tide.adapter.log("wallpaper: no file at " .. path .. "; the desktop picture stays as it is")
            return
        end
        -- Through JXA, as hs.screen:desktopImageURL can't say how to place
        -- it (wallpaper.desktop_script).
        local ok, out = tide.adapter.javascript(wallpaper.desktop_script(wallpaper.file_url(path), placement))
        if not ok then
            tide.adapter.log("wallpaper: couldn't set " .. path .. ": " .. tostring(out))
            return
        end
        local decoded, refused = pcall(hs.json.decode, out)
        if not decoded or type(refused) ~= "table" then
            tide.adapter.log("wallpaper: setting " .. path .. " gave back " .. tostring(out))
            return
        end
        for _, why in ipairs(refused) do
            tide.adapter.log("wallpaper: macOS didn't set " .. path .. " on a display: " .. tostring(why))
        end
    end

    -- The chooser for `key`'s wallpaper (wallpaper.KEYS), macOS's own file
    -- dialog, offering images, where it is now. Returns the setting for
    -- the file chosen, or nil for a cancel.
    function self.pick(key)
        local mode = key == wallpaper.KEYS.dark and "dark" or "light"
        local folder = wallpaper.folder((walls())[mode], home)
        local chosen = hs.dialog.chooseFileOrFolder("Choose the " .. mode .. " wallpaper", folder, true, false, false,
            { "public.image" })
        local path = chosen and (chosen["1"] or chosen[1])
        return wallpaper.setting(path, home)
    end

    -- Kept, as Hammerspoon stops one that's collected.
    self.theme_watch = hs.distributednotifications.new(function()
        self.apply()
    end, "AppleInterfaceThemeChangedNotification")
    self.theme_watch:start()
    self.screen_watch = hs.screen.watcher.new(function()
        self.apply()
    end)
    self.screen_watch:start()
    self.apply()
    return self
end

return M
