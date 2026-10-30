-- Screenshots (SPEC.md §10): macOS saves each to the folder set in
-- Screenshot's options, and tilemo puts it on the clipboard too, as tide
-- does both. This says which of the folder's files to copy. Pure Lua; the
-- adapter reads the folder, watches it and tells a shot from other files.

local M = {}

M.KINDS = { png = true, jpg = true, jpeg = true, heic = true, tiff = true, gif = true, pdf = true, bmp = true }

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- The folder, from `defaults read com.apple.screencapture location`'s
-- output, or nil when it's unset: then macOS uses the Desktop.
function M.folder(location, home)
    local dir = trim(location)
    if dir == "" then
        return home .. "/Desktop"
    end
    dir = dir:gsub("^~", home):gsub("/+$", "")
    return dir
end

-- Whether `name` could be a shot: an image, and not the hidden file macOS
-- writes one to first.
function M.is_image(name)
    if name:sub(1, 1) == "." then
        return false
    end
    local ext = name:match("%.(%w+)$")
    return ext ~= nil and M.KINDS[ext:lower()] == true
end

-- A watcher's state. `existing` names the files already in the folder, so
-- that editing one later doesn't put it on the clipboard. `is_shot(path)`
-- says whether a file is there and macOS took it as a screenshot, whatever
-- its name: macOS translates the name, and Screenshot's options can change
-- it. `copy(path)` puts a shot on the clipboard. Each is copied once,
-- though the folder reports it more than once (written, renamed, tagged).
-- The folder holds them all, so a name is enough to tell them apart.
function M.new(existing, is_shot, copy)
    local self = { is_shot = is_shot, copy = copy, done = {} }
    for _, name in ipairs(existing or {}) do
        self.done[name] = true
    end

    -- Some files in the folder changed.
    function self.changed(paths)
        for _, path in ipairs(paths or {}) do
            local name = path:match("([^/]+)$")
            if name and not self.done[name] and M.is_image(name) and self.is_shot(path) then
                self.done[name] = true
                self.copy(path)
            end
        end
    end

    return self
end

-- Screenshot's folder can change while tilemo runs, from its options or
-- setup-macos. This follows it: `watch(dir, on_paths)` starts watching a
-- folder and gives back the watcher, which has stop(), and the names of the
-- files already in it. `is_shot` and `copy` are as for new().
function M.follow(watch, is_shot, copy)
    local self = {}

    -- Screenshot's folder is now `dir`.
    function self.folder(dir)
        if dir == self.dir then
            return
        end
        if self.watcher then
            self.watcher:stop()
        end
        local watcher, existing = watch(dir, function(paths)
            self.state.changed(paths)
        end)
        self.dir, self.watcher, self.state = dir, watcher, M.new(existing, is_shot, copy)
    end

    return self
end

return M
