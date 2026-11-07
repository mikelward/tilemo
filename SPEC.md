# tidemo: tide for Linux and tide for Chrome on macOS

**Status: exploration.** This explores what macOS allows. It doesn't
yet decide what tide is. It takes everything tide for Linux does on Linux
([mikelward/tide](https://github.com/mikelward/tide)) and tide for Chrome does on
chromeOS ([mikelward/tideco](https://github.com/mikelward/tideco)), and says, for
each one, how a Mac can do it, how well, and at what cost.

The setup this would replace already exists: `setup-macos` in
[mikelward/scripts](https://github.com/mikelward/scripts) installs Amethyst
and Karabiner and rebinds the Spaces shortcuts. Its `docs/MACOS.md` compares
Amethyst, yabai and AeroSpace, and this spec builds on that comparison rather
than repeating it.

Claims about Apple or third-party behavior carry a source. Anything not
checked against a source or a Mac is marked *(unverified)*.

## 1. Goals

- **Everything tide for Linux and tide for Chrome do,** where macOS allows it:
  - window management: layouts, named workspaces and the dim;
  - keys: one key map across the three desktops;
  - one switcher for apps, workspaces, windows and tabs, and a dashboard
    with clocks and a calendar;
  - attention, focus, idle, theme, and the setup checklist.
- **The same key map and layouts** as tide for Linux and tide for Chrome, so a hand moving
  between Linux, chromeOS and a Mac doesn't notice. Where those two
  differ, tide follows tide for Linux, since macOS can bind all of its keys (§7).
- **No SIP changes.** A managed work Mac can't lower its security, and a
  personal one shouldn't have to.
- **Say what can't be done,** as tide for Chrome §2 does for chromeOS, so nobody spends
  a week finding out (§13).
- **Never degrade silently.** Fallbacks are tide's to choose: Option for
  Super without Karabiner (§7.1), Cmd+N for a kitty window without its
  socket (§6.3), the title for a workspace name without its patterns
  (§6.2). But whenever something a feature depends on is missing or out of
  date (Karabiner or its rule, a permission, an app, a config file, a
  helper), tide says so where you'll see it:
  - a notification, once each time it changes, naming what's missing and
    what stops working, and how to fix it;
  - a line in `tide doctor` saying the same, for as long as it lasts
    (§15).

  A key that does nothing, or a feature quietly turned off, is the
  failure this rules out.
- **One way in to every feature.** Each feature in this spec has its
  place in tide for Linux's settings window, the switcher or a key, whoever does the
  work: tide, macOS, or a helper such as LinearMouse or Karabiner (§15).
  - What tide can change itself, it changes there, even in another
    app's settings file when that app reloads it, as Karabiner does.
  - What it can't gets a button that opens the app or System Settings pane
    that can, on that feature's page.
  - No row only shows a value: a setting has a control, or a button to
    where it's changed.

## 2. What macOS allows

### 2.1 Moving other apps' windows: the Accessibility API

- **What it does:** `AXUIElement` lets an app list another app's windows, and
  move, resize, raise, focus, minimize and unminimize them. Every macOS
  window manager uses it: Amethyst, yabai, AeroSpace, Rectangle and
  Hammerspoon.
- **Permission:** the user grants **Accessibility** to the app once, in
  System Settings › Privacy & Security. An update or a re-signed build can
  reset the grant (scripts `docs/MACOS.md`, Troubleshooting).
- **Window IDs:** AeroSpace says the one private call it needs is
  `_AXUIElementGetWindow`, which maps an accessibility window to its window
  server ID. Everything else it does is public API
  ([AeroSpace README](https://github.com/nikitabobko/AeroSpace)).
- **Limits:**
  - Apps can refuse or round a size: terminals snap to their character grid,
    and apps with a minimum size leave gaps or overlap.
  - Each call is a synchronous round trip, so one hung app stalls a retile
    (scripts `docs/MACOS.md`).
  - Title bars and rounded corners stay. No public API removes another
    app's frame.
- **Not allowed in the Mac App Store:** the sandbox can't control other
  apps, so tide ships outside the store (§12).

### 2.2 Global keys

- **Without any permission:** Carbon's `RegisterEventHotKey` still works, and
  asks for no permission, on current macOS, including macOS 26
  ([go-macos/hotkey](https://pkg.go.dev/github.com/go-macos/hotkey)). It
  binds a fixed key and modifier set, and fails silently if another app
  already holds the combination.
- **With Accessibility:** a `CGEventTap` sees every key before apps do. That
  allows remapping, held-modifier tricks, and taking a key from the system.
- **What the system owns:** Spotlight, Mission Control and the Spaces keys
  live in `com.apple.symbolichotkeys`, which can be rewritten. `setup-macos`
  already does that (scripts `docs/MACOS.md`, "How desktop switching
  works").
- **So unlike chromeOS,** where an extension's keys work only while Chrome
  has focus (tide for Chrome §2.2), every tide for Linux key can work everywhere on a Mac.

### 2.3 Spaces: no public API

- **Native Spaces:** nothing public can switch to "desktop 3" or move a
  window there. The ways in are:
  - **symbolichotkeys:** rebind the system's own "Switch to Desktop N", which
    WindowServer enforces. It's reliable once live, but each Space has to
    exist first (scripts `docs/MACOS.md`).
  - **Private window-server calls:** these move a window to a Space.
    Amethyst's `throw-space` uses them, and so does yabai 7.1.25 (May 2026)
    with SIP enabled, through
    `SLSBridgedMoveWindowsToManagedSpaceOperation`, checked on macOS 26.4.
    They break when macOS changes (scripts `docs/MACOS.md`, yabai#2788).
  - The Space switch always animates. Reduce Motion turns the slide into a
    crossfade.
- **Emulated workspaces (AeroSpace's way):** keep everything on one Space,
  and park the windows of hidden workspaces outside the visible area. Its
  maintainer describes the windows as placed "outside of visible area of the
  screen", and a user reports them tucked into the lower-right corner
  ([HN](https://news.ycombinator.com/threads?id=irth)).
  - It switches instantly, and the workspace count is just config.
  - But Cmd+Tab and Mission Control show every workspace's windows, and
    native full-screen apps misbehave (scripts `docs/MACOS.md`). tide
    turns Mission Control off and has its own overview instead (§6.9).
  - **tide parks this way by default** (§6). macOS won't move a window
    wholly off screen, so a parked window keeps a 1 pt sliver inside a
    corner of its display, as AeroSpace's do *(unverified on a Mac)*.
- **Minimizing (tide for Chrome's way):** hide a workspace by minimizing its windows.
  It's public API, but every switch plays the Genie animation, and minimized
  windows pile up in the Dock *(unverified at scale)*. It was tide's
  first choice; it's now the `hide = "minimize"` setting (§6).

### 2.4 Drawing over the desktop

- **Own windows only:** an app can draw its own windows at any level: a
  borderless panel, a full-width bar, a dashboard, an overlay. It can't draw
  inside another app's window, and it can't move the menu bar.
- **The dim:** HazeOver lays "a translucent dark layer behind" the window in
  use, rather than shading each other window
  ([HazeOver help](https://hazeover.com/help.html)). It needs
  Accessibility to follow focus reliably. An `hs.canvas` can only be
  ordered against Hammerspoon's own windows, not just below another app's,
  so tide's layer goes over the windows instead, with a hole where the
  focused one is (§5.6).
- **A bar:** SketchyBar is a free, open-source menu bar replacement that also
  shows the system's own menu bar items
  ([SketchyBar](https://github.com/felixkratz/sketchybar)). It sits over a
  menu bar set to hide automatically *(unverified detail)*.
- **Borders:** JankyBorders (`brew install borders`) outlines the focused
  window, with SIP fully on (scripts `docs/MACOS.md`).

### 2.5 Reading what other apps are doing

- **Window list:** `CGWindowListCopyWindowInfo` lists every window and its
  owner. Its window names need the **Screen Recording** permission
  *(unverified on macOS 26)*. Accessibility's `AXTitle` gives the same
  titles with the Accessibility grant alone, which is how yabai and
  Amethyst read them *(unverified on macOS 26)*. So tide shouldn't need
  Screen Recording at all.
- **Notifications:** no public API lets an app read other apps'
  notifications. Notification Center's banners are Accessibility elements,
  though, in `com.apple.notificationcenterui`, each saying its app and text,
  so tide reads them as they appear (§14.2) *(unverified on macOS 26)*.
  The database behind them needs Full Disk Access, so tide leaves it
  alone.
- **Unread counts** are in Dock badges (Accessibility's `AXStatusLabel`)
  and window titles, but tide no longer reads them: a count rises with
  every message, wanted or not (§14.2).
- **Browser tabs:** Chrome, Brave and Safari list their tabs, with titles
  and addresses, to AppleScript or JavaScript for Automation. Brave carries
  Chromium's AppleScript dictionary, so it's asked as Chrome is, as
  `"Brave Browser"` *(unverified on a Mac)*. The user grants
  **Automation** per browser the first time *(unverified on macOS 26)*. That
  gives tide for Chrome's tab search without an extension, as the switcher's
  Windows tab (§9).

### 2.6 What macOS does natively

- **Tiling, since macOS 15 Sequoia:**
  - Fn-Control-F fills the screen and Fn-Control-C centers a window.
  - Fn-Control with an arrow takes half the screen; adding Shift arranges a
    second window alongside.
  - Fn-Control-R restores the window's size.
  - ([Apple](https://support.apple.com/guide/mac-help/mchl9674d0b0/mac),
    [9to5Mac](https://9to5mac.com/2024/07/19/use-automatic-window-tiling-macos-sequoia/),
    [SlashGear](https://www.slashgear.com/1673225/macos-sequoia-window-tiling-shortcuts))
  - It's manual snapping, not dwm layouts, and it has no API.
- **Spotlight in macOS 26 Tahoe:** runs actions, including ones apps provide
  through App Intents. It also has Quick Keys (short typed abbreviations)
  and clipboard history
  ([MacMost](https://macmost.com/how-to-use-spotlight-actions-in-macos-tahoe.html),
  [iThinkDiff](https://www.ithinkdiff.com/spotlight-macos-tahoe-quick-keys-clipboard/)).
  tide's commands could appear there as App Intents, beside its own
  launcher.
- **Pointer acceleration:** Sonoma added an on/off switch, under System
  Settings › Mouse › Advanced. `defaults write -g com.apple.mouse.scaling`
  takes values beyond the slider's range, and a log-out applies them
  ([iBoysoft](https://iboysoft.com/wiki/macos-mouse-acceleration.html),
  [NoMouseAccel](https://github.com/apsun/NoMouseAccel)).
- **The rest:** Notification Center, Focus modes, screenshots, lock, US
  Dvorak, and dark mode on a sun schedule are all native (§10).

## 3. Three ways to build it

| | A. Configure existing tools | B. Hammerspoon config | C. A native tide app |
|---|---|---|---|
| What | Amethyst, Karabiner, Spotlight or Raycast, SketchyBar, JankyBorders or HazeOver, as `setup-macos` does now | One Lua config on [Hammerspoon](https://www.hammerspoon.org), which wraps windows (`hs.window`), keys (`hs.hotkey`), drawing (`hs.canvas`) and a picker (`hs.chooser`) | One Swift app: window manager, keys, launcher, bar and dim |
| Layouts | Amethyst's built-ins match Krohnkite's. JavaScript layouts are possible | **tide for Linux's own Lua layout**, which is pure Lua by design (tide for Linux AGENTS: "keep geometry free of the `hl` API") | Port tide for Linux's or tide for Chrome's geometry |
| Workspaces | Native Spaces, via symbolichotkeys | Emulated, parking windows off screen (§6), or minimizing, or native Spaces through community modules | Any of §2.3 |
| Launcher and dashboard | Spotlight, or Raycast (free, with a paid tier) | `hs.chooser` plus canvases. Basic, but enough for tab search | Full control, like tide for Chrome's dashboard |
| Dim | HazeOver ($5) or borders | A canvas layer over the windows, a hole for the focused one (§5.6) | Own layer, as HazeOver does |
| Focus follows mouse | Off: Amethyst's breaks popovers (Amethyst#337) | tide's own (§5.2) | Same |
| Cost to build | Done | Days to a first version | Weeks |
| Breakage risk | Amethyst's throw-to-space on private API | Hammerspoon's community `spaces` modules | Ours to fix |

**Recommendation: B first, then decide on C.** Hammerspoon runs tide for Linux's
layout code unchanged, gets every tide for Linux key working everywhere, and shows
within days which parts macOS fights. Whatever turns out to need native
code becomes the case for C. Which Lua version Hammerspoon embeds
is *(unverified)*: tide for Linux's layout targets 5.4 and 5.5.

## 4. Feature map

Status: **yes** = tide or macOS meets the tide for Linux or tide for Chrome behavior;
**partial** = close, with the gap named; **no** = not reachable.

| tide for Linux / tide for Chrome | On macOS | Status |
|---|---|---|
| Tile, three-column, two columns + stack, monocle (tide for Linux §6.1) | tide for Linux's Lua layout over Accessibility moves (§5) | **yes**, with apps' own size limits |
| Lone window 80% on ultrawide, 60% from 32:9 | same layout, per display (§5) | **yes** |
| New windows join the end of the stack, with a setting for elsewhere (tide for Linux §6.1) | tide state (§5) | **yes** |
| Layout, `mfact`, master count per workspace, and per display within it | tide state | **yes** |
| Named workspaces, "in" first, Super+Home to "in", Super+Return to go and Super+Shift+Return to move (tide for Linux §6.5) | windows parked off screen, as AeroSpace does, or minimized as tide for Chrome does, named in tide's state (§6) | **partial**: Mission Control would show every workspace's windows, so setup turns it off and tide's overview takes its keys (§6.9); a sliver of each parked window shows in a corner; minimizing instead animates each switch |
| A new window on a workspace that asks, "in" by default, asks for a workspace name (tide for Linux §6.5) | tide's name prompt, an `hs.chooser` (§6.2) | **yes** |
| Pinned apps stay open on their workspace (tide for Linux §6.5) | the close key and the prompt's Esc leave them open; Cmd+W, Cmd+Shift+W and Cmd+Q are hotkeys while one has focus (§6.2) | **partial**: by app name; the close button still closes |
| `TIDE_WORKSPACE` in launched apps (tide for Linux §6.5) | `hs.task`'s environment, `open --env`, and kitty's remote control (§6.3) | **partial**: an app already running keeps its own |
| One workspace per monitor from a shared pool (tide for Linux §6.5) | decided against: one workspace spans every display, each display with its own layout in it (§6.1) | **differs** |
| Dim inactive, 0.12, not a lone window or video (tide for Linux §6.2) | one dark layer over the windows, a hole for the focused one (§5.6) | **partial**: dims the desktop too; drawn only in CI's smoke test, not yet checked by eye on a Mac |
| No borders, no gaps | gaps 0; title bars stay | **partial** |
| Maximize, fullscreen, restore (tide for Linux §6.3) | tide's own, on the same workspace (§5.4) | **yes**; native full screen is its own Space (§13) |
| Picture-in-picture pinned bottom-right on every workspace (tide for Linux §6.4) | left alone and never minimized (§5.5) | **partial**: its place is the app's |
| Dialogs float, centered | rules, subrole, fixed size and modality (§5.1) | **yes** *(unverified per app)* |
| Super+drag moves, Super+right-drag resizes (conf `hyprland.lua`) | an event tap on mouse buttons with Super held (§5.3) | **yes**, with Accessibility |
| Drag a tiled window's edge to set the split (tide for Chrome §5.3) | Accessibility's resize notification (§5.3) | **yes** |
| Drop a dragged tile on another to swap them (tide for Chrome §5.3) | Accessibility's move notification (§5.3) | **yes** |
| Super+middle-click maximizes the window under the pointer (tide for Linux §6.6) | the same event tap (§5.3) | **yes** |
| Resize mode for floats, Super+Shift+R (tide for Linux §6.6) | a tide key mode (§5.3) | **yes** |
| Focus follows mouse (KDE) | tide's own (§5.2) | **yes**, but focusing raises (§13) |
| Nothing steals focus (tide for Linux §14) | macOS activation rules, plus tide's focus guard (§14) | **partial**: apps can still activate themselves |
| Super+A lists the windows wanting attention, newest first (tide for Linux §14.4, tide for Chrome §10.3) | Notifications, bells, and apps activating themselves (§14.2) | **partial**: a banner a Focus hides marks nothing |
| Minimize by key, restore from a tray of icons in the corner (tide for Linux's design) | `Super+Z` and an `hs.canvas` tray per display (§6.7) | **yes** *(unverified on a Mac)* |
| Full-width bar with workspaces and urgency (tide for Linux §7) | tide's own bar over an auto-hidden menu bar, with its own status items (§8) | **partial**: app menus and other apps' status items still need the menu bar revealed |
| SYD / LAX / NYC / LON clocks (tide for Chrome `src/clocks.js`) | bar clocks, and tide for Chrome's clock panel in the dashboard | **yes** |
| One switcher with tabs: launcher, workspaces, windows, attention (tide for Linux §8) | tide's switcher, an `hs.chooser`; the lone Super tap needs an event tap or Karabiner (§7, §9) | **yes** |
| Clipboard history and characters by name on Super+V (tide for Linux §8.4) | an `hs.pasteboard` watcher and an `hs.chooser` with two tabs (§9.1) | **partial**: text only |
| Browser tabs in the Windows tab (tide for Chrome §9.4) | Chrome, Brave and Safari tabs through AppleScript (§2.5) | **yes**, with Automation granted |
| App keys (tide for Linux `hyprland.lua`, tide for Chrome §9.1) | global keys that bring an app's window, and its workspace, forward (§7) | **yes** |
| Second and third Chrome profiles (`browser2`, `browser3`) | separate `--user-data-dir`s, as tide for Linux runs them (§7) | **yes** |
| Notifications, history, DND (tide for Linux §9) | Notification Center and Focus | **yes**, native |
| Idle: dim, lock, off, suspend (tide for Linux §10) | Energy and Lock Screen settings; `caffeinate` or an IOPM assertion to keep awake | **partial**: system timings |
| Lock = login, short hostname | macOS lock and login | **partial**: no hostname |
| Screenshots, to the clipboard and a folder (tide for Linux §13) | macOS's own screenshot keys on tide for Linux's Print keys, and a watcher that copies each saved shot (§10) | **yes**, with macOS's file names |
| Meet: share a 16:9 slice of an ultrawide (tide for Linux §12) | ScreenCaptureKit can share a region *(unverified in Meet)* | **partial** |
| Light and dark by time (tide for Linux §15) | Appearance › Auto follows the sun; a fixed 07:00–19:00 needs a scheduled job | **yes**, with a job |
| US Dvorak | native input source | **yes** |
| Mouse: fastest, acceleration on, left-handed, wheel 3× (conf `hyprland.lua`) | Mouse settings and `com.apple.mouse.scaling`; the wheel's speed and direction through LinearMouse, from tide for Linux's `input.json` (§10) | **partial**: the wheel **yes**; speed and left-handed in Mouse settings |
| Touchpad: natural scroll, tap to click; mouse not natural | Trackpad settings (§10) | **partial**: one natural-scroll switch for both *(unverified)* |
| Key repeat: 600 ms, 25 a second | `InitialKeyRepeat` and `KeyRepeat` (§10) | **partial**: macOS's steps |
| Caps Lock as Compose | Caps Lock sends F18, and tide reads the keys after it from Linux's own Compose table (§10) | **yes** *(unverified on a Mac)*: not during Secure Input |
| Setup checklist (tide for Chrome §3.4) | a settings page with deep links to System Settings panes (§10) | **yes** |
| Settings pages, shared `~/.config/tide` files, `.local` overrides (tide for Linux §16) | tide reads the same files (§15); every page of tide for Linux's is a section, with buttons to macOS's panes and the helpers for what tide can't change | **partial**: Clocks, Layouts, Workspaces, Start at login, Clipboard, the muted list, Floating, Keyboard's Shortcuts and the Setup checklist are tide's own; Appearance is only a button |
| `tide doctor` (tide for Linux §5.4) | `tide doctor` (§15) | **yes** |
| Workspace swipe, three fingers (conf `hyprland.lua`) | the trackpad's touches through an event tap, with macOS's own swipe between Spaces off (§7.2) | **yes** *(unverified on a Mac)* |
| kitty, Ubuntu Mono, shell config | native, through `setup` and `conf` | **yes** |

## 5. Windows and layouts

- **Geometry:** tide for Linux's layout is pure Lua, and tide for Chrome's
  `src/geometry.js` is a tested port of it. The four layouts, the
  single-window rule and the share bounds carry over as they are:
  - tile, three-column, two columns plus a stack, and monocle (tide for Linux §6.1);
  - each workspace's own layout, `mfact` and master count;
  - the default by the display's shape: three-column from an aspect of
    2.1, tile below it;
  - a lone tiled window centered at 80% wide from 2.1, 60% from 3.2, and
    full width below 2.1;
  - floats and full-screen windows don't count toward "one window".
- **New windows join the end of the stack,** and the master stays put. A
  setting puts them at the top of the stack, after the focused window, or
  in as master (tide for Linux §6.1). A window moved in from another workspace, or
  tiled again after floating, counts as new. Amethyst's
  `new-windows-to-main: false` in conf agrees.
- **Applying a layout:** set position, then size, through Accessibility, and
  read the frame back. tide for Chrome reads its windows' bounds back the same way
  (tide for Chrome §5.3), and stores the difference per app, so the next layout
  allows for it. An app that refuses a size gets its own frame, and the
  rest tile around what it took *(design to settle)*.
- **When to retile:** when a window opens, closes, minimizes or comes back;
  when an app launches, quits or hides; when a display changes; and after
  any layout key. tide waits 50 ms after the last of a burst, as tide for Chrome does,
  since one window opening sends several notifications.
- **The mouse** can move and resize windows too (§5.3).

### 5.1 Floating windows and dialogs

Dialogs must float, and stay in front of the window that opened them.
Amethyst gets this wrong: it tiles some dialogs, such as autocomplete lists
(Amethyst#883), and hides others behind their parent (§5.2). tide decides
each new window once, in this order, and the first rule that matches wins.
The one exception is a new title: a tile whose title changes in its first
3 s is decided again, and floats if the rules now say so. A browser's popup
can open before its page names it, and a title rule needs that name.

1. **Not a window: ignore it.** Sheets (`AXSheet`) are attached to their
   window. Popovers, menus, tooltips and the menu bar aren't `AXWindow`s.
   tide never moves, focuses or counts any of them.
2. **A user rule** by app bundle ID and, optionally, title, as tide for Linux's float
   rules (tide for Linux §6.4): `start()`'s `rules` first, then the ones you make on
   the settings window's Floating section (§15). Rules come first so a
   misbehaving app can always be fixed. tide's own rules follow the user's: System Settings floats,
   since its width is fixed though its height isn't, so step 4 misses it
   and a tile would leave a gap beside it. Notification Center's windows
   are left alone, whatever they report: they're macOS's own, over every
   window. Hammerspoon's windows aren't watched at all: tide's own, the
   bar, the launchers and the settings window, and Hammerspoon's console
   and preferences, which stay where macOS puts them. The window filters
   leave Hammerspoon out (`hs.window.filter.ignoreAlways`): watching it,
   a filter asks Accessibility about each of its windows from
   Hammerspoon's own thread, which can't answer while it asks, so each
   question waits out the timeout, a dozen a window. On CI's Mac that held
   everything for 3 s as the launcher showed. And the window manager
   synced and retiled every window as the switcher closed. Nor is
   Hammerspoon asked which of its windows has the focus. While one does,
   tide takes it that none of the windows it manages has it, and a
   close behind it leaves the focus there. The attention poll and the bar
   ask every 2 s, half a dozen times, and on an older Mac that held Esc in
   the switcher for 2 to 3 s. Bitwarden's pop-outs in Chrome and Brave
   float: its extension asks you to sign in, fill a login or use a passkey
   in a popup window titled "Bitwarden". The vault's own tab is titled
   otherwise, and the desktop app is another app.
3. **A window with no close button, from an app that stays out of the
   Dock, is left alone.** It's part of that app's interface, not a window:
   Control Center's and menu bar apps' panels, Spotlight, the input source
   switcher. AeroSpace tells them apart the same way (its
   `isWindowHeuristic`).
4. **A standard window whose size can't be changed floats.** Accessibility
   says whether `AXSize` is settable, which catches fixed-size dialogs whose
   apps report them as standard windows. Other subroles go on to the steps
   below. So a fixed-size popup that's a window of its own, such as
   Chrome's find bar or a tooltip (`AXUnknown`, from AeroSpace's notes), is
   left alone, not floated: a float is centered on its app's window and
   can take focus.
5. **A modal window floats:** one whose app reports it `AXModal`
   *(unverified)*.
6. **A dialog or panel floats:** subrole `AXDialog`, `AXSystemDialog` or
   `AXFloatingWindow` *(unverified per app)*.
7. **A standard window tiles** (`AXStandardWindow`). That comes late on
   purpose: some dialogs report themselves as standard windows, and the
   checks above catch them first.
8. **Anything else is left alone,** such as `AXUnknown`. Extension popups
   and other odd windows mustn't take a tile *(which subrole Chrome's
   extension popups report is unverified)*.

Placing and keeping floats:

- **A new float centers on its parent,** the app's focused window (tide for Linux
  §6.4). One with no parent, like System Settings, centers on its display,
  as on tide. It used to open under the pointer, so the pointer's next move
  wouldn't focus the tile beside it. But a slow app's window, such as About
  This Mac, arrived after the pointer had moved on and landed where it had
  been. Focus follows mouse now leaves a tile alone while another app's
  float is in front of it (below), so the pointer can't bury it either way.
  One that opens already placed, like a palette remembering its spot, keeps
  its place.
- **Floats stay above the tiles.** macOS has no public way to set another
  app's window level. Tiles never overlap, though, so the only thing that
  can cover a float is a tile being raised.
  - **Hammerspoon's own floats** (its console, tide's settings) get a
    floating window level, which macOS honors for the app that owns the
    window. Nothing raised buries them. Its Preferences window floats
    too but keeps the normal level, so it counts as another app's float
    below.
  - **Another app's float** can't be raised back over the app just
    focused: on a Mac, Karabiner-Elements' settings and System Settings
    went behind Chrome a second after it took focus, though tide raised
    them again (§13). So focus follows mouse leaves a tile alone while
    another app's float is in front of it (§5.2), and the float stays on
    top. That holds for a float a rule made, and for one of an app with
    no Dock icon, such as a menu bar app's settings window, which tiles
    unless a rule floats it. Which window is in front comes from the
    window server's list of every window on screen below the Dock's level
    (`hs.window.list`). `hs.window.orderedWindows()` leaves out the apps
    with no Dock icon, so such a float never counted as in front, and the
    tile was focused over it. Of the windows tide doesn't manage, only
    Hammerspoon's console and Preferences stay in that list, by title and
    bounds, so a Super+drag or Super+middle-click over one leaves the tile
    behind alone, as over tide's own windows. tide's own drawing, such
    as the dim and the drag outline, is click-through and stays out. A click or a key still focuses the
    tile, and the float goes behind it.
  - **Nor does a focus tide picks for you.** A workspace switch, a
    window going into the tray, a window closing, a restore finishing,
    focus handed back from an app that took it (§14.1), and the launcher,
    dashboard or volume popover closing each pass over a tile with
    another app's float in front of it. The last used window on that
    workspace that doesn't bury one goes instead, which may be the float
    itself. With none, the tile is focused after all, so something always
    has focus. A key, a click or an app key you choose is unchanged.
  - **The tile's own app's floats** come back with it: tide raises them
    after it focuses the tile, as before.
- **A float's size** is what it asks for, capped at 80% of its display
  (tide for Linux §6.4). tide remembers each app's float size and position until you
  log out.
- **Floats move with their workspace,** as tide for Chrome's do (tide for Chrome §6.1), and are
  minimized and restored with it. A dialog moves with its parent's
  workspace.
- **A dialog from the app you're in takes focus.** One from any other app
  opens unfocused and is marked for attention (§14).
- **Super+Shift+F toggles** a window between tiled and floating, as on tide for Linux
  and tide for Chrome.
- **A window floated by hand can become a rule,** as on tide for Linux (tide for Linux §6.4).
  The Floating section's *Floating now* lists it, and `Super+Shift+I` opens
  that section filled in for the focused window (§15).
  - Floating one with `Super+Shift+F` or `Super+Insert`, when no rule
    covers it, asks once: a notification, *Always float APP?*, with
    **Always float**, which adds the app's rule at once, and **Edit
    rule…**, which opens the section filled in for it. A click on the
    notification itself is Edit rule… too.
    - Closing it, or letting it expire after 30 s, is Not now. That app
      isn't asked about again until the next login, whatever the answer.
      The apps asked about are kept in `hs.settings` with the login, so a
      reload doesn't ask again.
    - "Covers" counts every rule and the steps above that float a dialog,
      as tide for Linux counts `conf`'s dialog rules.
    - Only the keys ask. A window that floats on its own, by a rule or as
      a dialog, never does. tide has no drag that floats a window.
    - macOS shows the two buttons only as an alert, or on a banner you
      hover over; Edit rule… is under the Always float button's menu
      *(unverified on macOS 26)*.

Chrome's windows, from tide for Chrome §5.4 and tide for Linux §6.4:

- **Popups float:** sign-in popups, extension popups and Chrome's own
  "Save as". Each reports a dialog or floating subrole, or is a standard
  window of a fixed size *(unverified per kind)*. One that reports
  `AXUnknown` is left alone, as the find bar, tooltips and hover cards are.
  The popup an extension's button opens is one of those, anchored to the
  button, and left alone. A pop-out window is another matter: an
  extension's `chrome.windows.create({ type: "popup" })`, such as
  Bitwarden's passkey prompt, is a resizable window like any other, and
  tiles unless a title rule floats it. A site's sign-in popup is likely
  the same *(unverified)*.
- **App windows tile:** installed web apps and Secure Shell's terminals
  report as standard windows.
- **Chrome's own notification popups** appear only when Chrome isn't
  allowed to use Notification Center. They'd float if they report a dialog
  subrole or a fixed-size standard window, and be left alone otherwise
  *(unverified which)*. The fix is to allow Chrome's notifications, which
  the checklist asks for (§10).
- **Chrome Remote Desktop** and tide for Chrome's other URL rules can't be read from a
  window. A title rule stands in for each.

**Dialog checklist on a real Mac.** Each must open floating and centered on
its parent, and stay in front:

- TextEdit's Open and Save sheets;
- Chrome's Save As;
- an About window;
- System Settings opened from an app;
- System Settings opened on its own, under the pointer, staying in front
  until the pointer leaves it;
- an Electron app's dialog;
- a JetBrains IDE's dialog;
- Finder's Get Info window.

Bitwarden's passkey prompt, signing in to a site with a passkey saved in
Bitwarden's Chrome extension, must open floating too.

And each of these must be left where its app put it, never moved or
focused by tide: Chrome's find bar (Cmd+F), a tooltip, a link's status
bubble, a tab's hover card, Notification Center's banners and widgets,
and Control Center's panels.

### 5.2 Focus follows mouse

**What it should feel like** is tide for Linux's (tide for Linux §14.2), which is KDE's focus
follows mouse:

- Focus moves to a window when the pointer crosses into it, and nothing
  else moves it.
- Menus, popovers, dropdowns and dialogs stay open and in front while the
  pointer moves over, onto or off them.
- The pointer never jumps.

Amethyst is what `setup-macos` used before tide, and its focus follows
mouse had to be turned off. Its bugs are listed below, so tide doesn't repeat them. It
isn't a model for anything else.

#### How tide decides

Each step either hands on to the next, or stops with focus left where it
is.

1. **Watch pointer moves only.** An event tap, under the Accessibility
   permission (§2.2), sees mouse-moved events.
   - Drags arrive as separate events, so a drag never moves focus.
   - tide never moves the pointer, so it never sees a move of its own
     making.
2. **Track the window under the pointer, and act only when it changes.**
   tide remembers which window the pointer was last over.
   - Moving within that window does nothing, even if focus went elsewhere
     by a key. Hyprland's `mouse_refocus false` does the same, and tide for Linux
     uses it.
   - When a window opens, closes or moves under a still pointer (a retile,
     a workspace switch), tide updates its record without focusing
     anything. A one-pixel nudge afterward isn't a crossing.
3. **Ask the window server what's on top at that point,** the moment the
   pointer leaves the window it was over. There's no wait: focus moves on
   entering, as on tide.
   - So crossing another window on the way to the menu bar focuses it, and
     the menu bar shows that app's menus. Holding Super on the way keeps
     focus where it was (below). The window list
   (`CGWindowListCopyWindowInfo`) comes in front-to-back order, with each
   window's bounds and level. That's public API, and needs no Screen
   Recording permission for those fields *(unverified on macOS 26)*.
   - **If the topmost thing isn't a window tide manages, tiled or
     floating, stop.** That includes a menu, popover, dropdown,
     autocomplete list or tooltip (these sit above the normal level
     *(unverified for every kind)*), the menu bar, the Dock,
     notifications, Spotlight, or tide's own bar.
   - **tide's own windows aren't asked about at all:** the settings
     window, tide for Chrome's launcher, the dashboard, the volume popover and the
     tray. Each says where it is as it shows (`wm.own_window`), and its
     box counts for half a second after it goes, while macOS takes it off
     the screen. They're web pages, and asking Accessibility what's under
     the pointer over one waits on the page, up to a quarter of a second a
     question and a dozen questions a lookup. On CI's Mac that held Esc on
     tide for Chrome's launcher for 3.4 s, and over the settings window it would
     stall each move. The resync after a raise skips them too, and the
     bar and the Dock.
   - **Onto another display's desktop,** with no window there, focus
     stays put but that display takes the keys, as Hyprland's focused
     monitor follows the pointer: a launch opens there (§6.1), and
     Super+Left/Right start from it. Crossing into a window after
     focuses it, and the keys follow.
   - This is the rule Amethyst misses. It looks only among the windows it
     tiles, so the tile under a popover gets focus and the popover closes
     (Amethyst#337, #1566, #1629, #1872).
   - tide checks each move against the part of the last window that no
     other known window covers: its frame, less the frames of the floats
     above it. It asks the window server only when the pointer leaves that
     part, so moving from a tile onto a float over it counts as a crossing.
     That keeps the window list call off the busy path.
4. **Prefer the window's own dialog.** If that window has a sheet or
   drawer, or its app has a float open over it, focus that instead. yabai
   does the same, because macOS won't let the main window take focus from
   its sheet (yabai `src/mouse_handler.c`).
5. **Focus it, then put its floats back on top.**
   - On macOS, focusing a window raises it (§13). Tiles don't overlap, so
     that's harmless, except over a float.
   - So right after raising the window, tide raises its app's dialogs and
     then the workspace's other floats, in their previous order. A dialog
     can never end up behind the window that opened it, which Amethyst
     does (Amethyst#1243, #1026, #473).
6. **One focus in flight at a time.** Until macOS confirms the focus
   change, new moves update the target but don't start another. yabai
   holds back in the same way.
   - The next one starts the moment macOS confirms, or once the wait runs
     out, which can be before tide hears the report for the one before.
     So the focus guard (§14.1) takes every focus tide asked for in the
     last second as asked for, not only the latest. Otherwise it would
     take the window you just crossed for an app stealing focus, and hand
     focus back to where the pointer started.

#### When it stays still

Focus follows mouse pauses, and focus stays where it is:

- **While a mouse button is held,** for a drag, a selection or a resize
  (§5.3).
- **While a menu is open,** from Accessibility's `AXMenuOpened` until
  `AXMenuClosed`, in any app *(unverified across apps)*.
- **While Super is held,** so Super+drag (§5.3) and reaching for the menu
  bar are free. yabai and AutoRaise also pause while a modifier is held.
- **While a system screen is up:** Mission Control, App Exposé, Launchpad,
  Spotlight, Notification Center. It also pauses during a Space-switch
  swipe and for about a second after it, as yabai does (1250 ms).
- **While the pointer is in the menu bar's strip,** including an
  auto-hidden menu bar's reveal edge, or over the Dock or tide's bar
  (Amethyst#1221).
- **While tide's switcher, name prompt, dashboard or overview is
  open.** It keeps the keyboard until it closes (tide for Linux §14.2).
- **While the window under the pointer is a tile with another app's float
  in front of it.** Focusing the tile would bury the float for good (§5.1).
  That includes the tile's own dialog, which step 4 would prefer: focusing
  it activates the tile's app, which can bring the tile forward with it.
  Moving onto the float focuses the float; a click focuses the tile.
- **While an app that must keep focus is in front:** the screenshot picker
  (`com.apple.screencaptureui`) and password prompts
  (`com.apple.SecurityAgent`), from AutoRaise's own list. More can be added
  as a setting, by bundle ID.

#### Around the edges

- **Closing a window** focuses the window under the pointer, or else the
  last one used on that workspace. Something always has focus. Amethyst can
  leave nothing focused (Amethyst#1560). This is tide for Linux's
  `focus_on_close cursor`. A tile with another app's float in front of it
  is passed over while another window will do, so the float stays on top
  (§5.1).
- **No warping, ever.** tide has no "mouse follows focus". `Super+J`,
  the switcher and a new window move focus, not the pointer, as on tide for Linux
  (tide for Linux §14.2). Amethyst's warp sends a fake pointer move that its own
  focus follows mouse then reacts to (Amethyst#995, #1006).
- **More than one display:** every position is in macOS's single global
  coordinate space, never converted per screen. Amethyst's per-screen
  conversion breaks on rotated and offset displays (Amethyst#1150,
  #1120) *(cause inferred from its source)*. Moving onto another display
  follows the same rules. An empty desktop changes nothing.
- **A hung or slow app can't freeze it.** Each Accessibility call gets a
  short timeout (`AXUIElementSetMessagingTimeout`), and an app that misses
  it is skipped. Amethyst's focus follows mouse hangs Java apps
  (Amethyst#342).
- **A key turns it off and on,** for the rare app that misbehaves. It's a
  safety valve, not the fix. Amethyst's only answer to #337 was a toggle
  key *(key to settle in §7)*.
- **In monocle,** only the front window is visible, so there's nothing else
  to cross into, and focus follows the keys.
- **Focusing without raising,** as KDE does, needs a private call, which
  yabai's `autofocus` uses with SIP on. It's listed under §13.

#### Amethyst's bugs, and the rule above that prevents each

| Amethyst bug | tide's rule |
|---|---|
| Popovers, menus, extension popups and dropdowns close as the pointer moves (#337, #1566, #1629, #1872) | Hit-test the topmost window, and stop on anything that isn't a managed window (step 3) |
| A main window comes up over its own dialog or float, hiding it (#1243, #1026, #473) | Prefer the dialog (step 4), and re-raise floats after any raise (step 5) |
| Small modal windows can't keep focus (#889) | Prefer the dialog (step 4) |
| Launchpad, Spotlight and the menu bar close or lose focus (#1221, #1243) | Pause for system screens and the menu bar strip |
| Focus jumps with mouse follows focus on (#995, #1006) | No warping, ever |
| Nothing focused after a close (#1560) | Focus the window under the pointer, or the last used |
| Wrong targets on rotated or second displays (#1150, #1120) | One global coordinate space |
| Java apps hang (#342) | A timeout on every Accessibility call |
| Wide layout focuses the wrong window (#1595, #1705) | Hit-test real bounds, not layout slots *(cause unknown)* |

#### Checklist on a real Mac

Each of these must pass before focus follows mouse is on by default:

- A Chrome extension popup stays open while the pointer moves across it
  and over the window under it.
- Finder's right-click menu, Mail's address autocomplete, and a Calendar
  dropdown stay open while the pointer crosses another window.
- With a TextEdit Save sheet open, pointing at another app's window
  focuses that window, and the sheet stays open. Pointing back at
  TextEdit's window focuses the sheet, not the document under it.
- A Settings window (Notes, say) floats, and stays in front while the
  pointer moves over the tile behind it and back.
- Sweeping the pointer quickly across three apps' windows leaves focus in
  the last, with none of them marked for attention.
- Pointing into Chrome never names Notification Center in the bar, with a
  notification banner showing and without.
- Spotlight, Launchpad and the auto-hidden menu bar stay open while the
  pointer moves.
- Cmd-Shift-4 keeps its region picker while the pointer crosses windows.
- Typing into tide's switcher works with the pointer resting on a window,
  and again after moving it across two (tide for Linux §14.2).
- Moving onto a window focuses it at once, with no wait.
- After `Super+J`, a small move within the old window doesn't take focus
  back.
- A window tiling in under a still pointer doesn't get focus, even after a
  one-pixel nudge.
- Closing a window focuses the one under the pointer.
- A window-edge drag and a Super+drag across other windows change no focus.
- A Space swipe and Mission Control change no focus.
- With two displays, one rotated, focus lands on the window under the
  pointer on both.
- A JetBrains IDE doesn't hang.

### 5.3 Moving and resizing with the mouse

These are tide for Linux's mouse bindings (conf `hyprland.lua`) and tide for Chrome's drag
handling (tide for Chrome §5.3):

- **Dragging a window's own edge or title bar works as on any Mac.** tide
  sees the result through Accessibility's `kAXMovedNotification` and
  `kAXResizedNotification`, and treats it as a request:
  - **Resizing a tile** sets the workspace's split (`mfact`), and its
    neighbors follow as you drag, not only when you let go: tide looks
    every 0.1 s while the button is held, and on each resize notification.
  - **Resizing a lone tile** sets that workspace's lone-window width in place
    of the single-window rule. It stays centered, so the other edge follows
    as you drag, and the width comes back whenever the workspace is down to
    one window. With several windows and no stack, a drag changes nothing.
  - **Mid-drag, the dragged tile is placed too** when the layout keeps the
    edge you hold under the pointer: a centered tile, such as a lone window
    or threecol's middle master, narrows on both sides. When the layout
    wouldn't (a split at its 0.1 or 0.9 limit), the dragged tile is left as
    the pointer has it until the drop *(unverified on a Mac that an app's
    own resize takes a move mid-drag without jitter)*.
  - **A move** still waits for the drop, which may swap it.
  - **Dropping a moved tile** puts it in the tile nearest its center,
    swapping with that tile's window. If the center is on another display,
    the window first moves to that display, in the same workspace.
  - **A moved or resized float** keeps its new frame.
- **Super+drag moves any window, and Super+right-drag resizes it,** from
  anywhere inside it, as on tide.
  - macOS has no built-in way to do this for every app, so tide watches
    mouse buttons with an event tap while Super is held (§2.2), which
    Accessibility covers.
  - A plain click passes straight through to the app. Only a press with
    Super held is taken.
  - Under the rotation, Super is Option (§7.1), and Option-drag means
    something in many Mac apps: Finder copies, and text editors select a
    column. With Karabiner's mapping (§7.1), Super+drag arrives with
    Ctrl+Option+Command held instead, so those stay the apps'. Without
    Karabiner, tide takes them.
  - A resize moves the edge or corner nearest the pointer.
  - When the drag ends, it's handled like a drag of the window's own edge
    (above). A drag on a tile sets the split or swaps tiles, and one on a
    float moves it.
  - **While dragging,** tide shows an outline where the window will go, and
    moves the real window when the button is released. Moving another
    app's window on every mouse event lags, since each move is a round
    trip to that app (§2.1). Hammerspoon's SkyRocket spoon draws the
    outline in the same way *(unverified)*.
- **Super+middle-click** maximizes the window under the pointer, or puts it
  back in its tile, as on tide for Linux (tide for Linux §6.6).
- **Super+Shift+R** enters resize mode for a float. In it, H J K L or the
  arrows resize the window, and Esc or Return leaves. This is tide for Linux's resize
  mode (tide for Linux §6.6). It needs only keys.
- **Focus follows the mouse during none of this** (§5.2). While a button is
  held, focus doesn't change.

### 5.4 One window big: monocle, maximize, full screen

These work as on tide for Linux (tide for Linux §6.3), on the same workspace:

- **Monocle** is a layout. Every window fills the tiling area, and
  `Super+J` and `K` flip between them. New windows open full size. The bar
  shows `[n]`, the hidden count.
- **Maximize** (`Super+Up`) covers the tiling area with just this window.
  It lasts until you press it again, close the window, or focus another
  window on the workspace.
- **Full screen** (`Super+Shift+Up`) covers the whole display, bar and all.
  It's tide's own: a move to the display's whole frame, which works
  over an auto-hidden menu bar *(unverified)*, not macOS's native full
  screen, which moves the window to a Space of its own (§13).
  An app's own native full screen (the green button) is left alone, and
  that window isn't on any tide workspace while it lasts.
- **`Super+Down`** puts it back in its tile from either.
- **macOS brings all of an app's windows forward** when the app is
  activated *(unverified for Accessibility focus)*. In monocle that could
  shuffle the stack, so tide puts the order back after each activation.

### 5.5 Picture-in-picture and always-on-top windows

- **Picture-in-picture** and a call's pop-out stay on every workspace.
  tide never tiles, minimizes or dims them (tide for Linux §6.4, tide for Chrome §5.4).
- They're spotted by subrole and app: Safari's and Chrome's
  picture-in-picture windows, and Meet's pop-out by title
  *(unverified per kind)*.
- **Their place is the app's.** Pinning them to the bottom-right corner, as
  tide for Linux does, would mean moving them again after each move of the app's own.

### 5.6 The dim

- **Strength 0.12,** as on tide for Linux (tide for Linux §6.2). It's tide for Linux's `dimStrength`,
  in `appearance.json` and `appearance.local.json` (§15), and the
  Appearance page's − and + step it a point at a time, from none to 50%.
  A bad value is logged, and the one before it stands.
- **Never dimmed:** a workspace with one visible window, and a focused
  window that's full screen. A window full screen on its own Space isn't
  visible beside the others, so it doesn't count.
- **tide's own windows,** the settings window and the launchers, sit over
  the layer; while one has the focus, every window under it is dimmed. Picture-in-picture, a screen-share preview
  and apps' panels sit at the floating level or above, over the layer
  *(unverified per app)*.
- **How:** one click-through `hs.canvas` per display, at level 1: over
  normal windows, under floating ones, the bar, the tray, menus and the
  Dock (`dim.lua`, `dim_hs.lua`).
  - It's filled at the strength, with a hole cut where the focused window
    is, its corners rounded to a window's: 10 points, 16 from macOS 26
    *(unverified per kind of window)*.
  - A window in front of the focused one, such as a float over a tile, is
    dimmed again where it covers the hole, so it's dimmed all over, once.
  - That dims the desktop too, as HazeOver does, and every window on the
    other displays.
  - It's drawn again on focus, another app coming to the front
    (Hammerspoon included), a window moving, a retile and a change of
    displays, once for each burst, 30 ms after its first event.
  - A popover reaching outside the focused window, at the window's own
    level, is dimmed outside it *(unverified per app)*.
- **The alternative,** an outline round the focused window instead, is
  JankyBorders' (§13).

## 6. Workspaces

**Decided: park, with minimizing as a setting** (2026-11-05, replacing
minimize, which made each switch too slow). A workspace that isn't
showing parks its windows off screen, as AeroSpace does (§2.3): each one
moves past a corner of its display, all but a 1 pt sliver. A move lands at
once and plays no animation, so a switch is instant. It uses only public
API: the same Accessibility move a retile makes.

- **Where a window parks** (`park.lua`): its top-left 1 pt inside its
  display's bottom-right corner, reaching out past it. With more than one
  display, a window parked there could show on a display to the right or
  below, so the corners are tried in turn, bottom-right, bottom-left,
  top-right, top-left, each with the window reaching outward; the first
  whose window overlaps no other display, the sliver aside, wins. With
  every corner against another display, it's bottom-right. Whether macOS
  lets a window's top go above its display, for the top corners, is
  *(unverified on a Mac)*: it keeps title bars below the menu bar on
  some versions.
- **Coming back,** a tile takes its tile at the next retile, and a float
  takes the frame it had before the park.
- **The costs, plainly:**
  - Mission Control shows every workspace's windows, not just the one on
    screen. So `setup-macos` turns it off, its keys, gestures and hot
    corners (§6.6), and tide's overview takes its place: Ctrl+Up shows
    every workspace's windows grouped by workspace, Ctrl+Down this
    workspace's (§6.9).
  - A sliver of every parked window shows in a corner of each display.
    Focus follows mouse passes over it.
  - Tools that read window positions, such as screenshot pickers,
    window switchers and other window managers, see windows far off screen,
    and may be confused *(unverified which)*.
  - Cmd+Tab lists every app, as before. Choosing one whose window is
    parked focuses that window, and tide brings its workspace along
    (Activate, §6.1), so no window turns up on the wrong workspace. So does
    clicking a sliver, or an app's window coming to the front.
  - That's only while the window still has the focus, so a late report
    of a focus from before a switch doesn't flip you back.
  - A switch to an empty workspace gives the focus to Hammerspoon, which
    has no window to type into, so keys don't reach a parked window
    (`wm:unfocus_parked`) *(unverified on a Mac that activating it opens
    no console)*.
- **Native full screen** is a Space of its own, which a move can't take a
  window out of, so a full-screen window on a hidden workspace is
  minimized, as before, and restored when its workspace shows.
- **The windows you minimized** (`Super+Z`, Cmd+M, the yellow button)
  are still really minimized, to the tray (§6.7).
- **A window tide minimized before,** under minimizing, from a saved
  state or an upgrade, is restored, then parked or placed.
- **Minimizing stays a setting:** `tide.start({ hide = "minimize" })`.
  Mission Control then shows only the workspace on screen, but every switch
  animates. Two settings soften that, and the setup checklist (§10) asks
  for both:
  - **System Settings › Desktop & Dock › "Minimize windows into
    application icon"** keeps minimized windows out of the Dock, so hidden
    workspaces don't crowd it.
  - **"Minimize windows using: Scale effect"** is quicker than the default
    Genie animation.
- **`hide`** is `"park"` (the default) or `"minimize"`; anything else is
  an error at load, naming the setting.

### 6.1 Model

This is tide for Chrome's model (tide for Chrome §6.1), which already solves minimizing on
chromeOS, with tide for Linux's named workspaces (tide for Linux §6.5) in place of nine
numbered ones:

- **Workspaces have names, not numbers.** A workspace exists once it has a
  name. The bar lists them by name (§8), in bar order: the standing
  workspaces, then the rest in the order they were made.
- **Standing workspaces** are a setting, tide for Linux's `standing` (§15), or
  `workspaces` in `start()` where no file sets it, "in", "re", "oc" and
  "me" by default.
- **The first is the home workspace,** "in" by default. It's the first
  standing workspace that's special, not the name "in": whatever the list
  names first gets everything this spec says of "in". tide makes it at
  start. It can't be removed or renamed, holds the apps you keep open all
  day, and, unless its `askForName` is off, asks for a name for any other
  window (§6.2).
- **The other standing workspaces:**
  - they're always listed, on the bar and in the switcher, in the
    setting's order, even before they exist;
  - each is made the first time you show it or send a window to it, not
    at start;
  - they're never removed, even when empty;
  - a name typed at a prompt that matches one, ignoring case, is that
    workspace.
- **`Super+Home` goes to "in"; `Super+Tab` flips between "in" and the
  workspace you used last; `Super+End` goes to the last one other than
  "in"** (§7.2).
- **`Super+1…9` count along the bar:** `Super+N` is the Nth workspace in
  bar order, so `Super+1` is "in", as `Super+Home` is, and `Super+0` is
  the last (§7.2).
- **An empty workspace is removed once you leave it,** other than "in" and
  the standing ones. Leaving means no display shows it any more. A workspace holding only
  windows you minimized isn't empty.
- **Names are tide's own.** Its workspaces are parked or minimized
  windows, not Spaces, so a name is just tide state, saved with the rest (§6.5). Two
  workspaces can't share a name; names are compared ignoring case
  *(a guess, to confirm)*, with Unicode's case folding for Latin, Greek
  and Cyrillic letters, so "Équipe" and "équipe" are one workspace.
- **A name has no quotes (`"`, `'`, `` ` ``), backslashes, `@` or control
  characters,** as on tide for Linux (tide for Linux §6.5). tide for Linux keeps `@` for a monitor's
  part of a workspace, and the standing list is shared, so a name tide for Linux
  refuses is refused here too.
  - A name reaches JSON, the bar's web view, logs, and `workspace.name`,
    which a script or a shell prompt prints (§6.3). Without those
    characters, no quoting can go wrong, and no escape sequence reaches a
    terminal.
  - A standing name with one is an error at load, naming the setting.
  - The prompt refuses one with a short notice and asks again. A launch's
    prompt comes back with them dropped.
  - A default name from a title drops them, as tide for Linux's short names do.
  - A tab or newline typed in a name is a space, as before, not a refusal.
- **A workspace spans every display,** and each display has its own
  layout within it. **Decided** (2026-11-01, §19 question 12), and
  **built**. One workspace shows at a time, on every display at once.
  tide for Linux's monitors each show one of their own (tide for Linux §6.5), so here the two
  desktops differ.
- **Each workspace keeps** a part per display: that display's windows in
  tile order, its layout, `mfact` and master count. The workspace as a
  whole keeps its focused window.
  - A part is made the first time it's needed, in the default layout for
    that display's shape (§5).
  - A display with no windows in the workspace showing shows empty.
- **Each window belongs to one workspace, and to one display within it,**
  and has one flag: whether you minimized it yourself.
- **A new window joins the workspace showing,** on the display it opens on.
  Two exceptions:
  - A window of one of "in"'s apps always opens on "in" (§6.2).
  - A window from a launch you made, which opens after you've moved to
    another workspace, goes to the workspace you launched it from instead,
    marked for attention (tide for Linux §14.2).
- **A tile from a launch you made goes to the display keys acted on as you
  launched it,** one of "in"'s apps too, not where macOS opens it. macOS opens an app's new window
  where its last one was, so Win+T with the pointer on the internal display
  could open the terminal on the external one. Until tide first places
  it, the app moving it doesn't count as you moving it.
- **A new window opening on "in"** that isn't one of its apps asks for a
  workspace name first (§6.2).

**One rule decides what's on screen:** a window shows if its workspace is
showing and you haven't minimized it. Every operation
changes only that state. Then one reconcile step makes the screen match:
it brings back the windows that should show first, in tile order, lays
them out, and only then parks (or minimizes) the rest, so the screen is
never empty in between.

| Operation | What changes | Focus |
|---|---|---|
| **Show** a workspace (the switcher's Workspaces tab, `Super+Return`'s prompt, `Super+Home` for "in", a bar click) | Every display shows it, each its own part. | its last focused window; with none, the keys stay on the display they were on |
| **Move** a window to a workspace (`Super+Shift+Return`'s prompt, §7.2) | It moves to the end of that workspace's stack on the same display. A new name makes the workspace first, at the end of the list. Then that workspace shows. | that window, as on tide for Linux |
| **Next or previous** (`Super+PgUp`, `PgDn`) | Show the one after or before that has a window, in bar order, wrapping from the last to home and back, as on tide for Linux: an empty one, standing or made, or one whose only windows you minimized, is passed over, and with none other it stays. Scrolling over the bar's workspaces still stops at each, first and last. | as Show |
| **Move a window to the next or previous** (`Super+Shift+PgUp`, `PgDn`) | Move, to the one after or before, wrapping as Next does. | that window |
| **Move a window left or right** (`Super+Shift+Left`, `Right`, §7.2) | On its display, it swaps with the window that way. At the display's edge, it goes to the next display that way, as Moved to another display. | that window |
| **Activate**: an app key, the switcher, Cmd+Tab, a Dock click, a notification click | If the window's workspace isn't showing, show it. | that window |
| **Moved to another display** by you (a drag, `Super+Shift+Left` / `Right`, or macOS) | It joins that display's stack, in the same workspace. | that window |
| **Minimize** by you (`Super+Z`, Cmd+M, the yellow button) | Set the flag. The window joins its display's tray (§6.7). | `Super+Z`: the workspace's last used window still showing; otherwise macOS decides |
| **Restore** by you, from the tray (§6.7), the switcher's Windows tab (§9), the Dock or Cmd+Tab | Clear the flag. If its workspace is hidden, this is Activate. | that window |
| **Hide** an app (Cmd+H) | Nothing: hidden apps are macOS's, and come back where they were. | macOS decides |

- **The current Mac setup follows a thrown window**
  (`follow-space-thrown-windows: true` in conf's `amethyst.yml`), and so
  do tide's Move and its move to the next or previous workspace, as
  tide for Linux's move does (tide for Linux §6.5).
  **Decided.**
- **A window that refuses** to minimize or restore is logged and skipped,
  so it can't stop a workspace switch. tide then stops managing it, as
  tide for Chrome does (tide for Chrome §6.4).

### 6.2 "in" and the name prompt

This is tide for Linux's (tide for Linux §6.5), on tide's own workspaces. "in" here means
the home workspace, the first standing one (§6.1), which is "in" unless
`workspaces` names another first.

- **"in" holds the apps you keep open all day:** mail, chat, calendar and
  music by default. Their windows always open there. Any other window
  goes there only when you send it or name it.
  - The list is a setting (§15), matched by app name, since Chrome's
    installed web apps each get a bundle ID of their own per install
    *(unverified)*. Which names stand for those four is a guess, to
    confirm: Mail, Gmail; Messages, Google Chat; Calendar, Google
    Calendar; Music, YouTube Music.
  - The list is tide for Linux's `inApps` (§15), shared with tide for Linux, or `home_apps` in
    `start()` where no file sets it. It names Mac apps as well as tide for Linux's
    entries, and each desktop passes over the other's.
  - **A list you set starts at login,** as tide for Linux's home starts its apps
    (tide for Linux §6.5): once a login, told apart as Start at login's list is
    (§15), each app by name with `open -g -a`, so none takes focus, in
    order, and before that list, which doesn't wait for them. An app
    already running isn't opened again, and one that won't open is a
    notification naming it. The two keep their logins apart, so a list
    file that can't be read doesn't hold home's apps back.
    - **tide's default list starts nothing.** It names a Mac app and a
      web app for each of the four, so it would open both, including
      Mail's and Messages' first-run setup on a Mac that uses Google's
      *(a guess, to confirm)*.
    - **Entries are app names** here, not tide for Linux's programs and web
      addresses (tide for Linux §6.5). A `chrome --app=URL` window on a Mac is Google Chrome's
      own, which tide can't tell from a browser window, so a web address
      would match nothing; Chrome's installed web apps have names of their
      own, which the list already takes. A `scripts` launcher such as
      `google-calendar` can go in Start at login's list (§15) instead.
  - A web app open in a plain Chrome tab isn't its app. Only the installed
    web app's own window counts.
  - Any window can be sent to "in", and every prompt offers "in". So a
    window or launch you name "in" stays there.
  - Moving one of "in"'s windows elsewhere by hand is allowed: the rule
    says where they open, not where they must stay *(a guess, to
    confirm)*.
- **Each workspace has settings of its own,** tide for Linux's `workspaceSettings`
  in `workspaces.json` (tide for Linux §6.5, and §15 here), by name, ignoring case:
  - **`askForName`:** whether a new window there asks for a workspace's
    name, below, and whether a launch from there does. The settings window
    calls it "New windows ask for a workspace".
  - **`pinnedApps`:** the apps whose windows stay open there (Pinned apps,
    below).
  - With no `workspaceSettings` in either file, nor `workspace_settings`
    in `start()`, it's tide for Linux's default: "in" asks, and nothing is pinned.
    Once one is set, a workspace it doesn't list, or a field it leaves out,
    is off: with "in"'s `askForName` off, nothing asks, "in" included.
- **Any other window opening on a workspace that asks asks for a name,**
  "in" by default. That includes a link a browser opens as a new window.
  - One of "in"'s apps never asks: its window goes to "in", wherever you
    are.
  - Dialogs and other windows that follow a parent (§5.1), and
    picture-in-picture (§5.5), don't ask: they go where their parent is.
  - The prompt is an `hs.chooser` listing the existing names, with a
    default name typed in and selected, as tide for Linux's is (tide for Linux §6.5). Typing
    replaces it or filters the list. Until you type, the default filters
    nothing: it comes first, and every workspace follows in the bar's
    order. Left, Right, Home and End keep it and
    move the cursor; `Up` and `Down` pick a row.
    - `hs.chooser` has no call to select its text. Its `show()` makes the
      text field first responder, which in AppKit selects the field's
      text, so tide shows it again whenever it changes the default.
    - A Mac text field's Home and End only scroll, so while the prompt is
      open Home and End are hotkeys sending `Cmd+Left` and `Cmd+Right`.
  - **Enter** makes the workspace, or uses the existing one of that name,
    moves the window there, and shows it. Focus follows. The workspace
    it's on keeps it there, and it doesn't ask again.
  - **Esc closes the window,** politely, as the close-window key does
    (§7.2): Accessibility presses its close button, so the app can still
    ask to save. A window pinned where it is stays open, and a
    notification says it's pinned there.
  - A window's title often arrives after the window. The default follows
    the title until you type, or press Home or End *(a guess, to
    confirm)*.
  - Focus follows mouse pauses while it's open (§5.2), and the window
    stays put until you answer.
- **tide's own launches from a workspace that asks ask before
  launching,** "in" by default: the switcher's Launch tab, app keys and
  Cmd+Return (§9). From any other, they launch where you are.
  - The process then starts with the right `TIDE_WORKSPACE` (§6.3), and its
    first window goes straight to the named workspace.
  - Esc cancels the launch, so nothing opens.
  - Enter on the workspace you launched from launches there, and its
    window, matched to the launch, doesn't ask again.
  - An app key for one of "in"'s apps doesn't ask.
- **Pinned apps.** A window whose app is one of the `pinnedApps` of the
  workspace it's on stays open there. Its app's name is matched as "in"'s
  apps are, ignoring case, with spaces, hyphens and underscores alike, so
  tide for Linux's `google-chat` is Google Chat; tide for Linux's web addresses match nothing
  here.
  - tide's close actions leave it open, and a notification says it's
    pinned on that workspace: the close-window key (§7.2), and the name
    prompt's Esc. The switcher and the dashboard close no window.
  - **An app's own close and quit keys don't reach it:** Cmd+W, Cmd+Shift+W
    and Cmd+Q, physical Ctrl+W, Ctrl+Shift+W and Ctrl+Q under the rotation
    (§7.1), tide for Linux's own. tide for Linux's fourth, Alt+F4, closes nothing on a Mac.
    - How: they're hotkeys (`RegisterEventHotKey`, §2.2), like every key of
      tide's, so they need no permission. A hotkey can't depend on the
      window, so tide enables the three only while a pinned window has
      focus, checking on each focus change and whenever a window moves
      between workspaces, and every other window gets them as ever. With
      nothing pinned, tide never checks.
    - A press that finds focus moved on before tide heard goes to the app
      as a key posted with the hotkeys off. A press in the moment between
      focusing a pinned window and tide hearing of it still reaches the
      app *(how long that is, unmeasured)*.
    - A CGEventTap could decide per press, with no gap, but a keyboard tap
      may need Input Monitoring (§11.1), which tide otherwise needs only
      without Karabiner (§7.1).
  - It's pinned where it is, not as an app: sent to another workspace, it
    closes as any other does. Another app's window there closes as usual.
  - **The window's own close button still closes it,** and so do the app's
    menus (File > Close, Quit) and the Dock's Quit. Accessibility can't
    refuse them, and tide hears of them only once the window has gone.
- **The default name** comes from the window's title:
  - A setting holds a list of patterns, tried in order against the title.
    The first that matches gives its first capture, such as a ticket ID or
    a repository name.
  - Patterns are how to get a better name than the first word, such as an
    issue number or a project from a site's title.
  - With no match, it's the title's first word, as on tide for Linux (tide for Linux §6.5),
    once the app's name is stripped from the title's end (" - Google
    Chrome", " — Mozilla Firefox").
    - Punctuation clinging to the word's end goes: `.` `,` `:` `;` `!`
      `?` `|` `…` and dashes. So `ABC-123: Fix login - Tracker - Google
      Chrome` gives `ABC-123` with no patterns too.
    - A word left with no letter or digit, such as a lone `—`, is passed
      over for the next. Lua has no Unicode tables, so any character past
      ASCII counts as a letter here.
    - A word past 20 characters is cut to 20.
  - With no title, or no such word in it, the app's name.
- **The patterns are JavaScript regular expressions, not Lua patterns.**
  - tide for Linux's shell is QML, so tide for Linux's are JavaScript's. The setting lives in
    tide for Linux's shared files (tide for Linux §16.1), and one list serves both desktops
    only if both read it the same way.
  - Lua patterns couldn't: they have no alternation (`a|b`), no `{n}`
    counts, and `%d` where JavaScript says `\d`.
  - tide runs them in JavaScriptCore through `hs.osascript.javascript`,
    once per prompt, not per keystroke. That's an OSA call of some tens of
    milliseconds *(unverified)*, and no permission.
  - **A bad pattern is an error at load,** naming the setting and the
    pattern. tide compiles each one when it starts and whenever the file
    changes, and keeps the last good list.

### 6.3 `TIDE_WORKSPACE`

- **The variable is tide for Linux's** (tide for Linux §6.5), with the same name, so conf's
  shpool and tmux startup reads one variable on every desktop.
- **Its value** is the current workspace's name with only its letters and
  digits kept, in any script, NFC-normalized, as on tide for Linux (tide for Linux §6.5):
  `my-repo` gives `myrepo`, `Équipe 2` gives `Équipe2`, and `日本語` stays.
  A name with none gives an empty value, and conf's startup takes its
  default *(a guess, to confirm)*.
  - Letters and digits are Unicode's categories L and N. Punctuation,
    spaces, symbols, emoji, marks and control characters go.
  - The name is normalized before the rest go, so a decomposed `é` (`e`
    and a combining accent, as macOS file names and some text fields give
    it) is one letter, and kept.
  - Lua has no Unicode tables, so a name past ASCII goes through
    JavaScriptCore (`hs.osascript.javascript`, as the name patterns do,
    §6.2), whose `\p{L}`, `\p{N}` and `normalize("NFC")` follow the
    Unicode version macOS ships. An ASCII name needs none.
  - If JavaScriptCore fails, the value is empty, not a guess, and the file
    (below) holds the empty value; the launch logs why, and the file's
    writer says it once in a notification.
- **tide sets it for the processes it launches.** On a Mac that takes
  more than one way, since an app launched through LaunchServices (`open`,
  the Dock, Finder) gets launchd's environment, not Hammerspoon's:
  - **Helpers** (`runenv`, §7.2) run through `hs.task`, whose
    `setEnvironment` sets it. So does anything they start directly.
  - **Apps** the helpers open with `open` get it through `open --env
    NAME=value`, added in macOS 13 *(unverified on macOS 26)*. That covers a
    new process only: `open -na` starts one, as the browser keys do, but
    an app that's already running gets nothing.
  - **kitty** on Super+T: Cmd+N to a running kitty starts a shell with
    kitty's environment from when it launched. tide instead asks kitty
    for the window through its remote control, `kitten @ launch
    --type=os-window --env TIDE_WORKSPACE=…`. With no socket, it falls
    back to Cmd+N, and the shell reads the name from tide's file
    (below).
    - **The socket is private.** conf's `kitty.conf` sets, on a Mac only,
      `allow_remote_control socket-only` and `listen_on unix:kitty`. kitty
      0.27.0 or later is needed, for the Mac-only include.
    - A relative `listen_on` lands in kitty's temporary folder, and kitty
      adds its process ID, so the socket is `$TMPDIR/kitty-<pid>` (kitty's
      `expand_listen_on`). `$TMPDIR` is your own folder, mode 700, where
      `/tmp` is shared. That kitty, started from the Dock, has `$TMPDIR` is
      *(unverified)*.
    - kitty doesn't set the socket's mode, so the mode is whatever the
      umask leaves. macOS only lets a process connect to a socket it can
      write (`unp_connect`). So the folder is what keeps other users out.
    - **tide checks before it connects.** It takes the socket only if
      the socket and its folder are owned by your user ID, and no one else
      can write to the folder (`kitty.lua`). Anything else is refused, with
      a notice saying why, and the window comes from Cmd+N. Remote control
      runs anything as you, and tide sends the workspace's name, so a
      socket someone else made is never used.
    - Your user ID comes from one `id -u`, the first time there's a socket
      to check.
- **A running process can't see later changes.** It keeps the name it
  started with, after a rename or a move to another workspace, as on tide.
- **Scripts read the current name from a file:**
  `~/Library/Caches/tide/workspace` holds `TIDE_WORKSPACE`'s value, and
  `workspace.name` beside it holds the name as it shows, each ending in a
  newline. `cat ~/Library/Caches/tide/workspace` gives it.
  - tide writes both whenever the current workspace changes. Each is
    written whole: a temporary file, mode 600, renamed over the last.
  - The folder is mode 700, so only you can read them.
  - **Not Hammerspoon's IPC:** `hs.ipc` opens a port that runs any Lua a
    local process sends it, with tide's Accessibility grant, so tide
    never loads it. A config of your own that loads it is your choice.
  - Reading the file costs no process and no round trip, so it's fine
    even in a prompt.
  - With tide not running, the file says the last workspace it showed.
  - The cost is nothing in money, and no network.

### 6.4 Displays

- **A display that goes away,** from a lid closing or a cable coming out,
  hands its windows to the first display left, in the same workspace, at
  the end of that display's stack, in their order *(a guess, to confirm)*.
  - Each tile remembers the display it was on and its place there. When
    that display comes back, it goes back, in its old order, and that
    display's layout is as it was *(a guess, to confirm)*.
  - One you move in the meantime, to another display or workspace, stays
    where you put it.
  - A float stays where macOS puts it.
  - The display it goes back to is saved, so it holds across a restart.
- Each display is keyed by its UUID, so its settings follow it from port to
  port, as tide for Linux keys displays by description (tide for Linux §16).
- **A new workspace** from the name prompt shows, with the window on the
  display it opened on.

### 6.5 Restarts and saved state

- **When an app quits and relaunches,** its windows come back with new IDs.
  tide matches each to its old place by app and title, closest first, as
  tide for Chrome matches by tab addresses (tide for Chrome §14.2). A window it can't match joins
  the workspace showing.
- **If tide quits,** it restores every window it hid first, so nothing is
  left stranded in the Dock or off screen: a parked window goes back
  onto its display's tiling area, where it was before the park if that's
  still on a display.
- **A reload with windows parked,** if they weren't brought back first,
  finds them still off screen. Each one on a workspace that isn't showing
  stays parked; one whose workspace shows is placed as usual, a float at
  the frame saved with it (`frame`).
- **If it crashes,** the next start restores what it can't place and
  reconciles the rest. `tide restore` does it by hand (§16).
- **What's saved:** `hs.settings`' `tide.state` names each window's
  workspace by name, its display by UUID, and the display it goes back
  to, if any (§6.4); the workspace showing; and the list of names in
  order. A state from when each display showed its own shows the first
  display's.
- **Moving on from numbered workspaces:** a saved state whose workspaces
  are numbers is read once, then saved by name *(a guess, to confirm)*:
  - each numbered workspace with windows becomes one named by its number,
    "1" to "9", in that order after "in" and the standing workspaces;
  - a window of one of "in"'s apps goes to "in" instead;
  - an empty number is dropped;
  - the number a display showed shows, or "in" if it was dropped.
  - The same holds for timo's state, which tide still reads (README).

### 6.6 Mission Control settings

The checklist (§10) sets these, and undoes `setup-macos`'s nine Spaces:

- **One Space per display.** tide doesn't use the rest.
- **"Displays have separate Spaces"** stays on, the default.
- **"Automatically rearrange Spaces based on most recent use"** off
  (`mru-spaces`), as `setup-macos` sets it now.
- **Stage Manager** off, since it groups windows itself.
- **Sequoia's tiling:** "Drag windows to screen edges to tile" off, and
  "Hold Option key while dragging windows to tile" off. With Super as
  Option, the second would fight Super+drag (§5.3).
- **"Click wallpaper to reveal desktop"** set to "Only in Stage Manager".
- **Mission Control and App Exposé off,** since parked windows would
  crowd them (§6): `setup-macos` turns off their keys, Ctrl+Up and
  Ctrl+Down (symbolic hotkeys 32 and 33, `configure_shortcuts_tide` in
  scripts), the trackpad's swipes for them, and the hot corners. tide's
  overview takes the two keys (§6.9). The swipe left and right between
  Spaces goes too, for tide's own (§7.2).

### 6.7 Windows you minimized

**Decided: floating icons in the bottom-right corner,** option C of tide for Linux's
mock of five (tide for Linux's `docs/mocks/minimized.html`), as tide for Linux does.

- **`Super+Z` minimizes the focused window** (§7.2).
  - Decided over `Super+Delete`: a PC keyboard's Delete can arrive as
    forward delete or as Backspace, and `Super+Backspace` already closes
    the window.
  - It sets the window's flag (§6.1), so the window stays down when its
    workspace comes back, and focus moves to the workspace's last used
    window still showing.
  - Floats and dialogs minimize too. A window tide doesn't manage is left
    alone.
- **Only windows you minimized count.** tide parks windows itself to hide
  the other workspaces, or minimizes them with `hide = "minimize"` (§6),
  and those never show here. `wm.lua` flags
  yours as `mine`: from `Super+Z`, Cmd+M, the yellow button, or a window
  already minimized when tide first saw it. The tray and the Windows tab
  read that flag, not macOS's minimized state.
- **The tray** sits in the bottom-right corner of each display, 12 px in
  from the edges of its work area, over the Dock's side of the screen:
  - one app icon per window you minimized from that display's part of the
    workspace showing, 28 px, in a row on the bar's background, 5 px of padding
    and 6 px between icons;
  - in the order you minimized them, the newest at the right, nearest the
    corner;
  - an app with no icon shows a blank square, as on the bar (§8);
  - as many as fit across the display; the rest are in the Windows tab;
  - shown only while that workspace has such windows: a workspace with
    none shows nothing.
- **Hovering an icon shows its title,** in a tip just above it.
- **Clicking an icon restores the window:** Restore (§6.1), which clears
  the flag, puts the window back in its place in the stack, and focuses it.
- **It floats over the windows and doesn't change the tiling.** The cost:
  it covers the corner of whichever window is under it.
- **On Hammerspoon,** it's an `hs.canvas` per display at the floating
  window level, joining every Space, that takes clicks but doesn't make
  Hammerspoon the front app (`clickActivating(false)`) *(unverified that a
  click there leaves focus where it was)*. The tip is a second canvas, drawn
  on the pointer entering an icon, since a canvas element's own tooltip may
  only show while Hammerspoon is in front *(unverified)*.
- **Focus follows mouse pauses over it,** as over the bar (§5.2).
- **It hides with the bar,** under a full-screen window on that display
  (§8).
- **The Windows tab** (§9) lists every window you minimized, marked
  "minimized", and Return restores it, with its workspace.
- **A workspace holding only windows you minimized isn't empty** (§6.1), so
  it stays, and its tray shows them when it's back.
- **Saved across restarts:** the flag is saved with the window (§6.5), and
  quitting tide leaves your minimized windows down, restoring only the
  ones it hid (§6.5).

### 6.8 The alternatives, to revisit if parking doesn't work out

1. **Native Spaces, one per workspace:**
   - Switching uses symbolichotkeys, as `setup-macos` does now.
   - Spaces have no names in any public API, and each has to exist first,
     so named workspaces made on demand fit them poorly.
   - Sending a window uses the private calls Amethyst and yabai use.
   - It matches the user's current Mac, Cmd+Tab stays honest, and full
     screen works.
   - The costs: the animation, Spaces created by hand, and a private call
     that may break.
2. **Emulated, AeroSpace-style, parking windows off screen:** the choice
   above.
   - Switching is instant, there's one shared pool across monitors, and
     tide for Linux's model fits exactly.
   - The cost is Mission Control showing everything, a sliver in a corner
     of each display, and tools that read positions seeing windows off
     screen. Cmd+Tab bringing the workspace along softens the reason
     `setup-macos` turned AeroSpace down.
3. **Minimized, tideco-style:** tide's first choice, now the
   `hide = "minimize"` setting. Mission Control stays honest, but every
   switch animates, too slowly even with the Scale effect.

Revisit if apps refuse to move or snap back on screen, if macOS clamps a
parked window back into view, or if Mission Control's clutter outweighs the
speed. Minimizing is one setting away. Native Spaces come next, since
Cmd+Tab and Mission Control stay honest with them. The private call is
the risk, and it breaks about once a year at a major macOS release *(from
memory, not counted)*.

### 6.9 The overview, in place of Mission Control

**Built** (2026-11-05), only the tests have run it. Parking keeps every
workspace on one Space, so Mission Control would show them all mixed
together (§6). `setup-macos` turns it off (§6.6), and tide has its own.

- **Ctrl+Up shows every workspace's windows; Ctrl+Down only this
  workspace's,** in place of App Exposé. They're plain Control, not Super,
  the keys Mission Control had. Under the PC keyboard's modifier rotation
  that's physical Alt+Up and Alt+Down (§7.2).
- **What it is:** a full-screen borderless `hs.webview` over the display
  the keys act on, built as the dashboard is (§8): `overview.lua` makes the
  data, `overview_hs.lua` shows it, and `dashboard/overview.html` and
  `overview.js` are the page, with tide for Chrome's stylesheet.
- **The groups:** each workspace with a window tide manages is a group,
  headed by its name. The current workspace comes first, then the rest in
  bar order (§8). Ctrl+Down shows the current workspace even with no
  windows, and says so.
- **The cards:** every window tide manages on that workspace, on any
  display, each with its app's icon, its title and its app's name.
  - The order is each display's in turn, in the order macOS lists the
    displays: its tiles in stack order, then its floats, bottom to top.
    Then any left over, such as a window on a display that went away.
  - A window you minimized is there, marked "minimized" (§6.7).
  - A window tide doesn't manage, such as picture-in-picture, isn't.
- **No thumbnails.** They'd need Screen Recording, which tide never asks
  for (§11.1). The icons come from each app's bundle
  (`hs.image.imageFromAppBundle`), read once per app and sent as data
  URLs. Thumbnails as an opt-in setting are in `TODO.md`.
- **Choosing:**
  - A click on a card, or the arrow keys and Return, activates that window
    (Activate, §6.1): its workspace comes along, onto this display, and a
    window you minimized is restored. The arrows step through the cards in
    order, and the selection starts on the focused window.
  - A click on a group's header shows that workspace.
  - Typing filters the cards by title and app name, with tide for Linux's fuzzy
    matcher (`tide-fuzzy.js`, the launcher's). Backspace takes a letter
    back.
- **Closing:** Esc, the same key again, a click on empty space, or a click
  on another window. The other key while it's open switches it to that
  scope.
- **Focus follows mouse pauses** while it's open, as for the dashboard
  (§5.2).
- **The page talks to tide** as the dashboard does: tide calls
  `tide.update(state)`, and the page posts `{ activate: id }`,
  `{ show: name }` or `{ close: true }` to the `tide` message handler.
- **The keys need macOS to let go of them.** `RegisterEventHotKey` fails
  silently on a key the system still holds (§2.2). `setup-macos` frees
  Ctrl+Up and Ctrl+Down by turning off symbolic hotkeys 32 and 33
  (mikelward/scripts, `configure_shortcuts_tide`, §7.3). On a Mac that
  hasn't run it, Mission Control keeps them.
- **Unchecked:** *(unverified on a Mac)* the page's look, that the keys
  reach tide once setup has run, that a click on another window closes
  it, and whether conf's PC-arrows Karabiner rule, which sends physical
  Ctrl+Home as Control+Up outside terminals, reaches tide as Ctrl+Up and
  opens the overview.

## 7. Keys

### 7.1 Where Super comes from

- **tide for Linux's map, everywhere.** tide for Linux and tide for Chrome differ where chromeOS can't
  bind a key (tide for Chrome §7.1), but macOS can bind all of tide for Linux's, so tide follows
  tide for Linux (tide for Linux §6.6).
- **Super is the PC keyboard's Win key.** `setup-macos`'s rotation turns it
  into Option, and Ctrl into Command, so copy and paste stay under the same
  finger (scripts `docs/MACOS.md`, "Modifier rotation").
- **Option already means things on a Mac,** which plain Option bindings
  would take away:
  - Option+Backspace deletes a word, and Option+Up and Down move by
    paragraph.
  - Option+Left and Right move by word. Karabiner makes those from Ctrl+arrow
    now, and a hotkey on Option+arrow can't tell the two apart (conf
    `config/karabiner/README.md`).
  - Option+`, E, I, N and U are dead keys for accents on US layouts
    *(unverified on Dvorak)*.
- **Decided: Karabiner turns physical Win+key into a combination nothing
  else uses** (Ctrl+Option+Command+key), and tide registers that. Karabiner
  sees the physical key before the rotation (conf
  `config/karabiner/README.md`), so Option's own meanings stay intact.
  Depending on Karabiner is accepted, but tide must work without it.
  - Karabiner needs an admin, once, and IT can block it (§11).
- **Without Karabiner, tide falls back,** rather than leaving keys dead:
  - **How it tells:** at start, and whenever Karabiner starts or stops,
    tide checks that Karabiner is running and has tide's rules loaded
    *(how to check unverified: its background process, and its config
    file)*.
  - **The keys:** tide registers the same map on plain Option instead. Every
    key still works, at the cost of Option's text gestures above.
  - **The Super tap:** an event tap, if Input Monitoring is granted, or
    Super+Space alone if not (§7.2).
  - **Super+drag:** on Option, so Finder's Option-drag copy goes to tide
    (§5.3).
  - **It says so once,** in a notification naming what's lost and how to
    fix it. The checklist (§10) and `tide doctor` (§15) report it too.
  - **When Karabiner comes back,** tide moves its keys back to Karabiner's
    combinations, with no restart.
- **The rotation covers every keyboard,** the MacBook's own included. If
  that's wrong for the built-in keyboard, `hidutil` can match PC keyboards
  alone *(unverified)*. That's a question for `setup-macos`.

### 7.2 The map

tide registers each with `RegisterEventHotKey`, which needs no permission
(§2.2). The second column is what macOS sees once Karabiner has mapped it.

| Keys | Action | How |
|---|---|---|
| tap `Super` | the launcher: the switcher on Launch, as `Super+Space` and tide for Linux's and tide for Chrome's taps (§9) | Karabiner's tap rule, sending `Super+F20`; or tide's event tap (below) |
| `Super+Space` | the switcher, on its Launch tab | hotkey |
| `Super+Tab` | from any workspace, "in"; from "in", the workspace you used last. Pressed again, it flips back | hotkey |
| `Super+End` | the workspace you used last other than "in" and this one: from "in" where `Super+Tab` goes, from another the one before it | hotkey |
| `Super+A` | the switcher, on its Attention tab (§14.2) | hotkey |
| `Super+Shift+Space` | dashboard (§8) | hotkey |
| `Ctrl+Up` | the overview: every workspace's windows, grouped by workspace, in place of Mission Control (§6.9) | hotkey, once `setup-macos` frees it (§7.3) |
| `Ctrl+Down` | the overview of this workspace's windows, in place of App Exposé (§6.9) | hotkey, once `setup-macos` frees it (§7.3) |
| `Super+Alt+Space` | next input source | macOS's own "Select next source" *(unverified key)* |
| `Super+T` / `W` / `G` / `F` / `Shift+G` / `E` / `B` / `Shift+B` / `C` / `Shift+C` / `H` / `I` / `M` / `N` / `R` / `Y` | app keys (below) | hotkey |
| `Super+V` | the picker, on its Clipboard tab: what you've copied, and characters by name (§9.1); Return pastes. Terminal on the VM, which it was, has no key now; the switcher finds it | hotkey |
| `Super+Shift+V` | the picker, on its Fill tab: your snippets and each Bitwarden login's username, password and 2FA code; Return types it (§9.1) | hotkey |
| `Super+;` | the picker, on its Characters tab: emoji and symbols by name (§9.1); Return pastes | hotkey |
| `Super+Backspace` | close the window, unless it's pinned on its workspace (§6.2) | hotkey, on `Super+F19` with Karabiner's rule (below); Accessibility presses its close button |
| `Cmd+W` / `Cmd+Shift+W` / `Cmd+Q` | the app's own, except while a window pinned on its workspace has focus, which never sees them (§6.2) | hotkeys, enabled only then |
| `Super+Z` | minimize the window, to the tray (§6.7) | hotkey |
| `Super+L` | lock | hotkey; macOS's lock screen |
| `Super+S` | keep awake on or off (§10) | hotkey; `hs.caffeinate`, with an on-screen sign |
| `Super+P` | presenter mode: Do Not Disturb and keep awake together (§10) | hotkey; keep awake as `Super+S`, Do Not Disturb through two shortcuts you make in Shortcuts |
| `Super+Shift+E` | log out | hotkey; System Events, which asks first |
| `Super+Home` | show "in" (§6.2) | hotkey |
| `Super+Left` / `Right` | select the window left / right of this one; at a display's edge, the nearest on the next display that way (below) | hotkey |
| `Super+Shift+Left` / `Right` | move the window left / right the same way, onto the next display at the edge; a float straight onto the next display (below) | hotkey |
| `Super+PgUp` / `PgDn` | previous / next workspace | hotkey |
| `Super+Shift+PgUp` / `PgDn` | move the window to the previous / next workspace, and follow it | hotkey |
| three fingers left / right on the trackpad | next / previous workspace, as `Super+PgDn` / `PgUp` | event tap |
| `Super+J` / `K`, with Shift | focus / move down and up the stack | hotkey |
| `Super+Return` | go to a workspace, by name (below); it moves no window, so it works with none focused | hotkey |
| `Super+Shift+Return` | move the window to a workspace, by name (below), and follow it there; with no window focused, nothing | hotkey |
| `Alt+Tab` | swap with the master; on the master, swap with the previous master | conf's Karabiner rule turns physical Alt+Tab into `Ctrl+Option+Shift+Tab`, which tide registers (below) |
| `Super+\` / `Super+/` | grow / shrink the master (`mfact` ±0.025), repeating | hotkey |
| `Super+=` / `Super+-` | add / remove a master | hotkey |
| `Super+.` / `Super+,` | next / previous layout | hotkey |
| ``Super+` ``, `Super+O` | monocle | hotkey |
| `Super+Up` / `Super+Shift+Up` / `Super+Down` | maximize / full screen / restore (§5.4) | hotkey |
| `Super+Shift+F`, `Super+Insert` | float or tile | hotkey |
| `Super+Shift+I` | the settings window's Floating section, filled in for the focused window (§15), tide for Linux's `Super+Alt+F` | hotkey |
| `Super+Shift+R` | resize mode for a float (§5.3) | hotkey, then plain keys until Esc |
| `Super`+drag, `Super`+right-drag, `Super`+middle-click | move, resize, maximize (§5.3) | event tap |
| `Super+Shift+N` | Notification Center | no public way to open it *(unverified)*; else the clock in the menu bar |
| `Print` / `Alt+Print` / `Shift+Print`, `Super+Print` | screenshot screen / window / region, Super+Print a region too (§10) | hotkey on F13, which a PC keyboard's Print sends *(unverified)* |
| mic-mute key, `Super+Shift+M` | mute the microphone, everywhere | tide, through `hs.audiodevice`'s input mute on the default input device, with an on-screen sign; the bar's microphone item does the same |
| media, brightness, volume keys | as macOS does them; the volume keys step a monitor's speakers over DDC (§8) | native, `hs.eventtap` for DDC |

- **The Super tap** must not fire after Super+T, Super+drag or
  Super+click (tide for Linux §8). A mouse button or scroll counts as "another key"
  in between.
  - An event tap needs Accessibility and maybe Input Monitoring (§11). A
    Karabiner rule (`to_if_alone` on physical Win) avoids both.
  - Karabiner's rule is the better of the two here: it sees the physical
    key, and needs neither permission. tide's own tap is the fallback.
  - The rule sends the tap as `Super+F20`, a key no keyboard here has, so
    it's told apart from `Super+Space`.
- **Karabiner sends `Win+Backspace` as `Super+F19`.** On one Mac,
  something below Hammerspoon took Ctrl+Option+Command+Backspace: neither a
  hotkey nor an event tap saw it, though plain Backspace and the other
  chords got through. A chord on a key no keyboard here has does, as the
  tap's F20 shows. The Shortcuts list still says `Super+Backspace`, and
  with Option as Super it stays on Backspace, which nothing takes there. A
  rule copy that still sends Backspace is reported as out of date.
- **`Super+1…9` and `Super+Shift+1…9` count along the bar,** as on tide for Linux
  (tide for Linux §6.6). `Super+N` shows the Nth workspace in bar order, home first,
  so `Super+1` is "in"; `Super+Shift+N` sends the focused window there,
  with focus staying where you are. A number past the last workspace does
  nothing. A number is a position, not a name. `Super+0` and
  `Super+Shift+0` do the same for the last workspace in bar order.
- **`Super+Left` and `Right` go between windows, across displays.**
  **Decided** (2026-11-01, §19 question 12). They select the tiled window
  that way; at a display's edge, a window on the next display that way.
  - **One rule picks both the window and the display.** Of the ones whose
    center is on that side of yours: the one sharing the most height with
    yours, then the one whose center is nearest, then the first in tile
    order. "Yours" is the focused window, or the whole display with none
    of its own focused.
  - The next display is picked against this display, so with one to the
    upper right and one to the lower right, it's the one sharing more of
    this display's height. The window there is then picked against yours,
    from its tiles at the edge you come in by: those whose left edge is
    nearest that display's left going right, or whose right edge is nearest
    its right going left, a pixel's slack keeping a column together. So
    the stack beside you wins over a taller master on the far side, and on
    a taller display standing higher, it's the window in that column level
    with yours, not the top one.
  - The rule is tide for Linux's, in tide for Linux's own `direction.lua` (tide for Linux §6.6), copied
    unchanged; `make check-tide` fails if the two drift.
  - Past the last display that way, nothing. They don't wrap round to the
    far side *(a guess, to confirm)*.
  - A display that way with no tiles takes the keys, as one with nothing
    of the workspace showing does after a switch (§6.1) *(a guess, to
    confirm)*.
  - Floats aren't picked. A focused float starts from where it is.
  - In monocle, every tile has one center, so the keys go straight to the
    next display.
- **`Super+Shift+Left` and `Right` move the focused tile the same way.**
  On its display it swaps with the tile the rule picks. At the edge it
  goes to the next display, in the same workspace, as a window you drag
  there does (§6.1), into
  the place in that display's layout that puts it nearest the edge it came
  in by: its left edge moving right, its right edge moving left. Tile
  order isn't left to right (threecol's third tile is on the left), so
  tide lays out each place and picks by where the window would land;
  ties go to the place sharing the most height with where it was, then
  the nearest *(a guess, to confirm)*. Focus stays on it.
- **A focused float goes straight onto the next display that way,**
  **decided** (2026-11-01), picked by the same rule from the display it's
  on. It stays floating and in its workspace, joining that display's part
  of it, and focus stays on it. Past the last display, nothing. It keeps
  its place and size as far as it can, by tide for Linux's rule (tide for Linux §6.6,
  `direction.place`):
  - It keeps its relative spot. Its top-left corner's offset in the old
    display's work area, as a share of that area's width and height, gives
    the offset in the new one. One near the top left lands near the top
    left.
  - It keeps its size, unless it is wider or taller than the new work
    area. Then it shrinks to that width or height, and no further.
  - It is then moved just enough to be wholly inside the new work area.
    One in the bottom-right corner stays at that corner on a smaller
    display.
  - The work area is the display's area below the menu bar and tide's
    bar, where a new float is placed (§5.1).
- **`Super+PgUp` and `PgDn` step through workspaces with windows,**
  wrapping from the last to home and back, and passing over empty ones;
  with Shift they move the window to the very next, empty or not, and
  follow it. These took the jobs tide for Linux gives
  `Super+Left` / `Right` and `Super+Shift+Left` / `Right` (tide for Linux §6.6).
- **A three-finger swipe steps the same way** (`swipe.lua`), as tide for Linux's
  does (conf `hyprland.lua`): fingers moving left for the next workspace,
  right for the previous, as macOS's own swipe between Spaces goes.
  - There's no public gesture API, but an event tap on gesture events
    gets each finger's place on the trackpad (`getTouches()`), as
    community swipe Spoons read it. The events pass on, so apps still get
    their pinches and scrolls.
  - A swipe counts once three fingers have moved together 15% of the
    trackpad's width, at least twice as far sideways as up or down. It
    steps once, however far it goes, and the next needs every finger
    lifted first. Two or four fingers are left alone, and so is a
    three-finger drag, which holds the mouse button down.
  - `setup-macos --wm tide` turns off macOS's swipe left and right
    between Spaces, with three fingers or four, so the two don't both act
    (§6.6). `swipe = false` in start() turns tide's off.
  - *Unverified on a Mac:* that gesture events reach the tap on macOS 26
    with Accessibility alone, and that `getTouches()` still names each
    finger's `identity`, `phase` and `normalizedPosition`.
- **`Super+Tab` and `Super+End` remember the workspaces you've shown,**
  most recent first. Like every workspace key, they switch every display
  together. A workspace that's gone since is
  passed over, and either key does nothing with nowhere to go.
- **`Super+Return` goes to a workspace,** with tide for Linux's prompt (tide for Linux §6.5):
  an `hs.chooser` listing the existing names. It moves no window, so it
  works from any workspace, an empty one included.
  - It needs no focused window, so the text starts empty.
  - Typing filters the names or gives a new one. Enter on an existing name
    shows it. Enter on a new name shows a new, empty workspace of that
    name, which goes again once you leave it empty.
  - "in" is offered, since nothing moves there.
  - Esc stays where you are.
  - A second press while it's open asks nothing more.
- **`Super+Shift+Return` moves the focused window to a workspace,** with
  the same prompt. Enter moves the window, making the workspace if the
  name is new, and follows it: that workspace shows, with the window
  focused on the display it was on, as on tide. Esc leaves it where
  it is. This is Move (§6.1).
  - With no window focused there's nothing to move, so it does nothing,
    and Hammerspoon's console says why.
- **`Super+Return` used to move the window,** as tide for Linux's did. Both moved it
  to `Super+Shift+Return`, which nothing else used, so `Super+Return`
  works with no window to move.
- **`Alt+Tab` takes `Super+Return`'s first job,** the master swap. It
  makes the focused window the master. On the master, it swaps with the one that was master before.
  - Under the rotation, physical Alt sends Control, so physical Alt+Tab
    arrives as Ctrl+Tab, which is the apps' own next tab (scripts
    `docs/MACOS.md`, "The one binding the rotation inverts").
  - **Decided:** physical Alt+Tab gives up its job as Cmd+Tab, macOS's app
    switcher. conf's rule used to make it Cmd+Tab; now tide's Karabiner
    rule sends it as `Ctrl+Option+Shift+Tab`, a combination nothing else
    uses, which tide registers. Physical Ctrl+Tab stays the apps' next
    tab.
  - So physical Alt+Tab no longer switches apps. The switcher's Windows
    tab (§9) stands in. So does physical right Ctrl+Tab, on a keyboard
    that has a right Ctrl: the rotation makes it Cmd+Tab, and conf's Tab
    rule only takes left Ctrl.
  - A Mac keyboard's Cmd+Tab doesn't switch apps. `setup-macos` applies
    the rotation to every keyboard, the built-in one included, so its
    Command key sends Option.
  - Without Karabiner, tide doesn't take Ctrl+Tab, since that would take
    every app's next tab. Swap with the master has no key then *(a guess,
    to confirm)*.
- **App keys** are tide for Linux's (conf `hyprland.lua`). Each brings the app's
  window forward, launching the app if it has none, and brings its
  workspace with it (Activate, §6.1).
  - From a workspace that asks, "in" by default, a key that would launch
    asks for a workspace name first, unless the app is one of "in"'s
    (§6.2). Esc cancels the launch.
  - **Super+T opens a new kitty window every time,** on the workspace
    you're on, as tide for Linux's terminal key does: Cmd+N to a running kitty, or a
    launch.
  - Browser profiles run with their own `--user-data-dir`, as tide for Linux's
    `browser2` and `browser3` do.
  - Web apps are installed web apps, which have their own Dock icons and
    badges (tide for Chrome §3.5).
  - Helpers run through the login shell's environment. Apps started from a
    key inherit launchd's short `PATH`, which tide for Linux met as "PATH missing in
    keybinds" (tide for Linux §17).
- **Keyboard's Shortcuts,** in tide's settings window, list every binding
  that registered, and every key that didn't, as tide for Linux's Keyboard page does
  (§15, tide for Linux §16).

### 7.3 Taking keys from the system and the old setup

`RegisterEventHotKey` fails silently on a key someone else holds (§2.2), so
`setup-macos` has to free these first:

- **symbolichotkeys:**
  - 118–126 (Option+1…9, "Switch to Desktop N"), set by `setup-macos` now;
  - 64 (Spotlight on Option+Space): Spotlight moves back to Cmd+Space,
    physical Ctrl+Space;
  - 79 and 81 (Ctrl+Option+arrows, move a Space left and right);
  - 32 and 33 (Ctrl+Up and Ctrl+Down, Mission Control and App Exposé),
    which tide's overview takes (§6.9).
- **Amethyst:** no longer `setup-macos`'s default (§19, question 4), so its
  `mod1`-`mod4` combinations go. `setup-macos --wm amethyst` still sets it
  up, with conf's `amethyst.yml`, for a machine that wants it.
- **Rectangle:** `setup` no longer installs it. Its defaults sit on
  Ctrl+Option+arrows *(unverified)*, so `setup-macos` warns about one
  already installed.
- **Karabiner's Win+arrow rule** sends Ctrl+Option+arrow for native Spaces
  and Win+Shift+arrow for Amethyst's throw. Both now go to tide.
- **Karabiner's Alt+Tab rule** sent Cmd+Tab. It goes to tide's swap
  with the master instead (§7.2).
- **Super+Shift+N sent to workspace N.** Those keys are gone (§7.2), so
  `setup-macos`'s Super+Alt+N go with them.

## 8. Bar, clocks and dashboard

- **The menu bar stays the system's.** Two ways to live with it:
  - **Option 1:** the bar is a tide panel along the top, with the menu bar
    set to hide automatically. It shows the workspaces, the layout symbol,
    the title and the clocks, as tide for Linux's does (tide for Linux §7). The cost: the
    system's status items (Wi-Fi, battery, volume) and the app's menus show
    only when the pointer reaches the top edge.
  - **Option 2:** no bar. The workspaces and clocks go in the menu bar's
    right side as status items, plus a full-screen dashboard on a key, as
    tide for Chrome's is (tide for Chrome §8.1).
  - **Decided: option 1, with tide's own status icons.** At first the
    menu bar was set to hide automatically (System Settings › Control Center ›
    "Automatically hide and show the menu bar": Always, or
    `defaults write NSGlobalDomain _HIHideMenuBar -bool true`). tide's bar
    takes the top 36 px of each display, up over the notch on a MacBook's
    own (below), and draws the common status items itself, so they don't
    need the menu bar revealed.
  - **Now: the menu bar shown, and covered** (the hidden one slid
    in too easily). With "Automatically hide and
    show the menu bar" set to Never, the menu bar never slides in, so
    reaching the top edge by accident does nothing. tide's bar covers it:
    each display's bar starts at the top of the screen, at the status
    window level just above the menu bar's (`bar.level`), as tall as the
    menu bar or 36 px, whichever is taller (`bar.place`), and windows tile
    below it. A shown menu bar taller than 30 px is taken as a notched display's (`bar.top_room`), so the title and chips still keep clear of the notch. The Apple logo's menu starts with **Show Menu Bar**, which
    hides every bar so the real menu bar shows, with the app's menus and
    other apps' status items, until Esc, Return, or a click or release below the bars
    (`bar.reveal_done`): a click on the menu bar or a menu's title keeps
    it, and choosing a menu item, by a click or a drag, brings the bars back *(unverified on a
    Mac that macOS lets a window sit over a menu bar that shows; CI's
    smoke test checks the bar's frame there)*.
  - **Covering needs the setting.** While macOS still hides the menu bar,
    it slides in over everything at the top edge, tide's bar included,
    and no window level stops that. So tide says so at start and in
    `tide doctor` (`checklist.MENU_BAR_NOTICE`), and the setup checklist
    asks for Never. It reads the setting at start and again whenever the
    displays change, as they do when the setting does, so covering starts
    without a reload *(unverified on a Mac that the screen watcher fires
    for it)*.
  - **What still needs the menu bar:** the app's own menus, the Apple menu,
    and other apps' status items (a VPN, an IT agent, Zoom). The Apple
    logo opens tide's copy of the Apple menu (below); the app's menus
    and status items still need the pointer at the top edge.
  - **The pointer is kept off the bar's top row,** one point down
    (`bar.off_top`), so the hidden menu bar no longer slides over the bar
    each time the pointer reaches the top edge. macOS shows it only for the
    top row, and offers no setting to stop that. Top hot corners and
    anything else that needs the very top edge are lost on displays with a
    shown bar; under a full-screen window, where the bar hides, the menu bar
    shows as usual *(unverified that one point is enough on every macOS)*.
    Tide Settings' Appearance page has the switch, "Menu bar kept hidden",
    on by default and kept in `hs.settings` as tide's own; off, the menu
    bar shows at the top edge as on any Mac.
  - **Option 2 stays as the fallback,** with `bar = false` in `start()`: a
    menu bar item draws tide's logo, as a template image macOS tints for a
    light or dark menu bar, then the workspaces' names as text, current,
    occupied, and wanting attention, with no app icons. Its tooltip says
    tide. A click switches. It sits on the right, since
    the menu bar's left side is the Apple menu and the app's menus.
  - Either way, the workspace's name shows briefly in the middle of the
    screen on each switch, at about the size of macOS's own alerts
    (28 pt), not across the screen.
- **If it's a bar, it's tide for Linux's** (tide for Linux §7.1–§7.4):
  - a flush 36 px strip, one per display, with the tiling area starting
    below it;
  - **the Apple logo first of all,** in the corner as on a Mac's own
    menu bar: the system font's Apple glyph in the text color. A click
    opens tide's own copy of the Apple menu under it, drawn as the
    session menu is (`hs.menubar`'s `popupMenu`): About This Mac, System
    Settings…, App Store…, Sleep, Restart…, Shut Down…, Lock Screen and Log
    Out…. Each opens the real thing or runs the session menu's action. It
    has no Recent Items or Force Quit, nor what a profile adds to the real
    menu. The real Apple menu can't be opened while the menu bar stays
    hidden, all seen on a Mac: a pointer moved to the top edge by software
    doesn't reveal it, an Accessibility press (`AXPress`) on its first item
    reports success and shows nothing, and on one Mac "Move focus to the
    menu bar" (Control+F2) didn't show it either, pressed or sent. With the
    menu bar's "Reduce transparency" on (Accessibility, Display), the
    revealed menu bar is solid over the bar;
  - **tide's logo next,** two waves in the accent color, as on tide for Linux
    (tide for Linux §7.1). A click opens the switcher on Launch, as `Super+Space`
    does, or closes it if it's open, on any tab. It opens where
    `Super+Space` opens it, on the display with the focused window, not
    always the clicked bar's: `hs.chooser` centers itself there *(a
    guess, to confirm on two displays)*;
  - workspace chips in list order, each with its name, that show current,
    occupied and wanting attention, **drawn as tide for Linux's** (tide for Linux's
    `shell/Workspaces.qml`): 26 px tall, 7 px corners, the name semibold; an
    occupied chip on tide for Linux's surface color, the current one filled with its
    accent, an empty one bare with a faint name, one on another display
    ringed in the accent, and one wanting attention tinted and ringed amber,
    the current one's too. The colors are tide for Linux's palette's, light and dark,
    and `make check-tide` compares them; CI's smoke test checks the chips
    as Hammerspoon's WebKit draws them, light and dark. Every display shows the same
    workspace, so every bar marks the same one current. A long
    name is cut with an ellipsis at 16 characters *(a guess, to confirm)*. The only empty chips are "in" and
    the standing workspaces, dimmed: any other empty workspace goes once
    you leave it (§6.1);
  - **no app icons, except for attention.** Decided with tide for Linux: a chip is
    its name alone, plus the app icon of each window there wanting
    attention (§14.2), up to five, then `+n`. A click on that icon focuses
    the window, bringing its workspace along. The chips used to show an
    icon per window, which crowded the bar once workspaces had names;
  - a click elsewhere on a chip shows that workspace, and scrolling steps
    through them;
  - the title only on the display the focused window is on, where
    double-clicking it maximizes, and hovering it shows it uncut, as on
    tide for Linux (tide for Linux §7.1);
  - the clocks shrink to local time alone when the title would get narrower
    than 200 px.
  - **a right-click on an item opens its Tide Settings page,** by tide for Linux's map
    (tide for Linux §7.1), copied as `dashboard/tide-barsettings.js` and checked by
    `make check-tide`: a chip opens Workspaces, the title Floating, the
    clocks Clocks, the speaker and the mic Sound, keep awake and the session
    icon Idle, Presenting Notifications, and so on. The Apple logo, the
    camera and the system monitor open the first page, as tide's logo,
    sharing pill and system monitor do. WebKit's own menu stays away from
    the items *(unverified on a Mac that the bar's webview gets the
    right-click)*.
- **The bar on Hammerspoon** is built like the dashboard: one borderless
  `hs.webview` per display, from the same copies of tide for Chrome's modules and
  stylesheet, plus tide's `bar.js`. It stays open, and tide sends it new
  state as JSON on every change, on the attention poll (for titles that
  change without focus moving) and when the icons change. Each page only
  redraws when what it was sent changed.
  - A chip shows one app icon per window there wanting attention, tiles
    in layout order then floats, up to five, then `+n`. Icons come from
    `hs.image.imageFromAppBundle`, sent as 32 px PNG data URLs, made once
    per bundle id and sent once per app, not per window. An app with no
    icon shows as a blank square, so the count still reads.
  - A click on an icon names its bar's display and the window. tide shows
    the window's workspace if it isn't showing, then activates the window
    (§6.1).
  - Double-clicking the title, or the free bar around it, maximizes the
    focused window, or puts it back (§5.4), as a Mac's title bar does. The
    message names its bar's display, and tide acts only if the focused
    window is there, where the title shows.
  - Clicking the clocks opens the dashboard, with its clock panel.
  - **No dead clicks.** Each item's click target is its whole span (a
    chip, the clocks row with every zone's name and time, a status icon
    with its text) reaching the bar's top and bottom and halfway across
    the gap to each neighbor, so a click between two items goes to the
    nearer one. The logo reaches the display's left edge, and splits the
    gap to the first chip with it, and the last item reaches its right
    edge; the room between the two groups is the
    title's, while there is one. Inside a chip, a window icon's target is
    the chip's height and halfway to its neighbors. `bar.js` measures the
    items on each fit and draws each target as a box under the item's
    content.
  - **Hover shows the target.** Under the pointer, an item's whole target
    shows as a rounded rect, half pressed: tide for Chrome's `--hover`, a shade
    darker than the bar in light and lighter in dark. A chip shows with
    the space around it, a window icon as its own, the title as the free
    bar, a status item with its text, the logo, and the clocks as one row. The
    rounding is drawn, not hit-tested, so it moves no click. WebKit
    follows the pointer only in the key window, which the bar never is
    (WebKit's `trackingAreaOptions` in `WebViewImpl.mm`), so `:hover`
    doesn't fire there: tide's pointer tap tells the bar it's over where
    the pointer is, one small script per move over a bar, and the page
    marks that target. There's no appearance (dark mode) item in the bar.
  - **The same room around each target's content.** The clocks pad their
    sides 6 px, as a status icon does, and sit the icons' 2 px from the
    first, so the clocks' hover doesn't end at their first letter, and keep
    awake's isn't wider than the microphone's.
  - **Hovering the title shows all of it** in a tip below the bar,
    centered on the title, since the bar cuts a long one with an ellipsis.
    It wraps past 600 px. The page can't draw past its own strip, and a
    `title` attribute's tooltip needs WebKit to follow the pointer, which
    it doesn't here (above). So the page tells tide the title and where
    it is when the hovered target becomes the title, and that it's gone
    when it stops being; tide draws the tip as an `hs.canvas`, as the
    tray's tips are (§6.7). With no title there's no tip. The tip goes
    with its bar: when that bar hides for a full-screen window, its
    display is removed, or it moves.
  - **Every other tip takes the same path,** centered on its item: a
    status item's (its state, the Wi-Fi network's name, the battery's time
    left), the camera's, though it's no click target, and a chip's whole
    name when the chip cuts it. A whole name has no tip, nor does a window
    icon. The page keeps each tip in `data-tip`, not `title`, so no
    WebKit tooltip could ever show beside tide's.
  - A first click isn't spent on bringing Hammerspoon forward:
    `hs.webview`'s view accepts the first mouse (its `acceptsFirstMouse`
    returns yes, in Hammerspoon 1.4.27's `libwebview.m`), so it reaches the
    page.
  - It floats above every app's window but below the menu bar, joins every
    Space, and stays put.
  - Focus follows mouse pauses over it, as over the menu bar (§5.2).
  - The bar hides on a display while a window there is full screen, and
    comes back after: tide's full screen (§5.4) in that display's part
    of the workspace, or the focused window in macOS's own full screen on that
    display. macOS's is only known for the focused window *(unverified
    how a swipe away from its Space shows to tide)*.
- **tide's status items** are 16 px line drawings in the text color,
  drawn by `bar.js` itself with no icon font or fetch, so they follow the
  bar's light and dark colors. State shows as color: muted or off in the
  muted color, active (keeping awake, a camera in use) in the accent
  color, and a low battery in the urgent color. `make mocks` renders them.
  They come from Hammerspoon. Audio, cameras and the input source have
  watchers, so a change shows at once; the rest are read every 5 s. Left
  to right:
  - input source: `hs.keycodes`, a short label for the current layout or
    input method, only with more than one enabled. A click goes to the
    next one.
  - keep awake: a cup of coffee, `hs.caffeinate`'s `displayIdle`, the
    same switch as the launcher's Keep awake and `Super+S`. A click
    toggles it, with the same sign as `Super+S` (§10). Its tip says what
    it's doing in the sign's words, "Keeping awake" or "Not keeping
    awake", as tide for Linux's hover does (tide for Linux §10).
    **While presenter mode is on** (§10) it's a filled accent pill reading
    "Presenting", as tide for Linux's Presenting pill is, and a click ends presenter
    mode.
  - camera: `hs.camera`, shown only while one is in use, as macOS's green
    dot *(unverified that reading it needs no Camera permission)*.
  - microphone: the default input device through `hs.audiodevice`, muted
    or not. A click mutes or unmutes, as `Super+Shift+M` does (§7.2). A
    device without its own mute control says so rather than faking one.
    **No "in use" light:** Hammerspoon's `inUse()` reads
    `kAudioDevicePropertyDeviceIsRunningSomewhere` in the global scope, so
    on a headset that's both input and output, playing sound would light
    it. It has no input-only reading; macOS's own orange dot shows a
    microphone in use.
  - Bluetooth: on or off, as tide for Linux's: one glyph, faint while off and in the
    text color while on. A click opens Bluetooth settings.
    - Hammerspoon has no module for it (there is no `hs.bluetooth`), so
      tide asks `blueutil -p` (Homebrew's `blueutil`, which scripts'
      `setup-macos --wm tide` installs), found at `/opt/homebrew/bin` or
      `/usr/local/bin`, since Hammerspoon's PATH has neither.
    - It runs through `hs.task`, never waiting on it, one run at a time:
      as tide starts, on wake, and every 30 s, and again when the
      settings window's Bluetooth page changes anything (§15).
    - Hidden with no `blueutil`, no adapter, or any failure, and the log
      says why once, until the reason changes or clears. The headphones
      icons don't need it.
    - **Cost and reliability:** free and open source, from Homebrew. One
      short process every 30 s. A missing or failing `blueutil` only hides
      this icon.
  - headphones: one per connected Bluetooth audio device, as tide for Linux's
    headphones icons are (tide for Linux §7.4). They're `hs.audiodevice`'s output and
    input devices whose transport is Bluetooth, which macOS lists only while
    connected; a headset is both, and gets one icon. Hovering one names it.
    A click opens Bluetooth settings. No battery: `hs.audiodevice` doesn't
    read one.
  - speaker: the default output device, in four levels with mute, then
    its level as a %, dimmed while muted and held as wide as two digits, as
    tide for Linux's (tide for Linux §7.4). Its tip is "Sound 40%" or "Sound muted". A click
    opens the volume popover; scrolling on it changes the volume 5% a step,
    and up unmutes, as the volume keys do.
    - **The volume popover,** as tide for Linux's (tide for Linux §7.4), in a borderless
      `hs.webview` under the speaker (`volume.lua`, `volume_hs.lua`,
      `dashboard/volume.html`): the output's name, a mute button and a
      slider with its %, then every output device by name, the one in use
      checked, and "Sound Settings…". Clicking an output makes it the
      default. macOS's own volume follows the slider as it moves; a DDC
      monitor's is set once it's let go, since each change is a run of its
      tool. An output with no volume control says so in place of the
      slider, and its mute is off unless it can mute. A second click on
      the speaker, Esc, or a click anywhere else closes it; focus follows
      mouse waits while it's open. No per-app volumes or inputs, which
      tide for Linux's has: macOS has no API for an app's volume *(unverified on a
      Mac)*.
    - **An output with no volume control still shows:** a monitor's own
      speakers over HDMI or DisplayPort, and many USB interfaces, have none
      macOS can read, so `outputVolume()` is nil. The speaker shows full,
      with no % and no scrolling, and its tip names the device and says it
      has no volume control.
    - **A monitor's speakers answer over DDC/CI** (`ddc.lua`): MCCS's
      audio speaker volume (VCP `0x62`) and mute (`0x8D`). With a reading,
      the speaker shows as any other output's, level and %, and the
      popover and a scroll set the monitor's own volume and mute. The change shows at
      once, then goes to the monitor.
      - The tool is Homebrew's `m1ddc` on Apple silicon or `ddcctl` on
        Intel, found at `/opt/homebrew/bin` or `/usr/local/bin`; scripts'
        `setup-macos --wm tide` installs the one for the Mac. `m1ddc`
        comes first: `ddcctl`'s `IOFramebuffer` calls don't reach displays
        on Apple silicon.
      - The output's display is the one with the device's name, as macOS
        names a monitor's speakers, else the only external one. It's
        matched to the tool's own list by UUID (`m1ddc display list`, or
        bare `ddcctl`'s display lines), then by name, then by being the
        only one *(unverified that `m1ddc`'s UUIDs are `hs.screen`'s)*.
      - Read as tide starts, when the output or the displays change, on
        wake, and every 30 s, since the monitor's own buttons change it
        without telling anyone. Runs go through `hs.task`, never waiting,
        one at a time.
      - A reading belongs to the display it came from, and a change goes
        only there. Switching outputs, or a display coming or going (which
        can renumber `ddcctl`'s), forgets the reading at once and drops any
        read still out, and any change still queued, so a click or scroll
        can't reach the wrong monitor.
      - With no tool, no matching display, or a monitor that doesn't
        answer, the speaker stays as above, and the log says why once,
        until the reason changes or clears.
      - **Cost and reliability:** both tools are free and open source
        (MIT and GPL-3.0), from Homebrew. A read is three short `m1ddc`
        runs or one `ddcctl` run, every 30 s, only while the output has no
        volume of its own. DDC is slow and some monitors don't answer it,
        or not over a built-in HDMI port; then only the reading is lost.
      - **The volume keys** step a monitor's speakers it reads over DDC, as
        a scroll does, and mute toggles them, as a click does; a sign at
        the center of the screen says the level or "Sound muted". macOS
        would show its "no volume" sign there. tide takes them with an
        `hs.eventtap` on system-defined events (the media keys), which
        needs Accessibility, as tide's other taps do; for any other
        output, or before a reading, the keys go on to macOS. Steps are
        5%, not macOS's sixteenths, and Shift+Option's quarter steps don't
        apply *(unverified on a Mac)*.
  - network: Wi-Fi through `hs.wifi`, on or off with signal in three bars
    from the RSSI, or a wire, or no network, by which interface
    `hs.network.primaryInterfaces` says carries traffic. The Wi-Fi
    network's name shows on hover only when macOS gives it, which needs
    Location Services on recent macOS *(unverified for Hammerspoon)*.
    - **A VPN's lock,** as tide for Linux's (tide for Linux §7.4): a small lock on a disc of the
      bar's color at the icon's bottom right, and ", VPN on" after the tip.
      Hammerspoon has no VPN module, so a VPN is up when the interface
      carrying traffic is a tunnel (`utun`, `ipsec`, `ppp`, `tun`, `tap`),
      or when a VPN's network service is up: one in the System
      Configuration store (`hs.network.configuration`,
      `State:/Network/Service/*/IPv4` and `IPv6`) on a tunnel whose
      `Setup:/Network/Service/*/Interface` type is `VPN` (a VPN app's
      Network Extension), `IPSec`, or `PPP` for L2TP or PPTP. The second
      catches a VPN that carries only some traffic. A tunnel with no VPN
      service, as macOS's own `utun` interfaces and some apps' are, isn't
      one. Under a VPN that carries it all, the icon is the link below:
      Wi-Fi while it's joined to a network, else a wire. No "connecting"
      state: macOS's store shows a tunnel only once it's up *(unverified
      for every VPN client; a VPN client with no VPN service, such as
      Tunnelblick's, shows the lock only while it carries all traffic)*.
  - battery: `hs.battery`, with its percentage and a charging mark, and on
    hover how long until full or empty when macOS knows. None on a Mac
    without one.
  - system monitor: the CPU's %, as tide for Linux's (tide for Linux §7.4), held as wide as
    two digits. It's the share busy since the last reading, from
    `hs.host.cpuUsageTicks()`, so the first reading shows "–".
    - **Colors:** the warning color when the Mac is hot or memory is 90%
      full, and the danger color while it's throttling, both from tide for Linux's
      palette. Its tip says why: "CPU 23%, hot", "throttling", "memory
      nearly full".
    - macOS gives no temperature or throttle count to an app, so
      `hs.host.thermalState()` stands in: "serious" (high) is hot, and
      "critical" (performance cut until it cools) is throttling. "fair"
      (slightly raised) is normal, since it comes with any steady load
      *(a guess to confirm on a Mac under load)*.
    - Memory is wired, active and compressed pages from `hs.host.vmStat()`
      over its `memSize`, near Activity Monitor's "Memory Used" *(an
      approximation)*.
    - A click opens Activity Monitor. tide for Linux's opens a popover with the
      busiest processes; Activity Monitor already lists them on a Mac.
    - Read on the 5 s icon poll, where tide for Linux reads every 3 s. Each reading
      is a few kernel counters, with no process started.
  - session: a power symbol, last, as tide for Linux's (tide for Linux §7.4), whose tip is
    "Lock, log out or power off". A click shows macOS's own menu under it
    (`hs.menubar`'s `popupMenu`, from a menu item that's never in the menu
    bar): Lock, Log Out, then Sleep, Restart and Shut Down, in the Apple
    menu's words and groups. tide for Linux's Suspend is macOS's Sleep.
    - Lock and Sleep are `hs.caffeinate`'s `lockScreen` and
      `systemSleep`. Log out, restart and shut down ask System Events
      through `hs.osascript`, as `hs.caffeinate`'s do, but check its answer:
      a refusal, such as Automation access to System Events being denied,
      is logged and shown as a notification, where `hs.caffeinate` drops
      it. They go through macOS, so an app with unsaved work can stop them
      and say why, as tide for Linux's "blocked by" does *(unverified that none of
      them asks first)*.
    - The page sends where the icon is, and the menu opens below the bar
      there; macOS keeps it on screen at the right edge.
  - The battery, network, Bluetooth and headphones items open their System Settings panes, named
    by URL (`x-apple.systempreferences:…`) *(unverified on macOS 26)*.
- **Not drawn:** Focus (Do Not Disturb). Hammerspoon has no module for it
  (there is no `hs.focus`). Its menu bar item shows when the menu bar is
  revealed.
- **The notch,** on a MacBook's own display, sits where tide for Linux centers the
  title.
  - Even with the menu bar hidden, macOS keeps a strip as tall as the
    notch at the top of that display: `hs.screen`'s frame starts below it.
    A bar placed in the frame sat under the notch, wasting the strip.
  - **So the bar goes up to the very top there,** over the notch's strip,
    as tall as the strip or 36 px, whichever is taller, and windows tile
    below it (`bar.place`).
  - **macOS can refuse the strip:** on the owner's MacBook it moved the
    bar's window back down below the notch, so windows, tiled from the top
    of the strip, sat under the bar. So tide reads the bar's frame back
    each time it places it, and when macOS has moved it lower, windows tile
    below where the bar really is (`bar.place`'s floor), and the log says
    where macOS put it.
  - **What macOS leaves in the strip is the window level,** tried on the
    owner's MacBook: a canvas or a web view at the floating, or even the
    Dock's, level is moved down out of it, and one at the main menu's level
    or above stays. So a bar over a notch is at the main menu's level
    (`bar.level`), set before the window is placed; every other bar stays
    floating, below the menu bar. *(unverified: whether the menu bar,
    revealed at the top of that display, still shows over the bar, at the
    same level.)*
  - A display counts as having a notch when the menu bar is set to hide
    always (`_HIHideMenuBar`, read once with `defaults`) and its frame
    still starts below its full frame: with the menu bar hidden, the notch
    is the only thing that keeps room there. With the menu bar showing,
    the bar stays below it, as on any display.
  - **There's no title on that display,** since the notch sits where it
    goes, and the bar keeps its middle 220 px clear, a little wider than
    the notch *(unverified per model)*. The clocks already shrink to keep
    200 px there (tide for Linux's rule).
  - **Chips that would reach the notch hide behind a "+n" chip,** in bar
    order, the current workspace's always showing in place of the last
    that would. A click on "+n" opens the switcher's Workspaces tab, which
    lists every workspace. Super+1…9 still count every workspace, hidden or
    not. The right group isn't held back: its clocks shrink, and its icons
    fit beside the notch on a MacBook's width.
- **Status icons:** macOS's orange and green dots already show the
  microphone and camera in use, which covers tide for Linux's privacy pills
  (tide for Linux §7.4). The microphone-mute state from `Super+Shift+M` shows in the
  bar, since macOS has no system-wide mute of its own.
- **Clocks:** tide for Chrome's `src/clocks.js` and `calendar.js` hold the zone,
  daytime-strip, DST and calendar logic, all tested. A native tide would port
  them.
  - **Which clocks** is tide for Linux's setting, read from tide for Linux's `clocks.json` and
    `clocks.local.json` (§15) with tide for Linux's own module, `shell/lib/clocks.mjs`,
    copied unchanged as `dashboard/tide-clocks.js` and checked against
    tide for Linux's in CI. With neither file, they're tide for Chrome's: Sydney, Los Angeles,
    New York and London. A label of `"abbr"` shows the zone's abbreviation
    from Intl, which says `GMT+1` for London in summer (tide for Linux §7.3).
  - **Which are in the bar** is tide for Linux's setting too (tide for Linux §7.3): every zone
    is unless its entry says `"bar": false`, and the dashboard's clock
    panel lists them all. The Clocks window's **Bar** box on each clock
    sets it, in `clocks.local.json`.
  - tide for Linux's `hour24` and `dedupeLocal` switches are read but not followed:
    tide for Chrome's clock view is always 24-hour and always hides the local zone.
  - A file that's wrong keeps the clocks as they were, and a notification
    says which file and why, once. tide keeps the last good clocks the
    pages loaded, so a page opened while a file is wrong shows them too.
- **The dashboard, on Hammerspoon,** is a borderless `hs.webview` over the
  display you're on, from `Super+Shift+Space`:
  - It shows tide for Chrome's bar (the workspace chips, by name alone, the focused
    window's title, the clocks) over tide for Chrome's clock panel: each zone's day strip, the next
    DST change, and a month calendar.
  - tide for Chrome's `clocks.js`, `calendar.js`, `clockview.js` and `launcher.css` are
    copied unchanged, and CI checks they still match tide for Chrome's.
  - A webview can't load ES modules from files, so tide joins them into one
    script, each module in its own scope.
  - A click on a workspace's chip shows it. Esc, the key again,
    or clicking away closes it.
  - The switcher stays `hs.chooser` (§9) by default, so the dashboard has no
    search. tide for Chrome's own dashboard page, with its search, is built as the
    dashboard launcher (§9.2), switched off.
  - Focus follows mouse pauses while it's open (§5.2).

## 9. The switcher

**One overlay, with tabs,** as tide for Linux's (tide for Linux §8): the launcher, the
workspaces, every window, and the windows wanting attention. It's the
launcher's `hs.chooser` with tide for Chrome's scopes (tide for Chrome §9.4), one scope per
tab, the search field naming the tab you're in.

- **The default is the `hs.chooser` switcher** this section describes.
  `start()`'s `launcher = "dashboard"` swaps it for tide for Chrome's dashboard page
  (§9.2), which is built but switched off until it's been tried on a Mac.
  Any other value is an error at load. The name prompt and the picker
  (§9.1) stay `hs.chooser` either way.

- **The search field's hint names only the keys that work on that tab,**
  as tide for Linux's footer does (tide for Linux §8.1): `Tab` and the tab it goes to on all
  four, `Cmd+Return`'s new workspace on Launch, and `Cmd+M`'s mute on
  Windows and Attention. Elsewhere `Cmd+Return` does what Return does, and
  `Cmd+M` has no row to mute. `hs.chooser` has no footer, so the hint is
  the one place to say it.

- **How a row looks,** in tide for Linux's colors, dark or light as macOS is when
  it opens (`launcher.look`), 40% of the display wide and 10 rows tall:
  - **An icon on every row:** an app's own, a window's or a wanting-attention
    row's from its app, a tab's from its browser, a System Settings pane's
    from System Settings, a screenshot's from Screenshot, and the session's
    (lock, log out, sleep, restart, shut down) from macOS's images. tide for Linux's
    own rows, Tide Settings and its commands and toggles, show its logo.
    Each icon is read once and kept, since the rows are rebuilt on every
    keystroke; one that can't be read is left out.
  - **The query's matched letters** are bold and in the accent blue, where
    the fuzzy match found them.
  - **The line under the title** ends with the key that does the same,
    dimmer: `Super+L` beside Lock, `Shift+Print` beside a region's
    screenshot.
  - **Headers with nothing typed:** Launch shows Recent (the five used
    last) and then Apps, System Settings and Commands; Actions groups its
    rows as Session, tide for Linux, Toggles and Screenshots. A typed query, and the
    other tabs, are one ranked list. A header is a row that can't be
    chosen: `hs.chooser` has no other kind. The first real row is selected
    when the rows change, but the arrow keys still stop on a header, Return
    there does nothing (`hs.chooser` honors a row that can't be chosen only
    with an invalid callback, so tide registers an empty one), and
    `Cmd+1…9` count it as a row.
  - **Colors come from each row's styled text.** The switcher sets no
    chooser-wide text colors: `hs.chooser` applies those over every row,
    which would undo a match's accent, a header's gray and the dimmer key
    hint.

- **Tabs,** in this order *(the order is a guess, to confirm)*:
  - **Launch:** apps, System Settings' panes and tide's commands.
    **Tide Settings** is listed among the apps, with tide's logo, and opens
    tide's settings window. Each of the window's sections has a row of
    its own, "Tide Settings: Clocks" and so on, found by its name or by
    what it covers ("left-handed", "time zones"), which opens the window
    there. Those rows are for a query alone, as tide for Linux's per-page rows are
    (tide for Linux §8.2), so they don't crowd the empty list. The sections come
    from one list in `launcher.lua`, `SETTINGS_SECTIONS`, and a test checks
    each against `settings.html`.
  - **Workspaces:** every workspace by name, in bar order, with its app
    icons and whether it's showing, the standing ones included before they
    exist. Return shows it, making a standing one the first time (§6.1).
  - **Windows:** every window on every workspace, by title, with its app
    and workspace, and every Chrome and Safari tab, with its window's
    workspace. A window you minimized is marked "minimized" (§6.7). Return
    on a window activates it with its workspace (§6.1), restoring it if
    you'd minimized it.
    Return on a tab brings that tab forward in its window, then does the
    same. This takes in the old Tabs scope.
  - **Attention:** the windows wanting attention on any workspace (§14.2),
    most recent first, by title, with their app and workspace. Return goes
    there with its workspace.
  - **Actions:** every quick action, listed with nothing typed, in a fixed
    order: lock, log out, sleep, restart, shut down, reload and check
    tide, keep awake, presenter mode, Do Not Disturb, dark style, focus
    follows mouse, then the screenshots. Typing filters them. They're off
    Launch's empty list, and a query there that matches nothing on Launch
    still finds one, as text that matches nothing in a tab searches them
    all.

  An empty tab says so, in a row that can't be chosen.
- **Each key opens it on its own tab:** `Super+Space` on Launch, the
  Super tap on Launch too, `Super+A` on Attention (§7.2); Workspaces is
  a `Tab` away. `Super+Tab`
  doesn't open it: it flips between "in" and the last workspace. The Windows tab has no key of its own *(a guess, to confirm)*.
- **`Tab` and `Shift+Tab` move between tabs,** forward and back, as the
  scopes do now.
- **A switcher key pressed while it's open** closes it if it's on that
  key's tab, as tide for Linux's second Super tap closes its launcher (tide for Linux §8), and
  otherwise moves to that tab *(a guess, to confirm)*. Esc closes it.
- **Where the rows come from:**
  - **Apps** come from `/Applications` and `~/Applications`, with the folders
    in them (vendor folders, Chrome's web apps), `/System/Applications` and
    its Utilities, `/System/Library/CoreServices/Applications` (Archive
    Utility, Screen Sharing, …) and Finder. Not Spotlight's index, which
    would also bring installers and the helper apps inside other apps.
  - **App scripts,** as tide for Linux's launcher lists them (tide for Linux §8): the scripts
    in `~/scripts` that open an app (Gmail, Google Calendar, Google Chat,
    Google Meet, YouTube Music, Discord, the browsers, the terminals, …),
    from scripts' own list of them, `~/scripts/launcher-scripts`, which
    `setup-tide` reads too. Each is listed among the apps by the name the
    list gives it, found by the script's own name too, with the icon of
    the Mac app the list names (Chrome's for a web app). One the list marks
    `linux`, as `bluetooth-connect`, isn't listed, nor one whose script
    isn't there. The list is read as the switcher opens, so a pull shows
    at once; without it, no app scripts are listed and the log says why,
    once. One runs through runenv as the app keys run them (§7.2), as its
    key does when it has one. One of home's apps by name (Gmail, Google
    Calendar, Google Chat, YouTube Music) launches from home, as an app
    does, and Cmd+Return asks for a new workspace. The dashboard launcher
    lists them among its apps.
  - **Settings panes** are the app extensions in
    `/System/Library/ExtensionKit/Extensions` that plug into System Settings
    (`com.apple.Settings.extension.ui`), listed as "Mouse settings" and so on,
    and opened with their `x-apple.systempreferences:` URL. Read once a start,
    since only a macOS update changes them.
  - **Workspaces, windows and attention** are tide's own state, so they
    cost nothing to list.
  - **`Cmd+M`, or a right-click,** on a row in the Windows or Attention tab
    mutes its app or site, or unmutes it (§14.2).
  - **Browser tabs** come from Chrome, Brave and Safari through AppleScript, run
    by `/usr/bin/osascript` as an `hs.task` rather than `hs.osascript`,
    which would hold Hammerspoon until the browser answers (§2.5).
  - **A tab's workspace** is its window's. AppleScript's window numbers
    aren't Accessibility's, so tide finds the window by its name, which
    both give *(unverified that they always agree)*.
  - **Choosing a tab** addresses its browser window by AppleScript's window
    id, collected with the tabs, not its number, which changes as soon as
    tide raises the window.
- **Browser tabs, cost and reliability:**
  - **Permission:** macOS asks once per browser for Automation, the first
    time the Windows tab lists its tabs (§11.1). Refused, that browser's
    windows still show, without their tabs.
  - **Latency:** each call is an Apple Event round trip to the browser,
    slower with many tabs, and slow or stuck while the browser is busy
    *(unverified how slow)*. So tide asks when the switcher opens, shows
    the windows at once, and adds the tabs when they arrive. The call gets
    a 2 s timeout, and a browser that misses it is skipped this time.
  - **A browser that isn't running** isn't asked, since an Apple Event to it
    would launch it. tide asks macOS for it by bundle ID alone
    (`hs.application.applicationsForBundleID`): `hs.application.get` walks
    every running app by name when the ID finds none, which held each open
    for 165 ms on CI's Mac, with no browser running.
  - **Cost:** nothing in money, no network, and no work at all while the
    switcher is closed.
- **Matching:** tide for Chrome's fuzzy match and ranking (`src/launcher.js`), with
  the most used and most recent first, and tide for Linux's empty-query sections
  (tide for Linux §8). Text matching nothing in a tab searches all of them, so a
  window or a tab still turns up from Launch.
- **Quick actions, as tide for Linux's** (tide for Linux §8), on the Actions tab: screenshot
  the window, screen or a region; lock, log out, sleep, restart, shut down;
  Do Not Disturb, keep awake, presenter mode, and dark style; reload
  tide. tide's settings are an app on Launch, Tide Settings.
- **Launching from a workspace that asks, "in" by default, asks for a
  workspace name first** (§6.2), so the
  app starts with the right `TIDE_WORKSPACE` (§6.3). Esc cancels the launch.
- **Cmd+Return** (physical Ctrl+Enter) runs the app on a new workspace, as
  Ctrl+Enter does on tide for Linux: it asks for a name first, from any workspace,
  since there's no empty one to use (§6.1).
- **The window before the switcher** gets focus back if you dismiss it, and
  is the window "screenshot window" captures (tide for Linux §13).
- **Kept out of screen shares,** as tide for Linux keeps its launcher out (tide for Linux §12),
  by marking tide's windows unshareable (`NSWindow.sharingType`)
  *(unverified that screen sharing still honors it on macOS 26)*.
- **Spotlight stays** on Cmd+Space, physical Ctrl+Space (§7.3). In macOS
  26, tide's commands can also appear there as App Intents (§2.6).

### 9.1 The picker

**`Super+V` opens tide for Linux's picker** (tide for Linux §8.4): its own `hs.chooser`, with
three tabs. V as in paste. `Super+;` opens it on Characters and
`Super+Shift+V` on Fill.

- **Clipboard:** what you've copied, newest first, one line each,
  searched with the switcher's fuzzy match.
  - An `hs.pasteboard` watcher keeps each copy as it happens. It keeps
    text only: an image or a file copied isn't listed.
  - **It never keeps a password.** A copy whose pasteboard types include
    `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`
    is skipped. That's [nspasteboard.org](http://nspasteboard.org)'s
    convention, which password managers follow: Bitwarden's desktop app
    sets the concealed type through arboard 3.6.1. A copy whose types
    can't be read isn't kept either.
  - The types are read when the watcher fires, so a copy replaced within
    that moment is judged by its replacement's types, as on tide.
  - **Kept on disk for a week, encrypted:** the newest 100, each for 7
    days, or as the Clipboard settings say (§15), so it outlives a restart
    and a reboot, as tide for Linux's does (tide for Linux §8.4).
    - **The days:** an entry last copied that many days ago is forgotten,
      in memory and on disk, checked hourly and at each save. Copying it
      again starts its days afresh.
    - **Encrypted** (`clipcrypt.lua`) with AES-256 by macOS's own
      `openssl`, its key derived with PBKDF2 from a random 256-bit secret
      kept in the login keychain as "tide clipboard history" through
      `security`. The secret is made the first time a copy is saved.
    - **How it runs:** each save or read is one short `sh` script, run
      with `io.popen`, that fetches the secret itself and hands it to
      `openssl` in its environment, so it never passes through
      Hammerspoon or a command's arguments, save `security`'s the once
      it's made. `openssl` writes and reads the encrypted file; only the
      plain text crosses a pipe, written or read whole, rather than
      through `hs.task`, whose pipes can drop the end of a large
      history.
    - **No prompts:** the login keychain unlocks at login, and the item
      trusts `security`, which made it. A keychain set to lock after
      sleep or idle asks for your password the first time after.
    - **What it protects:** the history in a backup, a copied or synced
      file, another account, a stray `cat` or upload, or an agent
      reading files. Not from a program running as you, which can ask
      `security` for the key too.
    - **Where:** `~/Library/Caches/tide/clipboard-history`, mode 600
      in a 700 folder, which Time Machine leaves out. It's written whole
      after each copy kept, each entry forgotten, a clear, and a smaller
      cap, by a rename over the last, so a crash leaves the old file or
      the new one.
    - **Reading it back:** at start, after the Clipboard settings, so a
      cap over 200 gets all of it, behind anything copied meanwhile, and
      nothing's written until it's read. A file that can't be read or
      decrypted is said once and left as it is until the history
      changes.
    - **Cost:** one `security` and one `openssl` run per save, a few tens
      of milliseconds that Hammerspoon waits for, and the same at start.
      No network.
- **Characters:** tide for Linux's list, `chars.tsv`, copied unchanged with its
  Unicode License v3 notice, and searched as tide for Linux does: each typed word
  must start a word of the name, so `e acute` finds é and É.
- **Keys:** `Tab` / `Shift+Tab` switch tabs; Return copies the row and
  closes, then brings back the app that was in front and sends it Cmd+V,
  which pastes in a terminal too, as tide for Linux pastes; Shift+Delete (forward delete)
  forgets a clipboard entry; Esc closes; `Super+V` again closes.
- **Cost and reliability:** nothing to pay and no network. The watcher
  polls the pasteboard's change count, Hammerspoon's
  `hs.pasteboard.watcher.interval`, half a second by default. The list is
  about 130 KB, read the first time the Characters tab shows.

- **Fill:** tide for Linux's Fill tab (tide for Linux §8.4), from `fill.lua`. Typing
  "address" or "github" finds a snippet or a login's field, and Return
  types it into the app that was in front.
  - **Snippets** are tide for Linux's `snippets.json` and `snippets.local.json` in
    `~/.config/tide`, each an object of name to text, the local file's
    name winning.
  - **Logins** come from `rbw`, the unofficial Bitwarden client, run
    through `~/scripts/runenv` for the login environment's PATH: `rbw
    list --fields id,name,user,folder,type` for the rows, one each for a
    login's username, password and 2FA code, and `rbw get --field` or
    `rbw code` for the value. Cards, notes and identities have no rows.
    An rbw before 1.15 refuses `type`, so the listing goes again without
    it, keeping every entry. Without rbw, just the snippets.
  - **Locked,** the tab is one row, Unlock Bitwarden, since rbw's pinentry
    can't take the keyboard while the chooser holds it. Return runs `rbw
    unlock` and opens the tab again.
  - **Typed, never pasted:** `hs.eventtap.keyStrokes` into the app, once
    it's in front again, so the value never reaches the pasteboard or the
    clipboard history.
  - The rows are listed afresh each time the tab shows, without blocking:
    the snippets at once, then the logins as rbw answers.

### 9.2 The dashboard launcher (switched off)

**tide for Chrome's dashboard page as the launcher,** in a borderless `hs.webview`
on the display you're on, in place of the switcher.

- **A panel, not the whole display:** 728 by up to 600 points, tide for Chrome's
  680-point launcher card and its padding, near tide for Linux's switcher's 560,
  centered across and a third of the way down (`launcherpage.frame`).
  tide for Chrome's bar along the page's top is hidden: tide's own bar already
  shows the workspaces, clocks and status icons, which sat elsewhere in
  tide for Chrome's (the owner's call). The page's body stays tide for Chrome's, as
  `make check-tideco` checks; only tide's style block hides the bar. The Switcher row under
Keyboard in tide for Linux's settings chooses it, at once, and this Mac keeps the
choice in `hs.settings`; until it's chosen there, `start({ launcher =
"dashboard" })` does. The default stays `"chooser"` (§9). A stored choice
that isn't one is left out, and the log says so.

- **Opened by the same keys,** each on its own scope, and by the bar's
  logo, which also closes it. tide for Chrome's scopes are Launch, Tabs, Workspaces
  and Actions:
  - Launch: the Mac's apps and System Settings' panes, as tide for Chrome's app
    rows, most recently used first; Tide Settings; tide for Chrome's Browser window
    (`Super+G`'s browser). Tide Settings' sections and tide's commands
    turn up for a query.
  - Tabs: every window, most recent first, and the browser tabs as they
    arrive. A window is found by its title or its app.
  - Workspaces: tide for Chrome's rows, from tide's bar. Typing a name no
    workspace has makes it, as the name prompt does.
  - Actions: the switcher's Actions tab (§9), in its order, then tide's
    commands.
  - The `Super+A` key opens it on Tabs, since tide for Chrome has no Attention
    scope.
- **A switcher key pressed while it's open** closes it on that key's
  scope, and otherwise moves there, as the switcher does. Esc, a choice,
  or clicking away closes it, and Esc gives focus back to the window you
  were in.
- **Esc is tide's while it's open,** an `hs.hotkey`, so it closes at
  once, however long WebKit takes to wake the hidden page: on CI's Mac the
  page has answered from 100 ms to 3.8 s after an open, and a key it hears
  waits as long. With something typed, tide hands Esc to the page
  (`tide.escape()`), which clears the search as its own Esc does. The
  page says `{ typed }` as the search goes from empty to not and back, so
  a key typed while the page is still waking may not have said so yet, and
  Esc then closes it.
- **tide for Chrome's files are copied unchanged:** `launcherview.js`, `launcher.js`
  and what they import (`apps.js`, `workspaces.js`, `platform.js`,
  `extras.js`, `unread.js`, `watchers.js`, `keepawake.js`), and
  `launcher.html`'s markup in `dashboard/launcherpage.html`. `make
  check-tideco` compares them with tide for Chrome's.
- **Stand-ins answer the page's Chrome calls** (`dashboard/launcher-chrome.js`),
  fed by the switcher's own rows (`launcher.lua`'s items), and send what
  you chose back to tide, which runs it as the switcher would.
  Two of tide for Chrome's lists are chromeOS's, so tide's take their place
  (`launcher-lists.js`): Actions' rows and the settings sections, which are
  Tide Settings' (`SETTINGS_SECTIONS`). Its settings are tide for Linux's clocks
  (`launcher-settings.js`).
- **Not yet, against the switcher:** `Cmd+Return`'s new workspace, `Cmd+M`'s
  mute, the Attention scope, a window's "minimized" and "muted", and app
  icons (TODO.md).
- **Opens at once:** its webview is made, hidden, as it's chosen or
  tide starts, and loads the page then. A key moves it to the display
  you're on, fills it and shows it. Closing hides it. Each open starts with
  an empty search, on its key's scope. Making a webview and loading the
  page on each key took most of the time before: in Chromium, loading took
  45 to 275 ms and filling with 300 rows 10 to 30 ms. CI's smoke test logs
  the times on a Mac.
- **Cost:** no money and no network. The page is built once at start;
  the hidden webview keeps a WebKit process running while it's chosen.

## 10. The rest of the desktop

- **Notifications:** Notification Center, with Focus for Do Not Disturb.
  Automatic Do Not Disturb while sharing the screen is a Focus option
  *(unverified)*. tide for Linux's Notifications page's Do not disturb schedule and
  *Critical alerts break through* are Focus's own here: a schedule on the
  Do Not Disturb Focus, and Time Sensitive notifications, in System
  Settings, so tide has no copy of either. Clicking a notification counts as Activate, so its
  window's workspace comes along (§6.1).
- **Idle and lock** (tide for Linux §10):
  - System Settings sets the display sleep and when a password is required.
    The checklist asks for the password at once after the screen locks.
  - Sleep on battery only: "Prevent automatic sleeping when the display is
    off" on power adapter *(unverified wording on macOS 26)*. `pmset`
    sets the rest, with an admin (§11.2).
  - tide's keep-awake toggle holds a power assertion, as `caffeinate`
    does. As on tide for Linux, it never times out, starts off at each login, and
    turns on by itself while the microphone is in use (Core Audio reports
    that) *(unverified)*. That last part isn't built yet.
  - `Super+S` toggles it, as the bar's item does, with an on-screen sign:
    "Keeping awake" or "Not keeping awake".
- **Presenter mode** (tide for Linux §10): Do Not Disturb and keep awake together,
  for a talk, a demo, or a meeting room's screen.
  - **On:** `Super+P`, or the launcher's Presenter mode. Keep awake goes
    on, Do Not Disturb goes on, and the bar's keep-awake item reads
    "Presenting" (§8). A sign says "Presenting".
  - **Off:** `Super+P` again, the launcher, or a click on the bar's item.
    Keep awake goes back to what it was before. Do Not Disturb goes off:
    tide can't read a Focus, so it can't know it was on before. That's
    where tide differs from tide for Linux, which puts both back.
  - **Either one alone while presenting** ends presenter mode. `Super+S`
    or the bar's item turns keep awake off and leaves Do Not Disturb on;
    the launcher's Do Not Disturb turns it off and leaves keep awake on.
  - **It lasts until tide reloads,** which starts it off, as tide for Linux's
    starts off in a new shell. Keep awake itself is Hammerspoon's
    assertion and may outlive a reload.
- **Do Not Disturb has no public API.** It's a Focus, and macOS has no
  public call to set or read one, and Hammerspoon has no `hs.focus`
  (§8). The supported route is Shortcuts:
  - Shortcuts' **Set Focus** action turns a Focus on or off, and
    `/usr/bin/shortcuts run NAME` runs a shortcut from a script. Both came
    with Shortcuts on the Mac, in macOS 12 Monterey. `shortcuts` exits 0 on
    success and 1 on an error, and `shortcuts list` prints one name a line
    (Apple's Shortcuts User Guide, "Run shortcuts from the command line").
  - tide can't make a shortcut itself, so you make them, once: **"Do Not Disturb On"** (Set Focus: Do Not Disturb, on
    until turned off) and **"Do Not Disturb Off"** (Set Focus: Do Not
    Disturb, off). The launcher's Do Not Disturb toggle uses a third,
    **"Toggle Do Not Disturb"**. *(The action's wording on macOS 26 is
    unverified.)*
  - **Missing ones are never silent.** At load tide runs `shortcuts
    list`, and `tide doctor` names any that are missing. The first key
    or launcher action that needs one says in a notification what to make.
    A shortcut that's there but fails says so too, with what it printed.
  - **One at a time.** The shortcuts run one after another, in the order
    asked, and only the latest waiting request runs, so a quick second
    `Super+P` can't race the first and leave Do Not Disturb wrong. Each
    task is held until it exits, so Hammerspoon can't collect it part way.
  - Keep awake works without any of them.
  - Rejected: reading `~/Library/DoNotDisturb/DB/Assertions.json`, which
    is undocumented, changes between releases, and needs Full Disk Access;
    and `defaults write com.apple.ncprefs`, which is reported to have
    stopped working with Focus in macOS 12 *(unverified)*.
  - Chrome can hold the screen awake on its own. `pmset -g assertions`
    shows who's holding it (tide for Linux §17) *(unverified that it happens on a
    Mac)*.
- **Theme** (tide for Linux §15):
  - **Built: light or dark on tide for Linux's schedule** (`theme.lua`,
    `theme_hs.lua`), once tide for Linux's `appearance.json` or
    `appearance.local.json` sets a `mode`. With none, macOS's own
    appearance stays, Auto and all, so nothing changes for a Mac that
    hasn't chosen.
    - tide for Linux's own appearance module works out which, and until when: By the
      clock (07:00 and 19:00 unless set), Sunrise and sunset at the
      latitude and longitude set, Always light or Always dark. It runs in
      JavaScriptCore (`hs.osascript.javascript`), with the clocks, steps
      and palette modules it imports, so the Mac changes when tide for Linux does.
    - tide sets it through System Events (`set dark mode`), as it
      starts, at each change, on a wake, as the files change, and within
      the hour regardless. The first time, macOS asks to let Hammerspoon
      control System Events; refused, the log says why.
    - A switch by hand, in Control Center or the settings window's Light
      now or Dark now, holds until the next change, or until the settings
      change, as tide for Linux's flip does. tide's own changes aren't taken for
      one.
    - macOS's Auto can't be turned on from here: no AppleScript sets it,
      and System Settings ignores its `defaults` key. Sunrise and sunset is
      tide for Linux's instead.
    - **Cost and reliability:** nothing to install. A short JavaScript run
      at each look. *(Unverified on a Mac: that System Events' dark mode
      turns macOS's Auto off rather than fighting it, and how long the
      Automation prompt holds tide up the first time.)*
  - The settings window's Appearance page has tide for Linux's rows (tide for Linux §16):
    light or dark now and until when, with its switch; the mode, ‹ and ›
    through macOS's own and then tide for Linux's four; By the clock's times, − and
    + a quarter hour; and the latitude and longitude, typed and set with
    Enter. A change goes to `appearance.local.json`; macOS's own takes the
    mode out of it, and can't be chosen while the shared file sets one.
  - macOS's dynamic wallpapers already change with the appearance, and
    kitty can follow it with its automatic themes *(unverified version)*.
  - **Built: tide for Linux's wallpapers, light and dark, are the desktop picture.**
    - **The settings:** tide for Linux's own, `lightWallpaper` and `darkWallpaper` in
      tide for Linux's `appearance.json`, and in `appearance.local.json` over it. The
      settings window's Appearance page reads and changes them with tide for Linux's
      appearance module, copied unchanged (`dashboard/tide-appearance.js`;
      `make check-tide`), and saves a change to `appearance.local.json`.
    - **The picture:** tide sets it on every display for the mode macOS
      is in, placed as that mode's position says. It sets it again as the
      mode changes (`AppleInterfaceThemeChangedNotification`), as a display
      comes, and as the files change. A display showing it already, placed
      so, is left alone.
    - **Its position:** tide for Linux's, `lightWallpaperPosition` and
      `darkWallpaperPosition`, else `wallpaperPosition` for both, else
      `fill` (tide for Linux §15). macOS places a desktop picture with NSWorkspace's
      options, which `hs.screen:desktopImageURL` doesn't pass, so tide
      sets it through JXA's ObjC bridge (`hs.osascript.javascript`;
      `wallpaper.desktop_script`):
      - `fill` is Fill Screen: scaled to cover, the rest cropped
        (proportionally up or down, clipping allowed);
      - `fit` is Fit to Screen: all of it, with macOS's fill color beside
        it, not tide for Linux's bar color;
      - `stretch` is Stretch to Fill Screen (axes independently);
      - `fill-top` and `fill-bottom` are drawn as `fill`: macOS centers what
        it crops, and keeps no edge.
      - A display macOS won't set is logged with its reason. CI's
        Hammerspoon sets the picture stretched, then filled, and reads each
        back from macOS.
    - **The Appearance page** has tide for Linux's position row under each picture's
      wallpaper, Light wallpaper position and Dark wallpaper position, ‹ and
      › stepping through Fill, centered; Fill, keep top; Fill, keep bottom;
      Fit whole picture; and Stretch to fill, into `appearance.local.json`.
      A color has none.
    - **With none set** for the mode, or no such file, macOS's own picture
      stays, and System Settings' Wallpaper pane sets it. A missing file is
      logged. Taking a setting out leaves the last picture tide set.
    - **A color** (`#rrggbb` or `#rgb`), which tide for Linux shows as a solid
      wallpaper, is shown here too. macOS's desktop takes only a picture, so
      tide draws the color into a small square once (`hs.canvas`), kept in
      `~/Library/Application Support/tide`, and sets it filled, so it covers
      each display. The Appearance page takes one typed, as tide for Linux's does,
      or chosen from its swatch, as tide for Linux's: the color set, or a palette
      icon for a picture or none, opening tide for Linux's eight colors
      (`WALLPAPER_COLORS`) under the row, the one set marked, and a field
      for any `#rrggbb`. Choosing one sets it and closes them; Escape, or a
      click anywhere else, closes them with nothing set.
      *(Unverified on a Mac: that the stretched square shows as an even
      color on every display.)*
    - **Choosing one:** each wallpaper's field has a choose button, which
      opens macOS's own file dialog (`hs.dialog.chooseFileOrFolder`),
      offering images, where the wallpaper is now, or in Pictures. The file
      chosen is set as a typed path is: from `~/` when it's in your home
      folder, so it reads the same on Linux, where tide for Linux shows it. A cancel
      changes nothing.
    - The dialog is modal, so tide waits on it, as Hammerspoon's
      dialogs do: windows that open meanwhile are tiled once it closes.
    - **Cost and reliability:** nothing to install or pay for; one
      notification watcher, and a desktop picture set only when it
      changes.
- **Screenshots** (tide for Linux §13): macOS's own, with tide for Linux's Print keys mapped to
  them (§7.2). tide presses macOS's screenshot keys rather than running
  `screencapture`, because a capture an app starts needs Screen Recording
  for that app, while macOS's own keys need nothing (§11.1):
  - screen: Cmd+Shift+3; region: Cmd+Shift+4; window: the same, then
    Space;
  - those save the shot to the folder in Screenshot's options, and tide
    puts each new one there on the clipboard too, so a shot is both, as on
    tide for Linux (`shots.lua`). It watches the folder and copies each new image
    macOS tagged as a screen capture (Spotlight's `kMDItemIsScreenCapture`
    extended attribute), whatever its name, which macOS translates and
    Screenshot's options can change. So one taken with macOS's keys
    directly is copied as well. Files already in the folder when tide
    starts stay off the clipboard when they're edited. When Screenshot's
    options move the folder, tide watches the new one, as CI's smoke test
    checks. The Ctrl variants would put a shot on the clipboard alone.
  - `setup-macos` sets that folder to `~/Pictures/Screenshots`, tide for Linux's, and
    turns off the floating thumbnail, which holds a shot back from the
    folder until it goes. Without that, shots go to the Desktop, and
    Hammerspoon asks once for access to it.
  - Pressing the keys is a synthetic key event, which Accessibility already
    covers. CI's smoke test shows macOS takes the shot from it, on macOS 15.
- **Mouse** (conf `hyprland.lua`, tide for Linux §16):
  - Speed at the fastest, with acceleration left on: tide for Linux found a flat
    curve felt wrong. `com.apple.mouse.scaling` goes beyond the slider
    (§2.6).
  - Left-handed: the primary button on the right, in Mouse settings.
  - macOS can't say how far a wheel notch scrolls: its slider changes
    only the acceleration, so a slow notch moves a line or so. It's the
    gap that tide for Chrome §19.2 fills on chromeOS. `setup-macos` installs
    LinearMouse (free, open source, Accessibility) and gives every mouse
    nine lines a notch, and a pointer acceleration of 1.5 at speed 0.35
    (scripts `docs/MACOS.md`), which the Mouse section changes (§15).
  - **Built: tide for Linux's Scroll speed and Natural scrolling, through
    LinearMouse.** They're tide for Linux's Mouse settings, `mouse.scrollSpeed` and
    `mouse.naturalScroll` in `input.json` and `input.local.json` (tide for Linux
    §16), read with tide for Linux's own `input.mjs`, copied unchanged as
    `dashboard/tide-input.js`, so one setting serves both desktops. What
    isn't set is what tide for Linux's page shows: 3× and off.
    - tide writes them into LinearMouse's config, which LinearMouse
      reloads when it changes (its `FileWatcher`). That's
      `~/Library/Application Support/linearmouse/linearmouse.json` if it
      exists, else `~/.config/linearmouse/linearmouse.json`, as LinearMouse
      reads them (its `ConfigurationState.swift`); through a symlink if
      it's one.
    - One scheme for every mouse (`"if": {"device": {"category":
      "mouse"}}`), kept last: LinearMouse merges schemes in order, and a
      later one wins, so tide for Linux's values win over a device's own. When the
      last scheme is one for every mouse, it's edited in place; otherwise
      a new one is added last that sets only those. Only the vertical
      `distance` and `reverse` change, and every other scheme keeps its
      place, so a device's own pointer speed or horizontal scrolling
      still wins over every mouse's. The edit is JavaScript
      (`dashboard/linearmouse.js`) in JavaScriptCore, as Karabiner's is
      (§15).
    - Three lines a notch at 1×, so tide for Linux's 3× is nine, rounded to whole
      lines, one at least. setup-macos's ten becomes nine the first time
      tide runs.
    - macOS has one natural-scrolling switch,
      `com.apple.swipescrolldirection`, on while it's unset, read with
      `defaults` each time (`hs.mouse.scrollDirection()` takes unset as
      off). LinearMouse reverses every mouse when tide for Linux's
      `naturalScroll` differs from it, so the mouse scrolls as tide for Linux says,
      and the trackpad as macOS's switch says.
    - **When:** as tide starts (each login); when tide for Linux's folder changes;
      a second after the last USB device plugged in (`hs.usb.watcher`),
      since a KVM switching back brings several; and a second after a
      wake or an unlock (`hs.caffeinate.watcher`). Each of those starts
      LinearMouse in the background (`open -g`, no window) if it's
      installed and not running; a folder change does only when the Mouse
      settings changed. The 30 s check (below) puts back a change made in
      LinearMouse's own window, but never starts it: it says LinearMouse
      quit, so quitting it on purpose lasts until the next event.
    - The file is written only when it would change, compared as JSON,
      so LinearMouse's own spacing doesn't count, and the JavaScript runs
      only when a file or the switch changed. LinearMouse shows a
      "Configuration Reloaded" notification of its own at each write.
    - A config that isn't JSON (LinearMouse also reads one with comments)
      or whose `schemes` isn't a list is left alone. That, a save that
      fails, and an `input.json` that's wrong (by tide for Linux's checks: the last
      good settings stay) are each a notification once, and the Mouse
      section and `tide doctor` say so.
    - Without LinearMouse installed, nothing is written.
    - **Cost and reliability:** nothing to pay. One `defaults` run every
      30 s and at each event, off the main thread.
  - tide checks LinearMouse is installed and running, as it starts,
    every 30 s after, and after a plug or a wake, as it does for Karabiner (§7.1), and says so when
    it isn't (§1, §15). LinearMouse's bundle ID is `com.lujjjh.LinearMouse`
    (Homebrew's cask). LinearMouse asks for Accessibility itself, with its
    own window, as it starts; tide can't see another app's permissions.
  - The Mouse section's buttons open Mouse settings and LinearMouse's
    window (§15).
- **Trackpad:** natural scroll and tap to click, in Trackpad settings.
  macOS ties natural scrolling for the mouse and trackpad together, in
  one switch; LinearMouse reverses the mouse alone (Mouse, above).
- **Keyboard:** repeat after 600 ms at 25 a second, set as `InitialKeyRepeat`
  and `KeyRepeat` in 15 ms steps, so the nearest is 40 and 3
  *(unverified units)*. US Dvorak is a native input source.
- **Caps Lock as Compose,** as on Linux (`compose.lua`): Caps Lock, then
  ' and e, types é.
  - macOS has no Compose key, so `setup-macos` makes Caps Lock send F18
    in the same `hidutil` mapping as the modifiers, and tide binds F18.
    It's F18, not F19, since Karabiner sends `Super+Backspace` as
    `Super+F19` (§7.2).
  - The keys after it are held back from the app in front, by an event
    tap, and read as the characters they'd type, so Shift and the layout,
    Dvorak included, count as they do on Linux.
  - The sequences are Linux's own: libX11's en_US.UTF-8 Compose table,
    the one Linux's Compose key reads, as `compose.tsv` (1,199 of them,
    written by `ci/compose_table.lua`). Only those typed with ASCII keys
    are kept, since a Mac can't send the dead keys.
  - A sequence it doesn't know types nothing and ends, as on Linux. Esc,
    a click, or a key with Command or Control ends it too.
  - The character is typed with `hs.eventtap.keyStrokes`, so it works in
    every app, kitty included.
  - It doesn't work during Secure Input, such as in a password field, when
    event taps don't see typed keys (§13). `compose = false` in start()
    turns it off.
- **Setup checklist:** as tide for Chrome's (tide for Chrome §3.4). Each item links to its System
  Settings pane with an `x-apple.systempreferences:` URL *(unverified per
  pane on macOS 26)*. It covers the Mission Control settings (§6.6), the
  minimize settings (§6), the password at once (Idle, above), Chrome's
  notifications (§5.1), and each permission (§11). **Built,** as the
  settings window's last section (§15).
- **The rest of the setup:** tide for Chrome's Appendix A lists the helper scripts
  `setup` installs (Bluetooth, the audio profile switcher, notes, IRC,
  remote desktop, the file manager on `Super+E`). Which of them run on a
  Mac, and what stands in for the rest, is for `setup-macos` to settle,
  not tide.

## 11. Permissions, admin rights and managed Macs

### 11.1 What each permission buys

| Permission | Asked when | Buys |
|---|---|---|
| Accessibility | first run; tiling needs it | moving windows, focus follows mouse, mouse drags (§5.3), notification banners |
| Input Monitoring | only for the lone Super tap, if done by an event tap (§7) *(unverified that Accessibility alone isn't enough)* | seeing Option go down and up |
| Screen Recording | never: titles come through Accessibility (§2.5), screenshots use macOS's own keys (§10), and the overview shows app icons, not thumbnails (§6.9) | nothing tide needs |
| Automation, per browser | the first time the switcher's Windows tab lists tabs (§9) | tab titles and addresses |
| Automation, for System Events | the first time tide for Linux's light and dark schedule switches the Mac (§10) | setting macOS's appearance |
| Location Services | when you press its Setup checklist button, the first time: tide looks for where the Mac is for a minute, so macOS asks and lists Hammerspoon in Privacy & Security *(unverified)*; after that the button opens the list | the Wi-Fi network's name, on the bar and the Network page (§8, §15) |
| none | — | global keys, the bar, clocks, the switcher's apps, workspaces and windows |

Ask for each only when a feature needs it, as tide for Chrome does with its extras
(tide for Chrome §14.1).

### 11.2 Admin rights

A standard user can run tide once it's installed. These steps need an
administrator:

| Step | Needs admin? | Workaround without admin |
|---|---|---|
| Installing Homebrew | **yes**, once, to create `/opt/homebrew` | Install apps from a downloaded copy into `~/Applications` instead *(unverified for Hammerspoon)*. |
| Installing an app into `/Applications` | **yes**, usually | `~/Applications`. |
| Turning on a privacy permission (§11.1) | **yes**, an admin's password unlocks the setting *(unverified on macOS 26 for standard users)* | A managed Mac's MDM can grant it instead (§11.3). |
| Karabiner's keyboard driver | **yes**: it's a system extension, approved once | Skip Karabiner. tide then binds Option directly, which takes Option's text gestures (§7.1), and the lone Super tap needs an event tap. |
| `pmset` for the idle timeline (§10) | **yes**, `sudo` | Energy and Lock Screen settings, which a user can change. |
| Everything else `setup-macos` writes: symbolichotkeys, Dock and minimize settings, mouse scaling, appearance | no: per-user `defaults` | — |

### 11.3 On a managed work Mac

A Mac enrolled in MDM can grant or block most of this, so on a work machine
it's IT's call. tide for Chrome has the same section for chromeOS (tide for Chrome §14.4).

| Feature | What MDM can do | If it's blocked |
|---|---|---|
| Accessibility, so all of tiling | grant it to a named app with a Privacy Preferences (PPPC) profile, or block it | **No workaround**: no tiling, no focus follows mouse, no mouse drags. Global keys and the launcher still work. |
| Input Monitoring and Screen Recording | only let a standard user approve them, or block them; a profile can't switch them on silently *(unverified for Input Monitoring)* | Super+Space for the switcher (§7), or Karabiner's tap rule. tide shouldn't need Screen Recording (§2.5). |
| Automation for browser tabs | grant it per app pair in the same profile, or block it | No tabs in the Windows tab. Apps, workspaces, windows and commands still work. |
| Karabiner's system extension | allow or block it by team ID, and the rotation needs it too | Skip Karabiner (§11.2). |
| Running tide or Hammerspoon at all | block apps by name or signature, with Gatekeeper rules or a tool such as Santa | **No workaround.** Ask IT to allow it. A Developer ID build (§12) is easier for IT to allow than an unsigned one. |
| Login items | manage background items, and hide or block them | Start tide by hand. |
| Idle and lock timings | enforce the screen lock delay and password rules | **None.** The policy wins, and tide's keep-awake toggle may not stop the lock *(unverified)*. |
| Spaces, Dock and Mission Control settings | lock some of these preferences | Leave the defaults; parking, and minimizing, still work (§6). |

Nothing in tide needs SIP lowered, which a managed Mac wouldn't allow. That
was a goal (§1), and it's why the native-Spaces alternative avoids yabai's
scripting addition (§6).

## 12. Distribution, cost and reliability

- **Not the Mac App Store:** controlling other apps' windows isn't allowed
  in the sandbox (§2.1).
- **Hammerspoon (B):** free and open source. tide would be a config
  repository plus a `setup-macos` step, with no signing.
- **A native app (C):** needs a Developer ID and notarization, at $99 a year
  for the Apple Developer Program, or users clear Gatekeeper by hand.
  Homebrew can ship it as a cask.
- **Failure modes:**
  - A macOS update can break private calls (§2.3) or reset permissions.
  - An app that hangs stalls a retile (§2.1).
  - None of this touches the network, so there's nothing to go down and no
    running cost.
  - Do Not Disturb runs `/usr/bin/shortcuts`, part of macOS, free. Each
    run is a process start and an Apple Event to Shortcuts, typically well
    under a second *(unverified)*; it's off the key's path, so the key
    and keep awake don't wait for it (§10).

## 13. What tide can't have

These are the things macOS doesn't allow, or allows only through private
calls that break between releases or need SIP lowered, which §1 rules out.
Each one names a workaround, or says there is none.

| tide for Linux or tide for Chrome has | Why a Mac can't | Workaround |
|---|---|---|
| No title bars or borders | No public API removes another app's frame (§2.1). | **None** for the title bars. Gaps of 0 keep the tiles tight. |
| Focus without raising (KDE's focus follows mouse) | Focusing a window brings it to the front (§5.2). | yabai's `autofocus` does it through a private call, with SIP on *(unverified)*. Otherwise, raise, and keep floats above tiles (§5.1). |
| Floats always on top | No public way to set another app's window level (§5.1), and raising another app's window doesn't put it back over the app just focused (seen on a Mac, 2026-11-01). | Hammerspoon's own floats get a floating window level. Focus follows mouse leaves a tile with another app's float in front of it alone. A true window level for other apps needs yabai's scripting addition, which needs SIP lowered: **none** within §1. |
| Nothing ever steals focus (tide for Linux §14) | An app can activate itself, and macOS decides whether it may. | tide never focuses anything unasked, and hands focus back when an app takes it without a grant (§14.1) *(unverified that it can act in time)*. |
| Dimming exactly the inactive windows | tide can't draw inside or between other apps' windows (§2.4). | One dark layer over the windows with a hole for the focused one, which dims the desktop too (§5.6). |
| Instant workspace switches with an honest Cmd+Tab and Mission Control | Hiding windows off screen leaves them in Cmd+Tab and Mission Control; minimizing and Spaces animate (§2.3, §6). | Park, and bring the workspace along when Cmd+Tab picks a parked window; turn Mission Control off and use tide's overview on its keys (§6.9); or minimize with the Scale effect (`hide = "minimize"`). **No** way to get all three at once. |
| One workspace pool shared by every monitor (tide for Linux §6.5) | Parked and minimized windows have no display of their own, and native Spaces are per display. | tide tracks each workspace's display itself, as tide for Chrome does (tide for Chrome §6.1). |
| Moving a window to a native Space | Only private calls can (§2.3). | Workspaces by parking windows off screen, or minimizing (§6). |
| Exact tiles for every app | Apps can refuse or round a size, such as terminals snapping to their character grid (§2.1). | The rest tile around what the app took (§5). In kitty, the grid snapping can be turned off *(unverified)*. |
| Tiling native full-screen windows | A full-screen window lives in its own Space. | Maximize instead (§4). |
| Own bar replacing the menu bar | The menu bar is the system's (§8). | Hide the menu bar automatically and put a bar over it, or use SketchyBar. |
| Every window's attention request (tide for Linux §14.4) | There's no public signal for "this window wants attention" *(unverified)*. | Notifications, bells and self-activation (§14.2). **None** for an app that does none of those. |
| Own lock screen and login, with the hostname | The lock and login screens are the system's. | Lock Screen's "Show message when locked" can carry the hostname *(unverified on macOS 26)*. **None** for a custom lock screen. |
| tide for Linux's idle timeline (dim, lock, off, suspend) | macOS sets its own timings (§10). | Energy and Lock Screen settings come close. `pmset` sets more, with admin rights (§11). |
| Sharing a 16:9 slice of an ultrawide in Meet (tide for Linux §12) | Meet shares a screen, a window or a tab. | Share a window, or a virtual display from a tool such as BetterDisplay *(unverified)*. |
| Mouse wheel speed beyond the slider | Mouse settings change only the wheel's acceleration (§10). | LinearMouse, which `setup-macos` installs, tide checks is running, and tide sets from tide for Linux's Scroll speed (§10). |
| Keys and the Super tap during Secure Input | While a password field or a terminal's secure keyboard entry is active, event taps stop seeing typed keys *(unverified for hotkeys)*. | **None**, by design. Registered hotkeys keep working, if they do. |
| Pinning picture-in-picture to a corner (tide for Linux §6.4) | The app places it, and moves it back. | Leave it where the app puts it (§5.5). |
| Option's text gestures alongside Super on Option | One key can't be both. | Karabiner's mapping (§7.1). Without it, **none**: tide takes them. |
| Natural scrolling on the trackpad but not the mouse | macOS has one switch for both. | LinearMouse reverses the mouse alone, set from tide for Linux's Natural scrolling (§10). |
| Mac App Store distribution | The sandbox forbids controlling other apps (§2.1). | **None.** Ship through Homebrew, or as a Hammerspoon config (§12). |

## 14. Focus and attention

**Nothing takes the keyboard unless you asked for it,** as on tide for Linux
(tide for Linux §14). A window that wants attention is marked, never focused, and
`Super+A` lists it, to go there.

### 14.1 Who gets focus

| When | Gets focus? |
|---|---|
| tide's switcher, name prompt, dashboard or resize mode is open | It keeps it until it closes. Focus follows mouse pauses meanwhile (§5.2). |
| A new window from the app you're in: a dialog, a second window | **Yes**, as tide for Linux (tide for Linux §14.1). |
| The first window of an app you launched from tide (the switcher, an app key) | **Yes**, if you haven't typed, clicked or moved focus with a key since. The grant lasts 5 s and is used once. |
| What a click starts: a Dock icon, a link, a notification, a menu item | **Yes**, within 5 s, once, if you haven't typed or clicked since: an app's first window, or for a menu item, any window, since About This Mac is a window of System Settings, which may be open already. Focus follows mouse passing over a tile meanwhile doesn't end it. Whether a menu is open is read at each click (`hs.window.list(true)`, a few milliseconds). |
| A window started from the focused terminal (`open .` in kitty) | **Yes**, on the same terms *(how tide learns of it unsettled; tide for Linux's shell tells its guard, tide for Linux §14.3)*. |
| A notification you click | **Yes**: the click was yours (§10). |
| A password prompt | **Yes** when it follows something you did in the app that asks; otherwise it's macOS's to decide. |
| Any other app activating itself, or a window opening in the background | **No.** It's marked for attention. |

- **How tide enforces "no":** macOS lets an app activate itself, so tide
  can't refuse it. It can notice (`NSWorkspace`'s activation
  notification), and hand focus straight back to the window you were in
  when no grant covers it *(unverified that it can act before a keystroke
  lands)*. If that window is a tile with another app's float in front of
  it, the last used window on its workspace that isn't goes instead
  (§5.1). macOS 14 added cooperative activation, which already stops many
  apps taking focus unasked *(unverified how many apps it covers)*.
- **Pulled back to another workspace** (tide for Linux §14.2): an app launched on
  "work" whose window appears after you've moved to "home" opens on "work",
  marked for attention, not on "home" (§6.1).
- **A window opening on "in"** that isn't one of its apps waits for the name
  prompt (§6.2). The prompt has the keyboard; once you answer, the window
  is focused on its workspace, which counts as asked for.

### 14.2 Attention

- **What counts as wanting attention,** as on tide for Linux (tide for Linux §14.4):
  - a notification, as Notification Center's banner shows it;
  - a bell in kitty;
  - a window that activated itself without a grant (§14.1).
- **What doesn't:** an unread count. A Dock badge or a title such as
  `(3) Inbox` rises with every message, wanted or not, so it marked
  windows all day. tide used to read both every two seconds.
- **A notification marks its app.** tide watches Notification Center
  (`com.apple.notificationcenterui`) through Accessibility, for its window
  and the banners in it appearing *(unverified on macOS 26: which of
  `AXWindowCreated`, `AXCreated` and `AXLayoutChanged` fire)*.
  - A banner's subrole starts with `AXNotificationCenter`. Its
    `AXStackingIdentifier` names the app's bundle ID, else its
    `AXDescription`, "App, title, body", names the app *(unverified on
    macOS 26)*.
  - A browser's body leads with its site, `mail.google.com`, so a
    browser's mark goes to its window whose front tab is on that site, as
    the switcher last saw it (§9), else to its last-used window, and
    muting the site (below) silences it.
  - A notification from the app you're in, or the site in front, isn't
    marked.
  - A banner a Focus hides never shows, so it marks nothing. Nor does one
    from an app with banners off in System Settings.
- **A bell marks its window.** kitty's bell only bounces its Dock icon on
  a Mac, which tide can't see. So conf's kitty runs `tide-bell` on a
  bell, which asks kitty which window rang and opens
  `hammerspoon://tide-bell?window=<id>`. That marks the window, unless
  it's the one you're in. Any program of yours can open the URL, and all
  it does is mark a window.
- **The `!` and icons need no polling.** Every two seconds tide still
  reads titles, for matching windows after a restart, and clears the
  focused window's marks.
- **A mark clears** when you focus the window or app, as on tide for Linux
  (tide for Linux §14.4). A browser notification's mark clears only on a window whose
  front tab is on its site, so reading Chat doesn't clear Mail's.
- **Where it shows:** the app icon of each marked window on its
  workspace's chip in the bar, which a click focuses (§8); the chip's
  attention color; the `!` on the menu bar item's name; and `Super+A`'s
  list.
- **The list covers every workspace,** most recent first. With nothing
  waiting, it says so.
- **Mute** (`muted`, §15): an app such as Google Chat that flags all day
  can be muted, so it never counts as wanting attention. Empty by default.
  - **It's a backstop.** The usual fix is the app's own notification
    settings, or macOS's for it; Mute is for an app that keeps flagging
    once those are set.
  - **Each entry** is an app's bundle id (`com.google.Chrome.app.…` for an
    installed web app, which has its own), or `site:<host>` for a site in
    a browser tab (`site:chat.google.com`).
  - **An app matches** a mark for its window, or its notification.
  - **A site matches** a browser's notification from the host, and a
    browser window's mark when that window's front tab is on the host, as tide last saw it: the switcher's tab list
    (§9) reads which tab is in front, and that's remembered per window
    until the next time the switcher opens. A host matches exactly,
    ignoring case: `site:chat.google.com` isn't `mail.google.com`.
  - **A muted app or site gets no mark:** no icon or attention color on
    its workspace's chip (§8), no `!` on the menu bar item, no row in the
    Attention tab, and `Super+A` passes over it. Muting clears the marks
    it now covers.
  - **Its windows are otherwise normal,** and the focus guard (§14.1)
    still hands focus back from one that takes it unasked, just without
    marking it.
  - **Notifications: less than on tide.** On tide for Linux, Mute also keeps the
    app's notification popups from showing, though they still go into the
    notification center's history. tide can't stop macOS's own banners:
    they're Notification Center's, with no public way for another app to
    hold them back. So on a Mac, Mute stops only the marks, and says so
    when you mute: the notice offers to open System Settings › Notifications
    (`x-apple.systempreferences:com.apple.Notifications-Settings.extension`
    *(unverified on macOS 26, and it opens the list, not the app's own
    page)*), where the app's banners can be turned off.
- **Muting takes one key:** in the switcher's Windows and Attention tabs,
  `Cmd+M` (physical Ctrl+M under `setup-macos`'s rotation, as tide for Linux's
  `Ctrl+M`) on the selected row, or a right-click on any row, mutes that
  row's app, or a tab's site. The same on a muted row unmutes it.
  - `Cmd+M` is bound only while the switcher is open, so there it never
    reaches macOS's minimize, and everywhere else it's left alone.
  - A window's row and an Attention row mute the window's app; a tab's
    row mutes its site.
  - Muted rows say "muted" in their second line.
  - A short notice says what was muted or unmuted, and after a mute
    offers the Notifications settings (above).
  - `hs.chooser` has no buttons on a row, so the right-click stands in for
    a hover button *(a guess, to confirm)*.
- **What changed:** `Super+Tab` used to step through the waiting windows,
  and `Super+Home` with it. `Super+Tab` now flips between "in" and the
  last workspace, and `Super+Home` goes to "in" (§7.2). `Super+A`'s list takes over from both,
  so the step-while-held round, and its event tap for Super let go, go
  with them.

## 15. Settings and `tide doctor`

- **A new copy reloads tide.** `make install`, and so `setup`, copies
  tide into `~/.hammerspoon/tide`, which Hammerspoon runs. tide
  watches the folder it runs from (`hs.pathwatcher`), and a second after
  the last of a copy's files lands, it reloads Hammerspoon
  (`selfreload.lua`), so an update takes effect without a reload by hand.
  A hidden file, such as Finder's `.DS_Store`, changes nothing. Nothing
  else writes there: tide's own files are in `~/.config/tide` and
  `~/Library/Caches/tide`.

- **`start()`'s `launcher`** picks the launcher: `"chooser"`, the
  `hs.chooser` switcher, by default, or `"dashboard"`, tide for Chrome's dashboard
  page (§9.2). Anything else is an error at load, naming the setting.
- **One set of files with tide.** tide reads tide for Linux's settings from
  `~/.config/tide/` (tide for Linux §16.1): the clocks list, the layouts, and the dim
  strength. One file serves every desktop. A `.local` file beside each
  overrides it for one machine.
- **The layouts are tide for Linux's setting,** `layouts.json` and
  `layouts.local.json` (tide for Linux §16), read as tide starts, before the first
  workspace is made, and again whenever the folder changes.
  - They're laid over `start()`'s `layout`, or tide for Linux's defaults without one,
    so tide's own settings the files don't name (`cycle`, `mfact_step`)
    stay.
  - A change reaches every workspace, as on tide for Linux: each keeps its mode, and
    takes the new `mfact` and master count, losing any it was given with
    the keys. The displays are laid out again at once. Settings that
    haven't changed change nothing, so another file's change in the folder
    doesn't undo what the keys set.
  - A file that's wrong, by tide for Linux's checks, is an error at load, in a
    notification naming the file and why, and the last good settings stay.
  - **The workspace-name patterns** (§6.2) are tide for Linux's setting, in the same
    file tide for Linux reads them from *(its name to match tide for Linux's)*, so one list
    names workspaces on both desktops.
- **The muted apps and sites** (§14.2) are tide for Linux's setting, `muted` in
  `workspaces.json` and `workspaces.local.json`, so one list serves both
  desktops.
  - A list of strings, each a bundle id or `site:<host>`. Empty by
    default. A `.local` list replaces the shared one whole (tide for Linux §16.1).
  - **A malformed entry is an error at load,** in a notification and in
    `tide doctor`, naming the file and the entry, and the rest of the
    list still applies. Malformed: not a string, empty, with a space, or
    `site:` with no host or with more than a host (a scheme, a path, a
    port).
  - **A `muted` that isn't a list,** such as a JSON object, or a file that
    doesn't parse, is an error at load too, naming the file, and the last
    good list stays. So is a `namePatterns` that isn't a list (§6.2).
  - **tide writes only `workspaces.local.json`,** as tide for Linux's settings
    panel does: it reads the file just before each change, keeps every
    other key, and writes it whole, to a temporary file renamed over it.
    The first change copies the list in effect, since a local list
    replaces the shared one.
  - tide already watches the folder, so a hand edit takes effect at
    once.
- **Start at login** is tide for Linux's setting, `commands` in `startup.json` and
  `startup.local.json` (tide for Linux §16), so one list serves both desktops. It's
  empty by default.
  - tide runs the list once a login as it starts, in order (each
    command's check and start after the one before it's), each through
    `runenv`, as a helper key runs one (§7.2), so it gets the login
    shell's `PATH`. `google-calendar` and `google-chat` are `scripts`'
    helpers, which open Chrome's app windows on a Mac too.
  - Once a login: tide keeps the login it last ran in, as when this
    user's `loginwindow` started, in `hs.settings`. A reload in the same
    login runs nothing. A login that can't be told runs nothing either,
    and says why in the log, since Hammerspoon reloads often.
  - A command whose program a process of yours already runs, as `pgrep -x`
    matches its whole basename, isn't started again. macOS's pgrep matches
    the basename of a process's `argv[0]`, not the 15-byte name Linux's
    does (`pkill.c` in adv_cmds). A script runs with its interpreter as
    `argv[0]`, so one still running isn't caught. A pgrep that can't tell
    starts it, and says so in the log.
  - A command is words, with no shell: one with a quote, backslash, `$` or
    control character, a program ending in `/`, an empty one, or one listed twice is an error at
    load, in a notification naming the file and the entry, and the rest
    still run. A file that isn't a JSON object, or a `commands` that isn't
    a list, is an error too, and nothing runs until it's fixed.
  - A command that fails is a notification naming it, as a helper key's is.
  - macOS lets an app activate as it opens, so unlike tide for Linux, a command's
    window may take focus *(unverified on macOS 26)*. Its windows go where
    the home workspace's rules put them (§6.2).
  - **The settings window's Start at login section** edits the list, as
    tide for Linux's Start at login page does, with tide for Linux's own `startup.mjs`, copied
    unchanged as `dashboard/tide-startup.js`.
    - It shows the list in effect: `startup.local.json`'s, else
      `startup.json`'s. The first change copies it into
      `startup.local.json`, keeping that file's other keys, as the Clocks
      section does.
    - A command typed at the foot is added with Enter, at the end. The
      arrows move one, and ✕ takes it out.
    - A command with a quote, backslash, `$` or control character, or one
      listed already, is refused, and the section says why. A file that
      doesn't parse can't be changed here until it's fixed.
    - A change takes effect at the next login: the list already ran in
      this one (above).
- **The standing workspaces, home's apps and each workspace's own settings
  are tide for Linux's settings,** `standing`, `inApps` and `workspaceSettings` in
  `workspaces.json` and `workspaces.local.json` (tide for Linux §6.5, §16), so one
  file serves both desktops.
  - A `.local` file's replaces the shared one's whole (tide for Linux §16.1): the
    lists, and `workspaceSettings` too, so a Mac's is exactly what it says.
  - Where no file sets one, `start()`'s stands in: `workspaces`, a list of
    names, `{ "in", "re", "oc", "me" }` by default (§6.1), `home_apps`, a
    list of app names, tide's eight by default (§6.2), and
    `workspace_settings`, a table as tide for Linux's `workspaceSettings`, `{ ["in"]
    = { askForName = true, pinnedApps = { "Gmail" } } }`, unset by default:
    "in" asks and nothing is pinned (§6.2).
  - `workspaceSettings` is checked as tide for Linux checks it: a key that isn't a
    workspace's name, one named twice ignoring case, a field other than
    `askForName` and `pinnedApps`, an `askForName` that isn't `true` or
    `false`, or a `pinnedApps` that isn't a list of text, is an error at
    load, naming the file and the setting, and the last good settings
    stay. `start()`'s is checked the same way when tide starts, naming
    `workspace_settings`. A JSON decoder can't tell `[]` from `{}`, so an
    empty list passes as an empty `workspaceSettings` here, where tide for Linux
    would refuse it.
  - They're checked as tide for Linux checks them. An empty `standing`, a name in it
    twice (ignoring case), one with quotes, backslashes, `@` or control
    characters, space around it or over 32 characters, or an `inApps`
    entry that isn't text, is an error at load. It's a notification and a
    line in `tide doctor`, naming the file and the setting, and the last
    good lists stay. Each file is checked whole, as tide for Linux checks it, even
    where the other file's list is the one in effect.
  - A change applies at once, as tide for Linux's does. The first standing workspace
    is home from then on: made if it isn't yet, and first on the bar. The
    old home is an ordinary workspace, removed once it's empty and hidden.
    Windows stay where they are, since home's apps say where a window
    opens, not where it must stay.
  - **`inApps` names Mac apps as well as tide for Linux's entries.** tide matches a
    window's app name against each entry ignoring case, and with spaces,
    hyphens and underscores alike, so tide for Linux's `google-chat` is the Mac's
    Google Chat app too *(a guess, to confirm)*. tide for Linux's web addresses match
    nothing here (§6.2), and a Mac app's name with spaces is a window class
    on tide for Linux, which starts nothing there.
  - **The files' list starts at login,** as a list set in `start()` does
    (§6.2), but only the entries that are a Mac app. tide looks for each,
    as written and with hyphens as spaces, in `/Applications`,
    `/System/Applications`, `~/Applications` and Chrome's
    `~/Applications/Chrome Apps.localized`, and opens what it finds with
    `open -g -a`. An entry that finds none is tide for Linux's, so it's skipped, and
    the log says so, not a notification. One already running, by its
    bundle ID, isn't opened again.
  - **The settings window's Workspaces section** edits them, as tide for Linux's
    Workspaces page does, with tide for Linux's own `workspacepage.mjs`,
    `workspacenames.mjs`, `fuzzy.mjs` and `span.mjs`, copied unchanged as
    `dashboard/tide-workspacepage.js`, `tide-workspacenames.js`,
    `tide-fuzzy.js` and `tide-span.js` (`make check-tide`).
    - It lists `standing`, `inApps` and `namePatterns` (§6.2), as the
      files in effect have them, or `start()`'s or tide's defaults where
      they set none. The first standing workspace is marked home.
    - Below them, each standing workspace has a section of its own, home's
      marked: a "New windows ask for a workspace" switch, its
      `askForName`, and its pinned apps, each with a ✕, over a box that
      pins one with Enter. The first change copies the `workspaceSettings`
      in effect into `workspaces.local.json`, as a list's first change
      does: with none set, that's "in" asking, so turning on another
      workspace's switch leaves "in"'s on. It's tide for Linux's own
      `editedWorkspace`, `withAskForName`, `withPinned` and
      `withoutPinned`.
    - The standing workspaces and the patterns, whose order counts, have
      arrows that move one; each entry has a ✕ that takes it out. Moving
      another first makes it home.
    - An entry typed at a list's foot is added with Enter. One listed
      already, ignoring case, or one the files wouldn't take is refused,
      and the section says why: a name with quotes, a pattern that doesn't
      compile or has no capture group, or taking out the last standing
      workspace. The patterns are checked in the window's JavaScriptCore,
      as tide checks them at load.
    - The first change to a list copies it into `workspaces.local.json`,
      keeping the file's other settings, `muted` among them. A file that's
      wrong can't be changed here until it's fixed.
    - `muted` stays on the Notifications section, as it's on tide for Linux's
      Notifications page.
- **A bad value is an error at load,** naming the setting, not a failure
  later. A pattern that doesn't compile is one (§6.2).
- **Pages, as tide for Linux's** (tide for Linux §16): Layouts, Keyboard's shortcuts (§7.2),
  Appearance, Mouse and Keyboard, the checklist (§10), and the permissions
  (§11).
  - **Built: the Setup checklist,** the settings window's last section,
    after tide for Linux's pages, since tide for Linux has no checklist page; it's tide for Chrome's
    options page's (tide for Chrome §3.4). Its launcher row is "Tide Settings: Setup
    checklist", which "permissions" and "accessibility" find too.
    - **Permissions** first, each with its state and an Open button to
      its list in Privacy & Security
      (`com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility`
      and the rest) *(unverified that the anchors still select the list on
      macOS 26)*:
      - Accessibility: On or Off, as `hs.accessibilityState(false)` says,
        which shows no prompt. Off is in red, and `tide doctor` names it.
      - Input Monitoring: Not needed while Super comes from Karabiner (§7.1).
        Without it, Can't tell: Hammerspoon has no call that reads it
        without asking.
      - Screen Recording: Not needed (§11.1), whatever it's set to.
      - Automation: Can't tell. macOS asks per browser the first time the
        switcher lists its tabs (§9), and there's no way to read it unasked.
    - **Settings** next, each with what to set and an Open button to its
      pane: one Space per display and the rest of Mission Control's, and
      macOS's own tiling off (Desktop & Dock, §6.6); minimize into the app's
      icon with the Scale effect (Desktop & Dock, §6); the password at once
      (Lock Screen, §10); and Chrome's notifications allowed (Notifications,
      §5.1).
    - They're ticked off by hand, as tide for Chrome's are: macOS's settings are
      read nowhere. The ticks are this Mac's own, the items' IDs in
      `hs.settings` (`tide.setup_done`); a tick for an item that's gone
      is dropped. The section says how many are still to do.
    - The permissions are read each time the window draws, and again each
      time it comes forward, so one granted in System Settings shows on
      coming back, as tide for Chrome's keys list does.
    - **Cost and reliability:** nothing to pay, and nothing new to run; one
      Accessibility query each time the window draws or comes forward.
  - **Built: the sidebar, as tide for Linux's panel's** (tide for Linux §16): the pages run
    down the window's side under tide for Linux's group headings, Hardware, Windows
    and General, and one page shows beside them at a time.
    - Hardware is the machine and what's plugged into it, Windows is how
      windows are placed, and General is the rest. The Setup checklist,
      tide's own, is General's last page *(a guess, to confirm)*.
    - A heading can't be chosen. A click shows its page, at the top. Up and
      Down change the page, passing over the headings and stopping at the
      first and last, except while you're typing in a field.
    - The groups and each page's group are data in `launcher.lua`
      (`SETTINGS_GROUPS` and `SETTINGS_SECTIONS`), the list the launcher's
      rows come from, so a new page names its group.
    - A launcher row opens the window on its page. Keyboard shortcuts' row
      opens Keyboard, scrolled to them.
    - The window is 760 by 710 points, tall enough for every page and
      heading, as tide for Linux's card is, or the display's height, where the
      sidebar scrolls.
  - **Built: it looks as tide for Linux's panel does** (tide for Linux's
    `shell/SettingsWindow.qml`, and its mock, `docs/mocks/settings.png`):
    - **Colors:** tide for Linux's palette, light and dark. `make check-tide` checks
      each against tide for Linux's `theme/palette.json`.
    - **Sidebar:** a page is a 32-point row with its icon. The icons are
      Material Symbols Rounded, as tide for Linux's mocks draw them (Apache 2.0),
      inlined in the page, so it draws offline. There's no logo atop it,
      as tide for Linux's has none; the window's title says tide.
    - **A page:** its title, then what to know first, dimmer, under it.
      A sub-heading is small capitals, dim, as tide for Linux's Heading.
    - **Controls:** on and off is a round switch, the accent when on.
      Up, down, remove, − and +, and ‹ and › are icons, lit on hover. A
      field is filled, and edged in the accent while typed in.
    - **Buttons to System Settings or a helper:** rows at the page's foot,
      each with an open-in-a-window icon, as tide for Linux's advanced row.
    - The page keeps each button's glyph as its text, and draws the icon
      over it (`data-icon`), so its tests find it as before.
  - **Built: Displays sets each display itself,** as tide for Linux's Displays page
    does (tide for Linux §16), through `hs.screen` (`displays.lua`,
    `displays_hs.lua`).
    - Under each display's name, the main one first: its resolution, ‹ and
      ›, through the sizes macOS lists for it at the scale it's at, as
      System Settings' Looks like has them, each at its highest refresh
      rate. Only a size macOS lists is ever set.
    - For the others: where it goes beside the main display, ‹ and ›
      through To the right, To the left, Above and Below, as tide for Linux's Place
      has them, set edge to edge with the top or left edges lined up; and
      Make main. One overlapping the main display, as a mirror does, is
      Elsewhere.
    - Its brightness, where macOS can set it (`hs.screen:getBrightness`
      gives one): a slider, set as it moves. An external display's is read
      over DDC/CI with the bar's tool (m1ddc or ddcctl, §8), MCCS's
      luminance (VCP 0x10), as the window opens and as displays change, and
      set once the slider's let go, as a monitor's volume is. Every run of
      the tool goes through one queue, so reads and sets reach the monitor
      in the order asked, and of the sets waiting only the latest is sent. Without the
      tool, or for a monitor that doesn't answer, there's no slider, and
      the log says why once.
    - The page shows what macOS says after each change, and again as a
      display comes, goes or changes. tide for Linux tiles each display again as it
      changes, as it does for one plugged in.
    - **Cost and reliability:** nothing to install. *(Unverified on a Mac:
      whether every display's modes come back at their scale, and how long
      macOS takes to apply a size.)*
  - **Built: Sound sets the devices itself,** as tide for Linux's Sound page does
    (tide for Linux §16), through `hs.audiodevice` (`sound.lua`, `sound_hs.lua`).
    - Under Output, then Input: the device in use's mute, a slider and its
      level, then a row for each device, the one in use lit. A click on
      another uses it.
    - The output goes through the bar's volume popover's operations when
      the bar is on, so a monitor's volume over DDC is the one set, once
      the slider is let go, as the popover does. macOS's own volume follows
      the slider as it moves.
    - The page shows what macOS says after each change, and follows the
      volume keys and devices coming and going while it's open, as the
      bar sees them.
    - A device with no volume control has no slider. A device that goes
      while it's read is logged, and the page shows none, rather than the
      rest of the window going undrawn.
    - **Cost and reliability:** nothing to install; Core Audio through
      Hammerspoon, as the bar uses already.
  - **Built: Keyboard's input sources,** as tide for Linux's Keyboard page has its
    layouts (`inputsrc.lua`): the keyboard layouts and input methods
    macOS has on (`hs.keycodes`), layouts first as the bar lists them, the
    one in use lit, and a click to use another. Switched anywhere else,
    from the menu bar or a shortcut, the page follows, as the bar does:
    macOS calls one function as it changes, which the two share
    (`inputsrc.watch`). Adding or taking one out stays in Keyboard
    settings. Key repeat isn't here: macOS applies a
    change only at the next login *(unverified)*, so a live control
    would mislead.
  - **Built: Do not disturb on a schedule, as tide for Linux's** (`dndsched.lua`,
    `dndsched_hs.lua`), from tide for Linux's `notifications.json` and
    `notifications.local.json`, read with tide for Linux's own module (copied
    unchanged, `dashboard/tide-dnd.js`), run in JavaScriptCore.
    - As a window opens (`dndFrom` on a listed day), tide turns Do Not
      Disturb on, through presenter mode's Do Not Disturb On and Off
      shortcuts (§10); as it closes (`dndTo`), off, if the schedule turned
      it on. Turned on or off by hand meanwhile (the launcher, presenter
      mode), the close leaves it.
    - macOS doesn't say whether Do Not Disturb is on, so unlike tide for Linux's, a
      window opening turns it on even when it's on already, and one
      closing turns off what you turned on before it opened.
    - It looks every minute and on a wake. Off by default, as tide for Linux's is.
      A file gone wrong is logged, and the last good schedule stays in
      effect, as tide for Linux's does, so a slip in an edit doesn't end a window.
    - The page: On or Off, From and To, − and + a quarter hour past the
      other, and the days a window starts on. Critical alerts breaking
      through is tide for Linux's notification server's alone, so it isn't here.
    - **Cost and reliability:** the two shortcuts the Setup checklist asks
      for. A short JavaScript run a minute. Focus settings' own schedules
      run too.
  - **Built: Idle runs tide for Linux's timeline** (`idle.lua`, `idle_hs.lua`), from
    tide for Linux's `idle.json` and `idle.local.json`, read as tide for Linux's idle module
    reads them (copied unchanged, `dashboard/tide-idle.js`). With nothing
    set in either, macOS's own Lock Screen settings alone time it.
    - With no input for each step's time: a dark veil over every display
      for the dim (an `hs.canvas` at the screen saver's level), macOS's
      lock, the displays off (`pmset displaysleepnow`), and sleep, on
      battery or on AC too if set. Input lifts the dim, and the timeline
      starts again.
    - tide looks at the idle time (`hs.host.idleTime`) every 5 s, and
      every second while dimmed. Each step happens once until the next
      input; back from a long sleep, the steps due happen in order.
    - An app keeping the display awake (a power assertion, as a video
      playing holds) holds every step, as an idle inhibit does on tide for Linux;
      one keeping the system awake holds the sleep alone. tide's own
      keep awake holds the display, so it holds the timeline too.
    - The page: Use tide for Linux's idle settings, On or Off, then each step's time, − and +
      along tide for Linux's ladder, and Sleep when plugged in. On writes tide for Linux's timings
      as they stand to `idle.local.json`; Off empties it, and can't turn
      off what the shared file sets.
    - macOS's own timers still run, so the page says to disable its lock
      timer, above a Lock settings button. None of this needs an
      administrator.
    - **Cost and reliability:** nothing to install. One cheap reading every
      5 s while it runs. *(Unverified on a Mac: that the veil covers the
      menu bar and full-screen apps, and how `pmset displaysleepnow`
      behaves with an external display.)*
  - **Built: Network and Power show what the bar reads** (`netpower.lua`,
    `netpower_hs.lua`), through the bar's own `bar.icons`, so the two
    agree.
    - Network: Wi-Fi On or Off (`hs.wifi.setPower`), then the network
      it's joined to, and whether the Mac's online over Wi-Fi or a wire,
      through a VPN or not. Without Location Services for Hammerspoon,
      macOS gives no network's name, and the page says so. Picking a
      network stays in Network settings.
    - Power: the battery's level and what it's doing, as the bar's hover
      says it, or that the Mac has none. Low Power Mode needs an
      administrator's `pmset`, so it stays in Battery settings.
    - The pages read every 5 s while the window's open, so they follow
      the battery and the network with the bar off too, and again two
      seconds after the switch, as Wi-Fi takes a moment. A VPN is told as
      the bar tells it, by the tunnel or by its network service, so one
      that carries only some traffic counts.
    - **Cost and reliability:** nothing to install; what the bar reads
      already. *(Unverified on a Mac: whether `hs.wifi.setPower` needs an
      administrator on macOS 26.)*
  - **Built: Bluetooth switches it and connects devices itself,** as
    tide for Linux's Bluetooth popover does (tide for Linux §7.4), through the bar's blueutil
    (§8; `bluetooth.lua`, `bluetooth_hs.lua`).
    - Bluetooth On or Off, then, while it's on, the paired devices,
      connected first, then by name, each lit while connected, with its
      status: Connected, Connecting… or Disconnecting…. A click connects
      one, or disconnects one that's connected; one being either waits.
    - Pairing a new one stays in Bluetooth settings, as tide for Linux leaves it to
      blueman-manager.
    - `blueutil --power`, `--paired --format json`, `--connect` and
      `--disconnect`, through `hs.task`, never waiting on them. The page
      sends a device's address alone, which tide checks is one, so no
      name or option reaches blueutil.
    - It reads as the window opens, every 5 s while it's open, so a
      device that connects by itself shows, and after each change, when
      the bar reads too. One read at a time.
    - With no `blueutil`, or when it fails, the page says why, and the log
      says it once.
    - **Cost and reliability:** blueutil, which the bar uses already. Two
      short processes every 5 s while the window's open. *(Unverified on a
      Mac: how long a connect takes, and what blueutil prints for a
      device that won't.)*
  - **Built: every page of tide for Linux's is a section, in tide for Linux's order,** so the
    window is laid out as tide for Linux's panel is. Where a page's settings are
    macOS's or a helper's, it has a button for each place they're changed,
    and nothing else (§1):

    | Section | Buttons |
    |---|---|
    | Displays | each display's resolution, place beside the main display, Make main, and brightness where macOS can set it (below); Displays settings |
    | Sound | the output and the input in use, each with its mute, volume and level, and the devices to pick from (below); Sound settings |
    | Network | Wi-Fi On or Off, the network it's joined to, and how the Mac's online (below); Network settings |
    | Bluetooth | On or Off, and the paired devices, each connected or disconnected (below); Bluetooth settings |
    | Mouse | Speed and Acceleration, then Scroll speed and Natural scrolling (below); Mouse settings, LinearMouse settings |
    | Trackpad | Trackpad settings |
    | Keyboard | the input sources, each a click to use (below), the Switcher, tide for Linux's or tide for Chrome's (§9.2), and conf's Karabiner rules, each On or Off (below); Keyboard settings, Karabiner settings |
    | Power | the battery, as the bar's hover says it (below); Battery settings |
    | Layouts, Workspaces, Floating | none: tide's own (below) |
    | Appearance | light or dark on tide for Linux's schedule, and its switch (§10), the wallpapers, light and dark, each chosen in macOS's file dialog and placed as its position says, and the Menu bar switch; Appearance settings |
    | Notifications | Do not disturb on a schedule, its times and days (below); Notifications settings, above the muted list |
    | Clipboard | none: tide's own (below) |
    | Clocks | Date & Time settings, for the Mac's own zone |
    | Idle | Use tide for Linux's idle settings On or Off, each step's time, and Sleep when plugged in (below); Lock settings |
    | Start at login | Login Items settings, for macOS's own list |

    - A pane opens by its `x-apple.systempreferences:` ID, as the bar's
      status items do. CI's smoke test checks each is one of macOS 15's
      panes; macOS 26's are *(unverified)*.
    - LinearMouse settings runs `open -b com.lujjjh.LinearMouse --args
      --show`. That starts LinearMouse with its window showing, or brings
      a running one's window forward, as a reopen does (LinearMouse
      `AppDelegate.swift`).
    - Karabiner settings opens Karabiner-Elements, its settings app.
    - The page sends a button's name, and tide opens what that name
      stands for, so the page can't open just any URL.
    - The Mouse section says what's wrong with LinearMouse, only when
      something is: it isn't installed, isn't running, or its config
      can't be set (§10).
  - **Built: the Mouse section's Scroll speed and Natural scrolling,** as
    tide for Linux's Mouse page's rows (tide for Linux §16), for every mouse: − and + step
    through tide for Linux's marks (0.25× to 5×), and On or Off switches. A change
    writes only `input.local.json`, with tide for Linux's `withSetting`, keeping
    whatever else it says, and tide applies it to LinearMouse when the
    folder changes (§10). A file that's wrong is named, and nothing
    changes here until it's fixed. Left-handed stays in Mouse settings
    for now (TODO.md).
  - **Built: the Mouse section's Speed and Acceleration,** the Mac's own,
    above tide for Linux's rows, as tide for Linux's Mouse page has the same two (tide for Linux §16).
    They're LinearMouse's `pointer.speed` and `pointer.acceleration` for
    every mouse, in the same last every-mouse scheme as the scrolling,
    not tide for Linux's `input.json`: a value tuned for macOS's curve means
    nothing to libinput's, so the Mac keeps its own (§10).
    - − and + step through 0.05 to 1 for the speed, and 0 to 4 for the
      acceleration (macOS's own `com.apple.mouse.scaling`, which
      LinearMouse sets). Left to macOS, a row says "macOS's", and its
      first step lands on `setup-macos`'s 0.35 and 1.5.
    - A change goes to tide, which writes it with `linearmouse.js`'s
      `withMousePointer` and shows the result. One it can't make (out of
      range, a config that isn't JSON, LinearMouse not installed) is a
      notification, and nothing's written.
  - **Built: the Keyboard section switches Karabiner's rules,** each rule
    in the files conf links into Karabiner's assets folder
    (`~/.config/karabiner/assets/complex_modifications/`) with On or Off, so
    Ctrl+Tab's next tab and the rest never wait on Karabiner's own window.
    Its launcher row is "Tide Settings: Keyboard", which "karabiner" finds
    too.
    - On copies the rule from its file into the selected profile's
      `complex_modifications.rules` in `~/.config/karabiner/karabiner.json`,
      as Karabiner's Enable button does; Off takes every copy out. Karabiner
      watches that file and reloads it (its `configuration_monitor`), its
      settings window included.
    - Each goes in its place: Karabiner uses the first rule that matches a
      key, so tide's and the terminal rule go above the arrow rule, conf's
      lock screen rule (Ctrl+U clears the password) above tide's, which
      would take a Mac keyboard's Command+U there as Super+U, and a rule
      tide doesn't know goes at the top, as Karabiner puts it.
    - The edit is JavaScript (`dashboard/karabiner.js`), run in
      JavaScriptCore, as the name patterns are (§6.2), since only
      `JSON.parse` and `JSON.stringify` keep the rest of the file as it was;
      `hs.json` can't tell `[]` from `{}`. It's written whole, to a file
      renamed over it, through a symlink if it's one.
    - **Kept as conf has it,** as tide starts, every 30 s, and a second
      after a device plugged in or a wake (§10), when a file
      or `karabiner.json` changed: a copy that differs from its file is
      brought up to date in its place, keeping what Karabiner added (a rule
      turned off in Karabiner's window stays off). A rule tide hasn't seen
      before is turned on, once: tide keeps the ones it has seen in
      `hs.settings`, so one you turn off stays off. Each is a notification.
    - What's wrong shows only when something is: Karabiner hasn't written
      its settings yet, `karabiner.json` isn't JSON (left alone), there are
      no rule files (run `confinst`), a rule file is wrong, or Karabiner
      isn't running.
    - **Cost and reliability:** nothing to pay, and nothing new to run; the
      JavaScript runs only when a file changed. If Karabiner's window saves
      at the same moment, one of the two edits can be lost; the next check
      puts a rule tide turned on back.
  - **Built: Keyboard's Shortcuts,** below the Karabiner rules, as tide for Linux's
    Keyboard page has its shortcuts below its settings (tide for Linux §16).
    Read-only, as tide for Linux's are.
    - They come from `keys.lua`, as tide registered them as it started,
      or as Super last moved between Karabiner's and Option (§7.1): each
      binding's keys and what it does, in `keys.bindings`' order, then
      resize mode's keys, as "Resize mode: H", as tide for Linux shows a submap.
    - Keys show as they're printed on a PC keyboard, as tide for Linux's do: Super
      for whichever modifiers stand for it, `Super+Backspace`,
      `Super+Insert` for the Mac's Help, `Print` for F13, `Alt+Tab` for
      the Karabiner chord it arrives as, and "Tap Super" for Super+F20.
    - What one does is its `does` in `keys.lua`, in conf's words for
      tide for Linux's same key where it has one. One without says "no
      description", as on tide.
    - **A key that didn't register** is listed under them, in red, with
      what it does and why: macOS refused it, or another binding has the
      same chord. With Super on Option that's Super+Print, which is
      Alt+Print, the window screenshot. `tide doctor` names them too.
    - Its launcher row is "Tide Settings: Keyboard shortcuts", which
      scrolls to them, as tide for Linux's Keyboard shortcuts row does.
    - The mouse's Super+drag and the rest (§5.3) aren't listed: they're
      the event tap's, not `keys.lua`'s.
    - **Cost and reliability:** nothing to pay, and nothing new to run; the
      list is made as the keys bind.
  - **Built: Layouts,** a section of the settings window, as tide for Linux's
    Layouts page (tide for Linux §16), with tide for Linux's own `layouts.mjs` and `steps.mjs`,
    copied unchanged as `dashboard/tide-layouts.js` and `tide-steps.js`:
    where ultrawide begins, the mode a new workspace starts in on each kind
    of display, where a new window goes, each mode's master width and
    count, and a lone window's width. − and + step to tide for Linux's marks, ‹ and ›
    through the choices. It writes only `layouts.local.json`, keeping what
    else it says; a file that's wrong is named, and nothing changes here
    until it's fixed. Its launcher row is "Tide Settings: Layouts".
  - **Built: Clocks,** a window from the launcher ("Tide Settings: Clocks") or
    the dashboard ("Change the clocks…"). The window also has the Start at
    login, Clipboard and Muted sections. Each section has its own launcher
    row ("Tide Settings: Clocks", "Tide Settings: Start at login" and so
    on, §9), found by its name, which opens the window there, or
    turns an open one to it, as tide for Linux's per-page rows do (tide for Linux §16). As tide for Linux's Clocks page, it adds a
    zone by its ID, relabels, moves and removes clocks, and writes only
    `clocks.local.json`, with tide for Linux's own functions, so the first change
    copies the list the bar shows. A zone Intl doesn't know is refused.
    tide watches the folder, so the bar, the dashboard and the page
    follow a change, a hand edit's included.
  - **Built: Clipboard,** a section of the settings window, as tide for Linux's
    Clipboard page (tide for Linux §16), with tide for Linux's own `clipboard.mjs`, copied
    unchanged as `dashboard/tide-clipboard.js`. It reads and writes tide for Linux's
    `clipboard.json` and `clipboard.local.json`, key by key, so one setting
    serves both desktops.
    - `history` turns keeping new copies on or off, on by default. Off,
      what's kept stays until it's cleared or its days are up.
    - `maxItems` is how many it keeps, 100 by default, from 1 to 10,000.
      − and + step through tide for Linux's marks (25 to 1,000). A smaller cap trims
      the history at once.
    - `maxAgeDays` is how many days an entry stays after it was last
      copied, 7 by default, from 1 to 3,650: "Days to keep", whose − and
      + step through tide for Linux's marks (1 day to 365).
    - **Clear history** forgets every copy, at once.
    - A file that's wrong is an error at load, in a notification naming
      the file and the setting, and the last good settings stay; the
      section says so too, and changes nothing until it's fixed. tide
      reads the files again when the folder changes.
  - **The settings window also lists the muted apps and sites** (§14.2),
    each with an Unmute button, writing `workspaces.local.json` as the
    one-key mute does.
    - As on tide for Linux's Notifications page, a bundle id or `site:HOST` typed at
      the list's foot is muted with Enter. One the list wouldn't take back
      on loading, or one muted already, is refused, and the section says
      why.
- **Built: Floating,** a section of the settings window, as tide for Linux's
  Floating page (tide for Linux §16): the rules that float a window by its app and
  title, and the floating windows no rule covers yet. Its launcher row is
  "Tide Settings: Floating".
  - The rules are in `floating-macos.json` and `floating-macos.local.json`
    in tide for Linux's folder, `rules`, a list of `{"app": "com.apple.Preview"}`,
    each with an optional `"title"`. They're tide's own, not tide for Linux's
    `floating.json`: a bundle ID isn't a Wayland class, so the two lists
    can't be one.
    - A local list replaces the shared one whole (tide for Linux §16.1), and
      tide writes only the local file, keeping its other keys, so the
      first change copies the shared list. The shared file is for a list
      every Mac of yours takes, such as one `conf` installs; tide
      installs none.
    - The app is the window's bundle ID, matched exactly. The title is a
      **Lua pattern**, found anywhere in the title, as `start()`'s rules
      have always been: `^Save` for a title starting "Save", `%.` for a
      dot. Lua patterns have no `|` and match bytes, not characters, so
      `.` is one byte of a UTF-8 letter. tide for Linux's JavaScript and RE2
      dialect doesn't apply: the two desktops share no rules.
    - An entry with no app, an app with a space, a key other than these
      two, a title that isn't a Lua pattern, or one listed already is an
      error at load naming the file, `rules` and the entry. So is a list
      of more than 64, as on tide. The last good rules stay, and a
      notification says so once.
    - A pattern is checked whole, as Lua's matcher reads it: Lua says a
      pattern is malformed only when a match reaches the bad part, so a
      trial match would pass `^Save[`. `start()`'s titles are checked the
      same way. A bad one that gets past anyway matches nothing, and the
      log names it once, so it can't stop windows being decided.
    - They come after `start()`'s `rules` and before tide's own
      (§5.1). `start()`'s can tile or leave a window alone, and the
      section can't change them, so one there wins over the section's.
  - **A new rule floats the windows open now that it covers,** as tide for Linux's
    does (tide for Linux §16):
    - the tiled ones the new rules float and the old ones didn't, on every
      workspace and display, minimized ones included;
    - not one you tiled by hand under a rule that already covered it, or
      that a dialog step (§5.1) floated, so a broader rule doesn't
      re-float a tiled Save As;
    - not a full screen or maximized one;
    - each placed as a new float is, at the size it opened at, centered.
      One that isn't showing, minimized or on a hidden workspace, is
      placed the first time it shows again, by the same step.
    - A list only reordered, the same rules again, or a rule taken out
      floats nothing, and taking one out tiles nothing.
    - tide decides every window again as it starts, so unlike tide for Linux it
      keeps no record of what it last swept: a reload floats every window
      a rule covers, as `start()`'s rules always have.
  - The section lists the rules, with ↑ and ↓ to move one and ✕ to take it
    out. An app and a title typed at the foot are added with Enter or
    *Add*. tide makes each change, since the page can't check a Lua
    pattern, and names a rule by its place, app and title, so a hand edit
    that has moved it since is refused. A refusal says why under the
    fields.
  - *Floating now* lists the floating windows no rule covers, one per app,
    by app name. Every rule counts, and so do the dialog steps (§5.1). A
    window with no bundle ID can't be named, so it isn't listed.
  - *Always float* adds nothing yet. It fills the fields with the
    window's bundle ID and a pattern for its exact title: the title with
    Lua's magic characters escaped (`.` as `%.`), between `^` and `$`.
    - The title field takes the keys with its text selected, to trim, or
      clear for every window of the app.
    - Enter or *Add* adds the rule. Esc clears the fields; with them
      empty, it closes the window.
    - When something floats the window already, the section says what,
      under the fields: one of your rules, `start()`'s, tide's own, or
      the dialog step that does.
    - *More about this window*, under the fields, lists what macOS says of
      it, read-only: its role, subrole, whether it's modal, resizable and
      standard, its app's name and the app's path, each only when macOS
      says. Nothing matches on these but the rules' app and title; they
      show what a rule could need. The section starts closed, and stays as
      you leave it while the settings window is open.
  - `Super+Shift+I` opens the section filled in for the focused window, as
    *Always float* fills it (§7.2). tide for Linux's key is `Super+Alt+F`, which
    tide can't have: Super's chord holds Option already, with Karabiner
    or without. A focused window with no bundle ID, or none at all, is a
    notification saying so.
  - **Cost and reliability:** nothing to pay, and nothing new to run. A
    change reads every managed window's facts once, as a sync does.
- **One owner per job** (tide for Linux §5): tide tiles, binds keys and draws the
  bar. Karabiner remaps the keyboard. macOS owns notifications, lock and
  idle. Nothing else tiles.
- **`tide doctor`** checks what usually goes wrong. Each problem it finds
  is also a notification when it starts, as §1's "never degrade silently"
  asks, naming what stops working and the fix:
  - each permission (§11.1), and whether the event tap is still on (§16);
  - another tiler running: Amethyst, Rectangle, yabai, AeroSpace;
  - a symbolichotkey holding one of tide's keys (§7.3), and any key that
    failed to register (built: the keys, as Keyboard's Shortcuts list
    them);
  - Karabiner's rules loaded, and tide's rule up to date, checked again
    after a plug or a wake: Karabiner
    runs the copy it made when the rule was enabled, so a copy from before
    conf added Alt+Tab (Ctrl+Option+Shift+Tab) and the tap's Super+F20
    leaves those two dead. tide reads the copy in `karabiner.json`, and a
    notification names what's missing and says to remove and re-add the
    rule, once each time that changes, rechecked every 30 s (§7.1, §7.2).
    **Built so far:** this check, Accessibility (the Setup checklist,
    above), Karabiner's and LinearMouse's, as
    `tide.doctor()` in Hammerspoon's console and the switcher's "Check
    tide for Linux (doctor)";
  - conf's Karabiner rules that are off, and what stops tide switching
    them (the Keyboard section, above);
  - LinearMouse installed and running, for the mouse wheel (§10). A
    notification says so as tide starts, and once each time it changes,
    rechecked every 30 s. A click on the one for LinearMouse not running
    starts it with its window showing; and what stops tide setting its
    scrolling (§10);
  - the workspace file written and private, for scripts that read the
    workspace's name, and kitty's remote control on, for `TIDE_WORKSPACE`
    in new kitty windows (§6.3);
  - Stage Manager or Sequoia's tiling on (§6.6);
  - a second bar running, such as SketchyBar.

## 16. Known problems

| Problem | What tide does |
|---|---|
| macOS switches off an event tap whose handler is too slow (`kCGEventTapDisabledByTimeout`), which would stop the Super tap, drags and focus follows mouse *(unverified how quickly)* | Keeps the handler short, re-enables the tap when told it was switched off, and `tide doctor` reports it. |
| A macOS update, or a new tide build, resets Accessibility (scripts `docs/MACOS.md`) | The doctor and the checklist say so, and link the pane. |
| Screen Recording asks again every so often since macOS 15 *(unverified on macOS 26)* | tide doesn't use it (§2.5). |
| Secure Input stops event taps seeing keys (§13) | Registered hotkeys still work; the tap rules don't. |
| A hung app stalls Accessibility calls (§2.1) | A short timeout per call, and that app is skipped (§5.2). |
| tide quits or crashes with workspaces hidden | Restores everything on quit, and reconciles at start (§6.5). |

## 17. Where things live

- **On screen it's tide.** Notification titles, window titles, the
  switcher's own commands ("Reload tide", "Check tide (doctor)"), the
  settings page and every message say tide, and the menu bar item,
  notifications, those commands and the settings page show tide for Linux's wave
  logo, as the bar does. The logo's PNGs are rendered from a copy of
  tide for Linux's `shell/icons/tide-symbolic.svg` (`make check-tide` compares it)
  by `make icons`, with Playwright's Chromium: black on clear for the menu
  bar's template, tide for Linux's accent blue for the rest, at 4x their size in
  points. `brand.lua` holds the name and the logo's files.
- **The code is tide too:** the Lua modules (`require("tide")`), the
  `hs.settings` keys (`tide.*`), the workspace file's folder, the pages'
  message handler and conf's `tide:` Karabiner rule.
- **What was tilemo's carries over.** `require("tilemo")` and
  `require("timo")` load tide, with a note in the console. At start,
  `hs.settings` keys starting `tilemo.` are copied to the same `tide.` ones
  where tide has none, and the old ones stay, for a downgrade.
  `~/Library/Caches/tilemo` moves to `~/Library/Caches/tide`, with a link in
  its place for shells that still read it there. A Karabiner rule described
  `tilemo:` or `timo:` still counts as tide's, and conf's `tilemo.json` as
  conf's. A renamed command keeps its old name as the key the switcher
  remembers its use by.

- **tide** (this repo): the spec, then the code.
- **conf:**
  - Karabiner's rules (`config/karabiner/`), updated for §7.1 and §7.3, with
    physical Alt+Tab going to tide (§7.2);
  - the shell's shpool and tmux startup, which reads `TIDE_WORKSPACE`, and
    on a Mac reads tide's workspace file when it's missing (§6.3);
  - `kitty.conf`'s remote control socket, private to you, on a Mac only,
    for `TIDE_WORKSPACE` in new kitty windows (§6.3);
  - `amethyst.yml` retired;
  - the Hammerspoon config, if tide starts as route B (§3).
- **scripts:** `setup-macos`. It installs tide, frees the keys in §7.3,
  removes Amethyst and Rectangle, applies the Mission Control settings
  (§6.6), turning Mission Control's keys, gestures and hot corners off for
  tide's overview (§6.9), and stops making nine Spaces.
- **tide for Linux:** the layout geometry and its test fixtures, shared so tide
  doesn't keep its own copy, and the picker's character list (§9.1),
  which `make check-tide` compares.

## 18. Testing and milestones

- **Tests, as tide for Linux's and tide for Chrome's** (tide for Linux §20, tide for Chrome §17):
  - the geometry against tide for Linux's own fixtures;
  - the workspace model (§6.1) and focus follows mouse's decisions (§5.2)
    against a fake Accessibility layer, with no sleeps;
  - in CI on a macOS runner, a smoke test in a real Hammerspoon
    (`ci/hs-smoke.sh`): every `hs.*` name tide uses exists, tide starts
    with its bar along the top of each display, and opens its dashboard,
    then tiles three TextEdit windows and checks each lands below the bar
    where the layout puts it. GitHub's macOS runners come with
    Accessibility granted, which is what lets that run.
- **On a real Mac:** the focus follows mouse checklist (§5.2), the dialog
  checklist (§5.1), and each *(unverified)* claim in this spec. A claim
  checked comes out of italics, with the macOS version.
- **Milestones:**
  1. **This spec,** agreed.
  2. **Tiling and keys:** the layouts, floats, the key map and the mouse,
     on Hammerspoon. Done when the dialog checklist passes.
  3. **Focus follows mouse,** on by default. Done when its checklist
     passes.
  4. **Workspaces:** parking (or minimizing), displays and restarts. Done when a day's
     work needs no Mission Control.
  5. **Bar, switcher and dashboard,** then attention.
  6. **Named workspaces:** "in", the name prompt, `TIDE_WORKSPACE` and the
     switcher's tabs (§6.1–§6.3, §9). Done when a day starts on "in" and
     every new task gets its name.

## 19. Open questions

1. **Workspaces:** decided, park, with minimizing as a setting (§6, changed
   from minimize on 2026-11-05), and native Spaces next if neither works
   out.
2. **Build route:** Hammerspoon first (§3 B), or straight to a native app?
3. **Bar:** decided, tide's own bar over an auto-hidden menu bar, with its
   own status items (§8). The menu bar item stays as the fallback.
4. **Amethyst:** decided (2026-11-01), replace it. `setup-macos` sets up
   tide unless `--wm amethyst` says otherwise, so a plain `setup` does
   too, and it pulls an existing tide checkout first. Running both would
   fight over the same windows, so it warns about an Amethyst still
   installed.
5. **The dim:** decided (2026-11-04), tide's own, a layer over the
   windows with a hole for the focused one (§5.6), in place of HazeOver.
6. **Karabiner for Super:** decided, yes (§7.1).
7. **The built-in keyboard:** rotate its modifiers too, or PC keyboards
   only (§7.1)?
8. **A key to toggle focus follows mouse:** decided, none;
   `tide.toggle_focus_follows_mouse()` from Hammerspoon's console, or
   `focus_follows_mouse = false` in `start()` (§5.2).
9. **`Super+1…9` and `Super+Shift+1…9`:** decided, positions in bar order
   (§7.2).
10. **`Super+End`:** decided, the last workspace other than "in" and the
    one you're on (§7.2).
11. **Physical Alt+Tab:** decided, swap with the master, with the
    Windows tab in place of the app switcher (§7.2).
12. **Several displays:** decided (2026-11-01), and built. A workspace
    spans every display, each display with its own layout within it
    (§6.1). `Super+Left` / `Right` select the window that way, going on to
    the next display at the edge, by a rule for displays of any size and
    offset (§7.2); `Super+Shift+Left` / `Right` move the window the same
    way. Previous / next workspace stay on `Super+PgUp` / `PgDn`, and
    moving the window there is `Super+Shift+PgUp` / `PgDn`.

## Sources

- scripts `docs/MACOS.md`: the Amethyst, yabai and AeroSpace evaluation,
  symbolichotkeys, the modifier rotation, and focus follows mouse.
- [AeroSpace README](https://github.com/nikitabobko/AeroSpace): one private
  API (`_AXUIElementGetWindow`), emulated workspaces, no SIP.
- [Hacker News, AeroSpace](https://news.ycombinator.com/threads?id=irth):
  hidden windows parked in the lower-right corner.
- [go-macos/hotkey](https://pkg.go.dev/github.com/go-macos/hotkey):
  `RegisterEventHotKey` needs no permission, including on macOS 26.
- [HazeOver help](https://hazeover.com/help.html): one translucent layer
  behind the active window; Accessibility for focus.
- [SketchyBar](https://github.com/felixkratz/sketchybar): menu bar
  replacement.
- [Apple: tile windows on Mac](https://support.apple.com/guide/mac-help/mchl9674d0b0/mac),
  [9to5Mac](https://9to5mac.com/2024/07/19/use-automatic-window-tiling-macos-sequoia/),
  [SlashGear](https://www.slashgear.com/1673225/macos-sequoia-window-tiling-shortcuts):
  Sequoia tiling and its keys.
- [MacMost](https://macmost.com/how-to-use-spotlight-actions-in-macos-tahoe.html),
  [iThinkDiff](https://www.ithinkdiff.com/spotlight-macos-tahoe-quick-keys-clipboard/):
  Spotlight actions and Quick Keys in macOS 26.
- [iBoysoft](https://iboysoft.com/wiki/macos-mouse-acceleration.html),
  [NoMouseAccel](https://github.com/apsun/NoMouseAccel): pointer
  acceleration.
- [Hammerspoon docs](https://www.hammerspoon.org/docs/): `hs.canvas`,
  `hs.chooser`.
- [Amethyst issues](https://github.com/ianyh/Amethyst/issues), cited as
  Amethyst#N: its focus-follows-mouse and dialog bugs (§5.2), read October
  2026. Its handler is
  [`FocusFollowsMouseManager.swift`](https://github.com/ianyh/Amethyst/blob/development/Amethyst/Managers/FocusFollowsMouseManager.swift).
- [yabai wiki](https://github.com/koekeishiya/yabai/wiki/Configuration) and
  `src/mouse_handler.c`: `autofocus` and `autoraise`, sheet forwarding, and
  the pauses for Mission Control and Space swipes.
- [AutoRaise](https://github.com/sbmpost/AutoRaise): menu roles, and the
  apps that keep focus.
- [AeroSpace#12](https://github.com/nikitabobko/AeroSpace/issues/12): its
  focus follows mouse, added in v0.21.0-Beta.
