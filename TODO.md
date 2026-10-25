# TODO

## Next

The Hammerspoon version, in the order SPEC.md §18 sets:

1. Tiling and keys: layouts, floats, the window keys. **This PR.**
2. The mouse: edge drags set the split, Super+drag moves and resizes,
   Super+middle-click maximizes, resize mode (SPEC.md §5.3).
3. Focus follows mouse (SPEC.md §5.2).
4. Workspaces by minimizing, displays and restarts (SPEC.md §6).
5. The launcher, app keys, the dashboard and bar, attention
   (SPEC.md §7–§9, §14).
6. conf: the Karabiner rule that turns Win+key into Ctrl+Option+Command+key
   (description starting `timo:`). scripts: `setup-macos` installs
   Hammerspoon and timo, and frees the keys in SPEC.md §7.3.

## Decisions needing review

- **tide's geometry is copied, not shared.** `hammerspoon/timo/geometry.lua`
  is tide's file unchanged, and CI fails if they drift
  (`make check-geometry`). The alternative is a git submodule of tide.
  Reversible: swap the copy for the submodule path.
- **One workspace per display until workspaces land.** Each display's
  workspace is numbered in display order. Reversible: PR 4 replaces it.
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
- **Hammerspoon's own console floats** by a built-in rule. Reversible: drop
  the rule.
