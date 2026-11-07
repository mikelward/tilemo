# tidemo

tide on macOS: tide for Linux's tiling desktop, and tide for Chrome's launcher and dashboard:
[tide for Linux](https://github.com/mikelward/tide) is the Linux desktop and
[tide for Chrome](https://github.com/mikelward/tideco) the Chrome one.

**Status: exploration, with a first Hammerspoon version.** [SPEC.md](SPEC.md)
says what macOS allows for each of their features, how well, and at what
cost, and lists the open questions that decide what tide becomes.
[TODO.md](TODO.md) says what's next, and [INFEASIBLE.md](INFEASIBLE.md) what
macOS won't let tide fix.

## The Hammerspoon version

It brings tide for Linux's desktop to macOS:
- tide for Linux's layouts and window keys (SPEC.md §5, §7.2);
- the mouse: edge drags, Super+drag and resize mode;
- focus follows mouse;
- named workspaces, each spanning every display with a layout of its own
  on each, in the order you made them, with "in" first for the apps you keep open all day (§6). An empty one
  goes once you leave it. A state saved with timo's or tide's old numbered
  workspaces is read once into ones named "1" to "9";
- the switcher, with Tab moving between apps and commands, the workspaces,
  open tabs, and the windows wanting attention: Super+Space opens it on
  apps, a lone Super tap on apps too and Super+A on attention (§9);
- Super+Return to go to a workspace by name and Super+Shift+Return to move
  a window to one, Super+Tab to flip between "in" and the last workspace,
  Super+End to the last one other than "in", Super+1…9 to the Nth
  workspace on the bar (Super+1 is "in") and Super+Shift+1…9 to send a
  window there, Super+0 and Super+Shift+0 the same for the last workspace
  on the bar, and Alt+Tab to swap with the master, with conf's Karabiner
  rule (§7.2);
- Super+Left and Right to select the window that way, going on to the next
  display at the edge, and Super+Shift+Left and Right to move it there;
  Super+PgUp and PgDn for the previous and next workspace with windows,
  with Shift to move the window there, and a three-finger swipe left or
  right on the trackpad for the next or previous (§7.2);
- Caps Lock as Compose, as on Linux, with Linux's own sequences (§10);
- tide for Linux's bar along the top: tide's logo, opening the switcher, the
  workspaces, the window's title, the clocks
  and tide's own status items (input source, keep awake, camera,
  microphone, Bluetooth on or off with `blueutil`, Bluetooth headphones,
  speaker, opening a volume popover with a slider, mute and the outputs,
  and a monitor's own speakers over DDC with `m1ddc` or `ddcctl`, the
  volume keys included, network with a lock while a VPN is up, battery, CPU %, and a
  session menu to lock, log out, sleep, restart or shut down), with
  Super+Shift+M to mute the microphone
  (§7.2, §8, §14.2);
- Super+S to keep the display awake, and Super+P for presenter mode, Do
  Not Disturb and keep awake together (§10). Do Not Disturb needs two
  shortcuts you make in the Shortcuts app, "Do Not Disturb On" and "Do Not
  Disturb Off", each one Set Focus action; tide says so if they're
  missing, and keep awake works without them;
- tide for Linux's picker on Super+V: what you've copied since tide started,
  never a password manager's copy, and emoji and symbols by name (§9.1),
  with tide for Linux's Clipboard settings: the history on or off, how many copies it
  keeps, and Clear history (§15);
- the picker straight on its Characters tab with Super+;;
- the picker's Fill tab on Super+Shift+V: your snippets
  (`~/.config/tide/snippets.json`) and Bitwarden's logins through rbw
  (`brew install rbw`, then `rbw config set email` and `rbw login`), one
  row per field, typed where you were (§9.1);
- tide for Chrome's dashboard on Super+Shift+Space;
- an overview in place of Mission Control: Ctrl+Up shows every
  workspace's windows as cards grouped by workspace, Ctrl+Down this
  workspace's; click one, or type to filter and press Return, to go to it
  (SPEC.md §6.9). `setup-macos` frees the two keys;
- a settings window, from the launcher or the dashboard, with tide for Linux's
  Clocks, Start at login and Clipboard settings, sharing tide for Linux's
  `~/.config/tide/clocks*.json`, `startup*.json` and `clipboard*.json`, and
  the muted apps and sites, and a Floating section for the rules that
  float an app's windows by bundle ID and title pattern, with the floating
  windows no rule covers yet; each section has its own launcher row (§15).
  Super+Shift+I opens Floating for the focused window, and floating a
  window with Super+Shift+F asks once whether to always float its app.
  The window has a page for each of tide for Linux's settings pages, in tide for Linux's
  order, under its sidebar's groups, Hardware, Windows and General: where the settings are macOS's or a helper's, its buttons open
  the System Settings pane, LinearMouse or Karabiner (§1, §15). Its
  Keyboard section turns conf's Karabiner rules, such as Ctrl+Tab's next
  tab, on and off itself, keeps them up to date with conf, and turns a new
  one on once. Its Mouse section has tide for Linux's Scroll speed and Natural
  scrolling, which tide sets in LinearMouse's config as it starts, after
  a device is plugged in or a wake, and when tide for Linux's settings change. Its
  last section, the Setup checklist, shows each permission's state and
  links each to its list in Privacy & Security, and lists the Desktop &
  Dock, Lock Screen and Notifications settings to change, to tick off
  (§10, §15);
- a notification, and a line in the doctor, when LinearMouse isn't
  installed or isn't running, since without it a mouse wheel notch
  scrolls a line or so (§10).

With [mikelward/scripts](https://github.com/mikelward/scripts), a plain
`setup` (or `setup-macos`) does all of this: it installs Hammerspoon and
tide, pulling an existing checkout first so each run keeps it current,
writes the `init.lua` below if there isn't one, frees the keys tide needs
(SPEC.md §7.3), and stops the menu bar hiding, so tide's bar covers it. `--wm amethyst` sets up Amethyst
instead. Grant Hammerspoon Accessibility,
and add conf's `tide:` Karabiner rule for a Super key that leaves Option
alone (§7.1). By hand:

1. Install [Hammerspoon](https://www.hammerspoon.org) and grant it
   Accessibility.
2. `make install`, then add to `~/.hammerspoon/init.lua`:

   ```lua
   tide = require("tide")
   tide.start({})
   ```

3. Stop the menu bar hiding: System Settings › Control Center ›
   "Automatically hide and show the menu bar": Never. tide's bar covers
   it, so it no longer slides in when the pointer reaches the top; the
   Apple logo's **Show Menu Bar** brings it back until Esc, Return, or a
   click below it. Until it's set, tide says so when it starts.
4. Reload Hammerspoon's config.

To update, `git pull` and `make install` again (or run `setup`): tide
reloads itself a second after the new copy lands in
`~/.hammerspoon/tide`, so there's no reload to do by hand.

`tide.start({ bar = false })` leaves the bar out and shows tide's logo and
the workspaces in the menu bar instead.

A workspace that isn't showing parks its windows off screen, as AeroSpace
does, so a switch is instant: all but a 1 pt sliver of each goes past a
corner of its display. Mission Control would then show every workspace's
windows, so `setup-macos` turns it off and tide's overview takes its
keys, and Cmd+Tab to a parked window brings its workspace along.
`tide.start({ hide = "minimize" })` minimizes them instead, as tide
used to: Mission Control shows only the workspace on screen, but every
switch animates. The default is `hide = "park"` (SPEC.md §6).

The Switcher row under Keyboard in tide for Linux's settings swaps the `hs.chooser`
switcher for tide for Chrome's dashboard page, still being tried, at once (SPEC.md
§9.2). Until it's chosen there, `tide.start({ launcher = "dashboard" })`
does; the default is `launcher = "chooser"`.

On screen it's tide: notifications, window titles, the switcher's own
commands and the settings page say tide and show tide's wave logo.
`make icons` renders the logo's PNGs from tide for Linux's SVG with
Playwright's Chromium.

`workspaces` names the standing workspaces, which are always on the bar and
never removed. It defaults to `{ "in", "re", "oc", "me" }`. The first is the
home workspace, made at start, where Super+Home goes; each of the rest is
made the first time you go to it or send a window there.

`home_apps` names the apps whose windows always open on the home workspace,
by app name. It defaults to mail, chat, calendar and music, as both the Mac's
apps and Google's web apps. A list you set also starts at login, once a
login, in the background, skipping any app that's running:

```lua
tide.start({ home_apps = { "Mail", "Messages", "Calendar", "Music" } })
```

`workspace_settings` is each workspace's own, as tide for Linux's `workspaceSettings`:
whether a new window there asks for a name (`askForName`), and the apps,
by app name, whose windows stay open there (`pinnedApps`). Unset, home asks
and nothing is pinned; set, a workspace it doesn't list, or a field it
leaves out, is off:

```lua
tide.start({ workspace_settings = { ["in"] = { askForName = true, pinnedApps = { "Gmail", "Google Chat" } } } })
```

tide for Linux's `standing`, `inApps` and `workspaceSettings`, in
`~/.config/tide/workspaces.json` and `workspaces.local.json`, take the place
of `workspaces`, `home_apps` and `workspace_settings` where a file sets them,
and the settings window's Workspaces section edits them.
`inApps` can name Mac apps alongside tide for Linux's entries: names match ignoring
case, with hyphens as spaces, and at login only the ones that are Mac apps
start.

Any other window opening on a workspace whose `askForName` is on, "in" by
default, asks for a workspace name, and so does a launch from there: Enter
makes or uses the workspace and moves there, the one it's on included, and
Esc closes the window or cancels the launch. Home's apps never ask. Any
window can be sent to "in". A pinned app's window stays open on its
workspace: Super+Backspace and the prompt's Esc leave it open, and while it
has focus Cmd+W, Cmd+Shift+W and Cmd+Q never reach it, with a notification
saying it's pinned there. Its close button and its menus still close it,
since tide can't see those. The default name comes from
the window's title: its first word, or a match of tide for Linux's `namePatterns` in
`~/.config/tide/workspaces.json`, which are JavaScript regular expressions.
Apps tide starts get the workspace's name, letters and digits only (in
any script, NFC-normalized), as `TIDE_WORKSPACE`. Scripts read the current one with
`cat ~/Library/Caches/tide/workspace`, a file only you can read, which
tide rewrites whenever the workspace changes. tide doesn't load
`hs.ipc`, since its port runs any Lua a local process sends it.

`start()` takes float rules, checked when it starts:

```lua
tide.start({ rules = { { app = "com.apple.finder", title = "^Info$", action = "float" } } })
```

Each title is a Lua pattern, found anywhere in the title. They come before
the rules the settings window's Floating section keeps in
`~/.config/tide/floating-macos.local.json`, which only float (SPEC.md §15).

tide was called tilemo, and timo before that. An install from then keeps
working after `make install`: `require("tilemo")` and `require("timo")`
still load tide, with a note in the console to change it to
`require("tide")`; a Karabiner rule described `tilemo:` or `timo:` still
counts; what tilemo saved is copied to tide's settings the first time it
starts; and `~/Library/Caches/tilemo` moves to `~/Library/Caches/tide`, with
a link left in its place. `~/.hammerspoon/tilemo/` and `~/.hammerspoon/timo/`
can go once `init.lua` says `require("tide")`.

Super is the PC keyboard's Win key. With conf's Karabiner rule, it arrives
as Ctrl+Option+Command, so Option keeps its own meanings. Without it, tide
falls back to Option, and says so once (SPEC.md §7.1).

## Testing

`make test lint` runs everything in plain Lua 5.4, against a fake of macOS
(`tests/fake.lua`). The dashboard and bar pages' tests also need Node, and
skip with a note without it.

CI also runs `ci/hs-smoke.sh` on a macOS runner. It installs Hammerspoon from
Homebrew, checks that every `hs.*` name tide uses exists in it, then starts
tide, checks its bar is up along the top, opens and closes the dashboard,
and opens three TextEdit windows to check tide tiles them below the bar,
where its layout says. That's one layout on one
display; the checklists in SPEC.md §5.1 and §5.2 are what to try on a real
Mac.
