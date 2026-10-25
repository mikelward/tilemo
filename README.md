# timo

tide's tiling desktop, and tico's launcher and dashboard, on macOS:
[tide](https://github.com/mikelward/tide) is the Linux desktop and
[tico](https://github.com/mikelward/tico) the chromeOS one.

**Status: exploration, with a first Hammerspoon version.** [SPEC.md](SPEC.md)
says what macOS allows for each of their features, how well, and at what
cost, and lists the open questions that decide what timo becomes.
[TODO.md](TODO.md) says what's next.

## The Hammerspoon version

It tiles with tide's layouts and binds tide's window keys (SPEC.md §5,
§7.2). Workspaces, the mouse, focus follows mouse and the launcher come
next.

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
(`tests/fake.lua`). Nothing here has run on a Mac yet; the checklists in
SPEC.md §5.1 and §5.2 are what to try first.
