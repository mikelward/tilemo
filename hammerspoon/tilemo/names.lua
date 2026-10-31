-- Workspace names from window titles, and TIDE_WORKSPACE (SPEC.md §6.2,
-- §6.3). Pure Lua: the patterns are JavaScript regular expressions, run by
-- whatever `run_js(source)` the caller passes (JavaScriptCore through
-- hs.osascript.javascript on a Mac, node in the tests), which returns
-- ok, result.

local M = {}

-- tide's settings file and key, so one list names workspaces on both
-- desktops (tide SPEC.md §6.5, §16.1). The .local file beside it, if it
-- sets namePatterns, takes its place on this machine.
M.FILE = "workspaces.json"
M.LOCAL_FILE = "workspaces.local.json"
M.KEY = "namePatterns"

-- A default from the title alone is cut to this many characters at a word
-- boundary (SPEC.md §6.2, a guess to confirm).
M.FALLBACK_MAX = 20

-- TIDE_WORKSPACE's value: the name with only ASCII letters and digits kept.
function M.sanitize(name)
    return (tostring(name or ""):gsub("[^A-Za-z0-9]", ""))
end

local function trim(s)
    return (s:gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- Whether `s` ends with `suffix`.
local function ends(s, suffix)
    return suffix ~= "" and #s > #suffix and s:sub(-#suffix) == suffix
end

-- The title with the app's name stripped from its end (" - Google Chrome",
-- " — Mozilla Firefox"), cut to M.FALLBACK_MAX characters at a word
-- boundary, or the app's name with no title.
function M.fallback(title, app)
    title = trim(title or "")
    app = app or ""
    if app ~= "" then
        for _, dash in ipairs({ " - ", " — ", " – " }) do
            if ends(title, dash .. app) then
                title = trim(title:sub(1, #title - #dash - #app))
                break
            end
        end
    end
    if title == "" then
        return app
    end
    local len = utf8.len(title)
    if not len or len <= M.FALLBACK_MAX then
        return title
    end
    local cut = title:sub(1, utf8.offset(title, M.FALLBACK_MAX + 1) - 1)
    if title:sub(#cut + 1, #cut + 1) == " " then
        return trim(cut)
    end
    -- Back to the last word boundary, unless the first word alone is too
    -- long.
    return trim(cut:match("^(.*%S)%s") or cut)
end

-- `s` as a JavaScript string literal.
function M.js_string(s)
    s = tostring(s)
    s = s:gsub('[%c"\\]', function(c)
        if c == '"' then
            return '\\"'
        elseif c == "\\" then
            return "\\\\"
        end
        return string.format("\\u%04x", c:byte())
    end)
    -- U+2028 and U+2029 end a line in older JavaScript.
    s = s:gsub("\226\128\168", "\\u2028"):gsub("\226\128\169", "\\u2029")
    return '"' .. s .. '"'
end

local function js_array(list)
    local parts = {}
    for i, s in ipairs(list) do
        parts[i] = M.js_string(s)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- JavaScript giving the first non-empty first capture of `patterns` in
-- `title`, tried in order, or "".
function M.match_script(patterns, title)
    return "(function(){var ps=" .. js_array(patterns) .. ",t=" .. M.js_string(title)
        .. ";for(var i=0;i<ps.length;i++){var m=new RegExp(ps[i]).exec(t);"
        .. "if(m&&m[1])return String(m[1]);}return \"\";})()"
end

-- JavaScript giving a JSON list of what's wrong with `patterns`: each one
-- that doesn't compile, or has no capture group to give a name.
function M.check_script(patterns)
    return "(function(){var ps=" .. js_array(patterns) .. ",bad=[];"
        .. "for(var i=0;i<ps.length;i++){try{var g=new RegExp(ps[i]+\"|\").exec(\"\").length-1;"
        .. "if(g<1)bad.push(\"namePatterns[\"+(i+1)+\"] \"+JSON.stringify(ps[i])+\" has no capture group\");}"
        .. "catch(e){bad.push(\"namePatterns[\"+(i+1)+\"] \"+JSON.stringify(ps[i])+\": \"+e.message);}}"
        .. "return JSON.stringify(bad);})()"
end

-- The patterns tide's files set: the .local file's if it sets them, else
-- the shared one's, else none. Returns the list and the file it came from,
-- or nil and what's wrong. `read(path)` gives a file's text or nil, and
-- `decode(text)` a table or nil.
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
                if type(list) ~= "table" then
                    return nil, name .. ": " .. M.KEY .. " must be a list of patterns"
                end
                for i = 1, #list do
                    if type(list[i]) ~= "string" then
                        return nil, string.format("%s: %s[%d] must be a string", name, M.KEY, i)
                    end
                end
                return list, name
            end
        end
    end
    return {}, nil
end

-- Read and check the patterns: a bad one is an error at load, naming the
-- file and the pattern. Returns the list, or nil and the error.
function M.load(dir, read, decode, run_js)
    local list, file = M.read(dir, read, decode)
    if not list then
        return nil, file
    end
    if #list == 0 then
        return list
    end
    local ok, result = run_js(M.check_script(list))
    if not ok then
        return nil, (file or M.FILE) .. ": couldn't check " .. M.KEY .. ": " .. tostring(result)
    end
    local bad = decode(result)
    if type(bad) ~= "table" then
        return nil, (file or M.FILE) .. ": couldn't check " .. M.KEY .. ": " .. tostring(result)
    end
    if #bad > 0 then
        return nil, file .. ": " .. table.concat(bad, "; ")
    end
    return list
end

-- The default name for a window titled `title` of app `app`: the first
-- pattern's capture, else M.fallback. A pattern run that fails falls back
-- too, with `log` told why.
function M.default_name(title, app, patterns, run_js, log)
    title = title or ""
    if title ~= "" and patterns and #patterns > 0 then
        local ok, result = run_js(M.match_script(patterns, title))
        if ok and type(result) == "string" and result ~= "" then
            local name = trim(result)
            if name ~= "" then
                return name
            end
        elseif not ok and log then
            log("name patterns: " .. tostring(result))
        end
    end
    return M.fallback(title, app)
end

return M
