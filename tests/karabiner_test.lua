-- Karabiner's rules, switched by tide (karabiner.lua, dashboard/karabiner.js),
-- with node standing in for JavaScriptCore.

local t = require("t")
local json = require("json")
local karabiner = require("tide.karabiner")

local function node_runner()
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to switch Karabiner's rules")
        end
        return nil
    end
    return function(source)
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write("process.stdout.write(String(" .. source .. "));")
        f:close()
        local p = io.popen("node " .. path .. " 2>&1")
        local out = p:read("a")
        local ok = p:close()
        os.remove(path)
        return ok == true, out
    end
end

local run_node = node_runner()
if not run_node then
    print("SKIP Karabiner's rules: no node")
    return
end

local function read_file(path)
    local f = assert(io.open(path))
    local s = f:read("a")
    f:close()
    return s
end

local SOURCE = read_file("hammerspoon/tide/dashboard/karabiner.js")
local HOME = "/Users/me"
local CONFIG = HOME .. karabiner.CONFIG
local ASSETS = HOME .. karabiner.ASSETS

-- conf's four rules, each with one manipulator saying which it is.
local function rule_file(title, description, key)
    return '{"title": "' .. title .. '", "rules": [{"description": "' .. description
        .. '", "manipulators": [{"type": "basic", "from": {"key_code": "' .. key .. '"}}]}]}'
end

local TAB = "Ctrl+Tab goes to the next tab, not the application switcher (PC muscle memory)"
local ARROWS = "Ctrl+Left/Right moves by word, Win+Left/Right switches Spaces (PC muscle memory)"
local TERMINAL = "Ctrl is Control and Alt is Meta in kitty and Ghostty (PC muscle memory)"
local TIDE = "tide: Win+key sends Ctrl+Option+Command"

local function conf_assets()
    return {
        ["pc-alt-tab.json"] = rule_file("PC keyboard Ctrl+Tab", TAB, "tab"),
        ["pc-arrows.json"] = rule_file("PC keyboard arrows", ARROWS, "left_arrow"),
        ["pc-terminal.json"] = rule_file("PC keyboard terminals", TERMINAL, "u"),
        ["tide.json"] = rule_file("tide", TIDE, "left_command"),
    }
end

local EMPTY_CONFIG = '{"global": {"show_in_menu_bar": true}, "profiles": [{"name": "Default", "selected": true,'
    .. ' "simple_modifications": [], "complex_modifications": {"parameters": {"basic.to_if_alone_timeout_milliseconds": 1000}, "rules": []}}]}'

-- A Mac with these files, Karabiner running unless `running` is false.
local function machine(files, opts)
    opts = opts or {}
    local m = { files = files, settings = {}, notices = {}, logs = {}, writes = {}, runs = 0, running = opts.running ~= false }
    local deps = {
        home = HOME,
        source = SOURCE,
        read = function(path)
            return m.files[path]
        end,
        list = function(dir)
            if dir ~= ASSETS then
                return nil
            end
            local out = {}
            for path in pairs(m.files) do
                local name = path:match("^" .. ASSETS:gsub("%p", "%%%0") .. "/([^/]+)$")
                if name then
                    out[#out + 1] = name
                end
            end
            return out
        end,
        run_js = function(source)
            m.runs = m.runs + 1
            return run_node(source)
        end,
        decode = json.decode,
        write = function(path, text)
            if m.fail_write then
                return nil, "disk full"
            end
            m.writes[#m.writes + 1] = path
            m.files[path] = text
            return true
        end,
        resolve = function(path)
            return (opts.links or {})[path] or path
        end,
        running = function()
            return m.running
        end,
        get = function(k)
            return m.settings[k]
        end,
        set = function(k, v)
            m.settings[k] = v
        end,
        notify = function(text)
            m.notices[#m.notices + 1] = text
        end,
        log = function(text)
            m.logs[#m.logs + 1] = text
        end,
    }
    m.k = karabiner.new(deps)
    return m
end

local function with_assets(config, assets)
    local files = { [CONFIG] = config }
    for name, text in pairs(assets or conf_assets()) do
        files[ASSETS .. "/" .. name] = text
    end
    return files
end

-- The selected profile's rule descriptions, top first, from the file.
local function enabled(m, path)
    local config = json.decode(m.files[path or CONFIG])
    local out = {}
    for _, r in ipairs(config.profiles[1].complex_modifications.rules or {}) do
        out[#out + 1] = r.description
    end
    return out
end

local function on_of(state)
    local out = {}
    for _, r in ipairs(state.rules) do
        out[r.label] = r.on
    end
    return out
end

t.test("the first check turns conf's rules on, tide's and the terminal's above the arrow rule", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    local s = m.k.check()
    t.eq(enabled(m), { TIDE, TERMINAL, TAB, ARROWS })
    t.eq(#m.writes, 1)
    t.eq(s.problem, "")
    t.eq(on_of(s), {
        ["Ctrl+Tab goes to the next tab, not the application switcher"] = true,
        ["Ctrl+Left/Right moves by word, Win+Left/Right switches Spaces"] = true,
        ["Ctrl is Control and Alt is Meta in kitty and Ghostty"] = true,
        ["tide: Win+key sends Ctrl+Option+Command"] = true,
    })
    t.eq(#m.notices, 1)
    t.eq(m.notices[1]:find("tide turned on conf's Karabiner rules", 1, true) ~= nil, true, m.notices[1])
    t.eq(m.notices[1]:find("under Keyboard in tide's settings", 1, true) ~= nil, true, m.notices[1])
end)

t.test("the rest of karabiner.json stays as it was", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    m.k.check()
    local text = m.files[CONFIG]
    t.eq(text:find('"simple_modifications": []', 1, true) ~= nil, true, "an empty list stays a list: " .. text)
    local config = json.decode(text)
    t.eq(config.global.show_in_menu_bar, true)
    t.eq(config.profiles[1].complex_modifications.parameters["basic.to_if_alone_timeout_milliseconds"], 1000)
    t.eq(config.profiles[1].name, "Default")
end)

t.test("a rule you turn off stays off", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    m.k.check()
    t.eq(m.k.set(TAB, false), true)
    t.eq(enabled(m), { TIDE, TERMINAL, ARROWS })
    local writes = #m.writes
    local s = m.k.check(true)
    t.eq(#m.writes, writes, "nothing turned on again")
    t.eq(on_of(s)["Ctrl+Tab goes to the next tab, not the application switcher"], false)
end)

t.test("a rule turned back on goes in its place", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    m.k.check()
    m.k.set(TERMINAL, false)
    t.eq(m.k.set(TERMINAL, true), true)
    t.eq(enabled(m), { TIDE, TERMINAL, TAB, ARROWS })
end)

t.test("a rule already on stays where you put it", function()
    local config = '{"profiles": [{"selected": true, "complex_modifications": {"rules": ['
        .. '{"description": "' .. ARROWS .. '", "manipulators": [{"type": "basic", "from": {"key_code": "left_arrow"}}]},'
        .. '{"description": "my own rule", "manipulators": []}]}}]}'
    local m = machine(with_assets(config))
    m.k.check()
    -- The new ones go above the arrow rule; your own rule stays below it.
    t.eq(enabled(m), { TIDE, TERMINAL, TAB, ARROWS, "my own rule" })
end)

t.test("a copy that differs from conf's file is brought up to date in its place", function()
    local config = '{"profiles": [{"selected": true, "complex_modifications": {"rules": ['
        .. '{"description": "' .. TAB .. '", "enabled": false, "manipulators": [{"type": "basic", "from": {"key_code": "q"}}]}]}}]}'
    local m = machine(with_assets(config))
    m.settings[karabiner.SEEN_KEY] = { TAB, ARROWS, TERMINAL, TIDE }
    local s = m.k.check()
    local rule = json.decode(m.files[CONFIG]).profiles[1].complex_modifications.rules[1]
    t.eq(rule.description, TAB)
    t.eq(rule.manipulators[1].from.key_code, "tab")
    t.eq(rule.enabled, false, "turned off in Karabiner's window, it stays off")
    t.eq(on_of(s)["Ctrl+Tab goes to the next tab, not the application switcher"], false)
    t.eq(m.notices[1]:find("up to date with conf", 1, true) ~= nil, true, m.notices[1] or "no notice")
end)

-- Karabiner writes its file with each object's keys sorted, so a copy it
-- rewrote has conf's rule in another order, which is the same rule.
t.test("a copy whose keys Karabiner sorted is the same rule", function()
    local config = '{"profiles": [{"selected": true, "complex_modifications": {"rules": ['
        .. '{"description": "' .. TAB .. '", "manipulators": [{"from": {"key_code": "tab"}, "type": "basic"}]}]}}]}'
    local m = machine(with_assets(config))
    m.settings[karabiner.SEEN_KEY] = { TAB, ARROWS, TERMINAL, TIDE }
    local s = m.k.check()
    t.eq(#m.writes, 0)
    t.eq(#m.notices, 0)
    t.eq(on_of(s)["Ctrl+Tab goes to the next tab, not the application switcher"], true)
end)

t.test("nothing changed, nothing runs", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    m.k.check()
    m.k.check()
    local runs = m.runs
    m.k.check()
    t.eq(m.runs, runs)
end)

t.test("without karabiner.json, nothing's written and the rules wait to be turned on", function()
    local files = with_assets(EMPTY_CONFIG)
    files[CONFIG] = nil
    local m = machine(files)
    local s = m.k.check()
    t.eq(#m.writes, 0)
    t.eq(s.problem, karabiner.NO_CONFIG)
    t.eq(m.settings[karabiner.SEEN_KEY], nil)
    m.files[CONFIG] = EMPTY_CONFIG
    m.k.check()
    t.eq(enabled(m), { TIDE, TERMINAL, TAB, ARROWS })
end)

t.test("a karabiner.json that isn't JSON is left alone and named", function()
    local m = machine(with_assets("{not json"))
    local s = m.k.check()
    t.eq(#m.writes, 0)
    t.eq(s.problem:find("karabiner.json isn't JSON", 1, true) ~= nil, true, s.problem)
    t.eq(m.k.set(TAB, true), nil)
end)

t.test("no rule files says to run confinst", function()
    local m = machine({ [CONFIG] = EMPTY_CONFIG })
    local s = m.k.check()
    t.eq(s.problem, karabiner.NO_RULES)
    t.eq(#m.writes, 0)
end)

t.test("a rule file that isn't JSON is named, and the rest still switch", function()
    local assets = conf_assets()
    assets["pc-arrows.json"] = "{oops"
    local m = machine(with_assets(EMPTY_CONFIG, assets))
    local s = m.k.check()
    t.eq(s.problem:find("pc-arrows.json isn't JSON", 1, true) ~= nil, true, s.problem)
    t.eq(enabled(m), { TIDE, TERMINAL, TAB })
end)

t.test("Karabiner not running is said, and the rules still switch", function()
    local m = machine(with_assets(EMPTY_CONFIG), { running = false })
    local s = m.k.check()
    t.eq(s.problem, karabiner.NOT_RUNNING)
    t.eq(#enabled(m), 4)
end)

t.test("a symlinked karabiner.json is written where it points", function()
    local real = "/Users/me/conf/karabiner.json"
    local m = machine(with_assets(EMPTY_CONFIG), { links = { [CONFIG] = real } })
    m.k.check()
    t.eq(m.writes, { real })
end)

t.test("a failed save is said, shows what's in the file, and is tried again at the next check", function()
    local m = machine(with_assets(EMPTY_CONFIG))
    m.fail_write = true
    local s = m.k.check()
    t.eq(m.notices[1]:find("Couldn't save Karabiner's rules", 1, true) ~= nil, true, m.notices[1])
    t.eq(m.settings[karabiner.SEEN_KEY], nil)
    -- Nothing was saved, so nothing shows as on.
    for _, r in ipairs(s.rules) do
        t.eq(r.on, false, r.label)
    end
    -- The timer's check, unforced, with no file changed since.
    m.fail_write = false
    m.k.check()
    t.eq(enabled(m), { TIDE, TERMINAL, TAB, ARROWS })
end)

t.test("the doctor names conf's rules that are off, not other rules", function()
    local assets = conf_assets()
    assets["other.json"] = rule_file("Someone else's", "Caps Lock is Escape", "caps_lock")
    local m = machine(with_assets(EMPTY_CONFIG, assets))
    m.k.check()
    m.k.set(TAB, false)
    m.k.set("Caps Lock is Escape", false)
    local lines = m.k.doctor()
    t.eq(#lines, 1)
    t.eq(lines[1], "conf's Karabiner rules that are off: Ctrl+Tab goes to the next tab, not the application switcher."
        .. " Turn them on under Keyboard in tide's settings.")
end)

-- conf's lock screen rule (pc-lock.json): turned on at the top, above
-- tide's, which would take a Mac keyboard's Command+U there as Super+U,
-- and named in the doctor when it's off, as conf's others are.
local LOCK = "Ctrl+U clears the password at the lock screen, as on Linux (PC muscle memory)"

t.test("conf's lock screen rule goes on above tide's, and the doctor names it when it's off", function()
    local assets = conf_assets()
    assets["pc-lock.json"] = rule_file("PC keyboard lock screen", LOCK, "u")
    local m = machine(with_assets(EMPTY_CONFIG, assets))
    m.k.check()
    t.eq(enabled(m), { LOCK, TIDE, TERMINAL, TAB, ARROWS })
    m.k.set(LOCK, false)
    m.k.set(LOCK, true)
    t.eq(enabled(m), { LOCK, TIDE, TERMINAL, TAB, ARROWS }, "turned back on in its place")
    m.k.set(LOCK, false)
    local lines = m.k.doctor()
    t.eq(#lines, 1)
    t.eq(lines[1]:match("^conf's Karabiner rules that are off: Ctrl%+U clears the password at the lock screen") ~= nil, true,
        lines[1])
end)

t.done("karabiner")
