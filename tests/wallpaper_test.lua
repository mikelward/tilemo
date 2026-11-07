-- The wallpapers from tide's appearance files (wallpaper.lua): read as
-- tide reads them, the local file's over the shared one's, shown for the
-- mode macOS is in, and a file chosen set as tide sets one.

local t = require("t")
local wallpaper = require("tide.wallpaper")
local json = require("json")

local HOME = "/Users/u"

t.test("each mode's wallpaper, the local file's over the shared one's", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "~/day.jpg", "darkWallpaper": "/srv/night.png"}',
        '{"darkWallpaper": "~/Pictures/dark.heic"}', json.decode)
    t.eq(walls, { light = "~/day.jpg", dark = "~/Pictures/dark.heic" })
    t.eq(errors, {})
end)

t.test("none set, or no files, leaves macOS's own", function()
    local walls = wallpaper.load(nil, nil, json.decode)
    t.eq(walls, { light = "", dark = "" })
    t.eq(wallpaper.now(walls, true, HOME), nil)
    t.eq(wallpaper.now(wallpaper.load('{"lightWallpaper": ""}', nil, json.decode), false, HOME), nil)
end)

t.test("what's wrong with a file is said, and its good settings still count", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "day.jpg", "darkWallpaper": "~/n.png"}', "{", json.decode)
    t.eq(walls, { light = "", dark = "~/n.png" })
    t.eq(errors, {
        "appearance.json: lightWallpaper must be a file's path, such as \"~/Pictures/day.jpg\", a color such as \"#1a1d2e\", or \"\" for the default",
        "appearance.local.json isn't a JSON object",
    })
end)

t.test("a color set on tide is a setting, drawn as rrggbb", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "#1A1D2E", "darkWallpaper": "#abc"}', nil, json.decode)
    t.eq(errors, {})
    t.eq({ wallpaper.now(walls, false, HOME) }, { nil, "1a1d2e" })
    t.eq({ wallpaper.now(walls, true, HOME) }, { nil, "aabbcc" })
    t.eq(wallpaper.color_file("/x", "aabbcc"), "/x/wallpaper-aabbcc.png")
    local _, bad = wallpaper.load('{"lightWallpaper": "#12"}', nil, json.decode)
    t.eq(bad, { 'appearance.json: lightWallpaper must be a color as #rrggbb or #rgb, such as "#1a1d2e"' })
end)

-- Each mode's position, as tide's (tide SPEC.md §15): its own, else
-- wallpaperPosition for both, else fill.
local ONE = '"fill", "fill-top", "fill-bottom", "fit", "stretch"'

t.test("each mode's picture has its own position, wallpaperPosition both's", function()
    local _, errors, positions = wallpaper.load('{"wallpaperPosition": "fit", "darkWallpaperPosition": "stretch"}',
        '{"lightWallpaperPosition": "fill-top"}', json.decode)
    t.eq(errors, {})
    t.eq(positions, { light = "fill-top", dark = "stretch" })
    local _, _, both = wallpaper.load('{"wallpaperPosition": "fit"}', nil, json.decode)
    t.eq(both, { light = "fit", dark = "fit" }, "where a mode sets none")
    local _, _, none = wallpaper.load(nil, nil, json.decode)
    t.eq(none, { light = "fill", dark = "fill" }, "fill by default")
    local _, bad, kept = wallpaper.load('{"darkWallpaperPosition": "middle"}', '{"lightWallpaperPosition": "fit"}',
        json.decode)
    t.eq(bad, { "appearance.json: darkWallpaperPosition must be one of " .. ONE })
    t.eq(kept, { light = "fit", dark = "fill" }, "a position that's wrong is left out")
end)

t.test("each position as macOS places a desktop picture", function()
    -- NSImageScaleProportionallyUpOrDown is 3, NSImageScaleAxesIndependently 1.
    t.eq(wallpaper.placement("fill"), { scaling = 3, clip = true }, "Fill Screen: zoomed, the rest cropped")
    t.eq(wallpaper.placement("fill-top"), { scaling = 3, clip = true }, "centered: macOS can't keep an edge")
    t.eq(wallpaper.placement("fill-bottom"), { scaling = 3, clip = true })
    t.eq(wallpaper.placement("fit"), { scaling = 3, clip = false }, "Fit to Screen: all of it")
    t.eq(wallpaper.placement("stretch"), { scaling = 1, clip = false }, "Stretch to Fill Screen")
end)

local run = require("jsrun")("the desktop picture's JavaScript")

-- macOS, as the desktop picture's JavaScript sees it through JXA's ObjC
-- bridge: two displays, the first showing `url` placed as `shown`, and
-- what each set asked for.
local function fake_macos(url, shown, refuse)
    return [[
globalThis.ObjC = { import() {} };
const num = (v) => ({ intValue: v, boolValue: v });
const dict = (o) => ({ o, objectForKey(k) { return o[k] === undefined ? undefined : num(o[k]); },
  setObjectForKey(v, k) { o[k] = v.intValue; } });
const SET = [];
const screens = [
  { name: "one", url: ]] .. string.format("%q", url) .. [[, options: ]] .. shown .. [[ },
  { name: "two", url: "file:///System/Library/Desktop%20Pictures/Sonoma.heic", options: {} },
];
globalThis.Ref = () => [];
globalThis.$ = {
  NSWorkspaceDesktopImageScalingKey: "scaling", NSWorkspaceDesktopImageAllowClippingKey: "clip",
  NSNumber: { numberWithInteger: num, numberWithBool: (v) => num(v ? 1 : 0) },
  NSMutableDictionary: { get dictionary() { return dict({}); } },
  NSURL: { URLWithString: (s) => ({ absoluteString: { js: s } }) },
  NSScreen: { screens: { count: 2, objectAtIndex: (i) => screens[i] } },
  NSWorkspace: { sharedWorkspace: {
    desktopImageURLForScreen: (s) => ({ absoluteString: { js: s.url } }),
    desktopImageOptionsForScreen: (s) => dict(s.options),
    setDesktopImageURLForScreenOptionsError(u, s, opts, err) {
      if (]] .. (refuse and "true" or "false") .. [[) { err[0] = { localizedDescription: { js: "not allowed" } }; return false; }
      SET.push([s.name, u.absoluteString.js, opts.o.scaling, opts.o.clip]); s.url = u.absoluteString.js; return true;
    },
  } },
};
]]
end

if run then
    local URL = "file:///Users/u/day.jpg"
    t.test("the desktop picture is set on each display not showing it so, with macOS's placement", function()
        local script = wallpaper.desktop_script(URL, wallpaper.placement("stretch"))
        local ok, out = run(fake_macos(URL, "{ scaling: 1, clip: 0 }") .. script .. "\n;JSON.stringify(SET)")
        t.eq(ok, true, out)
        t.eq(json.decode(out), { { "two", URL, 1, 0 } }, "the first shows it stretched already")
        ok, out = run(fake_macos(URL, "{ scaling: 3, clip: 1 }") .. script .. "\n;JSON.stringify(SET)")
        t.eq(json.decode(out), { { "one", URL, 1, 0 }, { "two", URL, 1, 0 } }, "the same picture, placed otherwise")
    end)

    t.test("a display macOS won't set is said", function()
        local ok, out = run(fake_macos(URL, "{}", true) .. wallpaper.desktop_script(URL, wallpaper.placement("fill")))
        t.eq(ok, true, out)
        t.eq(json.decode(out), { "not allowed", "not allowed" })
    end)
end

t.test("the picture shown is the mode's, from ~/ as home", function()
    local walls = { light = "~/Pictures/day.jpg", dark = "/srv/night.png" }
    t.eq(wallpaper.now(walls, false, HOME), "/Users/u/Pictures/day.jpg")
    t.eq(wallpaper.now(walls, true, HOME), "/srv/night.png")
end)

t.test("a file chosen is set from ~/ when it's home's", function()
    t.eq(wallpaper.setting("/Users/u/Pictures/Day one.jpg", HOME), "~/Pictures/Day one.jpg")
    t.eq(wallpaper.setting("/Library/Desktop Pictures/Sky.heic", HOME), "/Library/Desktop Pictures/Sky.heic")
    t.eq(wallpaper.setting("/Users/uv/a.png", HOME), "/Users/uv/a.png", "not /Users/uv, which only starts like home")
    t.eq(wallpaper.setting(nil, HOME), nil)
    t.eq(wallpaper.setting("a.png", HOME), nil)
end)

t.test("the picture's URL is encoded, as macOS takes one", function()
    t.eq(wallpaper.file_url("/Users/u/Pictures/Day one.jpg"), "file:///Users/u/Pictures/Day%20one.jpg")
    t.eq(wallpaper.file_url("/srv/a+b#c?é.png"), "file:///srv/a%2Bb%23c%3F%C3%A9.png")
end)

t.test("the chooser opens where the wallpaper is, or in Pictures", function()
    t.eq(wallpaper.folder("~/Pictures/walls/day.jpg", HOME), "/Users/u/Pictures/walls")
    t.eq(wallpaper.folder("/srv/night.png", HOME), "/srv")
    t.eq(wallpaper.folder("", HOME), "/Users/u/Pictures")
end)

t.done("wallpaper")
