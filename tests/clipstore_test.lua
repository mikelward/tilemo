-- The clipboard history on disk (SPEC.md §9.1).

local t = require("t")
local clipstore = require("tide.clipstore")
local picker = require("tide.picker")
local json = require("json")

-- A stand-in for the file system: files and their modes. `fail` names a
-- call that fails.
local function disk(fail)
    local d = { files = {}, modes = {} }
    function d.open(path, how)
        if how == "rb" then
            if fail == "read" then
                return nil, path .. ": Permission denied"
            end
            local text = d.files[path]
            if not text then
                return nil, path .. ": No such file or directory"
            end
            return {
                read = function()
                    return text
                end,
                close = function()
                    return true
                end,
            }
        end
        local buf = {}
        return {
            write = function(self, text)
                buf[#buf + 1] = text
                return self
            end,
            close = function()
                if fail == "write" then
                    return nil, "No space left on device"
                end
                d.files[path] = table.concat(buf)
                return true
            end,
        }
    end
    function d.rename(from, to)
        if fail == "rename" then
            return nil, "Operation not permitted"
        end
        d.files[to], d.files[from] = d.files[from], nil
        d.modes[to], d.modes[from] = d.modes[from], nil
        return true
    end
    function d.remove(path)
        d.files[path] = nil
        return true
    end
    function d.mkdir()
        return true
    end
    function d.chmod(path, mode)
        d.modes[path] = mode
        return true
    end
    return d
end

-- A stand-in for clipcrypt, on disk `d`: writes the text reversed, so
-- what's on disk isn't the plain text; `held` keeps each answer until
-- release() hands it back.
local function crypt(opts, d)
    opts = opts or {}
    local c = { queue = {} }
    local function answer(fn)
        if c.held then
            c.queue[#c.queue + 1] = fn
        else
            fn()
        end
    end
    function c.seal(text, path, done)
        answer(function()
            if opts.fail then
                return done(nil, "the keychain is locked")
            end
            c.disk.files[path] = "SEALED:" .. text:reverse()
            done(true)
        end)
    end
    function c.open(path, done)
        answer(function()
            if opts.fail then
                return done(nil, "the keychain is locked")
            end
            local body = (c.disk.files[path] or ""):match("^SEALED:(.*)$")
            if not body then
                return done(nil, "bad decrypt")
            end
            done(body:reverse())
        end)
    end
    function c.release()
        local q = c.queue
        c.queue = {}
        c.held = false
        for _, fn in ipairs(q) do
            fn()
        end
    end
    c.disk = d
    return c
end

local PATH = "/c/tide/clipboard-history"
local DAY = 24 * 3600

local function clock(start)
    local c = { t = start or 1000000 }
    return c, function()
        return c.t
    end
end

local function store(d, c, now)
    local _, n = clock()
    c = c or crypt()
    c.disk = c.disk or d
    return clipstore.new("/c/tide", d, json.encode, json.decode, c, now or n)
end

-- Starts `st` on `h` with cap `max`, as tide does: the saved history
-- read back. Returns why it couldn't be, or nil.
local function start(st, h, max)
    local load_err
    st.configure(h, { history = true, max_items = max or 200 }, function(err)
        load_err = err
    end)
    return load_err
end

local function saved(d, now, max)
    local after = picker.history()
    start(store(d, nil, now), after, max)
    return after.items
end

t.test("what's copied comes back after a restart, newest first", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "first")
    picker.add(h, "second")
    st.changed(h)
    t.eq(saved(d), { "second", "first" })
end)

t.test("the file is encrypted, and yours alone", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "my address")
    st.changed(h)
    t.eq(d.files[PATH]:find("my address", 1, true), nil)
    t.eq(d.files[PATH]:sub(1, 7), "SEALED:")
    t.eq(d.modes[PATH], "600")
    t.eq(d.modes["/c/tide"], "700")
end)

t.test("a password a password manager marks is never written", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    if picker.keep({ "public.utf8-plain-text", "org.nspasteboard.ConcealedType" }) then
        picker.add(h, "hunter2")
    end
    picker.add(h, "kept")
    st.changed(h)
    t.eq(saved(d), { "kept" })
end)

t.test("a copy a week old is forgotten, in memory and on disk", function()
    local d = disk()
    local c, now = clock()
    local h = picker.history()
    local st = store(d, nil, now)
    start(st, h)
    picker.add(h, "old", now())
    st.changed(h)
    c.t = c.t + 6 * DAY
    picker.add(h, "new", now())
    st.changed(h)
    t.eq(saved(d, now), { "new", "old" }, "six days on, both")
    c.t = c.t + DAY
    t.eq(st.expire(h), true)
    t.eq(h.items, { "new" })
    t.eq(saved(d, now), { "new" }, "a week on, the old one's gone from the file too")
end)

t.test("the Clipboard settings' days are how long a copy stays", function()
    local d = disk()
    local c, now = clock()
    local h = picker.history()
    local st = store(d, nil, now)
    st.configure(h, { history = true, max_items = 100, max_age_days = 1 }, function() end)
    picker.add(h, "a", now())
    st.changed(h)
    c.t = c.t + DAY - 1
    t.eq(st.expire(h), false)
    c.t = c.t + 1
    t.eq(st.expire(h), true)
    t.eq(h.items, {})
    picker.configure(h, { history = true, max_items = 100, max_age_days = 30 })
    picker.add(h, "b", now())
    c.t = c.t + 29 * DAY
    t.eq(st.expire(h), false, "29 days under a 30-day setting")
end)

t.test("a week-old copy in the file isn't brought back, and the file loses it", function()
    local d = disk()
    local c, now = clock()
    local h = picker.history()
    local st = store(d, nil, now)
    start(st, h)
    picker.add(h, "old", now())
    st.changed(h)
    c.t = c.t + 8 * DAY
    local after = picker.history()
    start(store(d, nil, now), after)
    t.eq(after.items, {})
    t.eq(d.files[PATH]:find("dlo", 1, true), nil, "rewritten without it")
end)

t.test("copying something again starts its week afresh", function()
    local d = disk()
    local c, now = clock()
    local h = picker.history()
    local st = store(d, nil, now)
    start(st, h)
    picker.add(h, "again", now())
    st.changed(h)
    c.t = c.t + 6 * DAY
    picker.add(h, "again", now())
    st.changed(h)
    c.t = c.t + 2 * DAY
    t.eq(st.expire(h), false)
    t.eq(saved(d, now), { "again" }, "eight days after the first copy, two after the second")
end)

t.test("an entry forgotten or past the cap leaves no time behind", function()
    local h = picker.history()
    picker.configure(h, { history = true, max_items = 2 })
    picker.add(h, "a", 1)
    picker.add(h, "b", 2)
    picker.add(h, "c", 3)
    picker.forget(h, "c")
    t.eq(h.times, { b = 2 })
    picker.clear(h)
    t.eq(h.times, {})
end)

t.test("clearing the history clears the file", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "secret-ish")
    st.changed(h)
    picker.clear(h)
    st.changed(h)
    t.eq(saved(d), {})
end)

t.test("no file yet is an empty history, not an error", function()
    local h = picker.history()
    t.eq(start(store(disk()), h), nil)
    t.eq(h.items, {})
end)

t.test("a file it can't read or decrypt says so, keeps nothing, and isn't replaced until a change", function()
    local h = picker.history()
    t.eq(start(store(disk("read")), h):find("Permission denied", 1, true) ~= nil, true)
    local d = disk()
    d.files[PATH] = "SEALED:" .. ('[{"text":"kept","at":1000000}]'):reverse()
    local st = store(d, crypt({ fail = true }))
    t.eq(start(st, h), "the keychain is locked")
    t.eq(h.items, {})
    st.configure(h, { history = true, max_items = 100 }, function() end)
    t.eq(d.files[PATH]:find("tpek", 1, true) ~= nil, true, "a settings change leaves it")
end)

t.test("a failed save says why", function()
    local d = disk("rename")
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "x")
    local ok, err
    st.changed(h, function(o, e)
        ok, err = o, e
    end)
    t.eq({ ok, err }, { nil, "Operation not permitted" })
    t.eq(d.files[PATH .. ".tmp"], nil, "the half-done file is removed")
    local st2 = store(disk(), crypt({ fail = true }))
    start(st2, h)
    st2.changed(h, function(o, e)
        ok, err = o, e
    end)
    t.eq({ ok, err }, { nil, "the keychain is locked" })
end)

t.test("a copy made while the saved history is being read doesn't replace it", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "from before")
    st.changed(h)
    local c = crypt()
    c.held = true
    local after = picker.history()
    local st2 = store(d, c)
    start(st2, after)
    picker.add(after, "while reading")
    st2.changed(after)
    t.eq(d.files[PATH]:find("erofeb morf", 1, true) ~= nil, true, "not yet written over")
    c.release()
    t.eq(after.items, { "while reading", "from before" })
    t.eq(saved(d), { "while reading", "from before" })
end)

t.test("Clear history while the saved history is being read keeps it gone", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h)
    picker.add(h, "from before")
    st.changed(h)
    local c = crypt()
    c.held = true
    local after = picker.history()
    local st2 = store(d, c)
    start(st2, after)
    picker.clear(after)
    st2.cleared(after)
    c.release()
    t.eq(after.items, {})
    t.eq(saved(d), {})
end)

t.test("at start, a cap over the default gets back every saved copy", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h, 500)
    for i = 1, 300 do
        picker.add(h, "copy " .. i)
    end
    st.changed(h)
    t.eq(#saved(d, nil, 500), 300)
end)

t.test("a smaller cap trims the file, while running or stopped", function()
    local d = disk()
    local h = picker.history()
    local st = store(d)
    start(st, h, 10)
    for i = 1, 5 do
        picker.add(h, "c" .. i)
    end
    st.changed(h)
    st.configure(h, { history = true, max_items = 4 }, function() end)
    t.eq(saved(d, nil, 10), { "c5", "c4", "c3", "c2" })
    t.eq(saved(d, nil, 2), { "c5", "c4" })
    t.eq(saved(d, nil, 10), { "c5", "c4" }, "the dropped ones don't come back with a bigger cap")
end)

t.test("restored entries go behind new copies, without repeats, up to the cap", function()
    local h = picker.history()
    picker.configure(h, { history = true, max_items = 3 })
    picker.add(h, "new")
    t.eq(picker.restore(h, { "a", "new", 7, "  ", "b", "c" }), true)
    t.eq(h.items, { "new", "a", "b" })
end)

t.test("restoring keeps what was saved while the history is off", function()
    local h = picker.history()
    picker.configure(h, { history = false, max_items = 10 })
    picker.restore(h, { "kept from before" })
    t.eq(h.items, { "kept from before" })
end)

t.done("clipstore")
