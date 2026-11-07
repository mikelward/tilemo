-- Float rules you make (SPEC.md §5.1, §15), as tide's Floating page makes
-- them (tide SPEC.md §6.4, §16): each names an app by bundle ID and,
-- optionally, a Lua pattern found anywhere in the title. They're in
-- floating-macos.json and floating-macos.local.json in tide's settings
-- folder, `rules`, apart from tide's floating.json, since a bundle ID isn't
-- a Wayland class. Pure Lua: reading, writing and JSON come from the caller.

local rules = require("tide.rules")
local mute = require("tide.mute")

local M = {}

M.KEY = "rules"
M.FILE = "floating-macos.json"
M.LOCAL_FILE = "floating-macos.local.json"
-- As many as tide takes.
M.MAX = 64

local function show(v)
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

-- Why `title`, a rule's pattern, can't be used, or nil.
function M.pattern_problem(title)
    if type(title) ~= "string" then
        return "the title must be text"
    end
    local why = rules.pattern_problem(title)
    if why then
        return "the title isn't a Lua pattern: it " .. why
    end
end

-- Why `app` can't name an app, or nil.
local function app_problem(app)
    if type(app) ~= "string" or app == "" then
        return "names no app"
    elseif app:find("%s") then
        return "has a space in its app"
    end
end

-- Why list entry `v` is wrong, or nil. A title of "" is none.
local function entry_problem(v)
    if type(v) ~= "table" then
        return "is not an object"
    end
    for k in pairs(v) do
        if k ~= "app" and k ~= "title" then
            return "has " .. show(k) .. ", which isn't app or title"
        end
    end
    local why = app_problem(v.app)
    if why then
        return why
    end
    if v.title ~= nil then
        why = M.pattern_problem(v.title)
        if why then
            return why
        end
    end
end

-- A rule's title, "" for none.
local function title_of(r)
    return r.title or ""
end

local function same(a, b)
    return a.app == b.app and title_of(a) == title_of(b)
end

-- How a rule reads in a message: its app, and its title if it has one.
function M.describe(r)
    local t = title_of(r)
    return t == "" and r.app or (r.app .. ", " .. show(t))
end

-- The rules from `list`, read from `file`, as rules.lua's float rules, or
-- nil and an error naming the file and the entry: one bad entry is the
-- whole list's error, as on tide, so the caller keeps the last good rules.
function M.parse(list, file)
    if #list > M.MAX then
        return nil, string.format("%s: %s has %d rules, more than %d", file, M.KEY, #list, M.MAX)
    end
    local out = {}
    for i, v in ipairs(list) do
        local why = entry_problem(v)
        if not why then
            for _, r in ipairs(out) do
                if same(r, v) then
                    why = "is listed already"
                end
            end
        end
        if why then
            return nil, string.format("%s: %s[%d] %s", file, M.KEY, i, why)
        end
        local t = title_of(v)
        out[#out + 1] = { app = v.app, title = t ~= "" and t or nil, action = "float" }
    end
    return out
end

-- The list in effect, as tide reads one (tide §16.1): the .local file's if
-- it sets one, which replaces the shared one whole, else the shared one's,
-- else none. The raw list and the file it's from, or nil and an error.
function M.read(dir, read, decode)
    for _, name in ipairs({ M.LOCAL_FILE, M.FILE }) do
        local text = read(dir .. "/" .. name)
        if text then
            local v = decode(text)
            if type(v) ~= "table" or (next(v) ~= nil and mute.is_list(v)) then
                return nil, name .. ": not a JSON object"
            end
            local list = v[M.KEY]
            if list ~= nil then
                if not mute.is_list(list) then
                    return nil, name .. ": " .. M.KEY .. " must be a list"
                end
                return list, name
            end
        end
    end
    return {}, nil
end

-- The rules to use and the file they're from, or nil and an error.
function M.load(dir, read, decode)
    local list, file = M.read(dir, read, decode)
    if not list then
        return nil, file
    end
    local out, err = M.parse(list, file or M.FILE)
    if not out then
        return nil, err
    end
    return out, file
end

-- A pattern for exactly `title`: its magic characters escaped, between ^
-- and $, so "Save As..." is "^Save As%.%.%.$".
function M.exact(title)
    return "^" .. (title or ""):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$"
end

-- The list's edits, each on a list of { app, title } and returning the new
-- list, or nil and why. A move or removal names the rule by its place, app
-- and title, so a hand edit that has moved it since is refused.
function M.with(list, app, title)
    app = (app or ""):match("^%s*(.-)%s*$")
    title = title or ""
    if app == "" then
        return nil, "type an app's bundle ID, such as com.apple.Preview"
    end
    local why = app_problem(app) or (title ~= "" and M.pattern_problem(title))
    if why then
        return nil, why
    end
    local r = { app = app, title = title ~= "" and title or nil }
    for _, v in ipairs(list) do
        if type(v) == "table" and same(v, r) then
            return nil, M.describe(r) .. " is listed already"
        end
    end
    if #list >= M.MAX then
        return nil, "there are " .. M.MAX .. " rules already, as many as there can be"
    end
    local out = { table.unpack(list) }
    out[#out + 1] = r
    return out
end

local function at(list, i, app, title)
    local v = list[i]
    if type(v) ~= "table" or not same(v, { app = app, title = title }) then
        return nil, "the rules changed since this page showed them; try again"
    end
    return v
end

function M.moved(list, i, app, title, step)
    local ok, why = at(list, i, app, title)
    if not ok then
        return nil, why
    end
    local j = i + step
    if j < 1 or j > #list then
        return list
    end
    local out = { table.unpack(list) }
    out[i], out[j] = out[j], out[i]
    return out
end

function M.without(list, i, app, title)
    local ok, why = at(list, i, app, title)
    if not ok then
        return nil, why
    end
    local out = { table.unpack(list) }
    table.remove(out, i)
    return out
end

-- A rule as JSON: {"app": ..., "title": ...}, the title left out for none.
local function encode_rule(r)
    local t = title_of(r)
    local s = '{"app": ' .. mute.quote(r.app)
    if t ~= "" then
        s = s .. ', "title": ' .. mute.quote(t)
    end
    return s .. "}"
end

local PLACEHOLDER = "__tide_floating__"

-- Apply `fn`, one of the edits above, to the list in effect, and write the
-- result to the .local file: read just before, every other key kept,
-- written whole by `write(path, text)` (atomic.write's way). So the first
-- change copies the shared list, as a local list replaces it. Returns
-- true, or nil and why, writing nothing.
function M.edit(dir, read, decode, encode, write, fn)
    local list, err = M.read(dir, read, decode)
    if not list then
        return nil, err .. ". Fix the file to change the rules here"
    end
    local new, why = fn(list)
    if not new then
        return nil, why
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
    local parts = {}
    for i, r in ipairs(new) do
        if type(r) ~= "table" or app_problem(r.app) then
            return nil, string.format("%s[%d] can't be written back; fix the file by hand", M.KEY, i)
        end
        parts[i] = encode_rule(r)
    end
    obj[M.KEY] = PLACEHOLDER
    local json = encode(obj)
    local found = json and json:find('"' .. PLACEHOLDER .. '"', 1, true)
    if not found then
        return nil, "couldn't write " .. M.LOCAL_FILE .. ": the JSON encoder failed"
    end
    local encoded = #parts == 0 and "[]" or ("[\n    " .. table.concat(parts, ",\n    ") .. "\n  ]")
    json = json:sub(1, found - 1) .. encoded .. json:sub(found + #PLACEHOLDER + 2)
    local ok, werr = write(path, json .. (json:sub(-1) == "\n" and "" or "\n"))
    if not ok then
        return nil, "couldn't write " .. path .. ": " .. tostring(werr)
    end
    return true
end

-- The rule lists in the order they're tried: start()'s `rules`, then the
-- files', then tide's own (rules.defaults).
function M.combined(start_rules, file_rules)
    local out = {}
    for _, list in ipairs({ start_rules or {}, file_rules or {} }) do
        for _, r in ipairs(list) do
            out[#out + 1] = r
        end
    end
    return out
end

-- What floats window `facts` without your asking, as a phrase for the
-- page, or nil when nothing does: a rule in the files, one in start(), one
-- of tide's own, or the step that floats a dialog (rules.decide).
function M.covered_by(facts, start_rules, file_rules)
    if facts.role ~= "AXWindow" then
        return nil
    end
    local r, i = rules.first(start_rules, facts)
    if r then
        return r.action == "float" and "a start() rule" or nil
    end
    r, i = rules.first(file_rules, facts)
    if r then
        return string.format("rule %d", i)
    end
    r = rules.first(rules.defaults, facts)
    if r then
        return r.action == "float" and "built-in rule" or nil
    end
    local action, step = rules.step(facts)
    if action == "float" then
        return rules.STEPS[step]
    end
end

-- The windows a change from rules `old` to `new` floats: of `windows`,
-- each { id, facts, tiled, big }, the tiled ones the new rules float and
-- the old didn't. One the old rules floated is tiled by hand, and stays;
-- one full screen or maximized is left as it is. A reorder, the same rules
-- again, or a rule taken out floats nothing, and nothing is tiled.
function M.sweep(windows, old, new)
    local out = {}
    for _, w in ipairs(windows) do
        local f = w.facts
        if w.tiled and not w.big and f and not f.fullscreen
            and rules.decide(f, new) == "float" and rules.decide(f, old) ~= "float" then
            out[#out + 1] = w.id
        end
    end
    return out
end

-- What macOS says of a window, for "More about this window": `info` from
-- the adapter (role, subrole, modal, size_settable, standard, name, path),
-- as { label, value } rows, each only when it says something.
function M.about(info)
    local rows = {}
    local function add(label, v)
        if v ~= nil and v ~= "" then
            rows[#rows + 1] = { label = label, value = v }
        end
    end
    local function yes(v)
        if v == nil then
            return nil
        end
        return v and "yes" or "no"
    end
    info = info or {}
    add("Role", info.role)
    add("Subrole", info.subrole)
    add("Modal", yes(info.modal))
    add("Resizable", yes(info.size_settable))
    add("Standard", yes(info.standard))
    add("App", info.name)
    add("App's path", info.path)
    return rows
end

-- The page's fill-in for a window: its app and a pattern for its exact
-- title, what floats it already, and what macOS says of it. Nil for a
-- window with no app to name.
function M.prefill(facts, info, start_rules, file_rules)
    if not (facts and facts.app and facts.app ~= "") then
        return nil
    end
    local title = facts.title or ""
    return {
        app = facts.app,
        name = facts.name or facts.app,
        title = title ~= "" and M.exact(title) or "",
        covered = M.covered_by(facts, start_rules, file_rules),
        about = M.about(info),
    }
end

-- The question after Super+Shift+F floats a window no rule covers (tide
-- §6.4): asked once per app per login, whatever the answer. `store` is
-- the record kept across reloads, { login, apps }, or nil; `login` this
-- login (nil when it can't be told, which asks again after a reload).
-- Returns whether to ask and the record to keep.
function M.ask(store, login, app)
    if type(store) ~= "table" or store.login ~= login or type(store.apps) ~= "table" then
        store = { login = login, apps = {} }
    end
    if store.apps[app] then
        return false, store
    end
    store.apps[app] = true
    return true, store
end

-- What the question says.
function M.question(name)
    return "Always float " .. name .. "?"
end

return M
