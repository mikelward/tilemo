-- A smoke test that runs inside a real Hammerspoon, on CI's macOS runner.
-- The fake in tests/ can't tell whether an hs.* function tide calls exists
-- in the Hammerspoon people install, so this checks that, then starts tide,
-- checks its bar is up, opens and closes the dashboard, and tiles a few
-- windows below the bar. GitHub's macOS runners come with Accessibility
-- granted, so the tiling is real.
--
-- ci/hs-smoke.sh points ~/.hammerspoon/init.lua at this file, with
-- TIDE_SMOKE_OUT set to where the results go.

local bar = require("tide.bar")
local dashboard = require("tide.dashboard")
local layout = require("tide.layout")

local out_path = TIDE_SMOKE_OUT
local failed = false

-- Each line goes out as it's made, so a hang still shows how far it got.
local function say(fmt, ...)
    local line = string.format(fmt, ...)
    local f, err = io.open(out_path, "a")
    if not f then
        print("tide smoke: can't write " .. out_path .. ": " .. tostring(err))
        return
    end
    f:write(line, "\n")
    f:close()
end

local function fail(fmt, ...)
    failed = true
    say("FAIL " .. fmt, ...)
end

local function finish()
    say(failed and "RESULT fail" or "RESULT ok")
    -- Hammerspoon's os.exit is hs._exit, which only quits the app when its
    -- second argument is true.
    hs._exit(true, true)
end

say("Hammerspoon %s, %s", hs.processInfo.version, _VERSION)

-- Every hs.x.y tide names in its source, resolved here. hs loads its
-- extensions on first touch, so walking the path is the real lookup.
local dir = hs.configdir .. "/tide"
local seen = {}
for file in hs.fs.dir(dir) do
    if file:match("%.lua$") then
        local f = assert(io.open(dir .. "/" .. file))
        for line in f:lines() do
            local code = line:gsub("%-%-.*$", "")
            for path, stop in code:gmatch("%f[%w_](hs%.[%a_][%w_%.]*)()") do
                path = path:gsub("%.$", "")
                -- An assignment sets a slot that may start out nil
                -- (hs.shutdownCallback), so only its parent must exist.
                if code:sub(stop):match("^%s*=[^=]") then
                    path = path:match("^(.*)%.[^%.]+$")
                end
                if not seen[path] then
                    seen[path] = file
                end
            end
        end
        f:close()
    end
end
local paths = {}
for path in pairs(seen) do
    paths[#paths + 1] = path
end
table.sort(paths)
for _, path in ipairs(paths) do
    local v = _G
    for key in path:gmatch("[^%.]+") do
        local ok, next_v = pcall(function()
            return v[key]
        end)
        v = ok and next_v or nil
        if v == nil then
            break
        end
    end
    if v == nil then
        fail("%s (in %s) doesn't exist", path, seen[path])
    end
end
say("checked %d hs.* names", #paths)

-- Open TextEdit windows and check tide tiles them where its layout says
-- (SPEC.md §5). TextEdit, because `open` can give it several windows
-- without asking for Automation, which a runner can't grant.
local APP = "com.apple.TextEdit"
local WANT = 3
local SLACK = 2
local TILE_WAIT = 20

local function app_windows(wm)
    local out = {}
    for id, w in pairs(wm.windows) do
        if w.app == APP and not w.floating then
            out[#out + 1] = id
        end
    end
    return out
end

-- Where each tiled window is against where tide's layout puts it, or nil
-- and why not yet.
local function tiling_misses(wm)
    if #app_windows(wm) < WANT then
        return nil, string.format("%d of %d TextEdit windows tiled", #app_windows(wm), WANT)
    end
    local misses, checked = {}, 0
    for _, s in ipairs(wm:screens()) do
        local n = wm:current_ws()
        local ws = wm:part(n, s.uuid)
        local ids = wm:tiled(n, s.uuid)
        local boxes = ws and layout.arrange(ws, s.area, ids, wm.layout) or {}
        for _, id in ipairs(ids) do
            local want = boxes[id]
            local st = wm.a.state(id)
            local got = st and st.frame
            if want and got then
                if wm.windows[id].app == APP then
                    checked = checked + 1
                end
                local off = math.max(math.abs(got.x - want.x), math.abs(got.y - want.y),
                    math.abs(got.w - want.w), math.abs(got.h - want.h))
                if off > SLACK then
                    misses[#misses + 1] = string.format("window %s at %d,%d %dx%d, want %d,%d %dx%d", tostring(id),
                        got.x, got.y, got.w, got.h, want.x, want.y, want.w, want.h)
                end
            end
        end
    end
    if checked < WANT then
        return nil, string.format("%d of %d TextEdit windows on a shown workspace", checked, WANT)
    end
    return misses
end

-- The bar: a strip along the top of each display, its page loaded, and the
-- tiling area starting below it.
local function check_bar()
    if not tide.bar then
        fail("bar: tide started without its bar")
        return
    end
    local frames = tide.bar.frames()
    local n = 0
    for _, s in ipairs(tide.adapter.screens()) do
        -- Where bar.place puts it: over a menu bar that shows (as on CI's
        -- Mac), from the top of the screen; macOS must let it stay there.
        local want, below = bar.place(s, bar.HEIGHT)
        local got = frames[s.uuid]
        local v = tide.bar.views[s.uuid]
        if not got then
            fail("bar: none on display %s", s.uuid)
        else
            local off = math.max(math.abs(got.x - want.x), math.abs(got.y - want.y),
                math.abs(got.w - want.w), math.abs(got.h - want.h))
            if off > SLACK then
                fail("bar: at %d,%d %dx%d, want %d,%d %dx%d", got.x, got.y, got.w, got.h,
                    want.x, want.y, want.w, want.h)
            end
            if got.hidden then
                fail("bar: hidden on display %s with nothing full screen", s.uuid)
            end
            if not (v and v.ready) then
                fail("bar: its page on display %s didn't load (got as far as %s)", s.uuid, v and v.nav or "nothing")
            end
            n = n + 1
        end
        local tiling = tide.wm:screen_by_uuid(s.uuid).area
        if tiling.y ~= below.y then
            fail("bar: tiling starts at y=%d, want %d", tiling.y, below.y)
        end
    end
    -- Which status items this Mac has; the network one is always drawn.
    local items = {}
    for k in pairs(tide.bar.icons) do
        items[#items + 1] = k
    end
    table.sort(items)
    if not tide.bar.icons.network then
        fail("bar: no network status item")
    end
    -- A chip's app icon, from a bundle every Mac has.
    local finder = tide.bar.icon_of("com.apple.finder")
    if type(finder) ~= "string" or not finder:find("^data:image/png;base64,") then
        fail("bar: no icon for Finder (got %s)", tostring(finder))
    end
    -- Anything a page reported: a script error or a failed load.
    for _, e in ipairs(tide.bar.errors) do
        fail("bar: %s", e)
    end
    say("bar up on %d display(s), with %s", n, table.concat(items, ", "))
end

-- In a real WebKit, every point of each bar's two groups, top to bottom,
-- is some item's click target, not the bar between them (SPEC.md §8): from
-- the left edge to the last chip, and from the clocks to the right edge.
-- With the pointer there, that target, and only it, shows as hovered.
local TARGETS_JS = [==[
(() => {
  const bar = document.getElementById("bar");
  const chips = document.getElementById("workspaces").children;
  const clocks = document.getElementById("clocks").getBoundingClientRect();
  const spans = [[0, chips[chips.length - 1].getBoundingClientRect().right], [clocks.left, innerWidth]];
  const dead = [];
  for (const [from, to] of spans) {
    for (let x = Math.ceil(from); x < to; x++) {
      for (const y of [0, innerHeight / 2, innerHeight - 1]) {
        const e = document.elementFromPoint(x, y);
        if (!e || e === bar || e.id === "left" || e.id === "workspaces" || e.id === "right" || e.id === "icons") {
          dead.push(x + "," + y);
          continue;
        }
        // A status item that only shows something (the camera) isn't hovered.
        tide.pointer(x, y);
        const lit = document.querySelectorAll(".hover");
        const shows = !e.closest("button, #clocks, #title");
        if (shows ? lit.length !== 0 : lit.length !== 1 || !e.closest(".hover")) dead.push("hover " + x + "," + y);
      }
    }
  }
  tide.pointer(null);
  // The corner is the Apple logo's, which opens the Apple menu, as on a
  // Mac's own menu bar.
  if (!document.elementFromPoint(0, innerHeight / 2)?.closest("#apple")) dead.push("corner, not the Apple logo");
  return dead.length ? dead.slice(0, 10).join(" ") : "ok";
})()
]==]

local function check_bar_targets(after)
    local _, v = next(tide.bar and tide.bar.views or {})
    if not (v and v.ready) then
        -- check_bar has said why.
        after()
        return
    end
    v.view:evaluateJavaScript(TARGETS_JS, function(result, err)
        if dashboard.js_failed(err) then
            fail("bar: couldn't check its click targets: %s", hs.inspect(err))
        elseif result ~= "ok" then
            fail("bar: clicks at %s reach no item", tostring(result))
        else
            say("bar: every click in its groups reaches an item")
        end
        after()
    end)
end

-- The chips as WebKit draws them (bar.html, as tide's are): on a hidden
-- strip of chips, 7px corners on each, no fill on an empty one, and an
-- occupied, current and urgent one each in its color, the urgent one amber
-- even when it's the current one too. Each color is the page's own
-- --chip-* property, which `make check-tide` compares with tide's palette.
-- Gives back JSON: what's wrong, and the occupied fill.
local CHIPS_JS = [==[
(() => {
  const nav = document.createElement("nav");
  nav.style.cssText = "position: absolute; visibility: hidden";
  const probe = document.createElement("div");
  nav.append(probe);
  const color = (v) => {
    probe.style.backgroundColor = `var(${v})`;
    return getComputedStyle(probe).backgroundColor;
  };
  const chip = (cls) => {
    const b = document.createElement("button");
    b.className = cls;
    b.textContent = "in";
    nav.append(b);
    return b;
  };
  const chips = { empty: chip(""), occupied: chip("occupied"), current: chip("current occupied"), urgent: chip("current occupied urgent") };
  document.body.append(nav);
  const bad = [];
  const is = (what, got, want) => {
    if (got !== want) bad.push(`${what} ${got}, not ${want}`);
  };
  const style = (b) => getComputedStyle(b);
  for (const [name, b] of Object.entries(chips)) is(`${name}'s corners`, style(b).borderTopLeftRadius, "7px");
  is("empty's fill", style(chips.empty).backgroundColor, "rgba(0, 0, 0, 0)");
  is("occupied's fill", style(chips.occupied).backgroundColor, color("--chip-surface"));
  is("current's fill", style(chips.current).backgroundColor, color("--chip-current"));
  is("urgent current's fill", style(chips.urgent).backgroundColor, color("--chip-urgent-bg"));
  is("urgent current's ring", style(chips.urgent).borderTopColor, color("--chip-urgent-ring"));
  const occupied = style(chips.occupied).backgroundColor;
  nav.remove();
  return JSON.stringify({ bad, occupied });
})()
]==]

-- The chips in the bar's light look, then its dark one, which the webview's
-- dark mode brings: the occupied fill changes when the page takes it, so
-- the dark check waits for that, up to a deadline.
local CHIPS_WAIT = 5

local function check_bar_chips(after)
    local _, v = next(tide.bar and tide.bar.views or {})
    if not (v and v.ready) then
        -- check_bar has said why.
        after()
        return
    end
    local view = v.view
    local was = view:darkMode()
    local function finish()
        view:darkMode(was)
        after()
    end
    local function run(done)
        view:evaluateJavaScript(CHIPS_JS, function(result, err)
            if dashboard.js_failed(err) then
                fail("bar: couldn't check its chips: %s", hs.inspect(err))
                finish()
                return
            end
            done(hs.json.decode(result) or { bad = { "no result" } })
        end)
    end
    view:darkMode(false)
    run(function(light)
        if #light.bad > 0 then
            fail("bar, light: %s", table.concat(light.bad, "; "))
        end
        view:darkMode(true)
        local started = hs.timer.secondsSinceEpoch()
        local function dark_check()
            run(function(dark)
                if dark.occupied == light.occupied and hs.timer.secondsSinceEpoch() - started < CHIPS_WAIT then
                    -- A global, like smoke_timer, so it isn't collected.
                    smoke_chips_timer = hs.timer.doAfter(0.25, dark_check)
                    return
                end
                if dark.occupied == light.occupied then
                    fail("bar: dark mode left an occupied chip %s, as in light", tostring(light.occupied))
                elseif #dark.bad > 0 then
                    fail("bar, dark: %s", table.concat(dark.bad, "; "))
                elseif #light.bad == 0 then
                    say("bar: chips drawn as tide's, light (occupied %s) and dark (%s)", light.occupied, dark.occupied)
                end
                finish()
            end)
        end
        dark_check()
    end)
end

-- Wait for every bar page to load, up to a deadline, then check the bar
-- and call `next`.
local BAR_WAIT = 15

local function wait_for_bar(next)
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_bar_poll = hs.timer.doEvery(0.5, function()
        local ready = tide.bar ~= nil
        for _, v in pairs(tide.bar and tide.bar.views or {}) do
            ready = ready and v.ready
        end
        if ready or hs.timer.secondsSinceEpoch() - started > BAR_WAIT then
            smoke_bar_poll:stop()
            check_bar()
            check_bar_targets(function()
                check_bar_chips(next)
            end)
        end
    end)
end

-- The launcher's Attention scope lists a window marked for attention, by
-- its title, with its app and workspace (SPEC.md §9).
-- A row's text as a plain string: the rows are hs.styledtext (SPEC.md §9).
local function plain(v)
    if type(v) == "userdata" and v.getString then
        return v:getString()
    end
    return v
end

local function check_launcher_attention()
    local wm = tide.wm
    local id
    for _, w in ipairs(app_windows(wm)) do
        if w ~= tide.adapter.focused() then
            id = w
        end
    end
    if not id then
        fail("launcher: no TextEdit window to mark for attention")
        return
    end
    wm.attention:activated(id, wm.windows[id].app)
    local ok, err = xpcall(function()
        tide.launcher.show()
        local scope = "launch"
        repeat
            scope = require("tide.launcher").next_scope(scope)
            tide.launcher.set_scope(scope)
        until scope == "attention"
        local row = tide.launcher.row(1) or {}
        tide.launcher.cancel()
        local want = tide.adapter.title(id)
        if plain(row.text) ~= want or not tostring(plain(row.subText)):find("TextEdit", 1, true) then
            fail("launcher: Attention shows %s (%s), not %s", tostring(plain(row.text)), tostring(plain(row.subText)), want)
        else
            say("launcher: Attention lists %s (%s)", plain(row.text), plain(row.subText))
        end
        -- The Windows tab lists every window, with its app and workspace
        -- (SPEC.md §9).
        tide.launcher.show("windows")
        local listed = false
        for n = 1, 50 do
            local r = tide.launcher.row(n)
            if not r then
                break
            end
            listed = listed or (plain(r.text) == want and tostring(plain(r.subText)):find("TextEdit", 1, true) ~= nil)
        end
        tide.launcher.cancel()
        if not listed then
            fail("launcher: the Windows tab doesn't list %s", tostring(want))
        else
            say("launcher: Windows lists %s", want)
        end
        -- Return on a header leaves the switcher open (SPEC.md §9): Actions
        -- with nothing typed starts with its Session header.
        tide.launcher.show("actions")
        local header = tide.launcher.row(1) or {}
        tide.launcher.choose(1)
        local stayed = tide.launcher.is_open()
        tide.launcher.cancel()
        if header.valid ~= false then
            fail("launcher: Actions' first row is %s, not a header", tostring(plain(header.text)))
        elseif not stayed then
            fail("launcher: Return on a header closed the switcher")
        else
            say("launcher: Return on a header leaves the switcher open")
        end
        -- The bar's logo closes the switcher on any tab, and opens it on
        -- Launch (SPEC.md §8).
        tide.launcher.show("windows")
        tide.launcher.toggle()
        local closed = not tide.launcher.is_open()
        tide.launcher.toggle()
        local opened = tide.launcher.is_open() and tide.launcher.scope() == "launch"
        tide.launcher.cancel()
        if not (closed and opened) then
            fail("launcher: the logo's toggle %s", closed and "didn't open it on Launch" or "didn't close it on Windows")
        else
            say("launcher: the logo closes the switcher and opens it on Launch")
        end
    end, debug.traceback)
    if not ok then
        fail("launcher: %s", err)
    end
end

-- The settings window's Switcher row (SPEC.md §9.2): tileco's launcher
-- takes the keys at once, kept on this Mac, and the switcher comes back the
-- same way. Its page loads as it's made, hidden, so a key only shows it:
-- how long the first open and a reopen take to answer goes in the log.
local PAGE_WAIT = 15

local function check_launcher_page(after)
    local key = require("tide.launcherpage").SETTINGS_KEY
    local switcher = tide.launcher
    local function done()
        local back = tide.set_launcher("chooser")
        if not back or tide.launcher == switcher or tide.launcher_choice ~= "chooser" then
            fail("launcher: switching back to the switcher left %s", tostring(tide.launcher_choice))
        end
        hs.settings.clear(key)
        after()
    end
    local made = hs.timer.secondsSinceEpoch()
    local to, why = tide.set_launcher("dashboard")
    local page = tide.launcher
    if not to then
        fail("launcher: couldn't switch to tileco's: %s", tostring(why))
        done()
        return
    elseif page == switcher or page.row() ~= nil or tide.launcher_choice ~= "dashboard" or hs.settings.get(key) ~= "dashboard" then
        fail("launcher: switching to tileco's left %s, kept as %s", tostring(tide.launcher_choice), tostring(hs.settings.get(key)))
        done()
        return
    end
    -- Open on `tab`, and hear which scope the page is on once it has
    -- filled: heard(ms, lua_ms, scope, stayed), out of the page's own
    -- callback, as the switch back deletes the page. lua_ms is show()'s own
    -- share: the rows gathered and the window shown, before the page fills.
    -- stayed says it was still open as the page answered: a window that
    -- took the focus meanwhile closes it, and WebKit slows a hidden page.
    local function open(tab, heard)
        local asked = hs.timer.secondsSinceEpoch()
        page.show(tab)
        local lua_ms = math.floor((hs.timer.secondsSinceEpoch() - asked) * 1000)
        if not page.is_open() then
            fail("launcher: tileco's launcher didn't open on %s", tab)
            done()
            return
        end
        -- The page's own clock says where the time went: from the key to
        -- the page hearing tide.open, drawing it, and answering this.
        page.evaluate([[JSON.stringify({ scope: tide.scope(), at: Date.now(), opened: tide.opened })]],
            function(answer, err)
            local back = hs.timer.secondsSinceEpoch()
            local ms = math.floor((back - asked) * 1000)
            local stayed = page.is_open()
            tide.adapter.after(0, function()
                page.cancel()
                -- A string is evaluate()'s own; a table is { code = 0 } on
                -- success (dashboard.js_failed).
                local got = type(answer) == "string" and hs.json.decode(answer) or nil
                if type(err) == "string" or dashboard.js_failed(err) or not got then
                    fail("launcher: tileco's launcher on %s: %s", tab, hs.inspect(err))
                    done()
                    return
                end
                local o = got.opened or {}
                local t0 = asked * 1000
                say("launcher: on %s, the page heard the open at %s ms, %s, ran it by %s ms and answered at %s ms; "
                    .. "Lua had the answer at %d ms", tab, tostring(o.heard and math.floor(o.heard - t0)),
                    tostring(o.visibility), tostring(o.ran and math.floor(o.ran - t0)),
                    tostring(got.at and math.floor(got.at - t0)), ms)
                heard(ms, lua_ms, got.scope, stayed)
            end)
        end)
    end
    local waited = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_poll, so it isn't collected.
    smoke_page_poll = hs.timer.doEvery(0.1, function()
        local now = hs.timer.secondsSinceEpoch()
        if not page.ready() and now - waited <= PAGE_WAIT then
            return
        end
        smoke_page_poll:stop()
        if not page.ready() then
            fail("launcher: tileco's launcher page didn't load in %ds", PAGE_WAIT)
            done()
            return
        end
        say("launcher: tileco's launcher page loaded, hidden, in %d ms", math.floor((now - made) * 1000))
        -- The Lua side's parts, each as an open runs it: the apps read
        -- from disk, then that with each window's title and app, then the
        -- rows made from them.
        local launcher_hs = require("tide.launcher_hs")
        local function ms(fn)
            local t0 = hs.timer.secondsSinceEpoch()
            local out = fn()
            return math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000), out
        end
        local scan_ms, scanned = ms(launcher_hs.scan)
        local collector_ms, collect = ms(function()
            return launcher_hs.collector(tide)
        end)
        local rows_ms, rows = ms(function()
            return collect({})
        end)
        local placed = 0
        for _, w in pairs(tide.wm.windows) do
            if w.ws then
                placed = placed + 1
            end
        end
        say("launcher: its Lua side reads %d apps in %d ms, and with %d windows in %d ms, and makes %d rows in %d ms",
            #scanned, scan_ms, placed, collector_ms, #rows, rows_ms)
        local before = tide.adapter.focused()
        local function shown(stayed)
            return stayed and "open" or "closed"
        end
        open("launch", function(first, first_lua, scope, first_stayed)
            if scope ~= "launch" then
                fail("launcher: tileco's launcher opened on %s, not launch", tostring(scope))
                done()
                return
            end
            -- Esc gave the focus back to the window it came from: once
            -- that window has it, as a person's next key would find it,
            -- open it again.
            local closed = hs.timer.secondsSinceEpoch()
            smoke_page_poll = hs.timer.doEvery(0.05, function()
                local back = tide.adapter.focused() == before
                if not back and hs.timer.secondsSinceEpoch() - closed <= 2 then
                    return
                end
                smoke_page_poll:stop()
                local settled = math.floor((hs.timer.secondsSinceEpoch() - closed) * 1000)
                open("windows", function(again, again_lua, scope2, again_stayed)
                    local parts = {}
                    for _, st in ipairs(page.steps or {}) do
                        parts[#parts + 1] = st.name .. " " .. st.ms
                    end
                    say("launcher: the reopen's Lua steps, in ms: %s", table.concat(parts, ", "))
                    if scope2 ~= "tabs" then
                        fail("launcher: tileco's launcher reopened on %s, not tabs", tostring(scope2))
                    else
                        say("launcher: tileco's launcher answers in %d ms (%d in Lua, %s as it answered), and %d ms "
                            .. "(%d in Lua, %s) reopened once the focus was back, %s in %d ms", first, first_lua,
                            shown(first_stayed), again, again_lua, shown(again_stayed),
                            back and "back" or "not back", settled)
                        say("launcher: the settings window switches to tileco's launcher and back")
                    end
                    done()
                end)
            end)
        end)
    end)
end

-- Super+Space and Esc as a person presses them, for each launcher: how
-- long from the key until the launcher is open, and from Esc until it's
-- closed, polled every 10 ms, so a busy Hammerspoon shows in the times.
-- hs.eventtap.keyStroke waits between key down and up, holding Hammerspoon
-- that long, so it's 1 ms here.
local KEY_WAIT = 3
-- The most an attention poll may take with a launcher open: a few windows'
-- titles, the Dock's badges and a redraw of the bar, about 200 ms on CI's
-- Mac, and nothing that waits out a timeout, 300 ms an ask.
local POLL_LIMIT = 500

-- What one read of the displays costs, call by call: the adapter's
-- screens() asks for each display's ID and frames.
local function time_displays()
    local function ms(fn)
        local t0 = hs.timer.absoluteTime()
        local r = fn()
        return (hs.timer.absoluteTime() - t0) / 1e6, r
    end
    local all_ms, all = ms(hs.screen.allScreens)
    local parts = { string.format("allScreens %.1f", all_ms) }
    for name, fn in pairs({ id = "id", getUUID = "getUUID", frame = "frame", fullFrame = "fullFrame" }) do
        local total = 0
        for _, s in ipairs(all) do
            total = total + ms(function()
                return s[fn](s)
            end)
        end
        parts[#parts + 1] = string.format("%s %.1f", name, total)
    end
    table.sort(parts)
    say("displays: one read of %d, in ms: %s", #all, table.concat(parts, ", "))
end

local function check_launcher_keys(after)
    time_displays()
    local key = require("tide.launcherpage").SETTINGS_KEY
    local results = {}
    -- Poll until `cond()`, then done(ms, met): met only within KEY_WAIT,
    -- since a Hammerspoon held past it polls first once it's done.
    local function until_(cond, done)
        local t0 = hs.timer.secondsSinceEpoch()
        smoke_key_poll = hs.timer.doEvery(0.01, function()
            local met = cond()
            local elapsed = hs.timer.secondsSinceEpoch() - t0
            if met or elapsed > KEY_WAIT then
                smoke_key_poll:stop()
                done(math.floor(elapsed * 1000), met and elapsed <= KEY_WAIT)
            end
        end)
    end
    local before = tide.adapter.focused()
    -- How many times the window manager synced and retiled meanwhile: a
    -- launcher showing or hiding moves no window.
    local counts = { sync = 0, retile = 0 }
    for _, name in ipairs({ "sync", "retile" }) do
        local real = tide.wm[name]
        tide.wm[name] = function(...)
            counts[name] = counts[name] + 1
            return real(...)
        end
    end
    local function counted()
        local out = string.format("%d syncs, %d retiles", counts.sync, counts.retile)
        counts.sync, counts.retile = 0, 0
        return out
    end
    -- Every call that held Hammerspoon 50 ms or more meanwhile, by name:
    -- the adapter's, through which each Accessibility read goes, the window
    -- manager's and focus follows mouse's. A stall none of them owns is
    -- Hammerspoon's or WebKit's own.
    local slow = {}
    -- And every call's time, by name, however short: many quick reads can
    -- add up to a slow one.
    local totals = {}
    local function timed(name, fn)
        return function(...)
            local t0 = hs.timer.absoluteTime()
            local r = table.pack(fn(...))
            local ns = hs.timer.absoluteTime() - t0
            local ms = ns // 1000000
            if ms >= 50 then
                slow[#slow + 1] = { name = name, ms = ms }
            end
            local total = totals[name] or { n = 0, ns = 0 }
            total.n, total.ns = total.n + 1, total.ns + ns
            totals[name] = total
            return table.unpack(r, 1, r.n)
        end
    end
    -- The names that took longest in all since last asked, with how many
    -- calls.
    local function busiest()
        local list = {}
        for name, total in pairs(totals) do
            list[#list + 1] = { name = name, n = total.n, ms = total.ns / 1e6 }
        end
        totals = {}
        table.sort(list, function(x, y)
            return x.ms > y.ms
        end)
        local out = {}
        for i = 1, math.min(#list, 12) do
            out[#out + 1] = string.format("%s %d× %.1f", list[i].name, list[i].n, list[i].ms)
        end
        return #out > 0 and table.concat(out, ", ") or "none"
    end
    for name, fn in pairs(tide.adapter) do
        if type(fn) == "function" then
            tide.adapter[name] = timed("adapter." .. name, fn)
        end
    end
    for _, name in ipairs({ "focused", "focused_window", "moved", "retitled", "minimized", "unminimized", "schedule",
        "sync", "retile", "reconcile", "focus_window", "raise_floats", "changed", "ask_next", "hold", "own_window" }) do
        if tide.wm[name] then
            tide.wm[name] = timed("wm." .. name, tide.wm[name])
        end
    end
    -- What a change redraws: the bar, the tray and the workspace's file.
    for owner, names in pairs({ bar = { "update" }, tray = { "update" } }) do
        for _, name in ipairs(names) do
            local o = tide[owner]
            if o and o[name] then
                o[name] = timed(owner .. "." .. name, o[name])
            end
        end
    end
    if tide.publish_workspace then
        tide.publish_workspace = timed("publish_workspace", tide.publish_workspace)
    end
    -- What an open reads: the apps on disk, the rows made from them and
    -- the windows, and the browsers asked for their tabs.
    local launcher_hs = require("tide.launcher_hs")
    for _, name in ipairs({ "scan", "fetch_tabs" }) do
        launcher_hs[name] = timed("launcher_hs." .. name, launcher_hs[name])
    end
    local collector = launcher_hs.collector
    launcher_hs.collector = timed("launcher_hs.collector", function(...)
        return timed("launcher_hs.collect", collector(...))
    end)
    local ffm = tide.wm.ffm
    for _, name in ipairs({ "move", "resync", "remember", "hit", "settled", "under_float", "prefer_dialog", "focus" }) do
        if ffm and ffm[name] then
            ffm[name] = timed("ffm." .. name, ffm[name])
        end
    end
    local function slowest()
        table.sort(slow, function(x, y)
            return x.ms > y.ms
        end)
        local out = {}
        for i = 1, math.min(#slow, 10) do
            out[#out + 1] = slow[i].name .. " " .. slow[i].ms
        end
        slow = {}
        return #out > 0 and table.concat(out, ", ") or "none"
    end
    local function try(choice, next)
        local ok, why = tide.set_launcher(choice)
        if not ok then
            fail("launcher keys: couldn't switch to %s: %s", choice, tostring(why))
            next()
            return
        end
        local launcher = tide.launcher
        -- Shown once already, as tide's launcher has been by the time a
        -- person presses the key: a new hs.chooser's first show makes its
        -- window.
        if not launcher.ready then
            launcher.show("launch")
            launcher.cancel()
        end
        -- Loaded, and the focus back where it was, as a person's key finds
        -- it.
        until_(function()
            return (not launcher.ready or launcher.ready()) and tide.adapter.focused() == before
        end, function(_, settled)
            if not settled then
                fail("launcher keys: %s didn't settle before its key", choice)
            end
            counted()
            busiest()
            local t0 = hs.timer.secondsSinceEpoch()
            local lag
            hs.eventtap.keyStroke(tide.super, "space", 1000)
            -- How long Hammerspoon is busy after the key: a timer for now
            -- fires once it's free.
            smoke_key_lag = hs.timer.doAfter(0, function()
                lag = math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000)
            end)
            until_(function()
                return launcher.is_open()
            end, function(open_ms, opened)
                if not opened then
                    fail("launcher keys: Super+Space didn't open %s in %ds", choice, KEY_WAIT)
                    next()
                    return
                end
                local open_lag = lag
                lag = nil
                local open_work = counted()
                -- Each step of the open, as the launcher timed it, and the
                -- calls that took longest in all meanwhile.
                local parts = {}
                for _, st in ipairs(launcher.steps or {}) do
                    parts[#parts + 1] = st.name .. " " .. st.ms
                end
                say("launcher keys: %s's open steps, in ms: %s", choice,
                    #parts > 0 and table.concat(parts, ", ") or "none kept")
                say("launcher keys: while %s opened, the busiest calls, in all, in ms: %s", choice, busiest())
                -- The attention poll, as its timer runs it every two
                -- seconds while you look at the launcher: one that holds
                -- Hammerspoon then holds Esc too.
                slowest()
                busiest()
                local p0 = hs.timer.absoluteTime()
                tide.wm:poll_attention()
                local poll_ms = (hs.timer.absoluteTime() - p0) // 1000000
                local poll_slow = slowest()
                say("launcher keys: with %s open, the attention poll takes %d ms; its calls of 50 ms or more: %s",
                    choice, poll_ms, poll_slow)
                say("launcher keys: with %s open, the poll's busiest calls, in all, in ms: %s", choice, busiest())
                if poll_ms >= POLL_LIMIT then
                    fail("launcher keys: with %s open, the attention poll held Hammerspoon for %d ms", choice, poll_ms)
                end
                local t1 = hs.timer.secondsSinceEpoch()
                hs.eventtap.keyStroke({}, "escape", 1000)
                smoke_key_lag = hs.timer.doAfter(0, function()
                    lag = math.floor((hs.timer.secondsSinceEpoch() - t1) * 1000)
                end)
                until_(function()
                    return not launcher.is_open()
                end, function(close_ms, closed)
                    if not closed then
                        fail("launcher keys: Esc didn't close %s in %ds", choice, KEY_WAIT)
                        launcher.cancel()
                    end
                    -- What the window manager did after the close, once the
                    -- focus is back: a sync waits 50 ms for more changes.
                    local function report(painted, heard_esc)
                        say("launcher keys: %s's calls of 50 ms or more, in ms: %s", choice, slowest())
                        results[#results + 1] = string.format(
                            "%s opens in %d ms (busy %s ms, %s%s) and Esc closes it in %d ms (busy %s ms, %s%s)",
                            choice, open_ms, tostring(open_lag), open_work,
                            painted and (", painted at " .. painted .. " ms") or "", close_ms, tostring(lag),
                            counted(), heard_esc and (", the page heard it at " .. heard_esc .. " ms")
                                or (launcher.evaluate and ", tide's, not the page's" or ""))
                        next()
                    end
                    until_(function()
                        return tide.adapter.focused() == before
                    end, function()
                        smoke_key_lag = hs.timer.doAfter(0.3, function()
                            if not launcher.evaluate then
                                report(nil, nil)
                                return
                            end
                            -- When the page had painted the open, from
                            -- Super+Space, and heard Esc, from Esc, by its
                            -- clock.
                            launcher.evaluate("JSON.stringify({ esc: tide.esc, opened: tide.opened })",
                                function(answer)
                                tide.adapter.after(0, function()
                                    local got = type(answer) == "string" and hs.json.decode(answer) or {}
                                    local painted = got.opened and got.opened.painted
                                    -- Esc is tide's while it's open, so the
                                    -- page shouldn't hear it at all.
                                    local heard = got.esc and got.esc >= t1 * 1000
                                    report(painted and tostring(math.floor(painted - t0 * 1000)) or "not",
                                        heard and tostring(math.floor(got.esc - t1 * 1000)) or nil)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end
    try("dashboard", function()
        try("chooser", function()
            hs.settings.clear(key)
            say("launcher keys: %s", table.concat(results, "; "))
            after()
        end)
    end)
end

-- The dim (SPEC.md §5.6): with the TextEdit windows tiled and one of them
-- focused, a layer is up over the focused window's display, its hole cut
-- where that window is. Waits for the dim's redraw, up to a deadline.
local DIM_WAIT = 5
local function check_dim(after)
    local started = hs.timer.secondsSinceEpoch()
    local function near(p, q)
        return math.abs(p - q) <= 1
    end
    local function why_not()
        local id = tide.adapter.focused()
        local st = id and tide.adapter.state(id)
        if not st then
            return "no window has focus"
        end
        local why = "no layer is showing"
        for _, c in pairs(tide.dim.canvases) do
            local hole, full = c[2], c:frame()
            if c:isShowing() and hole then
                local f, w = hole.frame, st.frame
                if near(f.x + full.x, w.x) and near(f.y + full.y, w.y) and near(f.w, w.w) and near(f.h, w.h) then
                    return nil
                end
                why = string.format("the hole is at %d,%d %dx%d, the focused window at %d,%d %dx%d",
                    f.x + full.x, f.y + full.y, f.w, f.h, w.x, w.y, w.w, w.h)
            end
        end
        return why
    end
    -- A global, like smoke_poll, so it isn't collected.
    smoke_dim = hs.timer.doEvery(0.2, function()
        local why = why_not()
        if why and hs.timer.secondsSinceEpoch() - started <= DIM_WAIT then
            return
        end
        smoke_dim:stop()
        if why then
            fail("dim: %s after %ds", why, DIM_WAIT)
        else
            say("dim: a layer, its hole on the focused window")
        end
        after()
    end)
end

local function check_tiling()
    if not hs.accessibilityState() then
        fail("tiling: Hammerspoon doesn't have Accessibility on this runner")
        finish()
        return
    end
    local dir = os.getenv("TMPDIR") or "/tmp"
    local files = {}
    for i = 1, WANT do
        local path = string.format("%s/tide-smoke-%d.txt", dir, i)
        local f, err = io.open(path, "w")
        if not f then
            fail("tiling: can't write %s: %s", path, tostring(err))
            finish()
            return
        end
        f:close()
        files[#files + 1] = "'" .. path .. "'"
    end
    local output, opened = hs.execute("open -a TextEdit " .. table.concat(files, " ") .. " 2>&1")
    if not opened then
        fail("tiling: couldn't open TextEdit: %s", output)
        finish()
        return
    end
    -- TextEdit and tide's watchers take a moment; wait for them, up to a
    -- deadline, rather than a fixed time.
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_poll = hs.timer.doEvery(0.5, function()
        local misses, why = tiling_misses(tide.wm)
        local done = misses and #misses == 0
        if done or hs.timer.secondsSinceEpoch() - started > TILE_WAIT then
            smoke_poll:stop()
            if done then
                say("%d TextEdit windows tiled", WANT)
                check_dim(function()
                    check_launcher_attention()
                    check_launcher_page(function()
                        check_launcher_keys(finish)
                    end)
                end)
                return
            elseif not misses then
                fail("tiling: %s after %ds", why, TILE_WAIT)
            else
                for _, m in ipairs(misses) do
                    fail("tiling: %s", m)
                end
            end
            finish()
        end
    end)
end

-- An app key whose helper fails says so. ci/hs-smoke.sh puts a stand-in
-- runenv in ~/scripts, and a helper that waits on a FIFO, then exits 3;
-- collecting garbage before letting it go checks tide still hears it.
local HELPER_WAIT = 15

local function check_failing_helper(next)
    local notes = {}
    local notify = tide.adapter.notify
    tide.adapter.notify = function(text)
        notes[#notes + 1] = text
        notify(text)
    end
    tide.adapter.launch({ run = "tide-smoke-fail" })
    collectgarbage("collect")
    collectgarbage("collect")
    -- In the background: if the helper's gone, nothing reads the FIFO,
    -- and the write would wait for ever.
    hs.execute("echo go >\"$HOME/scripts/tide-smoke-go\" &")
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_helper_poll = hs.timer.doEvery(0.5, function()
        local heard
        for _, n in ipairs(notes) do
            if n:find("tide-smoke-fail failed: no such app", 1, true) then
                heard = n
            end
        end
        if heard or hs.timer.secondsSinceEpoch() - started > HELPER_WAIT then
            smoke_helper_poll:stop()
            tide.adapter.notify = notify
            if heard then
                say("a failing app key says so: %s", heard)
            else
                fail("app keys: a failing helper wasn't reported in %ds (heard: %s)", HELPER_WAIT,
                    table.concat(notes, " | "))
            end
            next()
        end
    end)
end

-- Print takes a screenshot with macOS's own keys, which saves it to
-- Screenshot's folder (ci/hs-smoke.sh points it at a temporary one), and
-- tide puts it on the clipboard too (SPEC.md §10).
local SHOT_WAIT = 20

local function shots_dir()
    local out = hs.execute("/usr/bin/defaults read com.apple.screencapture location 2>/dev/null")
    return require("tide.shots").folder(out, os.getenv("HOME") or "")
end

local function check_screenshot(next)
    local dir = shots_dir()
    local before = hs.pasteboard.changeCount()
    tide.wm:act("screenshot", "screen")
    local started = hs.timer.secondsSinceEpoch()
    local file
    -- A global, like smoke_timer, so it isn't collected.
    smoke_shot_poll = hs.timer.doEvery(0.5, function()
        for name in hs.fs.dir(dir) do
            if name:match("%.png$") and name:sub(1, 1) ~= "." then
                file = name
            end
        end
        local copied = hs.pasteboard.changeCount() ~= before and hs.pasteboard.readImage() ~= nil
        if (file and copied) or hs.timer.secondsSinceEpoch() - started > SHOT_WAIT then
            smoke_shot_poll:stop()
            if not file then
                fail("screenshot: nothing saved in %s after %ds", dir, SHOT_WAIT)
            elseif not copied then
                fail("screenshot: %s saved but not put on the clipboard", file)
            else
                say("screenshot saved as %s and copied", file)
            end
            next()
        end
    end)
end

-- Moving Screenshot's folder while tide runs, as setup-macos does: tide
-- follows it, and a shot saved there is copied too.
local function check_moved_screenshot(next)
    local dir = hs.execute("/usr/bin/mktemp -d"):gsub("%s+$", "")
    hs.execute("/usr/bin/defaults write com.apple.screencapture location '" .. dir .. "'")
    local started = hs.timer.secondsSinceEpoch()
    -- A global, like smoke_timer, so it isn't collected.
    smoke_move_poll = hs.timer.doEvery(0.5, function()
        if tide.shots.dir == dir then
            smoke_move_poll:stop()
            say("screenshot folder followed to a new one")
            check_screenshot(next)
        elseif hs.timer.secondsSinceEpoch() - started > SHOT_WAIT then
            smoke_move_poll:stop()
            fail("screenshot: still watching %s after the folder moved to %s", tostring(tide.shots.dir), dir)
            next()
        end
    end)
end

-- Start tide as init.lua would, then open and close the dashboard.
local ok, err = xpcall(function()
    tide = require("tide")
    -- TextEdit is one of "in"'s apps here, so its windows tile on "in"
    -- rather than wait on the name prompt, which nothing answers in CI.
    tide.start({ home_apps = { "TextEdit" } })
end, debug.traceback)
if not ok then
    fail("tide.start: %s", err)
    finish()
    return
end
say("tide started")
-- The runner has no Karabiner and no LinearMouse: tide doctor says so,
-- and what each costs.
do
    local report = tostring(tide.doctor())
    if not report:find("Karabiner isn't running", 1, true) then
        fail("tide.doctor() says %s", report)
    else
        say("tide doctor: no Karabiner, as expected")
    end
    if tide.linearmouse ~= "missing" or not report:find("LinearMouse isn't installed", 1, true) then
        fail("LinearMouse: %s, Launch Services' path %s; tide.doctor() says %s", tostring(tide.linearmouse),
            hs.inspect(hs.application.pathForBundleID("com.lujjjh.LinearMouse")), report)
    else
        say("tide doctor: no LinearMouse, as expected")
    end
end
-- The settings window's Shortcuts: the keys registered with Super on
-- Option, and only Super+Print left out, since Alt+Print has its chord,
-- and maybe the overview's keys.
do
    local s = tide.shortcuts
    local unexpected = {}
    -- The runner's macOS still holds Ctrl+Up and Ctrl+Down for Mission
    -- Control, which setup-macos frees on a real Mac (SPEC.md §6.9), so the
    -- overview's keys may be left out too.
    local may_fail = { ["Super+Print"] = true, ["Ctrl+Up"] = true, ["Ctrl+Down"] = true }
    for _, f in ipairs(s and s.failed or {}) do
        if not may_fail[f.keys] then
            unexpected[#unexpected + 1] = f.keys .. ": " .. f.why
        end
    end
    if not s or #s.binds < 40 or #unexpected > 0 then
        fail("shortcuts: %d listed; didn't register: %s", s and #s.binds or 0, table.concat(unexpected, "; "))
    else
        say("shortcuts: %d listed, %d left out", #s.binds, #s.failed)
    end
end
-- conf's Karabiner rules, switched in JavaScriptCore as on a Mac with
-- them: the runner has no Karabiner, so tide says it hasn't written its
-- settings, and a karabiner.json in memory gets conf's rules in order.
do
    local karabiner = require("tide.karabiner")
    local state = tide.karabiner_rules and tide.karabiner_rules.state
    if not state then
        fail("Karabiner's rules: not set up")
    elseif state.problem ~= karabiner.NO_CONFIG and state.problem ~= karabiner.NO_RULES then
        fail("Karabiner's rules: %s", state.problem)
    else
        say("Karabiner's rules: %s", state.problem)
    end
    local home = "/smoke"
    local assets = home .. karabiner.ASSETS
    local files = {
        [home .. karabiner.CONFIG] = '{"profiles": [{"selected": true, "simple_modifications": [], "complex_modifications": {"rules": []}}]}',
        [assets .. "/pc-arrows.json"] = '{"title": "PC keyboard arrows", "rules": [{"description": "Ctrl+Left/Right moves by word", "manipulators": []}]}',
        [assets .. "/pc-alt-tab.json"] = '{"title": "PC keyboard Ctrl+Tab", "rules": [{"description": "Ctrl+Tab goes to the next tab", "manipulators": []}]}',
        [assets .. "/tide.json"] = '{"title": "tide", "rules": [{"description": "tide: Win is Super", "manipulators": []}]}',
    }
    local saved = {}
    local k = karabiner.new({
        home = home,
        source = tide.adapter.read(karabiner.SOURCE_PATH),
        read = function(path)
            return files[path]
        end,
        list = function()
            return { "pc-arrows.json", "pc-alt-tab.json", "tide.json" }
        end,
        run_js = tide.adapter.javascript,
        decode = tide.adapter.decode,
        write = function(path, text)
            files[path] = text
            saved[#saved + 1] = path
            return true
        end,
        resolve = function(path)
            return path
        end,
        running = function()
            return true
        end,
        get = function()
            return nil
        end,
        set = function() end,
        notify = function() end,
        log = function(text)
            say("Karabiner's rules: %s", text)
        end,
    })
    local s = k.check()
    local config = tide.adapter.decode(files[home .. karabiner.CONFIG] or "")
    local got = {}
    for _, r in ipairs(config and config.profiles[1].complex_modifications.rules or {}) do
        got[#got + 1] = r.description
    end
    local want = "tide: Win is Super, Ctrl+Tab goes to the next tab, Ctrl+Left/Right moves by word"
    if s.problem ~= "" or table.concat(got, ", ") ~= want then
        fail("Karabiner's rules in JavaScriptCore: %s; got %s", s.problem, table.concat(got, ", "))
    elseif not files[home .. karabiner.CONFIG]:find('"simple_modifications": []', 1, true) then
        fail("Karabiner's rules in JavaScriptCore: an empty list didn't stay one")
    else
        say("Karabiner's rules switched in JavaScriptCore: %s", want)
    end
end
-- tide's logo, as the menu bar, notifications and the switcher show it:
-- both renders installed and readable, the menu bar's a template.
do
    local brand = require("tide.brand")
    local template = tide.adapter.logo(brand.TEMPLATE)
    local logo = tide.adapter.logo(brand.LOGO)
    if not template or not template:template() then
        fail("logo: the menu bar's template image didn't load as a template")
    end
    if not logo then
        fail("logo: the notifications' image didn't load")
    end
    if template and logo then
        say("logo: loaded, template %s, %dx%d pt", tostring(template:template()), logo:size().w, logo:size().h)
    end
end
-- What a script reads for the workspace's name (SPEC.md §6.3), in a
-- folder only you can read, and that tide leaves Hammerspoon's IPC port
-- shut.
do
    local dir = os.getenv("HOME") .. "/Library/Caches/tide"
    local f = io.open(dir .. "/workspace")
    local text = f and f:read("a")
    if f then
        f:close()
    end
    if text ~= "in\n" then
        fail("workspace file holds %q, not in", tostring(text))
    end
    local perms = hs.fs.attributes(dir, "permissions")
    if perms ~= "rwx------" then
        fail("workspace folder is %s, not rwx------", tostring(perms))
    end
    perms = hs.fs.attributes(dir .. "/workspace", "permissions")
    if perms ~= "rw-------" then
        fail("workspace file is %s, not rw-------", tostring(perms))
    end
    if package.loaded["hs.ipc"] then
        fail("hs.ipc is loaded")
    end
    say("workspace file: in, private")
end
-- The name patterns' JavaScript runs in JavaScriptCore (SPEC.md §6.2).
do
    local names = require("tide.names")
    local got = names.default_name("ABC-123: Fix login - Tracker", "Chrome", { "\\b([A-Z]+-[0-9]+)\\b" },
        tide.adapter.javascript, tide.adapter.log)
    if got ~= "ABC-123" then
        fail("name patterns: got %s, not ABC-123", tostring(got))
    end
    local bad = names.check_script({ "(", "no group" })
    local okjs, result = tide.adapter.javascript(bad)
    if not okjs or not tostring(result):find("namePatterns[1]", 1, true) or not tostring(result):find("namePatterns[2]", 1, true) then
        fail("name patterns: the check said %s", tostring(result))
    end
    say("name patterns run in JavaScriptCore")
end

-- tide's appearance module runs in JavaScriptCore too, and works out light
-- or dark by the clock (theme.lua); with no mode in tide's files, tide
-- leaves the runner's appearance alone.
do
    local theme = require("tide.theme")
    local dashboard = require("tide.dashboard")
    local dir = debug.getinfo(require("tide.theme_hs").new, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"
    local sources = {}
    for _, name in ipairs(theme.MODULES) do
        sources[name] = tide.adapter.read(dir .. name)
    end
    local noon = os.time({ year = 2026, month = 11, day = 4, hour = 12 }) * 1000
    local okjs, result = tide.adapter.javascript(theme.script(dashboard.bundle(sources, theme.MODULES),
        '{"mode": "schedule", "light": "07:00", "dark": "19:00"}', nil, noon, nil, hs.json.encode))
    local plan, why = theme.read(okjs, result, hs.json.decode)
    if not plan then
        fail("appearance: %s", why)
    elseif plan.dark ~= false or plan.next ~= os.time({ year = 2026, month = 11, day = 4, hour = 19 }) * 1000 then
        fail("appearance: at noon by the clock it says %s", tostring(result))
    elseif tide.theme.state().chosen ~= false then
        fail("appearance: with no mode set, tide says one's chosen")
    else
        say("appearance: tide's module says light until 19:00 at noon, in JavaScriptCore")
    end
end

-- tide's idle timeline reads macOS's power assertions as they come: held
-- display while keep awake holds it, and not once it lets go.
do
    local before = hs.caffeinate.get("displayIdle")
    hs.caffeinate.set("displayIdle", true)
    local on = tide.idle.held()
    hs.caffeinate.set("displayIdle", before == true)
    if not on.display then
        fail("idle: keep awake's assertion isn't seen as holding the display: %s",
            hs.inspect(hs.caffeinate.currentAssertions()))
    else
        say("idle: keep awake's assertion holds the timeline")
    end
end

-- tide's wallpaper positions reach the desktop picture through JXA's ObjC
-- bridge, as Hammerspoon's own call can't place one: the picture shown
-- now, set again stretched, reads back stretched from macOS, then filled.
do
    local wallpaper = require("tide.wallpaper")
    local main = hs.screen.mainScreen()
    local url = main and main:desktopImageURL()
    local function placed()
        local ok, out = tide.adapter.javascript([[ObjC.import('AppKit');
(function () {
  const o = $.NSWorkspace.sharedWorkspace.desktopImageOptionsForScreen($.NSScreen.mainScreen);
  const s = o && o.objectForKey($.NSWorkspaceDesktopImageScalingKey);
  const c = o && o.objectForKey($.NSWorkspaceDesktopImageAllowClippingKey);
  return JSON.stringify([s ? s.intValue : null, c ? Boolean(c.boolValue) : null]);
})()]])
        return ok and out or ("couldn't read: " .. tostring(out))
    end
    if type(url) ~= "string" or not url:match("^file://.*[^/]$") then
        say("wallpaper: the desktop picture is %s, not a file to place; skipped", tostring(url))
    else
        local ok, out = tide.adapter.javascript(wallpaper.desktop_script(url, wallpaper.placement("stretch")))
        local stretched = placed()
        local back_ok, back = tide.adapter.javascript(wallpaper.desktop_script(url, wallpaper.placement("fill")))
        local filled = placed()
        if not ok or out ~= "[]" then
            fail("wallpaper: the desktop picture's JavaScript said %s", tostring(out))
        elseif stretched ~= "[1,false]" then
            fail("wallpaper: set stretched, macOS reads it back as %s", stretched)
        elseif not back_ok or back ~= "[]" or filled ~= "[3,true]" then
            fail("wallpaper: set filled again, macOS said %s and reads it back as %s", tostring(back), filled)
        else
            say("wallpaper: macOS places the desktop picture as asked, stretched then filled")
        end
    end
end

-- An init.lua from before the rename still gets tide, through the shim
-- make install puts in ~/.hammerspoon/timo.
ok, err = pcall(require, "timo")
if not ok then
    fail('require("timo"): %s', err)
elseif err ~= tide then
    fail('require("timo") returned something other than tide')
else
    say('require("timo") is tide')
end

-- What the launcher lists from this Mac's disk: apps every Mac has, and
-- System Settings' panes, named as the launcher shows them.
ok, err = xpcall(function()
    local apps, panes = require("tide.launcher_hs").scan()
    local have = {}
    for _, a in ipairs(apps) do
        have[a.name] = true
    end
    for _, name in ipairs({ "Finder", "TextEdit", "Terminal", "Archive Utility" }) do
        if not have[name] then
            fail("launcher: no %s among %d apps", name, #apps)
        end
    end
    local names = {}
    for _, p in ipairs(panes) do
        names[#names + 1] = p.name
        have["pane:" .. p.name] = true
    end
    table.sort(names)
    for _, name in ipairs({ "Keyboard", "Displays", "Mouse", "Trackpad" }) do
        if not have["pane:" .. name] then
            fail("launcher: no %s settings pane", name)
        end
    end
    for _, name in ipairs(names) do
        if name:find("Extension") then
            fail("launcher: a pane named %s, not as System Settings names it", name)
        end
    end
    say("launcher: %d apps; %d settings panes: %s", #apps, #panes, table.concat(names, ", "))
    -- Every pane the settings window and the bar open is one of this
    -- Mac's. Battery, Wi-Fi and Bluetooth come with their hardware, which
    -- the runner may not have, so they're only reported.
    local ids = {}
    for _, p in ipairs(panes) do
        ids[p.id] = true
    end
    local hardware = { battery = true, wifi = true, bluetooth = true }
    local opened = require("tide.links").PANE_IDS
    local keys = {}
    for key in pairs(opened) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if ids[opened[key]] then
            say("pane %s: %s", key, opened[key])
        elseif hardware[key] then
            say("pane %s: no %s on this Mac, which may lack the hardware", key, opened[key])
        else
            fail("pane %s: no %s on this Mac", key, opened[key])
        end
    end
end, debug.traceback)
if not ok then
    fail("launcher: %s", err)
end

-- The settings window opened on Start at login: that page alone shows,
-- beside the sidebar's pages under tide's three groups (SPEC.md §15), as
-- the bundled script draws them in WebKit.
local function check_settings_page(next)
    local want = 0
    for _, sec in ipairs(require("tide.launcher").SETTINGS_SECTIONS) do
        if not sec.page then
            want = want + 1
        end
    end
    tide.settings.evaluate([[JSON.stringify({
        shown: Array.from(document.querySelectorAll(".page")).filter((p) => !p.hidden).map((p) => p.id),
        headings: Array.from(document.querySelectorAll("#sidebar h3")).map((h) => h.textContent),
        pages: document.querySelectorAll("#sidebar button").length,
        outputs: document.querySelectorAll("#sound-outputs li").length,
        displays: document.querySelectorAll("#display-list h2").length,
        bluetooth: document.getElementById("bluetooth-error").textContent,
        bluetoothPower: !document.getElementById("bluetooth-power").hidden,
        battery: document.getElementById("battery-status").textContent,
        sources: document.querySelectorAll("#input-sources li").length,
    })]], function(result, err)
        -- Out of the page's own callback.
        tide.adapter.after(0, function()
            local got = type(result) == "string" and not dashboard.js_failed(err) and hs.json.decode(result) or nil
            if not got then
                fail("settings: the page didn't say what it shows: %s", hs.inspect(err))
            elseif table.concat(got.shown or {}, ",") ~= "page-startup" then
                fail("settings: it shows %s, not Start at login alone", table.concat(got.shown or {}, ", "))
            elseif table.concat(got.headings or {}, ",") ~= "Hardware,Windows,General" or got.pages ~= want then
                fail("settings: the sidebar has %s pages under %s, not %d under Hardware, Windows and General",
                    tostring(got.pages), table.concat(got.headings or {}, ", "), want)
            else
                say("settings: Start at login shows alone, beside %d pages under %s", got.pages,
                    table.concat(got.headings, ", "))
            end
            -- The Sound page lists every output macOS has.
            local outputs = #(hs.audiodevice.allOutputDevices() or {})
            if got and got.outputs ~= outputs then
                fail("settings: the Sound page lists %s outputs; macOS has %d", tostring(got.outputs), outputs)
            elseif got then
                say("settings: the Sound page lists the %d output(s) macOS has", outputs)
            end
            -- The Displays page lists every display.
            local screens = #hs.screen.allScreens()
            if got and got.displays ~= screens then
                fail("settings: the Displays page lists %s displays; macOS has %d", tostring(got.displays), screens)
            elseif got then
                say("settings: the Displays page lists the %d display(s) macOS has", screens)
            end
            -- The Keyboard page lists every input source macOS has on.
            local sources = #(hs.keycodes.layouts() or {}) + #(hs.keycodes.methods() or {})
            if got and got.sources ~= sources then
                fail("settings: the Keyboard page lists %s input sources; macOS has %d", tostring(got.sources), sources)
            elseif got then
                say("settings: the Keyboard page lists the %d input source(s) macOS has", sources)
            end
            -- The Power page has the battery, or says there's none.
            local has_battery = hs.battery.percentage() ~= nil
            if got and has_battery ~= (tostring(got.battery):match("^Battery %d+%%") ~= nil) then
                fail("settings: the Power page says %q", tostring(got.battery))
            elseif got then
                say("settings: the Power page says %q", got.battery)
            end
            -- The Bluetooth page says blueutil's missing when it is; with
            -- it, a read may still be under way, so it's only reported.
            local bluetooth = require("tide.bluetooth")
            local have = bluetooth.find(tide.adapter.exists) ~= nil
            if got and not have and got.bluetooth ~= bluetooth.MISSING then
                fail("settings: with no blueutil, the Bluetooth page says %q", tostring(got.bluetooth))
            elseif got then
                say("settings: the Bluetooth page shows %s", have
                    and (got.bluetoothPower and "its switch" or string.format("%q", tostring(got.bluetooth)))
                    or "that blueutil's missing")
            end
            next()
        end)
    end)
end

-- The settings window builds its page and opens, on Start at login as its
-- launcher row asks; the clocks come from tide's folder, which tide makes
-- if it's missing, to watch it.
ok, err = xpcall(function()
    tide.settings.show("startup")
end, debug.traceback)
if not ok then
    fail("settings: %s", err)
elseif type(tide.clock_files) ~= "table" or type(tide.startup_files) ~= "table" or not hs.fs.attributes(tide.clock_dir) then
    fail("settings: no clocks folder at %s", tostring(tide.clock_dir))
elseif type(tide.layout_files) ~= "table" or type(tide.wm.layout.modes) ~= "table" then
    fail("settings: tide's layouts weren't read")
else
    say("settings shown, clocks from %s", tide.clock_dir)
end

ok, err = xpcall(function()
    tide.dashboard.show()
end, debug.traceback)
if not ok then
    fail("dashboard: %s", err)
    finish()
    return
end
say("dashboard shown")
-- Give the page a moment to load and run, then close it. Held in a global:
-- Hammerspoon stops a timer that's garbage collected.
smoke_timer = hs.timer.doAfter(3, function()
    local closed, close_err = xpcall(function()
        tide.dashboard.show()
    end, debug.traceback)
    if not closed then
        fail("closing the dashboard: %s", close_err)
        finish()
        return
    end
    say("dashboard opened and closed")
    -- The overview (SPEC.md §6.9), as Ctrl+Up opens it, then Ctrl+Down's
    -- scope in the same page, then closed as a second Ctrl+Down closes it.
    local shown, show_err = xpcall(function()
        tide.overview.show("all")
        tide.overview.show("current")
    end, debug.traceback)
    if not shown then
        fail("overview: %s", show_err)
        finish()
        return
    end
    smoke_timer = hs.timer.doAfter(2, function()
        local done, done_err = xpcall(function()
            tide.overview.show("current")
        end, debug.traceback)
        if not done then
            fail("closing the overview: %s", done_err)
            finish()
            return
        end
        say("overview opened and closed")
        check_failing_helper(function()
            check_settings_page(function()
                check_screenshot(function()
                    check_moved_screenshot(function()
                        wait_for_bar(check_tiling)
                    end)
                end)
            end)
        end)
    end)
end)
