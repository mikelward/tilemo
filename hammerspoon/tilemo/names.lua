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

-- A default from the title alone is its first word, cut to this many
-- characters (SPEC.md §6.2).
M.FALLBACK_MAX = 20

-- JavaScript giving `name` as TIDE_WORKSPACE holds it: its letters and
-- digits (Unicode's L and N) in any script, NFC-normalized. Normalizing
-- first makes a decomposed é (e and U+0301, as macOS hands it over) one
-- letter, which is kept where the bare mark would go; normalizing again
-- composes what dropping the rest put side by side.
function M.sanitize_script(name)
    return "(function(){return " .. M.js_string(name)
        .. ".normalize(\"NFC\").replace(/[^\\p{L}\\p{N}]/gu,\"\").normalize(\"NFC\");})()"
end

-- TIDE_WORKSPACE's value (SPEC.md §6.3): the name with only its letters and
-- digits, in any script, NFC-normalized, as on tide. Lua has no Unicode
-- tables, so a name past ASCII goes to `run_js` (JavaScriptCore on a Mac),
-- whose \p{L}, \p{N} and normalize are Unicode's; ASCII alone needs none,
-- since its letters and digits are A-Z, a-z and 0-9, and it's NFC already.
-- Returns the value, or "" and why when the JavaScript can't be run: an
-- empty value names no session, where a guess could name the wrong one.
function M.sanitize(name, run_js)
    name = tostring(name or "")
    if not name:find("[\128-\255]") then
        return (name:gsub("[^A-Za-z0-9]", ""))
    end
    if not run_js then
        return "", "no JavaScript to keep the workspace's letters and digits"
    end
    local ok, result = run_js(M.sanitize_script(name))
    if not ok or type(result) ~= "string" then
        return "", "couldn't keep the workspace's letters and digits: " .. tostring(result)
    end
    return result
end

-- What a workspace's name can't hold, as on tide (tide SPEC.md §6.5):
-- quotes, backslashes and control characters. A name reaches JSON, the
-- bar's web view, logs, and the workspace.name file a script or a shell
-- prompt prints (SPEC.md §6.3); with none of these in it, no quoting can
-- go wrong, and no escape sequence reaches a terminal.
M.UNSAFE = "[%c\"'`\\]"
M.UNSAFE_MESSAGE = "A workspace's name can't have quotes, backslashes or control characters"

-- Whether `name` holds one of M.UNSAFE.
function M.unsafe(name)
    return tostring(name or ""):find(M.UNSAFE) ~= nil
end

-- `name` with M.UNSAFE's characters dropped, for a default made from a
-- window's title.
function M.safe(name)
    return (tostring(name or ""):gsub(M.UNSAFE, ""))
end

local function trim(s)
    return (s:gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- Whether `s` ends with `suffix`.
local function ends(s, suffix)
    return suffix ~= "" and #s > #suffix and s:sub(-#suffix) == suffix
end

-- Punctuation that clings to a word's end, as in "ABC-123:" or "Docs,",
-- dropped from a default's first word as tide drops it (tide SPEC.md
-- §6.5): ASCII's, and the UTF-8 for "…", "–" and "—".
local TRAILING = { "%.", ",", ":", ";", "!", "%?", "|", "%-", "\226\128\166", "\226\128\147", "\226\128\148" }

local function strip_trailing(word)
    repeat
        local before = word
        for _, p in ipairs(TRAILING) do
            word = word:gsub(p .. "$", "")
        end
    until word == before
    return word
end

-- The first word of the title with the app's name stripped from its end
-- (" - Google Chrome", " — Mozilla Firefox") and the punctuation at its
-- own end dropped, cut to M.FALLBACK_MAX characters; or the app's name
-- with no title, or none with a letter or digit. Lua has no Unicode
-- tables, so any character past ASCII counts as one (a lone "—" doesn't,
-- since it's stripped first).
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
    for word in title:gmatch("%S+") do
        word = strip_trailing(word)
        if word:find("[%w\128-\255]") then
            local len = utf8.len(word)
            if len and len > M.FALLBACK_MAX then
                word = word:sub(1, utf8.offset(word, M.FALLBACK_MAX + 1) - 1)
            end
            return word
        end
    end
    return app
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

-- Whether `v` decoded from a JSON array: keys 1 to n and nothing else. A
-- JSON object decodes to a table too, and would read as no patterns.
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
                if not is_list(list) then
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
-- pattern's capture, else M.fallback, with M.UNSAFE's characters dropped,
-- as tide's short names drop them. A pattern run that fails falls back
-- too, with `log` told why.
function M.default_name(title, app, patterns, run_js, log)
    title = title or ""
    if title ~= "" and patterns and #patterns > 0 then
        local ok, result = run_js(M.match_script(patterns, title))
        if ok and type(result) == "string" and result ~= "" then
            local name = trim(M.safe(result))
            if name ~= "" then
                return name
            end
        elseif not ok and log then
            log("name patterns: " .. tostring(result))
        end
    end
    return trim(M.safe(M.fallback(title, app)))
end

return M
