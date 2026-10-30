// tilemo's dashboard page (SPEC.md §8): tileco's bar, with the workspaces, the
// focused window's title and the clocks, over tileco's clock and calendar
// panel. tilemo fills it with tilemo.update(state) and hears back through the
// "tilemo" message handler: { show: n }, { close: true }, { settings: true }
// to change the clocks, { clockErrors } naming a clocks file that's wrong, or
// { goodClocks }, the clocks to keep while one is.

import { stepMonth } from "./calendar.js";
import { renderClocks, renderDetail, today } from "./clockview.js";
import { DEFAULT_SETTINGS, nextSettings } from "./settings.js";

const send = (msg) => window.webkit?.messageHandlers?.tilemo?.postMessage(msg);

let calendar = null;
let settings = DEFAULT_SETTINGS;
let goodSent = null;

function renderWorkspaces(nav, workspaces) {
  nav.replaceChildren();
  for (const w of workspaces) {
    // As tide's bar: an empty workspace that isn't showing is left out.
    if (!w.current && !w.elsewhere && !w.occupied) continue;
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = String(w.n);
    // A field tilemo left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "elsewhere", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
    b.addEventListener("click", () => send({ show: w.n }));
    nav.append(b);
  }
}

function tick() {
  const now = new Date();
  renderClocks(document.getElementById("clocks"), now, false, settings);
  renderDetail(document.getElementById("clock-detail"), now, false, settings, calendar, (by) => {
    calendar = stepMonth(calendar.year, calendar.month, by);
    tick();
  });
}

window.tilemo = {
  update(state) {
    // This month to start with; an update while it's open, as a clocks file
    // changing, keeps the month you moved to.
    if (!calendar) {
      const t = today();
      calendar = { year: t.year, month: t.month };
    }
    const loaded = nextSettings(state, settings);
    settings = loaded.settings;
    if (loaded.errors.length > 0) send({ clockErrors: loaded.errors });
    const good = JSON.stringify(settings.tideClocks);
    if (good !== goodSent) {
      goodSent = good;
      send({ goodClocks: settings.tideClocks });
    }
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces);
    document.getElementById("title").textContent = state.title;
    tick();
  },
};

document.getElementById("edit-clocks").addEventListener("click", () => send({ settings: true }));

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") send({ close: true });
  else if (/^[1-9]$/.test(e.key)) send({ show: Number(e.key) });
});

// The clocks move on while it's open.
setInterval(tick, 30000);
