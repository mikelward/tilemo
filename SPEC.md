# tilemo: tide and tileco on macOS

**Status: exploration.** This explores what macOS allows. It doesn't
yet decide what tilemo is. It takes everything tide does on Linux
([mikelward/tide](https://github.com/mikelward/tide)) and tileco does on
chromeOS ([mikelward/tileco](https://github.com/mikelward/tileco)), and says, for
each one, how a Mac can do it, how well, and at what cost.

The setup this would replace already exists: `setup-macos` in
[mikelward/scripts](https://github.com/mikelward/scripts) installs Amethyst
and Karabiner and rebinds the Spaces shortcuts. Its `docs/MACOS.md` compares
Amethyst, yabai and AeroSpace, and this spec builds on that comparison rather
than repeating it.

Claims about Apple or third-party behavior carry a source. Anything not
checked against a source or a Mac is marked *(unverified)*.

## 1. Goals

- **Everything tide and tileco do,** where macOS allows it:
  - window management: layouts, named workspaces and the dim;
  - keys: one key map across the three desktops;
  - one switcher for apps, workspaces, windows and tabs, and a dashboard
    with clocks and a calendar;
  - attention, focus, idle, theme, and the setup checklist.
- **The same key map and layouts** as tide and tileco, so a hand moving
  between Linux, chromeOS and a Mac doesn't notice. Where those two
  differ, tilemo follows tide, since macOS can bind all of its keys (§7).
- **No SIP changes.** A managed work Mac can't lower its security, and a
  personal one shouldn't have to.
- **Say what can't be done,** as tileco §2 does for chromeOS, so nobody spends
  a week finding out (§13).
- **Never degrade silently.** Fallbacks are tilemo's to choose: Option for
  Super without Karabiner (§7.1), Cmd+N for a kitty window without its
  socket (§6.3), the title for a workspace name without its patterns
  (§6.2). But whenever something a feature depends on is missing or out of
  date (Karabiner or its rule, a permission, an app, a config file, a
  helper), tilemo says so where you'll see it:
  - a notification, once each time it changes, naming what's missing and
    what stops working, and how to fix it;
  - a line in `tilemo doctor` saying the same, for as long as it lasts
    (§15).

  A key that does nothing, or a feature quietly turned off, is the
  failure this rules out.

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
  apps, so tilemo ships outside the store (§12).

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
  has focus (tileco §2.2), every tide key can work everywhere on a Mac.

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
    native full-screen apps misbehave (scripts `docs/MACOS.md`).
- **Minimizing (tileco's way):** hide a workspace by minimizing its windows.
  It's public API, but every switch plays the Genie animation, and minimized
  windows pile up in the Dock *(unverified at scale)*.

### 2.4 Drawing over the desktop

- **Own windows only:** an app can draw its own windows at any level: a
  borderless panel, a full-width bar, a dashboard, an overlay. It can't draw
  inside another app's window, and it can't move the menu bar.
- **The dim:** HazeOver lays "a translucent dark layer behind" the window in
  use, rather than shading each other window
  ([HazeOver help](https://hazeover.com/help.html)). It needs
  Accessibility to follow focus reliably. That one-layer approach is what
  tilemo would copy. How HazeOver keeps the layer ordered just below another
  app's window is *(unverified)*.
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
  Amethyst read them *(unverified on macOS 26)*. So tilemo shouldn't need
  Screen Recording at all.
- **Unread counts:** an app can't read other apps' notifications. It can read
  the Dock badges, which carry the same counts:
  - Through Accessibility, as the `AXStatusLabel` of each Dock item. That's
    a community technique with no Apple documentation, and some apps don't
    report through it ([MailMate list](https://lists.freron.com/mailmate/2018-October/010356.html)).
  - Through `lsappinfo`, which can disagree with the visible badge
    ([Cursor forum](https://forum.cursor.com/t/macos-dock-badge-stuck-at-1-after-update-os-badge-null-until-killall-dock/165949)).
- **Browser tabs:** Chrome, Brave and Safari list their tabs, with titles
  and addresses, to AppleScript or JavaScript for Automation. Brave carries
  Chromium's AppleScript dictionary, so it's asked as Chrome is, as
  `"Brave Browser"` *(unverified on a Mac)*. The user grants
  **Automation** per browser the first time *(unverified on macOS 26)*. That
  gives tileco's tab search without an extension, as the switcher's
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
  tilemo's commands could appear there as App Intents, beside its own
  launcher.
- **Pointer acceleration:** Sonoma added an on/off switch, under System
  Settings › Mouse › Advanced. `defaults write -g com.apple.mouse.scaling`
  takes values beyond the slider's range, and a log-out applies them
  ([iBoysoft](https://iboysoft.com/wiki/macos-mouse-acceleration.html),
  [NoMouseAccel](https://github.com/apsun/NoMouseAccel)).
- **The rest:** Notification Center, Focus modes, screenshots, lock, US
  Dvorak, and dark mode on a sun schedule are all native (§10).

## 3. Three ways to build it

| | A. Configure existing tools | B. Hammerspoon config | C. A native tilemo app |
|---|---|---|---|
| What | Amethyst, Karabiner, Spotlight or Raycast, SketchyBar, JankyBorders or HazeOver, as `setup-macos` does now | One Lua config on [Hammerspoon](https://www.hammerspoon.org), which wraps windows (`hs.window`), keys (`hs.hotkey`), drawing (`hs.canvas`) and a picker (`hs.chooser`) | One Swift app: window manager, keys, launcher, bar and dim |
| Layouts | Amethyst's built-ins match Krohnkite's. JavaScript layouts are possible | **tide's own Lua layout**, which is pure Lua by design (tide AGENTS: "keep geometry free of the `hl` API") | Port tide's or tileco's geometry |
| Workspaces | Native Spaces, via symbolichotkeys | Minimizing (§6), or native Spaces through community modules, or emulated | Any of §2.3 |
| Launcher and dashboard | Spotlight, or Raycast (free, with a paid tier) | `hs.chooser` plus canvases. Basic, but enough for tab search | Full control, like tileco's dashboard |
| Dim | HazeOver ($5) or borders | A canvas layer *(ordering unverified)* | Own layer, as HazeOver does |
| Focus follows mouse | Off: Amethyst's breaks popovers (Amethyst#337) | tilemo's own (§5.2) | Same |
| Cost to build | Done | Days to a first version | Weeks |
| Breakage risk | Amethyst's throw-to-space on private API | Hammerspoon's community `spaces` modules | Ours to fix |

**Recommendation: B first, then decide on C.** Hammerspoon runs tide's
layout code unchanged, gets every tide key working everywhere, and shows
within days which parts macOS fights. Whatever turns out to need native
code becomes the case for C. Which Lua version Hammerspoon embeds
is *(unverified)*: tide's layout targets 5.4 and 5.5.

## 4. Feature map

Status: **yes** = tilemo or macOS meets the tide or tileco behavior;
**partial** = close, with the gap named; **no** = not reachable.

| tide / tileco | On macOS | Status |
|---|---|---|
| Tile, three-column, two columns + stack, monocle (tide §6.1) | tide's Lua layout over Accessibility moves (§5) | **yes**, with apps' own size limits |
| Lone window 80% on ultrawide, 60% from 32:9 | same layout, per display (§5) | **yes** |
| New windows join the end of the stack, with a setting for elsewhere (tide §6.1) | tilemo state (§5) | **yes** |
| Layout, `mfact`, master count per workspace | tilemo state | **yes** |
| Named workspaces, "in" first, Super+Home to "in", Super+Return to go and Super+Shift+Return to move (tide §6.5) | minimized windows, as tileco does, named in tilemo's state (§6) | **partial**: each switch animates |
| A new window on "in" asks for a workspace name (tide §6.5) | tilemo's name prompt, an `hs.chooser` (§6.2) | **yes** |
| `TIDE_WORKSPACE` in launched apps (tide §6.5) | `hs.task`'s environment, `open --env`, and kitty's remote control (§6.3) | **partial**: an app already running keeps its own |
| One workspace per monitor from a shared pool (tide §6.5) | tilemo tracks which display shows each workspace, as tileco does (§6) | **yes** |
| Dim inactive, 0.07, not a lone window or video (tide §6.2) | one dark layer behind the focused window (§5.6) | **not built**; when built, **partial**: dims the desktop too, as HazeOver does *(unverified)* |
| No borders, no gaps | gaps 0; title bars stay | **partial** |
| Maximize, fullscreen, restore (tide §6.3) | tilemo's own, on the same workspace (§5.4) | **yes**; native full screen is its own Space (§13) |
| Picture-in-picture pinned bottom-right on every workspace (tide §6.4) | left alone and never minimized (§5.5) | **partial**: its place is the app's |
| Dialogs float, centered | rules, subrole, fixed size and modality (§5.1) | **yes** *(unverified per app)* |
| Super+drag moves, Super+right-drag resizes (conf `hyprland.lua`) | an event tap on mouse buttons with Super held (§5.3) | **yes**, with Accessibility |
| Drag a tiled window's edge to set the split (tileco §5.3) | Accessibility's resize notification (§5.3) | **yes** |
| Drop a dragged tile on another to swap them (tileco §5.3) | Accessibility's move notification (§5.3) | **yes** |
| Super+middle-click maximizes the window under the pointer (tide §6.6) | the same event tap (§5.3) | **yes** |
| Resize mode for floats, Super+Shift+R (tide §6.6) | a tilemo key mode (§5.3) | **yes** |
| Focus follows mouse (KDE) | tilemo's own (§5.2) | **yes**, but focusing raises (§13) |
| Nothing steals focus (tide §14) | macOS activation rules, plus tilemo's focus guard (§14) | **partial**: apps can still activate themselves |
| Super+A lists the windows wanting attention, newest first (tide §14.4, tileco §10.3) | Dock badges, title counts, and apps activating themselves (§14.2) | **partial**: not every app says so |
| Minimize by key, restore from a tray of icons in the corner (tide's design) | `Super+Z` and an `hs.canvas` tray per display (§6.7) | **yes** *(unverified on a Mac)* |
| Full-width bar with workspaces and urgency (tide §7) | tilemo's own bar over an auto-hidden menu bar, with its own status items (§8) | **partial**: app menus and other apps' status items still need the menu bar revealed |
| SYD / LAX / NYC / LON clocks (tileco `src/clocks.js`) | bar clocks, and tileco's clock panel in the dashboard | **yes** |
| One switcher with tabs: launcher, workspaces, windows, attention (tide §8) | tilemo's switcher, an `hs.chooser`; the lone Super tap needs an event tap or Karabiner (§7, §9) | **yes** |
| Clipboard history and characters by name on Super+C (tide §8.4) | an `hs.pasteboard` watcher and an `hs.chooser` with two tabs (§9.1) | **partial**: text only, kept in memory, so not across a restart |
| Browser tabs in the Windows tab (tileco §9.4) | Chrome, Brave and Safari tabs through AppleScript (§2.5) | **yes**, with Automation granted |
| App keys (tide `hyprland.lua`, tileco §9.1) | global keys that bring an app's window, and its workspace, forward (§7) | **yes** |
| Second and third Chrome profiles (`browser2`, `browser3`) | separate `--user-data-dir`s, as tide runs them (§7) | **yes** |
| Notifications, history, DND (tide §9) | Notification Center and Focus | **yes**, native |
| Idle: dim, lock, off, suspend (tide §10) | Energy and Lock Screen settings; `caffeinate` or an IOPM assertion to keep awake | **partial**: system timings |
| Lock = login, short hostname | macOS lock and login | **partial**: no hostname |
| Screenshots, to the clipboard and a folder (tide §13) | macOS's own screenshot keys on tide's Print keys, and a watcher that copies each saved shot (§10) | **yes**, with macOS's file names |
| Meet: share a 16:9 slice of an ultrawide (tide §12) | ScreenCaptureKit can share a region *(unverified in Meet)* | **partial** |
| Light and dark by time (tide §15) | Appearance › Auto follows the sun; a fixed 07:00–19:00 needs a scheduled job | **yes**, with a job |
| US Dvorak | native input source | **yes** |
| Mouse: fastest, acceleration on, left-handed, wheel 3× (conf `hyprland.lua`) | Mouse settings and `com.apple.mouse.scaling` (§10) | **partial**: wheel scaling *(unverified)* |
| Touchpad: natural scroll, tap to click; mouse not natural | Trackpad settings (§10) | **partial**: one natural-scroll switch for both *(unverified)* |
| Key repeat: 600 ms, 25 a second | `InitialKeyRepeat` and `KeyRepeat` (§10) | **partial**: macOS's steps |
| Caps Lock as Compose | no Compose; Karabiner can map key sequences | **partial** |
| Setup checklist (tileco §3.4) | a settings page with deep links to System Settings panes (§10) | **yes** |
| Settings pages, shared `~/.config/tide` files, `.local` overrides (tide §16) | tilemo reads the same files (§15) | **partial**: Clocks, Layouts, Start at login, Clipboard and the muted list are built; Workspaces, Keys and the checklist aren't, and the standing workspaces and home's apps are still `start()` options |
| `tide doctor` (tide §5.4) | `tilemo doctor` (§15) | **yes** |
| Workspace swipe, three fingers (conf `hyprland.lua`) | no public gesture API (§13) | **no** |
| kitty, Ubuntu Mono, shell config | native, through `setup` and `conf` | **yes** |

## 5. Windows and layouts

- **Geometry:** tide's layout is pure Lua, and tileco's
  `src/geometry.js` is a tested port of it. The four layouts, the
  single-window rule and the share bounds carry over as they are:
  - tile, three-column, two columns plus a stack, and monocle (tide §6.1);
  - each workspace's own layout, `mfact` and master count;
  - the default by the display's shape: three-column from an aspect of
    2.1, tile below it;
  - a lone tiled window centered at 80% wide from 2.1, 60% from 3.2, and
    full width below 2.1;
  - floats and full-screen windows don't count toward "one window".
- **New windows join the end of the stack,** and the master stays put. A
  setting puts them at the top of the stack, after the focused window, or
  in as master (tide §6.1). A window moved in from another workspace, or
  tiled again after floating, counts as new. Amethyst's
  `new-windows-to-main: false` in conf agrees.
- **Applying a layout:** set position, then size, through Accessibility, and
  read the frame back. tileco reads its windows' bounds back the same way
  (tileco §5.3), and stores the difference per app, so the next layout
  allows for it. An app that refuses a size gets its own frame, and the
  rest tile around what it took *(design to settle)*.
- **When to retile:** when a window opens, closes, minimizes or comes back;
  when an app launches, quits or hides; when a display changes; and after
  any layout key. tilemo waits 50 ms after the last of a burst, as tileco does,
  since one window opening sends several notifications.
- **The mouse** can move and resize windows too (§5.3).

### 5.1 Floating windows and dialogs

Dialogs must float, and stay in front of the window that opened them.
Amethyst gets this wrong: it tiles some dialogs, such as autocomplete lists
(Amethyst#883), and hides others behind their parent (§5.2). tilemo decides
each new window once, in this order, and the first rule that matches wins.
The one exception is a new title: a tile whose title changes in its first
3 s is decided again, and floats if the rules now say so. A browser's popup
can open before its page names it, and a title rule needs that name.

1. **Not a window: ignore it.** Sheets (`AXSheet`) are attached to their
   window. Popovers, menus, tooltips and the menu bar aren't `AXWindow`s.
   tilemo never moves, focuses or counts any of them.
2. **A user rule** by app bundle ID and, optionally, title, as tide's float
   rules (tide §6.4). Rules come first so a misbehaving app can always be
   fixed. tilemo's own rules follow the user's: System Settings floats,
   since its width is fixed though its height isn't, so step 4 misses it
   and a tile would leave a gap beside it. Notification Center's windows
   are left alone, whatever they report: they're macOS's own, over every
   window. Bitwarden's pop-outs in Chrome and Brave float: its extension
   asks you to sign in, fill a login or use a passkey in a popup window
   titled "Bitwarden". The vault's own tab is titled otherwise, and the
   desktop app is another app.
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

- **A new float centers on its parent,** the app's focused window, or on its
  display if the app has none (tide §6.4). One that opens already placed,
  like a palette remembering its spot, keeps its place.
- **Floats stay above the tiles.** macOS has no public way to set another
  app's window level. Tiles never overlap, though, so the only thing that
  can cover a float is a tile being raised. When tilemo raises a tile, it
  raises that workspace's visible floats after it *(raising without focus
  unverified)*.
- **A float's size** is what it asks for, capped at 80% of its display
  (tide §6.4). tilemo remembers each app's float size and position until you
  log out.
- **Floats move with their workspace,** as tileco's do (tileco §6.1), and are
  minimized and restored with it. A dialog moves with its parent's
  workspace.
- **A dialog from the app you're in takes focus.** One from any other app
  opens unfocused and is marked for attention (§14).
- **Super+Shift+F toggles** a window between tiled and floating, as on tide
  and tileco.

Chrome's windows, from tileco §5.4 and tide §6.4:

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
- **Chrome Remote Desktop** and tileco's other URL rules can't be read from a
  window. A title rule stands in for each.

**Dialog checklist on a real Mac.** Each must open floating and centered on
its parent, and stay in front:

- TextEdit's Open and Save sheets;
- Chrome's Save As;
- an About window;
- System Settings opened from an app;
- an Electron app's dialog;
- a JetBrains IDE's dialog;
- Finder's Get Info window.

Bitwarden's passkey prompt, signing in to a site with a passkey saved in
Bitwarden's Chrome extension, must open floating too.

And each of these must be left where its app put it, never moved or
focused by tilemo: Chrome's find bar (Cmd+F), a tooltip, a link's status
bubble, a tab's hover card, Notification Center's banners and widgets,
and Control Center's panels.

### 5.2 Focus follows mouse

**What it should feel like** is tide's (tide §14.2), which is KDE's focus
follows mouse:

- Focus moves to a window when the pointer crosses into it, and nothing
  else moves it.
- Menus, popovers, dropdowns and dialogs stay open and in front while the
  pointer moves over, onto or off them.
- The pointer never jumps.

Amethyst is what `setup-macos` uses now, and its focus follows mouse had to
be turned off. Its bugs are listed below, so tilemo doesn't repeat them. It
isn't a model for anything else.

#### How tilemo decides

Each step either hands on to the next, or stops with focus left where it
is.

1. **Watch pointer moves only.** An event tap, under the Accessibility
   permission (§2.2), sees mouse-moved events.
   - Drags arrive as separate events, so a drag never moves focus.
   - tilemo never moves the pointer, so it never sees a move of its own
     making.
2. **Track the window under the pointer, and act only when it changes.**
   tilemo remembers which window the pointer was last over.
   - Moving within that window does nothing, even if focus went elsewhere
     by a key. Hyprland's `mouse_refocus false` does the same, and tide
     uses it.
   - When a window opens, closes or moves under a still pointer (a retile,
     a workspace switch), tilemo updates its record without focusing
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
   - **If the topmost thing isn't a window tilemo manages, tiled or
     floating, stop.** That includes a menu, popover, dropdown,
     autocomplete list or tooltip (these sit above the normal level
     *(unverified for every kind)*), the menu bar, the Dock,
     notifications, Spotlight, or tilemo's own bar.
   - This is the rule Amethyst misses. It looks only among the windows it
     tiles, so the tile under a popover gets focus and the popover closes
     (Amethyst#337, #1566, #1629, #1872).
   - tilemo checks each move against the part of the last window that no
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
   - So right after raising the window, tilemo raises its app's dialogs and
     then the workspace's other floats, in their previous order. A dialog
     can never end up behind the window that opened it, which Amethyst
     does (Amethyst#1243, #1026, #473).
6. **One focus in flight at a time.** Until macOS confirms the focus
   change, new moves update the target but don't start another. yabai
   holds back in the same way.
   - The next one starts the moment macOS confirms, or once the wait runs
     out, which can be before tilemo hears the report for the one before.
     So the focus guard (§14.1) takes every focus tilemo asked for in the
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
  auto-hidden menu bar's reveal edge, or over the Dock or tilemo's bar
  (Amethyst#1221).
- **While tilemo's switcher, name prompt or dashboard is open.** It keeps
  the keyboard until it closes (tide §14.2).
- **While an app that must keep focus is in front:** the screenshot picker
  (`com.apple.screencaptureui`) and password prompts
  (`com.apple.SecurityAgent`), from AutoRaise's own list. More can be added
  as a setting, by bundle ID.

#### Around the edges

- **Closing a window** focuses the window under the pointer, or else the
  last one used on that workspace. Something always has focus. Amethyst can
  leave nothing focused (Amethyst#1560). This is tide's
  `focus_on_close cursor`.
- **No warping, ever.** tilemo has no "mouse follows focus". `Super+J`,
  the switcher and a new window move focus, not the pointer, as on tide
  (tide §14.2). Amethyst's warp sends a fake pointer move that its own
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

| Amethyst bug | tilemo's rule |
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
- Typing into tilemo's switcher works with the pointer resting on a window,
  and again after moving it across two (tide §14.2).
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

These are tide's mouse bindings (conf `hyprland.lua`) and tileco's drag
handling (tileco §5.3):

- **Dragging a window's own edge or title bar works as on any Mac.** tilemo
  sees the result through Accessibility's `kAXMovedNotification` and
  `kAXResizedNotification`, and treats it as a request:
  - **Resizing a tile** sets the workspace's split (`mfact`), and its
    neighbors follow.
  - **Resizing a lone tile** sets that workspace's lone-window width in place
    of the single-window rule. It stays centered, so the other edge follows,
    and the width comes back whenever the workspace is down to one window.
    With several windows and no stack, a drag changes nothing.
  - **Dropping a moved tile** puts it in the tile nearest its center,
    swapping with that tile's window. If the center is on another display,
    the window first joins the workspace showing there.
  - **A moved or resized float** keeps its new frame.
- **Super+drag moves any window, and Super+right-drag resizes it,** from
  anywhere inside it, as on tide.
  - macOS has no built-in way to do this for every app, so tilemo watches
    mouse buttons with an event tap while Super is held (§2.2), which
    Accessibility covers.
  - A plain click passes straight through to the app. Only a press with
    Super held is taken.
  - Under the rotation, Super is Option (§7.1), and Option-drag means
    something in many Mac apps: Finder copies, and text editors select a
    column. With Karabiner's mapping (§7.1), Super+drag arrives with
    Ctrl+Option+Command held instead, so those stay the apps'. Without
    Karabiner, tilemo takes them.
  - A resize moves the edge or corner nearest the pointer.
  - When the drag ends, it's handled like a drag of the window's own edge
    (above). A drag on a tile sets the split or swaps tiles, and one on a
    float moves it.
  - **While dragging,** tilemo shows an outline where the window will go, and
    moves the real window when the button is released. Moving another
    app's window on every mouse event lags, since each move is a round
    trip to that app (§2.1). Hammerspoon's SkyRocket spoon draws the
    outline in the same way *(unverified)*.
- **Super+middle-click** maximizes the window under the pointer, or puts it
  back in its tile, as on tide (tide §6.6).
- **Super+Shift+R** enters resize mode for a float. In it, H J K L or the
  arrows resize the window, and Esc or Return leaves. This is tide's resize
  mode (tide §6.6). It needs only keys.
- **Focus follows the mouse during none of this** (§5.2). While a button is
  held, focus doesn't change.

### 5.4 One window big: monocle, maximize, full screen

These work as on tide (tide §6.3), on the same workspace:

- **Monocle** is a layout. Every window fills the tiling area, and
  `Super+J` and `K` flip between them. New windows open full size. The bar
  shows `[n]`, the hidden count.
- **Maximize** (`Super+Up`) covers the tiling area with just this window.
  It lasts until you press it again, close the window, or focus another
  window on the workspace.
- **Full screen** (`Super+Shift+Up`) covers the whole display, bar and all.
  It's tilemo's own: a move to the display's whole frame, which works
  over an auto-hidden menu bar *(unverified)*, not macOS's native full
  screen, which moves the window to a Space of its own (§13).
  An app's own native full screen (the green button) is left alone, and
  that window isn't on any tilemo workspace while it lasts.
- **`Super+Down`** puts it back in its tile from either.
- **macOS brings all of an app's windows forward** when the app is
  activated *(unverified for Accessibility focus)*. In monocle that could
  shuffle the stack, so tilemo puts the order back after each activation.

### 5.5 Picture-in-picture and always-on-top windows

- **Picture-in-picture** and a call's pop-out stay on every workspace.
  tilemo never tiles, minimizes or dims them (tide §6.4, tileco §5.4).
- They're spotted by subrole and app: Safari's and Chrome's
  picture-in-picture windows, and Meet's pop-out by title
  *(unverified per kind)*.
- **Their place is the app's.** Pinning them to the bottom-right corner, as
  tide does, would mean moving them again after each move of the app's own.

### 5.6 The dim

- **Strength 0.07,** as on tide (tide §6.2), set on the Appearance page.
- **Never dimmed:** a workspace with one visible window, a video playing
  full screen, picture-in-picture, and a screen-share preview.
- **How:** one dark layer just below the focused window, as HazeOver does
  (§2.4). That also dims the desktop, and the other display's windows.
  - A layer per other display isn't possible: tilemo can't place a layer
    between two other apps' windows.
  - The alternative, an outline round the focused window instead, is
    JankyBorders' (§13).

## 6. Workspaces

**Decided: minimize, as tileco does.** It uses only public API, so macOS
updates shouldn't break it. Mission Control shows only the workspace on
screen. Cmd+Tab still lists every app, but choosing one whose windows are
all hidden brings their workspace along (below), so no window turns up on
the wrong workspace. Two settings soften the costs, and the setup
checklist (§10) asks for both:

- **System Settings › Desktop & Dock › "Minimize windows into application
  icon"** keeps minimized windows out of the Dock, so hidden workspaces
  don't crowd it.
- **"Minimize windows using: Scale effect"** is quicker than the default
  Genie animation.

What it still costs is an animation on every switch, and switches slower
than the other two choices.

### 6.1 Model

This is tileco's model (tileco §6.1), which already solves minimizing on
chromeOS, with tide's named workspaces (tide §6.5) in place of nine
numbered ones:

- **Workspaces have names, not numbers.** A workspace exists once it has a
  name. The bar lists them by name (§8), in bar order: the standing
  workspaces, then the rest in the order they were made.
- **Standing workspaces** are a setting, `workspaces` in `start()` (§15),
  "in", "re", "oc" and "me" by default.
- **The first is the home workspace,** "in" by default. It's the first
  standing workspace that's special, not the name "in": whatever the list
  names first gets everything this spec says of "in". tilemo makes it at
  start. It can't be removed or renamed, holds the apps you keep open all
  day, and asks for a name for any other window (§6.2).
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
  bar order, so `Super+1` is "in", as `Super+Home` is (§7.2).
- **An empty workspace is removed once you leave it,** other than "in" and
  the standing ones. Leaving means no display shows it any more. A workspace holding only
  windows you minimized isn't empty.
- **Names are tilemo's own.** Its workspaces are minimized windows, not
  Spaces, so a name is just tilemo state, saved with the rest (§6.5). Two
  workspaces can't share a name; names are compared ignoring case
  *(a guess, to confirm)*, with Unicode's case folding for Latin, Greek
  and Cyrillic letters, so "Équipe" and "équipe" are one workspace.
- **A name has no quotes (`"`, `'`, `` ` ``), backslashes or control
  characters,** as on tide (tide §6.5).
  - A name reaches JSON, the bar's web view, logs, and `workspace.name`,
    which a script or a shell prompt prints (§6.3). Without those
    characters, no quoting can go wrong, and no escape sequence reaches a
    terminal.
  - A standing name with one is an error at load, naming the setting.
  - The prompt refuses one with a short notice and asks again. A launch's
    prompt comes back with them dropped.
  - A default name from a title drops them, as tide's short names do.
  - A tab or newline typed in a name is a space, as before, not a refusal.
- **Shared across displays.** Each display shows one at a time. Decided, as
  tide decided (tide §6.5): per display, not one desktop spanning every
  display.
- **Each workspace keeps** its windows in tile order, its layout, `mfact`
  and master count, and its focused window.
- **Each window belongs to one workspace,** and carries one flag: whether
  you minimized it yourself.
- **A new window joins the workspace showing** on the display it opens on.
  Two exceptions:
  - A window of one of "in"'s apps always opens on "in" (§6.2).
  - A window from a launch you made, which opens after you've moved to
    another workspace, goes to the workspace you launched it from instead,
    marked for attention (tide §14.2).
- **A new window opening on "in"** that isn't one of its apps asks for a
  workspace name first (§6.2).

**One rule decides what's on screen:** a window shows if its workspace is
showing on some display and you haven't minimized it. Every operation
changes only that state. Then one reconcile step makes the screen match:
it restores the windows that should show first, in tile order, and only
then minimizes the rest, so the screen is never empty in between.

| Operation | What changes | Focus |
|---|---|---|
| **Show** a workspace (the switcher's Workspaces tab, `Super+Return`'s prompt, `Super+Home` for "in", a bar click) on a display | That display shows it. If it was on another display, the two swap, as on tide. | its last focused window |
| **Move** a window to a workspace (`Super+Shift+Return`'s prompt, §7.2) | It moves to the end of that workspace's stack. A new name makes the workspace first, at the end of the list. Then that workspace shows on the display the window was on. | that window, as on tide |
| **Next or previous** (`Super+Left`, `Right`, `PgUp`, `PgDn`) | Show the one after or before, in bar order, stopping at the first and last. | as Show |
| **Carry** a window to the next or previous (`Super+Shift+Left`, `Right`) | Move, to the one after or before. | that window |
| **Activate**: an app key, the switcher, Cmd+Tab, a Dock click, a notification click | If the window's workspace isn't showing, show it on the focused display. | that window |
| **Moved to another display** by you | It joins the stack of the workspace showing there. | that window |
| **Minimize** by you (`Super+Z`, Cmd+M, the yellow button) | Set the flag. The window joins its display's tray (§6.7). | `Super+Z`: the workspace's last used window still showing; otherwise macOS decides |
| **Restore** by you, from the tray (§6.7), the switcher's Windows tab (§9), the Dock or Cmd+Tab | Clear the flag. If its workspace is hidden, this is Activate. | that window |
| **Hide** an app (Cmd+H) | Nothing: hidden apps are macOS's, and come back where they were. | macOS decides |

- **The current Mac setup follows a thrown window**
  (`follow-space-thrown-windows: true` in conf's `amethyst.yml`), and so
  do tilemo's Move and Carry, as tide's move does (tide §6.5).
  **Decided.**
- **A window that refuses** to minimize or restore is logged and skipped,
  so it can't stop a workspace switch. tilemo then stops managing it, as
  tileco does (tileco §6.4).

### 6.2 "in" and the name prompt

This is tide's (tide §6.5), on tilemo's own workspaces. "in" here means
the home workspace, the first standing one (§6.1), which is "in" unless
`workspaces` names another first.

- **"in" holds the apps you keep open all day:** mail, chat, calendar and
  music by default. Their windows always open there, and only theirs.
  - The list is a setting (§15), matched by app name, since Chrome's
    installed web apps each get a bundle ID of their own per install
    *(unverified)*. Which names stand for those four is a guess, to
    confirm: Mail, Gmail; Messages, Google Chat; Calendar, Google
    Calendar; Music, YouTube Music.
  - The list is tilemo's, not shared with tide: tide names apps by their
    Wayland app ID, which a Mac doesn't have.
  - **A list you set starts at login,** as tide's home starts its apps
    (tide §6.5): once a login, told apart as Start at login's list is
    (§15), each app by name with `open -g -a`, so none takes focus, in
    order, and before that list, which doesn't wait for them. An app
    already running isn't opened again, and one that won't open is a
    notification naming it. The two keep their logins apart, so a list
    file that can't be read doesn't hold home's apps back.
    - **tilemo's default list starts nothing.** It names a Mac app and a
      web app for each of the four, so it would open both, including
      Mail's and Messages' first-run setup on a Mac that uses Google's
      *(a guess, to confirm)*.
    - **Entries stay app names,** not tide's programs and web addresses
      (tide §6.5). A `chrome --app=URL` window on a Mac is Google Chrome's
      own, which tilemo can't tell from a browser window, so a web address
      would match nothing; Chrome's installed web apps have names of their
      own, which the list already takes. A `scripts` launcher such as
      `google-calendar` can go in Start at login's list (§15) instead.
  - A web app open in a plain Chrome tab isn't its app. Only the installed
    web app's own window counts.
  - Sending another app's window to "in" is refused, with a short notice
    *(a guess, to confirm)*.
  - Moving one of "in"'s windows elsewhere by hand is allowed: the rule
    says where they open, not where they must stay *(a guess, to
    confirm)*.
- **Any other window opening while you're on "in" asks for a name.** That
  includes a link a browser opens as a new window.
  - Dialogs and other windows that follow a parent (§5.1), and
    picture-in-picture (§5.5), don't ask: they go where their parent is.
  - The prompt is an `hs.chooser` listing the existing names, with a
    default name typed in and selected, as tide's is (tide §6.5). Typing
    replaces it or filters the list. Left, Right, Home and End keep it and
    move the cursor; `Up` and `Down` pick a row.
    - `hs.chooser` has no call to select its text. Its `show()` makes the
      text field first responder, which in AppKit selects the field's
      text, so tilemo shows it again whenever it changes the default.
    - A Mac text field's Home and End only scroll, so while the prompt is
      open Home and End are hotkeys sending `Cmd+Left` and `Cmd+Right`.
  - **Enter** makes the workspace, or uses the existing one of that name,
    moves the window there, and shows it. Focus follows.
  - **Esc closes the window,** politely, as the close-window key does
    (§7.2): Accessibility presses its close button, so the app can still
    ask to save.
  - A window's title often arrives after the window. The default follows
    the title until you type, or press Home or End *(a guess, to
    confirm)*.
  - Focus follows mouse pauses while it's open (§5.2), and the window
    stays put until you answer.
- **tilemo's own launches from "in" ask before launching:** the switcher's
  Launch tab, app keys and Cmd+Return (§9).
  - The process then starts with the right `TIDE_WORKSPACE` (§6.3), and its
    first window goes straight to the named workspace.
  - Esc cancels the launch, so nothing opens.
  - An app key for one of "in"'s apps doesn't ask.
- **The default name** comes from the window's title:
  - A setting holds a list of patterns, tried in order against the title.
    The first that matches gives its first capture, such as a ticket ID or
    a repository name.
  - Patterns are how to get a better name than the first word, such as an
    issue number or a project from a site's title.
  - With no match, it's the title's first word, as on tide (tide §6.5),
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
  - tide's shell is QML, so tide's are JavaScript's. The setting lives in
    tide's shared files (tide §16.1), and one list serves both desktops
    only if both read it the same way.
  - Lua patterns couldn't: they have no alternation (`a|b`), no `{n}`
    counts, and `%d` where JavaScript says `\d`.
  - tilemo runs them in JavaScriptCore through `hs.osascript.javascript`,
    once per prompt, not per keystroke. That's an OSA call of some tens of
    milliseconds *(unverified)*, and no permission.
  - **A bad pattern is an error at load,** naming the setting and the
    pattern. tilemo compiles each one when it starts and whenever the file
    changes, and keeps the last good list.

### 6.3 `TIDE_WORKSPACE`

- **The variable is tide's** (tide §6.5), with the same name, so conf's
  shpool and tmux startup reads one variable on every desktop.
- **Its value** is the current workspace's name with only its letters and
  digits kept, in any script, NFC-normalized, as on tide (tide §6.5):
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
- **tilemo sets it for the processes it launches.** On a Mac that takes
  more than one way, since an app launched through LaunchServices (`open`,
  the Dock, Finder) gets launchd's environment, not Hammerspoon's:
  - **Helpers** (`runenv`, §7.2) run through `hs.task`, whose
    `setEnvironment` sets it. So does anything they start directly.
  - **Apps** the helpers open with `open` get it through `open --env
    NAME=value`, added in macOS 13 *(unverified on macOS 26)*. That covers a
    new process only: `open -na` starts one, as the browser keys do, but
    an app that's already running gets nothing.
  - **kitty** on Super+T: Cmd+N to a running kitty starts a shell with
    kitty's environment from when it launched. tilemo instead asks kitty
    for the window through its remote control, `kitten @ launch
    --type=os-window --env TIDE_WORKSPACE=…`. With no socket, it falls
    back to Cmd+N, and the shell reads the name from tilemo's file
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
    - **tilemo checks before it connects.** It takes the socket only if
      the socket and its folder are owned by your user ID, and no one else
      can write to the folder (`kitty.lua`). Anything else is refused, with
      a notice saying why, and the window comes from Cmd+N. Remote control
      runs anything as you, and tilemo sends the workspace's name, so a
      socket someone else made is never used.
    - Your user ID comes from one `id -u`, the first time there's a socket
      to check.
- **A running process can't see later changes.** It keeps the name it
  started with, after a rename or a move to another workspace, as on tide.
- **Scripts read the current name from a file:**
  `~/Library/Caches/tilemo/workspace` holds `TIDE_WORKSPACE`'s value, and
  `workspace.name` beside it holds the name as it shows, each ending in a
  newline. `cat ~/Library/Caches/tilemo/workspace` gives it.
  - tilemo writes both whenever the current workspace changes. Each is
    written whole: a temporary file, mode 600, renamed over the last.
  - The folder is mode 700, so only you can read them.
  - **Not Hammerspoon's IPC:** `hs.ipc` opens a port that runs any Lua a
    local process sends it, with tilemo's Accessibility grant, so tilemo
    never loads it. A config of your own that loads it is your choice.
  - Reading the file costs no process and no round trip, so it's fine
    even in a prompt.
  - With tilemo not running, the file says the last workspace it showed.
  - The cost is nothing in money, and no network.

### 6.4 Displays

- **A display that goes away,** from a lid closing or a cable coming out,
  hands its workspaces to the remaining display, as on tide (tide §6.5).
  Its windows move with them. They stay put when it comes back; Show puts
  any workspace on it.
- Each display is keyed by its UUID, so its settings follow it from port to
  port, as tide keys displays by description (tide §16).
- **A new workspace** from the name prompt shows on the display the window
  opened on.

### 6.5 Restarts and saved state

- **When an app quits and relaunches,** its windows come back with new IDs.
  tilemo matches each to its old place by app and title, closest first, as
  tileco matches by tab addresses (tileco §14.2). A window it can't match joins
  the workspace showing.
- **If tilemo quits,** it restores every window it hid first, so nothing is
  left stranded in the Dock.
- **If it crashes,** the next start restores what it can't place and
  reconciles the rest. `tilemo restore` does it by hand (§16).
- **What's saved:** `hs.settings`' `tilemo.state` names each window's
  workspace, and each display's, by name, and keeps the list of names in
  order.
- **Moving on from numbered workspaces:** a saved state whose workspaces
  are numbers is read once, then saved by name *(a guess, to confirm)*:
  - each numbered workspace with windows becomes one named by its number,
    "1" to "9", in that order after "in" and the standing workspaces;
  - a window of one of "in"'s apps goes to "in" instead;
  - an empty number is dropped;
  - a display showing a number shows that workspace, or "in" if it was
    dropped.
  - The same holds for timo's state, which tilemo still reads (README).

### 6.6 Mission Control settings

The checklist (§10) sets these, and undoes `setup-macos`'s nine Spaces:

- **One Space per display.** tilemo doesn't use the rest.
- **"Displays have separate Spaces"** stays on, the default.
- **"Automatically rearrange Spaces based on most recent use"** off
  (`mru-spaces`), as `setup-macos` sets it now.
- **Stage Manager** off, since it groups windows itself.
- **Sequoia's tiling:** "Drag windows to screen edges to tile" off, and
  "Hold Option key while dragging windows to tile" off. With Super as
  Option, the second would fight Super+drag (§5.3).
- **"Click wallpaper to reveal desktop"** set to "Only in Stage Manager".

### 6.7 Windows you minimized

**Decided: floating icons in the bottom-right corner,** option C of tide's
mock of five (tide's `docs/mocks/minimized.html`), as tide does.

- **`Super+Z` minimizes the focused window** (§7.2).
  - Decided over `Super+Delete`: a PC keyboard's Delete can arrive as
    forward delete or as Backspace, and `Super+Backspace` already closes
    the window.
  - It sets the window's flag (§6.1), so the window stays down when its
    workspace comes back, and focus moves to the workspace's last used
    window still showing.
  - Floats and dialogs minimize too. A window tilemo doesn't manage is left
    alone.
- **Only windows you minimized count.** tilemo minimizes windows itself to
  hide the other workspaces, and those never show here. `wm.lua` flags
  yours as `mine`: from `Super+Z`, Cmd+M, the yellow button, or a window
  already minimized when tilemo first saw it. The tray and the Windows tab
  read that flag, not macOS's minimized state.
- **The tray** sits in the bottom-right corner of each display, 12 px in
  from the edges of its work area, over the Dock's side of the screen:
  - one app icon per window you minimized from the workspace showing on
    that display, 28 px, in a row on the bar's background, 5 px of padding
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
  quitting tilemo leaves your minimized windows down, restoring only the
  ones it hid (§6.5).

### 6.8 The alternatives, to revisit if minimizing doesn't work out

1. **Native Spaces, one per workspace:**
   - Switching uses symbolichotkeys, as `setup-macos` does now.
   - Spaces have no names in any public API, and each has to exist first,
     so named workspaces made on demand fit them poorly.
   - Sending a window uses the private calls Amethyst and yabai use.
   - It matches the user's current Mac, Cmd+Tab stays honest, and full
     screen works.
   - The costs: the animation, Spaces created by hand, and a private call
     that may break.
2. **Emulated, AeroSpace-style:**
   - Switching is instant, there's one shared pool across monitors, and
     tide's model fits exactly.
   - The cost is Cmd+Tab and Mission Control showing everything. That's the
     reason `setup-macos` turned AeroSpace down.
3. **Minimized, tileco-style:** the choice above.

Revisit if switching is too slow even with the Scale effect, if apps restore
from minimize in the wrong place or size, or if a window refuses to
minimize, which tileco had to handle on chromeOS (tileco §6.4). Native Spaces
come first then, since Cmd+Tab stays honest with them. The private call is
the risk, and it breaks about once a year at a major macOS release *(from
memory, not counted)*.

## 7. Keys

### 7.1 Where Super comes from

- **tide's map, everywhere.** tide and tileco differ where chromeOS can't
  bind a key (tileco §7.1), but macOS can bind all of tide's, so tilemo follows
  tide (tide §6.6).
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
  else uses** (Ctrl+Option+Command+key), and tilemo registers that. Karabiner
  sees the physical key before the rotation (conf
  `config/karabiner/README.md`), so Option's own meanings stay intact.
  Depending on Karabiner is accepted, but tilemo must work without it.
  - Karabiner needs an admin, once, and IT can block it (§11).
- **Without Karabiner, tilemo falls back,** rather than leaving keys dead:
  - **How it tells:** at start, and whenever Karabiner starts or stops,
    tilemo checks that Karabiner is running and has tilemo's rules loaded
    *(how to check unverified: its background process, and its config
    file)*.
  - **The keys:** tilemo registers the same map on plain Option instead. Every
    key still works, at the cost of Option's text gestures above.
  - **The Super tap:** an event tap, if Input Monitoring is granted, or
    Super+Space alone if not (§7.2).
  - **Super+drag:** on Option, so Finder's Option-drag copy goes to tilemo
    (§5.3).
  - **It says so once,** in a notification naming what's lost and how to
    fix it. The checklist (§10) and `tilemo doctor` (§15) report it too.
  - **When Karabiner comes back,** tilemo moves its keys back to Karabiner's
    combinations, with no restart.
- **The rotation covers every keyboard,** the MacBook's own included. If
  that's wrong for the built-in keyboard, `hidutil` can match PC keyboards
  alone *(unverified)*. That's a question for `setup-macos`.

### 7.2 The map

tilemo registers each with `RegisterEventHotKey`, which needs no permission
(§2.2). The second column is what macOS sees once Karabiner has mapped it.

| Keys | Action | How |
|---|---|---|
| tap `Super` | the switcher, on its Workspaces tab (§9) | Karabiner's tap rule, sending `Super+F20`; or tilemo's event tap (below) |
| `Super+Space` | the switcher, on its Launch tab | hotkey |
| `Super+Tab` | from any workspace, "in"; from "in", the workspace you used last. Pressed again, it flips back | hotkey |
| `Super+End` | the workspace you used last other than "in" and this one: from "in" where `Super+Tab` goes, from another the one before it | hotkey |
| `Super+A` | the switcher, on its Attention tab (§14.2) | hotkey |
| `Super+Shift+Space` | dashboard (§8) | hotkey |
| `Super+Alt+Space` | next input source | macOS's own "Select next source" *(unverified key)* |
| `Super+T` / `W` / `V` / `G` / `F` / `Shift+G` / `E` / `B` / `Shift+B` / `Shift+C` / `H` / `I` / `M` / `N` / `R` / `Y` | app keys (below) | hotkey |
| `Super+C` | the picker, on its Clipboard tab: what you've copied, and characters by name (§9.1). It was Google Calendar, which has no key now: it's one of "in"'s apps (§6.2), and the switcher finds it | hotkey |
| `Super+Backspace` | close the window | hotkey; Accessibility presses its close button |
| `Super+Z` | minimize the window, to the tray (§6.7) | hotkey |
| `Super+L` | lock | hotkey; macOS's lock screen |
| `Super+S` | keep awake on or off (§10) | hotkey; `hs.caffeinate`, with an on-screen sign |
| `Super+P` | presenter mode: Do Not Disturb and keep awake together (§10) | hotkey; keep awake as `Super+S`, Do Not Disturb through two shortcuts you make in Shortcuts |
| `Super+Shift+E` | log out | hotkey; System Events, which asks first |
| `Super+Home` | show "in" (§6.2) | hotkey |
| `Super+Left` / `Right`, `Super+PgUp` / `PgDn` | previous / next workspace | hotkey |
| `Super+Shift+Left` / `Right` | carry the window to the previous / next workspace | hotkey |
| `Super+J` / `K`, with Shift | focus / move down and up the stack | hotkey |
| `Super+Return` | go to a workspace, by name (below); it moves no window, so it works with none focused | hotkey |
| `Super+Shift+Return` | move the window to a workspace, by name (below), and follow it there; with no window focused, nothing | hotkey |
| `Alt+Tab` | swap with the master; on the master, swap with the previous master | conf's Karabiner rule turns physical Alt+Tab into `Ctrl+Option+Shift+Tab`, which tilemo registers (below) |
| `Super+\` / `Super+/` | grow / shrink the master (`mfact` ±0.025), repeating | hotkey |
| `Super+=` / `Super+-` | add / remove a master | hotkey |
| `Super+.` / `Super+,` | next / previous layout | hotkey |
| ``Super+` ``, `Super+O` | monocle | hotkey |
| `Super+Up` / `Super+Shift+Up` / `Super+Down` | maximize / full screen / restore (§5.4) | hotkey |
| `Super+Shift+F`, `Super+Insert` | float or tile | hotkey |
| `Super+Shift+R` | resize mode for a float (§5.3) | hotkey, then plain keys until Esc |
| `Super`+drag, `Super`+right-drag, `Super`+middle-click | move, resize, maximize (§5.3) | event tap |
| `Super+Shift+N` | Notification Center | no public way to open it *(unverified)*; else the clock in the menu bar |
| `Print` / `Alt+Print` / `Shift+Print`, `Super+Print` | screenshot screen / window / region, Super+Print a region too (§10) | hotkey on F13, which a PC keyboard's Print sends *(unverified)* |
| mic-mute key, `Super+Shift+M` | mute the microphone, everywhere | tilemo, through `hs.audiodevice`'s input mute on the default input device, with an on-screen sign; the bar's microphone item does the same |
| media, brightness, volume keys | as macOS does them | native |

- **The Super tap** must not fire after Super+T, Super+drag or
  Super+click (tide §8). A mouse button or scroll counts as "another key"
  in between.
  - An event tap needs Accessibility and maybe Input Monitoring (§11). A
    Karabiner rule (`to_if_alone` on physical Win) avoids both.
  - Karabiner's rule is the better of the two here: it sees the physical
    key, and needs neither permission. tilemo's own tap is the fallback.
  - The rule sends the tap as `Super+F20`, a key no keyboard here has, so
    it's told apart from `Super+Space`.
- **`Super+1…9` and `Super+Shift+1…9` count along the bar,** as on tide
  (tide §6.6). `Super+N` shows the Nth workspace in bar order, home first,
  so `Super+1` is "in"; `Super+Shift+N` sends the focused window there,
  with focus staying where you are. A number past the last workspace does
  nothing. A number is a position, not a name.
- **`Super+Tab` and `Super+End` remember the workspaces you've shown,**
  most recent first, across displays. A workspace that's gone since is
  passed over, and either key does nothing with nowhere to go.
- **`Super+Return` goes to a workspace,** with tide's prompt (tide §6.5):
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
  name is new, and follows it: that workspace shows on the display the
  window was on, with the window focused, as on tide. Esc leaves it where
  it is. This is Move (§6.1).
  - With no window focused there's nothing to move, so it does nothing,
    and Hammerspoon's console says why.
- **`Super+Return` used to move the window,** as tide's did. Both moved it
  to `Super+Shift+Return`, which nothing else used, so `Super+Return`
  works with no window to move.
- **`Alt+Tab` takes `Super+Return`'s first job,** the master swap. It
  makes the focused window the master. On the master, it swaps with the one that was master before.
  - Under the rotation, physical Alt sends Control, so physical Alt+Tab
    arrives as Ctrl+Tab, which is the apps' own next tab (scripts
    `docs/MACOS.md`, "The one binding the rotation inverts").
  - **Decided:** physical Alt+Tab gives up its job as Cmd+Tab, macOS's app
    switcher. conf's rule used to make it Cmd+Tab; now tilemo's Karabiner
    rule sends it as `Ctrl+Option+Shift+Tab`, a combination nothing else
    uses, which tilemo registers. Physical Ctrl+Tab stays the apps' next
    tab.
  - So physical Alt+Tab no longer switches apps. The switcher's Windows
    tab (§9) stands in. So does physical right Ctrl+Tab, on a keyboard
    that has a right Ctrl: the rotation makes it Cmd+Tab, and conf's Tab
    rule only takes left Ctrl.
  - A Mac keyboard's Cmd+Tab doesn't switch apps. `setup-macos` applies
    the rotation to every keyboard, the built-in one included, so its
    Command key sends Option.
  - Without Karabiner, tilemo doesn't take Ctrl+Tab, since that would take
    every app's next tab. Swap with the master has no key then *(a guess,
    to confirm)*.
- **App keys** are tide's (conf `hyprland.lua`). Each brings the app's
  window forward, launching the app if it has none, and brings its
  workspace with it (Activate, §6.1).
  - From "in", a key that would launch asks for a workspace name first,
    unless the app is one of "in"'s (§6.2). Esc cancels the launch.
  - **Super+T opens a new kitty window every time,** on the workspace
    you're on, as tide's terminal key does: Cmd+N to a running kitty, or a
    launch.
  - Browser profiles run with their own `--user-data-dir`, as tide's
    `browser2` and `browser3` do.
  - Web apps are installed web apps, which have their own Dock icons and
    badges (tileco §3.5).
  - Helpers run through the login shell's environment. Apps started from a
    key inherit launchd's short `PATH`, which tide met as "PATH missing in
    keybinds" (tide §17).
- **The Keys page** in tilemo's settings lists every binding live, as tide's
  does (tide §16).

### 7.3 Taking keys from the system and the old setup

`RegisterEventHotKey` fails silently on a key someone else holds (§2.2), so
`setup-macos` has to free these first:

- **symbolichotkeys:**
  - 118–126 (Option+1…9, "Switch to Desktop N"), set by `setup-macos` now;
  - 64 (Spotlight on Option+Space): Spotlight moves back to Cmd+Space,
    physical Ctrl+Space;
  - 79 and 81 (Ctrl+Option+arrows, move a Space left and right).
- **Amethyst:** retired once tilemo takes over (§19, question 4), and conf's
  `amethyst.yml` with it. Its `mod1`-`mod4` combinations go.
- **Rectangle:** `setup` installs it too, and its defaults sit on
  Ctrl+Option+arrows *(unverified)*. It goes.
- **Karabiner's Win+arrow rule** sends Ctrl+Option+arrow for native Spaces
  and Win+Shift+arrow for Amethyst's throw. Both now go to tilemo.
- **Karabiner's Alt+Tab rule** sent Cmd+Tab. It goes to tilemo's swap
  with the master instead (§7.2).
- **Super+Shift+N sent to workspace N.** Those keys are gone (§7.2), so
  `setup-macos`'s Super+Alt+N go with them.

## 8. Bar, clocks and dashboard

- **The menu bar stays the system's.** Two ways to live with it:
  - **Option 1:** the bar is a tilemo panel along the top, with the menu bar
    set to hide automatically. It shows the workspaces, the layout symbol,
    the title and the clocks, as tide's does (tide §7). The cost: the
    system's status items (Wi-Fi, battery, volume) and the app's menus show
    only when the pointer reaches the top edge.
  - **Option 2:** no bar. The workspaces and clocks go in the menu bar's
    right side as status items, plus a full-screen dashboard on a key, as
    tileco's is (tileco §8.1).
  - **Decided: option 1, with tilemo's own status icons.** The menu bar is
    set to hide automatically (System Settings › Control Center ›
    "Automatically hide and show the menu bar": Always, or
    `defaults write NSGlobalDomain _HIHideMenuBar -bool true`). tilemo's bar
    takes the top 36 px of each display, and draws the common status items
    itself (below), so they don't need the menu bar revealed.
  - **What still needs the menu bar:** the app's own menus, the Apple menu,
    and other apps' status items (a VPN, an IT agent, Zoom). They show when
    the pointer reaches the top edge, over the bar, which sits below the
    menu bar's level.
  - **Option 2 stays as the fallback,** with `bar = false` in `start()`: a
    tilemo menu bar item draws the workspaces' names as text, current,
    occupied, and wanting attention, with no app icons. A click switches. It sits on the right, since
    the menu bar's left side is the Apple menu and the app's menus.
  - Either way, the workspace's name shows briefly, large, in the middle
    of the screen on each switch.
- **If it's a bar, it's tide's** (tide §7.1–§7.4):
  - a flush 36 px strip, one per display, with the tiling area starting
    below it;
  - **tide's logo first,** two waves in the accent color, as on tide
    (tide §7.1). A click opens the switcher on Launch, as `Super+Space`
    does, or closes it if it's open, on any tab. It opens where
    `Super+Space` opens it, on the display with the focused window, not
    always the clicked bar's: `hs.chooser` centers itself there *(a
    guess, to confirm on two displays)*;
  - workspace chips in list order, each with its name, that show current,
    occupied, showing on another display, and wanting attention. A long
    name is cut with an ellipsis at 16 characters *(a guess, to confirm)*. The only empty chips are "in" and
    the standing workspaces, dimmed: any other empty workspace goes once
    you leave it (§6.1);
  - **no app icons, except for attention.** Decided with tide: a chip is
    its name alone, plus the app icon of each window there wanting
    attention (§14.2), up to five, then `+n`. A click on that icon focuses
    the window, bringing its workspace along. The chips used to show an
    icon per window, which crowded the bar once workspaces had names;
  - a click elsewhere on a chip shows that workspace, and scrolling steps
    through them;
  - the title only on the display the focused window is on, where
    double-clicking it maximizes, and hovering it shows it uncut, as on
    tide (tide §7.1);
  - the clocks shrink to local time alone when the title would get narrower
    than 200 px.
- **The bar on Hammerspoon** is built like the dashboard: one borderless
  `hs.webview` per display, from the same copies of tileco's modules and
  stylesheet, plus tilemo's `bar.js`. It stays open, and tilemo sends it new
  state as JSON on every change, on the attention poll (for titles that
  change without focus moving) and when the icons change. Each page only
  redraws when what it was sent changed.
  - A chip shows one app icon per window there wanting attention, tiles
    in layout order then floats, up to five, then `+n`. Icons come from
    `hs.image.imageFromAppBundle`, sent as 32 px PNG data URLs, made once
    per bundle id and sent once per app, not per window. An app with no
    icon shows as a blank square, so the count still reads.
  - A click on an icon names its bar's display and the window. tilemo shows
    the window's workspace on that display if it isn't showing anywhere,
    then activates the window (§6.1).
  - Double-clicking the title, or the free bar around it, maximizes the
    focused window, or puts it back (§5.4), as a Mac's title bar does. The
    message names its bar's display, and tilemo acts only if the focused
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
    shows as a rounded rect, half pressed: tileco's `--hover`, a shade
    darker than the bar in light and lighter in dark. A chip shows with
    the space around it, a window icon as its own, the title as the free
    bar, a status item with its text, the logo, and the clocks as one row. The
    rounding is drawn, not hit-tested, so it moves no click. WebKit
    follows the pointer only in the key window, which the bar never is
    (WebKit's `trackingAreaOptions` in `WebViewImpl.mm`), so `:hover`
    doesn't fire there: tilemo's pointer tap tells the bar it's over where
    the pointer is, one small script per move over a bar, and the page
    marks that target. There's no appearance (dark mode) item in the bar.
  - **Hovering the title shows all of it** in a tip below the bar,
    centered on the title, since the bar cuts a long one with an ellipsis.
    It wraps past 600 px. The page can't draw past its own strip, and a
    `title` attribute's tooltip needs WebKit to follow the pointer, which
    it doesn't here (above). So the page tells tilemo the title and where
    it is when the hovered target becomes the title, and that it's gone
    when it stops being; tilemo draws the tip as an `hs.canvas`, as the
    tray's tips are (§6.7). With no title there's no tip. The tip goes
    with its bar: when that bar hides for a full-screen window, its
    display is removed, or it moves.
  - **Every other tip takes the same path,** centered on its item: a
    status item's (its state, the Wi-Fi network's name, the battery's time
    left), the camera's, though it's no click target, and a chip's whole
    name when the chip cuts it. A whole name has no tip, nor does a window
    icon. The page keeps each tip in `data-tip`, not `title`, so no
    WebKit tooltip could ever show beside tilemo's.
  - A first click isn't spent on bringing Hammerspoon forward:
    `hs.webview`'s view accepts the first mouse (its `acceptsFirstMouse`
    returns yes, in Hammerspoon 1.4.27's `libwebview.m`), so it reaches the
    page.
  - It floats above every app's window but below the menu bar, joins every
    Space, and stays put.
  - Focus follows mouse pauses over it, as over the menu bar (§5.2).
  - The bar hides on a display while a window there is full screen, and
    comes back after: tilemo's full screen (§5.4) on that display's
    workspace, or the focused window in macOS's own full screen on that
    display. macOS's is only known for the focused window *(unverified
    how a swipe away from its Space shows to tilemo)*.
- **tilemo's status items** are 16 px line drawings in the text color,
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
    awake", as tide's hover does (tide §10).
    **While presenter mode is on** (§10) it's a filled accent pill reading
    "Presenting", as tide's Presenting pill is, and a click ends presenter
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
  - Bluetooth: on or off, as tide's: one glyph, faint while off and in the
    text color while on. A click opens Bluetooth settings.
    - Hammerspoon has no module for it (there is no `hs.bluetooth`), so
      tilemo asks `blueutil -p` (Homebrew's `blueutil`, which scripts'
      `setup-macos --wm tilemo` installs), found at `/opt/homebrew/bin` or
      `/usr/local/bin`, since Hammerspoon's PATH has neither.
    - It runs through `hs.task`, never waiting on it, one run at a time:
      as tilemo starts, on wake, and every 30 s. tilemo has no Bluetooth
      switch of its own, so nothing else changes it from here.
    - Hidden with no `blueutil`, no adapter, or any failure, and the log
      says why once, until the reason changes or clears. The headphones
      icons don't need it.
    - **Cost and reliability:** free and open source, from Homebrew. One
      short process every 30 s. A missing or failing `blueutil` only hides
      this icon.
  - headphones: one per connected Bluetooth audio device, as tide's
    headphones icons are (tide §7.4). They're `hs.audiodevice`'s output and
    input devices whose transport is Bluetooth, which macOS lists only while
    connected; a headset is both, and gets one icon. Hovering one names it.
    A click opens Bluetooth settings. No battery: `hs.audiodevice` doesn't
    read one.
  - speaker: the default output device, in four levels with mute. A click
    mutes or unmutes; scrolling on it changes the volume 5% a step, and up
    unmutes, as the volume keys do.
  - network: Wi-Fi through `hs.wifi`, on or off with signal in three bars
    from the RSSI, or a wire, or no network, by which interface
    `hs.network.primaryInterfaces` says carries traffic. The Wi-Fi
    network's name shows on hover only when macOS gives it, which needs
    Location Services on recent macOS *(unverified for Hammerspoon)*.
  - battery: `hs.battery`, with its percentage and a charging mark, and on
    hover how long until full or empty when macOS knows. None on a Mac
    without one.
  - The battery, network, Bluetooth and headphones items open their System Settings panes, named
    by URL (`x-apple.systempreferences:…`) *(unverified on macOS 26)*.
- **Not drawn:** Focus (Do Not Disturb). Hammerspoon has no module for it
  (there is no `hs.focus`). Its menu bar item shows when the menu bar is
  revealed.
- **The notch,** on a MacBook's own display, sits where tide centers the
  title. There, the title moves left of it *(unverified how wide it is per
  model)*.
- **Status icons:** macOS's orange and green dots already show the
  microphone and camera in use, which covers tide's privacy pills
  (tide §7.4). The microphone-mute state from `Super+Shift+M` shows in the
  bar, since macOS has no system-wide mute of its own.
- **Clocks:** tileco's `src/clocks.js` and `calendar.js` hold the zone,
  daytime-strip, DST and calendar logic, all tested. A native tilemo would port
  them.
  - **Which clocks** is tide's setting, read from tide's `clocks.json` and
    `clocks.local.json` (§15) with tide's own module, `shell/lib/clocks.mjs`,
    copied unchanged as `dashboard/tide-clocks.js` and checked against
    tide's in CI. With neither file, they're tileco's: Sydney, Los Angeles,
    New York and London. A label of `"abbr"` shows the zone's abbreviation
    from Intl, which says `GMT+1` for London in summer (tide §7.3).
  - tide's `hour24` and `dedupeLocal` switches are read but not followed:
    tileco's clock view is always 24-hour and always hides the local zone.
  - A file that's wrong keeps the clocks as they were, and a notification
    says which file and why, once. tilemo keeps the last good clocks the
    pages loaded, so a page opened while a file is wrong shows them too.
- **The dashboard, on Hammerspoon,** is a borderless `hs.webview` over the
  display you're on, from `Super+Shift+Space`:
  - It shows tileco's bar (the workspace chips, by name alone, the focused
    window's title, the clocks) over tileco's clock panel: each zone's day strip, the next
    DST change, and a month calendar.
  - tileco's `clocks.js`, `calendar.js`, `clockview.js` and `launcher.css` are
    copied unchanged, and CI checks they still match tileco's.
  - A webview can't load ES modules from files, so tilemo joins them into one
    script, each module in its own scope.
  - A click on a workspace's chip shows it. Esc, the key again,
    or clicking away closes it.
  - The switcher stays `hs.chooser` (§9), so the dashboard has no search.
  - Focus follows mouse pauses while it's open (§5.2).

## 9. The switcher

**One overlay, with tabs,** as tide's (tide §8): the launcher, the
workspaces, every window, and the windows wanting attention. It's the
launcher's `hs.chooser` with tileco's scopes (tileco §9.4), one scope per
tab, the search field naming the tab you're in.

- **The search field's hint names only the keys that work on that tab,**
  as tide's footer does (tide §8.1): `Tab` and the tab it goes to on all
  four, `Cmd+Return`'s new workspace on Launch, and `Cmd+M`'s mute on
  Windows and Attention. Elsewhere `Cmd+Return` does what Return does, and
  `Cmd+M` has no row to mute. `hs.chooser` has no footer, so the hint is
  the one place to say it.

- **Tabs,** in this order *(the order is a guess, to confirm)*:
  - **Launch:** apps, System Settings' panes and tilemo's commands.
  - **Workspaces:** every workspace by name, in bar order, with its app
    icons and where it's showing, the standing ones included before they
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

  An empty tab says so, in a row that can't be chosen.
- **Each key opens it on its own tab:** `Super+Space` on Launch, the
  Super tap on Workspaces, `Super+A` on Attention (§7.2). `Super+Tab`
  doesn't open it: it flips between "in" and the last workspace. The Windows tab has no key of its own *(a guess, to confirm)*.
- **`Tab` and `Shift+Tab` move between tabs,** forward and back, as the
  scopes do now.
- **A switcher key pressed while it's open** closes it if it's on that
  key's tab, as tide's second Super tap closes its launcher (tide §8), and
  otherwise moves to that tab *(a guess, to confirm)*. Esc closes it.
- **Where the rows come from:**
  - **Apps** come from `/Applications` and `~/Applications`, with the folders
    in them (vendor folders, Chrome's web apps), `/System/Applications` and
    its Utilities, `/System/Library/CoreServices/Applications` (Archive
    Utility, Screen Sharing, …) and Finder. Not Spotlight's index, which
    would also bring installers and the helper apps inside other apps.
  - **Settings panes** are the app extensions in
    `/System/Library/ExtensionKit/Extensions` that plug into System Settings
    (`com.apple.Settings.extension.ui`), listed as "Mouse settings" and so on,
    and opened with their `x-apple.systempreferences:` URL. Read once a start,
    since only a macOS update changes them.
  - **Workspaces, windows and attention** are tilemo's own state, so they
    cost nothing to list.
  - **`Cmd+M`, or a right-click,** on a row in the Windows or Attention tab
    mutes its app or site, or unmutes it (§14.2).
  - **Browser tabs** come from Chrome, Brave and Safari through AppleScript, run
    by `/usr/bin/osascript` as an `hs.task` rather than `hs.osascript`,
    which would hold Hammerspoon until the browser answers (§2.5).
  - **A tab's workspace** is its window's. AppleScript's window numbers
    aren't Accessibility's, so tilemo finds the window by its name, which
    both give *(unverified that they always agree)*.
  - **Choosing a tab** addresses its browser window by AppleScript's window
    id, collected with the tabs, not its number, which changes as soon as
    tilemo raises the window.
- **Browser tabs, cost and reliability:**
  - **Permission:** macOS asks once per browser for Automation, the first
    time the Windows tab lists its tabs (§11.1). Refused, that browser's
    windows still show, without their tabs.
  - **Latency:** each call is an Apple Event round trip to the browser,
    slower with many tabs, and slow or stuck while the browser is busy
    *(unverified how slow)*. So tilemo asks when the switcher opens, shows
    the windows at once, and adds the tabs when they arrive. The call gets
    a 2 s timeout, and a browser that misses it is skipped this time.
  - **A browser that isn't running** isn't asked, since an Apple Event to it
    would launch it.
  - **Cost:** nothing in money, no network, and no work at all while the
    switcher is closed.
- **Matching:** tileco's fuzzy match and ranking (`src/launcher.js`), with
  the most used and most recent first, and tide's empty-query sections
  (tide §8). Text matching nothing in a tab searches all of them, so a
  window or a tab still turns up from Launch.
- **Quick actions, as tide's** (tide §8): screenshot the window, screen or
  a region; lock, log out, sleep, restart, shut down; Do Not Disturb,
  keep awake, presenter mode, and dark style; tilemo's settings; reload
  tilemo.
- **Launching from "in" asks for a workspace name first** (§6.2), so the
  app starts with the right `TIDE_WORKSPACE` (§6.3). Esc cancels the launch.
- **Cmd+Return** (physical Ctrl+Enter) runs the app on a new workspace, as
  Ctrl+Enter does on tide: it asks for a name first, from any workspace,
  since there's no empty one to use (§6.1).
- **The window before the switcher** gets focus back if you dismiss it, and
  is the window "screenshot window" captures (tide §13).
- **Kept out of screen shares,** as tide keeps its launcher out (tide §12),
  by marking tilemo's windows unshareable (`NSWindow.sharingType`)
  *(unverified that screen sharing still honors it on macOS 26)*.
- **Spotlight stays** on Cmd+Space, physical Ctrl+Space (§7.3). In macOS
  26, tilemo's commands can also appear there as App Intents (§2.6).

### 9.1 The picker

**`Super+C` opens tide's picker** (tide §8.4): its own `hs.chooser`, with
two tabs. C is for clipboard and characters.

- **Clipboard:** what you've copied since tilemo started, newest first,
  one line each, searched with the switcher's fuzzy match.
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
  - **In memory only,** the newest 200, or as many as the Clipboard
    settings say (§15). Nothing is written to disk, so
    quitting Hammerspoon or reloading tilemo wipes it. That's cheaper
    than a file (no permissions to keep at 600, nothing to clean up), and
    safer: a copy you regret is gone at the next restart.
- **Characters:** tide's list, `chars.tsv`, copied unchanged with its
  Unicode License v3 notice, and searched as tide does: each typed word
  must start a word of the name, so `e acute` finds é and É.
- **Keys:** `Tab` / `Shift+Tab` switch tabs; Return copies the row and
  closes, and Cmd+V pastes it, as on tide; Shift+Delete (forward delete)
  forgets a clipboard entry; Esc closes; `Super+C` again closes.
- **Cost and reliability:** nothing to pay and no network. The watcher
  polls the pasteboard's change count, Hammerspoon's
  `hs.pasteboard.watcher.interval`, half a second by default. The list is
  about 130 KB, read the first time the Characters tab shows.

## 10. The rest of the desktop

- **Notifications:** Notification Center, with Focus for Do Not Disturb.
  Automatic Do Not Disturb while sharing the screen is a Focus option
  *(unverified)*. tide's Notifications page's Do not disturb schedule and
  *Critical alerts break through* are Focus's own here: a schedule on the
  Do Not Disturb Focus, and Time Sensitive notifications, in System
  Settings, so tilemo has no copy of either. Clicking a notification counts as Activate, so its
  window's workspace comes along (§6.1).
- **Idle and lock** (tide §10):
  - System Settings sets the display sleep and when a password is required.
    The checklist asks for the password at once after the screen locks.
  - Sleep on battery only: "Prevent automatic sleeping when the display is
    off" on power adapter *(unverified wording on macOS 26)*. `pmset`
    sets the rest, with an admin (§11.2).
  - tilemo's keep-awake toggle holds a power assertion, as `caffeinate`
    does. As on tide, it never times out, starts off at each login, and
    turns on by itself while the microphone is in use (Core Audio reports
    that) *(unverified)*. That last part isn't built yet.
  - `Super+S` toggles it, as the bar's item does, with an on-screen sign:
    "Keeping awake" or "Not keeping awake".
- **Presenter mode** (tide §10): Do Not Disturb and keep awake together,
  for a talk, a demo, or a meeting room's screen.
  - **On:** `Super+P`, or the launcher's Presenter mode. Keep awake goes
    on, Do Not Disturb goes on, and the bar's keep-awake item reads
    "Presenting" (§8). A sign says "Presenting".
  - **Off:** `Super+P` again, the launcher, or a click on the bar's item.
    Keep awake goes back to what it was before. Do Not Disturb goes off:
    tilemo can't read a Focus, so it can't know it was on before. That's
    where tilemo differs from tide, which puts both back.
  - **Either one alone while presenting** ends presenter mode. `Super+S`
    or the bar's item turns keep awake off and leaves Do Not Disturb on;
    the launcher's Do Not Disturb turns it off and leaves keep awake on.
  - **It lasts until tilemo reloads,** which starts it off, as tide's
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
  - tilemo can't make a shortcut itself, so you make them, once: **"Do Not Disturb On"** (Set Focus: Do Not Disturb, on
    until turned off) and **"Do Not Disturb Off"** (Set Focus: Do Not
    Disturb, off). The launcher's Do Not Disturb toggle uses a third,
    **"Toggle Do Not Disturb"**. *(The action's wording on macOS 26 is
    unverified.)*
  - **Missing ones are never silent.** At load tilemo runs `shortcuts
    list`, and `tilemo doctor` names any that are missing. The first key
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
    shows who's holding it (tide §17) *(unverified that it happens on a
    Mac)*.
- **Theme** (tide §15):
  - Appearance › Auto follows sunrise and sunset.
  - tide's fixed 07:00 and 19:00 need a scheduled job that sets
    the appearance through System Events *(unverified on macOS 26)*.
  - A switch by hand lasts until the next scheduled change.
  - macOS's dynamic wallpapers already change with the appearance, and
    kitty can follow it with its automatic themes *(unverified version)*.
- **Screenshots** (tide §13): macOS's own, with tide's Print keys mapped to
  them (§7.2). tilemo presses macOS's screenshot keys rather than running
  `screencapture`, because a capture an app starts needs Screen Recording
  for that app, while macOS's own keys need nothing (§11.1):
  - screen: Cmd+Shift+3; region: Cmd+Shift+4; window: the same, then
    Space;
  - those save the shot to the folder in Screenshot's options, and tilemo
    puts each new one there on the clipboard too, so a shot is both, as on
    tide (`shots.lua`). It watches the folder and copies each new image
    macOS tagged as a screen capture (Spotlight's `kMDItemIsScreenCapture`
    extended attribute), whatever its name, which macOS translates and
    Screenshot's options can change. So one taken with macOS's keys
    directly is copied as well. Files already in the folder when tilemo
    starts stay off the clipboard when they're edited. When Screenshot's
    options move the folder, tilemo watches the new one, as CI's smoke test
    checks. The Ctrl variants would put a shot on the clipboard alone.
  - `setup-macos` sets that folder to `~/Pictures/Screenshots`, tide's, and
    turns off the floating thumbnail, which holds a shot back from the
    folder until it goes. Without that, shots go to the Desktop, and
    Hammerspoon asks once for access to it.
  - Pressing the keys is a synthetic key event, which Accessibility already
    covers. CI's smoke test shows macOS takes the shot from it, on macOS 15.
- **Mouse** (conf `hyprland.lua`, tide §16):
  - Speed at the fastest, with acceleration left on: tide found a flat
    curve felt wrong. `com.apple.mouse.scaling` goes beyond the slider
    (§2.6).
  - Left-handed: the primary button on the right, in Mouse settings.
  - Wheel scaling beyond the slider is *(unverified)*. It's the gap that
    tileco §19.2 fills on chromeOS.
- **Trackpad:** natural scroll and tap to click, in Trackpad settings.
  macOS may tie natural scrolling for the mouse and trackpad together
  *(unverified)*; if so, LinearMouse can reverse the mouse alone (§13).
- **Keyboard:** repeat after 600 ms at 25 a second, set as `InitialKeyRepeat`
  and `KeyRepeat` in 15 ms steps, so the nearest is 40 and 3
  *(unverified units)*. US Dvorak is a native input source.
- **Setup checklist:** as tileco's (tileco §3.4). Each item links to its System
  Settings pane with an `x-apple.systempreferences:` URL *(unverified per
  pane on macOS 26)*. It covers the Mission Control settings (§6.6), the
  minimize settings (§6), Chrome's notifications (§5.1), and each
  permission (§11).
- **The rest of the setup:** tileco's Appendix A lists the helper scripts
  `setup` installs (Bluetooth, the audio profile switcher, notes, IRC,
  remote desktop, the file manager on `Super+E`). Which of them run on a
  Mac, and what stands in for the rest, is for `setup-macos` to settle,
  not tilemo.

## 11. Permissions, admin rights and managed Macs

### 11.1 What each permission buys

| Permission | Asked when | Buys |
|---|---|---|
| Accessibility | first run; tiling needs it | moving windows, focus follows mouse, mouse drags (§5.3), Dock badges |
| Input Monitoring | only for the lone Super tap, if done by an event tap (§7) *(unverified that Accessibility alone isn't enough)* | seeing Option go down and up |
| Screen Recording | never: titles come through Accessibility (§2.5), and screenshots use macOS's own keys (§10) | nothing tilemo needs |
| Automation, per browser | the first time the switcher's Windows tab lists tabs (§9) | tab titles and addresses |
| none | — | global keys, the bar, clocks, the switcher's apps, workspaces and windows |

Ask for each only when a feature needs it, as tileco does with its extras
(tileco §14.1).

### 11.2 Admin rights

A standard user can run tilemo once it's installed. These steps need an
administrator:

| Step | Needs admin? | Workaround without admin |
|---|---|---|
| Installing Homebrew | **yes**, once, to create `/opt/homebrew` | Install apps from a downloaded copy into `~/Applications` instead *(unverified for Hammerspoon)*. |
| Installing an app into `/Applications` | **yes**, usually | `~/Applications`. |
| Turning on a privacy permission (§11.1) | **yes**, an admin's password unlocks the setting *(unverified on macOS 26 for standard users)* | A managed Mac's MDM can grant it instead (§11.3). |
| Karabiner's keyboard driver | **yes**: it's a system extension, approved once | Skip Karabiner. tilemo then binds Option directly, which takes Option's text gestures (§7.1), and the lone Super tap needs an event tap. |
| `pmset` for the idle timeline (§10) | **yes**, `sudo` | Energy and Lock Screen settings, which a user can change. |
| Everything else `setup-macos` writes: symbolichotkeys, Dock and minimize settings, mouse scaling, appearance | no: per-user `defaults` | — |

### 11.3 On a managed work Mac

A Mac enrolled in MDM can grant or block most of this, so on a work machine
it's IT's call. tileco has the same section for chromeOS (tileco §14.4).

| Feature | What MDM can do | If it's blocked |
|---|---|---|
| Accessibility, so all of tiling | grant it to a named app with a Privacy Preferences (PPPC) profile, or block it | **No workaround**: no tiling, no focus follows mouse, no mouse drags. Global keys and the launcher still work. |
| Input Monitoring and Screen Recording | only let a standard user approve them, or block them; a profile can't switch them on silently *(unverified for Input Monitoring)* | Super+Space for the switcher (§7), or Karabiner's tap rule. tilemo shouldn't need Screen Recording (§2.5). |
| Automation for browser tabs | grant it per app pair in the same profile, or block it | No tabs in the Windows tab. Apps, workspaces, windows and commands still work. |
| Karabiner's system extension | allow or block it by team ID, and the rotation needs it too | Skip Karabiner (§11.2). |
| Running tilemo or Hammerspoon at all | block apps by name or signature, with Gatekeeper rules or a tool such as Santa | **No workaround.** Ask IT to allow it. A Developer ID build (§12) is easier for IT to allow than an unsigned one. |
| Login items | manage background items, and hide or block them | Start tilemo by hand. |
| Idle and lock timings | enforce the screen lock delay and password rules | **None.** The policy wins, and tilemo's keep-awake toggle may not stop the lock *(unverified)*. |
| Spaces, Dock and Mission Control settings | lock some of these preferences | Leave the defaults; minimizing still works (§6). |

Nothing in tilemo needs SIP lowered, which a managed Mac wouldn't allow. That
was a goal (§1), and it's why the native-Spaces alternative avoids yabai's
scripting addition (§6).

## 12. Distribution, cost and reliability

- **Not the Mac App Store:** controlling other apps' windows isn't allowed
  in the sandbox (§2.1).
- **Hammerspoon (B):** free and open source. tilemo would be a config
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

## 13. What tilemo can't have

These are the things macOS doesn't allow, or allows only through private
calls that break between releases or need SIP lowered, which §1 rules out.
Each one names a workaround, or says there is none.

| tide or tileco has | Why a Mac can't | Workaround |
|---|---|---|
| No title bars or borders | No public API removes another app's frame (§2.1). | **None** for the title bars. Gaps of 0 keep the tiles tight. |
| Focus without raising (KDE's focus follows mouse) | Focusing a window brings it to the front (§5.2). | yabai's `autofocus` does it through a private call, with SIP on *(unverified)*. Otherwise, raise, and keep floats above tiles (§5.1). |
| Floats always on top | No public way to set another app's window level (§5.1). | tilemo raises the floats again after any tile it raises. A true window level needs yabai's scripting addition, which needs SIP lowered: **none** within §1. |
| Nothing ever steals focus (tide §14) | An app can activate itself, and macOS decides whether it may. | tilemo never focuses anything unasked, and hands focus back when an app takes it without a grant (§14.1) *(unverified that it can act in time)*. |
| Dimming exactly the inactive windows | tilemo can't draw inside or between other apps' windows (§2.4). | One dark layer behind the focused window, which dims the desktop too, or JankyBorders' outline as the focus cue instead. |
| Instant workspace switches with an honest Cmd+Tab | Hiding windows off screen leaves them in Cmd+Tab; minimizing and Spaces animate (§2.3, §6). | Minimize with the Scale effect, and Reduce Motion for Spaces. **No** way to get both at once. |
| One workspace pool shared by every monitor (tide §6.5) | Minimized windows have no display, and native Spaces are per display. | tilemo tracks each workspace's display itself, as tileco does (tileco §6.1). |
| Moving a window to a native Space | Only private calls can (§2.3). | Workspaces by minimizing (§6). |
| Exact tiles for every app | Apps can refuse or round a size, such as terminals snapping to their character grid (§2.1). | The rest tile around what the app took (§5). In kitty, the grid snapping can be turned off *(unverified)*. |
| Tiling native full-screen windows | A full-screen window lives in its own Space. | Maximize instead (§4). |
| Own bar replacing the menu bar | The menu bar is the system's (§8). | Hide the menu bar automatically and put a bar over it, or use SketchyBar. |
| Every window's attention request (tide §14.4) | There's no public signal for "this window wants attention" *(unverified)*. | Dock badges, title counts and self-activation (§14.2). **None** for an app that shows none of those. |
| Own lock screen and login, with the hostname | The lock and login screens are the system's. | Lock Screen's "Show message when locked" can carry the hostname *(unverified on macOS 26)*. **None** for a custom lock screen. |
| tide's idle timeline (dim, lock, off, suspend) | macOS sets its own timings (§10). | Energy and Lock Screen settings come close. `pmset` sets more, with admin rights (§11). |
| Sharing a 16:9 slice of an ultrawide in Meet (tide §12) | Meet shares a screen, a window or a tab. | Share a window, or a virtual display from a tool such as BetterDisplay *(unverified)*. |
| Mouse wheel speed beyond the slider | Mouse settings scale the wheel only so far *(unverified)*. | LinearMouse or Mos, free tools that use Accessibility *(unverified)*. |
| A Compose key | macOS has none. | Option dead keys, a custom layout made with Ukelele, or Karabiner sequences. |
| Keys and the Super tap during Secure Input | While a password field or a terminal's secure keyboard entry is active, event taps stop seeing typed keys *(unverified for hotkeys)*. | **None**, by design. Registered hotkeys keep working, if they do. |
| Three-finger swipe between workspaces (conf `hyprland.lua`) | No public API for trackpad gestures; the native swipe switches Spaces, which tilemo doesn't use. | BetterTouchTool, a paid app, can bind gestures to keys *(unverified price)*. Otherwise **none**. |
| Pinning picture-in-picture to a corner (tide §6.4) | The app places it, and moves it back. | Leave it where the app puts it (§5.5). |
| Option's text gestures alongside Super on Option | One key can't be both. | Karabiner's mapping (§7.1). Without it, **none**: tilemo takes them. |
| Natural scrolling on the trackpad but not the mouse | macOS may have one switch for both *(unverified)*. | LinearMouse or Mos reverse the mouse alone *(unverified)*. |
| Mac App Store distribution | The sandbox forbids controlling other apps (§2.1). | **None.** Ship through Homebrew, or as a Hammerspoon config (§12). |

## 14. Focus and attention

**Nothing takes the keyboard unless you asked for it,** as on tide
(tide §14). A window that wants attention is marked, never focused, and
`Super+A` lists it, to go there.

### 14.1 Who gets focus

| When | Gets focus? |
|---|---|
| tilemo's switcher, name prompt, dashboard or resize mode is open | It keeps it until it closes. Focus follows mouse pauses meanwhile (§5.2). |
| A new window from the app you're in: a dialog, a second window | **Yes**, as tide (tide §14.1). |
| The first window of an app you launched from tilemo (the switcher, an app key) | **Yes**, if you haven't typed, clicked or moved focus since. The grant lasts 10 s and is used once. |
| A window started from the focused terminal (`open .` in kitty) | **Yes**, on the same terms *(how tilemo learns of it unsettled; tide's shell tells its guard, tide §14.3)*. |
| A notification you click | **Yes**: the click was yours (§10). |
| A password prompt | **Yes** when it follows something you did in the app that asks; otherwise it's macOS's to decide. |
| Any other app activating itself, or a window opening in the background | **No.** It's marked for attention. |

- **How tilemo enforces "no":** macOS lets an app activate itself, so tilemo
  can't refuse it. It can notice (`NSWorkspace`'s activation
  notification), and hand focus straight back to the window you were in
  when no grant covers it *(unverified that it can act before a keystroke
  lands)*. macOS 14 added cooperative activation, which already stops many
  apps taking focus unasked *(unverified how many apps it covers)*.
- **Pulled back to another workspace** (tide §14.2): an app launched on
  "work" whose window appears after you've moved to "home" opens on "work",
  marked for attention, not on "home" (§6.1).
- **A window opening on "in"** that isn't one of its apps waits for the name
  prompt (§6.2). The prompt has the keyboard; once you answer, the window
  is focused on its workspace, which counts as asked for.

### 14.2 Attention

- **What counts as wanting attention:**
  - a Dock badge appearing or rising (§2.5);
  - a window title gaining an unread count, such as `Chat (3)`, seen
    through Accessibility's title notification, as tileco reads titles
    (tileco §10.3);
  - a window that activated itself without a grant (§14.1);
  - a Dock icon bouncing *(unverified that it can be seen)*.
- **A badge marks the app; a title or activation marks the window.**
  `Super+A`'s list (§9) shows the window, or the app's last-used window.
- **A mark clears** when you focus the window or app, as on tide
  (tide §14.4).
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
  - **An app matches** a mark for its window, or its Dock badge.
  - **A site matches** a browser window's mark when that window's front
    tab is on the host, as tilemo last saw it: the switcher's tab list
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
  - **Notifications: less than on tide.** On tide, Mute also keeps the
    app's notification popups from showing, though they still go into the
    notification center's history. tilemo can't stop macOS's own banners:
    they're Notification Center's, with no public way for another app to
    hold them back. So on a Mac, Mute stops only the marks, and says so
    when you mute: the notice offers to open System Settings › Notifications
    (`x-apple.systempreferences:com.apple.Notifications-Settings.extension`
    *(unverified on macOS 26, and it opens the list, not the app's own
    page)*), where the app's banners can be turned off.
- **Muting takes one key:** in the switcher's Windows and Attention tabs,
  `Cmd+M` (physical Ctrl+M under `setup-macos`'s rotation, as tide's
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

## 15. Settings and `tilemo doctor`

- **One set of files with tide.** tilemo reads tide's settings from
  `~/.config/tide/` (tide §16.1): the clocks list, the layouts, and the dim
  strength. One file serves every desktop. A `.local` file beside each
  overrides it for one machine.
- **The layouts are tide's setting,** `layouts.json` and
  `layouts.local.json` (tide §16), read as tilemo starts, before the first
  workspace is made, and again whenever the folder changes.
  - They're laid over `start()`'s `layout`, or tide's defaults without one,
    so tilemo's own settings the files don't name (`cycle`, `mfact_step`)
    stay.
  - A change reaches every workspace, as on tide: each keeps its mode, and
    takes the new `mfact` and master count, losing any it was given with
    the keys. The displays are laid out again at once. Settings that
    haven't changed change nothing, so another file's change in the folder
    doesn't undo what the keys set.
  - A file that's wrong, by tide's checks, is an error at load, in a
    notification naming the file and why, and the last good settings stay.
  - **The workspace-name patterns** (§6.2) are tide's setting, in the same
    file tide reads them from *(its name to match tide's)*, so one list
    names workspaces on both desktops.
- **The muted apps and sites** (§14.2) are tide's setting, `muted` in
  `workspaces.json` and `workspaces.local.json`, so one list serves both
  desktops.
  - A list of strings, each a bundle id or `site:<host>`. Empty by
    default. A `.local` list replaces the shared one whole (tide §16.1).
  - **A malformed entry is an error at load,** in a notification and in
    `tilemo doctor`, naming the file and the entry, and the rest of the
    list still applies. Malformed: not a string, empty, with a space, or
    `site:` with no host or with more than a host (a scheme, a path, a
    port).
  - **A `muted` that isn't a list,** such as a JSON object, or a file that
    doesn't parse, is an error at load too, naming the file, and the last
    good list stays. So is a `namePatterns` that isn't a list (§6.2).
  - **tilemo writes only `workspaces.local.json`,** as tide's settings
    panel does: it reads the file just before each change, keeps every
    other key, and writes it whole, to a temporary file renamed over it.
    The first change copies the list in effect, since a local list
    replaces the shared one.
  - tilemo already watches the folder, so a hand edit takes effect at
    once.
- **Start at login** is tide's setting, `commands` in `startup.json` and
  `startup.local.json` (tide §16), so one list serves both desktops. It's
  empty by default.
  - tilemo runs the list once a login as it starts, in order (each
    command's check and start after the one before it's), each through
    `runenv`, as a helper key runs one (§7.2), so it gets the login
    shell's `PATH`. `google-calendar` and `google-chat` are `scripts`'
    helpers, which open Chrome's app windows on a Mac too.
  - Once a login: tilemo keeps the login it last ran in, as when this
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
  - macOS lets an app activate as it opens, so unlike tide, a command's
    window may take focus *(unverified on macOS 26)*. Its windows go where
    the home workspace's rules put them (§6.2).
  - **The settings window's Start at login section** edits the list, as
    tide's Start at login page does, with tide's own `startup.mjs`, copied
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
- **The home workspace's apps are tilemo's own setting,** `home_apps` in
  `start()`, a list of app names (§6.2). tide's list names Wayland app IDs,
  which a Mac doesn't have.
- **The standing workspaces are tilemo's own setting,** `workspaces` in
  `start()`, a list of names, `{ "in", "re", "oc", "me" }` by default
  (§6.1). The first is the home workspace. An empty list, or one naming a
  workspace twice, is an error at load.
- **A bad value is an error at load,** naming the setting, not a failure
  later. A pattern that doesn't compile is one (§6.2).
- **Pages, as tide's** (tide §16): Layouts, Keys (live, §7.2),
  Appearance, Mouse and Keyboard, the checklist (§10), and the permissions
  (§11).
  - **Built: Layouts,** a section of the settings window, as tide's
    Layouts page (tide §16), with tide's own `layouts.mjs` and `steps.mjs`,
    copied unchanged as `dashboard/tide-layouts.js` and `tide-steps.js`:
    where ultrawide begins, the mode a new workspace starts in on each kind
    of display, where a new window goes, each mode's master width and
    count, and a lone window's width. − and + step to tide's marks, ‹ and ›
    through the choices. It writes only `layouts.local.json`, keeping what
    else it says; a file that's wrong is named, and nothing changes here
    until it's fixed. Its launcher row is "Settings: layouts".
  - **Built: Clocks,** a window from the launcher ("Settings: clocks") or
    the dashboard ("Change the clocks…"). The window also has the Start at
    login, Clipboard and Muted sections. Each section has its own launcher
    row ("Settings: clocks", "Settings: start at login", "Settings:
    clipboard history", "Settings: muted apps and sites"), found by its name, which opens the window there, or
    scrolls an open one, as tide's per-page rows do (tide §16). As tide's Clocks page, it adds a
    zone by its ID, relabels, moves and removes clocks, and writes only
    `clocks.local.json`, with tide's own functions, so the first change
    copies the list the bar shows. A zone Intl doesn't know is refused.
    tilemo watches the folder, so the bar, the dashboard and the page
    follow a change, a hand edit's included.
  - **Built: Clipboard,** a section of the settings window, as tide's
    Clipboard page (tide §16), with tide's own `clipboard.mjs`, copied
    unchanged as `dashboard/tide-clipboard.js`. It reads and writes tide's
    `clipboard.json` and `clipboard.local.json`, key by key, so one setting
    serves both desktops.
    - `history` turns keeping new copies on or off, on by default. Off,
      what's kept stays until it's cleared.
    - `maxItems` is how many it keeps, 200 by default, from 1 to 10,000.
      − and + step through tide's marks (25 to 1,000). A smaller cap trims
      the history at once.
    - **Clear history** forgets every copy, at once.
    - A file that's wrong is an error at load, in a notification naming
      the file and the setting, and the last good settings stay; the
      section says so too, and changes nothing until it's fixed. tilemo
      reads the files again when the folder changes.
  - **The settings window also lists the muted apps and sites** (§14.2),
    each with an Unmute button, writing `workspaces.local.json` as the
    one-key mute does.
    - As on tide's Notifications page, a bundle id or `site:HOST` typed at
      the list's foot is muted with Enter. One the list wouldn't take back
      on loading, or one muted already, is refused, and the section says
      why.
- **One owner per job** (tide §5): tilemo tiles, binds keys and draws the
  bar. Karabiner remaps the keyboard. macOS owns notifications, lock and
  idle. Nothing else tiles.
- **`tilemo doctor`** checks what usually goes wrong. Each problem it finds
  is also a notification when it starts, as §1's "never degrade silently"
  asks, naming what stops working and the fix:
  - each permission (§11.1), and whether the event tap is still on (§16);
  - another tiler running: Amethyst, Rectangle, yabai, AeroSpace;
  - a symbolichotkey holding one of tilemo's keys (§7.3), and any key that
    failed to register;
  - Karabiner's rules loaded, and tilemo's rule up to date: Karabiner
    runs the copy it made when the rule was enabled, so a copy from before
    conf added Alt+Tab (Ctrl+Option+Shift+Tab) and the tap's Super+F20
    leaves those two dead. tilemo reads the copy in `karabiner.json`, and a
    notification names what's missing and says to remove and re-add the
    rule, once each time that changes, rechecked every 30 s (§7.1, §7.2).
    **Built so far:** this check and Karabiner's, as `tilemo.doctor()` in
    Hammerspoon's console and the switcher's "Check tilemo (doctor)";
  - the workspace file written and private, for scripts that read the
    workspace's name, and kitty's remote control on, for `TIDE_WORKSPACE`
    in new kitty windows (§6.3);
  - Stage Manager or Sequoia's tiling on (§6.6);
  - a second bar running, such as SketchyBar.

## 16. Known problems

| Problem | What tilemo does |
|---|---|
| macOS switches off an event tap whose handler is too slow (`kCGEventTapDisabledByTimeout`), which would stop the Super tap, drags and focus follows mouse *(unverified how quickly)* | Keeps the handler short, re-enables the tap when told it was switched off, and `tilemo doctor` reports it. |
| A macOS update, or a new tilemo build, resets Accessibility (scripts `docs/MACOS.md`) | The doctor and the checklist say so, and link the pane. |
| Screen Recording asks again every so often since macOS 15 *(unverified on macOS 26)* | tilemo doesn't use it (§2.5). |
| Secure Input stops event taps seeing keys (§13) | Registered hotkeys still work; the tap rules don't. |
| A hung app stalls Accessibility calls (§2.1) | A short timeout per call, and that app is skipped (§5.2). |
| tilemo quits or crashes with workspaces hidden | Restores everything on quit, and reconciles at start (§6.5). |

## 17. Where things live

- **tilemo** (this repo): the spec, then the code.
- **conf:**
  - Karabiner's rules (`config/karabiner/`), updated for §7.1 and §7.3, with
    physical Alt+Tab going to tilemo (§7.2);
  - the shell's shpool and tmux startup, which reads `TIDE_WORKSPACE`, and
    on a Mac reads tilemo's workspace file when it's missing (§6.3);
  - `kitty.conf`'s remote control socket, private to you, on a Mac only,
    for `TIDE_WORKSPACE` in new kitty windows (§6.3);
  - `amethyst.yml` retired;
  - the Hammerspoon config, if tilemo starts as route B (§3).
- **scripts:** `setup-macos`. It installs tilemo, frees the keys in §7.3,
  removes Amethyst and Rectangle, applies the Mission Control settings
  (§6.6), and stops making nine Spaces.
- **tide:** the layout geometry and its test fixtures, shared so tilemo
  doesn't keep its own copy, and the picker's character list (§9.1),
  which `make check-tide` compares.

## 18. Testing and milestones

- **Tests, as tide's and tileco's** (tide §20, tileco §17):
  - the geometry against tide's own fixtures;
  - the workspace model (§6.1) and focus follows mouse's decisions (§5.2)
    against a fake Accessibility layer, with no sleeps;
  - in CI on a macOS runner, a smoke test in a real Hammerspoon
    (`ci/hs-smoke.sh`): every `hs.*` name tilemo uses exists, tilemo starts
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
  4. **Workspaces:** minimizing, displays and restarts. Done when a day's
     work needs no Mission Control.
  5. **Bar, switcher and dashboard,** then attention.
  6. **Named workspaces:** "in", the name prompt, `TIDE_WORKSPACE` and the
     switcher's tabs (§6.1–§6.3, §9). Done when a day starts on "in" and
     every new task gets its name.

## 19. Open questions

1. **Workspaces:** decided, minimize (§6), with native Spaces next if it
   doesn't work out.
2. **Build route:** Hammerspoon first (§3 B), or straight to a native app?
3. **Bar:** decided, tilemo's own bar over an auto-hidden menu bar, with its
   own status items (§8). The menu bar item stays as the fallback.
4. **Amethyst:** keep it alongside while tilemo grows, or replace it outright?
   Running both would fight over the same windows.
5. **Does HazeOver's one-layer dim** carry over to a canvas or panel, and
   can a third-party app keep it just below another app's window (§2.4)?
6. **Karabiner for Super:** decided, yes (§7.1).
7. **The built-in keyboard:** rotate its modifiers too, or PC keyboards
   only (§7.1)?
8. **A key to toggle focus follows mouse:** decided, none;
   `tilemo.toggle_focus_follows_mouse()` from Hammerspoon's console, or
   `focus_follows_mouse = false` in `start()` (§5.2).
9. **`Super+1…9` and `Super+Shift+1…9`:** decided, positions in bar order
   (§7.2).
10. **`Super+End`:** decided, the last workspace other than "in" and the
    one you're on (§7.2).
11. **Physical Alt+Tab:** decided, swap with the master, with the
    Windows tab in place of the app switcher (§7.2).
12. **Several displays, a follow-up:** the direction is that a workspace
    spans every display, each display with its own layout within it. Open:
    - how to move between displays. The candidate: `Super+Left` / `Right`
      select the window left or right of this one, and at a display's edge
      wrap to the nearest window on the next display that way (rightmost
      on one to leftmost on the display to its right);
      `Super+Shift+Left` / `Right` move the window the same way.
    - whether that edge behavior is doable: it needs every display's
      windows laid out side by side, and a rule for "nearest" between
      displays of different sizes and offsets.
    - If it's doable, those keys replace today's: `Super+Left` / `Right`
      as previous / next workspace and `Super+Shift+Left` / `Right` as
      carry. Previous / next workspace stays on `Super+PgUp` / `PgDn`;
      carry would need a key of its own, or go.
    - Until then tilemo keeps one workspace per display (§6.1, §6.4).

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
- [MailMate list](https://lists.freron.com/mailmate/2018-October/010356.html),
  [Cursor forum](https://forum.cursor.com/t/macos-dock-badge-stuck-at-1-after-update-os-badge-null-until-killall-dock/165949):
  reading Dock badges.
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
