# TODO

## Next

The Hammerspoon version, in the order SPEC.md §18 sets:

1. Tiling and keys: layouts, floats, the window keys.
2. The mouse: edge drags set the split, Super+drag moves and resizes,
   Super+middle-click maximizes, resize mode (SPEC.md §5.3).
3. Focus follows mouse (SPEC.md §5.2).
4. Workspaces by minimizing, displays and restarts (SPEC.md §6). **This PR.**
5. The launcher, app keys, the dashboard, attention (SPEC.md §7–§9, §14).
   **Decided for v1:** no top bar. A menu bar item shows the workspaces as
   chips (current, occupied, wanting attention; a click switches), a large
   number shows briefly on each switch, and Clocker shows the time zones.
6. conf: the Karabiner rule that turns Win+key into Ctrl+Option+Command+key
   (description starting `timo:`). scripts: `setup-macos` installs
   Hammerspoon and timo, and frees the keys in SPEC.md §7.3.

## Decisions needing review

- **tide's geometry is copied, not shared.** `hammerspoon/timo/geometry.lua`
  is tide's file unchanged, and CI fails if they drift
  (`make check-geometry`). The alternative is a git submodule of tide.
  Reversible: swap the copy for the submodule path.
- **No frame-offset store.** tico stores, per app, how far a window's frame
  lands from where it asked (tico SPEC.md §5.3). timo leaves an app that
  rounds its size where it settled. Reversible: add the store in `wm.lua`'s
  retile if gaps or overlaps show up on a Mac.
- **The master count never drops below one,** in every mode. tide's tile
  can go to none. Reversible: one line in `layout.nmaster`.
- **How timo tells Karabiner is ready:** its config has a rule whose
  description starts `timo:`, and `Karabiner-Core-Service` or
  `karabiner_grabber` is running, checked every 30 s. Unverified on a Mac.
  Reversible: `keys.karabiner_ready`.
- **Insert is bound as the Mac's Help key,** which a PC keyboard's Insert
  sends *(unverified)*. Reversible: one line in `keys.map`.
- **Every new float is centered,** even one that opens where it remembers
  being. SPEC.md §5.1 wants those left in place, but timo can't yet tell
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
  `timo.toggle_focus_follows_mouse()` from Hammerspoon's console, or
  `focus_follows_mouse = false` in `start()`. Reversible: bind it in
  `keys.map`.
- **A window minimized before timo first starts counts as yours,** so timo
  never restores something you put away. Reversible: `wm.add`.
- **Restarts match windows by id only.** An app that quits and relaunches
  gets new window ids, and its windows join the workspace showing; SPEC.md
  §6.3's matching by app and title is still to do. Reversible: add it to
  `wm.add`.
- **A display that goes away hides its workspace;** Super+N brings it back
  on the display that's left. Reversible: `wm.map_screens`.
- **Hammerspoon's own console floats** by a built-in rule. Reversible: drop
  the rule.
