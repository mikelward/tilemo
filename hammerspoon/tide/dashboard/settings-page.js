// tide's settings page (SPEC.md §15): the clocks, the layouts, the
// workspaces and Start at login's commands, as tide's Clocks, Layouts,
// Workspaces and Start at login pages (tide SPEC.md §16). It changes
// ~/.config/tide/clocks.local.json, layouts.local.json,
// workspaces.local.json and startup.local.json only, with tide's own
// functions, so a change made here shows on tide too. And the muted apps
// and sites (SPEC.md §14.2), each with an Unmute button. tide fills it
// with tide.update({ clockFiles, layoutFiles, layoutBase, workspaceFiles,
// workspaceBase, startupFiles, muted }) and hears back through the
// "tide" message handler: { write: text } for clocks.local.json,
// { writeLayouts: text } for layouts.local.json, { writeWorkspaces: text }
// for workspaces.local.json, { writeStartup: text } for startup.local.json,
// { unmute: entry }, the Floating section's { floatAdd }, { floatMove } and
// { floatRemove }, { writeInput: text } for input.local.json's Mouse
// settings, { open: name } for a section's button to a System
// Settings pane or a helper (links.lua), { karabinerRule } for a Keyboard
// switch, the Setup checklist's { setupTick } and { setupRefresh }, or
// { close: true }. Keyboard's Shortcuts, tide's key bindings,
// come in update()'s `shortcuts` and are read-only.
// The sidebar, update()'s `sidebar`, lists the pages under their groups, as
// tide's settings panel does, and one page shows at a time.
// tide.reveal(id) shows a page, or the part of one, for the launcher's
// rows.

import { barredClock, editableClocks, editedClocks, inBar, movedClock, relabeledClock, withClock, withoutClock } from "./tide-clocks.js";
import { editableStartup, editedStartup, movedCommand, withCommand, withoutCommand } from "./tide-startup.js";
import { ageText, historySummary, loadClipboardSettings, steppedAge, steppedMax, withSetting } from "./tide-clipboard.js";
import {
  effectiveLayouts, formatLayout, layoutChoices, layoutRows, loadLayouts, shownLayout, steppedLayout, steppedSingle,
  withLayoutSetting,
} from "./tide-layouts.js";
import {
  formatValue, loadInput, shown as shownInput, stepped as steppedInput, withSetting as withInputSetting,
} from "./tide-input.js";
import {
  ASK_LABEL, LISTS, PINNED_HINT, PINNED_LABEL, editedList, editedWorkspace, itemNote, movedItem, withAskForName,
  withItem, withPinned, withoutItem, withoutPinned, workspaceHeading,
} from "./tide-workspacepage.js";
import { loadWorkspaceSettings, workspaceSetting } from "./tide-workspacenames.js";
import {
  MODE_CHOICES, POSITION_CHOICES, WALLPAPER_COLORS, clockTime, dimStrength, formatDim, loadAppearance, parseCoordinate,
  positionAt, steppedDim, steppedModeAt, steppedPositionAt, steppedTimePast, wallpaperColor,
  withSetting as withAppearance,
} from "./tide-appearance.js";
import {
  DEFAULT_IDLE, STEPS as IDLE_STEPS, SWITCHES as IDLE_SWITCHES, formatDuration, loadIdle, stepped as steppedIdle,
  withSetting as withIdle,
} from "./tide-idle.js";
import {
  DAYS, DAY_LABELS, loadNotificationSettings, steppedDndTime, withDayToggled, withSetting as withNotification,
} from "./tide-dnd.js";
import { isZone, localText, sharedText } from "./settings.js";
import { steppedPointer } from "./linearmouse.js";

const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage(msg);

let files = null;
let muted = [];
let startupFiles = null;
let clipboardFiles = null;
let appearanceFiles = null;
let layoutFiles = null;
let inputFiles = null;
// What's wrong with LinearMouse, from tide, shown with the Mouse rows.
let mouseProblem = "";
// Every mouse's pointer as LinearMouse has it: speed and acceleration, each
// missing while it's left to macOS.
let mousePointer = {};
// What the files lay over, in their names: start()'s layout, which may not
// be tide's defaults. Empty for tide's defaults alone.
let layoutBase = {};
let clipboardCount = 0;
let workspaceFiles = null;
// What the workspaces files lay over: start()'s lists, or tide's
// defaults, as { standing, inApps }.
let workspaceBase = {};
// The settings tide has in effect, the fallback when a file is wrong.
let clipboardInEffect;

const SOURCES = {
  "clocks.local.json": "From clocks.local.json, this Mac's own list.",
  "clocks.json": "From clocks.json, shared with tide. A change saves this Mac's own list to clocks.local.json.",
};
const DEFAULTS = "tide's defaults. A change saves them to clocks.local.json.";

function showError(text) {
  document.getElementById("error").textContent = text;
}

// Applies `change`, one of tide's list functions, and asks tide to save
// the result; tide hands the files back once it has. The page shows the
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

// The icon a button's glyph stands for, drawn in its place as tide's
// panel draws one (settings.html's [data-icon]); its label says what it does.
const ICONS = { "↑": "up", "↓": "down", "✕": "delete", "−": "less", "+": "more", "‹": "prev", "›": "next" };

function button(text, label, disabled, onClick) {
  const b = el("button", text);
  b.type = "button";
  b.setAttribute("aria-label", label);
  if (ICONS[text]) b.setAttribute("data-icon", ICONS[text]);
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
  // Without a clocks.json, tide's defaults stand in for one.
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
    // In the bar, or only in the dashboard's clock panel.
    const bar = el("input");
    bar.type = "checkbox";
    bar.checked = inBar(c);
    bar.setAttribute("aria-label", `Show ${c.zone} in the bar`);
    bar.addEventListener("change", () => change((cs) => barredClock(cs, i, c.zone, bar.checked)));
    const barLabel = el("label");
    barLabel.append(bar, " Bar");
    li.append(
      el("span", c.zone),
      label,
      barLabel,
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
  document.getElementById("clipboard-age").textContent = ageText(s.maxAgeDays);
  for (const id of ["clipboard-history", "clipboard-fewer", "clipboard-more", "clipboard-shorter", "clipboard-longer"]) {
    document.getElementById(id).disabled = errors.length > 0;
  }
  document.getElementById("clipboard-fewer").disabled ||= steppedMax(s.maxItems, -1) === s.maxItems;
  document.getElementById("clipboard-more").disabled ||= steppedMax(s.maxItems, 1) === s.maxItems;
  document.getElementById("clipboard-shorter").disabled ||= steppedAge(s.maxAgeDays, -1) === s.maxAgeDays;
  document.getElementById("clipboard-longer").disabled ||= steppedAge(s.maxAgeDays, 1) === s.maxAgeDays;
  document.getElementById("clipboard-clear").disabled = clipboardCount === 0;
}

// The Sound page, as tide's (tide SPEC.md §16): for the output, then the
// input, its mute, a slider and its level, then each device, the one in use
// lit. A click on another uses it; the slider sets the volume as it moves,
// or once it's let go for a monitor over DDC (`live`). tide answers each
// change with tide.sound(), what macOS says now.
const SOUND = {
  output: { volume: "soundVolume", mute: "soundMute", use: "soundOutput", icon: "output", on: "speaker-on", off: "speaker-off" },
  input: { volume: "inputVolume", mute: "inputMute", use: "soundInput", icon: "input", on: "mic", off: "mic-off" },
};
let soundState = {};
// What the page shows now, so the same again draws nothing, and the
// bar's refreshes don't take a control from under the keyboard.
let soundDrawn = "";
// The side whose slider is held: an update mustn't move it under you.
let soundDragging = null;

// Draws again with `draw()`, keeping the keyboard on the control it was
// on, by its data-key, so arrow keys go on stepping a slider.
function keepingFocus(draw) {
  const key = document.activeElement?.getAttribute?.("data-key");
  draw();
  if (key) document.querySelector?.(`[data-key="${key}"]`)?.focus?.();
}

function renderVolume(kind, s) {
  const k = SOUND[kind];
  const row = document.getElementById(`sound-${kind}-volume`);
  if (soundDragging === kind) return;
  row.replaceChildren();
  row.hidden = typeof s?.volume !== "number";
  if (row.hidden) return;
  const name = s.name || kind;
  const mute = button(s.muted ? "Unmute" : "Mute", `${s.muted ? "Unmute" : "Mute"} ${name}`, !s.can_mute,
    () => send({ [k.mute]: !s.muted }));
  mute.setAttribute("data-icon", s.muted ? k.off : k.on);
  mute.setAttribute("data-key", `${kind}-mute`);
  const slider = el("input");
  slider.type = "range";
  slider.min = "0";
  slider.max = "100";
  slider.step = "1";
  slider.value = String(s.volume);
  slider.setAttribute("aria-label", `${name}'s volume`);
  slider.setAttribute("data-key", `${kind}-volume`);
  const level = el("span", `${s.muted ? 0 : s.volume}%`);
  level.className = "value";
  slider.addEventListener("input", () => {
    soundDragging = kind;
    // Moved here, the slider no longer shows what was drawn, so macOS's
    // answer is drawn even if it's the same level, as a refusal is.
    soundDrawn = "";
    level.textContent = `${slider.value}%`;
    if (s.live) send({ [k.volume]: Number(slider.value) });
  });
  slider.addEventListener("change", () => {
    soundDragging = null;
    send({ [k.volume]: Number(slider.value) });
  });
  row.append(mute, slider, level);
}

function renderDevices(kind, s) {
  const k = SOUND[kind];
  const list = document.getElementById(`sound-${kind}s`);
  list.replaceChildren();
  for (const d of Array.isArray(s?.devices) ? s.devices : []) {
    const li = el("li");
    const b = button(d.name, d.current ? `${d.name}, in use` : `Use ${d.name}`, false, () => {
      if (!d.current) send({ [k.use]: d.uid });
    });
    b.setAttribute("data-icon", k.icon);
    b.setAttribute("aria-current", String(d.current === true));
    b.setAttribute("data-key", `${kind}-device-${d.uid}`);
    li.append(b);
    list.append(li);
  }
}

function renderSound(s) {
  soundState = isObject(s) ? s : {};
  const drawn = JSON.stringify(soundState);
  if (drawn === soundDrawn) return;
  // A held slider's side isn't drawn, so nothing is taken as drawn until
  // it's let go, and tide's answer to that draws it, even if it's the
  // same state again.
  soundDrawn = soundDragging === null ? drawn : "";
  keepingFocus(() => {
    for (const kind of ["output", "input"]) {
      renderVolume(kind, soundState[kind]);
      renderDevices(kind, soundState[kind]);
    }
  });
  const inputs = soundState.input?.devices;
  document.getElementById("sound-input-heading").hidden = !(Array.isArray(inputs) && inputs.length > 0);
}

// The Displays page, as tide's (tide SPEC.md §16): for each display, its
// name, then its resolution, ‹ and ›, through the sizes macOS offers at its
// scale; where it goes beside the main display, ‹ and ›; Make main; and its
// brightness, where macOS can set it. tide answers each change with
// tide.displays(), what macOS says now.
// The display whose brightness slider is held, so an update doesn't move
// it under you.
let displayDragging = null;
// What the page shows now, as soundDrawn is Sound's.
let displaysDrawn = "";

// A button that keeps its place for the keyboard across a redraw.
function keyed(node, key) {
  node.setAttribute("data-key", key);
  return node;
}

function renderDisplays(st) {
  if (displayDragging !== null) return;
  const drawn = JSON.stringify(isObject(st) ? st : {});
  if (drawn === displaysDrawn) return;
  displaysDrawn = drawn;
  keepingFocus(() => drawDisplays(st));
}

function drawDisplays(st) {
  const box = document.getElementById("display-list");
  box.replaceChildren();
  const places = Array.isArray(st?.places) ? st.places : [];
  for (const d of Array.isArray(st?.displays) ? st.displays : []) {
    box.append(el("h2", d.main ? `${d.name} · main` : d.name));
    const sizes = Array.isArray(d.sizes) ? d.sizes : [];
    const at = sizes.findIndex((s) => s.current);
    if (at >= 0) {
      const size = (by) => send({ displaySize: { uuid: d.uuid, w: sizes[at + by].w, h: sizes[at + by].h } });
      const value = el("span", `${sizes[at].w} × ${sizes[at].h}`);
      value.className = "value";
      const row = el("div");
      row.className = "row choice";
      row.append(el("span", "Resolution"),
        keyed(button("‹", `Smaller: ${d.name}`, at === 0, () => size(-1)), `${d.uuid}-smaller`), value,
        keyed(button("›", `Larger: ${d.name}`, at === sizes.length - 1, () => size(1)), `${d.uuid}-larger`));
      box.append(row);
    }
    if (d.main) {
      // Nothing to place it beside.
    } else if (places.length > 0) {
      // Overlapping the main display, as a mirror does, it's nowhere yet:
      // › starts at the first place, and ‹ at the last.
      const i = places.findIndex((p) => p.place === d.place);
      const place = (by) => {
        const next = i < 0 ? (by > 0 ? 0 : places.length - 1) : (i + by + places.length) % places.length;
        send({ displayPlace: { uuid: d.uuid, place: places[next].place } });
      };
      const value = el("span", i < 0 ? "Elsewhere" : places[i].label);
      value.className = "value";
      const row = el("div");
      row.className = "row choice";
      row.append(el("span", "Place"),
        keyed(button("‹", `Previous place: ${d.name}`, false, () => place(-1)), `${d.uuid}-previous`), value,
        keyed(button("›", `Next place: ${d.name}`, false, () => place(1)), `${d.uuid}-next`));
      box.append(row);
      const main = el("p");
      main.className = "row";
      const name = el("span", "Main display");
      name.className = "name";
      main.append(name, keyed(button("Make main", `Make ${d.name} the main display`, false,
        () => send({ displayMain: d.uuid })), `${d.uuid}-main`));
      box.append(main);
    }
    if (typeof d.brightness === "number") {
      const row = el("div");
      row.className = "row volume";
      const icon = el("span");
      icon.setAttribute("data-icon", "brightness");
      icon.className = "icon";
      const slider = el("input");
      slider.type = "range";
      slider.min = "0";
      slider.max = "100";
      slider.step = "1";
      slider.value = String(d.brightness);
      slider.setAttribute("aria-label", `${d.name}'s brightness`);
      keyed(slider, `${d.uuid}-brightness`);
      const level = el("span", `${d.brightness}%`);
      level.className = "value";
      slider.addEventListener("input", () => {
        displayDragging = d.uuid;
        // As Sound's: macOS's answer is drawn even if it's what was.
        displaysDrawn = "";
        level.textContent = `${slider.value}%`;
        // Over DDC, each set is a slow run of the tool: set once let go.
        if (!d.over_ddc) send({ displayBrightness: { uuid: d.uuid, level: Number(slider.value) } });
      });
      slider.addEventListener("change", () => {
        displayDragging = null;
        send({ displayBrightness: { uuid: d.uuid, level: Number(slider.value) } });
      });
      row.append(icon, slider, level);
      box.append(row);
    }
  }
}

// Notifications' Do Not Disturb on a schedule, as tide's page (tide SPEC.md
// §16): On or Off, its times, − and + a quarter hour past the other, and
// the days a window starts on. Shared with tide's notifications.json; a
// change goes to notifications.local.json ({ writeNotifications: text }),
// and tide runs it (dndsched_hs.lua). Critical alerts breaking through
// is tide's server's alone, so it isn't here.
let notificationFiles = null;
const notificationText = (which) => (typeof notificationFiles?.[which] === "string" ? notificationFiles[which] : null);
const DND_TIMES = [{ key: "dndFrom", label: "From", other: "dndTo" }, { key: "dndTo", label: "To", other: "dndFrom" }];

function writeNotifications(r) {
  const error = document.getElementById("dnd-error");
  if (r.error) {
    error.textContent = r.error;
    return;
  }
  error.textContent = "";
  notificationFiles = { ...notificationFiles, local: r.text };
  send({ writeNotifications: r.text });
  renderDnd();
}

function renderDnd() {
  const shared = notificationText("shared");
  const own = notificationText("local");
  const { settings: s, errors } = loadNotificationSettings(shared, own);
  const bad = errors.length > 0;
  if (bad) document.getElementById("dnd-error").textContent = `${errors.join("; ")}. Fix the file to change these here.`;
  const set = (key, value) => writeNotifications(withNotification(shared, own, key, value));
  keepingFocus(() => {
    const row = document.getElementById("dnd-scheduled");
    row.replaceChildren();
    const name = el("span", "Do not disturb on a schedule");
    name.className = "name";
    const toggle = keyed(button(s.dndScheduled ? "On" : "Off", `Do not disturb on a schedule: ${s.dndScheduled ? "on" : "off"}`,
      bad, () => set("dndScheduled", !s.dndScheduled)), "dnd-scheduled");
    toggle.setAttribute("aria-pressed", String(s.dndScheduled === true));
    row.append(name, toggle);
    const times = document.getElementById("dnd-times");
    times.replaceChildren();
    const days = document.getElementById("dnd-days");
    days.replaceChildren();
    days.hidden = !s.dndScheduled;
    if (!s.dndScheduled) return;
    for (const t of DND_TIMES) {
      const li = el("li");
      const value = el("span", s[t.key]);
      value.className = "value";
      li.append(el("span", t.label),
        keyed(button("−", `Earlier: ${t.label}`, bad, () => set(t.key, steppedDndTime(s[t.key], -1, s[t.other]))), `${t.key}-earlier`),
        value,
        keyed(button("+", `Later: ${t.label}`, bad, () => set(t.key, steppedDndTime(s[t.key], 1, s[t.other]))), `${t.key}-later`));
      times.append(li);
    }
    const label = el("span", "Days");
    label.className = "name";
    days.append(label);
    DAYS.forEach((d, i) => {
      const on = s.dndDays.includes(d);
      const b = keyed(button(DAY_LABELS[i], `${d}: ${on ? "on" : "off"}`, bad,
        () => writeNotifications(withDayToggled(shared, own, d))), `dnd-day-${d}`);
      b.setAttribute("aria-pressed", String(on));
      days.append(b);
    });
  });
}

// The Idle page, as tide's (tide SPEC.md §16): whether tide's timeline
// runs, then each step's time with no input, − and + along tide's ladder,
// and Sleep when plugged in. Shared with tide's idle.json; a change goes to
// idle.local.json ({ writeIdle: text }), and tide runs the timeline as it
// says (idle_hs.lua). Off is macOS's own: no step set in either file.
let idleFiles = null;
const idleText = (which) => (typeof idleFiles?.[which] === "string" ? idleFiles[which] : null);

// Whether a file's text sets any of the timeline.
function setsIdle(text) {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length > 0;
  } catch {
    return false;
  }
}

function writeIdle(text) {
  idleFiles = { ...idleFiles, local: text };
  send({ writeIdle: text });
  renderIdle();
}

function setIdle(key, value) {
  const r = withIdle(idleText("local"), key, value);
  const error = document.getElementById("idle-error");
  if (r.error) {
    error.textContent = `${r.error}; not changing ${key}`;
    return;
  }
  error.textContent = "";
  writeIdle(r.text);
}

function renderIdle() {
  const { idle, errors } = loadIdle(idleText("shared"), idleText("local"));
  const bad = errors.length > 0;
  const shared = idleText("shared");
  const on = [shared, idleText("local")].some((t) => t !== null && setsIdle(t));
  document.getElementById("idle-error").textContent = bad ? `${errors.join("; ")}. Fix the file to change these here.` : "";
  keepingFocus(() => {
    const row = document.getElementById("idle-timeline");
    row.replaceChildren();
    const name = el("span", "Use tide's idle settings");
    name.className = "name";
    // On writes tide's timings as they stand; Off empties this Mac's file,
    // which can't turn off what the shared one sets.
    const toggle = keyed(button(on ? "On" : "Off", `Use tide's idle settings: ${on ? "on" : "off"}`, bad || (on && setsIdle(shared ?? "")), () => {
      if (on) return writeIdle("{}\n");
      const all = Object.fromEntries(Object.keys(DEFAULT_IDLE).map((k) => [k, idle[k]]));
      writeIdle(JSON.stringify(all, null, 2) + "\n");
    }), "idle-timeline");
    toggle.setAttribute("aria-pressed", String(on));
    row.append(name, toggle);
    const list = document.getElementById("idle-steps");
    list.replaceChildren();
    if (!on) return;
    for (const s of IDLE_STEPS) {
      const li = el("li");
      const value = el("span", formatDuration(idle[s.key]));
      value.className = "value";
      li.append(el("span", s.label),
        keyed(button("−", `Sooner: ${s.label}`, bad || steppedIdle(idle[s.key], -1) === idle[s.key],
          () => setIdle(s.key, steppedIdle(idle[s.key], -1))), `idle-${s.key}-sooner`), value,
        keyed(button("+", `Later: ${s.label}`, bad || steppedIdle(idle[s.key], 1) === idle[s.key],
          () => setIdle(s.key, steppedIdle(idle[s.key], 1))), `idle-${s.key}-later`));
      list.append(li);
    }
    for (const s of IDLE_SWITCHES) {
      const li = el("li");
      li.className = "switch";
      const sw = keyed(button(idle[s.key] ? "On" : "Off", `${s.label}: ${idle[s.key] ? "on" : "off"}`, bad,
        () => setIdle(s.key, !idle[s.key])), `idle-${s.key}`);
      sw.setAttribute("aria-pressed", String(idle[s.key] === true));
      li.append(el("span", s.label), sw);
      list.append(li);
    }
  });
}

// Keyboard's input sources, as tide's Keyboard page has its layouts: the
// ones macOS has on, the one in use lit, and a click to use another
// ({ inputSource: name }). tide answers with tide.inputSources().
let sourcesDrawn = "";

function renderInputSources(st) {
  const s = isObject(st) ? st : {};
  const drawn = JSON.stringify(s);
  if (drawn === sourcesDrawn) return;
  sourcesDrawn = drawn;
  const sources = Array.isArray(s.sources) ? s.sources : [];
  keepingFocus(() => {
    const list = document.getElementById("input-sources");
    list.replaceChildren();
    for (const src of sources) {
      const li = el("li");
      const b = keyed(button(src.name, src.current ? `${src.name}, in use` : `Use ${src.name}`, false, () => {
        if (!src.current) send({ inputSource: src.name });
      }), `source-${src.name}`);
      b.setAttribute("data-icon", "keyboard");
      b.setAttribute("aria-current", String(src.current === true));
      li.append(b);
      list.append(li);
    }
  });
  document.getElementById("input-sources-heading").hidden = sources.length === 0;
}

// The Network and Power pages: Wi-Fi On or Off, the network it's joined
// to and how the Mac's online; and the battery, as the bar's hover says
// it. tide answers a switch with tide.netpower(), once Wi-Fi's had
// time to change, and follows the bar as it reads them again.
let netpowerDrawn = "";

function renderNetpower(st) {
  const s = isObject(st) ? st : {};
  const drawn = JSON.stringify(s);
  if (drawn === netpowerDrawn) return;
  netpowerDrawn = drawn;
  const wifi = isObject(s.network?.wifi) ? s.network.wifi : null;
  keepingFocus(() => {
    const power = document.getElementById("wifi-power");
    power.replaceChildren();
    power.hidden = wifi === null;
    if (wifi) {
      const name = el("span", "Wi-Fi");
      name.className = "name";
      const toggle = keyed(button(wifi.on ? "On" : "Off", `Wi-Fi: ${wifi.on ? "on" : "off"}`, false,
        () => send({ wifiPower: !wifi.on })), "wifi-power");
      toggle.setAttribute("aria-pressed", String(wifi.on === true));
      power.append(name, toggle);
    }
  });
  const lines = [wifi?.on ? wifi.line : null, s.network?.online].filter((l) => typeof l === "string" && l !== "");
  document.getElementById("network-status").textContent = lines.length ? `${lines.join(". ")}.` : "";
  const battery = typeof s.power?.battery === "string" ? s.power.battery : "This Mac has no battery";
  document.getElementById("battery-status").textContent = battery;
}

// The Bluetooth page, as tide's Bluetooth popover (tide SPEC.md §7.4):
// Bluetooth On or Off, then, while it's on, the paired devices, connected
// first, each lit while connected, with its status. A click connects one,
// or disconnects one that's connected; one being either waits. tide reads
// them through blueutil, and answers with tide.bluetooth().
let bluetoothDrawn = "";

function renderBluetooth(st) {
  const s = isObject(st) ? st : {};
  const drawn = JSON.stringify(s);
  if (drawn === bluetoothDrawn) return;
  bluetoothDrawn = drawn;
  const devices = s.on === true && Array.isArray(s.devices) ? s.devices : [];
  keepingFocus(() => {
    const power = document.getElementById("bluetooth-power");
    power.replaceChildren();
    power.hidden = typeof s.on !== "boolean";
    if (!power.hidden) {
      const name = el("span", "Bluetooth");
      name.className = "name";
      // Waiting, it stays focusable, so the keyboard isn't dropped; a
      // click then asks nothing.
      const toggle = keyed(button(s.on ? "On" : "Off", `Bluetooth: ${s.on ? "on" : "off"}`, false,
        () => s.switching !== true && send({ bluetoothPower: !s.on })), "bluetooth-power");
      toggle.setAttribute("aria-pressed", String(s.on));
      toggle.setAttribute("aria-disabled", String(s.switching === true));
      power.append(name, toggle);
    }
    const list = document.getElementById("bluetooth-devices");
    list.replaceChildren();
    for (const d of devices) {
      const li = el("li");
      const label = d.status ? `${d.name} · ${d.status}` : d.name;
      const b = keyed(button(label, d.connected ? `Disconnect ${d.name}` : `Connect ${d.name}`, false,
        () => d.busy !== true && send(d.connected ? { bluetoothDisconnect: d.address } : { bluetoothConnect: d.address })),
        `bluetooth-${d.address}`);
      b.setAttribute("aria-disabled", String(d.busy === true));
      b.setAttribute("data-icon", "bluetooth");
      b.setAttribute("aria-current", String(d.connected === true));
      li.append(b);
      list.append(li);
    }
  });
  document.getElementById("bluetooth-devices-heading").hidden = devices.length === 0;
  document.getElementById("bluetooth-error").textContent = typeof s.problem === "string" ? s.problem : "";
}

// The Appearance page's wallpapers, light and dark, as tide's has them
// (tide SPEC.md §15, §16): appearance.json and appearance.local.json, read
// and changed with tide's own module, so the Mac's desktop shows the ones
// tide does. Enter sets one typed; its choose button asks tide for
// macOS's file dialog ({ pickWallpaper: key }), and tide answers with
// tide.setWallpaper(key, value). A change goes to appearance.local.json
// ({ writeAppearance: text }).
const WALLPAPERS = [
  { key: "lightWallpaper", label: "Light wallpaper" },
  { key: "darkWallpaper", label: "Dark wallpaper" },
];
const appearanceText = (which) => (typeof appearanceFiles?.[which] === "string" ? appearanceFiles[which] : null);

// A path, or a color as tide takes one, which tide draws into a picture
// (wallpaper_hs.lua).
function setWallpaper(key, value) {
  setAppearance(key, value);
}

// A wallpaper's colors, as tide's page has them (tide SPEC.md §16): its
// swatch opens them under its row, tide's palette's backgrounds and a field
// for any color, set with Enter. Choosing one sets it as the row's field
// would, and closes them; Escape, or a click anywhere else, closes them
// with nothing set. The wallpaper they're open for, by key, or "", and
// what's typed in their field, kept as tide draws the page again.
let colorsOpen = "";
let colorsTyped = null;

const focusKey = (key) => document.querySelector?.(`[data-key="${key}"]`)?.focus?.();

function openColors(key) {
  colorsOpen = colorsOpen === key ? "" : key;
  colorsTyped = null;
  renderAppearance();
  if (colorsOpen) focusKey(`colors-hex-${key}`);
}

// Back on the swatch for Escape; a click elsewhere leaves the keyboard on
// what was clicked, drawn again if it's one of the rows.
function closeColors(toSwatch) {
  const key = colorsOpen;
  colorsOpen = "";
  colorsTyped = null;
  renderAppearance();
  if (toSwatch) focusKey(`swatch-${key}`);
}

function chooseColor(key, value) {
  colorsOpen = "";
  colorsTyped = null;
  setWallpaper(key, value);
  // Drawn shut even when the value's refused.
  renderAppearance();
  focusKey(`swatch-${key}`);
}

// The swatch: the color set, or the colors' icon for a picture or none.
function swatchFor(w, shows, disabled) {
  const b = keyed(button("", `Colors for the ${w.label.toLowerCase()}`, disabled, () => openColors(w.key)), `swatch-${w.key}`);
  b.className = "swatch";
  b.setAttribute("data-colors", "");
  b.setAttribute("aria-expanded", String(colorsOpen === w.key));
  if (shows) b.setAttribute("style", `--swatch: ${shows}`);
  else b.setAttribute("data-icon", "color");
  return b;
}

// The colors, under the row: what's pointed at, tide's palette's
// backgrounds, the one set marked, and the field.
function colorsFor(w, shows) {
  const li = el("li");
  li.className = "colors";
  li.setAttribute("data-colors", "");
  const caption = el("span", w.label);
  caption.className = "caption";
  const grid = el("div");
  grid.className = "grid";
  for (const c of WALLPAPER_COLORS) {
    const b = keyed(button("", c.label, false, () => chooseColor(w.key, c.color)), `colors-${w.key}-${c.label}`);
    b.className = "swatch";
    b.setAttribute("title", c.label);
    b.setAttribute("style", `--swatch: ${c.color}`);
    b.setAttribute("aria-current", String(c.color === shows));
    b.addEventListener("mouseenter", () => { caption.textContent = c.label; });
    b.addEventListener("mouseleave", () => { caption.textContent = w.label; });
    grid.append(b);
  }
  const hex = keyed(el("input"), `colors-hex-${w.key}`);
  hex.value = colorsTyped ?? shows;
  hex.placeholder = "#rrggbb";
  hex.spellcheck = false;
  hex.setAttribute("aria-label", `Any color for the ${w.label.toLowerCase()}`);
  hex.addEventListener("input", () => { colorsTyped = hex.value; });
  hex.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && hex.value.trim() !== "") chooseColor(w.key, hex.value.trim());
  });
  li.append(caption, grid, hex);
  return li;
}

document.addEventListener("click", (e) => {
  if (colorsOpen && !e.target?.closest?.("[data-colors]")) closeColors(false);
});

// Set one of appearance.local.json's settings to `value`, or take it out
// for undefined, or say why not.
function setAppearance(key, value) {
  const error = document.getElementById("appearance-error");
  const r = withAppearance(appearanceText("local"), key, value, appearanceText("shared"));
  if (r.error) {
    error.textContent = `${r.error}; not changing ${key}`;
    return;
  }
  error.textContent = "";
  // Shown at once, before the folder's watcher brings the file back.
  appearanceFiles = { ...appearanceFiles, local: r.text };
  send({ writeAppearance: r.text });
  renderAppearance();
}

// Appearance's light or dark, as tide's page has it (tide SPEC.md §16):
// what shows now and until when, with Light now or Dark now; the mode, ‹
// and › through macOS's own, then tide's; By the clock's times, − and + a
// quarter hour; and the place Sunrise and sunset needs, typed and set with
// Enter. A change goes to appearance.local.json, as a wallpaper's does, and
// tide sets macOS's appearance as it says (theme_hs.lua), answering
// with tide.theme().
let themeState = {};
const OWN_MODE = { mode: undefined, label: "macOS's own" };
const THEME_TIMES = [{ key: "light", label: "Light from", other: "dark" }, { key: "dark", label: "Dark from", other: "light" }];
const THEME_PLACE = [{ key: "latitude", label: "Latitude, negative for south", example: "such as 37.8" }, { key: "longitude", label: "Longitude, negative for west", example: "such as -122.4" }];

// Whether a file's text sets a mode.
function setsMode(text) {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && "mode" in v;
  } catch {
    return false;
  }
}

function renderTheme(settings, bad) {
  const shared = appearanceText("shared");
  const chosen = [shared, appearanceText("local")].some((t) => t !== null && setsMode(t));
  keepingFocus(() => {
    const now = document.getElementById("theme-now");
    now.replaceChildren();
    if (typeof themeState.dark === "boolean") {
      const until = Number.isFinite(themeState.next) ? ` until ${clockTime(themeState.next)}` : "";
      const name = el("span", `${themeState.dark ? "Dark" : "Light"}${until}`);
      name.className = "name";
      const flip = themeState.dark ? "Light now" : "Dark now";
      now.append(name, keyed(button(flip, flip, false, () => send({ themeFlip: true })), "theme-flip"));
    }
    // macOS's own, then tide's; macOS's own only while the shared file
    // sets no mode, as only the local one can be changed here.
    const tide = Math.max(0, MODE_CHOICES.findIndex((c) => c.mode === settings.mode));
    const at = chosen ? tide + 1 : 0;
    const stepped = (by) => {
      if (at === 0) return by > 0 ? 1 : null;
      if (at === 1 && by < 0) return setsMode(shared ?? "") ? null : 0;
      const next = steppedModeAt(settings, tide, by) + 1;
      return next === at ? null : next;
    };
    const choose = (i) => setAppearance("mode", i === 0 ? undefined : MODE_CHOICES[i - 1].mode);
    const mode = document.getElementById("theme-mode");
    mode.replaceChildren();
    const value = el("span", at === 0 ? OWN_MODE.label : MODE_CHOICES[tide].label);
    value.className = "value";
    const prev = stepped(-1);
    const next = stepped(1);
    mode.append(el("span", "Mode"),
      keyed(button("‹", "Previous mode", bad || prev === null, () => choose(prev)), "theme-mode-prev"), value,
      keyed(button("›", "Next mode", bad || next === null, () => choose(next)), "theme-mode-next"));
    const times = document.getElementById("theme-times");
    times.replaceChildren();
    for (const t of chosen && settings.mode === "schedule" ? THEME_TIMES : []) {
      const li = el("li");
      const time = el("span", settings[t.key]);
      time.className = "value";
      // Past the other time, as the same for both isn't a schedule.
      const step = (by) => setAppearance(t.key, steppedTimePast(settings[t.key], by, settings[t.other]));
      li.append(el("span", t.label),
        keyed(button("−", `Earlier: ${t.label}`, bad, () => step(-1)), `theme-${t.key}-earlier`), time,
        keyed(button("+", `Later: ${t.label}`, bad, () => step(1)), `theme-${t.key}-later`));
      times.append(li);
    }
    const place = document.getElementById("theme-place");
    place.replaceChildren();
    for (const c of chosen ? THEME_PLACE : []) {
      const li = el("li");
      const input = el("input");
      input.value = settings[c.key] === undefined ? "" : String(settings[c.key]);
      input.placeholder = c.example;
      input.spellcheck = false;
      input.disabled = bad;
      input.setAttribute("aria-label", c.label);
      input.addEventListener("keydown", (e) => {
        if (e.key !== "Enter") return;
        if (input.value.trim() === "") return setAppearance(c.key, undefined);
        const got = parseCoordinate(c.key, input.value);
        if (got.error) {
          document.getElementById("appearance-error").textContent = `${got.error}; not changing ${c.key}`;
          return;
        }
        setAppearance(c.key, got.value);
      });
      li.append(el("span", c.label), keyed(input, `theme-${c.key}`));
      place.append(li);
    }
  });
}

function renderAppearance() {
  const { settings, errors } = loadAppearance(appearanceText("shared"), appearanceText("local"));
  if (errors.length) {
    document.getElementById("appearance-error").textContent = `${errors.join("; ")}. Fix the file to change these here.`;
  }
  renderTheme(settings, errors.length > 0);
  keepingFocus(() => renderWallpapers(settings, errors.length > 0));
  // The dim, as tide's page steps it: a point at a time, from none to half.
  const dim = dimStrength(settings);
  document.getElementById("dim-strength").textContent = formatDim(dim);
  document.getElementById("dim-less").disabled = errors.length > 0 || steppedDim(dim, -1) === dim;
  document.getElementById("dim-more").disabled = errors.length > 0 || steppedDim(dim, 1) === dim;
}

// The wallpapers' rows, and the colors under one if they're open; none
// can be changed while a file is `bad`.
function renderWallpapers(settings, bad) {
  const list = document.getElementById("wallpapers");
  list.replaceChildren();
  for (const w of WALLPAPERS) {
    const li = el("li");
    // Keyed, so a redraw keeps the keyboard in it.
    const input = keyed(el("input"), `wallpaper-${w.key}`);
    input.value = settings[w.key] ?? "";
    input.placeholder = "macOS's own";
    input.spellcheck = false;
    input.disabled = bad;
    input.setAttribute("aria-label", w.label);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") setWallpaper(w.key, input.value.trim());
    });
    const choose = keyed(button("…", `Choose the ${w.label.toLowerCase()}`, bad, () => send({ pickWallpaper: w.key })),
      `choose-${w.key}`);
    choose.setAttribute("data-icon", "folder");
    const shows = wallpaperColor(settings[w.key] ?? "");
    li.append(el("span", w.label), input, swatchFor(w, shows, bad), choose);
    list.append(li);
    if (colorsOpen === w.key && !bad) list.append(colorsFor(w, shows));
    // A color has nothing to place.
    if (!shows) list.append(positionFor(w, settings, bad));
  }
}

// How a wallpaper's picture is placed, as tide's page has it (tide SPEC.md
// §15, §16): its own mode's, ‹ and › stepping through tide's positions
// into appearance.local.json; tide places the desktop picture so
// (wallpaper_hs.lua).
function positionFor(w, settings, bad) {
  const dark = w.key === "darkWallpaper";
  const key = dark ? "darkWallpaperPosition" : "lightWallpaperPosition";
  const at = positionAt(settings, dark);
  const step = (by) => {
    const next = steppedPositionAt(at, by);
    if (next !== at) setAppearance(key, POSITION_CHOICES[next].position);
  };
  const li = el("li");
  li.className = "position";
  const value = el("span", POSITION_CHOICES[at].label);
  value.className = "value";
  li.append(el("span", `${w.label} position`),
    keyed(button("‹", `Previous position: ${w.label}`, bad || steppedPositionAt(at, -1) === at, () => step(-1)), `${key}-prev`),
    value,
    keyed(button("›", `Next position: ${w.label}`, bad || steppedPositionAt(at, 1) === at, () => step(1)), `${key}-next`));
  return li;
}

const currentDim = () => dimStrength(loadAppearance(appearanceText("shared"), appearanceText("local")).settings);
document.getElementById("dim-less").addEventListener("click", () => setAppearance("dimStrength", steppedDim(currentDim(), -1)));
document.getElementById("dim-more").addEventListener("click", () => setAppearance("dimStrength", steppedDim(currentDim(), 1)));

document.getElementById("clipboard-history").addEventListener("click", () => {
  setClipboard("history", !clipboardSettings().settings.history);
});
document.getElementById("clipboard-fewer").addEventListener("click", () => {
  setClipboard("maxItems", steppedMax(clipboardSettings().settings.maxItems, -1));
});
document.getElementById("clipboard-more").addEventListener("click", () => {
  setClipboard("maxItems", steppedMax(clipboardSettings().settings.maxItems, 1));
});
document.getElementById("clipboard-shorter").addEventListener("click", () => {
  setClipboard("maxAgeDays", steppedAge(clipboardSettings().settings.maxAgeDays, -1));
});
document.getElementById("clipboard-longer").addEventListener("click", () => {
  setClipboard("maxAgeDays", steppedAge(clipboardSettings().settings.maxAgeDays, 1));
});
document.getElementById("clipboard-clear").addEventListener("click", () => send({ clearClipboard: true }));

// The Layouts section, as tide's Layouts page (tide SPEC.md §16): its rows,
// values and steps are tide's own, and a change writes only
// layouts.local.json, keeping whatever else it says.
const layoutText = (which) => (typeof layoutFiles?.[which] === "string" ? layoutFiles[which] : null);

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

// `over` laid on `base` as tide lays one file on another: objects key by
// key, lists and values whole.
function overlaid(base, over) {
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) {
    out[k] = isObject(base[k]) && isObject(v) ? overlaid(base[k], v) : v;
  }
  return out;
}

// The files' settings over the base, so a value shown or stepped is the
// one in effect; a change still writes only what it changes.
function layoutsLoaded() {
  const loaded = loadLayouts(layoutText("shared"), layoutText("local"));
  return { settings: overlaid(layoutBase, loaded.settings), errors: loaded.errors };
}

function setLayout(path, value) {
  const r = withLayoutSetting(layoutText("local"), path, value, layoutText("shared"));
  const error = document.getElementById("layouts-error");
  if (r.error) {
    error.textContent = r.error;
    return;
  }
  error.textContent = "";
  send({ writeLayouts: r.text });
  layoutFiles = { ...layoutFiles, local: r.text };
  renderLayouts();
}

// One row: its name, a button either side of its value.
function layoutRow(label, value, less, more) {
  const row = el("div");
  row.className = "row";
  const shown = el("span", value);
  shown.className = "value";
  row.append(el("span", label), less, shown, more);
  return row;
}

function renderLayouts() {
  const box = document.getElementById("layout-rows");
  box.replaceChildren();
  const { settings, errors } = layoutsLoaded();
  const broken = errors.length > 0;
  document.getElementById("layouts-source").textContent = layoutText("local") !== null
    ? "From layouts.local.json, this Mac's own, over layouts.json."
    : layoutText("shared") !== null
      ? "From layouts.json, shared with tide. A change saves to layouts.local.json."
      : "tide's defaults. A change saves to layouts.local.json.";
  document.getElementById("layouts-error").textContent = broken ? `${errors.join("; ")}. Fix the file to change these here.` : "";
  const effective = effectiveLayouts(settings);
  for (const r of layoutRows(effective)) {
    if (r.kind === "heading") {
      box.append(el("h2", r.label));
    } else if (r.kind === "choice") {
      const choices = layoutChoices(r.path);
      const value = shownLayout(settings, r.path);
      const i = choices.findIndex((c) => c.value === value);
      const step = (d) => setLayout(r.path, choices[(i + d + choices.length) % choices.length].value);
      box.append(layoutRow(r.label, choices[i]?.label ?? String(value),
        button("‹", `Previous: ${r.label}`, broken, () => step(-1)),
        button("›", `Next: ${r.label}`, broken, () => step(1))));
    } else if (r.kind === "number") {
      const value = shownLayout(settings, r.path);
      const less = steppedLayout(r.path, value, -1);
      const more = steppedLayout(r.path, value, 1);
      box.append(layoutRow(r.label, formatLayout(r.path, value),
        button("−", `Less: ${r.label}`, broken || less === value, () => setLayout(r.path, less)),
        button("+", `More: ${r.label}`, broken || more === value, () => setLayout(r.path, more))));
    } else if (r.kind === "single") {
      const width = effective.single[r.index].width;
      const less = steppedSingle(effective.single, r.index, -1);
      const more = steppedSingle(effective.single, r.index, 1);
      box.append(layoutRow(r.label, formatLayout("single.width", width),
        button("−", `Narrower: ${r.label}`, broken || less[r.index].width === width, () => setLayout("single", less)),
        button("+", `Wider: ${r.label}`, broken || more[r.index].width === width, () => setLayout("single", more))));
    }
  }
}

// The Mouse section: the Mac's own Speed and Acceleration, which tide
// writes straight to LinearMouse's config, then tide's Mouse page's Scroll
// speed and Natural scrolling rows (tide SPEC.md §16), with tide's own
// functions: a change writes only input.local.json, keeping whatever else
// it says, and tide applies it to LinearMouse (SPEC.md §10).
const POINTER_ROWS = [
  { key: "speed", label: "Speed" },
  { key: "acceleration", label: "Acceleration" },
];
const inputText = (which) => (typeof inputFiles?.[which] === "string" ? inputFiles[which] : null);
const MOUSE_ROWS = [
  { key: "scrollSpeed", label: "Scroll speed", kind: "scroll" },
  { key: "naturalScroll", label: "Natural scrolling", kind: "toggle" },
];

function setMouse(key, value) {
  const r = withInputSetting(inputText("local"), "mouse", key, value, inputText("shared"));
  if (r.error) {
    document.getElementById("mouse-error").textContent = r.error;
    return;
  }
  send({ writeInput: r.text });
  inputFiles = { ...inputFiles, local: r.text };
  renderMouse();
}

function renderMouse() {
  const box = document.getElementById("mouse-rows");
  box.replaceChildren();
  const { input, errors } = loadInput(inputText("shared"), inputText("local"));
  const broken = errors.length > 0;
  const problems = [mouseProblem];
  if (broken) problems.push(`${errors.join("; ")}. Fix the file to change these here.`);
  document.getElementById("mouse-error").textContent = problems.filter((p) => p !== "").join(" ");
  for (const r of POINTER_ROWS) {
    const value = typeof mousePointer[r.key] === "number" ? mousePointer[r.key] : undefined;
    const less = steppedPointer(r.key, value, -1);
    const more = steppedPointer(r.key, value, 1);
    box.append(layoutRow(r.label, value === undefined ? "macOS's" : String(value),
      button("−", `Less: ${r.label}`, less === value, () => send({ mousePointer: { key: r.key, value: less } })),
      button("+", `More: ${r.label}`, more === value, () => send({ mousePointer: { key: r.key, value: more } }))));
  }
  for (const r of MOUSE_ROWS) {
    const value = shownInput(input, "mouse", r.key);
    if (r.kind === "toggle") {
      const toggle = button(formatValue(r.kind, value), `${r.label}: ${value ? "on" : "off"}`, broken, () => setMouse(r.key, !value));
      toggle.setAttribute("aria-pressed", String(value === true));
      // In the value's column, as tide's switch sits where a value would.
      const row = el("div");
      row.className = "row";
      row.append(el("span", r.label), el("span"), toggle, el("span"));
      box.append(row);
      continue;
    }
    const less = steppedInput(r.kind, value, -1);
    const more = steppedInput(r.kind, value, 1);
    box.append(layoutRow(r.label, formatValue(r.kind, value),
      button("−", `Less: ${r.label}`, broken || less === value, () => setMouse(r.key, less)),
      button("+", `More: ${r.label}`, broken || more === value, () => setMouse(r.key, more))));
  }
}

// The Workspaces section, as tide's Workspaces page (tide SPEC.md §16): the
// standing workspaces, home's apps, the name patterns and each standing
// workspace's own settings, with tide's own functions, writing only
// workspaces.local.json and keeping its other settings, `muted` included. The muted list is the Notifications
// section's, as on tide.
const workspaceText = (which) => (typeof workspaceFiles?.[which] === "string" ? workspaceFiles[which] : null);

// workspaces.json as the page reads it: over start()'s settings or tide's
// defaults, which stand in for a key it doesn't set, so the page shows what's
// in effect and a first change copies that. A file that isn't an object goes
// as it is, for tide's functions to name what's wrong with it.
function workspaceShared() {
  const base = {};
  for (const key of ["standing", "inApps"]) {
    if (Array.isArray(workspaceBase[key])) base[key] = workspaceBase[key];
  }
  if (isObject(workspaceBase.workspaceSettings)) base.workspaceSettings = workspaceBase.workspaceSettings;
  const shared = workspaceText("shared");
  if (shared === null) return Object.keys(base).length > 0 ? JSON.stringify(base) : null;
  let value;
  try {
    value = JSON.parse(shared);
  } catch {
    return shared;
  }
  return isObject(value) ? JSON.stringify({ ...base, ...value }) : shared;
}

function showWorkspacesError(text) {
  document.getElementById("workspaces-error").textContent = text;
}

function changeWorkspaces(key, fn) {
  const r = editedList(workspaceShared(), workspaceText("local"), key, fn);
  if (r.error) {
    showWorkspacesError(r.error);
    return false;
  }
  showWorkspacesError("");
  send({ writeWorkspaces: r.text });
  workspaceFiles = { ...workspaceFiles, local: r.text };
  renderWorkspaces();
  return true;
}

// A change to standing workspace `name`'s own settings, as tide's page makes
// it: the first copies the workspaceSettings in effect, home asking by
// default, into workspaces.local.json.
function changeWorkspace(name, fn) {
  const r = editedWorkspace(workspaceShared(), workspaceText("local"), name, fn);
  if (r.error) {
    showWorkspacesError(r.error);
    return false;
  }
  showWorkspacesError("");
  send({ writeWorkspaces: r.text });
  workspaceFiles = { ...workspaceFiles, local: r.text };
  renderWorkspaces();
  return true;
}

// What's typed in each workspace's Pinned apps box, kept across a redraw.
const pinnedDrafts = {};

// Each standing workspace's section, home's marked: its "Open new windows
// on a new workspace" switch (askForName) and its pinned apps.
function renderWorkspaceSettings(loaded, broken) {
  const box = document.getElementById("ws-settings");
  box.replaceChildren();
  if (broken) return;
  loaded.settings.standing.forEach((name, i) => {
    const setting = workspaceSetting(loaded.settings, name);
    const section = el("div");
    section.className = "ws-setting";
    section.append(el("h3", workspaceHeading(name, i)));
    const row = el("div");
    row.className = "row";
    const on = setting.askForName;
    const toggle = keyed(button(on ? "On" : "Off", `${ASK_LABEL}: ${name}: ${on ? "on" : "off"}`, false,
      () => changeWorkspace(name, (s) => withAskForName(s, !on))), `ws-ask-${i}`);
    toggle.setAttribute("aria-pressed", String(on));
    row.append(el("span", ASK_LABEL), toggle);
    section.append(row, el("p", PINNED_LABEL));
    const list = el("ol");
    list.className = "ws-pinned";
    if (setting.pinnedApps.length === 0) list.append(el("li", "None yet."));
    setting.pinnedApps.forEach((item, j) => {
      const li = el("li");
      li.append(el("span", item),
        button("✕", `Unpin ${item} from ${name}`, false, () => changeWorkspace(name, (s) => withoutPinned(s, j, item))));
      list.append(li);
    });
    const add = el("p");
    add.className = "add";
    const input = keyed(el("input"), `ws-pin-${i}`);
    input.placeholder = PINNED_HINT;
    input.setAttribute("aria-label", `Pin an app on ${name}`);
    input.setAttribute("spellcheck", "false");
    input.value = pinnedDrafts[name] ?? "";
    input.addEventListener("input", () => {
      pinnedDrafts[name] = input.value;
    });
    input.addEventListener("keydown", (e) => {
      if (e.key !== "Enter") return;
      const typed = input.value;
      // Pinned, the box redrawn is empty; refused, it keeps what's typed.
      delete pinnedDrafts[name];
      if (!changeWorkspace(name, (s) => withPinned(s, typed))) pinnedDrafts[name] = typed;
    });
    add.append(input);
    section.append(list, add);
    box.append(section);
  });
}

function renderWorkspaces() {
  const loaded = loadWorkspaceSettings(workspaceShared(), workspaceText("local"));
  const broken = loaded.errors.length > 0;
  document.getElementById("workspaces-source").textContent = workspaceText("local") !== null
    ? "From workspaces.local.json, this Mac's own lists, over workspaces.json."
    : workspaceText("shared") !== null
      ? "From workspaces.json, shared with tide. A change saves this Mac's own list to workspaces.local.json."
      : "The defaults, or your init.lua's. A change saves this Mac's own list to workspaces.local.json.";
  if (broken) showWorkspacesError(`${loaded.errors.join("; ")}. Fix the file to change these here.`);
  for (const l of LISTS) {
    const list = document.getElementById(`ws-list-${l.key}`);
    list.replaceChildren();
    document.getElementById(`ws-add-${l.key}`).disabled = broken;
    if (broken) continue;
    const items = loaded.settings[l.key];
    if (items.length === 0) list.append(el("li", "None yet."));
    items.forEach((item, i) => {
      const li = el("li");
      li.append(el("span", item));
      if (l.ordered) {
        li.append(
          el("span", itemNote(l.key, i)),
          button("↑", `Move ${item} up`, i === 0, () => changeWorkspaces(l.key, (xs) => movedItem(xs, i, item, -1))),
          button("↓", `Move ${item} down`, i === items.length - 1, () => changeWorkspaces(l.key, (xs) => movedItem(xs, i, item, 1))),
        );
      }
      li.append(button("✕", `Remove ${item}`, false, () => changeWorkspaces(l.key, (xs) => withoutItem(xs, i, item))));
      list.append(li);
    });
  }
  keepingFocus(() => renderWorkspaceSettings(loaded, broken));
}

for (const l of LISTS) {
  const input = document.getElementById(`ws-add-${l.key}`);
  input.placeholder = l.hint;
  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    if (changeWorkspaces(l.key, (xs) => withItem(xs, input.value))) input.value = "";
  });
}

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

// tide checks a typed entry with its mute module, mutes it and hands the
// list back, or calls tide.mutedError(why, entry).
document.getElementById("add-muted").addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  const entry = e.target.value.trim();
  if (entry === "") return;
  document.getElementById("muted-error").textContent = "";
  send({ mute: entry });
  e.target.value = "";
});

// The Floating section (SPEC.md §15), as tide's Floating page: rules by
// bundle ID and title pattern, which tide edits, since only it can check
// a Lua pattern. It answers a change with tide.update(), and then
// tide.floatingDone() or tide.floatingError(why).
let floatingState = { rules: [], now: [] };

const floatApp = () => document.getElementById("floating-app");
const floatTitle = () => document.getElementById("floating-title");

function showFloatingError(text) {
  document.getElementById("floating-error").textContent = text;
}

// What the fields were filled in for, if anything: what floats it already,
// and what macOS says of it.
function showFill(fill) {
  document.getElementById("floating-covered").textContent = fill?.covered ? `Already floats (${fill.covered}).` : "";
  const about = document.getElementById("floating-about");
  const rows = document.getElementById("floating-about-rows");
  rows.replaceChildren();
  const list = Array.isArray(fill?.about) ? fill.about : [];
  for (const r of list) rows.append(el("dt", r.label), el("dd", r.value));
  // Closed to start with; opened, it stays as you leave it while the window's open.
  about.hidden = list.length === 0;
}

function fillFloating(fill) {
  if (!fill || typeof fill.app !== "string") return;
  floatApp().value = fill.app;
  floatTitle().value = typeof fill.title === "string" ? fill.title : "";
  showFloatingError("");
  showFill(fill);
  // The title takes the keys selected, to trim, or clear for the whole app.
  floatTitle().focus?.();
  floatTitle().select?.();
}

function clearFloating() {
  floatApp().value = "";
  floatTitle().value = "";
  showFloatingError("");
  showFill(null);
}

function addFloating() {
  const app = floatApp().value.trim();
  if (app === "") {
    showFloatingError("type an app's bundle ID, such as com.apple.Preview");
    return;
  }
  showFloatingError("");
  send({ floatAdd: { app, title: floatTitle().value } });
}

function renderFloating() {
  const f = floatingState;
  const broken = typeof f.error === "string" && f.error !== "";
  document.getElementById("floating-source").textContent = f.source === "floating-macos.local.json"
    ? "From floating-macos.local.json, this Mac's own list."
    : f.source === "floating-macos.json"
      ? "From floating-macos.json, shared by your Macs. A change saves this Mac's own list to floating-macos.local.json."
      : "None yet. The first saves this Mac's own list to floating-macos.local.json.";
  if (broken) showFloatingError(`${f.error}. Fix the file to change the rules here.`);
  floatApp().disabled = broken;
  floatTitle().disabled = broken;
  document.getElementById("floating-add-button").disabled = broken;
  const list = document.getElementById("floating-list");
  list.replaceChildren();
  const rules = Array.isArray(f.rules) ? f.rules : [];
  rules.forEach((r, i) => {
    const index = i + 1;
    const name = r.title ? `${r.app}, ${r.title}` : r.app;
    const li = el("li");
    li.append(
      el("span", r.app),
      el("code", r.title || "every window"),
      button("↑", `Move ${name} up`, broken || i === 0, () => send({ floatMove: { index, app: r.app, title: r.title, step: -1 } })),
      button("↓", `Move ${name} down`, broken || i === rules.length - 1, () => send({ floatMove: { index, app: r.app, title: r.title, step: 1 } })),
      button("✕", `Remove ${name}`, broken, () => send({ floatRemove: { index, app: r.app, title: r.title } })),
    );
    list.append(li);
  });
  const now = document.getElementById("floating-now");
  now.replaceChildren();
  const windows = Array.isArray(f.now) ? f.now : [];
  if (windows.length === 0) now.append(el("li", "None. Super+Shift+F floats a window."));
  for (const w of windows) {
    const li = el("li");
    li.append(el("span", w.name), el("span", w.title), button("Always float", `Always float ${w.name}`, broken, () => fillFloating(w)));
    now.append(li);
  }
}

for (const input of [floatApp(), floatTitle()]) {
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      addFloating();
    } else if (e.key === "Escape") {
      // Esc clears the fields; with nothing in them, it closes the window.
      if (floatApp().value !== "" || floatTitle().value !== "") {
        e.stopPropagation?.();
        e.handled = true;
        clearFloating();
      }
    }
  });
}
document.getElementById("floating-add-button").addEventListener("click", addFloating);

// The Keyboard section: conf's Karabiner rules, each with On or Off, which
// tide switches in karabiner.json (SPEC.md §15), and what's wrong, only
// when something is. A click sends { karabinerRule: { description, on } },
// and tide answers with tide.update(), or tide.keyboardError(why).
// What the switcher's keys and the bar's logo open: tide's switcher or
// tileco's launcher page (SPEC.md §9.2). ‹ and › step through the choices,
// sending { launcher: value }, and tide switches at once.
function renderLauncher(launcher) {
  const box = document.getElementById("launcher-choice");
  box.replaceChildren();
  const choices = Array.isArray(launcher?.choices) ? launcher.choices : [];
  const i = choices.findIndex((c) => c.value === launcher.value);
  if (i < 0) return;
  const step = (d) => send({ launcher: choices[(i + d + choices.length) % choices.length].value });
  const shown = el("span", choices[i].label);
  shown.className = "value";
  box.append(
    el("span", "Switcher"),
    button("‹", "Previous: Switcher", choices.length < 2, () => step(-1)),
    shown,
    button("›", "Next: Switcher", choices.length < 2, () => step(1)),
  );
}

// The Appearance page's Menu bar switch: whether tide keeps the hidden
// menu bar from sliding over its bar (SPEC.md §8). A click sends
// { keepMenuBarHidden: on }, and tide answers with tide.update().
let menuBarHidden = true;
function renderMenuBar(menuBar) {
  const toggle = document.getElementById("menubar-hidden");
  const on = menuBar.hidden !== false;
  menuBarHidden = on;
  toggle.textContent = on ? "Menu bar kept hidden" : "Menu bar shows at the top edge";
  toggle.setAttribute("aria-pressed", String(on));
}

document.getElementById("menubar-hidden").addEventListener("click", () => {
  send({ keepMenuBarHidden: !menuBarHidden });
});

function renderKeyboard(keyboard) {
  const list = document.getElementById("karabiner-rules");
  list.replaceChildren();
  const rules = Array.isArray(keyboard?.rules) ? keyboard.rules : [];
  for (const r of rules) {
    const li = el("li");
    const toggle = button(r.on ? "On" : "Off", `${r.label}: ${r.on ? "on" : "off"}`, false,
      () => send({ karabinerRule: { description: r.description, on: !r.on } }));
    toggle.setAttribute("aria-pressed", String(r.on === true));
    li.append(el("span", r.label), toggle);
    list.append(li);
  }
  document.getElementById("keyboard-error").textContent = typeof keyboard?.problem === "string" ? keyboard.problem : "";
}

// Keyboard's Shortcuts, as tide's Keyboard page has them (tide SPEC.md §16):
// each binding tide registered, its keys and what it does, in keys.lua's
// order, with resize mode's prefixed; then each key that didn't register,
// and why. Read-only, as tide's are.
function renderShortcuts(shortcuts) {
  const list = document.getElementById("shortcut-list");
  list.replaceChildren();
  const binds = Array.isArray(shortcuts?.binds) ? shortcuts.binds : [];
  for (const b of binds) {
    const li = el("li");
    const does = typeof b.does === "string" ? b.does : "";
    if (does === "") li.className = "undescribed";
    li.append(el("span", b.submap ? `${b.submap}: ${b.keys}` : b.keys), el("span", does === "" ? "no description" : does));
    list.append(li);
  }
  const failed = Array.isArray(shortcuts?.failed) ? shortcuts.failed : [];
  document.getElementById("shortcuts-error").textContent = failed.length === 0 ? ""
    : failed.length === 1 ? "This key didn't register, so it does nothing:" : "These keys didn't register, so they do nothing:";
  const out = document.getElementById("shortcut-failed");
  out.replaceChildren();
  for (const f of failed) {
    const li = el("li");
    li.append(el("span", f.keys), el("span", f.does ? `${f.does}: ${f.why}` : f.why));
    out.append(li);
  }
}

// Each section's buttons to where its settings are changed, when tide
// can't change them itself (SPEC.md §1, §15): tide lists them as
// { section, name, label }, and opens what a name stands for.
function renderLinks(links) {
  const drawn = new Set();
  for (const l of links) {
    const row = document.getElementById(`${l.section}-links`);
    if (!row) continue;
    if (!drawn.has(row)) {
      row.replaceChildren();
      drawn.add(row);
    }
    const b = button(l.label, l.label, false, () => send({ open: l.name }));
    b.setAttribute("data-icon", "open");
    row.append(b);
  }
}

// The Setup checklist (SPEC.md §10, §11), as tileco's (tileco SPEC.md
// §3.4): each permission's state as tide read it, and the settings to
// change by hand, ticked off on this Mac. Each Open sends its pane's name,
// as a section's buttons do; a tick sends { setupTick: { id, on } }, and
// tide answers with tide.setup().
function renderSetup(setup) {
  const perms = document.getElementById("setup-permissions");
  perms.replaceChildren();
  for (const p of Array.isArray(setup?.permissions) ? setup.permissions : []) {
    const li = el("li");
    const state = el("span", p.label);
    state.className = p.state;
    const how = el("p", `${p.how} (${p.ref})`);
    how.className = "note";
    li.append(el("span", p.title), state, button("Open", `Open the settings for: ${p.title}`, false, () => send({ open: p.link })), how);
    perms.append(li);
  }
  const items = Array.isArray(setup?.items) ? setup.items : [];
  const list = document.getElementById("setup-items");
  list.replaceChildren();
  for (const item of items) {
    const li = el("li");
    const box = el("input");
    box.type = "checkbox";
    box.checked = item.done === true;
    box.id = `setup-${item.id}`;
    box.addEventListener("change", () => send({ setupTick: { id: item.id, on: box.checked } }));
    const label = el("label", item.title);
    label.htmlFor = box.id;
    const how = el("p", `${item.how} (${item.ref})`);
    how.className = "note";
    li.append(box, label, button("Open", `Open the settings for: ${item.title}`, false, () => send({ open: item.link })), how);
    list.append(li);
  }
  const left = Number.isInteger(setup?.left) ? setup.left : items.length;
  document.getElementById("setup-summary").textContent = left === 0 ? "All done." : `${left} of ${items.length} still to do.`;
}

// The sidebar (SPEC.md §15), as tide's settings panel's: each group's
// heading, which can't be chosen, then its pages, with one page showing at
// a time. tide sends it as { rows: [{ heading } or { page, label }],
// parts: { id: page } }, a part being a heading within a page.
let sidebarRows = [];
let sidebarParts = {};
let sidebarDrawn = "";
let shownPage = "displays";
// A reveal() that came before the sidebar, done once it's drawn.
let pendingReveal = null;
const sidebarButtons = new Map();

const pageIds = () => sidebarRows.filter((r) => typeof r.page === "string").map((r) => r.page);

// Show page `id`, or the first page for one the sidebar doesn't have.
function showPage(id) {
  const ids = pageIds();
  if (ids.length === 0) return;
  shownPage = ids.includes(id) ? id : ids[0];
  for (const p of ids) {
    const el = document.getElementById(`page-${p}`);
    if (el) el.hidden = p !== shownPage;
  }
  for (const [p, b] of sidebarButtons) b.setAttribute("aria-current", p === shownPage ? "page" : "false");
}

// To page `id`, at its top.
function turnTo(id) {
  showPage(id);
  const content = document.getElementById("content");
  if (content) content.scrollTop = 0;
}

// Page `id`, or the page a part `id` is on, scrolled to the part.
function reveal(id) {
  const page = sidebarParts[id] ?? id;
  turnTo(page);
  if (page !== id) document.getElementById(id)?.scrollIntoView?.({ block: "start" });
}

// The page `step` pages on from the one showing, passing over the headings
// and stopping at either end, as tide's Up and Down do.
function movedPage(step) {
  const ids = pageIds();
  const i = Math.max(0, ids.indexOf(shownPage));
  return ids[Math.max(0, Math.min(ids.length - 1, i + step))];
}

function renderSidebar(sidebar) {
  const rows = Array.isArray(sidebar.rows) ? sidebar.rows : [];
  const parts = isObject(sidebar.parts) ? sidebar.parts : {};
  // Drawn again only when it changes, so a sidebar button keeps the focus.
  const drawn = JSON.stringify([rows, parts]);
  if (drawn === sidebarDrawn) return;
  sidebarDrawn = drawn;
  sidebarRows = rows;
  sidebarParts = parts;
  const nav = document.getElementById("sidebar");
  nav.replaceChildren();
  sidebarButtons.clear();
  for (const row of rows) {
    if (typeof row.page === "string") {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = String(row.label ?? row.page);
      // Its icon, as on tide's sidebar.
      b.setAttribute("data-icon", row.page);
      b.addEventListener("click", () => turnTo(row.page));
      sidebarButtons.set(row.page, b);
      nav.append(b);
    } else {
      const h = document.createElement("h3");
      h.textContent = String(row.heading ?? "");
      nav.append(h);
    }
  }
  if (pendingReveal !== null) {
    const id = pendingReveal;
    pendingReveal = null;
    reveal(id);
  } else {
    showPage(shownPage);
  }
}

// Typing in a field, where Up and Down are the field's.
const editing = (t) => ["INPUT", "TEXTAREA", "SELECT"].includes(t?.tagName) || t?.isContentEditable === true;

// Back in the window, perhaps from Privacy & Security: ask for the
// permissions as they are now, as tileco's keys list does.
window.addEventListener?.("focus", () => send({ setupRefresh: true }));

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !e.handled && colorsOpen) {
    // A wallpaper's colors close first, as tide's do.
    closeColors(true);
  } else if (e.key === "Escape" && !e.handled) {
    send({ close: true });
  } else if ((e.key === "ArrowUp" || e.key === "ArrowDown") && !editing(e.target)) {
    // Up and Down change the page, as on tide.
    e.preventDefault?.();
    const next = movedPage(e.key === "ArrowUp" ? -1 : 1);
    if (next) turnTo(next);
  }
});

window.tide = {
  update(state) {
    if (isObject(state.sidebar)) renderSidebar(state.sidebar);
    files = state.clockFiles;
    startupFiles = state.startupFiles ?? null;
    clipboardFiles = state.clipboardFiles ?? null;
    appearanceFiles = state.appearanceFiles ?? null;
    idleFiles = state.idleFiles ?? null;
    renderIdle();
    notificationFiles = state.notificationFiles ?? null;
    renderDnd();
    if (isObject(state.theme)) themeState = state.theme;
    layoutFiles = state.layoutFiles ?? null;
    inputFiles = state.inputFiles ?? null;
    layoutBase = isObject(state.layoutBase) ? state.layoutBase : {};
    workspaceFiles = state.workspaceFiles ?? null;
    workspaceBase = isObject(state.workspaceBase) ? state.workspaceBase : {};
    clipboardCount = Number.isInteger(state.clipboardCount) ? state.clipboardCount : 0;
    const e = state.clipboardSettings;
    clipboardInEffect = e && typeof e.history === "boolean" && Number.isInteger(e.maxItems) && Number.isInteger(e.maxAgeDays) ? e : undefined;
    muted = Array.isArray(state.muted) ? state.muted : [];
    // New files: what went wrong before is about the old ones.
    showError("");
    showStartupError("");
    document.getElementById("muted-error").textContent = "";
    document.getElementById("layouts-error").textContent = "";
    document.getElementById("appearance-error").textContent = "";
    showWorkspacesError("");
    render();
    renderLayouts();
    renderWorkspaces();
    renderStartup();
    renderClipboard();
    renderAppearance();
    if (isObject(state.sound)) renderSound(state.sound);
    if (isObject(state.displays)) renderDisplays(state.displays);
    if (isObject(state.bluetooth)) renderBluetooth(state.bluetooth);
    if (isObject(state.netpower)) renderNetpower(state.netpower);
    if (isObject(state.inputSources)) renderInputSources(state.inputSources);
    renderMuted();
    if (Array.isArray(state.links)) renderLinks(state.links);
    if (state.keyboard && typeof state.keyboard === "object") renderKeyboard(state.keyboard);
    if (state.launcher && typeof state.launcher === "object") renderLauncher(state.launcher);
    if (state.menuBar && typeof state.menuBar === "object") renderMenuBar(state.menuBar);
    if (state.shortcuts && typeof state.shortcuts === "object") renderShortcuts(state.shortcuts);
    // What's wrong with LinearMouse or the files, only when something is.
    mouseProblem = typeof state.mouse?.problem === "string" ? state.mouse.problem : "";
    mousePointer = state.mouse?.pointer && typeof state.mouse.pointer === "object" ? state.mouse.pointer : {};
    renderMouse();
    if (state.setup && typeof state.setup === "object") renderSetup(state.setup);
    if (state.floating && typeof state.floating === "object") {
      floatingState = state.floating;
      showFloatingError("");
      renderFloating();
    }
  },
  // A Floating change saved: an added rule clears the fields.
  floatingDone(added) {
    if (added) clearFloating();
  },
  floatingError(why) {
    showFloatingError(String(why ?? ""));
  },
  // Super+Shift+I or the question's Edit rule…: the fields filled in.
  floatingFill(fill) {
    fillFloating(fill);
  },
  // The clipboard history's count, from tide as copies come and go:
  // only the Clipboard section redraws.
  count(n) {
    clipboardCount = Number.isInteger(n) ? n : 0;
    renderClipboard();
  },
  // The Setup checklist alone, after a tick or on coming back.
  setup(setup) {
    renderSetup(setup);
  },
  // A Keyboard switch that couldn't be made.
  keyboardError(why) {
    document.getElementById("keyboard-error").textContent = String(why ?? "");
  },
  // The Displays page alone, as macOS says it is now.
  displays(st) {
    renderDisplays(st);
  },
  // The Sound page alone, as macOS says it is now.
  sound(s) {
    renderSound(s);
  },
  // Appearance's light or dark, as macOS has it now.
  theme(s) {
    themeState = isObject(s) ? s : {};
    renderAppearance();
  },
  // Keyboard's input sources alone, as macOS has them now.
  inputSources(s) {
    renderInputSources(s);
  },
  // The Network and Power pages alone, as macOS says they are now.
  netpower(s) {
    renderNetpower(s);
  },
  // The Bluetooth page alone, as blueutil says it is now.
  bluetooth(s) {
    renderBluetooth(s);
  },
  // The file macOS's dialog chose for wallpaper `key`, as a setting.
  setWallpaper(key, value) {
    if (WALLPAPERS.some((w) => w.key === key) && typeof value === "string") setWallpaper(key, value);
  },
  mutedError(why, entry) {
    document.getElementById("muted-error").textContent = why;
    const input = document.getElementById("add-muted");
    if (input.value === "") input.value = entry ?? "";
  },
  reveal(id) {
    if (sidebarRows.length === 0) pendingReveal = id;
    else reveal(id);
  },
};
