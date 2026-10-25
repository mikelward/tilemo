// timo's bar (SPEC.md §8): tide's bar along the top of each display, with
// the workspaces left, the focused window's title in the middle, and the
// clocks and status icons right. timo fills it with timo.update(state) and
// hears back through the "timo" message handler: { uuid, show: n },
// { uuid, step: 1 or -1 }, { open: "battery" | "volume" | "wifi" } or
// { dashboard: true }.

import { renderClocks } from "./clockview.js";
import { DEFAULT_SETTINGS } from "./settings.js";

// Every message names this bar's display, so timo acts there.
const send = (msg) => window.webkit?.messageHandlers?.timo?.postMessage({ uuid, ...msg });

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

const VOLUME = { mute: "🔇", low: "🔈", mid: "🔉", high: "🔊" };

let uuid = null;
let scrolled = 0;

function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

function renderWorkspaces(nav, workspaces) {
  nav.replaceChildren();
  for (const w of workspaces) {
    // As tide's bar: an empty workspace that isn't showing is left out.
    if (!w.current && !w.elsewhere && !w.occupied) continue;
    const b = el("button", null, String(w.n));
    b.type = "button";
    // A field timo left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "elsewhere", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
    b.addEventListener("click", () => send({ show: w.n }));
    nav.append(b);
  }
}

function icon(name, label) {
  const b = el("button", `icon ${name}`);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.setAttribute("title", label);
  b.addEventListener("click", () => send({ open: name }));
  return b;
}

function renderIcons(box, icons) {
  box.replaceChildren();
  if (icons.wifi) {
    const w = icons.wifi;
    const b = icon("wifi", w.on ? w.name || "Wi-Fi" : "Wi-Fi off");
    b.classList.toggle("off", !w.on);
    for (let i = 1; i <= 3; i++) b.append(el("span", i <= w.bars ? "lit" : ""));
    box.append(b);
  }
  if (icons.volume) {
    const v = icons.volume;
    box.append(Object.assign(icon("volume", v.muted ? "Sound muted" : "Sound"), { textContent: VOLUME[v.level] }));
  }
  if (icons.battery) {
    const p = icons.battery;
    const b = icon("battery", p.charging ? `Battery ${p.text}, charging` : `Battery ${p.text}`);
    const cell = el("span", "cell");
    const fill = el("span", "fill");
    fill.style.width = `${p.percent}%`;
    cell.append(fill);
    b.classList.toggle("low", p.percent <= 20 && !p.charging);
    b.append(cell, el("span", "text", p.charging ? `⚡${p.text}` : p.text));
    box.append(b);
  }
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

function tick() {
  renderClocks(document.getElementById("clocks"), new Date(), false, DEFAULT_SETTINGS);
  fit();
}

window.timo = {
  update(state) {
    uuid = state.uuid;
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces);
    document.getElementById("title").textContent = state.title;
    renderIcons(document.getElementById("icons"), state.icons);
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

// The clocks open the dashboard, with its clock panel.
document.getElementById("clocks").addEventListener("click", () => send({ dashboard: true }));

setInterval(tick, 30000);
