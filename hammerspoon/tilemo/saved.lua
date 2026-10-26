-- Reading what tilemo saved in hs.settings, under keys that were timo's
-- before the rename: a key never written as tilemo's is read under its old
-- name once and copied across, so a renamed install keeps its workspaces.
-- The old key is left as it was, in case of a downgrade.

local M = {}

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

return M
