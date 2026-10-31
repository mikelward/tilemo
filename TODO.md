# TODO

## Next

The Hammerspoon version, in the order SPEC.md §18 sets:

1. Tiling and keys: layouts, floats, the window keys.
2. The mouse: edge drags set the split, Super+drag moves and resizes,
   Super+middle-click maximizes, resize mode (SPEC.md §5.3).
3. Focus follows mouse (SPEC.md §5.2).
4. Workspaces by minimizing, displays and restarts (SPEC.md §6).
5. The launcher, app keys and the Super tap (SPEC.md §7.2, §9).
6. The menu bar workspaces, the sign on switching, and attention
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

## Named workspaces

SPEC.md now has named workspaces in place of the nine numbered ones, and
one switcher with tabs (SPEC.md §6, §7.2, §9, §14.2), as tide's does.
**Built:** workspaces by name, the standing workspaces (`workspaces`, the
first being home, "in" by default) and home's apps (`home_apps`),
`Super+Home`, the saved state, names on the bar, the menu bar item, the
dashboard and the switch sign, the name prompt, `TIDE_WORKSPACE`, and a
launch's window going to the workspace it was launched for, and the keys:
`Super+Return`, `Super+Tab`, `Super+End`, Alt+Tab, `Super+A` and the Super
tap, and the switcher's tabs. The rest:

- **Follow-up: several displays** (SPEC.md §19, question 12). The
  direction: a workspace spans every display, each display with its own
  layout within it. Open:
  - moving between displays. The candidate: `Super+Left` / `Right` select
    the window left or right of this one, wrapping at a display's edge to
    the nearest window on the next display that way, and
    `Super+Shift+Left` / `Right` move the window the same way;
  - whether the edge wrap is doable, across displays of different sizes
    and offsets;
  - if it is, those keys replace previous / next workspace and carry,
    which they are now. Previous / next stays on `Super+PgUp` / `PgDn`,
    and carry needs another key or goes.
  Until then each display shows one workspace, and a second display gets
  one named by its number (below).
- **conf:** Karabiner sends physical Alt+Tab as tilemo's
  `Ctrl+Option+Shift+Tab` instead of Cmd+Tab, and the lone Super tap as
  `Super+F20` (conf's PR for this goes with tilemo's keys PR); `kitty.conf` allows remote control on a socket; the shell reads
  `~/Library/Caches/tilemo/workspace` on a Mac when `TIDE_WORKSPACE` is
  missing (SPEC.md §6.3, §17).
- **Check on a Mac:** `open --env` on macOS 26, kitty's socket path, and
  how slow a pattern run through `hs.osascript.javascript` is (SPEC.md
  §6.2, §6.3).

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
- `Super+Z` reaches tilemo through Karabiner as Ctrl+Option+Command+Z,
  with nothing else on that chord.

## Mute: apps and sites that never want attention

**Built** (SPEC.md §14.2, §15): `muted` in tide's `workspaces.json` and
`workspaces.local.json`, the marks suppressed and cleared, `Cmd+M` and the
right-click in the switcher's Windows and Attention tabs, the "muted"
mark, each browser window's front tab, and the settings window's list.
**The key is `Cmd+M`** (decided by the maintainer, 2026-10-31), physical
Ctrl+M under `setup-macos`'s rotation, the same key as tide's `Ctrl+M`.
It's an `hs.hotkey` bound only while the switcher's chooser is open and
deleted as it closes, never globally, so it can't reach macOS's own
`Cmd+M` minimize there and leaves it alone everywhere else; `Super+Z` is
tilemo's minimize. Hammerspoon's hotkeys are Carbon hot keys
(`RegisterEventHotKey`, `extensions/hotkey/libhotkey.m`), which take the
key before the chooser or Hammerspoon's own Window › Minimize item
(`MainMenu.xib`) sees it, and the chooser's panel isn't miniaturizable
anyway (its `styleMask` in `HSChooserWindow.xib` is only
`nonactivatingPanel` and `fullSizeContentView`).
**Check on a Mac:**

- the Notifications pane's URL on macOS 26, from the notice after a mute;
- that clicking the notice opens it (`hs.notify`'s callback);
- `Cmd+M` and the right-click reach tilemo while the switcher is open,
  and `Cmd+M` doesn't minimize anything there;
- Chrome's `active tab index` and Safari's `current tab` in the tab list.

## Launcher looks

- **Try tileco's launcher page.** The launcher is `hs.chooser` with
  tileco's scopes, which Tab moves between (SPEC.md §9). tileco's own page,
  with its scope chips over the bar and clocks, may look nicer. Try it in the
  dashboard's webview: tileco's `launcherview.js` with a stand-in for the
  Chrome APIs it calls, fed by `launcher.lua`'s items. Then compare the two
  on the Mac.

## Decisions needing review

- **After a mute, clicking tilemo's notice opens Notifications settings,**
  rather than a dialog asking first, which would take the keyboard from
  the switcher. Reversible: `toggle_mute` in `init.lua`.
- **`muted` lives in `workspaces.json`,** beside `inApps` and
  `namePatterns`, rather than a file of its own, since it's another list
  of apps tide and tilemo share. Reversible: one name in `mute.lua`, and
  tide's agent may pick otherwise.
- **A right-click on a row stands in for a hover button,** which
  `hs.chooser` can't draw. Reversible: a webview switcher.
- **A site matches a browser window by its front tab as the switcher last
  saw it,** so a window whose tab changed since the switcher was last
  opened may be marked or not by the old tab. Polling the browsers for it
  would cost an Apple Event every 2 s. Reversible: `wm.tab_hosts`.
- **A site's host matches exactly,** ignoring case, so
  `site:chat.google.com` doesn't cover `mail.google.com`, and
  `site:google.com` doesn't cover either. Reversible: `mute.matches`.
- **Workspace names take tide's character rule but not its 32-character
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
  Win+Z as Ctrl+Option+Command+Z since it was first added. tilemo's rule
  check still flags a copy without it. Reversible: `keys.RULE_FEATURES`.
- **An out-of-date tilemo rule in Karabiner is flagged, not worked
  around:** tilemo reads the enabled copy in `karabiner.json`, and if
  Alt+Tab's or the tap's Super+F20 manipulator is missing it says which,
  and how to re-add the rule, in a notification and in `tilemo.doctor()`.
  It doesn't bind Super+Space's old tap or anything else in their place.
  `tilemo doctor` is so far just this and the Karabiner check, from the
  console or the switcher. Reversible: `keys.rule_gaps` and `init.lua`'s
  `check_rule`.

- **A second display shows a workspace of its own, named by the lowest
  free number from 2** ("2", then "3"), the number it had before names.
  SPEC.md doesn't say what a display shows before anything is named for
  it; tide leaves it open too (tide §21). Its workspace goes once left
  empty, like any other. Reversible: `wm.map_screens`.
- **The name prompt's default isn't selected:** `hs.chooser` has no way to
  select its text, so typing adds to the default rather than replacing it
  *(unverified)*; Cmd+A or Backspace clears it. Reversible: a webview
  prompt, or a keystroke to select all once it opens.
- **A name pattern with no capture group is an error at load,** as tide's
  spec says for the same shared file, since it can't give a name. The
  patterns are tide's `workspaces.json` `namePatterns`, with
  `workspaces.local.json` taking their place when it sets them; that's the
  name on tide's spec branch, not merged there yet. A bad list is said
  in a notification and the last good one stays, rather than stopping
  tilemo. Reversible: `names.lua`.
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
- **Scripts read the workspace from `~/Library/Caches/tilemo/workspace`,**
  not `hs -c`, since `hs.ipc`'s port runs any Lua a local process sends,
  with tilemo's Accessibility grant. Lua has no chmod, so each write runs
  `/bin/chmod` three times; that's only when the workspace changes. Reversible:
  `current.lua`.
- **A launch's window is matched by its app's bundle ID,** or, for a
  helper with none, as the next new window of any app, within the launch's
  10 s grant, once. A window from elsewhere opening in that time could be
  taken for it. Reversible: `wm.launch_to`.
- **Alt+Tab is `Ctrl+Option+Shift+Tab`** as Karabiner sends it: without
  Command, so physical Win+anything can't make it. Reversible:
  `keys.karabiner_only` and conf's `tilemo.json`.
- **The lone Super tap is `Super+F20`** as Karabiner sends it, told apart
  from `Super+Space`. Reversible: one line in `keys.map` and conf's
  `tilemo.json`.
- **`Super+Tab` and `Super+End` remember shown workspaces across
  displays,** one list, not one per display. Reversible: `wm.used_ws`.
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
  trimmed;** a blank name moves nothing. SPEC.md sets no length; tide caps
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
  focused,** on its display. tilemo hears of focus changes but not of Space
  swipes, so a full-screen window swiped away from but still focused may
  keep the bar hidden *(unverified)*. The alternative is tracking Spaces
  through `hs.spaces`. Reversible: `bar.hidden` in `bar.lua`.
- **A chip's attention icons are in layout order, then floats by window
  id, up to five, then `+n`,** as the chips' icons were before they showed
  only attention; an app with no icon is a blank square rather than left
  out, so the count matches the windows. Reversible: `apps_of` in `bar.lua`
  and `renderWorkspaces` in `bar.js`.
- **A click on an attention icon shows the window's workspace on that
  bar's display** if no display shows it, then focuses the window. One
  showing on another display stays there. Reversible: `bar.handle`.
- **A click on the bar may make Hammerspoon the front app** *(unverified)*,
  emptying the title until focus moves. Reversible: hand focus back after
  a click, as the dashboard does on closing.

- **tide's geometry and clocks module are copied, not shared.**
  `hammerspoon/tilemo/geometry.lua` and `dashboard/tide-clocks.js` are
  tide's files unchanged, and CI fails if they drift (`make check-tide`).
  The alternative is a git submodule of tide. Reversible: swap the copies
  for the submodule paths.
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
- **A display that goes away hides its workspace;** the bar, Next and
  Previous bring it back on the display that's left. Reversible: `wm.map_screens`.
- **App keys run tide's helpers** (`browser1`, `google-calendar`, …)
  through `runenv`, as tide does. Each has a macOS branch in scripts:
  `chrome` opens Google Chrome with `open -na`, so the browsers and web apps
  work, `home` opens Finder, `notepad` TextEdit and `irc` HexChat
  *(unverified per key on a Mac)*. Each press starts its helper, so a web
  app key opens another window, as on tide. A helper that fails says so in a
  notification. Super+T opens a new kitty window, by bundle ID. Reversible:
  `keys.APPS`.
- **Screenshots are saved and copied** (SPEC.md §10): macOS's own keys save
  each to Screenshot's folder, and tilemo copies each new file there that
  macOS tagged as a screen capture to the clipboard, so a shot taken with
  macOS's keys directly is copied too. They keep macOS's names ("Screenshot … at ….png"), not
  tide's `YYYY-MM-DD_HH-MM-SS.png`. Reversible: put Ctrl back in
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
- **With no clocks file, the clocks are tileco's,** Sydney, Los Angeles,
  New York and London (SPEC.md §8), not tide's San Francisco, New York and
  London; tide's `clocks.json` or `clocks.local.json` sets them on both.
  tide's `hour24` and `dedupeLocal` aren't followed, since tileco's view is
  always 24-hour and always hides local. Reversible: `DEFAULT_FILE` in
  `dashboard/settings.js`.
- **The dashboard has no search;** the launcher stays `hs.chooser`, with
  tileco's scopes (Launch, Tabs, Attention) moved between with Tab. The
  alternative is tileco's whole launcher page in the webview, which needs a
  stand-in for the Chrome APIs it calls. Reversible: add the page later.
