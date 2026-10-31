-- Writing a file whole or not at all: to a temporary file beside it, then
-- renamed over it, so a reader never sees half of it and a failed write
-- leaves the old file as it was. Pure Lua; `fs` stands in for io and os in
-- tests.

local M = {}

local REAL = { open = io.open, rename = os.rename, remove = os.remove }

-- Writes `text` to `path`: true, or nil and why not. With `mode` (as
-- chmod takes it, "600"), the file has that mode before it takes the
-- path's place, so it's never readable more widely; `fs.chmod` sets it.
function M.write(path, text, fs, mode)
    fs = fs or REAL
    local tmp = path .. ".tmp"
    local f, err = fs.open(tmp, "w")
    if not f then
        return nil, err
    end
    local wrote, werr = f:write(text)
    -- Writes are buffered, so a full disk may only show on closing.
    local closed, cerr = f:close()
    if not wrote or not closed then
        fs.remove(tmp)
        return nil, werr or cerr
    end
    if mode then
        local ok, merr = fs.chmod(tmp, mode)
        if not ok then
            fs.remove(tmp)
            return nil, merr
        end
    end
    local renamed, rerr = fs.rename(tmp, path)
    if not renamed then
        fs.remove(tmp)
        return nil, rerr
    end
    return true
end

return M
