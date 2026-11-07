-- What the desktop calls itself on screen: tide, with tide's logo, whatever
-- the code is called (brand.lua).
local t = require("t")
local brand = require("tide.brand")
local launcher = require("tide.launcher")

local DIR = "hammerspoon/tide/"

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("a")
    f:close()
    return s
end

local function says_tilemo(s)
    return tostring(s):lower():find("tilemo", 1, true) ~= nil
end

-- A stand-in for whatever hs.* the adapter touches as it's made: every
-- field is a function returning the stand-in again.
local function anything()
    local any
    any = setmetatable({}, {
        __index = function()
            return any
        end,
        __call = function()
            return any
        end,
    })
    return any
end

-- The adapter, made against a fake hs that keeps each notification's
-- attributes and each image path read.
local function adapter()
    local seen = { notes = {}, paths = {}, logs = {} }
    local was = _G.hs
    _G.hs = setmetatable({
        notify = {
            new = function(fn, attrs)
                seen.notes[#seen.notes + 1] = { fn = fn, attrs = attrs }
                return { send = function() end }
            end,
        },
        image = {
            imageFromPath = function(path)
                seen.paths[#seen.paths + 1] = path
                if seen.unreadable then
                    return nil
                end
                local img = { path = path }
                function img.size(self, s)
                    self.pt = s
                end
                function img.template(self, on)
                    self.is_template = on
                end
                return img
            end,
        },
        logger = {
            new = function()
                return {
                    i = function(text)
                        seen.logs[#seen.logs + 1] = text
                    end,
                }
            end,
        },
    }, {
        __index = function()
            return anything()
        end,
    })
    package.loaded["tide.hs_adapter"] = nil
    local ok, a = pcall(function()
        return require("tide.hs_adapter").new()
    end)
    package.loaded["tide.hs_adapter"] = nil
    if not ok then
        _G.hs = was
        error(a)
    end
    -- The fake stays for the adapter's calls; done() puts back what was.
    seen.done = function()
        _G.hs = was
    end
    return a, seen
end

t.test("a notification is titled tide and shows the logo", function()
    local a, seen = adapter()
    local open = function() end
    local ok, err = pcall(function()
        a.notify("Couldn't save")
        a.notify("Muted Slack", open, { withdrawAfter = 10 })
    end)
    seen.done()
    assert(ok, err)
    t.eq(#seen.notes, 2)
    for _, n in ipairs(seen.notes) do
        t.eq(n.attrs.title, "tide")
        t.eq(says_tilemo(n.attrs.title), false)
        t.eq(n.attrs.contentImage.path, DIR .. "icons/tide.png")
    end
    t.eq(seen.notes[1].attrs.informativeText, "Couldn't save")
    t.eq(seen.notes[2].fn, open, "a click still does what the caller asked")
    t.eq(seen.notes[2].attrs.withdrawAfter, 10)
end)

t.test("the logo is read once, the menu bar's as a template at 16 pt", function()
    local a, seen = adapter()
    local template = a.logo(brand.TEMPLATE)
    local logo = a.logo(brand.LOGO)
    a.logo(brand.TEMPLATE)
    seen.done()
    t.eq(template.path, DIR .. "icons/tide-template.png")
    t.eq(template.is_template, true)
    t.eq(template.pt, { w = 16, h = 16 })
    t.eq(logo.is_template, false)
    t.eq(#seen.paths, 2, "each read once")
end)

t.test("a logo that can't be read is left off, and logged", function()
    local a, seen = adapter()
    seen.unreadable = true
    local logo = a.logo(brand.LOGO)
    seen.done()
    t.eq(logo, nil)
    t.eq(#seen.logs, 1)
    t.eq(seen.logs[1]:find("couldn't read the logo", 1, true) ~= nil, true, seen.logs[1])
end)

t.test("the windows' and menu bar's titles say tide", function()
    t.eq(brand.title("settings"), "tide settings")
    t.eq(brand.title("bar"), "tide bar")
    t.eq(brand.title(), "tide")
    for _, page in ipairs({ "settings.html", "bar.html", "dashboard.html" }) do
        local title = read(DIR .. "dashboard/" .. page):match("<title>(.-)</title>")
        t.eq(title:find("^tide") ~= nil, true, page .. ": " .. title)
        t.eq(says_tilemo(title), false, page)
    end
end)

t.test("tide's own commands say tide, show the logo and keep their place in the switcher", function()
    local items = launcher.items({}, {}, launcher.COMMANDS, {}, {}, {}, {})
    local by_title = {}
    for _, item in ipairs(items) do
        t.eq(says_tilemo(item.title), false, item.title)
        by_title[item.title] = item
    end
    t.eq(by_title["Reload tide"].logo, true)
    t.eq(by_title["Reload tide"].key, "command:Reload tilemo", "the use remembered before the rename")
    t.eq(by_title["Check tide (doctor)"].logo, true)
    t.eq(by_title["Check tide (doctor)"].key, "command:Check tilemo (doctor)")
    t.eq(by_title["Lock"].logo, nil)
    t.eq(by_title["Lock"].key, "command:Lock")
end)

-- The `d`s of every <path> in `s`, in order.
local function paths(s)
    local out = {}
    for d in s:gmatch('<path[^>]-%sd="([^"]+)"') do
        out[#out + 1] = d
    end
    return out
end

t.test("the bar's logo is tide's SVG, which the PNGs are rendered from", function()
    local want = paths(read(DIR .. "icons/tide-symbolic.svg"))
    t.eq(#want, 2)
    local html = read(DIR .. "dashboard/bar.html")
    local svg = html:match('id="logo"[^>]*>(<svg.-</svg>)')
    t.eq(svg ~= nil, true, "bar.html")
    t.eq(paths(svg), want, "bar.html")
end)

-- Width, height, bit depth and color type from a PNG's IHDR.
local function png(path)
    local s = read(path)
    t.eq(s:sub(1, 8), "\137PNG\r\n\26\n", path)
    t.eq(s:sub(13, 16), "IHDR", path)
    return string.unpack(">I4I4BB", s, 17)
end

t.test("the logo's renders are 4x their size in points, with alpha", function()
    for name, size in pairs({ [brand.TEMPLATE] = brand.TEMPLATE_SIZE, [brand.LOGO] = brand.LOGO_SIZE }) do
        local w, h, depth, kind = png(brand.icon_path("hammerspoon/tide", name))
        t.eq({ w, h }, { size.w * 4, size.h * 4 }, name)
        t.eq(depth, 8, name)
        t.eq(kind, 6, name .. " is RGBA")
    end
end)

-- The names in the code that stay tilemo, so users' init.lua and saved
-- state keep working: hs.settings keys, files and folders, the message
-- handler pages talk to, conf's Karabiner rule, setup-macos's flag.
local INTERNAL = {
    "^Reload tilemo$", -- what the switcher remembers a command's use by
    "^Check tilemo %(doctor%)$",
    -- What tide moves over from when it was tilemo: hs.settings keys, the
    -- Caches folder, conf's Karabiner rule and its file, and the shim's note.
    "^tilemo%.$",
    "^Library/Caches/tilemo$",
    "^tilemo:$",
    "^tilemo%.json$",
    '^tide: require%("tilemo"%) is deprecated; use require%("tide"%)$',
}

local function internal(s)
    -- Naming a require is about the code, not the desktop.
    if not says_tilemo((s:gsub('require%("tilemo[%w_.]*"%)', ""))) then
        return true
    end
    for _, p in ipairs(INTERNAL) do
        if s:find(p) then
            return true
        end
    end
    return false
end

-- Whether the `/` at `i` in JavaScript `src` starts a regex literal rather
-- than dividing: it does after an operator or opening bracket, or at the
-- start, but not after a value.
local function regex_start(src, i)
    local before = src:sub(1, i - 1):match("(%S)%s*$")
    return before == nil or before:find("[%(,=:%[!&|%?{};]") ~= nil
end

-- Where the regex literal whose body starts at `i` ends, past its closing
-- `/`: a `/` inside a character class or after a backslash doesn't close it.
local function regex_end(src, i, n)
    local class = false
    while i <= n do
        local c = src:sub(i, i)
        if c == "\\" then
            i = i + 1
        elseif c == "[" then
            class = true
        elseif c == "]" then
            class = false
        elseif c == "/" and not class then
            return i + 1
        elseif c == "\n" then
            return i
        end
        i = i + 1
    end
    return i
end

-- Each string literal in Lua or JavaScript `src`, outside comments and
-- regex literals.
local function literals(src, js)
    local out = {}
    local i, n = 1, #src
    while i <= n do
        local c = src:sub(i, i)
        local two = src:sub(i, i + 1)
        if (not js and two == "--") or (js and two == "//") then
            if not js and src:sub(i + 2, i + 3) == "[[" then
                i = (src:find("]]", i + 4, true) or n) + 2
            else
                i = (src:find("\n", i, true) or n) + 1
            end
        elseif js and two == "/*" then
            i = (src:find("*/", i + 2, true) or n) + 2
        elseif js and c == "/" and regex_start(src, i) then
            i = regex_end(src, i + 1, n)
        elseif not js and two == "[[" then
            local stop = src:find("]]", i + 2, true) or n
            out[#out + 1] = src:sub(i + 2, stop - 1)
            i = stop + 2
        elseif c == '"' or c == "'" or (js and c == "`") then
            local j = i + 1
            while j <= n and src:sub(j, j) ~= c do
                if src:sub(j, j) == "\\" then
                    j = j + 1
                end
                j = j + 1
            end
            out[#out + 1] = src:sub(i + 1, j - 1)
            i = j + 1
        else
            i = i + 1
        end
    end
    return out
end

t.test("the scan finds strings, not comments", function()
    t.eq(literals('-- "tilemo"\nx("a \\"b\\"", \'c\') --[[ "d" ]] y([[e]])'), { 'a \\"b\\"', "c", "e" })
    t.eq(literals('// "tilemo"\n/* "x" */ f(`a`, "b")', true), { "a", "b" })
    t.eq(literals('const r = /["\'`]/u; f("a", x / 2, "b")', true), { "a", "b" }, "a regex's quotes start no string")
end)

local function files(dir, ext)
    local out = {}
    local p = assert(io.popen('ls "' .. dir .. '"'))
    for name in p:lines() do
        if name:sub(-#ext) == ext then
            out[#out + 1] = dir .. name
        end
    end
    p:close()
    return out
end

t.test("nothing shown says tilemo: every string in the code is tide, or one of the kept names", function()
    local found = {}
    local sources = files(DIR, ".lua")
    sources[#sources + 1] = "hammerspoon/timo/init.lua"
    for _, path in ipairs(sources) do
        for _, s in ipairs(literals(read(path))) do
            if says_tilemo(s) and not internal(s) then
                found[#found + 1] = path .. ": " .. s
            end
        end
    end
    for _, path in ipairs(files(DIR .. "dashboard/", ".js")) do
        for _, s in ipairs(literals(read(path), true)) do
            if says_tilemo(s) then
                found[#found + 1] = path .. ": " .. s
            end
        end
    end
    -- A page's text, without its comments and the build's placeholders.
    for _, path in ipairs(files(DIR .. "dashboard/", ".html")) do
        local html = read(path):gsub("<!%-%-.-%-%->", ""):gsub("/%*TILEMO_%u+%*/", "")
        html = html:gsub("(<style>)(.-)(</style>)", function(a, css, b)
            return a .. css:gsub("/%*.-%*/", "") .. b
        end)
        html = html:gsub("(<script>)(.-)(</script>)", function(a, js, b)
            return a .. table.concat(literals(js, true), " ") .. b
        end)
        for line in html:gmatch("[^\n]+") do
            if says_tilemo(line) then
                found[#found + 1] = path .. ": " .. line
            end
        end
    end
    t.eq(found, {})
end)

t.done("brand")
