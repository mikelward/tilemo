-- The picker's Fill tab on Super+Shift+V (SPEC.md §9.1), as tide's (tide
-- SPEC.md §8.4, bin/tide-fill): your snippets from tide's snippets.json
-- and snippets.local.json, and a row each for every Bitwarden login's
-- username, password and 2FA code, through rbw. Enter types the value into
-- the app you were in; nothing goes on the pasteboard. Plain Lua: what
-- picker_hs.lua runs and reads.

local launcher = require("tide.launcher")

local M = {}

M.FILES = { "snippets.json", "snippets.local.json" }

-- The snippets in the two files' texts (nil for a file that isn't there),
-- the local file's name winning, sorted by name, as [{name, text}], and
-- what's wrong with either. `decode` is hs.json.decode.
function M.load_snippets(dir, read, decode)
    local merged, errors = {}, {}
    for _, name in ipairs(M.FILES) do
        local text = read(dir .. "/" .. name)
        if text then
            local ok, t = pcall(decode, text)
            local good = ok and type(t) == "table" and next(t) ~= 1
            if good then
                for k, v in pairs(t) do
                    if type(k) ~= "string" or type(v) ~= "string" then
                        good = false
                    end
                end
            end
            if good then
                for k, v in pairs(t) do
                    merged[k] = v
                end
            else
                errors[#errors + 1] = name .. " isn't an object of name to text; its snippets are left out"
            end
        end
    end
    local out = {}
    for k, v in pairs(merged) do
        out[#out + 1] = { name = k, text = v }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, errors
end

-- Tab-separated fields, keeping empty ones: "a\t\tb" is a, "" and b.
local function split_tabs(line)
    local out = {}
    for f in (line .. "\t"):gmatch("([^\t]*)\t") do
        out[#out + 1] = f
    end
    return out
end

-- The listing, with each entry's type to leave out cards, notes and
-- identities; rbw before 1.15 has no type field and refuses it, so then the
-- plain listing, every entry kept.
M.LIST = { "rbw", "list", "--fields", "id,name,user,folder,type" }
M.LIST_UNTYPED = { "rbw", "list", "--fields", "id,name,user,folder" }

-- Either listing's output, as rows: one each for a login's username (when
-- it has one), password and 2FA code. An entry whose type isn't Login has
-- none of them, so no rows.
function M.login_rows(text)
    local rows = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local f = split_tabs(line)
        local id, name, user, folder, kind = f[1], f[2] or "", f[3] or "", f[4] or "", f[5] or ""
        if id and id ~= "" and (kind == "" or kind == "Login") then
            local detail = folder ~= "" and folder or "Bitwarden"
            if user ~= "" then
                detail = user .. " · " .. detail
            end
            if user ~= "" then
                rows[#rows + 1] = { kind = "login", key = id, field = "username", name = name .. " · username", sub = detail }
            end
            rows[#rows + 1] = { kind = "login", key = id, field = "password", name = name .. " · password", sub = detail }
            rows[#rows + 1] = { kind = "login", key = id, field = "totp", name = name .. " · 2FA code", sub = detail }
        end
    end
    return rows
end

-- The row standing for the logins while rbw is locked.
M.UNLOCK = { kind = "unlock", key = "-", field = "-", name = "Unlock Bitwarden", sub = "rbw asks for your master password" }

-- All the rows: the snippets, then the logins, or the Unlock row.
function M.entries(snippets, logins, locked)
    local out = {}
    if locked then
        out[1] = M.UNLOCK
    end
    for _, s in ipairs(snippets) do
        out[#out + 1] = { kind = "snippet", key = s.name, field = "text", name = s.name, sub = "Snippet" }
    end
    for _, l in ipairs(logins or {}) do
        out[#out + 1] = l
    end
    return out
end

-- The rows for `query`, best first (launcher.score over the name and its
-- detail), the Unlock row always first.
function M.rows(entries, query)
    local q = query or ""
    local rows = {}
    for order, e in ipairs(entries) do
        local score = e.kind == "unlock" and math.huge or launcher.score(q, e.name .. " " .. e.sub)
        if score then
            rows[#rows + 1] = { entry = e, score = score, order = order }
        end
    end
    if q:find("%S") then
        table.sort(rows, function(a, b)
            if a.score ~= b.score then
                return a.score > b.score
            end
            return a.order < b.order
        end)
    end
    return rows
end

-- The rbw arguments that print a login's field: get --field for the
-- username and password, code for the 2FA code.
function M.rbw_args(entry)
    if entry.field == "totp" then
        return { "rbw", "code", entry.key }
    end
    return { "rbw", "get", "--field", entry.field, entry.key }
end

-- A value as rbw printed it, less the one newline it adds.
function M.value(out)
    return ((out or ""):gsub("\n$", ""))
end

return M
