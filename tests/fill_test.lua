-- The picker's Fill tab (fill.lua): snippets from tide's two files, rbw's
-- logins one row per field, the search, and the rbw call for each field.
-- rbw and typing into an app can only be checked on a Mac.

local t = require("t")
local fill = require("tide.fill")
local json = require("json")

local function files(t_)
    return function(path)
        return t_[path:match("[^/]+$")]
    end
end

t.test("snippets come from both files, the local one's name winning, by name", function()
    local s, errors = fill.load_snippets("/c/tide", files({
        ["snippets.json"] = '{"Phone": "555-0100", "Home address": "1 Main St\\nSpringfield"}',
        ["snippets.local.json"] = '{"Phone": "555-0199"}',
    }), json.decode)
    t.eq(errors, {})
    t.eq(s, { { name = "Home address", text = "1 Main St\nSpringfield" }, { name = "Phone", text = "555-0199" } })
end)

t.test("a snippets file that isn't an object of strings is said and left out", function()
    local s, errors = fill.load_snippets("/c/tide", files({
        ["snippets.json"] = '["a", "list"]',
        ["snippets.local.json"] = '{"Phone": "555"}',
    }), json.decode)
    t.eq(s, { { name = "Phone", text = "555" } })
    t.eq(errors, { "snippets.json isn't an object of name to text; its snippets are left out" })
end)

t.test("a login has a row for its username, password and 2FA code; one with no user, no username row", function()
    local rows = fill.login_rows("id-1\tgithub.com\tme@example.com\tweb\nid-3\tbank\t\tmoney\nid-2\twifi\t\t\n")
    t.eq(rows[1], { kind = "login", key = "id-1", field = "username", name = "github.com · username", sub = "me@example.com · web" })
    t.eq(rows[2].field, "password")
    t.eq(rows[3].name, "github.com · 2FA code")
    t.eq(rows[4], { kind = "login", key = "id-3", field = "password", name = "bank · password", sub = "money" },
        "an empty user doesn't swallow the folder")
    t.eq(rows[6], { kind = "login", key = "id-2", field = "password", name = "wifi · password", sub = "Bitwarden" })
    t.eq(#rows, 7)
end)

t.test("with rbw's types, a card, note or identity has no rows; a login does", function()
    local rows = fill.login_rows("id-1\tgithub.com\tme\t\tLogin\nid-2\tVisa\t\t\tCard\nid-3\tNotes\t\t\tNote\nid-4\tMe\t\t\tIdentity\n")
    t.eq(#rows, 3)
    for _, r in ipairs(rows) do
        t.eq(r.key, "id-1")
    end
    t.eq(fill.LIST[4], "id,name,user,folder,type")
    t.eq(fill.LIST_UNTYPED[4], "id,name,user,folder", "an rbw before 1.15 refuses the type field")
end)

t.test("rows search by name and detail, and a locked vault's Unlock row stays first", function()
    local entries = fill.entries({ { name = "Home address", text = "x" } }, fill.login_rows("id-1\tgithub.com\tme\tweb\n"))
    t.eq(entries[1].kind, "snippet")
    local found = fill.rows(entries, "addr")
    t.eq(#found, 1)
    t.eq(found[1].entry.name, "Home address")
    t.eq(fill.rows(entries, "github pass")[1].entry.field, "password")
    local locked = fill.rows(fill.entries({ { name = "Phone", text = "5" } }, nil, true), "phone")
    t.eq(locked[1].entry.kind, "unlock")
    t.eq(locked[2].entry.name, "Phone")
end)

t.test("each field comes from its rbw call, less rbw's newline", function()
    t.eq(fill.rbw_args({ key = "id-1", field = "password" }), { "rbw", "get", "--field", "password", "id-1" })
    t.eq(fill.rbw_args({ key = "id-1", field = "username" }), { "rbw", "get", "--field", "username", "id-1" })
    t.eq(fill.rbw_args({ key = "id-1", field = "totp" }), { "rbw", "code", "id-1" })
    t.eq(fill.value("hunter2\n"), "hunter2")
    t.eq(fill.value("a\n\n"), "a\n", "only the one newline rbw adds")
end)

t.done("fill")
