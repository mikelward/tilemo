-- LinearMouse, which gives each mouse wheel notch the same distance, where
-- macOS's slider changes only the acceleration (SPEC.md §10): whether it's
-- there to, said in a notification, `tide doctor` and the settings
-- window's Mouse section (§1, §15). And tide's Mouse settings applied to
-- it: its scrolling for every mouse, from tide's input.json and
-- input.local.json, through dashboard/linearmouse.js in JavaScriptCore.
-- Pure Lua: files, the JavaScript and the app come from `deps`.

local dashboard = require("tide.dashboard")
local names = require("tide.names")

local M = {}

-- Homebrew's cask quits it by this.
M.BUNDLE = "com.lujjjh.LinearMouse"

-- What stops working, said the same wherever it's said.
local COST = "so a mouse wheel notch scrolls a line or so, faster as you spin it"

-- What's wrong: "missing", "stopped", or nil when it's installed and
-- running. `installed()` and `running()` ask about M.BUNDLE.
function M.problem(installed, running)
    if not installed() then
        return "missing"
    end
    if not running() then
        return "stopped"
    end
    return nil
end

-- `kind` (M.problem) said for `where`: "notice", a notification, a click
-- on which starts it when it's stopped; "doctor", tide doctor's line; or
-- "section", the Mouse section's line, beside the button that opens it.
function M.say(kind, where)
    if kind == "missing" then
        return "LinearMouse isn't installed, " .. COST .. ". setup-macos installs it."
    end
    if kind ~= "stopped" then
        return nil
    end
    local text = "LinearMouse isn't running, " .. COST .. "."
    if where == "notice" then
        return text .. " Click to start it, and turn on its Start at login."
    end
    if where == "doctor" then
        return text .. " Start it with LinearMouse settings, under Mouse in tide's settings,"
            .. " and turn on its Start at login."
    end
    return text
end

-- What the Mouse section shows from `state` (M.new's), as one string: the
-- problem and every mouse's pointer, so the page is redrawn when either
-- changes, a pointer set in LinearMouse's own window included, and not
-- every 30 s otherwise.
function M.shown(state)
    local p = state.pointer or {}
    return table.concat({ state.problem or "", tostring(p.speed), tostring(p.acceleration) }, "\0")
end

-- The two places LinearMouse reads its config from, the first that exists
-- (its ConfigurationState.swift); with neither, it makes the second.
M.CONFIGS = {
    "/Library/Application Support/linearmouse/linearmouse.json",
    "/.config/linearmouse/linearmouse.json",
}
M.DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/dashboard/"
-- The modules the edit runs, in order: each imports only ones before it.
M.MODULES = { "tide-clocks.js", "tide-input.js", "linearmouse.js" }

-- macOS's natural-scrolling switch, from `defaults read -g
-- com.apple.swipescrolldirection`'s exit code and output (stdout and
-- stderr): on when it's unset, as macOS has it. Returns true or false, or
-- nil and why when defaults couldn't say.
function M.natural_from(code, out)
    out = out or ""
    if code == 0 then
        local v = out:match("^%s*(%d)%s*$")
        if v then
            return v == "1"
        end
        return nil, "defaults read -g com.apple.swipescrolldirection said " .. out
    end
    if out:find("does not exist", 1, true) then
        return true
    end
    return nil, "defaults read -g com.apple.swipescrolldirection exited " .. tostring(code) .. ": " .. out
end

-- `fn` run `delay` seconds after the last of a burst of calls, through
-- `after(seconds, fn)` -> { stop }, as a KVM brings several devices at
-- once.
function M.debounce(after, delay, fn)
    local pending
    return function()
        if pending then
            pending.stop()
        end
        pending = after(delay, function()
            pending = nil
            fn()
        end)
    end
end

local js = names.js_string

-- `deps`: home; dir, tide's settings folder; sources, each of M.MODULES'
-- text by name; read(path) -> text or nil; exists(path); resolve(path) ->
-- the path a symlink names; write(path, text) -> true or nil, why;
-- run_js(source) -> ok, result; decode(json) -> table or nil;
-- natural(done), which calls done(on) with macOS's switch, or done(nil,
-- why); installed() and running(), LinearMouse's; start(done), which
-- starts it in the background and calls done(ok, why); notify(text);
-- log(text).
function M.new(deps)
    local self = { state = { problem = "" }, launching = false }
    local bundle = dashboard.bundle(deps.sources, M.MODULES)
    local home = deps.home or ""
    -- tide's settings as they last loaded, kept while a file is wrong, as
    -- tide keeps them: JSON, for the JavaScript.
    local good = "{}"
    local last_key, last_inputs
    -- The last natural-scrolling switch read, macOS's default until then.
    local natural = true
    local said = {}

    local function say_once(kind, text)
        if text ~= "" and text ~= said[kind] then
            deps.notify(text)
        end
        said[kind] = text
    end

    local function config_path()
        for _, p in ipairs(M.CONFIGS) do
            if deps.exists(home .. p) then
                return home .. p
            end
        end
        return home .. M.CONFIGS[#M.CONFIGS]
    end

    local function start_it()
        if self.launching or not deps.installed() or deps.running() then
            return
        end
        self.launching = true
        deps.start(function(ok, why)
            self.launching = false
            if not ok then
                local text = "Couldn't start LinearMouse: " .. tostring(why)
                deps.log(text)
                deps.notify(text)
            end
            if self.on_started then
                self.on_started()
            end
        end)
    end

    local function apply(shared, localtext, path, config)
        local source = "(function(){" .. bundle
            .. "const I = modules[\"./tide-input.js\"]; const L = modules[\"./linearmouse.js\"];\n"
            .. "const loaded = I.loadInput(" .. (shared and js(shared) or "null") .. ", "
            .. (localtext and js(localtext) or "null") .. ", " .. good .. ");\n"
            .. "const want = L.mouseScrolling(loaded.input, " .. tostring(natural) .. ");\n"
            .. "const r = L.withMouseScrolling(" .. (config and js(config) or "null") .. ", want.lines, want.reverse);\n"
            .. "return JSON.stringify({ input: JSON.stringify(loaded.input), errors: loaded.errors,"
            .. " lines: want.lines, reverse: want.reverse, text: r.text, error: r.error,"
            .. " pointer: L.mousePointer(r.text !== undefined ? r.text : " .. (config and js(config) or "null") .. ") });})()"
        local ok, out = deps.run_js(source)
        if not ok then
            return nil, "couldn't run the Mouse settings' JavaScript: " .. tostring(out)
        end
        local v = deps.decode(out)
        if type(v) ~= "table" then
            return nil, "the Mouse settings' JavaScript gave back " .. tostring(out)
        end
        return v
    end

    -- Bring LinearMouse's config in line with tide's Mouse settings, after
    -- reading macOS's switch. `why`: "event" (tide starting, a device
    -- plugged in, a wake or unlock), which also starts LinearMouse when it
    -- isn't running; "folder", tide's folder changed, which starts it only
    -- when the Mouse settings did; "check", the 30 s check, which never
    -- does, so quitting it on purpose lasts until the next event. Nothing
    -- runs when nothing changed. `done(state)`, if given, once it has.
    function self.apply(why, done)
        deps.natural(function(on, err)
            if on == nil then
                deps.log("natural scrolling: " .. tostring(err) .. "; taking it as " .. tostring(natural))
            else
                natural = on
            end
            local dir = deps.dir or ""
            local shared = deps.read(dir .. "/input.json")
            local localtext = deps.read(dir .. "/input.local.json")
            local inputs = (shared or "") .. "\0" .. (localtext or "")
            local changed = last_inputs ~= nil and inputs ~= last_inputs
            last_inputs = inputs
            if deps.installed() then
                local path = config_path()
                local config = deps.read(path)
                local key = inputs .. "\0" .. path .. "\0" .. (config or "") .. "\0" .. tostring(natural)
                if key ~= last_key then
                    last_key = key
                    local problems = {}
                    local v, jerr = apply(shared, localtext, path, config)
                    if not v then
                        deps.log(jerr)
                        problems[#problems + 1] = jerr
                    else
                        -- Kept until the file is fixed, so doctor says it
                        -- too, not only the notification.
                        if #(v.errors or {}) > 0 then
                            self.state.input_problem = "tide's Mouse settings stay as they were: " .. table.concat(v.errors, "; ")
                        else
                            good = v.input or good
                            self.state.input_problem = ""
                        end
                        say_once("input", self.state.input_problem)
                        if type(v.error) == "string" then
                            problems[#problems + 1] = "Can't set LinearMouse's scrolling: " .. v.error
                                .. ". Fix " .. path .. ", or move it aside and LinearMouse makes a new one."
                        elseif type(v.text) == "string" then
                            local wrote, werr = deps.write(deps.resolve(path), v.text)
                            if not wrote then
                                problems[#problems + 1] = "Couldn't save LinearMouse's scrolling to " .. path .. ": " .. tostring(werr)
                                -- Try again at the next check.
                                last_key = nil
                            else
                                -- What's in the file now.
                                last_key = inputs .. "\0" .. path .. "\0" .. v.text .. "\0" .. tostring(natural)
                            end
                        end
                        self.state.lines, self.state.reverse = v.lines, v.reverse
                        self.state.pointer = type(v.pointer) == "table" and v.pointer or {}
                    end
                    self.state.problem = table.concat(problems, " ")
                    say_once("config", self.state.problem)
                end
            end
            if why == "event" or (why == "folder" and changed) then
                start_it()
            end
            if done then
                done(self.state)
            end
        end)
    end

    -- The Mac's own Speed and Acceleration rows (dashboard/linearmouse.js's
    -- withMousePointer): every mouse's pointer `key` set to `value` in
    -- LinearMouse's config, which LinearMouse reads as it changes. Returns
    -- true, or nil and why, with nothing written.
    function self.set_pointer(key, value)
        if not deps.installed() then
            return nil, "LinearMouse isn't installed, so there's nothing to set the pointer in"
        end
        local path = config_path()
        local config = deps.read(path)
        local source = "(function(){" .. bundle
            .. "const L = modules[\"./linearmouse.js\"];\n"
            .. "const r = L.withMousePointer(" .. (config and js(config) or "null") .. ", " .. js(tostring(key)) .. ", "
            .. (type(value) == "number" and string.format("%.17g", value) or "null") .. ");\n"
            .. "return JSON.stringify({ text: r.text, error: r.error,"
            .. " pointer: L.mousePointer(r.text !== undefined ? r.text : " .. (config and js(config) or "null") .. ") });})()"
        local ok, out = deps.run_js(source)
        if not ok then
            return nil, "couldn't run the Mouse settings' JavaScript: " .. tostring(out)
        end
        local v = deps.decode(out)
        if type(v) ~= "table" then
            return nil, "the Mouse settings' JavaScript gave back " .. tostring(out)
        end
        if type(v.error) == "string" then
            return nil, "Can't set LinearMouse's pointer: " .. v.error
        end
        if type(v.text) == "string" then
            local wrote, werr = deps.write(deps.resolve(path), v.text)
            if not wrote then
                return nil, "Couldn't save LinearMouse's pointer to " .. path .. ": " .. tostring(werr)
            end
            -- The next apply reads the file afresh.
            last_key = nil
        end
        self.state.pointer = type(v.pointer) == "table" and v.pointer or {}
        return true
    end

    -- tide doctor's line, if anything's wrong with applying them.
    function self.doctor()
        local out = {}
        for _, p in ipairs({ self.state.input_problem or "", self.state.problem }) do
            if p ~= "" then
                out[#out + 1] = p
            end
        end
        return out
    end

    return self
end

return M
