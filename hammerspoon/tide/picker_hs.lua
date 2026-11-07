-- The picker on Super+V, and its Fill tab on Super+Shift+V, on Hammerspoon (SPEC.md §7.2, tide SPEC.md
-- §8.4): an hs.pasteboard watcher keeps what you copy, in memory only, and
-- an hs.chooser shows it on a Clipboard tab, beside a Characters tab of
-- emoji and symbols from tide's chars.tsv, copied unchanged. Tab and
-- Shift+Tab move between the tabs; Enter copies the row, closes, and
-- pastes it with Cmd+V into the app that was in front;
-- Shift+Delete (forward delete on a Mac) forgets a clipboard entry. What it
-- decides is picker.lua's. Not runnable outside Hammerspoon.

local picker = require("tide.picker")
local fill = require("tide.fill")

local M = {}

-- chars.tsv sits beside this file, installed or not.
local function here()
    local src = debug.getinfo(1, "S").source
    return (src:match("^@(.*)/[^/]*$") or ".")
end

-- `tide` is the started tide module: its wm and adapter.
function M.new(tide)
    local self = { history = picker.history() }
    local chooser
    local tab = "clipboard"
    local chars, chars_error
    local open_keys = {}
    -- The app in front when the picker opened, which Enter pastes into.
    local target
    -- The Fill tab's rows, listed afresh each time it shows; names only,
    -- never a secret. `listing` counts listings, so an old one that ends
    -- late is dropped.
    local fill_entries, fill_loading, listing = {}, false, 0

    -- rbw, run through runenv for the login environment's PATH, as the app
    -- keys' helpers are (hs_adapter's launch).
    local function rbw(args, done)
        local runenv = (os.getenv("HOME") or "") .. "/scripts/runenv"
        local full = { runenv }
        for _, a in ipairs(args) do
            full[#full + 1] = a
        end
        return tide.adapter.run("/usr/bin/env", full, done)
    end

    -- Read once, the first time the Characters tab shows.
    local function load_chars()
        if chars or chars_error then
            return
        end
        local path = here() .. "/chars.tsv"
        local f, err = io.open(path, "rb")
        if not f then
            chars_error = "Couldn't read the character list: " .. tostring(err)
            tide.adapter.log("picker: " .. chars_error)
            return
        end
        local text = f:read("a")
        f:close()
        local errors
        chars, errors = picker.parse_chars(text)
        for _, n in ipairs(errors) do
            tide.adapter.log(string.format("picker: %s line %d isn't character, name and group", path, n))
        end
    end

    local function choices(query)
        local out = {}
        if tab == "clipboard" then
            for _, r in ipairs(picker.history_rows(self.history, query)) do
                out[#out + 1] = { text = r.preview, subText = r.sub, copy = r.text }
            end
        elseif tab == "fill" then
            for _, r in ipairs(fill.rows(fill_entries, query)) do
                local e = r.entry
                out[#out + 1] = { text = e.name, subText = e.sub, fill_kind = e.kind, fill_key = e.key, fill_field = e.field }
            end
            if #out == 0 and fill_loading then
                return { { text = "Listing…", valid = false } }
            end
        else
            load_chars()
            for _, c in ipairs(picker.character_rows(chars or {}, query)) do
                out[#out + 1] = { text = c.char .. "  " .. c.name, subText = picker.character_sub(c), copy = c.char }
            end
        end
        if #out == 0 then
            out[1] = { text = picker.empty_text(tab, query, tab == "characters" and chars_error or nil), valid = false }
        end
        return out
    end

    local function refresh()
        if chooser:isVisible() then
            chooser:choices(choices(chooser:query()))
        end
    end

    -- The Fill tab's rows: the snippets at once, then rbw's logins, or the
    -- Unlock row while it's locked, since its pinentry can't take the
    -- keyboard while the chooser holds it. Without rbw (runenv's 127), the
    -- snippets alone.
    local function list_fill()
        listing = listing + 1
        local mine = listing
        local snippets, errors = fill.load_snippets(tide.clock_dir, tide.adapter.read, tide.adapter.decode)
        for _, e in ipairs(errors) do
            tide.adapter.log("picker: " .. e)
        end
        fill_entries, fill_loading = fill.entries(snippets), true
        local started = rbw({ "rbw", "unlocked" }, function(code)
            if mine ~= listing then
                return
            end
            if code == 127 then
                fill_loading = false
                refresh()
                return
            end
            if code ~= 0 then
                fill_entries, fill_loading = fill.entries(snippets, nil, true), false
                refresh()
                return
            end
            local function listed(lcode, err, out)
                if mine ~= listing then
                    return
                end
                if lcode ~= 0 then
                    tide.adapter.log("picker: rbw couldn't list the logins: " .. tostring(err))
                end
                fill_entries = fill.entries(snippets, lcode == 0 and fill.login_rows(out) or nil)
                fill_loading = false
                refresh()
            end
            rbw(fill.LIST, function(lcode, err, out)
                if lcode ~= 0 and mine == listing then
                    -- An rbw before 1.15, without the type field.
                    if not rbw(fill.LIST_UNTYPED, listed) then
                        fill_loading = false
                    end
                    return
                end
                listed(lcode, err, out)
            end)
        end)
        if not started then
            fill_loading = false
        end
    end

    local function set_tab(t)
        tab = t
        if t == "fill" then
            list_fill()
        end
        chooser:placeholderText(picker.PLACEHOLDERS[tab])
        chooser:choices(choices(chooser:query()))
    end

    -- Types `text` into `into`, the app that was in front, once it's in
    -- front again: keystrokes, never the pasteboard, so no clipboard
    -- history keeps a password.
    local function type_into(into, text)
        if not into or not into:activate() then
            tide.adapter.log("picker: couldn't bring the app back to type into")
            hs.alert.show("Couldn't type that")
            return
        end
        hs.eventtap.keyStrokes(text, into)
    end

    local function fill_chosen(choice, into)
        if choice.fill_kind == "unlock" then
            rbw({ "rbw", "unlock" }, function(code, err)
                if code == 0 then
                    self.show("fill")
                else
                    tide.adapter.log("picker: rbw couldn't unlock: " .. tostring(err))
                    hs.alert.show("Bitwarden stayed locked")
                end
            end)
        elseif choice.fill_kind == "snippet" then
            for _, s in ipairs(fill.load_snippets(tide.clock_dir, tide.adapter.read, tide.adapter.decode)) do
                if s.name == choice.fill_key then
                    type_into(into, s.text)
                    return
                end
            end
            hs.alert.show("No snippet named " .. choice.fill_key)
        else
            rbw(fill.rbw_args({ key = choice.fill_key, field = choice.fill_field }), function(code, err, out)
                if code == 0 and fill.value(out) ~= "" then
                    type_into(into, fill.value(out))
                else
                    tide.adapter.log("picker: rbw couldn't get the " .. choice.fill_field .. ": " .. tostring(err))
                    hs.alert.show("Couldn't get that from Bitwarden")
                end
            end)
        end
    end
    -- For CI's smoke test, as the launcher's set_scope.
    self.set_tab = set_tab

    local function release()
        tide.wm:hold("picker", false)
        for _, k in ipairs(open_keys) do
            k:delete()
        end
        open_keys = {}
    end

    chooser = hs.chooser.new(function(choice)
        release()
        local into = target
        target = nil
        if choice and choice.fill_kind then
            fill_chosen(choice, into)
        elseif choice and choice.copy then
            -- Enter copies, then pastes it where you were: Cmd+V, sent to
            -- the app that was in front, once it's in front again.
            if not hs.pasteboard.setContents(choice.copy) then
                tide.adapter.log("picker: couldn't put the selection on the pasteboard")
                hs.alert.show("Couldn't copy that")
            elseif into then
                if into:activate() then
                    hs.eventtap.keyStroke({ "cmd" }, "v", 0, into)
                else
                    tide.adapter.log("picker: couldn't bring " .. tostring(into:name()) .. " back to paste; it's on the clipboard")
                end
            end
        end
    end)
    chooser:queryChangedCallback(function(query)
        chooser:choices(choices(query))
    end)

    -- Every copy, unless it's marked concealed or transient, as password
    -- managers mark passwords. The types are read when the watcher calls,
    -- so a copy replaced within that moment is judged by its replacement's.
    self.watcher = hs.pasteboard.watcher.new(function()
        if picker.keep(hs.pasteboard.contentTypes()) then
            if picker.add(self.history, hs.pasteboard.readString()) and tide.on_clipboard then
                tide.on_clipboard()
            end
        end
    end)

    -- Open on `t` (Clipboard if none). Super+V again closes it; the other
    -- tab's key, from the switcher's IPC, moves there.
    function self.show(t)
        t = t or "clipboard"
        if chooser:isVisible() then
            if t == tab then
                chooser:cancel()
            else
                set_tab(t)
            end
            return
        end
        tide.wm:hold("picker", true)
        target = hs.application.frontmostApplication()
        open_keys = {
            hs.hotkey.bind({}, "tab", function()
                set_tab(picker.next_tab(tab))
            end),
            hs.hotkey.bind({ "shift" }, "tab", function()
                set_tab(picker.next_tab(tab, true))
            end),
            hs.hotkey.bind({ "shift" }, "forwarddelete", function()
                local row = chooser:selectedRowContents()
                if tab == "clipboard" and row and row.copy then
                    if picker.forget(self.history, row.copy) and tide.on_clipboard then
                        tide.on_clipboard()
                    end
                    chooser:choices(choices(chooser:query()))
                end
            end),
        }
        chooser:query("")
        set_tab(t)
        chooser:show()
    end

    -- The row shown `n`th, and closing it as Esc does: for CI's smoke test.
    function self.row(n)
        return chooser:selectedRowContents(n)
    end

    function self.cancel()
        chooser:cancel()
    end

    return self
end

return M
