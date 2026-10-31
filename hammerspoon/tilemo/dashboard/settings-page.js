// tilemo's settings page (SPEC.md §15): the clocks and Start at login's
// commands, as tide's Clocks and Start at login pages (tide SPEC.md §16).
// It changes ~/.config/tide/clocks.local.json and startup.local.json only,
// with tide's own functions, so a change made here shows on tide too. And
// the muted apps and sites (SPEC.md §14.2), each with an Unmute button.
// tilemo fills it with tilemo.update({ clockFiles, startupFiles, muted })
// and hears back through the "tilemo" message handler: { write: text } for
// clocks.local.json, { writeStartup: text } for startup.local.json,
// { unmute: entry }, or { close: true }. tilemo.reveal(id) scrolls to a
// section, for the launcher's rows.

import { editableClocks, editedClocks, movedClock, relabeledClock, withClock, withoutClock } from "./tide-clocks.js";
import { editableStartup, editedStartup, movedCommand, withCommand, withoutCommand } from "./tide-startup.js";
import { historySummary, loadClipboardSettings, steppedMax, withSetting } from "./tide-clipboard.js";
import { isZone, localText, sharedText } from "./settings.js";

const send = (msg) => window.webkit?.messageHandlers?.tilemo?.postMessage(msg);

let files = null;
let muted = [];
let startupFiles = null;
let clipboardFiles = null;
let clipboardCount = 0;
// The settings tilemo has in effect, the fallback when a file is wrong.
let clipboardInEffect;

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

// A startup file's text, or null when there's none.
const startupText = (which) => (typeof startupFiles?.[which] === "string" ? startupFiles[which] : null);

const STARTUP_SOURCES = {
  "startup.local.json": "From startup.local.json, this Mac's own list.",
  "startup.json": "From startup.json, shared with tide. A change saves this Mac's own list to startup.local.json.",
};

function showStartupError(text) {
  document.getElementById("startup-error").textContent = text;
}

// As change() is for the clocks: tide's startup functions, saved to
// startup.local.json, shown at once.
function changeStartup(fn) {
  const r = editedStartup(startupText("shared"), startupText("local"), fn);
  if (r.error) {
    showStartupError(r.error);
    return false;
  }
  showStartupError("");
  send({ writeStartup: r.text });
  startupFiles = { ...startupFiles, local: r.text };
  renderStartup();
  return true;
}

function renderStartup() {
  const list = document.getElementById("startup-list");
  list.replaceChildren();
  const base = editableStartup(startupText("shared"), startupText("local"));
  const add = document.getElementById("add-command");
  const source = document.getElementById("startup-source");
  if (base.error) {
    source.textContent = "";
    showStartupError(`${base.error}. Fix the file to change the commands here.`);
    add.disabled = true;
    return;
  }
  add.disabled = false;
  source.textContent = base.source ? STARTUP_SOURCES[base.source] : "None yet. The first saves this Mac's own list to startup.local.json.";
  if (base.commands.length === 0) {
    list.append(el("li", "Nothing runs at login."));
    return;
  }
  base.commands.forEach((c, i) => {
    const li = el("li");
    li.append(
      el("span", c),
      button("↑", `Move ${c} up`, i === 0, () => changeStartup((cs) => movedCommand(cs, i, c, -1))),
      button("↓", `Move ${c} down`, i === base.commands.length - 1, () => changeStartup((cs) => movedCommand(cs, i, c, 1))),
      button("✕", `Remove ${c}`, false, () => changeStartup((cs) => withoutCommand(cs, i, c))),
    );
    list.append(li);
  });
}

// The Clipboard section, as tide's Clipboard page: the history on or off,
// how many copies it keeps, and Clear history. Changes go to
// clipboard.local.json, key by key, with tide's own functions.
const clipboardText = (which) => (typeof clipboardFiles?.[which] === "string" ? clipboardFiles[which] : null);

function clipboardSettings() {
  return loadClipboardSettings(clipboardText("shared"), clipboardText("local"), clipboardInEffect);
}

function setClipboard(key, value) {
  const r = withSetting(clipboardText("local"), key, value);
  const error = document.getElementById("clipboard-error");
  if (r.error) {
    error.textContent = r.error;
    return;
  }
  error.textContent = "";
  send({ writeClipboard: r.text });
  clipboardFiles = { ...clipboardFiles, local: r.text };
  renderClipboard();
}

function renderClipboard() {
  const { settings: s, errors } = clipboardSettings();
  const count = clipboardCount === 1 ? "1 copy kept now" : `${clipboardCount} copies kept now`;
  document.getElementById("clipboard-summary").textContent = `${historySummary(s)}. ${count}.`;
  document.getElementById("clipboard-error").textContent = errors.length ? `${errors.join("; ")}. Fix the file to change these here.` : "";
  const toggle = document.getElementById("clipboard-history");
  toggle.textContent = s.history ? "History on" : "History off";
  toggle.setAttribute("aria-pressed", String(s.history));
  document.getElementById("clipboard-max").textContent = String(s.maxItems);
  for (const id of ["clipboard-history", "clipboard-fewer", "clipboard-more"]) {
    document.getElementById(id).disabled = errors.length > 0;
  }
  document.getElementById("clipboard-fewer").disabled ||= steppedMax(s.maxItems, -1) === s.maxItems;
  document.getElementById("clipboard-more").disabled ||= steppedMax(s.maxItems, 1) === s.maxItems;
  document.getElementById("clipboard-clear").disabled = clipboardCount === 0;
}

document.getElementById("clipboard-history").addEventListener("click", () => {
  setClipboard("history", !clipboardSettings().settings.history);
});
document.getElementById("clipboard-fewer").addEventListener("click", () => {
  setClipboard("maxItems", steppedMax(clipboardSettings().settings.maxItems, -1));
});
document.getElementById("clipboard-more").addEventListener("click", () => {
  setClipboard("maxItems", steppedMax(clipboardSettings().settings.maxItems, 1));
});
document.getElementById("clipboard-clear").addEventListener("click", () => send({ clearClipboard: true }));

// Each muted entry: an app's bundle id, or site:<host>, shown as the host.
function renderMuted() {
  const list = document.getElementById("muted-list");
  list.replaceChildren();
  if (muted.length === 0) {
    list.append(el("li", "Nothing is muted."));
    return;
  }
  for (const entry of muted) {
    const name = entry.startsWith("site:") ? entry.slice(5) : entry;
    const li = el("li");
    li.append(el("span", name), button("Unmute", `Unmute ${name}`, false, () => send({ unmute: entry })));
    list.append(li);
  }
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

document.getElementById("add-command").addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  const input = e.target;
  if (changeStartup((cs) => withCommand(cs, input.value))) input.value = "";
});

// tilemo checks a typed entry with its mute module, mutes it and hands the
// list back, or calls tilemo.mutedError(why, entry).
document.getElementById("add-muted").addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  const entry = e.target.value.trim();
  if (entry === "") return;
  document.getElementById("muted-error").textContent = "";
  send({ mute: entry });
  e.target.value = "";
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") send({ close: true });
});

window.tilemo = {
  update(state) {
    files = state.clockFiles;
    startupFiles = state.startupFiles ?? null;
    clipboardFiles = state.clipboardFiles ?? null;
    clipboardCount = Number.isInteger(state.clipboardCount) ? state.clipboardCount : 0;
    const e = state.clipboardSettings;
    clipboardInEffect = e && typeof e.history === "boolean" && Number.isInteger(e.maxItems) ? e : undefined;
    muted = Array.isArray(state.muted) ? state.muted : [];
    // New files: what went wrong before is about the old ones.
    showError("");
    showStartupError("");
    document.getElementById("muted-error").textContent = "";
    render();
    renderStartup();
    renderClipboard();
    renderMuted();
  },
  // The clipboard history's count, from tilemo as copies come and go:
  // only the Clipboard section redraws.
  count(n) {
    clipboardCount = Number.isInteger(n) ? n : 0;
    renderClipboard();
  },
  mutedError(why, entry) {
    document.getElementById("muted-error").textContent = why;
    const input = document.getElementById("add-muted");
    if (input.value === "") input.value = entry ?? "";
  },
  reveal(id) {
    document.getElementById(id)?.scrollIntoView?.({ block: "start" });
  },
};
