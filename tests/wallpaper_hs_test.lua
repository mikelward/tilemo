-- The desktop picture from tide's wallpapers (wallpaper_hs.lua), against
-- stand-in displays, files and macOS's appearance: set on every display
-- for the mode it's in, again as the mode changes or a display comes, and
-- left alone with none set; and macOS's file dialog for choosing one.

local t = require("t")
local json = require("json")

local HOME = os.getenv("HOME") or ""

-- tide's world: `files` by path (tide's settings folder is /c/tide),
-- the pictures that exist, macOS's mode, and the dialog's answer.
local function stub(opts)
    local s = { logged = {}, set = {}, dark = opts.dark or false, chooser = opts.chooser }
    s.screens = {}
    -- A display, showing `url`.
    function s.add_screen(url)
        local i = #s.screens + 1
        local scr = { url = url or "file:///System/Library/Desktop%20Pictures/Sonoma.heic" }
        function scr.desktopImageURL(self, set)
            if set == nil then
                return self.url
            end
            self.url = set
            s.set[#s.set + 1] = { i, set }
        end
        s.screens[i] = scr
    end
    for _ = 1, opts.screens or 1 do
        s.add_screen()
    end
    _G.hs = {
        json = { decode = json.decode },
        host = {
            interfaceStyle = function()
                return s.dark and "Dark" or nil
            end,
        },
        fs = {
            attributes = function(path, what)
                t.eq(what, "mode")
                return (opts.pictures or {})[path] and "file" or nil
            end,
            mkdir = function(dir)
                s.made_dir = dir
            end,
        },
        -- A color's picture, drawn: saved as a file that then exists.
        canvas = {
            new = function()
                local c = {}
                function c.appendElements(_, e)
                    s.drawn = e.fillColor.hex
                end
                function c.imageFromCanvas()
                    return {
                        saveToFile = function(_, path)
                            if opts.cant_save then
                                return false
                            end
                            opts.pictures = opts.pictures or {}
                            opts.pictures[path] = true
                            s.saved = (s.saved or 0) + 1
                            return true
                        end,
                    }
                end
                function c.delete() end
                return c
            end,
        },
        screen = {
            allScreens = function()
                return s.screens
            end,
            watcher = {
                new = function(fn)
                    s.screen_changed = fn
                    return { start = function() end }
                end,
            },
        },
        distributednotifications = {
            new = function(fn, name)
                t.eq(name, "AppleInterfaceThemeChangedNotification")
                s.theme_changed = fn
                return { start = function() end }
            end,
        },
        dialog = {
            chooseFileOrFolder = function(message, folder, files, dirs, many, types)
                s.asked = { message = message, folder = folder, files = files, dirs = dirs, many = many, types = types }
                return s.chooser
            end,
        },
    }
    s.placed = {}
    local tide = {
        clock_dir = "/c/tide",
        adapter = {
            read = function(path)
                return (opts.files or {})[path]
            end,
            -- The desktop picture's JavaScript (wallpaper.desktop_script),
            -- as macOS would run it: each display not showing the picture
            -- placed so is set, as Hammerspoon's own call can't place one.
            javascript = function(source)
                if opts.js_fails then
                    return false, "JXA isn't there"
                end
                local q, scaling, clip = source:match('const URL = (".-"), SCALING = (%d+), CLIP = (%a+);')
                local url = json.decode(q)
                local placement = { scaling = tonumber(scaling), clip = clip == "true" }
                if opts.refuse then
                    return true, '["not allowed"]'
                end
                for i, scr in ipairs(s.screens) do
                    local was = s.placed[i]
                    if scr.url ~= url or not was or was.scaling ~= placement.scaling or was.clip ~= placement.clip then
                        scr.url = url
                        s.placed[i] = placement
                        s.set[#s.set + 1] = { i, url }
                    end
                end
                return true, "[]"
            end,
            log = function(text)
                s.logged[#s.logged + 1] = text
            end,
        },
    }
    package.loaded["tide.wallpaper_hs"] = nil
    s.wall = require("tide.wallpaper_hs").new(tide)
    return s
end

local FILES = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "/srv/day one.jpg", "darkWallpaper": "/srv/night.png"}' }
local PICTURES = { ["/srv/day one.jpg"] = true, ["/srv/night.png"] = true }

t.test("every display shows the wallpaper for the mode macOS is in", function()
    local s = stub({ files = FILES, pictures = PICTURES, screens = 2 })
    t.eq(s.set, { { 1, "file:///srv/day%20one.jpg" }, { 2, "file:///srv/day%20one.jpg" } })
end)

t.test("turning dark shows the dark one, and a new display gets it too", function()
    local s = stub({ files = FILES, pictures = PICTURES })
    s.dark = true
    s.theme_changed()
    t.eq(s.screens[1].url, "file:///srv/night.png")
    s.add_screen("file:///other.png")
    s.set = {}
    s.screen_changed()
    t.eq(s.set, { { 2, "file:///srv/night.png" } }, "only the display that didn't show it")
end)

t.test("with none set, or no such file, macOS's own picture stays", function()
    local s = stub({ files = {}, pictures = PICTURES })
    t.eq(s.set, {})
    local gone = stub({ files = FILES, pictures = {} })
    t.eq(gone.set, {})
    t.eq(gone.logged, { "wallpaper: no file at /srv/day one.jpg; the desktop picture stays as it is" })
end)

t.test("a color from tide is drawn once into a picture, and shown on every display", function()
    local s = stub({ files = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "#1A1D2E"}' }, pictures = {}, screens = 2 })
    local file = HOME .. "/Library/Application Support/tide/wallpaper-1a1d2e.png"
    t.eq(s.drawn, "#1a1d2e")
    t.eq(s.made_dir, HOME .. "/Library/Application Support/tide")
    t.eq(#s.set, 2)
    t.eq(s.screens[1].url, "file://" .. HOME:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end)
        .. "/Library/Application%20Support/tide/wallpaper-1a1d2e.png")
    s.screen_changed()
    t.eq(s.saved, 1, "drawn once: " .. file)
    t.eq(s.logged, {})
end)

t.test("a color that can't be drawn leaves the picture, said once", function()
    local s = stub({ files = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "#1a1d2e"}' }, pictures = {}, screens = 2,
        cant_save = true })
    s.screen_changed()
    t.eq(s.set, {})
    t.eq(#s.logged, 1, "not at every display change")
    t.eq(s.logged[1]:match("^wallpaper: couldn't draw #1a1d2e") ~= nil, true, s.logged[1])
end)

t.test("each mode's picture is placed as its position says", function()
    local files = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "/srv/day one.jpg", "darkWallpaper": "/srv/night.png",'
        .. ' "lightWallpaperPosition": "stretch", "darkWallpaperPosition": "fit"}' }
    local s = stub({ files = files, pictures = PICTURES, screens = 2 })
    t.eq(s.placed, { { scaling = 1, clip = false }, { scaling = 1, clip = false } }, "light's stretched")
    s.dark = true
    s.theme_changed()
    t.eq(s.placed[1], { scaling = 3, clip = false }, "dark's fitted whole")
    t.eq(s.screens[1].url, "file:///srv/night.png")
end)

t.test("a position changed alone places the same picture again", function()
    local files = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "/srv/day one.jpg"}' }
    local s = stub({ files = files, pictures = PICTURES })
    t.eq(s.placed[1], { scaling = 3, clip = true }, "filled, cropped, by default")
    files["/c/tide/appearance.local.json"] = '{"lightWallpaperPosition": "fit"}'
    s.set = {}
    s.wall.apply()
    t.eq(s.set, { { 1, "file:///srv/day%20one.jpg" } })
    t.eq(s.placed[1], { scaling = 3, clip = false })
    s.set = {}
    s.wall.apply()
    t.eq(s.set, {}, "placed so already: left alone")
end)

t.test("a display macOS won't set, or JXA not running, is said", function()
    local refused = stub({ files = FILES, pictures = PICTURES, refuse = true })
    t.eq(refused.logged, { "wallpaper: macOS didn't set /srv/day one.jpg on a display: not allowed" })
    local broken = stub({ files = FILES, pictures = PICTURES, js_fails = true })
    t.eq(broken.logged, { "wallpaper: couldn't set /srv/day one.jpg: JXA isn't there" })
end)

t.test("choosing opens macOS's dialog, offering images, where the wallpaper is", function()
    local s = stub({ files = FILES, pictures = PICTURES, chooser = { ["1"] = HOME .. "/Pictures/Dusk.heic" } })
    t.eq(s.wall.pick("darkWallpaper"), "~/Pictures/Dusk.heic")
    t.eq(s.asked, { message = "Choose the dark wallpaper", folder = "/srv", files = true, dirs = false, many = false,
        types = { "public.image" } })
end)

t.test("a cancel chooses nothing", function()
    local s = stub({ files = FILES, pictures = PICTURES })
    t.eq(s.wall.pick("lightWallpaper"), nil)
end)

t.done("wallpaper_hs")
