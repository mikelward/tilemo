-- Where each setting tide can't change itself is changed (SPEC.md §1,
-- §15): the settings window's buttons, each opening a System Settings pane
-- or a helper's own window. Pure Lua. The page shows each button by its
-- label and sends back its name, and open() opens what the name stands
-- for, so the page can't open just any URL.

local M = {}

local function pane(id)
    return "x-apple.systempreferences:" .. id
end

-- System Settings' panes, by the IDs macOS 13 and later give them. CI's
-- smoke test checks each is a pane on its Mac (ci/hs_smoke.lua).
M.PANE_IDS = {
    displays = "com.apple.Displays-Settings.extension",
    sound = "com.apple.Sound-Settings.extension",
    network = "com.apple.Network-Settings.extension",
    wifi = "com.apple.wifi-settings-extension",
    bluetooth = "com.apple.BluetoothSettings",
    mouse = "com.apple.Mouse-Settings.extension",
    trackpad = "com.apple.Trackpad-Settings.extension",
    keyboard = "com.apple.Keyboard-Settings.extension",
    battery = "com.apple.Battery-Settings.extension",
    appearance = "com.apple.Appearance-Settings.extension",
    notifications = "com.apple.Notifications-Settings.extension",
    date_time = "com.apple.Date-Time-Settings.extension",
    lock_screen = "com.apple.Lock-Screen-Settings.extension",
    login_items = "com.apple.LoginItems-Settings.extension",
    desktop_dock = "com.apple.Desktop-Settings.extension",
    control_center = "com.apple.ControlCenter-Settings.extension",
    privacy = "com.apple.settings.PrivacySecurity.extension",
}

-- Privacy & Security's lists, for the setup checklist (checklist.lua): the
-- pane, at the list named after "?".
M.PRIVACY_ANCHORS = {
    accessibility = "Privacy_Accessibility",
    input_monitoring = "Privacy_ListenEvent",
    screen_recording = "Privacy_ScreenCapture",
    automation = "Privacy_Automation",
    location = "Privacy_LocationServices",
}

M.PANES = {}
for name, id in pairs(M.PANE_IDS) do
    M.PANES[name] = pane(id)
end
for name, anchor in pairs(M.PRIVACY_ANCHORS) do
    M.PANES["privacy_" .. name] = pane(M.PANE_IDS.privacy) .. "?" .. anchor
end

-- Helpers' own windows, for open(1): by bundle ID (-b) or app name (-a),
-- with `args` for the app as it starts.
M.APPS = {
    -- --show starts it with its settings window up; a running one brings
    -- the window forward on the reopen open sends (LinearMouse
    -- AppDelegate.swift).
    linearmouse = { bundle = "com.lujjjh.LinearMouse", args = { "--show" } },
    -- Karabiner-Elements.app is its settings window.
    karabiner = { app = "Karabiner-Elements" },
}

-- Each section's buttons, in the window's order: the name sent back, and
-- the label, which names the pane as System Settings does.
M.SECTIONS = {
    { id = "displays", links = { { "displays", "Displays settings" } } },
    { id = "sound", links = { { "sound", "Sound settings" } } },
    { id = "network", links = { { "network", "Network settings" } } },
    { id = "bluetooth", links = { { "bluetooth", "Bluetooth settings" } } },
    { id = "mouse", links = { { "mouse", "Mouse settings" }, { "linearmouse", "LinearMouse settings" } } },
    { id = "trackpad", links = { { "trackpad", "Trackpad settings" } } },
    { id = "keyboard", links = { { "keyboard", "Keyboard settings" }, { "karabiner", "Karabiner settings" } } },
    { id = "power", links = { { "battery", "Battery settings" } } },
    { id = "appearance", links = { { "appearance", "Appearance settings" } } },
    { id = "muted", links = { { "notifications", "Notifications settings" } } },
    { id = "clocks", links = { { "date_time", "Date & Time settings" } } },
    { id = "idle", links = { { "lock_screen", "Lock settings" } } },
    { id = "startup", links = { { "login_items", "Login Items settings" } } },
}

-- The buttons as the page takes them: { section, name, label } each.
function M.page_list()
    local out = {}
    for _, s in ipairs(M.SECTIONS) do
        for _, l in ipairs(s.links) do
            out[#out + 1] = { section = s.id, name = l[1], label = l[2] }
        end
    end
    return out
end

-- Open what `name` stands for: a pane through `adapter.open_url`, or a
-- helper through `adapter.open_helper`. Returns false, having opened
-- nothing, for a name that's neither.
function M.open(name, adapter)
    if type(name) ~= "string" then
        return false
    end
    if M.PANES[name] then
        adapter.open_url(M.PANES[name])
        return true
    end
    if M.APPS[name] then
        adapter.open_helper(M.APPS[name])
        return true
    end
    return false
end

return M
