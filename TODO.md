# TODO

## Next

The Hammerspoon version, in the order SPEC.md §18 sets:

1. Tiling and keys: layouts, floats, the window keys.
2. The mouse: edge drags set the split, Super+drag moves and resizes,
   Super+middle-click maximizes, resize mode (SPEC.md §5.3).
3. Focus follows mouse (SPEC.md §5.2).
4. Workspaces by minimizing, displays and restarts (SPEC.md §6).
5. The launcher, app keys and the Super tap (SPEC.md §7.2, §9).
6. The menu bar workspaces, the sign on switching, attention and Super+Tab
   (SPEC.md §8, §14.2).
7. The dashboard: tileco's bar and clock panel in an `hs.webview`, on
   Super+Shift+Space (SPEC.md §8).
   **Decided:** tilemo's own bar along the top, over an auto-hidden menu bar,
   with the workspaces, the title, tileco's clocks and its own status items.
   The menu bar item stays as the fallback (`bar = false`), and a large
   number shows briefly on each switch.
8. **Done:** conf's Karabiner rule turns Win+key into
   Ctrl+Option+Command+key (description starting `tilemo:`), and
   `setup-macos --wm tilemo` in scripts installs Hammerspoon and tilemo, frees
   the keys in SPEC.md §7.3, and hides the menu bar for tilemo's bar.

## Decisions needing review

- **The bar floats at the floating window level,** above every app's
  windows and below the menu bar, so the auto-hidden menu bar still shows
  over it. A float dragged to the top goes under it. Reversible: the
  `level` in `bar_hs.lua`.
- **The battery, network and keep awake are read every 5 s;** audio,
  cameras and the input source have watchers. A battery or network change
  takes up to 5 s to show. Reversible: `hs.battery.watcher` and
  `hs.network.reachability` in `bar_hs.lua`.
- **macOS's own full screen hides the bar only while that window is
  focused,** on its display. tilemo hears of focus changes but not of Space
  swipes, so a full-screen window swiped away from but still focused may
  keep the bar hidden *(unverified)*. The alternative is tracking Spaces
  through `hs.spaces`. Reversible: `bar.hidden` in `bar.lua`.
- **A chip's icons are its tiles in layout order, then its floats by
  window id;** an app with no icon is a blank square rather than left out,
  so the count matches the windows. Reversible: `apps_of` in `bar.lua` and
  `renderWorkspaces` in `bar.js`.
- **A click on the bar may make Hammerspoon the front app** *(unverified)*,
  emptying the title until focus moves. Reversible: hand focus back after
  a click, as the dashboard does on closing.

- **tide's geometry is copied, not shared.** `hammerspoon/tilemo/geometry.lua`
  is tide's file unchanged, and CI fails if they drift
  (`make check-geometry`). The alternative is a git submodule of tide.
  Reversible: swap the copy for the submodule path.
- **No frame-offset store.** tileco stores, per app, how far a window's frame
  lands from where it asked (tileco SPEC.md §5.3). tilemo leaves an app that
  rounds its size where it settled. Reversible: add the store in `wm.lua`'s
  retile if gaps or overlaps show up on a Mac.
- **The master count never drops below one,** in every mode. tide's tile
  can go to none. Reversible: one line in `layout.nmaster`.
- **How tilemo tells Karabiner is ready:** its config has a rule whose
  description starts `tilemo:` (or `timo:`, from before the rename), and
  `Karabiner-Core-Service` or `karabiner_grabber` is running, checked every
  30 s. Unverified on a Mac.
  Reversible: `keys.karabiner_ready`.
- **Insert is bound as the Mac's Help key,** which a PC keyboard's Insert
  sends *(unverified)*. Reversible: one line in `keys.map`.
- **Every new float is centered,** even one that opens where it remembers
  being. SPEC.md §5.1 wants those left in place, but tilemo can't yet tell
  them apart. Reversible: skip `place_float` for a float that opens away
  from the display's origin, say.
- **A tile's height can't be dragged.** tide's stacks are equal rows, so a
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
- **No key turns focus follows mouse off** (SPEC.md open question 8):
  `tilemo.toggle_focus_follows_mouse()` from Hammerspoon's console, or
  `focus_follows_mouse = false` in `start()`. Reversible: bind it in
  `keys.map`.
- **A window minimized before tilemo first starts counts as yours,** so tilemo
  never restores something you put away. Reversible: `wm.add`.
- **Restarts match windows by app and title, closest first** (SPEC.md
  §6.3). A window keeps its saved place by id only if the app matches. If
  not, it takes the place of its app's window whose title is most alike:
  the same title first, then the most in common at the start and end. With
  no title alike at all, any of its app's places still counts. Places are
  kept for 10 minutes, at most 50: a saved window that hasn't come back
  since tilemo started, or a window whose process quit, even if the app is
  running again already. A window you close while its process runs leaves
  no place, so its next window opens where you are. An app that quits when
  its last window closes leaves one, though. *Unverified:* that
  `hs.application.applicationForPID` no longer finds a process by the
  time its windows are reported gone. A window saves its current index,
  so if tilemo restarts while an app is still bringing windows back, the
  rest may land out of order around the ones already back. That's the
  price of a stack you've rearranged since staying put. Reversible:
  `wm.match`, `wm.KEEP` and `wm.snapshot`.
- **A display that goes away hides its workspace;** Super+N brings it back
  on the display that's left. Reversible: `wm.map_screens`.
- **App keys run tide's helpers** (`browser1`, `google-calendar`, …)
  through `runenv`, as tide does. Each has a macOS branch in scripts:
  `chrome` opens Google Chrome with `open -na`, so the browsers and web apps
  work, `home` opens Finder, `notepad` TextEdit and `irc` HexChat
  *(unverified per key on a Mac)*. Each press starts its helper, so a web
  app key opens another window, as on tide. A helper that fails says so in a
  notification. Super+T opens a new kitty window, by bundle ID. Reversible:
  `keys.APPS`.
- **Screenshots go to the clipboard only.** They press macOS's own
  screenshot keys, so tilemo needs no Screen Recording permission; tide also
  saves each to `~/Pictures/Screenshots` (SPEC.md §10), and macOS does one
  or the other. Reversible: drop Ctrl from `keys.SCREENSHOT` to save to
  Screenshot's folder instead.
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
- **Attention polls every 2 s** for Dock badges and window titles, rather
  than watching Accessibility notifications. A count can take up to 2 s to
  show. Reversible: `AXTitleChanged` observers in the adapter.
- **The focus guard guesses what you asked for from your input**
  (SPEC.md §14.1). A focus is yours if it's another window of the app you
  were in, one tilemo asked for, one that follows a click, Return or a key
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
- **The menu bar chips are text:** `[3]` here, `(5)` on another display,
  `2` occupied, `4!` wanting attention. Reversible: draw them with
  `hs.canvas` into the status item's icon.
- **Hammerspoon's console and preferences float, and its other windows are
  left alone** by built-in rules, matched by title, so tilemo doesn't place
  its own launcher and dashboard. Reversible: the rules in `rules.lua`.
- **The dashboard is on Super+Shift+Space,** next to the launcher on
  Super+Space; tide has no dashboard key to match. Reversible: one line in
  `keys.lua`.
- **The bar and dashboard show tileco's default clocks,** Sydney, Los
  Angeles, New York and London (SPEC.md §8), not tide's San Francisco, New
  York and London, and don't yet read tide's `clocks.json` (SPEC.md §15).
  Reversible: tilemo's `dashboard/settings.js`.
- **The dashboard has no search;** the launcher stays `hs.chooser`. The
  alternative is tileco's whole launcher page in the webview, which needs a
  stand-in for the Chrome APIs it calls. Reversible: add the page later.
