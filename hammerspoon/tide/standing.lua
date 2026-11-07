-- The standing workspaces, home's apps and each workspace's own settings
-- from tide's files (SPEC.md §6.1, §6.2, §15): `standing`, `inApps` and
-- `workspaceSettings` in workspaces.json and workspaces.local.json, checked
-- as tide checks them (tide SPEC.md §6.5, §16). The .local file's of each
-- replaces the shared one's whole. Pure Lua: reading and JSON come from the
-- caller.

local names = require("tide.names")

local M = {}

M.FILE = "workspaces.json"
M.LOCAL_FILE = "workspaces.local.json"
-- tide's longest name, in characters.
M.MAX_NAME = 32

-- Each setting tide reads, by its key in the files.
M.KEYS = { "standing", "inApps", "workspaceSettings" }

-- Whether `v` decoded from a JSON array: keys 1 to n and nothing else.
local function is_list(v)
    if type(v) ~= "table" then
        return false
    end
    local n = 0
    for k in pairs(v) do
        if math.type(k) ~= "integer" or k < 1 then
            return false
        end
        n = n + 1
    end
    return n == #v
end

-- `name` folded for comparing ignoring case, as the workspaces are (wm.lua).
-- As the window manager compares names: spaces collapsed, case ignored, so
-- a list it would refuse as naming one twice is refused here, at load.
local function fold(name)
    local wm = require("tide.wm")
    return wm.fold(wm.clean_name(name) or name)
end

local function quoted(v)
    return string.format("%q", tostring(v))
end

-- What's wrong with `v` as a workspace's name, or nil: said after the name,
-- as tide says it.
local function name_problem(v)
    if not v:find("%S") then
        return ": a workspace needs a name"
    elseif v:find("[\n\r]") then
        return ": a workspace's name is one line"
    elseif names.unsafe(v) then
        return ": a workspace's name can't have quotes, backslashes, @ or control characters"
    elseif (utf8.len(v) or #v) > M.MAX_NAME then
        return string.format(": a workspace's name is at most %d characters", M.MAX_NAME)
    elseif v:match("^%s") or v:match("%s$") then
        return " has space around it"
    end
    return nil
end

local problem

-- Whether `v` decoded from a JSON object. A decoder can't tell `{}` from
-- `[]`, so an empty table is either.
local function is_object(v)
    return type(v) == "table" and (next(v) == nil or not is_list(v))
end

-- Why `value`, read as workspaceSettings (`key`, start()'s
-- `workspace_settings` for one set there), can't be taken, or nil, as tide's
-- workspaceSettingsError says it: an object whose keys are workspaces'
-- names, each once ignoring case, and whose values set only askForName,
-- true or false, and pinnedApps, a list of text.
function M.settings_problem(value, key)
    key = key or "workspaceSettings"
    if not is_object(value) then
        return key .. " must be an object, each key a workspace's name"
    end
    local keys = {}
    for k in pairs(value) do
        if type(k) ~= "string" then
            return key .. " must be an object, each key a workspace's name"
        end
        keys[#keys + 1] = k
    end
    -- In one order, so the same file always says the same.
    table.sort(keys)
    local seen = {}
    for _, name in ipairs(keys) do
        local named = key .. ": " .. quoted(name)
        local why = name_problem(name)
        if why then
            return named .. why
        end
        local f = fold(name)
        if seen[f] then
            return key .. " names " .. quoted(seen[f]) .. " twice"
        end
        seen[f] = name
        local v = value[name]
        if not is_object(v) then
            return named .. " must be an object, with askForName or pinnedApps"
        end
        for field in pairs(v) do
            if field ~= "askForName" and field ~= "pinnedApps" then
                return named .. ": " .. tostring(field) .. " isn't a setting (askForName or pinnedApps)"
            end
        end
        if v.askForName ~= nil and type(v.askForName) ~= "boolean" then
            return named .. ": askForName must be true or false, not "
                .. (type(v.askForName) == "string" and quoted(v.askForName) or tostring(v.askForName))
        end
        if v.pinnedApps ~= nil then
            why = problem(named .. ": pinnedApps", v.pinnedApps)
            if why then
                return why
            end
        end
    end
    return nil
end

-- Each workspace's settings in effect (tide SPEC.md §6.5): `all`, as a file
-- or start() set them, or, with neither setting any, home's asking for a
-- name and nothing pinned, `home` being the home workspace's name.
function M.settings_of(all, home)
    if all == nil then
        return { [home] = { askForName = true } }
    end
    return all
end

-- One workspace's settings, { askForName, pinnedApps }, as tide's
-- workspaceSetting has them: its entry's, the name matched ignoring case. A
-- workspace with no entry, or a field the entry doesn't set, doesn't ask
-- and pins nothing.
function M.setting(all, home, name)
    local want = name and fold(name)
    for k, v in pairs(M.settings_of(all, home)) do
        if want and fold(k) == want then
            return { askForName = v.askForName == true, pinnedApps = v.pinnedApps or {} }
        end
    end
    return { askForName = false, pinnedApps = {} }
end

-- `all`, workspaceSettings, as JSON for the settings page: an object even
-- when empty, and each pinnedApps a list, which an encoder can't tell from
-- an empty object. `quote` makes a JSON string (mute.quote).
function M.encode_settings(all, quote)
    local keys = {}
    for k in pairs(all) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v, fields = all[k], {}
        if v.askForName ~= nil then
            fields[#fields + 1] = '"askForName": ' .. tostring(v.askForName == true)
        end
        if v.pinnedApps ~= nil then
            local apps = {}
            for i, a in ipairs(v.pinnedApps) do
                apps[i] = quote(a)
            end
            fields[#fields + 1] = '"pinnedApps": [' .. table.concat(apps, ", ") .. "]"
        end
        out[#out + 1] = quote(k) .. ": {" .. table.concat(fields, ", ") .. "}"
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

-- Why `list`, read as `key`, can't be taken, or nil.
function problem(key, list)
    if key == "workspaceSettings" then
        return M.settings_problem(list)
    end
    if not is_list(list) then
        return key .. " must be a list"
    end
    for i, v in ipairs(list) do
        if type(v) ~= "string" or not v:find("%S") then
            return string.format("%s must list text, not %s at %d", key, type(v) == "string" and quoted(v) or tostring(v), i)
        end
    end
    if key ~= "standing" then
        return nil
    end
    if #list == 0 then
        return "standing must name at least one workspace, the first being home"
    end
    local seen = {}
    for _, v in ipairs(list) do
        local why = name_problem(v)
        if why then
            return "standing: " .. quoted(v) .. why
        end
        local f = fold(v)
        if seen[f] then
            return "standing names " .. quoted(v) .. " twice"
        end
        seen[f] = true
    end
    return nil
end

-- The settings tide's files set: { standing = list or nil, inApps = list or
-- nil, workspaceSettings = table or nil, from = { key = file } }, each the
-- .local file's if it sets it, else
-- the shared one's. A key neither sets is nil, for the caller's fallback.
-- Returns nil and the errors, each naming the file and the setting, for a
-- file that can't be read as settings or a list that isn't one tide would
-- take. `read(path)` gives a file's text or nil; `decode(text)` a table or
-- nil.
function M.load(dir, read, decode)
    local out, errors = { from = {} }, {}
    for _, name in ipairs({ M.LOCAL_FILE, M.FILE }) do
        local text = read(dir .. "/" .. name)
        if text then
            local v = decode(text)
            if type(v) ~= "table" or (next(v) ~= nil and is_list(v)) then
                errors[#errors + 1] = name .. ": not a JSON object"
            else
                for _, key in ipairs(M.KEYS) do
                    -- Each file is checked whole, as tide checks it, even
                    -- where the .local file's list takes the place of its.
                    if v[key] ~= nil then
                        local why = problem(key, v[key])
                        if why then
                            errors[#errors + 1] = name .. ": " .. why
                        elseif out[key] == nil then
                            out[key] = v[key]
                            out.from[key] = name
                        end
                    end
                end
            end
        end
    end
    if #errors > 0 then
        return nil, errors
    end
    return out, {}
end

-- An app's name as home's apps compare it: ignoring case, and with spaces,
-- hyphens and underscores alike, so tide's `google-calendar` names the Mac's
-- Google Calendar app too.
function M.app_key(name)
    local s = fold(tostring(name or "")):gsub("[%s_%-]+", "-")
    return (s:gsub("^%-", ""):gsub("%-$", ""))
end

-- Whether an `inApps` entry is a web address, which tide starts as a Chrome
-- --app window and tide can't tell from a browser's (SPEC.md §6.2).
function M.is_url(entry)
    return tostring(entry or ""):match("^[Hh][Tt][Tt][Pp][Ss]?://") ~= nil
end

-- The names an `inApps` entry may have as a Mac app's bundle, to look for at
-- login: as written, and with hyphens as spaces. None for a web address.
function M.app_candidates(entry)
    entry = tostring(entry or ""):match("^%s*(.-)%s*$")
    if entry == "" or M.is_url(entry) or entry:find("/") then
        return {}
    end
    local out = { entry }
    local spaced = entry:gsub("[_%-]+", " ")
    if spaced ~= entry then
        out[2] = spaced
    end
    return out
end

-- Where a Mac app's bundle may be, for `home` the home folder: the
-- system's and your Applications folders, and Chrome's installed web apps'.
function M.app_folders(home)
    return {
        "/Applications",
        "/System/Applications",
        home .. "/Applications",
        home .. "/Applications/Chrome Apps.localized",
    }
end

-- Each path an `inApps` entry's app may be at, in the order to try them.
function M.app_paths(entry, home)
    local out = {}
    for _, name in ipairs(M.app_candidates(entry)) do
        for _, dir in ipairs(M.app_folders(home)) do
            out[#out + 1] = dir .. "/" .. name .. ".app"
        end
    end
    return out
end

return M
