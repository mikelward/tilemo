-- The picker on Super+C, on Hammerspoon (SPEC.md §7.2, tide SPEC.md
-- §8.4): an hs.pasteboard watcher keeps what you copy, in memory only, and
-- an hs.chooser shows it on a Clipboard tab, beside a Characters tab of
-- emoji and symbols from tide's chars.tsv, copied unchanged. Tab and
-- Shift+Tab move between the tabs; Enter copies the row and closes;
-- Shift+Delete (forward delete on a Mac) forgets a clipboard entry. What it
-- decides is picker.lua's. Not runnable outside Hammerspoon.

local picker = require("tilemo.picker")

local M = {}

-- chars.tsv sits beside this file, installed or not.
local function here()
    local src = debug.getinfo(1, "S").source
    return (src:match("^@(.*)/[^/]*$") or ".")
end

-- `tilemo` is the started tilemo module: its wm and adapter.
function M.new(tilemo)
    local self = { history = picker.history() }
    local chooser
    local tab = "clipboard"
    local chars, chars_error
    local open_keys = {}

    -- Read once, the first time the Characters tab shows.
    local function load_chars()
        if chars or chars_error then
            return
        end
        local path = here() .. "/chars.tsv"
        local f, err = io.open(path, "rb")
        if not f then
            chars_error = "Couldn't read the character list: " .. tostring(err)
            tilemo.adapter.log("picker: " .. chars_error)
            return
        end
        local text = f:read("a")
        f:close()
        local errors
        chars, errors = picker.parse_chars(text)
        for _, n in ipairs(errors) do
            tilemo.adapter.log(string.format("picker: %s line %d isn't character, name and group", path, n))
        end
    end

    local function choices(query)
        local out = {}
        if tab == "clipboard" then
            for _, r in ipairs(picker.history_rows(self.history, query)) do
                out[#out + 1] = { text = r.preview, subText = r.sub, copy = r.text }
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

    local function set_tab(t)
        tab = t
        chooser:placeholderText(picker.PLACEHOLDERS[tab])
        chooser:choices(choices(chooser:query()))
    end
    -- For CI's smoke test, as the launcher's set_scope.
    self.set_tab = set_tab

    local function release()
        tilemo.wm:hold("picker", false)
        for _, k in ipairs(open_keys) do
            k:delete()
        end
        open_keys = {}
    end

    chooser = hs.chooser.new(function(choice)
        release()
        if choice and choice.copy then
            -- Enter copies; Cmd+V pastes it where you were.
            if not hs.pasteboard.setContents(choice.copy) then
                tilemo.adapter.log("picker: couldn't put the selection on the pasteboard")
                hs.alert.show("Couldn't copy that")
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
            if picker.add(self.history, hs.pasteboard.readString()) and tilemo.on_clipboard then
                tilemo.on_clipboard()
            end
        end
    end)

    -- Open on `t` (Clipboard if none). Super+C again closes it; the other
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
        tilemo.wm:hold("picker", true)
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
                    if picker.forget(self.history, row.copy) and tilemo.on_clipboard then
                        tilemo.on_clipboard()
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
