# timo

tide's tiling desktop, and tico's launcher and dashboard, on macOS:
[tide](https://github.com/mikelward/tide) is the Linux desktop and
[tico](https://github.com/mikelward/tico) the chromeOS one.

**Status: exploration, with a first Hammerspoon version.** [SPEC.md](SPEC.md)
says what macOS allows for each of their features, how well, and at what
cost, and lists the open questions that decide what timo becomes.
[TODO.md](TODO.md) says what's next.

## The Hammerspoon version

It brings tide's desktop to macOS:
- tide's layouts and window keys (SPEC.md §5, §7.2);
- the mouse: edge drags, Super+drag and resize mode;
- focus follows mouse;
- nine workspaces shared across displays (§6);
- the launcher and app keys (§9);
- the workspaces in the menu bar, with Super+Tab to what wants attention
  (§8, §14.2);
- tico's dashboard on Super+Shift+Space.

1. Install [Hammerspoon](https://www.hammerspoon.org) and grant it
   Accessibility.
2. `make install`, then add to `~/.hammerspoon/init.lua`:

   ```lua
   timo = require("timo")
   timo.start({})
   ```

3. Reload Hammerspoon's config.

`start()` takes float rules, checked when it starts:

```lua
timo.start({ rules = { { app = "com.apple.finder", title = "^Info$", action = "float" } } })
```

Super is the PC keyboard's Win key. With conf's Karabiner rule, it arrives
as Ctrl+Option+Command, so Option keeps its own meanings. Without it, timo
falls back to Option, and says so once (SPEC.md §7.1).

## Testing

`make test lint` runs everything in plain Lua 5.4, against a fake of macOS
(`tests/fake.lua`). The dashboard page's test also needs Node, and skips
with a note without it.

CI also runs `ci/hs-smoke.sh` on a macOS runner. It installs Hammerspoon from
Homebrew, checks that every `hs.*` name timo uses exists in it, then starts
timo and opens and closes the dashboard. Hosted runners can't grant
Accessibility, so nothing tiles there. The tiling hasn't run on a Mac yet;
the checklists in SPEC.md §5.1 and §5.2 are what to try first.
