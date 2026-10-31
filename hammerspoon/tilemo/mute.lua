-- Mute: the apps and sites that never want attention (SPEC.md §14.2, §15),
-- tide's `muted`, in workspaces.json and workspaces.local.json, each entry
-- a bundle id or "site:<host>". Pure Lua: reading, writing and JSON come
-- from the caller.

local M = {}

M.KEY = "muted"
M.FILE = "workspaces.json"
M.LOCAL_FILE = "workspaces.local.json"
M.SITE = "site:"

-- An empty list: nothing is muted.
function M.empty()
    return { apps = {}, sites = {}, list = {} }
end

-- A URL's host, lowercased, or nil.
function M.host(url)
    local h = (url or ""):match("^%a[%w+.-]*://([^/?#]+)")
    if not h then
        return nil
    end
    -- No user info or port: the site is the host.
    h = h:gsub("^.*@", ""):gsub(":%d*$", "")
    return h ~= "" and h:lower() or nil
end

-- Why entry `v` is malformed, or nil if it's good.
local function problem(v)
    if type(v) ~= "string" then
        return "is not a string"
    elseif v == "" then
        return "is empty"
    elseif v:find("%s") then
        return "has a space in it"
    end
    if v:sub(1, #M.SITE) == M.SITE then
        local h = v:sub(#M.SITE + 1)
        if h == "" then
            return "names no host"
        elseif not h:match("^[%w.-]+$") then
            return "has more than a host after site: (a scheme, a path or a port)"
        end
    end
end

local function show(v)
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

-- The set from a list of entries, and an error for each malformed one,
-- naming `file` and the entry; the rest still count.
function M.parse(list, file)
    local set, errors = M.empty(), {}
    for i, v in ipairs(list) do
        local why = problem(v)
        if why then
            errors[#errors + 1] = string.format("%s: %s[%d] %s %s", file, M.KEY, i, show(v), why)
        elseif v:sub(1, #M.SITE) == M.SITE then
            set.sites[v:sub(#M.SITE + 1):lower()] = true
            set.list[#set.list + 1] = v
        else
            set.apps[v] = true
            set.list[#set.list + 1] = v
        end
    end
    return set, errors
end

-- Whether `v` decoded from a JSON array: keys 1 to n and nothing else. A
-- JSON object decodes to a table too, and ipairs would see none of it.
function M.is_list(v)
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

-- The list in effect, as tide reads it (tide §16.1): the .local file's if
-- it sets one, which replaces the shared list whole, else the shared
-- file's, else none. Returns the raw list and the file it's from, or nil
-- and an error for a file that can't be read as an object.
function M.read(dir, read, decode)
    for _, name in ipairs({ M.LOCAL_FILE, M.FILE }) do
        local text = read(dir .. "/" .. name)
        if text then
            local v = decode(text)
            if type(v) ~= "table" then
                return nil, name .. ": not a JSON object"
            end
            local list = v[M.KEY]
            if list ~= nil then
                if not M.is_list(list) then
                    return nil, name .. ": " .. M.KEY .. " must be a list"
                end
                return list, name
            end
        end
    end
    return {}, nil
end

-- The set to use, and the errors to report: a malformed entry is left
-- out, with an error naming it. A file that can't be read, or whose list
-- isn't one, gives no set and one error, and the caller keeps the last
-- good set.
function M.load(dir, read, decode)
    local list, file = M.read(dir, read, decode)
    if not list then
        return nil, { file }
    end
    return M.parse(list, file or M.FILE)
end

-- Whether a mark for `app`'s window, whose browser front tab is on `host`
-- if it's a browser window, is muted. A host matches exactly, ignoring
-- case.
function M.matches(set, app, host)
    if not set then
        return false
    end
    if app and set.apps[app] then
        return true
    end
    return host ~= nil and set.sites[host:lower()] == true
end

-- The entry a switcher row mutes: a tab's site, or a window's app.
function M.entry_for(item)
    if item.kind == "tab" then
        local h = M.host(item.url)
        return h and (M.SITE .. h) or nil
    elseif item.kind == "window" or item.kind == "attention" then
        return item.bundle
    end
end

-- Mark each switcher row whose app or site is muted, for its "muted"
-- (SPEC.md §14.2).
function M.mark_rows(items, set)
    for _, item in ipairs(items) do
        local entry = M.entry_for(item)
        if entry then
            item.muted = M.has(set, entry)
        end
    end
    return items
end

-- System Settings' Notifications pane, which the notice after a mute offers,
-- since tilemo can't hold back macOS's banners *(unverified on macOS 26)*.
M.NOTIFICATIONS_URL = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

-- What the notice after Cmd+M says: `name` is the app's name or the site.
function M.notice(name, now)
    if now then
        return "Muted " .. name .. ": it won't be marked for attention. macOS still shows its banners;"
            .. " click to turn them off in Notifications settings."
    end
    return "Unmuted " .. name .. ": it can be marked for attention again."
end

-- Whether `entry` is in `set`.
function M.has(set, entry)
    if not entry or not set then
        return false
    end
    if entry:sub(1, #M.SITE) == M.SITE then
        return set.sites[entry:sub(#M.SITE + 1):lower()] == true
    end
    return set.apps[entry] == true
end

-- Why `entry`, typed in the settings window, can't be muted, or nil: as
-- tide's Notifications page refuses one the list wouldn't take back on
-- loading, or one muted already.
function M.add_problem(set, entry)
    if entry == "" then
        return "type an app's bundle id, or site: and a host"
    end
    local why = problem(entry)
    if why then
        return show(entry) .. " " .. why
    end
    if M.has(set, entry) then
        local name = entry:sub(1, #M.SITE) == M.SITE and entry:sub(#M.SITE + 1):lower() or entry
        return name .. " is muted already"
    end
end

-- Whether two good entries name the same app or site.
local function same(a, b)
    local sa, sb = a:sub(1, #M.SITE) == M.SITE, b:sub(1, #M.SITE) == M.SITE
    if sa ~= sb then
        return false
    end
    return sa and a:lower() == b:lower() or a == b
end

-- A JSON string.
local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
        return named[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- A list of strings as JSON, so an empty one is [] rather than whatever an
-- encoder makes of an empty table.
function M.encode_list(list)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = quote(v)
    end
    return "[" .. table.concat(out, ", ") .. "]"
end

local PLACEHOLDER = "__tilemo_muted__"

-- Mute `entry`, adding it to the list in effect, or unmute it if it's
-- there, and write the result to the .local file: read just before, every
-- other key kept, written whole by `write(path, text)` (atomic.write's
-- way). Returns whether it's now muted, or nil and an error, writing
-- nothing.
function M.toggle(dir, entry, read, decode, encode, write)
    if problem(entry) then
        return nil, "can't mute " .. show(entry) .. ": " .. problem(entry)
    end
    local list, err = M.read(dir, read, decode)
    if not list then
        return nil, err
    end
    local path = dir .. "/" .. M.LOCAL_FILE
    local obj = {}
    local text = read(path)
    if text then
        obj = decode(text)
        if type(obj) ~= "table" then
            return nil, M.LOCAL_FILE .. ": not a JSON object"
        end
    end
    local set = M.parse(list, M.FILE)
    local now = not M.has(set, entry)
    local out = {}
    for _, v in ipairs(list) do
        -- A malformed string stays for its owner to fix; something that
        -- isn't a string can't be written back as one, so it goes.
        if type(v) == "string" and (problem(v) or not same(v, entry)) then
            out[#out + 1] = v
        end
    end
    if now then
        out[#out + 1] = entry
    end
    obj[M.KEY] = PLACEHOLDER
    local json = encode(obj)
    local at = json and json:find('"' .. PLACEHOLDER .. '"', 1, true)
    if not at then
        return nil, "couldn't write " .. M.LOCAL_FILE .. ": the JSON encoder failed"
    end
    json = json:sub(1, at - 1) .. M.encode_list(out) .. json:sub(at + #PLACEHOLDER + 2)
    local ok, werr = write(path, json .. (json:sub(-1) == "\n" and "" or "\n"))
    if not ok then
        return nil, "couldn't write " .. path .. ": " .. tostring(werr)
    end
    return now
end

return M
