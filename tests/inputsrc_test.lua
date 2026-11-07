-- The Keyboard page's input sources (inputsrc.lua): macOS's layouts and
-- input methods, the one in use lit, and a click using another.

local t = require("t")
local inputsrc = require("tide.inputsrc")

t.test("layouts, then input methods, the one in use lit", function()
    t.eq(inputsrc.state({ "U.S.", "Irish" }, { "Pinyin - Simplified" }, "Irish").sources, {
        { name = "U.S.", method = false, current = false },
        { name = "Irish", method = false, current = true },
        { name = "Pinyin - Simplified", method = true, current = false },
    })
    t.eq(inputsrc.state(nil, nil, nil).sources, {})
end)

t.test("a click uses a source macOS has on, and only one of those", function()
    local sources = inputsrc.state({ "U.S." }, { "Pinyin - Simplified" }, "U.S.").sources
    local used = {}
    local use = function(name, method)
        used[#used + 1] = { name, method }
    end
    t.eq(inputsrc.handle({ inputSource = "Pinyin - Simplified" }, sources, use), true)
    t.eq(inputsrc.handle({ inputSource = "Klingon" }, sources, use), true, "the page's, but nothing done")
    t.eq(inputsrc.handle({ soundMute = true }, sources, use), false)
    t.eq(used, { { "Pinyin - Simplified", true } })
end)

t.test("a switch made anywhere reaches each that follows it, the bar and the page", function()
    local changed
    local keycodes = {
        inputSourceChanged = function(fn)
            changed = fn
        end,
    }
    local logged, heard = {}, {}
    local on = inputsrc.watch(keycodes, function(line)
        logged[#logged + 1] = line
    end)
    on(function()
        error("the bar's broken")
    end)
    on(function()
        heard[#heard + 1] = "page"
    end)
    changed()
    t.eq(heard, { "page" }, "one that fails doesn't keep it from the rest")
    t.eq(#logged, 1)
    t.eq(logged[1]:match("the bar's broken") ~= nil, true, logged[1])
end)

t.done("inputsrc")
