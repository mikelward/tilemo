-- Start at login (SPEC.md §15, tide §16): tide's `commands`, in
-- startup.json and startup.local.json, run once a login as tilemo starts.
-- Pure Lua: reading, JSON, running and the login's identity come from the
-- caller.

local M = {}

M.KEY = "commands"
M.FILE = "startup.json"
M.LOCAL_FILE = "startup.local.json"
-- hs.settings' key for the login the list last ran in.
M.SETTINGS_KEY = "tilemo.startup_ran"

-- A command's words, split at spaces and tabs, as it runs.
function M.words(command)
    local out = {}
    for w in command:gmatch("[^ \t]+") do
        out[#out + 1] = w
    end
    return out
end

-- Why entry `v` can't be a command, or nil, as tide's startup.mjs says:
-- it runs as words with no shell, so a quote, backslash or $ would mean
-- nothing.
function M.problem(v)
    if type(v) ~= "string" then
        return "is not a string"
    elseif v:find("%c") then
        return "has a control character in it"
    elseif #M.words(v) == 0 then
        return "names no program"
    elseif M.words(v)[1]:sub(-1) == "/" then
        return "names a directory, not a program"
    elseif v:find("[\"'`\\$]") then
        return "has a quote, backslash or $, which runs as typed, with no shell; put shell syntax in a script"
    end
end

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

-- The commands to run, and the errors to report: the .local file's list
-- if it sets one, which replaces the shared one whole (tide §16.1), else
-- the shared file's, else none. A bad entry is an error naming the file
-- and the entry, and left out; so is one listed twice. A file that isn't
-- a JSON object, or whose list isn't one, gives nil and one error: which
-- list it meant can't be told, so nothing runs.
function M.load(dir, read, decode)
    for _, name in ipairs({ M.LOCAL_FILE, M.FILE }) do
        local text = read(dir .. "/" .. name)
        if text then
            -- An empty JSON list decodes as an empty table, as {} does,
            -- so the text says which it is.
            local v = decode(text)
            if type(v) ~= "table" or not text:match("^%s*{") then
                return nil, { name .. ": not a JSON object" }
            end
            local list = v[M.KEY]
            if list ~= nil then
                if not is_list(list) then
                    return nil, { name .. ": " .. M.KEY .. " must be a list" }
                end
                local out, errors, seen = {}, {}, {}
                for i, entry in ipairs(list) do
                    local why = M.problem(entry)
                    local normal = not why and table.concat(M.words(entry), " ")
                    if not why and seen[normal] then
                        why = "is listed already"
                    end
                    if why then
                        errors[#errors + 1] = string.format("%s: %s[%d] %s %s", name, M.KEY, i,
                            type(entry) == "string" and string.format("%q", entry) or tostring(entry), why)
                    else
                        seen[normal] = true
                        out[#out + 1] = normal
                    end
                end
                return out, errors
            end
        end
    end
    return {}, {}
end

-- Whether the list is due: this login (`login`, nil when it can't be told)
-- isn't the one it last ran in (`last`). A login that can't be told runs
-- nothing, since Hammerspoon reloads its config often and each would run
-- it again.
function M.due(last, login)
    return login ~= nil and login ~= "" and login ~= last
end

-- pgrep's arguments for whether a process of user `uid` runs `command`'s
-- program: its whole basename, with regular expressions' punctuation
-- escaped. macOS's pgrep -x matches the basename of a process's argv[0],
-- not its 15-byte comm (adv_cmds' pkill.c), so unlike tide's on Linux, the
-- name isn't cut short.
function M.pgrep_args(uid, command)
    local program = (M.words(command)[1] or ""):match("[^/]+$") or ""
    local name = program:gsub("[][%.%*%^%$%+%?%(%){}|\\]", "\\%0")
    return { "-u", tostring(uid), "-x", "--", name }
end

-- Runs each command not running already, in the list's order: each one's
-- check, and its launch, comes after the one before it's. `running(args,
-- done)` runs pgrep with `args` and calls done(code); `launch(command)`
-- starts one; `log(text)` says what was skipped and why. pgrep exiting 0
-- means it's running; 1 that it isn't; anything else can't tell, which
-- starts it anyway, saying so. One command that throws is logged, and the
-- rest still run.
function M.run(commands, uid, running, launch, log)
    local function from(i)
        local command = commands[i]
        if not command then
            return
        end
        local moved = false
        local function next_one()
            if not moved then
                moved = true
                from(i + 1)
            end
        end
        local ok, err = pcall(running, M.pgrep_args(uid, command), function(code)
            if code == 0 then
                log(command .. " is running already, so not starting it again")
            else
                if code ~= 1 then
                    log("pgrep couldn't say whether " .. command .. " is running (exit " .. tostring(code) .. "), so starting it")
                end
                local started, why = pcall(launch, command)
                if not started then
                    log("couldn't start " .. command .. ": " .. tostring(why))
                end
            end
            next_one()
        end)
        -- One command's failure mustn't keep the rest from starting, or
        -- tilemo from loading.
        if not ok then
            log("couldn't start " .. command .. ": " .. tostring(err))
            next_one()
        end
    end
    from(1)
end

-- hs.settings' key for the login home's apps last started in. Apart from
-- the list's, so a list that can't be read doesn't hold them back, nor
-- they it, as tide runs the two independently (tide §6.5).
M.HOME_SETTINGS_KEY = "tilemo.home_started"

-- The apps home starts at login (SPEC.md §6.2): the `home_apps` you set in
-- start(), in order, or none. tilemo's default list names a Mac app and a
-- web app for each of mail, chat, calendar and music, which match either,
-- so starting it would open both, Mail's and Messages' first-run setup
-- included.
function M.home_starts(configured)
    local out = {}
    for _, name in ipairs(configured or {}) do
        out[#out + 1] = name
    end
    return out
end

-- Opens each of home's apps that isn't running, in order. `running(name)`
-- says whether one is; `open(name)` starts one in the background; `log`
-- says what was skipped and why. One that throws is logged, and the rest
-- still start.
function M.start_home(names, running, open, log)
    for _, name in ipairs(names) do
        local ok, err = pcall(function()
            if running(name) then
                log(name .. " is running already, so not starting it again")
            else
                open(name)
            end
        end)
        if not ok then
            log("couldn't start " .. name .. ": " .. tostring(err))
        end
    end
end

-- Home's apps at login: once a login (`login`, as for the list), and only
-- with a `home_apps` you set. `settings` is hs.settings' get and set,
-- keeping the login they last started in. Returns whether they started.
function M.home_at_login(configured, settings, login, running, open, log)
    local names = M.home_starts(configured)
    if #names == 0 or not M.due(settings.get(M.HOME_SETTINGS_KEY), login) then
        return false
    end
    settings.set(M.HOME_SETTINGS_KEY, login)
    M.start_home(names, running, open, log)
    return true
end

return M
