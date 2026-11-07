// tide's bar (SPEC.md §8): tide's bar along the top of each display, with
// the workspaces left, the focused window's title in the middle, and the
// clocks and status icons right. tide fills it with tide.update(state),
// says where the pointer is with tide.pointer(x, y), and hears back through the "tide" message handler: { uuid, show: n },
// { uuid, step: 1 or -1 }, { uuid, focus: window id } from an attention icon,
// { open: "battery" | "wifi" | "network" | "volume" | "bluetooth" | "sysmon" },
// { toggle: "mic" | "volume" | "awake" | "presenter" | "source" },
// { sound: { right } } from the speaker, its right edge,
// { volume: 1 or -1 }, { session: { x } } from the session icon at x,
// { settings: page } from a right-click, "" for the first page,
// { dashboard: true }, { switcher: true } from the logo, { menubar: true } from the Apple logo, { maximize: true }, { tip: { text, x } } while
// an item with a tip is hovered and { tip: { text: "" } } once none is, { clockErrors } naming a clocks file that's wrong, or
// { goodClocks }, the clocks to keep while one is.

import { renderClocks } from "./clockview.js";
import { DEFAULT_SETTINGS, nextSettings } from "./settings.js";
import { page as tidePage } from "./tide-barsettings.js";

// Each bar item, by the selector its element matches and its name in
// tide's map (tide-barsettings.js), first match winning. The Apple logo
// opens the first page, as tide's logo does, and the camera too, as tide's
// sharing pill does.
const ITEMS = [
  ["#apple", "logo"],
  ["#logo", "logo"],
  ["#workspaces", "workspaces"],
  ["#title", "title"],
  ["#clocks", "clocks"],
  [".source", "keyboard"],
  [".awake", "keepawake"],
  [".camera", "sharing"],
  [".mic", "mic"],
  [".bluetooth", "bluetooth"],
  [".headphones", "bluetooth"],
  [".volume", "volume"],
  [".wifi, .wired", "network"],
  [".battery", "battery"],
  [".sysmon", "sysmon"],
  [".session", "session"],
];
// tide's ids for tide's pages, where they differ.
const PAGE_IDS = { notifications: "muted" };

// The settings page a right-click on `target` opens (tide §7.1): tide's
// id for it, "" for the first page, or null off every item.
export function settingsPage(target) {
  for (const [selector, item] of ITEMS) {
    const e = target?.closest?.(selector);
    if (!e) continue;
    const name = item === "keepawake" && e.getAttribute("data-state") === "presenting" ? "presenter" : item;
    const id = tidePage(name);
    return PAGE_IDS[id] ?? id;
  }
  return null;
}

// Every message names this bar's display, so tide acts there.
const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage({ uuid, ...msg });

// tide's rule (tide §7.3): below this the clocks shrink to local time.
export const MIN_TITLE = 200;

// The room the centered title has between the two sides: the bar's width
// less twice the wider side, and a gap each side.
export function titleRoom(width, left, right, gap = 24) {
  return width - 2 * Math.max(left, right) - 2 * gap;
}

// Whether the title would get narrower than MIN_TITLE with every clock
// showing.
export function crowded(width, left, right, gap = 24) {
  return titleRoom(width, left, right, gap) < MIN_TITLE;
}

// Over a notch (SPEC.md §8) the bar keeps this much of its middle clear, a
// little more than the widest MacBook notch *(unverified per model)*.
export const NOTCH_ROOM = 220;

// Which workspace chips show left of a notch, as indexes in order: those
// that fit before `limit` (the x no chip may pass), with room for a "+n"
// chip `more` wide when not all do. The chips start at `start`, each
// `widths[i]` wide with `gap` after it. Chip `keep` (the current one, or
// -1) always shows, in place of the last ones that would.
export function notchChips(start, widths, gap, limit, more, keep = -1) {
  const end = (ids) => ids.reduce((x, i) => x + widths[i] + gap, start);
  const all = widths.map((_, i) => i);
  if (end(all) - gap <= limit) return all;
  const shown = [];
  for (const i of all) {
    if (end([...shown, i]) + more > limit) break;
    shown.push(i);
  }
  if (keep >= 0 && !shown.includes(keep)) {
    while (shown.length > 0 && end([...shown, keep]) + more > limit) shown.pop();
    shown.push(keep);
  }
  return shown;
}

// Each item's click target, as how far it reaches past its own box on each
// side: to the bar's top and bottom, and halfway across the gap to each
// neighbor, so a click between two items goes to the nearer one rather than
// nowhere. A group's outer end (`start` on the left, `end` on the right)
// reaches the bar's edge; its inner end stops at the item, leaving the room
// between the groups to the title. Boxes are { left, right, top, bottom },
// left to right.
export function hitInsets(bar, items, { start = false, end = false } = {}) {
  const half = (a, b) => Math.max(0, (b - a) / 2);
  return items.map((r, i) => {
    const prev = items[i - 1];
    const next = items[i + 1];
    return {
      top: Math.max(0, r.top - bar.top),
      bottom: Math.max(0, bar.bottom - r.bottom),
      left: prev ? half(prev.right, r.left) : start ? Math.max(0, r.left - bar.left) : 0,
      right: next ? half(r.right, next.left) : end ? Math.max(0, bar.right - r.right) : 0,
    };
  });
}

// The title's target: the free bar between the two groups, from the left
// group's last item (`leftEnd`, its right edge) to the right group's first
// (`rightStart`), to the bar's top and bottom.
export function titleInsets(bar, title, leftEnd, rightStart) {
  return {
    top: Math.max(0, title.top - bar.top),
    bottom: Math.max(0, bar.bottom - title.bottom),
    left: Math.max(0, title.left - leftEnd),
    right: Math.max(0, rightStart - title.right),
  };
}

// What a click at an element reaches, innermost first: a chip's window
// icon, then the logo, a chip, the title, the clocks or a status item.
const TARGET = "nav > button .app.win, #apple, #logo, nav > button, #title, #clocks, #icons > button.icon";

// A trackpad sends many small scrolls; one step is this much of them.
const STEP = 50;


let uuid = null;
let scrolled = 0;

function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

// A long name is cut at 16 characters with an ellipsis (SPEC.md §8, a guess
// to confirm); the chip's tip has it whole.
const NAME_MAX = 16;
function shortName(name) {
  const chars = Array.from(String(name));
  return chars.length > NAME_MAX ? chars.slice(0, NAME_MAX).join("") + "…" : chars.join("");
}

// Each chip is its name, then the app icon of each window there wanting
// attention (tide sends at most five, their ids in `wins`, and how many
// more as `more`), which a click focuses (SPEC.md §8). An app with no icon
// shows as a blank square of the same size, so the count still reads.
function renderWorkspaces(nav, workspaces, appIcons = {}) {
  nav.replaceChildren();
  // Every workspace tide sends has a chip: the empty ones go once
  // they're left, and "in" stays (SPEC.md §6.1).
  for (const w of workspaces) {
    const b = el("button");
    b.type = "button";
    const short = shortName(w.n);
    // Only a cut name has a tip: a whole one would say it again.
    if (short !== String(w.n)) b.setAttribute("data-tip", String(w.n));
    b.append(el("span", "n", short));
    const wins = w.wins || [];
    (w.apps || []).forEach((app, i) => {
      const url = appIcons[app];
      let icon;
      if (url) {
        icon = el("img", "app");
        icon.src = url;
        icon.alt = "";
      } else {
        icon = el("span", "app none");
      }
      if (wins[i] !== undefined) {
        icon.className += " win";
        icon.addEventListener("click", (e) => {
          // The window, not the chip's workspace.
          e.stopPropagation();
          send({ focus: wins[i] });
        });
      }
      b.append(icon);
    });
    if (w.more > 0) b.append(el("span", "more", `+${w.more}`));
    // A field tide left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
    b.addEventListener("click", () => send({ show: w.n }));
    nav.append(b);
  }
}

// The status icons: 16 px line drawings in the text color, drawn here, so
// they follow the bar's light and dark colors. Each item's state is also in
// its data-state, for the styles and the tests.
const svg = (body, width = 16) =>
  `<svg viewBox="0 0 ${width} 16" width="${width}" height="16" fill="none" stroke="currentColor" ` +
  `stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

const SLASH = `<path d="M2.5 2.5l11 11"/>`;
const PATHS = {
  awake: `<path d="M3 6h7.5v3.5a3 3 0 0 1-3 3h-1.5a3 3 0 0 1-3-3z"/><path d="M10.5 7h1a1.75 1.75 0 0 1 0 3.5h-1"/><path d="M5.5 2.5v1.5M8 2.5v1.5"/>`,
  mic: `<rect x="6" y="2" width="4" height="7.5" rx="2"/><path d="M3.5 8a4.5 4.5 0 0 0 9 0"/><path d="M8 12.5v2"/>`,
  speaker: `<path d="M2.5 6h2.5l3.5-3v10l-3.5-3h-2.5z"/>`,
  waves: [`<path d="M10.5 6.5a2 2 0 0 1 0 3"/>`, `<path d="M12 5a4 4 0 0 1 0 6"/>`, `<path d="M13.5 3.5a6.4 6.4 0 0 1 0 9"/>`],
  speakerOff: `<path d="M11 6.5l3 3M14 6.5l-3 3"/>`,
  bluetooth: `<path d="M4.5 5l7 6-3.5 3V2l3.5 3-7 6"/>`,
  headphones: `<path d="M2.5 11V8.5a5.5 5.5 0 0 1 11 0V11"/><rect x="2" y="9.5" width="3" height="4.5" rx="1"/><rect x="11" y="9.5" width="3" height="4.5" rx="1"/>`,
  camera: `<rect x="1.5" y="4.5" width="9" height="7" rx="1.5"/><path d="M10.5 7.2l4-2.2v6l-4-2.2"/>`,
  arcs: [`<path d="M6 10.6a2.8 2.8 0 0 1 4 0"/>`, `<path d="M4 8.5a5.7 5.7 0 0 1 8 0"/>`, `<path d="M2 6.4a8.5 8.5 0 0 1 12 0"/>`],
  dot: `<path d="M8 12.8v.01"/>`,
  wired: `<path d="M5.5 2v3M10.5 2v3"/><path d="M3.5 5h9v2.5a4.5 4.5 0 0 1-9 0z"/><path d="M8 12v2.5"/>`,
  bolt: `<path d="M5.5 2.5l-3 6h3l-1 5 4-7h-3z"/>`,
  // A power symbol, as tide's system-shutdown-symbolic.
  power: `<path d="M8 2v5.5"/><path d="M4.6 4.3a5 5 0 1 0 6.8 0"/>`,
  // A processor, as tide's cpu-symbolic: a chip with pins on each side.
  cpu: `<rect x="4" y="4" width="8" height="8" rx="1.5"/><rect x="6.5" y="6.5" width="3" height="3" rx="0.5"/>` +
    `<path d="M6 1.5v2M10 1.5v2M6 12.5v2M10 12.5v2M1.5 6h2M1.5 10h2M12.5 6h2M12.5 10h2"/>`,
};

const VOLUME = { mute: 0, low: 1, mid: 2, high: 3 };

// Wi-Fi's dot and arcs, `lit` of three at full strength and the rest faint.
const arcs = (lit) =>
  PATHS.dot + PATHS.arcs.map((a, i) => (i < lit ? a : a.replace("<path ", '<path opacity="0.3" '))).join("");

// A status item: a button sending `msg` when clicked, drawn with `art`.
function icon(name, label, msg, art, state) {
  const b = el("button", `icon ${name}`);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.setAttribute("data-tip", label);
  b.setAttribute("data-state", state);
  b.innerHTML = art;
  if (msg) b.addEventListener("click", () => send(msg));
  return b;
}

// A VPN's lock, as tide's (tide §7.4): bottom right, on a disc of the
// bar's color so it reads over the icon.
const LOCK =
  `<circle cx="12.5" cy="12.5" r="3.9" fill="var(--bar)" stroke="none"/>` +
  `<rect x="10.4" y="12" width="4.2" height="3" rx="0.6" fill="currentColor" stroke="none"/>` +
  `<path d="M11.3 12v-0.9a1.2 1.2 0 0 1 2.4 0V12" stroke-width="1.1"/>`;

// Wi-Fi with its bars, a wire, or neither, with the lock while a VPN is up.
function network(icons) {
  const kind = icons.network?.kind ?? (icons.wifi?.on ? "wifi" : "none");
  const vpn = !!icons.network?.vpn;
  const w = icons.wifi;
  // The lock goes last, over the icon; the tip says so after the rest.
  const drawn = (art, label, msg, state) => {
    const b = icon(kind === "wired" ? "wired" : "wifi", vpn ? `${label}, VPN on` : label, msg, svg(art + (vpn ? LOCK : "")), state);
    if (vpn) b.setAttribute("data-vpn", "on");
    return b;
  };
  if (kind === "wifi" && w) {
    return drawn(arcs(w.bars), w.name || "Wi-Fi", { open: "wifi" }, `bars-${w.bars}`);
  }
  if (kind === "wired") {
    return drawn(PATHS.wired, "Wired network", { open: "network" }, "wired");
  }
  const off = w && !w.on;
  return drawn(arcs(0) + SLASH, off ? "Wi-Fi off" : "No network", { open: w ? "wifi" : "network" }, off ? "off" : "none");
}

// The battery: an outline with a bar as full as it is, and a bolt beside it
// while charging.
function battery(p) {
  const fill = Math.max(0, Math.min(100, Math.round(p.percent))) * 0.08;
  const body =
    `<rect x="1.5" y="4.5" width="11" height="7" rx="1.5"/><path d="M14.5 7v2"/>` +
    `<rect x="3" y="6" width="${fill.toFixed(2)}" height="4" rx="0.5" fill="currentColor" stroke="none"/>`;
  const state = p.charging ? "charging" : p.percent <= 20 ? "low" : "normal";
  const b = icon("battery", p.tip || `Battery ${p.text}`, { open: "battery" }, (p.charging ? svg(PATHS.bolt, 10) : "") + svg(body), state);
  b.append(el("span", "text", p.text));
  return b;
}

function renderIcons(box, icons) {
  box.replaceChildren();
  if (icons.source) {
    const b = icon("source", icons.source.name, { toggle: "source" }, "", "label");
    b.textContent = icons.source.label;
    box.append(b);
  }
  if (icons.awake?.presenting) {
    // Presenter mode (SPEC.md §10): the cup with a word, and a click ends it.
    const b = icon("awake", "Presenting: Do Not Disturb and keep awake", { toggle: "presenter" }, svg(PATHS.awake), "presenting");
    b.append(el("span", "text", "Presenting"));
    box.append(b);
  } else if (icons.awake) {
    // Its tip says what it's doing, in the sign's words (presenter.lua's
    // awake_sign), as tide's hover does.
    const on = !!icons.awake.on;
    box.append(icon("awake", on ? "Keeping awake" : "Not keeping awake", { toggle: "awake" }, svg(PATHS.awake), on ? "on" : "off"));
  }
  if (icons.camera) {
    const c = el("span", "icon camera");
    c.setAttribute("data-tip", "Camera in use");
    c.setAttribute("data-state", "in-use");
    c.innerHTML = svg(PATHS.camera);
    box.append(c);
  }
  if (icons.mic) {
    const muted = !!icons.mic.muted;
    const art = svg(PATHS.mic + (muted ? SLASH : ""));
    box.append(icon("mic", muted ? "Microphone muted" : "Microphone", { toggle: "mic" }, art, muted ? "muted" : "on"));
  }
  // Bluetooth: one glyph, faint while off, as tide's; a click opens
  // Bluetooth settings.
  if (icons.bluetooth) {
    const on = !!icons.bluetooth.on;
    box.append(icon("bluetooth", on ? "Bluetooth on" : "Bluetooth off", { open: "bluetooth" }, svg(PATHS.bluetooth), on ? "on" : "off"));
  }
  // Each connected Bluetooth audio device, named on hover; a click opens
  // Bluetooth settings.
  for (const d of icons.headphones?.devices ?? []) {
    box.append(icon("headphones", d.name, { open: "bluetooth" }, svg(PATHS.headphones), "connected"));
  }
  if (icons.volume) {
    // Four levels with mute, then the level as a %. An output with no
    // volume control (fixed) draws the full speaker with no %, and can't
    // be scrolled.
    const v = icons.volume;
    const waves = v.level === "fixed" ? 3 : (VOLUME[v.level] ?? 0);
    const art = svg(PATHS.speaker + (waves === 0 ? PATHS.speakerOff : PATHS.waves.slice(0, waves).join("")));
    const b = icon("volume", v.tip || (v.muted ? "Sound muted" : "Sound"), null, art, v.level);
    // A click opens the volume popover under it, as tide's; tide places
    // it, so it sends where the speaker's right edge is.
    b.addEventListener("click", () => {
      const r = b.getBoundingClientRect();
      send({ sound: { right: Math.round(r.right) } });
    });
    if (v.text) b.append(el("span", "text", v.text));
    if (!v.fixed) {
      let wheeled = 0;
      b.addEventListener("wheel", (e) => {
        e.preventDefault();
        wheeled += e.deltaY;
        if (Math.abs(wheeled) < STEP) return;
        // Scrolling up, away from you, turns it up.
        send({ volume: wheeled < 0 ? 1 : -1 });
        wheeled = 0;
      });
    }
    box.append(b);
  }
  box.append(network(icons));
  if (icons.battery) box.append(battery(icons.battery));
  // The system monitor: CPU %, colored when hot, throttling or short of
  // memory; a click opens Activity Monitor.
  if (icons.sysmon) {
    const s = icons.sysmon;
    const b = icon("sysmon", s.tip || "CPU", { open: "sysmon" }, svg(PATHS.cpu), s.tone || "normal");
    b.append(el("span", "text", s.text));
    box.append(b);
  }
  // The session menu, last, as tide's: tide shows macOS's own menu under
  // the icon, so it sends where the icon is.
  const session = icon("session", "Lock, log out or power off", null, svg(PATHS.power), "normal");
  session.addEventListener("click", () => {
    const r = session.getBoundingClientRect();
    send({ session: { x: Math.round(r.left) } });
  });
  box.append(session);
}

// Sets each item's reach (hitInsets) as --reach-* for its ::before, which
// bar.html draws as its click target. Hidden items take no room.
const SIDES = ["top", "bottom", "left", "right"];
const setReach = (e, h) => {
  for (const side of SIDES) e.style.setProperty(`--reach-${side}`, `${h ? h[side] : 0}px`);
};

// Returns the shown items' boxes.
function reach(bar, items, opts) {
  const shown = items.filter((e) => e.getBoundingClientRect().width > 0);
  for (const e of items) if (!shown.includes(e)) setReach(e, null);
  const boxes = shown.map((e) => e.getBoundingClientRect());
  hitInsets(bar, boxes, opts).forEach((h, i) => setReach(shown[i], h));
  return boxes;
}

// Every clock if the title keeps MIN_TITLE, else local time alone. Then the
// title is held to the room left, so a long one ends in an ellipsis rather
// than running over the chips or the clocks.
// The "+n" chip for workspaces hidden by the notch; a click opens the
// switcher's Workspaces tab, which lists them all.
const moreChip = el("button", "more-ws");
moreChip.type = "button";
moreChip.addEventListener("click", () => send({ workspaces: true }));

// Over a notch, hides the chips that would reach it (notchChips), behind
// moreChip.
function fitNotch() {
  const nav = document.getElementById("workspaces");
  if (moreChip.parentNode) moreChip.remove();
  const chips = [...nav.children];
  for (const c of chips) c.style.display = "";
  if (!notch || chips.length === 0) return;
  const bar = document.getElementById("bar").getBoundingClientRect();
  const width = document.getElementById("bar").clientWidth;
  const boxes = chips.map((c) => c.getBoundingClientRect());
  // Unmeasured, as before the page lays out: nothing to hide yet.
  if (!(width > 0) || boxes.some((b) => !(b.width > 0))) return;
  const gap = boxes.length > 1 ? Math.max(0, boxes[1].left - boxes[0].right) : 4;
  const limit = width / 2 - NOTCH_ROOM / 2;
  // Room for "+99", measured as tide's chips are sized.
  const more = 40;
  const keep = chips.findIndex((c) => c.classList.contains("current"));
  const shown = new Set(notchChips(boxes[0].left - bar.left, boxes.map((b) => b.width), gap, limit, more, keep));
  if (shown.size === chips.length) return;
  chips.forEach((c, i) => {
    if (!shown.has(i)) c.style.display = "none";
  });
  const hidden = chips.length - shown.size;
  moreChip.textContent = `+${hidden}`;
  moreChip.setAttribute("aria-label", `${hidden} more workspaces`);
  moreChip.setAttribute("data-tip", `${hidden} more: open the switcher's Workspaces`);
  nav.append(moreChip);
}

function fit() {
  fitNotch();
  const clocks = document.getElementById("clocks");
  const side = document.getElementById("right");
  clocks.classList.toggle("compact", false);
  const width = document.getElementById("bar").clientWidth;
  const left = document.getElementById("left").offsetWidth;
  let right = side.offsetWidth;
  const tight = crowded(width, left, right);
  clocks.classList.toggle("compact", tight);
  if (tight) right = side.offsetWidth;
  const room = titleRoom(width, left, right);
  // Unmeasured, as before the page lays out, leaves the title as it is.
  if (Number.isFinite(room)) document.getElementById("title-text").style.maxWidth = `${Math.max(0, room)}px`;
  const bar = document.getElementById("bar").getBoundingClientRect();
  // The Apple logo first, reaching the bar's left edge, so the corner opens
  // the Apple menu as on a Mac, then tide's logo, then the chips.
  const lefts = reach(bar, [document.getElementById("apple"), document.getElementById("logo"), ...document.getElementById("workspaces").children], { start: true });
  const rights = reach(bar, [document.getElementById("clocks"), ...document.getElementById("icons").children], { end: true });
  // An empty title has no target: there's no window there to maximize.
  const title = document.getElementById("title");
  const box = title.getBoundingClientRect();
  const leftEnd = lefts.length ? lefts[lefts.length - 1].right : bar.left;
  const rightStart = rights.length ? rights[0].left : bar.right;
  setReach(title, box.width > 0 ? titleInsets(bar, box, leftEnd, rightStart) : null);
}

// Where the pointer is on this bar, from tide, or null off it; kept so a
// redraw marks the new target.
let pointerAt = null;
let hovered = null;

function markHover() {
  hovered?.classList.toggle("hover", false);
  hovered = null;
  const target = pointerAt && document.elementFromPoint(pointerAt.x, pointerAt.y)?.closest(TARGET);
  if (target && !(target.id === "title" && !document.getElementById("title-text").textContent)) {
    target.classList.toggle("hover", true);
    hovered = target;
  }
  // The camera is no target, since a click there does nothing, but has a tip.
  showTip(hovered ?? (pointerAt && document.elementFromPoint(pointerAt.x, pointerAt.y)?.closest("#icons > .icon")));
}

// While the title, or an item with a tip, is hovered, tide shows the
// uncut title, or the tip, below the bar, centered on it at `x`: the page
// can't draw past its own strip, and WebKit shows no `title` attribute's
// tooltip in a window that's never key (SPEC.md §8). Sent only when it
// changes, since the pointer moves often.
let tipSent = JSON.stringify({ text: "" });
function showTip(target) {
  const at = target?.id === "title" ? document.getElementById("title-text") : target;
  const text = target?.id === "title" ? at.textContent : (target?.getAttribute("data-tip") ?? "");
  const box = at?.getBoundingClientRect();
  const tip = text ? { text, x: Math.round((box.left + box.right) / 2) } : { text: "" };
  const json = JSON.stringify(tip);
  if (json === tipSent) return;
  tipSent = json;
  send({ tip });
}

let settings = DEFAULT_SETTINGS;
let goodSent = null;

function tick() {
  renderClocks(document.getElementById("clocks"), new Date(), false, settings);
  fit();
}

// Whether this bar is over a notch (SPEC.md §8), from tide.
let notch = false;

window.tide = {
  update(state) {
    uuid = state.uuid;
    notch = !!state.notch;
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces, state.app_icons || {});
    document.getElementById("title-text").textContent = state.title;
    renderIcons(document.getElementById("icons"), state.icons);
    const loaded = nextSettings(state, settings);
    settings = loaded.settings;
    if (loaded.errors.length > 0) send({ clockErrors: loaded.errors });
    const good = JSON.stringify(settings.tideClocks);
    if (good !== goodSent) {
      goodSent = good;
      send({ goodClocks: settings.tideClocks });
    }
    tick();
    markHover();
  },
  // tide says where the pointer is, in this page's coordinates, or null
  // once it's left the bar.
  pointer(x, y) {
    pointerAt = x === null || x === undefined ? null : { x, y };
    markHover();
  },
};

document.getElementById("workspaces").addEventListener("wheel", (e) => {
  e.preventDefault();
  scrolled += e.deltaY;
  if (Math.abs(scrolled) < STEP) return;
  send({ step: scrolled > 0 ? 1 : -1 });
  scrolled = 0;
});

// Double-clicking the title, or the free bar around it, maximizes the
// focused window, as on a Mac's title bar; tide acts only if that window is
// on this bar's display. A double click on an item is that item's.
document.getElementById("bar").addEventListener("dblclick", (e) => {
  if (["bar", "title", "title-text"].includes(e.target.id)) send({ maximize: true });
});

// tide's logo opens the switcher on Launch, or closes it, as Super+Space
// does (SPEC.md §8).
document.getElementById("logo").addEventListener("click", () => send({ switcher: true }));
// A right-click on an item opens its settings page, in place of WebKit's
// menu; elsewhere on the bar it does nothing.
document.getElementById("bar").addEventListener("contextmenu", (e) => {
  const id = settingsPage(e.target);
  if (id === null) return;
  e.preventDefault();
  send({ settings: id });
});
// The Apple menu, which tide opens for real (bar_hs.lua).
document.getElementById("apple").addEventListener("click", () => send({ menubar: true }));

// The clocks open the dashboard, with its clock panel.
document.getElementById("clocks").addEventListener("click", () => send({ dashboard: true }));

setInterval(tick, 30000);
