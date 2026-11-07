-- Who sent a notification, read from Notification Center's banner through
-- Accessibility (SPEC.md §14.2). Pure Lua: hs_adapter.notifications reads
-- the banner and passes its attributes here.
--
-- A banner is an element whose subrole starts with AXNotificationCenter
-- (Banner, Alert). Its AXDescription reads "App, title, body", and a
-- browser's body leads with the site: "Google Chrome, mail.google.com, New
-- message". Its AXStackingIdentifier may name the app's bundle ID
-- *(unverified on macOS 26: both are what scripts that dismiss banners
-- read)*.

local launcher = require("tide.launcher")

local M = {}

-- Whether `subrole` is a notification's banner or alert.
function M.is_banner(subrole)
    return type(subrole) == "string" and subrole:find("^AXNotificationCenter") ~= nil
        and subrole ~= "AXNotificationCenterAlertStack"
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A bare host, such as "mail.google.com", or nil.
local function host(s)
    s = trim(s):lower()
    if s:find("^[%w-]+%.[%w.-]*%a$") and not s:find("%.%.") then
        return s
    end
    return nil
end

-- The bundle ID in a stacking identifier: "bundleIdentifier=com.x.y,…", or
-- a bare bundle ID.
local function bundle_of(stacking)
    if type(stacking) ~= "string" or stacking == "" then
        return nil
    end
    local b = stacking:match("bundleIdentifier=([^,;%s]+)")
    if b then
        return b
    end
    if stacking:find("^[%w-]+%.[%w.-]+$") then
        return stacking
    end
    return nil
end

local function browser_bundle(app, name)
    for _, b in ipairs(launcher.BROWSERS) do
        if b.bundle == app or b.name == name then
            return b.bundle
        end
    end
    return nil
end

-- What a banner says of its sender: { app = bundle ID or nil, name = app
-- name or nil, site = host or nil }, or nil if it says nothing. `site` is
-- only a browser's: the first part of the body that's a host.
function M.sender(description, stacking)
    local app = bundle_of(stacking)
    local parts = {}
    for part in ((type(description) == "string" and description or "") .. ","):gmatch("([^,]*),") do
        parts[#parts + 1] = trim(part)
    end
    local name = parts[1] ~= "" and parts[1] or nil
    if not (app or name) then
        return nil
    end
    local site
    if browser_bundle(app, name) then
        app = app or browser_bundle(app, name)
        for i = 2, #parts do
            site = host(parts[i])
            if site then
                break
            end
        end
    end
    return { app = app, name = name, site = site }
end

return M
