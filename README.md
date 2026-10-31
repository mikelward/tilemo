# tilemo

tide's tiling desktop, and tileco's launcher and dashboard, on macOS:
[tide](https://github.com/mikelward/tide) is the Linux desktop and
[tileco](https://github.com/mikelward/tileco) the chromeOS one.

**Status: exploration, with a first Hammerspoon version.** [SPEC.md](SPEC.md)
says what macOS allows for each of their features, how well, and at what
cost, and lists the open questions that decide what tilemo becomes.
[TODO.md](TODO.md) says what's next.

## The Hammerspoon version

It brings tide's desktop to macOS:
- tide's layouts and window keys (SPEC.md §5, §7.2);
- the mouse: edge drags, Super+drag and resize mode;
- focus follows mouse;
- named workspaces shared across displays, in the order you made them,
  with "in" first for the apps you keep open all day (§6). An empty one
  goes once you leave it. A state saved with timo's or tilemo's old numbered
  workspaces is read once into ones named "1" to "9";
- the switcher, with Tab moving between apps and commands, the workspaces,
  open tabs, and the windows wanting attention: Super+Space opens it on
  apps, a lone Super tap on workspaces and Super+A on attention (§9);
- Super+Return to move a window to a workspace by name, Super+Tab to flip
  between "in" and the last workspace, Super+End to the last one other than
  "in", and Alt+Tab to swap with the master, with conf's Karabiner rule
  (§7.2);
- tide's bar along the top: the workspaces, the window's title, the clocks
  and tilemo's own status items (input source, keep awake, camera,
  microphone, speaker, network, battery), with Super+Shift+M to mute the
  microphone (§7.2, §8, §14.2);
- tileco's dashboard on Super+Shift+Space;
- a Clocks settings page, from the launcher or the dashboard, sharing
  tide's `~/.config/tide/clocks*.json` (§15).

With [mikelward/scripts](https://github.com/mikelward/scripts),
`setup-macos --wm tilemo` does all of this: it installs Hammerspoon and tilemo,
writes the `init.lua` below if there isn't one, frees the keys tilemo needs
(SPEC.md §7.3), and hides the menu bar. Grant Hammerspoon Accessibility,
and add conf's `tilemo:` Karabiner rule for a Super key that leaves Option
alone (§7.1). By hand:

1. Install [Hammerspoon](https://www.hammerspoon.org) and grant it
   Accessibility.
2. `make install`, then add to `~/.hammerspoon/init.lua`:

   ```lua
   tilemo = require("tilemo")
   tilemo.start({})
   ```

3. Set the menu bar to hide: System Settings › Control Center ›
   "Automatically hide and show the menu bar": Always. tilemo's bar takes
   its place; the menu bar still shows when the pointer reaches the top.
4. Reload Hammerspoon's config.

`tilemo.start({ bar = false })` leaves the bar out and shows the workspaces in
the menu bar instead.

`workspaces` names the standing workspaces, which are always on the bar and
never removed. It defaults to `{ "in", "re", "oc", "me" }`. The first is the
home workspace, made at start, where Super+Home goes; each of the rest is
made the first time you go to it or send a window there.

`home_apps` names the apps whose windows always open on the home workspace,
by app name. It defaults to mail, chat, calendar and music:

```lua
tilemo.start({ home_apps = { "Mail", "Messages", "Calendar", "Music" } })
```

Any other window opening on "in" asks for a workspace name, and so does a
launch from "in": Enter makes or uses the workspace and moves there, and
Esc closes the window or cancels the launch. The default name comes from
the window's title, through tide's `namePatterns` in
`~/.config/tide/workspaces.json`, which are JavaScript regular expressions.
Apps tilemo starts get the workspace's name, letters and digits only (in
any script, NFC-normalized), as `TIDE_WORKSPACE`. Scripts read the current one with
`cat ~/Library/Caches/tilemo/workspace`, a file only you can read, which
tilemo rewrites whenever the workspace changes. tilemo doesn't load
`hs.ipc`, since its port runs any Lua a local process sends it.

`start()` takes float rules, checked when it starts:

```lua
tilemo.start({ rules = { { app = "com.apple.finder", title = "^Info$", action = "float" } } })
```

tilemo was called timo. An install from then keeps working after
`make install`: `require("timo")` still loads tilemo, with a note in the
console to change it to `require("tilemo")`; a Karabiner rule described
`timo:` still counts; and the workspaces and launcher history timo saved are
read the first time tilemo finds none of its own. The old modules in
`~/.hammerspoon/timo/` are no longer used, and can go once `init.lua` says
`require("tilemo")`.

Super is the PC keyboard's Win key. With conf's Karabiner rule, it arrives
as Ctrl+Option+Command, so Option keeps its own meanings. Without it, tilemo
falls back to Option, and says so once (SPEC.md §7.1).

## Testing

`make test lint` runs everything in plain Lua 5.4, against a fake of macOS
(`tests/fake.lua`). The dashboard and bar pages' tests also need Node, and
skip with a note without it.

CI also runs `ci/hs-smoke.sh` on a macOS runner. It installs Hammerspoon from
Homebrew, checks that every `hs.*` name tilemo uses exists in it, then starts
tilemo, checks its bar is up along the top, opens and closes the dashboard,
and opens three TextEdit windows to check tilemo tiles them below the bar,
where its layout says. That's one layout on one
display; the checklists in SPEC.md §5.1 and §5.2 are what to try on a real
Mac.
