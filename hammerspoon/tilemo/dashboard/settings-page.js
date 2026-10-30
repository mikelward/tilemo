// tilemo's settings page (SPEC.md §15): the clocks, as tide's Clocks page
// (tide SPEC.md §16). It changes ~/.config/tide/clocks.local.json only, with
// tide's own functions, so a change made here shows on tide too. tilemo
// fills it with tilemo.update({ clockFiles }) and hears back through the
// "tilemo" message handler: { write: text } for clocks.local.json, or
// { close: true }.

import { editableClocks, editedClocks, movedClock, relabeledClock, withClock, withoutClock } from "./tide-clocks.js";
import { isZone, localText, sharedText } from "./settings.js";

const send = (msg) => window.webkit?.messageHandlers?.tilemo?.postMessage(msg);

let files = null;

const SOURCES = {
  "clocks.local.json": "From clocks.local.json, this Mac's own list.",
  "clocks.json": "From clocks.json, shared with tide. A change saves this Mac's own list to clocks.local.json.",
};
const DEFAULTS = "tilemo's defaults. A change saves them to clocks.local.json.";

function showError(text) {
  document.getElementById("error").textContent = text;
}

// Applies `change`, one of tide's list functions, and asks tilemo to save
// the result; tilemo hands the files back once it has. The page shows the
// result at once, so a second change made before then builds on this one
// rather than undoing it.
function change(fn) {
  const r = editedClocks(sharedText(files), localText(files), fn);
  if (r.error) {
    showError(r.error);
    return false;
  }
  showError("");
  send({ write: r.text });
  files = { ...files, local: r.text };
  render();
  return true;
}

function el(tag, text) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  return e;
}

function button(text, label, disabled, onClick) {
  const b = el("button", text);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.disabled = disabled;
  b.addEventListener("click", onClick);
  return b;
}

function render() {
  const list = document.getElementById("clock-list");
  list.replaceChildren();
  const base = editableClocks(sharedText(files), localText(files));
  const add = document.getElementById("add-zone");
  if (base.error) {
    document.getElementById("source").textContent = "";
    showError(`${base.error}. Fix the file to change the clocks here.`);
    add.disabled = true;
    return;
  }
  add.disabled = false;
  // Without a clocks.json, tilemo's defaults stand in for one.
  const source = base.source === "clocks.json" && typeof files?.shared !== "string" ? null : base.source;
  document.getElementById("source").textContent = source ? SOURCES[source] : DEFAULTS;
  base.clocks.forEach((c, i) => {
    const li = el("li");
    const label = el("input");
    label.value = c.label;
    label.setAttribute("aria-label", `Label for ${c.zone}`);
    label.addEventListener("keydown", (e) => {
      if (e.key === "Enter") change((cs) => relabeledClock(cs, i, c.zone, label.value));
    });
    li.append(
      el("span", c.zone),
      label,
      button("↑", `Move ${c.zone} left`, i === 0, () => change((cs) => movedClock(cs, i, c.zone, -1))),
      button("↓", `Move ${c.zone} right`, i === base.clocks.length - 1, () => change((cs) => movedClock(cs, i, c.zone, 1))),
      button("✕", `Remove ${c.zone}`, false, () => change((cs) => withoutClock(cs, i, c.zone))),
    );
    list.append(li);
  });
  const local = el("li", `${Intl.DateTimeFormat().resolvedOptions().timeZone} (local)`);
  local.className = "local";
  list.append(local);
}

document.getElementById("add-zone").addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  const input = e.target;
  const zone = input.value.trim();
  // tide checks a zone's form; Intl also knows whether it exists.
  if (zone !== "" && !isZone(zone)) {
    showError(`unknown time zone ${zone}; use a zone ID such as America/Los_Angeles`);
    return;
  }
  if (change((cs) => withClock(cs, zone))) input.value = "";
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") send({ close: true });
});

window.tilemo = {
  update(state) {
    files = state.clockFiles;
    // New files: what went wrong before is about the old ones.
    showError("");
    render();
  },
};
