local t = require("t")
local volume = require("tide.volume")

t.test("the popover lists the outputs by name, marking the one in use", function()
    local s = volume.state({ name = "Speakers", volume = 40.4, muted = false },
        { { uid = "b", name = "Speakers" }, { uid = "a", name = "LG" }, { name = "no uid" } }, "b", false)
    t.eq(s.outputs, { { uid = "a", name = "LG", current = false }, { uid = "b", name = "Speakers", current = true } })
    t.eq(s.volume, 40)
    t.eq(s.muted, false)
    t.eq(s.can_mute, true)
    t.eq(s.live, true, "macOS's own volume follows the slider")
end)

t.test("an output with no volume control has no level, and a DDC monitor's is set on release", function()
    local s = volume.state({ name = "LG" }, {}, nil, false)
    t.eq(s.volume, nil)
    t.eq(s.can_mute, false)
    t.eq(volume.state({ name = "LG", volume = 30, muted = true }, {}, nil, true).live, false)
    t.eq(volume.state(nil, {}, nil, false).name, nil, "no output at all")
end)

t.test("the popover sits under the speaker, kept on the bar's display", function()
    local bar = { x = 100, y = 25, w = 1000, h = 30 }
    t.eq(volume.frame(bar, 900, 2), { x = 700, y = 55, w = volume.WIDTH, h = volume.CHROME + 2 * volume.ROW })
    t.eq(volume.frame(bar, 50, 2).x, 100, "not off the left edge")
    t.eq(volume.frame(bar, 5000, 2).x, 800, "not off the right edge")
    t.eq(volume.frame(bar, nil, 1).x, 800, "no position: the right end")
    t.eq(volume.height(100), volume.MAX_HEIGHT, "many outputs scroll")
end)

t.test("the popover's messages set the volume, mute, output, or open settings", function()
    local got = {}
    local act = {
        set_volume = function(v)
            got[#got + 1] = "volume " .. v
        end,
        set_mute = function(on)
            got[#got + 1] = "mute " .. tostring(on)
        end,
        use = function(uid)
            got[#got + 1] = "use " .. uid
        end,
        settings = function()
            got[#got + 1] = "settings"
        end,
        close = function()
            got[#got + 1] = "close"
        end,
    }
    for _, body in ipairs({ { volume = 120 }, { volume = "33.6" }, { volume = "x" }, { mute = true }, { mute = false },
        { output = "a" }, { output = 3 }, { settings = true }, { close = true }, "junk" }) do
        volume.handle(body, act)
    end
    t.eq(got, { "volume 100", "volume 34", "mute true", "mute false", "use a", "settings", "close" })
end)

t.test("the popover's page draws the output and sends what its controls ask", function()
    if not os.execute("command -v node >/dev/null 2>&1") then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to check the volume popover's page")
        end
        print("SKIP the volume popover's page: no node")
        return
    end
    local p = io.popen("node tests/volume_page.cjs hammerspoon/tide/dashboard/volume.js 2>&1")
    local out = p:read("a")
    if not p:close() then
        error(out)
    end
end)

t.test("the popover's page has the bar's colors and its script in place", function()
    local html = require("tide.volume_hs").page()
    t.eq(html:find("TIDE_", 1, true), nil, "no marker left")
    t.eq(html:find("--accent", 1, true) ~= nil, true, "launcher.css's colors")
    t.eq(html:find("window.tide = { update }", 1, true) ~= nil, true, "volume.js")
end)

t.done("volume")
