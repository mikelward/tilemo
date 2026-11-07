# TODO

## Next

The Hammerspoon version, in the order SPEC.md §18 sets:

1. Tiling and keys: layouts, floats, the window keys.
2. The mouse: edge drags set the split, Super+drag moves and resizes,
   Super+middle-click maximizes, resize mode (SPEC.md §5.3).
3. Focus follows mouse (SPEC.md §5.2).
4. Workspaces by parking (or minimizing), displays and restarts (SPEC.md §6).
5. The launcher, app keys and the Super tap (SPEC.md §7.2, §9).
6. The menu bar workspaces, the sign on switching, and attention
   (SPEC.md §8, §14.2).
7. The dashboard: tide for Chrome's bar and clock panel in an `hs.webview`, on
   Super+Shift+Space (SPEC.md §8).
   **Decided:** tide's own bar along the top, over an auto-hidden menu bar,
   with the workspaces, the title, tide for Chrome's clocks and its own status items.
   The menu bar item stays as the fallback (`bar = false`), and a large
   number shows briefly on each switch.
8. **Done:** conf's Karabiner rule turns Win+key into
   Ctrl+Option+Command+key (description starting `tide:`), and
   `setup-macos --wm tide` in scripts installs Hammerspoon and tide, frees
   the keys in SPEC.md §7.3, and stops the menu bar hiding, for tide's bar to cover.

## Settings pages, for parity with tide for Linux

tide for Linux has 17 settings pages (tide for Linux SPEC.md §16); tide's settings window has
a page for each, in tide for Linux's order and under its sidebar's groups, then a
Setup checklist of its own.
Clocks, Layouts, Workspaces, Start at login, Clipboard, the muted list,
Floating, Keyboard's Shortcuts and the Setup checklist are tide's own;
the rest are buttons to System Settings' panes, LinearMouse and Karabiner (SPEC.md
§15). **Check on a Mac:** a Layouts change retiles at once, and so does a
hand edit of `layouts.local.json`; each section's buttons open their pane,
on macOS 26 too; a Workspaces change moves home and the bar's order at
once, and at login the files' `inApps` opens only the entries that are Mac
apps, Chrome's installed web apps included; Keyboard's Shortcuts list
every key, and a key macOS won't register shows there in red and in
`tide doctor`; the Setup checklist shows Accessibility On, and Off (in
red, and in `tide doctor`) once it's turned off in Privacy & Security,
updating on coming back to the window; each Open lands on its list in
Privacy & Security or its pane in Desktop & Dock, Lock Screen and
Notifications, on macOS 26 too; the settings each item names are worded
so on macOS 26; ticks survive a reload. What's left:

- **Appearance**, if anything's left for it: a link to Appearance's own
  pane.
- **The dim (SPEC.md §5.6). Check on a Mac:** every window but the focused
  one is dimmed, and the desktop; the hole's corners match the window's on
  macOS 26 and before; clicks go through the layer; menus, popovers, the
  bar, the tray, picture-in-picture and Mission Control look right; a
  float over the focused tile is dimmed all over, once; the hole keeps up
  with a drag well enough; the Appearance page's − and + change it at
  once.
- **The sidebar's icons,** as tide for Linux's sidebar has one per page (its
  `settings.mjs` names a symbolic icon for each). **Check on a Mac:** every
  page and heading fits the window without scrolling the sidebar, and Up
  and Down change the page.

## Keep the Mac as you set it

The goal: after each login, each time a device is plugged in, each time a
KVM switches back to this Mac, and on wake, tide does its best to make
the Mac match your settings, with tide for Linux's files as the one source, so tide for Linux
looks and works the same on Linux, chromeOS and a Mac. The first piece,
the mouse wheel, is built:

- **Done: tide for Linux's Scroll speed and Natural scrolling through LinearMouse**
  (SPEC.md §10, §15), applied as tide starts, when tide for Linux's folder changes,
  after a plug or a wake, and at the 30 s check; Karabiner's rules are
  checked after a plug or a wake too. **Check on a Mac:** LinearMouse
  reloads tide's write and scrolls nine lines at 3×; the mouse reverses
  while the trackpad doesn't; a KVM switch back, a wake and an unlock each
  set it again and start a quit LinearMouse without its window; a change
  in LinearMouse's window is put back within 30 s; `hs.usb.watcher` and
  `hs.caffeinate.watcher` fire as expected on macOS 26.
- **scripts' setup-macos writes ten lines a notch;** tide makes it nine
  as it starts. setup-macos's `LINEARMOUSE_LINES` should move to nine to
  match, in mikelward/scripts.
- **Then the rest of tide for Linux's Mouse, Touchpad and Keyboard pages,** where
  macOS lets tide apply them at once: a keyboard's layout as its input
  source (`hs.keycodes`), and LinearMouse's pointer speed. What macOS
  takes only at the next login stays behind its pane's button.
- tide for Linux's per-device settings need one name for a device on both desktops:
  `hyprctl devices` names differ from LinearMouse's product names.

## Named workspaces

SPEC.md now has named workspaces in place of the nine numbered ones, and
one switcher with tabs (SPEC.md §6, §7.2, §9, §14.2), as tide for Linux's does.
**Built:** workspaces by name, the standing workspaces (`workspaces`, the
first being home, "in" by default) and home's apps (`home_apps`),
`Super+Home`, the saved state, names on the bar, the menu bar item, the
dashboard and the switch sign, the name prompt, `TIDE_WORKSPACE`, and a
launch's window going to the workspace it was launched for, and the keys:
`Super+Return`, `Super+Shift+Return`, `Super+Tab`, `Super+End`, Alt+Tab,
`Super+A` and the Super tap, and the switcher's tabs. The rest:

- **Several displays** (SPEC.md §6.1, §7.2, §19 question 12). **Decided**
  (2026-11-01): a workspace spans every display, each display with its own
  layout within it. **Built:** the keys. `Super+Left` / `Right` select the
  window that way, going on to the next display at its edge, and
  `Super+Shift+Left` / `Right` move it the same way, by one rule for
  displays of any size and offset (`direction.lua`); `Super+PgUp` / `PgDn`
  step through workspaces, and `Super+Shift+PgUp` / `PgDn` move the window
  there. **Built:** one workspace across every display (SPEC.md §6.1,
  §6.4): each display's own part of each workspace, with its own stack,
  layout, `mfact` and masters; each window's display kept and saved; every
  workspace key, the switcher and the bar switching every display
  together, with no "elsewhere" marks; each display's tray from its own
  part; and an unplugged display's windows handed to the first display
  left, going back when it returns. The rest:
  - **Check on a Mac:** with two displays, a switch brings back and parks
    (or, with `hide = "minimize"`, restores and minimizes) on both at once without a flash of the wrong workspace; a window
    dragged to the other display, or moved there by `Super+Shift+Right`,
    stays in its workspace; closing the lid or pulling the cable moves the
    other display's windows over, and plugging it back in returns them,
    each in its old place, with the display's own layout; how macOS itself
    moves windows off a display that goes away, and back, and whether
    tide's handoff fights it; that `hs.screen`'s UUIDs stay the same
    across a replug and a restart.
  - **Check on a Mac:** `Super+Shift+PgUp` / `PgDn` reach tide through
    Karabiner as Ctrl+Option+Command+Shift+PgUp / PgDn (conf's rule sends
    PgUp and PgDn with Shift already), and nothing else holds those
    chords; `Super+Left` / `Right` across two real displays of different
    sizes, one offset, pick the windows SPEC.md §7.2 says.
  - **tide for Linux** has the same keys (tide for Linux SPEC.md §6.6) and has decided on
    the same model, a workspace spanning every monitor with an empty
    part showing the wallpaper and the bar (tide for Linux SPEC.md §6.5); it's not
    built there yet.
- **conf:** Karabiner sends physical Alt+Tab as tide's
  `Ctrl+Option+Shift+Tab` instead of Cmd+Tab, and the lone Super tap as
  `Super+F20` (conf's PR for this goes with tide's keys PR); `kitty.conf` allows remote control on a socket; the shell reads
  `~/Library/Caches/tide/workspace` on a Mac when `TIDE_WORKSPACE` is
  missing (SPEC.md §6.3, §17).
- **Check on a Mac:** `open --env` on macOS 26, kitty's socket path, and
  how slow a pattern run through `hs.osascript.javascript` is (SPEC.md
  §6.2, §6.3).

## Parking hidden workspaces

**Built** (SPEC.md §6, 2026-11-05): a workspace that isn't showing parks
its windows off screen, all but a 1 pt sliver in a corner of their
display (`park.lua`), with `hide = "minimize"` for the old way. Only the
tests have run it. **Check on a Mac:**

- a switch is instant, with no animation and no flash of the wrong
  workspace, on one display and on two;
- macOS leaves a parked window where tide put it, a 1 pt sliver showing,
  rather than pulling it back on screen; and whether the top corners work,
  or macOS keeps a title bar below the menu bar (SPEC.md §6);
- apps that refuse a move, or snap back, such as a terminal or a window
  with a minimum size larger than what's left on screen;
- Cmd+Tab to an app whose window is parked brings its workspace along,
  as does clicking a sliver, a Dock click and a notification;
- after a switch to an empty workspace, Hammerspoon takes the focus
  without opening its console (SPEC.md §6);
- a native full-screen window on a hidden workspace minimizes and comes
  back;
- quitting or reloading Hammerspoon brings every parked window back on
  screen, and a crash's next start keeps the hidden ones parked and places
  the rest;
- which tools reading window positions are confused: screenshot pickers,
  window switchers, Raycast's window list.

## Minimizing by key

**Built** (SPEC.md §6.7): `Super+Z`, the corner tray, restoring from it
and from the Windows tab, and the rule check for `Super+Z`. **Confirmed**
by the user: each display's tray shows only the windows you minimized
from the workspace showing on that display. **Check on a
Mac:**

- the tray draws in the corner of each display, over the Dock's side,
  and goes when its last window is restored;
- a click on an icon restores its window without Hammerspoon becoming the
  front app first (`clickActivating(false)`);
- the title's tip shows on hover while another app is in front;
- the icons follow light and dark;
- `Super+Z` reaches tide through Karabiner as Ctrl+Option+Command+Z,
  with nothing else on that chord.

## The overview, in place of Mission Control

**Built** (SPEC.md §6.9): Ctrl+Up shows every workspace's windows as
cards grouped by workspace, Ctrl+Down this workspace's. Only the tests
have run it. **Check on a Mac:**

- once `setup-macos` has turned off symbolic hotkeys 32 and 33, Ctrl+Up and
  Ctrl+Down reach tide, and the settings window's Shortcuts list them as
  registered;
- the page fills the display the keys act on, the icons show, and it
  follows light and dark;
- a card's click, and Return, bring the window and its workspace, and
  restore one you minimized; a header's click shows its workspace;
- Esc, the same key again, a click on empty space and a click on another
  window each close it, and focus goes back where it was;
- whether conf's PC-arrows rule, which sends physical Ctrl+Home as
  Control+Up outside terminals, opens the overview; if it does, the rule
  should send Command+Up instead, or tide should pick other keys.

**Later, as an opt-in setting:** window thumbnails on the cards. They
need Screen Recording (`hs.window:snapshot()` or ScreenCaptureKit), which
tide never asks for now (SPEC.md §11.1), so off by default, with the
setup checklist asking for the permission only once it's on.

## Mute: apps and sites that never want attention

**Built** (SPEC.md §14.2, §15): `muted` in tide for Linux's `workspaces.json` and
`workspaces.local.json`, the marks suppressed and cleared, `Cmd+M` and the
right-click in the switcher's Windows and Attention tabs, the "muted"
mark, each browser window's front tab, and the settings window's list.
**The key is `Cmd+M`** (decided by the maintainer, 2026-10-31), physical
Ctrl+M under `setup-macos`'s rotation, the same key as tide for Linux's `Ctrl+M`.
It's an `hs.hotkey` bound only while the switcher's chooser is open and
deleted as it closes, never globally, so it can't reach macOS's own
`Cmd+M` minimize there and leaves it alone everywhere else; `Super+Z` is
tide's minimize. Hammerspoon's hotkeys are Carbon hot keys
(`RegisterEventHotKey`, `extensions/hotkey/libhotkey.m`), which take the
key before the chooser or Hammerspoon's own Window › Minimize item
(`MainMenu.xib`) sees it, and the chooser's panel isn't miniaturizable
anyway (its `styleMask` in `HSChooserWindow.xib` is only
`nonactivatingPanel` and `fullSizeContentView`).
**Check on a Mac:**

- the Notifications pane's URL on macOS 26, from the notice after a mute;
- that clicking the notice opens it (`hs.notify`'s callback);
- `Cmd+M` and the right-click reach tide while the switcher is open,
  and `Cmd+M` doesn't minimize anything there;
- Chrome's `active tab index` and Safari's `current tab` in the tab list.

## Launcher looks

**Built, switched off** (SPEC.md §9.2): tide for Chrome's dashboard page as the
launcher, in an `hs.webview`, with `start({ launcher = "dashboard" })`. The
default stays the `hs.chooser` switcher. Only the plain-Lua tests and the
page's test, against a fake DOM, cover it.

- **Next: make the dashboard launcher the default,** once it's been tried
  on a Mac with `launcher = "dashboard"`. Check there:
  - **open speed:** the webview is now kept, hidden, and loaded as it's
    chosen; CI's smoke test logs how long an open takes to answer. If it
    still feels slow, time the Lua side: the collector reads each window's
    title and app name on every open;
  - **key focus:** the search field has the keyboard as it opens, with no
    click; Esc, a click away and a second key give focus back to the
    window you were in, and a choice to the window it chose;
  - **Spaces and full screen:** it shows on the current Space, and over a
    full-screen app. It asks for `moveToActiveSpace` and
    `fullScreenAuxiliary` (`launcherpage_hs.lua`), which may need
    `canJoinAllSpaces` once the webview is kept;
  - **screen sharing:** the chooser isn't kept out of screen shares today
    (Decisions needing review: no part of Hammerspoon sets
    `NSWindow.sharingType`), so neither is the webview. Check whether
    `hs.webview` has gained a way since, and apply it to both.
- **The dashboard launcher's gaps against the switcher,** to close before
  it's the default:
  - `Cmd+Return`'s new workspace, and `Cmd+M` or a right-click to mute a row;
  - an Attention scope: `Super+A` opens it on Tabs;
  - a window's "minimized" and "muted", and the app's name, in its row:
    tide for Chrome's page says "tab on <workspace>" for every row on Tabs;
  - app icons on Launch and Tabs, which tide for Chrome's page takes as `favIconUrl`;
  - CI's smoke test opens only the chooser.
- **Compare the two on the Mac,** tide for Chrome's page with its scope chips over
  the bar and clocks against the chooser, then pick the default.

## Keep awake and presenter mode

**Built** (SPEC.md §7.2, §8, §10): `Super+S` and `Super+P`, the launcher's
Presenter mode, the bar's Presenting pill, and Do Not Disturb through
`/usr/bin/shortcuts`, with missing shortcuts named at load (console,
`tide doctor`) and in a notification on first use. Only the plain-Lua
tests and the bar page's test cover it. **Check on a Mac:**

- `Super+S` and `Super+P` reach tide through Karabiner as
  Ctrl+Option+Command+S and P, with nothing else on those chords;
- Set Focus's wording on macOS 26, and that "Do Not Disturb On" and
  "Do Not Disturb Off" made with it work from `shortcuts run`;
- with them missing, `Super+P` keeps awake and the notification says what
  to make;
- the bar's item reads "Presenting" while on, and a click ends it;
- the display stays awake, and the screen saver and lock hold off, while
  `displayIdle` is held.

## The bar at the main menu's level everywhere

On a display with a notch the bar now sits at the main menu's window level,
the lowest macOS leaves in the notch's strip (SPEC.md §8); every other bar
stays floating, below the menu bar. Consider the main menu's level on every
display, so the bar looks and stacks the same everywhere, and, further on,
hiding the system menu bar for good, so tide's bar is the only one:

- **What the menu bar still gives** (SPEC.md §8): the app's own menus, the
  Apple menu and other apps' status items. Those need a way in first, such
  as a key that reveals the menu bar or a menu of the app's menus, and the
  status items have no public API to draw elsewhere.
- **Check first, on a Mac:** whether the revealed menu bar shows over a bar
  at the same level, or under it, which decides whether the bar must hide
  while the menu bar is out.

## From the parity review (2026-11-07)

What the user picked from a list of what else would bring a Mac closer to
tide. INFEASIBLE.md lists what can't be fixed.

- **In progress, in scripts:** `setup-macos` opens Save and Print
  dialogs expanded, saves new documents to disk rather than iCloud, turns
  off window animations, and shows the hostname on the lock screen
  (mikelward/scripts#408).
- **Built: a three-finger swipe between workspaces** (SPEC.md §7.2,
  `swipe.lua`), with macOS's own swipe between Spaces turned off by
  `setup-macos` (mikelward/scripts#408). Only the tests have run it.
  **Check on a Mac:** that gesture events reach the tap on macOS 26
  without Input Monitoring; `getTouches()`' fields; that 15% of the
  trackpad's width feels right; that a three-finger drag, if turned on in
  Accessibility, holds the button down from its first touch, so it never
  swipes.
- **Built: Caps Lock as Compose** (SPEC.md §10, `compose.lua`), with
  Caps Lock sending F18 from `setup-macos` (mikelward/scripts#408). Only the
  tests have run it. **Check on a Mac:** that `hidutil`'s Caps Lock to F18
  holds alongside Karabiner, with no Caps Lock light or delay; that
  `getCharacters()` gives Dvorak's characters, with Shift; that
  `keyStrokes` types é, ① and combining marks in kitty, Chrome and a
  native text field.
- **Built: the clipboard history survives a restart, for a week,
  encrypted** (SPEC.md §9.1, `clipstore.lua`, `clipcrypt.lua`), text only.
  **Decided** by the user (2026-11-07): it keeps out only what password
  managers mark, concealed or transient; the file is encrypted with a key
  in the login keychain through `security` (no prompts, over a key only
  Hammerspoon may read); copies go after a week, or the Clipboard settings' Days to keep (also tide for Linux's; mikelward/tide#381). **Check on a Mac:** the
  first copy makes "tide clipboard history" in Keychain Access with no
  prompt; the file isn't readable text and comes back after a reload;
  LibreSSL's `openssl enc` takes `-pbkdf2` and `-pass env:`; a save doesn't stall typing; Clear history empties it.
- **For tide for Linux:** the same on Linux, the key in gnome-keyring through the
  Secret Service; it needs tide for Linux's own store in place of cliphist, which
  keeps every copy as it came.
- **To consider: more defenses for the saved history.** Ideas so far:
  - leave out copies that look like a secret, such as no spaces and a
    symbol, or a known token's shape (`ghp_`, `sk-`, `AKIA`), from the file
    only, kept in memory for the session;
  - pause the history while a password manager or a terminal's secure
    keyboard entry is in front.
- **Later: images in the clipboard history,** as tide for Linux's cliphist keeps
  them.
- **To consider: middle-click paste,** like Linux's primary selection.
  tide would copy what's selected and put the clipboard back after the
  paste, which can lose a copy made in between.
- **Not yet decided:** Tab reaching every control in dialogs
  (`AppleKeyboardUIMode`), no `.DS_Store` on network shares, and Touch ID
  for `sudo` (`/etc/pam.d/sudo_local`).
- **For tide for Linux, not here:** holding a key on Linux shows an accent picker, as
  macOS's press-and-hold does. macOS keeps its own.

## Decisions needing review

- **The overview's window order** (SPEC.md §6.9, 2026-11-05): each
  display in turn, in `wm:screens()`' order, its tiles in stack order, then
  its floats bottom to top, then any left over (a window on a display
  that went away, one you minimized out of the stack) in the order you
  minimized them, then by id.
- **The overview's selection starts on the focused window,** and the
  arrows step through the cards in order, Up and Left back, Down and Right
  on, stopping at the ends, rather than moving by row in the grid.
- **The other overview key while it's open switches scope** in the same
  page; only the same key again closes it.
- **Ctrl+Down with an empty current workspace** shows its header and "No
  windows on this workspace", rather than nothing or every workspace.

- **Parking is the default; the setting is `hide`,** `"park"` or
  `"minimize"` (SPEC.md §6, 2026-11-05), a start() option only: tide for Linux has
  nothing like it to share. Anything else is an error at load.
- **The corners are tried bottom-right, bottom-left, top-right, top-left**
  (`park.lua`), the first whose window overlaps no other display, else
  bottom-right. The top corners are unchecked on a Mac.
- **A native full-screen window still hides by minimizing** in park mode
  (SPEC.md §6), as it did before: a move can't take it off its own Space.
- **A focus of a parked window brings its workspace along** (Cmd+Tab, a
  click on its sliver, its app coming to the front) only while that window
  still has the focus, so a late report from before a switch doesn't flip
  you back.
- **A switch to an empty workspace gives the focus to Hammerspoon,** with
  no window of its own, so typing doesn't reach a parked window.

- **Pinned apps' close keys are hotkeys enabled while a pinned window has
  focus** (SPEC.md §6.2, 2026-11-04), not a keyboard event tap, so they
  need no Input Monitoring. A press just after focusing a pinned window,
  before tide hears of the focus, still reaches the app; one that finds
  focus moved on is posted on to the app. Only Cmd+W, Cmd+Shift+W and Cmd+Q
  are held, tide for Linux's three that mean something on a Mac; Cmd+Option+W (close
  all) isn't. A refused key notifies each press, as tide for Linux's does.
  Reversible: `pinned_hs.KEYS`, `wm:check_pinned_focus`.
- **start()'s `workspace_settings` takes tide for Linux's field names,** `askForName`
  and `pinnedApps`, inside a snake_case option (SPEC.md §15, 2026-11-04),
  so a table copies to and from workspaces.json unchanged.
- **Pinned apps match by app name, as home's apps do** (SPEC.md §6.2,
  2026-11-04); tide for Linux's web addresses pin nothing here, and a pinned app
  that isn't one of home's still asks for a name as it opens on a
  workspace that asks, as on tide.
- **Trackpad, key repeat and left-handed stay in System Settings**
  (2026-11-04): tide for Linux's pages set them live, but macOS's `defaults` for tap
  to click, natural scrolling, tracking speed, key repeat and swapping the
  buttons take effect only at the next login *(unverified)*, so controls
  here would seem not to work. Revisit if a live way turns up.

- **tide for Linux's idle timeline runs only once its files set some of it**
  (SPEC.md §15, 2026-11-04), as light and dark does, rather than tide for Linux's
  defaults locking every Mac after 5 minutes; the page's switch writes
  them. The dim is a half-dark veil, not the displays' brightness, so it
  covers every display alike. An app's power assertion holds the whole
  timeline. Reversible: `chosen` in `idle.load`, `idle_hs.DIM_ALPHA`.

- **Light or dark follows tide for Linux's schedule only once a mode is set**
  (SPEC.md §10, 2026-11-04): with none in tide for Linux's appearance files, macOS's
  own appearance stays, rather than tide for Linux's default of 07:00 and 19:00
  taking over every Mac. The page's first mode is "macOS's own". macOS's
  Auto can't be set from here, so Sunrise and sunset is tide for Linux's
  computation, not macOS's. Reversible: `chosen` in `theme.script`.

- **The Bluetooth page** (SPEC.md §15, 2026-11-04) lists the paired
  devices as tide for Linux's popover does, connected first, then by name, and a
  click connects or disconnects one; pairing stays in Bluetooth settings.
  It reads blueutil every 5 s while the window's open, rather than only
  as it opens. Reversible: `bluetooth.page_state`, `bluetooth_hs.EVERY`.

- **Over a notch, overflowing workspace chips hide behind "+n"** (SPEC.md
  §8, 2026-11-03), which opens the switcher's Workspaces tab; the middle 220 px stays
  clear. The alternatives were shrinking every chip's name further, or
  moving the chips to the right of the notch. Reversible: `NOTCH_ROOM` and
  `fitNotch` in `dashboard/bar.js`.

- **The settings window has no logo atop its sidebar** (2026-11-03), so
  it looks as tide for Linux's panel does, which has none; its title still says
  tide. Its toggles keep their words, such as "History on", rather than
  tide for Linux's bare On and Off. Reversible: the `brand` paragraph in
  `dashboard/settings.html`.
- **The Setup checklist is General's last page** in the settings window's
  sidebar (2026-11-02), since tide for Linux has no such page and General is "the
  rest". Reversible: its `group` in `launcher.SETTINGS_SECTIONS`.
- **The volume popover** (2026-11-02): a click on the speaker opens it
  rather than muting, as tide for Linux's does; mute is in the popover. No inputs
  or per-app volumes, unlike tide for Linux's.
- **The volume keys over DDC** (2026-11-02): 5% steps, the bar's scroll
  step, not macOS's sixteenths, and the level as an `hs.alert` sign rather
  than a drawn bar like macOS's.
- **The switcher's look** (2026-11-02): headers only with nothing typed, on
  Launch (Recent, the five used last, then Apps, System Settings,
  Commands) and Actions (Session, tide for Linux, Toggles, Screenshots); fonts at
  16/12/11 pt, 40% wide, 10 rows; the session's icons are macOS's
  `NSLockLockedTemplate`, `NSUser` and `NSComputer`, and tide for Linux's toggles
  show its logo, for want of a fitting system image; a workspace shows
  `NSMultipleDocuments`. Unseen on a Mac: whether a template image tints
  on the dark rows, and whether a styled title keeps hs.chooser's own
  size. Reversible: `launcher.look`, `launcher.icon`, `launcher.FONT`.
- **A display that goes away hands its windows to the first display
  left** (`hs.screen.allScreens()`'s first, the main one), each at the end
  of that display's stack in its old order, rather than to the nearest
  display or spread across several (2026-11-01). Reversible:
  `wm.map_screens`.
- **When that display comes back, its tiles go back,** in their old order,
  at their old indexes, rather than staying put; one you moved to another
  display or workspace meanwhile stays, and floats stay where macOS put
  them. The display each would go back to is saved, so it holds across a
  restart. Reversible: `w.from` in `wm.map_screens` and `wm.add`.
- **A switch focuses the workspace's last used window on whichever display
  it's on,** not the last used on the display the keys are on; with
  nothing to focus, the keys stay on their display (2026-11-01).
  Reversible: `wm.refocus_ws`.
- **A Send keeps focus on this display's part of the workspace;** with
  nothing left there, the keys stay on this display, rather than focus
  jumping to the workspace's window on another display (2026-11-01).
  Reversible: `wm.send_keeping_focus`.
- **Maximize lasts until another window on the same display is focused,**
  not any window of the workspace, since each display lays out its own
  part (2026-11-01). Reversible: `wm.focused_window`.
- **A state saved when each display showed its own** shows the one it
  saved as showing, else the first display's that's there, rather than
  home (2026-11-01). Reversible: `wm.map_screens`.
- **The switch sign shows on the display the keys act on,** not on every
  display (2026-11-01). Reversible: `on_show` in `init.lua`.
- **At the last display that way, `Super+Left` / `Right` stop** rather than
  wrap round to the far side (2026-11-01). Reversible: `direction.find`.
- **A display that way with no tiles takes the keys,** as a switch to an
  empty workspace leaves them, rather than being passed over for the one
  beyond (2026-11-01). Reversible: `A.select`.
- **A window moved onto the next display takes the place in its layout
  nearest the edge it came in by,** rather than the end of that display's
  stack, as a Send does (2026-11-01). Reversible: `M:entry_slot`.
- **Ties go to the first tile in tile order,** after shared height and
  the nearest center (2026-11-01). The alternative was the one used last.
  Reversible: `direction.nearest`.

- **The dashboard launcher feeds tide for Chrome's page through stand-ins for two
  of tide for Chrome's modules, not only Chrome's APIs** (2026-11-01):
  `launcher-lists.js` replaces `launcher.js`'s `actions()` and
  `settingsSections()`, whose rows are chromeOS's, with the switcher's
  Actions tab and Tide Settings' sections, and `launcher-settings.js`
  replaces tide for Chrome's `settings.js` with tide for Linux's clocks. The alternative was
  tide for Chrome's own Actions (keep awake, dim, reload) and settings sections,
  which name a Chromebook's settings. Reversible: drop the two from
  `launcherpage.MODULES`.
- **The page tells tide for Chrome it runs on chromeOS** (`getPlatformInfo` says
  `cros`), so it shows workspaces, as tide for Chrome does only there
  (2026-11-01). Reversible: `launcher-chrome.js`.
- **The page keeps tide for Chrome's chip names,** "Tabs" for the windows and tabs,
  since its footer names the scopes too (2026-11-01). The alternative is
  calling it "Windows", as the switcher does, which needs tide for Chrome's markup
  and `launcher.js` to change. Reversible: in tide for Chrome.
- **Windows are listed as tabs with a made-up address,**
  `tide-window://<app>/`, so a query finds a window by its app as tide for Chrome
  finds a tab by its site (2026-11-01). Reversible: `launcherpage.feed`.
- **System Settings' panes are among the apps on Launch,** most recently
  used first with them, since tide for Chrome's page has no other row for them
  (2026-11-01). Reversible: `launcherpage.feed`.
- **tide's commands go in as manifest commands with no key,** so tide for Chrome
  lists them on Actions after the actions and on Launch for a query
  (2026-11-01). The switcher lists them on Launch only. Reversible:
  `launcherpage.feed`.
- **`make check-tideco` compares `launcher.html`'s body with the page
  template's**, since the template wraps it in tide's style and script
  markers (2026-11-01). Reversible: the `Makefile`.
- **The Setup checklist is tide for Chrome's, not tide for Linux's,** and the window's last
  section, after Start at login (2026-11-01): tide for Linux has no checklist page
  (tide for Linux SPEC.md §16), and tide's SPEC.md §10 says "as tide for Chrome's". The
  alternative is putting it first, as a new Mac's first stop. Reversible:
  `settings.html`, `SETTINGS_SECTIONS` in `launcher.lua` and `TIDE_ORDER`
  in `links_test.lua`.
- **The checklist's settings are ticked off by hand,** as tide for Chrome's are,
  kept per Mac in `hs.settings` (2026-11-01). The alternative is reading
  each with `defaults` (`com.apple.dock` `minimize-to-application`,
  `mineffect`, `mru-spaces`, `com.apple.WindowManager`'s keys), which would
  need each key checked on macOS 26. Reversible: `checklist.ITEMS` and
  `checklist.page`.
- **Input Monitoring and Automation show "Can't tell",** and Screen
  Recording "Not needed" without reading it (2026-11-01): Hammerspoon reads
  neither of the first two without prompting, and tide never needs the
  third. The alternative is an Input Monitoring probe through the Super
  tap's event tap. Reversible: `checklist.permission_state`.
- **The permissions have no ticks;** only the settings do (2026-11-01).
  The alternative is a tick on the two that can't be read. Reversible:
  `checklist.PERMISSIONS` and `renderSetup`.

- **Keyboard's Shortcuts are under the Keyboard section,** as tide for Linux moved its
  Keys page into Keyboard (2026-11-01), with their own launcher row, "Tide
  Settings: Keyboard shortcuts". The alternative is a Keys section of its
  own. Reversible: `settings.html` and `SETTINGS_SECTIONS` in
  `launcher.lua`.
- **What each key does is written in `keys.lua`** (`DOES`, and `does` on
  the app keys), in conf's words for tide for Linux's same key (2026-11-01), since
  Hammerspoon's hotkeys have no description. The alternative is reading
  conf's `hyprland.lua`, which a Mac may not have and whose keys differ.
  Reversible: `keys.DOES`.
- **A chord left out for another binding counts as a key that didn't
  register** (2026-11-01): without Karabiner, Super+Print is listed in red
  and named by `tide doctor`, beside its fallback notice. The
  alternative is listing only the keys macOS refused. Reversible: where
  `bind_all` in `init.lua` adds `skipped` to `failed`.
- **Keys show as a PC keyboard prints them** (2026-11-01), as tide for Linux's do:
  `Super+Backspace`, `Super+Insert`, `Print`, `Alt+Tab`, not the Mac's
  delete, Help, F13 or Karabiner's Ctrl+Option+Shift+Tab. The alternative
  is the Mac's names. Reversible: `KEY_NAMES` and `keys_label` in
  `keys.lua`.

- **Home's apps match a Mac app's name ignoring case, with spaces, hyphens
  and underscores alike** (2026-11-01), so conf's shared `inApps`
  (`google-chat`, `youtube-music`) names the Mac's Google Chat and YouTube
  Music too. The alternative is exact names, as `home_apps` matched before.
  Reversible: `standing.app_key`.
- **At login, the files' `inApps` opens only the entries that are a Mac
  app** in the usual Applications folders (2026-11-01); the rest are taken
  to be tide for Linux's and skipped, logged but not notified, so tide for Linux's programs
  don't nag on every login. A typo goes unannounced too. The alternative is
  opening every entry and notifying each that fails, as `home_apps` does.
  Reversible: `standing.app_paths` and `find_app` in `hs_adapter.lua`.
- **A Workspaces change applies at once** (2026-11-01), as tide for Linux's does: a new
  first standing workspace is home from then on, and the old home becomes an
  ordinary workspace, its windows left where they are. The alternative is
  taking effect at the next reload. Reversible: `wm:set_workspaces`.
- **The muted list stays in the Notifications section** (2026-11-01), as on
  tide for Linux, where `muted` is the Notifications page's; the Workspaces section's
  writes keep it. The TODO item had it in the Workspaces section.
  Reversible: the sections in `settings.html`.
- **With no file setting a list, the Workspaces section shows `start()`'s or
  tide's defaults,** and its first change copies them into
  `workspaces.local.json` (2026-11-01), as the Clocks section copies its
  defaults. Copying tide's default home apps makes them a list you set, so
  the installed ones (Mail, Messages, Calendar, Music) start at the next
  login. The alternative is starting from tide for Linux's empty default. Reversible:
  `workspaceShared` in `settings-page.js`.

- **Focus follows mouse skips a tile with another app's float in front of
  it** (2026-11-01), since macOS buries the float once the tile is focused
  and tide's re-raise doesn't bring it back. Moving onto the float, or
  clicking the tile, still moves focus. The alternative is focusing the
  tile and losing the float behind it. Reversible: `under_float` in
  `ffm.lua`.
- **The Actions tab comes last,** after Attention, and has no key of its
  own (2026-11-01). Its order puts the session and power first, then
  tide, the toggles and the screenshots. Reversible: `SCOPE_ORDER` and
  `COMMANDS` in `launcher.lua`.
- **The settings sections' rows are for a query alone** (2026-11-01), as
  tide for Linux's per-page rows are, so Launch's empty list shows only Tide
  Settings. Reversible: `query_only` in `launcher.lua`.
- **tide turns on each Karabiner rule it hasn't seen, once,** and keeps
  every enabled copy up to date with its file, editing `karabiner.json`
  itself (SPEC.md §15). So Ctrl+Tab's next tab works without a visit to
  Karabiner's window, and a rule you turn off stays off. The alternative is
  leaving every rule off until switched on. Reversible: `synced` in
  `dashboard/karabiner.js`.
- **The doctor names only conf's rules that are off** (`karabiner.CONF_FILES`),
  so a rule file from elsewhere you've left off isn't nagged about.

- **The settings window's sections are in tide for Linux's order** (SPEC.md §15),
  Displays first, where Clocks used to be. The muted list's section is
  titled Notifications, as tide for Linux's page is, and its launcher row still
  scrolls to it. Reversible: the sections' order in `settings.html`.
- **LinearMouse missing or stopped is a notification** as tide starts,
  even on a Mac with no mouse, since `setup-macos` always installs it.
  tide starts it on a login, a plug or a wake, and a click on the
  notification does too. Reversible: `linearmouse.problem`.
- **tide for Linux's Mouse settings that aren't set apply as tide for Linux's page shows them**
  (2026-11-01): 3× and natural scrolling off, so setup-macos's ten lines
  become nine and the mouse wheel is reversed while macOS's switch is on.
  The alternative is leaving LinearMouse's own values alone until a
  setting is made. Reversible: `mouseScrolling` in
  `dashboard/linearmouse.js`.
- **Lines a notch round to the nearest whole line, one at least**
  (2026-11-01): LinearMouse takes whole lines, so tide for Linux's 1.5× is five, not
  4.5. Its pixel distance could be exact instead. Reversible: `linesFor`
  in `dashboard/linearmouse.js`.
- **A change to tide for Linux's folder starts LinearMouse only when the Mouse
  settings changed** (2026-11-01), so editing a clock doesn't undo quitting
  it on purpose. The alternative is starting it on every folder change, as
  the other events do. Reversible: `apply` in `linearmouse.lua`.
- **A wake or an unlock waits the same second as a plug** (2026-11-01), so
  the devices a wake brings back count as one event. Reversible:
  `PLUG_DELAY` and `plugs_and_wakes`.

- **The Floating section's rules are in `floating-macos.json` and
  `floating-macos.local.json`** in tide for Linux's folder (SPEC.md §15), not tide for Linux's
  `floating.json`, since a bundle ID isn't a Wayland class. The shared file
  is for every Mac of yours, the local one this Mac's, as tide for Linux's other
  files. The alternatives are one per-Mac file alone, or a `macos` key in
  tide for Linux's `floating.json`. Reversible: `floating.FILE` and `LOCAL_FILE`,
  and a rename of the file.
- **`start()`'s `rules` come before the section's,** so one there that
  tiles or ignores an app wins over a section rule floating it (SPEC.md
  §5.1). The alternative is the section's first, since they're newer and
  the page shows them. Reversible: the order in `floating.combined`.
- **Titles are Lua patterns,** as `start()`'s have always been, not a
  regex library: no new dependency, and one syntax for both kinds of
  rule. They have no `|` and match bytes, which SPEC.md §15 says. The
  alternative is a regex through `hs.javascript`, as the workspace-name
  patterns use. Reversible: `floating.pattern_problem`, `exact` and
  `rules.lua`'s `matches`.
- **The key is Super+Shift+I** (SPEC.md §7.2), since tide for Linux's Super+Alt+F
  can't be had with Super holding Option. Chosen as free, not for its
  letter. Reversible: one line in `keys.lua`.
- **A click on the "Always float APP?" notification is Edit rule…,** and
  it expires after 30 s, which is Not now (SPEC.md §5.1). tide for Linux's has no
  body click. Reversible: `floating_hs.lua`.
- **A swept window that isn't showing is placed when it next shows**
  (SPEC.md §15), not while minimized, which Accessibility may refuse
  *(unverified)*. The alternative is placing it at once, minimized.
  Reversible: `wm:set_float_rules` and `follow_floats`.
- **tide on screen and in the code** (SPEC.md §17), since tilemo became
  tide (2026-11-07). Each of these is a one-line change to undo or redo:
  - What tilemo saved is copied, not moved, to tide's `hs.settings` keys,
    so a downgrade still finds it. Reversible: `saved.move_prefix` in
    `start()`.
  - `~/Library/Caches/tilemo` becomes a link to `~/Library/Caches/tide`,
    for conf's shells until they read the new path. Reversible:
    `current.move_old`.
  - Karabiner rules described `tilemo:` and `timo:` still count, and conf's
    `tilemo.json` is still conf's, until conf's rule says `tide:`.
    Reversible: `keys.RULE_PREFIXES` and `karabiner.CONF_FILES`.
  - "Reload tide" and "Check tide (doctor)" keep "Reload tilemo" and "Check
    tilemo (doctor)" as the key their use is remembered by, so they don't
    drop down the switcher.
  - `make install` leaves the rest of an old `~/.hammerspoon/tilemo` in
    place, unused, rather than delete a folder in your home.
  - Comments in the code still say tide for the Linux desktop as well as
    for this. The docs say tide for Linux; the comments follow as they're
    next touched.
  - The logo is a PNG pair, not drawn with `hs.canvas`, so it's tide for Linux's SVG
    as rendered, and one file to swap: a 16 pt template (64 px) for the menu
    bar, and a 64 pt one (256 px) in the light accent blue, `#3584e4`, for
    notifications and the switcher's two rows. The dark accent, `#78aeed`,
    would read better on a dark notification; macOS gives a notification no
    way to switch.
  - The settings page gets a header, the logo and "tide", above Clocks; the
    dashboard, tide for Chrome's page, gets no logo.
  - Only the switcher's own two commands show the logo; the other commands'
    rows stay without an image.
- **Check the logo on a Mac:** the menu bar item with `bar = false` in light
  and dark, a notification's image, and the two switcher rows. Only
  `tests/brand_test.lua` and CI's smoke test (the PNGs load, the menu bar's
  as a template) cover them.

- **The switcher's tab keys go in the search field's hint,** after where
  Tab goes: "Cmd+Return: new workspace" on Launch, "Cmd+M: mute" on
  Windows and Attention (SPEC.md §9), since `hs.chooser` has no footer to
  put them in as tide for Linux does. The longest hint is now 80 characters
  *(unverified that it fits the chooser's default width on a Mac)*. The
  alternatives are a wider chooser (`chooser:width`), or the keys as a
  row of their own. Reversible: `launcher.SCOPE_KEYS`.
- **The bar's logo opens the switcher where `Super+Space` does,** on the
  display with the focused window, not always the clicked bar's (SPEC.md
  §8), as tide for Linux's opens on that bar's monitor. `hs.chooser:show` takes a
  top-left point, so it could be placed on the bar's display, at the cost
  of working out the chooser's width there. Reversible: `launcher_hs`'s
  `toggle`.
- **Home's apps start at login only from a `home_apps` you set** (SPEC.md
  §6.2), not tide's default list, which names a Mac app and a web app for
  each of mail, chat, calendar and music, and so would open Mail's and
  Messages' first-run setup on a Mac that uses Google's. tide for Linux starts its
  list, which `conf` sets to the four Google launchers. The alternatives are
  starting the default list's installed apps, or the first installed of
  each pair. Reversible: `startup.home_starts`.
- **Home's entries stay app names, not tide for Linux's programs and web
  addresses,** since a `chrome --app=URL` window on a Mac is Google
  Chrome's, which tide can't tell from a browser window (SPEC.md §6.2).
  The alternative is matching such windows by title. Reversible: it adds
  nothing, so it's an addition later.
- **tide's settings are one window with sections, not tide for Linux's pages**
  (SPEC.md §15): Clocks, Start at login, Clipboard and Muted, each with its own
  launcher row that scrolls there. It's one short window, and an
  `hs.webview` has no sidebar to build. The alternative is a page per
  section, as tide for Linux's panel has. Reversible: `settings.html` and
  `settings_hs.lua`'s `reveal`.
- **Enter on a new name in `Super+Return`'s prompt goes to a new, empty
  workspace of that name** (SPEC.md §7.2), as tide for Linux's does. It goes again
  once you leave it empty, so a stray name costs nothing. The alternative
  is offering only existing names there. Reversible: `wm.lua`'s
  `go_answer` would refuse a name `find` doesn't know.
- **`Super+Shift+Return` with no window focused does nothing,** and says
  why only in Hammerspoon's console, as tide for Linux's says it only in the shell's
  log. The alternative is a notification. Reversible: one line in
  `wm.lua`'s `A.move_to`.
- **A chip's tip shows only when the chip cuts its name** (SPEC.md §8),
  since a whole name would say it again. The alternative is a tip on
  every chip, as the old `title` attribute had. Reversible: one line in
  `bar.js`'s `renderWorkspaces`.
- **Start at login tells one login from the next by when `loginwindow`
  started,** kept in `hs.settings`, so a Hammerspoon reload runs nothing.
  A login it can't tell runs nothing. The alternatives are a file in
  `$TMPDIR`, which outlives a logout, or a Login Item that runs the list
  itself. Reversible: `startup.due` and `a.login`.
- **Start at login has no page in tide yet;** tide for Linux's page or a hand
  edit changes the list. The settings window could list it as it lists
  the muted apps. It's an addition.
- **A default name's first word loses `.` `,` `:` `;` `!` `?` `|` `…` and
  dashes from its end, a word with no letter or digit is passed over, and a
  title with no such word gives the app's name,** matching tide for Linux's list.
  The alternatives are a shorter list (only `:` `,` `|`), or an empty
  default as tide for Linux gives. Reversible: `names.fallback`.
- **The title's target is the whole free bar between the two groups,**
  for a double click and on hover, so it isn't just its text. The
  alternative was the title's own box stretched to the bar's height,
  leaving the rest of the middle dead. Reversible: `titleInsets` and the
  bar's `dblclick` listener in `bar.js`.
- **Hover comes from tide's pointer tap,** one `evaluateJavaScript` per
  pointer move over a bar, since WebKit gives the never-key bar no
  `:hover`. The alternative, making the bar's window key on entry, would
  take focus from the app under it. Reversible: `bar_hs`'s `pointer`.
- **The clocks stay one target, opening the dashboard,** rather than a
  target per clock: they did one thing before, and the dashboard's clock
  panel is where a single zone is picked. Reversible: `bar.js`'s clocks
  listener.
- **Presenter mode turns Do Not Disturb off when it ends,** even if it
  was on before, since tide can't read a Focus. Keep awake goes back as
  it was. A third shortcut using "Get Current Focus" could read it, at
  the cost of one more shortcut to make. Reversible: `presenter.presenter`.
- **The shortcuts are "Do Not Disturb On" and "Do Not Disturb Off",** two
  of them rather than one taking "on" or "off" as input, since a
  one-action shortcut is the easiest to make. Reversible: the names in
  `presenter.lua`.
- **A missing shortcut is a notification on first use, and only a
  console line and a `tide doctor` line at load,** so a Mac that never
  uses Do Not Disturb isn't told at every reload. Reversible:
  `presenter_hs.check`.
- **Presenter mode shows on the keep-awake item, not as an item of its
  own:** while on, that item becomes a filled "Presenting" pill. The bar
  has no room to spare beside the clocks. Reversible: `bar.js`'s
  `renderIcons`.
- **Either toggle alone while presenting ends presenter mode,** leaving
  the other on, as on tide. Reversible: `presenter.keep_awake` and
  `presenter.dnd`.
- **Super+V's clipboard history is in memory only, text only, the newest
  200.** Cheaper and safer than a file at mode 600: no permissions to keep
  right, nothing left on disk, and a reload wipes it. The cost is losing it
  at every restart, and images aren't listed. Reversible: picker.lua's
  history is a plain list a file could back, and the watcher could keep
  `hs.pasteboard.readImage()` too.
- **Return in the picker pastes with Cmd+V,** sent to the app that was
  in front when it opened, once it's brought back, as tide for Linux pastes. A
  terminal pastes on Cmd+V on a Mac too, so there's no exception list.
  Reversible: one call in `picker_hs.lua`'s chooser callback.
- **Shift+Delete forgets a clipboard entry,** which on a Mac keyboard is
  Shift+forward delete (Fn+Shift+Delete). tide for Linux's key; plain Delete stays
  the search field's.

- **After a mute, clicking tide's notice opens Notifications settings,**
  rather than a dialog asking first, which would take the keyboard from
  the switcher. Reversible: `toggle_mute` in `init.lua`.
- **`muted` lives in `workspaces.json`,** beside `inApps` and
  `namePatterns`, rather than a file of its own, since it's another list
  of apps tide for Linux and tide share. Reversible: one name in `mute.lua`, and
  tide for Linux's agent may pick otherwise.
- **A right-click on a row stands in for a hover button,** which
  `hs.chooser` can't draw. Reversible: a webview switcher.
- **A site matches a browser window by its front tab as the switcher last
  saw it,** so a window whose tab changed since the switcher was last
  opened may be marked or not by the old tab. Polling the browsers for it
  would cost an Apple Event every 2 s. Reversible: `wm.tab_hosts`.
- **A site's host matches exactly,** ignoring case, so
  `site:chat.google.com` doesn't cover `mail.google.com`, and
  `site:google.com` doesn't cover either. Reversible: `mute.matches`.
- **Workspace names take tide for Linux's character rule but not its 32-character
  cap.** No quotes, backslashes or control characters, refused at load and
  at the prompt. Long names are left alone, since nothing here breaks on
  them and the bar already shortens a long name. A refused launch prompt
  comes back with the characters dropped. A refused window prompt comes
  back with the title's default, as before. The alternatives were the cap
  too, or dropping the characters silently instead of refusing.
  Reversible: `names.UNSAFE` and `wm:refuse_unsafe`.
- **Minimize is `Super+Z`, not `Super+Delete`:** a PC keyboard's Delete
  may arrive as forward delete or as Backspace, and `Super+Backspace`
  already closes the window. Reversible: one line in `keys.map`.
- **The tray's icons are in the order you minimized them, newest at the
  right,** nearest the corner, and as many as fit across the display; the
  rest are only in the Windows tab. Reversible: `tray.lua`.
- **The tray's tip is a second canvas** drawn on the pointer entering an
  icon, not a canvas element's `toolTip`, which may only show while
  Hammerspoon is in front *(unverified)*. Reversible: `tray_hs.lua`.
- **conf's Karabiner rule needs no change for `Super+Z`:** it has sent
  Win+Z as Ctrl+Option+Command+Z since it was first added. tide's rule
  check still flags a copy without it. Reversible: `keys.RULE_FEATURES`.
- **An out-of-date tide rule in Karabiner is flagged, not worked
  around:** tide reads the enabled copy in `karabiner.json`, and if
  Alt+Tab's or the tap's Super+F20 manipulator is missing it says which,
  and how to re-add the rule, in a notification and in `tide.doctor()`.
  It doesn't bind Super+Space's old tap or anything else in their place.
  `tide doctor` is so far just this and the Karabiner check, from the
  console or the switcher. Reversible: `keys.rule_gaps` and `init.lua`'s
  `check_rule`.

- **A name pattern with no capture group is an error at load,** as tide for Linux's
  spec says for the same shared file, since it can't give a name. The
  patterns are tide for Linux's `workspaces.json` `namePatterns`, with
  `workspaces.local.json` taking their place when it sets them; that's the
  name on tide for Linux's spec branch, not merged there yet. A bad list is said
  in a notification and the last good one stays, rather than stopping
  tide. Reversible: `names.lua`.
- **The home workspace's name typed at the name prompt is refused** with a notice, and the
  window asks again; for a launch, nothing opens. Reversible:
  `wm.answer` and `wm.before_launch`.
- **`TIDE_WORKSPACE` reaches a helper through `env(1)`** in front of
  `runenv`, not `hs.task`'s `setEnvironment`, which would replace the whole
  environment rather than add to it. Apps by bundle ID start through
  `open -b … --env`, not `hs.application.launchOrFocusByBundleID`, which
  can't pass one. kitty's remote control is tried at `/tmp/kitty-<pid>`
  then `/tmp/kitty` *(unverified which kitty uses)*, falling back to Cmd+N.
  Reversible: `hs_adapter.lua`'s `launch`.
- **Scripts read the workspace from `~/Library/Caches/tide/workspace`,**
  not `hs -c`, since `hs.ipc`'s port runs any Lua a local process sends,
  with tide's Accessibility grant. Lua has no chmod, so each write runs
  `/bin/chmod` three times; that's only when the workspace changes. Reversible:
  `current.lua`.
- **A launch's window is matched by its app's bundle ID,** or, for a
  helper with none, as the next new window of any app, within the launch's
  10 s grant, once. A window from elsewhere opening in that time could be
  taken for it. Reversible: `wm.launch_to`.
- **Alt+Tab is `Ctrl+Option+Shift+Tab`** as Karabiner sends it: without
  Command, so physical Win+anything can't make it. Reversible:
  `keys.karabiner_only` and conf's `tide.json`.
- **The lone Super tap is `Super+F20`** as Karabiner sends it, told apart
  from `Super+Space`. Reversible: one line in `keys.map` and conf's
  `tide.json`.
- **The switcher's tabs are scopes of one `hs.chooser`,** as the launcher's
  were: Launch, Workspaces, Windows and Attention. The Workspaces tab
  lists each workspace's apps by name, without icons. Reversible:
  `launcher.lua`'s scopes and `launcher_hs.lua`.
- **A browser tab finds its window by the window's name,** which
  AppleScript and Accessibility both give, since their window numbers
  differ; two windows with one name leave the tab without a workspace
  *(unverified that the names always agree)*. Reversible:
  `launcher.tab_window`.
- **Browser tabs arrive after the switcher opens,** through `osascript`
  as a task, and a browser that hasn't answered in 2 s is skipped this
  time. Reversible: `launcher_hs.lua`'s `fetch_tabs` and `TAB_TIMEOUT`.
- **The Windows tab lists windows most recently used first,** then the
  rest by id. Reversible: `launcher_hs.lua`'s `windows`.
- **Launches from home that ask:** apps from the switcher, app keys and
  Cmd+Return. Settings panes, commands and tabs don't. Calendar, Chat and
  YouTube Music's keys are marked as home's apps. Reversible: `keys.APPS`
  and `launcher_hs.lua`'s `run`.
- **The dashboard no longer shows a workspace on a digit key,** since
  workspaces have names. Reversible: `dashboard.js`'s keydown.
- **Names are compared with a built-in case folding** for Latin (Latin-1
  and Extended-A), Greek and Cyrillic letters; other scripts compare as
  written. Lua has no Unicode case mapping of its own. Reversible:
  `wm.fold`.
- **A dialog stays with its parent:** a new dialog joins its parent's
  workspace, its parent being its app's focused window, before home's
  apps are routed home. Reversible: `wm.parent_ws`.
- **Names are one line, with runs of space made one and the ends
  trimmed;** a blank name moves nothing. SPEC.md sets no length; tide for Linux caps
  names at 32 characters. Reversible: `wm.clean_name`.

- **The bar floats at the floating window level,** above every app's
  windows and below the menu bar, so the auto-hidden menu bar still shows
  over it. A float dragged to the top goes under it. Reversible: the
  `level` in `bar_hs.lua`.
- **The battery, network and keep awake are read every 5 s;** audio,
  cameras and the input source have watchers. A battery or network change
  takes up to 5 s to show. Reversible: `hs.battery.watcher` and
  `hs.network.reachability` in `bar_hs.lua`.
- **macOS's own full screen hides the bar only while that window is
  focused,** on its display. tide hears of focus changes but not of Space
  swipes, so a full-screen window swiped away from but still focused may
  keep the bar hidden *(unverified)*. The alternative is tracking Spaces
  through `hs.spaces`. Reversible: `bar.hidden` in `bar.lua`.
- **A chip's attention icons are in layout order, then floats by window
  id, up to five, then `+n`,** as the chips' icons were before they showed
  only attention; an app with no icon is a blank square rather than left
  out, so the count matches the windows. Reversible: `apps_of` in `bar.lua`
  and `renderWorkspaces` in `bar.js`.
- **A click on the bar may make Hammerspoon the front app** *(unverified)*,
  emptying the title until focus moves. Reversible: hand focus back after
  a click, as the dashboard does on closing.

- **tide for Linux's geometry, direction and clocks modules are copied, not shared.**
  `hammerspoon/tide/geometry.lua`, `direction.lua` and
  `dashboard/tide-clocks.js` are tide for Linux's files unchanged, and CI fails if
  they drift (`make check-tide`).
  The alternative is a git submodule of tide. Reversible: swap the copies
  for the submodule paths.
- **No frame-offset store.** tide for Chrome stores, per app, how far a window's frame
  lands from where it asked (tide for Chrome SPEC.md §5.3). tide leaves an app that
  rounds its size where it settled. Reversible: add the store in `wm.lua`'s
  retile if gaps or overlaps show up on a Mac.
- **The master count never drops below one,** in every mode. tide for Linux's tile
  can go to none. Reversible: one line in `layout.nmaster`.
- **How tide tells Karabiner is ready:** its config has a rule whose
  description starts `tide:` (or `timo:`, from before the rename), and
  `Karabiner-Core-Service` or `karabiner_grabber` is running, checked every
  30 s. Unverified on a Mac.
  Reversible: `keys.karabiner_ready`.
- **Insert is bound as the Mac's Help key,** which a PC keyboard's Insert
  sends *(unverified)*. Reversible: one line in `keys.map`.
- **Only a standard window floats for being a fixed size** (SPEC.md §5.1,
  step 4). A fixed-size window reporting `AXUnknown` or no subrole, such as
  Chrome's find bar and tooltips, is left alone, where it used to float and
  be centered on Chrome's window. Reversible: drop the subrole check from
  step 4 in `rules.decide`, or a user rule per app.
- **Bitwarden's pop-outs are found by their title,** exactly "Bitwarden",
  in Chrome and Brave (SPEC.md §5.1). A pop-out of another extension, or a
  site's sign-in popup, still tiles: telling a browser's popup window from
  its ordinary ones needs a look at what Accessibility says about each on
  a real Mac. Reversible: the two rules in `rules.defaults`.
- **A tile's new title decides it again for its first 3 s**
  (`wm.SETTLE`), tile to float only, so a popup named after it opens
  floats once named. It shows as a tile for that moment. One you tiled or
  floated with Super+Shift+F stays as you put it. Reversible:
  `wm.retitled`.
- **A window with no close button from an app out of the Dock is left
  alone** (SPEC.md §5.1, step 3), as AeroSpace does: Notification Center,
  Control Center, Spotlight, menu bar apps' panels. A menu bar app whose
  real window has no close button would need a user rule to float or tile.
  Reversible: step 3 in `rules.decide`.
- **Every new float is centered,** even one that opens where it remembers
  being. SPEC.md §5.1 wants those left in place, but tide can't yet tell
  them apart. Reversible: skip `place_float` for a float that opens away
  from the display's origin, say.
- **A tile's height can't be dragged.** tide for Linux's stacks are equal rows, so a
  tile dragged taller or shorter snaps back; only the split between columns
  follows a drag. Reversible: give each stack row a weight in the layout.
- **Super+drag shows an outline and moves the window on release,** rather
  than moving it live, since each move is a round trip to the app.
  Reversible: call `set_frame` from the drag's `update` instead.
- **Focus follows mouse tells a menu is open from the window list:** any
  on-screen window at the pop-up menu level (101) pauses it *(unverified
  for every kind of menu)*. Mission Control isn't watched for; the hit test
  landing on something unmanaged stands in *(unverified)*. Reversible:
  `AXMenuOpened` observers in the adapter.
- **A window minimized before tide first starts counts as yours,** so tide
  never restores something you put away. Reversible: `wm.add`.
- **Restarts match windows by app and title, closest first** (SPEC.md
  §6.3). A window keeps its saved place by id only if the app matches. If
  not, it takes the place of its app's window whose title is most alike:
  the same title first, then the most in common at the start and end. With
  no title alike at all, any of its app's places still counts. Places are
  kept for 10 minutes, at most 50: a saved window that hasn't come back
  since tide started, or a window whose process quit, even if the app is
  running again already. A window you close while its process runs leaves
  no place, so its next window opens where you are. An app that quits when
  its last window closes leaves one, though. *Unverified:* that
  `hs.application.applicationForPID` no longer finds a process by the
  time its windows are reported gone. A window saves its current index,
  so if tide restarts while an app is still bringing windows back, the
  rest may land out of order around the ones already back. That's the
  price of a stack you've rearranged since staying put. Reversible:
  `wm.match`, `wm.KEEP` and `wm.snapshot`.
- **App keys run tide for Linux's helpers** (`browser1`, `google-calendar`, …)
  through `runenv`, as tide for Linux does. Each has a macOS branch in scripts:
  `chrome` opens Google Chrome with `open -na`, so the browsers and web apps
  work, `home` opens Finder, `notepad` TextEdit and `irc` HexChat
  *(unverified per key on a Mac)*. Each press starts its helper, so a web
  app key opens another window, as on tide. A helper that fails says so in a
  notification. Super+T opens a new kitty window, by bundle ID. Reversible:
  `keys.APPS`.
- **Screenshots are saved and copied** (SPEC.md §10): macOS's own keys save
  each to Screenshot's folder, and tide copies each new file there that
  macOS tagged as a screen capture to the clipboard, so a shot taken with
  macOS's keys directly is copied too. They keep macOS's names ("Screenshot … at ….png"), not
  tide for Linux's `YYYY-MM-DD_HH-MM-SS.png`. Reversible: put Ctrl back in
  `keys.SCREENSHOT` and drop the watcher for the clipboard alone.
- **Do Not Disturb runs a Shortcuts shortcut** named "Toggle Do Not
  Disturb", which you make once; macOS has no public switch for Focus.
  Reversible: `launcher_hs.lua`'s `QUICK.dnd`.
- **Cmd+Return on a running app presses Cmd+N** to get a new window on the
  empty workspace; an app without that shortcut just comes forward.
  Alternative: `open -n`, which starts a second copy of the app. Reversible:
  `hs_adapter.lua`'s `launch`.
- **The launcher isn't kept out of screen shares** (SPEC.md §9): no part
  of Hammerspoon sets a window's `NSWindow.sharingType`. Checked in its
  source at release tag 1.4.27 and at `main` on 2026-07-08 (23e387e):
  - nothing in any extension names `sharingType`;
  - `hs.chooser` gives no handle to its window;
  - `hs.webview:hswindow()`, `hs.canvas` and `hs.drawing` give an
    `hs.window` or a drawing, and neither has a sharing setting.

  Doing it would take a compiled Objective-C bridge or a private call, so
  it waits for Hammerspoon to add one. Reversible once it does.
- **Notification Center's banners are told apart by their text**
  (2026-11-05): two identical banners showing at once mark once.
  Reversible: `M.notifications` in `hs_adapter.lua`.
- **The focus guard guesses what you asked for from your input**
  (SPEC.md §14.1). A focus is yours if it's another window of the app you
  were in, one tide asked for, one that follows a click, Return or a key
  with Command within 1 s (or Command is still down, for Cmd+Tab), or one
  that moves on because the window you were in went away. An app key or
  the launcher grants its app's window 10 s, once. A click or Return also
  grants 10 s, once, to a window of an app that had none open before it,
  standing in for launches from the Dock, Spotlight or Finder. Anything
  else is marked and focus goes back *(unverified that it lands before a
  keystroke)*. Alternative: watch `hs.application.watcher` launches rather
  than guess from input. Reversible: `wm.may_focus`.
- **An app that takes focus straight back keeps it,** marked, rather than
  being fought over; and while the launcher, dashboard or resize mode is
  open a thief is only marked, not handed back. Reversible: `wm.refuse`.
- **The guard watches window focus, not app activation:** an app that
  activates itself with no window isn't caught. A launch with no bundle ID
  (a helper script, an app found by path) grants any app's window, and
  `open .` from a terminal is covered only by the Return grant, so a Finder
  that already has windows is refused. Reversible: `wm.grant`.
- **The menu bar chips are text:** `[3]` showing, `2` occupied, `4!` wanting attention. Reversible: draw them with
  `hs.canvas` into the status item's icon.
- **Hammerspoon's console and preferences float, and its other windows are
  left alone** by built-in rules, matched by title, so tide doesn't place
  its own launcher and dashboard. Reversible: the rules in `rules.lua`.
- **The dashboard is on Super+Shift+Space,** next to the launcher on
  Super+Space; tide for Linux has no dashboard key to match. Reversible: one line in
  `keys.lua`.
- **With no clocks file, the clocks are tide for Chrome's,** Sydney, Los Angeles,
  New York and London (SPEC.md §8), not tide for Linux's San Francisco, New York and
  London; tide for Linux's `clocks.json` or `clocks.local.json` sets them on both.
  tide for Linux's `hour24` and `dedupeLocal` aren't followed, since tide for Chrome's view is
  always 24-hour and always hides local. Reversible: `DEFAULT_FILE` in
  `dashboard/settings.js`.
- **The dashboard has no search;** the launcher stays `hs.chooser`, with
  tide for Chrome's scopes (Launch, Tabs, Attention) moved between with Tab. The
  alternative is tide for Chrome's whole launcher page in the webview, which needs a
  stand-in for the Chrome APIs it calls. Reversible: add the page later.

## Check the Floating section on a real Mac

Only the tests have run these (SPEC.md §5.1, §15):

- A rule added on the section floats an open tiled window of that app at
  once, and one on a hidden workspace once it shows.
- *Floating now* lists a window floated with Super+Shift+F, and Always
  float fills the fields with its title selected.
- Super+Shift+I opens the section filled in, with *More about this
  window* closed until clicked.
- The "Always float APP?" notification shows both actions, as an alert
  and as a banner, and each does what it says.

## Check workspace settings on a real Mac

Only the tests have run (SPEC.md §6.2): with a workspace's `askForName` on,
a new window and a launch there ask; with "in"'s off, nothing does. Pin
Gmail on "in" and check Super+Backspace, the prompt's Esc, Cmd+W,
Cmd+Shift+W and Cmd+Q each leave it open with a notification, that another
app's window still gets Cmd+W, and how soon after a click on the pinned
window Cmd+W is held.

## Check the picker on a real Mac

Hammerspoon can't run here, so only `tests/picker_test.lua` (the history,
the skipped types, the rows and the character search) and CI's smoke test
(the `hs.*` names exist) cover Super+V. On a Mac, check that the chooser
opens and Tab switches tabs; that a copy from Bitwarden, 1Password or
Passwords never shows on the Clipboard tab; that Return pastes into the
app you were in, a terminal too; that Shift+forward delete forgets an entry; and that emoji draw. On the Fill tab (Super+Shift+V), check that rbw's rows list, that Unlock asks for the master password and comes back, and that Return types a password into Safari and a terminal.


## Brave's tabs in the Windows tab

**Built** (SPEC.md §2.5, §9): Brave is asked for its tabs with Chrome's
script, as "Brave Browser" (`com.brave.Browser`), and a chosen tab is
brought forward the way Chrome's is. Only `tests/launcher_test.lua` covers
it. **Check on a Mac** that Brave answers, that macOS asks for Automation
for Brave once, and that a Brave window's tabs land under its window.

## The volume popover

**Built** (SPEC.md §8): a click on the speaker opens a slider, mute,
the outputs and Sound Settings under it. Only `tests/volume_test.lua` and
`tests/volume_page.cjs` cover it. **Check on a Mac** that it opens under
the speaker, takes focus and closes on a click elsewhere, that dragging the
slider follows on the built-in speakers and sets a DDC monitor on release,
and that picking an output switches it.

## A monitor's speakers over DDC

**Built** (SPEC.md §8): the bar reads a monitor's own volume and mute
with `m1ddc` (Apple silicon) or `ddcctl` (Intel), and a click or scroll on
the speaker sets them. Only `tests/ddc_test.lua` covers it, with fake tool
output taken from each tool's source. **Check on a Mac** that `m1ddc
display list`'s UUIDs match `hs.screen`'s, that the monitor's speakers are
named as the display is, that the reading follows the monitor's own
buttons within 30 s, and that the log names the reason when it can't
read.

**Built:** the volume keys step and mute a monitor's speakers read over
DDC, with a sign saying the level. Only `tests/bar_test.lua` covers the
choice of keys. **Check on a Mac** (Intel with `ddcctl` and Apple silicon
with `m1ddc`) that the keys reach the eventtap rather than only macOS's
sign, and that holding a key repeats.

## Check notifications and bells on a real Mac

- Which of `AXWindowCreated`, `AXCreated` and `AXLayoutChanged` fire on
  `com.apple.notificationcenterui` as a banner shows, and whether a banner
  has `AXStackingIdentifier` and an "App, title, body" `AXDescription`
  (SPEC.md §14.2). If neither names the app, try the banner's children.
- That a Chrome banner's body leads with its site.
- That conf's `command_on_bell` gets `KITTY_WINDOW_ID`, and that `kitten @
  ls`'s `platform_window_id` is the window's `hs.window:id()`.
