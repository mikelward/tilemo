-- The bar's chip colors (dashboard/bar.html's --chip-* properties) against
-- tide's palette (its theme/palette.json), light and dark, so the chips look
-- as tide's do. Run by `make check-tide`:
--
--   lua ci/check_chip_colors.lua TIDE/theme/palette.json hammerspoon/tide/dashboard/bar.html

local json = require("json")

-- Each --chip-* property, and the palette color it stands for.
local KEYS = {
    ["chip-surface"] = "surface",
    ["chip-current"] = "accent-bg",
    ["chip-on-current"] = "accent-fg",
    ["chip-faint"] = "fg-faint",
    ["chip-ring"] = "accent",
    ["chip-urgent"] = "urgent",
    ["chip-urgent-bg"] = "urgent-bg",
    ["chip-urgent-ring"] = "urgent-ring",
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

-- The --chip-* properties set in `block`.
local function props(block)
    local out = {}
    for name, value in block:gmatch("%-%-(chip%-[%w-]+):%s*([^;]+);") do
        out[name] = value
    end
    return out
end

local palette = json.decode(read(arg[1]))
local html = read(arg[2])
local light = html:match(":root%s*(%b{})")
local dark = html:match("@media %(prefers%-color%-scheme: dark%)%s*{%s*:root%s*(%b{})")
assert(light and dark, "no chip colors in " .. arg[2])

local failed = false
for mode, block in pairs({ light = light, dark = dark }) do
    local have = props(block)
    for prop, key in pairs(KEYS) do
        local want = palette[mode][key]
        if not have[prop] then
            print(string.format("%s: --%s isn't set; tide's %s is %s", mode, prop, key, want))
            failed = true
        elseif norm(have[prop]) ~= norm(want) then
            print(string.format("%s: --%s is %s; tide's %s is %s", mode, prop, have[prop], key, want))
            failed = true
        end
    end
end
if failed then
    os.exit(1)
end
print("chip colors match tide's palette")
