-- The setup checklist (SPEC.md §10, §11), as tileco's (tileco SPEC.md §3.4):
-- the permissions tide works with, each with its state where tide can
-- read it, and the System Settings changes that bring the Mac closer to
-- tide, each with the pane to open and what to set there. macOS settings
-- can't be changed for you, so you tick those off; the ticks are this
-- Mac's own, in hs.settings. Pure Lua: the page shows what page() gives,
-- and each item's button sends back its link's name (links.lua).

local M = {}

-- The ticked items' IDs, in hs.settings.
M.SETTINGS_KEY = "tide.setup_done"

-- Each permission: `link` the pane to open (links.PANES), `how` what it
-- buys and what to do, `ref` the spec section that wants it.
M.PERMISSIONS = {
    {
        id = "accessibility",
        title = "Accessibility for Hammerspoon",
        link = "privacy_accessibility",
        how = "Turn Hammerspoon on. Tiling, focus follows mouse and the mouse's drags need it, and a macOS update can turn it off.",
        ref = "§11.1",
    },
    {
        id = "input_monitoring",
        title = "Input Monitoring for Hammerspoon",
        link = "privacy_input_monitoring",
        how = "Only without Karabiner, for tapping Super on its own: turn Hammerspoon on if a tap doesn't open the switcher. Super+Space works without it.",
        ref = "§7.1",
    },
    {
        id = "screen_recording",
        title = "Screen Recording",
        link = "privacy_screen_recording",
        how = "tide doesn't use it: titles come through Accessibility, and screenshots use macOS's own keys. Leave it off.",
        ref = "§11.1",
    },
    {
        id = "automation",
        title = "Automation, for each browser and System Events",
        link = "privacy_automation",
        how = "macOS asks the first time the switcher lists a browser's tabs, and the first time tide's light and dark schedule switches the Mac. Allow Hammerspoon for each browser whose tabs you want, and for System Events.",
        ref = "§9, §10",
    },
    {
        id = "location",
        title = "Location Services for Hammerspoon",
        link = "privacy_location",
        how = "Only for the Wi-Fi network's name, on the bar and the Network page: macOS gives it only with this on. Everything else works without it. The first time, the button has macOS ask you; after that, it opens the list.",
        ref = "§8, §15",
    },
}

-- The settings to change by hand, ticked off when done.
M.ITEMS = {
    {
        id = "menu_bar",
        title = "Keep the menu bar shown",
        link = "control_center",
        how = "Set \"Automatically hide and show the menu bar\" to Never. tide's bar then covers it, so it doesn't slide in when the pointer reaches the top; the Apple logo's Show Menu Bar brings it up.",
        ref = "§8",
    },
    {
        id = "mission_control",
        title = "One Space per display",
        link = "desktop_dock",
        how = "Under Mission Control, keep one Space a display, keep \"Displays have separate Spaces\" on, and turn off \"Automatically rearrange Spaces based on most recent use\". Turn Stage Manager off, and set \"Click wallpaper to reveal desktop\" to \"Only in Stage Manager\".",
        ref = "§6.6",
    },
    {
        id = "tiling",
        title = "Turn off macOS's own tiling",
        link = "desktop_dock",
        how = "Under Windows, turn off \"Drag windows to screen edges to tile\" and \"Hold Option key while dragging windows to tile\", which would fight Super+drag.",
        ref = "§6.6",
    },
    {
        id = "minimize",
        title = "Minimize into the app's icon, with the Scale effect",
        link = "desktop_dock",
        how = "Turn on \"Minimize windows into application icon\" and set \"Minimize windows using\" to Scale effect, so hidden workspaces stay out of the Dock and switch quicker.",
        ref = "§6",
    },
    {
        id = "lock",
        title = "Ask for the password at once",
        link = "lock_screen",
        how = "Set \"Require password after screen saver begins or display is turned off\" to Immediately, as tide locks.",
        ref = "§10",
    },
    {
        id = "chrome_notifications",
        title = "Allow Chrome's notifications",
        link = "notifications",
        how = "Under Google Chrome, turn on \"Allow notifications\", so they come through Notification Center, not Chrome's own popups.",
        ref = "§5.1",
    },
}

M.STATE_LABELS = {
    on = "On",
    off = "Off",
    not_needed = "Not needed",
    unknown = "Can't tell",
}

-- A permission's state from what tide knows, `facts`: `accessibility`,
-- true or false as macOS says, nil if it couldn't be asked; `karabiner`,
-- true while Super comes from Karabiner. macOS gives Hammerspoon no way to
-- read Input Monitoring or Automation without asking for them, so those
-- are "unknown" where they're needed.
function M.permission_state(id, facts)
    facts = facts or {}
    if id == "accessibility" then
        if facts.accessibility == nil then
            return "unknown"
        end
        return facts.accessibility and "on" or "off"
    elseif id == "input_monitoring" then
        return facts.karabiner and "not_needed" or "unknown"
    elseif id == "screen_recording" then
        return "not_needed"
    elseif id == "location" then
        -- hs.location.authorizationStatus()'s answer: "undefined" until
        -- macOS has asked, which leaves it off.
        if facts.location == "authorized" then
            return "on"
        elseif facts.location == "denied" or facts.location == "restricted" or facts.location == "undefined" then
            return "off"
        end
        return "unknown"
    end
    return "unknown"
end

-- Whether a permission's button, `link`, should have macOS ask for it
-- rather than open its list: Location Services', until macOS has asked,
-- as Hammerspoon isn't in the list before.
function M.ask_first(link, facts)
    return link == "privacy_location" and (facts or {}).location == "undefined"
end

local known = {}
for _, item in ipairs(M.ITEMS) do
    known[item.id] = true
end

-- What's done, from what's stored: only ticks for items that still exist,
-- once each, in the items' order.
function M.progress(stored)
    local done = {}
    for _, id in ipairs(type(stored) == "table" and stored or {}) do
        done[id] = true
    end
    local ticked = {}
    for _, item in ipairs(M.ITEMS) do
        if done[item.id] then
            ticked[#ticked + 1] = item.id
        end
    end
    return { done = ticked, left = #M.ITEMS - #ticked }
end

-- The stored list with `id` ticked (`on`) or not. Returns nil and why for
-- an item the checklist doesn't have.
function M.ticked(stored, id, on)
    if not known[id] then
        return nil, "the checklist has no item " .. tostring(id)
    end
    local out = {}
    for _, d in ipairs(M.progress(stored).done) do
        if d ~= id then
            out[#out + 1] = d
        end
    end
    if on then
        out[#out + 1] = id
    end
    return out
end

-- The checklist as the page takes it: { permissions, items, left }, each
-- permission with its state and the state's label, each item with done.
function M.page(facts, stored)
    local perms = {}
    for i, p in ipairs(M.PERMISSIONS) do
        local state = M.permission_state(p.id, facts)
        perms[i] = {
            id = p.id, title = p.title, how = p.how, ref = p.ref, link = p.link,
            state = state, label = M.STATE_LABELS[state],
        }
    end
    local progress = M.progress(stored)
    local done = {}
    for _, id in ipairs(progress.done) do
        done[id] = true
    end
    local items = {}
    for i, item in ipairs(M.ITEMS) do
        items[i] = {
            id = item.id, title = item.title, how = item.how, ref = item.ref, link = item.link,
            done = done[item.id] == true,
        }
    end
    return { permissions = perms, items = items, left = progress.left }
end

-- What `tide doctor` says of the permissions: a line for each that's
-- off and needed, none when they're fine.
-- Said at start, and by the doctor, while macOS hides the menu bar: tide's
-- bar can't cover a menu bar that slides in over everything.
M.MENU_BAR_NOTICE = "The menu bar is set to hide, so it slides in over tide's bar whenever the pointer reaches the top:"
    .. " in System Settings, Control Center, set \"Automatically hide and show the menu bar\" to Never (or run setup and log out)."

function M.doctor(facts)
    facts = facts or {}
    local lines = {}
    if M.permission_state("accessibility", facts) == "off" then
        lines[#lines + 1] = "Accessibility is off for Hammerspoon, so nothing tiles, focus doesn't follow the mouse and the mouse's drags do nothing:"
            .. " turn it on in Privacy & Security, from the settings window's Setup checklist."
    end
    if facts.menu_bar_hidden then
        lines[#lines + 1] = M.MENU_BAR_NOTICE
    end
    return lines
end

return M
