// timo's dashboard page (SPEC.md §8): tico's bar, with the workspaces, the
// focused window's title and the clocks, over tico's clock and calendar
// panel. timo fills it with timo.update(state) and hears back through the
// "timo" message handler: { show: n } or { close: true }.

import { stepMonth } from "./calendar.js";
import { renderClocks, renderDetail, today } from "./clockview.js";
import { DEFAULT_SETTINGS } from "./settings.js";

const send = (msg) => window.webkit?.messageHandlers?.timo?.postMessage(msg);

let calendar = null;

function renderWorkspaces(nav, workspaces) {
  nav.replaceChildren();
  for (const w of workspaces) {
    // As tide's bar: an empty workspace that isn't showing is left out.
    if (!w.current && !w.elsewhere && !w.occupied) continue;
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = String(w.n);
    // A field timo left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "elsewhere", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
    b.addEventListener("click", () => send({ show: w.n }));
    nav.append(b);
  }
}

function tick() {
  const now = new Date();
  renderClocks(document.getElementById("clocks"), now, false, DEFAULT_SETTINGS);
  renderDetail(document.getElementById("clock-detail"), now, false, DEFAULT_SETTINGS, calendar, (by) => {
    calendar = stepMonth(calendar.year, calendar.month, by);
    tick();
  });
}

window.timo = {
  update(state) {
    const t = today();
    calendar = { year: t.year, month: t.month };
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces);
    document.getElementById("title").textContent = state.title;
    tick();
  },
};

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") send({ close: true });
  else if (/^[1-9]$/.test(e.key)) send({ show: Number(e.key) });
});

// The clocks move on while it's open.
setInterval(tick, 30000);
