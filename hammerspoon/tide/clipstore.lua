-- The clipboard history on disk, so it outlives a restart as tide's does
-- (SPEC.md §9.1, tide §8.4): newest first, each copy with when it was
-- kept, as JSON, encrypted with a key in the login keychain (clipcrypt),
-- in a folder only you can read, written whole, mode 600, after each
-- change. An entry past the Clipboard settings' days, a week by default,
-- is forgotten, on disk and in memory.
-- What it keeps is what picker.lua kept, so a copy password managers mark
-- is never written.
-- Pure Lua: `fs` is atomic.lua's, plus mkdir(path, mode) and chmod(path,
-- mode), as current.lua takes; `encode` and `decode` are JSON's; `crypt`
-- is clipcrypt's seal(text, path, done) and open(path, done); `now()` is
-- seconds since the epoch.

local picker = require("tide.picker")

local M = {}

-- Beside the workspace's name, in ~/Library/Caches/tide (current.lua),
-- which Time Machine leaves out.
M.FILE = "clipboard-history"
local DAY = 24 * 3600

-- How long an entry is kept after it was last copied: the Clipboard
-- settings' days, a week by default.
local function ttl(history)
    local s = history.settings or picker.DEFAULTS
    return (s.max_age_days or picker.MAX_AGE_DAYS) * DAY
end

function M.new(dir, fs, encode, decode, crypt, now)
    local self = { path = dir .. "/" .. M.FILE }
    -- Counts clears, so one made while the saved history is being read
    -- keeps it from coming back.
    local clears = 0
    local saving, again
    -- Saves asked for before the saved history was read back: they wait,
    -- so the file isn't replaced by what's in memory before it's read.
    local pending

    -- Forgets entries past the Clipboard settings' days from `history`. Returns whether any
    -- went.
    function self.expire(history)
        local t = now()
        local gone = false
        for i = #history.items, 1, -1 do
            local text = history.items[i]
            history.times[text] = history.times[text] or t
            if t - history.times[text] >= ttl(history) then
                table.remove(history.items, i)
                history.times[text] = nil
                gone = true
            end
        end
        return gone
    end

    -- Puts what was saved into `history`, then calls `done(err, trimmed)`:
    -- why it couldn't, or nil, and whether the cap or the week left some
    -- out. No file yet is nothing to read, not a failure.
    function self.load(history, done)
        local clears_then = clears
        local f, err = fs.open(self.path, "rb")
        if not f then
            if tostring(err):find("No such file", 1, true) then
                return done(nil, false)
            end
            return done("couldn't read " .. self.path .. ": " .. tostring(err))
        end
        f:close()
        crypt.open(self.path, function(text, cerr)
            if not text then
                return done(cerr)
            end
            local ok, list = pcall(decode, text)
            if not ok or type(list) ~= "table" then
                return done(self.path .. " isn't a list of copies")
            end
            if clears ~= clears_then then
                -- Cleared while it read: what was saved stays gone.
                return done(nil, false)
            end
            local t = now()
            local texts, times, dropped = {}, {}, false
            for _, e in ipairs(list) do
                if type(e) == "table" and type(e.text) == "string" and type(e.at) == "number" then
                    if t - e.at < ttl(history) then
                        texts[#texts + 1] = e.text
                        times[e.text] = times[e.text] or e.at
                    else
                        dropped = true
                    end
                end
            end
            local capped = picker.restore(history, texts, times)
            done(nil, capped or dropped)
        end)
    end

    local function write(history, done)
        local list = {}
        for _, text in ipairs(history.items) do
            list[#list + 1] = { text = text, at = history.times[text] }
        end
        local ok, werr = fs.mkdir(dir, "700")
        if ok then
            ok, werr = fs.chmod(dir, "700")
        end
        if not ok then
            return done(nil, werr)
        end
        -- Written beside it, then renamed over it, so a reader never sees
        -- half of it and a failure leaves the last one.
        local tmp = self.path .. ".tmp"
        crypt.seal(encode(list), tmp, function(sealed, err)
            if sealed then
                sealed, err = fs.chmod(tmp, "600")
            end
            if sealed then
                sealed, err = fs.rename(tmp, self.path)
            end
            if not sealed then
                fs.remove(tmp)
                return done(nil, err)
            end
            done(true)
        end)
    end

    -- Writes `history`'s entries, less any past their days, then calls
    -- `done(true)` or `done(nil, why)`. A save asked for while one is
    -- writing runs once that's done, with the history as it is then.
    function self.save(history, done)
        done = done or function() end
        if not self.ready then
            pending = pending or {}
            pending[#pending + 1] = done
            return
        end
        self.expire(history)
        if saving then
            again = again or {}
            again[#again + 1] = done
            return
        end
        saving = true
        write(history, function(ok, err)
            saving = false
            done(ok, err)
            if again then
                local waiting = again
                again = nil
                self.save(history, function(ok2, err2)
                    for _, d in ipairs(waiting) do
                        d(ok2, err2)
                    end
                end)
            end
        end)
    end

    -- Applies the Clipboard settings `s` to `history`, as picker.configure.
    -- The first time, then reads what was saved, so a cap over the default
    -- keeps all of it, and calls `on_load(err)` once it's read; a file that
    -- couldn't be read is left alone until the history changes, so a fixed
    -- permission gets it all back. After that, or when the first read
    -- dropped some, it writes the file when the cap trimmed the history.
    -- `done(ok, err)` hears of any save.
    function self.configure(history, s, on_load, done)
        local before = #history.items
        picker.configure(history, s)
        if not self.loaded then
            self.loaded = true
            self.load(history, function(err, trimmed)
                self.unreadable = err ~= nil
                self.ready = true
                on_load(err)
                local waiting = pending
                pending = nil
                if waiting then
                    -- A copy kept while it read: written now, with what
                    -- came back.
                    self.save(history, function(ok, serr)
                        for _, d in ipairs(waiting) do
                            d(ok, serr)
                        end
                    end)
                elseif trimmed and not err then
                    self.save(history, done)
                end
            end)
            return
        end
        if #history.items < before and not self.unreadable then
            self.save(history, done)
        end
    end

    -- The history changed: a copy kept or forgotten, or a clear. Writes it,
    -- replacing even a file that couldn't be read.
    function self.changed(history, done)
        self.unreadable = false
        self.save(history, done)
    end

    -- The history was cleared: as changed, and what was saved doesn't come
    -- back, even if it's still being read.
    function self.cleared(history, done)
        clears = clears + 1
        self.changed(history, done)
    end

    return self
end

return M
