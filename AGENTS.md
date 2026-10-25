---
last_modified: 2026-10-25
---

# AGENTS.md

`CLAUDE.md` is a symlink to this file, so every agent reads the same
conventions. Edit `AGENTS.md` and bump `last_modified`.

## Talking to the user

- **Claude Code only: reply only in the turn-ending message** (maintainer,
  2026-10-25). The Claude app reliably shows just a turn's last message, so
  text between tool calls can be lost. Answer a mid-turn ("sent while you
  were working") message there too, at a stopping point soon.
