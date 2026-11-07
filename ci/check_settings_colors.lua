-- The settings window's colors (dashboard/settings.html's own :root) against
-- tide's palette (its theme/palette.json), light and dark, so the window
-- looks as tide's settings panel does. Each property is named for the
-- palette color it is. Run by `make check-tide`:
--
--   lua ci/check_settings_colors.lua TIDE/theme/palette.json hammerspoon/tide/dashboard/settings.html

local json = require("json")

local KEYS = {
    "surface", "surface-2", "fg", "fg-dim", "fg-faint", "line", "accent", "accent-bg", "accent-fg", "danger",
}

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("a")
    f:close()
    return s
end

local function norm(v)
    return (v:lower():gsub("%s+", ""))
end

local palette = json.decode(read(arg[1]))
local html = read(arg[2])
local light = html:match(":root%s*(%b{})")
local dark = html:match("@media %(prefers%-color%-scheme: dark%)%s*{%s*:root%s*(%b{})")
assert(light and dark, "no palette in " .. arg[2])

local failed = false
for mode, block in pairs({ light = light, dark = dark }) do
    local have = {}
    for name, value in block:gmatch("%-%-([%w-]+):%s*([^;]+);") do
        have[name] = value
    end
    for _, key in ipairs(KEYS) do
        local want = palette[mode][key]
        if not have[key] then
            print(string.format("%s: --%s isn't set; tide's is %s", mode, key, want))
            failed = true
        elseif norm(have[key]) ~= norm(want) then
            print(string.format("%s: --%s is %s; tide's is %s", mode, key, have[key], want))
            failed = true
        end
    end
end
if failed then
    os.exit(1)
end
print("settings colors match tide's palette")
