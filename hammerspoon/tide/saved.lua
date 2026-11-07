-- Reading what tide saved in hs.settings, under keys that were timo's or
-- tilemo's before a rename: a key never written as tide's is read under its
-- old name once and copied across, so a renamed install keeps its
-- workspaces. The old key is left as it was, in case of a downgrade.

local M = {}

-- What tilemo saved, under keys starting "tilemo.", copied to the same keys
-- starting "tide." where tide hasn't saved one, before anything reads them.
-- `store` is hs.settings, with getKeys(). Returns how many were copied.
function M.move_prefix(store, from, to)
    local copied = 0
    for _, key in ipairs(store.getKeys() or {}) do
        if key:sub(1, #from) == from then
            local new = to .. key:sub(#from + 1)
            if store.get(new) == nil then
                store.set(new, store.get(key))
                copied = copied + 1
            end
        end
    end
    return copied
end

-- `store` is hs.settings, or anything with its get(key) and set(key, value).
function M.get(store, key, old_key)
    local v = store.get(key)
    if v == nil and old_key then
        v = store.get(old_key)
        if v ~= nil then
            store.set(key, v)
        end
    end
    return v
end

-- wm:snapshot() as the settings store takes it: window ids as strings,
-- and every other field as it is, so the workspace showing and the names'
-- order are kept along with the windows.
function M.form(snap)
    local out = {}
    for k, v in pairs(snap) do
        out[k] = v
    end
    out.windows = {}
    for id, v in pairs(snap.windows or {}) do
        out.windows[tostring(id)] = v
    end
    return out
end

return M
