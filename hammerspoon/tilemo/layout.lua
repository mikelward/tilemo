-- Per-workspace layout state (SPEC.md §5): the window order, the mode and
-- each mode's mfact and master count. Pure Lua, so it tests without
-- Hammerspoon. The geometry itself is tide's, unchanged (geometry.lua).

local geometry = require("tilemo.geometry")

local M = { geometry = geometry }

-- tide's defaults (tide hypr/tide/layout.lua), so a workspace looks the same
-- on every desktop.
M.defaults = {
    ultrawide_aspect = 2.1,
    default_mode = { normal = "tile", ultrawide = "threecol" },
    single = {
        { min_aspect = 2.1, width = 0.8 },
        { min_aspect = 3.2, width = 0.6 },
    },
    modes = {
        tile = { mfact = 0.55, nmaster = 1 },
        threecol = { mfact = 0.5, nmaster = 1 },
        twocol = { mfact = 0.72, nmaster = 2 },
        monocle = {},
    },
    cycle = { "tile", "threecol", "twocol" },
    -- "end" of the stack, "top" of it, "next" after the focused window, or
    -- "master".
    new_window = "end",
    mfact_step = 0.025,
}

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = copy(v)
    end
    return out
end
M.copy = copy

local function index_of(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
end
M.index_of = index_of

-- A new workspace, in the default mode for its area's shape.
function M.new(id, area, config)
    config = config or M.defaults
    local aspect = area and area.h > 0 and area.w / area.h or 0
    local mode = aspect >= config.ultrawide_aspect and config.default_mode.ultrawide
        or config.default_mode.normal
    return { id = id, mode = mode, opts = copy(config.modes), order = {} }
end

-- Put `wid` into the order where config.new_window says. `focused` is the
-- window that had focus, for "next".
function M.insert(ws, wid, focused, config)
    config = config or M.defaults
    if index_of(ws.order, wid) then
        return
    end
    local where = config.new_window
    local nmaster = (ws.opts[ws.mode] or {}).nmaster or 1
    local pos = #ws.order + 1
    if where == "master" then
        pos = 1
    elseif where == "top" then
        pos = math.min(nmaster + 1, #ws.order + 1)
    elseif where == "next" then
        local i = focused and index_of(ws.order, focused)
        if i then
            pos = i + 1
        end
    end
    table.insert(ws.order, pos, wid)
end

function M.remove(ws, wid)
    local i = index_of(ws.order, wid)
    if i then
        table.remove(ws.order, i)
    end
end

-- The window `delta` places from `wid` in `ids`, wrapping round. `ids` is
-- the order filtered to what's visible.
function M.neighbor(ids, wid, delta)
    local n = #ids
    if n == 0 then
        return nil
    end
    local i = index_of(ids, wid)
    if not i then
        return ids[1]
    end
    return ids[(i - 1 + delta) % n + 1]
end

local function swap(list, a, b)
    local i, j = index_of(list, a), index_of(list, b)
    if i and j then
        list[i], list[j] = list[j], list[i]
    end
end

-- Swap `wid` with its neighbor `delta` places along `ids`.
function M.move(ws, ids, wid, delta)
    local other = M.neighbor(ids, wid, delta)
    if other and other ~= wid then
        swap(ws.order, wid, other)
    end
end

-- Alt+Tab (tide's, SPEC.md §7.2): any other window swaps with the master,
-- which the workspace remembers; the master swaps with the window that was
-- master before it, or with the next window, as dwm's zoom, if that one's
-- gone.
function M.swap_master(ws, ids, wid)
    if #ids < 2 or not index_of(ids, wid) then
        return
    end
    local other, displaced
    if ids[1] == wid then
        local prev = ws.prev_master
        other = prev ~= wid and index_of(ids, prev) and prev or ids[2]
        displaced = wid
    else
        other = ids[1]
        displaced = other
    end
    ws.prev_master = displaced
    swap(ws.order, wid, other)
end

function M.mfact(ws, delta)
    local o = ws.opts[ws.mode]
    if o and o.mfact then
        o.mfact = geometry.clamp(o.mfact + delta, 0.1, 0.9)
    end
end

function M.nmaster(ws, delta)
    local o = ws.opts[ws.mode]
    if o and o.nmaster then
        o.nmaster = math.max(1, o.nmaster + delta)
    end
end

-- Step through config.cycle; from monocle, step from the mode before it.
function M.cycle(ws, delta, config)
    config = config or M.defaults
    local list = config.cycle
    local from = ws.mode == "monocle" and (ws.prev_mode or list[1]) or ws.mode
    local i = index_of(list, from) or 1
    ws.prev_mode = nil
    ws.mode = list[(i - 1 + delta) % #list + 1]
end

function M.toggle_monocle(ws)
    if ws.mode == "monocle" then
        ws.mode = ws.prev_mode or M.defaults.default_mode.normal
        ws.prev_mode = nil
    else
        ws.prev_mode = ws.mode
        ws.mode = "monocle"
    end
end

-- Boxes for `ids` (the tiled, visible windows in order) in `area`, keyed by
-- window id.
function M.arrange(ws, area, ids, config)
    config = config or M.defaults
    -- A width you dragged a lone window to on this workspace beats the
    -- single-window rule.
    local single = config.single
    if ws.single_width then
        single = { { min_aspect = 0, width = ws.single_width } }
    end
    local boxes = geometry.arrange(ws.mode, area, #ids, ws.opts[ws.mode], single)
    local out = {}
    for i, wid in ipairs(ids) do
        out[wid] = boxes[i]
    end
    return out
end

-- tide's layouts files (tide SPEC.md §16), in its settings folder: the
-- shared one, then this machine's, whose settings win.
M.FILES = { "layouts.json", "layouts.local.json" }
M.LOCAL_FILE = "layouts.local.json"

-- The modes a workspace can start in, and the fewest masters each mode
-- with a master takes: tide's shell/lib/layouts.mjs, whose checks these are.
local START_MODES = { tile = true, threecol = true, twocol = true, monocle = true }
local MIN_MASTERS = { tile = 0, threecol = 1, twocol = 1 }
local NEW_WINDOW = { ["end"] = true, top = true, next = true, master = true }

local function is_list(v)
    if type(v) ~= "table" then
        return false
    end
    local n = 0
    for _ in pairs(v) do
        n = n + 1
    end
    return n == #v
end

-- An object: a table with only string keys. An empty table passes as both,
-- as JSON's {} and [] decode alike.
local function is_object(v)
    if type(v) ~= "table" then
        return false
    end
    for k in pairs(v) do
        if type(k) ~= "string" then
            return false
        end
    end
    return true
end

local function number_error(path, v, lo, hi, whole)
    if type(v) ~= "number" or not (v >= lo and v <= hi) or (whole and v % 1 ~= 0) then
        return string.format("%s must be %s from %s to %s", path, whole and "a whole number" or "a number", lo, hi)
    end
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    return keys
end

-- What's wrong with one file's settings, as layouts.mjs's settingsError
-- words it, or nil.
local function settings_error(v)
    for _, key in ipairs(sorted_keys(v)) do
        local x = v[key]
        local err
        if key == "ultrawideAspect" then
            err = number_error(key, x, 0.1, 100)
        elseif key == "defaultMode" then
            if not is_object(x) then
                err = "defaultMode must be an object of normal and ultrawide"
            else
                for _, k in ipairs(sorted_keys(x)) do
                    if k ~= "normal" and k ~= "ultrawide" then
                        err = err or ("defaultMode." .. k .. " is not a setting")
                    elseif not START_MODES[x[k]] then
                        err = err or ("defaultMode." .. k .. " must be one of tile, threecol, twocol, monocle")
                    end
                end
            end
        elseif key == "modes" then
            if not is_object(x) then
                err = "modes must be an object of tile, threecol and twocol"
            else
                for _, mode in ipairs(sorted_keys(x)) do
                    local m = x[mode]
                    if MIN_MASTERS[mode] == nil then
                        err = err or ("modes." .. mode .. " is not a setting")
                    elseif not is_object(m) then
                        err = err or ("modes." .. mode .. " must be an object of mfact and nmaster")
                    else
                        for _, k in ipairs(sorted_keys(m)) do
                            if k == "mfact" then
                                err = err or number_error("modes." .. mode .. ".mfact", m[k], 0.1, 0.9)
                            elseif k == "nmaster" then
                                err = err or number_error("modes." .. mode .. ".nmaster", m[k], MIN_MASTERS[mode], 100, true)
                            else
                                err = err or ("modes." .. mode .. "." .. k .. " is not a setting")
                            end
                        end
                    end
                end
            end
        elseif key == "newWindow" then
            if not NEW_WINDOW[x] then
                err = "newWindow must be one of end, top, next, master"
            end
        elseif key == "single" then
            if not is_list(x) then
                err = "single must be a list of {minAspect, width}"
            else
                for i, rule in ipairs(x) do
                    local at = "single entry " .. i
                    if not is_object(rule) then
                        err = err or (at .. " must be {minAspect, width}")
                    else
                        for _, k in ipairs(sorted_keys(rule)) do
                            if k ~= "minAspect" and k ~= "width" then
                                err = err or (at .. ": " .. k .. " is not a setting")
                            end
                        end
                        err = err or number_error(at .. ": minAspect", rule.minAspect, 0, 100)
                        err = err or number_error(at .. ": width", rule.width, 0.1, 1)
                    end
                end
            end
        else
            err = 'unknown setting "' .. key .. '"'
        end
        if err then
            return err
        end
    end
end

-- One file's settings laid over `config`, in tilemo's names: objects key by
-- key, lists whole, as tide merges them (tide SPEC.md §16.1).
local function apply(config, v)
    if v.ultrawideAspect ~= nil then
        config.ultrawide_aspect = v.ultrawideAspect
    end
    for _, k in ipairs({ "normal", "ultrawide" }) do
        if v.defaultMode and v.defaultMode[k] ~= nil then
            config.default_mode[k] = v.defaultMode[k]
        end
    end
    for mode, m in pairs(v.modes or {}) do
        config.modes[mode] = config.modes[mode] or {}
        if m.mfact ~= nil then
            config.modes[mode].mfact = m.mfact
        end
        if m.nmaster ~= nil then
            config.modes[mode].nmaster = math.tointeger(m.nmaster) or m.nmaster
        end
    end
    if v.single ~= nil then
        config.single = {}
        for i, rule in ipairs(v.single) do
            config.single[i] = { min_aspect = rule.minAspect, width = rule.width }
        end
    end
    if v.newWindow ~= nil then
        config.new_window = v.newWindow
    end
end

-- The layout settings in effect and the errors to say: tide's layouts files
-- laid over `base` (M.defaults if nil), the local file's over the shared
-- one's. A file that's wrong keeps `last` (`base` if none), as tide does,
-- and an error names the file and why. `read(path)` gives a file's text or
-- nil; `decode(text)` its value, or nil if it doesn't parse.
function M.load_settings(dir, read, decode, base, last)
    base = base or M.defaults
    local config = copy(base)
    local errors = {}
    for _, name in ipairs(M.FILES) do
        local text = read(dir .. "/" .. name)
        if text then
            local ok, v = pcall(decode, text)
            local why
            if not ok or v == nil then
                why = "doesn't parse"
            elseif not is_object(v) or not text:match("^%s*{") then
                why = "expected an object of settings"
            else
                why = settings_error(v)
            end
            if why then
                errors[#errors + 1] = name .. ": " .. why
            else
                apply(config, v)
            end
        end
    end
    if #errors > 0 then
        return last or copy(base), errors
    end
    return config, errors
end

-- What of `config` tide's layouts files can set, in their names, for the
-- settings page to show the files over: a `start()` layout that isn't
-- tide's defaults is what the files lay over here, not tide's defaults.
function M.file_form(config)
    local modes = {}
    for _, mode in ipairs({ "tile", "threecol", "twocol" }) do
        local m = config.modes and config.modes[mode]
        if m then
            modes[mode] = { mfact = m.mfact, nmaster = m.nmaster }
        end
    end
    local single = {}
    for i, rule in ipairs(config.single or {}) do
        single[i] = { minAspect = rule.min_aspect, width = rule.width }
    end
    return {
        ultrawideAspect = config.ultrawide_aspect,
        defaultMode = copy(config.default_mode),
        modes = modes,
        single = single,
        newWindow = config.new_window,
    }
end

-- Settings `config` take effect on workspace `ws`, as tide's reload does
-- (tide SPEC.md §16): it keeps its mode, and takes the new mfact and
-- master count, losing any it was given with the keys.
function M.reconfigure(ws, config)
    ws.opts = copy(config.modes)
end

return M
