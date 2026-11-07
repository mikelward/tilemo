-- An app's own close and quit keys, kept from a pinned window (SPEC.md
-- §6.2, §7.2): while the focused window is one of the pinnedApps of the
-- workspace it's on, Cmd+W, Cmd+Shift+W and Cmd+Q are hotkeys of tide's,
-- so the app never sees them, and a notification says the window's pinned
-- there. They're tide's Ctrl+W, Ctrl+Shift+W and Ctrl+Q, still under
-- physical Ctrl once setup-macos's rotation makes Ctrl Command (§7.1).
-- tide's fourth, Alt+F4, closes nothing on a Mac, so it's left alone.
--
-- They're hotkeys (RegisterEventHotKey), as every key of tide's is, so
-- they need no permission (§2.2). A hotkey can't be conditional on the
-- window, so they're enabled only while a pinned window has focus
-- (wm:check_pinned_focus), and every other window gets the keys as ever. A
-- press that finds focus moved on before tide heard goes on to the app,
-- as a key posted with the hotkey off. `hs` is Hammerspoon, or a stand-in.

local M = {}

M.KEYS = {
    { mods = { "cmd" }, key = "w" },
    { mods = { "cmd", "shift" }, key = "w" },
    { mods = { "cmd" }, key = "q" },
}

function M.new(hs, wm, log)
    local self = { keys = {}, on = false }
    for _, k in ipairs(M.KEYS) do
        local hk
        local ok, made = pcall(hs.hotkey.new, k.mods, k.key, function()
            if wm:pinned_key() then
                return
            end
            -- Not pinned any more: the key is the app's.
            hk:disable()
            hs.eventtap.keyStroke(k.mods, k.key, 0)
            if self.on then
                hk:enable()
            end
        end)
        if ok and made then
            hk = made
            self.keys[#self.keys + 1] = hk
        else
            log("couldn't make " .. table.concat(k.mods, "+") .. "+" .. k.key .. " for pinned windows: " .. tostring(made))
        end
    end
    -- `ws`: the workspace the focused window is pinned on, or nil.
    function self.set(ws)
        self.on = ws ~= nil
        for _, hk in ipairs(self.keys) do
            if self.on then
                hk:enable()
            else
                hk:disable()
            end
        end
    end
    wm.on_pinned_focus = self.set
    return self
end

return M
