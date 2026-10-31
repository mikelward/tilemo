// tilemo's bar (SPEC.md §8): tide's bar along the top of each display, with
// the workspaces left, the focused window's title in the middle, and the
// clocks and status icons right. tilemo fills it with tilemo.update(state) and
// hears back through the "tilemo" message handler: { uuid, show: n },
// { uuid, step: 1 or -1 }, { uuid, focus: window id } from an attention icon,
// { open: "battery" | "wifi" | "network" },
// { toggle: "mic" | "volume" | "awake" | "presenter" | "source" },
// { volume: 1 or -1 },
// { dashboard: true }, { clockErrors } naming a clocks file that's wrong, or
// { goodClocks }, the clocks to keep while one is.

import { renderClocks } from "./clockview.js";
import { DEFAULT_SETTINGS, nextSettings } from "./settings.js";

// Every message names this bar's display, so tilemo acts there.
const send = (msg) => window.webkit?.messageHandlers?.tilemo?.postMessage({ uuid, ...msg });

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
// to confirm); the chip's tooltip has it whole.
const NAME_MAX = 16;
function shortName(name) {
  const chars = Array.from(String(name));
  return chars.length > NAME_MAX ? chars.slice(0, NAME_MAX).join("") + "…" : chars.join("");
}

// Each chip is its name, then the app icon of each window there wanting
// attention (tilemo sends at most five, their ids in `wins`, and how many
// more as `more`), which a click focuses (SPEC.md §8). An app with no icon
// shows as a blank square of the same size, so the count still reads.
function renderWorkspaces(nav, workspaces, appIcons = {}) {
  nav.replaceChildren();
  // Every workspace tilemo sends has a chip: the empty ones go once
  // they're left, and "in" stays (SPEC.md §6.1).
  for (const w of workspaces) {
    const b = el("button");
    b.type = "button";
    b.title = String(w.n);
    b.append(el("span", "n", shortName(w.n)));
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
        icon.addEventListener("click", (e) => {
          // The window, not the chip's workspace.
          e.stopPropagation();
          send({ focus: wins[i] });
        });
      }
      b.append(icon);
    });
    if (w.more > 0) b.append(el("span", "more", `+${w.more}`));
    // A field tilemo left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "elsewhere", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
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
  camera: `<rect x="1.5" y="4.5" width="9" height="7" rx="1.5"/><path d="M10.5 7.2l4-2.2v6l-4-2.2"/>`,
  arcs: [`<path d="M6 10.6a2.8 2.8 0 0 1 4 0"/>`, `<path d="M4 8.5a5.7 5.7 0 0 1 8 0"/>`, `<path d="M2 6.4a8.5 8.5 0 0 1 12 0"/>`],
  dot: `<path d="M8 12.8v.01"/>`,
  wired: `<path d="M5.5 2v3M10.5 2v3"/><path d="M3.5 5h9v2.5a4.5 4.5 0 0 1-9 0z"/><path d="M8 12v2.5"/>`,
  bolt: `<path d="M5.5 2.5l-3 6h3l-1 5 4-7h-3z"/>`,
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
  b.setAttribute("title", label);
  b.setAttribute("data-state", state);
  b.innerHTML = art;
  b.addEventListener("click", () => send(msg));
  return b;
}

// Wi-Fi with its bars, a wire, or neither.
function network(icons) {
  const kind = icons.network?.kind ?? (icons.wifi?.on ? "wifi" : "none");
  const w = icons.wifi;
  if (kind === "wifi" && w) {
    return icon("wifi", w.name || "Wi-Fi", { open: "wifi" }, svg(arcs(w.bars)), `bars-${w.bars}`);
  }
  if (kind === "wired") {
    return icon("wired", "Wired network", { open: "network" }, svg(PATHS.wired), "wired");
  }
  const off = w && !w.on;
  return icon("wifi", off ? "Wi-Fi off" : "No network", { open: w ? "wifi" : "network" }, svg(arcs(0) + SLASH), off ? "off" : "none");
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
    const on = !!icons.awake.on;
    box.append(icon("awake", on ? "Keeping awake" : "Keep awake", { toggle: "awake" }, svg(PATHS.awake), on ? "on" : "off"));
  }
  if (icons.camera) {
    const c = el("span", "icon camera");
    c.setAttribute("title", "Camera in use");
    c.setAttribute("data-state", "in-use");
    c.innerHTML = svg(PATHS.camera);
    box.append(c);
  }
  if (icons.mic) {
    const muted = !!icons.mic.muted;
    const art = svg(PATHS.mic + (muted ? SLASH : ""));
    box.append(icon("mic", muted ? "Microphone muted" : "Microphone", { toggle: "mic" }, art, muted ? "muted" : "on"));
  }
  if (icons.volume) {
    const v = icons.volume;
    const waves = VOLUME[v.level] ?? 0;
    const art = svg(PATHS.speaker + (waves === 0 ? PATHS.speakerOff : PATHS.waves.slice(0, waves).join("")));
    const b = icon("volume", v.muted ? "Sound muted" : "Sound", { toggle: "volume" }, art, v.level);
    let wheeled = 0;
    b.addEventListener("wheel", (e) => {
      e.preventDefault();
      wheeled += e.deltaY;
      if (Math.abs(wheeled) < STEP) return;
      // Scrolling up, away from you, turns it up.
      send({ volume: wheeled < 0 ? 1 : -1 });
      wheeled = 0;
    });
    box.append(b);
  }
  box.append(network(icons));
  if (icons.battery) box.append(battery(icons.battery));
}

// Every clock if the title keeps MIN_TITLE, else local time alone. Then the
// title is held to the room left, so a long one ends in an ellipsis rather
// than running over the chips or the clocks.
function fit() {
  const clocks = document.getElementById("clocks");
  const side = document.getElementById("right");
  clocks.classList.toggle("compact", false);
  const width = document.getElementById("bar").clientWidth;
  const left = document.getElementById("workspaces").offsetWidth;
  let right = side.offsetWidth;
  const tight = crowded(width, left, right);
  clocks.classList.toggle("compact", tight);
  if (tight) right = side.offsetWidth;
  const room = titleRoom(width, left, right);
  // Unmeasured, as before the page lays out, leaves the title as it is.
  if (Number.isFinite(room)) document.getElementById("title").style.maxWidth = `${Math.max(0, room)}px`;
}

let settings = DEFAULT_SETTINGS;
let goodSent = null;

function tick() {
  renderClocks(document.getElementById("clocks"), new Date(), false, settings);
  fit();
}

window.tilemo = {
  update(state) {
    uuid = state.uuid;
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces, state.app_icons || {});
    document.getElementById("title").textContent = state.title;
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
  },
};

document.getElementById("workspaces").addEventListener("wheel", (e) => {
  e.preventDefault();
  scrolled += e.deltaY;
  if (Math.abs(scrolled) < STEP) return;
  send({ step: scrolled > 0 ? 1 : -1 });
  scrolled = 0;
});

// Double-clicking the title maximizes the focused window, as on a Mac's
// title bar; tilemo acts only if that window is on this bar's display.
document.getElementById("title").addEventListener("dblclick", () => send({ maximize: true }));

// The clocks open the dashboard, with its clock panel.
document.getElementById("clocks").addEventListener("click", () => send({ dashboard: true }));

setInterval(tick, 30000);
