local t = require("t")
local shots = require("tilemo.shots")

t.test("the folder is Screenshot's location, with ~ expanded, else the Desktop", function()
    t.eq(shots.folder("~/Pictures/Screenshots\n", "/Users/me"), "/Users/me/Pictures/Screenshots")
    t.eq(shots.folder("/Volumes/Shots/", "/Users/me"), "/Volumes/Shots")
    t.eq(shots.folder(nil, "/Users/me"), "/Users/me/Desktop")
    t.eq(shots.folder("", "/Users/me"), "/Users/me/Desktop")
end)

t.test("a shot is an image, not its hidden first copy", function()
    t.eq(shots.is_image("Screenshot 2026-10-30 at 10.15.32.png"), true)
    t.eq(shots.is_image("Capture 2026-10-30 at 10.15.32.JPG"), true)
    t.eq(shots.is_image(".Screenshot 2026-10-30 at 10.15.32.png"), false)
    t.eq(shots.is_image("Screenshot notes.txt"), false)
    t.eq(shots.is_image("Screenshot"), false)
end)

-- A watcher over a folder of `files`, each a path and whether macOS took
-- it as a screenshot, and what it copied.
local function watch(existing, files)
    local copied = {}
    local w = shots.new(existing, function(p)
        return files[p] or false
    end, function(p)
        copied[#copied + 1] = p
    end)
    return w, copied
end

t.test("each new screenshot goes on the clipboard once", function()
    local w, copied = watch({}, {
        ["/s/Screenshot 1.png"] = true,
        ["/s/Screenshot 2.png"] = true,
    })
    -- Written to a hidden file, renamed into place, then reported again.
    w.changed({ "/s/.Screenshot 1.png", "/s/Screenshot 1.png" })
    w.changed({ "/s/Screenshot 1.png", "/s/notes.txt" })
    -- One reported but already gone, as a deleted shot is.
    w.changed({ "/s/Screenshot 3.png", "/s/Screenshot 2.png" })
    t.eq(copied, { "/s/Screenshot 1.png", "/s/Screenshot 2.png" })
end)

t.test("a shot is what macOS took, whatever its name", function()
    local w, copied = watch({}, {
        ["/s/Bildschirmfoto 2026-10-30 um 10.15.32.png"] = true,
        ["/s/Screenshot of a receipt.png"] = false,
    })
    w.changed({ "/s/Screenshot of a receipt.png", "/s/Bildschirmfoto 2026-10-30 um 10.15.32.png" })
    t.eq(copied, { "/s/Bildschirmfoto 2026-10-30 um 10.15.32.png" })
end)

t.test("a shot tagged after it's saved goes on the clipboard when it's tagged", function()
    local files = {}
    local w, copied = watch({}, files)
    w.changed({ "/s/Screenshot 1.png" })
    files["/s/Screenshot 1.png"] = true
    w.changed({ "/s/Screenshot 1.png" })
    t.eq(copied, { "/s/Screenshot 1.png" })
end)

t.test("a shot that was already in the folder stays off the clipboard when it changes", function()
    local w, copied = watch({ "Screenshot 1.png" }, {
        ["/s/Screenshot 1.png"] = true,
        ["/s/Screenshot 2.png"] = true,
    })
    -- Edited in Preview, or tagged in Finder.
    w.changed({ "/s/Screenshot 1.png" })
    w.changed({ "/s/Screenshot 2.png" })
    t.eq(copied, { "/s/Screenshot 2.png" })
end)

t.test("a new folder in Screenshot's options is watched instead", function()
    local folders = {
        ["/a"] = { "Screenshot old.png" },
        ["/b"] = { "Screenshot old.png", "Screenshot older.png" },
    }
    local watching, stopped, on = {}, {}, {}
    local copied = {}
    local f = shots.follow(function(dir, on_paths)
        watching[#watching + 1] = dir
        on[dir] = on_paths
        return {
            stop = function()
                stopped[#stopped + 1] = dir
            end,
        }, folders[dir]
    end, function()
        return true
    end, function(p)
        copied[#copied + 1] = p
    end)
    f.folder("/a")
    on["/a"]({ "/a/Screenshot 1.png", "/a/Screenshot old.png" })
    -- The options were saved, but the folder is the same.
    f.folder("/a")
    -- setup-macos, or Screenshot's options, moved it.
    f.folder("/b")
    on["/b"]({ "/b/Screenshot older.png", "/b/Screenshot 2.png" })
    t.eq(watching, { "/a", "/b" })
    t.eq(stopped, { "/a" })
    t.eq(copied, { "/a/Screenshot 1.png", "/b/Screenshot 2.png" })
end)

t.done("shots")
